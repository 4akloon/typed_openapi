import 'dart:io';

/// The parent directories of an output that a run had to create: they are
/// removed again, while empty, unless the run installed its output.
final class OutputParents {
  /// Creates the parents of an output that is in the given directory.
  OutputParents(this._directory);

  final Directory _directory;
  final _created = <Directory>[];

  /// Creates [_directory] and every missing directory above it.
  void create() {
    for (final missing in _missing()) {
      missing.createSync();
      _created.add(missing);
    }
  }

  /// Keeps what [create] made: the output lives in it now.
  void keep() => _created.clear();

  /// Removes what [create] made, innermost first, when it is empty.
  void removeCreated() {
    for (final directory in _created.reversed) {
      try {
        directory.deleteSync();
      } on FileSystemException {
        // Not empty or not ours any more: it stays.
      }
    }
  }

  /// The directories above [_directory] that do not exist, outermost first,
  /// then [_directory] itself if it does not exist.
  List<Directory> _missing() {
    final result = <Directory>[];
    var current = _directory.absolute;
    while (!current.existsSync()) {
      result.add(current);
      final parent = current.parent;
      if (parent.path == current.path) break;
      current = parent;
    }
    return result.reversed.toList();
  }
}
