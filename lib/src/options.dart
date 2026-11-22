import 'package:flutter/foundation.dart';

/// What happens when a session starts while another one is active (EC-09).
enum ConflictPolicy {
  /// The old session ends with `SmsConsentCancelled(CancelReason.replaced)`
  /// and the new one starts.
  replace,

  /// The new session immediately ends with
  /// `SmsConsentFailed(SmsConsentErrorCode.sessionAlreadyActive)`; the old one
  /// keeps running.
  reject,
}

/// What happens when the SMS arrives while the app is in the background
/// (EC-03). Android does not allow showing the consent sheet from the
/// background.
@immutable
sealed class BackgroundPolicy {
  const BackgroundPolicy();

  /// Keeps the consent sheet and shows it when the app returns to the
  /// foreground within [maxDelay]; otherwise the session ends with
  /// `SmsConsentTimedOut`.
  ///
  /// The default, because users often switch to their SMS app and back.
  const factory BackgroundPolicy.deferUntilResumed({
    required Duration maxDelay,
  }) = DeferUntilResumed;

  /// Ends the session with `SmsConsentCancelled(CancelReason.backgrounded)`
  /// as soon as the app goes to the background.
  const factory BackgroundPolicy.cancelOnBackground() = CancelOnBackground;
}

/// See [BackgroundPolicy.deferUntilResumed].
final class DeferUntilResumed extends BackgroundPolicy {
  /// Creates the policy.
  const DeferUntilResumed({required this.maxDelay});

  /// How long a deferred consent sheet stays valid.
  final Duration maxDelay;

  @override
  bool operator ==(Object other) =>
      other is DeferUntilResumed && other.maxDelay == maxDelay;

  @override
  int get hashCode => Object.hash(DeferUntilResumed, maxDelay);

  @override
  String toString() => 'BackgroundPolicy.deferUntilResumed($maxDelay)';
}

/// See [BackgroundPolicy.cancelOnBackground].
final class CancelOnBackground extends BackgroundPolicy {
  /// Creates the policy.
  const CancelOnBackground();

  @override
  bool operator ==(Object other) => other is CancelOnBackground;

  @override
  int get hashCode => (CancelOnBackground).hashCode;

  @override
  String toString() => 'BackgroundPolicy.cancelOnBackground()';
}

/// Session behavior that is rarely changed.
@immutable
final class SmsConsentOptions {
  /// Creates options; the defaults suit most apps.
  const SmsConsentOptions({
    this.conflictPolicy = ConflictPolicy.replace,
    this.backgroundPolicy = const BackgroundPolicy.deferUntilResumed(
      maxDelay: Duration(seconds: 30),
    ),
  });

  /// What happens when a session is already active.
  final ConflictPolicy conflictPolicy;

  /// What happens when the SMS arrives while the app is in the background.
  final BackgroundPolicy backgroundPolicy;

  @override
  bool operator ==(Object other) =>
      other is SmsConsentOptions &&
      other.conflictPolicy == conflictPolicy &&
      other.backgroundPolicy == backgroundPolicy;

  @override
  int get hashCode => Object.hash(conflictPolicy, backgroundPolicy);
}
