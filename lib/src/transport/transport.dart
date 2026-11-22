import 'dart:async';

import 'package:flutter/foundation.dart';

import '../result.dart';
import 'messages.g.dart';
import 'pigeon_transport.dart';
import 'unsupported_transport.dart';

/// Error code of [TransportException] when the device or platform cannot
/// use the API. The message carries the reason (see [unsupportedReasonOf]).
const String unsupportedErrorCode = 'unsupported';

/// Internal boundary between the session logic and the platform.
abstract interface class SmsConsentTransport {
  /// Native session events.
  Stream<SmsConsentEventMessage> get events;

  /// Whether the device supports the API.
  Future<SmsConsentSupport> checkSupport();

  /// Completes once listening is registered; otherwise throws a
  /// [TransportException].
  Future<void> start(StartRequestMessage request);

  /// Ends the native session with [sessionId] without an event.
  Future<void> cancel(int sessionId);

  /// Ends every native session of this engine without an event.
  Future<void> reset();
}

/// A failed transport call, with a native error code (doc/API.md §8).
final class TransportException implements Exception {
  /// Creates an exception.
  const TransportException(this.code, [this.message]);

  /// Native error code, e.g. `startFailed`.
  final String code;

  /// Details; never SMS content.
  final String? message;

  @override
  String toString() => 'TransportException($code, $message)';
}

/// Maps the message of an [unsupportedErrorCode] error.
UnsupportedReason unsupportedReasonOf(String? message) => switch (message) {
      'platform' => UnsupportedReason.platform,
      'PLAY_SERVICES_OUTDATED' => UnsupportedReason.playServicesOutdated,
      _ => UnsupportedReason.playServicesUnavailable,
    };

/// The transport for the current platform. The package targets Android only,
/// but shared code may call it elsewhere; that must not throw (EC-13).
SmsConsentTransport defaultTransport() {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return const UnsupportedTransport();
  }
  return PigeonTransport();
}
