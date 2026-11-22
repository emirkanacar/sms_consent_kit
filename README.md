# sms_consent_kit

A session-based, secure and lifecycle-aware Flutter plugin for the Android **SMS User Consent API**.

[![CI](https://github.com/emirkanacar/sms_consent_kit/actions/workflows/ci.yml/badge.svg)](https://github.com/emirkanacar/sms_consent_kit/actions/workflows/ci.yml)

> Status: **Phase 3 (ergonomics).** The full public API works: `SmsConsent`, `OtpExtractor` and `SmsConsentScope`. Hardening and the first release follow. The design lives in `doc/`; progress follows the phases in `doc/PLAN.md`.

## Why another package?

Common problems in existing packages:

- Listening is never stopped, so the OTP consent sheet pops up on **unrelated screens** of the app.
- An SMS that arrives while the app is in the background gets lost, or the consent sheet opens late and in the wrong place.
- Current platform rules are not handled, such as the Android 14+ `RECEIVER_EXPORTED` requirement and the Play Console *Unsafe Intent* warning.
- On devices without Google Play Services (Huawei/HMS, AOSP) they crash, or the `Future` never completes.
- "Orphan" native listeners survive a hot restart.
- Documentation is thin: SMS format, backend requirements and testing are not covered.

`sms_consent_kit` addresses each of these at the design level. Full list: [doc/EDGE_CASES.md](doc/EDGE_CASES.md).

## Key features

- **Session model:** Every listen is an `SmsConsentSession` with a clear start, a timeout and a result that **always completes**.
- **Widget scope:** `SmsConsentScope` starts listening when the screen opens and cancels when the screen closes or its route is hidden.
- **Type-safe results:** `sealed class SmsConsentResult` → `Received`, `Denied`, `TimedOut`, `Cancelled`, `Unsupported`, `Failed`.
- **OTP extraction:** Built-in `OtpExtractor`s (length, keyword proximity, regex) plus custom extractors.
- **Background policy:** If the SMS arrives while the app is in the background, the consent sheet is shown when the app returns to the foreground (within a TTL) or silently dropped.
- **Security:** The consent intent is launched only if it resolves to the Google Play Services component. SMS content is never logged.
- **Android only:** The package targets Android only. If shared (cross-platform) code calls it on another platform by mistake, it returns `Unsupported(platform)` instead of throwing `MissingPluginException`.
- **Type-safe bridge:** Dart ↔ Kotlin communication is generated with **Pigeon**; no hand-written, string-based MethodChannel. Each FlutterEngine has its own isolated state.

## At a glance

```dart
final result = await SmsConsent.instance.requestCode(
  senderPhoneNumber: null, // leave null for alphanumeric senders (e.g. "MYBANK")
  timeout: const Duration(minutes: 2),
  extractor: const OtpExtractor.digits(length: 6),
);

switch (result) {
  case SmsConsentReceived(:final code):
    otpController.text = code ?? '';
  case SmsConsentDenied():
  case SmsConsentTimedOut():
  case SmsConsentCancelled():
  case SmsConsentUnsupported():
    // The user enters the code manually.
  case SmsConsentFailed(:final error):
    log('sms consent failed: $error');
}
```

With the widget (recommended):

```dart
SmsConsentScope(
  extractor: const OtpExtractor.digits(length: 6),
  onCode: (code) => otpController.text = code,
  child: OtpForm(controller: otpController),
)
```

## Platform support

| Platform | Behavior |
|---|---|
| Android (with GMS) | Full support |
| Android (no / outdated GMS) | `SmsConsentUnsupported(reason: playServicesUnavailable)` |
| Other platforms | Not supported (not declared in pubspec). Calls return `Unsupported(platform)`. |

## Documentation

| Document | Contents |
|---|---|
| [doc/PLAN.md](doc/PLAN.md) | Phases, scope, acceptance criteria, decisions |
| [doc/ARCHITECTURE.md](doc/ARCHITECTURE.md) | Layers, interop decision, state machine, threading |
| [doc/API.md](doc/API.md) | Public Dart API design |
| [doc/EDGE_CASES.md](doc/EDGE_CASES.md) | Edge-case catalog and solutions |
| [doc/INTEGRATION.md](doc/INTEGRATION.md) | Setup, SMS format, backend guide |
| [doc/SECURITY.md](doc/SECURITY.md) | Threat model, intent validation, privacy |
| [doc/TESTING.md](doc/TESTING.md) | Unit / widget / device test strategy, manual test matrix |

## License

[BSD-3-Clause](LICENSE)
