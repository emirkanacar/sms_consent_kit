# Changelog

## 0.1.0-dev.1

- Phase 1 Kotlin core: `SmsConsentEngine` session state machine (single active session, timeout clamped to 5 minutes, background policies, orphan timeout), `ConsentReceiver` (`RECEIVER_EXPORTED` + `SEND_PERMISSION`, stale-broadcast guard), `ConsentIntentGuard`, Pigeon host API wiring. New error code `launchFailed`.
- Plugin manifest declares a `<queries>` entry for Play Services (Android 11+ package visibility).
- Build: applies the Kotlin Gradle plugin only on AGP < 9, so consumer apps on AGP 8 compile.
- Phase 0 skeleton: Pigeon schema (`pigeon/messages.dart`) and the generated Dart/Kotlin bridge.
- Android plugin skeleton (`SmsConsentPlugin`), minSdk 24.
- CI: format, analyze, tests, Pigeon freshness check, release APK, Kotlin tests, compatibility with older Flutter versions.
- Design documents: architecture, API, edge-case catalog, integration, security, test plan.
