/// JSON that does not match the schema a generated `fromJson` expects.
///
/// Thrown by `fromJson` (the json_serializable contract has no other way to
/// fail) and turned into a `DecodeError` result by the request sender,
/// so it never reaches the caller of a generated operation. The message names
/// the expected and the actual JSON type, never the value itself: values can
/// be large or private.
final class JsonDecodeException implements Exception {
  /// Creates an exception at [path] inside the value of [schema].
  JsonDecodeException({
    required this.expected,
    required this.actual,
    List<Object> path = const [],
    this.schema,
    this.hint,
  }) : path = List.unmodifiable(path);

  /// What the schema expects, such as `an integer`.
  final String expected;

  /// What the JSON has, such as `a string` or `no value`.
  final String actual;

  /// Object keys ([String]) and array indexes ([int]) from the decoded value
  /// to the place of the problem.
  final List<Object> path;

  /// The schema whose `fromJson` found the problem, if known.
  final String? schema;

  /// How to fix the problem when the server sends this on purpose, such as
  /// a converter for a date-time format; `null` when there is no advice.
  final String? hint;

  /// [path] as an RFC 6901 JSON pointer; `''` is the decoded value itself.
  String get pointer => [
    for (final segment in path)
      '/${'$segment'.replaceAll('~', '~0').replaceAll('/', '~1')}',
  ].join();

  /// The key of the field with the problem, or `null` when the problem is
  /// not in an object property.
  String? get field => switch (path.lastOrNull) {
    final String key => key,
    _ => null,
  };

  /// `expected …, got …`.
  String get message => 'expected $expected, got $actual';

  /// The same problem one level deeper: [segment] is prepended to [path],
  /// and [schema] is set when the problem has none yet.
  JsonDecodeException under(Object segment, {String? schema}) =>
      JsonDecodeException(
        expected: expected,
        actual: actual,
        path: [segment, ...path],
        schema: this.schema ?? schema,
        hint: hint,
      );

  /// The same problem with [schema] set when it has none yet.
  JsonDecodeException inSchema(String schema) => JsonDecodeException(
    expected: expected,
    actual: actual,
    path: path,
    schema: this.schema ?? schema,
    hint: hint,
  );

  /// Describes the JSON type of [value] for [actual]: `null`, `a boolean`,
  /// `a number`, `a string`, `an array`, `an object` or `a non-JSON value`.
  static String describe(Object? value) => switch (value) {
    null => 'null',
    bool() => 'a boolean',
    num() => 'a number',
    String() => 'a string',
    List() => 'an array',
    Map() => 'an object',
    _ => 'a non-JSON value',
  };

  @override
  String toString() {
    final at = path.isEmpty ? '' : ' at $pointer';
    final owner = schema == null ? '' : ' in $schema';
    final advice = hint == null ? '' : '. $hint';
    return 'JsonDecodeException: $message$at$owner$advice';
  }
}
