import '../diagnostics/json_pointer.dart';
import '../overrides/override_set.dart';
import 'config_sources.dart';

/// Reads the custom types of `types.formats` and `types.schemas` (R6.8),
/// entry by entry from every source (`defaults` first, so a client's entry
/// wins). A bad entry is reported through the `invalid` function (TOA902)
/// and left out.
final class CustomTypesReader {
  /// Creates a reader of [_sources] that reports a bad value through
  /// [_invalid] and an unknown key through [_checkKeys].
  const CustomTypesReader(this._sources, this._invalid, this._checkKeys);

  static const _customTypeKeys = {'type', 'import', 'converter'};

  /// The maps to read, `defaults` first, with their pointers.
  final ConfigSources _sources;

  final void Function(String message, JsonPointer at) _invalid;

  final void Function(
    Map<String, Object?> map,
    Set<String> allowed,
    JsonPointer at,
  )
  _checkKeys;

  /// The custom types under `types.<key>`, by format or schema key.
  Map<String, DartTypeOverride> read(String key) {
    final result = <String, DartTypeOverride>{};
    for (final (map, at) in _sources) {
      final types = map['types'];
      if (types is! Map<String, Object?> || !types.containsKey(key)) {
        continue;
      }
      final pointer = at.child('types').child(key);
      final entries = types[key];
      if (entries is! Map<String, Object?>) {
        _invalid('"$key" must be a mapping.', pointer);
        continue;
      }
      for (final MapEntry(key: name, :value) in entries.entries) {
        final custom = _customType(value, pointer.child(name));
        if (custom != null) result[name] = custom;
      }
    }
    return result;
  }

  DartTypeOverride? _customType(Object? value, JsonPointer at) {
    if (value is! Map<String, Object?>) {
      return _report('A custom type must be a mapping.', at);
    }
    _checkKeys(value, _customTypeKeys, at);
    final type = value['type'];
    final import = value['import'];
    final converter = value['converter'];
    if (type is! String || type.isEmpty) {
      return _report('A custom type needs "type", a Dart type name.', at);
    }
    if (import is! String || import.isEmpty) {
      return _report(
        'A custom type needs "import", the library that declares "$type".',
        at,
      );
    }
    if (converter != null && (converter is! String || converter.isEmpty)) {
      return _report(
        '"converter" must be a non-empty string.',
        at.child('converter'),
      );
    }
    if (!_checkFields(type, import, converter as String?, at)) return null;
    return DartTypeOverride(type: type, import: import, converter: converter);
  }

  /// Whether every field of a custom type is valid; reports each that is
  /// not.
  bool _checkFields(
    String type,
    String import,
    String? converter,
    JsonPointer at,
  ) {
    var valid = true;
    for (final (field, written) in [
      ('type', type),
      ('import', import),
      if (converter != null) ('converter', converter),
    ]) {
      if (DartTypeOverride.problem(field, written) case final problem?) {
        _invalid(problem, at.child(field));
        valid = false;
      }
    }
    return valid;
  }

  /// Reports [message] at [at]; returns null.
  Null _report(String message, JsonPointer at) {
    _invalid(message, at);
    return null;
  }
}
