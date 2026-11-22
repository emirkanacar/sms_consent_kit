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

/// Starts a session by hand and shows its events and result.
///
/// On an emulator, send an SMS from Extended controls → Phone after tapping
/// "Request code".
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
        SmsConsentReceived(:final code, :final message) =>
          'Received: code=$code, message=$message',
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
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const OtpPage()),
                  ),
                  child: const Text('OTP page'),
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

/// The recommended setup: [SmsConsentScope] around an OTP form.
///
/// Listening stops when you leave this page or push another one on top
/// (manual test M-01); "Resend code" starts a new session.
class OtpPage extends StatefulWidget {
  /// Creates the OTP page.
  const OtpPage({super.key});

  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> {
  final TextEditingController _otp = TextEditingController();
  String _status = 'Listening…';

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enter the code')),
      body: SmsConsentScope(
        timeout: const Duration(minutes: 2),
        onCode: (code) => _otp.text = code,
        onResult: (result) => setState(() => _status = '$result'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _otp,
                autofillHints: const [AutofillHints.oneTimeCode],
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Code'),
              ),
              const SizedBox(height: 12),
              Text(_status),
              Builder(
                builder: (context) => TextButton(
                  onPressed: () {
                    setState(() => _status = 'Listening…');
                    SmsConsentScope.of(context).restart();
                  },
                  child: const Text('Resend code'),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Help')),
                      body: const Center(
                        child: Text('Listening stopped while this is open.'),
                      ),
                    ),
                  ),
                ),
                child: const Text('Open help (covers the page)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
