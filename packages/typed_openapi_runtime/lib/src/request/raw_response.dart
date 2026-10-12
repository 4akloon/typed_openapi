import 'dart:convert';
import 'dart:typed_data';

import '../json/json_decode_exception.dart';
import '../json/json_reader.dart';
import '../result/result.dart';

/// A response before decoding, independent of how it was received: what a
/// generated decoder switches on.
///
/// ```dart
/// (response) => switch (response.statusCode) {
///   200 => response.success(Pet.fromJson(response.jsonObject)),
///   404 => response.error(NotFound.fromJson(response.jsonObject)),
///   _ => response.undocumented(),
/// }
/// ```
final class RawResponse {
  /// Creates a response.
  const RawResponse({
    required this.statusCode,
    this.body,
    this.headers = const {},
  });

  /// The HTTP status code.
  final int statusCode;

  /// The body as the HTTP client returned it: JSON parsed by Dio, a
  /// [String], bytes ([Uint8List]) or `null`.
  final Object? body;

  /// The response headers, names in lower case.
  final Map<String, List<String>> headers;

  /// The body as parsed JSON. Nothing is parsed or converted here: a server
  /// that answers a JSON operation with `text/plain` gives a [String], which
  /// a decoder that expects an object rejects. Nesting deeper than
  /// [JsonReader.maxDepth] throws [JsonDecodeException].
  Object? get json {
    JsonReader.checkDepth(body);
    return body;
  }

  /// The body as a JSON object; anything else throws [JsonDecodeException].
  Map<String, Object?> get jsonObject => JsonReader.asObject(json);

  /// The body of a text operation; no body is `''`.
  String get text => switch (body) {
    null => '',
    final String text => text,
    final other => throw JsonDecodeException(
      expected: 'a text body',
      actual: JsonDecodeException.describe(other),
    ),
  };

  /// The body of a binary operation; no body is empty.
  Uint8List get bytes => switch (body) {
    null => Uint8List(0),
    final Uint8List bytes => bytes,
    final other => throw JsonDecodeException(
      expected: 'a binary body',
      actual: JsonDecodeException.describe(other),
    ),
  };

  /// A success with the decoded [data].
  Result<T, E> success<T, E>(T data) =>
      Success(data, statusCode: statusCode, headers: headers);

  /// A documented error with the decoded [body].
  Result<T, E> error<T, E>(E body) =>
      HttpError(body, statusCode: statusCode, headers: headers);

  /// A status the operation does not document; the body is kept as is.
  Result<T, E> undocumented<T, E>() => UndocumentedStatus(
    statusCode: statusCode,
    rawBody: body,
    headers: headers,
  );

  /// Parses a body the HTTP client did not parse (an error body of a
  /// streaming operation): JSON when [headers] name a JSON content type,
  /// UTF-8 text otherwise, `null` when empty. Text that is not JSON throws
  /// [JsonDecodeException].
  static Object? parse(Uint8List bytes, Map<String, List<String>> headers) {
    if (bytes.isEmpty) return null;
    final text = utf8.decode(bytes, allowMalformed: true);
    if (!isJson(headers)) return text;
    try {
      return jsonDecode(text);
    } on FormatException {
      throw JsonDecodeException(
        expected: 'a JSON body',
        actual: 'text that is not JSON',
      );
    }
  }

  /// Whether [headers] name a JSON content type (`application/json`,
  /// `text/json`, `*/*+json`), as Dio decides.
  static bool isJson(Map<String, List<String>> headers) {
    final type = headers['content-type']?.firstOrNull
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    return type != null &&
        (type == 'application/json' ||
            type == 'text/json' ||
            type.endsWith('+json'));
  }
}
