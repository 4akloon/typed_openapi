import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/diagnostics/reporters.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/load/openapi_version.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/model/spec_node.dart';
import 'package:typed_openapi/src/normalize/normalizer.dart';
import 'package:typed_openapi/src/overrides/override_loader.dart';
import 'package:typed_openapi/src/overrides/override_snippet.dart';
import 'package:typed_openapi/src/resolve/spec_reader.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

/// Normalizes [spec] with the overrides in [overrides], if any.
DiagnosticBag _normalize(String spec, {String? overrides}) {
  final bag = DiagnosticBag();
  final document = SpecLoader(bag).parse(spec, 'api.yaml')!;
  final version = OpenApiVersionDetector(bag).detect(document)!;
  final set = overrides == null
      ? null
      : OverrideLoader(bag).parse(overrides, 'o.yaml');
  Normalizer(bag).normalize(document, version, overrides: set);
  return bag;
}

void main() {
  group('addressOf', () {
    late Uri api;
    late Uri pet;
    late OverrideSnippet snippet;

    setUpAll(() {
      final dir = TempDir();
      dir.write('pet.yaml', 'Pet: {type: object, properties: {id: {}}}\n');
      final path = dir.write('api.yaml', r'''
openapi: 3.1.0
info: {title: t, version: '1'}
paths:
  /pets:
    get:
      parameters:
        - {name: q, in: query, schema: {type: string}}
      responses: {'200': {description: ok}}
components:
  schemas:
    Alias: {$ref: '#/components/schemas/Order'}
    Order:
      type: object
      properties:
        lines: {type: array, items: {type: object, properties: {n: {}}}}
    Pet: {$ref: 'pet.yaml#/Pet'}
''');
      final bag = DiagnosticBag();
      final document = SpecLoader(bag).load(path)!;
      final model = SpecReader(bag).read(document, OpenApiVersion.v31);
      snippet = OverrideSnippet(model);
      api = document.uri;
      pet = api.resolve('pet.yaml');
    });

    SpecLocation at(String pointer, [Uri? file]) =>
        SpecLocation(file ?? api, JsonPointer.parse(pointer));

    test('names a components schema by the key that defines it', () {
      expect(snippet.addressOf(at('#/components/schemas/Order')), [
        'schemas',
        'Order',
      ]);
    });

    test('names a property of a components schema', () {
      expect(
        snippet.addressOf(at('#/components/schemas/Order/properties/lines')),
        ['schemas', 'Order', 'properties', 'lines'],
      );
    });

    test(r'follows a key whose $ref leads into another file', () {
      expect(snippet.addressOf(at('#/Pet', pet)), ['schemas', 'Pet']);
      expect(snippet.addressOf(at('#/Pet/properties/id', pet)), [
        'schemas',
        'Pet',
        'properties',
        'id',
      ]);
    });

    test('has no address for schemas the overrides file cannot name', () {
      for (final pointer in [
        '#/paths/~1pets/get/parameters/0/schema',
        '#/components/schemas/Order/properties/lines/items',
        '#/components/schemas/Order/properties/lines/items/properties/n',
        '#/components/schemas/Alias',
      ]) {
        expect(snippet.addressOf(at(pointer)), isNull, reason: pointer);
      }
    });

    test('writes block YAML and quotes what YAML would misread', () {
      expect(
        snippet.forSchema(at('#/components/schemas/Order/properties/lines'), {
          'format': null,
          'items': {
            'type': 'string',
            'enum': ['on', '1.5', 'a b', 2],
          },
          r'$ref': '#/components/schemas/Order',
        }),
        'schemas:\n'
        '  Order:\n'
        '    properties:\n'
        '      lines:\n'
        '        format: null\n'
        '        items: {type: string, enum: ["on", "1.5", "a b", 2]}\n'
        r'        $ref: "#/components/schemas/Order"',
      );
    });
  });

  test('a value YAML cannot carry gives no snippet', () {
    final dir = TempDir();
    final path = dir.write('api.yaml', '''
openapi: 3.1.0
info: {title: t, version: '1'}
paths: {}
components:
  schemas:
    Order: {type: object}
''');
    final bag = DiagnosticBag();
    final document = SpecLoader(bag).load(path)!;
    final snippet = OverrideSnippet(
      SpecReader(bag).read(document, OpenApiVersion.v31),
    );
    final order = SpecLocation(
      document.uri,
      JsonPointer.parse('#/components/schemas/Order'),
    );
    expect(snippet.forSchema(order, {'default': 1.5}), isNotNull);
    for (final value in [double.infinity, double.nan]) {
      expect(snippet.forSchema(order, {'default': value}), isNull);
      expect(
        snippet.forSchema(order, {
          'items': {
            'x': [value],
          },
        }),
        isNull,
      );
    }
  });

  group('rule fixes carry an override that removes the finding', () {
    const header = '''
openapi: 3.0.3
info: {title: t, version: '1'}
paths: {}
''';
    final cases = {
      DiagnosticCode.doubleArray: '''
    Order:
      type: object
      properties:
        lines:
          type: array
          items: {required: true, type: array, items: {type: string}}
''',
      DiagnosticCode.formatOnArray: '''
    Ids: {type: array, format: int64}
''',
      DiagnosticCode.binaryObject: '''
    Upload:
      type: object
      properties:
        file: {type: object, format: binary}
''',
      DiagnosticCode.contradictoryObjectType: '''
    Value:
      type: object
      oneOf: [{type: string}, {type: integer}]
''',
      DiagnosticCode.nullableEnumOneOf: r'''
    Status: {type: string, enum: [a, b]}
    Pet:
      type: object
      properties:
        status:
          oneOf:
            - {enum: [null]}
            - {$ref: '#/components/schemas/Status'}
''',
    };
    for (final MapEntry(key: code, value: schemas) in cases.entries) {
      test(code.slug, () {
        final spec = '${header}components:\n  schemas:\n$schemas';
        final found = _normalize(spec).all.where((d) => d.code == code);
        final fix = found.single.fix!;
        expect(fix, contains(' Override:\nschemas:\n'));
        final overrides = fix.substring(fix.indexOf('\n') + 1);
        final again = _normalize(spec, overrides: overrides);
        expect(again.all.where((d) => d.code == code), isEmpty);
        expect(again.all.where((d) => d.file == 'o.yaml'), isEmpty);
      });
    }

    test('format-on-array has no override for an unknown format', () {
      const spec = '''
openapi: 3.0.3
info: {title: t, version: '1'}
paths: {}
components:
  schemas:
    Prices: {type: array, format: money}
    Days: {type: array, format: date}
''';
      final found = _normalize(
        spec,
      ).all.where((d) => d.code == DiagnosticCode.formatOnArray).toList();
      final [days, prices] = found;
      expect(days.pointer?.value, '#/components/schemas/Days/format');
      expect(days.fix, contains('items: {type: string, format: date}'));
      expect(prices.pointer?.value, '#/components/schemas/Prices/format');
      expect(prices.fix, isNot(contains('Override:')));
      expect(prices.fix, contains('the element schema'));
    });

    test(r'a 3.0 property that is a $ref with siblings gets no override', () {
      const spec = r'''
openapi: 3.0.3
info: {title: t, version: '1'}
paths: {}
components:
  schemas:
    Other: {type: string}
    Upload:
      type: object
      properties:
        file: {$ref: '#/components/schemas/Other', type: object, format: binary}
''';
      final d = _normalize(
        spec,
      ).all.singleWhere((d) => d.code == DiagnosticCode.binaryObject);
      expect(d.fix, isNot(contains('Override:')));
    });

    test('a double array with a non-finite number is reported, no snippet', () {
      const head = '''
openapi: 3.0.3
info: {title: t, version: '1'}
paths: {}
''';
      final specs = {
        'yaml':
            '${head}components:\n  schemas:\n    Order:\n'
            '      type: object\n      properties:\n        lines:\n'
            '          type: array\n          items:\n'
            '            required: true\n            type: array\n'
            '            items: {type: number, default: .inf}\n',
        'json':
            '{"openapi": "3.0.3", "info": {"title": "t", "version": "1"}, '
            '"paths": {}, "components": {"schemas": {"Order": {"type": '
            '"object", "properties": {"lines": {"type": "array", "items": '
            '{"required": true, "type": "array", "items": '
            '{"type": "number", "maximum": 1e999}}}}}}}}',
      };
      for (final MapEntry(:key, :value) in specs.entries) {
        final d = _normalize(
          value,
        ).all.singleWhere((d) => d.code == DiagnosticCode.doubleArray);
        expect(d.fix, isNot(contains('Override:')), reason: key);
      }
    });

    test('a schema without an address gets no override', () {
      const spec = '''
openapi: 3.0.3
info: {title: t, version: '1'}
paths:
  /files:
    post:
      requestBody:
        content:
          application/json: {schema: {type: object, format: binary}}
      responses: {'200': {description: ok}}
''';
      final d = _normalize(
        spec,
      ).all.singleWhere((d) => d.code == DiagnosticCode.binaryObject);
      expect(d.fix, isNot(contains('Override:')));
    });
  });

  test('the text report indents the lines of a multi-line fix', () {
    final bag = DiagnosticBag()
      ..add(
        const Diagnostic(
          code: DiagnosticCode.binaryObject,
          severity: Severity.warning,
          message: 'm',
          fix: 'Do it. Override:\nschemas:\n  A:\n    type: string',
        ),
      );
    expect(
      const TextReporter().format(bag),
      'warning TOA205 binary-object: m\n'
      '  fix: Do it. Override:\n'
      '    schemas:\n'
      '      A:\n'
      '        type: string\n'
      'errors: 0, warnings: 1, infos: 0',
    );
  });
}
