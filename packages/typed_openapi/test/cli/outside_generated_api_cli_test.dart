import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

import '../helpers/cli_runner.dart';

const _spec = r'''
openapi: 3.0.0
info: {title: t, version: "1"}
paths:
  /pets:
    get:
      operationId: listPets
      tags: [pets]
      responses: {'204': {description: ok}}
  /links:
    get:
      operationId: listLinks
      tags: [links]
      responses:
        '200':
          description: ok
          content:
            application/json:
              schema: {$ref: '#/components/schemas/'}
''';

void main() {
  group('a finding outside the generated API', () {
    late TempDir dir;

    setUp(() {
      dir = TempDir();
      dir.write('api.yaml', _spec);
    });

    Future<(int, String, String)> inDir(String config, List<String> args) {
      dir.write('typed_openapi.yaml', config);
      return CliRunner.run(args, workingDirectory: dir.path);
    }

    const filtered = '''
clients:
  api:
    input: api.yaml
    output: lib/api
    include: {paths: [/pets]}
''';

    test('does not stop generate, and check shows it as info', () async {
      final (code, out, _) = await inDir(filtered, ['generate']);
      expect(code, 0, reason: out);
      expect(File(p.join(dir.path, 'lib/api/api.dart')).existsSync(), isTrue);
      final (checked, text, _) = await inDir(filtered, ['check']);
      expect(checked, 0);
      expect(text, contains('info TOA100 invalid-ref'));
      expect(text, contains('info TOA811 findings-outside-generated-api'));
      expect(text, contains('errors: 0'));
    });

    test('in an included operation it still blocks generate', () async {
      final (code, out, _) = await inDir(
        filtered.replaceAll('/pets', '/links'),
        ['generate'],
      );
      expect(code, 1);
      expect(out, contains('Skipped'));
      expect(Directory(p.join(dir.path, 'lib/api')).existsSync(), isFalse);
    });

    test('an exclude override acts as the filter', () async {
      dir.write(
        'overrides.yaml',
        'operations:\n  GET /links: {exclude: true}\n',
      );
      final (code, _, _) = await inDir(
        '''
clients:
  api: {input: api.yaml, output: lib/api, overrides: overrides.yaml}
''',
        ['generate'],
      );
      expect(code, 0);
      expect(File(p.join(dir.path, 'lib/api/api.dart')).existsSync(), isTrue);
    });

    test('a baseline accepts none of the lowered findings', () async {
      final (created, out, _) = await inDir(
        '$filtered    baseline: api.baseline.yaml\n',
        ['baseline', 'create'],
      );
      expect(created, 0);
      final baseline = File(p.join(dir.path, 'api.baseline.yaml'));
      final text = baseline.existsSync() ? baseline.readAsStringSync() : '';
      expect(text, isNot(contains('TOA100')), reason: out);
      expect(text, isNot(contains('TOA811')));
    });

    test('two clients over one spec are judged by their own filter', () async {
      final (code, out, _) = await inDir(
        '''
clients:
  pets: {input: api.yaml, output: lib/pets, include: {paths: [/pets]}}
  links: {input: api.yaml, output: lib/links, include: {paths: [/links]}}
''',
        ['generate'],
      );
      expect(code, 1);
      expect(out, contains('Skipped links'));
      expect(File(p.join(dir.path, 'lib/pets/api.dart')).existsSync(), isTrue);
      expect(Directory(p.join(dir.path, 'lib/links')).existsSync(), isFalse);
    });
  });
}
