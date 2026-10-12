import 'package:test/test.dart';
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/ir/ir.dart';
import 'package:typed_openapi/src/ir/ir_builder.dart';
import 'package:typed_openapi/src/overrides/override_set.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/mapping.dart';

/// The declaration [name] of [ir].
T declaration<T extends Declaration>(ClientIr ir, String name) =>
    ir.declarations.firstWhere((d) => d.name == name) as T;

/// The variants of the union [name] as `type` strings.
List<String> variantsOf(ClientIr ir, String name) => [
  for (final v in declaration<UnionDecl>(ir, name).variants)
    v.type.code(ir.nameOf),
];

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

  group('oneOf and anyOf beside properties (T5 I1)', () {
    test('a type: object branch without properties adds only constraints', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Pick:
      type: object
      properties: {a: {type: string}, b: {type: string}}
      anyOf:
        - {type: object, required: [a]}
        - {type: object, required: [b]}
    Real:
      type: object
      properties: {a: {type: string}}
      oneOf:
        - {type: object, properties: {x: {type: string}}}
        - {type: object, properties: {y: {type: string}}}
''', generation: const GenerationConfig(union: UnionMode.structural));
      final (ir, types) = mapComponents(fixture, ['Pick', 'Real']);
      expect(types['Pick'], 'Pick');
      expect(fieldsOf(ir, 'Pick'), ['a(a): String?', 'b(b): String?']);
      expect(fixture.codes, [
        (
          DiagnosticCode.oneOfConstraintsIgnored,
          '#/components/schemas/Pick/anyOf',
        ),
        (
          DiagnosticCode.compositionPartsIgnored,
          '#/components/schemas/Real/properties',
        ),
      ]);
    });

    test('branches that only add constraints leave a model (TOA255)', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Contact:
      type: object
      properties: {email: {type: string}, phone: {type: string}}
      oneOf: [{required: [email]}, {required: [phone]}]
    Contact2:
      type: object
      properties: {email: {type: string}, phone: {type: string}}
      anyOf: [{required: [email]}, {required: [phone]}]
    Contact3:
      type: object
      oneOf: [{required: [email]}, {required: [phone]}]
''');
      final (ir, types) = mapComponents(fixture, [
        'Contact',
        'Contact2',
        'Contact3',
      ]);
      expect(types, {
        'Contact': 'Contact',
        'Contact2': 'Contact2',
        'Contact3': 'Map<String, JsonValue>',
      });
      expect(fieldsOf(ir, 'Contact'), [
        'email(email): String?',
        'phone(phone): String?',
      ]);
      expect(fieldsOf(ir, 'Contact2'), [
        'email(email): String?',
        'phone(phone): String?',
      ]);
      expect(fixture.codes, [
        (
          DiagnosticCode.oneOfConstraintsIgnored,
          '#/components/schemas/Contact/oneOf',
        ),
        (
          DiagnosticCode.oneOfConstraintsIgnored,
          '#/components/schemas/Contact2/anyOf',
        ),
      ]);
    });

    test('const branches of one type are one enum, with no diagnostic', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Color: {type: string, oneOf: [{const: red}, {const: green}]}
    Size: {type: string, anyOf: [{const: s}, {enum: [m, l]}, {type: 'null'}]}
    Holder:
      type: object
      properties:
        color: {$ref: '#/components/schemas/Color'}
        size: {$ref: '#/components/schemas/Size'}
''');
      final (ir, _) = mapComponents(fixture, ['Holder']);
      expect(fixture.reported, isEmpty);
      expect(fieldsOf(ir, 'Holder'), [
        'color(color): Color?',
        'size(size): Size?',
      ]);
      expect(declaration<EnumDecl>(ir, 'Color').values.map((v) => v.value), [
        'red',
        'green',
      ]);
      expect(declaration<EnumDecl>(ir, 'Size').values.map((v) => v.value), [
        's',
        'm',
        'l',
      ]);
    });

    test('a branch that is a type keeps the union', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    A: {type: object, properties: {a: {type: string}}}
    Mixed: {oneOf: [{const: x}, {$ref: '#/components/schemas/A'}]}
''');
      final (ir, _) = mapComponents(fixture, ['Mixed']);
      expect(variantsOf(ir, 'Mixed'), ['MixedVariant1', 'A']);
      expect(fixture.reported, isEmpty);
    });

    test('properties beside a union of types are ignored with TOA256', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    A: {type: object, properties: {a: {type: string}}}
    B: {type: object, properties: {b: {type: string}}}
    U:
      properties: {kind: {type: string}}
      oneOf: [{$ref: '#/components/schemas/A'}, {$ref: '#/components/schemas/B'}]
''', generation: const GenerationConfig(union: UnionMode.structural));
      final (ir, _) = mapComponents(fixture, ['U']);
      expect(variantsOf(ir, 'U'), ['A', 'B']);
      expect(fixture.codes, [
        (
          DiagnosticCode.compositionPartsIgnored,
          '#/components/schemas/U/properties',
        ),
      ]);
      expect(
        fixture.reported.single.message,
        'The properties of this schema are ignored: it is generated as the '
        'union of its oneOf branches.',
      );
    });

    test('the discriminator property beside a union is not ignored', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    A: {type: object, properties: {type: {type: string}}}
    B: {type: object, properties: {type: {type: string}}}
    U:
      properties: {type: {type: string}}
      required: [type]
      oneOf: [{$ref: '#/components/schemas/A'}, {$ref: '#/components/schemas/B'}]
      discriminator: {propertyName: type}
''');
      final (ir, _) = mapComponents(fixture, ['U']);
      expect(variantsOf(ir, 'U'), ['A', 'B']);
      expect(fixture.reported, isEmpty);
    });

    test('constraint branches inside an allOf part are TOA255', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Contact:
      allOf:
        - type: object
          properties: {email: {type: string}, phone: {type: string}}
        - oneOf: [{required: [email]}, {required: [phone]}]
''');
      final (ir, _) = mapComponents(fixture, ['Contact']);
      expect(fieldsOf(ir, 'Contact'), [
        'email(email): String?',
        'phone(phone): String?',
      ]);
      expect(fixture.codes, [
        (
          DiagnosticCode.oneOfConstraintsIgnored,
          '#/components/schemas/Contact/allOf/1/oneOf',
        ),
      ]);
    });

    test('branches beside allOf parts are ignored with TOA256', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    A: {type: object, properties: {a: {type: string}}}
    B: {type: object, properties: {b: {type: string}}}
    Base: {type: object, properties: {id: {type: integer}}}
    M:
      allOf: [{$ref: '#/components/schemas/Base'}]
      oneOf: [{$ref: '#/components/schemas/A'}, {type: 'null'}]
''');
      final (ir, _) = mapComponents(fixture, ['M']);
      expect(fieldsOf(ir, 'M'), ['id(id): int?']);
      expect(fixture.codes, [
        (
          DiagnosticCode.compositionPartsIgnored,
          '#/components/schemas/M/oneOf',
        ),
      ]);
    });
  });

  group(r'allOf of one $ref and annotation-only parts (final review I1)', () {
    const specTail = r'''
components:
  schemas:
    Pet: {type: object, properties: {name: {type: string}}}
    Color: {type: string, description: A color, enum: [red, green]}
    Choice:
      oneOf: [{$ref: '#/components/schemas/Cat'}, {$ref: '#/components/schemas/Dog'}]
    Cat: {type: object, properties: {meow: {type: string}}}
    Dog: {type: object, properties: {bark: {type: string}}}
    Holder:
      type: object
      properties:
        pet:
          allOf: [{$ref: '#/components/schemas/Pet'}, {nullable: true}]
        color:
          allOf: [{$ref: '#/components/schemas/Color'}, {description: Mine}]
        choice:
          allOf: [{$ref: '#/components/schemas/Choice'}, {nullable: true, description: Which}]
        noted:
          allOf:
            - $ref: '#/components/schemas/Pet'
            - {description: Noted, default: {name: rex}, deprecated: true, title: T}
        plain:
          allOf: [{$ref: '#/components/schemas/Pet'}, {description: Plain}]
''';
    const head = 'openapi: 3.0.3\ninfo: {title: t, version: "1"}\n';

    test('is a reference to the target, nullable when a part says so', () {
      final fixture = IrFixture(
        '$head$specTail',
        generation: const GenerationConfig(union: UnionMode.structural),
      );
      final (ir, _) = mapComponents(fixture, ['Holder']);
      expect(fixture.reported, isEmpty);
      expect(fieldsOf(ir, 'Holder'), [
        'pet(pet): Pet?',
        'color(color): Color?',
        'choice(choice): Choice?',
        'noted(noted): Pet?',
        'plain(plain): Pet?',
      ]);
      expect(ir.declarations.map((d) => d.name), [
        'Cat',
        'Choice',
        'Color',
        'Dog',
        'Holder',
        'Pet',
      ]);
    });

    test('keeps the annotations of the parts for the field', () {
      final fixture = IrFixture('$head$specTail');
      final (ir, _) = mapComponents(fixture, ['Holder']);
      final fields = {
        for (final f in declaration<ModelDecl>(ir, 'Holder').fields) f.name: f,
      };
      expect(fields['color']!.description, 'Mine');
      expect(fields['choice']!.description, 'Which');
      expect(fields['pet']!.description, isNull);
      expect(fields['noted']!.description, 'Noted');
      expect(fields['noted']!.defaultValue!.$1, {'name': 'rex'});
      expect(fields['noted']!.deprecated, isTrue);
      expect(fields['plain']!.deprecated, isFalse);
    });

    test('a 3.1 type: null part makes the reference nullable', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Pet: {type: object, properties: {name: {type: string}}}
    Holder:
      type: object
      properties:
        pet: {allOf: [{$ref: '#/components/schemas/Pet'}, {type: 'null'}]}
''');
      final (ir, _) = mapComponents(fixture, ['Holder']);
      expect(fixture.reported, isEmpty);
      expect(fieldsOf(ir, 'Holder'), ['pet(pet): Pet?']);
      expect(ir.declarations.map((d) => d.name), ['Holder', 'Pet']);
    });

    test('a part with structure is still merged', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Pet: {type: object, properties: {name: {type: string}}}
    Strict:
      allOf: [{$ref: '#/components/schemas/Pet'}, {required: [name]}]
''');
      final (ir, _) = mapComponents(fixture, ['Strict']);
      expect(fieldsOf(ir, 'Strict'), ['name(name): String']);
    });

    test('a request body of annotation-only parts is the target model', () {
      final fixture = IrFixture(r'''
openapi: 3.0.3
info: {title: t, version: "1"}
paths:
  /pets:
    patch:
      operationId: patchPet
      requestBody:
        content:
          application/json:
            schema:
              allOf: [{$ref: '#/components/schemas/Pet'}, {nullable: true}]
      responses: {'204': {description: ok}}
components:
  schemas:
    Pet: {type: object, properties: {name: {type: string}}}
''');
      final ir = IrBuilder(
        fixture.diagnostics,
      ).build(fixture.context.spec, fixture.context.client);
      expect(ir.declarations.map((d) => d.name), ['Pet']);
      expect(fixture.reported.map((d) => d.code), [
        DiagnosticCode.operationUntagged,
      ]);
    });
  });

  group(r'annotations beside a $ref (final review I2)', () {
    const specTail = r'''
components:
  schemas:
    Status: {type: string, description: Status of anything, enum: [on, off]}
    Old: {type: string, deprecated: true, default: x}
    Holder:
      type: object
      properties:
        status:
          $ref: '#/components/schemas/Status'
          description: The pet status
          default: 'on'
          deprecated: true
        inherited: {$ref: '#/components/schemas/Status'}
        old: {$ref: '#/components/schemas/Old', default: y}
''';

    test('3.1 takes description, default and deprecated of the property', () {
      final fixture = IrFixture(
        'openapi: 3.1.0\ninfo: {title: t, version: "1"}\n$specTail',
      );
      final (ir, _) = mapComponents(fixture, ['Holder']);
      final fields = {
        for (final f in declaration<ModelDecl>(ir, 'Holder').fields) f.name: f,
      };
      expect(fields['status']!.description, 'The pet status');
      expect(fields['status']!.defaultValue, ('on',));
      expect(fields['status']!.deprecated, isTrue);
      // Without siblings the target's keywords are used.
      expect(fields['inherited']!.description, 'Status of anything');
      expect(fields['inherited']!.deprecated, isFalse);
      expect(fields['old']!.defaultValue, ('y',));
      expect(fields['old']!.deprecated, isTrue);
    });

    test(r'3.0 has no siblings of a $ref: the target is used', () {
      final fixture = IrFixture(
        'openapi: 3.0.3\ninfo: {title: t, version: "1"}\n$specTail',
      );
      final (ir, _) = mapComponents(fixture, ['Holder']);
      final status = declaration<ModelDecl>(
        ir,
        'Holder',
      ).fields.firstWhere((f) => f.name == 'status');
      expect(status.description, 'Status of anything');
      expect(status.defaultValue, isNull);
      expect(status.deprecated, isFalse);
    });
  });

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
      expect(variantsOf(ir, 'P'), ['A', 'B']);
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
      String? extra(String name) => declaration<ModelDecl>(
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
      final pet = declaration<UnionDecl>(ir, 'Pet');
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
      expect(declaration<UnionDecl>(ir, 'Pet').defaultVariant, isNull);
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
