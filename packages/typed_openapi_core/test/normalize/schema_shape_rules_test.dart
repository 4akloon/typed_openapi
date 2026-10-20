import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/diagnostics/severity.dart';

import '../helpers/normalizer_fixture.dart';

void main() {
  /// A document of [version] whose `components.schemas` are [schemas].
  String spec(String schemas, {String version = '3.0.3'}) =>
      'openapi: $version\ninfo: {title: Shop, version: "1"}\n'
      'components:\n  schemas:\n$schemas';

  const base = '#/components/schemas';

  group('array-without-items', () {
    const schemas = '''
    Tags: {type: array}
    Ids: {type: array, items: {type: string}}
''';

    test('an array without items in 3.0 is reported', () {
      final run = NormalizerFixture(spec(schemas));
      expect(run.pointersOf(DiagnosticCode.arrayWithoutItems), ['$base/Tags']);
      expect(
        run.of(DiagnosticCode.arrayWithoutItems).single.severity,
        Severity.warning,
      );
    });

    test('3.1 does not require items', () {
      final run = NormalizerFixture(spec(schemas, version: '3.1.0'));
      expect(run.of(DiagnosticCode.arrayWithoutItems), isEmpty);
    });
  });

  test('double-array: items that are arrays with a boolean required', () {
    final run = NormalizerFixture(
      spec('''
    Order:
      type: object
      properties:
        lines:
          type: array
          items:
            required: true
            type: array
            items: {type: string}
'''),
    );
    expect(run.pointersOf(DiagnosticCode.doubleArray), [
      '$base/Order/properties/lines/items',
    ]);
    expect(
      run.of(DiagnosticCode.doubleArray).single.fix,
      contains('inner "items"'),
    );
  });

  test('format-on-array replaces array-without-items for that schema', () {
    final run = NormalizerFixture(
      spec('    Ids: {type: array, format: uuid}\n'),
    );
    expect(run.pointersOf(DiagnosticCode.formatOnArray), ['$base/Ids/format']);
    expect(run.of(DiagnosticCode.arrayWithoutItems), isEmpty);
    expect(
      run.of(DiagnosticCode.formatOnArray).single.fix,
      contains('{type: string, format: uuid}'),
    );
  });

  test('binary-object: a file written as an object', () {
    final run = NormalizerFixture(
      spec('''
    Upload:
      type: object
      properties:
        file: {type: object, format: binary}
        data: {type: string, format: binary}
'''),
    );
    expect(run.pointersOf(DiagnosticCode.binaryObject), [
      '$base/Upload/properties/file/type',
    ]);
  });

  group('contradictory-object-type', () {
    test('object next to branches that are all scalars', () {
      final run = NormalizerFixture(
        spec(r'''
    Amount:
      type: object
      oneOf: [{type: string}, {$ref: '#/components/schemas/Cents'}]
    Cents: {type: integer}
'''),
      );
      final d = run.of(DiagnosticCode.contradictoryObjectType).single;
      expect(d.pointer?.value, '$base/Amount/type');
      expect(d.message, contains('integer, string'));
    });

    test('a branch that may be an object is not reported', () {
      final run = NormalizerFixture(
        spec('''
    Pet:
      type: object
      anyOf: [{type: string}, {type: object}, {description: anything}]
'''),
      );
      expect(run.of(DiagnosticCode.contradictoryObjectType), isEmpty);
    });
  });

  group('example-type-mismatch', () {
    test('a list example for an object, through a one-member allOf', () {
      final run = NormalizerFixture(
        spec(r'''
    Token: {type: object, properties: {value: {type: string}}}
    Session:
      type: object
      properties:
        tokens:
          allOf: [{$ref: '#/components/schemas/Token'}]
          example: [{value: a}, {value: b}]
        count: {type: integer, example: 3}
        ratio: {type: number, example: "1.5"}
'''),
      );
      expect(run.pointersOf(DiagnosticCode.exampleTypeMismatch), [
        '$base/Session/properties/tokens/example',
      ]);
      final scalar = run.of(DiagnosticCode.exampleScalarType).single;
      expect(scalar.pointer?.value, '$base/Session/properties/ratio/example');
      expect(scalar.severity, Severity.info);
      expect(
        run.of(DiagnosticCode.exampleTypeMismatch).first.message,
        'The example is a list, but the schema is object; clients built from '
        'the schema fail on such values.',
      );
    });

    test('allOf members that point at each other end, not loop', () {
      final run = NormalizerFixture(
        spec(r'''
    A: {allOf: [{$ref: '#/components/schemas/B'}], example: 1}
    B: {allOf: [{$ref: '#/components/schemas/A'}]}
'''),
      );
      expect(run.of(DiagnosticCode.exampleTypeMismatch), isEmpty);
    });
  });

  test('nestjs gets the element type recipe for arrays', () {
    final run = NormalizerFixture(
      spec('    Tags: {type: array}\n'),
      preset: .nestjs,
    );
    expect(
      run.of(DiagnosticCode.arrayWithoutItems).single.fix,
      endsWith('@ApiProperty({ type: [Item] }).'),
    );
  });
}
