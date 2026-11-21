package com.emirkanacar.sms_consent_kit

import android.content.Intent

internal class FakeConsentApi : ConsentApi {
    var support = SupportStatusMessage.SUPPORTED

    /** If false, completions are queued in [pending] until [completeNext]. */
    var completeImmediately = true
    var startError: Exception? = null
    var throwOnStart: RuntimeException? = null
    val pending = ArrayDeque<(Exception?) -> Unit>()
    val senders = mutableListOf<String?>()

    override fun checkSupport() = support

    override fun startListening(senderPhoneNumber: String?, onComplete: (Exception?) -> Unit) {
        throwOnStart?.let { throw it }
        senders += senderPhoneNumber
        if (completeImmediately) onComplete(startError) else pending.addLast(onComplete)
    }

    fun completeNext(error: Exception? = null) = pending.removeFirst()(error)
}

internal class FakeReceiverRegistry : ReceiverRegistry {
    var listener: ((Intent) -> Unit)? = null
        private set
    var registerCount = 0
        private set
    var throwOnRegister: RuntimeException? = null

    val isRegistered get() = listener != null

    override fun register(onConsentIntent: (Intent) -> Unit) {
        throwOnRegister?.let { throw it }
        registerCount++
        listener = onConsentIntent
    }

    override fun unregister() {
        listener = null
    }

    /** Simulates Play Services delivering a consent broadcast. */
    fun deliver(consentIntent: Intent) {
        listener?.invoke(consentIntent)
    }
}

/** Virtual-time scheduler. */
internal class FakeScheduler : Scheduler {
    private class Task(val at: Long, val action: () -> Unit) {
        var cancelled = false
    }

    var now = 0L
        private set
    private val tasks = mutableListOf<Task>()

    val pendingCount get() = tasks.count { !it.cancelled }

    override fun schedule(delayMs: Long, action: () -> Unit): Cancellable {
        val task = Task(now + delayMs, action)
        tasks += task
        return Cancellable { task.cancelled = true }
    }

    fun advanceBy(ms: Long) {
        val target = now + ms
        while (true) {
            val next = tasks.filter { !it.cancelled && it.at <= target }.minByOrNull { it.at } ?: break
            tasks.remove(next)
            now = next.at
            next.action()
        }
        tasks.removeAll { it.cancelled }
        now = target
    }
}

internal class FakeHost(override var isResumed: Boolean = true) : ConsentHost {
    val launched = mutableListOf<Pair<Intent, Int>>()
    var throwOnLaunch: RuntimeException? = null

    override fun launch(intent: Intent, requestCode: Int) {
        throwOnLaunch?.let { throw it }
        launched += intent to requestCode
    }
}

internal class RecordingEventSink : EventSink {
    val events = mutableListOf<SmsConsentEventMessage>()

    /** Simulates a Dart side that no longer listens (hot restart). */
    var dartIsGone = false

    val types get() = events.map { it.type }

    override fun send(event: SmsConsentEventMessage, onFailure: () -> Unit) {
        if (dartIsGone) onFailure() else events += event
    }
}
