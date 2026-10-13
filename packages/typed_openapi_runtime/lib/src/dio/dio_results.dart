import 'dart:convert';

import 'package:dio/dio.dart';

import '../json/json_decode_exception.dart';
import '../request/raw_response.dart';
import '../result/result.dart';

/// Turns what Dio gives `DioRequestSender` (a response, or a
/// [DioException] without one) into a [Result].
final class DioResults {
  /// Creates the mapping; [isWeb] tells whether the program runs in a
  /// browser (see `DioRequestSender.isWeb`).
  const DioResults({required this.isWeb});

  /// Whether the program runs in a browser.
  final bool isWeb;

  /// A response without a status (only a faulty interceptor builds one)
  /// gets status 0, which no operation documents.
  static RawResponse raw(Response<Object?> response, Object? body) =>
      RawResponse(
        statusCode: response.statusCode ?? 0,
        body: body,
        headers: response.headers.map,
      );

  /// [raw] decoded with [decode]; a [JsonDecodeException] or a
  /// [FormatException] it throws is a [DecodeError].
  static Result<T, E> decode<T, E>(
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
  Failure<T, E> failure<T, E>(DioException e, StackTrace stackTrace) {
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
