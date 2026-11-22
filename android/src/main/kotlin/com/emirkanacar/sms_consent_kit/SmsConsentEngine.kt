package com.emirkanacar.sms_consent_kit

import android.app.Activity
import android.content.Intent
import com.google.android.gms.auth.api.phone.SmsRetriever

/** Error codes shared with the Dart side (doc/API.md §8). */
internal object ErrorCodes {
    /** Play Services is missing or outdated; the message carries the [SupportStatusMessage] name. */
    const val UNSUPPORTED = "unsupported"
    const val START_FAILED = "startFailed"
    const val INTENT_REJECTED = "intentRejected"
    const val NO_ACTIVITY = "noActivity"
    const val LAUNCH_FAILED = "launchFailed"
    const val INTERNAL = "internal"
}

/**
 * Per-engine session state machine (doc/ARCHITECTURE.md §3–4).
 *
 * Guarantees:
 * - At most one active session.
 * - A session reaches a terminal state exactly once; on that transition the
 *   receiver is unregistered and every timer is cancelled immediately.
 * - Without an active session nothing is ever launched (EC-01).
 * - Sessions ended by Dart (cancel, replace, reset) produce no event; Dart
 *   has already resolved them locally.
 *
 * Not thread-safe by design: every entry point runs on the main thread.
 */
internal class SmsConsentEngine(
    private val consentApi: ConsentApi,
    private val receivers: ReceiverRegistry,
    private val scheduler: Scheduler,
    private val isSafeConsentIntent: (Intent) -> Boolean,
    private val events: EventSink,
) {
    internal enum class State { LISTENING, DEFERRED, AWAITING_USER }

    private class Session(
        val id: Long,
        val backgroundPolicy: BackgroundPolicyMessage,
        val deferMaxDelayMs: Long,
    ) {
        var state = State.LISTENING
        var deferredIntent: Intent? = null
        var timeout: Cancellable? = null
        var deferTimeout: Cancellable? = null
        var orphanTimeout: Cancellable? = null

        fun cancelTimers() {
            timeout?.cancel()
            deferTimeout?.cancel()
            orphanTimeout?.cancel()
            timeout = null
            deferTimeout = null
            orphanTimeout = null
        }
    }

    private var session: Session? = null
    private var host: ConsentHost? = null

    /**
     * Ids cancelled before their `start` ran. Pigeon dispatches `@async` host
     * calls (start) to a later main-loop turn but runs synchronous ones (cancel)
     * right away, so a `cancel` sent after `start` can overtake it. Without this
     * the cancelled session would start listening with nobody waiting (EC-01).
     */
    private val cancelledBeforeStart = ArrayDeque<Long>()

    /** Visible for tests. */
    internal val activeSessionId: Long? get() = session?.id

    /** Visible for tests. */
    internal val activeState: State? get() = session?.state

    fun checkSupport(): SupportStatusMessage = consentApi.checkSupport()

    /**
     * Starts a session. [callback] is invoked exactly once: with success once
     * listening is registered, or with an [SmsConsentFlutterError].
     */
    fun start(request: StartRequestMessage, callback: (Result<Unit>) -> Unit) {
        // Dart's ConflictPolicy has already decided; end the old one silently.
        session?.let { finish(it, event = null) }

        if (cancelledBeforeStart.remove(request.sessionId)) {
            callback(Result.success(Unit))
            return
        }

        val support = consentApi.checkSupport()
        if (support != SupportStatusMessage.SUPPORTED) {
            callback(failure(ErrorCodes.UNSUPPORTED, support.name))
            return
        }
        if (request.backgroundPolicy == BackgroundPolicyMessage.CANCEL_ON_BACKGROUND && host == null) {
            // EC-07: the session would be cancelled immediately anyway.
            callback(failure(ErrorCodes.NO_ACTIVITY, "No Activity is attached."))
            return
        }

        val s = Session(
            id = request.sessionId,
            backgroundPolicy = request.backgroundPolicy,
            deferMaxDelayMs = request.deferMaxDelayMs.coerceIn(0, MAX_TIMEOUT_MS),
        )
        try {
            receivers.register(::onConsentIntent)
        } catch (e: RuntimeException) {
            callback(failure(ErrorCodes.INTERNAL, "Receiver registration failed: ${e.javaClass.simpleName}"))
            return
        }
        session = s
        // EC-27: Play Services stops listening after 5 minutes.
        val timeoutMs = request.timeoutMs.coerceIn(1, MAX_TIMEOUT_MS)
        s.timeout = scheduler.schedule(timeoutMs) { finish(s, s.event(EventTypeMessage.TIMED_OUT)) }

        val onComplete: (Exception?) -> Unit = onComplete@{ error ->
            if (session !== s) {
                // Replaced, cancelled or reset while starting; Dart no longer cares.
                callback(Result.success(Unit))
                return@onComplete
            }
            if (error == null) {
                callback(Result.success(Unit))
            } else {
                finish(s, event = null)
                callback(failure(ErrorCodes.START_FAILED, error.javaClass.simpleName))
            }
        }
        try {
            consentApi.startListening(request.senderPhoneNumber, onComplete)
        } catch (e: RuntimeException) {
            onComplete(e)
        }
    }

    /** Ends the session started by Dart with [sessionId]. No-op for any other id. */
    fun cancel(sessionId: Long) {
        val s = session
        if (s != null && s.id == sessionId) {
            finish(s, event = null)
            return
        }
        // Possibly a start that has not run yet. Ids are unique per Dart
        // isolate, so a few remembered ids are enough; stale ones age out.
        if (sessionId !in cancelledBeforeStart) {
            cancelledBeforeStart.addLast(sessionId)
            if (cancelledBeforeStart.size > MAX_REMEMBERED_CANCELS) cancelledBeforeStart.removeFirst()
        }
    }

    /** Ends any session silently (first access / hot restart / engine detach). */
    fun reset() {
        cancelledBeforeStart.clear()
        session?.let { finish(it, event = null) }
    }

    // region Host (Activity) lifecycle

    fun attachHost(newHost: ConsentHost) {
        host = newHost
        if (newHost.isResumed) onHostResumed()
    }

    /**
     * [isConfigChange] is true for rotation / dark mode / locale changes, where
     * a new host attaches right away and the session must survive (EC-04).
     */
    fun detachHost(isConfigChange: Boolean) {
        host = null
        if (isConfigChange) return
        val s = session ?: return
        when (s.state) {
            State.LISTENING, State.DEFERRED ->
                if (s.backgroundPolicy == BackgroundPolicyMessage.CANCEL_ON_BACKGROUND) {
                    finish(s, s.event(EventTypeMessage.CANCELLED))
                }
            State.AWAITING_USER ->
                // The result may still be delivered to a recreated Activity
                // (cached engine, "Don't keep activities"). Never wait forever.
                if (s.orphanTimeout == null) {
                    s.orphanTimeout = scheduler.schedule(ORPHAN_TIMEOUT_MS) {
                        finish(s, s.failed(ErrorCodes.NO_ACTIVITY))
                    }
                }
        }
    }

    fun onHostResumed() {
        val s = session ?: return
        val h = host ?: return
        if (s.state != State.DEFERRED) return
        val intent = s.deferredIntent ?: return
        launch(s, h, intent)
    }

    /** The host left the foreground. Ignored during configuration changes. */
    fun onHostStopped(isChangingConfigurations: Boolean) {
        if (isChangingConfigurations) return
        val s = session ?: return
        if (s.backgroundPolicy != BackgroundPolicyMessage.CANCEL_ON_BACKGROUND) return
        // While the consent sheet is open our Activity is covered by it; that is not "background".
        if (s.state == State.AWAITING_USER) return
        finish(s, s.event(EventTypeMessage.CANCELLED))
    }

    /** Returns true if [requestCode] belongs to this plugin, even when the result is dropped. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val s = session
        // Cancelled while the sheet was open, or the process was recreated (EC-05).
        if (s == null || s.state != State.AWAITING_USER) return true

        if (resultCode == Activity.RESULT_OK) {
            val message = data?.getStringExtra(SmsRetriever.EXTRA_SMS_MESSAGE)
            if (message == null) {
                finish(s, s.failed(ErrorCodes.INTERNAL))
            } else {
                finish(s, s.event(EventTypeMessage.RECEIVED, message = message))
            }
        } else {
            finish(s, s.event(EventTypeMessage.DENIED))
        }
        return true
    }

    // endregion

    private fun onConsentIntent(consentIntent: Intent) {
        val s = session ?: return
        // One sheet per session (EC-22). Later broadcasts are ignored.
        if (s.state != State.LISTENING) return

        if (!isSafeConsentIntent(consentIntent)) {
            finish(s, s.failed(ErrorCodes.INTENT_REJECTED))
            return
        }
        val h = host
        if (h != null && h.isResumed) {
            launch(s, h, consentIntent)
        } else {
            defer(s, consentIntent)
        }
    }

    private fun defer(s: Session, consentIntent: Intent) {
        if (s.backgroundPolicy == BackgroundPolicyMessage.CANCEL_ON_BACKGROUND) {
            finish(s, s.event(EventTypeMessage.CANCELLED))
            return
        }
        // EC-03: keep the intent in memory only, show it when the host resumes.
        s.state = State.DEFERRED
        s.deferredIntent = consentIntent
        s.deferTimeout = scheduler.schedule(s.deferMaxDelayMs) {
            finish(s, s.event(EventTypeMessage.TIMED_OUT))
        }
        emit(s, s.event(EventTypeMessage.CONSENT_DEFERRED))
    }

    private fun launch(s: Session, h: ConsentHost, consentIntent: Intent) {
        try {
            h.launch(consentIntent, REQUEST_CODE)
        } catch (e: RuntimeException) {
            finish(s, s.failed(ErrorCodes.LAUNCH_FAILED))
            return
        }
        // EC-25: once the sheet is open, the user decides; our timeouts stop.
        s.cancelTimers()
        s.deferredIntent = null
        s.state = State.AWAITING_USER
        emit(s, s.event(EventTypeMessage.CONSENT_SHOWN))
    }

    /** Non-terminal event. If Dart is gone (EC-06), end the session silently. */
    private fun emit(s: Session, event: SmsConsentEventMessage) {
        events.send(event) { if (session === s) finish(s, event = null) }
    }

    private fun finish(s: Session, event: SmsConsentEventMessage?) {
        if (session !== s) return
        session = null
        s.cancelTimers()
        s.deferredIntent = null
        receivers.unregister()
        if (event != null) events.send(event) {}
    }

    private fun Session.event(type: EventTypeMessage, message: String? = null) =
        SmsConsentEventMessage(sessionId = id, type = type, message = message)

    private fun Session.failed(errorCode: String) =
        SmsConsentEventMessage(sessionId = id, type = EventTypeMessage.FAILED, errorCode = errorCode)

    private fun failure(code: String, message: String): Result<Unit> =
        Result.failure(SmsConsentFlutterError(code, message))

    companion object {
        /** Play Services listens for at most 5 minutes. */
        const val MAX_TIMEOUT_MS = 5 * 60 * 1000L
        const val MAX_REMEMBERED_CANCELS = 8

        /** How long to wait for a result after the host Activity is destroyed with the sheet open. */
        const val ORPHAN_TIMEOUT_MS = 60 * 1000L

        /** Plugin-specific; fits in the lower 16 bits required by FragmentActivity. */
        const val REQUEST_CODE = 0x534B
    }
}
