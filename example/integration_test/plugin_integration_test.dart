import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sms_consent_kit_example/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // The real end-to-end flow (SMS sent from the emulator) lands in phase 2.
  testWidgets('app starts with the plugin registered', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('sms_consent_kit'), findsOneWidget);
  });
}
