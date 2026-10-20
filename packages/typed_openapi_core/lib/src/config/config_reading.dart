/// The result of reading one source's value of a setting: a usable value, or
/// the problem with it.
sealed class ConfigReading<T> {
  const ConfigReading();
}

/// A value of a setting that can be used.
final class ValidValue<T> extends ConfigReading<T> {
  /// Creates a reading of [value].
  const ValidValue(this.value);

  /// The value to apply.
  final T value;
}

/// A value of a setting that cannot be used, so the source acts as if it
/// lacked the key.
final class InvalidValue<T> extends ConfigReading<T> {
  /// Creates a reading that is rejected for [problem], found at [child] of
  /// the value when that is set.
  const InvalidValue(this.problem, {this.child});

  /// What is wrong with the value, as a sentence for TOA902.
  final String problem;

  /// The key under the value where the problem is, null when it is the
  /// value itself.
  final String? child;
}
