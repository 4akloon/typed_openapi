import 'package:test/test.dart';
import 'package:typed_openapi_core/src/config/generation_config.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/ir/dart_type.dart';
import 'package:typed_openapi_core/src/ir/ir.dart';
import 'package:typed_openapi_core/src/overrides/override_set.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/mapping.dart';

void main() {
  test('names inline schemas after their parent, an equal inline enum '
      'included (R5.4)', () {
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Order:
      type: object
      properties:
        status: {type: string, enum: [placed, in-progress, "2"]}
        state: {type: string, enum: [placed, in-progress, "2"]}
        items:
          type: array
          items:
            type: object
            properties:
              sku: {type: string}
        kind: {const: order}
        prices: {type: object, additionalProperties: {type: object, properties: {amount: {type: number}}}}
''');
    final (ir, _) = mapComponents(fixture, ['Order']);
    expect(fixture.reported, isEmpty);
    expect(ir.declarations.map((d) => d.name), [
      'Order',
      'OrderItemsItem',
      'OrderPricesValue',
      'OrderState',
      'OrderStatus',
    ]);
    expect(fieldsOf(ir, 'Order'), [
      'status(status): OrderStatus?',
      'state(state): OrderState?',
      'items(items): List<OrderItemsItem>?',
      'kind(kind): String?',
      'prices(prices): Map<String, OrderPricesValue>?',
    ]);
    final status =
        ir.declarations.firstWhere((d) => d.name == 'OrderStatus') as EnumDecl;
    expect(status.kind, EnumKind.string);
    expect(status.values.map((v) => (v.name, v.value)), [
      ('placed', 'placed'),
      ('inProgress', 'in-progress'),
      ('value2', '2'),
    ]);
  });

  test('names enum values of numbers, booleans and x-enum-varnames', () {
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Level: {type: integer, enum: [1, -1, 2]}
    Ratio: {type: number, enum: [0.5, 1]}
    Flag: {type: boolean, enum: [true, false]}
    Code:
      type: integer
      enum: [200, 404]
      x-enum-varnames: [ok, not_found]
      x-enum-descriptions: [Fine, Missing]
''');
    final (ir, _) = mapComponents(fixture, ['Level', 'Ratio', 'Flag', 'Code']);
    List<(String, Object)> values(String name) => [
      for (final v
          in (ir.declarations.firstWhere((d) => d.name == name) as EnumDecl)
              .values)
        (v.name, v.value),
    ];
    expect(values('Level'), [
      ('value1', 1),
      ('valueMinus1', -1),
      ('value2', 2),
    ]);
    expect(values('Ratio'), [('value0_5', 0.5), ('value1', 1)]);
    expect(values('Flag'), [('true_', true), ('false_', false)]);
    expect(values('Code'), [('ok', 200), ('notFound', 404)]);
    expect(
      (ir.declarations.firstWhere((d) => d.name == 'Ratio') as EnumDecl).kind,
      EnumKind.number,
    );
    expect(fixture.codes, [
      (DiagnosticCode.nameReserved, '#/components/schemas/Flag'),
      (DiagnosticCode.nameReserved, '#/components/schemas/Flag'),
    ]);
  });

  test('suffixes reserved and colliding names with a diagnostic (R5.2)', () {
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    List:
      type: object
      properties:
        class: {type: string}
        pet_id: {type: string}
        petId: {type: string}
        toJson: {type: string}
    pet: {type: object, properties: {a: {type: string}}}
    Pet: {type: object, properties: {a: {type: string}}}
''');
    final (ir, types) = mapComponents(fixture, ['List', 'pet', 'Pet']);
    expect(types, {'List': 'ListModel', 'pet': 'Pet2', 'Pet': 'Pet'});
    expect(fieldsOf(ir, 'ListModel'), [
      'class_(class): String?',
      'petId(pet_id): String?',
      'petId2(petId): String?',
      'toJson_(toJson): String?',
    ]);
    expect(fixture.codes, [
      (DiagnosticCode.nameReserved, '#/components/schemas/List'),
      (DiagnosticCode.nameCollision, '#/components/schemas/pet'),
      (
        DiagnosticCode.nameReserved,
        '#/components/schemas/List/properties/class',
      ),
      (
        DiagnosticCode.nameCollision,
        '#/components/schemas/List/properties/petId',
      ),
      (
        DiagnosticCode.nameReserved,
        '#/components/schemas/List/properties/toJson',
      ),
    ]);
    expect(
      fixture.reported[1].message,
      'Another type is named "Pet"; this one is named "Pet2".',
    );
    expect(fixture.reported[1].fix, '''
Name the type explicitly to keep the name stable. Override:
schemas:
  pet:
    name: Pet2''');
  });

  group('declaration identity', () {
    test('declares the inline types of a structural alias once, however '
        'often it is used', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Tags:
      type: array
      items:
        type: object
        properties:
          kind: {type: string, enum: [a, b]}
    U:
      type: object
      properties:
        a: {$ref: '#/components/schemas/Tags'}
        b: {$ref: '#/components/schemas/Tags'}
''');
      final (ir, types) = mapComponents(fixture, ['U', 'Tags']);
      expect(fixture.reported, isEmpty);
      expect(types, {'U': 'U', 'Tags': 'List<TagsItem>'});
      expect(ir.declarations.map((d) => d.name), [
        'TagsItem',
        'TagsItemKind',
        'U',
      ]);
      expect(fieldsOf(ir, 'U'), [
        'a(a): List<TagsItem>?',
        'b(b): List<TagsItem>?',
      ]);
    });

    test('declares the inline types of an allOf base once for every model '
        'that merges it', () {
      final fixture = IrFixture(r'''
openapi: 3.0.3
info: {title: t, version: "1"}
components:
  schemas:
    Base:
      type: object
      properties:
        addr:
          type: object
          properties:
            kind: {type: string, enum: [home, work]}
    Pet:
      allOf:
        - {$ref: '#/components/schemas/Base'}
        - {type: object, properties: {tag: {type: string}}}
    Cat:
      allOf:
        - {$ref: '#/components/schemas/Base'}
        - {type: object, properties: {lives: {type: integer}}}
''');
      final (ir, _) = mapComponents(fixture, ['Pet', 'Cat']);
      expect(fixture.reported, isEmpty);
      expect(ir.declarations.map((d) => d.name), [
        'Cat',
        'Pet',
        'PetAddr',
        'PetAddrKind',
      ]);
      expect(fieldsOf(ir, 'Pet'), [
        'addr(addr): PetAddr?',
        'tag(tag): String?',
      ]);
      expect(fieldsOf(ir, 'Cat'), [
        'addr(addr): PetAddr?',
        'lives(lives): int?',
      ]);
    });

    test('declares the inline part of a collapsed allOf alias once', () {
      final fixture = IrFixture(r'''
openapi: 3.0.3
info: {title: t, version: "1"}
components:
  schemas:
    E:
      allOf:
        - type: object
          properties:
            a: {type: string, enum: [a, b]}
    U:
      type: object
      properties:
        e: {$ref: '#/components/schemas/E'}
        e2: {$ref: '#/components/schemas/E'}
''');
      final (ir, types) = mapComponents(fixture, ['U', 'E']);
      expect(fixture.reported, isEmpty);
      expect(types, {'U': 'U', 'E': 'E'});
      expect(ir.declarations.map((d) => d.name), ['E', 'EA', 'U']);
      expect(fieldsOf(ir, 'U'), ['e(e): E?', 'e2(e2): E?']);
    });

    test('names an inline enum after a declaration that exists', () {
      // Two uses of one list alias whose item is an object with an enum, and
      // a second owner of an equal enum: every hint resolves to a declared
      // parent, in either mapping order, and each site has its own enum.
      const spec = r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Tags:
      type: array
      items:
        type: object
        properties:
          kind: {type: string, enum: [a, b]}
    Other:
      type: object
      properties:
        kind: {type: string, enum: [a, b]}
    U:
      type: object
      properties:
        a: {$ref: '#/components/schemas/Tags'}
        o: {$ref: '#/components/schemas/Other'}
        b: {$ref: '#/components/schemas/Tags'}
''';
      for (final order in [
        ['U', 'Tags', 'Other'],
        ['Tags', 'Other', 'U'],
        ['Other', 'U', 'Tags'],
      ]) {
        final (ir, _) = mapComponents(IrFixture(spec), order);
        final names = ir.declarations.map((d) => d.name).toList();
        expect(names.toSet().length, names.length, reason: '$order');
        expect(names, contains('Other'), reason: '$order');
        expect(names, contains('TagsItem'), reason: '$order');
        expect(names.where((n) => n.endsWith('Kind')), hasLength(2));
      }
    });

    test('does not declare what a property dartType replaces (R4.2)', () {
      final fixture = IrFixture(
        r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Pet:
      type: object
      properties:
        price: {type: object, properties: {amount: {type: string}}}
        kind: {type: string, enum: [cat, dog]}
        owner: {$ref: '#/components/schemas/Owner'}
        mixed: {type: [string, integer]}
        plain: {type: string}
    Owner: {type: object, properties: {name: {type: string}}}
''',
        overrides: '''
schemas:
  Pet:
    properties:
      price: {dartType: {type: Money, import: 'package:app/money.dart'}}
      kind: {dartType: {type: Kind, import: 'package:app/kind.dart'}}
      owner: {dartType: {type: Person, import: 'package:app/person.dart'}}
      mixed: {dartType: {type: Either, import: 'package:app/either.dart'}}
''',
      );
      final (ir, _) = mapComponents(fixture, ['Pet']);
      expect(ir.declarations.map((d) => d.name), ['Pet']);
      // Nothing under a replaced schema is reported either (TOA250).
      expect(fixture.reported, isEmpty);
      expect(fieldsOf(ir, 'Pet'), [
        'price(price): Money?',
        'kind(kind): Kind?',
        'owner(owner): Person?',
        'mixed(mixed): Either?',
        'plain(plain): String?',
      ]);
      final owner = (ir.declarations.single as ModelDecl).fields[2].valueType;
      expect((owner as CustomType).json, const MapType(CoreType(.json)));
    });

    test('maps a recursive structural alias with a custom type without '
        'overflowing', () {
      final fixture = IrFixture(
        r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Tree: {type: array, items: {$ref: '#/components/schemas/Tree'}}
    Forest: {type: object, additionalProperties: {$ref: '#/components/schemas/Forest'}}
    Holder:
      type: object
      properties:
        tree: {$ref: '#/components/schemas/Tree'}
        forest: {$ref: '#/components/schemas/Forest'}
''',
        generation: const GenerationConfig(
          schemas: {
            'Tree': DartTypeOverride(type: 'Tree', import: 'package:a/t.dart'),
          },
        ),
        overrides: '''
schemas:
  Forest: {dartType: {type: Forest, import: 'package:a/f.dart'}}
''',
      );
      final (ir, types) = mapComponents(fixture, ['Holder', 'Tree', 'Forest']);
      expect(types['Tree'], 'Tree');
      expect(types['Forest'], 'Forest');
      expect(fieldsOf(ir, 'Holder'), [
        'tree(tree): Tree?',
        'forest(forest): Forest?',
      ]);
      // The custom types replace the aliases, so there is nothing to fix.
      expect(fixture.reported, isEmpty);
    });

    test('types a recursion through an allOf alias of a declared model', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Base:
      type: object
      properties:
        kids: {type: array, items: {$ref: '#/components/schemas/Node'}}
    Node:
      allOf: [{$ref: '#/components/schemas/Base'}]
''');
      final (ir, types) = mapComponents(fixture, ['Node']);
      expect(fixture.reported, isEmpty);
      expect(types, {'Node': 'Base'});
      expect(fieldsOf(ir, 'Base'), ['kids(kids): List<Base>?']);
    });
  });
}
