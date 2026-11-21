import 'package:material_ui/material_ui.dart';
// The public API is used from phases 2–3; for now this only verifies that the
// plugin compiles and registers.
// ignore: unused_import
import 'package:sms_consent_kit/sms_consent_kit.dart';

void main() {
  runApp(const ExampleApp());
}

/// Example app for sms_consent_kit.
class ExampleApp extends StatelessWidget {
  /// Creates the example app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'sms_consent_kit',
      home: Scaffold(
        appBar: AppBar(title: const Text('sms_consent_kit')),
        body: const Center(
          child: Text('Phase 0 skeleton. The OTP flow lands in phase 3.'),
        ),
      ),
    );
  }
}
