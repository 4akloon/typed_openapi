import 'package:test/test.dart';
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/config/project_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/ir/dart_type.dart';
import 'package:typed_openapi/src/ir/ir.dart';
import 'package:typed_openapi/src/ir/ir_builder.dart';
import 'package:typed_openapi/src/ir/ir_json.dart';

import '../helpers/ir_fixture.dart';

/// The IR of [fixture]'s spec.
ClientIr build(IrFixture fixture) => IrBuilder(
  fixture.diagnostics,
).build(fixture.context.spec, fixture.context.client);

/// The operations of [ir] as `Group.method` strings.
List<String> methods(ClientIr ir) => [
  for (final group in ir.groups)
    for (final operation in group.operations) '${group.name}.${operation.name}',
];

/// The JSON of the operation [name] of [ir].
Map<String, Object?> operationJson(ClientIr ir, String name) {
  final json = IrJson((_) => 'api.yaml').toJson(ir);
  for (final group
      in (json['groups']! as List<Object?>).cast<Map<String, Object?>>()) {
    for (final operation
        in (group['operations']! as List<Object?>)
            .cast<Map<String, Object?>>()) {
      if (operation['name'] == name) return operation..remove('at');
    }
  }
  throw StateError('No operation $name');
}

void main() {
  test('groups operations by first tag and names methods (R5.1, R5.3)', () {
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets:
    get: {operationId: PetController_list, tags: [pets], responses: {"200": {description: ok}}}
    post: {operationId: PetController_create, tags: [pets, admin], responses: {"201": {description: ok}}}
  /pets/{id}:
    parameters: [{name: id, in: path, required: true, schema: {type: integer}}]
    get: {tags: [Pets], responses: {"200": {description: ok}}}
  /health:
    get: {operationId: health, responses: {"200": {description: ok}}}
  /store/order:
    get: {operationId: get_order, tags: [store front], responses: {"200": {description: ok}}}
  /users/{userId}/posts/{postId}:
    get:
      tags: [users]
      parameters:
        - {name: userId, in: path, required: true, schema: {type: string}}
        - {name: postId, in: path, required: true, schema: {type: string}}
      responses: {"200": {description: ok}}
''', preset: Preset.nestjs);
    final ir = build(fixture);
    expect(methods(ir), [
      'DefaultApi.health',
      'PetsApi.create',
      'PetsApi.getPetsById',
      'PetsApi.list',
      'StoreFrontApi.getOrder',
      'UsersApi.getUsersPostsByUserIdAndPostId',
    ]);
    expect(fixture.codes, [
      (DiagnosticCode.operationMultipleTags, '#/paths/~1pets/post/tags'),
      (DiagnosticCode.tagsMerged, '#/paths/~1pets~1{id}/get/tags/0'),
      (DiagnosticCode.operationUntagged, '#/paths/~1health/get'),
    ]);
    expect(fixture.reported[0].fix, '''
Keep one tag at the source, or name the group. Override:
operations:
  PetController_create:
    group: Pets''');
  });

  test('groups by path or into one class, as configured', () {
    const spec = '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets: {get: {operationId: listPets, responses: {"200": {description: ok}}}}
  /{id}/store: {get: {operationId: getStore, parameters: [{name: id, in: path, required: true, schema: {type: string}}], responses: {"200": {description: ok}}}}
  /: {get: {operationId: root, responses: {"200": {description: ok}}}}
''';
    expect(
      methods(
        build(
          IrFixture(
            spec,
            generation: const GenerationConfig(groupBy: GroupBy.path),
          ),
        ),
      ),
      ['DefaultApi.root', 'PetsApi.listPets', 'StoreApi.getStore'],
    );
    expect(
      methods(
        build(
          IrFixture(
            spec,
            generation: const GenerationConfig(
              groupBy: GroupBy.single,
              defaultGroup: 'Client',
            ),
          ),
        ),
      ),
      ['Client.getStore', 'Client.listPets', 'Client.root'],
    );
  });

  test('gives colliding methods a suffix and uses override names', () {
    final fixture = IrFixture(
      '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a: {get: {operationId: get_item, tags: [x], responses: {"200": {description: ok}}}}
  /b: {get: {operationId: getItem, tags: [x], responses: {"200": {description: ok}}}}
  /c: {get: {operationId: toString, tags: [x], responses: {"200": {description: ok}}}}
  /d: {get: {operationId: d, tags: [x], responses: {"200": {description: ok}}}}
''',
      overrides: '''
operations:
  d: {name: fetchD, group: Other}
''',
    );
    final ir = build(fixture);
    expect(methods(ir), [
      'OtherApi.fetchD',
      'XApi.getItem',
      'XApi.getItem2',
      'XApi.toString_',
    ]);
    expect(fixture.codes, [
      (DiagnosticCode.nameCollision, '#/paths/~1b/get'),
      (DiagnosticCode.nameReserved, '#/paths/~1c/get'),
    ]);
  });

  test('merges path item parameters and names arguments (R5.2)', () {
    final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets/{id}:
    parameters:
      - {name: id, in: path, required: true, schema: {type: string}}
      - {name: limit, in: query, schema: {type: integer}}
    get:
      operationId: getPet
      tags: [pets]
      parameters:
        - {name: id, in: path, required: true, schema: {type: integer}}
        - {name: id, in: query, schema: {type: string}}
        - {$ref: '#/components/parameters/Trace'}
        - {name: class, in: query, required: true, schema: {type: string, enum: [a, b]}}
      responses: {"200": {description: ok}}
components:
  parameters:
    Trace: {name: X-Trace-Id, in: header, schema: {type: string, format: uuid}}
''');
    final ir = build(fixture);
    expect(operationJson(ir, 'getPet')['parameters'], [
      {
        'name': 'id',
        'in': 'path',
        'wire': 'id',
        'type': 'int',
        'required': true,
      },
      {'name': 'limit', 'in': 'query', 'wire': 'limit', 'type': 'int?'},
      {'name': 'idQuery', 'in': 'query', 'wire': 'id', 'type': 'String?'},
      {
        'name': 'class_',
        'in': 'query',
        'wire': 'class',
        'type': 'GetPetClass',
        'required': true,
      },
      {
        'name': 'xTraceId',
        'in': 'header',
        'wire': 'X-Trace-Id',
        'type': 'String?',
      },
    ]);
    expect(fixture.codes, [
      (DiagnosticCode.nameCollision, '#/paths/~1pets~1{id}/get/parameters/1'),
      (DiagnosticCode.nameReserved, '#/paths/~1pets~1{id}/get/parameters/3'),
    ]);
    expect(fixture.reported.first.fix, '''
Name the argument explicitly to keep the name stable. Override:
operations:
  getPet:
    parameters:
      "query:id":
        name: idQuery''');
  });

  test('does not generate an operation whose path variable is unbound', () {
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets/{id}/{ID}:
    get:
      operationId: getPet
      parameters: [{name: id, in: path, required: true, schema: {type: string}}]
      responses: {"200": {description: ok}}
''');
    final ir = build(fixture);
    expect(ir.groups, isEmpty);
    expect(fixture.codes, [
      (DiagnosticCode.operationUntagged, '#/paths'),
      (DiagnosticCode.pathVariableUnbound, '#/paths/~1pets~1{id}~1{ID}/get'),
      (DiagnosticCode.clientEmpty, '#/paths'),
    ]);
  });

  test('maps bodies, responses and envelopes (R6.4, R10.6)', () {
    final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets:
    post:
      operationId: createPet
      tags: [pets]
      requestBody:
        required: true
        content:
          text/plain: {schema: {type: string}}
          application/json:
            schema: {type: object, required: [name], properties: {name: {type: string}}}
      responses:
        "200": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/PetData'}}}}
        "201":
          description: created
          content:
            application/json:
              schema: {type: object, properties: {id: {type: integer}}}
        "204": {description: none}
        "202": {description: text, content: {text/plain: {schema: {type: string}}}}
  /pets/{id}/photo:
    get:
      operationId: getPhoto
      tags: [pets]
      parameters: [{name: id, in: path, required: true, schema: {type: string}}]
      responses:
        "200": {description: ok, content: {image/png: {schema: {type: string, format: binary}}}}
components:
  schemas:
    Pet: {type: object, properties: {name: {type: string}}}
    PetData:
      type: object
      required: [data]
      properties:
        data: {$ref: '#/components/schemas/Pet'}
''');
    final ir = build(fixture);
    // The text alternative of the request body is dropped.
    expect(fixture.codes, [
      (
        DiagnosticCode.mediaTypeAsBytes,
        '#/paths/~1pets/post/requestBody/content',
      ),
    ]);
    final create = operationJson(ir, 'createPet');
    expect(create['body'], {
      'kind': 'json',
      'contentType': 'application/json',
      'type': 'CreatePetRequest',
      'required': true,
    });
    expect(create['responses'], [
      {'status': '200', 'kind': 'json', 'type': 'Pet', 'envelope': 'data'},
      {'status': '201', 'kind': 'json', 'type': 'CreatePetResponse201'},
      {'status': '204', 'kind': 'none'},
      {'status': '202', 'kind': 'text', 'type': 'String'},
    ]);
    expect(create['errors'], 'Never');
    expect(operationJson(ir, 'getPhoto')['responses'], [
      {'status': '200', 'kind': 'bytes', 'type': 'Uint8List'},
    ]);
    expect(ir.declarations.map((d) => d.name), [
      'CreatePetRequest',
      'CreatePetResponse201',
      'Pet',
    ]);
  });

  test('adds the status to inline names only when a kind has several '
      'bodies', () {
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets:
    get:
      operationId: getPet
      tags: [pets]
      responses:
        "200": {description: ok, content: {application/json: {schema: {type: object, properties: {a: {type: string}}}}}}
        "204": {description: none}
        "404": {description: no, content: {application/json: {schema: {type: object, properties: {b: {type: string}}}}}}
    post:
      operationId: createPet
      tags: [pets]
      responses:
        "200": {description: ok}
        "400": {description: bad, content: {application/json: {schema: {type: object, properties: {c: {type: string}}}}}}
        "404": {description: no, content: {application/json: {schema: {type: object, properties: {d: {type: string}}}}}}
        default: {description: other, content: {application/json: {schema: {type: object, properties: {e: {type: string}}}}}}
''');
    final ir = build(fixture);
    expect(fixture.reported, isEmpty);
    expect(ir.declarations.map((d) => d.name), [
      'CreatePetError400',
      'CreatePetError404',
      'CreatePetErrorDefault',
      'GetPetError',
      'GetPetResponse',
    ]);
  });

  test('types errors by R11.4', () {
    const spec = r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: one
      responses:
        "200": {description: ok}
        "400": {description: bad, content: {application/json: {schema: {$ref: '#/components/schemas/Err'}}}}
        "404": {description: missing, content: {application/json: {schema: {$ref: '#/components/schemas/Err'}}}}
  /b:
    get:
      operationId: two
      responses:
        "200": {description: ok}
        "400": {description: bad, content: {application/json: {schema: {$ref: '#/components/schemas/Err'}}}}
        "409": {description: conflict, content: {application/json: {schema: {$ref: '#/components/schemas/Conflict'}}}}
        default: {description: other}
  /c:
    get:
      operationId: three
      responses:
        "200": {description: ok}
        "500": {description: down}
components:
  schemas:
    Err: {type: object, properties: {message: {type: string}}}
    Conflict: {type: object, properties: {id: {type: string}}}
''';
    final plain = build(IrFixture(spec));
    expect(operationJson(plain, 'one')['errors'], 'Err');
    expect(operationJson(plain, 'two')['errors'], {
      '400': 'Err',
      '409': 'Conflict',
      'default': null,
    });
    expect(operationJson(plain, 'three')['errors'], {'500': null});
    final withDefault = build(
      IrFixture(
        spec,
        generation: const GenerationConfig(defaultErrorSchema: 'Err'),
      ),
    );
    expect(operationJson(withDefault, 'one')['errors'], 'Err');
    expect(operationJson(withDefault, 'two')['errors'], {
      '400': 'Err',
      '409': 'Conflict',
      'default': 'Err',
    });
    expect(operationJson(withDefault, 'three')['errors'], 'Err');
  });

  test('builds a valid spec without diagnostics', () {
    final fixture = IrFixture(r'''
openapi: 3.0.3
info: {title: t, version: "1"}
tags: [{name: pets}]
paths:
  /pets/{petId}:
    get:
      operationId: getPetById
      tags: [pets]
      parameters: [{name: petId, in: path, required: true, schema: {type: integer, format: int64}}]
      responses:
        "200": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/Pet'}}}}
        "404": {description: missing, content: {application/json: {schema: {$ref: '#/components/schemas/ApiError'}}}}
components:
  schemas:
    Pet:
      type: object
      required: [id, name]
      properties:
        id: {type: integer, format: int64}
        name: {type: string}
        status: {type: string, enum: [available, sold]}
    ApiError:
      type: object
      properties:
        message: {type: string}
''');
    final ir = build(fixture);
    expect(fixture.reported, isEmpty);
    expect(methods(ir), ['PetsApi.getPetById']);
    expect(ir.declarations.map((d) => d.name), [
      'ApiError',
      'Pet',
      'PetStatus',
    ]);
  });

  test('splits a model by direction only when it needs to (spec 4)', () {
    final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /owners:
    post:
      operationId: createOwner
      tags: [owners]
      requestBody: {content: {application/json: {schema: {$ref: '#/components/schemas/Owner'}}}}
      responses:
        "201": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/Owner'}}}}
  /audit:
    get:
      operationId: audit
      tags: [owners]
      responses:
        "200": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/Audit'}}}}
components:
  schemas:
    Owner:
      type: object
      properties:
        name: {type: string}
        pet: {$ref: '#/components/schemas/Pet'}
        tag: {$ref: '#/components/schemas/Tag'}
    Pet:
      type: object
      properties:
        id: {type: integer, readOnly: true}
        name: {type: string}
        password: {type: string, writeOnly: true}
    Tag:
      type: object
      properties:
        label: {type: string}
    Audit:
      type: object
      properties:
        id: {type: integer, readOnly: true}
''');
    final ir = build(fixture);
    expect(fixture.reported, isEmpty);
    List<String> fields(String name) => [
      for (final f
          in (ir.declarations.firstWhere((d) => d.name == name) as ModelDecl)
              .fields)
        '${f.name}: ${f.type.code(ir.nameOf)}',
    ];
    expect(ir.declarations.map((d) => (d.name, (d as ModelDecl).direction)), [
      ('Audit', ModelDirection.response),
      ('Owner', ModelDirection.response),
      ('OwnerInput', ModelDirection.request),
      ('Pet', ModelDirection.response),
      ('PetInput', ModelDirection.request),
      ('Tag', ModelDirection.both),
    ]);
    expect(fields('Pet'), ['id: int?', 'name: String?']);
    expect(fields('PetInput'), ['name: String?', 'password: String?']);
    expect(fields('OwnerInput'), [
      'name: String?',
      'pet: PetInput?',
      'tag: Tag?',
    ]);
    expect(fields('Audit'), ['id: int?']);
    expect(operationJson(ir, 'createOwner')['body'], {
      'kind': 'json',
      'contentType': 'application/json',
      'type': 'OwnerInput',
    });
  });

  test('makes PATCH body fields tri-state by the configured rule (R7.2)', () {
    const spec = r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets/{id}:
    parameters: [{name: id, in: path, required: true, schema: {type: string}}]
    patch:
      operationId: updatePet
      tags: [pets]
      requestBody:
        required: true
        content: {application/json: {schema: {$ref: '#/components/schemas/UpdatePet'}}}
      responses: {"204": {description: ok}}
    put:
      operationId: replacePet
      tags: [pets]
      requestBody:
        required: true
        content: {application/json: {schema: {$ref: '#/components/schemas/Pet'}}}
      responses: {"204": {description: ok}}
components:
  schemas:
    UpdatePet:
      type: object
      required: [owner]
      properties:
        tag: {type: [string, "null"]}
        name: {type: string}
        owner: {type: [string, "null"]}
        note: {type: [string, "null"], x-typed-tri-state: true}
    Pet:
      type: object
      properties:
        tag: {type: [string, "null"]}
''';
    List<String> fields(ClientIr ir, String name) => [
      for (final f
          in (ir.declarations.firstWhere((d) => d.name == name) as ModelDecl)
              .fields)
        '${f.name}: ${f.type.code(ir.nameOf)}',
    ];
    final byDefault = build(IrFixture(spec));
    expect(fields(byDefault, 'UpdatePet'), [
      'tag: Patch<String>?',
      'name: String?',
      'owner: String?',
      'note: Patch<String>?',
    ]);
    expect(fields(byDefault, 'Pet'), ['tag: String?']);
    final optional = build(
      IrFixture(
        spec,
        generation: const GenerationConfig(triState: TriStateRule.optional),
      ),
    );
    expect(fields(optional, 'UpdatePet'), [
      'tag: Patch<String>?',
      'name: Patch<String>?',
      'owner: String?',
      'note: Patch<String>?',
    ]);
    final extension = build(
      IrFixture(
        spec,
        generation: const GenerationConfig(triState: TriStateRule.extension),
        overrides: '''
schemas:
  Pet:
    properties:
      tag: {triState: true}
''',
      ),
    );
    expect(fields(extension, 'UpdatePet'), [
      'tag: String?',
      'name: String?',
      'owner: String?',
      'note: Patch<String>?',
    ]);
    expect(fields(extension, 'Pet'), ['tag: Patch<String>?']);
  });

  test('gives a PATCH body schema used elsewhere a model of its own', () {
    const spec = r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets:
    post:
      operationId: createPet
      tags: [pets]
      requestBody: {content: {application/json: {schema: {$ref: '#/components/schemas/Pet'}}}}
      responses:
        "201": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/Pet'}}}}
  /pets/{id}:
    parameters: [{name: id, in: path, required: true, schema: {type: string}}]
    patch:
      operationId: updatePet
      tags: [pets]
      requestBody: {content: {application/json: {schema: {$ref: '#/components/schemas/Pet'}}}}
      responses: {"204": {description: ok}}
components:
  schemas:
    Pet:
      type: object
      required: [name]
      properties:
        id: {type: integer, readOnly: true}
        name: {type: string}
        tag: {type: [string, "null"]}
        owner: {$ref: '#/components/schemas/Owner'}
    Owner:
      type: object
      properties:
        id: {type: integer, readOnly: true}
        name: {type: string}
''';
    List<String> fields(ClientIr ir, String name) => [
      for (final f
          in (ir.declarations.firstWhere((d) => d.name == name) as ModelDecl)
              .fields)
        '${f.name}: ${f.type.code(ir.nameOf)}',
    ];
    final fixture = IrFixture(spec);
    final ir = build(fixture);
    expect(fixture.reported, isEmpty);
    expect(ir.declarations.map((d) => (d.name, d.id.variant)), [
      ('Owner', DeclVariant.base),
      ('OwnerInput', DeclVariant.input),
      ('Pet', DeclVariant.base),
      ('PetInput', DeclVariant.input),
      ('PetPatch', DeclVariant.patch),
    ]);
    expect(fields(ir, 'Pet'), [
      'id: int?',
      'name: String',
      'tag: String?',
      'owner: Owner?',
    ]);
    expect(fields(ir, 'PetInput'), [
      'name: String',
      'tag: String?',
      'owner: OwnerInput?',
    ]);
    expect(fields(ir, 'PetPatch'), [
      'name: String',
      'tag: Patch<String>?',
      'owner: OwnerInput?',
    ]);
    expect(operationJson(ir, 'updatePet')['body'], {
      'kind': 'json',
      'contentType': 'application/json',
      'type': 'PetPatch',
    });

    final renamed = build(
      IrFixture(
        spec,
        generation: const GenerationConfig(patchSuffix: 'Changes'),
        overrides: 'schemas:\n  Pet: {name: Animal}\n',
      ),
    );
    expect(renamed.declarations.map((d) => d.name), [
      'Animal',
      'AnimalChanges',
      'AnimalInput',
      'Owner',
      'OwnerInput',
    ]);
  });

  test('declares an inline schema shared by several operations once', () {
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets:
    parameters:
      - name: filter
        in: query
        schema:
          type: object
          properties:
            a: {type: string, enum: [x, y]}
    get: {operationId: getPets, tags: [pets], responses: {"204": {description: ok}}}
    delete: {operationId: deletePets, tags: [pets], responses: {"204": {description: ok}}}
''');
    final ir = build(fixture);
    expect(fixture.reported, isEmpty);
    expect(ir.declarations.map((d) => d.name), [
      'DeletePetsFilter',
      'DeletePetsFilterA',
    ]);
    expect(
      [
        for (final o in ir.groups.single.operations)
          o.parameters.single.type.code(ir.nameOf),
      ],
      ['DeletePetsFilter?', 'DeletePetsFilter?'],
    );
  });

  test('skips a parameter without a valid location and builds the rest', () {
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets:
    get:
      operationId: getPets
      tags: [pets]
      parameters:
        - {name: a, in: Query, schema: {type: string}}
        - {name: b, schema: {type: string}}
        - {name: c, in: query, schema: {type: string}}
      responses: {"204": {description: ok}}
''');
    final ir = build(fixture);
    expect(
      [for (final p in ir.groups.single.operations.single.parameters) p.name],
      ['c'],
    );
    // The parser has reported both; the IR adds nothing.
    expect(fixture.reported, isEmpty);
    expect(
      fixture.diagnostics.all.where(
        (d) =>
            d.code == DiagnosticCode.invalidValue ||
            d.code == DiagnosticCode.missingRequiredField,
      ),
      hasLength(2),
    );
  });

  test(
    'splits a model by direction whatever order the schemas are used in',
    () {
      String spec(String first, String second) =>
          '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: getA
      tags: [t]
      responses: {"200": {description: ok, content: {application/json: {schema: {\$ref: '#/components/schemas/$first'}}}}}
    post:
      operationId: postA
      tags: [t]
      requestBody: {content: {application/json: {schema: {\$ref: '#/components/schemas/$first'}}}}
      responses: {"204": {description: ok}}
  /b:
    get:
      operationId: getB
      tags: [t]
      responses: {"200": {description: ok, content: {application/json: {schema: {\$ref: '#/components/schemas/$second'}}}}}
    post:
      operationId: postB
      tags: [t]
      requestBody: {content: {application/json: {schema: {\$ref: '#/components/schemas/$second'}}}}
      responses: {"204": {description: ok}}
components:
  schemas:
    X:
      type: object
      properties:
        y: {\$ref: '#/components/schemas/Y'}
        c: {\$ref: '#/components/schemas/C'}
    Y:
      type: object
      properties:
        x: {\$ref: '#/components/schemas/X'}
    C:
      type: object
      properties:
        id: {type: integer, readOnly: true}
''';
      for (final (first, second) in [('X', 'Y'), ('Y', 'X')]) {
        final fixture = IrFixture(spec(first, second));
        final ir = build(fixture);
        expect(fixture.reported, isEmpty, reason: '$first, $second');
        expect(
          ir.declarations.map((d) => d.name),
          ['C', 'CInput', 'X', 'XInput', 'Y', 'YInput'],
          reason: '$first, $second',
        );
      }
    },
  );

  test('names a schema a ref finds outside components.schemas', () {
    final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets/{id}:
    get:
      operationId: getPet
      tags: [pets]
      parameters: [{name: id, in: path, required: true, schema: {type: string}}]
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema: {$ref: '#/components/schemas/Pet/properties/owner'}
    post:
      $ref: '#/components/pathItems/Other'
components:
  schemas:
    Pet:
      type: object
      properties:
        owner: {type: object, properties: {name: {type: string}}}
''');
    final ir = build(fixture);
    expect(ir.declarations.map((d) => d.name), ['Owner']);
    expect(ir.groups.single.operations.map((o) => o.name), ['getPet']);
    expect(
      fixture.codes.where((c) => c.$1 == DiagnosticCode.pathVariableUnbound),
      isEmpty,
    );
  });
}
