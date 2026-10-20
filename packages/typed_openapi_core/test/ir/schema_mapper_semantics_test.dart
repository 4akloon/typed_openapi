import 'package:test/test.dart';
import 'package:typed_openapi_core/src/config/generation_config.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/ir/ir_builder.dart';
import 'package:typed_openapi_core/src/overrides/override_set.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/mapping.dart';

void main() {
  group('custom types', () {
    test('the dartType override TOA250 suggests silences TOA250 (T4 I2)', () {
      const spec = r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Box:
      type: object
      properties:
        id: {type: [string, integer]}
        mixed: {$ref: '#/components/schemas/Mixed'}
    Mixed: {type: [string, integer]}
''';
      final plain = IrFixture(spec);
      mapComponents(plain, ['Box']);
      expect(plain.codes, [
        (
          DiagnosticCode.mixedTypeSchema,
          '#/components/schemas/Box/properties/id',
        ),
        (DiagnosticCode.mixedTypeSchema, '#/components/schemas/Mixed'),
      ]);
      final fixed = IrFixture(
        spec,
        overrides: '''
schemas:
  Box:
    properties:
      id:
        dartType: {type: MyId, import: 'package:app/my_id.dart'}
  Mixed:
    dartType: {type: Mixed, import: 'package:app/mixed.dart'}
''',
      );
      final (ir, _) = mapComponents(fixed, ['Box']);
      expect(fieldsOf(ir, 'Box'), ['id(id): MyId?', 'mixed(mixed): Mixed?']);
      expect(fixed.reported, isEmpty);
    });

    test(
      'exclude beside a custom type: the type wins, TOA254 says so (T8 2)',
      () {
        final fixture = IrFixture(
          r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Holder:
      type: object
      properties:
        money: {$ref: '#/components/schemas/Money'}
        price: {$ref: '#/components/schemas/Price'}
    Money: {type: object, properties: {amount: {type: string}}}
    Price: {type: object, properties: {amount: {type: string}}}
''',
          generation: const GenerationConfig(
            schemas: {
              'Money': DartTypeOverride(
                type: 'Money',
                import: 'package:a/m.dart',
              ),
            },
          ),
          overrides: '''
schemas:
  Money: {exclude: true}
  Price: {exclude: true, dartType: {type: Price, import: 'package:a/p.dart'}}
''',
        );
        final (ir, _) = mapComponents(fixture, ['Holder']);
        expect(fieldsOf(ir, 'Holder'), [
          'money(money): Money?',
          'price(price): Price?',
        ]);
        expect(ir.declarations.map((d) => d.name), ['Holder']);
        expect(fixture.codes, [
          (
            DiagnosticCode.excludedSchemaReferenced,
            '#/components/schemas/Money',
          ),
          (
            DiagnosticCode.excludedSchemaReferenced,
            '#/components/schemas/Price',
          ),
        ]);
        expect(
          fixture.reported.last.message,
          'This schema is excluded by an override, but it also has a custom '
          'Dart type; the type is used and the exclude has no effect.',
        );
      },
    );
  });

  test(r'a $ref into a union branch is named after the union (T9 M3)', () {
    final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    U:
      oneOf:
        - {type: object, properties: {a: {type: string}}}
        - {type: object, properties: {b: {type: string}}}
    V:
      anyOf:
        - {type: string}
        - {type: object, properties: {c: {type: string}}}
    Holder:
      type: object
      properties:
        first: {$ref: '#/components/schemas/U/oneOf/0'}
        second: {$ref: '#/components/schemas/U/oneOf/1'}
        other: {$ref: '#/components/schemas/V/anyOf/1'}
''');
    final (ir, _) = mapComponents(fixture, ['Holder']);
    expect(fieldsOf(ir, 'Holder'), [
      'first(first): UVariant1?',
      'second(second): UVariant2?',
      'other(other): VVariant2?',
    ]);
    expect(fixture.reported, isEmpty);
  });

  test('a valid spec with plain names, allOf, unions and PATCH is silent', () {
    final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets:
    get:
      tags: [pets]
      operationId: listPets
      responses: {"200": {description: ok, content: {application/json: {schema: {type: array, items: {$ref: '#/components/schemas/Pet'}}}}}}
    post:
      tags: [pets]
      operationId: createPet
      requestBody: {content: {application/json: {schema: {$ref: '#/components/schemas/NewPet'}}}}
      responses: {"201": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/Pet'}}}}}
  /pets/{id}:
    parameters: [{name: id, in: path, required: true, schema: {type: string}}]
    patch:
      tags: [pets]
      operationId: updatePet
      requestBody: {content: {application/json: {schema: {$ref: '#/components/schemas/NewPet'}}}}
      responses: {"200": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/Animal'}}}}}
components:
  schemas:
    NewPet:
      type: object
      required: [name]
      properties:
        name: {type: string}
        tag: {type: [string, "null"]}
        status: {type: string, enum: [available, sold, in-progress]}
    Pet:
      allOf:
        - $ref: '#/components/schemas/NewPet'
        - type: object
          properties:
            id: {type: integer, readOnly: true}
    Cat: {type: object, properties: {kind: {type: string}, lives: {type: integer}}}
    Dog: {type: object, properties: {kind: {type: string}, bark: {type: string}}}
    Animal:
      oneOf: [{$ref: '#/components/schemas/Cat'}, {$ref: '#/components/schemas/Dog'}]
      discriminator: {propertyName: kind}
    Color: {type: string, oneOf: [{const: red}, {const: green}]}
''');
    final ir = IrBuilder(
      fixture.diagnostics,
    ).build(fixture.context.spec, fixture.context.client);
    expect(fixture.reported, isEmpty);
    expect(ir.declarations.map((d) => d.name), [
      'Animal',
      'Cat',
      'Dog',
      'NewPet',
      'NewPetPatch',
      'Pet',
      'PetStatus',
    ]);
  });
}
