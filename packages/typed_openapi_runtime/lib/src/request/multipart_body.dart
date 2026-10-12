import 'file_upload.dart';

/// A part of a `multipart/form-data` body.
final class MultipartPart {
  /// A value part: [value] is the JSON form of a property (`toJson`
  /// applied). A string, number or boolean is sent as text; an object as
  /// JSON; each item of a list as a part of its own with this [name]; `null`
  /// is not sent. [contentType] is the `encoding` of the spec for the
  /// property: a JSON media type sends any value as JSON, another one is the
  /// media type of the text.
  const MultipartPart.value(this.name, this.value, {this.contentType})
    : file = null;

  /// A file part.
  const MultipartPart.file(this.name, FileUpload this.file)
    : value = null,
      contentType = null;

  /// The name of the part (the property name).
  final String name;

  /// The JSON form of a value part.
  final Object? value;

  /// The file of a file part.
  final FileUpload? file;

  /// The media type of a value part, from the spec's `encoding`.
  final String? contentType;
}

/// A `multipart/form-data` body: its parts in order. The request sender
/// builds the HTTP client's form data from it for each request.
final class MultipartBody {
  /// Creates the body.
  const MultipartBody(this.parts);

  /// The parts, in order.
  final List<MultipartPart> parts;
}
