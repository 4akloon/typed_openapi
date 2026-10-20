import 'package:test/test.dart';
import 'package:typed_openapi_core/src/ir/json_equality.dart';

void main() {
  test('equal trees are equal, whatever the order of the keys', () {
    expect(
      JsonEquality.equals(
        {
          'a': [1, 'x', null],
          'b': {'c': true},
        },
        {
          'b': {'c': true},
          'a': [1, 'x', null],
        },
      ),
      isTrue,
    );
  });

  test('a different value, key, length or type is a difference', () {
    expect(JsonEquality.equals({'a': 1}, {'a': 2}), isFalse);
    expect(JsonEquality.equals({'a': 1}, {'b': 1}), isFalse);
    expect(JsonEquality.equals([1], [1, 2]), isFalse);
    expect(JsonEquality.equals({'a': 1}, [1]), isFalse);
    expect(JsonEquality.equals('1', 1), isFalse);
  });

  test('NaN and infinities are compared without throwing', () {
    expect(JsonEquality.equals([double.nan], [double.nan]), isTrue);
    expect(JsonEquality.equals(double.infinity, double.infinity), isTrue);
    expect(
      JsonEquality.equals(double.infinity, double.negativeInfinity),
      isFalse,
    );
    expect(JsonEquality.equals(double.nan, 1.0), isFalse);
  });
}
