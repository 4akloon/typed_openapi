@TestOn('vm')
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_cli.dart';

const _plain = '''
openapi: 3.1.0
info: {title: Plain, version: '1'}
paths: {}
bogus: 1
''';

const _fastapi = '''
openapi: 3.1.0
info: {title: Marked, version: '1'}
paths: {}
components:
  schemas:
    HTTPValidationError: {type: object}
    ValidationError: {type: object}
''';

String _hashOf(String text) => sha256.convert(utf8.encode(text)).toString();

void main() {
  late TempDir temp;
  setUp(() => temp = TempDir());

  String corpus({String plainFramework = '', String? hash}) =>
      temp.write('corpus.yaml', '''
specs:
  plain:
    url: https://example.com/plain.yaml
    sha256: ${hash ?? _hashOf(_plain)}
    license: MIT
    expect: generate
$plainFramework  marked:
    url: https://example.com/marked.yaml
    sha256: ${_hashOf(_fastapi)}
    license: MIT
    expect: generate
    framework: fastapi
''');

  Future<({int code, String out, String err})> lint(
    String file,
    List<String> names,
  ) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code =
        await CorpusCli(
          out: out,
          err: err,
          download: (url) async =>
              utf8.encode(url.path.endsWith('plain.yaml') ? _plain : _fastapi),
        ).run([
          'lint',
          '--corpus',
          file,
          '--cache',
          '${temp.path}/cache',
          ...names,
        ]);
    return (code: code, out: '$out', err: '$err');
  }

  test('prints a line per spec, the counts by framework and exits 0', () async {
    final run = await lint(corpus(), []);
    expect(run.code, 0, reason: run.err);
    expect(run.out, '''
spec    framework  detected  errors  warnings  infos
plain     generic   generic       0         1      0  TOA110:1
marked    fastapi   fastapi       0         0      0

By framework:
framework  specs  detected  errors  warnings  infos
generic        1         1       0         1      0
fastapi        1         1       0         0      0

Detection: 2 of 2 as the corpus expects.
''');
  });

  test('a spec with detects: false is expected as generic and not counted '
      'as detected in its framework', () async {
    final file = corpus(
      plainFramework: '    framework: aspnet\n    detects: false\n',
    );
    final run = await lint(file, []);
    expect(run.code, 0, reason: run.err);
    expect(run.out, '''
spec    framework  detected  errors  warnings  infos
plain      aspnet   generic       0         1      0  TOA110:1
marked    fastapi   fastapi       0         0      0

By framework:
framework  specs  detected  errors  warnings  infos
fastapi        1         1       0         0      0
aspnet         1         0       0         1      0

Detection: 2 of 2 as the corpus expects.
''');
  });

  test('a framework the detector misses fails and names why', () async {
    final file = corpus(plainFramework: '    framework: fastapi\n');
    final run = await lint(file, []);
    expect(run.code, 1);
    expect(
      run.out,
      contains(
        'expected fastapi, detected generic (no framework marks were found)',
      ),
    );
  });

  test(
    'names select the specs, and an unknown name is a usage error',
    () async {
      final file = corpus();
      final one = await lint(file, ['marked']);
      expect(one.code, 0, reason: one.err);
      expect(one.out, contains('Detection: 1 of 1'));
      expect((await lint(file, ['nope'])).code, 64);
    },
  );

  test('a download with another hash is a failure, not a crash', () async {
    final run = await lint(corpus(hash: _hashOf('other')), []);
    expect(run.code, 1);
    expect(run.err.trim().split('\n'), hasLength(1));
  });
}
