@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';
import 'package:typed_openapi_tool/src/corpus/archive_extractor.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_exception.dart';
import 'package:typed_openapi_tool/src/corpus/tar_runner.dart';
import 'package:typed_openapi_tool/src/corpus/tree_hash.dart';

import '../helpers/tar_archive.dart';

/// The entries of a small repository archive whose root is `specs`.
const _repo = [
  TarEntry.directory('repo/'),
  TarEntry.directory('repo/specs/'),
  TarEntry.file('repo/specs/openapi.yaml', 'openapi: 3.1.0\n'),
];

Matcher _rejects(Pattern entry) => throwsA(
  isA<CorpusException>().having((e) => e.message, 'message', contains(entry)),
);

void main() {
  Future<void> extract(TempDir temp, List<TarEntry> entries) =>
      const ArchiveExtractor().extract(
        TarArchive(entries).toTarGz(),
        'specs',
        p.join(temp.path, 'cache', 'pets'),
      );

  void expectNothingLeft(TempDir temp) {
    final cache = Directory(p.join(temp.path, 'cache'));
    expect(cache.existsSync() ? cache.listSync() : const [], isEmpty);
    expect(Directory(p.join(temp.path, 'escaped')).existsSync(), isFalse);
  }

  test('a tar that outlives its time limit is killed and reported', () async {
    final temp = TempDir();
    final script = temp.write(
      'sleep.dart',
      'void main() => '
          'Future<void>.delayed(const Duration(seconds: 60));',
    );
    await expectLater(
      TarRunner(
        timeout: const Duration(milliseconds: 500),
        executable: Platform.resolvedExecutable,
      ).run([script]),
      _rejects('did not finish within'),
    );
  });

  test('extracts the root of a hand-made archive', () async {
    final temp = TempDir();
    await extract(temp, _repo);
    expect(
      File(p.join(temp.path, 'cache', 'pets', 'openapi.yaml')).existsSync(),
      isTrue,
    );
  });

  test('a symbolic link below the root fails and names the entry', () async {
    final temp = TempDir();
    await expectLater(
      extract(temp, [..._repo, const TarEntry.symlink('repo/specs/l', '/etc')]),
      _rejects('repo/specs/l'),
    );
    expectNothingLeft(temp);
  });

  test('a hard link below the root fails and names the entry', () async {
    final temp = TempDir();
    await expectLater(
      extract(temp, [
        ..._repo,
        const TarEntry.hardlink('repo/specs/h', 'repo/specs/openapi.yaml'),
      ]),
      _rejects('repo/specs/h'),
    );
    expectNothingLeft(temp);
  });

  test('a link that is the root or above it fails', () async {
    final temp = TempDir();
    await expectLater(
      extract(temp, [
        const TarEntry.directory('repo/'),
        const TarEntry.symlink('repo/specs', '../../escaped'),
        const TarEntry.file('repo/specs/openapi.yaml', 'a: 1\n'),
      ]),
      _rejects('repo/specs'),
    );
    expectNothingLeft(temp);
  });

  test('an entry with a .. segment fails and writes nothing outside', () async {
    final temp = TempDir();
    await expectLater(
      extract(temp, [..._repo, const TarEntry.file('repo/../../escaped/x')]),
      _rejects('repo/../../escaped/x'),
    );
    expectNothingLeft(temp);
  });

  test('an absolute entry name fails', () async {
    final temp = TempDir();
    await expectLater(
      extract(temp, [..._repo, TarEntry.file('${temp.path}/escaped/x')]),
      _rejects('/escaped/x'),
    );
    expectNothingLeft(temp);
  });

  test(
    'a link outside the kept root is not extracted and not an error',
    () async {
      final temp = TempDir();
      await extract(temp, [
        ..._repo,
        const TarEntry.symlink('repo/link', '/etc'),
      ]);
      expect(
        Directory(p.join(temp.path, 'cache', 'pets')).listSync().single.path,
        endsWith('openapi.yaml'),
      );
    },
  );

  test(
    'a link written with . or empty segments cannot dodge the check',
    () async {
      for (final name in [
        './repo/specs/l',
        'repo//specs/l',
        'repo/./specs/l',
      ]) {
        final temp = TempDir();
        await expectLater(
          extract(temp, [..._repo, TarEntry.symlink(name, '/etc')]),
          throwsA(isA<CorpusException>()),
          reason: name,
        );
        expectNothingLeft(temp);
      }
    },
  );

  test('a FIFO in the kept root fails and names the entry', () async {
    final temp = TempDir();
    await expectLater(
      extract(temp, [..._repo, const TarEntry.fifo('repo/specs/pipe')]),
      _rejects('repo/specs/pipe'),
    );
    expectNothingLeft(temp);
  });

  test('an archive without the root fails', () async {
    final temp = TempDir();
    await expectLater(
      extract(temp, [const TarEntry.file('repo/other.yaml', 'a: 1\n')]),
      throwsA(isA<CorpusException>()),
    );
    expectNothingLeft(temp);
  });

  test('the hash of a tree with a symbolic link fails and names it', () {
    final temp = TempDir()
      ..write('tree/a.yaml', 'a: 1\n')
      ..link('tree/l', 'tree/a.yaml');
    expect(
      () => const TreeHash().of(p.join(temp.path, 'tree')),
      _rejects('l'),
    );
  });
}
