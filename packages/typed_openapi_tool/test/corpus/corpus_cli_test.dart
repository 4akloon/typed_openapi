@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_cli.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_exception.dart';
import 'package:typed_openapi_tool/src/corpus/spec_cache.dart';

import '../helpers/temp_dir.dart';

const _text = 'openapi: 3.1.0\n';

/// The exit code and the two streams of one run of the corpus command line.
typedef Run = ({int code, String out, String err});

void main() {
  final pinned = sha256.convert(utf8.encode(_text)).toString();

  String corpus(TempDir temp, {String? hash}) => temp.write('corpus.yaml', '''
specs:
  pets: {url: https://example.com/a/openapi.yaml, sha256: ${hash ?? pinned}, license: MIT, expect: generate}
''');

  Future<Run> run(TempDir temp, List<String> args, Download download) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await CorpusCli(
      out: out,
      err: err,
      download: download,
      fetchesPackages: false,
    ).run(args);
    return (code: code, out: '$out', err: '$err');
  }

  Future<Run> command(
    TempDir temp,
    String name,
    String corpusFile,
    Download download,
  ) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code =
        await CorpusCli(
          out: out,
          err: err,
          download: download,
          fetchesPackages: false,
        ).run([
          name,
          '--corpus',
          corpusFile,
          '--cache',
          p.join(temp.path, 'cache'),
          if (name != 'fetch') ...[
            '--lock',
            p.join(temp.path, 'corpus.lock'),
            '--work',
            p.join(temp.path, 'work'),
          ],
        ]);
    return (code: code, out: '$out', err: '$err');
  }

  Future<List<int>> serve(Uri _) async => utf8.encode(_text);

  test('fetch exits 0 and prints the cached path', () async {
    final temp = TempDir();
    final result = await command(temp, 'fetch', corpus(temp), serve);
    expect(result.code, 0);
    expect(result.out, contains('pets: '));
  });

  test('fetch exits 1 when the download has another hash', () async {
    final temp = TempDir();
    final result = await command(
      temp,
      'fetch',
      corpus(temp),
      (_) async => utf8.encode('changed'),
    );
    expect(result.code, 1);
    expect(result.err, contains('corpus.yaml pins $pinned'));
  });

  test('fetch exits 1 when the download fails', () async {
    final temp = TempDir();
    final result = await command(
      temp,
      'fetch',
      corpus(temp),
      (_) async => throw const CorpusException('GET x answered 404.'),
    );
    expect(result.code, 1);
    expect(result.err, contains('answered 404'));
  });

  for (final name in ['update', 'check']) {
    test('$name exits 1 when a spec cannot be fetched', () async {
      final temp = TempDir();
      final result = await command(
        temp,
        name,
        corpus(temp),
        (_) async => utf8.encode('changed'),
      );
      expect(result.code, 1);
      expect(result.err, contains('corpus.yaml pins $pinned'));
    });
  }

  for (final name in ['fetch', 'update', 'check']) {
    test('$name exits 1 with a message for a malformed corpus.yaml', () async {
      final temp = TempDir();
      final bad = temp.write('corpus.yaml', 'specs: [unclosed\n');
      final result = await command(temp, name, bad, serve);
      expect(result.code, 1);
      expect(result.err, startsWith('corpus.yaml: '));
    });

    test('$name exits 1 with a message for a missing corpus.yaml', () async {
      final temp = TempDir();
      final result = await command(
        temp,
        name,
        p.join(temp.path, 'absent.yaml'),
        serve,
      );
      expect(result.code, 1);
      expect(result.err, contains('absent.yaml'));
    });
  }

  test('an unknown command and an unknown option are usage errors', () async {
    final temp = TempDir();
    expect((await run(temp, ['nothing'], serve)).code, 64);
    expect((await run(temp, ['fetch', '--nope'], serve)).code, 64);
  });

  test(
    'semver with a base that looks like an option is a usage error',
    () async {
      final temp = TempDir();
      final result = await run(
        temp,
        ['semver', '--base', '--evil', '--root', temp.path],
        serve,
      );
      expect(result.code, 64);
    },
  );

  test('a file that is not a repository makes semver exit 1', () async {
    final temp = TempDir();
    final result = await run(temp, ['semver', '--root', temp.path], serve);
    expect(result.code, 1);
    expect(result.err, isNotEmpty);
  });

  test('a cache that is a file is reported, not thrown', () async {
    final temp = TempDir();
    temp.write('cache/pets', 'a file where a directory belongs');
    final result = await command(temp, 'fetch', corpus(temp), serve);
    expect(result.code, 1);
    expect(File(p.join(temp.path, 'cache', 'pets')).existsSync(), isTrue);
  });
}
