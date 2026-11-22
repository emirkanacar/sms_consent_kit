import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_consent_kit/src/session.dart';
import 'package:sms_consent_kit/src/transport/messages.g.dart';
import 'package:sms_consent_kit/src/transport/transport.dart';

import 'support/fake_transport.dart';

/// Resource leak check (doc/PLAN.md, phase 4): 1000 sessions through random
/// paths. After each one nothing may be left behind: no active session, no
/// timer, a closed event stream and exactly one result.
void main() {
  test('1000 random sessions leave nothing behind', () {
    final transport = FakeTransport();
    final random = Random(20261122);
    const scenarios = 10;

    fakeAsync((async) {
      final manager = SessionManager(transport, firstSessionId: 1);
      async.flushMicrotasks();

      var results = 0;
      var eventsClosed = 0;
      var sessions = 0;

      SmsConsentSession start({Duration timeout = maxSmsConsentTimeout}) {
        final session = manager.start(timeout: timeout);
        sessions++;
        session.events.listen(null, onDone: () => eventsClosed++);
        unawaited(session.result.then((_) => results++));
        async.flushMicrotasks();
        return session;
      }

      void runScenario(int kind) {
        switch (kind) {
          case 0:
            final s = start();
            transport.emit(s.id, EventTypeMessage.received,
                message: 'code 1234');
          case 1:
            final s = start();
            transport.emit(s.id, EventTypeMessage.consentShown);
            transport.emit(s.id, EventTypeMessage.denied);
          case 2:
            final s = start();
            transport.emit(s.id, EventTypeMessage.timedOut);
          case 3:
            final s = start();
            transport.emit(s.id, EventTypeMessage.failed,
                errorCode: 'internal');
          case 4:
            unawaited(start().cancel());
          case 5:
            start();
            final s = start(); // replaces the first
            unawaited(s.cancel());
          case 6:
            transport.startError = const TransportException('startFailed');
            start();
            transport.startError = null;
          case 7:
            start(timeout: const Duration(minutes: 1));
            async.elapse(const Duration(minutes: 2)); // watchdog
          case 8:
            transport.holdStart = true;
            final s = start();
            unawaited(s.cancel()); // cancel overtakes the start
            async.flushMicrotasks();
            transport.releaseStart();
            transport.holdStart = false;
          case 9:
            final s = start();
            transport.emit(s.id, EventTypeMessage.consentDeferred);
            transport.emit(s.id, EventTypeMessage.consentShown);
            transport.emit(s.id, EventTypeMessage.received, message: 'Hi');
            // A late duplicate must be ignored.
            transport.emit(s.id, EventTypeMessage.received, message: 'Hi');
        }
        async.flushMicrotasks();
      }

      for (var i = 0; i < 1000; i++) {
        final kind = i < scenarios ? i : random.nextInt(scenarios);
        runScenario(kind);
        final context = 'session #$i (scenario $kind)';
        expect(manager.activeSession, isNull, reason: context);
        expect(async.pendingTimers, isEmpty, reason: context);
        expect(results, sessions, reason: context);
        expect(eventsClosed, sessions, reason: context);
      }
      expect(sessions, greaterThan(1000));

      unawaited(manager.dispose());
      async.flushMicrotasks();
    });
    transport.close();
  });
}
