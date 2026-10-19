@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/model/spec_node.dart';
import 'package:typed_openapi/src/snapshot/api_snapshot.dart';
import 'package:typed_openapi/src/snapshot/snapshot_identities.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/snapshot_fixture.dart';

void main() {
  final petstore = snapshotOfFixture('petstore.yaml');

  test('a declaration is keyed by its spec location', () {
    final pet = petstore.types['#/components/schemas/Pet']!;
    expect((pet.name, pet.kind), ('Pet', TypeKind.model));
    expect(pet.members['status']?.facts, {
      'json': 'status',
      'required': 'false',
      'type': 'Status?',
    });
  });

  test('an enum lists its values by their JSON', () {
    final status = petstore.types['#/components/schemas/Status']!;
    expect(status.kind, TypeKind.enumeration);
    expect(status.exhaustive, isTrue);
    expect(status.members.keys, ['"available"', '"sold"']);
    expect(status.facts['known'], 'StatusKnown');
  });

  test('a method is keyed by its operationId, an argument by its method', () {
    final pets = petstore.types['group:Pets']!;
    expect(pets.name, 'PetsApi');
    expect(
      pets.members['createPet']?.facts['returns'],
      'Result<CreatePetResponse, CreatePetError>',
    );
    final body = pets.members['createPet/body']!;
    expect((body.kind, body.owner), (MemberKind.body, 'createPet'));
    final trace = pets.members['listPets/xTrace']!;
    expect(trace.facts['wire'], 'X-Trace');
    expect(trace.facts['in'], 'header');
  });

  test('a status type is keyed by its method and has a case per status', () {
    final success = petstore.types['createPet#success']!;
    expect(success.kind, TypeKind.statusType);
    expect(success.members.keys, ['200', '201', '204']);
    expect(success.members['204']?.facts['type'], 'none');
  });

  test('the root holds the groups and the servers', () {
    final root = petstore.types['root']!;
    expect(root.members['group:Pets']?.name, 'pets');
    expect(root.members['server:1']?.facts['url'], 'http://localhost:8080');
  });

  test('an event union is keyed by its stream method', () {
    final chat = snapshotOfFixture('chat.yaml');
    final events = chat.types['followChat#stream#events']!;
    expect(events.kind, TypeKind.eventUnion);
    expect(events.name, 'FollowChatEvent');
  });

  test('exhaustive: false is kept for enums and status types', () {
    final open = snapshotOfFixture(
      'petstore.yaml',
      generation: const GenerationConfig(exhaustive: false),
    );
    expect(open.types['#/components/schemas/Status']?.exhaustive, isFalse);
    expect(open.types['createPet#success']?.exhaustive, isFalse);
    expect(open.types['#/components/schemas/Pet']?.exhaustive, isTrue);
  });

  test('a repeated operationId keys the operations by method and path', () {
    final snapshot = snapshotOf('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get: {operationId: list, responses: {'204': {description: ok}}}
  /b:
    get: {operationId: list, responses: {'204': {description: ok}}}
''');
    expect(
      snapshot.types['group:']?.members.keys,
      containsAll(['GET /a', 'GET /b']),
    );
  });

  test('a location in another file is keyed by its relative path', () {
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths: {}
''');
    final ids = SnapshotIdentities(
      fixture.build(),
      Uri.file('/work/spec/api.yaml'),
    );
    final pointer = JsonPointer.parse('#/Pet');
    expect(
      ids.location(SpecLocation(Uri.file('/work/spec/api.yaml'), pointer)),
      '#/Pet',
    );
    expect(
      ids.location(
        SpecLocation(Uri.file('/work/spec/models/pet.yaml'), pointer),
      ),
      'models/pet.yaml#/Pet',
    );
    expect(
      ids.location(SpecLocation(Uri.file('/work/shared/pet.yaml'), pointer)),
      '../shared/pet.yaml#/Pet',
    );
  });
}
