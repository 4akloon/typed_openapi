import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_exception.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_spec.dart';
import 'package:typed_openapi_tool/src/corpus/expectation.dart';
import 'package:typed_openapi_tool/src/corpus/pinned_schema.dart';
import 'package:typed_openapi_tool/src/corpus/spec_cache.dart';
import 'package:typed_openapi_tool/src/corpus/spec_source.dart';
import 'package:typed_openapi_tool/src/corpus/tree_hash.dart';

import '../helpers/tar_archive.dart';
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

  test(
    'a pinned schema is downloaded once, checked and kept by name',
    () async {
      final temp = TempDir();
      var downloads = 0;
      final cache = SpecCache(temp.path, (url) async {
        downloads++;
        return utf8.encode(_text);
      });
      final schema = PinnedSchema(
        name: 'sarif_schema',
        url: Uri.parse('https://example.com/x/schema.json'),
        sha256: pinned,
        license: 'MIT',
      );
      final path = await cache.fetchSchema(schema);
      expect(path, p.join(temp.path, 'sarif_schema', 'schema.json'));
      await cache.fetchSchema(schema);
      expect(downloads, 1);
      final wrong = PinnedSchema(
        name: 'other',
        url: schema.url,
        sha256: '0' * 64,
        license: 'MIT',
      );
      await expectLater(
        cache.fetchSchema(wrong),
        throwsA(isA<CorpusException>()),
      );
    },
  );

  group('an archive', () {
    final tree = {
      'openapi.yaml': pinned,
      'paths/a.yaml': sha256.convert(utf8.encode('a: 1\n')).toString(),
    };
    final source = ArchiveSource(
      Uri.parse('https://example.com/repo.tar.gz'),
      root: 'specs',
      entry: 'openapi.yaml',
    );
    final bytes = const TarArchive([
      TarEntry.directory('repo/'),
      TarEntry.directory('repo/specs/'),
      TarEntry.directory('repo/specs/paths/'),
      TarEntry.file('repo/specs/openapi.yaml', _text),
      TarEntry.file('repo/specs/paths/a.yaml', 'a: 1\n'),
    ]).toTarGz();

    test('with another tree hash is an error and leaves nothing', () async {
      final temp = TempDir();
      final cache = SpecCache(temp.path, (url) async => bytes);
      await expectLater(
        cache.fetch(spec(source, '0' * 64)),
        throwsA(isA<CorpusException>()),
      );
      expect(Directory(temp.path).listSync(), isEmpty);
    });

    test('is fetched again when a cached file was tampered with', () async {
      final temp = TempDir();
      var downloads = 0;
      final cache = SpecCache(temp.path, (url) async {
        downloads++;
        return bytes;
      });
      final pin = const TreeHash().combine(tree);
      await cache.fetch(spec(source, pin));
      File(p.join(temp.path, 'pets', 'paths', 'a.yaml')).writeAsStringSync('x');
      await cache.fetch(spec(source, pin));
      expect(downloads, 2);
      expect(
        File(p.join(temp.path, 'pets', 'paths', 'a.yaml')).readAsStringSync(),
        'a: 1\n',
      );
    });

    test('is fetched again when a link was added to the cache', () async {
      final temp = TempDir();
      var downloads = 0;
      final cache = SpecCache(temp.path, (url) async {
        downloads++;
        return bytes;
      });
      final pin = const TreeHash().combine(tree);
      await cache.fetch(spec(source, pin));
      temp.link('pets/evil', 'pets/openapi.yaml');
      await cache.fetch(spec(source, pin));
      expect(downloads, 2);
      expect(Link(p.join(temp.path, 'pets', 'evil')).existsSync(), isFalse);
    });

    test('with a link entry is an error and leaves nothing', () async {
      final temp = TempDir();
      final linked = const TarArchive([
        TarEntry.directory('repo/'),
        TarEntry.file('repo/specs/openapi.yaml', _text),
        TarEntry.symlink('repo/specs/evil', '/etc/passwd'),
      ]).toTarGz();
      final cache = SpecCache(temp.path, (url) async => linked);
      await expectLater(
        cache.fetch(spec(source, pinned)),
        throwsA(
          isA<CorpusException>().having(
            (e) => e.message,
            'message',
            contains('repo/specs/evil'),
          ),
        ),
      );
      expect(Directory(temp.path).listSync(), isEmpty);
    });
  });

  test(
    'a file whose cached copy was tampered with is downloaded again',
    () async {
      final temp = TempDir();
      var downloads = 0;
      final cache = SpecCache(temp.path, (url) async {
        downloads++;
        return utf8.encode(_text);
      });
      final path = await cache.fetch(spec(file, pinned));
      File(path).writeAsStringSync('tampered');
      expect(await cache.fetch(spec(file, pinned)), path);
      expect(downloads, 2);
      expect(File(path).readAsStringSync(), _text);
    },
  );

  test(
    'a file download with another hash replaces a good cached copy',
    () async {
      final temp = TempDir();
      final cache = SpecCache(temp.path, (url) async => utf8.encode('changed'));
      final path = p.join(temp.path, 'pets', 'openapi.yaml');
      File(path)
        ..createSync(recursive: true)
        ..writeAsStringSync('tampered');
      await expectLater(
        cache.fetch(spec(file, pinned)),
        throwsA(isA<CorpusException>()),
      );
      expect(Directory(p.join(temp.path, 'pets')).existsSync(), isFalse);
    },
  );

  test(
    'an entry that leaves the cache folder is refused before any write',
    () async {
      final temp = TempDir();
      var downloads = 0;
      final cache = SpecCache(p.join(temp.path, 'cache'), (url) async {
        downloads++;
        return utf8.encode(_text);
      });
      for (final url in [
        'https://example.com/a%2F..%2F..%2Fx.json',
        'https://example.com/',
        'https://example.com',
      ]) {
        await expectLater(
          cache.fetch(spec(FileSource(Uri.parse(url)), pinned)),
          throwsA(isA<CorpusException>()),
          reason: url,
        );
      }
      expect(downloads, 0);
      expect(File(p.join(temp.path, 'x.json')).existsSync(), isFalse);
      expect(Directory(p.join(temp.path, 'cache')).existsSync(), isFalse);
    },
  );
}
