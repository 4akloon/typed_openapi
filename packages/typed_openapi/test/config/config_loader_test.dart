import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/config/config_loader.dart';
import 'package:typed_openapi/src/config/project_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

void main() {
  test('reads clients, inherits defaults and resolves paths', () {
    final dir = TempDir();
    final path = dir.write('typed_openapi.yaml', '''
defaults:
  preset: nestjs
  line_width: 100
clients:
  payments:
    input: specs/payments.yaml
    output: lib/src/api/payments
    preset: fastapi
  core_api:
    input: specs/core_api.json
    output: lib/src/api/core_api
    overrides: specs/core_api.overrides.yaml
''');
    final bag = DiagnosticBag();
    final config = ConfigLoader(bag).load(path)!;
    expect(bag.all, isEmpty);
    expect(config.clients.map((c) => c.name), ['core_api', 'payments']);
    final core = config.clients.first;
    expect(core.input, p.join(dir.path, 'specs', 'core_api.json'));
    expect(core.output, p.join(dir.path, 'lib', 'src', 'api', 'core_api'));
    expect(
      core.overrides,
      p.join(dir.path, 'specs', 'core_api.overrides.yaml'),
    );
    expect(core.preset, Preset.nestjs);
    expect(core.lineWidth, 100);
    expect(config.clients.last.preset, Preset.fastapi);
  });

  test('uses the default line width when none is set', () {
    final dir = TempDir();
    final path = dir.write('c.yaml', '''
clients:
  api: {input: a.json, output: lib/api}
''');
    expect(
      ConfigLoader(DiagnosticBag()).load(path)!.clients.single.lineWidth,
      ClientConfig.defaultLineWidth,
    );
  });

  test('reports a missing config file', () {
    final bag = DiagnosticBag();
    expect(ConfigLoader(bag).load('/nope/typed_openapi.yaml'), isNull);
    expect(bag.all.single.code, DiagnosticCode.configNotFound);
  });

  test('reports a config file that is not UTF-8', () {
    final dir = TempDir();
    final path = p.join(dir.path, 'c.yaml');
    File(path).writeAsBytesSync([0xFF, 0xFE, 0x41]);
    final bag = DiagnosticBag();
    expect(ConfigLoader(bag).load(path), isNull);
    expect(bag.all.single.code, DiagnosticCode.configInvalid);
  });

  test('reports a directory given as the config', () {
    final dir = TempDir();
    final bag = DiagnosticBag();
    expect(ConfigLoader(bag).load(dir.path), isNull);
    expect(bag.all.single.code, DiagnosticCode.configInvalid);
    expect(bag.all.single.message, contains('is a directory'));
  });

  test('reports a config nested too deeply instead of crashing', () {
    final path = TempDir().write(
      'typed_openapi.yaml',
      'clients: ${'[' * 20000}${']' * 20000}\n',
    );
    final bag = DiagnosticBag();
    expect(ConfigLoader(bag).load(path), isNull);
    expect(bag.all.single.code, DiagnosticCode.configInvalid);
    expect(bag.all.single.message, contains('nests deeper'));
  });

  test('rejects a collection as a key without expanding it', () {
    final path = TempDir().write('typed_openapi.yaml', '''
x-list: &l [a, b]
? *l
: v
clients:
  api: {input: a.json, output: lib/api}
''');
    final bag = DiagnosticBag();
    expect(ConfigLoader(bag).load(path)!.clients, hasLength(1));
    final codes = bag.all.map((d) => d.code).toList();
    expect(codes, contains(DiagnosticCode.configInvalid));
    expect(
      bag.all.firstWhere((d) => d.code == DiagnosticCode.configInvalid).message,
      contains('mapping key'),
    );
  });

  test('reports a syntax error with its position', () {
    final path = TempDir().write('c.yaml', 'clients: [a, b\n');
    final bag = DiagnosticBag();
    expect(ConfigLoader(bag).load(path), isNull);
    expect(bag.all.single.code, DiagnosticCode.configInvalid);
    expect(bag.all.single.span, isNotNull);
  });

  test('reads rules from defaults and clients; a client overrides', () {
    final path = TempDir().write('c.yaml', '''
defaults:
  rules: {bool-required-to-array: false, drop-invalid-default: false}
clients:
  a: {input: a.json, output: lib/a}
  b:
    input: b.json
    output: lib/b
    rules: {drop-invalid-default: true}
''');
    final bag = DiagnosticBag();
    final clients = ConfigLoader(bag).load(path)!.clients;
    expect(bag.all, isEmpty);
    expect(clients.first.disabledRules, {
      'bool-required-to-array',
      'drop-invalid-default',
    });
    expect(clients.last.disabledRules, {'bool-required-to-array'});
  });

  test('an unknown rule name is a warning; a value that is not a boolean '
      'is an error', () {
    final path = TempDir().write('c.yaml', '''
clients:
  a:
    input: a.json
    output: lib/a
    rules: {bool-required: false, drop-invalid-default: off}
''');
    final bag = DiagnosticBag();
    expect(ConfigLoader(bag).load(path)!.clients.single.disabledRules, isEmpty);
    expect(bag.all.map((d) => (d.code, d.pointer?.value)), [
      (DiagnosticCode.configUnknownKey, '#/clients/a/rules/bool-required'),
      (DiagnosticCode.configInvalid, '#/clients/a/rules/drop-invalid-default'),
    ]);
    expect(bag.all.first.fix, contains('bool-required-to-array'));
  });

  test('accepts an alias in a value', () {
    final path = TempDir().write('typed_openapi.yaml', '''
clients:
  api:
    input: &i a.json
    output: lib/api
  other:
    input: *i
    output: lib/other
''');
    final bag = DiagnosticBag();
    expect(ConfigLoader(bag).load(path)!.clients, hasLength(2));
    expect(bag.all, isEmpty);
  });

  test('reports unknown keys as warnings and keeps going', () {
    final dir = TempDir();
    final path = dir.write('c.yaml', '''
clients:
  api: {input: a.json, output: lib/api, ouput: typo}
''');
    final bag = DiagnosticBag();
    expect(ConfigLoader(bag).load(path)!.clients, hasLength(1));
    final d = bag.all.single;
    expect(d.code, DiagnosticCode.configUnknownKey);
    expect(d.pointer?.value, '#/clients/api/ouput');
    expect(d.span?.start.line, 1);
  });

  test('skips a client without input and reports it', () {
    final dir = TempDir();
    final path = dir.write('c.yaml', '''
clients:
  broken: {output: lib/broken}
  ok: {input: a.json, output: lib/ok}
''');
    final bag = DiagnosticBag();
    final config = ConfigLoader(bag).load(path)!;
    expect(config.clients.map((c) => c.name), ['ok']);
    expect(bag.all.single.code, DiagnosticCode.configInvalid);
    expect(bag.all.single.message, 'Missing required key "input".');
  });

  test('rejects an unknown preset', () {
    final dir = TempDir();
    final path = dir.write('c.yaml', '''
clients:
  api: {input: a.json, output: lib/api, preset: django}
''');
    final bag = DiagnosticBag();
    expect(ConfigLoader(bag).load(path)!.clients.single.preset, isNull);
    expect(bag.all.single.code, DiagnosticCode.configInvalid);
    expect(bag.all.single.pointer?.value, '#/clients/api/preset');
    expect(
      bag.all.single.message,
      'Unknown preset "django". '
      'Known presets: aspnet, fastapi, generic, nestjs, springdoc.',
    );
  });

  test('reports overlapping output directories', () {
    final dir = TempDir();
    final path = dir.write('c.yaml', '''
clients:
  a: {input: a.json, output: lib/api}
  b: {input: b.json, output: lib/api/b}
''');
    final bag = DiagnosticBag();
    ConfigLoader(bag).load(path);
    expect(bag.all.single.code, DiagnosticCode.outputOverlap);
    expect(bag.all.single.pointer?.value, '#/clients/b/output');
  });

  test('requires a non-empty clients mapping', () {
    final dir = TempDir();
    final bag = DiagnosticBag();
    expect(
      ConfigLoader(bag).load(dir.write('c.yaml', 'clients: {}\n')),
      isNull,
    );
    expect(bag.all.single.code, DiagnosticCode.configInvalid);
  });

  test('reads levels by code or name; a client overrides defaults per '
      'code', () {
    final path = TempDir().write('c.yaml', '''
defaults:
  severity: {TOA201: off, example-scalar-type: warning}
clients:
  a: {input: a.json, output: lib/a}
  b:
    input: b.json
    output: lib/b
    severity: {bool-required: error, TOA804: error}
''');
    final bag = DiagnosticBag();
    final clients = ConfigLoader(bag).load(path)!.clients;
    expect(bag.all, isEmpty);
    expect(clients.first.severity.levels, {
      DiagnosticCode.boolRequired: null,
      DiagnosticCode.exampleScalarType: Severity.warning,
    });
    expect(clients.last.severity.levels, {
      DiagnosticCode.boolRequired: Severity.error,
      DiagnosticCode.exampleScalarType: Severity.warning,
      DiagnosticCode.overrideTargetNotFound: Severity.error,
    });
  });

  test('reports unknown codes, bad levels and codes named twice', () {
    final path = TempDir().write('c.yaml', '''
clients:
  a:
    input: a.json
    output: lib/a
    severity:
      TOA999: off
      bool-required: fatal
      TOA111: info
      invalid-value: off
''');
    final bag = DiagnosticBag();
    final client = ConfigLoader(bag).load(path)!.clients.single;
    expect(client.severity.levels, {
      DiagnosticCode.invalidValue: Severity.info,
    });
    expect(bag.all.map((d) => (d.code, d.pointer?.value, d.message)), [
      (
        DiagnosticCode.configUnknownKey,
        '#/clients/a/severity/TOA999',
        'Unknown diagnostic code "TOA999".',
      ),
      (
        DiagnosticCode.configInvalid,
        '#/clients/a/severity/bool-required',
        'The level of "bool-required" must be error, warning, info or off.',
      ),
      (
        DiagnosticCode.configInvalid,
        '#/clients/a/severity/invalid-value',
        '"invalid-value" names the same code as "TOA111" (TOA111); only the '
            'first is used.',
      ),
    ]);
  });

  test('any code but a config code may be raised; a fixed code may not be '
      'lowered or turned off', () {
    final path = TempDir().write('c.yaml', '''
defaults:
  severity:
    parse-error: warning
    TOA801: off
    TOA804: off
    TOA807: warning
    example-type-mismatch: error
    config-unknown-key: error
clients:
  a: {input: a.json, output: lib/a}
''');
    final bag = DiagnosticBag();
    final client = ConfigLoader(bag).load(path)!.clients.single;
    expect(client.severity.levels, {
      DiagnosticCode.overrideTargetNotFound: null,
      DiagnosticCode.overrideUnchanged: Severity.warning,
      DiagnosticCode.exampleTypeMismatch: Severity.error,
    });
    expect(bag.all.map((d) => (d.code, d.pointer?.value, d.message)), [
      (
        DiagnosticCode.configInvalid,
        '#/defaults/severity/parse-error',
        'TOA001 parse-error cannot be lowered or turned off: without it a '
            'file that cannot be read would pass.',
      ),
      (
        DiagnosticCode.configInvalid,
        '#/defaults/severity/TOA801',
        'TOA801 overrides-not-found cannot be lowered or turned off: '
            'without it a file that cannot be read would pass.',
      ),
      (
        DiagnosticCode.configInvalid,
        '#/defaults/severity/config-unknown-key',
        'The level of TOA903 config-unknown-key cannot be changed: the '
            'config is read before levels apply.',
      ),
    ]);
  });

  test('severity must be a mapping', () {
    final path = TempDir().write('c.yaml', '''
clients:
  a: {input: a.json, output: lib/a, severity: [TOA201]}
''');
    final bag = DiagnosticBag();
    expect(ConfigLoader(bag).load(path)!.clients.single.severity.levels, {});
    expect(bag.all.map((d) => (d.code, d.pointer?.value)), [
      (DiagnosticCode.configInvalid, '#/clients/a/severity'),
    ]);
  });

  test('reports a baseline file two clients share', () {
    final path = TempDir().write('c.yaml', '''
clients:
  a: {input: a.json, output: lib/a, baseline: shared.yaml}
  b: {input: b.json, output: lib/b, baseline: ./shared.yaml}
  c: {input: c.json, output: lib/c, baseline: c.yaml}
''');
    final bag = DiagnosticBag();
    ConfigLoader(bag).load(path);
    expect(bag.all.map((d) => (d.code, d.pointer?.value, d.message)), [
      (
        DiagnosticCode.configInvalid,
        '#/clients/b/baseline',
        'Clients "a" and "b" name the same baseline file.',
      ),
    ]);
  });
}
