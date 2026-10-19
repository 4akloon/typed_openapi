import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

import 'dio_failures.dart';

/// Turns a Dio [Response] into a [TransportResponse].
///
/// The adapter's response is a [ResponseBody] stream, but an interceptor may
/// resolve a request itself with parsed data (a cache, a mock); that data is
/// turned back into bytes so the client reads it as any other body.
final class DioResponses {
  const DioResponses._();

  /// The [TransportResponse] of [response], with lower-case header names.
  ///
  /// Throws a [TransportException] of kind `other` when the data of an
  /// interceptor's response cannot be written as bytes.
  static TransportResponse of(Response<Object?> response) {
    final data = response.data;
    return TransportResponse(
      statusCode:
          response.statusCode ?? (data is ResponseBody ? data.statusCode : 200),
      headers: {
        for (final MapEntry(:key, :value) in response.headers.map.entries)
          key.toLowerCase(): value,
      },
      body: _body(data),
    );
  }

  static Stream<List<int>> _body(Object? data) => switch (data) {
    ResponseBody() => DioFailures.body(data.stream),
    null => const Stream<List<int>>.empty(),
    Uint8List() => Stream.value(data),
    List<int>() => Stream.value(data),
    String() => Stream.value(utf8.encode(data)),
    Map<Object?, Object?>() ||
    List<Object?>() => Stream.value(utf8.encode(jsonEncode(data))),
    _ => throw TransportException(
      .other,
      'A Dio interceptor resolved the request with data of type '
      '${data.runtimeType}, which cannot be sent to the client as a body. '
      'Resolve with a map, a list, a string, bytes or null.',
    ),
  };
}
