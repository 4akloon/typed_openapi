import 'package:test/test.dart';
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/ir/dart_type.dart';
import 'package:typed_openapi/src/ir/ir.dart';
import 'package:typed_openapi/src/ir/ir_json.dart';
import 'package:typed_openapi/src/overrides/override_set.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/mapping.dart';

void main() {
  test('maps types and formats (R6.2)', () {
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    All:
      type: object
      required: [id, big, price, ratio, amount, name, at, day, raw, file, ok, tags, meta, any, extra, uuid]
      properties:
        id: {type: integer}
        big: {type: integer, format: int64}
        price: {type: number, format: double}
        ratio: {type: number, format: float}
        amount: {type: number}
        name: {type: string}
        at: {type: string, format: date-time}
        day: {type: string, format: date}
        raw: {type: string, format: byte}
        file: {type: string, format: binary}
        ok: {type: boolean}
        tags: {type: array, items: {type: string}}
        meta: {type: object, additionalProperties: {type: integer}}
        any: {}
        extra: {type: object}
        uuid: {type: string, format: uuid}
''');
    final (ir, types) = mapComponents(fixture, ['All']);
    expect(fixture.reported, isEmpty);
    expect(types, {'All': 'All'});
    expect(fieldsOf(ir, 'All'), [
      'id(id): int',
      'big(big): int',
      'price(price): double',
      'ratio(ratio): double',
      'amount(amount): num',
      'name(name): String',
      'at(at): DateTime',
      'day(day): Date',
      'raw(raw): Uint8List',
      'file(file): Uint8List',
      'ok(ok): bool',
      'tags(tags): List<String>',
      'meta(meta): Map<String, int>',
      'any(any): JsonValue',
      'extra(extra): Map<String, JsonValue>',
      'uuid(uuid): String',
    ]);
  });

  test('applies the required x nullable matrix (R6.1)', () {
    final fixture = IrFixture(r'''
openapi: 3.0.3
info: {title: t, version: "1"}
components:
  schemas:
    Pet:
      type: object
      required: [a, b]
      properties:
        a: {type: string}
        b: {type: string, nullable: true}
        c: {type: string}
        d: {type: string, nullable: true}
        owner: {$ref: '#/components/schemas/Owner'}
    Owner:
      type: object
      properties:
        name: {type: string}
''');
    final (ir, _) = mapComponents(fixture, ['Pet']);
    expect(fixture.reported, isEmpty);
    expect(fieldsOf(ir, 'Pet'), [
      'a(a): String',
      'b(b): String?',
      'c(c): String?',
      'd(d): String?',
      'owner(owner): Owner?',
    ]);
    expect(ir.declarations.map((d) => d.name), ['Owner', 'Pet']);
  });

  test('names inline schemas after their parent and dedupes inline enums '
      '(R5.4)', () {
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
      'OrderStatus',
    ]);
    expect(fieldsOf(ir, 'Order'), [
      'status(status): OrderStatus?',
      'state(state): OrderStatus?',
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

  test('uses override names, custom types and the number setting (R6.8)', () {
    final fixture = IrFixture(
      r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Pet:
      type: object
      properties:
        price: {type: string, format: decimal}
        weight: {type: number}
        cost: {$ref: '#/components/schemas/Money'}
        secret: {type: string}
        nick: {type: string}
    Money: {type: object, properties: {amount: {type: string}}}
''',
      generation: const GenerationConfig(
        numberType: 'double',
        formats: {
          'decimal': DartTypeOverride(
            type: 'Decimal',
            import: 'package:decimal/decimal.dart',
          ),
        },
        schemas: {
          'Money': DartTypeOverride(
            type: 'Money',
            import: 'package:app/money.dart',
            converter: 'MoneyConverter',
          ),
        },
      ),
      overrides: '''
schemas:
  Pet:
    name: Animal
    properties:
      secret: {exclude: true}
      nick: {name: nickname}
''',
    );
    final (ir, types) = mapComponents(fixture, ['Pet']);
    expect(fixture.reported, isEmpty);
    expect(types, {'Pet': 'Animal'});
    expect(fieldsOf(ir, 'Animal'), [
      'price(price): Decimal?',
      'weight(weight): double?',
      'cost(cost): Money?',
      'nickname(nick): String?',
    ]);
    expect(ir.declarations.map((d) => d.name), ['Animal']);
    final cost = (ir.declarations.single as ModelDecl).fields[2].valueType;
    expect(cost, isA<CustomType>());
    expect((cost as CustomType).converter, 'MoneyConverter');
    expect(cost.json, const CoreType(.json));
  });

  test('maps a mixed type or mixed enum to JsonValue with a warning', () {
    final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Box:
      type: object
      properties:
        id: {type: [string, integer]}
        mark: {enum: [a, 1]}
        maybe: {type: [string, "null"]}
    Tree: {type: array, items: {$ref: '#/components/schemas/Tree'}}
''');
    final (ir, types) = mapComponents(fixture, ['Box', 'Tree']);
    expect(fieldsOf(ir, 'Box'), [
      'id(id): JsonValue',
      'mark(mark): JsonValue',
      'maybe(maybe): String?',
    ]);
    expect(types['Tree'], 'List<JsonValue>');
    expect(fixture.codes, [
      (
        DiagnosticCode.mixedTypeSchema,
        '#/components/schemas/Box/properties/id',
      ),
      (
        DiagnosticCode.enumMixedValues,
        '#/components/schemas/Box/properties/mark',
      ),
      (DiagnosticCode.recursiveAlias, '#/components/schemas/Tree'),
    ]);
  });

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
      // parent, in either mapping order.
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
        expect(names.where((n) => n.endsWith('Kind')), hasLength(1));
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
      expect((owner as CustomType).json, const CoreType(.json));
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
