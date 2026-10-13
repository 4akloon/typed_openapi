/// Checks that spec text stays in its sink (spec decision 5, check 3): no
/// line of generated code starts with text a spec string smuggled out of
/// its comment or literal, the code holds no raw line break other than
/// `\n` and no bidirectional control, and the report holds no raw control
/// character.
final class LeakCheck {
  /// Creates the check.
  const LeakCheck();

  /// Characters that must never be raw in code: C0 controls but `\t` and `\n`, DEL,
  /// U+0085, U+2028, U+2029 and the bidirectional controls.
  static final _unsafeInCode = RegExp(
    r'[\x00-\x08\x0b-\x1f\x7f\u0085\u2028\u2029'
    r'\u202a-\u202e\u2066-\u2069\u200e\u200f\u061c]',
  );

  /// A line that the fuzz's hostile texts would start after an escape.
  static final _smuggled = RegExp(r'^\s*(?:injected|void injected)');

  /// The problems of the files [files] of the client [client].
  List<String> code(String client, Map<String, String> files) => [
    for (final MapEntry(key: path, value: text) in files.entries) ...[
      if (_unsafeInCode.firstMatch(text) case final m?)
        '$client/$path: a raw U+${_hex(m[0] ?? '')} in the code.',
      for (final line in text.split('\n'))
        if (_smuggled.hasMatch(line))
          '$client/$path: spec text left its sink: $line',
    ],
  ];

  /// A workflow command a CI log would run if a spec line reached it raw.
  static final _command = RegExp('^::[a-z-]+::', multiLine: true);

  /// The problems of the text report [report].
  List<String> report(String report) => [
    if (_unsafeInCode.firstMatch(report) case final m?)
      'The report holds a raw U+${_hex(m[0] ?? '')}.',
    if (_command.hasMatch(report))
      'The report holds a line that starts like a workflow command.',
  ];

  static String _hex(String char) =>
      char.codeUnitAt(0).toRadixString(16).toUpperCase().padLeft(4, '0');
}
