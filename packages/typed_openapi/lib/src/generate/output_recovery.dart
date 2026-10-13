import 'dart:io';

import 'package:path/path.dart' as p;

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/display_paths.dart';
import 'output_manifest.dart';
import 'output_target.dart';
import 'real_paths.dart';
import 'tree_remover.dart';

/// Finds and cleans up what a run killed while it swapped left behind.
final class OutputRecovery {
  /// Creates a recovery that reports to the bag and removes trees with the
  /// remover.
  OutputRecovery(this._diagnostics, this._paths, this._remover);

  /// What a leftover of a killed run is called, after its leading dot, the
  /// name of the output and `.typed_openapi-`: eight letters or digits, and
  /// `-old` for a backup.
  static final _leftover = RegExp(r'^[A-Za-z0-9]{8}(-old)?$');

  final DiagnosticBag _diagnostics;
  final DisplayPaths _paths;
  final TreeRemover _remover;

  /// The directories next to the output of [target] that a killed run left
  /// (`.<name>.typed_openapi-<8 characters>[-old]`), sorted by name, except
  /// those that hold an input of the run: such a name may be the user's own,
  /// and an input is never deleted, restored or touched.
  List<Directory> leftovers(OutputTarget target) {
    final parent = target.parent;
    if (!parent.existsSync()) return const [];
    final prefix = '.${p.basename(target.root)}.typed_openapi-';
    final inputs = target.presentInputs;
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

  /// The backup that becomes [root] again: [root] is missing and a run that
  /// was killed while it swapped left backups among [leftovers]; the newest.
  static Directory? restorable(String root, List<Directory> leftovers) {
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
  /// output has been checked: [restore], when given, becomes the output of
  /// [target] again, and every directory of [leftovers] is removed, a backup
  /// only when the output holds a finished tree (a manifest), since it is the
  /// only copy of the old tree until then. Reports TOA832 when it did
  /// anything.
  void recover(
    OutputTarget target,
    List<Directory> leftovers,
    Directory? restore,
  ) {
    if (leftovers.isEmpty) return;
    final root = target.root;
    restore?.renameSync(root);
    final installed = File(p.join(root, OutputManifest.fileName)).existsSync();
    var removed = 0;
    for (final directory in leftovers) {
      if (directory.path == restore?.path) continue;
      if (p.basename(directory.path).endsWith('-old') && !installed) continue;
      _remover.remove(directory);
      removed++;
    }
    if (restore == null && removed == 0) return;
    _diagnostics.report(
      .outputRecovered,
      'An earlier run for client "${target.client.name}" was interrupted while '
      'it replaced ${_paths.of(root)}. ${restore == null ? '' : 'The previous '
                'output was restored from ${_paths.of(restore.path)}. '}'
      'Removed $removed temporary '
      '${removed == 1 ? 'directory' : 'directories'} it left.',
      file: _paths.of(root),
    );
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
}
