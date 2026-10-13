import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_exception.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_spec.dart';
import 'package:typed_openapi_tool/src/corpus/expectation.dart';
import 'package:typed_openapi_tool/src/corpus/spec_cache.dart';
import 'package:typed_openapi_tool/src/corpus/spec_source.dart';
import 'package:typed_openapi_tool/src/corpus/tree_hash.dart';

import '../helpers/temp_dir.dart';

const _text = 'openapi: 3.1.0\n';

/// An entry for [source] pinned to [sha256].
CorpusSpec spec(SpecSource source, String sha256) => CorpusSpec(
  name: 'pets',
  source: source,
  sha256: sha256,
  license: 'MIT',
  expectation: const Generates(),
);

void main() {
  final file = FileSource(Uri.parse('https://example.com/x/openapi.yaml'));
  final pinned = sha256.convert(utf8.encode(_text)).toString();

  test('downloads a missing file once and serves it from the cache', () async {
    final temp = TempDir();
    var downloads = 0;
    final cache = SpecCache(temp.path, (url) async {
      downloads++;
      return utf8.encode(_text);
    });
    final path = await cache.fetch(spec(file, pinned));
    expect(path, p.join(temp.path, 'pets', 'openapi.yaml'));
    expect(File(path).readAsStringSync(), _text);
    await cache.fetch(spec(file, pinned));
    expect(downloads, 1);
  });

  test('a download with another hash is an error and is not kept', () async {
    final temp = TempDir();
    final cache = SpecCache(temp.path, (url) async => utf8.encode('changed'));
    await expectLater(
      cache.fetch(spec(file, pinned)),
      throwsA(
        isA<CorpusException>().having(
          (e) => e.message,
          'message',
          allOf(contains('corpus.yaml pins $pinned'), contains('pets: https')),
        ),
      ),
    );
    expect(Directory(p.join(temp.path, 'pets')).existsSync(), isFalse);
  });

  test('keeps the root of an archive and pins its tree', () async {
    final temp = TempDir()
      ..write('src/repo-abc/specs/store/openapi.yaml', _text)
      ..write('src/repo-abc/specs/store/paths/a.yaml', 'a: 1\n')
      ..write('src/repo-abc/README.md', 'not kept\n');
    final archive = p.join(temp.path, 'repo.tar.gz');
    final tar = await Process.run('tar', [
      '-czf',
      archive,
      '-C',
      p.join(temp.path, 'src'),
      'repo-abc',
    ]);
    expect(tar.exitCode, 0, reason: '${tar.stderr}');
    final expected = const TreeHash().combine({
      'openapi.yaml': pinned,
      'paths/a.yaml': sha256.convert(utf8.encode('a: 1\n')).toString(),
    });
    final source = ArchiveSource(
      Uri.parse('https://example.com/repo.tar.gz'),
      root: 'specs/store',
      entry: 'openapi.yaml',
    );
    final cache = SpecCache(
      p.join(temp.path, 'cache'),
      (url) async => File(archive).readAsBytesSync(),
    );
    final path = await cache.fetch(spec(source, expected));
    expect(path, p.join(temp.path, 'cache', 'pets', 'openapi.yaml'));
    expect(
      File(p.join(temp.path, 'cache', 'pets', 'README.md')).existsSync(),
      isFalse,
    );
  });
}
