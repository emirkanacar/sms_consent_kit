/// Session-based, lifecycle-aware and secure one-time code (OTP) autofill
/// using the Android SMS User Consent API.
///
/// Android only. Calling the API on any other platform returns
/// `SmsConsentUnsupported` instead of throwing.
///
/// Design: `doc/ARCHITECTURE.md`, public API: `doc/API.md`.
library;

export 'src/options.dart'
    show
        BackgroundPolicy,
        CancelOnBackground,
        ConflictPolicy,
        DeferUntilResumed,
        SmsConsentOptions;
export 'src/result.dart';
export 'src/session.dart'
    show
        SmsConsentEvent,
        SmsConsentSession,
        SmsConsentSessionState,
        maxSmsConsentTimeout;
export 'src/sms_consent.dart';
