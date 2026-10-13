import 'dart_literals.dart';

/// Checks that spec text stays in its sink (spec decision 5, check 3): no
/// generated code holds a call that a spec string smuggled out of its
/// comment or literal, the code holds no raw line break other than
/// `\n` and no bidirectional control, and the report holds no raw control
/// character.
final class LeakCheck {
  /// Creates the check.
  const LeakCheck();

  /// Characters that must never be raw in code: C0 controls but `\t` and
  /// `\n`, DEL, U+0085, U+2028, U+2029 and the bidirectional controls.
  static final _unsafeInCode = RegExp(
    r'[\x00-\x08\x0b-\x1f\x7f\u0085\u2028\u2029'
    r'\u202a-\u202e\u2066-\u2069\u200e\u200f\u061c]',
  );

  /// A lone UTF-16 surrogate, which no file can hold (it is written as a
  /// replacement character).
  static final _loneSurrogate = RegExp(
    r'[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]',
  );

  /// The call that the fuzz's hostile texts make, found in code (outside
  /// every comment and literal) anywhere on a line.
  static final _smuggled = RegExp(r'\binjected\b');

  /// The problems of the files [files] of the client [client].
  List<String> code(String client, Map<String, String> files) => [
    for (final MapEntry(key: path, value: text) in files.entries) ...[
      if (_raw(text) case final char?)
        '$client/$path: a raw U+${_hex(char)} in the code.',
      ..._smuggledLines(text).map(
        (line) => '$client/$path: spec text left its sink: $line',
      ),
    ],
  ];

  /// The first character of [text] that must not be raw, or null.
  static String? _raw(String text) =>
      (_unsafeInCode.firstMatch(text) ?? _loneSurrogate.firstMatch(text))?[0];

  /// The lines of [text] where code, not a comment or a literal, calls
  /// `injected`.
  static List<String> _smuggledLines(String text) {
    final lines = text.split('\n');
    final masked = DartLiterals(text).masked().split('\n');
    return [
      for (var i = 0; i < lines.length; i++)
        if (_smuggled.hasMatch(masked[i])) lines[i].trim(),
    ];
  }

  /// A workflow command a CI log would run if a spec line reached it raw.
  static final _command = RegExp('^::[a-z-]+::', multiLine: true);

  /// The problems of the text report [report].
  List<String> report(String report) => [
    if (_raw(report) case final char?)
      'The report holds a raw U+${_hex(char)}.',
    if (_command.hasMatch(report))
      'The report holds a line that starts like a workflow command.',
  ];

  static String _hex(String char) =>
      char.codeUnitAt(0).toRadixString(16).toUpperCase().padLeft(4, '0');
}
