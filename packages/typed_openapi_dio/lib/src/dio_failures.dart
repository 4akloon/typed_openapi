import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

/// Turns Dio's failures into the client's [TransportException]s.
final class DioFailures {
  const DioFailures._();

  /// The [TransportException] of [e], with [e] as its cause. An [Error]
  /// that an interceptor or the adapter threw (Dio wraps it into an
  /// `unknown` [DioException]) is thrown again: it is a bug, not a
  /// transport failure.
  static TransportException exception(DioException e, StackTrace stackTrace) {
    if (e case DioException(type: .unknown, error: final Error cause)) {
      Error.throwWithStackTrace(cause, e.stackTrace);
    }
    return TransportException(
      switch (e.type) {
        .connectionTimeout || .sendTimeout || .receiveTimeout => .timeout,
        .connectionError => .connection,
        .cancel => .cancelled,
        _ => .other,
      },
      e.message ?? '${e.type.name}: ${e.error}',
      cause: e,
      stackTrace: stackTrace,
    );
  }

  /// [body] with each [DioException] it emits (a timeout or a cancel while
  /// it is read) turned into a [TransportException].
  static Stream<List<int>> body(Stream<Uint8List> body) => body.transform(
    StreamTransformer<Uint8List, List<int>>.fromHandlers(
      handleError: (error, stackTrace, sink) => sink.addError(
        error is DioException ? exception(error, stackTrace) : error,
        stackTrace,
      ),
    ),
  );
}
