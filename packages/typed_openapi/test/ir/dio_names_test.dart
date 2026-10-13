import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';

import '../helpers/ir_fixture.dart';

void main() {
  test('Response, Options and Headers stay free: the API shows only Dio', () {
    final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: read
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema:
                type: object
                properties:
                  r: {$ref: '#/components/schemas/Response'}
                  o: {$ref: '#/components/schemas/Options'}
                  h: {$ref: '#/components/schemas/Headers'}
                  d: {$ref: '#/components/schemas/Dio'}
components:
  schemas:
    Response: {type: object, properties: {id: {type: string}}}
    Options: {type: object, properties: {id: {type: string}}}
    Headers: {type: object, properties: {id: {type: string}}}
    Dio: {type: object, properties: {id: {type: string}}}
''');
    final names = [for (final d in fixture.build().declarations) d.name];
    expect(names, containsAll(['Response', 'Options', 'Headers', 'DioModel']));
    expect(
      [
        for (final d in fixture.reportedOf(DiagnosticCode.nameReserved))
          d.pointer?.value,
      ],
      ['#/components/schemas/Dio'],
    );
  });
}
