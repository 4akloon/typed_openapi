import 'dart:convert';

import 'package:dio/dio.dart';

import '../request/file_upload.dart';
import '../request/media_type_text.dart';
import '../request/multipart_body.dart';

/// Builds the Dio `FormData` of a [MultipartBody], in the order of its
/// parts.
///
/// Dio writes every plain field of a `FormData` before its files. A plain
/// text part stays a field while no file or typed part precedes it, which is
/// the usual shape (values first, files last) and sends no `Content-Type`
/// for the text. After the first file or typed part, text parts are sent as
/// `text/plain; charset=utf-8` parts, so that the wire order is the order of
/// [MultipartBody.parts].
final class MultipartForm {
  /// Creates the builder.
  const MultipartForm();

  /// The form data of [body], made for one request.
  ///
  /// Throws [ArgumentError] for a value that cannot be a part (not a finite
  /// JSON scalar, a list inside a list, a non-JSON value in a JSON part, an
  /// object with a media type that is not JSON) and [FormatException] for a
  /// media type that is not one.
  FormData build(MultipartBody body) {
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
          if (item is List<Object?>) {
            throw _notAPart(name, item, 'a nested list');
          }
          _addValue(data, name, item, contentType);
        }
      case _ when contentType != null && MediaTypeText(contentType).isJson:
        data.files.add(MapEntry(name, _text(_json(name, value), contentType)));
      case Map<Object?, Object?>() when contentType != null:
        throw ArgumentError.value(
          value,
          name,
          'An object part cannot be sent as "$contentType": only JSON '
          'media types carry an object',
        );
      case Map<Object?, Object?>():
        data.files.add(
          MapEntry(name, _text(_json(name, value), 'application/json')),
        );
      default:
        _addScalar(data, name, _scalar(name, value), contentType);
    }
  }

  static void _addScalar(
    FormData data,
    String name,
    String text,
    String? contentType,
  ) {
    if (contentType != null) {
      data.files.add(MapEntry(name, _text(text, contentType)));
    } else if (data.files.isEmpty) {
      data.fields.add(MapEntry(name, text));
    } else {
      data.files.add(MapEntry(name, _text(text, 'text/plain')));
    }
  }

  static MultipartFile _text(String text, String contentType) =>
      MultipartFile.fromString(
        text,
        contentType: DioMediaType.parse(contentType),
      );

  /// The text of a scalar JSON value of a part.
  static String _scalar(String name, Object? value) => switch (value) {
    final String text => text,
    final bool flag => '$flag',
    final num number when number.isFinite => '$number',
    _ => throw _notAPart(name, value, 'not a finite JSON scalar'),
  };

  /// The JSON text of [value], which must be made of JSON values only.
  static String _json(String name, Object? value) {
    if (!_isJson(value)) throw _notAPart(name, value, 'not JSON');
    return jsonEncode(value);
  }

  static bool _isJson(Object? value) => switch (value) {
    null || String() || bool() => true,
    final num number => number.isFinite,
    final List<Object?> items => items.every(_isJson),
    final Map<Object?, Object?> map =>
      map.keys.every((key) => key is String) && map.values.every(_isJson),
    _ => false,
  };

  static ArgumentError _notAPart(String name, Object? value, String why) =>
      ArgumentError.value(
        value,
        name,
        'Cannot be sent as a multipart part ($why); convert values with '
        'toJson',
      );
}
