/// The text of a media type, such as `application/json; charset=utf-8`.
///
/// This is the one definition of a JSON media type the generator uses, for
/// the kind of a body and for the encoding of a part. It is the runtime's
/// (`MediaTypeText`): `text/json` is JSON, as Dio reads it.
extension type const MediaTypeName(String value) {
  /// The type and subtype in lower case, without parameters.
  String get base => value.split(';').first.trim().toLowerCase();

  /// Whether the type names JSON: `application/json`, `text/json` or a
  /// `+json` type.
  bool get isJson =>
      base == 'application/json' ||
      base == 'text/json' ||
      base.endsWith('+json');
}
