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

/// The lock of an output: the file and what this run wrote into it.
final class _Lock {
  _Lock(this.file)
    : content = jsonEncode({
        'pid': pid,
        'host': Platform.localHostname,
        'id': Random.secure().nextInt(1 << 32).toRadixString(36),
      });

  /// The lock file, `.<output>.typed_openapi.lock` next to the output.
  final File file;

  /// What identifies this run in the file.
  final String content;
}

/// What a lock file says about the run that holds it.
final class _Held {
  _Held(this.text) {
    try {
      if (jsonDecode(text) case {
        'pid': final int pid,
        'host': final String host,
      }) {
        this.pid = pid;
        this.host = host;
      }
    } on FormatException {
      // An empty or foreign file: the process stays unknown.
    }
  }

  /// The content of the lock file.
  final String text;

  /// The process id it names, or null.
  int? pid;

  /// The host it names, or null.
  String? host;

  /// The holder, as a message says it.
  String get describe => pid == null
      ? 'a lock file typed_openapi did not write'
      : 'process $pid on $host';

  @override
  bool operator ==(Object other) => other is _Held && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

/// Writes the generated files of a client into its output directory (decisions
/// 15 and 17 of M8).
///
/// A run is atomic: the whole new tree and its manifest are built in a
/// temporary directory next to the output, which is then swapped in (the old
/// directory is renamed to a backup, the new one to the output, the backup
/// is removed). Any failure puts the old directory back, so the output is
/// the previous run's or the new one, never a mix, and a failed first run
/// leaves nothing. A run that would change nothing does not touch the
/// directory. The manifest lists the generator, its format, a hash of the
/// inputs and every file with its hash.
///
/// The generator replaces only what it wrote: a file of the old directory
/// that the manifest does not list, or whose hash differs from the
/// manifest's, is foreign or modified, and the directory is refused (TOA830,
/// nothing is written, the message names the files) unless `force` is set.
/// A directory is refused whatever `force` says when it holds a
/// `pubspec.yaml`, is the `lib` directory of a package, holds a symbolic
/// link or holds an input of the run (the config, the spec, the overrides or
/// the baseline file, also through a symbolic link, a hard link or a name
/// that differs in case).
///
/// One run at a time works on an output: it holds the lock file
/// `.<output>.typed_openapi.lock` next to it, created exclusively and naming
/// its process. A second run gets TOA831 and changes nothing; a lock whose
/// process is gone is taken over (TOA832), and `force` breaks any lock.
///
/// A process killed while it swaps leaves the backup and the new tree in
/// sibling directories named `.<output>.typed_openapi-<8 letters or
/// digits>`, with `-old` for the backup. Under the lock, once the output has
/// been checked as above, the next run puts the backup back when the output
/// is missing, removes those directories and says so (TOA832); it leaves
/// alone a directory that holds an input of the run.
final class OutputWriter {
  /// Creates a writer that reports to [_diagnostics]; [_paths] names
  /// directories in diagnostics.
  OutputWriter(this._diagnostics, [this._paths = const DisplayPaths()])
    : beforeInstall = null,
      _run = _runSystem;

  /// Creates a writer for a test: [beforeInstall] is called between the
  /// renames of the swap, and [run] starts the processes the writer needs
  /// (`chmod`, `kill`), so a test can make either fail.
  @visibleForTesting
  OutputWriter.forTesting(
    this._diagnostics, {
    DisplayPaths paths = const DisplayPaths(),
    this.beforeInstall,
    ProcessResult Function(String executable, List<String> arguments)? run,
  }) : _paths = paths,
       _run = run ?? _runSystem;

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

  /// What a leftover of a killed run is called, after its leading dot, the
  /// name of the output and `.typed_openapi-`: eight letters or digits, and
  /// `-old` for a backup.
  static final _leftover = RegExp(r'^[A-Za-z0-9]{8}(-old)?$');

  /// Called after the old directory is renamed to its backup and before the
  /// new one is renamed to the output, where a test makes the failure it
  /// wants; null outside tests ([OutputWriter.forTesting]).
  final void Function()? beforeInstall;

  final DiagnosticBag _diagnostics;
  final DisplayPaths _paths;
  final ProcessResult Function(String, List<String>) _run;

  static ProcessResult _runSystem(String executable, List<String> arguments) =>
      Process.runSync(executable, arguments);

  /// Writes [files] (paths relative to the output directory of [client])
  /// and the manifest with [inputs], the hash of what they were generated
  /// from; [protected] are the input files of the run, which the directory
  /// must not hold. With [force] a file the generator did not write, or that
  /// changed since, and a lock another run holds do not stop the run.
  /// Returns null after reporting why nothing was written.
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
    _Lock? lock;
    try {
      final parent = Directory(p.dirname(root));
      for (final missing in _missing(parent)) {
        missing.createSync();
        created.add(missing);
      }
      lock = _acquire(client, root, force: force);
      if (lock == null) return null;
      final keys = files.keys.toList()..sort();
      final hashes = {for (final path in keys) path: _hash(files[path]!)};
      // What a killed run left, found before anything is looked into, and
      // changed only once the output (or the backup that would become it)
      // has been checked.
      final leftovers = _leftovers(root, protected);
      final backup = _restorable(root, leftovers);
      final existing = _inspect(
        client,
        root,
        backup?.path ?? root,
        protected,
        hashes,
        force: force,
      );
      if (existing == null) return null;
      _recover(client, root, leftovers, backup);
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
      staging = _createStaging(parent, root);
      for (final path in keys) {
        _writeFile(p.join(staging.path, path), files[path]!);
      }
      _writeFile(p.join(staging.path, manifest), text);
      // The mode comes last: a read-only output would refuse the files.
      _copyMode(staging, root);
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
      _release(lock);
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

  /// The lock file of the output [root]: next to it, so it is there before
  /// the output is and is not part of it; a file system that ignores case
  /// gets one name whatever the case of the output's.
  static File _lockFile(String root) {
    final resolved = RealPaths.resolve(root);
    var name = p.basename(resolved);
    if (RealPaths.isCaseInsensitive(resolved)) name = name.toLowerCase();
    return File(p.join(p.dirname(resolved), '.$name.typed_openapi.lock'));
  }

  /// Takes the lock of [root] by creating its file exclusively, and returns
  /// it; null after reporting TOA831 when another run holds it. A lock of a
  /// process that is gone (it is on this host and no longer exists) is taken
  /// over, and [force] breaks any other, both with TOA832.
  _Lock? _acquire(ClientConfig client, String root, {required bool force}) {
    final file = _lockFile(root);
    final lock = _Lock(file);
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        file.createSync(exclusive: true);
        file.writeAsStringSync(lock.content, flush: true);
        return lock;
      } on PathExistsException {
        final held = _readLock(file);
        if (held == null) continue; // Released in the meantime.
        final alive = _isAlive(held);
        if (alive != false && !force) {
          _lockHeld(client, root, file, held, knownAlive: alive == true);
          return null;
        }
        // Another process may have replaced it since: delete only what was
        // looked at.
        if (_readLock(file) == held) file.deleteSync();
        _diagnostics.report(
          .outputRecovered,
          'Took over the lock ${_paths.of(file.path)} of client '
          '"${client.name}", ${alive == false ? 'which ${held.describe} had '
                    'left behind: that process is gone' : 'which ${held.describe} '
                    'held: --force breaks it'}.',
          file: _paths.of(root),
        );
      }
    }
    _diagnostics.report(
      .outputNotWritten,
      'Cannot take the lock ${_paths.of(file.path)} of client '
      '"${client.name}": it keeps coming back.',
      file: _paths.of(root),
      fix: 'Check whether another generate runs on this output.',
    );
    return null;
  }

  void _lockHeld(
    ClientConfig client,
    String root,
    File file,
    _Held held, {
    required bool knownAlive,
  }) {
    _diagnostics.report(
      .outputNotWritten,
      'Client "${client.name}" is not generated: another typed_openapi run '
      'holds the lock ${_paths.of(file.path)} of its output '
      '${_paths.of(root)} (${held.describe}'
      '${knownAlive ? ', which is running' : '; it cannot be told whether '
                'that process still runs'}). Nothing was changed.',
      file: _paths.of(root),
      fix:
          'Wait for it to finish. If no run is going, delete '
          '${_paths.of(file.path)}, or run generate --force, which breaks '
          'the lock.',
    );
  }

  /// What the lock [file] says, or null when it is gone.
  static _Held? _readLock(File file) {
    try {
      return _Held(file.readAsStringSync());
    } on FileSystemException {
      return null;
    } on FormatException {
      return _Held('');
    }
  }

  /// Whether the process that wrote [held] still runs: true or false when
  /// that can be told, null when it cannot (another host, no readable pid, a
  /// system with no `kill`).
  bool? _isAlive(_Held held) {
    final process = held.pid;
    if (process == null || held.host != Platform.localHostname) return null;
    if (process == pid) return true;
    if (Platform.isWindows) return null;
    try {
      final result = _run('kill', ['-0', '$process']);
      if (result.exitCode == 0) return true;
      return '${result.stderr}'.contains('No such process') ? false : null;
    } on ProcessException {
      return null;
    }
  }

  /// Removes the lock of this run, unless another run broke and replaced it.
  static void _release(_Lock? lock) {
    if (lock == null) return;
    try {
      if (lock.file.readAsStringSync() == lock.content) lock.file.deleteSync();
    } on FileSystemException {
      // Gone already.
    }
  }

  /// The directories next to [root] that a killed run left
  /// (`.<name>.typed_openapi-<8 characters>[-old]`), sorted by name, except
  /// those that hold an input of the run: such a name may be the user's own,
  /// and an input is never deleted, restored or touched.
  List<Directory> _leftovers(String root, List<String> protected) {
    final parent = Directory(p.dirname(root));
    if (!parent.existsSync()) return const [];
    final prefix = '.${p.basename(root)}.typed_openapi-';
    final inputs = [
      for (final input in protected)
        if (File(input).existsSync()) input,
    ];
    return [
      for (final entry in parent.listSync(followLinks: false))
        if (entry is Directory &&
            p.basename(entry.path).startsWith(prefix) &&
            _leftover.hasMatch(
              p.basename(entry.path).substring(prefix.length),
            ) &&
            !_holdsInput(entry, inputs))
          entry,
    ]..sort((a, b) => a.path.compareTo(b.path));
  }

  /// Whether [directory] holds, or is, one of [inputs], by location or, for
  /// a file whose location differs (a hard link), by identity.
  static bool _holdsInput(Directory directory, List<String> inputs) {
    if (inputs.isEmpty) return false;
    for (final input in inputs) {
      if (RealPaths.equals(directory.path, input) ||
          RealPaths.isWithin(directory.path, input)) {
        return true;
      }
    }
    final lengths = {
      for (final input in inputs) input: File(input).lengthSync(),
    };
    for (final entry in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entry is! File) continue;
      final length = entry.lengthSync();
      for (final MapEntry(key: input, value: size) in lengths.entries) {
        if (length == size &&
            FileSystemEntity.identicalSync(entry.path, input)) {
          return true;
        }
      }
    }
    return false;
  }

  /// The backup that becomes [root] again: [root] is missing and a run that
  /// was killed while it swapped left backups among [leftovers]; the newest.
  static Directory? _restorable(String root, List<Directory> leftovers) {
    if (FileSystemEntity.typeSync(root, followLinks: false) !=
        FileSystemEntityType.notFound) {
      return null;
    }
    final backups = [
      for (final directory in leftovers)
        if (p.basename(directory.path).endsWith('-old')) directory,
    ];
    if (backups.isEmpty) return null;
    return backups.reduce(
      (a, b) => b.statSync().modified.isBefore(a.statSync().modified) ? a : b,
    );
  }

  /// Cleans up after a run that was killed while it swapped, once the
  /// output has been checked: [restore], when given, becomes [root] again,
  /// and every directory of [leftovers] is removed, a backup only when
  /// [root] holds a finished tree (a manifest), since it is the only copy of
  /// the old tree until then. Reports TOA832 when it did anything.
  void _recover(
    ClientConfig client,
    String root,
    List<Directory> leftovers,
    Directory? restore,
  ) {
    if (leftovers.isEmpty) return;
    restore?.renameSync(root);
    final installed = File(p.join(root, manifest)).existsSync();
    var removed = 0;
    for (final directory in leftovers) {
      if (directory.path == restore?.path) continue;
      if (p.basename(directory.path).endsWith('-old') && !installed) continue;
      _removeTree(directory);
      removed++;
    }
    if (restore == null && removed == 0) return;
    _diagnostics.report(
      .outputRecovered,
      'An earlier run for client "${client.name}" was interrupted while it '
      'replaced ${_paths.of(root)}. ${restore == null ? '' : 'The previous '
                'output was restored from ${_paths.of(restore.path)}. '}'
      'Removed $removed temporary '
      '${removed == 1 ? 'directory' : 'directories'} it left.',
      file: _paths.of(root),
    );
  }

  /// Creates the directory the new tree is built in, next to [root] (so the
  /// swap is a rename). It is made like any directory, with the mode the
  /// umask gives (a temp directory would be private, `drwx------`).
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
    return staging;
  }

  /// Gives [staging] the mode of [root], when that exists and differs, so
  /// the swap keeps the permissions of the output. Ownership, ACLs and
  /// extended attributes are not copied. There is no `dart:io` call for a
  /// mode, so it runs `chmod`; when that is missing or fails, the run fails
  /// (a [FileSystemException], TOA831) instead of changing the permissions.
  void _copyMode(Directory staging, String root) {
    if (Platform.isWindows || !Directory(root).existsSync()) return;
    final mode = Directory(root).statSync().mode & 0xfff;
    if (staging.statSync().mode & 0xfff == mode) return;
    final ProcessResult result;
    try {
      result = _run('chmod', [mode.toRadixString(8), staging.path]);
    } on ProcessException catch (e) {
      throw FileSystemException(
        'cannot give the new directory the mode of the old one, since '
        '${e.executable} cannot be run (${e.message})',
        root,
      );
    }
    if (result.exitCode != 0) {
      throw FileSystemException(
        'cannot give the new directory the mode of the old one '
        '(chmod: ${'${result.stderr}'.trim()})',
        root,
      );
    }
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
        _removeTree(backup);
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

  /// Deletes [directory] with everything in it. A read-only directory (an
  /// output with the mode 555) cannot lose its files, so on a failure it is
  /// made writable, as far as `chmod` can, and deleted again.
  void _removeTree(Directory directory) {
    try {
      directory.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      if (Platform.isWindows) rethrow;
    }
    try {
      _run('chmod', ['u+rwx', directory.path]);
    } on ProcessException {
      // The deletion below says what is wrong.
    }
    directory.deleteSync(recursive: true);
  }

  /// Removes the temporary directory [directory] of a failed run.
  void _discard(Directory? directory) {
    if (directory == null) return;
    try {
      if (directory.existsSync()) _removeTree(directory);
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
    String dir,
    List<String> inputs,
    Map<String, String> generated, {
    required bool force,
  }) {
    final subject = dir == root
        ? 'its output directory ${_paths.of(root)}'
        : 'the backup ${_paths.of(dir)} of its output directory '
              '${_paths.of(root)}';
    _Existing? refuse(String why, String fix) {
      _diagnostics.report(
        .outputNotOwned,
        'Client "${client.name}" is not generated: $subject $why.',
        file: _paths.of(root),
        fix: fix,
      );
      return null;
    }

    const move =
        'Point output to a directory of its own, such as '
        'lib/src/<client>.';
    final type = FileSystemEntity.typeSync(dir, followLinks: false);
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
    if (File(p.join(dir, 'pubspec.yaml')).existsSync()) {
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
      if (RealPaths.isWithin(dir, input)) {
        return refuse('holds ${_paths.of(input)}, an input of the run', move);
      }
    }
    final entries = Directory(
      dir,
    ).listSync(recursive: true, followLinks: false);
    final lengths = {
      for (final input in protected) input: File(input).lengthSync(),
    };
    final hashes = <String, String>{};
    final directories = <String>{};
    for (final entry in entries) {
      final path = p.posix.joinAll(p.split(p.relative(entry.path, from: dir)));
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
    final written = _readManifest(File(p.join(dir, manifest)));
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
