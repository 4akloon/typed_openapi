/// What a traced event stream just did (`SseTrace.kind`).
enum SseTraceKind {
  /// A connection attempt is about to be sent.
  connect,

  /// The response headers arrived.
  open,

  /// A message arrived, also one that does not decode or that the program
  /// drops.
  event,

  /// A comment line arrived (`: ping`).
  heartbeat,

  /// A connection ended with an error, or a response was not an event
  /// stream.
  error,

  /// The stream waits before another connection attempt.
  reconnecting,

  /// The stream is over: its last item went out, or the listener cancelled.
  closed,
}

/// One step of an event stream, handed to `SseOptions.onTrace`.
///
/// For a debug panel or a log. It reports what the stream does and never
/// changes the items it emits. Which fields are set depends on [kind].
final class SseTrace {
  /// Creates a trace of [kind] for the stream [streamId].
  const SseTrace(
    this.kind, {
    required this.streamId,
    this.attempt,
    this.statusCode,
    this.event,
    this.eventId,
    this.delay,
    this.error,
    this.stackTrace,
  });

  /// What happened.
  final SseTraceKind kind;

  /// The correlation id of the stream: one per call, the same on every
  /// connection of it, different for every call in the program.
  final int streamId;

  /// [SseTraceKind.connect]: the number of the connection, 1 for the first
  /// request and 2 for the first reconnection. [SseTraceKind.reconnecting]:
  /// the number of the attempt, as `SseReconnecting.attempt`.
  final int? attempt;

  /// [SseTraceKind.open]: the status of the response.
  final int? statusCode;

  /// [SseTraceKind.event]: the `event` field, or `message`.
  final String? event;

  /// [SseTraceKind.event]: the last event id of the stream, `''` for none.
  final String? eventId;

  /// [SseTraceKind.reconnecting]: how long the stream waits.
  final Duration? delay;

  /// [SseTraceKind.error]: the cause, usually a `TransportException` (a
  /// timeout, a cancel) or the `Failure` the server's status gave.
  final Object? error;

  /// [SseTraceKind.error]: where [error] was raised, when known.
  final StackTrace? stackTrace;

  @override
  String toString() {
    final fields = [
      if (attempt != null) 'attempt: $attempt',
      if (statusCode != null) 'status: $statusCode',
      if (event != null) 'event: $event',
      if (eventId != null) 'id: $eventId',
      if (delay != null) 'delay: $delay',
      if (error != null) 'error: $error',
    ];
    return 'SseTrace(#$streamId ${kind.name}'
        '${fields.isEmpty ? '' : ' ${fields.join(', ')}'})';
  }
}
