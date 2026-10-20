import 'package:test/test.dart';
import 'package:typed_openapi_core/src/config/generation_config.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi_core/src/ir/ir.dart';
import 'package:typed_openapi_core/src/ir/ir_builder.dart';

import '../helpers/ir_fixture.dart';

void main() {
  const spec = r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets:
    get:
      operationId: listPets
      tags: [pets]
      responses:
        "200": {description: ok, content: {application/json: {schema: {type: array, items: {$ref: '#/components/schemas/Pet'}}}}}
  /pets/{id}:
    delete:
      operationId: deletePet
      tags: [pets]
      parameters: [{name: id, in: path, required: true, schema: {type: string}}]
      responses: {"204": {description: ok}}
  /store/orders:
    get:
      operationId: listOrders
      tags: [store]
      responses:
        "200": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/Order'}}}}
components:
  schemas:
    Pet: {type: object, properties: {name: {type: string}, owner: {$ref: '#/components/schemas/Owner'}}}
    Owner: {type: object, properties: {name: {type: string}}}
    Order: {type: object, properties: {id: {type: string}}}
    Unused: {type: object, properties: {id: {type: string}}}
''';

  FilterPattern pattern(String value, String pointer) =>
      FilterPattern(value, JsonPointer.parse(pointer));

  ClientIr build(IrFixture fixture) => IrBuilder(
    fixture.diagnostics,
  ).build(fixture.context.spec, fixture.context.client);

  List<String> methods(ClientIr ir) => [
    for (final group in ir.groups)
      for (final operation in group.operations) operation.name,
  ];

  test('generates only schemas the operations reach (R4.2)', () {
    final fixture = IrFixture(spec);
    final ir = build(fixture);
    expect(fixture.reported, isEmpty);
    expect(methods(ir), ['deletePet', 'listPets', 'listOrders']);
    expect(ir.declarations.map((d) => d.name), ['Order', 'Owner', 'Pet']);
  });

  test('keeps included operations and drops excluded ones (R4.1)', () {
    final fixture = IrFixture(
      spec,
      generation: GenerationConfig(
        include: OperationFilter(
          tags: [pattern('pets', '#/clients/a/include/tags/0')],
        ),
        exclude: OperationFilter(
          paths: [pattern('/pets/*', '#/clients/a/exclude/paths/0')],
        ),
      ),
    );
    final ir = build(fixture);
    expect(fixture.reported, isEmpty);
    expect(methods(ir), ['listPets']);
    expect(ir.declarations.map((d) => d.name), ['Owner', 'Pet']);
  });

  test('matches path globs and operation ids', () {
    final fixture = IrFixture(
      spec,
      generation: GenerationConfig(
        include: OperationFilter(
          paths: [pattern('/store/**', '#/i/paths/0')],
          operations: [pattern('deletePet', '#/i/operations/0')],
        ),
      ),
    );
    expect(methods(build(fixture)), ['deletePet', 'listOrders']);
  });

  test('reports patterns that match nothing and patterns both filters '
      'list', () {
    final fixture = IrFixture(
      spec,
      generation: GenerationConfig(
        file: 'typed_openapi.yaml',
        client: JsonPointer.root.child('clients').child('a'),
        include: OperationFilter(
          tags: [
            pattern('pets', '#/clients/a/include/tags/0'),
            pattern('Pets', '#/clients/a/include/tags/1'),
          ],
        ),
        exclude: OperationFilter(
          tags: [pattern('pets', '#/clients/a/exclude/tags/0')],
          operations: [
            pattern('deletePet', '#/clients/a/exclude/operations/0'),
          ],
        ),
      ),
    );
    final ir = build(fixture);
    expect(methods(ir), isEmpty);
    expect(
      fixture.reported.map((d) => (d.code, d.file, d.pointer?.value)),
      [
        (
          DiagnosticCode.filterConflict,
          'typed_openapi.yaml',
          '#/clients/a/exclude/tags/0',
        ),
        (
          DiagnosticCode.filterMatchesNothing,
          'typed_openapi.yaml',
          '#/clients/a/include/tags/1',
        ),
        (
          DiagnosticCode.clientEmpty,
          'typed_openapi.yaml',
          '#/clients/a',
        ),
      ],
    );
  });

  test('applies exclude from overrides to operations and schemas', () {
    final fixture = IrFixture(
      spec,
      overrides: '''
operations:
  listOrders: {exclude: true}
schemas:
  Owner: {exclude: true}
''',
    );
    final ir = build(fixture);
    expect(methods(ir), ['deletePet', 'listPets']);
    expect(ir.declarations.map((d) => d.name), ['Pet']);
    expect(fixture.codes, [
      (DiagnosticCode.excludedSchemaReferenced, '#/components/schemas/Owner'),
    ]);
  });
}
