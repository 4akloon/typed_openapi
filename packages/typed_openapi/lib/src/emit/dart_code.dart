import 'dart:convert';

/// Turns values from a spec into Dart source: string literals, constants,
/// interpolations and doc comment text, escaped for every place they go.
final class DartCode {
  /// Creates the helper.
  const DartCode();

  /// [value] as a single-quoted Dart string literal: `\`, `'` and `$` are
  /// escaped, and so are line breaks (also U+0085, U+2028 and U+2029, which
  /// other tools read as such), tabs, control characters, lone
  /// surrogates, which would break the line or the file's encoding, and the
  /// bidirectional controls, which could reorder the code on screen.
  String string(String value) => "'${escaped(value)}'";

  /// [value] as the text between the quotes of [string], for a literal that
  /// has other parts, such as an interpolation of its own.
  String escaped(String value) {
    final out = StringBuffer();
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
        0x85 ||
        0x2028 ||
        0x2029 ||
        0x061c ||
        0x200e ||
        0x200f ||
        (>= 0x202a && <= 0x202e) ||
        (>= 0x2066 && <= 0x2069) ||
        (>= 0xd800 && <= 0xdfff) => '\\u{${unit.toRadixString(16)}}',
        _ => String.fromCharCode(unit),
      });
    }
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
  /// U+FFFD, a lone `\r` and the Unicode line separators end a line, and
  /// each line is wrapped at [width] characters except inside fenced code
  /// blocks, where only the `{` of a directive is escaped. A code span is
  /// never broken across lines.
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
        // Markdown shows a fenced line as it is, but dartdoc expands a
        // directive there too.
        lines.add(line.replaceAll('{@', r'\{@'));
        continue;
      }
      // A code span stays on one line: the analyzer reads the text of a
      // span that starts on the line before as Markdown.
      lines.addAll(proseLines(_escapeDoc(line), width));
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

  /// [text], the generator's own sentence (not a spec string: it keeps
  /// `[Name]` references and backticks as they are), wrapped at [width]
  /// characters.
  ///
  /// A code span is never broken across lines: the analyzer reads a doc
  /// directive (`{@template}`) inside a span that starts on the previous
  /// line as a directive.
  List<String> proseLines(String text, int width) {
    // Spaces inside a code span are held back from `_wrap`, then restored.
    const held = '\u0000';
    final spans = _spans(text);
    final joined = StringBuffer();
    var written = 0;
    for (final (:start, :end) in spans) {
      joined
        ..write(text.substring(written, start))
        ..write(text.substring(start, end).replaceAll(' ', held));
      written = end;
    }
    joined.write(text.substring(written));
    return [
      for (final line in _wrap('$joined', width < 20 ? 20 : width))
        line.replaceAll(held, ' '),
    ];
  }

  static String _clean(String text) =>
      text.replaceAll(_loneSurrogate, '\uFFFD');

  static final _lineBreaks = RegExp('[\r\n\u2028\u2029\u0085]+');
  static final _lineBreak = RegExp('\r\n?|[\u2028\u2029\u0085]');
  static final _dropped = RegExp(
    '[\x00-\x08\x0b-\x1f\x7f\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069]',
  );
  static final _loneSurrogate = RegExp(
    '[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]',
  );
  static final _fenceOpen = RegExp(r'^\s*```[^`]*$');
  static final _fenceClose = RegExp(r'^\s*```+\s*$');
  static final _special = RegExp(r'[\\\[\]<>]|\{(?=@)');

  /// The text inside the code spans of [text] as `(start, end)` indexes: the
  /// backtick runs are paired, the first with the second, the third with the
  /// fourth. A run of any length closes a span, so a stray second backtick
  /// at the end of a span does not shift the spans after it. A last run with
  /// no partner opens nothing.
  static List<({int start, int end})> _spans(String text) {
    final runs = _backticks.allMatches(text).toList();
    return [
      for (var i = 0; i + 1 < runs.length; i += 2)
        (start: runs[i].end, end: runs[i + 1].start),
    ];
  }

  static final _backticks = RegExp('`+');

  /// Escapes [line] outside its code spans: a span shows its text as it
  /// is, so an escape there would show too. A line with an unpaired
  /// backtick has no spans.
  static String _escapeDoc(String line) {
    final runs = _backticks.allMatches(line).length;
    String escape(String text) =>
        text.replaceAllMapped(_special, (m) => '\\${m[0]}');
    if (runs.isOdd) return escape(line);
    final result = StringBuffer();
    var written = 0;
    for (final (:start, :end) in _spans(line)) {
      result
        ..write(escape(line.substring(written, start)))
        ..write(line.substring(start, end));
      written = end;
    }
    return (result..write(escape(line.substring(written)))).toString();
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
