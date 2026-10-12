import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';

import '../helpers/override_run.dart';

const _header30 = OverrideRun.header30;
const _header31 = OverrideRun.header31;

void main() {
  test('sets schema, property, parameter and body fields (3.0)', () {
    final run = OverrideRun(
      '''
$_header30
paths:
  /files/{id}:
    post:
      operationId: upload
      parameters:
        - {name: id, in: path, required: true, schema: {type: string}}
        - {name: tag, in: query, schema: {type: string}}
      requestBody:
        content:
          '*/*': {schema: {type: object, format: binary}}
      responses:
        '200':
          description: ok
          content:
            application/json: {schema: {type: object}}
components:
  schemas:
    Pet:
      type: object
      required: [id]
      properties:
        id: {type: string, format: uuid}
        tags: {type: array, format: uuid}
        name: {type: string}
''',
      r'''
operations:
  upload:
    parameters:
      id: {schema: {type: integer}}
      tag: {required: true}
    requestBody:
      contentType: application/octet-stream
      schema: {type: string, format: binary}
    responses:
      '200': {schema: {$ref: '#/components/schemas/Pet'}}
schemas:
  Pet:
    discriminator: {propertyName: kind}
    additionalProperties: false
    properties:
      id: {format: null, nullable: true}
      tags: {format: null, items: {type: string, format: uuid}}
      name: {required: true, enum: [a, b]}
''',
    );
    expect(run.overrideDiagnostics, isEmpty);
    expect(run.codes, isNot(contains(DiagnosticCode.wildcardMediaType)));
    expect(run.codes, isNot(contains(DiagnosticCode.binaryObject)));
    expect(run.codes, isNot(contains(DiagnosticCode.formatOnArray)));
    const op = '#/paths/~1files~1{id}/post';
    expect(run.at('$op/parameters/0/schema'), {'type': 'integer'});
    expect(run.at('$op/parameters/1/required'), isTrue);
    expect(run.at('$op/requestBody/content'), {
      'application/octet-stream': {
        'schema': {'type': 'string', 'format': 'binary'},
      },
    });
    expect(run.at('$op/responses/200/content/application~1json/schema'), {
      r'$ref': '#/components/schemas/Pet',
    });
    expect(run.at('#/components/schemas/Pet'), {
      'type': 'object',
      'required': ['id', 'name'],
      'properties': {
        'id': {'type': 'string', 'nullable': true},
        'tags': {
          'type': 'array',
          'items': {'type': 'string', 'format': 'uuid'},
        },
        'name': {
          'type': 'string',
          'enum': ['a', 'b'],
        },
      },
      'discriminator': {'propertyName': 'kind'},
      'additionalProperties': false,
    });
    expect(run.result.overrides?.schemas.single.key, 'Pet');
  });

  test(r'"$ref" and nullable references follow the dialect', () {
    const spec = r'''
components:
  schemas:
    Status: {type: string, enum: [a, b]}
    Owner: {type: object}
    Pet:
      type: object
      properties:
        owner: {$ref: '#/components/schemas/Owner'}
        status:
          oneOf:
            - {enum: [null]}
            - {$ref: '#/components/schemas/Status'}
''';
    const overrides = r'''
schemas:
  Pet:
    properties:
      owner: {nullable: true}
      status: {$ref: '#/components/schemas/Status', nullable: true}
''';
    final v30 = OverrideRun('$_header30$spec', overrides);
    expect(v30.overrideDiagnostics, isEmpty);
    expect(v30.codes, isNot(contains(DiagnosticCode.nullableEnumOneOf)));
    expect(v30.at('#/components/schemas/Pet/properties/owner'), {
      'allOf': [
        {r'$ref': '#/components/schemas/Owner'},
      ],
      'nullable': true,
    });
    final v31 = OverrideRun('$_header31$spec', overrides);
    expect(v31.overrideDiagnostics, isEmpty);
    expect(v31.at('#/components/schemas/Pet/properties/status'), {
      'anyOf': [
        {r'$ref': '#/components/schemas/Status'},
        {'type': 'null'},
      ],
    });
  });

  test('a field the spec already has is reported as removable', () {
    final run = OverrideRun(
      '''
$_header30
paths:
  /pets:
    get:
      operationId: listPets
      parameters:
        - {name: limit, in: query, required: true, schema: {type: integer}}
      responses:
        '200':
          description: ok
          content:
            application/json: {schema: {type: array}}
components:
  schemas:
    Pet:
      type: object
      nullable: true
      required: [id]
      properties:
        id: {type: string}
        name: {type: string}
''',
      '''
operations:
  listPets:
    parameters:
      limit: {required: true, schema: {type: integer}}
    responses:
      '200': {contentType: application/json, schema: {type: array}}
schemas:
  Pet:
    reason: the backend sends null
    type: object
    nullable: true
    format: null
    properties:
      id: {required: true}
      name: {required: false, type: integer}
''',
    );
    expect(run.overrideDiagnostics, [
      for (final p in [
        '#/operations/listPets/parameters/limit/required',
        '#/operations/listPets/parameters/limit/schema',
        '#/operations/listPets/responses/200/contentType',
        '#/operations/listPets/responses/200/schema',
        '#/schemas/Pet/type',
        '#/schemas/Pet/nullable',
        '#/schemas/Pet/format',
        '#/schemas/Pet/properties/id/required',
        '#/schemas/Pet/properties/name/required',
      ])
        (DiagnosticCode.overrideUnchanged, p),
    ]);
    final type = run.bag.sorted.firstWhere(
      (d) => d.pointer?.value == '#/schemas/Pet/type',
    );
    expect(
      type.message,
      'The spec already has this "type"; the override changes nothing and '
      'can be removed. Reason given: "the backend sends null".',
    );
    expect(type.line, 10);
    expect(run.at('#/components/schemas/Pet/properties/name/type'), 'integer');
  });

  test('generation fields change nothing in the spec', () {
    final run = OverrideRun(
      '''
$_header30
paths:
  /pets:
    get:
      operationId: listPets
      responses: {'200': {description: ok}}
components:
  schemas:
    Pet: {type: object, properties: {id: {type: string}}}
''',
      '''
operations:
  listPets: {name: pets, group: zoo, exclude: false}
schemas:
  Pet:
    exhaustive: false
    name: Animal
    properties:
      id: {name: petId, triState: true}
''',
    );
    expect(run.bag.all, isEmpty);
    expect(run.at('#/components/schemas/Pet'), {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
      },
    });
    expect(run.result.overrides?.operations.single.group, 'zoo');
  });

  group(r'fields next to "$ref"', () {
    const spec = r'''
components:
  schemas:
    Status: {type: string}
    Pet:
      type: object
      properties:
        status: {$ref: '#/components/schemas/Status'}
''';
    const overrides = '''
schemas:
  Pet:
    properties:
      status: {enum: [a, b], format: x}
''';

    test('are not written in 3.0, where they are ignored', () {
      final run = OverrideRun('$_header30$spec', overrides);
      expect(run.overrideDiagnostics, [
        (DiagnosticCode.fixNotApplied, '#/schemas/Pet/properties/status/enum'),
        (
          DiagnosticCode.fixNotApplied,
          '#/schemas/Pet/properties/status/format',
        ),
      ]);
      expect(
        run.bag.sorted.first.message,
        'This override was not applied: in OpenAPI 3.0 the siblings of '
        r'"$ref" are ignored, so "enum" would have no effect on a schema '
        'that is a reference.',
      );
      expect(run.bag.sorted.first.severity, Severity.warning);
      expect(run.at('#/components/schemas/Pet/properties/status'), {
        r'$ref': '#/components/schemas/Status',
      });
    });

    test('are written from 3.1, where they are valid', () {
      final run = OverrideRun('$_header31$spec', overrides);
      expect(run.overrideDiagnostics, isEmpty);
      expect(run.at('#/components/schemas/Pet/properties/status'), {
        r'$ref': '#/components/schemas/Status',
        'format': 'x',
        'enum': ['a', 'b'],
      });
    });
  });

  group(r'a "$ref" that is not a string', () {
    for (final (version, header) in [('3.0', _header30), ('3.1', _header31)]) {
      for (final ref in ['5', 'null']) {
        for (final nullable in [true, false]) {
          test(
            'is no reference: $version, \$ref: $ref, nullable: $nullable',
            () {
              final run = OverrideRun(
                '''
$header
components:
  schemas:
    Pet:
      type: object
      properties:
        owner: {\$ref: $ref}
''',
                'schemas: {Pet: {properties: {owner: {nullable: $nullable}}}}\n',
              );
              const pointer = '#/schemas/Pet/properties/owner/nullable';
              expect(run.overrideDiagnostics, [
                if (version == '3.1' && nullable)
                  (DiagnosticCode.invalidOverride, pointer)
                else if (!nullable)
                  (DiagnosticCode.overrideUnchanged, pointer),
              ]);
            },
          );
        }
      }
    }
  });

  test(r'"type" is not written next to a "$ref" in 3.0', () {
    final run = OverrideRun(
      '''
$_header30
components:
  schemas:
    Status: {type: string}
    Pet:
      type: object
      properties:
        status: {\$ref: '#/components/schemas/Status'}
''',
      'schemas: {Pet: {properties: {status: {type: integer}}}}\n',
    );
    expect(run.overrideDiagnostics, [
      (DiagnosticCode.fixNotApplied, '#/schemas/Pet/properties/status/type'),
    ]);
    expect(run.at('#/components/schemas/Pet/properties/status'), {
      r'$ref': '#/components/schemas/Status',
    });
  });
}
