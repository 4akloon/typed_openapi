import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';

void main() {
  const deep = DeepEquality();

  void same(Object? a, Object? b) {
    expect(deep.equals(a, b), isTrue, reason: '$a == $b');
    expect(deep.hash(a), deep.hash(b), reason: 'hash of $a and $b');
  }

  test('compares lists by items in order', () {
    same([1, 'a', null], [1, 'a', null]);
    same(<Object?>[], <Object?>[]);
    expect(deep.equals([1, 2], [2, 1]), isFalse);
    expect(deep.equals([1], [1, 1]), isFalse);
    same(Uint8List.fromList([1, 2, 3]), [1, 2, 3]);
  });

  test('compares maps by entries in any order', () {
    same({'a': 1, 'b': 2}, {'b': 2, 'a': 1});
    expect(deep.equals({'a': 1}, {'a': 2}), isFalse);
    expect(deep.equals({'a': null}, {'b': null}), isFalse);
    expect(deep.equals({'a': 1}, {'a': 1, 'b': 1}), isFalse);
  });

  test('compares nested JSON, JsonValue and patches by content', () {
    same(
      {
        'a': [
          {'b': true},
        ],
      },
      {
        'a': [
          {'b': true},
        ],
      },
    );
    same(
      const JsonValue({
        'x': [1],
      }),
      const JsonValue({
        'x': [1],
      }),
    );
    same(const Patch.value([1, 2]), const Patch.value([1, 2]));
    same(
      const Patch<List<int>>.nullValue(),
      const Patch<List<int>>.nullValue(),
    );
    expect(
      deep.equals(const Patch.value([1]), const Patch<List<int>>.nullValue()),
      isFalse,
    );
  });

  test('falls back to == for everything else', () {
    same(1, 1);
    same(null, null);
    same(Date(2024, 2, 3), Date(2024, 2, 3));
    expect(deep.equals(1, '1'), isFalse);
    expect(deep.equals(null, <Object?>[]), isFalse);
  });
}
