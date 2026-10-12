import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
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
    this.forced = 0,
  });

  /// Files written because they are new or their content changed.
  final int written;

  /// Files whose content was already the generated one.
  final int unchanged;

  /// Files deleted because the generator no longer writes them.
  final int deleted;

  /// How many of the files written over or deleted were not the generator's
  /// own or had changed since it wrote them, and went only because of
  /// `force`.
  final int forced;
}

/// A file of an output directory that the generator may not replace: it did
/// not write it, or it differs from what the manifest says it wrote.
final class _Stray {
  const _Stray(this.path, this.reason);

  /// The path relative to the directory, with `/` separators.
  final String path;

  /// Why the file counts as someone else's.
  final String reason;
}

/// What an output directory holds before a run.
final class _Existing {
  const _Existing(this.hashes, this.directories, [this.strays = const []]);

  /// An output directory that does not exist yet.
  static const none = _Existing({}, {});

  /// The files, by path relative to the directory with `/` separators, with
  /// the SHA-256 of their content.
  final Map<String, String> hashes;

  /// The directories, the same way.
  final Set<String> directories;

  /// The files the generator did not write or that changed, sorted.
  final List<_Stray> strays;
}

/// The manifest of a generated tree: which files the generator wrote and
/// their hashes.
final class _Manifest {
  const _Manifest(this.hashes);

  /// The files by relative path; a hash is null where the manifest has none
  /// (a format before 2).
  final Map<String, String?> hashes;
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
/// A process killed while it swaps leaves the backup and the new tree in
/// sibling directories named `.<output>.typed_openapi-*`. The next run puts
/// the backup back when the output is missing, removes those directories
/// and says so (TOA832).
final class OutputWriter {
  /// Creates a writer that reports to [_diagnostics]; [_paths] names
  /// directories in diagnostics. [beforeInstall] is a test seam: it is
  /// called between the renames of the swap, where tests make a failure.
  const OutputWriter(
    this._diagnostics, [
    this._paths = const DisplayPaths(),
    this.beforeInstall,
  ]);

  /// The name of the manifest in the output directory.
  static const manifest = '.typed_openapi.json';

  /// The generator and its version, as the manifest names them.
  static const generator = 'typed_openapi 0.0.1';

  /// The format of the manifest, which it records as `format`: 2 lists every
  /// file with its hash, and `generate` deletes only files whose hash it
  /// still finds. A manifest without a format has no hash to rely on for a
  /// file where one is missing.
  static const manifestFormat = 2;

  /// What a manifest's `generator` starts with, whatever the version.
  static const _generatorName = 'typed_openapi';

  /// A test seam: called after the old directory is renamed to its backup
  /// and before the new one is renamed to the output, where a test makes
  /// the failure it wants. Production code leaves it null.
  @visibleForTesting
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
    bool force = false,
  }) {
    final root = p.normalize(p.absolute(client.output));
    final created = <Directory>[];
    Directory? staging;
    try {
      _recover(client, root);
      final keys = files.keys.toList()..sort();
      final hashes = {for (final path in keys) path: _hash(files[path]!)};
      final existing = _inspect(client, root, protected, hashes, force: force);
      if (existing == null) return null;
      final text = manifestOf(files, inputs: inputs);
      var written = 0;
      var unchanged = 0;
      for (final path in keys) {
        if (existing.hashes[path] == hashes[path]) {
          unchanged++;
        } else {
          written++;
        }
      }
      final deleted = existing.hashes.keys
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
          existing.hashes[manifest] == _hash(text) &&
          existing.directories.length == directories.length &&
          existing.directories.containsAll(directories);
      final changes = OutputChanges(
        written: written,
        unchanged: unchanged,
        deleted: deleted,
        forced: existing.strays.length,
      );
      if (same) return changes;
      final parent = Directory(p.dirname(root));
      for (final missing in _missing(parent)) {
        missing.createSync();
        created.add(missing);
      }
      staging = _createStaging(parent, root);
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
      for (final path in files.keys.toList()..sort()) path: _hash(files[path]!),
    };
    return '${const JsonEncoder.withIndent('  ').convert({
      'generator': generator,
      'format': manifestFormat,
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

  /// Cleans up after a run that was killed while it swapped: when [root] is
  /// missing and an earlier run left its backup (`.<name>.typed_openapi-*-old`,
  /// the newest if there are several), the backup becomes [root] again; every
  /// other directory with such a name is removed, a backup only when [root]
  /// holds a generated tree. Reports TOA832 when it did anything.
  void _recover(ClientConfig client, String root) {
    final parent = Directory(p.dirname(root));
    if (!parent.existsSync()) return;
    final name = RegExp(
      '^${RegExp.escape('.${p.basename(root)}.typed_openapi-')}'
      r'[A-Za-z0-9]+(-old)?$',
    );
    final leftovers = <Directory>[
      for (final entry in parent.listSync(followLinks: false))
        if (entry is Directory && name.hasMatch(p.basename(entry.path))) entry,
    ];
    if (leftovers.isEmpty) return;
    final backups = [
      for (final directory in leftovers)
        if (p.basename(directory.path).endsWith('-old')) directory,
    ]..sort((a, b) => a.path.compareTo(b.path));
    Directory? restored;
    if (FileSystemEntity.typeSync(root, followLinks: false) ==
            FileSystemEntityType.notFound &&
        backups.isNotEmpty) {
      restored = backups.reduce(
        (a, b) => b.statSync().modified.isBefore(a.statSync().modified) ? a : b,
      );
      restored.renameSync(root);
    }
    // A backup is the only copy of the old tree until the output holds a
    // finished one (a manifest), so it is kept otherwise.
    final installed = File(p.join(root, manifest)).existsSync();
    var removed = 0;
    for (final directory in leftovers) {
      if (directory.path == restored?.path) continue;
      if (backups.contains(directory) && !installed) continue;
      directory.deleteSync(recursive: true);
      removed++;
    }
    if (restored == null && removed == 0) return;
    _diagnostics.report(
      .outputRecovered,
      'An earlier run for client "${client.name}" was interrupted while it '
      'replaced ${_paths.of(root)}. ${restored == null ? '' : 'The previous '
                'output was restored from ${_paths.of(restored.path)}. '}'
      'Removed $removed temporary '
      '${removed == 1 ? 'directory' : 'directories'} it left.',
      file: _paths.of(root),
    );
  }

  /// Creates the directory the new tree is built in, next to [root] (so the
  /// swap is a rename). It is made like any directory, with the mode the
  /// umask gives (a temp directory would be private, `drwx------`), and gets
  /// the mode of [root] when that exists, so the swap keeps the permissions
  /// of the output. Ownership, ACLs and extended attributes are not copied.
  static Directory _createStaging(Directory parent, String root) {
    const letters =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    Directory staging;
    do {
      final suffix = [
        for (var i = 0; i < 8; i++) letters[random.nextInt(letters.length)],
      ].join();
      staging = Directory(
        p.join(parent.path, '.${p.basename(root)}.typed_openapi-$suffix'),
      );
    } while (staging.existsSync() ||
        FileSystemEntity.typeSync(staging.path, followLinks: false) !=
            FileSystemEntityType.notFound);
    staging.createSync();
    if (!Platform.isWindows && Directory(root).existsSync()) {
      final mode = Directory(root).statSync().mode & 0xfff;
      // Best effort: a directory that keeps another mode still works.
      Process.runSync('chmod', [mode.toRadixString(8), staging.path]);
    }
    return staging;
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
      if (hasOld) {
        try {
          backup.renameSync(root);
        } on FileSystemException catch (e) {
          throw FileSystemException(
            'the previous output could not be put back and is in '
            '${_paths.of(backup.path)}; move it to ${_paths.of(root)} by '
            'hand (${e.message})',
            e.path,
          );
        }
      }
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
  /// replace it (TOA830). [generated] has the hashes of the files the run
  /// writes: a file that already holds one is never lost, so it is no stray.
  /// With [force] strays are reported in the result instead of refused; a
  /// package, a link or an input of the run never are.
  _Existing? _inspect(
    ClientConfig client,
    String root,
    List<String> inputs,
    Map<String, String> generated, {
    required bool force,
  }) {
    _Existing? refuse(String why, String fix) {
      _diagnostics.report(
        .outputNotOwned,
        'Client "${client.name}" is not generated: its output directory '
        '${_paths.of(root)} $why.',
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
    final lengths = {
      for (final input in protected) input: File(input).lengthSync(),
    };
    final hashes = <String, String>{};
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
          hashes[path] = _hash(File(entry.path).readAsBytesSync());
      }
    }
    if (hashes.isEmpty) return _Existing(hashes, directories);
    final written = _readManifest(File(p.join(root, manifest)));
    final strays = <_Stray>[];
    for (final MapEntry(key: path, value: hash)
        in hashes.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
      if (generated[path] == hash) continue;
      if (path == manifest) {
        if (written == null) {
          strays.add(_Stray(path, 'not a manifest of $_generatorName'));
        }
        continue;
      }
      final stray = _strayReason(written, path, hash);
      if (stray != null) strays.add(_Stray(path, stray));
    }
    if (strays.isEmpty) return _Existing(hashes, directories);
    if (!force) {
      final others = [
        for (final stray in strays)
          if (stray.path != manifest || written != null) stray,
      ];
      final names = [
        for (final stray in others.take(8)) '${stray.path} (${stray.reason})',
        if (others.length > 8) 'and ${others.length - 8} more',
      ].join(', ');
      final list = names.isEmpty ? '' : ': $names';
      final hashless = strays.any((s) => s.reason.startsWith('no hash'));
      final why = written != null
          ? 'holds files that the generator did not write or that changed '
                'since it wrote them, and it would delete them$list'
          : hashes.containsKey(manifest)
          ? 'holds a $manifest that is not a manifest of $_generatorName, so '
                'its files were not written by it$list'
          : 'holds files but no $manifest, so they were not written by it'
                '$list';
      return refuse(
        why,
        hashless
            ? 'Run generate --force once: the manifest it writes has the '
                  'hash of every file.'
            : 'Move them out of the directory, or run generate --force to '
                  'replace them.',
      );
    }
    return _Existing(hashes, directories, strays);
  }

  /// Why the file [path] with [hash] is not the generator's to replace
  /// according to [written], or null when it is.
  static String? _strayReason(_Manifest? written, String path, String hash) {
    if (written == null || !written.hashes.containsKey(path)) {
      return 'not written by $_generatorName';
    }
    final listed = written.hashes[path];
    if (listed == null) {
      return 'no hash in the manifest of an older $_generatorName';
    }
    return listed == hash ? null : 'changed since $_generatorName wrote it';
  }

  /// The manifest in [file], or null when it is missing, does not parse or
  /// does not name this generator, in any version.
  static _Manifest? _readManifest(File file) {
    if (!file.existsSync()) return null;
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map<String, Object?> ||
          json['generator'] is! String ||
          !(json['generator']! as String).startsWith('$_generatorName ')) {
        return null;
      }
      final hash = RegExp(r'^[0-9a-f]{64}$');
      return _Manifest(switch (json['files']) {
        final Map<String, Object?> files => {
          for (final MapEntry(:key, :value) in files.entries)
            key: value is String && hash.hasMatch(value) ? value : null,
        },
        final List<Object?> names => {
          for (final name in names)
            if (name is String) name: null,
        },
        _ => const {},
      });
    } on FormatException {
      return null;
    }
  }

  /// The SHA-256 of [content], a `String` (as UTF-8) or bytes, in hex.
  static String _hash(Object content) => sha256
      .convert(content is String ? utf8.encode(content) : content as List<int>)
      .toString();

  /// Writes [content] to [path], creating its directory.
  static void _writeFile(String path, String content) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content, flush: true);
  }
}
