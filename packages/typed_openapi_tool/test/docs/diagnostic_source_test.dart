import 'package:test/test.dart';
import 'package:typed_openapi_core/typed_openapi_core.dart';
import 'package:typed_openapi_tool/src/docs/diagnostic_source.dart';

void main() {
  DiagnosticSource source(String comment, {String entry = 'parseError'}) =>
      DiagnosticSource('''
enum DiagnosticCode {
$comment
  $entry('TOA001', 'parse-error', .error),

  const DiagnosticCode(this.id, this.slug, this.defaultSeverity);
}
''');

  test('a comment is read as meaning, example and fix', () {
    final docs = source('''
  /// The document is not
  /// valid JSON.
  ///
  /// It stops the run.
  ///
  /// Example: A trailing
  /// comma.
  ///
  /// Fix: Remove it at the source.''').read();
    final doc = docs.docs.single;
    expect(doc.code, DiagnosticCode.parseError);
    expect(doc.meaning, [
      'The document is not valid JSON.',
      'It stops the run.',
    ]);
    expect(doc.example, 'A trailing comma.');
    expect(doc.fix, 'Remove it at the source.');
  });

  test('a missing Example or Fix is a problem', () {
    final docs = source('''
  /// Bad.
  ///
  /// Example: A comma.''').read();
    expect(docs.problems, contains('TOA001 has no "Fix:" paragraph.'));
    expect(docs.docs, isEmpty);
  });

  test('a text without a full stop is a problem', () {
    final docs = source('''
  /// Bad.
  ///
  /// Example: A comma
  ///
  /// Fix: Remove it.''').read();
    expect(
      docs.problems,
      contains('TOA001: "Example:" does not end with a full stop.'),
    );
  });

  test('an entry without a comment is a problem', () {
    expect(
      source('').read().problems,
      contains('TOA001 has no doc comment.'),
    );
  });

  test('an entry the enum lacks is a problem', () {
    final docs = source('  /// Bad.', entry: 'notACode').read();
    expect(
      docs.problems,
      contains('The source has an entry "notACode" that the enum lacks.'),
    );
  });

  test('every code of the enum has a complete doc comment', () async {
    final docs = (await DiagnosticSource.load()).read();
    expect(docs.problems, isEmpty);
    expect(docs.docs.map((d) => d.code), DiagnosticCode.values);
  });

  test('the migrated fixes keep the advice of the old table', () async {
    final docs = (await DiagnosticSource.load()).read();
    String fix(DiagnosticCode code) =>
        docs.docs.singleWhere((d) => d.code == code).fix;
    expect(fix(DiagnosticCode.duplicateKey), 'Remove one of the keys.');
    expect(
      fix(DiagnosticCode.eventStreamNotGenerated),
      startsWith('Offer `text/event-stream` on every success with a body'),
    );
  });
}
