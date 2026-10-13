import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/ir/ir.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/mapping.dart';

/// The discriminator values of each variant of the union [name] of [ir].
List<List<String>> valuesOf(ClientIr ir, String name) => [
  for (final v
      in (ir.declarations.firstWhere((d) => d.name == name) as UnionDecl)
          .variants)
    v.discriminatorValues,
];

/// A spec whose union `Tool` has the variants [variants] and the
/// discriminator [discriminator], next to the components [components].
String spec(String variants, String discriminator, String components) =>
    '''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Tool:
      oneOf:
$variants
      discriminator: $discriminator
$components''';

const _components = r'''
    FunctionTool:
      type: object
      required: [type]
      properties:
        type: {const: function}
        name: {type: string}
    FileSearch:
      allOf:
        - $ref: '#/components/schemas/Base'
        - type: object
          properties:
            type: {$ref: '#/components/schemas/FileSearchType'}
    FileSearchType: {type: string, enum: [file_search]}
    Base: {type: object, properties: {id: {type: string}}}
    Plain: {type: object, properties: {type: {type: string}}}
''';

void main() {
  test('a variant that fixes the property is selected by that value', () {
    final fixture = IrFixture(
      spec(
        r'''
        - $ref: '#/components/schemas/FunctionTool'
        - $ref: '#/components/schemas/FileSearch'
        - $ref: '#/components/schemas/Plain'
''',
        '{propertyName: type}',
        _components,
      ),
    );
    final (ir, _) = mapComponents(fixture, ['Tool']);
    expect(valuesOf(ir, 'Tool'), [
      ['function'],
      ['file_search'],
      ['Plain'],
    ]);
    final derived = fixture.reportedOf(
      DiagnosticCode.discriminatorValueDerived,
    );
    expect(
      [for (final d in derived) d.pointer?.value],
      [
        '#/components/schemas/Tool/oneOf/0',
        '#/components/schemas/Tool/oneOf/1',
      ],
    );
    expect(derived.first.severity, Severity.info);
    expect(derived.first.message, contains('"function"'));
    expect(derived.first.message, contains('"FunctionTool"'));
  });

  test('an explicit mapping wins over the constant', () {
    final fixture = IrFixture(
      spec(
        r'''
        - $ref: '#/components/schemas/FunctionTool'
        - $ref: '#/components/schemas/FileSearch'
''',
        "{propertyName: type, mapping: {fn: '#/components/schemas/FunctionTool'}}",
        _components,
      ),
    );
    final (ir, _) = mapComponents(fixture, ['Tool']);
    expect(valuesOf(ir, 'Tool'), [
      ['fn'],
      ['file_search'],
    ]);
    expect(
      fixture.reportedOf(DiagnosticCode.discriminatorValueDerived),
      hasLength(1),
    );
  });

  test('two variants that derive one value are TOA456', () {
    final fixture = IrFixture(
      spec(
        r'''
        - $ref: '#/components/schemas/FunctionTool'
        - $ref: '#/components/schemas/OtherFunction'
''',
        '{propertyName: type}',
        '$_components    OtherFunction: '
            '{type: object, properties: {type: {const: function}}}\n',
      ),
    );
    final (ir, _) = mapComponents(fixture, ['Tool']);
    expect(valuesOf(ir, 'Tool'), [
      ['function'],
      ['function'],
    ]);
    expect(
      fixture.reportedOf(DiagnosticCode.discriminatorValueDuplicate),
      hasLength(1),
    );
  });

  test('a constant equal to the component name is not reported', () {
    final fixture = IrFixture(
      spec(
        r'''
        - $ref: '#/components/schemas/Same'
        - $ref: '#/components/schemas/Plain'
''',
        '{propertyName: type}',
        '$_components    Same: '
            '{type: object, properties: {type: {const: Same}}}\n',
      ),
    );
    final (ir, _) = mapComponents(fixture, ['Tool']);
    expect(valuesOf(ir, 'Tool'), [
      ['Same'],
      ['Plain'],
    ]);
    expect(
      fixture.reportedOf(DiagnosticCode.discriminatorValueDerived),
      isEmpty,
    );
  });

  test('a value with a quote and a line break is escaped in the message', () {
    final fixture = IrFixture(
      spec(
        r'''
        - $ref: '#/components/schemas/Odd'
        - $ref: '#/components/schemas/Plain'
''',
        '{propertyName: type}',
        '$_components    Odd: {type: object, properties: '
            '{type: {const: "a\\"b\\n"}}}\n',
      ),
    );
    mapComponents(fixture, ['Tool']);
    final derived = fixture.reportedOf(
      DiagnosticCode.discriminatorValueDerived,
    );
    expect(derived, hasLength(1));
    final message = derived.single.message;
    expect(message, isNot(contains('\n')));
    expect(message, contains(r'"a\"b\n"'));
  });
}
