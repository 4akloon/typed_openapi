/// A request body field with three states: absent, explicit `null` or a
/// value.
///
/// A field has the type `Patch<T>?`: `null` means the key is not sent,
/// [Patch.nullValue] sends `null` and [Patch.value] sends the value.
///
/// ```dart
/// UpdatePet(name: .value('Rex'), tag: .nullValue())
/// // {"name":"Rex","tag":null}
/// ```
sealed class Patch<T> {
  const Patch();

  /// Sends [value].
  const factory Patch.value(T value) = PatchValue<T>;

  /// Sends an explicit `null`.
  const factory Patch.nullValue() = PatchNull<T>;

  /// The value, or `null` for [PatchNull].
  T? get valueOrNull;

  /// The JSON for this field: `encode(value)` or `null`.
  Object? toJson(Object? Function(T value) encode);
}

/// A [Patch] that sends a value.
final class PatchValue<T> extends Patch<T> {
  /// Creates a patch that sends [value].
  const PatchValue(this.value);

  /// The value to send.
  final T value;

  @override
  T? get valueOrNull => value;

  @override
  Object? toJson(Object? Function(T value) encode) => encode(value);

  @override
  bool operator ==(Object other) =>
      other is PatchValue<T> && other.value == value;

  @override
  int get hashCode => Object.hash(PatchValue, value);

  @override
  String toString() => 'Patch.value($value)';
}

/// A [Patch] that sends an explicit `null`.
final class PatchNull<T> extends Patch<T> {
  /// Creates a patch that sends `null`.
  const PatchNull();

  @override
  T? get valueOrNull => null;

  @override
  Object? toJson(Object? Function(T value) encode) => null;

  @override
  bool operator ==(Object other) => other is PatchNull<T>;

  @override
  int get hashCode => (PatchNull).hashCode;

  @override
  String toString() => 'Patch.nullValue()';
}
