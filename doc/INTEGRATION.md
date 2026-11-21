# Integration guide

## 1. Installation

```yaml
dependencies:
  sms_consent_kit: ^0.1.0
```

### Android requirements (planned)

| Requirement | Value |
|---|---|
| Flutter | ≥ 3.27 (target; the exact lower bound will be set from the CI compat matrix) |
| Dart | ≥ 3.6 |
| `minSdk` | 24 (Android 7.0) |
| `compileSdk` | ≥ 34 |
| Permissions | **None.** `READ_SMS` / `RECEIVE_SMS` are not needed. |

No manifest changes are needed; the receiver is registered at runtime.

## 2. Basic usage

### With the widget (recommended)

```dart
class OtpPage extends StatefulWidget { /* ... */ }

class _OtpPageState extends State<OtpPage> {
  final _otp = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return SmsConsentScope(
      extractor: const OtpExtractor.digits(length: 6),
      timeout: const Duration(minutes: 2),
      onCode: (code) {
        _otp.text = code;
        _submit();
      },
      child: Column(children: [
        TextField(
          controller: _otp,
          autofillHints: const [AutofillHints.oneTimeCode], // keyboard code suggestions
          keyboardType: TextInputType.number,
        ),
        Builder(builder: (context) => TextButton(
          onPressed: () {
            _resendCode();
            SmsConsentScope.of(context).restart();
          },
          child: const Text('Resend code'),
        )),
      ]),
    );
  }
}
```

### Managing the session manually

```dart
final session = SmsConsent.instance.start(timeout: const Duration(minutes: 2));
// ... when leaving the screen:
await session.cancel();
```

**Rule:** Code that calls `start()` is also responsible for calling `cancel()`. If in doubt, use `SmsConsentScope`.

## 3. SMS format and backend guide

For the User Consent API to trigger (Google's rules):

1. The message must contain an alphanumeric code of **4–10 characters** with **at least one digit**.
2. The sender must **not be in the user's contacts**.
3. The SMS must arrive **after** listening starts → send the "send code" request to your backend **after** `start()`.

Recommended message template:

```
Your MyApp verification code is 482913.
Do not share this code with anyone.
```

Avoid:
- Other 4–8 digit numbers in the same message as the code (amounts, order numbers). If you cannot avoid them, use `OtpExtractor.keyword` / `regex`.
- Long marketing text before the code.

### `senderPhoneNumber`

- Pass it only if the sender is a real phone number (E.164 recommended, e.g. `+15551234567`).
- Leave it **`null`** for alphanumeric sender IDs (`MYBANK`, `SHOP`).

## 4. Recommended flow order

```
1. The OTP screen opens → SmsConsentScope starts a session
2. The app asks the backend to send the code
3. The SMS arrives → Android consent sheet ("Allow ... to read the message?")
4. The user allows → onCode(code)
5. The user leaves the screen → the session is cancelled automatically
```

## 5. Other platforms

The package supports Android only. If your app also runs on other platforms and the OTP screen is shared code, `sms_consent_kit` returns `Unsupported(platform)` there; `SmsConsentScope` does nothing and renders its child as is. You do not need to write platform checks.

## 6. Devices without Play Services

```dart
final support = await SmsConsent.instance.checkSupport();
if (!support.isSupported) {
  // Manual entry UI; HMS devices need a separate solution (out of scope).
}
```

Calling `checkSupport` is optional; `requestCode` already returns `Unsupported` on unsupported devices.

## 7. Release builds

No extra R8 / ProGuard rules are needed (Pigeon does not use reflection). If you run into problems, see the release checklist in TESTING.md.

## 8. Using it with other SMS packages

- It can work in the same app as a package that uses the (hash-based) `SMS Retriever API`; the broadcasts are told apart (EC-15).
- If **another** package also uses User Consent at the same time, both may try to open the consent sheet; use only one.
