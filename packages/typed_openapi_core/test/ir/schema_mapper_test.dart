import 'package:test/test.dart';
import 'package:typed_openapi_core/src/config/generation_config.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/ir/dart_type.dart';
import 'package:typed_openapi_core/src/ir/ir.dart';
import 'package:typed_openapi_core/src/overrides/override_set.dart';

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
    // An object schema: its JSON side is a map, which `fromJson` takes.
    expect(cost.json, const MapType(CoreType(.json)));
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
}
