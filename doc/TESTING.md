# Test strategy

## 1. Layers

| Layer | Tool | Scope |
|---|---|---|
| Dart unit | `flutter test` + `FakeTransport` | SessionManager state machine, policies, extractors, watchdog |
| Widget | `flutter test` | `SmsConsentScope` mount/dispose/route/enabled |
| Kotlin unit | JUnit + Robolectric | `ConsentIntentGuard`, `SmsConsentEngine` state transitions, stale event filter |
| Integration | `integration_test` (emulator with GMS) | End-to-end flow, sending SMS from the emulator |
| Manual | Real device matrix | The M-xx list below |

## 2. Sending SMS on the emulator

```bash
# Emulator console (requires an emulator image with Google Play)
adb emu sms send 5551234567 "Your verification code is 482913"
```

The sender number must **not** be in the contacts (EC-20).

## 3. Dart unit test examples (planned)

- start → native RECEIVED → `Received(code: '482913')`
- start → cancel → a late RECEIVED is ignored (EC-01)
- start(A) → start(B) [replace] → A `Cancelled(replaced)`, B active (EC-09)
- start(reject) twice → the second one `Failed(sessionAlreadyActive)`
- no native event ever arrives → watchdog → `Failed(internal)` (EC-26)
- timeout 10 min → clamped to 5 min (EC-27)
- `result` never throws in any scenario
- `toString()` masks the message (EC-28)

### Extractor tables

| Message | Extractor | Expected |
|---|---|---|
| `Your code: 482913` | auto | `482913` |
| `Use code 4829 to pay $1,250.00` | auto | `4829` |
| `1.250,00 TL ödemeniz için kod 4829` | auto | `4829` |
| `Transaction on 12/11/2026, code: 773311` | auto | `773311` |
| `Order 99887766: your code is 1234` | keyword | `1234` |
| `Hello` | auto | `null` |

## 4. Manual device test matrix

| ID | Scenario | Expected |
|---|---|---|
| M-01 | Leave the OTP screen before the SMS arrives, then send the SMS | **No sheet appears anywhere** |
| M-02 | Rotate the screen while the sheet is open, then allow | `Received` |
| M-03 | Background the app before the SMS arrives, send the SMS, return within 10 s | The sheet opens on return |
| M-04 | Same as M-03, but return after 60 s (maxDelay 30 s) | No sheet, `TimedOut` |
| M-05 | Tap "Deny" on the sheet | `Denied` |
| M-06 | Hot restart while a session is active, then send the SMS | No sheet, no crash |
| M-07 | Huawei (HMS) device | `Unsupported(playServicesUnavailable)` |
| M-08 | Sender saved in contacts | No sheet, `TimedOut` |
| M-09 | Two SMS back to back | Sheet for the first; the second needs `restart()` |
| M-10 | "Developer options → Don't keep activities" on while the sheet is open | No crash; the result either arrives or is dropped |
| M-11 | Split screen | The sheet is visible, the result arrives |
| M-12 | Release build (R8) | The whole flow works |
| M-13 | Old session cancelled, new session on a new screen, the old SMS arrives | EC-02 behavior is recorded |

### Device / OS coverage (minimum)

- Android 7 (minSdk) / 8 / 10 / 12 / 13 / 14 / 15 / 16
- Samsung (One UI), Xiaomi (HyperOS), Pixel, Huawei (HMS)

## 5. CI

- `flutter analyze`, `dart format --set-exit-if-changed`
- Dart unit + widget tests
- Kotlin unit tests (`./gradlew :sms_consent_kit:testDebugUnitTest`)
- Check that the Pigeon output is up to date (`tool/generate_pigeon.sh` + `git diff --exit-code`)
- Release APK of the example app (R8 on)
- `compat`: release build of a consumer app created from older Flutter templates (3.27 / 3.32 / 3.38)
- (Optional) `integration_test` on an emulator with GMS
