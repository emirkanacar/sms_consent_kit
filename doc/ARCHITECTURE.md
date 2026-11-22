# Architecture

## 1. Overview

```
┌──────────────────────────── Dart ─────────────────────────────┐
│  Public API                                                    │
│   SmsConsent  ·  SmsConsentSession  ·  SmsConsentScope (widget)│
│   SmsConsentResult (sealed)  ·  OtpExtractor                   │
│                         │                                      │
│  SessionManager  (single active session, timeout, policies)    │
│                         │                                      │
│  SmsConsentTransport  (internal abstract)                      │
│     ├─ PigeonTransport   → Pigeon generated API (Android)      │
│     ├─ UnsupportedTransport (non-Android, defensive)           │
│     └─ FakeTransport     (tests)                               │
└─────────────────────────┬──────────────────────────────────────┘
                          │  Pigeon (BinaryMessenger, type-safe codec)
┌─────────────────────────┴──── Kotlin ─────────────────────────┐
│  SmsConsentPlugin   (FlutterPlugin + ActivityAware +           │
│                      ActivityResultListener + SmsConsentHostApi)│
│  SmsConsentEngine   (per-plugin-instance state, session token) │
│  ConsentReceiver    (BroadcastReceiver, only during a session) │
│  ConsentIntentGuard (intent validation)                        │
│  SmsConsentFlutterApi (generated, native → Dart events)        │
└─────────────────────────┬──────────────────────────────────────┘
                          │
              Google Play Services – SmsRetriever
              startSmsUserConsent(sender?)
```

## 2. Interop decision: Pigeon

JNIgen became stable in Flutter 3.50. However, the native side of this plugin has to be in Kotlin anyway:

| Part | Why it has to be Kotlin |
|---|---|
| `BroadcastReceiver` | An abstract **class**; JNIgen cannot extend a class from Dart. |
| Activity result | `ActivityPluginBinding.addActivityResultListener` is tied to the plugin lifecycle. |
| Config change / reattach | `ActivityAware` callbacks arrive at the Kotlin plugin class. |
| Hot restart resilience | Native state survives while the Dart isolate restarts; cleanup must happen natively. |
| Security checks | Intent validation must happen atomically, where the intent is launched. |

That leaves only a few calls and a few event types between Dart and Kotlin. For this small, fixed surface **Pigeon** is a better fit:

- **Engine isolation for free:** Pigeon APIs are bound to the plugin instance's `BinaryMessenger`. Every FlutterEngine gets its own plugin instance → no need to pass an engine id around in add-to-app / multi-engine setups.
- **Native → Dart events** are type-safe through `@FlutterApi`. If there is no Dart isolate / after a hot restart the call fails with an error that the native side catches. The "callback into a dead isolate" and JNI reference management problems of JNIgen disappear.
- **Mature and widely used:** Flutter's own first-party plugins (e.g. `shared_preferences`, `url_launcher`) use Pigeon.
- **Simple build:** The generated code is plain Kotlin/Dart files; no JDK 17–21 requirement or binding generation step as with JNIgen, no extra R8 rules.

The only thing we lose is synchronous calls; `checkSupport()` already returns a `Future`, so the API does not change.

The `SmsConsentTransport` abstraction is still used for `FakeTransport` in tests.

### Pigeon schema — `pigeon/messages.dart`

```dart
@ConfigurePigeon(PigeonOptions(
  dartPackageName: 'sms_consent_kit',
  dartOut: 'lib/src/transport/messages.g.dart',
  kotlinOut: 'android/src/main/kotlin/com/emirkanacar/sms_consent_kit/Messages.g.kt',
  kotlinOptions: KotlinOptions(
    package: 'com.emirkanacar.sms_consent_kit',
    errorClassName: 'SmsConsentFlutterError',
  ),
))

enum SupportStatusMessage { supported, playServicesUnavailable, playServicesOutdated }
enum BackgroundPolicyMessage { deferUntilResumed, cancelOnBackground }

enum EventTypeMessage {
  received, denied, timedOut, cancelled, failed,
  consentShown, consentDeferred,
}

class StartRequestMessage {
  StartRequestMessage({
    required this.sessionId,
    required this.timeoutMs,
    required this.backgroundPolicy,
    required this.deferMaxDelayMs,
    this.senderPhoneNumber,
  });
  int sessionId;
  String? senderPhoneNumber;
  int timeoutMs;
  BackgroundPolicyMessage backgroundPolicy;
  int deferMaxDelayMs;
}

class SmsConsentEventMessage {
  SmsConsentEventMessage({required this.sessionId, required this.type,
                          this.message, this.errorCode});
  int sessionId;
  EventTypeMessage type;
  String? message;    // received only
  String? errorCode;  // failed only
}

@HostApi()
abstract class SmsConsentHostApi {
  @async
  SupportStatusMessage checkSupport();

  /// Completes once listening is registered; otherwise fails with an error code.
  @async
  void start(StartRequestMessage request);

  void cancel(int sessionId);

  /// First access / hot restart: clears all sessions of this engine.
  void reset();
}

@FlutterApi()
abstract class SmsConsentFlutterApi {
  void onEvent(SmsConsentEventMessage event);
}
```

Pigeon is a `dev_dependency`; the generated `*.g.dart` / `*.g.kt` files are committed to the repo (codegen does not run in a pub package).

## 3. Session state machine

```
           start()
  idle ───────────────► listening ──── broadcast (consent intent) ───► awaitingUser
   ▲                       │  │                                         │   │
   │          cancel()/    │  │ app in background +                     │   │
   │          timeout      │  │ policy=defer                            │   │
   │                       │  ▼                                         │   │
   │                       │ deferred ── onResume (within TTL) ─────────┘   │
   │                       │  │                                             │
   │                       │  └── TTL expired / cancel ──► cancelled/timedOut│
   │                       ▼                                                ▼
   └─────────────── terminal (received | denied | timedOut | cancelled | failed)
```

Rules:

1. **The terminal state is produced exactly once.** The native side guards it with a single `terminated` flag on the main thread; the Dart side with a `Completer.isCompleted` check.
2. On the transition to a terminal state the receiver is unregistered **immediately**, the timeout is cancelled and any pending intent is released.
3. Any event whose session id does not match the active session is **ignored** (stale event), on both the native and the Dart side.
4. If `cancel()` is called in the `awaitingUser` state: Android does not allow closing a consent sheet that is already open; when its result arrives it is **dropped**, and `Cancelled` has already been delivered to Dart.

## 4. Critical native flow

```
start(request):
  1. If a session is active → Dart's ConflictPolicy has already decided;
     the native side silently closes the old session (defensive)
  2. GoogleApiAvailability check → if missing, FlutterError("unsupported")
  3. ContextCompat.registerReceiver(
         receiver,
         IntentFilter(SmsRetriever.SMS_RETRIEVED_ACTION),
         SmsRetriever.SEND_PERMISSION,   // only GMS can send
         null,
         ContextCompat.RECEIVER_EXPORTED) // required on Android 14+
  4. SmsRetriever.getClient(ctx).startSmsUserConsent(sender)
       .addOnSuccessListener → callback(Result.success)
       .addOnFailureListener → callback(FlutterError("startFailed")) + cleanup
  5. Handler.postDelayed(timeout) → TIMED_OUT (clamped to ≤ 5 min)

onReceive(intent):
  - No session → ignore
  - No EXTRA_CONSENT_INTENT → ignore (may be a broadcast for another
    library that uses the SMS Retriever API)
  - Status.TIMEOUT → TIMED_OUT
  - Status.SUCCESS → ConsentIntentGuard.validate(intent) → FAILED if it fails
  - Activity RESUMED → startActivityForResult(consentIntent, REQUEST_CODE)
    otherwise → deferred / dropped according to backgroundPolicy

onActivityResult(REQUEST_CODE):
  - RESULT_OK → EXTRA_SMS_MESSAGE → RECEIVED
  - anything else → DENIED
```

`REQUEST_CODE` is a plugin-specific constant (chosen to avoid clashing with other plugins, within the 16-bit limit).

## 5. Engine and isolate model

- Every FlutterEngine gets its own `SmsConsentPlugin` instance; state (`SmsConsentEngine`) lives on that instance. Pigeon APIs are bound to that engine's messenger, so events only go to the engine that started the session.
- `onDetachedFromEngine` → the active session is cancelled, the receiver is unregistered, the Pigeon API handlers are set to `null`.
- When Dart first accesses `SmsConsent.instance`, `reset()` is called → sessions left over from before a hot restart are cleared. The first `start` waits for it.
- Session ids start at a random value per isolate, so ids from before a hot restart never match new sessions while their events are still in flight.
- If the `SmsConsentFlutterApi.onEvent` call fails (`channel-error`: nothing listening on the Dart side), the native side terminates the session; no exception escapes.

## 6. Threading

- All Kotlin state changes happen on the **main thread**. Pigeon HostApi calls arrive on the main thread; the receiver also runs on the main thread (no scheduler is passed to `registerReceiver`). So no locks are needed.
- Pigeon 29 generates Kotlin `suspend fun`s for `@async` HostApi methods and all FlutterApi methods. It runs handlers in `CoroutineScope(Dispatchers.Main)`, which is why `kotlinx-coroutines-android` is a dependency.
- `SmsConsentFlutterApi.onEvent` is a `suspend fun` called from the main thread. It throws if nothing is listening on the Dart side; the native side catches this and terminates the session (§5).
- All calls are lightweight (register / cancel); there is no blocking work.
- **Ordering:** Pigeon dispatches `@async` methods (`checkSupport`, `start`) through a coroutine, which runs later, while sync methods (`cancel`, `reset`) run at once. A `cancel` sent right after its `start` can therefore arrive first. The engine remembers such cancels (at most 8 ids; cleared by `reset`) and the matching `start` then succeeds without listening. The Dart side also repeats the cancel if the session was resolved while its `start` was in flight.

## 6a. Dart core

- `SessionManager` owns the single active session and talks to the native side through `SmsConsentTransport`: `PigeonTransport` on Android, `UnsupportedTransport` elsewhere (every session ends with `Unsupported(platform)`).
- Dart resolves sessions locally first (cancel, replace, watchdog) and then sends `cancel`; the native side ends them without an event.
- **Watchdog (EC-26):** each session has a Dart timer for the clamped timeout + 5 s. It fails the session with `Failed(internal)` if no native result arrived. It stops on `consentShown`, like the native timers (EC-25).

## 7. Package layout (target)

```
sms_consent_kit/
├── pigeon/
│   └── messages.dart                   # Pigeon schema (single source of truth)
├── lib/
│   ├── sms_consent_kit.dart            # public export
│   └── src/
│       ├── sms_consent.dart            # SmsConsent, SmsConsentSession
│       ├── result.dart                 # sealed SmsConsentResult
│       ├── extractor.dart              # OtpExtractor
│       ├── options.dart                # policies
│       ├── widgets/sms_consent_scope.dart
│       ├── session_manager.dart
│       └── transport/
│           ├── transport.dart          # abstract
│           ├── pigeon_transport.dart   # Android
│           ├── unsupported_transport.dart
│           └── messages.g.dart         # generated
├── android/
│   ├── build.gradle.kts
│   └── src/main/kotlin/com/emirkanacar/sms_consent_kit/
│       ├── SmsConsentPlugin.kt
│       ├── SmsConsentEngine.kt
│       ├── ConsentReceiver.kt
│       ├── ConsentIntentGuard.kt
│       └── Messages.g.kt               # generated
├── tool/generate_pigeon.sh
├── example/
├── test/
└── doc/
```

The package targets Android only (only the `android` platform is declared in pubspec). Still, so that shared code does not crash when called on another platform, the transport is selected defensively: `UnsupportedTransport` if `kIsWeb` or `defaultTargetPlatform != TargetPlatform.android`, otherwise `PigeonTransport`.
