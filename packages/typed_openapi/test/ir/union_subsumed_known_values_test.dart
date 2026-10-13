import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/ir/ir.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/mapping.dart';
import '../helpers/union_spec.dart';

void main() {
  const head = UnionSpec.head;

  test('a field keeps the values of the branch it drops', () {
    final fixture = IrFixture('''
$head    Transcription:
      type: object
      properties:
        model:
          description: The model.
          anyOf:
            - {type: string}
            - {type: string, enum: [whisper-1, 'gpt`4', '']}
        plain: {type: string}
        three:
          anyOf:
            - {type: string}
            - {enum: [x]}
            - \$ref: '#/components/schemas/Customer'
''');
    final (ir, _) = mapComponents(fixture, ['Transcription']);
    final fields =
        (ir.declarations.firstWhere((d) => d.name == 'Transcription')
                as ModelDecl)
            .fields;
    expect(
      {for (final f in fields) f.name: f.knownValues},
      {
        'model': ['whisper-1', 'gpt`4', ''],
        'plain': <Object?>[],
        'three': ['x'],
      },
    );
  });

  test('a union that stays JsonValue lists no known values', () {
    final fixture = IrFixture('''
$head    Holder:
      type: object
      properties:
        raw:
          anyOf:
            - {type: string, maxLength: 3}
            - {enum: [abcdef]}
            - {enum: [a]}
''');
    final (ir, types) = mapComponents(fixture, ['Holder']);
    final raw =
        (ir.declarations.firstWhere((d) => d.name == 'Holder') as ModelDecl)
            .fields
            .single;
    expect(raw.valueType.code(ir.nameOf), 'JsonValue');
    expect(raw.knownValues, isEmpty);
    expect(types['Holder'], isNotNull);
  });

  test('a wrapper of a reference lists the values like the reference', () {
    final fixture = IrFixture('''
$head    Flavor:
      anyOf: [{type: string}, {enum: [sweet, sour]}]
    Holder:
      type: object
      properties:
        direct: {\$ref: '#/components/schemas/Flavor'}
        wrapped:
          allOf:
            - \$ref: '#/components/schemas/Flavor'
        described:
          allOf:
            - \$ref: '#/components/schemas/Flavor'
            - {description: Which flavor.}
        nullable:
          anyOf:
            - \$ref: '#/components/schemas/Flavor'
            - {type: 'null'}
''');
    final (ir, _) = mapComponents(fixture, ['Holder']);
    final fields =
        (ir.declarations.firstWhere((d) => d.name == 'Holder') as ModelDecl)
            .fields;
    expect(
      {for (final f in fields) f.name: f.knownValues},
      {
        for (final name in ['direct', 'wrapped', 'described', 'nullable'])
          name: ['sweet', 'sour'],
      },
    );
  });

  test('valid unions and enums report no TOA455', () {
    final fixture = IrFixture('''
$head    Color:
      anyOf: [{const: red}, {const: green}]
    Mixed:
      oneOf: [{type: string}, {type: integer}, {type: boolean}]
    Pet:
      oneOf:
        - \$ref: '#/components/schemas/Customer'
        - {type: object, properties: {kind: {const: fish}}}
      discriminator: {propertyName: kind}
''');
    mapComponents(fixture, ['Color', 'Mixed', 'Pet']);
    expect(
      fixture.codes.where((c) => c.$1 == DiagnosticCode.unionBranchSubsumed),
      isEmpty,
    );
  });
}
