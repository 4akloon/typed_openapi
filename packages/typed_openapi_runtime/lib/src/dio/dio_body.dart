import 'dart:convert';

import 'package:dio/dio.dart';

import '../request/file_upload.dart';
import '../request/form_body.dart';
import '../request/multipart_body.dart';
import '../request/operation_request.dart';

/// Turns the body of an `OperationRequest` into what Dio sends: form text,
/// `FormData` built for this request, the bytes or the stream of a file, or
/// the body as it is (JSON, text).
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
    FileUpload(contentType: final type?) => type,
    MultipartBody() => null,
    _ => request.contentType,
  };

  /// What Dio sends for [body].
  Object? data(Object? body) => switch (body) {
    final FormBody form => form.encode(),
    final MultipartBody multipart => _formData(multipart),
    FileUpload(:final bytes?) => bytes,
    FileUpload(:final stream?) => stream,
    _ => body,
  };

  FormData _formData(MultipartBody body) {
    final data = FormData();
    for (final part in body.parts) {
      switch (part.file) {
        case final file?:
          data.files.add(MapEntry(part.name, _file(file, part.contentType)));
        case null:
          _addValue(data, part.name, part.value, part.contentType);
      }
    }
    return data;
  }

  /// A file part: the file's own media type wins over the spec's.
  static MultipartFile _file(FileUpload file, String? specType) {
    final type = file.contentType ?? specType;
    final contentType = type == null ? null : DioMediaType.parse(type);
    return switch (file) {
      FileUpload(:final bytes?) => MultipartFile.fromBytes(
        bytes,
        filename: file.filename,
        contentType: contentType,
      ),
      _ => MultipartFile.fromStream(
        () => file.stream!,
        file.length,
        filename: file.filename,
        contentType: contentType,
      ),
    };
  }

  /// Adds the value parts of [value]: none for `null`, a part per item of a
  /// list, JSON for an object or a JSON [contentType], text otherwise.
  static void _addValue(
    FormData data,
    String name,
    Object? value,
    String? contentType,
  ) {
    switch (value) {
      case null:
        return;
      case final List<Object?> items:
        for (final item in items) {
          _addValue(data, name, item, contentType);
        }
      case _ when contentType != null && _isJson(contentType):
        data.files.add(MapEntry(name, _text(jsonEncode(value), contentType)));
      case Map<Object?, Object?>():
        data.files.add(
          MapEntry(name, _text(jsonEncode(value), 'application/json')),
        );
      case _ when contentType != null:
        data.files.add(MapEntry(name, _text(_scalar(value), contentType)));
      default:
        data.fields.add(MapEntry(name, _scalar(value)));
    }
  }

  static MultipartFile _text(String text, String contentType) =>
      MultipartFile.fromString(
        text,
        contentType: DioMediaType.parse(contentType),
      );

  static bool _isJson(String contentType) {
    final type = contentType.split(';').first.trim().toLowerCase();
    return type == 'application/json' || type.endsWith('+json');
  }

  /// The text of a scalar JSON value of a part.
  static String _scalar(Object? value) => switch (value) {
    final String text => text,
    _ => '$value',
  };
}
