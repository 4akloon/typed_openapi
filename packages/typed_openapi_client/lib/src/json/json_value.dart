import 'json_objects.dart';

/// Any JSON value: the type of a schema without constraints (`{}`, `true`).
///
/// A zero-cost wrapper over the decoded value ([raw]): `null`, [bool], [num],
/// [String], `List<Object?>` or `Map<String, Object?>`. `jsonEncode` accepts
/// it as is. The accessors never throw: a value of another JSON type gives
/// `null`, and [operator []] gives `JsonValue(null)` for a missing key or
/// index, so lookups chain (`value['a'][0].asString`).
extension type const JsonValue(Object? raw) {
  /// Wraps a decoded JSON value; the json_serializable contract.
  factory JsonValue.fromJson(Object? json) => JsonValue(json);

  /// The JSON value; the json_serializable contract.
  Object? toJson() => raw;

  /// Whether the value is JSON `null` (or missing).
  bool get isNull => raw == null;

  /// The value as a JSON object, or `null`. A map with a non-string key is
  /// not an object.
  Map<String, Object?>? get asObject => JsonObjects(raw).view;

  /// The value as a JSON array, or `null`.
  List<Object?>? get asList => switch (raw) {
    final List<Object?> list => list,
    _ => null,
  };

  /// The value as a JSON string, or `null`.
  String? get asString => switch (raw) {
    final String text => text,
    _ => null,
  };

  /// The value as a JSON number, or `null`.
  num? get asNumber => switch (raw) {
    final num number => number,
    _ => null,
  };

  /// The value as a JSON boolean, or `null`.
  bool? get asBool => switch (raw) {
    final bool flag => flag,
    _ => null,
  };

  /// The property [key] of an object or the item at index [key] of an
  /// array; `JsonValue(null)` when there is none.
  JsonValue operator [](Object key) => switch ((asObject, raw, key)) {
    (final map?, _, final String name) => JsonValue(map[name]),
    (_, final List<Object?> list, final int index)
        when index >= 0 && index < list.length =>
      JsonValue(list[index]),
    _ => const JsonValue(null),
  };
}
