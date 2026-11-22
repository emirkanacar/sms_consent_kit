package com.emirkanacar.sms_consent_kit

import android.app.Activity
import android.app.Application
import android.content.BroadcastReceiver
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
import kotlin.random.Random
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/*
 * Resource leak check (doc/PLAN.md, phase 4): 1000 sessions through random
 * lifecycle paths with the real receiver registry. After every session the
 * engine must be back to idle: no registered receiver, no timer, no kept
 * intent, bounded bookkeeping, and at most one terminal event per session.
 */
@RunWith(RobolectricTestRunner::class)
internal class SmsConsentStressTest {
    private lateinit var app: Application
    private lateinit var api: FakeConsentApi
    private lateinit var scheduler: FakeScheduler
    private lateinit var sink: RecordingEventSink
    private lateinit var host: FakeHost
    private lateinit var engine: SmsConsentEngine
    private var intentIsSafe = true

    /** Every receiver ever registered, to check that old ones stay inert. */
    private val seenReceivers = mutableSetOf<BroadcastReceiver>()
    private var nextId = 1L

    @Before
    fun setUp() {
        app = RuntimeEnvironment.getApplication()
        api = FakeConsentApi()
        scheduler = FakeScheduler()
        sink = RecordingEventSink()
        host = FakeHost(isResumed = true)
        engine = SmsConsentEngine(api, ContextReceiverRegistry(app), scheduler, { intentIsSafe }, sink)
        engine.attachHost(host)
    }

    private fun registered() =
        shadowOf(app).registeredReceivers.filter { it.broadcastReceiver is ConsentReceiver }

    private fun request(
        id: Long,
        policy: BackgroundPolicyMessage = BackgroundPolicyMessage.DEFER_UNTIL_RESUMED,
    ) = StartRequestMessage(id, null, 120_000, policy, 30_000)

    private fun start(id: Long, policy: BackgroundPolicyMessage = BackgroundPolicyMessage.DEFER_UNTIL_RESUMED) {
        engine.start(request(id, policy)) {}
        registered().forEach { seenReceivers += it.broadcastReceiver }
    }

    private fun consentBroadcast() = Intent(SmsRetriever.SMS_RETRIEVED_ACTION).apply {
        putExtra(SmsRetriever.EXTRA_STATUS, Status(CommonStatusCodes.SUCCESS))
        putExtra(SmsRetriever.EXTRA_CONSENT_INTENT, Intent("test.CONSENT"))
    }

    /** Delivers an SMS broadcast the way the system would: to every registered receiver. */
    private fun deliverSms() {
        registered().map { it.broadcastReceiver }.forEach { it.onReceive(app, consentBroadcast()) }
    }

    private fun allow(message: String = "code 1234") =
        engine.onActivityResult(
            SmsConsentEngine.REQUEST_CODE,
            Activity.RESULT_OK,
            Intent().putExtra(SmsRetriever.EXTRA_SMS_MESSAGE, message),
        )

    private fun deny() = engine.onActivityResult(SmsConsentEngine.REQUEST_CODE, Activity.RESULT_CANCELED, null)

    private fun runScenario(kind: Int) {
        val id = nextId++
        when (kind) {
            0 -> { start(id); engine.cancel(id) }
            1 -> { start(id); scheduler.advanceBy(120_000) }
            2 -> { start(id); deliverSms(); allow() }
            3 -> { start(id); deliverSms(); deny() }
            4 -> {
                start(id)
                host.isResumed = false
                deliverSms()
                scheduler.advanceBy(10_000)
                host.isResumed = true
                engine.onHostResumed()
                allow()
            }
            5 -> {
                start(id)
                host.isResumed = false
                deliverSms()
                scheduler.advanceBy(31_000)
                host.isResumed = true
                engine.onHostResumed()
            }
            6 -> {
                start(id, BackgroundPolicyMessage.CANCEL_ON_BACKGROUND)
                engine.onHostStopped(isChangingConfigurations = false)
            }
            7 -> {
                start(id)
                val next = nextId++
                start(next)
                engine.cancel(id) // late cancel of the replaced one: harmless
                engine.cancel(next)
            }
            8 -> {
                api.startError = IllegalStateException("boom")
                start(id)
                api.startError = null
            }
            9 -> { engine.cancel(id); start(id) } // cancel overtakes its start
            10 -> {
                api.completeImmediately = false
                start(id)
                engine.cancel(id)
                api.completeNext()
                api.completeImmediately = true
            }
            11 -> {
                start(id)
                deliverSms()
                engine.detachHost(isConfigChange = false)
                scheduler.advanceBy(SmsConsentEngine.ORPHAN_TIMEOUT_MS)
                engine.attachHost(host)
            }
            12 -> {
                start(id)
                deliverSms()
                engine.detachHost(isConfigChange = true)
                host = FakeHost(isResumed = true)
                engine.attachHost(host)
                allow()
            }
            13 -> { start(id); engine.reset() }
            14 -> {
                start(id)
                sink.dartIsGone = true
                deliverSms() // consentShown cannot be delivered: end silently
                sink.dartIsGone = false
                deny()
            }
            15 -> {
                intentIsSafe = false
                start(id)
                deliverSms()
                intentIsSafe = true
            }
            else -> error("unknown scenario $kind")
        }
    }

    private fun assertIdle(context: String) {
        assertNull(engine.activeSessionId, "active session after $context")
        assertTrue(registered().isEmpty(), "receiver leaked after $context")
        assertEquals(0, scheduler.pendingCount, "timer leaked after $context")
        assertTrue(engine.rememberedCancelCount <= SmsConsentEngine.MAX_REMEMBERED_CANCELS, "cancels unbounded")
    }

    @Test
    fun thousandRandomSessions_leaveNothingBehind() {
        val random = Random(seed = 20261122)
        val scenarios = 16
        val kinds = (0 until 1000).map { if (it < scenarios) it else random.nextInt(scenarios) }

        for ((index, kind) in kinds.withIndex()) {
            runScenario(kind)
            assertIdle("session #$index (scenario $kind)")
        }

        val terminal = setOf(
            EventTypeMessage.RECEIVED,
            EventTypeMessage.DENIED,
            EventTypeMessage.TIMED_OUT,
            EventTypeMessage.CANCELLED,
            EventTypeMessage.FAILED,
        )
        val perSession = sink.events.filter { it.type in terminal }.groupingBy { it.sessionId }.eachCount()
        assertTrue(perSession.values.all { it == 1 }, "a session produced more than one terminal event")

        // Old receivers must stay inert: a late SMS reaches nothing.
        val eventsBefore = sink.events.size
        val launchesBefore = host.launched.size
        seenReceivers.forEach { it.onReceive(app, consentBroadcast()) }
        assertEquals(eventsBefore, sink.events.size)
        assertEquals(launchesBefore, host.launched.size)
        assertTrue(seenReceivers.size > 500, "the test must actually register receivers")
    }
}
