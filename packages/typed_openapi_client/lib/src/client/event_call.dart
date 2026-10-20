import '../request/operation_request.dart';
import '../request/raw_response.dart';
import '../result/result.dart';
import '../sse/reconnection_plan.dart';
import '../sse/sse_item.dart';
import '../sse/sse_message.dart';
import '../sse/sse_settings.dart';
import '../sse/sse_tracer.dart';
import 'call_options.dart';
import 'connection_signals.dart';

/// What every connection of one event-stream call shares: the request, how
/// it decodes events and error responses, the call's options and its
/// connections' cancel signals.
final class EventCall<T, E> {
  /// Creates the call; its connections are linked to `call.cancel`.
  EventCall(
    OperationRequest request,
    T Function(SseMessage message) decodeEvent,
    Result<Stream<SseItem<T>>, E> Function(RawResponse response) decodeError,
    CallOptions? call,
  ) : this._(
        request,
        decodeEvent,
        decodeError,
        call,
        SseSettings.of(call?.sse),
      );

  EventCall._(
    this.request,
    this.decodeEvent,
    this.decodeError,
    this.call,
    this.settings,
  ) : plan = ReconnectionPlan(settings),
      signals = ConnectionSignals(call?.cancel),
      tracer = SseTracer.of(call?.sse?.onTrace, request.operation);

  /// The request every connection sends.
  final OperationRequest request;

  /// Decodes the data of one event.
  final T Function(SseMessage message) decodeEvent;

  /// Decodes a response that is not an event stream.
  final Result<Stream<SseItem<T>>, E> Function(RawResponse response)
  decodeError;

  /// The options of the call.
  final CallOptions? call;

  /// The call's [SseOptions] with the built-in defaults applied.
  final SseSettings settings;

  /// The failed attempts of the call, counted for the opening and the
  /// reconnections together.
  final ReconnectionPlan plan;

  /// The cancel signals of the connections.
  final ConnectionSignals signals;

  /// Where the call's traces go, or null without `SseOptions.onTrace`.
  final SseTracer? tracer;

  int _connections = 0;

  /// The number of the next connection of the call, from 1.
  int nextConnection() => ++_connections;
}
