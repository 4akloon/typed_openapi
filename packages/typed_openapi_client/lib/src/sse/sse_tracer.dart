import '../request/operation_info.dart';
import '../result/result.dart';
import 'sse_trace.dart';

/// Sends the [SseTrace]s of one event-stream call to `SseOptions.onTrace`.
///
/// A callback that throws an [Exception] is ignored: tracing must not break
/// the stream. An [Error] from it is a bug of the program and is not
/// caught, as elsewhere in the client.
final class SseTracer {
  SseTracer._(this._callback, this._operation) : streamId = _nextId++;

  /// The tracer of a call to [operation] whose `onTrace` is [callback];
  /// null for no tracing.
  static SseTracer? of(
    void Function(SseTrace trace)? callback,
    OperationInfo operation,
  ) => callback == null ? null : SseTracer._(callback, operation);

  // Process-wide, so ids differ between calls; they do not need to be
  // stable between runs.
  static int _nextId = 1;

  final void Function(SseTrace trace) _callback;
  final OperationInfo _operation;

  /// The correlation id of the call.
  final int streamId;

  /// A connection attempt, number [attempt] of the call.
  void connect(int attempt) => _send(
    SseTrace(
      .connect,
      streamId: streamId,
      operation: _operation,
      attempt: attempt,
    ),
  );

  /// The response headers, with [statusCode].
  void open(int statusCode) => _send(
    SseTrace(
      .open,
      streamId: streamId,
      operation: _operation,
      statusCode: statusCode,
    ),
  );

  /// A message named [event] with the stream's last event [id].
  void event(String event, String id) => _send(
    SseTrace(
      .event,
      streamId: streamId,
      operation: _operation,
      event: event,
      eventId: id,
    ),
  );

  /// A comment line.
  void heartbeat() =>
      _send(SseTrace(.heartbeat, streamId: streamId, operation: _operation));

  /// A failure: [error], raised at [stackTrace].
  void error(Object error, StackTrace? stackTrace) => _send(
    SseTrace(
      .error,
      streamId: streamId,
      operation: _operation,
      error: error,
      stackTrace: stackTrace,
    ),
  );

  /// A failed attempt or the end of a call: a [TransportError] or
  /// [Cancelled] traces its exception and stack trace, any other failure
  /// itself.
  void failed(Failure<Object?, Object?> failure) {
    // One trace per failure: an opening that ends on the failure it already
    // traced before a wait must not trace it again as the end of the call.
    if (identical(failure, _lastFailed)) return;
    _lastFailed = failure;
    _traceFailure(failure);
  }

  Failure<Object?, Object?>? _lastFailed;

  void _traceFailure(Failure<Object?, Object?> failure) => switch (failure) {
    TransportError(:final exception, :final stackTrace) => error(
      exception,
      stackTrace,
    ),
    Cancelled(:final exception, :final stackTrace) => error(
      exception,
      stackTrace,
    ),
    _ => error(failure, null),
  };

  /// A wait of [delay] before attempt [attempt].
  void reconnecting(int attempt, Duration delay) => _send(
    SseTrace(
      .reconnecting,
      streamId: streamId,
      operation: _operation,
      attempt: attempt,
      delay: delay,
    ),
  );

  /// The end of the stream.
  void closed() =>
      _send(SseTrace(.closed, streamId: streamId, operation: _operation));

  void _send(SseTrace trace) {
    try {
      _callback(trace);
    } on Exception {
      // A debug hook must not break the stream.
    }
  }
}
