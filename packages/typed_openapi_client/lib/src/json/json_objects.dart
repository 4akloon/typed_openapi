import 'json_decode_exception.dart';

/// A decoded JSON value viewed as an object, `Map<String, Object?>`.
///
/// `jsonDecode` gives `Map<String, dynamic>`, but a mock or a transport that
/// decodes bodies itself can give a `Map<dynamic, dynamic>`; it is an object
/// all the same as long as every key is a string.
extension type const JsonObjects(Object? _value) {
  /// The value as `Map<String, Object?>` (the same map, or a view of it
  /// without copying), or `null` when it is not a map or has a non-string key.
  Map<String, Object?>? get view => switch (_value) {
    final Map<String, Object?> map => map,
    final Map<Object?, Object?> map when map.keys.every((k) => k is String) =>
      map.cast<String, Object?>(),
    _ => null,
  };

  /// The value as `Map<String, Object?>`, or a [JsonDecodeException] that
  /// says why it is not an object.
  Map<String, Object?> require() {
    if (view case final map?) return map;
    if (_value case final Map<Object?, Object?> map) {
      final key = map.keys.firstWhere((k) => k is! String);
      throw JsonDecodeException(
        expected: 'an object',
        actual: 'an object with a non-string key `$key`',
      );
    }
    throw JsonDecodeException(
      expected: 'an object',
      actual: JsonDecodeException.describe(_value),
    );
  }
}
