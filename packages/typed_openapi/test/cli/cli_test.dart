import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/cli/cli.dart';

import '../helpers/temp_dir.dart';

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

  Future<(int, String, String)> run(
    List<String> args, {
    String? workingDirectory,
  }) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await TypedOpenApiCli(
      out: out,
      err: err,
      workingDirectory: workingDirectory,
    ).run(args);
    return (code, out.toString(), err.toString());
  }

  test('exits 0 when the named client is clean', () async {
    final (code, out, _) = await run(['check', '-c', configPath, 'ok']);
    expect(code, 0);
    expect(out.trim(), 'errors: 0, warnings: 0, infos: 0');
  });

  test('exits 1 and prints the location when a spec has errors', () async {
    final (code, out, _) = await run([
      'check',
      '--config',
      configPath,
    ], workingDirectory: workingDirectory);
    expect(code, 1);
    expect(out, contains('error TOA011 unsupported-openapi-version'));
    expect(out, contains('  --> ${p.join('specs', 'old.json')}:2:14'));
  });

  test('prints JSON with --format json', () async {
    final (_, out, _) = await run([
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
    final (sarifCode, sarif, _) = await run([
      'check',
      '-c',
      configPath,
      '--format',
      'sarif',
    ], workingDirectory: workingDirectory);
    expect(sarifCode, 1);
    expect(sarif, contains('"uri": "specs/old.json"'));
    final (code, out, _) = await run([
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
    final (code, out, _) = await run([
      'check',
      '-c',
      '/nope/typed_openapi.yaml',
    ]);
    expect(code, 78);
    expect(out, contains('TOA901 config-not-found'));
  });

  test('reads a relative config path from the working directory', () async {
    final (code, out, _) = await run([
      'check',
      '-c',
      'typed_openapi.yaml',
      'ok',
    ], workingDirectory: workingDirectory);
    expect(code, 0);
    expect(out.trim(), 'errors: 0, warnings: 0, infos: 0');
  });

  test('names the missing config relative to the working directory', () async {
    final (code, out, _) = await run([
      'check',
      '-c',
      'nope.yaml',
    ], workingDirectory: workingDirectory);
    expect(code, 78);
    expect(out, contains('Config file nope.yaml does not exist.'));
    expect(out, contains('  --> nope.yaml\n'));
  });

  test('exits 64 on an unknown client', () async {
    final (code, _, err) = await run(['check', '-c', configPath, 'nope']);
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
    final (code, out, err) = await run(['check', '-c', path, 'broken']);
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
    final (code, out, _) = await run([
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
    final (code, out, _) = await run(['check', '-c', path]);
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
    final (code, out, _) = await run([
      'check',
      '-c',
      path,
    ], workingDirectory: dir.path);
    expect(code, 0);
    expect(out, contains('warning TOA504 duplicate-operation-id'));
    expect(out, endsWith('errors: 0, warnings: 1, infos: 0\n'));
  });

  group('baseline', () {
    const spec = '''
openapi: 3.0.3
info: {title: api, version: "1"}
paths:
  /a: {get: {operationId: same, tags: [a], responses: {'200': {description: ok}}}}
  /b: {get: {operationId: same, tags: [b], responses: {'200': {description: ok}}}}
components:
  schemas:
    Tag:
      type: object
      properties:
        name: {type: string, required: true}
''';
    late TempDir dir;
    late String config;

    setUp(() {
      dir = TempDir();
      dir.write('api.yaml', spec);
      config = dir.write('typed_openapi.yaml', '''
clients:
  api: {input: api.yaml, output: lib/api, baseline: api.baseline.yaml}
''');
    });

    Future<(int, String, String)> inDir(List<String> args) =>
        run([...args, '-c', config], workingDirectory: dir.path);

    test('create accepts the current diagnostics; check hides them', () async {
      final (created, createOut, _) = await inDir(['baseline', 'create']);
      expect(created, 0);
      expect(
        createOut,
        'errors: 0, warnings: 0, infos: 0\n'
        'Wrote api.baseline.yaml: 2 entries accept 2 diagnostics.\n',
      );
      expect(
        File(p.join(dir.path, 'api.baseline.yaml')).readAsStringSync(),
        contains('code: "TOA504"'),
      );
      final (code, out, _) = await inDir(['check']);
      expect(code, 0);
      expect(out, 'errors: 0, warnings: 0, infos: 0, baselined: 2\n');
      final (_, shown, _) = await inDir(['check', '--show-baselined']);
      expect(
        shown,
        contains('error TOA504 duplicate-operation-id [baselined]: '),
      );
    });

    test('check fails on a new problem only', () async {
      await inDir(['baseline', 'create']);
      dir.write(
        'api.yaml',
        spec.replaceFirst(
          '/b: {get: {operationId: same, tags: [b]',
          '/b: {get: {operationId: same, tags: [b], parameters: '
              '[{name: x, in: path}]',
        ),
      );
      final (code, out, _) = await inDir(['check']);
      expect(code, 1);
      expect(out, contains('error TOA502 path-parameter-not-in-template'));
      expect(out, isNot(contains('TOA504')));
      expect(out, endsWith('baselined: 2\n'));
    });

    test('a fixed problem leaves a stale entry; prune removes it', () async {
      await inDir(['baseline', 'create']);
      dir.write('api.yaml', spec.replaceFirst('required: true', 'x: 1'));
      final (code, out, _) = await inDir(['check']);
      expect(code, 0);
      expect(
        out,
        contains(
          'warning TOA822 baseline-entry-stale: No diagnostic matches this '
          'entry (TOA201 at @/schemas/Tag/properties/name#/required); the '
          'problem is gone.\n'
          '  --> api.baseline.yaml:',
        ),
      );
      expect(out, contains('  fix: Run `typed_openapi baseline prune`'));
      final (strict, _, _) = await inDir(['check', '--strict-baseline']);
      expect(strict, 1);
      final (pruned, pruneOut, _) = await inDir(['baseline', 'prune']);
      expect(pruned, 0);
      expect(
        pruneOut,
        contains('Pruned api.baseline.yaml: removed 1 entries, 1 left.'),
      );
      final (after, afterOut, _) = await inDir(['check']);
      expect(after, 0);
      expect(afterOut, contains('baselined: 1\n'));
      expect(afterOut, isNot(contains('TOA822')));
    });

    test('a missing baseline file is an error and hides nothing', () async {
      final (code, out, _) = await inDir(['check']);
      expect(code, 1);
      expect(out, contains('error TOA820 baseline-not-found'));
      expect(out, contains('error TOA504 duplicate-operation-id'));
    });

    test('prune reports a missing baseline file', () async {
      final (code, out, _) = await inDir(['baseline', 'prune']);
      expect(code, 1);
      expect(out, contains('error TOA820 baseline-not-found'));
    });

    test('write leaves no temporary file behind', () async {
      await inDir(['baseline', 'create']);
      await inDir(['baseline', 'prune']);
      expect(
        Directory(dir.path).listSync().where((e) => e.path.endsWith('.tmp')),
        isEmpty,
      );
    });

    for (final (label, breakSpec) in <(String, void Function(File))>[
      ('a broken', (f) => f.writeAsStringSync('openapi: [3\n')),
      ('a deleted', (f) => f.deleteSync()),
    ]) {
      group('$label spec', () {
        late String before;

        setUp(() async {
          await inDir(['baseline', 'create']);
          before = File(
            p.join(dir.path, 'api.baseline.yaml'),
          ).readAsStringSync();
          breakSpec(File(p.join(dir.path, 'api.yaml')));
        });

        for (final command in ['create', 'prune']) {
          test('keeps the baseline on baseline $command', () async {
            final (code, out, _) = await inDir(['baseline', command]);
            expect(code, 1);
            expect(out, contains('error TOA'));
            expect(out, isNot(contains('Wrote')));
            expect(out, isNot(contains('Pruned')));
            expect(
              File(p.join(dir.path, 'api.baseline.yaml')).readAsStringSync(),
              before,
            );
          });
        }

        test('check shows the read error, not stale entries', () async {
          final (code, out, _) = await inDir(['check']);
          expect(code, 1);
          expect(out, contains('error TOA'));
          expect(out, isNot(contains('TOA822')));
        });
      });
    }

    group('a file the spec references', () {
      String baselineText() =>
          File(p.join(dir.path, 'api.baseline.yaml')).readAsStringSync();

      setUp(() {
        dir.write('shared.yaml', '''
Tag:
  type: object
  properties:
    name: {type: string, required: true}
''');
        dir.write(
          'api.yaml',
          spec
              .replaceFirst(
                'components:',
                'components:\n  schemas:\n    Ref: {\$ref: "shared.yaml#/Tag"}',
              )
              .replaceFirst('  schemas:\n    Tag:', '    Tag:'),
        );
      });

      test('that is gone is a read error: the baseline is kept', () async {
        final (created, _, _) = await inDir(['baseline', 'create']);
        expect(created, 0);
        final before = baselineText();
        expect(before, contains('@/schemas/Ref/'));
        File(p.join(dir.path, 'shared.yaml')).deleteSync();
        for (final command in ['prune', 'create']) {
          final (code, out, _) = await inDir(['baseline', command]);
          expect(code, 1, reason: command);
          expect(out, contains('error TOA004 input-not-found'));
          expect(out, isNot(contains('Wrote')));
          expect(out, isNot(contains('Pruned')));
          expect(baselineText(), before, reason: command);
        }
        final (code, out, _) = await inDir(['check']);
        expect(code, 1);
        expect(out, contains('error TOA004 input-not-found'));
        expect(out, isNot(contains('TOA822')));
      });

      test('with a missing target is an ordinary problem', () async {
        dir.write(
          'api.yaml',
          File(
            p.join(dir.path, 'api.yaml'),
          ).readAsStringSync().replaceFirst('#/Tag', '#/Nope'),
        );
        final (created, _, _) = await inDir(['baseline', 'create']);
        expect(created, 0);
        expect(baselineText(), contains('code: "TOA101"'));
        final (pruned, out, _) = await inDir(['baseline', 'prune']);
        expect(pruned, 0);
        expect(out, contains('Pruned api.baseline.yaml: removed 0 entries'));
      });
    });

    test('prune keeps a baseline with a rejected entry', () async {
      await inDir(['baseline', 'create']);
      final file = File(p.join(dir.path, 'api.baseline.yaml'));
      file.writeAsStringSync(
        '${file.readAsStringSync()}'
        '  - {fingerprint: "0123456789ab", count: "1"}\n',
      );
      final before = file.readAsStringSync();
      final (code, out, _) = await inDir(['baseline', 'prune']);
      expect(code, 1);
      expect(out, contains('error TOA821 invalid-baseline'));
      expect(out, isNot(contains('Pruned')));
      expect(file.readAsStringSync(), before);
    });

    test('clients that share a baseline file write nothing', () async {
      final shared = dir.write('shared.yaml', '''
clients:
  a: {input: api.yaml, output: lib/a, baseline: one.baseline.yaml}
  b: {input: api.yaml, output: lib/b, baseline: ./one.baseline.yaml}
''');
      for (final command in ['create', 'prune']) {
        final (code, out, _) = await run([
          'baseline',
          command,
          '-c',
          shared,
        ], workingDirectory: dir.path);
        expect(code, 1, reason: command);
        expect(out, contains('error TOA902'));
        expect(out, isNot(contains('Wrote')));
        expect(
          File(p.join(dir.path, 'one.baseline.yaml')).existsSync(),
          isFalse,
        );
      }
    });

    test(
      'an empty baseline path is explained before the usage error',
      () async {
        final path = dir.write(
          'empty.yaml',
          'clients:\n  api: {input: api.yaml, output: lib/api, baseline: ""}\n',
        );
        final (code, out, err) = await run([
          'baseline',
          'create',
          '-c',
          path,
        ], workingDirectory: dir.path);
        expect(code, 64);
        expect(out, contains('error TOA902'));
        expect(err, contains('No client has a "baseline" in the config.'));
      },
    );

    test('a client without a baseline is a usage error', () async {
      final path = dir.write(
        'other.yaml',
        'clients:\n  api: {input: api.yaml, output: lib/api}\n',
      );
      final (code, _, err) = await run([
        'baseline',
        'create',
        '-c',
        path,
      ], workingDirectory: dir.path);
      expect(code, 64);
      expect(err, contains('No client has a "baseline" in the config.'));
    });
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
    final (code, out, _) = await run([
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
    final (code, out, _) = await run([
      'ir',
      '-c',
      path,
    ], workingDirectory: dir.path);
    expect(code, 0);
    expect(jsonDecode(out), {
      'api': {
        'declarations': <Object?>[],
        'groups': [
          {
            'name': 'PetsApi',
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
              },
            ],
          },
        ],
      },
    });
    final (_, help, _) = await run(['help']);
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
      final (code, out, err) = await run([
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
      expect(err, contains('errors: 2, warnings: 0, infos: 1'));
      final (checkCode, checkOut, _) = await run([
        'check',
        '-c',
        path,
      ], workingDirectory: dir.path);
      expect(checkCode, code);
      expect(checkOut, err);
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
        final (code, out, err) = await run([
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
      final (code, out, err) = await run([
        'ir',
        '-c',
        path,
      ], workingDirectory: dir.path);
      expect(code, 0);
      expect(jsonDecode(out), contains('api'));
      expect(err, isEmpty);
    });

    test('an unreadable spec says so on stderr', () async {
      final dir = TempDir();
      final path = dir.write(
        'typed_openapi.yaml',
        'clients:\n  broken: {input: missing.yaml, output: lib/b}\n',
      );
      final (code, out, err) = await run([
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
        final (code, out, err) = await run([
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
