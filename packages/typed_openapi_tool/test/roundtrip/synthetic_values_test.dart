import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/roundtrip/sample.dart';
import 'package:typed_openapi_tool/src/roundtrip/synthetic_values.dart';

import '../helpers/client_ir.dart';

const _spec = r'''
openapi: 3.1.0
info: {title: Pets, version: "1"}
paths:
  /pets:
    get:
      operationId: getPet
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema: {$ref: "#/components/schemas/Pet"}
components:
  schemas:
    Pet:
      oneOf:
        - {$ref: "#/components/schemas/Cat"}
        - {$ref: "#/components/schemas/Dog"}
      discriminator:
        propertyName: kind
        mapping: {cat: "#/components/schemas/Cat", dog: "#/components/schemas/Dog"}
    Cat:
      type: object
      required: [kind, born]
      properties:
        kind: {type: string}
        born: {type: string, format: date}
        tags: {type: array, items: {type: string}}
    Dog:
      type: object
      required: [kind]
      properties:
        kind: {type: string}
        size: {$ref: "#/components/schemas/Size"}
    Size: {type: string, enum: [small, medium, large]}
''';

void main() {
  late List<Sample> samples;
  setUp(() => samples = SyntheticValues(clientIr(_spec)).all());

  /// The values of the class [type].
  List<Object?> valuesOf(String type) => [
    for (final s in samples)
      if (s.type == type) s.value,
  ];

  test('a model has a value of its required fields and one of all', () {
    expect(valuesOf('Cat'), [
      {'kind': 'text', 'born': '2026-01-02'},
      {
        'kind': 'text',
        'born': '2026-01-02',
        'tags': ['text'],
      },
    ]);
  });

  test('an enum has its first and its last value', () {
    expect(valuesOf('Size'), ['small', 'large']);
  });

  test('each variant of a union carries its discriminator value', () {
    expect(valuesOf('Pet'), [
      {'kind': 'cat', 'born': '2026-01-02'},
      {'kind': 'dog'},
    ]);
  });

  test('no synthetic value is an example', () {
    expect(samples.where((s) => s.isExample), isEmpty);
  });
}
