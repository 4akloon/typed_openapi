import 'package:test/test.dart';
import 'package:typed_openapi/src/check/spec_checker.dart';
import 'package:typed_openapi/src/config/config_loader.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';

import '../helpers/temp_dir.dart';

void main() {
  test('checks every client and names files relative to the config', () {
    final dir = TempDir();
    dir.write('specs/ok.yaml', 'openapi: 3.0.3\n');
    dir.write('specs/old.json', '{"swagger": "2.0"}');
    final path = dir.write('typed_openapi.yaml', '''
clients:
  ok: {input: specs/ok.yaml, output: lib/ok}
  old: {input: specs/old.json, output: lib/old}
  missing: {input: specs/missing.yaml, output: lib/missing}
''');
    final bag = DiagnosticBag();
    final config = ConfigLoader(bag).load(path)!;
    SpecChecker(bag).check(config);
    expect(
      bag.all.map((d) => (d.code, d.file)),
      unorderedEquals([
        (DiagnosticCode.inputNotFound, 'specs/missing.yaml'),
        (DiagnosticCode.unsupportedOpenApiVersion, 'specs/old.json'),
      ]),
    );
  });

  test('only checks the named clients', () {
    final dir = TempDir();
    final path = dir.write('typed_openapi.yaml', '''
clients:
  a: {input: a.yaml, output: lib/a}
  b: {input: b.yaml, output: lib/b}
''');
    final bag = DiagnosticBag();
    final config = ConfigLoader(bag).load(path)!;
    SpecChecker(bag).check(config, only: {'a'});
    expect(bag.all.single.file, 'a.yaml');
  });

  test('checks a spec shared by several clients once', () {
    final dir = TempDir();
    dir.write('shared.json', '{"swagger": "2.0"}');
    final path = dir.write('typed_openapi.yaml', '''
clients:
  a: {input: shared.json, output: lib/a}
  b: {input: shared.json, output: lib/b}
''');
    final bag = DiagnosticBag();
    final config = ConfigLoader(bag).load(path)!;
    SpecChecker(bag).check(config);
    expect(bag.all.single.code, DiagnosticCode.unsupportedOpenApiVersion);
  });
}
