/// The text of a media type, such as `application/json; charset=utf-8`.
///
/// This is the one definition of a JSON media type the runtime uses, for
/// request bodies, response bodies and multipart parts alike.
extension type const MediaTypeText(String value) {
  /// The type and subtype in lower case, without parameters.
  String get base => value.split(';').first.trim().toLowerCase();

  /// Whether the type names JSON: `application/json`, `text/json` (which
  /// Dio reads as JSON as well) or a `+json` type, with or without
  /// parameters.
  bool get isJson =>
      base == 'application/json' ||
      base == 'text/json' ||
      base.endsWith('+json');
}
