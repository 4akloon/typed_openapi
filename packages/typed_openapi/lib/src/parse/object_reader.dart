import '../diagnostics/json_pointer.dart';
import '../model/spec_node.dart';
import 'parse_context.dart';

/// Reads the fields of one JSON object of a spec.
///
/// Every getter remembers the key it read. A value of the wrong JSON type is
/// reported as `invalid-value` and read as missing. [unknownKeys] reports
/// the keys nobody read, so call it after reading every field.
final class ObjectReader {
  /// Creates a reader for [_map], which is at [pointer].
  ObjectReader(this._context, this._map, this.pointer);

  final ParseContext _context;
  final Map<String, Object?> _map;
  final Set<String> _read = {};

  /// Where the object is.
  final JsonPointer pointer;

  /// The location of the object.
  SpecLocation get location => _context.locate(pointer);

  /// Whether the object has [key].
  bool has(String key) => _map.containsKey(key);

  /// The keys of the object, in document order.
  Iterable<String> get keys => _map.keys;

  /// The raw value of [key] as a one-element record, or null when the key
  /// is missing.
  (Object?,)? value(String key) {
    _read.add(key);
    return _map.containsKey(key) ? (_map[key],) : null;
  }

  /// Marks [keys] as read without reading them: keys the spec defines but
  /// the model does not type.
  void accept(Iterable<String> keys) => _read.addAll(keys);

  /// [key] as a string.
  String? string(String key) => _typed<String>(key, 'a string');

  /// [key] as a string; reports `missing-required-field` when it is missing.
  String? requiredString(String key) {
    if (!has(key)) _missing(key);
    return string(key);
  }

  /// [key] as a boolean.
  bool? boolean(String key) => _typed<bool>(key, 'true or false');

  /// [key] as a number.
  num? number(String key) => _typed<num>(key, 'a number');

  /// [key] as a non-negative integer; `3.0` reads as `3`.
  int? count(String key) {
    final raw = value(key);
    if (raw == null) return null;
    final (number,) = raw;
    if (number is num && number >= 0 && number == number.truncate()) {
      return number.toInt();
    }
    _invalid(key, 'a non-negative integer', number);
    return null;
  }

  /// [key] as one of the names in [byName].
  T? choice<T>(String key, Map<String, T> byName) {
    final name = string(key);
    if (name == null) return null;
    final result = byName[name];
    if (result != null) return result;
    _context.report(
      .invalidValue,
      '"$key" must be one of ${byName.keys.join(', ')}, not "$name".',
      pointer.child(key),
    );
    return null;
  }

  /// [key] as one of the names in [byName]; reports
  /// `missing-required-field` when it is missing.
  T? requiredChoice<T>(String key, Map<String, T> byName) {
    if (!has(key)) _missing(key);
    return choice(key, byName);
  }

  /// [key] as a list of strings; items that are not strings are reported
  /// and skipped.
  List<String>? strings(String key) =>
      list(key, (raw, at) => _item<String>(raw, at, 'a string'));

  /// [key] as a list of raw values, `null` items included.
  List<Object?>? rawList(String key) {
    final raw = value(key);
    if (raw == null) return null;
    final (items,) = raw;
    if (items is List<Object?>) return List.unmodifiable(items);
    _invalid(key, 'a list', items);
    return null;
  }

  /// [key] as a list whose items [read] converts; null items are skipped.
  List<T>? list<T>(String key, T? Function(Object? raw, JsonPointer at) read) {
    final raw = value(key);
    if (raw == null) return null;
    final (items,) = raw;
    if (items is! List<Object?>) {
      _invalid(key, 'a list', items);
      return null;
    }
    final at = pointer.child(key);
    return List.unmodifiable([
      for (var i = 0; i < items.length; i++) ?read(items[i], at.child(i)),
    ]);
  }

  /// [key] as an object whose values [read] converts, in document order;
  /// null values are skipped. With [skipExtensions], `x-` keys are not
  /// entries.
  Map<String, T>? map<T>(
    String key,
    T? Function(Object? raw, JsonPointer at) read, {
    bool skipExtensions = false,
  }) {
    final raw = value(key);
    if (raw == null) return null;
    final (entries,) = raw;
    if (entries is! Map<String, Object?>) {
      _invalid(key, 'an object', entries);
      return null;
    }
    final at = pointer.child(key);
    return Map.unmodifiable({
      for (final MapEntry(key: name, :value) in entries.entries)
        if (!skipExtensions || !name.startsWith('x-'))
          name: ?read(value, at.child(name)),
    });
  }

  /// [key] as an object of strings.
  Map<String, String>? stringMap(String key) =>
      map(key, (raw, at) => _item<String>(raw, at, 'a string'));

  /// [key] read by [read] when it is an object.
  T? object<T>(String key, T Function(ObjectReader reader) read) {
    final raw = value(key);
    if (raw == null) return null;
    final reader = _context.reader(raw.$1, pointer.child(key), '"$key"');
    return reader == null ? null : read(reader);
  }

  /// [key] read by [read]; reports `missing-required-field` when it is
  /// missing.
  T? requiredObject<T>(String key, T Function(ObjectReader reader) read) {
    if (!has(key)) _missing(key);
    return object(key, read);
  }

  /// The `x-` keys of the object and their raw values.
  Map<String, Object?> get extensions => Map.unmodifiable({
    for (final MapEntry(:key, :value) in _map.entries)
      if (key.startsWith('x-')) key: value,
  });

  /// Reports each key that was not read and is not an `x-` key as
  /// `unknown-key`, and returns them with their raw values.
  ///
  /// With [reportExtensions], `x-` keys are reported too: Reference Objects
  /// cannot be extended.
  Map<String, Object?> unknownKeys({bool reportExtensions = false}) {
    final unknown = <String, Object?>{};
    for (final MapEntry(:key, :value) in _map.entries) {
      if (_read.contains(key)) continue;
      if (!reportExtensions && key.startsWith('x-')) continue;
      unknown[key] = value;
      _context.report(
        .unknownKey,
        'Unknown key "$key"; it is ignored.',
        pointer.child(key),
      );
    }
    return Map.unmodifiable(unknown);
  }

  /// How a raw value is named in messages.
  static String describe(Object? raw) => switch (raw) {
    null => 'null',
    bool() => '$raw',
    num() => 'the number $raw',
    String() => 'a string',
    List<Object?>() => 'a list',
    _ => 'an object',
  };

  T? _typed<T>(String key, String expected) {
    final raw = value(key);
    if (raw == null) return null;
    final (result,) = raw;
    if (result is T) return result;
    _invalid(key, expected, result);
    return null;
  }

  T? _item<T>(Object? raw, JsonPointer at, String expected) {
    if (raw is T) return raw;
    _context.report(
      .invalidValue,
      'Each item must be $expected, not ${describe(raw)}.',
      at,
    );
    return null;
  }

  void _invalid(String key, String expected, Object? raw) {
    _context.report(
      .invalidValue,
      '"$key" must be $expected, not ${describe(raw)}; it is ignored.',
      pointer.child(key),
    );
  }

  void _missing(String key) {
    _context.report(
      .missingRequiredField,
      'The required field "$key" is missing.',
      pointer,
    );
  }
}
