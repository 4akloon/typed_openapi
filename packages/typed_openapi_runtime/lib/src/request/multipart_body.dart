import 'file_upload.dart';

/// A part of a `multipart/form-data` body.
final class MultipartPart {
  /// A value part: [value] is the JSON form of a property (`toJson`
  /// applied). A string, number or boolean is sent as text; an object as
  /// JSON; each item of a list as a part of its own with this [name]; `null`
  /// is not sent. [contentType] is the `encoding` of the spec for the
  /// property: a JSON media type sends any value as JSON, another one is the
  /// media type of the text. Sending throws [ArgumentError] for a value that
  /// cannot be a part (a number that is not finite, an object that is not
  /// JSON, a list inside a list) and for an object with a media type that is
  /// not JSON.
  const MultipartPart.value(this.name, this.value, {this.contentType})
    : file = null;

  /// A file part; [contentType], the spec's `encoding` for the property,
  /// is the media type when [file] has none.
  const MultipartPart.file(
    this.name,
    FileUpload this.file, {
    this.contentType,
  }) : value = null;

  /// The name of the part (the property name).
  final String name;

  /// The JSON form of a value part.
  final Object? value;

  /// The file of a file part.
  final FileUpload? file;

  /// The media type of the part, from the spec's `encoding`.
  final String? contentType;
}

/// A `multipart/form-data` body: its parts in order. The request sender
/// builds the HTTP client's form data from it for each request and sends the
/// parts in this order. A text part that follows a file or a part with a
/// media type is sent with `Content-Type: text/plain; charset=utf-8`.
final class MultipartBody {
  /// Creates the body.
  const MultipartBody(this.parts);

  /// The body of [json], the JSON of a body whose schema has no parts of
  /// its own: a value part for each property, in order; `null` has none.
  /// Anything but an object throws [ArgumentError].
  factory MultipartBody.fromJson(Object? json) => switch (json) {
    null => const MultipartBody([]),
    final Map<String, Object?> object => MultipartBody([
      for (final MapEntry(:key, :value) in object.entries)
        MultipartPart.value(key, value),
    ]),
    final other => throw ArgumentError.value(
      other,
      'json',
      'A multipart body must be a JSON object',
    ),
  };

  /// The parts, in order.
  final List<MultipartPart> parts;
}
