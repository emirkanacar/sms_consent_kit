# Public API design

> Draft. Names may change during implementation; changes are reflected in this document.
>
> **Implemented:** everything below (phases 2 and 3).

## 1. `SmsConsent`

```dart
final class SmsConsent {
  static SmsConsent get instance;

  /// Whether the device supports the SMS User Consent API. Never throws:
  /// if the plugin cannot be reached, reports `playServicesUnavailable`.
  Future<SmsConsentSupport> checkSupport();

  /// One-shot shortcut: starts a session and waits for its result.
  Future<SmsConsentResult> requestCode({
    String? senderPhoneNumber,
    Duration timeout = maxSmsConsentTimeout,      // 5 minutes
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

- `timeout` must be positive and at most `maxSmsConsentTimeout` (assert in debug; clamped in release, EC-27).
- `senderPhoneNumber` must be a phone number (assert in debug). Pass `null` for alphanumeric sender IDs such as `MYBANK` (EC-21).
- A session is completed locally first (cancel, replace, watchdog) and the native side is told afterwards, so `result` completes at once.

## 2. `SmsConsentSession`

```dart
final class SmsConsentSession {
  int get id;
  SmsConsentSessionState get state; // listening, deferred, awaitingUser, completed

  /// Always completes (never hangs, never throws).
  Future<SmsConsentResult> get result;

  /// Intermediate events: consentDeferred, consentShown. Broadcast; closes
  /// when the session completes. Optional to observe.
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

`SmsConsentReceived.toString()` **masks** the message content (`<redacted, N chars>`) so it is not logged by accident. All result types have value equality, and `switch` over `SmsConsentResult` is exhaustive.

Native `cancelled` events map to `CancelReason.backgrounded` (the native side only cancels on its own for the background policy or a lost Activity).

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
1. Find every standalone 4–8 digit number: not touching letters or other digits (`ABC12345` is not a candidate; `G-482913` is).
2. Drop amounts, dates, times and grouped numbers: digit groups joined by `.` `,` `:` `/` `-` form one token and are dropped as a whole (`1,250.00`, `12/11/2026`, `12:30`, `555-0100`). Also drop numbers next to a currency symbol or code (`$`, `€`, `₺`, `TL`, `USD`, `Rs.` …), after `+` or `#`, or before `%`.
3. Pick the one closest to a keyword (`OtpExtractor.defaultKeywords`); on a tie, the earlier one. Without a keyword in the message, the first one.

- `digits(length: n)` applies the same rules with exactly `n` digits.
- `keyword(...)` returns `null` if the message contains none of the keywords.
- Keywords match case-insensitively at the start of a word: `kod` matches `kodunuz`, `pin` does not match `shipping`.
- The digit-based strategies read Arabic-Indic, Persian, Devanagari and full-width digits and return ASCII digits.
- `regex` returns `null` if the pattern does not match or the group is out of range.
- A custom extractor extends `OtpExtractor`. If `extract` throws, `code` is `null`, the message is still delivered, and the error is reported to `FlutterError.onError` without the message.

Default keywords are English. Apps that send SMS in other languages pass their own list to `OtpExtractor.keyword` (e.g. `['kod', 'şifre']` for Turkish).

## 6. `SmsConsentScope` (widget)

```dart
SmsConsentScope({
  required Widget child,
  required ValueChanged<String> onCode,
  ValueChanged<SmsConsentResult>? onResult,
  String? senderPhoneNumber,
  OtpExtractor extractor = const OtpExtractor.auto(),
  Duration timeout = maxSmsConsentTimeout,
  SmsConsentOptions options = const SmsConsentOptions(),
  bool cancelWhenRouteHidden = true,
  bool enabled = true,
});
```

Behavior:
- Mount → start a session (if `enabled`). A scope mounted under another route (e.g. restored routes) starts when its route becomes visible.
- `onCode` is called only when the extractor found a code; `onResult` gets every result of the scope's current session, after `onCode`. Neither is called after dispose.
- `dispose` → `Cancelled(scopeDisposed)`.
- `cancelWhenRouteHidden` → cancels when another route is pushed on top of `ModalRoute.of(context)`, and **does not restart** on return (the user should tap "resend code"). Manual restart: `SmsConsentScope.of(context).restart()`; the old session's result is not reported. While the route is hidden, the restart waits until it is visible. Dialogs and bottom sheets also hide the route. Popping the scope's own route ends the session with `scopeDisposed`, not `routeHidden`.
- `enabled` false → true starts a session, true → false cancels it (`CancelReason.manual`).
- Changes to `senderPhoneNumber`, `extractor`, `timeout` and `options` apply from the next session.
- `SmsConsentScopeState.session` is the current session, if any.
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
| `internal` | Unexpected error, including a native result that never arrived (watchdog, EC-26) and unknown native codes |
