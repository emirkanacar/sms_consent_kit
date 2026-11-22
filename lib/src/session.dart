import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'options.dart';
import 'result.dart';
import 'transport/messages.g.dart';
import 'transport/transport.dart';

/// Where a session is in its lifecycle (doc/ARCHITECTURE.md §3).
enum SmsConsentSessionState {
  /// Waiting for a matching SMS.
  listening,

  /// The SMS arrived while the app was in the background; the consent sheet
  /// will be shown when the app returns (EC-03).
  deferred,

  /// The consent sheet is on screen; the user decides. Timeouts are paused
  /// (EC-25).
  awaitingUser,

  /// A result has been produced.
  completed,
}

/// Intermediate session events, for UI feedback. Optional to observe.
enum SmsConsentEvent {
  /// The SMS arrived in the background; the sheet is waiting for the app.
  consentDeferred,

  /// The consent sheet is on screen.
  consentShown,
}

/// Longest listening time Play Services supports (EC-27).
const Duration maxSmsConsentTimeout = Duration(minutes: 5);

/// One listening session, from `start` to its single result.
final class SmsConsentSession {
  SmsConsentSession._(this.id, this._manager);

  /// Unique within this isolate.
  final int id;
  final SessionManager _manager;

  final Completer<SmsConsentResult> _result = Completer<SmsConsentResult>();
  final StreamController<SmsConsentEvent> _events =
      StreamController<SmsConsentEvent>.broadcast();
  SmsConsentSessionState _state = SmsConsentSessionState.listening;
  Timer? _watchdog;

  /// Current state.
  SmsConsentSessionState get state => _state;

  /// Whether the session has not produced a result yet.
  bool get isActive => _state != SmsConsentSessionState.completed;

  /// The single result. Always completes and never throws: every error
  /// arrives as [SmsConsentFailed].
  Future<SmsConsentResult> get result => _result.future;

  /// Intermediate events; closes when the session completes.
  Stream<SmsConsentEvent> get events => _events.stream;

  /// Ends the session with `SmsConsentCancelled(CancelReason.manual)`.
  /// No-op if it has already completed.
  ///
  /// A consent sheet that is already on screen cannot be closed by the app;
  /// its result is dropped.
  Future<void> cancel() => _manager.cancel(this, CancelReason.manual);

  void _setState(SmsConsentSessionState state, SmsConsentEvent event) {
    _state = state;
    if (!_events.isClosed) _events.add(event);
  }

  /// Returns false if the session had already completed.
  bool _complete(SmsConsentResult result) {
    if (!isActive) return false;
    _state = SmsConsentSessionState.completed;
    _watchdog?.cancel();
    _watchdog = null;
    _result.complete(result);
    unawaited(_events.close());
    return true;
  }

  @override
  String toString() => 'SmsConsentSession($id, ${_state.name})';
}

/// Owns the single active session of this isolate and keeps the native side
/// in sync with it (doc/ARCHITECTURE.md §3).
///
/// Dart resolves a session locally first (cancel, replace, watchdog) and then
/// tells the native side, which ends it without an event. Events that do not
/// belong to the active session are ignored.
final class SessionManager {
  /// Creates a manager and clears native sessions left over from a previous
  /// isolate (hot restart, EC-06).
  SessionManager(
    this._transport, {
    this.watchdogGrace = const Duration(seconds: 5),
    @visibleForTesting int? firstSessionId,
  }) : _nextId = firstSessionId ?? _randomSessionId() {
    _subscription = _transport.events.listen(_onEvent);
    _ready = _transport.reset().catchError((Object _) {});
  }

  /// How long after the native timeout the watchdog fails a session whose
  /// result never arrived (EC-26).
  final Duration watchdogGrace;

  final SmsConsentTransport _transport;
  late final StreamSubscription<SmsConsentEventMessage> _subscription;
  late final Future<void> _ready;
  int _nextId;
  SmsConsentSession? _active;

  /// The session that has not completed yet, if any.
  SmsConsentSession? get activeSession => _active;

  /// Whether the device supports the API. Never throws: if the plugin
  /// cannot be reached, reports `playServicesUnavailable`.
  Future<SmsConsentSupport> checkSupport() async {
    try {
      return await _transport.checkSupport();
    } on TransportException catch (e) {
      return SmsConsentSupport.unsupported(
        e.code == unsupportedErrorCode
            ? unsupportedReasonOf(e.message)
            : UnsupportedReason.playServicesUnavailable,
      );
    }
  }

  /// Starts a session. Never throws for runtime conditions; argument errors
  /// are reported by asserts in debug builds.
  SmsConsentSession start({
    String? senderPhoneNumber,
    Duration timeout = maxSmsConsentTimeout,
    SmsConsentOptions options = const SmsConsentOptions(),
  }) {
    assert(timeout > Duration.zero, 'timeout must be positive.');
    assert(
      timeout <= maxSmsConsentTimeout,
      'Play Services listens for at most 5 minutes; timeout is clamped.',
    );
    assert(
      senderPhoneNumber == null || _phoneNumber.hasMatch(senderPhoneNumber),
      'senderPhoneNumber must be a phone number. Pass null for alphanumeric '
      'sender IDs such as "MYBANK" (EC-21).',
    );

    final session = SmsConsentSession._(_nextId++, this);

    final previous = _active;
    if (previous != null) {
      if (options.conflictPolicy == ConflictPolicy.reject) {
        session._complete(const SmsConsentFailed(
          SmsConsentError(SmsConsentErrorCode.sessionAlreadyActive),
        ));
        return session;
      }
      _end(previous, const SmsConsentCancelled(CancelReason.replaced));
    }
    _active = session;

    final clamped = _clamp(timeout);
    session._watchdog = Timer(clamped + watchdogGrace, () {
      _end(
        session,
        const SmsConsentFailed(SmsConsentError(
          SmsConsentErrorCode.internal,
          'No result from the native side (watchdog).',
        )),
      );
    });

    final policy = options.backgroundPolicy;
    unawaited(_begin(
      session,
      StartRequestMessage(
        sessionId: session.id,
        senderPhoneNumber: senderPhoneNumber,
        timeoutMs: clamped.inMilliseconds,
        backgroundPolicy: switch (policy) {
          DeferUntilResumed() => BackgroundPolicyMessage.deferUntilResumed,
          CancelOnBackground() => BackgroundPolicyMessage.cancelOnBackground,
        },
        deferMaxDelayMs: switch (policy) {
          DeferUntilResumed(:final maxDelay) => _clamp(maxDelay).inMilliseconds,
          CancelOnBackground() => 0,
        },
      ),
    ));
    return session;
  }

  /// Cancels [session] (or the active one) with [reason].
  Future<void> cancel(SmsConsentSession? session, CancelReason reason) async {
    final target = session ?? _active;
    if (target == null || target != _active) return;
    _end(target, SmsConsentCancelled(reason));
  }

  /// Stops listening for native events. Active sessions are cancelled.
  @visibleForTesting
  Future<void> dispose() async {
    final active = _active;
    if (active != null) {
      _end(active, const SmsConsentCancelled(CancelReason.manual));
    }
    await _subscription.cancel();
  }

  Future<void> _begin(
      SmsConsentSession session, StartRequestMessage request) async {
    await _ready;
    // Cancelled while waiting: never start native listening for it.
    if (!session.isActive) return;
    try {
      await _transport.start(request);
    } on TransportException catch (e) {
      _end(session, _resultOf(e), notifyNative: false);
      return;
    } catch (e) {
      _end(
        session,
        SmsConsentFailed(SmsConsentError(SmsConsentErrorCode.internal, '$e')),
        notifyNative: false,
      );
      return;
    }
    // Resolved locally while the start was in flight. The native side drops
    // cancels that overtake their start, but repeat it in case one was lost.
    if (!session.isActive) unawaited(_cancelNative(session.id));
  }

  void _onEvent(SmsConsentEventMessage event) {
    final session = _active;
    // Stale: from a replaced, cancelled or pre-restart session.
    if (session == null || session.id != event.sessionId) return;

    switch (event.type) {
      case EventTypeMessage.consentDeferred:
        session._setState(
            SmsConsentSessionState.deferred, SmsConsentEvent.consentDeferred);
      case EventTypeMessage.consentShown:
        // EC-25: the native timeouts stop too; the user decides.
        session._watchdog?.cancel();
        session._watchdog = null;
        session._setState(
            SmsConsentSessionState.awaitingUser, SmsConsentEvent.consentShown);
      case EventTypeMessage.received:
        final message = event.message;
        _end(
          session,
          message == null
              ? const SmsConsentFailed(SmsConsentError(
                  SmsConsentErrorCode.internal, 'Received without a message.'))
              : SmsConsentReceived(message),
          notifyNative: false,
        );
      case EventTypeMessage.denied:
        _end(session, const SmsConsentDenied(), notifyNative: false);
      case EventTypeMessage.timedOut:
        _end(session, const SmsConsentTimedOut(), notifyNative: false);
      case EventTypeMessage.cancelled:
        // The native side only cancels on its own for the background policy
        // or a lost Activity.
        _end(session, const SmsConsentCancelled(CancelReason.backgrounded),
            notifyNative: false);
      case EventTypeMessage.failed:
        _end(
          session,
          SmsConsentFailed(
              SmsConsentError(SmsConsentErrorCode.fromWire(event.errorCode))),
          notifyNative: false,
        );
    }
  }

  /// Completes [session] and, unless the native side ended it itself, tells
  /// the native side to stop.
  void _end(
    SmsConsentSession session,
    SmsConsentResult result, {
    bool notifyNative = true,
  }) {
    if (identical(_active, session)) _active = null;
    if (session._complete(result) && notifyNative) {
      unawaited(_cancelNative(session.id));
    }
  }

  Future<void> _cancelNative(int sessionId) async {
    try {
      await _transport.cancel(sessionId);
    } catch (_) {
      // Nothing to do: the native side also ends sessions on its own timeout.
    }
  }

  static SmsConsentResult _resultOf(TransportException e) {
    if (e.code == unsupportedErrorCode) {
      return SmsConsentUnsupported(unsupportedReasonOf(e.message));
    }
    return SmsConsentFailed(
      SmsConsentError(SmsConsentErrorCode.fromWire(e.code), e.message),
    );
  }

  static Duration _clamp(Duration value) {
    if (value < Duration.zero) return Duration.zero;
    if (value > maxSmsConsentTimeout) return maxSmsConsentTimeout;
    return value;
  }

  /// Random start, so ids of a previous isolate (hot restart) never collide
  /// with new ones while their events are still in flight.
  static int _randomSessionId() => Random().nextInt(1 << 30) + 1;

  static final RegExp _phoneNumber = RegExp(r'^\+?[0-9][0-9 ()\-]{2,19}$');
}
