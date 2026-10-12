import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/ir/ir.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/mapping.dart';

T declaration<T extends Declaration>(ClientIr ir, String name) =>
    ir.declarations.firstWhere((d) => d.name == name) as T;

/// The variants of the union [name] as `Class [values]` strings.
List<String> variants(ClientIr ir, String name) => [
  for (final v in declaration<UnionDecl>(ir, name).variants)
    '${v.name} ${v.discriminatorValues}',
];

void main() {
  group('a base with a discriminator is a union of its subtypes', () {
    const head = r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Holder:
      type: object
      properties: {pet: {$ref: '#/components/schemas/Pet'}}
''';

    test('over every level of the hierarchy, with implicit values', () {
      final fixture = IrFixture(
        r'''
$head    Pet:
      type: object
      required: [petType]
      properties: {petType: {type: string}, name: {type: string}}
      discriminator: {propertyName: petType}
    Cat:
      allOf:
        - $ref: '#/components/schemas/Pet'
        - {properties: {lives: {type: integer}}}
    Kitten:
      allOf:
        - $ref: '#/components/schemas/Cat'
        - {properties: {age: {type: integer}}}
    Dog:
      allOf: [{$ref: '#/components/schemas/Pet'}]
'''
            .replaceFirst(r'$head', head),
      );
      final (ir, types) = mapComponents(fixture, ['Holder']);
      expect(fixture.codes, isEmpty);
      expect(fieldsOf(ir, 'Holder'), ['pet(pet): Pet?']);
      final pet = declaration<UnionDecl>(ir, 'Pet');
      expect(pet.dispatch, UnionDispatch.discriminator);
      expect(pet.discriminator, 'petType');
      expect(variants(ir, 'Pet'), [
        'PetCat [Cat]',
        'PetKitten [Kitten]',
        'PetDog [Dog]',
      ]);
      expect(fieldsOf(ir, 'Kitten'), [
        'petType(petType): String',
        'name(name): String?',
        'lives(lives): int?',
        'age(age): int?',
      ]);
    });

    test('a mapping to the base itself is reported and decodes as unknown', () {
      final fixture = IrFixture(
        r'''
$head    Pet:
      type: object
      properties: {petType: {type: string}}
      discriminator:
        propertyName: petType
        mapping: {pet: Pet, cat: '#/components/schemas/Cat', bird: Holder}
    Cat:
      allOf: [{$ref: '#/components/schemas/Pet'}]
'''
            .replaceFirst(r'$head', head),
      );
      final (ir, _) = mapComponents(fixture, ['Holder']);
      expect(variants(ir, 'Pet'), ['PetCat [cat]']);
      expect(fixture.codes, [
        (
          DiagnosticCode.discriminatorMappingNotVariant,
          '#/components/schemas/Pet/discriminator/mapping/pet',
        ),
        (
          DiagnosticCode.discriminatorMappingNotVariant,
          '#/components/schemas/Pet/discriminator/mapping/bird',
        ),
      ]);
      expect(fixture.reported.first.message, contains('base schema itself'));
    });

    test('a recursive hierarchy refers to the union from a subtype', () {
      final fixture = IrFixture(
        r'''
$head    Pet:
      type: object
      properties:
        petType: {type: string}
        friends: {type: array, items: {$ref: '#/components/schemas/Pet'}}
      discriminator: {propertyName: petType}
    Cat:
      allOf:
        - $ref: '#/components/schemas/Pet'
        - {properties: {mother: {$ref: '#/components/schemas/Cat'}}}
'''
            .replaceFirst(r'$head', head),
      );
      final (ir, _) = mapComponents(fixture, ['Holder']);
      expect(fixture.codes, isEmpty);
      expect(fieldsOf(ir, 'Cat'), [
        'petType(petType): String?',
        'friends(friends): List<Pet>?',
        'mother(mother): Cat?',
      ]);
      expect(variants(ir, 'Pet'), ['PetCat [Cat]']);
    });

    test('a subtype that is a base itself is its own union too', () {
      final fixture = IrFixture(
        r'''
$head    Pet:
      type: object
      properties: {petType: {type: string}}
      discriminator: {propertyName: petType}
    Cat:
      allOf: [{$ref: '#/components/schemas/Pet'}]
      discriminator: {propertyName: petType}
    Kitten:
      allOf: [{$ref: '#/components/schemas/Cat'}]
'''
            .replaceFirst(r'$head', head),
      );
      final (ir, _) = mapComponents(fixture, ['Holder']);
      expect(variants(ir, 'Pet'), ['PetCat [Cat]', 'PetKitten [Kitten]']);
      expect(variants(ir, 'Cat'), ['CatKitten [Kitten]']);
    });

    test('a base used only as an allOf part stays out of the IR', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Pet:
      type: object
      properties: {petType: {type: string}}
      discriminator: {propertyName: petType}
    Cat:
      allOf: [{$ref: '#/components/schemas/Pet'}]
''');
      final (ir, _) = mapComponents(fixture, ['Cat']);
      expect(fixture.codes, isEmpty);
      expect(ir.declarations.map((d) => d.name), ['Cat']);
    });

    test('an excluded subtype is left out', () {
      final fixture = IrFixture(
        r'''
$head    Pet:
      type: object
      properties: {petType: {type: string}}
      discriminator: {propertyName: petType}
    Cat:
      allOf: [{$ref: '#/components/schemas/Pet'}]
    Dog:
      allOf: [{$ref: '#/components/schemas/Pet'}]
'''
            .replaceFirst(r'$head', head),
        overrides: 'schemas:\n  Dog: {exclude: true}\n',
      );
      final (ir, _) = mapComponents(fixture, ['Holder']);
      expect(variants(ir, 'Pet'), ['PetCat [Cat]']);
    });
  });

  group('a union without a discriminator dispatches what it can', () {
    test('a shared JSON type is one variant of any JSON value (R9.2)', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Customer: {type: object, properties: {id: {type: string}}}
    DeletedCustomer: {type: object, properties: {deleted: {type: boolean}}}
    Holder:
      type: object
      properties:
        customer:
          anyOf:
            - {type: string, maxLength: 5000}
            - $ref: '#/components/schemas/Customer'
            - $ref: '#/components/schemas/DeletedCustomer'
''');
      final (ir, _) = mapComponents(fixture, ['Holder']);
      final customer = declaration<UnionDecl>(ir, 'HolderCustomer');
      expect(customer.dispatch, UnionDispatch.jsonType);
      expect(customer.variants.map((v) => '${v.name} ${v.jsonKinds}'), [
        'HolderCustomerString []',
        'HolderCustomerJson [JsonKind.object]',
      ]);
      expect(ir.declarations.map((d) => d.name), ['Holder', 'HolderCustomer']);
      expect(fixture.codes, [
        (
          DiagnosticCode.unionUndiscriminated,
          '#/components/schemas/Holder/properties/customer',
        ),
      ]);
      final found = fixture.reported.single;
      expect(
        found.message,
        startsWith(
          'Variants Customer, DeletedCustomer of this anyOf share the JSON '
          'type object',
        ),
      );
      expect(found.fix, contains('customer:\n        union: structural'));
    });

    test('several shared types go to one variant at the first of them', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    A: {type: object, properties: {a: {type: string}}}
    B: {type: object, properties: {b: {type: string}}}
    Mixed:
      oneOf:
        - {type: integer}
        - {type: string}
        - $ref: '#/components/schemas/A'
        - {type: string, format: uuid}
        - $ref: '#/components/schemas/B'
''');
      final (ir, _) = mapComponents(fixture, ['Mixed']);
      final mixed = declaration<UnionDecl>(ir, 'Mixed');
      expect(mixed.variants.map((v) => '${v.name} ${v.jsonKinds}'), [
        'MixedInt []',
        'MixedJson [JsonKind.string, JsonKind.object]',
      ]);
      expect(fixture.reported.single.message, contains('#1, A, #3, B'));
    });

    test('a variant of any JSON value makes the whole union JsonValue', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Loose:
      oneOf: [{}, {type: string}]
''');
      final (_, types) = mapComponents(fixture, ['Loose']);
      expect(types['Loose'], 'JsonValue');
      expect(fixture.codes, [
        (DiagnosticCode.unionUndiscriminated, '#/components/schemas/Loose'),
      ]);
    });
  });
}
