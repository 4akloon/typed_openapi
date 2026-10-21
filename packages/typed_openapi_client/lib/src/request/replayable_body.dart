import 'file_upload.dart';
import 'multipart_body.dart';

/// Tells whether a request body can be sent more than once.
///
/// A retried opening or a reconnection sends the body again. A
/// `FileUpload.stream` is read once, so a second send would fail.
final class ReplayableBody {
  const ReplayableBody._();

  /// Whether [body] can be sent again: false for a [FileUpload] that reads a
  /// stream and for a [MultipartBody] with such a part.
  static bool isReplayable(Object? body) => switch (body) {
    FileUpload(:final stream) => stream == null,
    MultipartBody(:final parts) => parts.every(
      (part) => isReplayable(part.file),
    ),
    _ => true,
  };
}
