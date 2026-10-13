import 'package:test/test.dart';
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/ir/ir_json.dart';
import 'package:typed_openapi/src/overrides/override_set.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/mapping.dart';

void main() {
  test('merges allOf parts into a flat model and collapses single schemas '
      '(R6.3)', () {
    final fixture = IrFixture(r'''
openapi: 3.0.3
info: {title: t, version: "1"}
components:
  schemas:
    Base:
      type: object
      required: [id]
      properties:
        id: {type: integer}
    Named:
      type: object
      properties:
        name: {type: string}
    Pet:
      allOf:
        - $ref: '#/components/schemas/Base'
        - $ref: '#/components/schemas/Named'
        - type: object
          required: [name]
          properties:
            tag: {type: string}
    Holder:
      type: object
      required: [a, b, c, d]
      properties:
        a:
          allOf: [{$ref: '#/components/schemas/Base'}]
        b:
          nullable: true
          allOf: [{$ref: '#/components/schemas/Base'}]
        c:
          oneOf: [{$ref: '#/components/schemas/Named'}, {enum: [null]}]
        d:
          anyOf: [{type: string}]
    BaseAlias:
      allOf: [{$ref: '#/components/schemas/Base'}]
''');
    final (ir, types) = mapComponents(fixture, ['Pet', 'Holder', 'BaseAlias']);
    expect(fixture.reported, isEmpty);
    expect(types, {'Pet': 'Pet', 'Holder': 'Holder', 'BaseAlias': 'Base'});
    expect(fieldsOf(ir, 'Pet'), [
      'id(id): int',
      'name(name): String',
      'tag(tag): String?',
    ]);
    expect(fieldsOf(ir, 'Holder'), [
      'a(a): Base',
      'b(b): Base?',
      'c(c): Named?',
      'd(d): String',
    ]);
    expect(ir.declarations.map((d) => d.name), [
      'Base',
      'Holder',
      'Named',
      'Pet',
    ]);
  });

  test('reports allOf parts that conflict or are not objects', () {
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Pet:
      allOf:
        - {type: object, properties: {id: {type: integer}, same: {type: string}}}
        - {type: object, properties: {id: {type: string}, same: {type: string}}}
        - {type: string}
''');
    final (ir, _) = mapComponents(fixture, ['Pet']);
    expect(fieldsOf(ir, 'Pet'), ['id(id): String?', 'same(same): String?']);
    expect(fixture.codes, [
      (
        DiagnosticCode.allOfPropertyConflict,
        '#/components/schemas/Pet/allOf/1/properties/id',
      ),
      (DiagnosticCode.allOfPartIgnored, '#/components/schemas/Pet/allOf/2'),
    ]);
  });

  test('builds unions with a resolved discriminator mapping (R9)', () {
    final fixture = IrFixture(
      r'''
openapi: 3.2.0
info: {title: t, version: "1"}
components:
  schemas:
    Cat: {type: object, properties: {kind: {type: string}}}
    Dog: {type: object, properties: {kind: {type: string}}}
    Bird: {type: object, properties: {kind: {type: string}}}
    Pet:
      oneOf:
        - $ref: '#/components/schemas/Cat'
        - $ref: '#/components/schemas/Dog'
        - $ref: '#/components/schemas/Bird'
        - type: 'null'
      discriminator:
        propertyName: kind
        mapping:
          cat: '#/components/schemas/Cat'
          kitty: Cat
          dog: Dog
        defaultMapping: Bird
    Id:
      anyOf: [{type: string}, {type: integer}]
    Holder:
      type: object
      properties:
        pet: {$ref: '#/components/schemas/Pet'}
        shape:
          oneOf:
            - {type: object, properties: {r: {type: number}}}
            - {type: object, properties: {w: {type: number}}}
''',
      generation: const GenerationConfig(union: UnionMode.structural),
      overrides: '''
schemas:
  Id: {exhaustive: false}
''',
    );
    final (ir, types) = mapComponents(fixture, ['Holder', 'Id']);
    expect(fixture.reported, isEmpty);
    expect(fieldsOf(ir, 'Holder'), [
      'pet(pet): Pet?',
      'shape(shape): HolderShape?',
    ]);
    Map<String, Object?> json(String name) =>
        (IrJson((_) => 'api.yaml').toJson(ir)['declarations']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .firstWhere((d) => d['name'] == name);
    expect(json('Pet'), {
      'name': 'Pet',
      'at': 'api.yaml#/components/schemas/Pet',
      'kind': 'oneOf',
      'discriminator': 'kind',
      'variants': [
        {
          'type': 'Cat',
          'values': ['cat', 'kitty'],
        },
        {
          'type': 'Dog',
          'values': ['dog'],
        },
        {
          'type': 'Bird',
          'values': ['Bird'],
        },
      ],
      'default': 'Bird',
    });
    expect(json('Id'), {
      'name': 'Id',
      'at': 'api.yaml#/components/schemas/Id',
      'kind': 'anyOf',
      'exhaustive': false,
      'variants': [
        {'type': 'String'},
        {'type': 'int'},
      ],
    });
    expect(types['Id'], 'Id');
    expect(ir.declarations.map((d) => d.name), [
      'Bird',
      'Cat',
      'Dog',
      'Holder',
      'HolderShape',
      'HolderShapeVariant1',
      'HolderShapeVariant2',
      'Id',
      'Pet',
    ]);
  });

  test('reports inline variants and mapping values outside the union', () {
    final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Cat: {type: object, properties: {kind: {type: string}}}
    Other: {type: object, properties: {kind: {type: string}}}
    Pet:
      oneOf:
        - $ref: '#/components/schemas/Cat'
        - {type: object, properties: {kind: {type: string}}}
      discriminator:
        propertyName: kind
        mapping: {other: Other}
''');
    mapComponents(fixture, ['Pet']);
    expect(fixture.codes, [
      (
        DiagnosticCode.discriminatorMappingNotVariant,
        '#/components/schemas/Pet/discriminator/mapping/other',
      ),
      (
        DiagnosticCode.discriminatorValueMissing,
        '#/components/schemas/Pet/oneOf/1',
      ),
    ]);
  });
}
