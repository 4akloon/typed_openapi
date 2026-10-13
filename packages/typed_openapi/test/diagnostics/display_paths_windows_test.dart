// Runs only on Windows, so only the Windows job of CI checks it (M11).
@TestOn('windows')
library;

import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/display_paths.dart';

void main() {
  const paths = DisplayPaths(r'C:\work');

  test('a file on the drive of the working directory is relative', () {
    expect(paths.of(r'C:\work\specs\pets.yaml'), r'specs\pets.yaml');
    expect(paths.of(r'specs\pets.yaml'), r'specs\pets.yaml');
  });

  test('a file on another drive is absolute, with its drive letter', () {
    expect(paths.of(r'D:\specs\pets.yaml'), r'D:\specs\pets.yaml');
  });

  test('a drive letter in another case is the same drive', () {
    expect(paths.of(r'c:\work\pets.yaml'), 'pets.yaml');
  });
}
