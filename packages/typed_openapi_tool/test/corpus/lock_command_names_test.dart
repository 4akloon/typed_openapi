@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_cli.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_exception.dart';
import 'package:typed_openapi_tool/src/corpus/spec_cache.dart' show Download;

import '../helpers/corpus_entry.dart';

const _spec = '''
openapi: 3.1.0
info: {title: Pets, version: "1"}
paths: {}
components:
  schemas:
    Pet: {type: object, properties: {id: {type: string}}}
''';

/// A corpus of the specs `pets` and `cats` (the same text) and the options of
/// `corpus update` / `corpus check`.
({List<String> options, String lock}) _corpus(TempDir temp) {
  final hash = sha256.convert(utf8.encode(_spec));
  final corpus = temp.write('corpus.yaml', '''
specs:
  pets: {url: https://example.com/pets.yaml, sha256: $hash, license: MIT, expect: generate}
  cats: {url: https://example.com/cats.yaml, sha256: $hash, license: MIT, expect: generate}
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
  List<String> arguments, {
  Download? download,
}) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await CorpusCli(
    out: out,
    err: err,
    download: download ?? (_) async => utf8.encode(_spec),
    fetchesPackages: false,
  ).run(arguments);
  return (code: code, out: '$out', err: '$err');
}

void main() {
  test(
    'check with an unknown name is a usage error that lists the names',
    () async {
      final corpus = _corpus(TempDir());
      final result = await _run(['check', ...corpus.options, 'dogs']);
      expect(result.code, 64);
      expect(result.err, contains('Unknown name dogs; known: pets, cats.'));
    },
  );

  test('update with an unknown name is a usage error', () async {
    final corpus = _corpus(TempDir());
    final result = await _run(['update', ...corpus.options, 'dogs']);
    expect(result.code, 64);
    expect(result.err, contains('Unknown name dogs'));
  });

  test('update with names is a usage error and writes nothing', () async {
    final corpus = _corpus(TempDir());
    final result = await _run(['update', ...corpus.options, 'pets']);
    expect(result.code, 64);
    expect(result.err, contains('takes no names'));
    expect(File(corpus.lock).existsSync(), isFalse);
  });

  test('check of one name compares only that spec', () async {
    final corpus = _corpus(TempDir());
    expect((await _run(['update', ...corpus.options])).code, 0);
    final result = await _run(['check', ...corpus.options, 'pets']);
    expect(result.out, isNot(contains('client is gone')));
    expect(result.out, contains('0 differences'));
    expect(result.code, 0);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('check of one name still reports a change of that spec', () async {
    final corpus = _corpus(TempDir());
    expect((await _run(['update', ...corpus.options])).code, 0);
    final lock = File(corpus.lock);
    lock.writeAsStringSync(
      lock.readAsStringSync().replaceFirst('"failures": 0', '"failures": 1'),
    );
    final result = await _run(['check', ...corpus.options, 'cats']);
    expect(result.out, contains('raw/cats: failures 1 -> 0'));
    expect(result.code, 1);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test(
    'check of one name reports a lost or new client of that spec only',
    () async {
      final corpus = _corpus(TempDir());
      expect((await _run(['update', ...corpus.options])).code, 0);
      final lock = File(corpus.lock);
      final clients =
          (jsonDecode(lock.readAsStringSync())
                  as Map<String, Object?>)['clients']!
              as Map<String, Object?>;
      clients
        ..['other/pets'] = clients['raw/pets']
        ..remove('structural/pets')
        ..remove('raw/cats')
        ..['other/cats'] = clients['raw/pets'];
      lock.writeAsStringSync(jsonEncode({'version': 1, 'clients': clients}));
      final result = await _run(['check', ...corpus.options, 'pets']);
      expect(result.out, contains('other/pets: client is gone'));
      expect(result.out, contains('structural/pets: new client'));
      expect(result.out, isNot(contains('cats')));
      expect(result.code, 1);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('check without a lock file exits 1 and says to run update', () async {
    final corpus = _corpus(TempDir());
    final result = await _run(['check', ...corpus.options]);
    expect(result.code, 1);
    expect(result.out, contains('does not exist: run corpus update.'));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('check with a failed download exits 1 with the reason', () async {
    final corpus = _corpus(TempDir());
    File(corpus.lock).writeAsStringSync('{"version": 1, "clients": {}}');
    final result = await _run(
      ['check', ...corpus.options],
      download: (url) async => throw CorpusException('GET $url answered 503.'),
    );
    expect(result.code, 1);
    expect(result.err, contains('answered 503'));
  });
}
