// Single source of truth for the Dart <-> Kotlin bridge.
//
// After editing, run:
//   tool/generate_pigeon.sh
//
// Generated files are committed; CI verifies they are up to date.
// Design: doc/ARCHITECTURE.md §2.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'sms_consent_kit',
    dartOut: 'lib/src/transport/messages.g.dart',
    kotlinOut:
        'android/src/main/kotlin/com/emirkanacar/sms_consent_kit/Messages.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'com.emirkanacar.sms_consent_kit',
      errorClassName: 'SmsConsentFlutterError',
    ),
  ),
)

/// Whether the device supports the SMS User Consent API.
enum SupportStatusMessage {
  supported,
  playServicesUnavailable,
  playServicesOutdated,
}

/// What to do when the SMS arrives while the app is in the background.
enum BackgroundPolicyMessage { deferUntilResumed, cancelOnBackground }

/// Event types sent from the native side to Dart.
enum EventTypeMessage {
  received,
  denied,
  timedOut,
  cancelled,
  failed,
  consentShown,
  consentDeferred,
}

/// Request to start a listening session.
class StartRequestMessage {
  StartRequestMessage({
    required this.sessionId,
    required this.timeoutMs,
    required this.backgroundPolicy,
    required this.deferMaxDelayMs,
    this.senderPhoneNumber,
  });

  int sessionId;

  /// Real phone numbers only; null for alphanumeric sender IDs.
  String? senderPhoneNumber;

  /// At most 5 minutes due to the Play Services limit.
  int timeoutMs;

  BackgroundPolicyMessage backgroundPolicy;

  /// Maximum wait for [BackgroundPolicyMessage.deferUntilResumed].
  int deferMaxDelayMs;
}

/// Session event coming from the native side.
class SmsConsentEventMessage {
  SmsConsentEventMessage({
    required this.sessionId,
    required this.type,
    this.message,
    this.errorCode,
  });

  int sessionId;
  EventTypeMessage type;

  /// SMS body; only for [EventTypeMessage.received].
  String? message;

  /// Error code; only for [EventTypeMessage.failed].
  String? errorCode;
}

/// Dart -> Kotlin calls.
@HostApi()
abstract class SmsConsentHostApi {
  @async
  SupportStatusMessage checkSupport();

  /// Completes once listening is registered; otherwise fails with an error code.
  @async
  void start(StartRequestMessage request);

  /// Cancels the given session. No-op if there is no such session.
  void cancel(int sessionId);

  /// Clears all sessions of this engine (first access / hot restart).
  void reset();
}

/// Kotlin -> Dart events.
@FlutterApi()
abstract class SmsConsentFlutterApi {
  void onEvent(SmsConsentEventMessage event);
}
