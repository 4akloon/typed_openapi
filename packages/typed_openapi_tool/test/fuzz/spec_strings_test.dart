import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/fuzz/spec_strings.dart';

import '../helpers/client_ir.dart';

const _spec = r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets:
    get:
      operationId: getPet
      parameters:
        - {name: "it's", in: query, schema: {type: string}}
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
        - $ref: "#/components/schemas/Cat"
        - $ref: "#/components/schemas/Name"
      discriminator: {propertyName: kind}
    Cat: {type: object, properties: {kind: {type: string}, $cost: {type: integer}}}
    Name: {type: string}
''';

void main() {
  test('holds keys, names and the values of object variants only', () {
    final strings = const SpecStrings().of(clientIr(_spec));
    expect(strings, containsAll([r'$cost', "it's", 'kind', 'Cat']));
    // A string variant is picked by its JSON type, not by a value.
    expect(strings, isNot(contains('Name')));
  });
}
