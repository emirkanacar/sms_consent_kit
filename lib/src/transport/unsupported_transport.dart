import '../result.dart';
import 'messages.g.dart';
import 'transport.dart';

/// Used outside Android: every session ends with
/// `SmsConsentUnsupported(UnsupportedReason.platform)`.
final class UnsupportedTransport implements SmsConsentTransport {
  /// Creates the transport.
  const UnsupportedTransport();

  @override
  Stream<SmsConsentEventMessage> get events => const Stream.empty();

  @override
  Future<SmsConsentSupport> checkSupport() async =>
      const SmsConsentSupport.unsupported(UnsupportedReason.platform);

  @override
  Future<void> start(StartRequestMessage request) async =>
      throw const TransportException(unsupportedErrorCode, 'platform');

  @override
  Future<void> cancel(int sessionId) async {}

  @override
  Future<void> reset() async {}
}
