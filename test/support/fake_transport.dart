import 'dart:async';

import 'package:sms_consent_kit/sms_consent_kit.dart';
import 'package:sms_consent_kit/src/transport/messages.g.dart';
import 'package:sms_consent_kit/src/transport/transport.dart';

/// Records calls and lets tests play the native side.
final class FakeTransport implements SmsConsentTransport {
  /// In call order, e.g. `reset`, `start:1`, `cancel:1`.
  final List<String> calls = <String>[];
  final List<StartRequestMessage> requests = <StartRequestMessage>[];

  SmsConsentSupport support = const SmsConsentSupport.supported();
  Object? checkSupportError;

  /// Thrown by the next `start` calls.
  Object? startError;

  /// If true, `start` waits for [releaseStart].
  bool holdStart = false;

  /// If true, `reset` waits for [releaseReset].
  bool holdReset = false;

  // Created by the calls, so they belong to the caller's (fake) zone.
  final List<Completer<void>> _startGates = <Completer<void>>[];
  Completer<void>? _resetGate;

  /// Releases the oldest held `start`.
  void releaseStart() => _startGates.removeAt(0).complete();
  void releaseReset() => _resetGate!.complete();

  bool throwOnCancel = false;

  final StreamController<SmsConsentEventMessage> _events =
      StreamController<SmsConsentEventMessage>(sync: true);

  @override
  Stream<SmsConsentEventMessage> get events => _events.stream;

  @override
  Future<SmsConsentSupport> checkSupport() async {
    calls.add('checkSupport');
    final error = checkSupportError;
    if (error != null) throw error;
    return support;
  }

  @override
  Future<void> start(StartRequestMessage request) async {
    calls.add('start:${request.sessionId}');
    requests.add(request);
    if (holdStart) {
      final gate = Completer<void>();
      _startGates.add(gate);
      await gate.future;
    }
    final error = startError;
    if (error != null) throw error;
  }

  @override
  Future<void> cancel(int sessionId) async {
    calls.add('cancel:$sessionId');
    if (throwOnCancel) throw const TransportException('channel-error');
  }

  @override
  Future<void> reset() async {
    calls.add('reset');
    if (holdReset) await (_resetGate = Completer<void>()).future;
  }

  /// Simulates a native event.
  void emit(
    int sessionId,
    EventTypeMessage type, {
    String? message,
    String? errorCode,
  }) =>
      _events.add(SmsConsentEventMessage(
        sessionId: sessionId,
        type: type,
        message: message,
        errorCode: errorCode,
      ));

  void close() => unawaited(_events.close());
}
