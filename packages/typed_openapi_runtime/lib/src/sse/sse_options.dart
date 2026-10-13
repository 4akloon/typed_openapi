/// How an event stream reconnects after its connection ends (R12.5): the
/// `sse` field of `CallOptions`.
///
/// Reconnection is off unless the call or the operation turns it on. Before
/// each attempt the stream gets an `SseReconnecting` item; a reconnect sends
/// the last event id as `Last-Event-ID`. The first delay is the server's
/// `retry`, else [delay]; each further delay doubles up to [maxDelay] (a
/// server `retry` longer than [maxDelay] is kept as it is). After
/// [maxAttempts] attempts in a row without a message, the stream ends with
/// `SseDisconnected`.
final class SseOptions {
  /// Creates the options of one call.
  const SseOptions({
    this.reconnect,
    this.delay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.maxAttempts = 5,
    this.wait,
  });

  /// Whether the stream reconnects; null keeps the operation's setting
  /// (see [SseReconnection]). `true` has no effect on an operation whose
  /// reconnection is [SseReconnection.off] (a POST that does not enable it):
  /// repeating such a request may not be safe.
  final bool? reconnect;

  /// The first delay when the server sent no `retry`.
  final Duration delay;

  /// The longest delay a doubling reaches.
  final Duration maxDelay;

  /// How many attempts in a row may fail before the stream ends; a message
  /// on a new connection (an event, also one that does not decode or that
  /// the program drops) starts the count again.
  final int maxAttempts;

  /// Waits [delay] before an attempt; `Future.delayed` when null. Tests
  /// pass a function that does not sleep.
  final Future<void> Function(Duration delay)? wait;

  /// The delay before [attempt] (1 for the first), given the server's last
  /// [retry].
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
  /// Never: the operation is not GET and does not enable reconnection.
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
