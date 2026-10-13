@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_cli.dart';

import '../helpers/temp_dir.dart';

const _spec = '''
openapi: 3.1.0
info: {title: Pets, version: "1"}
paths: {}
components:
  schemas:
    Pet:
      type: object
      required: [id]
      properties: {id: {type: string}}
      example: {id: a}
''';

void main() {
  test('check exits 1 when a round-trip count differs from the lock', () async {
    final temp = TempDir();
    final hash = sha256.convert(utf8.encode(_spec));
    final corpus = temp.write('corpus.yaml', '''
specs:
  pets: {url: https://example.com/pets.yaml, sha256: $hash, license: MIT, expect: generate}
''');
    final lock = p.join(temp.path, 'corpus.lock');
    final options = [
      '--corpus',
      corpus,
      '--cache',
      p.join(temp.path, 'cache'),
      '--lock',
      lock,
      '--work',
      p.join(temp.path, 'work'),
      '--runtime',
      p.normalize(p.absolute(p.join('..', 'typed_openapi_runtime'))),
    ];
    Future<int> run(String command, StringBuffer out) => CorpusCli(
      out: out,
      err: StringBuffer(),
      download: (_) async => utf8.encode(_spec),
    ).run([command, ...options]);

    expect(await run('update', StringBuffer()), 0);
    final unchanged = StringBuffer();
    expect(await run('check', unchanged), 0);
    expect(unchanged.toString(), contains('0 differences'));

    final text = File(lock).readAsStringSync();
    File(lock).writeAsStringSync(
      text.replaceFirst('"failures": 0', '"failures": 1'),
    );
    final changed = StringBuffer();
    expect(await run('check', changed), 1);
    expect(changed.toString(), contains('raw/pets: failures 1 -> 0'));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
