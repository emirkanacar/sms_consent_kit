/// Session-based, lifecycle-aware and secure one-time code (OTP) autofill
/// using the Android SMS User Consent API.
///
/// Android only. Calling the API on any other platform returns
/// `SmsConsentUnsupported` instead of throwing.
///
/// Design: `doc/ARCHITECTURE.md`, public API: `doc/API.md`.
///
/// Phase 0: skeleton. The public API lands in phases 2–3.
library;
