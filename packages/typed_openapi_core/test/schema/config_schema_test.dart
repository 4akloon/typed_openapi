import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_openapi_core/src/config/config_keys.dart';
import 'package:typed_openapi_core/src/schema/config_catalog.dart';
import 'package:typed_openapi_core/src/schema/config_generation_keys.dart';
import 'package:typed_openapi_core/src/schema/config_naming_keys.dart';
import 'package:typed_openapi_core/src/schema/key_spec.dart';
import 'package:typed_openapi_core/src/schema/schema_writer.dart';
import 'package:typed_openapi_core/typed_openapi_core.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

import '../helpers/key_cases.dart';

void main() {
  final schema = JsonSchema(const ConfigSchema().toJson());
  final required = {
    for (final key in ConfigCatalog.clientOnly)
      if (key.isRequired) key.name: key.example,
  };

  bool loaderAccepts(Map<String, Object?> document) {
    final bag = DiagnosticBag();
    final config = ConfigLoader(
      bag,
    ).load(TempDir().write('typed_openapi.yaml', jsonEncode(document)));
    return config != null && bag.all.isEmpty;
  }

  Map<String, Object?> withDefaults(Map<String, Object?> defaults) => {
    'defaults': defaults,
    'clients': {'a': required},
  };

  void expectAgreement(Map<String, Object?> document, {required bool valid}) {
    expect(schema.accepts(document), valid, reason: 'schema');
    expect(loaderAccepts(document), valid, reason: 'loader');
  }

  final containers = [
    KeyCases(
      place: 'defaults',
      keys: ConfigCatalog.defaultsKeys,
      base: const {},
      wrap: withDefaults,
    ),
    KeyCases(
      place: 'client',
      keys: ConfigCatalog.client,
      base: required,
      wrap: (container) => {
        'clients': {'a': container},
      },
    ),
  ];

  for (final container in containers) {
    for (final c in container.all()) {
      test(
        '${c.name}: schema and loader both ${c.isValid ? 'accept' : 'reject'}',
        () => expectAgreement(c.document, valid: c.isValid),
      );
    }
  }

  test('the file itself: unknown key, missing clients, empty clients', () {
    expectAgreement({
      'bogus': 1,
      'clients': {'a': required},
    }, valid: false);
    expectAgreement(<String, Object?>{}, valid: false);
    expectAgreement({'clients': <String, Object?>{}}, valid: false);
  });

  test('severity: the levels each code allows', () {
    expectAgreement(
      withDefaults({
        'severity': {'TOA303': 'off', 'TOA201': 'info'},
      }),
      valid: true,
    );
    for (final severity in [
      {'TOA001': 'warning'},
      {'TOA901': 'off'},
      {'TOA201': 'fatal'},
    ]) {
      expectAgreement(withDefaults({'severity': severity}), valid: false);
    }
  });

  test('what the schema cannot say: one code under its id and its name', () {
    final document = withDefaults({
      'severity': {'TOA303': 'info', 'nullable-enum-one-of': 'warning'},
    });
    expect(loaderAccepts(document), isFalse);
    expect(schema.accepts(document), isTrue);
  });

  test('known gap: equal input_suffix and patch_suffix', () {
    final document = withDefaults({
      'naming': {'input_suffix': 'Same', 'patch_suffix': 'Same'},
    });
    expect(loaderAccepts(document), isFalse);
    expect(schema.accepts(document), isTrue);
  });

  test('known gap: an operation_prefix that is not a regular expression', () {
    final document = withDefaults({
      'naming': {'operation_prefix': '('},
    });
    expect(loaderAccepts(document), isFalse);
    expect(schema.accepts(document), isTrue);
  });

  test('severity: a fixed code is only raised, a config code is absent', () {
    final levels = _properties(const ConfigSchema().toJson(), 'severity');
    List<Object?> of(DiagnosticCode code) =>
        (levels[code.id]! as Map)['enum']! as List<Object?>;
    expect(of(DiagnosticCode.parseError), ['error']);
    expect(of(DiagnosticCode.outputFileReplaced), isNot(contains('off')));
    expect(of(DiagnosticCode.outputFileReplaced).length, lessThan(4));
    for (final code in DiagnosticCode.configCodes) {
      expect(levels, isNot(contains(code.id)));
      expect(levels, isNot(contains(code.slug)));
    }
  });

  test('severity: the schema lists every code that can be changed', () {
    final levels = _properties(const ConfigSchema().toJson(), 'severity');
    for (final code in DiagnosticCode.values) {
      if (DiagnosticCode.fixedCodes.contains(code)) continue;
      for (final name in [code.id, code.slug]) {
        expect(
          (levels[name]! as Map)['enum'],
          ['error', 'warning', 'info', 'off'],
          reason: name,
        );
      }
    }
  });

  test('rules: every normalizer rule, and nothing else', () {
    final rules = _properties(const ConfigSchema().toJson(), 'rules');
    expect(rules.keys.toSet(), Normalizer.ruleNames);
    final first = Normalizer.ruleNames.first;
    expectAgreement(
      withDefaults({
        'rules': {first: false},
      }),
      valid: true,
    );
    expectAgreement(
      withDefaults({
        'rules': {'no-such-rule': false},
      }),
      valid: false,
    );
  });

  test('ConfigKeys is the key names of the catalog', () {
    Set<String> names(List<KeySpec> keys) => {for (final k in keys) k.name};
    expect(ConfigKeys.topLevel, {'defaults', 'clients'});
    expect(ConfigKeys.defaults, names(ConfigCatalog.defaultsKeys));
    expect(ConfigKeys.client, names(ConfigCatalog.client));
    expect(ConfigKeys.naming, names(ConfigNamingKeys.keys));
    expect(ConfigKeys.types, names(ConfigGenerationKeys.typeKeys));
    expect(ConfigKeys.filter, names(ConfigGenerationKeys.filter));
    expect(ConfigKeys.customType, names(ConfigGenerationKeys.customType));
    expect(ConfigKeys.errors, names(ConfigGenerationKeys.errorsKeys));
    expect(ConfigKeys.sse, names(ConfigGenerationKeys.sseKeys));
  });

  test('every key says what it does', () {
    final undescribed = <String>[];
    void visit(KeySpec key) {
      if (key.description.trim().isEmpty) undescribed.add(key.name);
    }

    ConfigCatalog.file.forEach(visit);
    ConfigCatalog.client.forEach(visit);
    ConfigGenerationKeys.generation.forEach(visit);
    ConfigNamingKeys.keys.forEach(visit);
    ConfigGenerationKeys.customType.forEach(visit);
    ConfigGenerationKeys.typeKeys.forEach(visit);
    ConfigGenerationKeys.filter.forEach(visit);
    expect(undescribed, isEmpty);
  });

  test('the schema is a draft-07 document with the title and definitions', () {
    final json = const ConfigSchema().toJson();
    expect(json[r'$schema'], SchemaWriter.dialect);
    expect(json['title'], 'typed_openapi.yaml');
    expect(
      (json['definitions']! as Map).keys,
      containsAll([
        'defaults',
        'client',
        for (final key in ConfigCatalog.shared) key.name,
      ]),
    );
  });
}

Map<String, Object?> _properties(Map<String, Object?> schema, String key) {
  final definitions = schema['definitions']! as Map<String, Object?>;
  final shared = definitions[key]! as Map<String, Object?>;
  return shared['properties']! as Map<String, Object?>;
}
