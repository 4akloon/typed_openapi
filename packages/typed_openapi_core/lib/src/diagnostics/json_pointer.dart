/// An RFC 6901 JSON Pointer in URI-fragment form, such as
/// `#/paths/~1users/get`.
///
/// Tokens are escaped (`~` → `~0`, `/` → `~1`) but not percent-encoded, so
/// pointers stay readable in diagnostics.
extension type const JsonPointer._(String value) {
  /// Parses a pointer in `#` or `#/...` form.
  ///
  /// Throws a [FormatException] for any other input.
  factory JsonPointer.parse(String value) {
    if (value != '#' && !value.startsWith('#/')) {
      throw FormatException('A JSON pointer must start with "#/".', value);
    }
    return JsonPointer._(value);
  }

  /// The pointer to the document root.
  static const JsonPointer root = JsonPointer._('#');

  /// The pointer to [token] (a property name or a list index) under this one.
  JsonPointer child(Object token) =>
      JsonPointer._('$value/${_escape(token.toString())}');

  /// The unescaped reference tokens, outermost first.
  List<String> get tokens => value == '#'
      ? const []
      : [for (final token in value.substring(2).split('/')) _unescape(token)];

  static String _escape(String token) =>
      token.replaceAll('~', '~0').replaceAll('/', '~1');

  static String _unescape(String token) =>
      token.replaceAll('~1', '/').replaceAll('~0', '~');
}
