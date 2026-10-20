import 'dart:math';

import 'package:meta/meta.dart';

import '../result/result.dart';
import 'sse_cooldown.dart';
import 'sse_trace.dart';

/// How an event stream reconnects after its connection ends (R12.5), and how
/// its opening is retried: the `sse` field of `CallOptions`.
///
/// Every field is optional: null leaves it unset, and the built-in default
/// applies once the options of the client and of the call are merged
/// ([merge]). Reconnection is off unless the call or the operation turns it
/// on. Before each attempt the stream gets an `SseReconnecting` item; a
/// reconnect sends the last event id as `Last-Event-ID`. The first delay is
/// the server's `retry`, else [delay]; each further delay doubles up to
/// [maxDelay] (a server `retry` longer than [maxDelay] is kept as it is).
/// After [maxAttempts] attempts in a row without a message, the stream ends
/// with `SseDisconnected`; a null [maxAttempts] never gives up. [jitter]
/// spreads the delays and [cooldown] pauses for long after many failures. A
/// failed reconnection is retried when it is transient (`SseRetry`, or
/// `retryWhen`), and a `Retry-After` of its response lengthens the wait.
/// The server's `retry` replaces [delay] as the first delay and, while it is
/// in effect, the delays are not spread; [cooldown] is not affected by it.
final class SseOptions {
  /// Creates the options of one call or of a client's defaults.
  ///
  /// An omitted [maxAttempts] is unset, a written `null` is "never give up";
  /// a negative number counts as omitted.
  const SseOptions({
    this.reconnect,
    this.delay,
    this.maxDelay,
    int? maxAttempts = _omitted,
    this.idleTimeout,
    this.handshakeTimeout,
    this.jitter,
    this.cooldown,
    this.random,
    this.onTrace,
    this.wait,
    this.retryOpen,
    this.retryWhen,
  }) : maxAttempts = maxAttempts != null && maxAttempts < 0
           ? null
           : maxAttempts,
       _hasMaxAttempts = maxAttempts == null || maxAttempts >= 0,
       assert(
         jitter == null || (jitter >= 0 && jitter <= 1),
         'jitter is a ratio from 0 to 1',
       );

  /// The value of an omitted [maxAttempts]; any negative number is no
  /// attempt count and counts as omitted.
  static const int _omitted = -1;

  /// Whether the stream reconnects; null keeps the operation's setting
  /// (see [SseReconnection]). `true` has no effect on an operation whose
  /// reconnection is [SseReconnection.off] (a POST that does not enable it,
  /// or an operation whose `sse.reconnect` override turns it off): repeating
  /// such a request may not be safe.
  final bool? reconnect;

  /// The first delay when the server sent no `retry`; null leaves it unset
  /// (1 second).
  final Duration? delay;

  /// The longest delay a doubling reaches (before [jitter] is applied); null
  /// leaves it unset (30 seconds).
  final Duration? maxDelay;

  /// How many attempts in a row may fail before the stream ends; a message
  /// on a new connection (an event, also one that does not decode or that
  /// the program drops) starts the count again. A connection that brings
  /// only comments, or blocks with just an `id:` or a `retry:` (they move
  /// the last event id and the delay, but are no message), does not. A
  /// written `null` never gives up: the stream reconnects until the call is
  /// cancelled, the listener cancels or an attempt fails in a way that
  /// retrying cannot fix (`SseRetry`, or `retryWhen`). Omitted leaves it
  /// unset (5). This field reads null both when it was omitted and when
  /// `null` was written; [merge] keeps the difference. A negative number
  /// counts as omitted.
  final int? maxAttempts;

  final bool _hasMaxAttempts;

  /// The longest silence on a connected stream, or null (unset) for no
  /// limit; [Duration.zero] switches a default off. Any received bytes reset
  /// it: events, but also comments and heartbeats such as `: ping`. When it
  /// runs out the connection is dead (a half-open socket): the request is
  /// cancelled and the stream reconnects when reconnection is on, with a
  /// `TransportException` of kind timeout as the cause of `SseReconnecting`,
  /// else it ends with `SseDisconnected` and that cause. Choose a value
  /// above the server's heartbeat interval. Not counted while the listener
  /// is paused.
  final Duration? idleTimeout;

  /// The longest wait for the response headers of each attempt (the first
  /// and every reconnection), or null (unset) for no limit; [Duration.zero]
  /// switches a default off. The request is cancelled when it runs out and
  /// the attempt fails with a `TransportException` of kind timeout: a failed
  /// first attempt is a `TransportError`, a failed reconnection is retried
  /// like any other.
  final Duration? handshakeTimeout;

  /// The share, from 0 to 1, by which each backoff delay is moved at random
  /// either way: 0.2 gives 80% to 120% of the delay. Null leaves it unset
  /// (0, no jitter); 0 switches a default off. A delay that comes from the
  /// server's `retry` and a [cooldown] are not spread.
  final double? jitter;

  /// A long pause after many failed attempts in a row, or null (unset) for
  /// none; [SseCooldown.none] switches a default off. The count of failed
  /// attempts then starts again, so [maxAttempts] counts the attempts of one
  /// cycle: a [maxAttempts] larger than `cooldown.after` is inert, the
  /// stream never ends because the cooldown resets the count.
  final SseCooldown? cooldown;

  /// The source of [jitter]; a fresh `Random()` per stream when null. Tests
  /// pass a seeded one.
  final Random? random;

  /// Called with a small [SseTrace] for each step of the stream: connect,
  /// open, event, heartbeat, error, reconnecting and closed, all with the
  /// stream's correlation id. For a debug panel or a log; it never changes
  /// the items the stream emits. It runs synchronously, so keep it short. An
  /// [Exception] it throws is ignored; an [Error] is a bug of the program
  /// and is not caught.
  final void Function(SseTrace trace)? onTrace;

  /// Waits the given delay before an attempt; a timer that a cancel stops
  /// (`CancellableWait`) when null. Tests pass a function that does not
  /// sleep.
  final Future<void> Function(Duration delay)? wait;

  /// Whether a failure to open the stream is retried; null leaves it unset
  /// and follows the reconnection policy. `false` switches a default off.
  final bool? retryOpen;

  /// Decides whether a failure is transient and worth another attempt;
  /// replaces `SseRetry.isTransient`. An [Exception] it throws counts as
  /// final (no retry).
  final bool Function(Failure<Object?, Object?> failure)? retryWhen;

  /// These options as defaults, with the fields [call] sets on top: a field
  /// the call sets wins, one it leaves unset keeps the default. A null
  /// [call] gives these options.
  SseOptions merge(SseOptions? call) {
    if (call == null) return this;
    final source = call._hasMaxAttempts ? call : this;
    return SseOptions(
      reconnect: call.reconnect ?? reconnect,
      delay: call.delay ?? delay,
      maxDelay: call.maxDelay ?? maxDelay,
      maxAttempts: source._hasMaxAttempts ? source.maxAttempts : _omitted,
      idleTimeout: call.idleTimeout ?? idleTimeout,
      handshakeTimeout: call.handshakeTimeout ?? handshakeTimeout,
      jitter: call.jitter ?? jitter,
      cooldown: call.cooldown ?? cooldown,
      random: call.random ?? random,
      onTrace: call.onTrace ?? onTrace,
      wait: call.wait ?? wait,
      retryOpen: call.retryOpen ?? retryOpen,
      retryWhen: call.retryWhen ?? retryWhen,
    );
  }

  /// Whether [maxAttempts] was written, `null` included. For the package's
  /// own use.
  @internal
  bool get hasMaxAttempts => _hasMaxAttempts;
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
