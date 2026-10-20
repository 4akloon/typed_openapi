import 'dart:math' as math;

/// A finite number as the exact decimal its shortest text is, so that
/// `multipleOf` can be decided without float error (`0.3` is a multiple of
/// `0.1`, `1.0000000001` is not a multiple of `1`).
///
/// A JSON number reaches the generator as a `double` or an `int`; its
/// shortest round-trip text (`toString`) is what was written for every
/// number of up to 15 significant digits, which is the exact value used
/// here.
final class Decimal {
  const Decimal._(this._unscaled, this._scale);

  /// The decimal [value] is written as; [value] must be finite.
  factory Decimal.of(num value) {
    final match = _text.firstMatch(value.toString());
    if (match == null) {
      throw ArgumentError.value(value, 'value', 'is not a finite number');
    }
    final fraction = match[3] ?? '';
    final unscaled = BigInt.parse('${match[2]}$fraction');
    return Decimal._(
      match[1] == '-' ? -unscaled : unscaled,
      fraction.length - (int.tryParse(match[4] ?? '0') ?? 0),
    );
  }

  /// The text of a finite number: sign, digits, fraction, exponent.
  static final _text = RegExp(r'^(-?)(\d+)(?:\.(\d+))?(?:[eE]([+-]?\d+))?$');

  /// The value is `_unscaled / 10^_scale`.
  final BigInt _unscaled;
  final int _scale;

  /// Whether this is a whole multiple of [step]; false for a zero [step].
  bool isMultipleOf(Decimal step) {
    if (step._unscaled == BigInt.zero) return false;
    final scale = math.max(_scale, step._scale);
    BigInt scaled(Decimal value) =>
        value._unscaled * BigInt.from(10).pow(scale - value._scale);
    return scaled(this) % scaled(step) == BigInt.zero;
  }
}
