package com.emirkanacar.sms_consent_kit

import android.content.Intent
import android.content.pm.PackageManager

/**
 * Validates the consent intent before it is launched (doc/SECURITY.md, T1/T2).
 *
 * The broadcast can only come from Play Services (the receiver requires
 * SmsRetriever.SEND_PERMISSION, a signature permission of GMS), and the GMS
 * package is signature-checked by GoogleApiAvailability before a session
 * starts. This guard is defense in depth against intent redirection and is
 * what the Play Console "Unsafe Intent" check expects: the intent must resolve
 * to Play Services and must not grant URI permissions.
 */
internal object ConsentIntentGuard {
    const val GMS_PACKAGE = "com.google.android.gms"

    private const val FORBIDDEN_FLAGS =
        Intent.FLAG_GRANT_READ_URI_PERMISSION or
            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
            Intent.FLAG_GRANT_PREFIX_URI_PERMISSION

    fun isSafe(intent: Intent, packageManager: PackageManager): Boolean {
        if (intent.flags and FORBIDDEN_FLAGS != 0) return false
        // A selector replaces the intent during resolution; it could point anywhere.
        if (intent.selector != null) return false
        // The plugin manifest declares a <queries> entry so GMS is visible on Android 11+.
        val component = try {
            intent.resolveActivity(packageManager)
        } catch (e: RuntimeException) {
            null
        } ?: return false
        return component.packageName == GMS_PACKAGE
    }
}
