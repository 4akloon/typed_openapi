import 'package:test/test.dart';
import 'package:typed_openapi/src/config/config_loader.dart';
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/ir/ir.dart';
import 'package:typed_openapi/src/overrides/override_loader.dart';
import 'package:typed_openapi/src/overrides/override_set.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/mapping.dart';
import '../helpers/temp_dir.dart';

UnionDecl union(ClientIr ir, String name) =>
    ir.declarations.firstWhere((d) => d.name == name) as UnionDecl;

void main() {
  const head = '''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Cat: {type: object, properties: {lives: {type: integer}}}
    Dog: {type: object, properties: {bark: {type: boolean}}}
''';

  test('a discriminator dispatches; an inline variant uses its const', () {
    final fixture = IrFixture('''
$head    Pet:
      oneOf:
        - \$ref: '#/components/schemas/Cat'
        - type: object
          required: [kind]
          properties:
            kind: {const: fish}
            fins: {type: integer}
        - allOf:
            - type: object
              properties: {kind: {type: string, enum: [bird]}}
      discriminator: {propertyName: kind}
''');
    final (ir, types) = mapComponents(fixture, ['Pet']);
    expect(fixture.reported, isEmpty);
    final pet = union(ir, 'Pet');
    expect(pet.dispatch, UnionDispatch.discriminator);
    expect(pet.variants.map((v) => '${v.name} ${v.discriminatorValues}'), [
      'PetCat [Cat]',
      'PetVariant2Case [fish]',
      'PetVariant3Case [bird]',
    ]);
  });

  test('variants of different JSON types dispatch by type (R9.3)', () {
    final fixture = IrFixture('''
$head    IdOrName:
      oneOf: [{type: string, format: date-time}, {type: integer}, {type: number}]
    CatOrList:
      anyOf:
        - \$ref: '#/components/schemas/Cat'
        - {type: array, items: {type: string}}
        - {type: string, enum: [none]}
        - {type: boolean}
''');
    final (ir, types) = mapComponents(fixture, ['IdOrName', 'CatOrList']);
    expect(fixture.reported, isEmpty);
    expect(union(ir, 'IdOrName').dispatch, UnionDispatch.jsonType);
    expect(union(ir, 'IdOrName').variants.map((v) => v.name), [
      'IdOrNameDateTime',
      'IdOrNameInt',
      'IdOrNameNum',
    ]);
    expect(union(ir, 'CatOrList').dispatch, UnionDispatch.jsonType);
    expect(union(ir, 'CatOrList').variants.map((v) => v.name), [
      'CatOrListCat',
      'CatOrListList',
      'CatOrListVariant3Case',
      'CatOrListBool',
    ]);
  });

  test('a union whose variants share a JSON type is JsonValue (R9.2)', () {
    final fixture = IrFixture('''
$head    Pet:
      oneOf:
        - \$ref: '#/components/schemas/Cat'
        - \$ref: '#/components/schemas/Dog'
    Holder:
      type: object
      properties:
        pet: {\$ref: '#/components/schemas/Pet'}
        inline:
          anyOf: [{type: string}, {type: string, format: uuid}]
''');
    final (ir, types) = mapComponents(fixture, ['Holder']);
    expect(fieldsOf(ir, 'Holder'), [
      'pet(pet): JsonValue',
      'inline(inline): JsonValue',
    ]);
    expect(ir.declarations.map((d) => d.name), ['Holder']);
    expect(fixture.codes, [
      (DiagnosticCode.unionUndiscriminated, '#/components/schemas/Pet'),
      (
        DiagnosticCode.unionUndiscriminated,
        '#/components/schemas/Holder/properties/inline',
      ),
    ]);
    final pet = fixture.reported.first;
    expect(pet.severity.name, 'warning');
    expect(
      pet.fix,
      endsWith('Override:\nschemas:\n  Pet:\n    union: structural'),
    );
    expect(
      fixture.reported.last.fix,
      endsWith(
        'Override:\nschemas:\n  Holder:\n    properties:\n      inline:\n'
        '        union: structural',
      ),
    );
  });

  test('union: structural tries the variants, by override or config', () {
    const spec =
        '''
$head    Pet:
      oneOf:
        - \$ref: '#/components/schemas/Cat'
        - \$ref: '#/components/schemas/Dog'
''';
    final byOverride = IrFixture(
      spec,
      overrides: 'schemas:\n  Pet: {union: structural}\n',
    );
    final (ir, _) = mapComponents(byOverride, ['Pet']);
    expect(byOverride.reported, isEmpty);
    expect(union(ir, 'Pet').dispatch, UnionDispatch.structural);
    final byConfig = IrFixture(
      spec,
      generation: const GenerationConfig(union: UnionMode.structural),
    );
    final (other, _) = mapComponents(byConfig, ['Pet']);
    expect(byConfig.reported, isEmpty);
    expect(union(other, 'Pet').dispatch, UnionDispatch.structural);
    final rawOverride = IrFixture(
      spec,
      generation: const GenerationConfig(union: UnionMode.structural),
      overrides: 'schemas:\n  Pet: {union: raw}\n',
    );
    final (raw, types) = mapComponents(rawOverride, ['Pet']);
    expect(types['Pet'], 'JsonValue');
    expect(rawOverride.codes, [
      (DiagnosticCode.unionUndiscriminated, '#/components/schemas/Pet'),
    ]);
    expect(raw.declarations, isEmpty);
  });

  test('a union override that changes nothing is TOA807', () {
    final fixture = IrFixture(
      '''
$head    Pet:
      oneOf:
        - \$ref: '#/components/schemas/Cat'
        - \$ref: '#/components/schemas/Dog'
      discriminator: {propertyName: kind}
    Id:
      oneOf: [{type: string}, {type: integer}]
''',
      overrides: '''
schemas:
  Pet: {union: structural}
  Id: {union: structural}
  Cat: {union: raw}
''',
    );
    mapComponents(fixture, ['Pet', 'Id']);
    expect(fixture.codes, [
      (DiagnosticCode.overrideUnchanged, '#/schemas/Cat/union'),
      (DiagnosticCode.overrideUnchanged, '#/schemas/Pet/union'),
      (DiagnosticCode.overrideUnchanged, '#/schemas/Id/union'),
    ]);
  });

  test('a variant of the same Dart type as another is dropped (TOA454)', () {
    final fixture = IrFixture('''
$head    Pet:
      anyOf:
        - \$ref: '#/components/schemas/Cat'
        - {type: string}
        - \$ref: '#/components/schemas/Cat'
''');
    final (ir, _) = mapComponents(fixture, ['Pet']);
    expect(union(ir, 'Pet').variants.map((v) => v.name), [
      'PetCat',
      'PetString',
    ]);
    expect(union(ir, 'Pet').dispatch, UnionDispatch.jsonType);
    expect(fixture.codes, [
      (
        DiagnosticCode.unionVariantDuplicate,
        '#/components/schemas/Pet/anyOf/2',
      ),
    ]);
  });

  test('an inline union of a property takes the property override', () {
    final fixture = IrFixture(
      '''
$head    Holder:
      type: object
      properties:
        inline:
          anyOf: [{type: string}, {type: string, format: uuid}]
''',
      overrides: '''
schemas:
  Holder:
    properties:
      inline: {union: structural}
''',
    );
    final (ir, _) = mapComponents(fixture, ['Holder']);
    // Both variants are String: the second is a duplicate.
    expect(fixture.codes, [
      (
        DiagnosticCode.unionVariantDuplicate,
        '#/components/schemas/Holder/properties/inline/anyOf/1',
      ),
    ]);
    expect(fieldsOf(ir, 'Holder'), ['inline(inline): HolderInline?']);
    expect(
      union(ir, 'HolderInline').variants.map((v) => v.name),
      ['HolderInlineString'],
    );
  });

  test('a variant that takes any JSON joins the shared variant', () {
    final fixture = IrFixture(
      '''
$head    Pet:
      oneOf:
        - \$ref: '#/components/schemas/Cat'
        - {type: string}
''',
      overrides: 'schemas:\n  Cat: {exclude: true}\n',
    );
    final (ir, _) = mapComponents(fixture, ['Pet']);
    final pet = union(ir, 'Pet');
    expect(pet.dispatch, UnionDispatch.jsonType);
    expect(pet.variants.map((v) => '${v.name} ${v.jsonKinds}'), [
      'PetJson [JsonKind.object]',
      'PetString []',
    ]);
    expect(fixture.codes, [
      (DiagnosticCode.excludedSchemaReferenced, '#/components/schemas/Cat'),
    ]);
  });

  test('the override and the config key reject other values', () {
    final bag = DiagnosticBag();
    final set = OverrideLoader(
      bag,
    ).parse('schemas:\n  Pet: {union: guess}\n', 'o.yaml')!;
    expect(set.schemas.single.union, isNull);
    expect(
      [for (final d in bag.all) (d.code, d.pointer?.value)],
      [
        (DiagnosticCode.invalidOverride, '#/schemas/Pet/union'),
      ],
    );
    final configBag = DiagnosticBag();
    final config = ConfigLoader(configBag).load(
      TempDir().write('c.yaml', '''
defaults: {union: structural}
clients:
  a: {input: a.json, output: lib/a}
  b: {input: b.json, output: lib/b, union: maybe}
'''),
    )!;
    // An invalid value falls back to the built-in default (M13 documents
    // this for every key).
    expect(config.clients.map((c) => c.generation.union), [
      UnionMode.structural,
      UnionMode.raw,
    ]);
    expect(
      [for (final d in configBag.all) d.pointer?.value],
      [
        '#/clients/b/union',
      ],
    );
  });

  test('nested unions that share children map in linear time', () {
    // U_i is a oneOf of U_(i+1) and U_(i+2): the number of paths through
    // the chain is Fibonacci, which a mapper without a memo cannot finish
    // for 40 levels.
    const n = 40;
    final schemas = StringBuffer();
    for (var i = 0; i < n; i++) {
      schemas.writeln(
        '    U$i: {oneOf: [{\$ref: "#/components/schemas/U${i + 1}"}, '
        '{\$ref: "#/components/schemas/U${i + 2}"}]}',
      );
    }
    schemas
      ..writeln('    U$n: {type: object, properties: {a: {type: string}}}')
      ..writeln(
        '    U${n + 1}: {type: object, properties: {b: {type: string}}}',
      );
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
$schemas''');
    final (ir, types) = mapComponents(fixture, ['U0']);
    expect(types['U0'], 'JsonValue');
    expect(ir.declarations, isEmpty);
    expect(fixture.codes.first.$1, DiagnosticCode.unionUndiscriminated);
  });
}
