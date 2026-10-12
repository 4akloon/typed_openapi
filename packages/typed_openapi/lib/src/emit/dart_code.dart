import 'dart:convert';

/// Turns values from a spec into Dart source: string literals, constants,
/// interpolations and doc comment text, escaped for every place they go.
final class DartCode {
  /// Creates the helper.
  const DartCode();

  /// [value] as a single-quoted Dart string literal: `\`, `'` and `$` are
  /// escaped, and so are line breaks, tabs, control characters, lone
  /// surrogates, which would break the line or the file's encoding, and the
  /// bidirectional controls, which could reorder the code on screen.
  String string(String value) {
    final out = StringBuffer("'");
    for (final unit in value.runes) {
      out.write(switch (unit) {
        0x5c => r'\\',
        0x27 => r"\'",
        0x24 => r'\$',
        0x0a => r'\n',
        0x0d => r'\r',
        0x09 => r'\t',
        < 0x20 ||
        0x7f ||
        0x2028 ||
        0x2029 ||
        (>= 0x202a && <= 0x202e) ||
        (>= 0x2066 && <= 0x2069) ||
        (>= 0xd800 && <= 0xdfff) => '\\u{${unit.toRadixString(16)}}',
        _ => String.fromCharCode(unit),
      });
    }
    out.write("'");
    return out.toString();
  }

  /// [value], a JSON scalar from the spec, as a Dart constant: a string
  /// literal, a number, `true`, `false` or `null`. A number that is not
  /// finite has no literal: JSON has none and the parser reports it, so it
  /// is a [StateError].
  String literal(Object? value) => switch (value) {
    final String text => string(text),
    final int number => '$number',
    final double number when !number.isFinite => throw StateError(
      'The number $number has no Dart literal.',
    ),
    final double number =>
      number == number.roundToDouble() ? number.toStringAsFixed(1) : '$number',
    final bool flag => '$flag',
    null => 'null',
    _ => string(jsonEncode(value)),
  };

  /// The interpolation of the identifier [name] in a string literal:
  /// `$name`, or `${name}` when the name has a `$` (`$$2fa` would not
  /// parse).
  String interpolate(String name) =>
      name.contains(r'$') ? '\${$name}' : '\$$name';

  /// [text] as the text of a code span inside one line of a doc comment
  /// that the caller writes: line breaks become spaces, control characters
  /// and bidirectional controls are dropped, a lone surrogate becomes
  /// U+FFFD and a backtick becomes `'`, so the text cannot leave the line
  /// or end the span.
  String docSpan(String text) => _clean(
    text,
  ).replaceAll(_lineBreaks, ' ').replaceAll(_dropped, '').replaceAll('`', "'");

  /// The JSON encoding of [value] as a code span for a doc comment; a
  /// backtick inside is the JSON escape `\u0060`, so the span never ends
  /// early.
  String jsonSpan(Object? value) =>
      '`${docSpan(jsonEncode(value).replaceAll('`', r'\u0060'))}`';

  /// [text] as the lines of a doc comment, without the `///`: Markdown
  /// that would be read as code or HTML is escaped (`[`, `]`, `<`, `>`,
  /// `\`, and `{` of a doc directive such as `{@link}`), control characters
  /// and bidirectional controls are dropped, a lone surrogate becomes
  /// U+FFFD, a lone `\r` and the Unicode line separators end a line, and each line is wrapped at [width]
  /// characters except inside fenced code blocks.
  List<String> docLines(String text, int width) {
    final lines = <String>[];
    var fenced = false;
    for (final raw in _clean(text).replaceAll(_lineBreak, '\n').split('\n')) {
      final line = raw.replaceAll(_dropped, '').trimRight();
      if (fenced ? _fenceClose.hasMatch(line) : _fenceOpen.hasMatch(line)) {
        fenced = !fenced;
        lines.add(line.trim().isEmpty ? line : line.trimRight());
        continue;
      }
      if (fenced) {
        lines.add(line);
        continue;
      }
      lines.addAll(_wrap(_escapeDoc(line), width < 20 ? 20 : width));
    }
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    while (lines.isNotEmpty && lines.first.isEmpty) {
      lines.removeAt(0);
    }
    if (fenced) lines.add('```');
    return lines;
  }

  static String _clean(String text) =>
      text.replaceAll(_loneSurrogate, '\uFFFD');

  static final _lineBreaks = RegExp('[\r\n\u2028\u2029\u0085]+');
  static final _lineBreak = RegExp('\r\n?|[\u2028\u2029\u0085]');
  static final _dropped = RegExp(
    '[\x00-\x08\x0b-\x1f\x7f\u202a-\u202e\u2066-\u2069]',
  );
  static final _loneSurrogate = RegExp(
    '[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]',
  );
  static final _fenceOpen = RegExp(r'^\s*```[^`]*$');
  static final _fenceClose = RegExp(r'^\s*```+\s*$');
  static final _special = RegExp(r'[\\\[\]<>]|\{(?=@)');

  /// Escapes [line] outside its code spans: a span shows its text as it
  /// is, so an escape there would show too. A line with an unpaired
  /// backtick has no spans.
  static String _escapeDoc(String line) {
    final parts = line.split('`');
    if (parts.length.isEven) {
      return line.replaceAllMapped(_special, (m) => '\\${m[0]}');
    }
    return [
      for (final (i, part) in parts.indexed)
        if (i.isEven)
          part.replaceAllMapped(_special, (m) => '\\${m[0]}')
        else
          part,
    ].join('`');
  }

  static List<String> _wrap(String line, int width) {
    if (line.length <= width) return [line];
    final indent = RegExp('^ *').stringMatch(line)!;
    final words = line.trimLeft().split(' ').where((w) => w.isNotEmpty);
    final out = <String>[];
    var current = indent;
    for (final word in words) {
      if (current.trim().isEmpty) {
        current = '$indent$word';
      } else if (current.length + 1 + word.length <= width) {
        current = '$current $word';
      } else {
        out.add(current);
        current = '$indent$word';
      }
    }
    out.add(current);
    return out;
  }
}
