import 'package:test/test.dart';
import 'package:typed_openapi_core/src/config/generation_config.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/ir/ir.dart';
import 'package:typed_openapi_core/src/ir/ir_builder.dart';

import '../helpers/ir_fixture.dart';

ClientIr build(IrFixture fixture) => IrBuilder(
  fixture.diagnostics,
).build(fixture.context.spec, fixture.context.client);

/// The fields of the model [name] as `name: type` strings.
List<String> fields(ClientIr ir, String name) => [
  for (final f
      in (ir.declarations.firstWhere((d) => d.name == name) as ModelDecl)
          .fields)
    '${f.name}: ${f.type.code(ir.nameOf)}',
];

/// The declarations of [ir] as `name/variant/direction` strings.
List<String> models(ClientIr ir) => [
  for (final d in ir.declarations)
    '${d.name}/${d.id.variant.name}'
        '${d is ModelDecl ? '/${d.direction.name}' : ''}',
];

/// The type of the body of the operation [name] of [ir].
String? bodyOf(ClientIr ir, String name) => [
  for (final group in ir.groups)
    for (final operation in group.operations)
      if (operation.name == name) operation.body?.type?.code(ir.nameOf),
].single;

void main() {
  group('a wrapped PATCH body (T7 I1)', () {
    const spec = r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets:
    get:
      tags: [t]
      operationId: listPets
      responses: {"200": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/Pet'}}}}}
    post:
      tags: [t]
      operationId: createPet
      requestBody: {content: {application/json: {schema: {$ref: '#/components/schemas/Pet'}}}}
      responses: {"204": {description: ok}}
  /pets/{id}:
    parameters: [{name: id, in: path, required: true, schema: {type: string}}]
    patch:
      tags: [t]
      operationId: patchPlain
      requestBody: {content: {application/json: {schema: {$ref: '#/components/schemas/Pet'}}}}
      responses: {"204": {description: ok}}
    put:
      tags: [t]
      operationId: replacePet
      requestBody: {content: {application/json: {schema: {allOf: [{$ref: '#/components/schemas/Pet'}]}}}}
      responses: {"204": {description: ok}}
  /pets/{id}/a:
    parameters: [{name: id, in: path, required: true, schema: {type: string}}]
    patch:
      tags: [t]
      operationId: patchAllOf
      requestBody: {content: {application/json: {schema: {allOf: [{$ref: '#/components/schemas/Pet'}]}}}}
      responses: {"204": {description: ok}}
  /pets/{id}/b:
    parameters: [{name: id, in: path, required: true, schema: {type: string}}]
    patch:
      tags: [t]
      operationId: patchNullable
      requestBody: {content: {application/json: {schema: {anyOf: [{$ref: '#/components/schemas/Pet'}, {type: 'null'}]}}}}
      responses: {"204": {description: ok}}
components:
  schemas:
    Pet:
      type: object
      properties:
        id: {type: integer, readOnly: true}
        name: {type: string}
        tag: {type: [string, "null"]}
''';

    test(r'is the model of the schema it wraps, like a bare $ref', () {
      final fixture = IrFixture(spec);
      final ir = build(fixture);
      expect(fixture.reported, isEmpty);
      expect(models(ir), [
        'Pet/base/response',
        'PetInput/input/request',
        'PetPatch/patch/request',
      ]);
      expect(fields(ir, 'PetInput'), ['name: String?', 'tag: String?']);
      expect(fields(ir, 'PetPatch'), ['name: String?', 'tag: Patch<String>?']);
      expect(bodyOf(ir, 'patchPlain'), 'PetPatch');
      expect(bodyOf(ir, 'patchAllOf'), 'PetPatch');
      expect(bodyOf(ir, 'patchNullable'), 'PetPatch?');
      expect(bodyOf(ir, 'createPet'), 'PetInput');
      expect(bodyOf(ir, 'replacePet'), 'PetInput');
    });
  });

  group('a schema used only as a PATCH body (T7 I2)', () {
    test('is a request model: readOnly is dropped, writeOnly kept', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets/{id}:
    parameters: [{name: id, in: path, required: true, schema: {type: string}}]
    patch:
      tags: [t]
      operationId: patchPet
      requestBody: {content: {application/json: {schema: {$ref: '#/components/schemas/Pet'}}}}
      responses: {"204": {description: ok}}
  /owners/{id}:
    parameters: [{name: id, in: path, required: true, schema: {type: string}}]
    patch:
      tags: [t]
      operationId: patchOwner
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                id: {type: integer, readOnly: true}
                password: {type: string, writeOnly: true}
                nick: {type: [string, "null"]}
      responses: {"204": {description: ok}}
components:
  schemas:
    Pet:
      type: object
      properties:
        id: {type: integer, readOnly: true}
        password: {type: string, writeOnly: true}
        name: {type: [string, "null"]}
''');
      final ir = build(fixture);
      expect(fixture.reported, isEmpty);
      expect(models(ir), [
        'PatchOwnerRequest/base/request',
        'Pet/base/request',
      ]);
      expect(fields(ir, 'Pet'), ['password: String?', 'name: Patch<String>?']);
      expect(fields(ir, 'PatchOwnerRequest'), [
        'password: String?',
        'nick: Patch<String>?',
      ]);
    });
  });

  test(
    'an inline type of a split model has no second variant suffix (T7 m1)',
    () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets:
    get:
      tags: [t]
      operationId: listPets
      responses: {"200": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/Pet'}}}}}
    post:
      tags: [t]
      operationId: createPet
      requestBody: {content: {application/json: {schema: {$ref: '#/components/schemas/Pet'}}}}
      responses: {"204": {description: ok}}
components:
  schemas:
    Pet:
      type: object
      properties:
        id: {type: integer, readOnly: true}
        address:
          type: object
          properties:
            zip: {type: string, readOnly: true}
            street: {type: string}
''');
      final ir = build(fixture);
      expect(fixture.reported, isEmpty);
      expect(ir.declarations.map((d) => d.name), [
        'Pet',
        'PetAddress',
        'PetInput',
        'PetInputAddress',
      ]);
      expect(fields(ir, 'PetInput'), ['address: PetInputAddress?']);
      expect(fields(ir, 'Pet'), ['id: int?', 'address: PetAddress?']);
    },
  );

  group('tri-state applies to request models only (T7 m3)', () {
    const spec = r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets:
    get:
      tags: [t]
      operationId: listPets
      responses: {"200": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/Pet'}}}}}
    post:
      tags: [t]
      operationId: createOwner
      requestBody: {content: {application/json: {schema: {$ref: '#/components/schemas/Owner'}}}}
      responses: {"204": {description: ok}}
components:
  schemas:
    Pet:
      type: object
      properties:
        tag: {type: [string, "null"], x-typed-tri-state: true}
        nick: {type: [string, "null"]}
    Owner:
      type: object
      properties:
        tag: {type: [string, "null"], x-typed-tri-state: true}
''';

    test('the extension marker on a response-only model is a plain T?', () {
      final fixture = IrFixture(
        spec,
        generation: const GenerationConfig(triState: TriStateRule.extension),
      );
      final ir = build(fixture);
      expect(fields(ir, 'Pet'), ['tag: String?', 'nick: String?']);
      expect(fields(ir, 'Owner'), ['tag: Patch<String>?']);
      expect(fixture.reported, isEmpty);
    });

    test('an override triState on a response-only model has no effect', () {
      final fixture = IrFixture(
        spec,
        overrides: '''
schemas:
  Pet:
    properties:
      nick: {triState: true}
  Owner:
    properties:
      tag: {triState: false}
''',
      );
      final ir = build(fixture);
      expect(fields(ir, 'Pet'), ['tag: String?', 'nick: String?']);
      expect(fields(ir, 'Owner'), ['tag: String?']);
      expect(
        [
          for (final d in fixture.reported) (d.code, d.file, d.pointer?.value),
        ],
        [
          (
            DiagnosticCode.overrideUnchanged,
            'o.yaml',
            '#/schemas/Pet/properties/nick/triState',
          ),
        ],
      );
    });
  });

  group('an exclude on the only readOnly property (T7 m4)', () {
    const spec = r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets:
    get:
      tags: [t]
      operationId: listPets
      responses: {"200": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/Pet'}}}}}
    post:
      tags: [t]
      operationId: createPet
      requestBody: {content: {application/json: {schema: {$ref: '#/components/schemas/Pet'}}}}
      responses: {"204": {description: ok}}
components:
  schemas:
    Pet:
      type: object
      properties:
        id: {type: integer, readOnly: true}
        name: {type: string}
''';

    test('is split without the exclude', () {
      expect(models(build(IrFixture(spec))), [
        'Pet/base/response',
        'PetInput/input/request',
      ]);
    });

    test('does not split the schema', () {
      final fixture = IrFixture(
        spec,
        overrides: '''
schemas:
  Pet:
    properties:
      id: {exclude: true}
''',
      );
      final ir = build(fixture);
      expect(models(ir), ['Pet/base/both']);
      expect(fields(ir, 'Pet'), ['name: String?']);
      expect(fixture.reported, isEmpty);
    });
  });
}
