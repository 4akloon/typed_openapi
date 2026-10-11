import 'package:test/test.dart';
import 'package:typed_openapi/src/config/project_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/model/schema.dart';
import 'package:typed_openapi/src/normalize/normalizer.dart';
import 'package:typed_openapi/src/normalize/rules/bool_required_to_array.dart';
import 'package:typed_openapi/src/normalize/rules/drop_invalid_default.dart';

void main() {
  /// Normalizes the 3.0 document whose `components.schemas` are [schemas]
  /// with every rule.
  (NormalizedSpec, DiagnosticBag) normalize(String schemas, {Preset? preset}) {
    final bag = DiagnosticBag();
    final document = SpecLoader(bag).parse(
      'openapi: 3.0.3\ninfo: {title: Shop, version: "1"}\n'
          'components:\n  schemas:\n$schemas',
      'api.yaml',
    )!;
    final result = Normalizer(bag, preset: preset).normalize(document, .v30);
    return (result, bag);
  }

  Map<String, Object?> schemaIn(NormalizedSpec result, String name) =>
      ((result.documents.root.root['components']! as Map)['schemas']!
              as Map)[name]!
          as Map<String, Object?>;

  test('the fix rules are registered once, in this order', () {
    expect(
      Normalizer.rules.map((r) => r.name),
      containsAllInOrder(['bool-required-to-array', 'drop-invalid-default']),
    );
    expect(Normalizer.ruleNames, hasLength(Normalizer.rules.length));
    expect(const BoolRequiredToArray().codes, [DiagnosticCode.boolRequired]);
    expect(const DropInvalidDefault().codes, [DiagnosticCode.invalidDefault]);
  });

  group('bool-required-to-array', () {
    test('required: true moves the name into the object\'s list', () {
      final (result, bag) = normalize('''
    Order:
      type: object
      required: [id]
      properties:
        id: {type: string}
        note: {type: string, required: true}
        total: {type: number, required: true}
        coupon: {type: string, required: false}
''');
      expect(schemaIn(result, 'Order'), {
        'type': 'object',
        'required': ['id', 'note', 'total'],
        'properties': {
          'id': {'type': 'string'},
          'note': {'type': 'string'},
          'total': {'type': 'number'},
          'coupon': {'type': 'string'},
        },
      });
      final order =
          result.model.document.components!.schemas['Order']! as SchemaObject;
      expect(order.required, ['id', 'note', 'total']);
      expect(bag.all.map((d) => (d.code, d.pointer?.value)), [
        (
          DiagnosticCode.boolRequired,
          '#/components/schemas/Order/properties/note/required',
        ),
        (
          DiagnosticCode.boolRequired,
          '#/components/schemas/Order/properties/total/required',
        ),
        (
          DiagnosticCode.boolRequired,
          '#/components/schemas/Order/properties/coupon/required',
        ),
      ]);
      expect(bag.all.first.severity, Severity.warning);
      expect(bag.all.first.line, 10);
    });

    test('an object without a list gets one', () {
      final (result, bag) = normalize('''
    Tag:
      type: object
      properties:
        name: {type: string, required: true}
''');
      expect(schemaIn(result, 'Tag')['required'], ['name']);
      expect(bag.all.single.message, contains('"name"'));
    });

    test('a required property that has required properties itself', () {
      final (result, bag) = normalize('''
    Order:
      type: object
      properties:
        address:
          type: object
          required: true
          properties:
            city: {type: string, required: true}
''');
      expect(schemaIn(result, 'Order')['required'], ['address']);
      final address =
          (schemaIn(result, 'Order')['properties']! as Map)['address']! as Map;
      expect(address['required'], ['city']);
      expect(bag.all.map((d) => d.code), [
        DiagnosticCode.boolRequired,
        DiagnosticCode.boolRequired,
      ]);
      expect(
        bag.all.where((d) => d.code == DiagnosticCode.invalidValue),
        isEmpty,
      );
    });

    test('a parent whose required is not a list is left alone', () {
      final (result, bag) = normalize('''
    Tag:
      type: object
      required: "z"
      properties:
        name: {type: string, required: true}
''');
      final tag = schemaIn(result, 'Tag');
      expect(tag['required'], 'z');
      expect((tag['properties']! as Map)['name'], {
        'type': 'string',
        'required': true,
      });
      // The parser keeps its TOA111 on the parent's list and on the flag that
      // could not be moved.
      final codes = {for (final d in bag.all) (d.code, d.pointer?.value)};
      expect(
        codes,
        containsAll([
          (DiagnosticCode.invalidValue, '#/components/schemas/Tag/required'),
          (
            DiagnosticCode.boolRequired,
            '#/components/schemas/Tag/properties/name/required',
          ),
        ]),
      );
      final flag = bag.all.singleWhere(
        (d) => d.code == DiagnosticCode.boolRequired,
      );
      expect(flag.fix, contains('a list'));
      expect(
        flag.message,
        'Property "name" says "required: true", the OpenAPI 2 way; OpenAPI 3 '
        'lists required properties in the "required" array of the object, '
        'which has to become a list before the name can be put there.',
      );
      expect(
        bag.all.where((d) => d.code == DiagnosticCode.fixNotApplied),
        isEmpty,
      );
    });

    test('a valid required list is left alone', () {
      final (_, bag) = normalize('''
    Tag:
      type: object
      required: [name]
      properties:
        name: {type: string}
''');
      expect(bag.all, isEmpty);
    });
  });

  group('drop-invalid-default', () {
    test('a default of another type is removed', () {
      final (result, bag) = normalize('''
    Filter:
      type: object
      properties:
        tags: {type: array, items: {type: string}, default: ""}
        limit: {type: integer, default: 2.5}
        page: {type: integer, default: 1}
        sort: {type: string, nullable: true, default: null}
''');
      final properties = schemaIn(result, 'Filter')['properties']! as Map;
      expect(properties['tags'], {
        'type': 'array',
        'items': {'type': 'string'},
      });
      expect((properties['limit']! as Map).containsKey('default'), isFalse);
      expect((properties['page']! as Map)['default'], 1);
      expect((properties['sort']! as Map)['default'], isNull);
      expect(bag.sorted.map((d) => d.pointer?.value), [
        '#/components/schemas/Filter/properties/tags/default',
        '#/components/schemas/Filter/properties/limit/default',
      ]);
      expect(
        bag.sorted.first.message,
        'The default, a string, is not of type array; it is ignored.',
      );
    });

    test('a whole number is an integer, however large', () {
      final (result, bag) = normalize('''
    Limits:
      type: object
      properties:
        max64: {type: integer, default: 18446744073709551615}
        big: {type: integer, default: 1e19}
        whole: {type: integer, default: 3.0}
        half: {type: integer, default: 3.5}
''');
      final properties = schemaIn(result, 'Limits')['properties']! as Map;
      expect((properties['max64']! as Map).containsKey('default'), isTrue);
      expect((properties['big']! as Map).containsKey('default'), isTrue);
      expect((properties['whole']! as Map)['default'], 3.0);
      expect((properties['half']! as Map).containsKey('default'), isFalse);
      expect(bag.all.map((d) => d.code), [DiagnosticCode.invalidDefault]);
    });

    test('nestjs gets a hint about dynamic defaults', () {
      final (_, bag) = normalize(
        '    When: {type: string, format: date-time, default: 0}\n',
        preset: .nestjs,
      );
      expect(bag.all.single.fix, contains('excludeDynamicDefaults'));
    });
  });

  test('SchemaType.accepts follows the JSON type of a plain value', () {
    expect(SchemaType.integer.accepts(1.0), isTrue);
    expect(SchemaType.integer.accepts(1e19), isTrue);
    expect(SchemaType.integer.accepts(-1e300), isTrue);
    expect(SchemaType.integer.accepts(1.5), isFalse);
    expect(SchemaType.integer.accepts(double.infinity), isFalse);
    expect(SchemaType.integer.accepts(double.nan), isFalse);
    expect(SchemaType.number.accepts(1), isTrue);
    expect(SchemaType.number.accepts('1'), isFalse);
    expect(SchemaType.nullType.accepts(null), isTrue);
    expect(SchemaType.string.accepts(null), isFalse);
    expect(SchemaType.array.accepts(<Object?>[]), isTrue);
    expect(SchemaType.object.accepts(<String, Object?>{}), isTrue);
    expect(SchemaType.boolean.accepts(0), isFalse);
  });
}
