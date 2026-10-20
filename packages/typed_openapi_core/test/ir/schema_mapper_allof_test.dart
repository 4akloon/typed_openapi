import 'package:test/test.dart';
import 'package:typed_openapi_core/src/config/generation_config.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/diagnostics/severity.dart';
import 'package:typed_openapi_core/src/ir/ir.dart';
import 'package:typed_openapi_core/src/overrides/override_set.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/mapped_ir.dart';
import '../helpers/mapping.dart';

void main() {
  group('allOf (T5 I2, I3)', () {
    test('allOf beside a union is ignored with TOA256', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Base: {type: object, properties: {id: {type: integer}}}
    A: {type: object, properties: {a: {type: string}}}
    B: {type: object, properties: {b: {type: string}}}
    P:
      allOf: [{$ref: '#/components/schemas/Base'}]
      oneOf: [{$ref: '#/components/schemas/A'}, {$ref: '#/components/schemas/B'}]
''', generation: const GenerationConfig(union: UnionMode.structural));
      final (ir, _) = mapComponents(fixture, ['P']);
      expect(MappedIr.variantsOf(ir, 'P'), ['A', 'B']);
      expect(fixture.codes, [
        (
          DiagnosticCode.compositionPartsIgnored,
          '#/components/schemas/P/allOf',
        ),
      ]);
    });

    test('additionalProperties of a part is merged, the later part wins', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Base: {type: object, additionalProperties: {type: string}}
    Child:
      allOf:
        - $ref: '#/components/schemas/Base'
        - {properties: {a: {type: string}}}
    Other:
      allOf:
        - $ref: '#/components/schemas/Base'
        - {properties: {a: {type: string}}, additionalProperties: {type: integer}}
    Closed:
      allOf:
        - $ref: '#/components/schemas/Base'
        - {properties: {a: {type: string}}, additionalProperties: false}
''');
      final (ir, _) = mapComponents(fixture, ['Child', 'Other', 'Closed']);
      String? extra(String name) => MappedIr.declaration<ModelDecl>(
        ir,
        name,
      ).additionalProperties?.code(ir.nameOf);
      expect(extra('Child'), 'String');
      expect(extra('Other'), 'int');
      expect(extra('Closed'), isNull);
      expect(fixture.codes, [
        (
          DiagnosticCode.allOfPropertyConflict,
          '#/components/schemas/Other/allOf/1/additionalProperties',
        ),
        (
          DiagnosticCode.allOfPropertyConflict,
          '#/components/schemas/Closed/allOf/1/additionalProperties',
        ),
      ]);
    });

    test('a discriminator on an extended base makes a union of subtypes', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Pet:
      type: object
      properties: {kind: {type: string}, name: {type: string}}
      discriminator: {propertyName: kind, mapping: {cat: Cat, dog: Dog}}
    Cat:
      allOf:
        - $ref: '#/components/schemas/Pet'
        - {properties: {lives: {type: integer}}}
    Dog:
      allOf:
        - $ref: '#/components/schemas/Pet'
        - {properties: {bark: {type: string}}}
    Holder:
      type: object
      properties: {pet: {$ref: '#/components/schemas/Pet'}}
''');
      final (ir, _) = mapComponents(fixture, ['Holder', 'Cat', 'Dog']);
      expect(fieldsOf(ir, 'Cat'), [
        'kind(kind): String?',
        'name(name): String?',
        'lives(lives): int?',
      ]);
      expect(fieldsOf(ir, 'Holder'), ['pet(pet): Pet?']);
      final pet = MappedIr.declaration<UnionDecl>(ir, 'Pet');
      expect(pet.variants.map((v) => '${v.name} ${v.discriminatorValues}'), [
        'PetCat [cat]',
        'PetDog [dog]',
      ]);
      expect(fixture.codes, isEmpty);
    });

    test('a discriminator on a schema nothing extends is TOA452', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Pet:
      type: object
      properties: {kind: {type: string}}
      discriminator: {propertyName: kind}
''');
      mapComponents(fixture, ['Pet']);
      final found = fixture.reported.single;
      expect(found.code, DiagnosticCode.discriminatorWithoutSubtypes);
      expect(found.message, contains('no schema extends'));
    });

    test('a discriminator on a union is not TOA452', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Cat: {type: object, properties: {kind: {type: string}}}
    Dog: {type: object, properties: {kind: {type: string}}}
    Pet:
      oneOf: [{$ref: '#/components/schemas/Cat'}, {$ref: '#/components/schemas/Dog'}]
      discriminator: {propertyName: kind}
''');
      mapComponents(fixture, ['Pet']);
      expect(fixture.reported, isEmpty);
    });

    test('a defaultMapping that is no variant is TOA451', () {
      final fixture = IrFixture(r'''
openapi: 3.2.0
info: {title: t, version: "1"}
components:
  schemas:
    Cat: {type: object, properties: {kind: {type: string}}}
    Dog: {type: object, properties: {kind: {type: string}}}
    Other: {type: object, properties: {kind: {type: string}}}
    Pet:
      oneOf: [{$ref: '#/components/schemas/Cat'}, {$ref: '#/components/schemas/Dog'}]
      discriminator: {propertyName: kind, defaultMapping: Other}
''');
      final (ir, _) = mapComponents(fixture, ['Pet']);
      expect(MappedIr.declaration<UnionDecl>(ir, 'Pet').defaultVariant, isNull);
      expect(fixture.codes, [
        (
          DiagnosticCode.discriminatorMappingNotVariant,
          '#/components/schemas/Pet/discriminator/defaultMapping',
        ),
      ]);
    });

    test('an excluded allOf parent is still merged, TOA254 says so (T8 1)', () {
      final fixture = IrFixture(
        r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    X: {type: object, properties: {a: {type: string}, dep: {$ref: '#/components/schemas/Dep'}}}
    Dep: {type: object, properties: {d: {type: string}}}
    Child:
      allOf:
        - $ref: '#/components/schemas/X'
        - {properties: {c: {type: string}}}
''',
        overrides: '''
schemas:
  X: {exclude: true}
''',
      );
      final (ir, _) = mapComponents(fixture, ['Child']);
      expect(fieldsOf(ir, 'Child'), [
        'a(a): String?',
        'dep(dep): Dep?',
        'c(c): String?',
      ]);
      // X has no declaration of its own, its dependency has.
      expect(ir.declarations.map((d) => d.name), ['Child', 'Dep']);
      expect(fixture.codes, [
        (
          DiagnosticCode.excludedSchemaReferenced,
          '#/components/schemas/Child/allOf/0',
        ),
      ]);
      expect(fixture.reported.single.severity, Severity.info);
      expect(fixture.reported.single.message, contains('merged'));
    });

    test(
      'an override name or exhaustive on an alias has no effect (T5 M1)',
      () {
        final fixture = IrFixture(
          r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    M: {type: object, properties: {a: {type: string}}}
    Al: {allOf: [{$ref: '#/components/schemas/M'}]}
    Tags: {type: array, items: {type: string}}
    Holder:
      type: object
      properties:
        al: {$ref: '#/components/schemas/Al'}
        tags: {$ref: '#/components/schemas/Tags'}
''',
          overrides: '''
schemas:
  Al: {name: Renamed, exhaustive: false}
  Tags: {name: TagList}
  M: {name: Model}
''',
        );
        final (ir, _) = mapComponents(fixture, ['Holder']);
        expect(fieldsOf(ir, 'Holder'), [
          'al(al): Model?',
          'tags(tags): List<String>?',
        ]);
        expect(
          [
            for (final d in fixture.reported)
              (d.code, d.file, d.pointer?.value),
          ],
          [
            (DiagnosticCode.overrideUnchanged, 'o.yaml', '#/schemas/Al/name'),
            (
              DiagnosticCode.overrideUnchanged,
              'o.yaml',
              '#/schemas/Al/exhaustive',
            ),
            (DiagnosticCode.overrideUnchanged, 'o.yaml', '#/schemas/Tags/name'),
          ],
        );
        expect(
          fixture.reported.first.message,
          'The name of this override has no effect: the schema is not '
          'generated as a type of its own, its uses are the type of what it '
          'stands for.',
        );
      },
    );
  });
}
