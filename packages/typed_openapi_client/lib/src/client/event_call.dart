import '../request/operation_request.dart';
import '../request/raw_response.dart';
import '../result/result.dart';
import '../sse/sse_item.dart';
import '../sse/sse_message.dart';
import '../sse/sse_tracer.dart';
import 'call_options.dart';
import 'connection_signals.dart';

/// What every connection of one event-stream call shares: the request, how
/// it decodes events and error responses, the call's options and its
/// connections' cancel signals.
final class EventCall<T, E> {
  /// Creates the call; its connections are linked to `call.cancel`.
  EventCall(this.request, this.decodeEvent, this.decodeError, this.call)
    : signals = ConnectionSignals(call?.cancel),
      tracer = SseTracer.of(call?.sse?.onTrace);

  /// The request every connection sends.
  final OperationRequest request;

  /// Decodes the data of one event.
  final T Function(SseMessage message) decodeEvent;

  /// Decodes a response that is not an event stream.
  final Result<Stream<SseItem<T>>, E> Function(RawResponse response)
  decodeError;

  /// The options of the call.
  final CallOptions? call;

  /// The cancel signals of the connections.
  final ConnectionSignals signals;

  /// Where the call's traces go, or null without `SseOptions.onTrace`.
  final SseTracer? tracer;

  int _connections = 0;

  /// The number of the next connection of the call, from 1.
  int nextConnection() => ++_connections;
}
