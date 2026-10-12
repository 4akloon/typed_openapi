import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/display_paths.dart';

void main() {
  final root = p.rootPrefix(p.current);
  final base = p.join(root, 'work', 'project');
  final paths = DisplayPaths(base);

  test('names a file inside the working directory relative to it', () {
    expect(
      paths.of(p.join(base, 'specs', 'api.yaml')),
      p.join('specs', 'api.yaml'),
    );
    expect(paths.of(p.join('specs', 'api.yaml')), p.join('specs', 'api.yaml'));
    expect(paths.of(p.join(base, 'specs', '..', 'api.yaml')), 'api.yaml');
  });

  test('names a file outside the working directory by its absolute path', () {
    final outside = p.join(root, 'work', 'shared', 'a.yaml');
    expect(paths.of(outside), outside);
    expect(paths.of(p.join('..', 'shared', 'a.yaml')), outside);
  });

  test('resolves relative paths against the working directory', () {
    expect(
      paths.absolute('typed_openapi.yaml'),
      p.join(base, 'typed_openapi.yaml'),
    );
    expect(paths.workingDirectory, base);
  });

  test('defaults to the current directory', () {
    expect(const DisplayPaths().workingDirectory, p.normalize(p.current));
    expect(const DisplayPaths().of('a.yaml'), 'a.yaml');
  });
}
