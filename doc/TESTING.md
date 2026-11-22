# Test strategy

## 1. Layers

| Layer | Tool | Scope |
|---|---|---|
| Dart unit | `flutter test` + `FakeTransport` | SessionManager state machine, policies, extractors, watchdog |
| Widget | `flutter test` | `SmsConsentScope` mount/dispose/route/enabled |
| Kotlin unit | JUnit + Robolectric | `ConsentIntentGuard`, `SmsConsentEngine` state transitions, stale event filter |
| Stress | `flutter test` + Robolectric | 1000 random sessions; nothing may be left behind (§3.1) |
| End-to-end | `tool/e2e.sh` (emulator with GMS) | Release (R8) example app driven with adb, SMS from the emulator console (§4.1) |
| Manual | Real device matrix | The M-xx list below |

## 2. Sending SMS on the emulator

```bash
# Emulator console (requires an emulator image with Google Play)
adb emu sms send 5551234567 "Your verification code is 482913"
```

The sender number must **not** be in the contacts (EC-20).

## 3. Dart unit test examples

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

### 3.1 Resource leak checks

Each runs 1000 sessions through randomly mixed paths (received, denied,
timeout, cancel, replace, start error, cancel before start, background,
rotation, process death, Dart gone, rejected intent). After **every**
session:

- `SmsConsentStressTest.kt` (real `ContextReceiverRegistry`): no active
  session, no registered `ConsentReceiver`, no pending timer, bounded
  remembered cancels, one terminal event per session; afterwards a late SMS
  to any old receiver reaches nothing.
- `test/stress_test.dart`: no active session, no pending timer, every
  session has exactly one result and a closed event stream.

Both were checked against a deliberately broken build (unregister and
watchdog cancel removed) and failed as they should.

On a device, the example's debug build includes
[LeakCanary](https://square.github.io/leakcanary/). Open and leave the OTP
page, start and cancel sessions, rotate, then send the app to the
background; LeakCanary reports retained objects in logcat and as a
notification. To see the registered receivers:

```bash
adb shell dumpsys activity broadcasts | grep -A3 sms_consent_kit_example
```

## 4. Manual device test matrix

| ID | Scenario | Expected | `tool/e2e.sh` |
|---|---|---|---|
| M-01 | Leave the OTP screen before the SMS arrives, then send the SMS | **No sheet appears anywhere** | `m01_leave_otp_screen`, `m01_covered_otp_screen` |
| M-02 | Rotate the screen while the sheet is open, then allow | `Received` | `m02_rotate_while_sheet_open` |
| M-03 | Background the app before the SMS arrives, send the SMS, return within 10 s | The sheet opens on return | `m03_background_then_return` |
| M-04 | Same as M-03, but return after 60 s (maxDelay 30 s) | No sheet, `TimedOut` | `m04_background_too_long` (returns after 35 s) |
| M-05 | Tap "Deny" on the sheet | `Denied` | `m05_denied` |
| M-06 | Hot restart while a session is active, then send the SMS | No sheet, no crash | manual: `flutter run`, start a session, `kill -USR2 <pid>` |
| M-07 | Huawei (HMS) device | `Unsupported(playServicesUnavailable)` | manual |
| M-08 | Sender saved in contacts | No sheet, `TimedOut` | manual |
| M-09 | Two SMS back to back | Sheet for the first; the second needs `restart()` | `m09_two_sms` |
| M-10 | "Developer options → Don't keep activities" on while the sheet is open | No crash; the result either arrives or is dropped | `m10_dont_keep_activities` |
| M-11 | Split screen | The sheet is visible, the result arrives | manual |
| M-12 | Release build (R8) | The whole flow works | `m12_received` (all scenarios run on the release build) |
| M-13 | Old session cancelled, new session on a new screen, the old SMS arrives | EC-02 behavior is recorded | `m13_old_sms_new_session`: the new session receives the SMS (EC-02) |

### 4.1 Automated run

`tool/e2e.sh` builds the release example (R8 on), installs it on the one
connected device (or `ANDROID_SERIAL`) and drives it through adb (UI
hierarchy dumps, taps). On an emulator it sends the SMS with `adb emu sms
send`; on a real device it prints each SMS and waits until you have sent it
from another phone, so run it in a terminal. `m08_sender_in_contacts` runs on
real devices only. Rotation and "Don't keep activities" change for a few
scenarios; the device's own values are restored at the end.

```bash
tool/e2e.sh                  # build and run every scenario (~4 min)
tool/e2e.sh --no-build m05   # reuse the build, scenarios by prefix
```

Last run: Android 15 (API 35) Google Play emulator, Play Services 26.45:
11 of 11 passed. M-06 was checked by hand on the same emulator: after the
hot restart the receiver was gone, the SMS showed no sheet, no crash.
M-07, M-08 and M-11 are still open, as is the device list below.

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
- Stress tests run with the unit tests. `tool/e2e.sh` needs an emulator and runs locally.
