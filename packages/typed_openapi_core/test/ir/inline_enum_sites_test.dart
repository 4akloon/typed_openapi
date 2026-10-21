import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/diff/api_change.dart';
import 'package:typed_openapi_core/src/diff/api_diff.dart';
import 'package:typed_openapi_core/src/ir/ir.dart';
import 'package:typed_openapi_core/src/snapshot/snapshot_json.dart';
import 'package:typed_openapi_core/src/snapshot/snapshot_name_lock.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/mapping.dart';
import '../helpers/snapshot_fixture.dart';

const _enum = '{type: string, enum: [cat, dog]}';

String _spec({String bodyEnum = _enum}) =>
    '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets:
    get:
      operationId: listPets
      parameters:
        - {name: type, in: query, schema: $_enum}
      responses: {'200': {description: ok}}
    post:
      operationId: createPet
      requestBody:
        content:
          application/json:
            schema: {\$ref: '#/components/schemas/NewPet'}
      responses: {'200': {description: ok}}
components:
  schemas:
    NewPet:
      type: object
      properties:
        type: $bodyEnum
''';

const _bodySite = '#/components/schemas/NewPet/properties/type';
const _querySite = '#/paths/~1pets/get/parameters/0/schema';

Map<String, String> _names(ClientIr ir) => {
  for (final d in ir.declarations) d.id.location.pointer.value: d.name,
};

void main() {
  test('an equal enum on a query parameter and a body property is two', () {
    final names = _names(IrFixture(_spec()).build());
    expect(names[_querySite], 'ListPetsType');
    expect(names[_bodySite], 'NewPetType');
  });

  test('the order of the operations changes no name', () {
    final swapped = _spec()
        .replaceFirst('    post:', '    put:')
        .replaceFirst('    get:', '    post:')
        .replaceFirst('    put:', '    get:');
    final names = _names(IrFixture(swapped).build());
    expect(names[_bodySite], 'NewPetType');
    expect(names.values.where((n) => n.endsWith('Type')), hasLength(2));
  });

  test('another value in one copy leaves the other copy as it was', () {
    final before = _names(IrFixture(_spec()).build());
    final after = _names(
      IrFixture(
        _spec(bodyEnum: '{type: string, enum: [cat, dog, owl]}'),
      ).build(),
    );
    expect(after, before);
  });

  test('an enum in a component that two operations reach stays one', () {
    final ir = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: a
      responses:
        '200':
          description: ok
          content: {application/json: {schema: {\$ref: '#/components/schemas/Pet'}}}
  /b:
    get:
      operationId: b
      responses:
        '200':
          description: ok
          content: {application/json: {schema: {\$ref: '#/components/schemas/Pet'}}}
components:
  schemas:
    Pet:
      type: object
      properties:
        type: $_enum
''').build();
    expect(ir.declarations.map((d) => d.name), ['Pet', 'PetType']);
  });

  test('sites that derive one name get 2, 3 and TOA551', () {
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Pet:
      type: object
      properties:
        kind: $_enum
        Kind: $_enum
''');
    final (ir, _) = mapComponents(fixture, ['Pet']);
    final names = ir.declarations.map((d) => d.name).toList();
    expect(names, containsAll(['PetKind', 'PetKind2']));
    expect(fixture.reportedOf(DiagnosticCode.nameCollision), isNotEmpty);
  });

  group('a lock written when the sites shared one enum', () {
    // The old run kept both sites as the enum of the body property.
    final fresh = snapshotOf(_spec());
    final old = const SnapshotJson().decode(
      const SnapshotJson()
          .encode({'c': fresh})
          .replaceAll('ListPetsType?', 'NewPetType?')
          .replaceAll(
            RegExp(
              r'\n      "#/paths/~1pets/get/parameters/0/schema": \{.*?\n      \},',
              dotAll: true,
            ),
            '',
          ),
    )['c']!;

    test('keeps the first owner name, names the other site afresh', () {
      final fixture = IrFixture(_spec());
      final root = fixture.context.model.document.location.document;
      final lock = SnapshotNameLock.of(old, root);
      final names = _names(fixture.build(names: lock));
      expect(names[_bodySite], 'NewPetType');
      expect(names[_querySite], 'ListPetsType');
      expect(fixture.reportedOf(DiagnosticCode.lockedNameTaken), isEmpty);
    });

    test('the diff says a type was added and members were retyped', () {
      final changes = const ApiDiff().compare(old, fresh);
      expect(
        [for (final c in changes) (c.category, c.type, c.member)],
        [
          (ChangeCategory.breaking, 'group:', 'listPets/type'),
          (ChangeCategory.additive, _querySite, null),
        ],
      );
    });
  });

  test('a collapsed union still lists the known values of each field', () {
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Pet:
      type: object
      properties:
        a: {anyOf: [{type: string}, {enum: [x, y]}]}
        b: {anyOf: [{type: string}, {enum: [x, y]}]}
        c: {type: string, enum: [x, y]}
        d: {type: string, enum: [x, y]}
''');
    final (ir, _) = mapComponents(fixture, ['Pet']);
    final pet = ir.declarations.firstWhere((d) => d.name == 'Pet') as ModelDecl;
    expect(
      {for (final f in pet.fields) f.name: f.knownValues},
      {
        'a': ['x', 'y'],
        'b': ['x', 'y'],
        'c': <Object?>[],
        'd': <Object?>[],
      },
    );
    expect(
      ir.declarations.map((d) => d.name),
      containsAll(['Pet', 'PetC', 'PetD']),
    );
  });
}
