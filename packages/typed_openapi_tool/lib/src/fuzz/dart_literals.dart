/// Finds the string literals of Dart source that the fuzz evaluates: every
/// single or double quoted literal, raw or not, one or three quotes, that
/// has no interpolation. Comments are skipped; an interpolation `${...}` is
/// scanned as code, so literals inside it are found too.
///
/// The source is generated code that passes the analyzer, so the scanner
/// needs no error recovery.
final class DartLiterals {
  /// Creates the scanner of [_source].
  DartLiterals(this._source);

  final String _source;
  var _at = 0;
  final _found = <String>[];

  /// The text of each literal without interpolation, in source order.
  List<String> scan() {
    _code(untilBrace: false);
    return _found;
  }

  void _code({required bool untilBrace}) {
    var depth = 0;
    while (_at < _source.length) {
      final char = _source[_at];
      if (_source.startsWith('//', _at)) {
        final end = _source.indexOf('\n', _at);
        _at = end < 0 ? _source.length : end;
      } else if (_source.startsWith('/*', _at)) {
        final end = _source.indexOf('*/', _at + 2);
        _at = end < 0 ? _source.length : end + 2;
      } else if (char == "'" || char == '"') {
        _string(raw: _at > 0 && _source[_at - 1] == 'r' && _isRawPrefix());
      } else {
        _at++;
        if (char == '{') depth++;
        if (char != '}') continue;
        if (depth == 0 && untilBrace) return;
        depth--;
      }
    }
  }

  bool _isRawPrefix() =>
      _at < 2 || !RegExp(r'[\w$]').hasMatch(_source[_at - 2]);

  void _string({required bool raw}) {
    final start = raw ? _at - 1 : _at;
    final quote =
        _source.startsWith("'''", _at) || _source.startsWith('"""', _at)
        ? _source.substring(_at, _at + 3)
        : _source[_at];
    _at += quote.length;
    var interpolated = false;
    while (!_source.startsWith(quote, _at)) {
      final char = _source[_at];
      if (!raw && char == r'\') {
        _at += 2;
      } else if (!raw && char == r'$') {
        interpolated = true;
        _at++;
        if (_source[_at] == '{') {
          _at++;
          _code(untilBrace: true);
        }
      } else {
        _at++;
      }
    }
    _at += quote.length;
    if (!interpolated) _found.add(_source.substring(start, _at));
  }
}
