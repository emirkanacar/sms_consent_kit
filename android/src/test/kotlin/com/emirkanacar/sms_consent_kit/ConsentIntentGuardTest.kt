package com.emirkanacar.sms_consent_kit

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class)
internal class ConsentIntentGuardTest {
    private lateinit var packageManager: PackageManager
    private val gmsConsent = ComponentName(ConsentIntentGuard.GMS_PACKAGE, "com.google.android.gms.auth.api.phone.ui.UserConsentPromptActivity")
    private val evil = ComponentName("com.evil.app", "com.evil.app.StealActivity")

    @Before
    fun setUp() {
        packageManager = RuntimeEnvironment.getApplication().packageManager
        shadowOf(packageManager).addActivityIfNotPresent(gmsConsent)
        shadowOf(packageManager).addActivityIfNotPresent(evil)
    }

    private fun intentFor(component: ComponentName) = Intent().setComponent(component)

    @Test
    fun intentResolvingToPlayServices_isSafe() {
        assertTrue(ConsentIntentGuard.isSafe(intentFor(gmsConsent), packageManager))
    }

    @Test
    fun intentResolvingToAnotherApp_isRejected() {
        assertFalse(ConsentIntentGuard.isSafe(intentFor(evil), packageManager))
    }

    @Test
    fun unresolvableIntent_isRejected() {
        val notInstalled = ComponentName("com.not.installed", "com.not.installed.Activity")
        assertFalse(ConsentIntentGuard.isSafe(intentFor(notInstalled), packageManager))
        assertFalse(ConsentIntentGuard.isSafe(Intent("test.NO_HANDLER"), packageManager))
    }

    @Test
    fun uriPermissionGrantFlags_areRejected() {
        listOf(
            Intent.FLAG_GRANT_READ_URI_PERMISSION,
            Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
        ).forEach { flag ->
            val intent = intentFor(gmsConsent).addFlags(flag)
            assertFalse(ConsentIntentGuard.isSafe(intent, packageManager), "flag $flag")
        }
    }

    @Test
    fun harmlessFlags_areAllowed() {
        val intent = intentFor(gmsConsent).addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION)
        assertTrue(ConsentIntentGuard.isSafe(intent, packageManager))
    }

    @Test
    fun selector_isRejected() {
        val intent = intentFor(gmsConsent).apply { selector = intentFor(evil) }
        assertFalse(ConsentIntentGuard.isSafe(intent, packageManager))
    }
}
