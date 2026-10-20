import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi_core/src/model/spec_node.dart';

void main() {
  final a = Uri.parse('file:///specs/a.yaml');
  final b = Uri.parse('file:///specs/b.yaml');
  final user = JsonPointer.parse('#/components/schemas/User');

  test('a location is equal to another with the same file and pointer', () {
    expect(SpecLocation(a, user), SpecLocation(a, user));
    expect(SpecLocation(a, user).hashCode, SpecLocation(a, user).hashCode);
  });

  test('the same pointer in two files is two locations', () {
    expect(SpecLocation(a, user), isNot(SpecLocation(b, user)));
  });

  test('locations sort by file, then by pointer', () {
    final sorted = [
      SpecLocation(b, JsonPointer.root),
      SpecLocation(a, user),
      SpecLocation(a, JsonPointer.root),
    ]..sort();
    expect(sorted.map((l) => '$l'), [
      'file:///specs/a.yaml#',
      'file:///specs/a.yaml#/components/schemas/User',
      'file:///specs/b.yaml#',
    ]);
  });

  test('ref kinds name themselves with an article', () {
    expect(RefKind.example.withArticle, 'an example');
    expect(RefKind.requestBody.withArticle, 'a request body');
  });
}
