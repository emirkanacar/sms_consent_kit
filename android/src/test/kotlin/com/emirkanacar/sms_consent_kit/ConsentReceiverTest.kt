package com.emirkanacar.sms_consent_kit

import android.app.Application
import android.content.Context
import android.content.Intent
import com.google.android.gms.auth.api.phone.SmsRetriever
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.Status
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class)
internal class ConsentReceiverTest {
    private lateinit var app: Application
    private val consent = Intent("test.CONSENT")

    @Before
    fun setUp() {
        app = RuntimeEnvironment.getApplication()
    }

    private fun broadcast(
        statusCode: Int? = CommonStatusCodes.SUCCESS,
        consentIntent: Intent? = consent,
        action: String = SmsRetriever.SMS_RETRIEVED_ACTION,
    ) = Intent(action).apply {
        statusCode?.let { putExtra(SmsRetriever.EXTRA_STATUS, Status(it)) }
        consentIntent?.let { putExtra(SmsRetriever.EXTRA_CONSENT_INTENT, it) }
    }

    private fun registeredConsentReceivers() =
        shadowOf(app).registeredReceivers.filter { it.broadcastReceiver is ConsentReceiver }

    // region ConsentBroadcast

    @Test
    fun successfulConsentBroadcast_yieldsConsentIntent() {
        val result = ConsentBroadcast.consentIntentOf(broadcast())
        assertEquals("test.CONSENT", result?.action)
    }

    @Test
    fun ec15_retrieverApiBroadcastWithoutConsentIntent_isIgnored() {
        assertNull(ConsentBroadcast.consentIntentOf(broadcast(consentIntent = null)))
    }

    @Test
    fun timeoutStatus_isIgnored() {
        // Cannot be attributed to a session; the engine has its own timeout.
        assertNull(ConsentBroadcast.consentIntentOf(broadcast(statusCode = CommonStatusCodes.TIMEOUT)))
    }

    @Test
    fun missingStatus_isIgnored() {
        assertNull(ConsentBroadcast.consentIntentOf(broadcast(statusCode = null)))
    }

    @Test
    fun otherAction_isIgnored() {
        assertNull(ConsentBroadcast.consentIntentOf(broadcast(action = "other.ACTION")))
    }

    @Test
    fun noExtras_isIgnored() {
        assertNull(ConsentBroadcast.consentIntentOf(Intent(SmsRetriever.SMS_RETRIEVED_ACTION)))
    }

    // endregion

    // region ContextReceiverRegistry

    @Test
    fun ec14_registersWithSendPermissionForTheRetrievedAction() {
        ContextReceiverRegistry(app).register {}

        val wrapper = registeredConsentReceivers().single()
        assertEquals(SmsRetriever.SEND_PERMISSION, wrapper.broadcastPermission)
        assertTrue(wrapper.intentFilter.hasAction(SmsRetriever.SMS_RETRIEVED_ACTION))
        assertEquals(1, wrapper.intentFilter.countActions())
        // Android 14+ throws without an explicit export flag; the sender is Play Services.
        assertEquals(Context.RECEIVER_EXPORTED, wrapper.flags and Context.RECEIVER_EXPORTED)
        assertEquals(0, wrapper.flags and Context.RECEIVER_NOT_EXPORTED)
    }

    @Test
    fun unregister_removesReceiverAndIsIdempotent() {
        val registry = ContextReceiverRegistry(app)
        registry.register {}
        registry.unregister()
        registry.unregister()

        assertTrue(registeredConsentReceivers().isEmpty())
    }

    @Test
    fun register_replacesPreviousRegistration() {
        val registry = ContextReceiverRegistry(app)
        registry.register {}
        registry.register {}

        assertEquals(1, registeredConsentReceivers().size)
    }

    @Test
    fun receiver_forwardsConsentIntent() {
        var received: Intent? = null
        ContextReceiverRegistry(app).register { received = it }
        val receiver = registeredConsentReceivers().single().broadcastReceiver

        receiver.onReceive(app, broadcast())

        assertEquals("test.CONSENT", received?.action)
    }

    @Test
    fun ec01_queuedBroadcastAfterUnregister_neverReachesTheCallback() {
        var calls = 0
        val registry = ContextReceiverRegistry(app)
        registry.register { calls++ }
        val oldReceiver = registeredConsentReceivers().single().broadcastReceiver

        registry.unregister()
        registry.register {}
        oldReceiver.onReceive(app, broadcast())

        assertEquals(0, calls)
        assertSame(1, registeredConsentReceivers().size)
    }

    // endregion
}
