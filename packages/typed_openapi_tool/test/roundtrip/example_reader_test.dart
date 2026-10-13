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
    final set = ExampleReader().of(clientIr(_spec));
    final samples = set.samples;
    expect(set.skipped, 0);
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

  test('counts the examples it cannot read instead of dropping them', () {
    final set = ExampleReader().of(clientIr(_skipping));
    expect(
      [for (final s in set.samples) s.value],
      [
        {'id': 'chained'},
      ],
    );
    // schema example null, schema examples [null], external ref, no value
    // and value null.
    expect(set.skipped, 5);
  });

  test('reads the property of the envelope a response wraps its data in', () {
    final set = ExampleReader().of(clientIr(_enveloped));
    expect(
      [for (final s in set.samples) s.value],
      [
        {'id': 'inside'},
      ],
    );
  });
}

const _skipping = r'''
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
              examples:
                external: {$ref: "other.yaml#/Example"}
                chained: {$ref: "#/components/examples/First"}
                bare: {summary: no value}
                nothing: {value: null}
components:
  examples:
    First: {$ref: "#/components/examples/Second"}
    Second: {value: {id: chained}}
  schemas:
    Pet:
      type: object
      properties:
        id: {type: string}
      example: null
      examples: [null]
''';

const _enveloped = r'''
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
              schema:
                type: object
                required: [data]
                properties:
                  data: {$ref: "#/components/schemas/Pet"}
              example: {data: {id: inside}}
components:
  schemas:
    Pet:
      type: object
      properties:
        id: {type: string}
''';
