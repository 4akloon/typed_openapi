import 'dart:math';

import 'sse_cooldown.dart';

/// How an event stream reconnects after its connection ends (R12.5): the
/// `sse` field of `CallOptions`.
///
/// Reconnection is off unless the call or the operation turns it on. Before
/// each attempt the stream gets an `SseReconnecting` item; a reconnect sends
/// the last event id as `Last-Event-ID`. The first delay is the server's
/// `retry`, else [delay]; each further delay doubles up to [maxDelay] (a
/// server `retry` longer than [maxDelay] is kept as it is). After
/// [maxAttempts] attempts in a row without a message, the stream ends with
/// `SseDisconnected`; a null [maxAttempts] never gives up. [jitter] spreads
/// the delays and [cooldown] pauses for long after many failures. The server's
/// `retry` replaces [delay] as the first delay and, while it is in effect,
/// the delays are not spread; [cooldown] is not affected by it.
final class SseOptions {
  /// Creates the options of one call.
  const SseOptions({
    this.reconnect,
    this.delay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.maxAttempts = 5,
    this.jitter = 0,
    this.cooldown,
    this.random,
    this.wait,
  }) : assert(jitter >= 0 && jitter <= 1, 'jitter is a ratio from 0 to 1');

  /// Whether the stream reconnects; null keeps the operation's setting
  /// (see [SseReconnection]). `true` has no effect on an operation whose
  /// reconnection is [SseReconnection.off] (a POST that does not enable it,
  /// or an operation whose `sse.reconnect` override turns it off): repeating
  /// such a request may not be safe.
  final bool? reconnect;

  /// The first delay when the server sent no `retry`.
  final Duration delay;

  /// The longest delay a doubling reaches (before [jitter] is applied).
  final Duration maxDelay;

  /// How many attempts in a row may fail before the stream ends; a message
  /// on a new connection (an event, also one that does not decode or that
  /// the program drops) starts the count again. A connection that brings
  /// only comments, or blocks with just an `id:` or a `retry:` (they move
  /// the last event id and the delay, but are no message), does not. Null
  /// never gives up: the stream reconnects until the call is cancelled, the
  /// listener cancels or the server answers with a status that is not a
  /// stream.
  final int? maxAttempts;

  /// The share, from 0 to 1, by which each backoff delay is moved at random
  /// either way: 0.2 gives 80% to 120% of the delay. 0 (the default) adds no
  /// jitter. A delay that comes from the server's `retry` and a [cooldown]
  /// are not spread.
  final double jitter;

  /// A long pause after many failed attempts in a row, or null for none.
  /// The count of failed attempts then starts again, so [maxAttempts] counts
  /// the attempts of one cycle.
  final SseCooldown? cooldown;

  /// The source of [jitter]; a fresh `Random()` per stream when null. Tests
  /// pass a seeded one.
  final Random? random;

  /// Waits [delay] before an attempt; a timer that a cancel stops
  /// (`CancellableWait`) when null. Tests pass a function that does not
  /// sleep.
  final Future<void> Function(Duration delay)? wait;

  /// The delay before [attempt] (1 for the first), given the server's last
  /// [retry], without [jitter].
  Duration delayBefore(int attempt, Duration? retry) {
    final first = retry ?? delay;
    final cap = first > maxDelay ? first : maxDelay;
    var result = first;
    for (var i = 1; i < attempt && result < cap; i++) {
      result *= 2;
    }
    return result > cap ? cap : result;
  }
}

/// Whether an event-stream operation reconnects, as the generated method
/// says: by default a GET reconnects when the call asks for it, and an
/// operation that enables reconnection reconnects unless the call says no.
enum SseReconnection {
  /// Never: the operation is not GET and does not enable reconnection, or
  /// its override turns reconnection off.
  off,

  /// When [SseOptions.reconnect] is true.
  onRequest,

  /// Unless [SseOptions.reconnect] is false.
  on;

  /// Whether a call with [options] reconnects.
  bool reconnects(SseOptions options) => switch (this) {
    off => false,
    onRequest => options.reconnect ?? false,
    on => options.reconnect ?? true,
  };
}
