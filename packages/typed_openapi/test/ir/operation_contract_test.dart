import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/ir/dart_type.dart';
import 'package:typed_openapi/src/ir/ir.dart';
import 'package:typed_openapi/src/ir/ir_builder.dart';
import 'package:typed_openapi/src/ir/operation_builder.dart';
import 'package:typed_openapi/src/model/operation.dart';
import 'package:typed_openapi_runtime/typed_openapi_runtime.dart'
    show OperationRequest;

import '../helpers/ir_fixture.dart';

ClientIr build(IrFixture fixture) => IrBuilder(
  fixture.diagnostics,
).build(fixture.context.spec, fixture.context.client);

List<Diagnostic> reported(IrFixture fixture, DiagnosticCode code) => [
  for (final d in fixture.reported)
    if (d.code == code) d,
];

OperationIr single(ClientIr ir) => ir.groups.single.operations.single;

void main() {
  test('the generator reads path variables as the runtime does', () {
    expect(
      OperationBuilder.pathVariable.pattern,
      OperationRequest.pathVariable.pattern,
    );
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /c/{}:
    get:
      operationId: empty
      tags: [t]
      responses: {"200": {description: ok}}
''');
    build(fixture);
    expect(
      reported(fixture, .pathVariableUnbound).single.message,
      contains('"{}"'),
    );
  });

  test('a parameter keeps the default of its schema', () {
    final ir = build(
      IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: list
      tags: [t]
      parameters:
        - {name: limit, in: query, schema: {type: integer, default: 20}}
        - {name: sort, in: query, schema: {$ref: '#/components/schemas/Sort'}}
        - {name: q, in: query, schema: {type: string}}
      responses: {"200": {description: ok}}
components:
  schemas:
    Sort: {type: string, enum: [asc, desc], default: asc}
'''),
    );
    expect(
      [for (final p in single(ir).parameters) p.defaultValue],
      [
        (20,),
        ('asc',),
        null,
      ],
    );
  });

  group('request bodies', () {
    test('a form body keeps the encoding of its properties', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    post:
      operationId: send
      tags: [t]
      requestBody:
        content:
          application/x-www-form-urlencoded:
            schema:
              type: object
              properties:
                tags: {type: array, items: {type: string}}
                meta: {type: object, additionalProperties: {type: string}}
                next: {type: string}
                bad: {type: string}
            encoding:
              tags: {style: form, explode: false}
              meta: {style: deepObject, explode: true}
              next: {allowReserved: true, contentType: application/json}
              bad: {style: matrix}
      responses: {"204": {description: ok}}
''');
      final body = single(build(fixture)).body!;
      expect(body.kind, BodyKind.form);
      expect(
        [
          for (final e in body.encoding)
            (e.property, e.style, e.explode, e.allowReserved, e.contentType),
        ],
        [
          ('bad', null, null, false, null),
          ('meta', ParameterStyle.deepObject, true, false, null),
          ('next', null, null, true, 'application/json'),
          ('tags', ParameterStyle.form, false, false, null),
        ],
      );
      final style = reported(fixture, .parameterStyleInvalid).single;
      expect(
        style.pointer?.value,
        '#/paths/~1a/post/requestBody/content/'
        'application~1x-www-form-urlencoded/encoding/bad/style',
      );
      expect(style.message, contains('"matrix"'));
      expect(fixture.reported, hasLength(1));
    });

    test('a multipart part keeps its media type; its headers are reported', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    post:
      operationId: upload
      tags: [t]
      requestBody:
        content:
          multipart/form-data:
            schema:
              type: object
              properties:
                file: {type: string, format: binary}
                meta: {type: object}
            encoding:
              file:
                contentType: image/png
                style: matrix
                headers:
                  X-Rate: {schema: {type: integer}}
              meta: {contentType: application/json}
      responses: {"204": {description: ok}}
''');
      final body = single(build(fixture)).body!;
      expect(body.kind, BodyKind.multipart);
      expect(
        [for (final e in body.encoding) (e.property, e.style, e.contentType)],
        [('file', null, 'image/png'), ('meta', null, 'application/json')],
      );
      final headers = reported(fixture, .encodingHeadersIgnored).single;
      expect(headers.severity, Severity.info);
      expect(
        headers.pointer?.value,
        '#/paths/~1a/post/requestBody/content/multipart~1form-data/'
        'encoding/file/headers',
      );
      // Styles are for forms only; a multipart body ignores them.
      expect(fixture.reported, hasLength(1));
    });

    test('a text body is a string, whatever its schema', () {
      final ir = build(
        IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    post:
      operationId: send
      tags: [t]
      requestBody:
        content:
          text/csv: {schema: {type: object, properties: {a: {type: string}}}}
      responses: {"204": {description: ok}}
'''),
      );
      expect(single(ir).body?.type, const CoreType(.string));
      expect(ir.declarations, isEmpty);
    });
  });

  test('a form or multipart response is read as bytes (TOA650)', () {
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: get
      tags: [t]
      responses:
        "200":
          description: ok
          content:
            multipart/form-data: {schema: {type: object, properties: {a: {type: string}}}}
''');
    final ir = build(fixture);
    final response = single(ir).responses.single;
    expect(response.kind, BodyKind.bytes);
    expect(response.type, const CoreType(.binary));
    expect(ir.declarations, isEmpty);
    expect(
      reported(fixture, .mediaTypeAsBytes).single.pointer?.value,
      '#/paths/~1a/get/responses/200/content/multipart~1form-data',
    );
  });

  group('names the API files import', () {
    test('a schema named like a dio export other than Dio keeps its name', () {
      final ir = build(
        IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: get
      tags: [t]
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema:
                type: object
                properties:
                  a: {$ref: '#/components/schemas/Response'}
                  b: {$ref: '#/components/schemas/Options'}
                  c: {$ref: '#/components/schemas/Headers'}
                  d: {$ref: '#/components/schemas/Dio'}
                  e: {$ref: '#/components/schemas/FileUpload'}
                  f: {$ref: '#/components/schemas/SecurityScheme'}
components:
  schemas:
    Response: {type: object, properties: {x: {type: string}}}
    Options: {type: object, properties: {x: {type: string}}}
    Headers: {type: object, properties: {x: {type: string}}}
    Dio: {type: object, properties: {x: {type: string}}}
    FileUpload: {type: object, properties: {x: {type: string}}}
    SecurityScheme: {type: object, properties: {x: {type: string}}}
'''),
      );
      expect(
        [for (final d in ir.declarations) d.name],
        containsAll([
          'Response',
          'Options',
          'Headers',
          'DioModel',
          'FileUploadModel',
          'SecuritySchemeModel',
        ]),
      );
    });
  });
}
