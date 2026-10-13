import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/github_actions_reporter.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/diagnostics/message_text.dart';
import 'package:typed_openapi/src/diagnostics/reporters.dart';

/// A name a hostile spec could use: an escape sequence, a line that is a
/// workflow command, and a percent escape.
final _hostile =
    '\u001b[31mRED\n::error::pwned\r\n%0A ${String.fromCharCode(0x202e)}';

/// Whether [text] has a control character (but a line break is allowed when
/// [lineBreaks] is).
bool _hasControls(String text, {bool lineBreaks = false}) => text.runes.any(
  (r) => (r < 0x20 && !(lineBreaks && r == 0x0A)) || r == 0x7F || r == 0x202E,
);

void main() {
  group('MessageText.quote', () {
    test('keeps a plain name between quotes', () {
      expect(MessageText.quote('delta'), '"delta"');
    });

    test('escapes quotes, backslashes and line breaks', () {
      expect(MessageText.quote('a"b\\c\nd'), r'"a\"b\\c\nd"');
    });

    test('writes controls and bidi marks as code points', () {
      expect(
        MessageText.quote(
          String.fromCharCodes([
            0x1b,
            0x7f,
            0x200e,
            0x200f,
            0x61c,
            0x202e,
            0x2028,
          ]),
        ),
        r'"\u{1b}\u{7f}\u{200e}\u{200f}\u{61c}\u{202e}\u{2028}"',
      );
    });

    test('leaves text beyond ASCII alone', () {
      expect(MessageText.quote('подія 🎉'), '"подія 🎉"');
    });
  });

  group('the reporters with a hostile message', () {
    final bag = DiagnosticBag()
      ..report(
        .eventNameDuplicate,
        'Event $_hostile twice.',
        fix: 'Rename $_hostile.',
      );

    test('the text report has no control character in the message', () {
      final text = const TextReporter().format(bag);
      expect(_hasControls(text, lineBreaks: true), isFalse);
      final lines = text.split('\n');
      expect(lines.where((l) => l.startsWith('::')), isEmpty);
      expect(lines.first, startsWith('warning TOA667'));
      expect(lines.first, contains(r'\n::error::pwned'));
    });

    test('the text report keeps the fix on its own lines', () {
      final text = const TextReporter().format(
        DiagnosticBag()
          ..report(.eventNameDuplicate, 'x', fix: 'First.\nSecond.'),
      );
      expect(text, contains('  fix: First.\n    Second.'));
    });

    test('the GitHub report is one command with escaped data', () {
      final text = const GitHubActionsReporter().format(bag);
      final lines = text.split('\n');
      expect(_hasControls(text, lineBreaks: true), isFalse);
      expect(lines.where((l) => l.startsWith('::')), hasLength(1));
      expect(text, contains(r'RED%0A::error::pwned\r%0A%250A'));
    });
  });

  group('the reporters with a hostile pointer and file', () {
    final pointer = JsonPointer.root
        .child('components')
        .child('schemas')
        .child('\u001b[32mp\n::error::z%0A\u200f');
    const file = 'a\n::error::f.yaml';
    final bag = DiagnosticBag()
      ..add(
        Diagnostic(
          code: .unknownKey,
          severity: .warning,
          message: 'm',
          file: file,
          pointer: pointer,
          related: [
            RelatedLocation(message: 'r', file: file, pointer: pointer),
          ],
        ),
      );

    test('the text report prints no control character or ::', () {
      final text = const TextReporter().format(bag);
      expect(_hasControls(text, lineBreaks: true), isFalse);
      expect(text.contains('\u200f'), isFalse);
      expect(text.split('\n').where((l) => l.startsWith('::')), isEmpty);
      expect(text, contains(r'  at #/components/schemas/\u{1b}[32mp\n::error'));
      expect(text, contains(r'  --> a\n::error::f.yaml'));
      expect(
        text,
        contains(r'    at #/components/schemas/\u{1b}[32mp\n::error'),
      );
    });

    test('the GitHub report prints no control character', () {
      final text = const GitHubActionsReporter().format(bag);
      expect(_hasControls(text, lineBreaks: true), isFalse);
      expect(text.contains('\u200f'), isFalse);
      expect(text.split('\n').where((l) => l.startsWith('::')), hasLength(2));
    });
  });
}
