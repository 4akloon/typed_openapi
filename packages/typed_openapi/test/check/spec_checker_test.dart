import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/check/spec_checker.dart';
import 'package:typed_openapi/src/config/config_loader.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/display_paths.dart';

import '../helpers/temp_dir.dart';

void main() {
  test('checks every client and names files relative to the working '
      'directory', () {
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
    SpecChecker(bag, DisplayPaths(dir.path)).check(config);
    expect(
      bag.all.map((d) => (d.code, d.file)),
      unorderedEquals([
        (DiagnosticCode.inputNotFound, 'specs/missing.yaml'),
        (DiagnosticCode.unsupportedOpenApiVersion, 'specs/old.json'),
      ]),
    );
  });

  test('normalizes each spec with the client\'s rules', () {
    final dir = TempDir();
    const spec = '''
openapi: 3.0.3
info: {title: t, version: "1"}
components:
  schemas:
    Tag:
      type: object
      properties:
        name: {type: string, required: true}
''';
    dir.write('a.yaml', spec);
    dir.write('b.yaml', spec);
    final path = dir.write('typed_openapi.yaml', '''
clients:
  a: {input: a.yaml, output: lib/a}
  b:
    input: b.yaml
    output: lib/b
    rules: {bool-required-to-array: false}
''');
    final bag = DiagnosticBag();
    SpecChecker(
      bag,
      DisplayPaths(dir.path),
    ).check(ConfigLoader(bag).load(path)!);
    expect(bag.all.map((d) => (d.code, d.file)), [
      (DiagnosticCode.boolRequired, 'a.yaml'),
      (DiagnosticCode.invalidValue, 'b.yaml'),
    ]);
  });

  test("applies each client's overrides before the rules", () {
    final dir = TempDir();
    const spec = '''
openapi: 3.0.3
info: {title: t, version: "1"}
paths: {}
components:
  schemas:
    File: {type: object, format: binary}
''';
    dir.write('specs/api.yaml', spec);
    dir.write('specs/api.overrides.yaml', 'schemas: {File: {type: string}}\n');
    final path = dir.write('typed_openapi.yaml', '''
clients:
  fixed:
    input: specs/api.yaml
    output: lib/fixed
    overrides: specs/api.overrides.yaml
  plain: {input: specs/api.yaml, output: lib/plain}
  broken:
    input: specs/api.yaml
    output: lib/broken
    overrides: specs/missing.yaml
''');
    final bag = DiagnosticBag();
    SpecChecker(
      bag,
      DisplayPaths(dir.path),
    ).check(ConfigLoader(bag).load(path)!);
    expect(
      bag.all.map((d) => (d.code, d.file)),
      unorderedEquals([
        (DiagnosticCode.overridesNotFound, 'specs/missing.yaml'),
        (DiagnosticCode.binaryObject, 'specs/api.yaml'),
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
    SpecChecker(bag, DisplayPaths(dir.path)).check(config, only: {'a'});
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
    SpecChecker(bag, DisplayPaths(dir.path)).check(config);
    expect(bag.all.single.code, DiagnosticCode.unsupportedOpenApiVersion);
  });

  test('a shared spec is checked once per preset and rule set', () {
    final dir = TempDir();
    dir.write('shared.yaml', '''
openapi: 3.0.3
info: {title: t, version: "1"}
components:
  schemas:
    Tag:
      type: object
      properties:
        name: {type: string, required: true}
''');
    final path = dir.write('typed_openapi.yaml', '''
clients:
  a: {input: shared.yaml, output: lib/a}
  b:
    input: shared.yaml
    output: lib/b
    rules: {bool-required-to-array: false}
  c: {input: shared.yaml, output: lib/c}
''');
    final bag = DiagnosticBag();
    SpecChecker(
      bag,
      DisplayPaths(dir.path),
    ).check(ConfigLoader(bag).load(path)!);
    // a and c share one run (TOA201); b runs without the fix (TOA111).
    expect(bag.all.map((d) => d.code), [
      DiagnosticCode.boolRequired,
      DiagnosticCode.invalidValue,
    ]);
  });

  test('reads each spec into the model and follows its references', () {
    final dir = TempDir();
    dir.write('specs/api.yaml', r'''
openapi: 3.0.3
info: {title: api}
paths:
  /pets:
    get:
      operationId: listPets
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
    SpecChecker(bag, DisplayPaths(dir.path)).check(config);
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

  test('a side file shared by two clients is reported once', () {
    final dir = TempDir();
    const spec = r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components: {schemas: {E: {$ref: "common.yaml#/Err"}}}
''';
    dir.write('a.yaml', spec);
    dir.write('b.yaml', spec);
    dir.write('common.yaml', 'Err: {type: object, bogus: 1}\n');
    final path = dir.write('typed_openapi.yaml', '''
clients:
  a: {input: a.yaml, output: lib/a}
  b: {input: b.yaml, output: lib/b}
''');
    final bag = DiagnosticBag();
    SpecChecker(
      bag,
      DisplayPaths(dir.path),
    ).check(ConfigLoader(bag).load(path)!);
    expect(bag.all.map((d) => (d.code, d.file, d.pointer?.value)), [
      (DiagnosticCode.unknownKey, 'common.yaml', '#/Err/bogus'),
    ]);
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
    SpecChecker(
      bag,
      DisplayPaths(dir.path),
    ).check(ConfigLoader(bag).load(path)!);
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
    SpecChecker(
      bag,
      DisplayPaths(dir.path),
    ).check(ConfigLoader(bag).load(path)!);
    expect(bag.all.single.code, DiagnosticCode.missingOpenApiVersion);
  });

  test('names files by the working directory, not the config', () {
    final dir = TempDir();
    dir.write('specs/api.yaml', r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components: {schemas: {E: {$ref: "common.yaml#/Err"}}}
''');
    dir.write('specs/common.yaml', 'Err: {type: object, bogus: 1}\n');
    final path = dir.write('config/typed_openapi.yaml', '''
clients:
  api: {input: ../specs/api.yaml, output: ../lib/api}
''');
    final bag = DiagnosticBag();
    SpecChecker(
      bag,
      DisplayPaths(dir.path),
    ).check(ConfigLoader(bag).load(path)!);
    expect(bag.all.map((d) => (d.code, d.file)), [
      (DiagnosticCode.unknownKey, p.join('specs', 'common.yaml')),
    ]);
  });

  test('names a file outside the working directory by its absolute path', () {
    final dir = TempDir();
    dir.write('project/api.yaml', r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components: {schemas: {E: {$ref: "../shared/common.yaml#/Err"}}}
''');
    dir.write('shared/common.yaml', 'Err: {type: object, bogus: 1}\n');
    final path = dir.write('project/typed_openapi.yaml', '''
clients:
  api: {input: api.yaml, output: lib/api}
''');
    final bag = DiagnosticBag();
    SpecChecker(
      bag,
      DisplayPaths(p.join(dir.path, 'project')),
    ).check(ConfigLoader(bag).load(path)!);
    expect(bag.all.map((d) => (d.code, d.file)), [
      (
        DiagnosticCode.unknownKey,
        p.normalize(p.join(dir.path, 'shared', 'common.yaml')),
      ),
    ]);
  });
}
