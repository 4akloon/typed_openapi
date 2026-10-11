import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/cli/cli.dart';

import '../helpers/temp_dir.dart';

void main() {
  late String configPath;

  setUp(() {
    final dir = TempDir();
    dir.write('specs/ok.yaml', 'openapi: 3.1.0\n');
    dir.write('specs/old.json', '{\n  "swagger": "2.0"\n}');
    configPath = dir.write('typed_openapi.yaml', '''
clients:
  ok: {input: specs/ok.yaml, output: lib/ok}
  old: {input: specs/old.json, output: lib/old}
''');
  });

  Future<(int, String, String)> run(List<String> args) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await TypedOpenApiCli(out: out, err: err).run(args);
    return (code, out.toString(), err.toString());
  }

  test('exits 0 when the named client is clean', () async {
    final (code, out, _) = await run(['check', '-c', configPath, 'ok']);
    expect(code, 0);
    expect(out.trim(), 'errors: 0, warnings: 0, infos: 0');
  });

  test('exits 1 and prints the location when a spec has errors', () async {
    final (code, out, _) = await run(['check', '--config', configPath]);
    expect(code, 1);
    expect(out, contains('error TOA011 unsupported-openapi-version'));
    expect(out, contains('  --> ${p.join('specs', 'old.json')}:2:14'));
  });

  test('prints JSON with --format json', () async {
    final (_, out, _) = await run([
      'check',
      '-c',
      configPath,
      '--format',
      'json',
    ]);
    final json = jsonDecode(out) as Map<String, Object?>;
    expect(json['summary'], {'error': 1, 'warning': 0, 'info': 0});
  });

  test('exits 78 when the config file is missing', () async {
    final (code, out, _) = await run([
      'check',
      '-c',
      '/nope/typed_openapi.yaml',
    ]);
    expect(code, 78);
    expect(out, contains('TOA901 config-not-found'));
  });

  test('exits 64 on an unknown client', () async {
    final (code, _, err) = await run(['check', '-c', configPath, 'nope']);
    expect(code, 64);
    expect(err, contains('Unknown client: nope.'));
  });
}
