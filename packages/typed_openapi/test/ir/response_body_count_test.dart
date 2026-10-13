import 'package:test/test.dart';

import '../helpers/ir_fixture.dart';

void main() {
  test('a response that is read as bytes does not make a name longer', () {
    // The form response is bytes (TOA650): it declares nothing, so the one
    // JSON error keeps the short name, without its status.
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: read
      tags: [t]
      responses:
        "200": {description: ok}
        "404": {description: no, content: {application/json: {schema: {type: object, properties: {a: {type: string}}}}}}
        "409": {description: form, content: {application/x-www-form-urlencoded: {schema: {type: object, properties: {b: {type: string}}}}}}
        "410": {description: file, content: {application/octet-stream: {schema: {type: string, format: binary}}}}
''');
    final ir = fixture.build();
    expect([for (final d in ir.declarations) d.name], ['ReadError']);
  });

  test('several bodies that are mapped still get their status', () {
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: read
      tags: [t]
      responses:
        "200": {description: ok}
        "404": {description: no, content: {application/json: {schema: {type: object, properties: {a: {type: string}}}}}}
        "409": {description: no, content: {application/json: {schema: {type: object, properties: {b: {type: string}}}}}}
''');
    final ir = fixture.build();
    expect(
      [for (final d in ir.declarations) d.name],
      [
        'ReadError404',
        'ReadError409',
      ],
    );
  });
}
