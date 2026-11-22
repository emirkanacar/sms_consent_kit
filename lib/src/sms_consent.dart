import 'package:flutter/foundation.dart';

import 'options.dart';
import 'result.dart';
import 'session.dart';
import 'transport/transport.dart';

/// Entry point of the SMS User Consent API.
///
/// ```dart
/// final result = await SmsConsent.instance.requestCode(
///   timeout: const Duration(minutes: 2),
/// );
/// if (result case SmsConsentReceived(:final message)) {
///   // Extract and verify the code.
/// }
/// ```
///
/// There is one active session per isolate. The Flutter binding must be
/// initialized before first use (it is once `runApp` has been called).
final class SmsConsent {
  SmsConsent._(this._manager);

  /// Uses [transport] instead of the platform one. For tests only.
  @visibleForTesting
  SmsConsent.withTransport(
    SmsConsentTransport transport, {
    Duration watchdogGrace = const Duration(seconds: 5),
  }) : _manager = SessionManager(transport, watchdogGrace: watchdogGrace);

  static SmsConsent? _instance;

  /// The shared instance. The first access clears native sessions left over
  /// from before a hot restart (EC-06).
  static SmsConsent get instance =>
      _instance ??= SmsConsent._(SessionManager(defaultTransport()));

  final SessionManager _manager;

  /// Whether the device supports the SMS User Consent API. Never throws.
  ///
  /// Not required before [start]: a session on an unsupported device simply
  /// ends with [SmsConsentUnsupported].
  Future<SmsConsentSupport> checkSupport() => _manager.checkSupport();

  /// Starts a session and returns its handle.
  ///
  /// - [senderPhoneNumber]: only accept SMS from this phone number. Pass null
  ///   for alphanumeric sender IDs such as "MYBANK" (EC-21).
  /// - [timeout]: at most 5 minutes, the Play Services limit (EC-27). Shorter
  ///   values reduce the chance of a late, unrelated consent sheet (EC-01).
  ///
  /// The session must start **before** the SMS is sent: an SMS that is
  /// already in the inbox is not detected.
  SmsConsentSession start({
    String? senderPhoneNumber,
    Duration timeout = maxSmsConsentTimeout,
    SmsConsentOptions options = const SmsConsentOptions(),
  }) =>
      _manager.start(
        senderPhoneNumber: senderPhoneNumber,
        timeout: timeout,
        options: options,
      );

  /// Starts a session and waits for its result. Never throws.
  Future<SmsConsentResult> requestCode({
    String? senderPhoneNumber,
    Duration timeout = maxSmsConsentTimeout,
    SmsConsentOptions options = const SmsConsentOptions(),
  }) =>
      start(
        senderPhoneNumber: senderPhoneNumber,
        timeout: timeout,
        options: options,
      ).result;

  /// The session that has not completed yet, if any.
  SmsConsentSession? get activeSession => _manager.activeSession;

  /// Cancels the active session with `CancelReason.manual`. No-op if there
  /// is none.
  Future<void> cancel() => _manager.cancel(null, CancelReason.manual);
}
