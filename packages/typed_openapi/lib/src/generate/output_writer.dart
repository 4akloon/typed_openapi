import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../config/project_config.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/display_paths.dart';
import 'existing_output.dart';
import 'generated_tree.dart';
import 'lock_acquirer.dart';
import 'output_changes.dart';
import 'output_inspector.dart';
import 'output_installer.dart';
import 'output_lock.dart';
import 'output_manifest.dart';
import 'output_parents.dart';
import 'output_recovery.dart';
import 'output_target.dart';
import 'process_runner.dart';
import 'tree_remover.dart';

export 'output_changes.dart';

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
/// process is gone is taken over (TOA832), and `breakLock` takes over one
/// whose owner cannot be told; neither replaces files, which `force` does.
///
/// A process killed while it swaps leaves the backup and the new tree in
/// sibling directories named `.<output>.typed_openapi-<8 letters or
/// digits>`, with `-old` for the backup. Under the lock, once the output has
/// been checked as above, the next run puts the backup back when the output
/// is missing, removes those directories and says so (TOA832); it leaves
/// alone a directory that holds an input of the run.
final class OutputWriter {
  /// Creates a writer that reports to [diagnostics]; [paths] names
  /// directories in diagnostics.
  OutputWriter(
    DiagnosticBag diagnostics, [
    DisplayPaths paths = const DisplayPaths(),
  ]) : this._(diagnostics, paths, null, _runSystem);

  /// Creates a writer for a test: [beforeInstall] is called between the
  /// renames of the swap, and [run] starts the processes the writer needs
  /// (`chmod`, `kill`), so a test can make either fail.
  @visibleForTesting
  OutputWriter.forTesting(
    DiagnosticBag diagnostics, {
    DisplayPaths paths = const DisplayPaths(),
    void Function()? beforeInstall,
    ProcessResult Function(String executable, List<String> arguments)? run,
  }) : this._(diagnostics, paths, beforeInstall, run ?? _runSystem);

  OutputWriter._(
    this._diagnostics,
    this._paths,
    this.beforeInstall,
    ProcessRunner run,
  ) : _locks = LockAcquirer(_diagnostics, _paths, run),
      _recovery = OutputRecovery(_diagnostics, _paths, TreeRemover(run)),
      _inspector = OutputInspector(_diagnostics, _paths),
      _installer = OutputInstaller(
        _diagnostics,
        _paths,
        TreeRemover(run),
        run,
        beforeInstall,
      );

  /// The name of the manifest in the output directory.
  static const manifest = OutputManifest.fileName;

  /// The generator and its version, as the manifest names them.
  static const generator = OutputManifest.generator;

  /// The format of the manifest, which it records as `format`: 2 lists every
  /// file with its hash, and `generate` deletes only files whose hash it
  /// still finds. A manifest without a format has no hash to rely on for a
  /// file where one is missing.
  static const manifestFormat = OutputManifest.format;

  /// Called after the old directory is renamed to its backup and before the
  /// new one is renamed to the output, where a test makes the failure it
  /// wants; null outside tests ([OutputWriter.forTesting]).
  final void Function()? beforeInstall;

  final DiagnosticBag _diagnostics;
  final DisplayPaths _paths;
  final LockAcquirer _locks;
  final OutputRecovery _recovery;
  final OutputInspector _inspector;
  final OutputInstaller _installer;

  static ProcessResult _runSystem(String executable, List<String> arguments) =>
      Process.runSync(executable, arguments);

  /// Writes [files] (paths relative to the output directory of [client])
  /// and the manifest with [inputs], the hash of what they were generated
  /// from; [protected] are the input files of the run, which the directory
  /// must not hold. With [force] a file the generator did not write, or that
  /// changed since do not stop the run, and each one it replaces is reported
  /// (TOA833); [breakLock] takes over a lock whose owner cannot be told, and
  /// never replaces a file. Returns null after reporting why nothing was
  /// written.
  OutputChanges? write(
    ClientConfig client,
    Map<String, String> files, {
    required String inputs,
    List<String> protected = const [],
    bool force = false,
    bool breakLock = false,
  }) {
    final target = OutputTarget(client, protected);
    final parents = OutputParents(target.parent);
    OutputLock? lock;
    try {
      parents.create();
      lock = _locks.acquire(target, breakLock: breakLock);
      if (lock == null) return null;
      return _generate(
        target,
        GeneratedTree(files, inputs: inputs),
        parents,
        force: force,
      );
    } on FileSystemException catch (e) {
      _reportNotWritten(target, e);
      return null;
    } finally {
      lock?.release();
      parents.removeCreated();
    }
  }

  /// The manifest of [files] generated from [inputs]: JSON with sorted
  /// keys, the same for the same files.
  static String manifestOf(
    Map<String, String> files, {
    required String inputs,
  }) => GeneratedTree(files, inputs: inputs).manifest;

  /// Replaces the output of [target] with [tree] under the lock, unless it
  /// holds that tree already; null after reporting why it may not.
  OutputChanges? _generate(
    OutputTarget target,
    GeneratedTree tree,
    OutputParents parents, {
    required bool force,
  }) {
    final existing = _checkExisting(target, tree, force: force);
    if (existing == null) return null;
    final changes = tree.changesFrom(existing);
    if (tree.isInstalledIn(existing, changes)) return changes;
    _installer.replace(target.root, tree);
    parents.keep();
    _reportReplaced(target, tree, existing);
    return changes;
  }

  /// What the output of [target] holds, after the leftovers of a killed run
  /// are cleaned up; null after reporting why the generator may not replace
  /// it.
  ExistingOutput? _checkExisting(
    OutputTarget target,
    GeneratedTree tree, {
    required bool force,
  }) {
    // What a killed run left, found before anything is looked into, and
    // changed only once the output (or the backup that would become it)
    // has been checked.
    final leftovers = _recovery.leftovers(target);
    final backup = OutputRecovery.restorable(target.root, leftovers);
    final existing = _inspector.inspect(
      target,
      backup?.path ?? target.root,
      tree,
      force: force,
    );
    if (existing == null) return null;
    _recovery.recover(target, leftovers, backup);
    return existing;
  }

  /// Reports every file that `force` replaced or deleted (TOA833).
  void _reportReplaced(
    OutputTarget target,
    GeneratedTree tree,
    ExistingOutput existing,
  ) {
    final root = target.root;
    for (final stray in existing.strays) {
      _diagnostics.report(
        .outputFileReplaced,
        '${tree.files.containsKey(stray.path) ? 'Overwrote' : 'Deleted'} '
        '${stray.path} (${stray.reason}) in ${_paths.of(root)} because of '
        '--force.',
        file: _paths.of(p.join(root, stray.path)),
      );
    }
  }

  /// Reports that [target] could not be written because of [error] (TOA831).
  void _reportNotWritten(OutputTarget target, FileSystemException error) {
    final root = target.root;
    final path = error.path;
    _diagnostics.report(
      .outputNotWritten,
      'Cannot write the output of client "${target.client.name}" to '
      '${_paths.of(root)}: ${error.message}${path == null ? '' : ' (${_paths.of(path)})'}.',
      file: _paths.of(root),
      fix:
          'Check that the directory can be written, then run generate '
          'again.',
    );
  }
}
