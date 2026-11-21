package com.emirkanacar.sms_consent_kit

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.core.content.ContextCompat
import androidx.core.os.BundleCompat
import com.google.android.gms.auth.api.phone.SmsRetriever
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.Status

/** Extracts the consent intent from an SMS_RETRIEVED_ACTION broadcast. */
internal object ConsentBroadcast {
    /**
     * Returns the consent intent of a successful User Consent broadcast, or
     * null for anything else:
     * - Broadcasts of the hash-based SMS Retriever API share the action but
     *   carry no consent intent (EC-15). They are ignored, never consumed.
     * - Status.TIMEOUT is ignored on purpose. It cannot be attributed to a
     *   session: it may come from an earlier `start` call (whose 5 minutes run
     *   out first) or from another library. The session has its own timeout,
     *   which is always at most 5 minutes.
     */
    fun consentIntentOf(intent: Intent): Intent? {
        if (intent.action != SmsRetriever.SMS_RETRIEVED_ACTION) return null
        return try {
            val extras = intent.extras ?: return null
            val status = BundleCompat.getParcelable(extras, SmsRetriever.EXTRA_STATUS, Status::class.java)
            if (status?.statusCode != CommonStatusCodes.SUCCESS) return null
            BundleCompat.getParcelable(extras, SmsRetriever.EXTRA_CONSENT_INTENT, Intent::class.java)
        } catch (e: RuntimeException) {
            // Malformed extras (BadParcelableException etc.).
            null
        }
    }
}

/** Receiver for a single registration. Inert once [deactivate] is called. */
internal class ConsentReceiver(
    private val onConsentIntent: (Intent) -> Unit,
) : BroadcastReceiver() {
    private var active = true

    /**
     * A broadcast already queued for this instance may still be delivered
     * after unregisterReceiver; it must not reach the next session.
     */
    fun deactivate() {
        active = false
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (!active) return
        ConsentBroadcast.consentIntentOf(intent)?.let(onConsentIntent)
    }
}

/** Registers [ConsentReceiver] on the application context, one at a time. */
internal class ContextReceiverRegistry(private val context: Context) : ReceiverRegistry {
    private var receiver: ConsentReceiver? = null

    override fun register(onConsentIntent: (Intent) -> Unit) {
        unregister()
        val newReceiver = ConsentReceiver(onConsentIntent)
        ContextCompat.registerReceiver(
            context,
            newReceiver,
            IntentFilter(SmsRetriever.SMS_RETRIEVED_ACTION),
            // Only holders of this permission (Play Services) can send (T1).
            SmsRetriever.SEND_PERMISSION,
            // Main thread.
            null,
            // Required on Android 14+ (EC-14); the sender is another app.
            ContextCompat.RECEIVER_EXPORTED,
        )
        receiver = newReceiver
    }

    override fun unregister() {
        val current = receiver ?: return
        receiver = null
        current.deactivate()
        try {
            context.unregisterReceiver(current)
        } catch (e: IllegalArgumentException) {
            // Already unregistered.
        }
    }
}
