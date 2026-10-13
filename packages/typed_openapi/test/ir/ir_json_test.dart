@TestOn('vm')
library;

import 'dart:mirrors';

import 'package:test/test.dart';
import 'package:typed_openapi/src/ir/ir.dart';
import 'package:typed_openapi/src/ir/ir_json.dart';

import '../helpers/ir_fixture.dart';

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
components:
  securitySchemes:
    key: {type: apiKey, name: X-Key, in: header}
    bearer: {type: http, scheme: bearer, bearerFormat: JWT}
    oauth: {type: oauth2, flows: {implicit: {authorizationUrl: "https://a.example/auth", scopes: {write: w}}}}
    oidc: {type: openIdConnect, openIdConnectUrl: "https://a.example/.well-known/openid-configuration"}
    mtls: {type: mutualTLS}
''';

/// The key of the dump a field is written under, when it is not the field's
/// name; `Class.field` entries are for one class.
const _renames = {
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
};

/// The classes whose fields the dump must write.
final _classes = <Type>[
  ClientIr,
  GroupIr,
  OperationIr,
  EventStreamIr,
  EventUnionIr,
  EventVariantIr,
  ParameterIr,
  RequestBodyIr,
  ResponseIr,
  SingleError,
  ErrorsByStatus,
  EncodingIr,
  PartIr,
  StatusTypeIr,
  StatusCaseIr,
  RootIr,
  ServerIr,
  ServerVariableIr,
  SecurityUseIr,
  SecuritySchemeIr,
];

void _collectKeys(Object? json, Set<String> keys) {
  switch (json) {
    case final Map<String, Object?> map:
      for (final MapEntry(:key, :value) in map.entries) {
        keys.add(key);
        _collectKeys(value, keys);
      }
    case final List<Object?> list:
      for (final item in list) {
        _collectKeys(item, keys);
      }
  }
}

/// The public fields of [type], by name.
List<String> _fieldsOf(Type type) => [
  for (final member in reflectClass(type).declarations.values)
    if (member is VariableMirror && !member.isStatic && !member.isPrivate)
      MirrorSystem.getName(member.simpleName),
];

void main() {
  final ir = IrFixture(_spec).build();
  final json = IrJson((_) => 'api.yaml').toJson(ir);
  final keys = <String>{};
  _collectKeys(json, keys);

  test('every field of the operation IR is in the dump', () {
    final missing = [
      for (final type in _classes)
        for (final field in _fieldsOf(type))
          if (!_notDumped.contains('$type.$field') &&
              !keys.contains(
                _renames['$type.$field'] ?? _renames[field] ?? field,
              ))
            '$type.$field',
    ];
    expect(missing, isEmpty, reason: 'Write these fields in IrJson.');
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
}

Map<String, Object?> _operation(Map<String, Object?> json, String name) => [
  for (final group in json['groups']! as List<Object?>)
    for (final operation
        in (group! as Map<String, Object?>)['operations']! as List<Object?>)
      if ((operation! as Map<String, Object?>)['name'] == name)
        operation as Map<String, Object?>,
].single;
