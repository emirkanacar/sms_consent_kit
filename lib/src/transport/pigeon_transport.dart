import 'dart:async';

import 'package:flutter/services.dart';

import '../result.dart';
import 'messages.g.dart';
import 'transport.dart';

/// Android transport on top of the Pigeon-generated bridge.
final class PigeonTransport
    implements SmsConsentTransport, SmsConsentFlutterApi {
  /// Binds to [binaryMessenger], or to the default one of this isolate.
  PigeonTransport({BinaryMessenger? binaryMessenger})
      : _binaryMessenger = binaryMessenger,
        _host = SmsConsentHostApi(binaryMessenger: binaryMessenger) {
    SmsConsentFlutterApi.setUp(this, binaryMessenger: binaryMessenger);
  }

  final BinaryMessenger? _binaryMessenger;
  final SmsConsentHostApi _host;

  // Single subscriber (the session manager); events are buffered until it
  // listens. Closed by [dispose].
  final StreamController<SmsConsentEventMessage> _events =
      StreamController<SmsConsentEventMessage>();

  @override
  Stream<SmsConsentEventMessage> get events => _events.stream;

  /// Called by the native side.
  @override
  void onEvent(SmsConsentEventMessage event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  Future<SmsConsentSupport> checkSupport() async {
    final status = await _call(_host.checkSupport);
    return switch (status) {
      SupportStatusMessage.supported => const SmsConsentSupport.supported(),
      SupportStatusMessage.playServicesUnavailable =>
        const SmsConsentSupport.unsupported(
            UnsupportedReason.playServicesUnavailable),
      SupportStatusMessage.playServicesOutdated =>
        const SmsConsentSupport.unsupported(
            UnsupportedReason.playServicesOutdated),
    };
  }

  @override
  Future<void> start(StartRequestMessage request) =>
      _call(() => _host.start(request));

  @override
  Future<void> cancel(int sessionId) => _call(() => _host.cancel(sessionId));

  @override
  Future<void> reset() => _call(_host.reset);

  /// Unregisters the event handler. The transport is unusable afterwards.
  void dispose() {
    SmsConsentFlutterApi.setUp(null, binaryMessenger: _binaryMessenger);
    // Not awaited: the close of a never-listened stream never completes.
    unawaited(_events.close());
  }

  static Future<T> _call<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (e) {
      // Includes `channel-error` (plugin not registered in this engine).
      throw TransportException(e.code, e.message);
    }
  }
}
