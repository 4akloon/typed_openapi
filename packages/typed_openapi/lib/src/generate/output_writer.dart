import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../config/project_config.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/display_paths.dart';
import 'real_paths.dart';

/// What [OutputWriter.write] did to an output directory.
final class OutputChanges {
  /// Creates the counts.
  const OutputChanges({
    required this.written,
    required this.unchanged,
    required this.deleted,
  });

  /// Files written because they are new or their content changed.
  final int written;

  /// Files whose content was already the generated one.
  final int unchanged;

  /// Files deleted because the generator no longer writes them.
  final int deleted;
}

/// What an output directory holds before a run.
final class _Existing {
  const _Existing(this.files, this.directories);

  /// An output directory that does not exist yet.
  static const none = _Existing({}, {});

  /// The files, by path relative to the directory with `/` separators.
  final Set<String> files;

  /// The directories, the same way.
  final Set<String> directories;
}

/// Writes the generated files of a client into its output directory, which
/// the generator owns (decisions 15 and 17 of M8).
///
/// A run is atomic: the whole new tree and its manifest are built in a
/// temporary directory next to the output, which is then swapped in (the old
/// directory is renamed to a backup, the new one to the output, the backup
/// is removed). Any failure puts the old directory back, so the output is
/// the previous run's or the new one, never a mix, and a failed first run
/// leaves nothing. A run that would change nothing does not touch the
/// directory. Files the generator did not write this time are gone with the
/// old directory. The manifest lists the generator, a hash of the inputs and
/// every file with its hash.
///
/// The directory is refused (TOA830, nothing is written) when it holds a
/// `pubspec.yaml`, is the `lib` directory of a package, holds an input of
/// the run (the config, the spec, the overrides or the baseline file, also
/// through a symbolic link, a hard link or a name that differs in case),
/// holds a symbolic link, or holds files but no manifest of this generator.
/// A process killed between the swap's two renames leaves the backup and
/// the new tree in sibling directories named `.<output>.typed_openapi-*`.
final class OutputWriter {
  /// Creates a writer that reports to [_diagnostics]; [_paths] names
  /// directories in diagnostics. [beforeInstall] is called between the
  /// renames of the swap, where tests make a failure.
  const OutputWriter(
    this._diagnostics, [
    this._paths = const DisplayPaths(),
    this.beforeInstall,
  ]);

  /// The name of the manifest in the output directory.
  static const manifest = '.typed_openapi.json';

  /// The generator and its version, as the manifest names them.
  static const generator = 'typed_openapi 0.0.1';

  /// What a manifest's `generator` starts with, whatever the version.
  static const _generatorName = 'typed_openapi';

  /// Called after the old directory is renamed to its backup and before the
  /// new one is renamed to the output.
  final void Function()? beforeInstall;

  final DiagnosticBag _diagnostics;
  final DisplayPaths _paths;

  /// Writes [files] (paths relative to the output directory of [client])
  /// and the manifest with [inputs], the hash of what they were generated
  /// from; [protected] are the input files of the run, which the directory
  /// must not hold. Returns null after reporting why nothing was written.
  OutputChanges? write(
    ClientConfig client,
    Map<String, String> files, {
    required String inputs,
    List<String> protected = const [],
  }) {
    final root = p.normalize(p.absolute(client.output));
    final created = <Directory>[];
    Directory? staging;
    try {
      final existing = _inspect(client, root, protected);
      if (existing == null) return null;
      final keys = files.keys.toList()..sort();
      final text = manifestOf(files, inputs: inputs);
      var written = 0;
      var unchanged = 0;
      for (final path in keys) {
        if (existing.files.contains(path) &&
            _holds(p.join(root, path), files[path]!)) {
          unchanged++;
        } else {
          written++;
        }
      }
      final deleted = existing.files
          .where((f) => f != manifest && !files.containsKey(f))
          .length;
      final directories = {
        for (final path in keys)
          for (var d = p.posix.dirname(path); d != '.'; d = p.posix.dirname(d))
            d,
      };
      final same =
          written == 0 &&
          deleted == 0 &&
          existing.files.contains(manifest) &&
          _holds(p.join(root, manifest), text) &&
          existing.directories.length == directories.length &&
          existing.directories.containsAll(directories);
      final changes = OutputChanges(
        written: written,
        unchanged: unchanged,
        deleted: deleted,
      );
      if (same) return changes;
      final parent = Directory(p.dirname(root));
      for (final missing in _missing(parent)) {
        missing.createSync();
        created.add(missing);
      }
      staging = parent.createTempSync('.${p.basename(root)}.typed_openapi-');
      for (final path in keys) {
        _writeFile(p.join(staging.path, path), files[path]!);
      }
      _writeFile(p.join(staging.path, manifest), text);
      _install(staging, root, hasOld: Directory(root).existsSync());
      staging = null;
      created.clear();
      return changes;
    } on FileSystemException catch (e) {
      _diagnostics.report(
        .outputNotWritten,
        'Cannot write the output of client "${client.name}" to '
        '${_paths.of(root)}: ${e.message}${e.path == null ? '' : ' (${_paths.of(e.path!)})'}.',
        file: _paths.of(root),
        fix:
            'Check that the directory can be written, then run generate '
            'again.',
      );
      return null;
    } finally {
      _discard(staging);
      for (final directory in created.reversed) {
        try {
          directory.deleteSync();
        } on FileSystemException {
          // Not empty or not ours any more: it stays.
        }
      }
    }
  }

  /// The manifest of [files] generated from [inputs]: JSON with sorted
  /// keys, the same for the same files.
  static String manifestOf(
    Map<String, String> files, {
    required String inputs,
  }) {
    final hashes = {
      for (final path in files.keys.toList()..sort())
        path: sha256.convert(utf8.encode(files[path]!)).toString(),
    };
    return '${const JsonEncoder.withIndent('  ').convert({
      'generator': generator,
      'inputs': inputs,
      'files': hashes,
    })}\n';
  }

  /// The directories above [directory] that do not exist, outermost first,
  /// then [directory] itself if it does not exist.
  static List<Directory> _missing(Directory directory) {
    final result = <Directory>[];
    var current = directory.absolute;
    while (!current.existsSync()) {
      result.add(current);
      final parent = current.parent;
      if (parent.path == current.path) break;
      current = parent;
    }
    return result.reversed.toList();
  }

  /// Swaps [staging] in as [root]; the old directory, if [hasOld], goes to a
  /// backup first, comes back when the swap fails and is removed when it
  /// works.
  void _install(Directory staging, String root, {required bool hasOld}) {
    final backup = Directory('${staging.path}-old');
    final output = Directory(root);
    if (hasOld) output.renameSync(backup.path);
    try {
      beforeInstall?.call();
      staging.renameSync(root);
    } on Object {
      if (hasOld) backup.renameSync(root);
      rethrow;
    }
    if (hasOld) {
      try {
        backup.deleteSync(recursive: true);
      } on FileSystemException catch (e) {
        _diagnostics.report(
          .outputNotWritten,
          'The new output in ${_paths.of(root)} is in place, but the old '
          'one, moved to ${_paths.of(backup.path)}, could not be removed: '
          '${e.message}.',
          file: _paths.of(root),
          fix: 'Remove ${_paths.of(backup.path)} by hand.',
        );
      }
    }
  }

  /// Removes the temporary directory [directory] of a failed run.
  static void _discard(Directory? directory) {
    if (directory == null) return;
    try {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    } on FileSystemException {
      // Nothing more to do for a directory that cannot be removed.
    }
  }

  /// What [root] holds, or null after reporting why the generator may not
  /// own it (TOA830).
  _Existing? _inspect(ClientConfig client, String root, List<String> inputs) {
    _Existing? refuse(String why, String fix) {
      _diagnostics.report(
        .outputNotOwned,
        'Client "${client.name}" is not generated: its output directory '
        '${_paths.of(root)} $why. The generator deletes every file there it '
        'did not write.',
        file: _paths.of(root),
        fix: fix,
      );
      return null;
    }

    const move =
        'Point output to a directory of its own, such as '
        'lib/src/<client>.';
    final type = FileSystemEntity.typeSync(root, followLinks: false);
    if (type == FileSystemEntityType.notFound) return _Existing.none;
    if (type == FileSystemEntityType.link) {
      return refuse(
        'is a symbolic link, which the generator does not follow',
        move,
      );
    }
    if (type != FileSystemEntityType.directory) {
      return refuse('is not a directory', move);
    }
    if (File(p.join(root, 'pubspec.yaml')).existsSync()) {
      return refuse('holds a pubspec.yaml', move);
    }
    if (p.basename(root) == 'lib' &&
        File(p.join(p.dirname(root), 'pubspec.yaml')).existsSync()) {
      return refuse('is the lib directory of a package', move);
    }
    final protected = [
      for (final input in inputs)
        if (File(input).existsSync()) input,
    ];
    for (final input in protected) {
      if (RealPaths.isWithin(root, input)) {
        return refuse('holds ${_paths.of(input)}, an input of the run', move);
      }
    }
    final entries = Directory(
      root,
    ).listSync(recursive: true, followLinks: false);
    if (entries.isEmpty) return _Existing.none;
    final lengths = {
      for (final input in protected) input: File(input).lengthSync(),
    };
    final files = <String>{};
    final directories = <String>{};
    for (final entry in entries) {
      final path = p.posix.joinAll(p.split(p.relative(entry.path, from: root)));
      switch (entry) {
        case Link():
          return refuse(
            'holds a symbolic link, $path, which the generator does not '
                'follow',
            'Remove the link, or point output to a new directory.',
          );
        case Directory():
          directories.add(path);
        case _:
          // Whatever the path, never delete a file that is an input.
          for (final MapEntry(key: input, value: length) in lengths.entries) {
            if (File(entry.path).lengthSync() == length &&
                FileSystemEntity.identicalSync(entry.path, input)) {
              return refuse(
                'holds ${_paths.of(entry.path)}, which is the input '
                '${_paths.of(input)} of the run',
                move,
              );
            }
          }
          files.add(path);
      }
    }
    if (!_isManifest(File(p.join(root, manifest)))) {
      return refuse(
        files.contains(manifest)
            ? 'holds a $manifest that is not a manifest of typed_openapi, so '
                  'its files were not written by it'
            : 'holds files but no $manifest, so they were not written by it',
        'Empty the directory, or point output to a new one.',
      );
    }
    return _Existing(files, directories);
  }

  /// Whether [file] exists and is a manifest of this generator, of any
  /// version.
  static bool _isManifest(File file) {
    if (!file.existsSync()) return false;
    try {
      final json = jsonDecode(file.readAsStringSync());
      return json is Map<String, Object?> &&
          json['generator'] is String &&
          (json['generator']! as String).startsWith('$_generatorName ');
    } on FormatException {
      return false;
    }
  }

  /// Whether the file at [path] holds [content].
  static bool _holds(String path, String content) {
    try {
      return File(path).readAsStringSync() == content;
    } on FormatException {
      return false;
    }
  }

  /// Writes [content] to [path], creating its directory.
  static void _writeFile(String path, String content) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content, flush: true);
  }
}
