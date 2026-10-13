import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/fuzz/fuzz_build.dart';
import 'package:typed_openapi_tool/src/fuzz/seed_checks.dart';

FuzzOutput _output(
  Map<String, Map<String, String>> files, [
  String report = '',
]) => (files: files, irs: const {}, report: report);

void main() {
  const checks = SeedChecks();
  final one = _output({
    'c': {'a.dart': 'const a = 1;\n'},
  });

  test('equal builds have no problem', () {
    expect(checks.of(1, one, one), isEmpty);
  });

  test('builds with different files are not deterministic', () {
    final other = _output({
      'c': {'a.dart': 'const a = 2;\n'},
    });
    expect(checks.of(1, one, other), ['seed 1: c is not deterministic.']);
  });

  test('a client that only one build has is not deterministic', () {
    expect(checks.of(2, one, _output({})), ['seed 2: c is not deterministic.']);
    expect(checks.of(2, _output({}), one), ['seed 2: c is not deterministic.']);
  });

  test('a leaking file is reported with the seed and the client', () {
    final leaking = _output({
      'c': {'a.dart': '/// x */\ninjected();\n'},
    });
    expect(checks.of(3, leaking, leaking), [
      'seed 3 c/a.dart: spec text left its sink: injected();',
    ]);
  });

  test('a leaking text report is reported with the seed', () {
    final leaking = _output(const {}, 'error - a\x1b[31m');
    expect(checks.of(4, leaking, leaking), [
      'seed 4: The report holds a raw U+001B.',
    ]);
  });
}
