package com.emirkanacar.sms_consent_kit

import android.content.Intent

/*
 * Seams between SmsConsentEngine and the Android platform.
 *
 * The engine only talks to these interfaces, so every lifecycle edge case
 * can be driven deterministically from unit tests with fakes. All methods
 * are called on, and must call back on, the main thread.
 */

/** Wraps Google Play Services (availability + SmsRetriever). */
internal interface ConsentApi {
    fun checkSupport(): SupportStatusMessage

    /**
     * Calls `startSmsUserConsent`. [onComplete] receives null on success or
     * the failure cause.
     */
    fun startListening(senderPhoneNumber: String?, onComplete: (Exception?) -> Unit)
}

/** Registers the SMS_RETRIEVED_ACTION receiver for the duration of a session. */
internal interface ReceiverRegistry {
    /**
     * Replaces any previous registration. [onConsentIntent] receives the
     * consent intent of a successful User Consent broadcast; every other
     * broadcast on the same action is ignored.
     */
    fun register(onConsentIntent: (Intent) -> Unit)

    /** Idempotent. After this returns, the previous callback is never invoked again. */
    fun unregister()
}

/** A cancellable handle for a scheduled action. */
internal fun interface Cancellable {
    fun cancel()
}

/** Main-thread delayed execution. */
internal interface Scheduler {
    fun schedule(delayMs: Long, action: () -> Unit): Cancellable
}

/** The Activity the consent sheet is launched from. */
internal interface ConsentHost {
    /** True if the host is in the foreground and may launch an Activity now. */
    val isResumed: Boolean

    /** Launches [intent] for a result. May throw (e.g. ActivityNotFoundException). */
    fun launch(intent: Intent, requestCode: Int)
}

/** Delivers events to Dart. */
internal interface EventSink {
    /** [onFailure] is called if nothing is listening on the Dart side. */
    fun send(event: SmsConsentEventMessage, onFailure: () -> Unit)
}
