import 'dart:io';

import 'process_runner.dart';

/// Deletes directory trees.
final class TreeRemover {
  /// Creates a remover that starts `chmod` with the runner.
  TreeRemover(this._run);

  final ProcessRunner _run;

  /// Deletes [directory] with everything in it. A read-only directory (an
  /// output with the mode 555) cannot lose its files, so on a failure it is
  /// made writable, as far as `chmod` can, and deleted again.
  void remove(Directory directory) {
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
  void discard(Directory? directory) {
    if (directory == null) return;
    try {
      if (directory.existsSync()) remove(directory);
    } on FileSystemException {
      // Nothing more to do for a directory that cannot be removed.
    }
  }
}
