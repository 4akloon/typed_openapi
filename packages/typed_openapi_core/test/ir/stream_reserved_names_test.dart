import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';

import '../helpers/ir_fixture.dart';

void main() {
  test('a schema named like an M10 runtime type gets Model (TOA550)', () {
    const names = [
      'SseEventIgnored',
      'SseOptions',
      'SseReconnecting',
      'SseReconnection',
      'SseReconnector',
      'SseResume',
    ];
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /feed:
    get:
      operationId: feed
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema:
                type: object
                properties:
${[for (final n in names) "                  ${n.toLowerCase()}: {\$ref: '#/components/schemas/$n'}"].join('\n')}
components:
  schemas:
${[for (final n in names) '    $n: {type: object, properties: {id: {type: string}}}'].join('\n')}
''');
    final ir = fixture.build();
    expect(
      [
        for (final d in ir.declarations) d.name,
      ].where((n) => n.startsWith('Sse')),
      [for (final n in names) '${n}Model'],
    );
    expect(
      fixture.reportedOf(DiagnosticCode.nameReserved),
      hasLength(names.length),
    );
  });
}
