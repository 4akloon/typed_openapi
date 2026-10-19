import '../diagnostics/json_pointer.dart';
import 'config_sources.dart';

/// Reads the settings of how a client's types are generated: `types.number`
/// from the last source that has it (`defaults` first). A bad value is
/// reported through the `invalid` function (TOA902) and the default is
/// used.
final class TypeSettingsReader {
  /// Creates a reader of [_sources] that reports through [_invalid].
  const TypeSettingsReader(this._sources, this._invalid);

  /// The maps to read, `defaults` first, with their pointers.
  final ConfigSources _sources;

  final void Function(String message, JsonPointer at) _invalid;

  /// `types.number`: the Dart type of a `number` without a format, `double`
  /// or `int`; null for `num`, the default.
  String? numberType() {
    final picked = _sources.pick('number', 'types');
    if (picked == null) return null;
    final (value, at) = picked;
    if (value is! String || value.isEmpty) {
      return _report('"number" must be a non-empty string.', at);
    }
    return switch (value) {
      'num' => null,
      'double' || 'int' => value,
      _ => _report('"number" must be num, double or int.', at),
    };
  }

  /// Reports [message] at [at]; returns null.
  Null _report(String message, JsonPointer at) {
    _invalid(message, at);
    return null;
  }
}
