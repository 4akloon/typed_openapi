import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/display_paths.dart';
import 'generated_tree.dart';
import 'output_manifest.dart';
import 'process_runner.dart';
import 'tree_remover.dart';

/// Builds the new tree next to the output and swaps it in.
final class OutputInstaller {
  /// Creates an installer; the hook is called between the renames of the
  /// swap, and the runner starts `chmod`.
  OutputInstaller(
    this._diagnostics,
    this._paths,
    this._remover,
    this._run,
    this._beforeInstall,
  );

  final DiagnosticBag _diagnostics;
  final DisplayPaths _paths;
  final TreeRemover _remover;
  final ProcessRunner _run;
  final void Function()? _beforeInstall;

  /// Builds [tree] and its manifest in a temporary directory next to [root]
  /// and swaps it in as [root]. The temporary directory is removed when the
  /// run fails.
  void replace(String root, GeneratedTree tree) {
    final staging = _createStaging(root);
    try {
      for (final MapEntry(key: path, value: content) in tree.entries) {
        _writeFile(p.join(staging.path, path), content);
      }
      _writeFile(p.join(staging.path, OutputManifest.fileName), tree.manifest);
      // The mode comes last: a read-only output would refuse the files.
      _copyMode(staging, root);
      _swap(staging, root, hasOld: Directory(root).existsSync());
    } on Object {
      _remover.discard(staging);
      rethrow;
    }
  }

  /// Creates the directory the new tree is built in, next to [root] (so the
  /// swap is a rename). It is made like any directory, with the mode the
  /// umask gives (a temp directory would be private, `drwx------`).
  static Directory _createStaging(String root) {
    const letters =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    Directory staging;
    do {
      final suffix = [
        for (var i = 0; i < 8; i++) letters[random.nextInt(letters.length)],
      ].join();
      staging = Directory(
        p.join(p.dirname(root), '.${p.basename(root)}.typed_openapi-$suffix'),
      );
    } while (staging.existsSync() ||
        FileSystemEntity.typeSync(staging.path, followLinks: false) !=
            FileSystemEntityType.notFound);
    staging.createSync();
    return staging;
  }

  /// Writes [content] to [path], creating its directory.
  static void _writeFile(String path, String content) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content, flush: true);
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
  void _swap(Directory staging, String root, {required bool hasOld}) {
    final backup = Directory('${staging.path}-old');
    if (hasOld) Directory(root).renameSync(backup.path);
    try {
      _beforeInstall?.call();
      staging.renameSync(root);
    } on Object {
      if (hasOld) _putBack(backup, root);
      rethrow;
    }
    if (hasOld) _removeBackup(backup, root);
  }

  /// Moves [backup] back to [root] after a failed swap.
  void _putBack(Directory backup, String root) {
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

  /// Removes the [backup] of the old output once the new one is in place.
  void _removeBackup(Directory backup, String root) {
    try {
      _remover.remove(backup);
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
