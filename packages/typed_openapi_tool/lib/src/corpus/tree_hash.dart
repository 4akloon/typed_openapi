import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// The SHA-256 of a directory tree: of the lines `<path>` and `<sha256>` of
/// every file, sorted by path, with `/` between segments on every system.
///
/// It pins a spec of several files whatever archive brought them: the bytes
/// of a downloaded archive may change while its files do not.
final class TreeHash {
  /// Creates the hash function.
  const TreeHash();

  /// The hash of the files under [directory].
  String of(String directory) => combine(files(directory));

  /// The hash of each file under [directory], by its path relative to it
  /// with `/` separators, sorted by path.
  Map<String, String> files(String directory) {
    final paths = <String, String>{};
    for (final entity in Directory(directory).listSync(recursive: true)) {
      if (entity is! File) continue;
      final relative = p
          .relative(entity.path, from: directory)
          .replaceAll(r'\', '/');
      paths[relative] = sha256.convert(entity.readAsBytesSync()).toString();
    }
    return Map.fromEntries(
      paths.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  /// The hash of [files], a map from a path to the hash of its file.
  String combine(Map<String, String> files) {
    final lines = StringBuffer();
    for (final MapEntry(key: path, value: hash)
        in files.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
      lines
        ..writeln(path)
        ..writeln(hash);
    }
    return sha256.convert(utf8.encode(lines.toString())).toString();
  }
}
