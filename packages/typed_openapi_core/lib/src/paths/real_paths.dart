import 'dart:io';

import 'package:path/path.dart' as p;

/// Compares paths as the file system does: symbolic links are resolved, and
/// case is ignored on a file system that ignores it.
///
/// A path that does not exist yet is resolved through its nearest existing
/// ancestor, so the place a directory will be created compares like one
/// that exists. Nothing here writes to the file system.
final class RealPaths {
  const RealPaths._();

  /// [path] as an absolute, normalized path whose existing part has no
  /// symbolic link: the longest existing prefix is resolved, the rest is
  /// appended as written.
  static String resolve(String path) {
    final absolute = p.normalize(p.absolute(path));
    var existing = absolute;
    final rest = <String>[];
    while (true) {
      if (FileSystemEntity.typeSync(existing, followLinks: false) !=
          FileSystemEntityType.notFound) {
        try {
          existing = File(existing).resolveSymbolicLinksSync();
        } on FileSystemException {
          // A link to nowhere: it stays as written.
        }
        break;
      }
      final parent = p.dirname(existing);
      if (parent == existing) break;
      rest.add(p.basename(existing));
      existing = parent;
    }
    return p.normalize(p.joinAll([existing, ...rest.reversed]));
  }

  /// Whether the file system that holds [path] ignores the case of names.
  ///
  /// It looks at the nearest existing ancestor of [path] whose name has a
  /// letter, and asks whether the name with its case swapped is the same
  /// directory; a file system is never assumed from the platform.
  static bool isCaseInsensitive(String path) {
    var current = resolve(path);
    while (true) {
      if (FileSystemEntity.typeSync(current, followLinks: false) !=
          FileSystemEntityType.notFound) {
        final name = p.basename(current);
        final swapped = name == name.toLowerCase()
            ? name.toUpperCase()
            : name.toLowerCase();
        if (swapped != name) {
          final other = p.join(p.dirname(current), swapped);
          return FileSystemEntity.typeSync(other, followLinks: false) !=
                  FileSystemEntityType.notFound &&
              FileSystemEntity.identicalSync(current, other);
        }
      }
      final parent = p.dirname(current);
      if (parent == current) return false;
      current = parent;
    }
  }

  /// Whether [a] and [b] are the same place.
  static bool equals(String a, String b) {
    final (x, y) = _keys(a, b);
    return p.equals(x, y);
  }

  /// Whether [child] is inside [parent], not the same place.
  static bool isWithin(String parent, String child) {
    final (x, y) = _keys(parent, child);
    return p.isWithin(x, y);
  }

  /// Whether directories [a] and [b] are the same or one is inside the
  /// other.
  static bool overlap(String a, String b) {
    final (x, y) = _keys(a, b);
    return p.equals(x, y) || p.isWithin(x, y) || p.isWithin(y, x);
  }

  /// The resolved paths, lower-cased when either file system ignores case.
  static (String, String) _keys(String a, String b) {
    final x = resolve(a);
    final y = resolve(b);
    return isCaseInsensitive(a) || isCaseInsensitive(b)
        ? (x.toLowerCase(), y.toLowerCase())
        : (x, y);
  }
}
