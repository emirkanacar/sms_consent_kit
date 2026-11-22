import 'package:flutter_test/flutter_test.dart';
import 'package:sms_consent_kit/sms_consent_kit.dart';

typedef _Case = (String message, String? code);

void _table(OtpExtractor extractor, List<_Case> cases) {
  for (final (message, code) in cases) {
    test('"$message" → $code', () {
      expect(extractor.extract(message), code);
    });
  }
}

void main() {
  group('auto', () {
    _table(const OtpExtractor.auto(), [
      ('Your code is 482913', '482913'),
      ('482913 is your verification code.', '482913'),
      ('G-482913 is your Google verification code.', '482913'),
      ('Use 4829 to sign in', '4829'),
      ('Your passcode: 1234. Order 5678', '1234'),
      // EC-23: amounts, dates, times, phone numbers.
      (r'You paid $1,250.00. Your code: 7731', '7731'),
      ('You paid 1250 TL. Code 553311', '553311'),
      ('Rs.5000 debited. OTP 112233', '112233'),
      ('2000€ sent. Code 3344', '3344'),
      ('Transfer of 2000 USD. Code 4433', '4433'),
      ('12/11/2026 işlem için 9876', '9876'),
      ('Valid until 12:30. 665544 is your code', '665544'),
      ('Call +15551234567 if this was not you. Code 4455', '4455'),
      ('Call 555-0100 if not you: 8080', '8080'),
      ('Ref ABC12345, code 7788', '7788'),
      ('Order #99887766 shipped, pin 1212', '1212'),
      // Closest to a keyword; on a tie the earlier one.
      ('Order 99887766 shipped. Your OTP is 1234', '1234'),
      ('code 1111 2222', '1111'),
      // Keywords match at word starts only ("shipping" has no "pin").
      ('shipping 5555, then pin 6666', '6666'),
      // Non-ASCII digits come back as ASCII.
      ('رمز التحقق: ٤٨٢٩١٣', '482913'),
      ('کد شما ۱۲۳۴۵۶', '123456'),
      ('コード １２３４', '1234'),
      // Nothing usable.
      ('No numbers here', null),
      ('Your code is 123', null),
      ('Code 1234567890', null),
      ('You paid 1250 TL', null),
      ('', null),
    ]);
  });

  group('digits', () {
    _table(const OtpExtractor.digits(length: 6), [
      ('Code 1234 or 123456', '123456'),
      ('Code 1234', null),
      ('Order 654321, your code is 123456', '123456'),
    ]);
  });

  group('regex', () {
    _table(const OtpExtractor.regex(r'([A-Z0-9]{3}-[A-Z0-9]{3})', group: 1), [
      ('Your code is AB1-2C3', 'AB1-2C3'),
      ('Your code is 482913', null),
    ]);
    _table(const OtpExtractor.regex(r'code (\d+)', group: 5), [
      ('code 1234', null),
    ]);
    _table(const OtpExtractor.regex(r'\d{4}'), [
      ('pin 9876', '9876'),
    ]);
  });

  group('keyword', () {
    _table(const OtpExtractor.keyword(keywords: ['kod', 'şifre']), [
      ('Doğrulama kodunuz: 482913', '482913'),
      ('KOD 1234', '1234'),
      ('Şifre: 9988. Tutar 1500 TL', '9988'),
      ('Tutar 1500, işlem 4455', null),
      ('Kodunuz hazır', null),
    ]);
    _table(const OtpExtractor.keyword(minLength: 6, maxLength: 6), [
      ('Your code: 1234 / 654321', '654321'),
      ('Use 654321', null),
    ]);
  });

  test('custom extractors', () {
    expect(const _Fixed().extract('anything'), 'fixed');
  });
}

final class _Fixed extends OtpExtractor {
  const _Fixed();

  @override
  String? extract(String message) => 'fixed';
}
