import 'dart:convert';

import 'package:dio/dio.dart';

import '../json/json_decode_exception.dart';
import '../request/operation_info.dart';
import '../request/operation_request.dart';
import '../request/raw_response.dart';
import '../result/result.dart';
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
///   [DecodeError]. Nothing else is caught: an [Error] thrown by the decoder,
///   or thrown in a user interceptor or adapter (Dio wraps it into an
///   `unknown` [DioException]; it is rethrown with its original stack
///   trace), reaches the caller. Other causes (`SocketException`,
///   `HandshakeException`, custom exceptions) are [TransportError]. A
///   [FormatException] thrown by the decoder reaches the caller too.
final class DioRequestSender {
  /// Sends requests through [dio].
  ///
  /// [isWeb] tells whether the program runs in a browser, where Dio's JSON
  /// parser reports a failure with the body text instead of its bytes; it is
  /// detected by default and set by tests only.
  const DioRequestSender(this.dio, {this.isWeb = _runsOnWeb});

  /// `true` when compiled to JavaScript, where `0` and `0.0` are the same
  /// value.
  static const bool _runsOnWeb = identical(0, 0.0);

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

  Future<Response<Object?>> _request(
    OperationRequest request,
    CallOptions? call,
  ) {
    final path = _guardQuery(request.resolvePath());
    final options = Options(
      method: request.operation.method,
      headers: {
        ...request.resolveHeaders(),
        for (final MapEntry(:key, :value) in call?.headers.entries ?? const [])
          key: ?value,
      },
      extra: {...?call?.extra, OperationInfo.extraKey: request.operation},
      contentType: request.contentType,
      responseType: switch (request.responseKind) {
        .json => .json,
        .text => .plain,
        .bytes => .bytes,
      },
    );
    // The type argument picks how Dio reads the body: Dio forces JSON for
    // any type but String and List<int> with bytes.
    Future<Response<R>> send<R>() => dio.request<R>(
      path,
      data: request.body,
      options: options,
      cancelToken: call?.cancelToken,
      onSendProgress: call?.onSendProgress,
      onReceiveProgress: call?.onReceiveProgress,
    );
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
      return DecodeError(
        e,
        statusCode: raw.statusCode,
        rawBody: raw.body,
        headers: raw.headers,
      );
    }
  }

  /// A failure without a response.
  ///
  /// - Cancellation is [Cancelled].
  /// - An `unknown` failure whose cause is an [Error] (a `TypeError` or
  ///   `StateError` thrown in a user interceptor or adapter, which Dio
  ///   wraps) is a bug, not a transport problem: it is rethrown with its
  ///   original stack trace.
  /// - Dio drops the response when its JSON parser fails (`unknown` with a
  ///   [FormatException]). That is a decode error without a status when the
  ///   request reads JSON and the exception reports the bytes of the body
  ///   (what Dio's default transformer does on the VM): the raw body is that
  ///   text (for a body Dio read in chunks, only the chunk that failed). On
  ///   the web ([isWeb]) Dio's parser reports the text itself, so a text
  ///   source counts too. A [FormatException] from anywhere else
  ///   (`Uri.parse` in an interceptor, a custom transformer that reports
  ///   text on the VM) stays a [TransportError].
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
          when source is List<int> || isWeb && source is String:
        return DecodeError(
          JsonDecodeException(
            expected: 'a JSON body',
            actual: 'text that is not JSON',
          ),
          rawBody: switch (source) {
            final List<int> bytes => utf8.decode(bytes, allowMalformed: true),
            _ => source,
          },
        );
      default:
        return TransportError(e, stackTrace);
    }
  }
}
