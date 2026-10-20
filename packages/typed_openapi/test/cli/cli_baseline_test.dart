import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

import '../helpers/cli_runner.dart';

void main() {
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
        CliRunner.run([...args, '-c', config], workingDirectory: dir.path);

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
        final (code, out, _) = await CliRunner.run([
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
        final (code, out, err) = await CliRunner.run([
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
      final (code, _, err) = await CliRunner.run([
        'baseline',
        'create',
        '-c',
        path,
      ], workingDirectory: dir.path);
      expect(code, 64);
      expect(err, contains('No client has a "baseline" in the config.'));
    });
  });
}
