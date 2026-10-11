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

    test('nestjs gets a hint about dynamic defaults', () {
      final (_, bag) = normalize(
        '    When: {type: string, format: date-time, default: 0}\n',
        preset: .nestjs,
      );
      expect(bag.all.single.fix, contains('excludeDynamicDefaults'));
    });
  });
}
