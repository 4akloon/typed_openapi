import 'package:test/test.dart';
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/ir/ir.dart';
import 'package:typed_openapi/src/ir/ir_builder.dart';

import '../helpers/ir_fixture.dart';

ClientIr build(IrFixture fixture) => IrBuilder(
  fixture.diagnostics,
).build(fixture.context.spec, fixture.context.client);

List<String> methods(ClientIr ir) => [
  for (final group in ir.groups)
    for (final operation in group.operations) '${group.name}.${operation.name}',
];

List<Diagnostic> reported(IrFixture fixture, DiagnosticCode code) => [
  for (final d in fixture.reported)
    if (d.code == code) d,
];

/// A spec with one operation per entry of [operations] (`path: operation
/// YAML`), all with an empty 200 response.
String specOf(Map<String, String> operations) {
  final buffer = StringBuffer('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
''');
  for (final MapEntry(:key, :value) in operations.entries) {
    buffer.writeln('  $key:\n    get:');
    for (final line in value.split('\n')) {
      buffer.writeln('      $line');
    }
    buffer.writeln('      responses: {"200": {description: ok}}');
  }
  return buffer.toString();
}

void main() {
  group('operation_prefix', () {
    final prefix = GenerationConfig(operationPrefix: RegExp('api_v1_'));

    test('is removed only from the start of the id', () {
      final ir = build(
        IrFixture(
          specOf({
            '/a': 'operationId: api_v1_list\ntags: [t]',
            '/b': 'operationId: users_api_v1_list\ntags: [t]',
          }),
          generation: prefix,
        ),
      );
      expect(methods(ir), ['TApi.list', 'TApi.usersApiV1List']);
    });

    test('is not applied when its match is empty', () {
      final ir = build(
        IrFixture(
          specOf({
            '/a': 'operationId: xxabc\ntags: [t]',
            '/b': 'operationId: abc\ntags: [t]',
          }),
          generation: GenerationConfig(operationPrefix: RegExp('x*')),
        ),
      );
      // `x*` matches `xx` at the start of the first id, and nothing at all
      // at the start of the second, which stays as it is.
      expect(methods(ir), ['TApi.abc', 'TApi.abc2']);
    });
  });

  group('names an override gives', () {
    test('a group, a method and an argument are validated (TOA560)', () {
      final fixture = IrFixture(
        '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: ov
      tags: [t]
      parameters: [{name: id, in: query, schema: {type: string}}]
      responses: {"200": {description: ok}}
  /b:
    get:
      operationId: ow
      tags: [t]
      responses: {"200": {description: ok}}
  /c:
    get:
      operationId: ox
      tags: [t]
      responses: {"200": {description: ok}}
''',
        overrides: '''
operations:
  ov:
    group: "###"
    name: "my method!"
    parameters:
      "query:id": {name: bad name}
  ow: {name: _hidden, group: pet store}
  ox: {name: "###"}
''',
      );
      final ir = build(fixture);
      expect(methods(ir), [
        'PetStoreApi.hidden',
        'TApi.myMethod',
        'TApi.ox',
      ]);
      expect(ir.groups.last.operations.first.parameters.single.name, 'badName');
      final found = reported(fixture, .overrideNameInvalid);
      expect(
        [for (final d in found) (d.file, d.pointer?.value)],
        unorderedEquals([
          ('o.yaml', '#/operations/ov/group'),
          ('o.yaml', '#/operations/ov/name'),
          ('o.yaml', '#/operations/ov/parameters/query:id/name'),
          ('o.yaml', '#/operations/ow/name'),
          ('o.yaml', '#/operations/ow/group'),
          ('o.yaml', '#/operations/ox/name'),
        ]),
      );
      expect(found.map((d) => d.severity).toSet(), {Severity.warning});
      expect(
        found.where((d) => d.message.contains('is ignored')),
        hasLength(2),
      );
    });

    test('valid names give no diagnostic', () {
      final fixture = IrFixture(
        specOf({
          '/a':
              'operationId: ov\ntags: [t]\nparameters: '
              '[{name: id, in: query, schema: {type: string}}]',
        }),
        overrides: '''
operations:
  ov:
    group: PetStore
    name: fetchAll
    parameters:
      "query:id": {name: petId}
''',
      );
      final ir = build(fixture);
      expect(methods(ir), ['PetStoreApi.fetchAll']);
      expect(
        ir.groups.single.operations.single.parameters.single.name,
        'petId',
      );
      expect(fixture.reported, isEmpty);
    });

    test('an override name is claimed before an automatic name', () {
      final fixture = IrFixture(
        specOf({
          '/a': 'operationId: getItem\ntags: [t]',
          '/b': 'operationId: other\ntags: [t]',
        }),
        overrides: '''
operations:
  other: {name: getItem}
''',
      );
      final ir = build(fixture);
      expect(methods(ir), ['TApi.getItem', 'TApi.getItem2']);
      final byPath = {
        for (final o in ir.groups.single.operations) o.path: o.name,
      };
      expect(byPath, {'/a': 'getItem2', '/b': 'getItem'});
      final collision = reported(fixture, .nameCollision).single;
      expect(collision.pointer?.value, '#/paths/~1a/get');
      expect(collision.fix, contains('name: getItem2'));
    });
  });

  group('lossy names (TOA559)', () {
    test('a group, a method and an argument that lost letters', () {
      final fixture = IrFixture(
        specOf({
          '/a':
              'operationId: Größe\ntags: [Über]\nparameters: '
              '[{name: größe, in: query, schema: {type: string}}]',
        }),
      );
      final ir = build(fixture);
      expect(methods(ir), ['BerApi.grE']);
      final found = reported(fixture, .nameLossy);
      expect(
        [for (final d in found) d.pointer?.value],
        [
          '#/paths/~1a/get/tags/0',
          '#/paths/~1a/get',
          '#/paths/~1a/get/parameters/0',
        ],
      );
      expect(found[1].fix, contains('name: grE'));
    });

    test('changes of case and separators are silent', () {
      final fixture = IrFixture(
        specOf({
          '/a':
              'operationId: get_the-ITEM\ntags: [pet store]\nparameters: '
              '[{name: X-Request-ID, in: header, schema: {type: string}}]',
        }),
      );
      build(fixture);
      expect(reported(fixture, .nameLossy), isEmpty);
    });
  });

  group('parameters', () {
    test('a name with no ASCII letter or digit is TOA552', () {
      final fixture = IrFixture(
        specOf({
          '/a':
              'operationId: a\ntags: [t]\nparameters: '
              r'[{name: "$", in: query, schema: {type: string}}, '
              '{name: "@", in: query, schema: {type: string}}]',
        }),
      );
      final ir = build(fixture);
      expect(
        [for (final p in ir.groups.single.operations.single.parameters) p.name],
        ['param', 'paramQuery'],
      );
      final found = reported(fixture, .nameUnrepresentable);
      expect(
        [for (final d in found) d.pointer?.value],
        [
          '#/paths/~1a/get/parameters/0',
          '#/paths/~1a/get/parameters/1',
        ],
      );
      expect(found.first.fix, contains(r'"query:$"'));
    });

    test('keep the document order within a location', () {
      final names = [for (var i = 0; i < 40; i++) 'p${'$i'.padLeft(2, '0')}'];
      final fixture = IrFixture(
        specOf({
          '/a':
              'operationId: a\ntags: [t]\nparameters: ['
              '${[for (final n in names) '{name: $n, in: query, schema: {type: string}}'].join(', ')}]',
        }),
      );
      final ir = build(fixture);
      expect(
        [for (final p in ir.groups.single.operations.single.parameters) p.name],
        names,
      );
    });
  });

  group('groups', () {
    test('TOA554 is decided on the operations that are generated', () {
      final fixture = IrFixture(
        specOf({
          '/a': 'operationId: a\ntags: [t]',
          '/b': 'operationId: b',
          '/c': 'operationId: c',
        }),
        generation: GenerationConfig(
          exclude: OperationFilter(
            tags: [FilterPattern('t', JsonPointer.root.child('x'))],
          ),
        ),
      );
      build(fixture);
      final found = reported(fixture, .operationUntagged);
      expect(found, hasLength(1));
      expect(found.single.pointer?.value, '#/paths');
    });

    test('TOA554 does not say the group of an override is the default', () {
      final spec = specOf({
        '/a': 'operationId: a',
        '/b': 'operationId: b',
        '/c': 'operationId: c',
      });
      final some = IrFixture(
        spec,
        overrides: '''
operations:
  a: {group: Other}
''',
      );
      expect(methods(build(some)), [
        'DefaultApi.b',
        'DefaultApi.c',
        'OtherApi.a',
      ]);
      final found = reported(some, .operationUntagged).single;
      expect(found.message, contains('without a group override'));
      final all = IrFixture(
        spec,
        overrides: '''
operations:
  a: {group: Other}
  b: {group: Other}
  c: {group: Other}
''',
      );
      build(all);
      expect(reported(all, .operationUntagged), isEmpty);
    });

    test('a group that collides with the default group says so', () {
      final fixture = IrFixture(
        specOf({
          '/a': 'operationId: a\ntags: [Default]',
          '/b': 'operationId: b',
        }),
      );
      final ir = build(fixture);
      expect(ir.groups.map((g) => g.name), ['DefaultApi', 'DefaultApi2']);
      final found = reported(fixture, .nameCollision).single;
      expect(found.message, contains('group'));
      expect(found.message, isNot(contains('schema')));
      expect(found.fix, contains('group'));
      expect(found.fix, isNot(contains('rename the schema')));
    });
  });

  group('media types (TOA561)', () {
    const xml = r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    post:
      operationId: send
      tags: [t]
      requestBody:
        content:
          application/xml: {schema: {$ref: '#/components/schemas/Doc'}}
      responses:
        "200":
          description: ok
          content:
            application/xml: {schema: {$ref: '#/components/schemas/Doc'}}
components:
  schemas:
    Doc: {type: object, properties: {id: {type: string}}}
''';

    test('a body that becomes bytes names its media type', () {
      final fixture = IrFixture(xml);
      final ir = build(fixture);
      final operation = ir.groups.single.operations.single;
      expect(operation.body?.kind, BodyKind.bytes);
      expect(operation.body?.type?.code(ir.nameOf), 'Uint8List');
      expect(operation.responses.single.type?.code(ir.nameOf), 'Uint8List');
      expect(ir.declarations, isEmpty);
      final found = reported(fixture, .mediaTypeAsBytes);
      expect(
        [for (final d in found) d.pointer?.value],
        unorderedEquals([
          '#/paths/~1a/post/requestBody/content/application~1xml',
          '#/paths/~1a/post/responses/200/content/application~1xml',
        ]),
      );
      expect(found.first.severity, Severity.info);
      expect(found.first.message, contains('application/xml'));
    });

    test('a file download is silent', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: download
      tags: [t]
      responses:
        "200":
          description: ok
          content:
            application/octet-stream: {schema: {type: string, format: binary}}
        "204": {description: none, content: {image/png: {}}}
''');
      build(fixture);
      expect(reported(fixture, .mediaTypeAsBytes), isEmpty);
    });

    test('other media types of an operation are reported as dropped', () {
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
          application/xml: {schema: {type: object}}
          application/x-www-form-urlencoded: {schema: {type: object}}
          application/json: {schema: {type: object}}
      responses:
        "200":
          description: ok
          content:
            application/json: {schema: {type: object}}
''');
      final ir = build(fixture);
      expect(
        ir.groups.single.operations.single.body?.contentType,
        'application/json',
      );
      final found = reported(fixture, .mediaTypeAsBytes);
      expect(
        found.single.pointer?.value,
        '#/paths/~1a/post/requestBody/content',
      );
      expect(found.single.message, contains('application/json'));
      expect(found.single.message, contains('application/xml'));
      expect(
        found.single.message,
        contains('application/x-www-form-urlencoded'),
      );
    });

    test('one JSON media type is silent', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    post:
      operationId: send
      tags: [t]
      requestBody: {content: {application/json: {schema: {type: object}}}}
      responses:
        "200": {description: ok, content: {application/json: {schema: {type: object}}}}
''');
      build(fixture);
      expect(reported(fixture, .mediaTypeAsBytes), isEmpty);
    });
  });

  group('errors.default_schema', () {
    GenerationConfig config(String key) => GenerationConfig(
      file: 'typed_openapi.yaml',
      defaultErrorSchema: key,
      defaultErrorSchemaPointer: JsonPointer.root
          .child('defaults')
          .child('errors')
          .child('default_schema'),
    );

    test('a key that is not in components.schemas is TOA562, ignored', () {
      final fixture = IrFixture(
        '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: a
      tags: [t]
      responses:
        "200": {description: ok}
        "500": {description: down}
components:
  schemas:
    Err: {type: object, properties: {message: {type: string}}}
''',
        generation: config('Nope'),
      );
      final ir = build(fixture);
      final found = reported(fixture, .defaultErrorSchemaMissing).single;
      expect(found.severity, Severity.warning);
      expect(found.file, 'typed_openapi.yaml');
      expect(found.pointer?.value, '#/defaults/errors/default_schema');
      expect(found.message, contains('Nope'));
      expect(
        ir.groups.single.operations.single.errors,
        isA<ErrorsByStatus>().having((e) => e.cases, 'cases', [('500', null)]),
      );
      expect(ir.declarations, isEmpty);
    });

    test('a key that exists is silent', () {
      final fixture = IrFixture(
        '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: a
      tags: [t]
      responses:
        "500": {description: down}
components:
  schemas:
    Err: {type: object, properties: {message: {type: string}}}
''',
        generation: config('Err'),
      );
      build(fixture);
      expect(reported(fixture, .defaultErrorSchemaMissing), isEmpty);
    });
  });

  group('an empty client (TOA563)', () {
    final client = JsonPointer.root.child('clients').child('api');

    GenerationConfig filtered(OperationFilter exclude) => GenerationConfig(
      file: 'typed_openapi.yaml',
      client: client,
      exclude: exclude,
    );

    test('everything filtered out is reported at the client', () {
      final fixture = IrFixture(
        specOf({'/a': 'operationId: a\ntags: [t]'}),
        generation: filtered(
          OperationFilter(paths: [FilterPattern('/**', client.child('x'))]),
        ),
      );
      final ir = build(fixture);
      expect(ir.groups, isEmpty);
      final found = reported(fixture, .clientEmpty).single;
      expect(found.severity, Severity.warning);
      expect(found.file, 'typed_openapi.yaml');
      expect(found.pointer?.value, '#/clients/api');
      expect(found.message, contains('filters'));
    });

    test(r'every operation a $ref is reported at the paths', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get: {$ref: '#/components/pathItems/Other'}
''');
      build(fixture);
      final found = reported(fixture, .clientEmpty).single;
      expect(found.pointer?.value, '#/paths');
      expect(found.message, contains(r'$ref'));
    });

    test('every operation with an unbound path variable', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets/{ID}:
    get:
      operationId: getPet
      parameters: [{name: id, in: path, required: true, schema: {type: string}}]
      responses: {"200": {description: ok}}
''');
      build(fixture);
      final found = reported(fixture, .clientEmpty).single;
      expect(found.pointer?.value, '#/paths');
      expect(found.message, contains('TOA556'));
    });

    test('a spec without operations is silent, and so is one that builds', () {
      final empty = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths: {}
''');
      build(empty);
      expect(reported(empty, .clientEmpty), isEmpty);
      final fine = IrFixture(specOf({'/a': 'operationId: a\ntags: [t]'}));
      build(fine);
      expect(fine.reported, isEmpty);
    });
  });
}
