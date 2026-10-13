import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:typed_openapi_tool/src/corpus/corpus_list_reader.dart';
import 'package:typed_openapi_tool/src/corpus/pinned_schema.dart';
import 'package:typed_openapi_tool/src/corpus/spec_cache.dart';

/// A schema pinned in `schemas` of `corpus.yaml`, read from the corpus
/// cache. When the cache lacks it, a local run skips and a CI run
/// (`CI=true`) fails; a file whose hash is not the pin always fails. Tests
/// only.
final class CachedSchema {
  /// Looks for the pin [name] of [corpusFile] in [cacheDirectory];
  /// [environment] tells whether this is CI.
  CachedSchema(
    String name, {
    required String corpusFile,
    required String cacheDirectory,
    required Map<String, String> environment,
  }) : _cache = SpecCache(cacheDirectory, _noDownload),
       _isCi = environment['CI'] == 'true',
       _pin = const CorpusListReader()
           .readSchemas(File(corpusFile).readAsStringSync())
           .firstWhere((s) => s.name == name),
       _directory = cacheDirectory;

  final SpecCache _cache;
  final bool _isCi;
  final PinnedSchema _pin;
  final String _directory;

  static Future<List<int>> _noDownload(Uri url) =>
      throw StateError('Tests never download: $url');

  File get _file => File(
    p.join(_directory, _pin.name, _pin.url.pathSegments.last),
  );

  /// Why a test using the schema is skipped, or null when it runs (or fails,
  /// see [problem]).
  String? get skipReason => _file.existsSync() || _isCi
      ? null
      : 'The ${_pin.name} is not in the cache: run '
            '`dart run bin/corpus.dart fetch ${_pin.name}`.';

  /// What is wrong with the cached file, or null when it is the pinned one.
  String? get problem {
    if (!_file.existsSync()) {
      return 'The ${_pin.name} is not in the cache; CI fetches it with '
          '`dart run bin/corpus.dart fetch ${_pin.name}`.';
    }
    final actual = _cache.hashOfSchema(_pin);
    return actual == _pin.sha256
        ? null
        : 'The cached ${_pin.name} has the SHA-256 $actual; corpus.yaml '
              'pins ${_pin.sha256}.';
  }

  /// The decoded schema; throws [StateError] when [problem] is not null.
  Map<String, Object?> load() {
    if (problem case final String message) throw StateError(message);
    return jsonDecode(_file.readAsStringSync()) as Map<String, Object?>;
  }
}
