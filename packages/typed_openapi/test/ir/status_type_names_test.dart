import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/ir/ir.dart';
import 'package:typed_openapi/src/ir/ir_builder.dart';

import '../helpers/ir_fixture.dart';

ClientIr build(IrFixture fixture) => IrBuilder(
  fixture.diagnostics,
).build(fixture.context.spec, fixture.context.client);

List<Diagnostic> collisions(IrFixture fixture) => [
  for (final d in fixture.reported)
    if (d.code == DiagnosticCode.nameCollision) d,
];

/// The operation [name] of the group [group].
OperationIr operation(ClientIr ir, String group, String name) => ir.groups
    .firstWhere((g) => g.name == group)
    .operations
    .singleWhere((o) => o.name == name);

/// An operation `list` in the tag [tag], with two successes and two errors
/// with different bodies, so it has a sealed type of each.
String listIn(String tag) =>
    '''
  /$tag:
    get:
      operationId: list
      tags: [$tag]
      responses:
        "200": {description: ok, content: {application/json: {schema: {type: string}}}}
        "201": {description: made, content: {application/json: {schema: {type: integer}}}}
        "404": {description: no, content: {application/json: {schema: {type: string}}}}
        "409": {description: clash, content: {application/json: {schema: {type: integer}}}}
''';

void main() {
  group('the name of a sealed status type', () {
    test('of operations with one name in two groups gets a suffix', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
${listIn('a')}${listIn('b')}''');
      final ir = build(fixture);
      final first = operation(ir, 'AApi', 'list');
      final second = operation(ir, 'BApi', 'list');
      expect(first.successType?.name, 'ListResponse');
      expect(first.errorType?.name, 'ListError');
      expect(second.successType?.name, 'ListResponse2');
      expect(second.errorType?.name, 'ListError2');
      expect(second.errorType?.cases.first.name, 'ListError2NotFound');
      final found = collisions(fixture);
      expect(found.map((d) => d.pointer?.value), [
        '#/paths/~1b/get',
        '#/paths/~1b/get',
      ]);
      expect(found.first.message, contains('"ListResponse2"'));
      expect(found.last.message, contains('"ListError2"'));
    });

    test('of an operation whose schema is named like it gets a suffix', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: getPet
      tags: [pets]
      responses:
        "404": {description: no, content: {application/json: {schema: {type: string}}}}
        "409": {description: clash, content: {application/json: {schema: {type: integer}}}}
  /b:
    get:
      operationId: other
      tags: [pets]
      responses:
        "200": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/GetPetError'}}}}
components:
  schemas:
    GetPetError: {type: object, properties: {a: {type: string}}}
''');
      final ir = build(fixture);
      expect(
        operation(ir, 'PetsApi', 'getPet').errorType?.name,
        'GetPetError2',
      );
      expect(collisions(fixture).single.message, contains('"GetPetError2"'));
    });

    test('is the plural when the operation\'s own inline body has it', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: getPet
      tags: [pets]
      responses:
        "200": {description: ok, content: {application/json: {schema: {type: object, properties: {a: {type: string}}}}}}
        "204": {description: none}
        "404": {description: no, content: {application/json: {schema: {type: object, properties: {b: {type: string}}}}}}
        "500": {description: down}
''');
      final ir = build(fixture);
      final get = operation(ir, 'PetsApi', 'getPet');
      expect(get.successType?.name, 'GetPetResponses');
      expect(get.errorType?.name, 'GetPetErrors');
      expect(fixture.reported, isEmpty);
    });

    test('is suffixed when the plural is taken as well', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: getPet
      tags: [pets]
      responses:
        "200": {description: ok, content: {application/json: {schema: {type: object, properties: {a: {type: string}}}}}}
        "204": {description: none}
  /b:
    get:
      operationId: other
      tags: [pets]
      responses:
        "200": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/GetPetResponses'}}}}
components:
  schemas:
    GetPetResponses: {type: object, properties: {a: {type: string}}}
''');
      final ir = build(fixture);
      expect(
        operation(ir, 'PetsApi', 'getPet').successType?.name,
        'GetPetResponse2',
      );
      expect(collisions(fixture), hasLength(1));
    });
  });
}
