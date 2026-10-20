import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/ir/ir.dart';

import '../helpers/ir_fixture.dart';

const _v1 = r'''
openapi: 3.0.3
info: {title: t, version: "1"}
paths:
  /pets:
    get:
      responses:
        '200':
          description: ok
          content:
            application/json:
              schema: {$ref: '#/components/schemas/Pet'}
components:
  schemas:
    Pet:
      type: object
      properties:
        status: {type: string, enum: [a, b]}
''';

/// [_v1] with a component `PetStatus` that `Pet` uses, and an operation
/// whose `operationId` is the name `GET /pets` had.
const _v2 = r'''
openapi: 3.0.3
info: {title: t, version: "1"}
paths:
  /animals:
    get:
      operationId: getPets
      responses:
        '200': {description: ok}
  /pets:
    get:
      responses:
        '200':
          description: ok
          content:
            application/json:
              schema: {$ref: '#/components/schemas/Pet'}
components:
  schemas:
    Pet:
      type: object
      properties:
        status: {type: string, enum: [a, b]}
        detail: {$ref: '#/components/schemas/PetStatus'}
    PetStatus:
      type: object
      properties:
        code: {type: integer}
''';

const _inline = '#/components/schemas/Pet/properties/status';
const _component = '#/components/schemas/PetStatus';

String _typeAt(ClientIr ir, String pointer) => ir.declarations
    .firstWhere((d) => d.id.location.pointer.value == pointer)
    .name;

String _methodOf(ClientIr ir, String path) => ir.groups
    .expand((g) => g.operations)
    .firstWhere((o) => o.path == path)
    .name;

void main() {
  final v1 = IrFixture(_v1);
  final lock = v1.lockOf(v1.build());

  test('without the lock a new schema renames an existing type', () {
    final ir = IrFixture(_v2).build();
    expect(_typeAt(ir, _inline), 'PetStatus2');
    expect(_typeAt(ir, _component), 'PetStatus');
  });

  test('adding a schema never renames an existing type with the lock', () {
    final ir = IrFixture(_v2).build(names: lock);
    expect(_typeAt(ir, _inline), 'PetStatus');
    expect(_typeAt(ir, _component), 'PetStatus2');
  });

  test('adding an operation never renames an existing method', () {
    expect(_methodOf(IrFixture(_v2).build(), '/pets'), 'getPets2');
    final ir = IrFixture(_v2).build(names: lock);
    expect(_methodOf(ir, '/pets'), 'getPets');
    expect(_methodOf(ir, '/animals'), 'getPets2');
  });

  test('a kept name a fresh run would not give is TOA570', () {
    final v2 = IrFixture(_v2);
    final kept = v2.lockOf(v2.build(names: lock));
    final v3 = IrFixture(
      _v2.replaceFirst('        status: {type: string, enum: [a, b]}\n', ''),
    );
    expect(_typeAt(v3.build(names: kept), _component), 'PetStatus2');
    expect(
      v3.reportedOf(DiagnosticCode.lockedNameKept).single.message,
      'typed_openapi.lock keeps the name "PetStatus2" of this type; without '
      'the lock it would be named "PetStatus".',
    );
  });

  test('a type of the lock the spec no longer declares is TOA571', () {
    final v3 = IrFixture(
      _v1.replaceFirst('status: {type: string, enum: [a, b]}', 'name: {}'),
    )..build(names: lock);
    expect(
      v3.reportedOf(DiagnosticCode.lockedNameReleased).single.message,
      contains('"PetStatus" for the schema at "$_inline"'),
    );
  });

  test('an override name that takes a kept name is TOA569', () {
    final fixture = IrFixture(
      _v1,
      overrides: 'schemas:\n  Pet:\n    name: PetStatus\n',
    );
    final ir = fixture.build(names: lock);
    expect(_typeAt(ir, '#/components/schemas/Pet'), 'PetStatus');
    expect(_typeAt(ir, _inline), 'PetStatusStatus');
    expect(fixture.reportedOf(DiagnosticCode.lockedNameTaken), hasLength(1));
  });
}
