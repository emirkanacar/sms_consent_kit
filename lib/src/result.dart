import 'package:flutter/foundation.dart';

/// Final outcome of a session. Exactly one is produced per session.
///
/// Use an exhaustive `switch`:
///
/// ```dart
/// switch (await session.result) {
///   case SmsConsentReceived(:final code, :final message):
///     // ...
///   case SmsConsentDenied():
///   case SmsConsentTimedOut():
///   case SmsConsentCancelled():
///   case SmsConsentUnsupported():
///   case SmsConsentFailed():
/// }
/// ```
@immutable
sealed class SmsConsentResult {
  const SmsConsentResult();
}

/// The user allowed the app to read the SMS.
final class SmsConsentReceived extends SmsConsentResult {
  /// Creates a received result.
  const SmsConsentReceived(this.message, {this.code});

  /// Full SMS body. Treat it as sensitive and do not log it.
  final String message;

  /// The code found by the session's `OtpExtractor`; `null` if it found
  /// none. [message] is always available as a fallback.
  final String? code;

  @override
  bool operator ==(Object other) =>
      other is SmsConsentReceived &&
      other.message == message &&
      other.code == code;

  @override
  int get hashCode => Object.hash(SmsConsentReceived, message, code);

  /// Masked, so the SMS content does not end up in logs by accident (EC-28).
  @override
  String toString() => 'SmsConsentReceived(message: '
      '<redacted, ${message.length} chars>, '
      'code: ${code == null ? 'none' : '<redacted>'})';
}

/// The user tapped "Deny" on the consent sheet (EC-24).
final class SmsConsentDenied extends SmsConsentResult {
  /// Creates a denied result.
  const SmsConsentDenied();

  @override
  bool operator ==(Object other) => other is SmsConsentDenied;

  @override
  int get hashCode => (SmsConsentDenied).hashCode;

  @override
  String toString() => 'SmsConsentDenied()';
}

/// No matching SMS arrived in time, or a deferred sheet expired (EC-03).
final class SmsConsentTimedOut extends SmsConsentResult {
  /// Creates a timed-out result.
  const SmsConsentTimedOut();

  @override
  bool operator ==(Object other) => other is SmsConsentTimedOut;

  @override
  int get hashCode => (SmsConsentTimedOut).hashCode;

  @override
  String toString() => 'SmsConsentTimedOut()';
}

/// Why a session was cancelled.
enum CancelReason {
  /// `cancel()` was called.
  manual,

  /// A newer session replaced this one (`ConflictPolicy.replace`).
  replaced,

  /// The `SmsConsentScope` that owned the session was disposed.
  scopeDisposed,

  /// Another route was pushed over the `SmsConsentScope`.
  routeHidden,

  /// The app went to the background under `BackgroundPolicy.cancelOnBackground`,
  /// or its Activity went away.
  backgrounded,
}

/// The session was cancelled before it produced a result.
final class SmsConsentCancelled extends SmsConsentResult {
  /// Creates a cancelled result.
  const SmsConsentCancelled(this.reason);

  /// Why the session was cancelled.
  final CancelReason reason;

  @override
  bool operator ==(Object other) =>
      other is SmsConsentCancelled && other.reason == reason;

  @override
  int get hashCode => Object.hash(SmsConsentCancelled, reason);

  @override
  String toString() => 'SmsConsentCancelled(${reason.name})';
}

/// Why the SMS User Consent API is not available.
enum UnsupportedReason {
  /// Not running on Android (e.g. shared code on iOS or web).
  platform,

  /// Google Play Services is missing (Huawei HMS, Amazon, AOSP...).
  playServicesUnavailable,

  /// Google Play Services is present but too old, disabled or updating.
  playServicesOutdated,
}

/// The device cannot use the SMS User Consent API (EC-12, EC-13).
final class SmsConsentUnsupported extends SmsConsentResult {
  /// Creates an unsupported result.
  const SmsConsentUnsupported(this.reason);

  /// Why the API is not available.
  final UnsupportedReason reason;

  @override
  bool operator ==(Object other) =>
      other is SmsConsentUnsupported && other.reason == reason;

  @override
  int get hashCode => Object.hash(SmsConsentUnsupported, reason);

  @override
  String toString() => 'SmsConsentUnsupported(${reason.name})';
}

/// Error codes of [SmsConsentFailed] (doc/API.md §8).
enum SmsConsentErrorCode {
  /// Play Services could not start listening.
  startFailed,

  /// The consent intent failed security validation.
  intentRejected,

  /// No Activity was available to show the consent sheet.
  noActivity,

  /// Launching the consent sheet failed.
  launchFailed,

  /// A session was already active under `ConflictPolicy.reject`.
  sessionAlreadyActive,

  /// Unexpected error, including a lost native event (watchdog).
  internal;

  /// Maps a code sent by the native side; unknown codes become [internal].
  static SmsConsentErrorCode fromWire(String? code) {
    for (final value in values) {
      if (value.name == code) return value;
    }
    return internal;
  }
}

/// Details of a [SmsConsentFailed] result. Never contains SMS content.
@immutable
final class SmsConsentError {
  /// Creates an error.
  const SmsConsentError(this.code, [this.message]);

  /// Machine-readable error code.
  final SmsConsentErrorCode code;

  /// Human-readable details for debugging, if any.
  final String? message;

  @override
  bool operator ==(Object other) =>
      other is SmsConsentError &&
      other.code == code &&
      other.message == message;

  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() => message == null ? code.name : '${code.name}: $message';
}

/// The session failed. `result` never throws; errors arrive as this type.
final class SmsConsentFailed extends SmsConsentResult {
  /// Creates a failed result.
  const SmsConsentFailed(this.error);

  /// What went wrong.
  final SmsConsentError error;

  @override
  bool operator ==(Object other) =>
      other is SmsConsentFailed && other.error == error;

  @override
  int get hashCode => Object.hash(SmsConsentFailed, error);

  @override
  String toString() => 'SmsConsentFailed($error)';
}

/// Result of `SmsConsent.checkSupport()`.
@immutable
final class SmsConsentSupport {
  /// The API is available.
  const SmsConsentSupport.supported()
      : isSupported = true,
        reason = null;

  /// The API is not available for [reason].
  const SmsConsentSupport.unsupported(UnsupportedReason this.reason)
      : isSupported = false;

  /// Whether the SMS User Consent API can be used on this device.
  final bool isSupported;

  /// Why it cannot be used; null when [isSupported] is true.
  final UnsupportedReason? reason;

  @override
  bool operator ==(Object other) =>
      other is SmsConsentSupport &&
      other.isSupported == isSupported &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(isSupported, reason);

  @override
  String toString() => isSupported
      ? 'SmsConsentSupport.supported()'
      : 'SmsConsentSupport.unsupported(${reason!.name})';
}
