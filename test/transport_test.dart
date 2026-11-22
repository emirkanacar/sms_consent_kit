import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sms_consent_kit/sms_consent_kit.dart';
import 'package:sms_consent_kit/src/transport/messages.g.dart';
import 'package:sms_consent_kit/src/transport/pigeon_transport.dart';
import 'package:sms_consent_kit/src/transport/transport.dart';
import 'package:sms_consent_kit/src/transport/unsupported_transport.dart';

const _prefix = 'dev.flutter.pigeon.sms_consent_kit.SmsConsentHostApi';
const _codec = SmsConsentHostApi.pigeonChannelCodec;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Answers [method] with [reply] (a Pigeon response list).
  void mockHost(String method, List<Object?> Function(Object? args) reply) {
    messenger.setMockMessageHandler('$_prefix.$method', (data) async {
      return _codec.encodeMessage(reply(_codec.decodeMessage(data)));
    });
  }

  tearDown(() {
    for (final method in ['checkSupport', 'start', 'cancel', 'reset']) {
      messenger.setMockMessageHandler('$_prefix.$method', null);
    }
  });

  group('PigeonTransport', () {
    test('maps support status', () async {
      mockHost(
          'checkSupport', (_) => [SupportStatusMessage.playServicesOutdated]);
      final transport = PigeonTransport();
      addTearDown(transport.dispose);

      expect(
          await transport.checkSupport(),
          const SmsConsentSupport.unsupported(
              UnsupportedReason.playServicesOutdated));
    });

    test('sends the start request and maps native errors', () async {
      StartRequestMessage? sent;
      mockHost('start', (args) {
        sent = (args! as List<Object?>).single! as StartRequestMessage;
        return ['startFailed', 'ApiException', null];
      });
      final transport = PigeonTransport();
      addTearDown(transport.dispose);

      await expectLater(
        transport.start(StartRequestMessage(
          sessionId: 3,
          timeoutMs: 1000,
          backgroundPolicy: BackgroundPolicyMessage.deferUntilResumed,
          deferMaxDelayMs: 0,
        )),
        throwsA(isA<TransportException>()
            .having((e) => e.code, 'code', 'startFailed')
            .having((e) => e.message, 'message', 'ApiException')),
      );
      expect(sent?.sessionId, 3);
    });

    test('a missing plugin becomes a TransportException', () async {
      final transport = PigeonTransport();
      addTearDown(transport.dispose);

      await expectLater(
          transport.reset(),
          throwsA(isA<TransportException>()
              .having((e) => e.code, 'code', 'channel-error')));
    });

    test('delivers native events', () async {
      final transport = PigeonTransport();
      addTearDown(transport.dispose);
      final events = <SmsConsentEventMessage>[];
      transport.events.listen(events.add);

      final eventCodec = SmsConsentFlutterApi.pigeonChannelCodec;
      await messenger.handlePlatformMessage(
        'dev.flutter.pigeon.sms_consent_kit.SmsConsentFlutterApi.onEvent',
        eventCodec.encodeMessage(<Object?>[
          SmsConsentEventMessage(
              sessionId: 9, type: EventTypeMessage.consentShown),
        ]),
        (_) {},
      );
      await pumpEventQueue();

      expect(events.single.sessionId, 9);
      expect(events.single.type, EventTypeMessage.consentShown);
    });
  });

  group('UnsupportedTransport (EC-13)', () {
    test('sessions end with Unsupported(platform)', () async {
      final consent = SmsConsent.withTransport(const UnsupportedTransport());
      expect(await consent.requestCode(),
          const SmsConsentUnsupported(UnsupportedReason.platform));
      expect(await consent.checkSupport(),
          const SmsConsentSupport.unsupported(UnsupportedReason.platform));
    });

    test('is selected outside Android', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(defaultTransport(), isA<UnsupportedTransport>());
    });
  });
}
