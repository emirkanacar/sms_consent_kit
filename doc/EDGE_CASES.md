# Edge-case catalog

Each entry: **Scenario → Risk → Solution → Test.** The codes (`EC-xx`) are referenced in issues and tests.

> ⚠️ Entries marked "to be verified on device" are assumptions about Play Services behavior. They will be verified on real devices in phase 2 and this document will be updated.

---

## A. Lifecycle and "OTP sheet in the wrong place"

### EC-01 — Listening never stops, the consent sheet appears on another screen
- **Scenario:** The user opens the OTP screen and leaves before the SMS arrives. Two minutes later any SMS (or a delayed OTP) arrives and the consent sheet appears on the home screen.
- **Root cause:** Play Services offers **no cancel API** for `startSmsUserConsent`; it may send the broadcast for up to 5 minutes. Existing packages do not unregister the receiver, or they show the sheet on every broadcast.
- **Solution:**
  1. The receiver is registered only while a session is active and is unregistered **immediately** on a terminal state.
  2. Even if a broadcast arrives, the consent intent is **not launched** without an active session token.
  3. `SmsConsentScope` dispose / route hidden → automatic cancel.
  4. Recommend a shorter timeout than the default (e.g. 2 minutes).
- **Test:** Widget test (scope dispose → Cancelled), device test M-01.

### EC-02 — The broadcast of an old `start` call lands in a new session
- **Scenario:** Screen A listens and is cancelled; screen B starts a new session; the SMS sent for A arrives and the sheet opens on B.
- **Root cause:** The broadcast does not say which `start` call it belongs to.
- **Solution:** A strict separation is not possible. Mitigations: the `senderPhoneNumber` filter, extractor validation (`Received` is still returned, but `code` is null if nothing matches), and the raw `message` is always returned so the app can validate it. This is stated clearly in the docs.
- **Status:** To be verified on device (how Play Services merges two consecutive `start` calls).

### EC-03 — The SMS arrives while the app is in the background
- **Risk:** Android 10+ restricts starting Activities from the background; the sheet never opens, or opens at an unexpected moment when the app comes back.
- **Solution:** `BackgroundPolicy`:
  - `deferUntilResumed(maxDelay)` (default 30 s): the intent is kept in memory and shown on `onResume` if the session is still active and the delay has not passed; otherwise it is dropped → `TimedOut`.
  - `cancelOnBackground()`: `Cancelled(backgrounded)` when the app goes to the background.
- Note: The app also goes to the background when the user switches to the SMS app to read the message, which is why `defer` is the default.

### EC-04 — Configuration change while the consent sheet is open (rotation, dark mode, locale)
- **Risk:** The Activity is recreated, the result listener is lost, the `Future` hangs.
- **Solution:** `onDetachedFromActivityForConfigChanges` → the session is kept; `onReattachedToActivityForConfigChanges` → the result listener is re-added. State lives in the engine object, not in the Activity.

### EC-05 — Process death (the system kills the app while the sheet is open)
- **Risk:** The result arrives on return, but nothing is waiting for it on the Dart side.
- **Solution:** The result is silently dropped; no crash. The user enters the code manually. Documented (no state is persisted, since writing SMS content to disk is a privacy risk).

### EC-06 — Hot restart / hot reload
- **Risk:** Dart state resets while the native receiver stays alive; the old session's event lands in the new isolate.
- **Solution:** `SmsConsent.instance` calls `reset()` on first access (native sessions are cleared). The Dart side ignores events with an unknown session id. If the `SmsConsentFlutterApi` call fails, the native session is terminated.

### EC-07 — No Activity (background isolate, detached engine in add-to-app)
- **Solution:** `start` immediately returns `Failed(noActivity)`, or stays `deferred` until an Activity attaches (depending on policy). A call from a background isolate → `Failed(noActivity)`, not `Unsupported(platform)`.

### EC-08 — Multiple FlutterEngines / add-to-app
- **Solution:** State is per engine. Each engine manages its own receiver; events go only to the engine that started the session.

### EC-09 — Several `requestCode` calls / two `SmsConsentScope`s at once
- **Solution:** Single active session. `ConflictPolicy.replace` (default) / `reject`.

### EC-10 — The widget is disposed before the result arrives
- **Solution:** The session is cancelled; a late native event is dropped by the token mismatch; `onCode` is **never** called after dispose (`mounted` check).

### EC-11 — The user pushes another route (e.g. a "help" page) and comes back
- **Solution:** `cancelWhenRouteHidden: true` cancels. There is no automatic restart on return; a `restart()` API is provided. (Automatic restart increases the EC-02 risk.)

## B. Platform and device compatibility

### EC-12 — Google Play Services missing / outdated (Huawei HMS, Amazon, AOSP, Chinese ROMs)
- **Solution:** `GoogleApiAvailability.isGooglePlayServicesAvailable` → `Unsupported(playServicesUnavailable | playServicesOutdated)`. Play Services classes are used without reflection, but calls are made only after the availability check. No update dialog is **shown** to the user (that is the app's decision).

### EC-13 — Called on a platform other than Android
- **Scenario:** The package targets Android only, but the app's shared code (e.g. an OTP screen that also runs on iOS) calls the API.
- **Solution:** Returns `Unsupported(platform)` instead of throwing `MissingPluginException`; `SmsConsentScope` does nothing and renders its child as is. The transport is selected with `kIsWeb` / `defaultTargetPlatform`.

### EC-14 — Android 14+ `RECEIVER_EXPORTED` requirement
- **Risk:** Without the flag, registration crashes with a `SecurityException`.
- **Solution:** `ContextCompat.registerReceiver(..., RECEIVER_EXPORTED)` together with `SmsRetriever.SEND_PERMISSION`, so only Play Services can send the broadcast.

### EC-15 — Another library listening to the same action (SMS Retriever API)
- **Scenario:** Another package in the app listens to `SMS_RETRIEVED_ACTION` (e.g. the hash-based Retriever API).
- **Solution:** Broadcasts without `EXTRA_CONSENT_INTENT` are ignored. We never consume their broadcast (`abortBroadcast` is not used).

### EC-16 — R8 / ProGuard breaks the release build
- **Solution:** Pigeon code does not use reflection, so no keep rules should be needed. Play Services ships its own consumer rules. The example app's release build (minify on) is still tested in CI; a `consumer-rules.pro` is added if needed.

### EC-17 — Dual SIM, work profile, multiple users
- **Status:** To be verified on device. Expected: it works in whichever profile Play Services runs in; an app in the work profile may not see personal-profile SMS → timeout.

### EC-18 — Multi-window / split screen / PiP
- **Solution:** The "resumed" check uses `Lifecycle.State.RESUMED` (or at least STARTED + focus); in split screen the sheet is shown while visible but unfocused (Android allows this). To be verified on device.

### EC-19 — Lock screen
- **Expected:** If the app is not active on the lock screen, the EC-03 policy applies.

## C. SMS content and flow

### EC-20 — The SMS format does not trigger the API
- **Rules (Google):** The message must contain a 4–10 character alphanumeric code with at least one digit; the sender must **not be in the user's contacts**; the SMS must arrive **after** listening starts.
- **Solution:** Documentation (INTEGRATION.md – backend guide). The library returns `TimedOut` in this case.

### EC-21 — Alphanumeric sender ID (e.g. "MYBANK")
- **Solution:** `senderPhoneNumber` only makes sense with phone numbers; pass `null` for alphanumeric senders. Documented, plus an assert in debug mode if an alphanumeric value is passed.

### EC-22 — Multiple OTP SMS (resend code)
- **Behavior:** One `start` call shows the sheet for a **single** message.
- **Solution:** Call `restart()` from the "resend" button; the current session ends with `Cancelled(replaced)`.

### EC-23 — Several numbers in the message (amount, date, code)
- **Solution:** `OtpExtractor.auto()` heuristics plus `regex` / `keyword` options; `message` is always returned.

### EC-24 — The user denies
- **Solution:** `Denied`; no automatic retry (do not annoy the user). The app falls back to manual entry.

### EC-25 — The user leaves the sheet open for a long time
- **Solution:** While the sheet is open, our timeout is **paused** in the `awaitingUser` state; the user decides the result.

## D. Dart API robustness

### EC-26 — The `Future` never completes
- **Solution:** Every path leads to a terminal result; on the Dart side there is a native timeout + 5 s "watchdog" (`Failed(internal)` if the native event is lost).

### EC-27 — Timeout longer than 5 minutes
- **Solution:** The Play Services limit is 5 minutes; the value is clamped, with an assert in debug mode.

### EC-28 — SMS content leaking into logs
- **Solution:** Content is not logged in native or Dart code; `toString()` is masked; error messages never contain content.

### EC-29 — Native resource leaks (receiver, Handler callbacks, Activity reference)
- **Solution:** On a terminal state the receiver is unregistered and `removeCallbacks` is called; the Activity is referenced only through `ActivityPluginBinding` and released on detach. Checked with 1000 start/cancel cycles + LeakCanary (in the example app).
