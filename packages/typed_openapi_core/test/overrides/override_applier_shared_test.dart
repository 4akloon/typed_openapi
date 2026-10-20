import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

import '../helpers/override_run.dart';

const _header30 = OverrideRun.header30;

void main() {
  test('two different changes of one node conflict; equal ones apply once', () {
    final run = OverrideRun(
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
    final run = OverrideRun(
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
      final run = OverrideRun(spec, '''
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
      final run = OverrideRun(spec, '''
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
    final run = OverrideRun(
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
    final run = OverrideRun('', '''
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
}
