import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/load/openapi_version.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/overrides/override_loader.dart';
import 'package:typed_openapi/src/overrides/override_resolver.dart';
import 'package:typed_openapi/src/resolve/spec_documents.dart';
import 'package:typed_openapi/src/resolve/spec_reader.dart';

const _spec = r'''
openapi: 3.1.0
info: {title: t, version: '1'}
paths:
  /pets/{id}:
    parameters:
      - {name: id, in: path, required: true, schema: {type: string}}
    get:
      operationId: getPet
      parameters:
        - {name: id, in: query, schema: {type: string}}
        - $ref: '#/components/parameters/Limit'
      responses:
        '200': {$ref: '#/components/responses/PetResponse'}
    delete:
      operationId: deletePet
      requestBody:
        content: {application/json: {schema: {type: object}}}
      responses:
        '204': {description: gone}
  /pets:
    get:
      operationId: listPets
      responses: {'200': {description: ok}}
    post:
      operationId: listPets
      responses: {'201': {description: ok}}
components:
  parameters:
    Limit: {name: limit, in: query, schema: {type: integer}}
  responses:
    PetResponse:
      description: ok
      content:
        application/json: {schema: {$ref: '#/components/schemas/Pet'}}
  schemas:
    Pet:
      type: object
      properties:
        id: {type: string}
        owner: {$ref: '#/components/schemas/Owner'}
    Owner: {type: object}
    Animal: {$ref: '#/components/schemas/Pet'}
    Flag: true
''';

/// The targets of [overrides] in [_spec], and what the resolver reported.
(List<OverrideTarget>, DiagnosticBag) _resolve(String overrides) {
  final setup = DiagnosticBag();
  final document = SpecLoader(setup).parse(_spec, 'api.yaml')!;
  final version = OpenApiVersionDetector(setup).detect(document)!;
  final documents = SpecDocuments(SpecLoader(setup), document);
  final model = SpecReader(
    setup,
  ).read(document, version, documents: documents);
  final set = OverrideLoader(setup).parse(overrides, 'o.yaml')!;
  expect(
    setup.all.where((d) => d.file == 'o.yaml'),
    isEmpty,
    reason: 'the overrides file itself is valid',
  );
  final bag = DiagnosticBag();
  return (OverrideResolver(bag, set).resolve(model, documents), bag);
}

/// Each target as (entry pointer, node pointer).
List<(String, String)> _pairs(List<OverrideTarget> targets) => [
  for (final t in targets) (t.entry.pointer.value, t.node.pointer.value),
];

void main() {
  test(r'finds every kind of node, through $refs, without diagnostics', () {
    final (targets, bag) = _resolve('''
operations:
  getPet:
    parameters:
      path:id: {name: petId}
      query:id: {required: false}
      limit: {name: max}
    responses:
      '200': {reason: x}
  DELETE /pets/{id}:
    requestBody: {contentType: application/json}
  get /pets: {name: list}
schemas:
  Pet:
    type: object
    properties:
      owner: {nullable: true}
  Owner: {exhaustive: false}
''');
    expect(bag.all, isEmpty);
    expect(_pairs(targets), [
      ('#/operations/getPet', '#/paths/~1pets~1{id}/get'),
      (
        '#/operations/getPet/parameters/path:id',
        '#/paths/~1pets~1{id}/parameters/0',
      ),
      (
        '#/operations/getPet/parameters/query:id',
        '#/paths/~1pets~1{id}/get/parameters/0',
      ),
      ('#/operations/getPet/parameters/limit', '#/components/parameters/Limit'),
      (
        '#/operations/getPet/responses/200',
        '#/components/responses/PetResponse',
      ),
      ('#/operations/DELETE ~1pets~1{id}', '#/paths/~1pets~1{id}/delete'),
      (
        '#/operations/DELETE ~1pets~1{id}/requestBody',
        '#/paths/~1pets~1{id}/delete/requestBody',
      ),
      ('#/operations/get ~1pets', '#/paths/~1pets/get'),
      ('#/schemas/Pet', '#/components/schemas/Pet'),
      (
        '#/schemas/Pet/properties/owner',
        '#/components/schemas/Pet/properties/owner',
      ),
      ('#/schemas/Owner', '#/components/schemas/Owner'),
    ]);
    expect(targets[9], isA<PropertyTarget>());
    expect(
      (targets[9] as PropertyTarget).owner.pointer.value,
      '#/components/schemas/Pet',
    );
  });

  test(r'a schema override follows the $ref of a components key', () {
    final (targets, bag) = _resolve('schemas: {Animal: {nullable: true}}');
    expect(bag.all, isEmpty);
    expect(_pairs(targets), [('#/schemas/Animal', '#/components/schemas/Pet')]);
  });

  test('a missing node is a warning with the reason, and the rest applies', () {
    final (targets, bag) = _resolve('''
operations:
  getPets: {reason: renamed upstream, name: x}
  GET /owners: {name: x}
  PUT /pets: {name: x}
  getPet:
    parameters:
      header:limit: {required: true}
      offset: {required: true}
    requestBody: {contentType: application/json}
    responses:
      '404': {contentType: application/json}
schemas:
  Cat: {type: object}
  Flag: {type: object}
  Pet:
    properties:
      name: {type: string}
      id: {type: integer}
''');
    expect(
      [for (final d in bag.sorted) (d.code, d.pointer?.value)],
      [
        for (final p in [
          '#/operations/getPets',
          '#/operations/GET ~1owners',
          '#/operations/PUT ~1pets',
          '#/operations/getPet/parameters/header:limit',
          '#/operations/getPet/parameters/offset',
          '#/operations/getPet/requestBody',
          '#/operations/getPet/responses/404',
          '#/schemas/Cat',
          '#/schemas/Flag',
          '#/schemas/Pet/properties/name',
        ])
          (DiagnosticCode.overrideTargetNotFound, p),
      ],
    );
    expect(
      bag.sorted.first.message,
      'No operation has operationId "getPets". The override is not applied. '
      'Reason given: "renamed upstream".',
    );
    expect(bag.sorted.first.file, 'o.yaml');
    expect(bag.sorted.first.line, 2);
    expect(bag.sorted[1].message, startsWith('The path /owners is not in'));
    expect(bag.sorted[2].message, startsWith('The path /pets has no PUT'));
    expect(_pairs(targets), [
      ('#/operations/getPet', '#/paths/~1pets~1{id}/get'),
      ('#/schemas/Pet', '#/components/schemas/Pet'),
      ('#/schemas/Pet/properties/id', '#/components/schemas/Pet/properties/id'),
    ]);
  });

  test('an operationId two operations share is ambiguous', () {
    final (targets, bag) = _resolve('''
operations:
  listPets:
    parameters:
      nope: {required: true}
''');
    expect(targets, isEmpty);
    final d = bag.all.single;
    expect(d.code, DiagnosticCode.overrideTargetAmbiguous);
    expect(d.pointer?.value, '#/operations/listPets');
    expect(
      d.fix,
      'Address the operation as METHOD /path: GET /pets, POST /pets.',
    );
  });

  test('a parameter name shared by two "in"s is ambiguous', () {
    final (targets, bag) = _resolve('''
operations:
  getPet:
    parameters:
      id: {required: true}
''');
    expect(_pairs(targets), [
      ('#/operations/getPet', '#/paths/~1pets~1{id}/get'),
    ]);
    final d = bag.all.single;
    expect(d.code, DiagnosticCode.overrideTargetAmbiguous);
    expect(d.pointer?.value, '#/operations/getPet/parameters/id');
    expect(d.fix, 'Write the key as in:name: path:id, query:id.');
  });

  test('two overrides of one node conflict and neither applies', () {
    final (targets, bag) = _resolve('''
operations:
  getPet:
    parameters:
      limit: {required: true}
  GET /pets/{id}: {name: x}
  deletePet:
    parameters:
      id: {required: true}
      path:id: {name: petId}
schemas:
  Pet: {type: object}
  Animal: {nullable: true}
''');
    expect(
      [for (final d in bag.sorted) (d.code, d.pointer?.value)],
      [
        for (final p in [
          '#/operations/getPet',
          '#/operations/GET ~1pets~1{id}',
          '#/operations/deletePet/parameters/id',
          '#/operations/deletePet/parameters/path:id',
          '#/schemas/Pet',
          '#/schemas/Animal',
        ])
          (DiagnosticCode.overrideConflict, p),
      ],
    );
    expect(
      bag.sorted.first.message,
      'This override and the one at #/operations/GET ~1pets~1{id} name the '
      'same node (#/paths/~1pets~1{id}/get); neither is applied.',
    );
    expect(_pairs(targets), [
      ('#/operations/deletePet', '#/paths/~1pets~1{id}/delete'),
    ]);
  });

  test('a spec change through an operation of a node it shares is an info '
      'that names the node', () {
    final (targets, bag) = _resolve('''
operations:
  getPet:
    parameters:
      path:id: {required: true}
      query:id: {required: true}
      limit: {required: true}
    responses:
      '200': {contentType: application/json}
  deletePet:
    requestBody: {contentType: application/json}
schemas:
  Pet: {nullable: true}
''');
    expect(
      [for (final d in bag.sorted) (d.code, d.pointer?.value)],
      [
        for (final p in [
          '#/operations/getPet/parameters/path:id',
          '#/operations/getPet/parameters/limit',
          '#/operations/getPet/responses/200',
        ])
          (DiagnosticCode.overrideSharedTarget, p),
      ],
    );
    expect(
      bag.sorted.first.message,
      'This override changes the shared node at '
      '#/paths/~1pets~1{id}/parameters/0; the change applies to every '
      'operation that uses it.',
    );
    expect(targets, hasLength(8));
  });

  test('two operations may each override a parameter they share', () {
    final (targets, bag) = _resolve('''
operations:
  getPet:
    parameters:
      path:id: {name: petId}
  deletePet:
    parameters:
      id: {name: petId}
''');
    expect(bag.all, isEmpty);
    expect(_pairs(targets).map((p) => p.$2), [
      '#/paths/~1pets~1{id}/get',
      '#/paths/~1pets~1{id}/parameters/0',
      '#/paths/~1pets~1{id}/delete',
      '#/paths/~1pets~1{id}/parameters/0',
    ]);
  });
}
