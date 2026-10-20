import 'package:test/test.dart';

import '../helpers/ir_fixture.dart';

void main() {
  test(
    'an operation mixing event streams and bodies leaves nothing behind',
    () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /stream:
    get:
      operationId: watch
      tags: [t]
      responses:
        "200": {description: ok, content: {text/event-stream: {schema: {type: string}}}}
        "201": {description: made, content: {application/json: {schema: {type: object, properties: {b: {type: string}}}}}}
        "404": {description: no, content: {application/json: {schema: {$ref: '#/components/schemas/Gone'}}}}
        "500": {description: down, content: {application/json: {schema: {type: object, properties: {a: {type: string}}}}}}
  /pets:
    get:
      operationId: listPets
      tags: [t]
      responses:
        "200": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/Pet'}}}}
components:
  schemas:
    Gone: {type: object, properties: {why: {type: string}}}
    Pet: {type: object, properties: {name: {type: string}}}
''');
      final ir = fixture.build();
      expect(
        [for (final o in ir.groups.single.operations) o.name],
        ['listPets'],
      );
      expect([for (final d in ir.declarations) d.name], ['Pet']);
      expect(fixture.reportedOf(.eventStreamNotGenerated), hasLength(1));
    },
  );
}
