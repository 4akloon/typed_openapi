import 'dart:convert';
import 'dart:typed_data';

import '../json/json_decode_exception.dart';
import '../request/operation_request.dart';
import '../request/raw_response.dart';
import '../transport/transport_response.dart';
import 'progress_counter.dart';

/// Reads the body of a [TransportResponse] into what a generated decoder
/// switches on, by the [ResponseKind] of the operation.
final class ResponseReader {
  /// Creates the reader; [onProgress] gets the received bytes.
  const ResponseReader(this.onProgress);

  /// Called with the received bytes and the `Content-Length`, `-1` without
  /// one.
  final void Function(int count, int total)? onProgress;

  /// [response] read to the end, the bytes counted for [onProgress].
  Future<Uint8List> readAll(TransportResponse response) async {
    final bytes = BytesBuilder(copy: false);
    await ProgressCounter(
      onProgress,
    ).count(response.body, totalOf(response)).forEach(bytes.add);
    return bytes.takeBytes();
  }

  /// The `Content-Length` of [response], `-1` without a valid one.
  static int totalOf(TransportResponse response) =>
      switch (response.headers['content-length']) {
        [final length, ...] => int.tryParse(length) ?? -1,
        _ => -1,
      };

  /// The [RawResponse] of [response], whose body is [bytes], read as
  /// [kind] says:
  ///
  /// - [ResponseKind.json]: parsed JSON when the headers name a JSON media
  ///   type, else the text; `null` when empty. Text that is not JSON, or not
  ///   UTF-8, throws [JsonDecodeException].
  /// - [ResponseKind.text]: the text, invalid UTF-8 replaced.
  /// - [ResponseKind.bytes]: the bytes.
  static RawResponse raw(
    TransportResponse response,
    Uint8List bytes,
    ResponseKind kind,
  ) => RawResponse(
    statusCode: response.statusCode,
    body: switch (kind) {
      .json => _json(bytes, response.headers),
      .text => utf8.decode(bytes, allowMalformed: true),
      .bytes => bytes,
    },
    headers: response.headers,
  );

  static Object? _json(Uint8List bytes, Map<String, List<String>> headers) {
    if (bytes.isEmpty) return null;
    if (!RawResponse.isJson(headers)) {
      return utf8.decode(bytes, allowMalformed: true);
    }
    try {
      return _utf8Json.convert(bytes);
    } on FormatException {
      throw JsonDecodeException(
        expected: 'a JSON body',
        actual: 'text that is not JSON',
      );
    }
  }

  static final Converter<List<int>, Object?> _utf8Json = const Utf8Decoder()
      .fuse(const JsonDecoder());
}
