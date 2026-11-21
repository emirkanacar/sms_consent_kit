package com.emirkanacar.sms_consent_kit

import kotlinx.coroutines.test.runTest
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

internal class SmsConsentPluginTest {
    @Test
    fun hostApiCallsBeforeAttach_failWithInternal() = runTest {
        val error = assertFailsWith<SmsConsentFlutterError> {
            SmsConsentPlugin().checkSupport()
        }
        assertEquals(ErrorCodes.INTERNAL, error.code)
    }

    @Test
    fun cancelAndReset_areSafeWithoutEngine() {
        val plugin = SmsConsentPlugin()
        plugin.cancel(42)
        plugin.reset()
    }
}
