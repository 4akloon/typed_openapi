@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_cli.dart';

import '../helpers/corpus_entry.dart';

const _spec = '''
openapi: 3.1.0
info: {title: Pets, version: "1"}
paths: {}
components:
  schemas:
    Pet: {type: object, properties: {id: {type: string}}}
''';

/// A corpus of one spec `pets` whose expectation is [expect], a cache that
/// holds it, and the options of `corpus update` / `corpus check`.
({List<String> options, String lock}) _corpus(TempDir temp, String expect) {
  final hash = sha256.convert(utf8.encode(_spec));
  final corpus = temp.write('corpus.yaml', '''
specs:
  pets: {url: https://example.com/pets.yaml, sha256: $hash, license: MIT, expect: $expect}
''');
  final lock = p.join(temp.path, 'corpus.lock');
  return (
    lock: lock,
    options: [
      '--corpus',
      corpus,
      '--cache',
      p.join(temp.path, 'cache'),
      '--lock',
      lock,
      '--work',
      p.join(temp.path, 'work'),
      '--runtime',
      runtimeDirectory(),
    ],
  );
}

Future<({int code, String out, String err})> _run(
  String command,
  List<String> options,
) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await CorpusCli(
    out: out,
    err: err,
    download: (_) async => utf8.encode(_spec),
    fetchesPackages: false,
  ).run([command, ...options]);
  return (code: code, out: '$out', err: '$err');
}

void main() {
  test('check with a lock that is not JSON exits 1 with a message', () async {
    final corpus = _corpus(TempDir(), 'generate');
    File(corpus.lock).writeAsStringSync('{ not json');
    final result = await _run('check', corpus.options);
    expect(result.code, 1);
    expect(result.err, contains('corpus.lock is not a valid lock'));
  });

  test('check with a lock of the wrong shape exits 1 with a message', () async {
    final corpus = _corpus(TempDir(), 'generate');
    File(corpus.lock).writeAsStringSync(
      '{"version": 1, "clients": {"raw/pets": {"diagnostics": []}}}',
    );
    final result = await _run('check', corpus.options);
    expect(result.code, 1);
    expect(result.err, contains('raw/pets: "diagnostics" is not an object'));
  });

  test('update writes no lock when a gate failed', () async {
    final corpus = _corpus(TempDir(), '{check-errors: [TOA009]}');
    final result = await _run('update', corpus.options);
    expect(result.code, 1);
    expect(result.err, contains('raw/pets: expected the errors [TOA009]'));
    expect(result.err, contains('was not written'));
    expect(File(corpus.lock).existsSync(), isFalse);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
