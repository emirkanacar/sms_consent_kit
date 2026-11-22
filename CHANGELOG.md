# Changelog

## 0.1.0-dev.1

- Phase 3 ergonomics: `OtpExtractor` (`auto`, `digits`, `regex`, `keyword`, custom subclasses; amount/date/phone filtering, non-ASCII digits), `SmsConsentReceived.code`, `SmsConsentScope` (route awareness, `restart()`, `enabled`, `of` / `maybeOf`). `start` / `requestCode` take an `extractor`.
- Phase 2 Dart core: `SmsConsent` (`checkSupport`, `start`, `requestCode`, `cancel`), `SmsConsentSession` (state, events, a `result` that never throws), sealed `SmsConsentResult`, `SmsConsentOptions` (`ConflictPolicy`, `BackgroundPolicy`), Dart watchdog, `PigeonTransport` and `UnsupportedTransport`. The native engine now ignores a `cancel` that overtakes its `start`.
- Phase 1 Kotlin core: `SmsConsentEngine` session state machine (single active session, timeout clamped to 5 minutes, background policies, orphan timeout), `ConsentReceiver` (`RECEIVER_EXPORTED` + `SEND_PERMISSION`, stale-broadcast guard), `ConsentIntentGuard`, Pigeon host API wiring. New error code `launchFailed`.
- Plugin manifest declares a `<queries>` entry for Play Services (Android 11+ package visibility).
- Build: applies the Kotlin Gradle plugin only on AGP < 9, so consumer apps on AGP 8 compile.
- Build: on Kotlin Gradle plugin < 2.2, skips the metadata version check for this module (current Play Services jars carry Kotlin 2.3 metadata).
- Phase 0 skeleton: Pigeon schema (`pigeon/messages.dart`) and the generated Dart/Kotlin bridge.
- Android plugin skeleton (`SmsConsentPlugin`), minSdk 24.
- CI: format, analyze, tests, Pigeon freshness check, release APK, Kotlin tests, compatibility with older Flutter versions.
- Design documents: architecture, API, edge-case catalog, integration, security, test plan.
