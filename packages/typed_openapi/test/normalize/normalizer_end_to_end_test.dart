import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/normalize/normalizer.dart';

import '../helpers/normalizer_fixture.dart';

void main() {
  const spec = r'''
openapi: 3.0.3
info: {title: Pet shop, version: "1"}
paths:
  /pets/{petId}:
    get:
      operationId: getPet
      parameters:
        - {name: limit, in: query, schema: {type: integer, default: many}}
      responses:
        "200":
          description: ok
          content:
            "*/*":
              schema: {$ref: '#/components/schemas/Pet'}
  /owners/{ownerId}:
    get:
      operationId: getPet
      responses: {}
    post:
      parameters:
        - {name: OwnerId, in: path, required: true, schema: {type: string}}
      responses: {}
components:
  schemas:
    Pet:
      type: object
      properties:
        name: {type: string, required: true}
        tags: {type: array, format: uuid}
        grid:
          type: array
          items: {type: array, items: {type: string}, required: true}
        photo: {type: object, format: binary}
        mood: {type: string, enum: [happy, sad, happy]}
        size: {type: integer, example: [1, 2]}
        owner:
          oneOf:
            - {type: string, enum: [null]}
            - {$ref: '#/components/schemas/Owner'}
        pocket: {type: array}
    Owner: {type: object, properties: {name: {type: string}}}
    Animal:
      oneOf:
        - {$ref: '#/components/schemas/Cat'}
        - {$ref: '#/components/schemas/Dog'}
      discriminator:
        propertyName: kind
        mapping: {cat: '#/components/schemas/Cat', ghost: Ghost}
    Cat:
      type: object
      required: [kind]
      properties: {kind: {type: string}}
    Dog:
      type: object
      properties: {kind: {type: string}}
    Mixed:
      type: object
      oneOf:
        - {type: string}
        - {type: integer}
    "Bad Name": {type: string}
''';

  test('every rule over one spec reports and fixes it in one go', () {
    final run = NormalizerFixture(spec);
    expect(Normalizer.rules, hasLength(18));
    expect(run.of(DiagnosticCode.fixNotApplied), isEmpty);
    expect(
      [for (final d in run.diagnostics.sorted) (d.code, d.pointer?.value)],
      [
        (DiagnosticCode.missingPathParameter, '#/paths/~1pets~1{petId}/get'),
        (
          DiagnosticCode.duplicateOperationId,
          '#/paths/~1pets~1{petId}/get/operationId',
        ),
        (
          DiagnosticCode.invalidDefault,
          '#/paths/~1pets~1{petId}/get/parameters/0/schema/default',
        ),
        (
          DiagnosticCode.wildcardMediaType,
          '#/paths/~1pets~1{petId}/get/responses/200/content/*~1*',
        ),
        (
          DiagnosticCode.missingPathParameter,
          '#/paths/~1owners~1{ownerId}/get',
        ),
        (
          DiagnosticCode.missingOperationId,
          '#/paths/~1owners~1{ownerId}/post',
        ),
        (
          DiagnosticCode.pathParameterNotInTemplate,
          '#/paths/~1owners~1{ownerId}/post/parameters/0',
        ),
        (
          DiagnosticCode.boolRequired,
          '#/components/schemas/Pet/properties/name/required',
        ),
        (
          DiagnosticCode.formatOnArray,
          '#/components/schemas/Pet/properties/tags/format',
        ),
        (
          DiagnosticCode.doubleArray,
          '#/components/schemas/Pet/properties/grid/items',
        ),
        (
          DiagnosticCode.invalidValue,
          '#/components/schemas/Pet/properties/grid/items/required',
        ),
        (
          DiagnosticCode.binaryObject,
          '#/components/schemas/Pet/properties/photo/type',
        ),
        (
          DiagnosticCode.duplicateEnumValue,
          '#/components/schemas/Pet/properties/mood/enum',
        ),
        (
          DiagnosticCode.exampleTypeMismatch,
          '#/components/schemas/Pet/properties/size/example',
        ),
        (
          DiagnosticCode.nullableEnumOneOf,
          '#/components/schemas/Pet/properties/owner/oneOf',
        ),
        (
          DiagnosticCode.arrayWithoutItems,
          '#/components/schemas/Pet/properties/pocket',
        ),
        (
          DiagnosticCode.discriminatorNotRequired,
          '#/components/schemas/Animal/discriminator',
        ),
        (
          DiagnosticCode.discriminatorMappingUnresolved,
          '#/components/schemas/Animal/discriminator/mapping/ghost',
        ),
        (
          DiagnosticCode.contradictoryObjectType,
          '#/components/schemas/Mixed/type',
        ),
        (
          DiagnosticCode.invalidComponentKey,
          '#/components/schemas/Bad Name',
        ),
      ],
    );
    final tree = run.result.documents.root.root;
    final paths = tree['paths']! as Map;
    final schemas = (tree['components']! as Map)['schemas']! as Map;
    final pet = schemas['Pet']! as Map;
    final properties = pet['properties']! as Map;
    // Both fixes on one parameter list: the added path parameter and the
    // removed default.
    expect(((paths['/pets/{petId}']! as Map)['get'] as Map)['parameters'], [
      {
        'name': 'limit',
        'in': 'query',
        'schema': {'type': 'integer'},
      },
      {
        'name': 'petId',
        'in': 'path',
        'required': true,
        'schema': {'type': 'string'},
      },
    ]);
    expect(
      ((paths['/owners/{ownerId}']! as Map)['get'] as Map)['parameters'],
      [
        {
          'name': 'ownerId',
          'in': 'path',
          'required': true,
          'schema': {'type': 'string'},
        },
      ],
    );
    expect(pet['required'], ['name']);
    expect(properties['name'], {'type': 'string'});
    expect((properties['mood']! as Map)['enum'], ['happy', 'sad']);
    // Diagnostic-only findings leave the tree as it was.
    expect(properties['photo'], {'type': 'object', 'format': 'binary'});
    expect(properties['pocket'], {'type': 'array'});
    expect((schemas['Mixed']! as Map)['type'], 'object');
  });
}
