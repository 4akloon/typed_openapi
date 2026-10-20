import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/mapping.dart';

/// A value with a quote, a backslash, a control and a bidirectional mark.
final hostile = 'a"b\\c\u001b[31m${String.fromCharCode(0x202E)}';

/// [hostile] as `MessageText.quote` writes it.
const escaped = r'"a\"b\\c\u{1b}[31m\u{202e}"';

void main() {
  final text = jsonEncode(hostile);
  const head = '''
openapi: 3.2.0
info: {title: t, version: "1"}
components:
  schemas:
    Cat: {type: object, properties: {lives: {type: integer}}}
    Dog: {type: object, properties: {bark: {type: boolean}}}
    Other: {type: object, properties: {x: {type: integer}}}
''';

  void expectEscaped(String message) {
    expect(message, contains(escaped));
    expect(message, isNot(contains(String.fromCharCode(0x202E))));
    expect(message, isNot(contains('\u001b')));
  }

  test('TOA456 writes a hostile discriminator value as an escape', () {
    final fixture = IrFixture('''
$head    Pet:
      oneOf:
        - {type: object, properties: {kind: {const: $text}}}
        - {type: object, properties: {kind: {const: $text}}}
      discriminator: {propertyName: kind}
''');
    mapComponents(fixture, ['Pet']);
    final reports = fixture.reportedOf(
      DiagnosticCode.discriminatorValueDuplicate,
    );
    expect(reports, hasLength(1));
    expectEscaped(reports.single.message);
  });

  test('a mapping to a non-variant writes a hostile key as an escape', () {
    final fixture = IrFixture('''
$head    Pet:
      oneOf:
        - \$ref: '#/components/schemas/Cat'
        - \$ref: '#/components/schemas/Dog'
      discriminator:
        propertyName: kind
        mapping: {$text: '#/components/schemas/Other'}
''');
    mapComponents(fixture, ['Pet']);
    final reports = fixture.reportedOf(
      DiagnosticCode.discriminatorMappingNotVariant,
    );
    expect(reports, hasLength(1));
    expectEscaped(reports.single.message);
  });

  test('a mapping to the base writes a hostile key as an escape', () {
    final fixture = IrFixture('''
$head    Base:
      type: object
      required: [kind]
      properties: {kind: {type: string}}
      discriminator:
        propertyName: kind
        mapping: {$text: '#/components/schemas/Base'}
    Child:
      allOf:
        - \$ref: '#/components/schemas/Base'
        - {type: object, properties: {c: {type: integer}}}
''');
    mapComponents(fixture, ['Base']);
    final reports = fixture.reportedOf(
      DiagnosticCode.discriminatorMappingNotVariant,
    );
    expect(reports, hasLength(1));
    expectEscaped(reports.single.message);
  });

  test('a default mapping that names no variant is written as an escape', () {
    final fixture = IrFixture('''
$head    Pet:
      oneOf:
        - \$ref: '#/components/schemas/Cat'
        - \$ref: '#/components/schemas/Dog'
      discriminator:
        propertyName: kind
        defaultMapping: $text
''');
    mapComponents(fixture, ['Pet']);
    final reports = fixture.reportedOf(
      DiagnosticCode.discriminatorMappingNotVariant,
    );
    expect(reports, hasLength(1));
    expectEscaped(reports.single.message);
  });

  test('TOA455 writes a hostile enum value as an escape', () {
    final fixture = IrFixture('''
$head    Name:
      anyOf:
        - {type: string}
        - {type: string, enum: [$text]}
''');
    mapComponents(fixture, ['Name']);
    final reports = fixture.reportedOf(DiagnosticCode.unionBranchSubsumed);
    expect(reports, hasLength(1));
    expect(
      reports.single.message,
      contains('\'a"b\\\\c\\u{1b}[31m\\u{202e}\''),
    );
    expect(reports.single.message, isNot(contains('\u202E')));
  });
}
