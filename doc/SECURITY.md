# Security and privacy

## 1. Assets

- The SMS body (OTP + potentially personal data)
- The OTP code
- The app's Activity context (the ability to launch intents)

## 2. Threats and mitigations

| # | Threat | Mitigation |
|---|---|---|
| T1 | A malicious app sends a fake `SMS_RETRIEVED_ACTION` broadcast and makes us launch its intent (**intent redirection**) | The receiver is registered with `SmsRetriever.SEND_PERMISSION`, so only holders of that permission (Play Services) can send it. Plus `ConsentIntentGuard` (below). |
| T2 | The consent intent targets an unexpected component or carries URI permissions | `ConsentIntentGuard`: the `resolveActivity()` package must be `com.google.android.gms`; intents carrying `FLAG_GRANT_READ/WRITE_URI_PERMISSION`, `FLAG_GRANT_PERSISTABLE_URI_PERMISSION` or `FLAG_GRANT_PREFIX_URI_PERMISSION` are rejected. On failure: `Failed(intentRejected)`. This also avoids the Play Console *Unsafe Intent* warning. |
| T3 | Consent sheet on the wrong screen → the user shares an unrelated message without noticing | Session model (EC-01, EC-02). |
| T4 | SMS content leaking into logs or crash reports | Content is never logged in any layer; `toString()` is masked; error objects carry no content. |
| T5 | Content written to disk | No persistent storage; the result is dropped on process death. |
| T6 | The receiver staying registered longer than needed (attack surface) | Registered only for the duration of a session. |
| T7 | Accidentally consuming another plugin's `onActivityResult` | Plugin-specific `REQUEST_CODE`; returns `false` for results that do not match. |

## 3. `ConsentIntentGuard` (draft)

```kotlin
internal object ConsentIntentGuard {
    private const val GMS = "com.google.android.gms"
    private const val FORBIDDEN_FLAGS =
        Intent.FLAG_GRANT_READ_URI_PERMISSION or
        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
        Intent.FLAG_GRANT_PREFIX_URI_PERMISSION

    fun validate(intent: Intent, pm: PackageManager): Boolean {
        val component = intent.resolveActivity(pm) ?: return false
        if (component.packageName != GMS) return false
        if (intent.flags and FORBIDDEN_FLAGS != 0) return false
        return true
    }
}
```

Note: Android 11+ package visibility rules apply to `resolveActivity`. Whether a `<queries>` entry for `com.google.android.gms` is needed in the manifest will be verified during implementation. If it is, it goes into the plugin manifest; app developers do not need to do anything.

## 4. Recommendations for app developers

- Always verify the OTP **on the server**; a code coming from the client is not a source of trust on its own.
- Do not send `SmsConsentReceived.message` to analytics or logging services.
- Blocking screenshots on the OTP screen (`FLAG_SECURE`) is the app's decision; the package does not touch it.

## 5. Reporting vulnerabilities

See the root [SECURITY.md](../SECURITY.md). Report vulnerabilities through the private channel, not as public issues.
