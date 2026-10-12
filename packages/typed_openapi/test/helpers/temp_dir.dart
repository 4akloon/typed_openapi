import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A temp directory that is deleted after the current test.
final class TempDir {
  /// Creates the directory and schedules its removal.
  TempDir()
    : directory = Directory.systemTemp.createTempSync('typed_openapi_test_') {
    addTearDown(() => directory.deleteSync(recursive: true));
  }

  /// The created directory.
  final Directory directory;

  /// The path of [directory].
  String get path => directory.path;

  /// Writes [content] to [relativePath] under [directory]; returns the full
  /// path.
  String write(String relativePath, String content) {
    final file = File(p.join(path, relativePath))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
    return file.path;
  }

  /// Creates a symbolic link at [relativePath] to [target], a path relative
  /// to [directory]; returns the link's path.
  String link(String relativePath, String target) {
    final link = Link(p.join(path, relativePath))
      ..parent.createSync(recursive: true)
      ..createSync(p.join(path, target));
    return link.path;
  }

  /// Creates a hard link at [relativePath] to the file at [target], a path
  /// relative to [directory]; returns the link's path.
  String hardLink(String relativePath, String target) {
    final link = p.join(path, relativePath);
    Directory(p.dirname(link)).createSync(recursive: true);
    final result = Process.runSync('ln', [p.join(path, target), link]);
    if (result.exitCode != 0) throw StateError('ln failed: ${result.stderr}');
    return link;
  }

  /// Whether the file system of [directory] ignores the case of names.
  bool get isCaseInsensitive {
    write('.case_probe', '');
    return File(p.join(path, '.CASE_PROBE')).existsSync();
  }
}
