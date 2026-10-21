import 'dart:math';
import 'dart:typed_data';

import '../json/json_decode_exception.dart';
import '../request/body_encoder.dart';
import '../request/operation_request.dart';
import '../request/raw_response.dart';
import '../result/result.dart';
import '../sse/sse_item.dart';
import '../sse/sse_message.dart';
import '../sse/sse_options.dart';
import '../transport/client_transport.dart';
import '../transport/transport_exception.dart';
import '../transport/transport_response.dart';
import 'call_options.dart';
import 'client_results.dart';
import 'event_opener.dart';
import 'request_builder.dart';
import 'response_reader.dart';

/// Sends an [OperationRequest] through a [ClientTransport] and turns every
/// outcome into a [Result]: what every generated group holds.
///
/// - The core builds the request: the path and the query string (one
///   finished target, resolved by the transport against its base URL), the
///   headers and the body bytes. The transport is used as it is, and nothing
///   is retried.
/// - A response of any status is read to the end and decoded here: the
///   decoder switches on the status, so a transport whose interceptors turn
///   an error into another response still gets a typed result.
/// - A cancel is [Cancelled], another [TransportException] is
///   [TransportError], a body the decoder rejects with
///   [JsonDecodeException] is [DecodeError], and so is a [FormatException]
///   it throws (a user converter or `Date.parse` rejecting the data), at the
///   root pointer, and a JSON body that does not parse. Nothing else is
///   caught: an [Error] thrown by the decoder or the transport reaches the
///   caller.
final class ClientSender {
  /// Sends requests through [transport]; [defaults] are merged under the
  /// options of every call ([CallOptions.merge]); [boundary] makes the
  /// boundary of each multipart body (random by default, fixed in tests).
  ClientSender(
    this.transport, {
    this.defaults = const CallOptions(),
    String Function()? boundary,
  }) : _builder = RequestBuilder(
         BodyEncoder(boundary ?? _randomBoundary),
         defaultHeaders: defaults.headers,
       ),
       _options = defaults.withoutHeaders();

  /// The transport every request goes through.
  final ClientTransport transport;

  /// The options every call starts from; a call's own options win field by
  /// field.
  final CallOptions defaults;

  final RequestBuilder _builder;

  // The defaults but their headers, which the builder layers under the
  // operation's; merging a call into this keeps the call's headers alone.
  final CallOptions _options;

  static const _results = ClientResults();

  /// Sends [request] and decodes the response of any status with [decode].
  Future<Result<T, E>> send<T, E>(
    OperationRequest request,
    Result<T, E> Function(RawResponse response) decode, {
    CallOptions? call,
  }) async {
    final merged = _options.merge(call);
    final sent = _builder.build(request, merged);
    if (merged.cancel case final cancel? when cancel.isCancelled) {
      return _results.cancelledBefore(cancel);
    }
    final TransportResponse response;
    try {
      response = await transport.send(sent);
    } on TransportException catch (e, stackTrace) {
      return _results.failure(e, stackTrace);
    }
    return _read(response, request.responseKind, merged, decode);
  }

  /// Opens a `text/event-stream` operation. A status in
  /// [OperationRequest.streamStatuses] gives a [Success] whose stream reads
  /// every event with [decodeEvent]; any other status reads the whole body
  /// and decodes it with [decodeError] (which returns a documented error or
  /// an undocumented status).
  ///
  /// The stream of a [Success] holds the connection open: listen to it, or
  /// the connection stays open. Cancelling the subscription closes the
  /// connection, as does cancelling `call.cancel` (the stream then ends with
  /// [SseDisconnected]). The stream never emits errors, with one exception:
  /// an [Error] thrown by [decodeEvent] is a bug of the program, so it
  /// reaches the listener as a stream error and the stream closes. Problems
  /// with the data are items ([SseDecodeError]), never errors.
  ///
  /// The stream reconnects (R12.5) when [reconnection] and `call.sse` say
  /// so (see [SseReconnection], [SseOptions] and `SseReconnector`); a 204
  /// No Content never reconnects.
  ///
  /// A transient failure of the opening is retried in the same cases, with
  /// the same delays, `Retry-After` and traces ([SseOptions.retryOpen]). The
  /// returned [Future] waits meanwhile: it completes when the stream opens,
  /// when a failure is final, when the attempts are used up (the last
  /// [Failure]) or with [Cancelled] when `call.cancel` fires, also during a
  /// wait. There is no listener to cancel before it completes, so cancel
  /// through `call.cancel`. [SseReconnection.off] and a request body that
  /// can be read once (`FileUpload.stream`) are never sent twice, whatever
  /// `retryOpen` says.
  ///
  /// [OperationRequest.streamStatuses] must not be empty (checked by an
  /// `assert`): a generated method always sets it.
  Future<Result<Stream<SseItem<T>>, E>> openEvents<T, E>(
    OperationRequest request,
    T Function(SseMessage message) decodeEvent,
    Result<Stream<SseItem<T>>, E> Function(RawResponse response) decodeError, {
    CallOptions? call,
    SseReconnection reconnection = .onRequest,
  }) async {
    assert(
      request.streamStatuses.isNotEmpty,
      'openEvents needs OperationRequest.streamStatuses (the documented '
      'success statuses of the event stream): without them every status is '
      'read to the end as an error body, so an endless stream would fill '
      'memory. This is a bug of the generated code.',
    );
    return EventOpener(transport, _builder).open(
      request,
      decodeEvent,
      decodeError,
      call: _options.merge(call),
      reconnection: reconnection,
    );
  }

  /// Reads [response] to the end as [kind] says and decodes it.
  Future<Result<T, E>> _read<T, E>(
    TransportResponse response,
    ResponseKind kind,
    CallOptions? call,
    Result<T, E> Function(RawResponse response) decode,
  ) async {
    final Uint8List bytes;
    try {
      bytes = await ResponseReader(call?.onReceiveProgress).readAll(response);
    } on TransportException catch (e, stackTrace) {
      return _results.failure(e, stackTrace);
    } on Exception catch (e, stackTrace) {
      return _results.unexpected(e, stackTrace);
    }
    final RawResponse raw;
    try {
      raw = ResponseReader.raw(response, bytes, kind);
    } on JsonDecodeException catch (e) {
      return _results.decodeError(
        e,
        response.statusCode,
        bytes,
        response.headers,
      );
    }
    return _results.decode(raw, decode);
  }

  /// A boundary of 10 random digits after a fixed prefix, as Dio made one.
  static String _randomBoundary() =>
      '--typed-openapi-boundary-'
      '${_random.nextInt(_boundaryRange).toString().padLeft(10, '0')}';

  // 2^32 as a literal: `1 << 32` is 0 when compiled to JavaScript, whose
  // shifts work on 32 bits.
  static const _boundaryRange = 4294967296;

  static final Random _random = Random();
}
