import 'dart:convert';
import 'dart:typed_data';

import 'encoded_body.dart';
import 'file_upload.dart';
import 'media_type_text.dart';
import 'multipart_body.dart';
import 'parsed_media_type.dart';

/// One part on the wire: its header lines, its content (bytes or a file)
/// and whether it is a plain field, without a `Content-Type`.
typedef _WirePart = ({
  String head,
  Uint8List? bytes,
  FileUpload? file,
  bool isField,
});

/// Writes a [MultipartBody] as `multipart/form-data` bytes, in the order of
/// its parts, byte for byte as Dio's `FormData` wrote it.
///
/// A plain text part (a value without a media type) has no `Content-Type`
/// while no file or typed part precedes it, the usual shape (values first,
/// files last). After the first file or typed part, text parts are sent as
/// `text/plain; charset=utf-8` parts. A file part without a media type of
/// its own or of the spec is `application/octet-stream`.
final class MultipartEncoder {
  /// Creates the encoder of one request, whose parts are separated by
  /// [boundary].
  const MultipartEncoder(this.boundary);

  /// The boundary between the parts.
  final String boundary;

  /// The `Content-Type` of the body.
  String get contentType => 'multipart/form-data; boundary=$boundary';

  /// The bytes of [body].
  ///
  /// Throws [ArgumentError] for a value that cannot be a part (not a finite
  /// JSON scalar, a list inside a list, a non-JSON value in a JSON part, an
  /// object with a media type that is not JSON) and [FormatException] for a
  /// media type that is not one.
  EncodedBody encode(MultipartBody body) {
    final parts = <_WirePart>[];
    for (final part in body.parts) {
      switch (part.file) {
        case final file?:
          parts.add(_file(part.name, file, part.contentType));
        case null:
          _addValue(parts, part.name, part.value, part.contentType);
      }
    }
    var length = utf8.encode('--$boundary--\r\n').length;
    for (final part in parts) {
      length +=
          utf8.encode('--$boundary\r\n${part.head}').length +
          (part.bytes?.length ?? part.file?.length ?? 0) +
          2;
    }
    return EncodedBody.stream(
      _write(parts),
      length: length,
      contentType: contentType,
    );
  }

  Stream<List<int>> _write(List<_WirePart> parts) async* {
    for (final part in parts) {
      yield utf8.encode('--$boundary\r\n${part.head}');
      if (part.bytes ?? part.file?.bytes case final bytes?) {
        yield bytes;
      } else if (part.file?.stream case final stream?) {
        yield* stream;
      }
      yield const [13, 10];
    }
    yield utf8.encode('--$boundary--\r\n');
  }

  /// A file part: the file's own media type wins over the spec's.
  static _WirePart _file(String name, FileUpload file, String? specType) {
    final type = file.contentType ?? specType;
    final contentType = type == null
        ? 'application/octet-stream'
        : '${ParsedMediaType.parse(type)}';
    final filename = switch (file.filename) {
      final filename? => '; filename="${_escape(filename)}"',
      null => '',
    };
    return (
      head:
          'content-disposition: form-data; name="${_escape(name)}"$filename'
          '\r\ncontent-type: $contentType\r\n\r\n',
      bytes: null,
      file: file,
      isField: false,
    );
  }

  /// Adds the parts of [value]: none for `null`, a part per item of a list,
  /// JSON for an object or a JSON [contentType], text otherwise.
  static void _addValue(
    List<_WirePart> parts,
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
          _addValue(parts, name, item, contentType);
        }
      case _ when contentType != null && MediaTypeText(contentType).isJson:
        parts.add(_text(name, _json(name, value), contentType));
      case Map<Object?, Object?>() when contentType != null:
        throw ArgumentError.value(
          value,
          name,
          'An object part cannot be sent as "$contentType": only JSON '
          'media types carry an object',
        );
      case Map<Object?, Object?>():
        parts.add(_text(name, _json(name, value), 'application/json'));
      default:
        parts.add(_scalar(parts, name, _scalarText(name, value), contentType));
    }
  }

  /// A scalar part: a plain field while only plain fields precede it.
  static _WirePart _scalar(
    List<_WirePart> parts,
    String name,
    String text,
    String? contentType,
  ) {
    if (contentType != null) return _text(name, text, contentType);
    if (parts.any((part) => !part.isField)) {
      return _text(name, text, 'text/plain');
    }
    return (
      head: 'content-disposition: form-data; name="${_escape(name)}"\r\n\r\n',
      bytes: utf8.encode(text),
      file: null,
      isField: true,
    );
  }

  /// A text part in the charset of [contentType] (UTF-8 when it names none
  /// or one that is unknown), which then names that charset.
  static _WirePart _text(String name, String text, String contentType) {
    final type = ParsedMediaType.parse(contentType);
    final encoding =
        Encoding.getByName(type.parameter('charset') ?? 'utf-8') ?? utf8;
    final named = type.withParameter('charset', encoding.name);
    return (
      head:
          'content-disposition: form-data; name="${_escape(name)}"'
          '\r\ncontent-type: $named\r\n\r\n',
      bytes: Uint8List.fromList(encoding.encode(text)),
      file: null,
      isField: false,
    );
  }

  /// [value] as Dio wrote it into a header: line breaks and quotes cannot
  /// end the header line or the quoted name.
  static String _escape(String value) =>
      value.replaceAll(RegExp('\r\n|\r|\n'), '%0D%0A').replaceAll('"', '%22');

  /// The text of a scalar JSON value of a part.
  static String _scalarText(String name, Object? value) => switch (value) {
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
