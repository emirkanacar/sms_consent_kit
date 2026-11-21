package com.emirkanacar.sms_consent_kit

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * Android entry point of sms_consent_kit.
 *
 * Each FlutterEngine gets its own instance; all state lives in that
 * instance's [SmsConsentEngine], and the Pigeon APIs are bound to that
 * engine's BinaryMessenger, so events only reach the engine that started
 * the session (EC-08).
 */
class SmsConsentPlugin : FlutterPlugin, ActivityAware, SmsConsentHostApi {
    private var engine: SmsConsentEngine? = null
    private var host: ActivityConsentHost? = null
    private var scope: CoroutineScope? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        val flutterApi = SmsConsentFlutterApi(binding.binaryMessenger)
        val eventScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        scope = eventScope

        val eventSink = object : EventSink {
            override fun send(event: SmsConsentEventMessage, onFailure: () -> Unit) {
                eventScope.launch {
                    try {
                        flutterApi.onEvent(event)
                    } catch (e: SmsConsentFlutterError) {
                        // channel-error: nothing is listening on the Dart side (EC-06).
                        onFailure()
                    }
                }
            }
        }

        engine = SmsConsentEngine(
            consentApi = GmsConsentApi(context),
            receivers = ContextReceiverRegistry(context),
            scheduler = HandlerScheduler(),
            isSafeConsentIntent = { ConsentIntentGuard.isSafe(it, context.packageManager) },
            events = eventSink,
        )
        SmsConsentHostApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        SmsConsentHostApi.setUp(binding.binaryMessenger, null)
        detachHost(isConfigChange = false)
        engine?.reset()
        engine = null
        scope?.cancel()
        scope = null
    }

    // region ActivityAware
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        attachHost(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        // The session survives (EC-04); a new binding follows right away.
        detachHost(isConfigChange = true)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        attachHost(binding)
    }

    override fun onDetachedFromActivity() {
        detachHost(isConfigChange = false)
    }

    private fun attachHost(binding: ActivityPluginBinding) {
        val currentEngine = engine ?: return
        detachHost(isConfigChange = true)
        host = ActivityConsentHost(binding, currentEngine).also { it.attach() }
    }

    private fun detachHost(isConfigChange: Boolean) {
        host?.dispose(isConfigChange)
        host = null
    }
    // endregion

    // region SmsConsentHostApi
    override suspend fun checkSupport(): SupportStatusMessage = requireEngine().checkSupport()

    override suspend fun start(request: StartRequestMessage) {
        val currentEngine = requireEngine()
        suspendCancellableCoroutine { continuation ->
            currentEngine.start(request) { result -> continuation.resumeWith(result) }
        }
    }

    override fun cancel(sessionId: Long) {
        engine?.cancel(sessionId)
    }

    override fun reset() {
        engine?.reset()
    }
    // endregion

    private fun requireEngine(): SmsConsentEngine =
        engine ?: throw SmsConsentFlutterError(ErrorCodes.INTERNAL, "Plugin is not attached to an engine.")
}
