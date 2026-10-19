import 'patch.dart';

/// Deep equality for the `==` and `hashCode` of generated models.
///
/// Lists are equal when their items are equal in order, maps when they have
/// the same keys with equal values in any order, and [PatchValue]s when
/// their values are equal; everything else is compared with `==`. A
/// `JsonValue` is its raw value at run time, so JSON of any shape compares
/// by content. Generated code calls it as `const DeepEquality()`.
final class DeepEquality {
  /// Creates the comparison.
  const DeepEquality();

  /// Whether [a] and [b] are deeply equal.
  bool equals(Object? a, Object? b) {
    if (identical(a, b)) return true;
    return switch ((a, b)) {
      (final List<Object?> x, final List<Object?> y) => _lists(x, y),
      (final Map<Object?, Object?> x, final Map<Object?, Object?> y) => _maps(
        x,
        y,
      ),
      (final PatchValue<Object?> x, final PatchValue<Object?> y) => equals(
        x.value,
        y.value,
      ),
      _ => a == b,
    };
  }

  /// A hash code of [value] that agrees with [equals].
  int hash(Object? value) => switch (value) {
    final List<Object?> list => Object.hashAll(list.map(hash)),
    final Map<Object?, Object?> map => Object.hashAllUnordered(
      map.entries.map((e) => Object.hash(e.key, hash(e.value))),
    ),
    final PatchValue<Object?> patch => Object.hash(
      PatchValue,
      hash(patch.value),
    ),
    _ => value.hashCode,
  };

  bool _lists(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!equals(a[i], b[i])) return false;
    }
    return true;
  }

  bool _maps(Map<Object?, Object?> a, Map<Object?, Object?> b) {
    if (a.length != b.length) return false;
    for (final MapEntry(:key, :value) in a.entries) {
      if (!b.containsKey(key) || !equals(value, b[key])) return false;
    }
    return true;
  }
}
