@TestOn('vm')
library;

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/fuzz/fuzz_run.dart';
import 'package:typed_openapi_tool/src/fuzz/fuzz_spec.dart';
import 'package:typed_openapi_tool/src/fuzz/literal_check.dart';

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

  test('a few seeds build, analyze and keep their literals', () async {
    final temp = TempDir();
    final log = StringBuffer();
    final report = await FuzzRun(
      work: p.join(temp.path, 'fuzz'),
      runtime: p.normalize(p.absolute(p.join('..', 'typed_openapi_runtime'))),
      log: log,
      sampleEvery: 2,
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
}
