import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';

import '../helpers/ir_fixture.dart';

/// A spec whose events are named [first] and [second] by constants (YAML
/// double-quoted scalars, so escapes work) and [second] twice.
String _spec(String first, String second) =>
    '''
openapi: 3.2.0
info: {title: t, version: "1"}
paths:
  /feed:
    get:
      operationId: watch
      responses:
        "200":
          description: ok
          content:
            text/event-stream:
              itemSchema:
                oneOf:
                  - properties: {event: {const: "$first"}}
                  - properties: {event: {const: "$second"}}
                  - properties: {event: {const: "$second"}}
''';

/// Whether [text] holds a control character or a bidirectional mark.
bool _hasHidden(String text) => text.runes.any(
  (r) =>
      r < 0x20 ||
      r == 0x7F ||
      r == 0x200E ||
      r == 0x200F ||
      r == 0x061C ||
      (r >= 0x202A && r <= 0x202E),
);

void main() {
  final hostile =
      '\\e[31mRED\\n::error::x%0A${String.fromCharCodes([0x202e, 0x200f])}';
  final marked = '\\e${String.fromCharCode(0x202e)}';
  final oneLine =
      '\\e[31mRED::error::x%0A${String.fromCharCodes([0x202e, 0x200f])}';

  test('a repeated event name is quoted in TOA667', () {
    final fixture = IrFixture(_spec('ok', oneLine))..build();
    final message = fixture
        .reportedOf(DiagnosticCode.eventNameDuplicate)
        .single
        .message;
    expect(_hasHidden(message), isFalse);
    expect(message, contains('::error::x%0A'));
    expect(message, contains(r'\u{1b}[31mRED'));
  });

  test('a name with a line break is quoted in TOA670', () {
    final fixture = IrFixture(_spec('ok', hostile))..build();
    final message = fixture
        .reportedOf(DiagnosticCode.eventNameUnreachable)
        .first
        .message;
    expect(_hasHidden(message), isFalse);
    expect(message, contains(r'\n::error::x%0A'));
    expect(message, contains(r'\u{1b}[31mRED'));
  });

  test('a name without letters is quoted in TOA668', () {
    final fixture = IrFixture(_spec('ok', marked))..build();
    final reports = fixture.reportedOf(DiagnosticCode.eventNameUnrepresentable);
    expect(reports, isNotEmpty);
    for (final report in reports) {
      expect(_hasHidden(report.message), isFalse);
      expect(report.message, contains(r'"\u{1b}\u{202e}"'));
    }
  });

  test('no message of the run holds a control character', () {
    final fixture = IrFixture(_spec(hostile, marked))..build();
    for (final d in fixture.reported) {
      expect(_hasHidden(d.message), isFalse, reason: d.code.id);
    }
  });
}
