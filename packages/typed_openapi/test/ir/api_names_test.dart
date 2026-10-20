import 'package:test/test.dart';
import 'package:typed_openapi/src/config/config_loader.dart';
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/ir/api_names.dart';
import 'package:typed_openapi/src/ir/ir.dart';
import 'package:typed_openapi/src/ir/ir_builder.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

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

List<(String, String, String?)> cases(StatusTypeIr? type, ClientIr ir) => [
  for (final c in type!.cases) (c.status, c.name, c.type?.code(ir.nameOf)),
];

const petstore = r'''
openapi: 3.1.0
info: {title: Pets, version: "1"}
servers:
  - url: https://pets.example.com/v1
paths:
  /pets:
    post:
      operationId: createPet
      tags: [pets]
      requestBody:
        content:
          application/json: {schema: {$ref: '#/components/schemas/Pet'}}
      responses:
        "200": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/Pet'}}}}
        "202": {description: queued, content: {application/json: {schema: {$ref: '#/components/schemas/Job'}}}}
        "404": {description: no, content: {application/json: {schema: {$ref: '#/components/schemas/Problem'}}}}
        "4XX": {description: bad, content: {application/json: {schema: {$ref: '#/components/schemas/Job'}}}}
        "499": {description: odd}
        default: {description: other, content: {application/json: {schema: {$ref: '#/components/schemas/Problem'}}}}
  /pets/{id}:
    get:
      operationId: getPet
      tags: [pets]
      parameters: [{name: id, in: path, required: true, schema: {type: integer}}]
      responses:
        "200": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/Pet'}}}}
        "201": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/Pet'}}}}
        "404": {description: no, content: {application/json: {schema: {$ref: '#/components/schemas/Problem'}}}}
components:
  schemas:
    Pet: {type: object, properties: {name: {type: string}}}
    Job: {type: object, properties: {id: {type: string}}}
    Problem: {type: object, properties: {code: {type: string}}}
''';

void main() {
  test('a status variant is named by the HTTP reason phrase', () {
    expect(
      [
        for (final status in [
          '200', '201', '204', '404', '422', '413', '4XX', '5xx', '2XX', //
          '1XX', 'default', '499', '299', '6XX',
        ])
          ApiNames.variantOf(status),
      ],
      [
        'Ok', 'Created', 'NoContent', 'NotFound', 'UnprocessableEntity', //
        'PayloadTooLarge', 'ClientError', 'ServerError', 'Success',
        'Informational', 'Other', 'Status499', 'Status299', 'Status6XX',
      ],
    );
  });

  test(
    'statuses with different bodies get sealed types; equal ones do not',
    () {
      final fixture = IrFixture(petstore);
      final ir = build(fixture);
      expect(fixture.reported, isEmpty);
      final create = operation(ir, 'createPet');
      expect(create.successType?.name, 'CreatePetResponse');
      expect(cases(create.successType, ir), [
        ('200', 'CreatePetResponseOk', 'Pet'),
        ('202', 'CreatePetResponseAccepted', 'Job'),
      ]);
      expect(create.errorType?.name, 'CreatePetError');
      expect(cases(create.errorType, ir), [
        ('404', 'CreatePetErrorNotFound', 'Problem'),
        ('4XX', 'CreatePetErrorClientError', 'Job'),
        ('499', 'CreatePetErrorStatus499', null),
        ('default', 'CreatePetErrorOther', 'Problem'),
      ]);
      final get = operation(ir, 'getPet');
      expect(get.successType, isNull);
      expect(get.errorType, isNull);
      expect(ir.root.name, 'ApiClient');
      expect(
        [for (final g in ir.groups) (g.name, g.field)],
        [
          ('PetsApi', 'pets'),
        ],
      );
      expect(
        [for (final s in ir.root.servers) (s.name, s.url, s.variables.length)],
        [('server', 'https://pets.example.com/v1', 0)],
      );
    },
  );

  test('the names are claimed after the models, which never move', () {
    // Models named like these types, reached from a property of Job.
    final fixture = IrFixture(
      petstore.replaceFirst(
        '    Job: {type: object, properties: {id: {type: string}}}',
        r'''
    Job:
      type: object
      properties:
        a: {$ref: '#/components/schemas/CreatePetError'}
        b: {$ref: '#/components/schemas/CreatePetErrors'}
        c: {$ref: '#/components/schemas/CreatePetResponse'}
        d: {$ref: '#/components/schemas/ApiClient'}
    CreatePetError: {type: object, properties: {a: {type: string}}}
    CreatePetErrors: {type: object, properties: {a: {type: string}}}
    CreatePetResponse: {type: object, properties: {a: {type: string}}}
    ApiClient: {type: object, properties: {a: {type: string}}}''',
      ),
    );
    final ir = build(fixture);
    expect(
      [for (final d in ir.declarations) d.name],
      containsAll([
        'ApiClient',
        'CreatePetError',
        'CreatePetErrors',
        'CreatePetResponse',
      ]),
    );
    expect(ir.root.name, 'ApiClient2');
    final create = operation(ir, 'createPet');
    expect(create.successType?.name, 'CreatePetResponse2');
    expect(create.errorType?.name, 'CreatePetError2');
    expect(create.errorType?.cases.first.name, 'CreatePetError2NotFound');
    final collisions = reported(fixture, .nameCollision);
    expect(collisions.map((d) => d.message), [
      contains('the root client is named "ApiClient2"'),
      contains(
        'the sealed type of the successes of createPet is named '
        '"CreatePetResponse2"',
      ),
      contains(
        'the sealed type of the errors of createPet is named '
        '"CreatePetError2"',
      ),
    ]);
    expect(collisions.last.fix, contains('operations:'));
    expect(collisions.last.severity, Severity.info);
  });

  test('an inline body named like the sealed type gives the plural', () {
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: getPet
      tags: [pets]
      responses:
        "200": {description: ok, content: {application/json: {schema: {type: object, properties: {a: {type: string}}}}}}
        "204": {description: none}
        "404": {description: no, content: {application/json: {schema: {type: object, properties: {b: {type: string}}}}}}
        "500": {description: down}
''');
    final ir = build(fixture);
    expect(fixture.reported, isEmpty);
    final get = operation(ir, 'getPet');
    expect(get.successType?.name, 'GetPetResponses');
    expect(cases(get.successType, ir), [
      ('200', 'GetPetResponsesOk', 'GetPetResponse'),
      ('204', 'GetPetResponsesNoContent', null),
    ]);
    expect(get.errorType?.name, 'GetPetErrors');
  });

  test('naming.client names the root client', () {
    final ir = build(
      IrFixture(
        petstore,
        generation: const GenerationConfig(clientClass: 'PetStore'),
      ),
    );
    expect(ir.root.name, 'PetStore');
  });

  test('naming.client must be a class name', () {
    final dir = TempDir();
    final path = dir.write('typed_openapi.yaml', '''
clients:
  a: {input: a.yaml, output: lib/a, naming: {client: Shop}}
  b: {input: a.yaml, output: lib/b, naming: {client: class}}
  c: {input: a.yaml, output: lib/c, naming: {client: shop}}
''');
    final bag = DiagnosticBag();
    final config = ConfigLoader(bag).load(path)!;
    expect(
      [for (final c in config.clients) c.generation.clientClass],
      [
        'Shop',
        null,
        null,
      ],
    );
    expect(bag.all.map((d) => (d.code, d.pointer?.value)), [
      (DiagnosticCode.configInvalid, '#/clients/b/naming/client'),
      (DiagnosticCode.configInvalid, '#/clients/c/naming/client'),
    ]);
  });

  test('group fields and servers are members of the root client', () {
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
servers:
  - url: https://{region}.example.com/{class}
    description: Production
    variables:
      region: {default: eu, enum: [eu, us], description: Where.}
      class: {default: v1}
  - url: /local
paths:
  /a:
    get:
      operationId: a
      tags: [class]
      responses: {"200": {description: ok}}
  /b:
    get:
      operationId: b
      responses: {"200": {description: ok}}
  /c:
    get:
      operationId: c
      tags: [hash code]
      responses: {"200": {description: ok}}
''');
    final ir = build(fixture);
    expect(
      [for (final g in ir.groups) (g.name, g.field)],
      [
        ('ClassApi', 'class_'),
        ('DefaultApi', 'defaultApi'),
        ('HashCodeApi', 'hashCode_'),
      ],
    );
    final [production, local] = ir.root.servers;
    expect(production.name, 'server1');
    expect(production.description, 'Production');
    expect(
      [
        for (final v in production.variables)
          (v.name, v.wireName, v.defaultValue, v.values.join('|')),
      ],
      [('region', 'region', 'eu', 'eu|us'), ('class_', 'class', 'v1', '')],
    );
    expect((local.name, local.url), ('server2', '/local'));
  });

  test('the names are the same on every build', () {
    String names(ClientIr ir) => [
      ir.root.name,
      for (final g in ir.groups)
        for (final o in g.operations) ...[
          ?o.successType?.name,
          ?o.errorType?.name,
          for (final c in [...?o.successType?.cases, ...?o.errorType?.cases])
            c.name,
        ],
    ].join(',');
    expect(
      names(build(IrFixture(petstore))),
      names(build(IrFixture(petstore))),
    );
  });
}
