package com.emirkanacar.sms_consent_kit

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding

/**
 * Android entry point of sms_consent_kit.
 *
 * Each FlutterEngine gets its own instance; state lives on the instance and
 * the Pigeon APIs are bound to that engine's BinaryMessenger.
 *
 * Phase 0: skeleton only. Session logic arrives in phase 1 with
 * `SmsConsentEngine`, `ConsentReceiver` and `ConsentIntentGuard`.
 */
class SmsConsentPlugin : FlutterPlugin, ActivityAware, SmsConsentHostApi {
    private var flutterApi: SmsConsentFlutterApi? = null
    private var activityBinding: ActivityPluginBinding? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        SmsConsentHostApi.setUp(binding.binaryMessenger, this)
        flutterApi = SmsConsentFlutterApi(binding.binaryMessenger)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        reset()
        SmsConsentHostApi.setUp(binding.binaryMessenger, null)
        flutterApi = null
    }

    // region ActivityAware
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
    }

    override fun onDetachedFromActivityForConfigChanges() {
        // The session survives (EC-04); only the Activity reference is dropped.
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
    }

    override fun onDetachedFromActivity() {
        activityBinding = null
    }
    // endregion

    // region SmsConsentHostApi
    override suspend fun checkSupport(): SupportStatusMessage = throw notImplemented()

    override suspend fun start(request: StartRequestMessage) {
        throw notImplemented()
    }

    override fun cancel(sessionId: Long) {
        // Phase 1.
    }

    override fun reset() {
        // Phase 1.
    }
    // endregion

    private fun notImplemented() =
        SmsConsentFlutterError("unimplemented", "Not implemented yet (phase 1).")
}
