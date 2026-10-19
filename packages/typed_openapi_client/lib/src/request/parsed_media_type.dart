/// A media type read by the rules of RFC 9110 (a type, a subtype and
/// parameters), written back in one canonical form.
///
/// It reads and writes media types exactly as `package:http_parser` does
/// (which Dio used), so a part's `Content-Type` keeps its bytes: the type
/// and subtype in lower case, parameters in order with their names as
/// given, a value quoted only when it is not a token.
final class ParsedMediaType {
  const ParsedMediaType._(this.type, this.subtype, this._parameters);

  /// Reads [text]; throws [FormatException] when it is not a media type.
  factory ParsedMediaType.parse(String text) {
    final reader = _Reader(text)..skip(_whitespace);
    final type = reader.expect(_token, 'a type');
    reader.expect(RegExp('/'), '"/"');
    final subtype = reader.expect(_token, 'a subtype');
    reader.skip(_whitespace);
    final parameters = <String, (String, String)>{};
    while (reader.skip(RegExp(';'))) {
      reader.skip(_whitespace);
      final name = reader.expect(_token, 'a parameter name');
      reader.expect(RegExp('='), '"="');
      final value = reader.skip(_token)
          ? reader.last
          : _unquote(reader.expect(_quoted, 'a quoted string'));
      reader.skip(_whitespace);
      parameters[name.toLowerCase()] = (name, value);
    }
    reader.done();
    return ParsedMediaType._(
      type.toLowerCase(),
      subtype.toLowerCase(),
      parameters,
    );
  }

  /// The type in lower case, such as `text`.
  final String type;

  /// The subtype in lower case, such as `plain`.
  final String subtype;

  /// Parameters by lower-case name: the name as written and the value.
  final Map<String, (String, String)> _parameters;

  /// The value of the parameter [name] (in any case), or null.
  String? parameter(String name) => _parameters[name.toLowerCase()]?.$2;

  /// This media type with the parameter [name] set to [value]: it keeps the
  /// place of a parameter of that name and takes the new spelling.
  ParsedMediaType withParameter(String name, String value) =>
      ParsedMediaType._(type, subtype, {
        ..._parameters,
        name.toLowerCase(): (name, value),
      });

  @override
  String toString() {
    final text = StringBuffer('$type/$subtype');
    for (final (name, value) in _parameters.values) {
      text.write('; $name=');
      if (_nonToken.hasMatch(value)) {
        final escaped = value.replaceAllMapped(_escaped, (m) => '\\${m[0]}');
        text.write('"$escaped"');
      } else {
        text.write(value);
      }
    }
    return '$text';
  }

  static String _unquote(String quoted) => quoted
      .substring(1, quoted.length - 1)
      .replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1]!);

  static final RegExp _token = RegExp(
    r'[^()<>@,;:"\\/[\]?={} \t\x00-\x1F\x7F]+',
  );
  static final RegExp _nonToken = RegExp(
    r'[()<>@,;:"\\/\[\]?={} \t\x00-\x1F\x7F]',
  );
  static final RegExp _whitespace = RegExp(r'(?:(?:\r\n)?[ \t]+)*');
  static final RegExp _quoted = RegExp(r'"(?:[^"\x00-\x1F\x7F\\]|\\.)*"');
  static final RegExp _escaped = RegExp(r'["\x00-\x1F\x7F]');
}

/// Reads a string from left to right with patterns.
final class _Reader {
  _Reader(this._text);

  final String _text;
  int _position = 0;
  String _last = '';

  /// The text the last successful match read.
  String get last => _last;

  /// Reads [pattern] at the position; whether it matched.
  bool skip(RegExp pattern) {
    final match = pattern.matchAsPrefix(_text, _position);
    if (match == null) return false;
    _last = match[0]!;
    _position = match.end;
    return true;
  }

  /// Reads [pattern], or throws [FormatException] naming [what].
  String expect(RegExp pattern, String what) {
    if (!skip(pattern)) throw _error('expected $what');
    return _last;
  }

  /// Throws [FormatException] when text is left.
  void done() {
    if (_position < _text.length) throw _error('expected no more input');
  }

  FormatException _error(String message) => FormatException(
    'Invalid media type "$_text": $message',
    _text,
    _position,
  );
}
