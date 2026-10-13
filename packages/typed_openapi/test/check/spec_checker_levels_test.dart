import 'package:test/test.dart';
import 'package:typed_openapi/src/check/spec_checker.dart';
import 'package:typed_openapi/src/config/config_loader.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/display_paths.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';

import '../helpers/temp_dir.dart';

void main() {
  test("gives each client's diagnostics its levels", () {
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
  a: {input: shared.yaml, output: lib/a, severity: {bool-required: error}}
  b: {input: shared.yaml, output: lib/b, severity: {bool-required: off}}
  c: {input: shared.yaml, output: lib/c}
''');
    final bag = DiagnosticBag();
    SpecChecker(
      bag,
      DisplayPaths(dir.path),
    ).check(ConfigLoader(bag).load(path)!);
    // One run: a raises the finding, b turns it off, c keeps the default.
    expect(bag.all.map((d) => (d.code, d.severity)), [
      (DiagnosticCode.boolRequired, Severity.error),
      (DiagnosticCode.boolRequired, Severity.warning),
    ]);
    expect(bag.hasErrors, isTrue);
  });

  test('a code turned off leaves nothing in the report', () {
    final dir = TempDir();
    dir.write('api.yaml', '''
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
defaults: {severity: {TOA201: off}}
clients:
  api: {input: api.yaml, output: lib/api}
''');
    final bag = DiagnosticBag();
    SpecChecker(
      bag,
      DisplayPaths(dir.path),
    ).check(ConfigLoader(bag).load(path)!);
    expect(bag.all, isEmpty);
  });

  test('clients with different presets keep both hints on a shared '
      'finding', () {
    final dir = TempDir();
    dir.write('api.yaml', '''
openapi: 3.0.3
info: {title: t, version: "1"}
components: {schemas: {Kind: {type: string, enum: [a, a]}}}
''');
    final path = dir.write('typed_openapi.yaml', '''
clients:
  a: {input: api.yaml, output: lib/a}
  b: {input: api.yaml, output: lib/b, preset: nestjs}
''');
    final bag = DiagnosticBag();
    SpecChecker(
      bag,
      DisplayPaths(dir.path),
    ).check(ConfigLoader(bag).load(path)!);
    final finding = bag.all.single;
    expect(finding.code, DiagnosticCode.duplicateEnumValue);
    expect(finding.fix, contains('In NestJS, give the enum its own schema'));
    expect(finding.fix, isNot(contains('nestjs:')));
  });

  test('hints of several presets are named by their preset', () {
    final dir = TempDir();
    dir.write('api.yaml', '''
openapi: 3.0.3
info: {title: t, version: "1"}
paths:
  /a: {get: {operationId: same, tags: [a], responses: {'200': {description: ok}}}}
  /b: {get: {operationId: same, tags: [b], responses: {'200': {description: ok}}}}
''');
    final path = dir.write('typed_openapi.yaml', '''
clients:
  a: {input: api.yaml, output: lib/a, preset: nestjs}
  b: {input: api.yaml, output: lib/b, preset: fastapi}
''');
    final bag = DiagnosticBag();
    SpecChecker(
      bag,
      DisplayPaths(dir.path),
    ).check(ConfigLoader(bag).load(path)!);
    final finding = bag.all.single;
    expect(finding.code, DiagnosticCode.duplicateOperationId);
    expect(
      finding.fix,
      'Give each operation its own operationId at the source. To generate '
      "anyway, lower TOA504 in the client's severity and pin the second "
      "method's name with an override. nestjs: In NestJS, set "
      '`operationIdFactory` in SwaggerModule.createDocument (the default is '
      'controllerKey_methodKey). fastapi: In FastAPI, pass '
      '`generate_unique_id_function` to FastAPI(...).',
    );
  });
}
