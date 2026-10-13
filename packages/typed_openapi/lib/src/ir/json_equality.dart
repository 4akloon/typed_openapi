/// Structural equality of the plain trees a spec is read into (maps, lists,
/// strings, numbers, booleans, null). It never throws: a `NaN` equals a
/// `NaN`, which JSON encoding and `==` cannot say, and an infinity equals
/// itself.
final class JsonEquality {
  const JsonEquality._();

  /// Whether [a] and [b] are the same tree.
  static bool equals(Object? a, Object? b) => switch ((a, b)) {
    (final Map<Object?, Object?> x, final Map<Object?, Object?> y) =>
      x.length == y.length &&
          x.entries.every(
            (e) => y.containsKey(e.key) && equals(e.value, y[e.key]),
          ),
    (final List<Object?> x, final List<Object?> y) =>
      x.length == y.length &&
          [
            for (final (i, item) in x.indexed) equals(item, y[i]),
          ].every((same) => same),
    (final double x, final double y) => x == y || (x.isNaN && y.isNaN),
    _ => a == b,
  };
}
