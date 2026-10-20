import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../paths/real_paths.dart';

/// The lock of an output: the file and what this run wrote into it.
final class OutputLock {
  /// Creates the lock of this run for the lock [file], with a content that
  /// identifies the run.
  OutputLock(this.file)
    : content = jsonEncode({
        'pid': pid,
        'host': Platform.localHostname,
        'id': Random.secure().nextInt(1 << 32).toRadixString(36),
      });

  /// The lock file, `.<output>.typed_openapi.lock` next to the output.
  final File file;

  /// What identifies this run in the file.
  final String content;

  /// The lock file of the output [root]: next to it, so it is there before
  /// the output is and is not part of it; a file system that ignores case
  /// gets one name whatever the case of the output's.
  static File fileOf(String root) {
    final resolved = RealPaths.resolve(root);
    var name = p.basename(resolved);
    if (RealPaths.isCaseInsensitive(resolved)) name = name.toLowerCase();
    return File(p.join(p.dirname(resolved), '.$name.typed_openapi.lock'));
  }

  /// Creates the lock file exclusively and writes this run into it; throws
  /// a [PathExistsException] when another run holds it.
  void create() {
    file.createSync(exclusive: true);
    file.writeAsStringSync(content, flush: true);
  }

  /// Removes the lock of this run, unless another run broke and replaced it.
  void release() {
    try {
      if (file.readAsStringSync() == content) file.deleteSync();
    } on FileSystemException {
      // Gone already.
    }
  }
}
