import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/ir/dart_type.dart';
import 'package:typed_openapi/src/ir/ir.dart';
import 'package:typed_openapi/src/ir/ir_builder.dart';

import '../helpers/ir_fixture.dart';

ClientIr build(IrFixture fixture) => IrBuilder(
  fixture.diagnostics,
).build(fixture.context.spec, fixture.context.client);

List<Diagnostic> reported(IrFixture fixture, DiagnosticCode code) => [
  for (final d in fixture.reported)
    if (d.code == code) d,
];

OperationIr operation(ClientIr ir, String name) => [
  for (final group in ir.groups)
    for (final operation in group.operations)
      if (operation.name == name) operation,
].single;

void main() {
  group('security metadata (R10.8)', () {
    const spec = '''
openapi: 3.1.0
info: {title: t, version: "1"}
security: [{bearer: []}]
paths:
  /inherit:
    get:
      operationId: inherit
      tags: [t]
      responses: {"200": {description: ok}}
  /own:
    get:
      operationId: own
      tags: [t]
      security: [{oauth: [read, write], key: []}, {}]
      responses: {"200": {description: ok}}
  /none:
    get:
      operationId: none
      tags: [t]
      security: []
      responses: {"200": {description: ok}}
  /unknown:
    get:
      operationId: unknown
      tags: [t]
      security: [{nope: []}]
      responses: {"200": {description: ok}}
components:
  securitySchemes:
    bearer: {type: http, scheme: Bearer, bearerFormat: JWT}
    key: {type: apiKey, name: X-Key, in: header}
    oauth:
      type: oauth2
      flows: {clientCredentials: {tokenUrl: https://a.example/token, scopes: {}}}
''';

    List<List<String>> uses(ClientIr ir, String name) => [
      for (final alternative in operation(ir, name).security)
        [
          for (final use in alternative)
            '${use.scheme.name}:${use.scheme.kind.name}:'
                '${use.scopes.join(',')}',
        ],
    ];

    test('an operation has its own requirements or the document\'s', () {
      final fixture = IrFixture(spec);
      final ir = build(fixture);
      expect(uses(ir, 'inherit'), [
        ['bearer:http:'],
      ]);
      expect(uses(ir, 'own'), [
        ['oauth:oauth2:read,write', 'key:apiKey:'],
        <String>[],
      ]);
      expect(uses(ir, 'none'), isEmpty);
      final bearer = operation(ir, 'inherit').security.single.single.scheme;
      expect((bearer.scheme, bearer.bearerFormat), ('bearer', 'JWT'));
      final key = operation(ir, 'own').security.first.last.scheme;
      expect((key.parameterName, key.placement), ('X-Key', 'header'));
      final unknown = reported(fixture, .securitySchemeUnknown).single;
      expect(unknown.pointer?.value, '#/paths/~1unknown/get/security/0');
      expect(uses(ir, 'unknown'), [
        ['nope:unknown:'],
      ]);
      expect(fixture.reported, hasLength(1));
    });
  });

  group('what the client does not generate', () {
    test('servers of a path item or an operation are reported (TOA566)', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    servers: [{url: https://a.example.com}]
    get:
      operationId: a
      tags: [t]
      servers: [{url: https://b.example.com}]
      responses: {"200": {description: ok}}
    post:
      operationId: b
      tags: [t]
      responses: {"200": {description: ok}}
''');
      build(fixture);
      expect(
        reported(
          fixture,
          .operationServersIgnored,
        ).map((d) => d.pointer?.value),
        ['#/paths/~1a/servers', '#/paths/~1a/get/servers'],
      );
    });

    test('callbacks and webhooks are reported (TOA567)', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    post:
      operationId: subscribe
      tags: [t]
      callbacks:
        onEvent:
          '{$request.body#/url}':
            post: {responses: {"200": {description: ok}}}
      responses: {"200": {description: ok}}
webhooks:
  newPet:
    post: {responses: {"200": {description: ok}}}
''');
      build(fixture);
      final found = reported(fixture, .callbacksNotGenerated);
      expect(found.map((d) => d.pointer?.value), [
        '#/paths/~1a/post/callbacks',
        '#/webhooks',
      ]);
      expect(found.first.message, contains('onEvent'));
      expect(found.last.message, contains('newPet'));
      expect(found.first.severity, Severity.info);
    });

    test('an operation without a 2xx response is reported (TOA653)', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: a
      tags: [t]
      responses:
        default: {description: any, content: {application/json: {schema: {type: object, properties: {a: {type: string}}}}}}
''');
      final ir = build(fixture);
      expect(operation(ir, 'a').successes, isEmpty);
      expect(
        reported(fixture, .successUndocumented).single.pointer?.value,
        '#/paths/~1a/get/responses',
      );
    });

    test('an event stream next to another body is not generated (TOA654)', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: watch
      tags: [t]
      responses:
        "200": {description: ok, content: {text/event-stream: {schema: {type: string}}}}
        "201": {description: ok, content: {application/json: {schema: {type: string}}}}
''');
      final ir = build(fixture);
      expect(ir.groups, isEmpty);
      expect(
        reported(fixture, .eventStreamNotGenerated).single.pointer?.value,
        '#/paths/~1a/get/responses',
      );
      expect(
        reported(fixture, .clientEmpty).single.message,
        contains('1 has event streams the client cannot express (TOA654)'),
      );
    });
  });

  group('multipart parts', () {
    test('the properties of an object are the parts; files are binary', () {
      final fixture = IrFixture(r'''
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
            schema: {$ref: '#/components/schemas/Upload'}
            encoding: {file: {contentType: image/png}}
      responses: {"204": {description: ok}}
components:
  schemas:
    Upload:
      type: object
      required: [file]
      properties:
        file: {type: string, format: binary, description: The image.}
        files: {type: array, items: {type: string, format: binary}}
        class: {type: string}
        toParts: {type: integer}
        id: {type: string, readOnly: true}
        meta: {type: object, properties: {a: {type: string}}}
''');
      final ir = build(fixture);
      // The parts named like a reserved word or a member are renamed, and
      // reported as an argument would be (TOA550).
      expect(
        [for (final d in fixture.reported) (d.code, d.pointer?.value)],
        [
          (
            DiagnosticCode.nameReserved,
            '#/components/schemas/Upload/properties/class',
          ),
          (
            DiagnosticCode.nameReserved,
            '#/components/schemas/Upload/properties/toParts',
          ),
        ],
      );
      final upload = operation(ir, 'upload');
      expect(upload.partsName, 'UploadRequest');
      expect(upload.body?.type, isNull);
      expect(
        [
          for (final p in upload.body!.parts!)
            (
              p.name,
              p.wireName,
              p.type.code(ir.nameOf),
              p.required,
              p.contentType,
            ),
        ],
        [
          ('file', 'file', 'Uint8List', true, 'image/png'),
          ('files', 'files', 'List<Uint8List>?', false, null),
          ('class_', 'class', 'String?', false, null),
          ('toParts_', 'toParts', 'int?', false, null),
          ('meta', 'meta', 'UploadRequestMeta?', false, null),
        ],
      );
      expect(upload.body!.parts!.first.description, 'The image.');
      // The schema itself is not a model: its parts are.
      expect([for (final d in ir.declarations) d.name], ['UploadRequestMeta']);
    });

    test('another schema has no parts (TOA655)', () {
      final fixture = IrFixture(r'''
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
              oneOf: [{$ref: '#/components/schemas/A'}, {type: string}]
      responses: {"204": {description: ok}}
components:
  schemas:
    A: {type: object, properties: {a: {type: string}}}
''');
      final ir = build(fixture);
      final upload = operation(ir, 'upload');
      expect(upload.body?.parts, isNull);
      expect(upload.partsName, isNull);
      expect(upload.body?.type, isA<NamedType>());
      expect(
        reported(fixture, .multipartNotObject).single.pointer?.value,
        '#/paths/~1a/post/requestBody/content/multipart~1form-data/schema',
      );
    });
  });
}
