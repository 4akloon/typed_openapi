import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';
import 'package:typed_openapi_tool/src/docs/docs_cli.dart';
import 'package:typed_openapi_tool/src/docs/generated_docs.dart';

void main() {
  Future<(int, String, String)> run(List<String> args) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await DocsCli(out: out, err: err).run(args);
    return (code, out.toString(), err.toString());
  }

  test('the generated docs of the repository are current', () async {
    final (code, out, err) = await run(['check']);
    expect(code, 0, reason: '$out$err');
    expect(out, contains('current'));
  });

  test(
    'generate writes the four files, and a second run writes none',
    () async {
      final root = TempDir().path;
      final (code, out, _) = await run(['--root', root, 'generate']);
      expect(code, 0);
      expect(
        out.trim().split('\n'),
        unorderedEquals([
          'Wrote ${GeneratedDocs.diagnosticsPath}',
          'Wrote ${GeneratedDocs.extensionsPath}',
          'Wrote ${GeneratedDocs.configSchemaPath}',
          'Wrote ${GeneratedDocs.overridesSchemaPath}',
        ]),
      );
      final (_, again, _) = await run(['--root', root, 'generate']);
      expect(again, isEmpty);
    },
  );

  test('check names a file that is stale or missing', () async {
    final root = TempDir().path;
    await run(['--root', root, 'generate']);
    File(p.join(root, GeneratedDocs.diagnosticsPath)).writeAsStringSync('old');
    File(p.join(root, GeneratedDocs.extensionsPath)).deleteSync();
    final (code, _, err) = await run(['--root', root, 'check']);
    expect(code, 1);
    expect(err, contains(GeneratedDocs.diagnosticsPath));
    expect(err, contains(GeneratedDocs.extensionsPath));
    expect(err, isNot(contains('schema.json')));
    expect(err, contains('dart run bin/docs.dart generate'));
  });

  test('an unknown command is a usage error', () async {
    final (code, _, err) = await run(['publish']);
    expect(code, 64);
    expect(err, contains('Usage:'));
  });

  test('--root without a command is a usage error', () async {
    final (code, _, err) = await run(['--root', TempDir().path]);
    expect(code, 64);
    expect(err, contains('Usage:'));
  });
}
