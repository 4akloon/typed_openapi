/// The text of a media type, such as `application/json; charset=utf-8`.
extension type const MediaTypeText(String value) {
  /// Whether the type names JSON: `application/json` or a `+json` type, with
  /// or without parameters.
  bool get isJson {
    final type = value.split(';').first.trim().toLowerCase();
    return type == 'application/json' || type.endsWith('+json');
  }
}
