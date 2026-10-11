import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/config/config_loader.dart';
import 'package:typed_openapi/src/config/project_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';

import '../helpers/temp_dir.dart';

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

  for (final (name, key) in [
    ('an explicit ? key', 'x-key:\n  ? *l7\n  : v'),
    ('a flow sequence key', '[*l7]: v'),
    ('a flow mapping key', '{a: *l7}: v'),
    ('a ? key inside a flow mapping', 'x-key: {? *l7 : v}'),
  ]) {
    test('rejects $name with an alias before expanding it', () {
      final text = StringBuffer('x-l0: &l0 [x, x, x, x, x, x, x, x, x]\n');
      for (var i = 1; i <= 7; i++) {
        text.writeln(
          'x-l$i: &l$i [${List.filled(9, '*l${i - 1}').join(', ')}]',
        );
      }
      text.writeln(key);
      text.writeln('clients:\n  api: {input: a.json, output: lib/api}');
      final path = TempDir().write('typed_openapi.yaml', '$text');
      final bag = DiagnosticBag();
      expect(ConfigLoader(bag).load(path), isNull);
      expect(bag.all.single.code, DiagnosticCode.configInvalid);
      expect(bag.all.single.message, contains('mapping key'));
    }, timeout: const Timeout(Duration(seconds: 30)));
  }

  test('accepts an alias in a value', () {
    final path = TempDir().write('typed_openapi.yaml', '''
clients:
  api: {input: &i a.json, output: lib/api}
  other: {input: *i, output: lib/other}
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
}
