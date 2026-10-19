import 'dart:typed_data';

/// The bytes of a request body, its length and its `Content-Type`.
final class EncodedBody {
  /// A body held in memory.
  EncodedBody.bytes(Uint8List this._bytes, {this.contentType})
    : _stream = null,
      length = _bytes.length;

  /// A body read from [stream], which has [length] bytes.
  const EncodedBody.stream(
    Stream<List<int>> this._stream, {
    required this.length,
    this.contentType,
  }) : _bytes = null;

  /// The size of the body in bytes.
  final int length;

  /// The `Content-Type` to send, or null for none.
  final String? contentType;

  final Uint8List? _bytes;
  final Stream<List<int>>? _stream;

  /// Bytes held in memory are sent in chunks of this size, as Dio sent
  /// them, so send progress moves in steps.
  static const int chunkSize = 1024;

  /// The body as it is sent; a body read from a stream can be read once.
  Stream<List<int>> read() => switch ((_stream, _bytes)) {
    (final stream?, _) => stream,
    (_, final bytes?) => Stream.fromIterable([
      for (var start = 0; start < bytes.length; start += chunkSize)
        Uint8List.sublistView(
          bytes,
          start,
          start + chunkSize < bytes.length ? start + chunkSize : bytes.length,
        ),
    ]),
    _ => const Stream.empty(),
  };
}
