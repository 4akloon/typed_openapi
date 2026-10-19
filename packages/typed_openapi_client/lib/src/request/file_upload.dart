import 'dart:typed_data';

/// A file a generated method sends: a binary request body, or a file part
/// of a `multipart/form-data` body.
///
/// Generated methods take a [FileUpload] instead of a type of an HTTP
/// client, so their signatures do not depend on one. [FileUpload.bytes]
/// works on every platform, the web included; [FileUpload.stream] sends the
/// data as it is read and can be sent once. A transport may buffer an upload, for
/// example in a browser, so a stream is not always streamed; for Dio see the
/// README of `typed_openapi_dio`.
final class FileUpload {
  /// A file held in memory.
  FileUpload.bytes(Uint8List this.bytes, {this.filename, this.contentType})
    : stream = null,
      length = bytes.length;

  /// A file read from [stream], which has [length] bytes. A stream can be
  /// listened to once, so the upload can be sent once.
  const FileUpload.stream(
    Stream<List<int>> this.stream, {
    required this.length,
    this.filename,
    this.contentType,
  }) : bytes = null;

  /// The content of a file held in memory.
  final Uint8List? bytes;

  /// The content of a streamed file.
  final Stream<List<int>>? stream;

  /// The size in bytes.
  final int length;

  /// The file name sent with a multipart part.
  final String? filename;

  /// The media type, such as `image/png`; it wins over the media type of the
  /// spec. A value that is not a media type makes sending throw
  /// [FormatException].
  final String? contentType;

  @override
  String toString() =>
      'FileUpload(${filename ?? 'unnamed'}, $length bytes'
      '${contentType == null ? '' : ', $contentType'})';
}
