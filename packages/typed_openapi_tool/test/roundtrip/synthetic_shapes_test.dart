import 'package:test/test.dart';
import 'package:typed_openapi_core/typed_openapi_core.dart';
import 'package:typed_openapi_tool/src/roundtrip/roundtrip_program.dart';
import 'package:typed_openapi_tool/src/roundtrip/sample.dart';
import 'package:typed_openapi_tool/src/roundtrip/synthetic_values.dart';

import '../helpers/client_ir.dart';

const _spec = r'''
openapi: 3.1.0
info: {title: Shapes, version: "1"}
paths:
  /bag:
    get:
      operationId: getBag
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema: {$ref: "#/components/schemas/Bag"}
  /upload:
    get:
      operationId: getUpload
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema: {$ref: "#/components/schemas/Upload"}
  /value:
    get:
      operationId: getValue
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema: {$ref: "#/components/schemas/Value"}
components:
  schemas:
    Bag:
      type: object
      properties:
        id: {type: string}
      additionalProperties: {type: integer}
    Upload:
      type: object
      required: [file]
      properties:
        file: {type: string, format: binary}
    Value:
      oneOf:
        - {type: string}
        - {type: boolean}
''';

void main() {
  late ClientIr ir;
  late SyntheticValues synthetic;
  late List<Sample> samples;
  setUp(() {
    ir = clientIr(_spec);
    synthetic = SyntheticValues(ir);
    samples = synthetic.all();
  });

  List<Object?> valuesOf(String type) => [
    for (final s in samples)
      if (s.type == type) s.value,
  ];

  test('a model with additional properties gets one under __extra', () {
    expect(valuesOf('Bag'), [
      <String, Object?>{},
      {'id': 'text', '__extra': 1},
    ]);
  });

  test('a variant of a JSON type is a value of that type', () {
    expect(valuesOf('Value'), ['text', true]);
  });

  test('a value no synthetic form exists for is counted as skipped', () {
    expect(valuesOf('Upload'), isEmpty);
    expect(synthetic.attempted - samples.length, equals(2));
  });

  test('the program holds one codec for each declaration', () {
    final source = RoundTripProgram(
      ir,
    ).source('package:corpus_raw/api/models.dart');
    for (final d in ir.declarations) {
      expect(source, contains("  '${d.name}': (decode: "));
    }
    expect(
      source,
      contains("import 'package:corpus_raw/api/models.dart' as m;"),
    );
  });

  test('a sample is encodable only when jsonEncode writes it', () {
    bool encodable(Object? v) => Sample('T', v, isExample: true).isEncodable;
    expect(
      encodable({
        'a': [1, 2.5, null, 'x', true],
      }),
      isTrue,
    );
    expect(encodable(double.nan), isFalse);
    expect(encodable({'a': double.infinity}), isFalse);
    expect(encodable([DateTime(2001)]), isFalse);
    expect(encodable({1: 'x'}), isFalse);
  });
}
