import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/ir/ir_builder.dart';

import '../helpers/ir_fixture.dart';

const _spec = '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    post:
      operationId: send
      tags: [t]
      parameters:
        - {name: jsonEncode, in: query, content: {application/json: {schema: {type: string}}}}
        - {name: base64Encode, in: query, schema: {type: string, format: byte}}
      requestBody:
        content:
          multipart/form-data:
            schema:
              type: object
              properties:
                jsonEncode: {type: string}
                base64Encode: {type: string, format: byte}
                a-b: {type: string}
                a_b: {type: string}
      responses: {"204": {description: ok}}
''';

void main() {
  final fixture = IrFixture(_spec);
  final operation = IrBuilder(fixture.diagnostics)
      .build(fixture.context.spec, fixture.context.client)
      .groups
      .single
      .operations
      .single;

  test('an argument named like a function the method calls is renamed', () {
    expect(
      [for (final p in operation.parameters) p.name],
      [
        'jsonEncode_',
        'base64Encode_',
      ],
    );
    expect(
      fixture.reported
          .where((d) => d.message.startsWith('Parameter'))
          .map(
            (d) => d.code,
          ),
      everyElement(DiagnosticCode.nameReserved),
    );
  });

  test('a part named like a function the class calls is renamed', () {
    expect(
      [for (final p in operation.body!.parts!) p.name],
      [
        'jsonEncode_',
        'base64Encode_',
        'aB',
        'aB2',
      ],
    );
    expect(
      fixture.reported
          .where(
            (d) =>
                d.message.startsWith('Part') ||
                d.message.startsWith('Another part'),
          )
          .map((d) => (d.code, d.pointer?.value)),
      [
        (
          DiagnosticCode.nameReserved,
          '#/paths/~1a/post/requestBody/content/multipart~1form-data/schema/properties/jsonEncode',
        ),
        (
          DiagnosticCode.nameReserved,
          '#/paths/~1a/post/requestBody/content/multipart~1form-data/schema/properties/base64Encode',
        ),
        (
          DiagnosticCode.nameCollision,
          '#/paths/~1a/post/requestBody/content/multipart~1form-data/schema/properties/a_b',
        ),
      ],
    );
  });

  test('a method named like a helper function or a type is renamed', () {
    final names = [
      for (final name in [
        'jsonEncode',
        'base64Encode',
        'int',
        'bool',
        'double',
        'num',
      ])
        '''
  /$name:
    get:
      operationId: $name
      tags: [t]
      responses: {"204": {description: ok}}''',
    ].join('\n');
    final spec = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
$names
''');
    final ir = IrBuilder(
      spec.diagnostics,
    ).build(spec.context.spec, spec.context.client);
    expect(
      [for (final o in ir.groups.single.operations) o.name],
      ['base64Encode_', 'bool_', 'double_', 'int_', 'jsonEncode_', 'num_'],
    );
    expect(
      spec.reported.map((d) => d.code),
      everyElement(DiagnosticCode.nameReserved),
    );
    expect(spec.reported, hasLength(6));
  });
}
