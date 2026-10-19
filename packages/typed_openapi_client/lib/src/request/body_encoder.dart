import 'dart:convert';
import 'dart:typed_data';

import 'encoded_body.dart';
import 'file_upload.dart';
import 'form_body.dart';
import 'media_type_text.dart';
import 'multipart_body.dart';
import 'multipart_encoder.dart';
import 'operation_request.dart';
import 'parsed_media_type.dart';

/// Turns the body of an [OperationRequest] into the bytes every transport
/// sends: form text, `multipart/form-data`, the bytes or the stream of a
/// file, JSON text, or text.
final class BodyEncoder {
  /// Creates the encoder; [boundary] gives the boundary of each multipart
  /// body.
  const BodyEncoder(this.boundary);

  /// Makes the boundary of a multipart body.
  final String Function() boundary;

  /// The encoded body of [request], or null when nothing is sent.
  ///
  /// - A [FormBody] is its text, a [MultipartBody] its parts, a
  ///   [FileUpload] its bytes or its stream, with the file's own media type
  ///   when it has one (a value that is not a media type throws
  ///   [FormatException]).
  /// - With a JSON `Content-Type` (`application/json`, `text/json` or a
  ///   `+json` type) any value is JSON text: a string is quoted, and `null`
  ///   is the JSON value `null` of a required nullable body.
  /// - Without one, `null` sends nothing, [Uint8List] is sent as it is and
  ///   any other value as its text in UTF-8.
  EncodedBody? encode(OperationRequest request) {
    final contentType = request.contentType;
    final isJson = contentType != null && MediaTypeText(contentType).isJson;
    return switch (request.body) {
      final FormBody form => EncodedBody.bytes(
        utf8.encode(form.encode()),
        contentType: contentType,
      ),
      final MultipartBody multipart => MultipartEncoder(
        boundary(),
      ).encode(multipart),
      final FileUpload file => _file(file, contentType),
      final body when isJson => EncodedBody.bytes(
        utf8.encode(jsonEncode(body)),
        contentType: contentType,
      ),
      null => null,
      final Uint8List bytes => EncodedBody.bytes(
        bytes,
        contentType: contentType,
      ),
      final body => EncodedBody.bytes(
        utf8.encode('$body'),
        contentType: contentType,
      ),
    };
  }

  /// A file body: the file's own media type wins over the spec's, and is
  /// sent as written once it reads as a media type.
  static EncodedBody _file(FileUpload file, String? specType) {
    final type = file.contentType;
    if (type != null) ParsedMediaType.parse(type);
    final contentType = type ?? specType;
    return switch (file) {
      FileUpload(:final bytes?) => EncodedBody.bytes(
        bytes,
        contentType: contentType,
      ),
      FileUpload(:final stream?) => EncodedBody.stream(
        stream,
        length: file.length,
        contentType: contentType,
      ),
      _ => EncodedBody.bytes(Uint8List(0), contentType: contentType),
    };
  }
}
