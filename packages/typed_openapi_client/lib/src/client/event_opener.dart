import 'dart:typed_data';

import '../json/json_decode_exception.dart';
import '../request/operation_request.dart';
import '../request/raw_response.dart';
import '../result/result.dart';
import '../sse/sse_item.dart';
import '../sse/sse_item_decoder.dart';
import '../sse/sse_message.dart';
import '../sse/sse_options.dart';
import '../sse/sse_reconnector.dart';
import '../transport/cancel_signal.dart';
import '../transport/client_transport.dart';
import '../transport/transport_exception.dart';
import '../transport/transport_response.dart';
import 'call_options.dart';
import 'client_results.dart';
import 'event_call.dart';
import 'progress_counter.dart';
import 'request_builder.dart';
import 'response_reader.dart';

/// Opens the event streams of `ClientSender.openEvents`: the first
/// connection, the reconnections, and the error responses that are read to
/// the end.
final class EventOpener {
  /// Creates the opener over [transport], building requests with
  /// [builder].
  const EventOpener(this.transport, this.builder);

  /// The transport every connection goes through.
  final ClientTransport transport;

  /// Builds the request of each connection.
  final RequestBuilder builder;

  static const _results = ClientResults();

  /// Opens [request] as `ClientSender.openEvents` describes.
  Future<Result<Stream<SseItem<T>>, E>> open<T, E>(
    OperationRequest request,
    T Function(SseMessage message) decodeEvent,
    Result<Stream<SseItem<T>>, E> Function(RawResponse response) decodeError, {
    required CallOptions? call,
    required SseReconnection reconnection,
  }) async {
    final event = EventCall(request, decodeEvent, decodeError, call);
    final first = await _connect(event, (
      lastEventId: RequestBuilder.userLastEventId(call?.headers),
      retry: null,
    ));
    final options = call?.sse ?? const SseOptions();
    if (first case Success(
      :final data,
      :final statusCode,
      :final headers,
    ) when statusCode != 204 && reconnection.reconnects(options)) {
      return Success(
        SseReconnector<T>(
          options,
          (resume) => _connect(event, resume),
          cancel: call?.cancel,
          onCancel: event.signals.cancel,
        ).bind(data),
        statusCode: statusCode,
        headers: headers,
      );
    }
    return first;
  }

  /// One connection: it sends `Last-Event-ID` and starts the decoder from
  /// [resume].
  Future<Result<Stream<SseItem<T>>, E>> _connect<T, E>(
    EventCall<T, E> event,
    SseResume resume,
  ) async {
    final signal = event.signals.next();
    final sent = builder.build(
      event.request,
      event.call,
      events: true,
      cancel: signal,
      lastEventId: resume.lastEventId,
    );
    if (signal.isCancelled) return _results.cancelledBefore(signal);
    final TransportResponse response;
    try {
      response = await transport.send(sent);
    } on TransportException catch (e, stackTrace) {
      return _results.failure(e, stackTrace);
    }
    if (!event.request.streamStatuses.contains(response.statusCode)) {
      return _openFailed(response, event);
    }
    return _events(response, event, signal, resume);
  }

  /// The [Success] of an opened stream: its items, decoded from the body of
  /// [response]; the end of the stream cancels [signal], closing the
  /// connection.
  Success<Stream<SseItem<T>>, E> _events<T, E>(
    TransportResponse response,
    EventCall<T, E> event,
    CancelSignal signal,
    SseResume resume,
  ) {
    final body = ProgressCounter(
      event.call?.onReceiveProgress,
    ).count(response.body, ResponseReader.totalOf(response));
    final items = SseItemDecoder<T>(
      event.decodeEvent,
      onClose: () => signal.cancel('the event stream was closed'),
      lastEventId: resume.lastEventId,
      retry: resume.retry,
    ).bind(body);
    return Success(
      items,
      statusCode: response.statusCode,
      headers: response.headers,
    );
  }

  /// Reads the whole body of an event-stream response that did not open,
  /// parses it (JSON by content type) and decodes it with the error decoder
  /// of [event].
  Future<Result<Stream<SseItem<T>>, E>> _openFailed<T, E>(
    TransportResponse response,
    EventCall<T, E> event,
  ) async {
    final Uint8List bytes;
    try {
      bytes = await ResponseReader(
        event.call?.onReceiveProgress,
      ).readAll(response);
    } on TransportException catch (e, stackTrace) {
      return _results.failure(e, stackTrace);
    } on Exception catch (e, stackTrace) {
      // The transport's own exception while reading the body breaks its
      // contract; it is still a transport failure. An Error reaches the
      // caller.
      return _results.unexpected(e, stackTrace);
    }
    final Object? body;
    try {
      body = RawResponse.parse(bytes, response.headers);
    } on JsonDecodeException catch (e) {
      return _results.decodeError(
        e,
        response.statusCode,
        bytes,
        response.headers,
      );
    }
    return _results.decode(
      RawResponse(
        statusCode: response.statusCode,
        body: body,
        headers: response.headers,
      ),
      event.decodeError,
    );
  }
}
