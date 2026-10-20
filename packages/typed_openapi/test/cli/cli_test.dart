import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

import '../helpers/cli_runner.dart';

void main() {
  late String configPath;
  late String workingDirectory;

  setUp(() {
    final dir = TempDir();
    workingDirectory = dir.path;
    dir.write(
      'specs/ok.yaml',
      'openapi: 3.1.0\ninfo: {title: ok, version: "1"}\n',
    );
    dir.write('specs/old.json', '{\n  "swagger": "2.0"\n}');
    configPath = dir.write('typed_openapi.yaml', '''
clients:
  ok: {input: specs/ok.yaml, output: lib/ok}
  old: {input: specs/old.json, output: lib/old}
''');
  });

  test('exits 0 when the named client is clean', () async {
    final (code, out, _) = await CliRunner.run([
      'check',
      '-c',
      configPath,
      'ok',
    ]);
    expect(code, 0);
    expect(out.trim(), 'errors: 0, warnings: 0, infos: 0');
  });

  test('exits 1 and prints the location when a spec has errors', () async {
    final (code, out, _) = await CliRunner.run([
      'check',
      '--config',
      configPath,
    ], workingDirectory: workingDirectory);
    expect(code, 1);
    expect(out, contains('error TOA011 unsupported-openapi-version'));
    expect(out, contains('  --> specs/old.json:2:14'));
  });

  test('prints JSON with --format json', () async {
    final (_, out, _) = await CliRunner.run([
      'check',
      '-c',
      configPath,
      '--format',
      'json',
    ]);
    final json = jsonDecode(out) as Map<String, Object?>;
    expect(json['summary'], {
      'error': 1,
      'warning': 0,
      'info': 0,
      'baselined': 0,
    });
  });

  test('prints SARIF and GitHub Actions annotations', () async {
    final (sarifCode, sarif, _) = await CliRunner.run([
      'check',
      '-c',
      configPath,
      '--format',
      'sarif',
    ], workingDirectory: workingDirectory);
    expect(sarifCode, 1);
    expect(sarif, contains('"uri": "specs/old.json"'));
    final (code, out, _) = await CliRunner.run([
      'check',
      '-c',
      configPath,
      '--format',
      'github-actions',
    ], workingDirectory: workingDirectory);
    expect(code, 1);
    expect(
      out,
      startsWith(
        '::error file=specs/old.json,line=2,col=14,endLine=2,endColumn=19,'
        'title=TOA011 unsupported-openapi-version::',
      ),
    );
  });

  test('exits 78 when the config file is missing', () async {
    final (code, out, _) = await CliRunner.run([
      'check',
      '-c',
      '/nope/typed_openapi.yaml',
    ]);
    expect(code, 78);
    expect(out, contains('TOA901 config-not-found'));
  });

  test('reads a relative config path from the working directory', () async {
    final (code, out, _) = await CliRunner.run([
      'check',
      '-c',
      'typed_openapi.yaml',
      'ok',
    ], workingDirectory: workingDirectory);
    expect(code, 0);
    expect(out.trim(), 'errors: 0, warnings: 0, infos: 0');
  });

  test('names the missing config relative to the working directory', () async {
    final (code, out, _) = await CliRunner.run([
      'check',
      '-c',
      'nope.yaml',
    ], workingDirectory: workingDirectory);
    expect(code, 78);
    expect(out, contains('Config file nope.yaml does not exist.'));
    expect(out, contains('  --> nope.yaml\n'));
  });

  test('exits 64 on an unknown client', () async {
    final (code, _, err) = await CliRunner.run([
      'check',
      '-c',
      configPath,
      'nope',
    ]);
    expect(code, 64);
    expect(err, contains('Unknown client: nope.'));
  });

  test('prints the config error for a declared but invalid client', () async {
    final dir = TempDir();
    dir.write('ok.yaml', 'openapi: 3.1.0\n');
    final path = dir.write('typed_openapi.yaml', '''
clients:
  broken: {output: lib/broken}
  ok: {input: ok.yaml, output: lib/ok}
''');
    final (code, out, err) = await CliRunner.run([
      'check',
      '-c',
      path,
      'broken',
    ]);
    expect(code, 1);
    expect(out, contains('TOA902'));
    expect(err, isEmpty);
  });

  test('reports stale, redundant and conflicting overrides', () async {
    final dir = TempDir();
    dir.write('api.yaml', '''
openapi: 3.0.3
info: {title: api, version: "1"}
paths:
  /pets/{id}:
    get:
      operationId: getPet
      tags: [pets]
      parameters:
        - {name: id, in: path, required: true, schema: {type: string}}
      responses: {'200': {description: ok}}
components:
  schemas:
    Pet: {type: object, format: binary}
''');
    dir.write('api.overrides.yaml', '''
operations:
  getPet: {name: fetchPet}
  GET /pets/{id}: {name: loadPet}
  deletePet:
    reason: removed in v2
    exclude: true
schemas:
  Pet: {type: string, nullable: false}
''');
    final path = dir.write('typed_openapi.yaml', '''
clients:
  api: {input: api.yaml, output: lib/api, overrides: api.overrides.yaml}
''');
    final (code, out, _) = await CliRunner.run([
      'check',
      '-c',
      path,
    ], workingDirectory: dir.path);
    expect(code, 1);
    expect(
      out,
      'error TOA806 override-conflict: This override and the one at '
      '#/operations/GET ~1pets~1{id} name the same node '
      '(#/paths/~1pets~1{id}/get); neither is applied.\n'
      '  --> api.overrides.yaml:2:11\n'
      '  at #/operations/getPet\n'
      '  fix: Merge them into one override.\n'
      'error TOA806 override-conflict: This override and the one at '
      '#/operations/getPet name the same node (#/paths/~1pets~1{id}/get); '
      'neither is applied.\n'
      '  --> api.overrides.yaml:3:19\n'
      '  at #/operations/GET ~1pets~1{id}\n'
      '  fix: Merge them into one override.\n'
      'warning TOA804 override-target-not-found: No operation has '
      'operationId "deletePet". The override is not applied. Reason given: '
      '"removed in v2".\n'
      '  --> api.overrides.yaml:5:5\n'
      '  at #/operations/deletePet\n'
      '  fix: Remove the override, or fix its address.\n'
      'info TOA807 override-unchanged: The spec already has this '
      '"nullable"; the override changes nothing and can be removed.\n'
      '  --> api.overrides.yaml:8:33\n'
      '  at #/schemas/Pet/nullable\n'
      '  fix: Remove "nullable" from the override.\n'
      'errors: 2, warnings: 1, infos: 1\n',
    );
  });

  test('reports broken references in the spec', () async {
    final dir = TempDir();
    dir.write('api.yaml', r'''
openapi: 3.0.0
info: {title: api, version: "1"}
components:
  schemas:
    Owner: {properties: {pet: {$ref: "#/components/schemas/"}}}
''');
    final path = dir.write(
      'typed_openapi.yaml',
      'clients:\n  api: {input: api.yaml, output: lib/api}\n',
    );
    final (code, out, _) = await CliRunner.run(['check', '-c', path]);
    expect(code, 1);
    expect(out, contains('error TOA100 invalid-ref'));
    expect(
      out,
      contains(r'  at #/components/schemas/Owner/properties/pet/$ref'),
    );
  });

  test('a level from the config changes the exit code', () async {
    final dir = TempDir();
    dir.write('api.yaml', '''
openapi: 3.0.3
info: {title: api, version: "1"}
paths:
  /a: {get: {operationId: same, tags: [a], responses: {'200': {description: ok}}}}
  /b: {get: {operationId: same, tags: [b], responses: {'200': {description: ok}}}}
''');
    final path = dir.write('typed_openapi.yaml', '''
clients:
  api:
    input: api.yaml
    output: lib/api
    severity: {duplicate-operation-id: warning}
''');
    final (code, out, _) = await CliRunner.run([
      'check',
      '-c',
      path,
    ], workingDirectory: dir.path);
    expect(code, 0);
    expect(out, contains('warning TOA504 duplicate-operation-id'));
    expect(out, endsWith('errors: 0, warnings: 1, infos: 0\n'));
  });

  test('a problem an override introduces names the override', () async {
    final dir = TempDir();
    dir.write('api.yaml', '''
openapi: 3.0.3
info: {title: api, version: "1"}
paths: {}
components:
  schemas:
    Pet: {type: object}
''');
    dir.write('api.overrides.yaml', 'schemas:\n  Pet: {format: binary}\n');
    final path = dir.write('typed_openapi.yaml', '''
clients:
  api: {input: api.yaml, output: lib/api, overrides: api.overrides.yaml}
''');
    final (code, out, _) = await CliRunner.run([
      'check',
      '-c',
      path,
    ], workingDirectory: dir.path);
    expect(code, 0);
    expect(
      out,
      contains(
        '  at #/components/schemas/Pet/type\n'
        '  fix: ',
      ),
    );
    expect(
      out,
      contains(
        '  related: Introduced by this override.\n'
        '    --> api.overrides.yaml:2:17\n'
        '    at #/schemas/Pet/format\n',
      ),
    );
  });
}
