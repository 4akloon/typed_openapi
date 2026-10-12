import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A Dio adapter that answers from memory, so tests never touch the
/// network. It records every request with its body text.
final class FakeAdapter implements HttpClientAdapter {
  /// Answers every request with [respond].
  FakeAdapter(this.respond);

  /// A JSON response with [status].
  factory FakeAdapter.json(int status, Object? body) => FakeAdapter(
    (_) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    ),
  );

  /// A response with [status], [text] and [contentType].
  factory FakeAdapter.text(int status, String text, String contentType) =>
      FakeAdapter(
        (_) => ResponseBody.fromString(
          text,
          status,
          headers: {
            Headers.contentTypeHeader: [contentType],
          },
        ),
      );

  /// Builds the response, or throws a [DioException].
  final ResponseBody Function(RequestOptions options) respond;

  /// The requests seen, in order.
  final List<RequestOptions> requests = [];

  /// The request bodies seen, as text.
  final List<String> bodies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
    }
    bodies.add(utf8.decode(bytes));
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}
