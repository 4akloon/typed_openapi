import 'package:test/test.dart';

import '../helpers/ir_fixture.dart';

void main() {
  test('an inline body of a shared response is not the operation\'s own', () {
    // The body of components.responses/NotFound is named GetPetError, as the
    // sealed type of the operation would be. It belongs to a shared entry,
    // not to the operation, so it never takes the plural: the sealed type
    // gets a number and the collision is reported (TOA551).
    final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: getPet
      tags: [pets]
      responses:
        "200": {description: ok}
        "404": {$ref: '#/components/responses/NotFound'}
        "500": {description: down}
components:
  responses:
    NotFound:
      description: no
      content:
        application/json:
          schema: {type: object, properties: {b: {type: string}}}
''');
    final ir = fixture.build();
    final get = ir.groups.single.operations.single;
    expect([for (final d in ir.declarations) d.name], ['GetPetError']);
    expect(get.errorType?.name, 'GetPetError2');
    expect(fixture.reportedOf(.nameCollision), hasLength(1));
    expect(
      fixture.reportedOf(.nameCollision).first.message,
      contains('"GetPetError"'),
    );
  });
}
