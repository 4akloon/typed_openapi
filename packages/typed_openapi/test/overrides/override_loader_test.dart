import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/model/operation.dart';
import 'package:typed_openapi/src/overrides/override_loader.dart';
import 'package:typed_openapi/src/overrides/override_set.dart';

import '../helpers/temp_dir.dart';

void main() {
  OverrideSet? parse(
    DiagnosticBag bag,
    String text, {
    String file = 'o.yaml',
  }) => OverrideLoader(bag).parse(text, file);

  test('reads every section and field without diagnostics', () {
    final bag = DiagnosticBag();
    final set = parse(bag, r'''
operations:
  getPet:
    reason: the backend forgets 404
    name: fetchPet
    exclude: false
    group: pets
    parameters:
      id:
        required: true
        schema: {type: integer, format: int64}
        name: petId
        dartType: {type: PetId, import: 'package:app/pet_id.dart'}
      query:id: {required: false}
    requestBody:
      contentType: application/json
      schema: {$ref: '#/components/schemas/NewPet'}
    responses:
      '200':
        contentType: text/event-stream
  POST /pets:
    exclude: true
schemas:
  Pet:
    reason: nullable in practice
    type: object
    nullable: true
    required: [id]
    exhaustive: false
    name: PetModel
    dartType:
      type: Pet
      import: package:app/pet.dart
      converter: PetConverter
    properties:
      tag:
        format: null
        required: true
        triState: true
  Owner:
    $ref: '#/components/schemas/Person'
    nullable: true
''')!;
    expect(bag.all, isEmpty);
    expect(set.file, 'o.yaml');
    final [get, post] = set.operations;
    expect(get.operationId, 'getPet');
    expect(get.method, isNull);
    expect(get.reason, 'the backend forgets 404');
    expect((get.name, get.exclude, get.group), ('fetchPet', false, 'pets'));
    final [id, queryId] = get.parameters;
    expect(id.parameterName, 'id');
    expect(id.placement, isNull);
    expect(id.spec, {
      'required': true,
      'schema': {'type': 'integer', 'format': 'int64'},
    });
    expect(id.name, 'petId');
    expect(id.dartType?.import, 'package:app/pet_id.dart');
    expect(queryId.parameterName, 'id');
    expect(queryId.placement, ParameterLocation.query);
    expect(get.requestBody?.spec, {
      'contentType': 'application/json',
      'schema': {r'$ref': '#/components/schemas/NewPet'},
    });
    expect(get.responses.single.key, '200');
    expect(get.responses.single.spec, {'contentType': 'text/event-stream'});
    expect(post.operationId, isNull);
    expect((post.method, post.path, post.exclude), ('post', '/pets', true));
    final [pet, owner] = set.schemas;
    expect(pet.key, 'Pet');
    expect(pet.pointer.value, '#/schemas/Pet');
    expect(pet.spec, {
      'type': 'object',
      'nullable': true,
      'required': ['id'],
    });
    expect((pet.exhaustive, pet.name), (false, 'PetModel'));
    expect(pet.dartType?.converter, 'PetConverter');
    final tag = pet.properties.single;
    expect(tag.pointer.value, '#/schemas/Pet/properties/tag');
    expect(tag.spec, {'format': null, 'required': true});
    expect(tag.triState, isTrue);
    expect(owner.spec, {
      r'$ref': '#/components/schemas/Person',
      'nullable': true,
    });
  });

  test('reads a JSON file', () {
    final bag = DiagnosticBag();
    final set = parse(
      bag,
      '{"schemas": {"Pet": {"type": "string"}}}',
      file: 'o.json',
    )!;
    expect(bag.all, isEmpty);
    expect(set.schemas.single.spec, {'type': 'string'});
  });

  test('an empty file is an empty set', () {
    final bag = DiagnosticBag();
    expect(parse(bag, '{}')!.isEmpty, isTrue);
    expect(bag.all, isEmpty);
  });

  test('an empty or comment-only file is an empty set', () {
    for (final text in ['', '\n', '# nothing yet\n\n  # still nothing\n']) {
      final bag = DiagnosticBag();
      expect(parse(bag, text)!.isEmpty, isTrue, reason: text);
      expect(bag.all, isEmpty, reason: text);
    }
  });

  test('an empty file on disk is an empty set', () {
    final dir = TempDir();
    final path = dir.write('o.yaml', '# all overrides removed\n');
    final bag = DiagnosticBag();
    expect(
      OverrideLoader(bag).load(path, displayPath: 'o.yaml')!.isEmpty,
      isTrue,
    );
    expect(bag.all, isEmpty);
  });

  test('a section without entries is empty', () {
    final bag = DiagnosticBag();
    final set = parse(bag, '''
operations:
  # getPet: {name: x}
schemas:
''')!;
    expect(set.isEmpty, isTrue);
    expect(bag.all, isEmpty);
    final other = parse(bag, '''
operations:
  getPet: {name: fetchPet}
schemas:
''')!;
    expect(other.operations.single.name, 'fetchPet');
    expect(other.schemas, isEmpty);
    expect(bag.all, isEmpty);
  });

  test('a root that is not an object is an invalid file', () {
    final bag = DiagnosticBag();
    expect(parse(bag, '[1]'), isNull);
    expect(parse(bag, 'text\n', file: 'p.yaml'), isNull);
    expect(bag.all.map((d) => d.code), [
      DiagnosticCode.invalidOverride,
      DiagnosticCode.invalidOverride,
    ]);
  });

  test('reports a missing file', () {
    final bag = DiagnosticBag();
    expect(OverrideLoader(bag).load('/nope/o.yaml'), isNull);
    expect(bag.all.single.code, DiagnosticCode.overridesNotFound);
    expect(bag.all.single.file, '/nope/o.yaml');
  });

  test('loads a file from disk and names it by its display path', () {
    final dir = TempDir();
    final path = dir.write('o.yaml', 'schemas: {Pet: {type: 1}}\n');
    final bag = DiagnosticBag();
    final set = OverrideLoader(bag).load(path, displayPath: 'o.yaml')!;
    expect(set.schemas.single.spec, isEmpty);
    expect(bag.all.single.code, DiagnosticCode.invalidOverride);
    expect(bag.all.single.location, 'o.yaml:1:23');
  });

  test('a directory as the overrides path is an invalid overrides file', () {
    final dir = TempDir();
    final bag = DiagnosticBag();
    expect(OverrideLoader(bag).load(dir.path, displayPath: 'o'), isNull);
    final d = bag.all.single;
    expect(d.code, DiagnosticCode.invalidOverride);
    expect(d.message, 'Overrides path o is a directory, not a file.');
    expect(d.fix, contains('"overrides"'));
  });

  test('a syntax error or a non-object root is an invalid file', () {
    final bag = DiagnosticBag();
    expect(parse(bag, 'schemas: [\n'), isNull);
    expect(parse(bag, '- a\n'), isNull);
    expect(bag.all.map((d) => d.code), [
      DiagnosticCode.invalidOverride,
      DiagnosticCode.invalidOverride,
    ]);
  });

  test('a duplicate key is reported as a problem of the overrides file', () {
    final bag = DiagnosticBag();
    parse(bag, 'schemas:\n  Pet: {type: string}\n  Pet: {type: integer}\n');
    expect(bag.all.single.code, DiagnosticCode.invalidOverride);
  });

  test('reports unknown keys at every level and reads the rest', () {
    final bag = DiagnosticBag();
    final set = parse(bag, '''
paths: {}
operations:
  getPet:
    summary: x
    parameters:
      id: {in: path}
    requestBody: {required: true}
    responses:
      '200': {headers: {}}
schemas:
  Pet:
    title: x
    dartType: {type: P, import: p.dart, from: x}
    properties:
      id: {nullabel: true, nullable: true}
''')!;
    expect(
      [for (final d in bag.sorted) (d.code, d.pointer?.value)],
      [
        (DiagnosticCode.unknownOverrideKey, '#/paths'),
        (DiagnosticCode.unknownOverrideKey, '#/operations/getPet/summary'),
        (
          DiagnosticCode.unknownOverrideKey,
          '#/operations/getPet/parameters/id/in',
        ),
        (
          DiagnosticCode.unknownOverrideKey,
          '#/operations/getPet/requestBody/required',
        ),
        (
          DiagnosticCode.unknownOverrideKey,
          '#/operations/getPet/responses/200/headers',
        ),
        (DiagnosticCode.unknownOverrideKey, '#/schemas/Pet/title'),
        (DiagnosticCode.unknownOverrideKey, '#/schemas/Pet/dartType/from'),
        (
          DiagnosticCode.unknownOverrideKey,
          '#/schemas/Pet/properties/id/nullabel',
        ),
      ],
    );
    expect(set.schemas.single.properties.single.spec, {'nullable': true});
    expect(set.schemas.single.dartType?.type, 'P');
  });

  test('an unknown key is an error that suggests a close known key', () {
    final bag = DiagnosticBag();
    final set = parse(bag, '''
schemas:
  Pet:
    properties:
      id: {nulable: true, type: string}
    exhaustiveness: false
operations:
  getPet:
    responses:
      '200': {sse: {type: object}}
''')!;
    final [typo, far, sse] = bag.sorted;
    expect(typo.code, DiagnosticCode.unknownOverrideKey);
    expect(typo.severity, Severity.error);
    expect(typo.pointer?.value, '#/schemas/Pet/properties/id/nulable');
    expect(
      typo.fix,
      startsWith('Did you mean "nullable"? Allowed keys here: '),
    );
    expect(far.pointer?.value, '#/schemas/Pet/exhaustiveness');
    expect(far.fix, startsWith('Allowed keys here: '));
    expect(sse.pointer?.value, '#/operations/getPet/responses/200/sse');
    expect(sse.fix, startsWith('Allowed keys here: '));
    expect(set.schemas.single.properties.single.spec, {'type': 'string'});
  });

  test('reports values of the wrong type and ignores only them', () {
    final bag = DiagnosticBag();
    final set = parse(bag, '''
operations:
  getPet:
    name: ''
    exclude: yes
    parameters:
      id: {required: 1, schema: string}
    requestBody: {contentType: json}
    responses: []
  listPets: 1
schemas:
  Pet:
    type: 'null'
    nullable: 'true'
    required: [1]
    enum: []
    items: [1]
    additionalProperties: 1
    exhaustive: 0
    dartType: {type: Pet}
    format: date
    properties:
      id: {required: [id], type: string}
''')!;
    expect(
      [for (final d in bag.sorted) d.pointer?.value],
      [
        '#/operations/getPet/name',
        '#/operations/getPet/exclude',
        '#/operations/getPet/parameters/id/required',
        '#/operations/getPet/parameters/id/schema',
        '#/operations/getPet/requestBody/contentType',
        '#/operations/getPet/responses',
        '#/operations/listPets',
        '#/schemas/Pet/type',
        '#/schemas/Pet/nullable',
        '#/schemas/Pet/required',
        '#/schemas/Pet/enum',
        '#/schemas/Pet/items',
        '#/schemas/Pet/additionalProperties',
        '#/schemas/Pet/exhaustive',
        '#/schemas/Pet/dartType',
        '#/schemas/Pet/properties/id/required',
      ],
    );
    expect(
      bag.all.every((d) => d.code == DiagnosticCode.invalidOverride),
      isTrue,
    );
    final get = set.operations.single;
    expect((get.name, get.exclude), (null, null));
    expect(get.parameters.single.spec, isEmpty);
    expect(get.requestBody?.spec, isEmpty);
    final pet = set.schemas.single;
    expect(pet.spec, {'format': 'date'});
    expect(pet.dartType, isNull);
    expect(pet.properties.single.spec, {'type': 'string'});
  });

  test(r'"$ref" replaces the schema: other schema fields are reported', () {
    final bag = DiagnosticBag();
    final set = parse(bag, r'''
schemas:
  Pet:
    $ref: '#/components/schemas/Animal'
    nullable: true
    type: object
    name: Animal
    properties:
      id: {type: string}
  Owner:
    properties:
      pet:
        $ref: '#/components/schemas/Pet'
        required: true
        format: uuid
''')!;
    expect(
      [for (final d in bag.sorted) (d.code, d.pointer?.value)],
      [
        (DiagnosticCode.invalidOverride, '#/schemas/Pet/type'),
        (DiagnosticCode.invalidOverride, '#/schemas/Pet/properties'),
        (
          DiagnosticCode.invalidOverride,
          '#/schemas/Owner/properties/pet/format',
        ),
      ],
    );
    final [pet, owner] = set.schemas;
    expect(pet.spec.keys, [r'$ref', 'nullable']);
    expect(pet.name, 'Animal');
    expect(pet.properties, isEmpty);
    expect(owner.properties.single.spec.keys, [r'$ref', 'required']);
  });

  test('reports an operation key with an unknown method and a parameter '
      'key with an unknown "in"', () {
    final bag = DiagnosticBag();
    final set = parse(bag, '''
operations:
  FETCH /pets: {name: fetch}
  GET /pets:
    parameters:
      body:id: {required: true}
      path:id: {required: true}
''')!;
    expect(
      [for (final d in bag.sorted) d.pointer?.value],
      [
        '#/operations/FETCH ~1pets',
        '#/operations/GET ~1pets/parameters/body:id',
      ],
    );
    final get = set.operations.single;
    expect((get.method, get.path), ('get', '/pets'));
    expect(get.parameters.single.placement, ParameterLocation.path);
  });
}
