@TestOn('vm')
library;

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/fuzz/fuzz_build.dart';
import 'package:typed_openapi_tool/src/fuzz/fuzz_run.dart';
import 'package:typed_openapi_tool/src/fuzz/fuzz_spec.dart';
import 'package:typed_openapi_tool/src/fuzz/literal_check.dart';
import 'package:typed_openapi_tool/src/fuzz/seed_builds.dart';

import '../helpers/temp_dir.dart';

void main() {
  test('a seed always gives the same spec, and hostile strings', () {
    const spec = FuzzSpec();
    expect(spec.of(7).spec, spec.of(7).spec);
    expect(spec.of(7).spec, isNot(spec.of(8).spec));
    final all = [for (var seed = 0; seed < 20; seed++) spec.of(seed).spec];
    for (final name in ["it's", r'$cost', '*/ name']) {
      expect(all.join(), contains(name), reason: name);
    }
  });

  test('the specs reach every kind of sink', () {
    const spec = FuzzSpec();
    final all = [for (var seed = 0; seed < 60; seed++) spec.of(seed).spec];
    final joined = all.join();
    for (final key in [
      '"servers"',
      '"variables"',
      '"securitySchemes"',
      '"security"',
      '"summary"',
      '"default"',
      '"x-enum-varnames"',
      '"mapping"',
    ]) {
      expect(joined, contains(key), reason: key);
    }
  });

  test('a few seeds build, analyze and keep their literals', () async {
    final temp = TempDir();
    final log = StringBuffer();
    final report = await FuzzRun(
      work: p.join(temp.path, 'fuzz'),
      runtime: p.normalize(p.absolute(p.join('..', 'typed_openapi_runtime'))),
      log: log,
      sampleEvery: 2,
      fetchesPackages: false,
    ).run(from: 0, count: 4);
    expect(report.failures, isEmpty);
    expect(report.builds, greaterThan(0));
    expect(report.sampled, greaterThan(0));
    expect('$log', isEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('successive samples cover every client', () {
    final clients = {
      for (var seed = 0; seed < 72; seed += 12) FuzzRun.sampledClient(seed, 12),
    };
    expect(clients, hasLength(6));
    expect(clients.where((c) => c.endsWith('_structural')), hasLength(3));
  });

  test('a spec string that no literal holds is reported', () async {
    final temp = TempDir()
      ..write('pubspec.yaml', 'name: sample\nenvironment:\n  sdk: ^3.10.0\n')
      ..write('lib/s1/a.dart', "const a = 'it\\'s';\n");
    final failures = await LiteralCheck(temp.path).run({
      's1': ["it's", r'$cost'],
    });
    expect(failures, [r's1: the spec string "$cost" is in no literal.']);
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('a run that built nothing fails', () async {
    final temp = TempDir();
    final report = await FuzzRun(
      work: p.join(temp.path, 'fuzz'),
      runtime: p.normalize(p.absolute(p.join('..', 'typed_openapi_runtime'))),
      log: StringBuffer(),
      fetchesPackages: false,
    ).run(from: 0, count: 0);
    expect(report.failures, ['The fuzz built no client.']);
  });

  test(
    'a string that is in fewer literals than the spec holds it fails',
    () async {
      final temp = TempDir()
        ..write('pubspec.yaml', 'name: sample\nenvironment:\n  sdk: ^3.10.0\n')
        ..write('lib/s1/a.dart', "const a = 'kind';\n");
      final failures = await LiteralCheck(temp.path).run({
        's1': ['kind', 'kind'],
      });
      expect(failures, ['s1: the spec string "kind" is in 1 literals, not 2.']);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  group('a crash of the generator', () {
    FuzzOutput empty() => (files: const {}, irs: const {}, report: '');

    test('on the second build names the seed and the build', () {
      final log = StringBuffer();
      var calls = 0;
      expect(
        () => SeedBuilds(log).twice(5, () {
          if (++calls == 2) throw StateError('boom');
          return empty();
        }),
        throwsStateError,
      );
      expect('$log', 'The generator crashed on the second build of seed 5.\n');
    });

    test('on the first build names the seed and the build', () {
      final log = StringBuffer();
      expect(
        () => SeedBuilds(log).twice(6, () => throw StateError('boom')),
        throwsStateError,
      );
      expect('$log', 'The generator crashed on the first build of seed 6.\n');
    });

    test('is not reported when both builds work', () {
      final log = StringBuffer();
      SeedBuilds(log).twice(7, empty);
      expect('$log', isEmpty);
    });
  });
}
