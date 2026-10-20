import 'package:test/test.dart';
import 'package:typed_openapi/src/config/config_loader.dart';
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/ir/dart_type.dart';
import 'package:typed_openapi/src/ir/ir.dart';
import 'package:typed_openapi/src/ir/ir_builder.dart';
import 'package:typed_openapi/src/ir/names.dart';
import 'package:typed_openapi/src/overrides/override_loader.dart';
import 'package:typed_openapi/src/overrides/override_set.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/mapping.dart';

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

    test('variants of the same kind are told apart by their element', () {
      final fixture = IrFixture(
        r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /x:
    get:
      operationId: getX
      responses:
        '200':
          description: ok
          content:
            application/json:
              schema: {$ref: '#/components/schemas/Holder'}
components:
  schemas:
    Pet2:
      oneOf:
        - {type: array, items: {type: string}}
        - {type: array, items: {type: integer}}
        - {type: object, additionalProperties: {type: string}}
        - {type: object, additionalProperties: {type: boolean}}
        - {type: string}
    Single:
      oneOf:
        - {type: array, items: {type: string}}
        - {type: string}
    Holder:
      type: object
      properties:
        a: {$ref: '#/components/schemas/Pet2'}
        b: {$ref: '#/components/schemas/Single'}
''',
        generation: const GenerationConfig(union: .structural),
      );
      final ir = build(fixture);
      expect(declaration<UnionDecl>(ir, 'Pet2').variants.map((v) => v.name), [
        'Pet2ListString',
        'Pet2ListInt',
        'Pet2MapString',
        'Pet2MapBool',
        'Pet2String',
      ]);
      expect(declaration<UnionDecl>(ir, 'Single').variants.map((v) => v.name), [
        'SingleList',
        'SingleString',
      ]);
      expect(
        fixture.codes.where((c) => c.$1 == DiagnosticCode.nameCollision),
        isEmpty,
      );
    });

    test('a helper name that is taken has no override to suggest', () {
      final fixture = IrFixture(spec, generation: const GenerationConfig());
      build(fixture);
      final reports = fixture.reported.where(
        (d) => d.code == DiagnosticCode.nameCollision,
      );
      expect(reports, isNotEmpty);
      expect(
        reports.where((d) => d.fix?.contains('Override:') ?? false),
        isEmpty,
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

  test('a field is never named like its class', () {
    final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /x:
    get:
      operationId: getX
      responses:
        '200':
          description: ok
          content:
            application/json:
              schema: {$ref: '#/components/schemas/2fa'}
components:
  schemas:
    2fa:
      type: object
      properties:
        2fa: {type: string}
        other: {type: integer}
''');
    final ir = build(fixture);
    final model = ir.declarations.whereType<ModelDecl>().single;
    expect(model.name, r'$2Fa');
    expect(model.fields.map((f) => f.name), [r'$2Fa_', 'other']);
    expect(
      fixture.codes.map((c) => c.$1),
      contains(DiagnosticCode.nameReserved),
    );
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

  test('a constant field is never tri-state', () {
    final fixture = IrFixture(
      '''
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
                kind: {const: pet}
                name: {type: string}
                other: {const: x}
      responses:
        '204': {description: ok}
''',
      generation: const GenerationConfig(triState: .optional),
    );
    final ir = build(fixture);
    final body = declaration<ModelDecl>(ir, 'PatchPetRequest');
    expect(body.fields.map((f) => (f.name, f.constValue, f.triState)), [
      ('kind', 'pet', false),
      ('name', null, true),
      ('other', 'x', false),
    ]);
  });

  test('an override cannot make a constant field tri-state', () {
    final fixture = IrFixture(
      r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets:
    patch:
      operationId: patchPet
      requestBody:
        content:
          application/json:
            schema: {$ref: '#/components/schemas/Body'}
      responses:
        '204': {description: ok}
components:
  schemas:
    Body:
      type: object
      properties:
        kind: {const: pet}
        name: {type: string}
''',
      overrides: '''
schemas:
  Body:
    properties:
      kind: {triState: true}
      name: {triState: true}
''',
    );
    final ir = build(fixture);
    final bodies = ir.declarations.whereType<ModelDecl>().where(
      (d) => d.fields.any((f) => f.jsonKey == 'kind'),
    );
    for (final body in bodies) {
      final kind = body.fields.firstWhere((f) => f.jsonKey == 'kind');
      expect(kind.triState, isFalse, reason: body.name);
    }
    expect(
      ir.declarations
          .whereType<ModelDecl>()
          .expand((d) => d.fields)
          .where((f) => f.jsonKey == 'name' && f.triState),
      isNotEmpty,
    );
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
    test('type names are checked against the words of Dart (DartNames)', () {
      for (final word in [
        ...DartNames.reservedWords,
        ...DartNames.builtInIdentifiers,
      ]) {
        expect(
          DartTypeOverride.problem('type', word),
          isNotNull,
          reason: word,
        );
        expect(
          DartTypeOverride.problem('converter', word),
          isNotNull,
          reason: word,
        );
      }
      expect(DartTypeOverride.problem('type', 'Money'), isNull);
      expect(DartTypeOverride.problem('type', 'import'), isNotNull);
      expect(DartTypeOverride.problem('type', 'await'), isNotNull);
    });

    test('a record with a converter that is reported is not applied', () {
      final bag = DiagnosticBag();
      final set = OverrideLoader(bag).parse('''
schemas:
  Empty:
    dartType: {type: Money, import: 'dart:core', converter: ''}
  Number:
    dartType: {type: Money, import: 'dart:core', converter: 5}
  Reserved:
    dartType: {type: Money, import: 'dart:core', converter: abstract}
  Fine:
    dartType: {type: Money, import: 'dart:core', converter: MoneyConverter}
''', 'o.yaml')!;
      expect(set.schemas.map((s) => (s.key, s.dartType?.converter)), [
        ('Empty', null),
        ('Number', null),
        ('Reserved', null),
        ('Fine', 'MoneyConverter'),
      ]);
      expect(set.schemas.map((s) => s.dartType == null), [
        true,
        true,
        true,
        false,
      ]);
      expect(
        [for (final d in bag.all) (d.code, d.pointer?.value)],
        [
          (
            DiagnosticCode.invalidOverride,
            '#/schemas/Empty/dartType/converter',
          ),
          (
            DiagnosticCode.invalidOverride,
            '#/schemas/Number/dartType/converter',
          ),
          (
            DiagnosticCode.invalidOverride,
            '#/schemas/Reserved/dartType/converter',
          ),
        ],
      );
    });
  });
}
