import '../request/operation_request.dart';
import '../request/raw_response.dart';
import '../result/result.dart';
import '../sse/sse_item.dart';
import '../sse/sse_message.dart';
import 'call_options.dart';
import 'connection_tokens.dart';

/// What every connection of one event-stream call shares: the request, how
/// it decodes events and error responses, the call's options and its
/// connections' cancel tokens.
final class EventCall<T, E> {
  /// Creates the call; its connections are linked to `call.cancelToken`.
  EventCall(this.request, this.decodeEvent, this.decodeError, this.call)
    : tokens = ConnectionTokens(call?.cancelToken);

  /// The request every connection sends.
  final OperationRequest request;

  /// Decodes the data of one event.
  final T Function(SseMessage message) decodeEvent;

  /// Decodes a response that is not an event stream.
  final Result<Stream<SseItem<T>>, E> Function(RawResponse response)
  decodeError;

  /// The options of the call.
  final CallOptions? call;

  /// The cancel tokens of the connections.
  final ConnectionTokens tokens;
}
