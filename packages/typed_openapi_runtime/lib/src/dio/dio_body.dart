import 'dart:convert';

import 'package:dio/dio.dart';

import '../request/file_upload.dart';
import '../request/form_body.dart';
import '../request/multipart_body.dart';
import '../request/operation_request.dart';
import 'media_type_text.dart';
import 'multipart_form.dart';

/// Turns the body of an `OperationRequest` into what Dio sends: form text,
/// `FormData` built for this request, the bytes or the stream of a file, JSON
/// text, or the body as it is (text).
final class DioBody {
  /// Creates the converter.
  const DioBody();

  /// The headers [body] needs: Dio sends a stream as it is and needs its
  /// length.
  Map<String, String> headers(Object? body) => switch (body) {
    FileUpload(stream: _?, :final length) => {
      Headers.contentLengthHeader: '$length',
    },
    _ => const {},
  };

  /// The `Content-Type` of [request]: a file's own media type wins over the
  /// spec's, and Dio sets the one of form data with its boundary.
  String? contentType(OperationRequest request) => switch (request.body) {
    FileUpload(contentType: final type?) => _mediaType(type),
    MultipartBody() => null,
    null when !_isJsonBody(request) => null,
    _ => request.contentType,
  };

  /// What Dio sends for the body of [request].
  ///
  /// A JSON body (`application/json` or `+json`) is encoded here only
  /// where Dio gets it wrong: Dio sends a `String` as it is, so the string
  /// `a"b` would go out unquoted, and it sends `null` as no body. A `null`
  /// body with a JSON `Content-Type` is the JSON value `null` (a required
  /// nullable body). A map, list, number or boolean stays as it is, and
  /// Dio's transformer (and so an interceptor) sees the object itself.
  /// With no body and no JSON `Content-Type` nothing is sent.
  Object? data(OperationRequest request) => switch (request.body) {
    final FormBody form => form.encode(),
    final MultipartBody multipart => const MultipartForm().build(multipart),
    FileUpload(:final bytes?) => bytes,
    FileUpload(:final stream?) => stream,
    final body when _isJsonBody(request) && _needsEncoding(body) => jsonEncode(
      body,
    ),
    final body => body,
  };

  static bool _isJsonBody(OperationRequest request) {
    final type = request.contentType;
    return type != null && MediaTypeText(type).isJson;
  }

  /// Whether Dio would send [body] wrongly as JSON: a string goes out as it
  /// is, without quotes, and `null` goes out as no body.
  static bool _needsEncoding(Object? body) => body == null || body is String;

  /// [type] when it is a media type; throws [FormatException] otherwise, as a
  /// part's media type does.
  static String _mediaType(String type) {
    DioMediaType.parse(type);
    return type;
  }
}
