import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';

import '../helpers/ir_fixture.dart';

void main() {
  test('Dio names stay free; the transport names of the client are taken', () {
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
                  d: {$ref: '#/components/schemas/Dio'}
                  t: {$ref: '#/components/schemas/ClientTransport'}
components:
  schemas:
    Response: {type: object, properties: {id: {type: string}}}
    Dio: {type: object, properties: {id: {type: string}}}
    ClientTransport: {type: object, properties: {id: {type: string}}}
''');
    final names = [for (final d in fixture.build().declarations) d.name];
    expect(names, containsAll(['Response', 'Dio', 'ClientTransportModel']));
    expect(
      [
        for (final d in fixture.reportedOf(DiagnosticCode.nameReserved))
          d.pointer?.value,
      ],
      ['#/components/schemas/ClientTransport'],
    );
  });
}
