import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/display_paths.dart';

void main() {
  final root = p.rootPrefix(p.current);
  final base = p.join(root, 'work', 'project');
  final paths = DisplayPaths(base);

  test('names a file inside the working directory relative to it', () {
    expect(paths.of(p.join(base, 'specs', 'api.yaml')), 'specs/api.yaml');
    expect(paths.of(p.join('specs', 'api.yaml')), 'specs/api.yaml');
    expect(paths.of(p.join(base, 'specs', '..', 'api.yaml')), 'api.yaml');
  });

  test('names a file outside the working directory by its absolute path', () {
    final outside = p.join(root, 'work', 'shared', 'a.yaml');
    final named = DisplayPaths.withSlashes(outside);
    expect(paths.of(outside), named);
    expect(paths.of(p.join('..', 'shared', 'a.yaml')), named);
  });

  test('resolves relative paths against the working directory', () {
    expect(
      paths.absolute('typed_openapi.yaml'),
      p.join(base, 'typed_openapi.yaml'),
    );
    expect(paths.workingDirectory, base);
  });

  test('a Windows path is named with / and keeps its drive letter', () {
    expect(
      DisplayPaths.withSlashes(r'C:\work\specs\api.yaml', p.Style.windows),
      'C:/work/specs/api.yaml',
    );
    expect(
      DisplayPaths.withSlashes(r'specs\a.yaml', p.Style.windows),
      'specs/a.yaml',
    );
  });

  test('a backslash in a POSIX file name stays', () {
    expect(DisplayPaths.withSlashes(r'a\b.yaml', p.Style.posix), r'a\b.yaml');
  });

  test('defaults to the current directory', () {
    expect(const DisplayPaths().workingDirectory, p.normalize(p.current));
    expect(const DisplayPaths().of('a.yaml'), 'a.yaml');
  });
}
