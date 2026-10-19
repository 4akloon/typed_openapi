import 'package:dio/dio.dart';

import '../json/json_decode_exception.dart';

/// The outcome of a generated operation: [Success] with the decoded body of
/// type [T], or a [Failure] whose documented error body has type [E].
///
/// Generated operations never throw for expected problems (HTTP errors,
/// transport failures, cancellation, bodies that do not match the schema,
/// including a `FormatException` of a converter or `Date.parse` on the
/// data); errors of the program (`TypeError`, `StateError`) are not caught. There
/// are no helper methods: read a result with pattern matching.
///
/// ```dart
/// switch (await api.pets.getPetById(petId: 1)) {
///   case Success(:final data): show(data);
///   case HttpError(:final body): showError(body);
///   case Failure(): retryLater();
/// }
/// ```
///
/// An operation without documented errors has `E = Never`; a success
/// without a body has `T = void`.
sealed class Result<T, E> {
  const Result();
}

/// A response with a documented success status.
final class Success<T, E> extends Result<T, E> {
  /// Creates a success with the decoded [data].
  const Success(this.data, {required this.statusCode, this.headers = const {}});

  /// The decoded body.
  final T data;

  /// The HTTP status code.
  final int statusCode;

  /// The response headers, names in lower case.
  final Map<String, List<String>> headers;

  @override
  String toString() => 'Success($statusCode)';
}

/// Any outcome but [Success].
sealed class Failure<T, E> extends Result<T, E> {
  const Failure();
}

/// A response with a documented error status (4xx, 5xx or `default`) whose
/// body decoded as [E]. A body that does not decode is a [DecodeError].
final class HttpError<T, E> extends Failure<T, E> {
  /// Creates an error with the decoded [body].
  const HttpError(
    this.body, {
    required this.statusCode,
    this.headers = const {},
  });

  /// The decoded error body.
  final E body;

  /// The HTTP status code.
  final int statusCode;

  /// The response headers, names in lower case.
  final Map<String, List<String>> headers;

  @override
  String toString() => 'HttpError($statusCode)';
}

/// A response whose status the operation does not document; the body is
/// kept as received.
final class UndocumentedStatus<T, E> extends Failure<T, E> {
  /// Creates an undocumented-status failure.
  const UndocumentedStatus({
    required this.statusCode,
    this.rawBody,
    this.headers = const {},
  });

  /// The HTTP status code.
  final int statusCode;

  /// The body as the HTTP client returned it (decoded JSON, text or bytes).
  final Object? rawBody;

  /// The response headers, names in lower case.
  final Map<String, List<String>> headers;

  @override
  String toString() => 'UndocumentedStatus($statusCode)';
}

/// A response body that does not match the schema of its status (success
/// or documented error), is not valid JSON, or is rejected by a decoder
/// with a `FormatException` (a converter, `Date.parse`). Carries the first
/// mismatch.
final class DecodeError<T, E> extends Failure<T, E> {
  /// Creates a decode failure.
  const DecodeError(
    this.error, {
    this.statusCode,
    this.rawBody,
    this.headers = const {},
  });

  /// What did not match and where (JSON pointer, expected, actual).
  final JsonDecodeException error;

  /// The HTTP status code; `null` when Dio could not parse the JSON body
  /// and dropped the response.
  final int? statusCode;

  /// The body as the HTTP client returned it; for JSON Dio could not parse,
  /// the text its parser reported.
  final Object? rawBody;

  /// The response headers, names in lower case.
  final Map<String, List<String>> headers;

  @override
  String toString() => 'DecodeError(${statusCode ?? 'no status'}: $error)';
}

/// The request got no response: a timeout, a connection or certificate
/// problem, or another failure Dio reports.
final class TransportError<T, E> extends Failure<T, E> {
  /// Creates a transport failure.
  const TransportError(this.exception, this.stackTrace);

  /// What Dio reported; `exception.type` tells the kind.
  final DioException exception;

  /// Where [exception] was thrown.
  final StackTrace stackTrace;

  @override
  String toString() => 'TransportError(${exception.type.name})';
}

/// The caller cancelled the request; not a failure of the server or the
/// network.
final class Cancelled<T, E> extends Failure<T, E> {
  /// Creates a cancellation outcome.
  const Cancelled(this.exception, this.stackTrace);

  /// What Dio reported (`DioExceptionType.cancel`).
  final DioException exception;

  /// Where [exception] was thrown.
  final StackTrace stackTrace;

  @override
  String toString() => 'Cancelled';
}
