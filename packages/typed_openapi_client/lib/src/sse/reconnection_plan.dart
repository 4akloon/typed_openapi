import 'dart:math';

import '../result/result.dart';
import 'retry_after.dart';
import 'sse_settings.dart';

/// One reconnection attempt the plan allows: its number and the wait before
/// it.
typedef ReconnectionStep = ({int attempt, Duration delay});

/// Decides, for one stream, how long to wait before each reconnection
/// attempt and when to give up: it counts the failed attempts in a row,
/// applies the backoff, the jitter and the cooldown of [SseSettings].
final class ReconnectionPlan {
  /// Creates the plan of one stream.
  ReconnectionPlan(this._options) : _random = _options.random ?? Random();

  final SseSettings _options;
  final Random _random;
  int _failed = 0;

  /// Starts the count of failed attempts again: the connection delivered a
  /// message.
  void reset() => _failed = 0;

  /// The next attempt, given the server's last [retry], or null when
  /// [SseSettings.maxAttempts] attempts in a row have failed.
  ///
  /// When the [failure] that ends the last attempt carries a valid
  /// `Retry-After`, the delay is at least that long, whatever `maxDelay`
  /// says, for this attempt only.
  ReconnectionStep? next(
    Duration? retry, {
    Failure<Object?, Object?>? failure,
  }) {
    final limit = _options.maxAttempts;
    if (limit != null && _failed >= limit) return null;
    final asked = failure == null ? null : RetryAfter.of(failure);
    if (_options.cooldown case final cooldown? when _failed >= cooldown.after) {
      final step = (
        attempt: _failed + 1,
        delay: _atLeast(cooldown.duration, asked),
      );
      _failed = 0;
      return step;
    }
    _failed++;
    final base = _options.delayBefore(_failed, retry);
    // The server asked for that timing: it is not spread.
    return (
      attempt: _failed,
      delay: _atLeast(retry == null ? _spread(base) : base, asked),
    );
  }

  static Duration _atLeast(Duration delay, Duration? asked) =>
      asked != null && asked > delay ? asked : delay;

  /// [base] moved by a random share of at most [SseSettings.jitter] either
  /// way.
  Duration _spread(Duration base) {
    // The constructor asserts the range; a release build must not give a
    // negative Duration for a value outside it.
    final jitter = _options.jitter.clamp(0.0, 1.0);
    if (jitter == 0) return base;
    final factor = 1 + (_random.nextDouble() * 2 - 1) * jitter;
    return Duration(microseconds: (base.inMicroseconds * factor).round());
  }
}
