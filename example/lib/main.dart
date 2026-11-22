import 'package:material_ui/material_ui.dart';
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
    return const MaterialApp(title: 'sms_consent_kit', home: ConsentDemoPage());
  }
}

/// Starts a session and shows its events and result.
///
/// On an emulator, send an SMS from Extended controls → Phone after tapping
/// "Request code". Phase 3 adds code extraction and the widget layer.
class ConsentDemoPage extends StatefulWidget {
  /// Creates the demo page.
  const ConsentDemoPage({super.key});

  @override
  State<ConsentDemoPage> createState() => _ConsentDemoPageState();
}

class _ConsentDemoPageState extends State<ConsentDemoPage> {
  final List<String> _log = <String>[];
  SmsConsentSession? _session;

  @override
  void initState() {
    super.initState();
    SmsConsent.instance.checkSupport().then(
      (support) => _add('Support: $support'),
    );
  }

  void _add(String line) {
    if (mounted) setState(() => _log.insert(0, line));
  }

  void _request() {
    final session = SmsConsent.instance.start(
      timeout: const Duration(minutes: 2),
    );
    setState(() => _session = session);
    _add('Started session ${session.id}');
    session.events.listen((event) => _add('Event: ${event.name}'));
    session.result.then((result) {
      // Only for this demo: show the message. Never log SMS content in an
      // app (doc/SECURITY.md).
      final text = switch (result) {
        SmsConsentReceived(:final message) => 'Received: $message',
        _ => 'Result: $result',
      };
      _add(text);
      if (mounted) setState(() => _session = null);
    });
  }

  @override
  void dispose() {
    _session?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _session != null;
    return Scaffold(
      appBar: AppBar(title: const Text('sms_consent_kit')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                FilledButton(
                  onPressed: active ? null : _request,
                  child: const Text('Request code'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: active ? () => _session?.cancel() : null,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [for (final line in _log) Text(line)],
            ),
          ),
        ],
      ),
    );
  }
}
