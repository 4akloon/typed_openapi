import 'package:yaml/yaml.dart';

import 'corpus_spec.dart';
import 'expectation.dart';
import 'pinned_schema.dart';
import 'spec_source.dart';

/// Reads `corpus.yaml`: a map `specs` from a name to its entry.
///
/// An entry has `url` (one file) or `archive`, `root` and `entry` (a
/// `.tar.gz` of several files), a `sha256`, a `license` and `expect`:
/// `generate`, or `{check-errors: [TOA...]}`. The optional map `schemas`
/// pins single files with a `url`, a `sha256` and a `license`. A malformed
/// file is a [FormatException] that names the entry: the file is ours, not a
/// user's.
final class CorpusListReader {
  /// Creates the reader.
  const CorpusListReader();

  static final _sha256 = RegExp(r'^[0-9a-f]{64}$');
  static final _name = RegExp(r'^[a-z][a-z0-9_]*$');
  static const _keys = {
    'url',
    'archive',
    'root',
    'entry',
    'sha256',
    'license',
    'expect',
  };

  /// The entries of the corpus file [text], in the order of the file.
  List<CorpusSpec> read(String text) {
    final root = loadYaml(text);
    if (root is! YamlMap || root['specs'] is! YamlMap) {
      throw const FormatException('corpus.yaml: no "specs" map.');
    }
    return [
      for (final MapEntry(:key, :value) in (root['specs'] as YamlMap).entries)
        _entry('$key', value),
    ];
  }

  /// The entries of `schemas` in the corpus file [text], in file order; none
  /// when the file has no such map.
  List<PinnedSchema> readSchemas(String text) {
    final root = loadYaml(text);
    if (root is! YamlMap || root['schemas'] is! YamlMap) return const [];
    return [
      for (final MapEntry(:key, :value) in (root['schemas'] as YamlMap).entries)
        _schema('$key', value),
    ];
  }

  PinnedSchema _schema(String name, Object? value) {
    final map = _entryMap(name, value, const {'url', 'sha256', 'license'});
    return PinnedSchema(
      name: name,
      url: Uri.parse(_text(name, map, 'url')),
      sha256: _hash(name, map),
      license: _text(name, map, 'license'),
    );
  }

  CorpusSpec _entry(String name, Object? value) {
    final map = _entryMap(name, value, _keys);
    return CorpusSpec(
      name: name,
      source: _source(name, map),
      sha256: _hash(name, map),
      license: _text(name, map, 'license'),
      expectation: _expectation(name, map['expect']),
    );
  }

  static YamlMap _entryMap(String name, Object? value, Set<String> keys) {
    if (!_name.hasMatch(name)) {
      throw FormatException('corpus.yaml: "$name" is not a snake_case name.');
    }
    if (value is! YamlMap) {
      throw FormatException('corpus.yaml: "$name" is not a map.');
    }
    final unknown = value.keys.where((k) => !keys.contains(k)).toList();
    if (unknown.isNotEmpty) {
      throw FormatException('corpus.yaml: $name has unknown keys: $unknown.');
    }
    return value;
  }

  static String _hash(String name, YamlMap value) {
    final sha256 = _text(name, value, 'sha256');
    if (!_sha256.hasMatch(sha256)) {
      throw FormatException('corpus.yaml: $name has no lowercase sha256.');
    }
    return sha256;
  }

  SpecSource _source(String name, YamlMap value) {
    if (value['url'] != null) {
      return FileSource(Uri.parse(_text(name, value, 'url')));
    }
    return ArchiveSource(
      Uri.parse(_text(name, value, 'archive')),
      root: _text(name, value, 'root'),
      entry: _text(name, value, 'entry'),
    );
  }

  Expectation _expectation(String name, Object? value) => switch (value) {
    'generate' => const Generates(),
    YamlMap(:final length) when length == 1 => switch (value['check-errors']) {
      final YamlList codes when codes.every((c) => c is String) => CheckErrors(
        [for (final c in codes) '$c']..sort(),
      ),
      _ => throw FormatException(
        'corpus.yaml: $name: "check-errors" is not a list of codes.',
      ),
    },
    _ => throw FormatException(
      'corpus.yaml: $name: "expect" is not "generate" or {check-errors: '
      '[...]}.',
    ),
  };

  static String _text(String name, YamlMap value, String key) =>
      switch (value[key]) {
        final String text when text.isNotEmpty => text,
        _ => throw FormatException('corpus.yaml: $name has no "$key".'),
      };
}
