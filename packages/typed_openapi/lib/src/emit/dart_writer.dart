import 'dart_code.dart';

/// Lays out generated Dart code: lines with two-space indentation, doc
/// comments, and lists that stay on one line when they fit in [width] and
/// take a line per item, with a trailing comma, when they do not.
///
/// The layout is the generator's own, close to `dart format` but not the
/// same: generated files start with `// dart format off`.
final class DartWriter {
  /// Creates a writer that wraps at [width] characters.
  DartWriter(this.width);

  /// The line width.
  final int width;

  static const _code = DartCode();
  final StringBuffer _out = StringBuffer();
  int _depth = 0;

  /// The current indentation.
  String get indent => '  ' * _depth;

  /// Writes [text] on a line of its own at the current indentation; an
  /// empty line has no spaces. [text] has no line break.
  void line([String text = '']) {
    assert(!text.contains('\n'), 'a line cannot hold a line break: $text');
    if (text.isEmpty) {
      _out.writeln();
    } else {
      _out.writeln('$indent$text');
    }
  }

  /// Runs [body] one level deeper.
  void indented(void Function() body) {
    _depth++;
    try {
      body();
    } finally {
      _depth--;
    }
  }

  /// Writes `head {`, [body] one level deeper, and `}`.
  void block(String head, void Function() body) {
    line('$head {');
    indented(body);
    line('}');
  }

  /// Writes [text] as a doc comment; nothing when it is null or empty.
  void doc(String? text) {
    if (text == null) return;
    for (final line in _code.docLines(text, width - indent.length - 4)) {
      this.line(line.isEmpty ? '///' : '/// $line');
    }
  }

  /// Writes [open], the [items] separated by `, ` and [close] on one line
  /// when it fits, else [open], each item and a comma on a line one level
  /// deeper, and [close]. No items give `open` and `close` together.
  void list(String open, List<String> items, String close) {
    final flat = '$open${items.join(', ')}$close';
    if (items.isEmpty || indent.length + flat.length <= width) {
      line(flat);
      return;
    }
    line(open);
    indented(() {
      for (final item in items) {
        line('$item,');
      }
    });
    line(close);
  }

  /// Writes `head` and an expression of [operands] joined by [operator]:
  /// on one line when it fits, else one operand per line, indented by two
  /// levels after the head line (`head\n    a &&\n    b;`).
  void chain(String head, List<String> operands, String operator) {
    final flat = '$head ${operands.join(' $operator ')};';
    if (indent.length + flat.length <= width) {
      line(flat);
      return;
    }
    line(head);
    indented(() {
      indented(() {
        for (final (i, operand) in operands.indexed) {
          line(i == operands.length - 1 ? '$operand;' : '$operand $operator');
        }
      });
    });
  }

  /// The code written so far.
  String get text => _out.toString();
}
