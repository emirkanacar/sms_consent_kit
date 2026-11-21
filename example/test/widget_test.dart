import 'package:flutter_test/flutter_test.dart';
import 'package:sms_consent_kit_example/main.dart';

void main() {
  testWidgets('example app starts', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('sms_consent_kit'), findsOneWidget);
  });
}
