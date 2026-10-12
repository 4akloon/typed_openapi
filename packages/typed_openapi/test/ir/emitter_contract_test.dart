import 'package:test/test.dart';
import 'package:typed_openapi/src/config/config_loader.dart';
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/ir/dart_type.dart';
import 'package:typed_openapi/src/ir/ir.dart';
import 'package:typed_openapi/src/ir/ir_builder.dart';
import 'package:typed_openapi/src/overrides/override_loader.dart';
import 'package:typed_openapi/src/overrides/override_set.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/mapping.dart';
import '../helpers/temp_dir.dart';

/// The IR of [fixture]'s spec.
ClientIr build(IrFixture fixture) => IrBuilder(
  fixture.diagnostics,
).build(fixture.context.spec, fixture.context.client);

T declaration<T extends Declaration>(ClientIr ir, String name) =>
    ir.declarations.firstWhere((d) => d.name == name) as T;

FieldIr field(ClientIr ir, String model, String json) => declaration<ModelDecl>(
  ir,
  model,
).fields.firstWhere((f) => f.jsonKey == json);

void main() {
  group('constant fields', () {
    test('a const or one-value enum written inline is a constant', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Kind: {type: string, enum: [cat]}
    Cat:
      type: object
      required: [petType]
      properties:
        petType: {const: cat}
        version: {type: integer, enum: [2]}
        ratio: {type: number, const: 0.5}
        flag: {const: true}
        maybe: {type: [string, 'null'], const: cat}
        named: {$ref: '#/components/schemas/Kind'}
        two: {type: string, enum: [a, b]}
''');
      final (ir, _) = mapComponents(fixture, ['Cat']);
      expect(fixture.reported, isEmpty);
      expect(field(ir, 'Cat', 'petType').constValue, 'cat');
      expect(field(ir, 'Cat', 'petType').type, const CoreType(.string));
      expect(field(ir, 'Cat', 'version').constValue, 2);
      expect(
        field(ir, 'Cat', 'version').type,
        const CoreType(.integer, nullable: true),
      );
      expect(field(ir, 'Cat', 'ratio').constValue, 0.5);
      expect(field(ir, 'Cat', 'flag').constValue, isTrue);
      expect(field(ir, 'Cat', 'maybe').constValue, isNull);
      expect(field(ir, 'Cat', 'named').constValue, isNull);
      expect(field(ir, 'Cat', 'two').constValue, isNull);
      expect(ir.declarations.map((d) => d.name), [
        'Cat',
        'CatMaybe',
        'CatTwo',
        'Kind',
      ]);
    });
  });

  group('constraints and additional properties', () {
    test('reads constraints, with 3.0 exclusive flags as bounds (R6.7)', () {
      final fixture = IrFixture(r'''
openapi: 3.0.3
info: {title: t, version: "1"}
components:
  schemas:
    Name: {type: string, minLength: 1, maxLength: 64, pattern: '^[a-z]+$'}
    Pet:
      type: object
      properties:
        name: {$ref: '#/components/schemas/Name'}
        age: {type: integer, minimum: 0, maximum: 30, exclusiveMaximum: true, multipleOf: 1}
        tags: {type: array, items: {type: string}, minItems: 1, maxItems: 5, uniqueItems: true}
        meta: {type: object, minProperties: 1, maxProperties: 3}
        plain: {type: string}
''');
      final (ir, _) = mapComponents(fixture, ['Pet']);
      final name = field(ir, 'Pet', 'name').constraints;
      expect(
        (name.minLength, name.maxLength, name.pattern),
        (1, 64, r'^[a-z]+$'),
      );
      final age = field(ir, 'Pet', 'age').constraints;
      expect(
        (age.minimum, age.maximum, age.exclusiveMaximum, age.multipleOf),
        (0, null, 30, 1),
      );
      final tags = field(ir, 'Pet', 'tags').constraints;
      expect((tags.minItems, tags.maxItems, tags.uniqueItems), (1, 5, true));
      final meta = field(ir, 'Pet', 'meta').constraints;
      expect((meta.minProperties, meta.maxProperties), (1, 3));
      expect(field(ir, 'Pet', 'plain').constraints.isEmpty, isTrue);
    });

    test('3.1 numeric exclusive bounds are kept as written', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Pet:
      type: object
      properties:
        age: {type: integer, exclusiveMinimum: 0, exclusiveMaximum: 30}
''');
      final (ir, _) = mapComponents(fixture, ['Pet']);
      final age = field(ir, 'Pet', 'age').constraints;
      expect((age.exclusiveMinimum, age.exclusiveMaximum), (0, 30));
    });

    test('the additional properties field yields to a property', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Counts:
      type: object
      properties:
        additionalProperties: {type: string}
      additionalProperties: {type: integer}
    Plain:
      type: object
      properties:
        id: {type: integer}
      additionalProperties: {type: integer}
''');
      final (ir, _) = mapComponents(fixture, ['Counts', 'Plain']);
      final counts = declaration<ModelDecl>(ir, 'Counts');
      expect(counts.fields.single.name, 'additionalProperties');
      expect(counts.additionalPropertiesName, 'additionalProperties2');
      expect(fixture.codes, [
        (DiagnosticCode.nameCollision, '#/components/schemas/Counts'),
      ]);
      expect(
        declaration<ModelDecl>(ir, 'Plain').additionalPropertiesName,
        'additionalProperties',
      );
    });
  });

  group('names of the types the emitters add', () {
    const spec = r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets:
    get:
      operationId: listPets
      tags: [PetUnknown]
      responses:
        '200':
          description: ok
          content:
            application/json:
              schema: {$ref: '#/components/schemas/Holder'}
components:
  schemas:
    Status: {type: string, enum: [a, b]}
    StatusKnown: {type: object, properties: {a: {type: string}}}
    PetCat: {type: object, properties: {lives: {type: integer}}}
    Cat: {type: object, properties: {lives: {type: integer}}}
    Pet:
      oneOf:
        - {$ref: '#/components/schemas/Cat'}
        - {$ref: '#/components/schemas/PetCat'}
        - {type: object, properties: {x: {type: string}}}
    IdOrName:
      oneOf: [{type: string}, {type: integer}]
    Holder:
      type: object
      properties:
        status: {$ref: '#/components/schemas/Status'}
        known: {$ref: '#/components/schemas/StatusKnown'}
        pet: {$ref: '#/components/schemas/Pet'}
        id: {$ref: '#/components/schemas/IdOrName'}
''';

    test('enums and unions get their helper class names', () {
      final fixture = IrFixture(
        spec,
        generation: const GenerationConfig(
          groupTemplate: '{Tag}',
          union: UnionMode.structural,
        ),
      );
      final ir = build(fixture);
      final status = declaration<EnumDecl>(ir, 'Status');
      expect(
        (status.knownName, status.unknownName),
        (
          'StatusKnown2',
          'StatusUnknown',
        ),
      );
      expect(ir.groups.single.name, 'PetUnknown');
      final pet = declaration<UnionDecl>(ir, 'Pet');
      expect(pet.variants.map((v) => v.name), [
        'PetCat2',
        'PetCatCase',
        'PetVariant3Case',
      ]);
      expect(pet.unknownName, 'PetUnknown2');
      final id = declaration<UnionDecl>(ir, 'IdOrName');
      expect(id.variants.map((v) => v.name), ['IdOrNameString', 'IdOrNameInt']);
      expect(
        fixture.codes.where((c) => c.$1 == DiagnosticCode.nameCollision),
        [
          (DiagnosticCode.nameCollision, '#/components/schemas/Pet'),
          (DiagnosticCode.nameCollision, '#/components/schemas/Pet'),
          (DiagnosticCode.nameCollision, '#/components/schemas/Status'),
        ],
      );
    });

    test('a group keeps its name before helper names (no TOA551 on it)', () {
      final fixture = IrFixture(
        spec,
        generation: const GenerationConfig(
          groupTemplate: '{Tag}',
          union: UnionMode.structural,
        ),
      );
      final ir = build(fixture);
      expect(ir.groups.single.name, 'PetUnknown');
      expect(
        fixture.reported.where((d) => d.message.contains('group class')),
        isEmpty,
      );
    });
  });

  test('an optional JsonValue field of a PATCH body is tri-state (R7.1)', () {
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets:
    patch:
      operationId: patchPet
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                meta: {}
                name: {type: string}
      responses:
        '204': {description: ok}
''');
    final ir = build(fixture);
    final body = declaration<ModelDecl>(ir, 'PatchPetRequest');
    expect(body.fields.map((f) => (f.name, f.triState)), [
      ('meta', true),
      ('name', false),
    ]);
    expect(body.fields.first.type.code(ir.nameOf), 'Patch<JsonValue>?');
  });

  group('custom types must be writable as code (R6.8)', () {
    test('in the config', () {
      final bag = DiagnosticBag();
      final config = ConfigLoader(bag).load(
        TempDir().write('c.yaml', '''
clients:
  a:
    input: a.json
    output: lib/a
    types:
      formats:
        money: {type: 'Money<int>', import: 'package:app/money.dart'}
        rate: {type: Rate, import: rate.dart}
        ok: {type: Decimal, import: 'package:decimal/decimal.dart', converter: 'a b'}
        good: {type: Decimal, import: 'package:decimal/decimal.dart'}
'''),
      )!;
      expect(config.clients.single.generation.formats.keys, ['good']);
      expect(
        [for (final d in bag.all) (d.code, d.pointer?.value)],
        [
          (
            DiagnosticCode.configInvalid,
            '#/clients/a/types/formats/money/type',
          ),
          (
            DiagnosticCode.configInvalid,
            '#/clients/a/types/formats/rate/import',
          ),
          (
            DiagnosticCode.configInvalid,
            '#/clients/a/types/formats/ok/converter',
          ),
        ],
      );
    });

    test('in an override', () {
      final bag = DiagnosticBag();
      final set = OverrideLoader(bag).parse('''
schemas:
  Pet:
    dartType: {type: void, import: 'dart:core'}
  Tag:
    dartType: {type: Tag, import: 'dart:core'}
''', 'o.yaml')!;
      expect(set.schemas.map((s) => (s.key, s.dartType?.type)), [
        ('Pet', null),
        ('Tag', 'Tag'),
      ]);
      expect(
        [for (final d in bag.all) (d.code, d.pointer?.value)],
        [
          (DiagnosticCode.invalidOverride, '#/schemas/Pet/dartType/type'),
        ],
      );
    });
  });
}
