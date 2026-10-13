import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../json/json_decode_exception.dart';
import '../request/operation_info.dart';
import '../request/operation_request.dart';
import '../request/raw_response.dart';
import '../result/result.dart';
import '../sse/sse_item.dart';
import '../sse/sse_item_decoder.dart';
import '../sse/sse_message.dart';
import 'call_options.dart';
import 'dio_call.dart';
import 'dio_results.dart';

/// Sends an [OperationRequest] through the user's [Dio] and turns every
/// outcome into a [Result].
///
/// - The Dio instance is never changed: no `baseUrl`, interceptor,
///   transformer or `validateStatus` is set, and nothing is retried.
///   Requests go through `dio.request`, which merges the instance
///   `BaseOptions` (base URL, headers, timeouts).
/// - The path and the query string are encoded here and passed to Dio as
///   one finished path: interceptors see an empty `queryParameters`.
/// - HTTP errors take Dio's usual path: `validateStatus` decides, error
///   statuses reach the `onError` of interceptors, and only then is the
///   response decoded here. An interceptor may resolve an error into a
///   response of any status, so the decoder always switches on the status.
/// - Cancellation is [Cancelled], other Dio failures are [TransportError],
///   a body the decoder rejects with [JsonDecodeException] is
///   [DecodeError], and so is a [FormatException] it throws (a user converter
///   or `Date.parse` rejecting the data), at the root pointer. Nothing else is
///   caught: an [Error] thrown by the decoder, or thrown in a user
///   interceptor or adapter (Dio wraps it into an `unknown` [DioException];
///   it is rethrown with its original stack trace), reaches the caller. Other
///   causes (`SocketException`, `HandshakeException`, custom exceptions) are
///   [TransportError].
final class DioRequestSender {
  /// Sends requests through [dio].
  ///
  /// [isWeb] tells whether the program runs in a browser (dart2js or
  /// dart2wasm), where Dio's JSON parser reports a failure without the bytes
  /// of the body; it is detected by default and set by tests only.
  const DioRequestSender(this.dio, {this.isWeb = _runsOnWeb});

  /// `true` when `dart:js_interop` is available, which it is on dart2js and
  /// dart2wasm and nowhere else.
  static const bool _runsOnWeb = bool.fromEnvironment(
    'dart.library.js_interop',
  );

  /// The user's Dio instance.
  final Dio dio;

  /// Whether the program runs in a browser.
  final bool isWeb;

  DioResults get _results => DioResults(isWeb: isWeb);

  DioCall get _call => DioCall(dio);

  /// Sends [request] and decodes the response of any status with [decode].
  Future<Result<T, E>> send<T, E>(
    OperationRequest request,
    Result<T, E> Function(RawResponse response) decode, {
    CallOptions? call,
  }) async {
    final Response<Object?> response;
    try {
      response = await _call.send(request, call);
    } on DioException catch (e, stackTrace) {
      final failed = e.response;
      if (e.type == .badResponse && failed != null) {
        return DioResults.decode(DioResults.raw(failed, failed.data), decode);
      }
      return _results.failure(e, stackTrace);
    }
    return DioResults.decode(
      DioResults.raw(response, response.data),
      decode,
    );
  }

  /// Opens a `text/event-stream` operation. A status in
  /// [OperationRequest.streamStatuses] gives a [Success] whose stream reads
  /// every event with [decodeEvent]; any other status reads the whole body
  /// and decodes it with [decodeError] (which returns a documented error or
  /// an undocumented status). On the web, with Dio's default adapter, the
  /// result is a [TransportError] that explains how to get a streaming
  /// adapter: the default adapter delivers the body only when the
  /// connection closes.
  ///
  /// The stream of a [Success] holds the connection open: listen to it, or
  /// the connection stays open. Cancelling the subscription closes the
  /// connection, as does cancelling `call.cancelToken` (the stream then
  /// ends with [SseDisconnected]). The stream never emits errors, with one
  /// exception: an [Error] thrown by [decodeEvent] is a bug of the program,
  /// so it reaches the listener as a stream error and the stream closes.
  /// Problems with the data are items ([SseDecodeError]), never errors.
  ///
  /// [OperationRequest.streamStatuses] must not be empty (checked by an
  /// `assert`): a generated method always sets it.
  Future<Result<Stream<SseItem<T>>, E>> openEvents<T, E>(
    OperationRequest request,
    T Function(SseMessage message) decodeEvent,
    Result<Stream<SseItem<T>>, E> Function(RawResponse response) decodeError, {
    CallOptions? call,
  }) async {
    assert(
      request.streamStatuses.isNotEmpty,
      'openEvents needs OperationRequest.streamStatuses (the documented '
      'success statuses of the event stream): without them every status is '
      'read to the end as an error body, so an endless stream would fill '
      'memory. This is a bug of the generated code.',
    );
    if (isWeb && _hasDefaultAdapter) {
      final exception = DioException(
        requestOptions: RequestOptions(
          path: request.resolvePath(),
          method: request.operation.method,
          extra: {OperationInfo.extraKey: request.operation},
        ),
        error: UnsupportedError(webStreamingMessage),
        message: webStreamingMessage,
      );
      return TransportError(exception, StackTrace.current);
    }
    final token = CancelToken();
    final outer = call?.cancelToken;
    if (outer != null) {
      if (outer.isCancelled) {
        token.cancel(outer.cancelError?.error);
      } else {
        outer.whenCancel.then((e) {
          if (!token.isCancelled) token.cancel(e.error);
        });
      }
    }
    final Response<Object?> response;
    try {
      response = await _call.send(
        request,
        call,
        events: true,
        cancelToken: token,
      );
    } on DioException catch (e, stackTrace) {
      final failed = e.response;
      if (e.type == .badResponse && failed != null) {
        return _openFailed(failed, decodeError);
      }
      return _results.failure(e, stackTrace);
    }
    final status = response.statusCode ?? 0;
    final body = response.data;
    if (request.streamStatuses.contains(status) && body is ResponseBody) {
      return Success(
        SseItemDecoder<T>(
          decodeEvent,
          onClose: () {
            if (!token.isCancelled) token.cancel('the event stream was closed');
          },
        ).bind(body.stream),
        statusCode: status,
        headers: response.headers.map,
      );
    }
    return _openFailed(response, decodeError);
  }

  /// Explains why server-sent events cannot stream on the web with the
  /// default Dio adapter.
  static const String webStreamingMessage =
      'Server-sent events need a streaming HTTP adapter on the web: Dio\'s '
      'default browser adapter delivers the body only when the connection '
      'closes. Set a fetch-based adapter on your Dio, such as '
      'ConversionLayerAdapter from package:dio_compatibility_layer with '
      'package:http\'s BrowserClient or package:fetch_client.';

  bool get _hasDefaultAdapter =>
      dio.httpClientAdapter.runtimeType == HttpClientAdapter().runtimeType;

  /// Reads the whole body of an event-stream response that did not open,
  /// parses it (JSON by content type) and decodes it with [decodeError].
  Future<Result<Stream<SseItem<T>>, E>> _openFailed<T, E>(
    Response<Object?> response,
    Result<Stream<SseItem<T>>, E> Function(RawResponse response) decodeError,
  ) async {
    final headers = response.headers.map;
    final Uint8List bytes;
    try {
      bytes = switch (response.data) {
        final ResponseBody body => await _readAll(body.stream),
        _ => Uint8List(0),
      };
    } on DioException catch (e, stackTrace) {
      return _results.failure(e, stackTrace);
    } on Exception catch (e, stackTrace) {
      // The adapter's own exception while reading the body (a reset
      // connection): a transport failure. An Error still reaches the caller.
      return TransportError(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: .unknown,
          error: e,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
    final Object? body;
    try {
      body = RawResponse.parse(bytes, headers);
    } on JsonDecodeException catch (e) {
      return DecodeError(
        e,
        statusCode: response.statusCode,
        rawBody: utf8.decode(bytes, allowMalformed: true),
        headers: headers,
      );
    }
    return DioResults.decode(DioResults.raw(response, body), decodeError);
  }

  static Future<Uint8List> _readAll(Stream<List<int>> stream) async {
    final bytes = BytesBuilder(copy: false);
    await stream.forEach(bytes.add);
    return bytes.takeBytes();
  }
}
