import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'archive_extractor.dart';
import 'corpus_exception.dart';
import 'corpus_spec.dart';
import 'pinned_schema.dart';
import 'spec_source.dart';
import 'tree_hash.dart';

/// Downloads the bytes at a URL.
typedef Download = Future<List<int>> Function(Uri url);

/// The downloaded corpus specs: `<directory>/<name>/` per entry, verified
/// against the pinned hash on every use.
final class SpecCache {
  /// Creates the cache in [directory]; [download] fetches a missing spec.
  const SpecCache(this.directory, this._download);

  /// The directory of the cache.
  final String directory;

  final Download _download;

  /// The path of the spec file of [spec]: from the cache when its hash is
  /// the pinned one, else downloaded again. A download whose hash differs
  /// from the pin is a [CorpusException], and nothing of it is kept.
  Future<String> fetch(CorpusSpec spec) =>
      _fetch(spec.name, spec.source, spec.sha256);

  /// The path of the file of [schema], kept and checked as [fetch] does.
  Future<String> fetchSchema(PinnedSchema schema) =>
      _fetch(schema.name, FileSource(schema.url), schema.sha256);

  Future<String> _fetch(String name, SpecSource source, String pinned) async {
    final folder = p.join(directory, name);
    final entry = p.joinAll([folder, ...source.entry.split('/')]);
    if (_hashOf(name, source) == pinned) return entry;
    _delete(folder);
    final bytes = await _download(source.url);
    switch (source) {
      case FileSource():
        File(entry)
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes);
      case ArchiveSource(:final root):
        await const ArchiveExtractor().extract(bytes, root, folder);
    }
    final actual = _hashOf(name, source);
    if (actual != pinned) {
      _delete(folder);
      throw CorpusException(
        '$name: ${source.url} has the SHA-256 $actual; '
        'corpus.yaml pins $pinned.',
      );
    }
    return entry;
  }

  /// The hash of the cached file of [schema], or null when there is none.
  String? hashOfSchema(PinnedSchema schema) =>
      _hashOf(schema.name, FileSource(schema.url));

  /// The hash of the cached files of [spec], or null when there are none.
  String? hashOf(CorpusSpec spec) => _hashOf(spec.name, spec.source);

  String? _hashOf(String name, SpecSource source) {
    final folder = p.join(directory, name);
    if (!Directory(folder).existsSync()) return null;
    return switch (source) {
      FileSource(:final entry) => switch (File(p.join(folder, entry))) {
        final file when file.existsSync() =>
          sha256.convert(file.readAsBytesSync()).toString(),
        _ => null,
      },
      ArchiveSource() => const TreeHash().of(folder),
    };
  }

  static void _delete(String folder) {
    final directory = Directory(folder);
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}
