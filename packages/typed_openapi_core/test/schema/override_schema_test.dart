import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_openapi_core/src/overrides/override_keys.dart';
import 'package:typed_openapi_core/src/schema/key_spec.dart';
import 'package:typed_openapi_core/src/schema/key_type.dart';
import 'package:typed_openapi_core/src/schema/override_catalog.dart';
import 'package:typed_openapi_core/src/schema/override_operation_keys.dart';
import 'package:typed_openapi_core/src/schema/override_schema_keys.dart';
import 'package:typed_openapi_core/src/schema/schema_writer.dart';
import 'package:typed_openapi_core/typed_openapi_core.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

import '../helpers/key_cases.dart';

void main() {
  final schema = JsonSchema(const OverrideSchema().toJson());

  bool loaderAccepts(Map<String, Object?> document) {
    final bag = DiagnosticBag();
    final set = OverrideLoader(
      bag,
    ).load(TempDir().write('overrides.yaml', jsonEncode(document)));
    return set != null && bag.all.isEmpty;
  }

  void expectAgreement(Map<String, Object?> document, {required bool valid}) {
    expect(schema.accepts(document), valid, reason: 'schema');
    expect(loaderAccepts(document), valid, reason: 'loader');
  }

  void expectGap(Map<String, Object?> document) {
    expect(loaderAccepts(document), isFalse, reason: 'loader');
    expect(schema.accepts(document), isTrue, reason: 'schema');
  }

  Map<String, Object?> operation(Map<String, Object?> entry) => {
    'operations': {'getPet': entry},
  };
  Map<String, Object?> schemaEntry(Map<String, Object?> entry) => {
    'schemas': {'Pet': entry},
  };

  final containers = [
    KeyCases(
      place: 'overrides',
      keys: OverrideCatalog.file,
      base: const {},
      wrap: (c) => c,
    ),
    KeyCases(
      place: 'operation',
      keys: OverrideOperationKeys.operation,
      base: const {},
      wrap: operation,
    ),
    KeyCases(
      place: 'parameter',
      keys: OverrideOperationKeys.parameter,
      base: const {},
      wrap: (c) => operation({
        'parameters': {'limit': c},
      }),
    ),
    KeyCases(
      place: 'request body',
      keys: OverrideOperationKeys.content,
      base: const {},
      wrap: (c) => operation({'requestBody': c}),
    ),
    KeyCases(
      place: 'response',
      keys: OverrideOperationKeys.content,
      base: const {},
      wrap: (c) => operation({
        'responses': {'200': c},
      }),
    ),
    KeyCases(
      place: 'sse',
      keys: OverrideOperationKeys.sse,
      base: const {},
      wrap: (c) => operation({'sse': c}),
    ),
    KeyCases(
      place: 'schema',
      keys: OverrideSchemaKeys.schema,
      base: const {},
      wrap: schemaEntry,
    ),
    KeyCases(
      place: 'property',
      keys: OverrideSchemaKeys.property,
      base: const {},
      wrap: (c) => schemaEntry({
        'properties': {'id': c},
      }),
    ),
  ];

  final names = <String>{};
  for (final container in containers) {
    for (final c in container.all()) {
      if (!names.add(c.name)) throw StateError('Two cases: "${c.name}".');
      test(
        '${c.name}: schema and loader both ${c.isValid ? 'accept' : 'reject'}',
        () => expectAgreement(c.document, valid: c.isValid),
      );
    }
  }

  test('an operation is addressed by operationId or METHOD /path', () {
    for (final key in [
      'getPet',
      'GET /pets/{id}',
      'get /pets',
      'GET',
      ' /pets',
      '',
      'GET  /x',
    ]) {
      expectAgreement({
        'operations': {key: <String, Object?>{}},
      }, valid: true);
    }
    for (final key in ['FOO /pets', 'fetch /pets']) {
      expectAgreement({
        'operations': {key: <String, Object?>{}},
      }, valid: false);
    }
  });

  test('a parameter is addressed by name or in:name', () {
    for (final key in ['limit', 'query:limit', 'header:X-Id']) {
      expectAgreement(
        operation({
          'parameters': {key: <String, Object?>{}},
        }),
        valid: true,
      );
    }
    for (final key in ['bogus:limit', 'Query:limit']) {
      expectAgreement(
        operation({
          'parameters': {key: <String, Object?>{}},
        }),
        valid: false,
      );
    }
  });

  test('a section may be null, as when its entries are commented out', () {
    expectAgreement({'operations': null, 'schemas': null}, valid: true);
  });

  test('an entry must be a mapping, not null', () {
    expectAgreement({
      'operations': {'getPet': null},
    }, valid: false);
    expectAgreement({
      'schemas': {'Pet': null},
    }, valid: false);
  });

  test('sse: data is a component name or a schema, events a non-empty map', () {
    for (final sse in [
      {'data': 'Pet'},
      {
        'data': {'type': 'string'},
      },
      {
        'events': {'ping': null, 'pet': 'Pet', 'other': <String, Object?>{}},
      },
    ]) {
      expectAgreement(operation({'sse': sse}), valid: true);
    }
    for (final sse in [
      {'data': 1},
      {'events': <String, Object?>{}},
      {
        'events': {'ping': 1},
      },
    ]) {
      expectAgreement(operation({'sse': sse}), valid: false);
    }
  });

  test('known gap: sse data and events together', () {
    expectGap(
      operation({
        'sse': {
          'data': 'Pet',
          'events': {'pet': 'Pet'},
        },
      }),
    );
  });

  test(r'known gap: a schema field beside a $ref', () {
    expectGap(
      schemaEntry({r'$ref': 'Other', 'type': 'string'}),
    );
    expectGap(
      schemaEntry({
        r'$ref': 'Other',
        'required': ['id'],
      }),
    );
  });

  test(r'a property keeps its required beside a $ref', () {
    expectAgreement(
      schemaEntry({
        'properties': {
          'id': {r'$ref': 'Other', 'required': true},
        },
      }),
      valid: true,
    );
  });

  test(r'known gap: properties beside a $ref', () {
    expectGap(
      schemaEntry({
        r'$ref': 'Other',
        'properties': {
          'id': {'name': 'identifier'},
        },
      }),
    );
  });

  test('known gap: a contentType that is not a media type is only a text', () {
    expectAgreement(
      operation({
        'requestBody': {'contentType': 'application/json'},
      }),
      valid: true,
    );
    expectAgreement(
      operation({
        'requestBody': {'contentType': 'json'},
      }),
      valid: false,
    );
  });

  test('known gap: a dartType name that is a reserved word', () {
    expectGap(
      schemaEntry({
        'dartType': {'type': 'class', 'import': 'package:a/a.dart'},
      }),
    );
    expectGap(
      schemaEntry({
        'dartType': {
          'type': 'Money',
          'import': 'package:a/a.dart',
          'converter': 'class',
        },
      }),
    );
  });

  test('OverrideKeys is the key names of the catalog', () {
    Set<String> names(List<KeySpec> keys) => {for (final k in keys) k.name};
    expect(OverrideKeys.sections, {'operations', 'schemas'});
    expect(OverrideKeys.sections, names(OverrideCatalog.file));
    expect(OverrideKeys.operation, names(OverrideOperationKeys.operation));
    expect(OverrideKeys.parameter, names(OverrideOperationKeys.parameter));
    expect(OverrideKeys.requestBody, names(OverrideOperationKeys.content));
    expect(OverrideKeys.response, names(OverrideOperationKeys.content));
    expect(OverrideKeys.sse, names(OverrideOperationKeys.sse));
    expect(OverrideKeys.schema, names(OverrideSchemaKeys.schema));
    expect(OverrideKeys.property, names(OverrideSchemaKeys.property));
    expect(OverrideKeys.dartType, {'type', 'import', 'converter'});
  });

  test('every key says what it does', () {
    final undescribed = <String>[];
    void visit(KeySpec key) {
      if (key.description.trim().isEmpty) undescribed.add(key.name);
      if (key.type case ObjectKey(:final keys)) keys.forEach(visit);
      if (key.type case MapKey(value: ObjectKey(:final keys))) {
        keys.forEach(visit);
      }
    }

    for (final keys in [
      OverrideCatalog.file,
      OverrideOperationKeys.operation,
      OverrideOperationKeys.parameter,
      OverrideOperationKeys.content,
      OverrideOperationKeys.sse,
      OverrideSchemaKeys.schema,
      OverrideSchemaKeys.property,
    ]) {
      keys.forEach(visit);
    }
    expect(undescribed, isEmpty);
  });

  test('the schema is a draft-07 document with the title and the url', () {
    final json = const OverrideSchema().toJson();
    expect(json[r'$schema'], SchemaWriter.dialect);
    expect(json['title'], 'typed_openapi overrides');
    expect(json['additionalProperties'], false);
    expect(
      OverrideSchema.url,
      endsWith('/schema/typed_openapi.overrides.schema.json'),
    );
    expect(const OverrideSchema().toText(), endsWith('}\n'));
  });
}
