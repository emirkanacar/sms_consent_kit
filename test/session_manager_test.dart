import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_consent_kit/sms_consent_kit.dart';
import 'package:sms_consent_kit/src/session.dart';
import 'package:sms_consent_kit/src/transport/messages.g.dart';
import 'package:sms_consent_kit/src/transport/transport.dart';

import 'support/fake_transport.dart';

void main() {
  late FakeTransport transport;
  SessionManager? created;

  // Created on first use, so tests in fake time can create it inside the
  // fake zone (the transport's event stream allows a single listener).
  SessionManager manager() =>
      created ??= SessionManager(transport, firstSessionId: 1);

  setUp(() {
    transport = FakeTransport();
    created = null;
  });

  tearDown(() async {
    await created?.dispose();
    transport.close();
  });

  /// Runs [body] in fake time, with the manager created inside the zone so
  /// its timers are fake too.
  void fake(void Function(FakeAsync async) body) {
    fakeAsync((async) {
      manager();
      async.flushMicrotasks();
      body(async);
    });
  }

  SmsConsentResult? resultOf(SmsConsentSession session, FakeAsync async) {
    SmsConsentResult? result;
    unawaited(session.result.then((r) => result = r));
    async.flushMicrotasks();
    return result;
  }

  group('start', () {
    test('resets native sessions before the first start (EC-06)', () {
      fake((async) {
        manager().start();
        async.flushMicrotasks();
        expect(transport.calls.take(2), ['reset', 'start:1']);
      });
    });

    test('waits for reset before starting', () {
      transport.holdReset = true;
      fake((async) {
        manager().start();
        async.flushMicrotasks();
        expect(transport.calls, ['reset']);

        transport.releaseReset();
        async.flushMicrotasks();
        expect(transport.calls, ['reset', 'start:1']);
      });
    });

    test('sends the request with clamped durations and the policy', () {
      fake((async) {
        manager().start(
          senderPhoneNumber: '+15551234567',
          timeout: const Duration(minutes: 2),
          options: const SmsConsentOptions(
            backgroundPolicy: BackgroundPolicy.deferUntilResumed(
              maxDelay: Duration(minutes: 10),
            ),
          ),
        );
        async.flushMicrotasks();

        final request = transport.requests.single;
        expect(request.sessionId, 1);
        expect(request.senderPhoneNumber, '+15551234567');
        expect(request.timeoutMs, 120000);
        expect(request.backgroundPolicy,
            BackgroundPolicyMessage.deferUntilResumed);
        expect(request.deferMaxDelayMs, maxSmsConsentTimeout.inMilliseconds);
      });
    });

    test('maps cancelOnBackground', () {
      fake((async) {
        manager().start(
          options: const SmsConsentOptions(
            backgroundPolicy: BackgroundPolicy.cancelOnBackground(),
          ),
        );
        async.flushMicrotasks();
        expect(transport.requests.single.backgroundPolicy,
            BackgroundPolicyMessage.cancelOnBackground);
      });
    });

    test('asserts on a timeout over 5 minutes (EC-27)', () {
      expect(() => manager().start(timeout: const Duration(minutes: 6)),
          throwsAssertionError);
    });

    test('asserts on an alphanumeric sender (EC-21)', () {
      expect(() => manager().start(senderPhoneNumber: 'MYBANK'),
          throwsAssertionError);
    });

    test('session ids are unique and increasing', () {
      fake((async) {
        final a = manager().start();
        final b = manager().start();
        expect(b.id, a.id + 1);
      });
    });

    test('random first id when not given', () {
      final ids =
          List.generate(5, (_) => SessionManager(FakeTransport()).start().id)
              .toSet();
      expect(ids.length, greaterThan(1));
    });
  });

  group('native results', () {
    test('received', () {
      fake((async) {
        final session = manager().start();
        async.flushMicrotasks();
        transport.emit(1, EventTypeMessage.received, message: 'Code: 482913');

        expect(resultOf(session, async),
            const SmsConsentReceived('Code: 482913', code: '482913'));
        expect(session.state, SmsConsentSessionState.completed);
        expect(manager().activeSession, isNull);
        expect(transport.calls, isNot(contains('cancel:1')),
            reason: 'the native side ended it itself');
      });
    });

    test('uses the session extractor', () {
      fake((async) {
        final session = manager().start(
          extractor: const OtpExtractor.digits(length: 4),
        );
        transport.emit(1, EventTypeMessage.received,
            message: 'Order 123456, code 7788');
        expect(resultOf(session, async),
            const SmsConsentReceived('Order 123456, code 7788', code: '7788'));
      });
    });

    test('a throwing extractor costs only the code (EC-28)', () {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);

      fake((async) {
        final session = manager().start(extractor: const _Throwing());
        transport.emit(1, EventTypeMessage.received, message: 'secret 482913');
        expect(resultOf(session, async),
            const SmsConsentReceived('secret 482913'));
      });
      expect(reported, hasLength(1));
      expect(reported.single.exceptionAsString(), isNot(contains('482913')));
    });

    test('received without a message fails', () {
      fake((async) {
        final session = manager().start();
        transport.emit(1, EventTypeMessage.received);
        final result = resultOf(session, async);
        expect(result, isA<SmsConsentFailed>());
        expect((result! as SmsConsentFailed).error.code,
            SmsConsentErrorCode.internal);
      });
    });

    test('denied, timedOut, cancelled', () {
      fake((async) {
        final expected = {
          EventTypeMessage.denied: const SmsConsentDenied(),
          EventTypeMessage.timedOut: const SmsConsentTimedOut(),
          EventTypeMessage.cancelled:
              const SmsConsentCancelled(CancelReason.backgrounded),
        };
        expected.forEach((type, result) {
          final session = manager().start();
          transport.emit(session.id, type);
          expect(resultOf(session, async), result, reason: '$type');
        });
      });
    });

    test('failed maps known and unknown codes', () {
      fake((async) {
        final a = manager().start();
        transport.emit(a.id, EventTypeMessage.failed,
            errorCode: 'intentRejected');
        expect(
            resultOf(a, async),
            const SmsConsentFailed(
                SmsConsentError(SmsConsentErrorCode.intentRejected)));

        final b = manager().start();
        transport.emit(b.id, EventTypeMessage.failed,
            errorCode: 'somethingNew');
        expect(
            resultOf(b, async),
            const SmsConsentFailed(
                SmsConsentError(SmsConsentErrorCode.internal)));
      });
    });

    test('intermediate events update the state and the stream', () {
      fake((async) {
        final session = manager().start();
        final events = <SmsConsentEvent>[];
        var closed = false;
        session.events.listen(events.add, onDone: () => closed = true);

        transport.emit(1, EventTypeMessage.consentDeferred);
        async.flushMicrotasks();
        expect(session.state, SmsConsentSessionState.deferred);

        transport.emit(1, EventTypeMessage.consentShown);
        async.flushMicrotasks();
        expect(session.state, SmsConsentSessionState.awaitingUser);

        transport.emit(1, EventTypeMessage.denied);
        async.flushMicrotasks();
        expect(events,
            [SmsConsentEvent.consentDeferred, SmsConsentEvent.consentShown]);
        expect(closed, isTrue);
      });
    });

    test('a result is produced once; later events are ignored', () {
      fake((async) {
        final session = manager().start();
        transport.emit(1, EventTypeMessage.denied);
        transport.emit(1, EventTypeMessage.received, message: 'late');
        expect(resultOf(session, async), const SmsConsentDenied());
      });
    });

    test('stale events of other sessions are ignored (EC-06, EC-10)', () {
      fake((async) {
        final session = manager().start();
        transport.emit(999, EventTypeMessage.received, message: 'stale');
        async.flushMicrotasks();
        expect(session.isActive, isTrue);
      });
    });
  });

  group('start failures', () {
    test('unsupported maps the reason (EC-12)', () {
      fake((async) {
        transport.startError = const TransportException(
            unsupportedErrorCode, 'PLAY_SERVICES_OUTDATED');
        final session = manager().start();
        expect(
            resultOf(session, async),
            const SmsConsentUnsupported(
                UnsupportedReason.playServicesOutdated));
        expect(manager().activeSession, isNull);
      });
    });

    test('native error codes become Failed', () {
      fake((async) {
        transport.startError =
            const TransportException('startFailed', 'ApiException');
        final session = manager().start();
        expect(
            resultOf(session, async),
            const SmsConsentFailed(SmsConsentError(
                SmsConsentErrorCode.startFailed, 'ApiException')));
      });
    });

    test('unexpected errors become Failed(internal), never thrown', () {
      fake((async) {
        transport.startError = StateError('boom');
        final session = manager().start();
        final result = resultOf(session, async);
        expect((result! as SmsConsentFailed).error.code,
            SmsConsentErrorCode.internal);
      });
    });

    test('a failure of a replaced session does not touch the new one', () {
      fake((async) {
        transport.holdStart = true;
        transport.startError = const TransportException('startFailed');
        final first = manager().start();
        async.flushMicrotasks();
        final second = manager().start();
        async.flushMicrotasks();

        // The first start fails late, while the second is still starting.
        transport.releaseStart();
        async.flushMicrotasks();

        expect(resultOf(first, async),
            const SmsConsentCancelled(CancelReason.replaced));
        expect(second.isActive, isTrue);
        expect(manager().activeSession, same(second));
      });
    });
  });

  group('conflicts (EC-09)', () {
    test('replace cancels the old session', () {
      fake((async) {
        final first = manager().start();
        async.flushMicrotasks();
        final second = manager().start();
        async.flushMicrotasks();

        expect(resultOf(first, async),
            const SmsConsentCancelled(CancelReason.replaced));
        expect(manager().activeSession, same(second));
        expect(transport.calls, containsAllInOrder(['cancel:1', 'start:2']));
      });
    });

    test('reject keeps the old session', () {
      fake((async) {
        final first = manager().start();
        final second = manager().start(
          options:
              const SmsConsentOptions(conflictPolicy: ConflictPolicy.reject),
        );

        expect(
            resultOf(second, async),
            const SmsConsentFailed(
                SmsConsentError(SmsConsentErrorCode.sessionAlreadyActive)));
        expect(manager().activeSession, same(first));
        expect(transport.requests.length, 1);
      });
    });
  });

  group('cancel (EC-01)', () {
    test('cancel resolves locally and stops the native session', () {
      fake((async) {
        final session = manager().start();
        async.flushMicrotasks();
        unawaited(session.cancel());
        async.flushMicrotasks();

        expect(resultOf(session, async),
            const SmsConsentCancelled(CancelReason.manual));
        expect(transport.calls.last, 'cancel:1');
        transport.emit(1, EventTypeMessage.received, message: 'late');
        expect(resultOf(session, async),
            const SmsConsentCancelled(CancelReason.manual));
      });
    });

    test('cancel before reset completes never starts native listening', () {
      transport.holdReset = true;
      fake((async) {
        final session = manager().start();
        unawaited(session.cancel());
        transport.releaseReset();
        async.flushMicrotasks();

        expect(transport.calls, isNot(contains('start:1')));
      });
    });

    test('cancel during an in-flight start repeats the native cancel', () {
      fake((async) {
        transport.holdStart = true;
        final session = manager().start();
        async.flushMicrotasks();
        unawaited(session.cancel());
        async.flushMicrotasks();
        transport.releaseStart();
        async.flushMicrotasks();

        expect(transport.calls.where((c) => c == 'cancel:1').length, 2);
      });
    });

    test('cancelling a completed or non-active session is a no-op', () {
      fake((async) {
        final first = manager().start();
        final second = manager().start();
        unawaited(first.cancel());
        async.flushMicrotasks();
        expect(second.isActive, isTrue);
      });
    });

    test('a failing native cancel is swallowed', () {
      fake((async) {
        transport.throwOnCancel = true;
        final session = manager().start();
        unawaited(session.cancel());
        async.flushMicrotasks();
        expect(resultOf(session, async), isA<SmsConsentCancelled>());
      });
    });
  });

  group('watchdog (EC-26)', () {
    test('fails a session whose native result never arrives', () {
      fake((async) {
        final session = manager().start(timeout: const Duration(minutes: 1));
        async.elapse(const Duration(minutes: 1, seconds: 4));
        expect(session.isActive, isTrue);

        async.elapse(const Duration(seconds: 1));
        final result = resultOf(session, async);
        expect((result! as SmsConsentFailed).error.code,
            SmsConsentErrorCode.internal);
        expect(transport.calls.last, 'cancel:1');
      });
    });

    test('stops once the consent sheet is shown (EC-25)', () {
      fake((async) {
        final session = manager().start(timeout: const Duration(minutes: 1));
        transport.emit(1, EventTypeMessage.consentShown);
        async.elapse(const Duration(minutes: 30));
        expect(session.state, SmsConsentSessionState.awaitingUser);
      });
    });

    test('does not fire after a result', () {
      fake((async) {
        final session = manager().start(timeout: const Duration(minutes: 1));
        transport.emit(1, EventTypeMessage.timedOut);
        async.elapse(const Duration(minutes: 5));
        expect(resultOf(session, async), const SmsConsentTimedOut());
        expect(async.pendingTimers, isEmpty);
      });
    });
  });

  group('checkSupport', () {
    test('passes the transport result through', () async {
      transport.support = const SmsConsentSupport.unsupported(
          UnsupportedReason.playServicesOutdated);
      expect(await manager().checkSupport(), transport.support);
    });

    test('never throws', () async {
      transport.checkSupportError = const TransportException('channel-error');
      expect(
          await manager().checkSupport(),
          const SmsConsentSupport.unsupported(
              UnsupportedReason.playServicesUnavailable));
    });
  });
}

final class _Throwing extends OtpExtractor {
  const _Throwing();

  @override
  String? extract(String message) => throw FormatException(message);
}
