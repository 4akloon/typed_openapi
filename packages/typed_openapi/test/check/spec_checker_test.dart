import 'package:test/test.dart';
import 'package:typed_openapi/src/check/spec_checker.dart';
import 'package:typed_openapi/src/config/config_loader.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';

import '../helpers/temp_dir.dart';

void main() {
  test('checks every client and names files relative to the config', () {
    final dir = TempDir();
    dir.write(
      'specs/ok.yaml',
      'openapi: 3.0.3\ninfo: {title: ok, version: "1"}\npaths: {}\n',
    );
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

  test('reads each spec into the model and follows its references', () {
    final dir = TempDir();
    dir.write('specs/api.yaml', r'''
openapi: 3.0.3
info: {title: api}
paths:
  /pets:
    get:
      responses:
        "200": {$ref: "common.yaml#/components/responses/Missing"}
''');
    dir.write('specs/common.yaml', 'components: {responses: {}}\n');
    final path = dir.write('typed_openapi.yaml', '''
clients:
  api: {input: specs/api.yaml, output: lib/api}
''');
    final bag = DiagnosticBag();
    final config = ConfigLoader(bag).load(path)!;
    SpecChecker(bag).check(config);
    expect(
      bag.sorted.map((d) => (d.code, d.file, d.pointer?.value)),
      [
        (DiagnosticCode.missingRequiredField, 'specs/api.yaml', '#/info'),
        (
          DiagnosticCode.unresolvedRef,
          'specs/api.yaml',
          r'#/paths/~1pets/get/responses/200/$ref',
        ),
      ],
    );
  });

  test('reports the dialect of a spec against its declared version', () {
    final dir = TempDir();
    dir.write('api.json', '''
{
  "openapi": "3.1.0",
  "info": {"title": "api", "version": "1"},
  "components": {"schemas": {"A": {"type": "string", "nullable": true}}}
}
''');
    final path = dir.write(
      'typed_openapi.yaml',
      'clients:\n  api: {input: api.json, output: lib/api}\n',
    );
    final bag = DiagnosticBag();
    SpecChecker(bag).check(ConfigLoader(bag).load(path)!);
    expect(bag.all.single.code, DiagnosticCode.nullableAfterOpenApi30);
  });

  test('does not read a spec whose version it cannot detect', () {
    final dir = TempDir();
    dir.write('api.yaml', 'info: {title: 5}\nnmae: x\n');
    final path = dir.write(
      'typed_openapi.yaml',
      'clients:\n  api: {input: api.yaml, output: lib/api}\n',
    );
    final bag = DiagnosticBag();
    SpecChecker(bag).check(ConfigLoader(bag).load(path)!);
    expect(bag.all.single.code, DiagnosticCode.missingOpenApiVersion);
  });
}
