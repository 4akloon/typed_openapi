@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_cli.dart';

import '../helpers/temp_dir.dart';

const _hash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  test('a name that is no spec and no schema is a usage error', () async {
    final temp = TempDir();
    final corpus = temp.write('corpus.yaml', '''
specs:
  pets: {url: https://example.com/a.yaml, sha256: $_hash, license: MIT, expect: generate}
schemas:
  sarif_schema: {url: https://example.com/s.json, sha256: $_hash, license: MIT}
''');
    final err = StringBuffer();
    final code = await CorpusCli(
      out: StringBuffer(),
      err: err,
      download: (_) async => throw StateError('no download'),
    ).run(['fetch', '--corpus', corpus, 'sarif_schma']);
    expect(code, 64);
    expect(err.toString(), contains('Unknown name sarif_schma'));
    expect(err.toString(), contains('known: pets, sarif_schema'));
  });
}
