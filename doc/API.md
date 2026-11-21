# Public API design

> Draft. Names may change during implementation; changes are reflected in this document.

## 1. `SmsConsent`

```dart
final class SmsConsent {
  static SmsConsent get instance;

  /// Whether the device supports the SMS User Consent API.
  Future<SmsConsentSupport> checkSupport();

  /// One-shot shortcut: starts a session and waits for its result.
  Future<SmsConsentResult> requestCode({
    String? senderPhoneNumber,
    Duration timeout = const Duration(minutes: 5),
    OtpExtractor extractor = const OtpExtractor.auto(),
    SmsConsentOptions options = const SmsConsentOptions(),
  });

  /// Starts a session and returns its handle.
  SmsConsentSession start({ /* same parameters as requestCode */ });

  /// The active session, if any.
  SmsConsentSession? get activeSession;

  /// Cancels the active session. No-op if there is none.
  Future<void> cancel();
}
```

## 2. `SmsConsentSession`

```dart
final class SmsConsentSession {
  int get id;
  SmsConsentSessionState get state; // listening, deferred, awaitingUser, completed

  /// Always completes (never hangs, never throws).
  Future<SmsConsentResult> get result;

  /// Intermediate events (e.g. consent sheet shown / deferred). Optional.
  Stream<SmsConsentEvent> get events;

  Future<void> cancel();
}
```

**Guarantee:** `result` never throws; every error arrives as `SmsConsentFailed`.

## 3. Result types

```dart
sealed class SmsConsentResult { const SmsConsentResult(); }

final class SmsConsentReceived extends SmsConsentResult {
  final String message;   // SMS body
  final String? code;     // extractor output; null if not found
}
final class SmsConsentDenied     extends SmsConsentResult {}
final class SmsConsentTimedOut   extends SmsConsentResult {}
final class SmsConsentCancelled  extends SmsConsentResult {
  final CancelReason reason; // manual, replaced, scopeDisposed, routeHidden, backgrounded
}
final class SmsConsentUnsupported extends SmsConsentResult {
  final UnsupportedReason reason; // platform, playServicesUnavailable, playServicesOutdated
}
final class SmsConsentFailed extends SmsConsentResult {
  final SmsConsentError error;   // code + message (never contains SMS content)
}
```

`SmsConsentReceived.toString()` **masks** the message content so it is not logged by accident.

## 4. `SmsConsentOptions`

```dart
final class SmsConsentOptions {
  const SmsConsentOptions({
    this.conflictPolicy = ConflictPolicy.replace,
    this.backgroundPolicy = const BackgroundPolicy.deferUntilResumed(
      maxDelay: Duration(seconds: 30),
    ),
  });
}

enum ConflictPolicy {
  replace, // the old session ends with Cancelled(replaced), the new one starts
  reject,  // the new call immediately returns Failed(sessionAlreadyActive)
}

sealed class BackgroundPolicy {
  /// If the SMS arrives in the background, show the sheet if the app returns within maxDelay.
  const factory BackgroundPolicy.deferUntilResumed({required Duration maxDelay});
  /// Cancel the session as soon as the app goes to the background.
  const factory BackgroundPolicy.cancelOnBackground();
}
```

## 5. `OtpExtractor`

```dart
abstract class OtpExtractor {
  const factory OtpExtractor.auto();                       // 4–8 digits, closest to a keyword wins
  const factory OtpExtractor.digits({required int length});
  const factory OtpExtractor.regex(String pattern, {int group = 0});
  const factory OtpExtractor.keyword({
    List<String> keywords = const ['code', 'otp', 'pin', 'password'],
    int minLength = 4, int maxLength = 8,
  });

  String? extract(String message);
}
```

Rules of `auto()`:
1. Find every 4–8 digit number sequence in the message.
2. Drop money and date formats (`1,250.00`, `1.250,00`, `12/11/2026`, numbers next to currency symbols or codes).
3. Pick the one closest to a keyword; otherwise the first one.

Default keywords are English. Apps that send SMS in other languages pass their own list to `OtpExtractor.keyword` (e.g. `['kod', 'şifre']` for Turkish).

## 6. `SmsConsentScope` (widget)

```dart
SmsConsentScope({
  required Widget child,
  required ValueChanged<String> onCode,
  ValueChanged<SmsConsentResult>? onResult,
  String? senderPhoneNumber,
  OtpExtractor extractor = const OtpExtractor.auto(),
  Duration timeout = const Duration(minutes: 5),
  bool cancelWhenRouteHidden = true,
  bool enabled = true,
});
```

Behavior:
- `initState` → start a session (if `enabled`).
- `dispose` → `Cancelled(scopeDisposed)`.
- `cancelWhenRouteHidden` → cancels when another route is pushed on top of `ModalRoute.of(context)`, and **does not restart** on return (the user should tap "resend code"). Manual restart: `SmsConsentScope.of(context).restart()`.
- `enabled` false → true starts a session, true → false cancels it.
- If two scopes are mounted at the same time, the last one mounted wins (`ConflictPolicy.replace`) and the previous one gets `Cancelled(replaced)`.

## 7. Support check

```dart
final class SmsConsentSupport {
  final bool isSupported;
  final UnsupportedReason? reason;
}
```

## 8. Error codes

| Code | Description |
|---|---|
| `startFailed` | The `startSmsUserConsent` task failed |
| `intentRejected` | The consent intent failed security validation |
| `noActivity` | No Activity to show the consent sheet (also: the Activity was destroyed while the sheet was open and no result arrived within 60 s) |
| `launchFailed` | Launching the consent sheet threw (e.g. `ActivityNotFoundException`) |
| `sessionAlreadyActive` | Second call while `ConflictPolicy.reject` is set |
| `internal` | Unexpected native error |
