import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/roundtrip/example_reader.dart';

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
              example: {id: from-media}
              examples:
                named: {value: {id: named}}
                shared: {$ref: "#/components/examples/Shared"}
components:
  examples:
    Shared: {value: {id: shared}}
  schemas:
    Pet:
      type: object
      properties:
        id: {type: string}
      example: {id: from-schema}
      examples: [{id: listed}]
''';

void main() {
  test('reads the examples of schemas and JSON responses by class', () {
    final samples = ExampleReader().of(clientIr(_spec));
    expect({for (final s in samples) s.type}, {'Pet'});
    expect(samples.every((s) => s.isExample), isTrue);
    expect(
      [for (final s in samples) s.value],
      [
        {'id': 'from-schema'},
        {'id': 'listed'},
        {'id': 'from-media'},
        {'id': 'named'},
        {'id': 'shared'},
      ],
    );
  });
}
