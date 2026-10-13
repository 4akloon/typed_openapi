import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_list_reader.dart';
import 'package:typed_openapi_tool/src/corpus/spec_source.dart';

void main() {
  final specs = const CorpusListReader().read(
    File('corpus.yaml').readAsStringSync(),
  );

  test('the corpus has the five specs R15.3 names', () {
    expect(
      [for (final s in specs) s.name],
      containsAll(['petstore', 'stripe', 'github', 'openai', 'kubernetes']),
    );
  });

  test('every URL is fixed to a commit, a tag or a versioned file', () {
    final pinned = RegExp(
      r'/[0-9a-f]{40}/|/tar\.gz/[0-9a-f]{40}$|/releases/download/v[\d.]+/|'
      r'-\d+\.\d+\.json$',
    );
    for (final spec in specs) {
      expect('${spec.source.url}', matches(pinned), reason: spec.name);
    }
  });

  test('an archive keeps a directory and names a file in it', () {
    for (final spec in specs) {
      if (spec.source case ArchiveSource(:final root, :final entry)) {
        expect(root, isNot(startsWith('/')), reason: spec.name);
        expect(entry, isNot(contains('..')), reason: spec.name);
      }
    }
  });
}
