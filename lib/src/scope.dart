import 'package:flutter/widgets.dart';

import 'options.dart';
import 'otp_extractor.dart';
import 'result.dart';
import 'session.dart';
import 'sms_consent.dart';

/// Listens for the code while this widget is on screen (doc/API.md §6).
///
/// - Starts a session when mounted, or when its route becomes visible if it
///   was mounted under another route.
/// - Cancels it when disposed (`CancelReason.scopeDisposed`) and, with
///   [cancelWhenRouteHidden], when another route is pushed on top
///   (`CancelReason.routeHidden`). It does **not** restart on return
///   (EC-11); call [SmsConsentScopeState.restart], e.g. from "resend code".
/// - [onCode] and [onResult] are never called after dispose (EC-10).
///
/// ```dart
/// SmsConsentScope(
///   timeout: const Duration(minutes: 2),
///   onCode: (code) => otpController.text = code,
///   child: otpForm,
/// )
/// ```
///
/// Changes to [senderPhoneNumber], [extractor], [timeout] and [options]
/// apply from the next session.
class SmsConsentScope extends StatefulWidget {
  /// Creates a scope.
  const SmsConsentScope({
    super.key,
    required this.child,
    required this.onCode,
    this.onResult,
    this.senderPhoneNumber,
    this.extractor = const OtpExtractor.auto(),
    this.timeout = maxSmsConsentTimeout,
    this.options = const SmsConsentOptions(),
    this.cancelWhenRouteHidden = true,
    this.enabled = true,
  });

  /// The subtree, typically the OTP form.
  final Widget child;

  /// Called with the extracted code. Not called if the extractor found no
  /// code; [onResult] still gets the message then.
  final ValueChanged<String> onCode;

  /// Called with every result of this scope's current session, after
  /// [onCode]. Results of sessions replaced by [SmsConsentScopeState.restart]
  /// are not reported.
  final ValueChanged<SmsConsentResult>? onResult;

  /// Only accept SMS from this phone number; `null` for any sender (EC-21).
  final String? senderPhoneNumber;

  /// Finds the code in the message.
  final OtpExtractor extractor;

  /// Listening time, at most 5 minutes (EC-27).
  final Duration timeout;

  /// Conflict and background policies.
  final SmsConsentOptions options;

  /// Whether to cancel when another route covers this one. Dialogs and
  /// bottom sheets count too.
  final bool cancelWhenRouteHidden;

  /// `false` cancels the session; `true` again starts a new one.
  final bool enabled;

  /// The nearest scope. Throws if there is none.
  static SmsConsentScopeState of(BuildContext context) {
    final state = maybeOf(context);
    assert(state != null, 'No SmsConsentScope above this context.');
    return state!;
  }

  /// The nearest scope, or `null`.
  static SmsConsentScopeState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<SmsConsentScopeState>();

  @override
  State<SmsConsentScope> createState() => SmsConsentScopeState();
}

/// State of [SmsConsentScope]; reach it with [SmsConsentScope.of].
class SmsConsentScopeState extends State<SmsConsentScope> {
  SmsConsentSession? _session;

  /// A start is due as soon as the scope is enabled and visible.
  bool _startPending = true;
  bool _routeVisible = true;
  bool _routeLeaving = false;

  /// The current session, if it has not completed.
  SmsConsentSession? get session => _session;

  /// Ends the current session and starts a new one, e.g. after "resend
  /// code" (EC-22). The old session's result is not reported.
  ///
  /// No-op while disabled. While the route is hidden, the start waits until
  /// it is visible again.
  void restart() {
    if (!widget.enabled) return;
    _stop(CancelReason.replaced, report: false);
    _startPending = true;
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    _routeVisible = route?.isCurrent ?? true;
    _routeLeaving = route != null && !route.isActive;
    _sync();
  }

  @override
  void didUpdateWidget(SmsConsentScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) _startPending = true;
    _sync();
  }

  @override
  void dispose() {
    _stop(CancelReason.scopeDisposed);
    super.dispose();
  }

  void _sync() {
    if (!widget.enabled) {
      _stop(CancelReason.manual);
      _startPending = false;
    } else if (widget.cancelWhenRouteHidden && !_routeVisible) {
      // A popped route is on its way out, not hidden.
      _stop(_routeLeaving
          ? CancelReason.scopeDisposed
          : CancelReason.routeHidden);
    } else if (_startPending) {
      _startPending = false;
      _start();
    }
  }

  void _start() {
    final session = SmsConsent.instance.start(
      senderPhoneNumber: widget.senderPhoneNumber,
      timeout: widget.timeout,
      extractor: widget.extractor,
      options: widget.options,
    );
    _session = session;
    session.result.then((result) {
      if (!mounted || !identical(_session, session)) return;
      _session = null;
      if (result case SmsConsentReceived(:final code?)) widget.onCode(code);
      widget.onResult?.call(result);
    });
  }

  /// Cancels the current session. Its result is still reported unless
  /// [report] is false or the scope is disposed by then.
  void _stop(CancelReason reason, {bool report = true}) {
    final session = _session;
    if (session == null) return;
    if (!report) _session = null;
    cancelSession(session, reason);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
