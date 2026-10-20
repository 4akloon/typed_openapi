import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/mapping.dart';

void main() {
  IrFixture spec(String branches) => IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Color: {type: string, enum: [red, green]}
    Level: {type: integer, enum: [1, 2]}
    Cat: {type: object, required: [kind], properties: {kind: {const: cat}}}
    Pet:
      oneOf:
$branches
      discriminator: {propertyName: kind}
''');

  test('a non-object variant of a JSON type an earlier one has is TOA458', () {
    final fixture = spec(r'''
        - {type: string}
        - $ref: '#/components/schemas/Color'
        - $ref: '#/components/schemas/Cat'
''');
    mapComponents(fixture, ['Pet']);
    final reports = fixture.reportedOf(DiagnosticCode.unionJsonTypeShadowed);
    expect(reports, hasLength(1));
    expect(reports.single.severity.name, 'info');
    expect(reports.single.pointer?.value, '#/components/schemas/Pet/oneOf/1');
    expect(reports.single.message, contains('string'));
  });

  test('integer and number are told apart, and objects are not reported', () {
    final fixture = spec(r'''
        - {type: number}
        - {type: integer}
        - $ref: '#/components/schemas/Level'
        - $ref: '#/components/schemas/Cat'
        - {type: object, properties: {kind: {const: dog}}}
''');
    mapComponents(fixture, ['Pet']);
    final reports = fixture.reportedOf(DiagnosticCode.unionJsonTypeShadowed);
    expect(reports.map((d) => d.pointer?.value), [
      '#/components/schemas/Pet/oneOf/2',
    ]);
  });

  test('a union without a discriminator reports nothing here', () {
    final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Color: {type: string, enum: [red, green]}
    Pet:
      oneOf:
        - {type: string}
        - $ref: '#/components/schemas/Color'
''');
    mapComponents(fixture, ['Pet']);
    expect(fixture.reportedOf(DiagnosticCode.unionJsonTypeShadowed), isEmpty);
  });
}
