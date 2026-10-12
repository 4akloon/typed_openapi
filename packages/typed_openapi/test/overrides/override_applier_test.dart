import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/load/openapi_version.dart';
import 'package:typed_openapi/src/load/spec_document.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/normalize/normalizer.dart';
import 'package:typed_openapi/src/overrides/override_loader.dart';

import '../helpers/temp_dir.dart';

/// A spec normalized with overrides.
final class _Run {
  /// Normalizes [spec] (or the file at [path]) with [overrides].
  _Run(String spec, String overrides, {String? path}) {
    final SpecDocument document = path == null
        ? SpecLoader(bag).parse(spec, 'api.yaml')!
        : SpecLoader(bag).load(path, displayPath: 'api.yaml')!;
    final version = OpenApiVersionDetector(bag).detect(document)!;
    final set = OverrideLoader(bag).parse(overrides, 'o.yaml')!;
    result = Normalizer(bag).normalize(document, version, overrides: set);
  }

  final DiagnosticBag bag = DiagnosticBag();
  late final NormalizedSpec result;

  /// The value at [pointer] of the root document after normalizing.
  Object? at(String pointer) =>
      result.documents.root.valueAt(JsonPointer.parse(pointer))?.$1;

  /// The diagnostics about the overrides file.
  List<(DiagnosticCode, String?)> get overrideDiagnostics => [
    for (final d in bag.sorted)
      if (d.file == 'o.yaml') (d.code, d.pointer?.value),
  ];

  /// The codes of every diagnostic.
  List<DiagnosticCode> get codes => [for (final d in bag.sorted) d.code];
}

const _header30 = '''
openapi: 3.0.3
info: {title: t, version: '1'}
''';

const _header31 = '''
openapi: 3.1.0
info: {title: t, version: '1'}
''';

void main() {
  test('sets schema, property, parameter and body fields (3.0)', () {
    final run = _Run(
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

  test('nullable is "null" in type from 3.1; type keeps nullability', () {
    final run = _Run(
      '''
$_header31
components:
  schemas:
    A: {type: string}
    B: {type: [integer, 'null']}
    C: {type: [string, 'null']}
    D: {properties: {x: {type: string}}}
''',
      '''
schemas:
  A: {nullable: true}
  B: {type: number}
  C: {nullable: false}
  D: {nullable: true}
''',
    );
    expect(run.at('#/components/schemas/A/type'), ['string', 'null']);
    expect(run.at('#/components/schemas/B/type'), ['number', 'null']);
    expect(run.at('#/components/schemas/C/type'), 'string');
    expect(run.at('#/components/schemas/D'), {
      'properties': {
        'x': {'type': 'string'},
      },
    });
    expect(run.overrideDiagnostics, [
      (DiagnosticCode.invalidOverride, '#/schemas/D/nullable'),
    ]);
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
    final v30 = _Run('$_header30$spec', overrides);
    expect(v30.overrideDiagnostics, isEmpty);
    expect(v30.codes, isNot(contains(DiagnosticCode.nullableEnumOneOf)));
    expect(v30.at('#/components/schemas/Pet/properties/owner'), {
      'allOf': [
        {r'$ref': '#/components/schemas/Owner'},
      ],
      'nullable': true,
    });
    final v31 = _Run('$_header31$spec', overrides);
    expect(v31.overrideDiagnostics, isEmpty);
    expect(v31.at('#/components/schemas/Pet/properties/status'), {
      'anyOf': [
        {r'$ref': '#/components/schemas/Status'},
        {'type': 'null'},
      ],
    });
  });

  test('a field the spec already has is reported as removable', () {
    final run = _Run(
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

  test('two different changes of one node conflict; equal ones apply once', () {
    final run = _Run(
      '''
$_header30
paths:
  /pets/{id}:
    parameters:
      - {name: id, in: path, required: true, schema: {type: string}}
      - {name: v, in: query, schema: {type: string}}
    get:
      operationId: getPet
      responses: {'200': {description: ok}}
    delete:
      operationId: deletePet
      responses: {'204': {description: ok}}
components:
  schemas:
    Pet:
      type: object
      properties:
        a: {type: string}
        b: {type: string}
''',
      '''
operations:
  getPet:
    parameters:
      id: {schema: {type: integer}}
      v: {required: true}
  deletePet:
    parameters:
      id: {schema: {type: number}}
      v: {required: true}
schemas:
  Pet:
    required: [a]
    properties:
      b: {required: true}
''',
    );
    expect(run.overrideDiagnostics, [
      (
        DiagnosticCode.overrideSharedTarget,
        '#/operations/getPet/parameters/id',
      ),
      (
        DiagnosticCode.overrideConflict,
        '#/operations/getPet/parameters/id/schema',
      ),
      (DiagnosticCode.overrideSharedTarget, '#/operations/getPet/parameters/v'),
      (
        DiagnosticCode.overrideSharedTarget,
        '#/operations/deletePet/parameters/id',
      ),
      (
        DiagnosticCode.overrideConflict,
        '#/operations/deletePet/parameters/id/schema',
      ),
      (
        DiagnosticCode.overrideSharedTarget,
        '#/operations/deletePet/parameters/v',
      ),
      (DiagnosticCode.overrideConflict, '#/schemas/Pet/required'),
      (DiagnosticCode.overrideConflict, '#/schemas/Pet/properties/b/required'),
    ]);
    expect(run.at('#/paths/~1pets~1{id}/parameters/0/schema'), {
      'type': 'string',
    });
    expect(run.at('#/paths/~1pets~1{id}/parameters/1/required'), isTrue);
    expect(run.at('#/components/schemas/Pet/required'), isNull);
  });

  test('different fields of one shared parameter are both applied', () {
    final run = _Run(
      '''
$_header30
paths:
  /pets/{id}:
    parameters:
      - {name: v, in: query, schema: {type: string}}
    get:
      operationId: getPet
      responses: {'200': {description: ok}}
    delete:
      operationId: deletePet
      responses: {'204': {description: ok}}
''',
      '''
operations:
  getPet:
    parameters:
      v: {schema: {type: integer}}
  deletePet:
    parameters:
      v: {required: true}
''',
    );
    expect(run.overrideDiagnostics, [
      (DiagnosticCode.overrideSharedTarget, '#/operations/getPet/parameters/v'),
      (
        DiagnosticCode.overrideSharedTarget,
        '#/operations/deletePet/parameters/v',
      ),
    ]);
    expect(run.at('#/paths/~1pets~1{id}/parameters/0'), {
      'name': 'v',
      'in': 'query',
      'schema': {'type': 'integer'},
      'required': true,
    });
  });

  group('one response that two status codes share', () {
    const spec =
        '''
$_header30
paths:
  /a:
    get:
      operationId: a
      responses:
        '400': {\$ref: '#/components/responses/Bad'}
        '422': {\$ref: '#/components/responses/Bad'}
components:
  responses:
    Bad:
      description: bad
      content:
        application/json: {schema: {type: object}}
''';
    const sharedDiagnostics = [
      (DiagnosticCode.overrideSharedTarget, '#/operations/a/responses/400'),
      (DiagnosticCode.overrideSharedTarget, '#/operations/a/responses/422'),
    ];

    test('the same change from both is made once', () {
      final run = _Run(spec, '''
operations:
  a:
    responses:
      '400': {schema: {type: string}}
      '422': {schema: {type: string}}
''');
      expect(run.overrideDiagnostics, sharedDiagnostics);
      expect(run.at('#/components/responses/Bad/content'), {
        'application/json': {
          'schema': {'type': 'string'},
        },
      });
    });

    test('different values for one field are a conflict; none is made', () {
      final run = _Run(spec, '''
operations:
  a:
    responses:
      '400': {schema: {type: string}}
      '422': {schema: {type: integer}}
''');
      expect(run.overrideDiagnostics, [
        sharedDiagnostics[0],
        (
          DiagnosticCode.overrideConflict,
          '#/operations/a/responses/400/schema',
        ),
        sharedDiagnostics[1],
        (
          DiagnosticCode.overrideConflict,
          '#/operations/a/responses/422/schema',
        ),
      ]);
      expect(run.at('#/components/responses/Bad/content'), {
        'application/json': {
          'schema': {'type': 'object'},
        },
      });
    });
  });

  test('a body with several media types needs a contentType that names '
      'one', () {
    final run = _Run(
      '''
$_header30
paths:
  /a:
    post:
      operationId: a
      requestBody:
        content:
          application/json: {schema: {type: object}}
          application/xml: {schema: {type: object}}
      responses: {'200': {description: ok}}
  /b:
    post:
      operationId: b
      requestBody:
        content:
          application/json: {schema: {type: object}}
          application/xml: {schema: {type: object}}
      responses: {'200': {description: ok}}
  /c:
    post:
      operationId: c
      requestBody:
        content:
          application/json: {schema: {type: object}}
          application/xml: {schema: {type: object}}
      responses: {'200': {description: ok}}
''',
      '''
operations:
  a: {requestBody: {schema: {type: string}}}
  b: {requestBody: {contentType: text/plain}}
  c: {requestBody: {contentType: application/json}}
''',
    );
    expect(run.overrideDiagnostics, [
      (
        DiagnosticCode.overrideTargetAmbiguous,
        '#/operations/a/requestBody/schema',
      ),
      (
        DiagnosticCode.overrideTargetAmbiguous,
        '#/operations/b/requestBody/contentType',
      ),
    ]);
    expect(run.at('#/paths/~1c/post/requestBody/content'), {
      'application/json': {
        'schema': {'type': 'object'},
      },
    });
  });

  test('changes nodes defined in another file', () {
    final dir = TempDir();
    dir.write('pet.yaml', '''
Pet: {type: object}
Ok:
  description: ok
  content: {application/json: {schema: {type: object}}}
''');
    final path = dir.write('api.yaml', '''
$_header30
paths:
  /pets:
    get:
      operationId: listPets
      responses:
        '200': {\$ref: 'pet.yaml#/Ok'}
components:
  schemas:
    Pet: {\$ref: 'pet.yaml#/Pet'}
''');
    final run = _Run('', '''
operations:
  listPets:
    responses:
      '200': {schema: {type: array}}
schemas:
  Pet: {nullable: true}
''', path: path);
    // Addressed by schema name: no info; through an operation: an info that
    // names the shared node in its file.
    expect(run.overrideDiagnostics, [
      (
        DiagnosticCode.overrideSharedTarget,
        '#/operations/listPets/responses/200',
      ),
    ]);
    expect(
      run.bag.all.firstWhere((d) => d.file == 'o.yaml').message,
      'This override changes the shared node at pet.yaml#/Ok; the change '
      'applies to every operation that uses it.',
    );
    final pet = run.result.documents.loaded.last;
    expect(pet.valueAt(JsonPointer.parse('#/Pet'))?.$1, {
      'type': 'object',
      'nullable': true,
    });
  });

  test('generation fields change nothing in the spec', () {
    final run = _Run(
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

  test(
    '"type: null" on a nullable 3.1 schema removes the type and says so',
    () {
      final run = _Run(
        '''
$_header31
components:
  schemas:
    A: {type: [string, 'null'], description: d}
''',
        'schemas: {A: {type: null}}\n',
      );
      expect(run.overrideDiagnostics, [
        (DiagnosticCode.overrideNullabilityDropped, '#/schemas/A/type'),
      ]);
      expect(run.at('#/components/schemas/A'), {'description': 'd'});
    },
  );

  test('a 3.1 nullable reference is already nullable', () {
    const spec = r'''
components:
  schemas:
    Owner: {type: object}
    Pet:
      type: object
      properties:
        owner:
          anyOf:
            - {$ref: '#/components/schemas/Owner'}
            - {type: 'null'}
''';
    final same = _Run(
      '$_header31$spec',
      'schemas: {Pet: {properties: {owner: {nullable: true}}}}\n',
    );
    expect(same.overrideDiagnostics, [
      (
        DiagnosticCode.overrideUnchanged,
        '#/schemas/Pet/properties/owner/nullable',
      ),
    ]);
    final off = _Run(
      '$_header31$spec',
      'schemas: {Pet: {properties: {owner: {nullable: false}}}}\n',
    );
    expect(off.overrideDiagnostics, isEmpty);
    expect(off.at('#/components/schemas/Pet/properties/owner'), {
      r'$ref': '#/components/schemas/Owner',
    });
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
      final run = _Run('$_header30$spec', overrides);
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
      final run = _Run('$_header31$spec', overrides);
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
              final run = _Run(
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

  group('3.1 nullable through a "null" branch', () {
    const spec = r'''
components:
  schemas:
    Owner: {type: object}
    Pet:
      type: object
      properties:
        owner:
          anyOf: [{$ref: '#/components/schemas/Owner'}, {type: 'null'}]
          default: null
          title: Owner
        age:
          anyOf: [{type: integer}, {type: 'null'}]
          default: null
          title: Age
        nick:
          oneOf: [{type: string}, {type: 'null'}]
          description: d
        plain: {description: x}
''';

    test('"nullable: true" says the schema is already nullable', () {
      final run = _Run('$_header31$spec', '''
schemas:
  Pet:
    properties:
      owner: {nullable: true}
      age: {nullable: true}
      nick: {nullable: true}
''');
      expect(run.overrideDiagnostics, [
        for (final name in ['owner', 'age', 'nick'])
          (
            DiagnosticCode.overrideUnchanged,
            '#/schemas/Pet/properties/$name/nullable',
          ),
      ]);
    });

    test('"nullable: false" keeps the branch and the siblings', () {
      final run = _Run('$_header31$spec', '''
schemas:
  Pet:
    properties:
      owner: {nullable: false}
      age: {nullable: false}
      nick: {nullable: false}
      plain: {nullable: false}
''');
      expect(run.overrideDiagnostics, [
        (
          DiagnosticCode.overrideUnchanged,
          '#/schemas/Pet/properties/plain/nullable',
        ),
      ]);
      const props = '#/components/schemas/Pet/properties';
      expect(run.at('$props/owner'), {
        r'$ref': '#/components/schemas/Owner',
        'title': 'Owner',
      });
      expect(run.at('$props/age'), {'type': 'integer', 'title': 'Age'});
      expect(run.at('$props/nick'), {'type': 'string', 'description': 'd'});
    });

    test('a field that comes with "nullable" is not set beside the union', () {
      final run = _Run('$_header31$spec', '''
schemas:
  Pet:
    properties:
      age: {nullable: false, enum: [1]}
''');
      expect(run.overrideDiagnostics, [
        (DiagnosticCode.invalidOverride, '#/schemas/Pet/properties/age/enum'),
      ]);
    });
  });

  group(r'a "$ref" with siblings and a "nullable" override', () {
    const spec = r'''
components:
  schemas:
    Owner: {type: object}
    Pet:
      type: object
      properties:
        friend:
          $ref: '#/components/schemas/Owner'
          description: buddy
          readOnly: true
''';
    const nullable = '''
schemas: {Pet: {properties: {friend: {nullable: true}}}}
''';
    const friend = '#/components/schemas/Pet/properties/friend';

    test('keeps the siblings in 3.1', () {
      final run = _Run('$_header31$spec', nullable);
      expect(run.overrideDiagnostics, isEmpty);
      expect(run.at(friend), {
        'description': 'buddy',
        'readOnly': true,
        'anyOf': [
          {r'$ref': '#/components/schemas/Owner'},
          {'type': 'null'},
        ],
      });
    });

    test('keeps the siblings in 3.0', () {
      final run = _Run('$_header30$spec', nullable);
      expect(run.overrideDiagnostics, isEmpty);
      expect(run.at(friend), {
        'description': 'buddy',
        'readOnly': true,
        'allOf': [
          {r'$ref': '#/components/schemas/Owner'},
        ],
        'nullable': true,
      });
    });

    test('"nullable: false" on a plain reference changes nothing', () {
      for (final header in [_header30, _header31]) {
        final run = _Run(
          '$header$spec',
          'schemas: {Pet: {properties: {friend: {nullable: false}}}}\n',
        );
        expect(run.overrideDiagnostics, [
          (
            DiagnosticCode.overrideUnchanged,
            '#/schemas/Pet/properties/friend/nullable',
          ),
        ]);
        expect(run.at(friend), {
          r'$ref': '#/components/schemas/Owner',
          'description': 'buddy',
          'readOnly': true,
        });
      }
    });

    test(r'an explicit "$ref" replaces the whole node', () {
      final run = _Run('$_header31$spec', r'''
schemas: {Pet: {properties: {friend: {$ref: '#/components/schemas/Pet'}}}}
''');
      expect(run.overrideDiagnostics, isEmpty);
      expect(run.at(friend), {r'$ref': '#/components/schemas/Pet'});
    });

    test('the 3.0 nullable form with siblings is already nullable', () {
      final run = _Run(
        '''
$_header30
components:
  schemas:
    Owner: {type: object}
    Pet:
      type: object
      properties:
        friend:
          allOf: [{\$ref: '#/components/schemas/Owner'}]
          nullable: true
          description: buddy
''',
        '''
schemas: {Pet: {properties: {friend: {nullable: true}}}}
''',
      );
      expect(run.overrideDiagnostics, [
        (
          DiagnosticCode.overrideUnchanged,
          '#/schemas/Pet/properties/friend/nullable',
        ),
      ]);
      final off = _Run(
        '''
$_header30
components:
  schemas:
    Owner: {type: object}
    Pet:
      type: object
      properties:
        friend:
          allOf: [{\$ref: '#/components/schemas/Owner'}]
          nullable: true
          description: buddy
''',
        '''
schemas: {Pet: {properties: {friend: {nullable: false}}}}
''',
      );
      expect(off.overrideDiagnostics, isEmpty);
      expect(off.at(friend), {
        r'$ref': '#/components/schemas/Owner',
        'description': 'buddy',
      });
    });
  });

  test(r'"type" is not written next to a "$ref" in 3.0', () {
    final run = _Run(
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
