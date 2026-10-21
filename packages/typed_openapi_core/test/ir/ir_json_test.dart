@TestOn('vm')
library;

import 'dart:mirrors';

import 'package:test/test.dart';
import 'package:typed_openapi_core/src/config/generation_config.dart';
import 'package:typed_openapi_core/src/ir/dart_type.dart';
import 'package:typed_openapi_core/src/ir/ir.dart';
import 'package:typed_openapi_core/src/ir/ir_json.dart';
import 'package:typed_openapi_core/src/ir/ir_type_text.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/ir_json_classes.dart';

/// A spec that gives every field of the operation IR a value.
const _spec = '''
openapi: 3.1.0
info: {title: t, version: "1"}
servers:
  - url: https://{region}.example.com/v1
    description: Production
    variables:
      region: {default: eu, enum: [eu, us], description: The region.}
security: [{key: []}]
paths:
  /files/{id}:
    parameters:
      - {name: id, in: path, required: true, schema: {type: string}}
    post:
      operationId: upload
      summary: Uploads a file.
      description: Uploads.
      deprecated: true
      tags: [files]
      security: [{oauth: [write]}, {bearer: []}, {oidc: []}, {mtls: []}]
      parameters:
        - name: q
          in: query
          style: pipeDelimited
          explode: false
          allowReserved: true
          deprecated: true
          description: The query.
          schema: {type: array, items: {type: string}, default: [a]}
        - {name: j, in: header, content: {application/json: {schema: {type: object, properties: {a: {type: string}}}}}}
      requestBody:
        description: The body.
        required: true
        content:
          multipart/form-data:
            schema:
              type: object
              properties:
                file: {type: string, format: binary, description: The file.}
                note: {type: string}
              required: [file]
            encoding: {file: {contentType: image/png}}
      responses:
        "200": {description: ok, content: {application/json: {schema: {type: object, properties: {a: {type: string}}}}}}
        "201": {description: created, content: {application/json: {schema: {type: string, format: password}}}}
        "404": {description: no, content: {application/json: {schema: {type: string, writeOnly: true}}}}
        "4XX": {description: bad, content: {application/json: {schema: {type: object, properties: {b: {type: string}}}}}}
    put:
      operationId: save
      tags: [files]
      requestBody:
        content:
          application/x-www-form-urlencoded:
            schema: {type: object, properties: {a: {type: array, items: {type: string}}}}
            encoding: {a: {style: spaceDelimited, explode: false, allowReserved: true, contentType: text/plain}}
      responses:
        "200": {description: ok, content: {application/json: {schema: {type: object, properties: {data: {type: string}}, required: [data]}}}}
        "400": {description: bad, content: {application/json: {schema: {type: object, properties: {c: {type: string}}}}}}
  /feed:
    get:
      operationId: feed
      tags: [files]
      responses:
        "200": {description: ok, content: {text/event-stream: {schema: {type: object, properties: {n: {type: integer}}}}}}
  /chat:
    get:
      operationId: chat
      tags: [files]
      responses:
        "200":
          description: ok
          content:
            text/event-stream:
              itemSchema:
                oneOf:
                  - {properties: {event: {const: token}, data: {type: string, format: password}}}
                  - {properties: {event: {const: done}}}
                  - {properties: {event: {const: info}, data: {type: string, contentMediaType: application/json, contentSchema: {type: object, properties: {a: {type: string}}}}}}
  /talk:
    get:
      operationId: talk
      tags: [files]
      responses:
        "200":
          description: ok
          content:
            application/json: {schema: {type: object, properties: {n: {type: integer}}}}
            text/event-stream: {schema: {type: object, properties: {n: {type: integer}}}}
components:
  securitySchemes:
    key: {type: apiKey, name: X-Key, in: header}
    bearer: {type: http, scheme: bearer, bearerFormat: JWT}
    oauth: {type: oauth2, flows: {implicit: {authorizationUrl: "https://a.example/auth", scopes: {write: w}}}}
    oidc: {type: openIdConnect, openIdConnectUrl: "https://a.example/.well-known/openid-configuration"}
    mtls: {type: mutualTLS}
''';

/// A spec that gives every field of the declarations a value.
const _declarations = r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets:
    get:
      operationId: listPets
      responses:
        '200':
          description: ok
          content:
            application/json:
              schema:
                oneOf:
                  - {$ref: '#/components/schemas/Pet'}
                  - {$ref: '#/components/schemas/Status'}
                  - {type: integer}
                  - {type: number}
components:
  schemas:
    Pet:
      type: object
      description: A pet.
      deprecated: true
      required: [id, kind]
      additionalProperties: {type: string}
      properties:
        id: {type: integer, description: The id., minimum: 1, maximum: 9, exclusiveMinimum: 0, exclusiveMaximum: 10, multipleOf: 1}
        kind: {const: pet}
        name: {type: string, deprecated: true, default: rex, minLength: 1, maxLength: 5, pattern: '^a'}
        tags: {type: array, items: {type: string}, minItems: 1, maxItems: 3, uniqueItems: true}
        meta: {type: object, minProperties: 1, maxProperties: 2}
        mood: {anyOf: [{type: string}, {enum: ['']}]}
    Status:
      type: string
      description: A status.
      enum: [a, b]
      x-enum-descriptions: [First, Second]
''';

/// A spec that sets the flags the first one leaves off: secrets, direction,
/// a discriminator and the variants of one JSON type.
const _flags = r'''
openapi: 3.2.0
info: {title: t, version: "1"}
paths:
  /owner:
    post:
      operationId: saveOwner
      requestBody:
        content:
          application/json:
            schema: {$ref: '#/components/schemas/Owner'}
      responses:
        '204': {description: ok}
    get:
      operationId: getOwner
      responses:
        '200':
          description: ok
          content:
            application/json:
              schema: {$ref: '#/components/schemas/Owner'}
  /animal:
    get:
      operationId: getAnimal
      responses:
        '200':
          description: ok
          content:
            application/json:
              schema: {$ref: '#/components/schemas/Animal'}
  /text:
    get:
      operationId: getText
      responses:
        '200':
          description: ok
          content:
            application/json:
              schema: {$ref: '#/components/schemas/Text'}
  /secret:
    get:
      operationId: getSecret
      responses:
        '200':
          description: ok
          content:
            application/json:
              schema: {$ref: '#/components/schemas/Secret'}
  /status:
    get:
      operationId: getStatus
      responses:
        '200':
          description: ok
          content:
            application/json:
              schema: {$ref: '#/components/schemas/Status'}
components:
  schemas:
    Status: {type: string, enum: [a, b]}
    Owner:
      type: object
      additionalProperties: {type: string, writeOnly: true}
      properties:
        id: {type: integer, readOnly: true}
        secret: {type: string, writeOnly: true}
        note: {type: string, x-typed-tri-state: true}
    Animal:
      oneOf:
        - {$ref: '#/components/schemas/Cat'}
        - {$ref: '#/components/schemas/Dog'}
      discriminator: {propertyName: kind, defaultMapping: Dog}
    Cat:
      type: object
      required: [kind]
      properties:
        kind: {const: cat}
        token: {type: string, format: password}
    Dog:
      type: object
      required: [kind]
      properties:
        kind: {const: dog}
    Secret:
      oneOf:
        - {type: string, format: password}
        - {type: integer}
    Text:
      oneOf:
        - {type: string}
        - {type: string, minLength: 1}
        - {type: integer}
''';

/// The key of the dump a field is written under, when it is not the field's
/// name; `Class.field` entries are for one class.
const _renames = {
  'jsonKey': 'json',
  'valueType': 'type',
  'EnumDecl.values': 'cases',
  'EnumDecl.kind': 'values',
  'UnionDecl.defaultVariant': 'default',
  'discriminatorValues': 'values',
  'location': 'at',
  'wireName': 'wire',
  'placement': 'in',
  'defaultValue': 'default',
  'envelopeKey': 'envelope',
  'ErrorsByStatus.cases': 'errors',
  'ErrorsByStatus.sensitive': 'sensitiveErrors',
  'SingleError.type': 'errors',
  'SingleError.statuses': 'errorStatuses',
  'PartIr.name': 'name',
  'SecuritySchemeIr.placement': 'placement',
  'SecuritySchemeIr.scheme': 'scheme',
};

/// Fields the dump leaves out on purpose: the location of a node whose
/// operation is named by `at`, and the text and media type of a response,
/// which the status and the kind already tell.
const _notDumped = {
  'ParameterIr.location',
  'RequestBodyIr.location',
  'ResponseIr.location',
  'ResponseIr.contentType',
  'ResponseIr.description',
  // A location or an identity made of one: no emitter reads it (the emitters
  // use a declaration's id only as a key), and the dump of the manifest hash
  // leaves locations out so the hash does not depend on where the spec is.
  'Declaration.id',
  'FieldIr.location',
  'EventVariantIr.location',
};

/// The public fields of [type], by name.
List<String> _fieldsOf(Type type) => [
  for (final member in reflectClass(type).declarations.values)
    if (member is VariableMirror && !member.isStatic && !member.isPrivate)
      MirrorSystem.getName(member.simpleName),
];

String _nameOf(DeclId id) => 'N';

void main() {
  final ir = IrFixture(_spec).build();
  final json = IrJson((_) => 'api.yaml').toJson(ir);

  test('every field of every IR class is in the dump', () {
    // `exhaustive` and the flags are written only when set (R14.2).
    const open = GenerationConfig(exhaustive: false, triState: .extension);
    final dumps = [
      json,
      for (final fixture in [
        IrFixture(_spec, generation: open),
        IrFixture(_declarations),
        IrFixture(_flags, generation: open),
      ])
        IrJson((_) => 'api.yaml').toJson(fixture.build()),
    ];
    final missing = [
      for (final MapEntry(key: type, value: path)
          in IrJsonClasses.paths.entries)
        for (final field in _fieldsOf(type))
          if (!_notDumped.contains('$type.$field') &&
              !{
                for (final dump in dumps) ...IrJsonClasses.keysAt(dump, path),
              }.contains(_renames['$type.$field'] ?? _renames[field] ?? field))
            '$type.$field',
    ];
    expect(missing, isEmpty, reason: 'Write these fields in IrJson.');
  });

  test('the dump without locations has no location', () {
    final ir = IrFixture(_spec).build();
    expect(
      const IrJson.withoutLocations().encode(ir),
      isNot(contains('"at"')),
    );
  });

  test('every kind of type is written with all it has', () {
    const text = IrTypeText(_nameOf);
    const string = CoreType(.string);
    const custom = CustomType(type: 'M', import: 'a', json: string);
    final types = <String, DartType>{
      'nullable': const CoreType(.string, nullable: true),
      'bytes': const CoreType(.bytes),
      'binary': const CoreType(.binary),
      'string': string,
      'list': const ListType(string),
      'list of nullable': const ListType(CoreType(.string, nullable: true)),
      'map': const MapType(string),
      'patch': const PatchType(string),
      'custom': custom,
      'custom import': const CustomType(type: 'M', import: 'b', json: string),
      'custom converter': const CustomType(
        type: 'M',
        import: 'a',
        json: string,
        converter: 'C',
      ),
      'custom json': const CustomType(
        type: 'M',
        import: 'a',
        json: CoreType(.integer),
      ),
      'custom nullable': custom.withNullable(true),
    };
    final written = types.map((name, type) => MapEntry(name, text.of(type)));
    expect(written.values.toSet().length, types.length, reason: '$written');
  });

  test('the classes list has fields to check', () {
    expect(_fieldsOf(OperationIr), contains('security'));
    expect(_fieldsOf(ServerVariableIr), contains('values'));
  });

  test('the servers, the security and the status types are written', () {
    final root = json['root']! as Map<String, Object?>;
    expect(root['name'], 'ApiClient');
    final servers = root['servers']! as List<Object?>;
    expect(servers.single, {
      'name': 'server',
      'url': 'https://{region}.example.com/v1',
      'at': 'api.yaml#/servers/0',
      'description': 'Production',
      'variables': [
        {
          'name': 'region',
          'wire': 'region',
          'default': 'eu',
          'values': ['eu', 'us'],
          'description': 'The region.',
        },
      ],
    });
    final upload = _operation(json, 'upload');
    expect(
      (upload['security']! as List<Object?>).map(
        (alternative) => [
          for (final use in alternative! as List<Object?>)
            ((use! as Map<String, Object?>)['scheme']!
                as Map<String, Object?>)['kind'],
        ],
      ),
      [
        ['oauth2'],
        ['http'],
        ['openIdConnect'],
        ['mutualTls'],
      ],
    );
    expect(upload['successType'], {
      'name': 'UploadResponse',
      'cases': [
        {
          'status': '200',
          'name': 'UploadResponseOk',
          'type': 'UploadResponse200',
        },
        {
          'status': '201',
          'name': 'UploadResponseCreated',
          'type': 'String',
          'sensitive': true,
        },
      ],
    });
    expect(upload['sensitiveErrors'], ['404']);
    expect(upload['partsName'], 'UploadRequest');
  });

  test('the Accept of the method that returns the body is written', () {
    expect(_operation(json, 'talk')['accept'], 'application/json');
    expect(_operation(json, 'talkStream').containsKey('accept'), isFalse);
  });
}

Map<String, Object?> _operation(Map<String, Object?> json, String name) => [
  for (final group in json['groups']! as List<Object?>)
    for (final operation
        in (group! as Map<String, Object?>)['operations']! as List<Object?>)
      if ((operation! as Map<String, Object?>)['name'] == name)
        operation as Map<String, Object?>,
].single;
