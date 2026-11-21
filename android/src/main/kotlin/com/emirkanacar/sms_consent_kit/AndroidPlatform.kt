package com.emirkanacar.sms_consent_kit

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.google.android.gms.auth.api.phone.SmsRetriever
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.lifecycle.HiddenLifecycleReference
import io.flutter.plugin.common.PluginRegistry

/** [ConsentApi] backed by Google Play Services. */
internal class GmsConsentApi(private val context: Context) : ConsentApi {
    override fun checkSupport(): SupportStatusMessage =
        // Also verifies the GMS signature and the minimum version this library needs (EC-12).
        when (GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context)) {
            ConnectionResult.SUCCESS -> SupportStatusMessage.SUPPORTED
            ConnectionResult.SERVICE_VERSION_UPDATE_REQUIRED,
            ConnectionResult.SERVICE_UPDATING,
            -> SupportStatusMessage.PLAY_SERVICES_OUTDATED
            else -> SupportStatusMessage.PLAY_SERVICES_UNAVAILABLE
        }

    override fun startListening(senderPhoneNumber: String?, onComplete: (Exception?) -> Unit) {
        // Task listeners without an executor run on the main thread.
        SmsRetriever.getClient(context)
            .startSmsUserConsent(senderPhoneNumber)
            .addOnSuccessListener { onComplete(null) }
            .addOnFailureListener { onComplete(it) }
    }
}

/** [Scheduler] on the main looper. */
internal class HandlerScheduler(
    private val handler: Handler = Handler(Looper.getMainLooper()),
) : Scheduler {
    override fun schedule(delayMs: Long, action: () -> Unit): Cancellable {
        val runnable = Runnable(action)
        handler.postDelayed(runnable, delayMs)
        return Cancellable { handler.removeCallbacks(runnable) }
    }
}

/**
 * [ConsentHost] for the Activity of one [ActivityPluginBinding].
 *
 * Forwards lifecycle changes and activity results to the engine. Call
 * [dispose] when the binding goes away.
 */
internal class ActivityConsentHost(
    private val binding: ActivityPluginBinding,
    private val engine: SmsConsentEngine,
) : ConsentHost, PluginRegistry.ActivityResultListener {
    // Works for both FlutterActivity and FlutterFragment hosts. Null only for
    // unusual custom embeddings; then window focus is the best signal we have.
    private val lifecycle: Lifecycle? = (binding.lifecycle as? HiddenLifecycleReference)?.lifecycle

    private val observer = LifecycleEventObserver { _, event ->
        when (event) {
            Lifecycle.Event.ON_RESUME -> engine.onHostResumed()
            // ON_STOP, not ON_PAUSE: a paused Activity can still be visible
            // (dialogs, multi-window). Stopped means it is in the background.
            Lifecycle.Event.ON_STOP -> engine.onHostStopped(binding.activity.isChangingConfigurations)
            else -> Unit
        }
    }

    override val isResumed: Boolean
        get() = lifecycle?.currentState?.isAtLeast(Lifecycle.State.RESUMED)
            ?: binding.activity.hasWindowFocus()

    override fun launch(intent: Intent, requestCode: Int) {
        binding.activity.startActivityForResult(intent, requestCode)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean =
        engine.onActivityResult(requestCode, resultCode, data)

    fun attach() {
        binding.addActivityResultListener(this)
        engine.attachHost(this)
        // Replays the events up to the current state, so a deferred sheet is
        // shown if the Activity is already resumed.
        lifecycle?.addObserver(observer)
    }

    fun dispose(isConfigChange: Boolean) {
        lifecycle?.removeObserver(observer)
        binding.removeActivityResultListener(this)
        engine.detachHost(isConfigChange)
    }
}
