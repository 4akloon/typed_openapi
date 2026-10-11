import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';

import '../helpers/temp_dir.dart';

void main() {
  final doc = SpecLoader(DiagnosticBag()).parse(
    'paths:\n  /a~b:\n    get: {tags: [x, y]}\n  /c: null\n',
    'api.yaml',
  )!;

  test('finds values by pointer, through objects and lists', () {
    final get = JsonPointer.root.child('paths').child('/a~b').child('get');
    expect(doc.valueAt(get.child('tags').child(1)), ('y',));
    expect(doc.valueAt(JsonPointer.root)?.$1, same(doc.root));
  });

  test('tells an explicit null from a missing node', () {
    final paths = JsonPointer.root.child('paths');
    expect(doc.valueAt(paths.child('/c')), (null,));
    expect(doc.valueAt(paths.child('/d')), isNull);
  });

  test('rejects list indexes that are not plain numbers', () {
    final tags = JsonPointer.parse('#/paths/~1a~0b/get/tags');
    expect(doc.valueAt(tags.child('01')), isNull);
    expect(doc.valueAt(tags.child('-')), isNull);
    expect(doc.valueAt(tags.child(2)), isNull);
  });

  test('parse defaults the URI to the file in the current directory', () {
    expect(doc.uri, p.toUri(p.absolute('api.yaml')));
  });

  test('load records the absolute, normalized file URI', () {
    final dir = TempDir();
    dir.write('specs/api.yaml', 'openapi: 3.1.0\n');
    final path = p.join(dir.path, 'specs', '..', 'specs', 'api.yaml');
    final loaded = SpecLoader(DiagnosticBag()).load(path)!;
    expect(loaded.uri, p.toUri(p.join(dir.path, 'specs', 'api.yaml')));
  });
}
