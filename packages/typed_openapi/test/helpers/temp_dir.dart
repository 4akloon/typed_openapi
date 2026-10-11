import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Creates a temp directory that is deleted after the current test.
Directory createTempDir() {
  final dir = Directory.systemTemp.createTempSync('typed_openapi_test_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// Writes [content] to [relativePath] under [dir]; returns the full path.
String writeFile(Directory dir, String relativePath, String content) {
  final file = File(p.join(dir.path, relativePath))
    ..createSync(recursive: true)
    ..writeAsStringSync(content);
  return file.path;
}
