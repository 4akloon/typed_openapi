import 'package:test/test.dart';
import 'package:typed_openapi/src/ir/decimal.dart';

void main() {
  bool multiple(num value, num step) =>
      Decimal.of(value).isMultipleOf(Decimal.of(step));

  test('a decimal is a multiple of a step without float error', () {
    expect(multiple(0.3, 0.1), isTrue);
    expect(multiple(0.07, 0.01), isTrue);
    expect(multiple(19.99, 0.01), isTrue);
    expect(multiple(-0.3, 0.1), isTrue);
    expect(multiple(0, 0.1), isTrue);
    expect(multiple(6, 2), isTrue);
    expect(multiple(1e21, 1e20), isTrue);
    expect(multiple(3e-7, 1e-7), isTrue);
  });

  test('a value off the grid is not a multiple', () {
    expect(multiple(0.35, 0.1), isFalse);
    expect(multiple(1.0000000001, 1), isFalse);
    expect(multiple(2.0000000005, 2), isFalse);
    expect(multiple(1.000000000001, 0.25), isFalse);
    expect(multiple(7, 5), isFalse);
    expect(multiple(1e-8, 1e-7), isFalse);
  });

  test('a zero step has no multiples', () {
    expect(multiple(0, 0), isFalse);
  });
}
