@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/emit/api_library.dart';
import 'package:typed_openapi/src/ir/ir.dart';
import 'package:typed_openapi/src/overrides/override_set.dart';

import '../helpers/emit_fixture.dart';

void main() {
  test('the petstore fixture matches its goldens (R15.3)', () {
    final files = emitClient('petstore.yaml');
    final goldens = p.join('test', 'emit', 'goldens', 'petstore');
    if (Platform.environment['UPDATE_GOLDENS'] == '1') {
      for (final MapEntry(:key, :value) in files.entries) {
        File(p.join(goldens, '$key.golden'))
          ..createSync(recursive: true)
          ..writeAsStringSync(value);
      }
    }
    final expected = {
      for (final file in Directory(
        goldens,
      ).listSync(recursive: true).whereType<File>())
        p
            .relative(file.path, from: goldens)
            .replaceAll(r'\', '/')
            .replaceAll(RegExp(r'\.golden$'), ''): file
            .readAsStringSync(),
    };
    expect(files.keys.toSet(), expected.keys.toSet());
    for (final MapEntry(:key, :value) in files.entries) {
      expect(value, expected[key], reason: key);
    }
  });

  test('a client is its models, a file per group and the root', () {
    final files = emitClient('petstore.yaml');
    expect(
      files.keys.where((f) => !f.startsWith('models')),
      [
        'api.dart',
        'api/default_api.dart',
        'api/pets_api.dart',
        'api/store_api.dart',
        'api_client.dart',
      ],
    );
    expect(files['api.dart'], contains("export 'api/pets_api.dart';"));
    expect(files['api_client.dart'], contains("export 'models.dart';"));
    expect(files['api_client.dart'], contains("export 'api.dart';"));
    for (final MapEntry(:key, :value) in files.entries) {
      expect(
        value,
        startsWith(
          '// GENERATED CODE - DO NOT MODIFY BY HAND.\n// dart format off\n',
        ),
        reason: key,
      );
    }
  });

  test('the root file is named after the client, apart from the barrels', () {
    expect(ApiLibrary.rootFile('petstore'), 'petstore.dart');
    expect(ApiLibrary.rootFile('my-shop'), 'my_shop.dart');
    expect(ApiLibrary.rootFile('api'), 'api_client.dart');
    expect(ApiLibrary.rootFile('models'), 'models_client.dart');
    expect(ApiLibrary.rootFile('2fa'), 'type_2_fa.dart');
    expect(ApiLibrary.rootFile('ü'), 'api_client.dart');
  });

  test('group files that would share a name get 2, 3, ...', () {
    final ir = ClientIr(
      declarations: const [],
      groups: [
        GroupIr('UserDTOApi', const []),
        GroupIr('UserDtoApi', const []),
      ],
    );
    expect(const ApiLibrary().fileNames(ir), {
      'UserDTOApi': 'user_dto_api.dart',
      'UserDtoApi': 'user_dto_api2.dart',
    });
  });

  test('the same spec gives the same files', () {
    expect(emitClient('petstore.yaml'), emitClient('petstore.yaml'));
    expect(
      emitClient('hostile_operations.yaml'),
      emitClient('hostile_operations.yaml'),
    );
  });

  test('strings from the spec cannot leave their literal or comment', () {
    for (final mode in UnionMode.values) {
      final files = emitClient(
        'hostile_operations.yaml',
        generation: GenerationConfig(union: mode),
      );
      for (final MapEntry(:key, :value) in files.entries) {
        for (final line in value.split('\n')) {
          final code = line.trimLeft();
          expect(
            code.startsWith('injected') || code.startsWith('void injected'),
            isFalse,
            reason: '$key: $line',
          );
          if (!code.startsWith('///') && !code.startsWith('//')) {
            expect(code, isNot(startsWith('/*')), reason: '$key: $line');
          }
          expect(line, isNot(contains('\r')), reason: key);
        }
        expect(
          value,
          isNot(matches(RegExp('[\u202a-\u202e\u2066-\u2069\u2028\u2029]'))),
          reason: key,
        );
      }
    }
  });
}
