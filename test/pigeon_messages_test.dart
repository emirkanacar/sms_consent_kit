import 'package:flutter_test/flutter_test.dart';
import 'package:sms_consent_kit/src/transport/messages.g.dart';

void main() {
  group('Pigeon messages', () {
    test('StartRequestMessage survives an encode/decode round trip', () {
      final request = StartRequestMessage(
        sessionId: 7,
        senderPhoneNumber: '+15550000000',
        timeoutMs: 120000,
        backgroundPolicy: BackgroundPolicyMessage.deferUntilResumed,
        deferMaxDelayMs: 30000,
      );

      final decoded = StartRequestMessage.decode(request.encode());

      expect(decoded.sessionId, 7);
      expect(decoded.senderPhoneNumber, '+15550000000');
      expect(decoded.timeoutMs, 120000);
      expect(
          decoded.backgroundPolicy, BackgroundPolicyMessage.deferUntilResumed);
      expect(decoded.deferMaxDelayMs, 30000);
    });

    test('SmsConsentEventMessage keeps optional fields null', () {
      final event = SmsConsentEventMessage(
        sessionId: 1,
        type: EventTypeMessage.timedOut,
      );

      final decoded = SmsConsentEventMessage.decode(event.encode());

      expect(decoded.type, EventTypeMessage.timedOut);
      expect(decoded.message, isNull);
      expect(decoded.errorCode, isNull);
    });
  });
}
