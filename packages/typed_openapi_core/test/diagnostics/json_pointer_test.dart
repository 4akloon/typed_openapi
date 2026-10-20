import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/json_pointer.dart';

void main() {
  group('JsonPointer', () {
    test('root is #', () {
      expect(JsonPointer.root.value, '#');
      expect(JsonPointer.root.tokens, isEmpty);
    });

    test('child escapes ~ and / per RFC 6901', () {
      final pointer = JsonPointer.root
          .child('paths')
          .child('/users/{id}')
          .child('a~b');
      expect(pointer.value, '#/paths/~1users~1{id}/a~0b');
    });

    test('child accepts list indexes', () {
      expect(JsonPointer.root.child('tags').child(2).value, '#/tags/2');
    });

    test('tokens unescape in the right order', () {
      final pointer = JsonPointer.parse('#/paths/~1users~1{id}/a~0b/~01');
      expect(pointer.tokens, ['paths', '/users/{id}', 'a~b', '~1']);
    });

    test('parse rejects pointers without #/', () {
      expect(() => JsonPointer.parse('/paths'), throwsFormatException);
    });
  });
}
