import 'dart:convert';

/// Turns values from a spec into Dart source: string literals, constants,
/// interpolations and doc comment text, escaped for every place they go.
final class DartCode {
  /// Creates the helper.
  const DartCode();

  /// [value] as a single-quoted Dart string literal: `\`, `'` and `$` are
  /// escaped, and so are line breaks, tabs, control characters and lone
  /// surrogates, which would break the line or the file's encoding.
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
        (>= 0xd800 && <= 0xdfff) => '\\u{${unit.toRadixString(16)}}',
        _ => String.fromCharCode(unit),
      });
    }
    out.write("'");
    return out.toString();
  }

  /// [value], a JSON scalar from the spec, as a Dart constant: a string
  /// literal, a number, `true`, `false` or `null`.
  String literal(Object? value) => switch (value) {
    final String text => string(text),
    final int number => '$number',
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

  /// [text] as the lines of a doc comment, without the `///`: Markdown
  /// that would be read as code or HTML is escaped (`[`, `]`, `<`, `>`,
  /// `\`), control characters are dropped, and each line is wrapped at
  /// [width] characters except inside fenced code blocks.
  List<String> docLines(String text, int width) {
    final lines = <String>[];
    var fenced = false;
    for (final raw in text.replaceAll('\r\n', '\n').split('\n')) {
      final line = raw.trimRight().replaceAll(_control, '');
      if (line.trimLeft().startsWith('```')) {
        fenced = !fenced;
        lines.add(line);
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

  static final _control = RegExp('[\x00-\x08\x0b-\x1f\x7f]');
  static final _special = RegExp(r'[\\\[\]<>]');

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
    final words = line.trimLeft().split(' ');
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
