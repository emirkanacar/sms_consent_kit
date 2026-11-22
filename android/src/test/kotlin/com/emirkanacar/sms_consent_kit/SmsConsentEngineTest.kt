package com.emirkanacar.sms_consent_kit

import android.app.Activity
import android.content.Intent
import com.emirkanacar.sms_consent_kit.SmsConsentEngine.State
import com.google.android.gms.auth.api.phone.SmsRetriever
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

/*
 * State machine tests. Robolectric is only needed for android.content.Intent;
 * every platform dependency is a fake, and time is virtual.
 *
 * Run from example/android:
 *   ./gradlew :sms_consent_kit:testDebugUnitTest
 */
@RunWith(RobolectricTestRunner::class)
internal class SmsConsentEngineTest {
    private lateinit var api: FakeConsentApi
    private lateinit var receivers: FakeReceiverRegistry
    private lateinit var scheduler: FakeScheduler
    private lateinit var sink: RecordingEventSink
    private lateinit var host: FakeHost
    private lateinit var engine: SmsConsentEngine
    private var intentIsSafe = true

    private val consentIntent = Intent("test.CONSENT")

    @Before
    fun setUp() {
        api = FakeConsentApi()
        receivers = FakeReceiverRegistry()
        scheduler = FakeScheduler()
        sink = RecordingEventSink()
        host = FakeHost(isResumed = true)
        engine = SmsConsentEngine(api, receivers, scheduler, { intentIsSafe }, sink)
        engine.attachHost(host)
    }

    // region helpers

    private fun request(
        id: Long = 1,
        timeoutMs: Long = 120_000,
        policy: BackgroundPolicyMessage = BackgroundPolicyMessage.DEFER_UNTIL_RESUMED,
        deferMaxDelayMs: Long = 30_000,
        sender: String? = null,
    ) = StartRequestMessage(id, sender, timeoutMs, policy, deferMaxDelayMs)

    private fun start(request: StartRequestMessage = request()): Result<Unit>? {
        var result: Result<Unit>? = null
        engine.start(request) {
            if (result != null) fail("callback invoked twice")
            result = it
        }
        return result
    }

    private fun Result<Unit>?.errorCode(): String? =
        (this?.exceptionOrNull() as? SmsConsentFlutterError)?.code

    private fun smsResult(message: String?) =
        Intent().apply { message?.let { putExtra(SmsRetriever.EXTRA_SMS_MESSAGE, it) } }

    private fun assertIdle() {
        assertNull(engine.activeSessionId)
        assertFalse(receivers.isRegistered, "receiver must be unregistered")
        assertEquals(0, scheduler.pendingCount, "no timers may be left")
    }

    private fun showSheet() {
        assertTrue(start()!!.isSuccess)
        receivers.deliver(consentIntent)
        assertEquals(State.AWAITING_USER, engine.activeState)
    }

    // endregion

    @Test
    fun start_registersReceiverAndSucceeds() {
        val result = start(request(sender = "+15551234567"))

        assertTrue(result!!.isSuccess)
        assertTrue(receivers.isRegistered)
        assertEquals(listOf<String?>("+15551234567"), api.senders)
        assertEquals(State.LISTENING, engine.activeState)
        assertTrue(sink.events.isEmpty())
    }

    @Test
    fun fullFlow_received() {
        showSheet()
        assertEquals(1, host.launched.size)
        assertEquals(SmsConsentEngine.REQUEST_CODE, host.launched.single().second)

        val handled = engine.onActivityResult(
            SmsConsentEngine.REQUEST_CODE, Activity.RESULT_OK, smsResult("Your code is 482913"),
        )

        assertTrue(handled)
        assertEquals(listOf(EventTypeMessage.CONSENT_SHOWN, EventTypeMessage.RECEIVED), sink.types)
        assertEquals("Your code is 482913", sink.events.last().message)
        assertEquals(1L, sink.events.last().sessionId)
        assertIdle()
    }

    @Test
    fun userDenies_denied() {
        showSheet()
        engine.onActivityResult(SmsConsentEngine.REQUEST_CODE, Activity.RESULT_CANCELED, null)

        assertEquals(EventTypeMessage.DENIED, sink.types.last())
        assertIdle()
    }

    @Test
    fun okWithoutMessage_failsInternal() {
        showSheet()
        engine.onActivityResult(SmsConsentEngine.REQUEST_CODE, Activity.RESULT_OK, smsResult(null))

        assertEquals(EventTypeMessage.FAILED, sink.types.last())
        assertEquals(ErrorCodes.INTERNAL, sink.events.last().errorCode)
        assertIdle()
    }

    @Test
    fun terminalStateIsProducedOnce() {
        showSheet()
        engine.onActivityResult(SmsConsentEngine.REQUEST_CODE, Activity.RESULT_OK, smsResult("1234"))
        val handledAgain = engine.onActivityResult(SmsConsentEngine.REQUEST_CODE, Activity.RESULT_OK, smsResult("5678"))

        assertTrue(handledAgain, "our request code is still consumed")
        assertEquals(1, sink.types.count { it == EventTypeMessage.RECEIVED })
    }

    @Test
    fun foreignRequestCode_isNotConsumed() {
        showSheet()
        assertFalse(engine.onActivityResult(1, Activity.RESULT_OK, null))
        assertEquals(State.AWAITING_USER, engine.activeState)
    }

    // region EC-01 / EC-10 / EC-22: no sheet outside a session

    @Test
    fun ec01_broadcastAfterCancel_launchesNothing() {
        start()
        val staleListener = receivers.listener!!
        engine.cancel(1)

        staleListener(consentIntent)

        assertTrue(host.launched.isEmpty())
        assertTrue(sink.events.isEmpty(), "Dart-initiated cancel produces no event")
        assertIdle()
    }

    @Test
    fun ec01_cancelWithOtherId_isNoOp() {
        start(request(id = 7))
        engine.cancel(6)
        assertEquals(7L, engine.activeSessionId)
    }

    @Test
    fun ec01_cancelOvertakingItsStart_neverListens() {
        // Pigeon runs the sync cancel before the dispatched async start.
        engine.cancel(5)
        val result = start(request(id = 5))

        assertTrue(result!!.isSuccess, "Dart already resolved the session")
        assertEquals(0, receivers.registerCount)
        assertTrue(api.senders.isEmpty())
        assertIdle()

        // The id is consumed; it does not affect later sessions.
        assertTrue(start(request(id = 6))!!.isSuccess)
        assertEquals(6L, engine.activeSessionId)
    }

    @Test
    fun ec01_rememberedCancelsAreBounded() {
        (1L..SmsConsentEngine.MAX_REMEMBERED_CANCELS + 1L).forEach(engine::cancel)

        start(request(id = 1))
        assertEquals(1L, engine.activeSessionId, "the oldest remembered id aged out")
    }

    @Test
    fun reset_forgetsRememberedCancels() {
        engine.cancel(5)
        engine.reset()
        start(request(id = 5))
        assertEquals(5L, engine.activeSessionId)
    }

    @Test
    fun ec22_secondBroadcastWhileSheetOpen_isIgnored() {
        showSheet()
        receivers.deliver(Intent("test.SECOND"))
        assertEquals(1, host.launched.size)
    }

    @Test
    fun cancelWhileSheetOpen_resultIsConsumedAndDropped() {
        showSheet()
        engine.cancel(1)
        assertIdle()

        val handled = engine.onActivityResult(SmsConsentEngine.REQUEST_CODE, Activity.RESULT_OK, smsResult("1234"))

        assertTrue(handled)
        assertEquals(listOf(EventTypeMessage.CONSENT_SHOWN), sink.types)
    }

    // endregion

    // region Timeouts (EC-25, EC-27)

    @Test
    fun timeout_timedOut() {
        start(request(timeoutMs = 60_000))
        scheduler.advanceBy(59_999)
        assertEquals(State.LISTENING, engine.activeState)

        scheduler.advanceBy(1)

        assertEquals(listOf(EventTypeMessage.TIMED_OUT), sink.types)
        assertIdle()
    }

    @Test
    fun ec27_timeoutIsClampedToFiveMinutes() {
        start(request(timeoutMs = 10 * 60_000))
        scheduler.advanceBy(SmsConsentEngine.MAX_TIMEOUT_MS)
        assertEquals(listOf(EventTypeMessage.TIMED_OUT), sink.types)
    }

    @Test
    fun ec25_timeoutStopsWhileSheetIsOpen() {
        showSheet()
        scheduler.advanceBy(10 * 60_000)

        assertEquals(State.AWAITING_USER, engine.activeState)
        assertEquals(listOf(EventTypeMessage.CONSENT_SHOWN), sink.types)
    }

    // endregion

    // region EC-03: background policies

    @Test
    fun ec03_defer_showsSheetOnResume() {
        start()
        host.isResumed = false
        receivers.deliver(consentIntent)

        assertEquals(State.DEFERRED, engine.activeState)
        assertEquals(listOf(EventTypeMessage.CONSENT_DEFERRED), sink.types)
        assertTrue(host.launched.isEmpty())

        host.isResumed = true
        engine.onHostResumed()

        assertEquals(State.AWAITING_USER, engine.activeState)
        assertEquals(1, host.launched.size)
        assertEquals(EventTypeMessage.CONSENT_SHOWN, sink.types.last())
    }

    @Test
    fun ec03_defer_expires() {
        start(request(deferMaxDelayMs = 30_000))
        host.isResumed = false
        receivers.deliver(consentIntent)

        scheduler.advanceBy(30_000)
        assertEquals(EventTypeMessage.TIMED_OUT, sink.types.last())
        assertIdle()

        host.isResumed = true
        engine.onHostResumed()
        assertTrue(host.launched.isEmpty(), "an expired sheet must never appear later")
    }

    @Test
    fun ec03_stopDoesNotCancelWithDeferPolicy() {
        start()
        engine.onHostStopped(isChangingConfigurations = false)
        assertEquals(State.LISTENING, engine.activeState)
    }

    @Test
    fun ec03_cancelOnBackground_cancelsWhenStopped() {
        start(request(policy = BackgroundPolicyMessage.CANCEL_ON_BACKGROUND))
        engine.onHostStopped(isChangingConfigurations = false)

        assertEquals(listOf(EventTypeMessage.CANCELLED), sink.types)
        assertIdle()
    }

    @Test
    fun ec03_cancelOnBackground_broadcastInBackgroundCancels() {
        start(request(policy = BackgroundPolicyMessage.CANCEL_ON_BACKGROUND))
        host.isResumed = false
        receivers.deliver(consentIntent)

        assertEquals(listOf(EventTypeMessage.CANCELLED), sink.types)
        assertTrue(host.launched.isEmpty())
        assertIdle()
    }

    @Test
    fun ec03_cancelOnBackground_sheetCoveringActivityIsNotBackground() {
        start(request(policy = BackgroundPolicyMessage.CANCEL_ON_BACKGROUND))
        receivers.deliver(consentIntent)
        engine.onHostStopped(isChangingConfigurations = false)

        assertEquals(State.AWAITING_USER, engine.activeState)
    }

    // endregion

    // region EC-04 / EC-07: Activity lifecycle

    @Test
    fun ec04_configChangeWhileListening_cancelOnBackgroundSurvives() {
        start(request(policy = BackgroundPolicyMessage.CANCEL_ON_BACKGROUND))
        engine.onHostStopped(isChangingConfigurations = true)
        engine.detachHost(isConfigChange = true)
        engine.attachHost(FakeHost())

        assertEquals(State.LISTENING, engine.activeState)
    }

    @Test
    fun ec04_configChangeWhileSheetOpen_resultArrivesOnNewHost() {
        showSheet()
        engine.detachHost(isConfigChange = true)
        engine.attachHost(FakeHost())

        engine.onActivityResult(SmsConsentEngine.REQUEST_CODE, Activity.RESULT_OK, smsResult("1234"))

        assertEquals(EventTypeMessage.RECEIVED, sink.types.last())
        assertIdle()
    }

    @Test
    fun ec04_broadcastDuringConfigChange_isShownOnNewHost() {
        start()
        engine.detachHost(isConfigChange = true)
        receivers.deliver(consentIntent)
        assertEquals(State.DEFERRED, engine.activeState)

        val newHost = FakeHost(isResumed = true)
        engine.attachHost(newHost)

        assertEquals(1, newHost.launched.size)
        assertEquals(State.AWAITING_USER, engine.activeState)
    }

    @Test
    fun activityDestroyedWithSheetOpen_failsAfterOrphanTimeout() {
        showSheet()
        engine.detachHost(isConfigChange = false)

        scheduler.advanceBy(SmsConsentEngine.ORPHAN_TIMEOUT_MS)

        assertEquals(EventTypeMessage.FAILED, sink.types.last())
        assertEquals(ErrorCodes.NO_ACTIVITY, sink.events.last().errorCode)
        assertIdle()
    }

    @Test
    fun ec07_cancelOnBackgroundWithoutActivity_failsNoActivity() {
        engine.detachHost(isConfigChange = false)
        val result = start(request(policy = BackgroundPolicyMessage.CANCEL_ON_BACKGROUND))

        assertEquals(ErrorCodes.NO_ACTIVITY, result.errorCode())
        assertEquals(0, receivers.registerCount)
    }

    @Test
    fun ec07_activityGoneWithCancelOnBackground_cancels() {
        start(request(policy = BackgroundPolicyMessage.CANCEL_ON_BACKGROUND))
        engine.detachHost(isConfigChange = false)

        assertEquals(listOf(EventTypeMessage.CANCELLED), sink.types)
        assertIdle()
    }

    // endregion

    // region EC-06: hot restart

    @Test
    fun ec06_reset_endsSessionSilently() {
        showSheet()
        engine.reset()

        assertEquals(listOf(EventTypeMessage.CONSENT_SHOWN), sink.types)
        assertIdle()
    }

    @Test
    fun ec06_dartGone_endsSessionSilently() {
        start()
        host.isResumed = false
        sink.dartIsGone = true
        receivers.deliver(consentIntent)

        assertIdle()
        host.isResumed = true
        engine.onHostResumed()
        assertTrue(host.launched.isEmpty())
    }

    // endregion

    // region EC-09: replace

    @Test
    fun ec09_newStartReplacesOldSilently() {
        start(request(id = 1))
        start(request(id = 2))

        assertEquals(2L, engine.activeSessionId)
        assertEquals(2, receivers.registerCount)
        assertTrue(sink.events.isEmpty())

        engine.cancel(1)
        assertEquals(2L, engine.activeSessionId, "a stale cancel must not end the new session")
    }

    @Test
    fun ec09_lateStartCompletionOfReplacedSession_isHarmless() {
        api.completeImmediately = false
        var first: Result<Unit>? = null
        engine.start(request(id = 1)) { first = it }
        engine.start(request(id = 2)) {}

        api.completeNext(RuntimeException("late"))

        assertTrue(first!!.isSuccess)
        assertEquals(2L, engine.activeSessionId)
    }

    // endregion

    // region EC-12 and start failures

    @Test
    fun ec12_playServicesMissing_unsupported() {
        api.support = SupportStatusMessage.PLAY_SERVICES_OUTDATED
        val result = start()

        assertEquals(ErrorCodes.UNSUPPORTED, result.errorCode())
        assertEquals("PLAY_SERVICES_OUTDATED", result?.exceptionOrNull()?.message)
        assertEquals(0, receivers.registerCount)
        assertIdle()
    }

    @Test
    fun startTaskFails_startFailedAndCleanedUp() {
        api.startError = IllegalStateException("boom")
        val result = start()

        assertEquals(ErrorCodes.START_FAILED, result.errorCode())
        assertTrue(sink.events.isEmpty())
        assertIdle()
    }

    @Test
    fun startThrowsSynchronously_startFailedAndCleanedUp() {
        api.throwOnStart = SecurityException("boom")
        val result = start()

        assertEquals(ErrorCodes.START_FAILED, result.errorCode())
        assertIdle()
    }

    @Test
    fun receiverRegistrationThrows_internal() {
        receivers.throwOnRegister = IllegalStateException("boom")
        val result = start()

        assertEquals(ErrorCodes.INTERNAL, result.errorCode())
        assertIdle()
    }

    // endregion

    // region Security

    @Test
    fun unsafeConsentIntent_isRejectedAndNeverLaunched() {
        intentIsSafe = false
        start()
        receivers.deliver(consentIntent)

        assertTrue(host.launched.isEmpty())
        assertEquals(EventTypeMessage.FAILED, sink.types.single())
        assertEquals(ErrorCodes.INTENT_REJECTED, sink.events.single().errorCode)
        assertIdle()
    }

    @Test
    fun launchThrows_launchFailed() {
        host.throwOnLaunch = android.content.ActivityNotFoundException()
        start()
        receivers.deliver(consentIntent)

        assertEquals(ErrorCodes.LAUNCH_FAILED, sink.events.single().errorCode)
        assertIdle()
    }

    // endregion
}
