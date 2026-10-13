import 'package:path/path.dart' as p;

import 'existing_output.dart';
import 'output_changes.dart';
import 'output_manifest.dart';

/// The new tree of a run: its files, the hash of each and its manifest.
final class GeneratedTree {
  /// Reads [files] (paths relative to the output directory) generated from
  /// [inputs], the hash of what they were generated from.
  factory GeneratedTree(Map<String, String> files, {required String inputs}) {
    final entries = files.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final hashes = {
      for (final MapEntry(:key, :value) in entries)
        key: OutputManifest.hashOf(value),
    };
    final directories = {
      for (final MapEntry(key: path) in entries)
        for (var d = p.posix.dirname(path); d != '.'; d = p.posix.dirname(d)) d,
    };
    return GeneratedTree._(
      files,
      entries,
      hashes,
      OutputManifest.render(hashes, inputs: inputs),
      directories,
    );
  }

  GeneratedTree._(
    this.files,
    this.entries,
    this.hashes,
    this.manifest,
    this.directories,
  ) : manifestHash = OutputManifest.hashOf(manifest);

  /// The files by path.
  final Map<String, String> files;

  /// The files in the order of their paths.
  final List<MapEntry<String, String>> entries;

  /// The SHA-256 of every file, by path, in the order of the paths.
  final Map<String, String> hashes;

  /// The text of the manifest.
  final String manifest;

  /// The SHA-256 of [manifest].
  final String manifestHash;

  /// The directories the files need, by relative path.
  final Set<String> directories;

  /// What a run that writes this tree changes in [existing].
  OutputChanges changesFrom(ExistingOutput existing) {
    var written = 0;
    var unchanged = 0;
    for (final MapEntry(key: path, value: hash) in hashes.entries) {
      if (existing.hashes[path] == hash) {
        unchanged++;
      } else {
        written++;
      }
    }
    final deleted = existing.hashes.keys
        .where((f) => f != OutputManifest.fileName && !files.containsKey(f))
        .length;
    return OutputChanges(
      written: written,
      unchanged: unchanged,
      deleted: deleted,
      forced: existing.strays.length,
    );
  }

  /// Whether [existing] is this tree already, so [changes] has nothing to
  /// write or delete and the directory need not be touched.
  bool isInstalledIn(ExistingOutput existing, OutputChanges changes) =>
      changes.written == 0 &&
      changes.deleted == 0 &&
      existing.hashes[OutputManifest.fileName] == manifestHash &&
      existing.directories.length == directories.length &&
      existing.directories.containsAll(directories);
}
