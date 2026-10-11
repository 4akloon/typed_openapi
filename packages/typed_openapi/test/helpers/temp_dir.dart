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
}
