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
    final spec = _spec();
    final get = spec.indexOf('    get:');
    final post = spec.indexOf('    post:');
    final end = spec.indexOf('components:');
    final swapped =
        spec.substring(0, get) +
        spec.substring(post, end) +
        spec.substring(get, post) +
        spec.substring(end);
    expect(swapped.indexOf('createPet'), lessThan(swapped.indexOf('listPets')));
    expect(_names(IrFixture(swapped).build()), _names(IrFixture(spec).build()));
  });

  test('an anyOf of two equal enums collapses to one enum of its site', () {
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Pet:
      type: object
      properties:
        kind:
          anyOf:
            - {type: string, enum: [a, b]}
            - {type: string, enum: [a, b]}
''');
    final (ir, _) = mapComponents(fixture, ['Pet']);
    expect(
      [for (final d in ir.declarations) (d.name, d.runtimeType)],
      [('Pet', ModelDecl), ('PetKind', EnumDecl)],
    );
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
    // Taken from a run of the generator before 0.3.1 over `_spec()`: the
    // operations are built first, so the query parameter owned the enum and
    // the body property was typed with it.
    const oldLock = r'''
{
  "version": 1,
  "clients": {
    "c": {
      "#/components/schemas/NewPet": {
        "name": "NewPet",
        "kind": "model",
        "members": {
          "type": {"name":"type","kind":"field","facts":{"json":"type","required":"false","type":"ListPetsType?"}}
        }
      },
      "#/paths/~1pets/get/parameters/0/schema": {
        "name": "ListPetsType",
        "kind": "enumeration",
        "facts": {"kind":"string","known":"ListPetsTypeKnown","unknown":"ListPetsTypeUnknown"},
        "members": {
          "\"cat\"": {"name":"cat","kind":"value"},
          "\"dog\"": {"name":"dog","kind":"value"}
        }
      },
      "group:": {
        "name": "DefaultApi",
        "kind": "group",
        "members": {
          "createPet": {"name":"createPet","kind":"method","facts":{"method":"POST","path":"/pets","responses":"200","returns":"Result<void, Never>"}},
          "createPet/body": {"name":"body","kind":"body","owner":"createPet","facts":{"kind":"json","media":"application/json","required":"false","type":"NewPet"}},
          "listPets": {"name":"listPets","kind":"method","facts":{"method":"GET","path":"/pets","responses":"200","returns":"Result<void, Never>"}},
          "listPets/type": {"name":"type","kind":"parameter","owner":"listPets","facts":{"in":"query","required":"false","type":"ListPetsType?","wire":"type"}}
        }
      },
      "root": {
        "name": "ApiClient",
        "kind": "root",
        "members": {
          "group:": {"name":"defaultApi","kind":"groupField","facts":{"type":"DefaultApi"}}
        }
      }
    }
  }
}''';
    final old = const SnapshotJson().decode(oldLock)['c']!;
    final fresh = snapshotOf(_spec());

    test('keeps the first owner name, names the other site afresh', () {
      final fixture = IrFixture(_spec());
      final root = fixture.context.model.document.location.document;
      final names = _names(
        fixture.build(names: SnapshotNameLock.of(old, root)),
      );
      expect(names[_querySite], 'ListPetsType');
      expect(names[_bodySite], 'NewPetType');
      expect(fixture.reportedOf(DiagnosticCode.lockedNameTaken), isEmpty);
      expect(fixture.reportedOf(DiagnosticCode.lockedNameKept), isEmpty);
      expect(fixture.reportedOf(DiagnosticCode.lockedNameReleased), isEmpty);
    });

    test('the diff says a type was added and a member retyped', () {
      final changes = const ApiDiff().compare(old, fresh);
      expect(
        [for (final c in changes) (c.category, c.type, c.member)],
        [
          (ChangeCategory.breaking, '#/components/schemas/NewPet', 'type'),
          (ChangeCategory.additive, _bodySite, null),
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
