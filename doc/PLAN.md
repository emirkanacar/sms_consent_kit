# Project plan

## 1. Name

| Field | Value |
|---|---|
| pub.dev package name | **`sms_consent_kit`** (available on pub.dev as of 2026-11-22) |
| Dart import | `package:sms_consent_kit/sms_consent_kit.dart` |
| Android namespace / Kotlin package | `com.emirkanacar.sms_consent_kit` |
| License | BSD-3-Clause |
| GitHub repo | `sms_consent_kit` |

Fallback names (available): `otp_consent_kit`, `consent_otp`, `smart_otp_consent`.
Taken: `sms_consent`, `sms_user_consent`, `otp_consent`.

## 2. Goals

1. A session-based API that **never hangs** and **never shows the consent sheet on the wrong screen**.
2. Work without crashing on Android 7–16 (minSdk 24) and on devices without Play Services. The package targets Android only.
3. A type-safe native bridge with Pigeon, isolated per engine.
4. Complete documentation, an example app and a test matrix.

### Out of scope (v1)

- SMS Retriever API (hash-based, no consent) → v2 candidate
- Huawei HMS ReadSmsManager → v2 candidate (possibly a separate package)
- Platforms other than Android (iOS, web, desktop)

## 3. Phases

### Phase 0 — Skeleton
- `flutter create --template=plugin --platforms=android --org com.emirkanacar sms_consent_kit`
- Lints (`flutter_lints` + strict analyzer), CI, LICENSE, CODEOWNERS, SECURITY.md, CONTRIBUTING.md, dependabot
- `pigeon/messages.dart` + `tool/generate_pigeon.sh`, generated code committed
- Android dependencies (lower bounds: `play-services-auth-api-phone` 18.3.1, `play-services-base` 18.11.1, `androidx.core` 1.13.1, `kotlinx-coroutines-android` 1.8.1)
- **Acceptance:** CI green; the example app's release APK builds; the Flutter lower bound is set from the `compat` job.
- **Status:** Done. The first CI run found two issues, both fixed: the committed `GeneratedPluginRegistrant.java` made pub dry-run warn (now ignored), and R4 occurred (fixed).

### Phase 1 — Kotlin core
- `SmsConsentPlugin` (FlutterPlugin, ActivityAware, ActivityResultListener, `SmsConsentHostApi` implementation)
- `SmsConsentEngine` (state machine, token, timeout)
- `ConsentReceiver` (`RECEIVER_EXPORTED` + `SEND_PERMISSION`)
- `ConsentIntentGuard`
- Robolectric tests
- **Acceptance:** EC-01, 03, 04, 06, 12, 14, 15 covered by Kotlin tests.
- **Status:** Done. 54 Kotlin tests (engine with fakes and virtual time, Robolectric for receiver/guard); CI green on all `compat` versions.

### Phase 2 — Pigeon bridge + Dart core
- `PigeonTransport` on top of the generated code
- `SessionManager`, `SmsConsentResult`, `SmsConsentOptions`, watchdog
- `UnsupportedTransport` (when called outside Android)
- Unit tests with `FakeTransport`
- **Real-device verification:** EC-02, EC-17, EC-18
- **Acceptance:** End-to-end `Received` on an emulator.
- **Status:** Done locally: 43 Dart tests (`FakeTransport` + `fake_async`, Pigeon channel mocks), 57 Kotlin tests (3 new: cancel overtaking its start), analyze. The example app runs the flow. Open: the emulator end-to-end run and the real-device checks.

### Phase 3 — Ergonomics
- `OtpExtractor` (auto, digits, regex, keyword) + table tests
- `SmsConsentScope` (route awareness, `restart()`, `enabled`)
- Widget tests
- **Acceptance:** Manual tests M-01…M-06 pass.

### Phase 4 — Hardening
- Release / R8 verification
- Native resource leak test (1000 cycles + LeakCanary)
- Device matrix (TESTING.md §4)
- **Acceptance:** M-01…M-13 done.

### Phase 5 — Release
- Full flow in `example/` (with a fake backend)
- pub.dev score check (`dart pub publish --dry-run`, `pana`)
- CHANGELOG, API doc comments (`///`), README GIF
- `0.1.0` release

## 4. Technical decisions (ADR summary)

| # | Decision | Rationale |
|---|---|---|
| D1 | Pigeon + Kotlin core | The native logic has to live in Kotlin anyway (BroadcastReceiver, ActivityAware). For a small bridge surface Pigeon is mature, and engine isolation and isolate safety come for free. JNIgen was considered and rejected (ARCHITECTURE.md §2). |
| D2 | Single active session | Play Services offers no cancel; multiple sessions would make EC-02 worse. |
| D3 | `result` never throws | Users cannot forget a try/catch; a sealed switch forces exhaustive handling. |
| D4 | Default `BackgroundPolicy.deferUntilResumed(30 s)` | Users may leave the app to look at the SMS. |
| D5 | Cancel when the route is hidden, no automatic restart | Lowers the risk of matching the wrong SMS. |
| D6 | SMS content is never logged or stored | Privacy. |
| D7 | Transport abstraction | Testability (`FakeTransport`), `Unsupported` per platform. |

## 5. Risks

| # | Risk | Impact | Mitigation |
|---|---|---|---|
| R1 | Undocumented Play Services behavior (consecutive `start` calls, the 5-minute limit) | Medium | Verify with device tests, update EDGE_CASES. |
| R2 | OEM-specific background Activity restrictions (Xiaomi, Samsung) | Medium | `deferUntilResumed` never tries to launch from the background. |
| R3 | `minSdk` / AGP / Kotlin version mismatches in consumer projects | Low | Wide version range, min/max matrix in CI. |
| R4 | The plugin relies on AGP 9's built-in Kotlin support (no `kotlin-android` plugin applied); consumer apps on AGP 8 may fail to compile the Kotlin sources | Medium | The CI `compat` job builds consumer apps from older Flutter templates. **Occurred** in the first CI run; fixed by applying `kotlin-android` only on AGP < 9 and setting `jvmTarget` via `KotlinCompile` tasks. |

## 6. Decisions made

| Topic | Decision | Rationale |
|---|---|---|
| License | **BSD-3-Clause** | Same as the Flutter/Dart ecosystem. |
| Org / namespace | **`com.emirkanacar`** → `com.emirkanacar.sms_consent_kit` | — |
| SMS Retriever API (no consent, hash-based) | **Not in v1**, v2 candidate | A different flow: it requires adding a hash derived from the app signature to the backend SMS template, and release / debug / Play App Signing produce different hashes. Keeping v1 focused and solid on User Consent is more valuable. The transport and result model are designed so it can be added in v2 (the EC-15 broadcast separation is already in place). |
| minSdk | **24 (Android 7.0)** | Current Google Play Services releases dropped Android 5.x (API 21–22), so the API would not work there anyway; `play-services-base` 18.11.1 itself requires minSdk 24. Current Flutter templates and Jetpack libraries are also moving above 21. The device share below 24 is negligible. |
