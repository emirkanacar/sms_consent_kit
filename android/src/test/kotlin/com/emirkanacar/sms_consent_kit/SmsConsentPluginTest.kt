package com.emirkanacar.sms_consent_kit

import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

/*
 * Run from example/android:
 *   ./gradlew :sms_consent_kit:testDebugUnitTest
 */
internal class SmsConsentPluginTest {
    @Test
    fun checkSupport_isNotImplementedYet() = runTest {
        val error = assertFailsWith<SmsConsentFlutterError> {
            SmsConsentPlugin().checkSupport()
        }
        assertEquals("unimplemented", error.code)
    }

    @Test
    fun cancelAndReset_areSafeWithoutSession() {
        val plugin = SmsConsentPlugin()
        plugin.cancel(42)
        plugin.reset()
    }
}
