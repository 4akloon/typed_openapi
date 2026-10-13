import 'package:test/test.dart';
import 'package:typed_openapi_runtime/typed_openapi_runtime.dart';

void main() {
  test('a constant says whether it was there', () {
    const r = JsonReader({'kind': 'cat', 'tag': null}, schema: 'Cat');
    expect(r.constant('kind', 'cat'), isTrue);
    expect(r.constant('kind', 'cat', required: false), isTrue);
    expect(r.constant('tag', 'x', required: false), isFalse);
    expect(r.constant('gone', 'x', required: false), isFalse);
  });
}
