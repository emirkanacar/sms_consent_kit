import 'package:flutter_test/flutter_test.dart';
import 'package:sms_consent_kit/sms_consent_kit.dart';

void main() {
  test('Received.toString masks the SMS content (EC-28)', () {
    const result = SmsConsentReceived('Your code is 482913');
    expect(result.toString(), isNot(contains('482913')));
    expect(result.toString(), contains('19 chars'));
  });

  test('error codes map from the wire, unknown ones to internal', () {
    expect(SmsConsentErrorCode.fromWire('launchFailed'),
        SmsConsentErrorCode.launchFailed);
    expect(SmsConsentErrorCode.fromWire('nope'), SmsConsentErrorCode.internal);
    expect(SmsConsentErrorCode.fromWire(null), SmsConsentErrorCode.internal);
  });

  test('results switch exhaustively', () {
    String describe(SmsConsentResult result) => switch (result) {
          SmsConsentReceived() => 'received',
          SmsConsentDenied() => 'denied',
          SmsConsentTimedOut() => 'timedOut',
          SmsConsentCancelled(:final reason) => 'cancelled:${reason.name}',
          SmsConsentUnsupported(:final reason) => 'unsupported:${reason.name}',
          SmsConsentFailed(:final error) => 'failed:${error.code.name}',
        };
    expect(describe(const SmsConsentCancelled(CancelReason.replaced)),
        'cancelled:replaced');
  });

  test('default options', () {
    const options = SmsConsentOptions();
    expect(options.conflictPolicy, ConflictPolicy.replace);
    expect(
        options.backgroundPolicy,
        const BackgroundPolicy.deferUntilResumed(
            maxDelay: Duration(seconds: 30)));
  });
}
