import 'dart:convert';

import 'package:test/test.dart';

import '../helpers/cli_runner.dart';
import '../helpers/temp_dir.dart';

void main() {
  test('ir prints the IR of clients as JSON and is hidden', () async {
    final dir = TempDir();
    dir.write('api.yaml', '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /pets:
    get:
      operationId: listPets
      tags: [pets]
      responses: {"204": {description: ok}}
''');
    final path = dir.write(
      'typed_openapi.yaml',
      'clients:\n  api: {input: api.yaml, output: lib/api}\n',
    );
    final ir = await CliRunner.run([
      'ir',
      '-c',
      path,
    ], workingDirectory: dir.path);
    expect(ir.$1, 0);
    expect(jsonDecode(ir.$2), {
      'api': {
        'declarations': <Object?>[],
        'groups': [
          {
            'name': 'PetsApi',
            'field': 'pets',
            'key': 'Pets',
            'operations': [
              {
                'name': 'listPets',
                'method': 'GET',
                'path': '/pets',
                'at': 'api.yaml#/paths/~1pets/get',
                'parameters': <Object?>[],
                'responses': [
                  {'status': '204', 'kind': 'none'},
                ],
                'errors': 'Never',
                'operationId': 'listPets',
                'tags': ['pets'],
              },
            ],
          },
        ],
        'root': {'name': 'ApiClient', 'servers': <Object?>[]},
      },
    });
    final (_, help, _) = await CliRunner.run(['help']);
    expect(help, isNot(contains(' ir ')));
  });

  group('ir diagnostics', () {
    const spec = '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a: {get: {operationId: same, tags: [a], responses: {"204": {description: ok}}}}
  /b: {get: {operationId: same, tags: [b], responses: {"204": {description: ok}}}}
''';

    test('are printed to stderr and the JSON stays alone on stdout', () async {
      final dir = TempDir();
      dir.write('api.yaml', spec.replaceAll('tags: [b]', 'tags: [a]'));
      final path = dir.write('typed_openapi.yaml', '''
clients:
  api: {input: api.yaml, output: lib/api, naming: {group: Api}}
''');
      final (code, out, err) = await CliRunner.run([
        'ir',
        '-c',
        path,
      ], workingDirectory: dir.path);
      // The invalid config and the duplicate operationId are errors, as in
      // `check`.
      expect(code, 1);
      expect(jsonDecode(out), contains('api'));
      expect(err, contains('error TOA902 config-invalid'));
      expect(err, contains('error TOA504 duplicate-operation-id'));
      // The info is counted, not listed.
      expect(err, isNot(contains('TOA551')));
      expect(err, contains('errors: 2, warnings: 0, infos: 1'));
      expect(
        err,
        endsWith('1 info diagnostic not shown; run `check` to see it.\n'),
      );
      final (checkCode, checkOut, _) = await CliRunner.run([
        'check',
        '-c',
        path,
      ], workingDirectory: dir.path);
      expect(checkCode, code);
      expect(checkOut, contains('info TOA551 name-collision'));
      expect(checkOut, contains('error TOA504 duplicate-operation-id'));
    });

    test(
      'give the exit code check gives, levels and baseline included',
      () async {
        final dir = TempDir();
        dir.write('api.yaml', spec);
        final path = dir.write('typed_openapi.yaml', '''
clients:
  api:
    input: api.yaml
    output: lib/api
    severity: {duplicate-operation-id: warning}
''');
        final (code, out, err) = await CliRunner.run([
          'ir',
          '-c',
          path,
        ], workingDirectory: dir.path);
        expect(code, 0);
        expect(jsonDecode(out), contains('api'));
        expect(err, contains('warning TOA504 duplicate-operation-id'));
      },
    );

    test('a clean run prints nothing to stderr', () async {
      final dir = TempDir();
      dir.write(
        'api.yaml',
        spec.replaceAll('same', 'one').replaceFirst('one', 'two'),
      );
      final path = dir.write(
        'typed_openapi.yaml',
        'clients:\n  api: {input: api.yaml, output: lib/api}\n',
      );
      final (code, out, err) = await CliRunner.run([
        'ir',
        '-c',
        path,
      ], workingDirectory: dir.path);
      expect(code, 0);
      expect(jsonDecode(out), contains('api'));
      expect(err, isEmpty);
    });

    test(
      'infos alone are counted, not listed, and the exit code is 0',
      () async {
        final dir = TempDir();
        dir.write('api.yaml', '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a: {get: {operationId: one, tags: [a, b], responses: {"204": {description: ok}}}}
''');
        final path = dir.write(
          'typed_openapi.yaml',
          'clients:\n  api: {input: api.yaml, output: lib/api}\n',
        );
        final (code, out, err) = await CliRunner.run([
          'ir',
          '-c',
          path,
        ], workingDirectory: dir.path);
        expect(code, 0);
        expect(jsonDecode(out), contains('api'));
        expect(
          err,
          'errors: 0, warnings: 0, infos: 1\n'
          '1 info diagnostic not shown; run `check` to see it.\n',
        );
      },
    );

    test('an unreadable spec says so on stderr', () async {
      final dir = TempDir();
      final path = dir.write(
        'typed_openapi.yaml',
        'clients:\n  broken: {input: missing.yaml, output: lib/b}\n',
      );
      final (code, out, err) = await CliRunner.run([
        'ir',
        '-c',
        path,
      ], workingDirectory: dir.path);
      expect(code, 1);
      expect(jsonDecode(out), {'broken': null});
      expect(err, contains('error TOA004'));
      expect(err, contains('Client broken has no IR'));
    });

    test(
      'a config that cannot be loaded goes to stderr, stdout is empty',
      () async {
        final dir = TempDir();
        final (code, out, err) = await CliRunner.run([
          'ir',
          '-c',
          'missing.yaml',
        ], workingDirectory: dir.path);
        expect(code, 78);
        expect(out, isEmpty);
        expect(err, contains('TOA901'));
      },
    );
  });
}
