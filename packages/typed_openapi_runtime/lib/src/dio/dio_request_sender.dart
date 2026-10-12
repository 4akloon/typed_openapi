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

  /// Sends [request] and decodes the response of any status with [decode].
  Future<Result<T, E>> send<T, E>(
    OperationRequest request,
    Result<T, E> Function(RawResponse response) decode, {
    CallOptions? call,
  }) async {
    final Response<Object?> response;
    try {
      response = await _request(request, call);
    } on DioException catch (e, stackTrace) {
      final failed = e.response;
      if (e.type == .badResponse && failed != null) {
        return _decode(_raw(failed, failed.data), decode);
      }
      return _failure(e, stackTrace);
    }
    return _decode(_raw(response, response.data), decode);
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
      response = await _request(
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
      return _failure(e, stackTrace);
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

  Future<Response<Object?>> _request(
    OperationRequest request,
    CallOptions? call, {
    bool events = false,
    CancelToken? cancelToken,
  }) {
    final path = _guardQuery(request.resolvePath());
    final options = Options(
      method: request.operation.method,
      headers: {
        if (events) 'Accept': 'text/event-stream',
        ...request.resolveHeaders(),
        for (final MapEntry(:key, :value) in call?.headers.entries ?? const [])
          key: ?value,
      },
      extra: {...?call?.extra, OperationInfo.extraKey: request.operation},
      contentType: request.contentType,
      responseType: events
          ? .stream
          : switch (request.responseKind) {
              .json => .json,
              .text => .plain,
              .bytes => .bytes,
            },
    );
    // The type argument picks how Dio reads the body: Dio forces JSON for
    // any type but String, List<int> with bytes or ResponseBody with stream.
    Future<Response<R>> send<R>() => dio.request<R>(
      path,
      data: request.body,
      options: options,
      cancelToken: cancelToken ?? call?.cancelToken,
      onSendProgress: call?.onSendProgress,
      onReceiveProgress: call?.onReceiveProgress,
    );
    if (events) return send<ResponseBody>();
    return switch (request.responseKind) {
      .json => send<Object?>(),
      .text => send<String>(),
      .bytes => send<List<int>>(),
    };
  }

  /// Dio joins the base URL and a relative path and then collapses every
  /// `//` of the whole string, query included (`RequestOptions.uri`), which
  /// would change an `allowReserved` value such as `next=/a//b`. When the
  /// query holds `//`, the base URL is joined here, collapsing `//` in the
  /// path part only, and the result is passed as an absolute URL, which Dio
  /// leaves alone. Interceptors still see the finished URI. Otherwise the
  /// relative path goes to Dio, so interceptors that change `baseUrl` keep
  /// working.
  String _guardQuery(String path) {
    final queryStart = path.indexOf('?');
    final base = dio.options.baseUrl;
    if (queryStart < 0 ||
        !path.substring(queryStart).contains('//') ||
        !_absolute.hasMatch(base)) {
      return path;
    }
    final joined = (base + path.substring(0, queryStart)).split(':/');
    final target = joined.length == 2
        ? '${joined[0]}:/${joined[1].replaceAll('//', '/')}'
        : joined.join(':/');
    return target + path.substring(queryStart);
  }

  static final RegExp _absolute = RegExp('^https?:');

  /// A response without a status (only a faulty interceptor builds one)
  /// gets status 0, which no operation documents.
  static RawResponse _raw(Response<Object?> response, Object? body) =>
      RawResponse(
        statusCode: response.statusCode ?? 0,
        body: body,
        headers: response.headers.map,
      );

  static Result<T, E> _decode<T, E>(
    RawResponse raw,
    Result<T, E> Function(RawResponse response) decode,
  ) {
    try {
      return decode(raw);
    } on JsonDecodeException catch (e) {
      return _decodeError(e, raw);
    } on FormatException catch (e) {
      // A user converter (R6.8) or `Date.parse` rejecting server data.
      return _decodeError(JsonDecodeException.fromFormatException(e), raw);
    }
  }

  static DecodeError<T, E> _decodeError<T, E>(
    JsonDecodeException error,
    RawResponse raw,
  ) => DecodeError(
    error,
    statusCode: raw.statusCode,
    rawBody: raw.body,
    headers: raw.headers,
  );

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
      return _failure(e, stackTrace);
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
    return _decode(_raw(response, body), decodeError);
  }

  static Future<Uint8List> _readAll(Stream<List<int>> stream) async {
    final bytes = BytesBuilder(copy: false);
    await stream.forEach(bytes.add);
    return bytes.takeBytes();
  }

  /// A failure without a response.
  ///
  /// - Cancellation is [Cancelled].
  /// - An `unknown` failure whose cause is an [Error] (a `TypeError` or
  ///   `StateError` thrown in a user interceptor or adapter, which Dio
  ///   wraps) is a bug, not a transport problem: it is rethrown with its
  ///   original stack trace.
  /// - Dio drops the response when its JSON parser fails (`unknown` with a
  ///   [FormatException]), so the result has no status. That is a decode
  ///   error when the request reads JSON and the exception reports the bytes
  ///   of the body (what Dio's default transformer does on the VM and
  ///   dart2wasm): the raw body is that text (for a body Dio read in chunks,
  ///   only the chunk that failed). On the web ([isWeb]) every such
  ///   [FormatException] counts: dart2js reports the browser's `SyntaxError`
  ///   text and no source, so the raw body is the source when it is text and
  ///   `null` otherwise; a [FormatException] from an interceptor of a JSON
  ///   request is a decode error there too, because the failures cannot be
  ///   told apart. On the VM a [FormatException] from anywhere else
  ///   (`Uri.parse` in an interceptor, a custom transformer that reports
  ///   text) stays a [TransportError]; a request that does not read JSON
  ///   never gets a decode error here.
  Failure<T, E> _failure<T, E>(
    DioException e,
    StackTrace stackTrace,
  ) {
    switch (e) {
      case DioException(type: .cancel):
        return Cancelled(e, stackTrace);
      case DioException(type: .unknown, error: final Error cause):
        Error.throwWithStackTrace(cause, e.stackTrace);
      case DioException(
            type: .unknown,
            response: null,
            requestOptions: RequestOptions(responseType: .json),
            error: FormatException(:final source),
          )
          when source is List<int> || isWeb:
        return DecodeError(
          JsonDecodeException(
            expected: 'a JSON body',
            actual: 'text that is not JSON',
          ),
          rawBody: switch (source) {
            final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
            final String text => text,
            _ => null,
          },
        );
      default:
        return TransportError(e, stackTrace);
    }
  }
}
