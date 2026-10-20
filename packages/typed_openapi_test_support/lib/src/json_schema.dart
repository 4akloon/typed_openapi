import 'dart:convert';

/// A validator for the part of JSON Schema (draft-04 and draft-07) that the
/// SARIF 2.1.0 schema and the config schema use: `type`, `enum` and `const`
/// (compared by value), `properties`, `patternProperties`,
/// `additionalProperties`, `propertyNames`, `required`, `minProperties`,
/// `items`, `minItems`, `minLength`, `uniqueItems`, `minimum`, `maximum`,
/// `pattern`, `anyOf`, `oneOf` and local `$ref`s (`#/definitions/...`). `format`,
/// `default` and the annotations are not checked. Tests only: nothing ships
/// it.
final class JsonSchema {
  /// Creates the validator of the schema [root].
  const JsonSchema(this.root);

  /// The schema, as decoded JSON.
  final Map<String, Object?> root;

  /// The problems of [value], each with its JSON pointer; empty when the
  /// value is valid.
  List<String> validate(Object? value) => _check(root, value, '');

  /// Whether [document] is valid.
  bool accepts(Object? document) => validate(document).isEmpty;

  List<String> _check(Map<String, Object?> schema, Object? value, String at) {
    if (schema[r'$ref'] case final String ref) {
      return _check(_resolve(ref), value, at);
    }
    final problems = [
      if (schema['type'] case final Object type when !_hasType(value, type))
        '$at: expected $type, got ${jsonEncode(value)}',
      if (schema['enum'] case final List<Object?> values
          when !values.any((v) => _same(v, value)))
        '$at: ${jsonEncode(value)} is not one of $values',
      if (schema.containsKey('const') && !_same(schema['const'], value))
        '$at: ${jsonEncode(value)} is not ${jsonEncode(schema['const'])}',
      ..._number(schema, value, at),
      if (schema['minLength'] case final int min
          when value is String && value.runes.length < min)
        '$at: "$value" is shorter than $min',
      if (schema['pattern'] case final String pattern
          when value is String && !RegExp(pattern).hasMatch(value))
        '$at: "$value" does not match $pattern',
      ..._choices(schema, value, at),
    ];
    return [
      ...problems,
      if (value is Map<String, Object?>) ..._object(schema, value, at),
      if (value is List<Object?>) ..._array(schema, value, at),
    ];
  }

  Map<String, Object?> _resolve(String ref) {
    Object? node = root;
    for (final token in ref.substring(2).split('/')) {
      node = (node! as Map<String, Object?>)[token];
    }
    return node! as Map<String, Object?>;
  }

  static bool _same(Object? a, Object? b) =>
      jsonEncode(_sorted(a)) == jsonEncode(_sorted(b));

  static Object? _sorted(Object? value) => switch (value) {
    final Map<Object?, Object?> map => {
      for (final key in map.keys.map((k) => '$k').toList()..sort())
        key: _sorted(map[key]),
    },
    final List<Object?> list => list.map(_sorted).toList(),
    _ => value,
  };

  static bool _hasType(Object? value, Object type) => switch (type) {
    final List<Object?> types => types.any((t) => _hasType(value, t!)),
    'object' => value is Map,
    'array' => value is List,
    'string' => value is String,
    'integer' => value is int || (value is double && value % 1 == 0),
    'number' => value is num,
    'boolean' => value is bool,
    'null' => value == null,
    _ => false,
  };

  static List<String> _number(
    Map<String, Object?> schema,
    Object? value,
    String at,
  ) => [
    if (value is num) ...[
      if (schema['minimum'] case final num min when value < min)
        '$at: $value is less than $min',
      if (schema['maximum'] case final num max when value > max)
        '$at: $value is more than $max',
    ],
  ];

  List<String> _choices(Map<String, Object?> schema, Object? value, String at) {
    final valid = <String, int>{
      for (final key in ['anyOf', 'oneOf'])
        if (schema[key] case final List<Object?> options)
          key: options
              .where(
                (o) => _check(o! as Map<String, Object?>, value, at).isEmpty,
              )
              .length,
    };
    return [
      if (valid['anyOf'] == 0) '$at: matches no schema of anyOf',
      if (valid['oneOf'] case final n? when n != 1)
        '$at: matches $n schemas of oneOf, not one',
    ];
  }

  List<String> _object(
    Map<String, Object?> schema,
    Map<String, Object?> value,
    String at,
  ) {
    final properties =
        schema['properties'] as Map<String, Object?>? ?? const {};
    final additional = schema['additionalProperties'];
    final patterns =
        schema['patternProperties'] as Map<String, Object?>? ?? const {};
    final names = schema['propertyNames'];
    return [
      if (schema['minProperties'] case final int min when value.length < min)
        '$at: fewer than $min properties',
      if (names is Map<String, Object?>)
        for (final key in value.keys) ..._check(names, key, '$at/$key (name)'),
      for (final key in schema['required'] as List<Object?>? ?? const [])
        if (!value.containsKey(key)) '$at: "$key" is required',
      for (final MapEntry(:key, value: item) in value.entries)
        ..._property(properties, patterns, additional, key, item, at),
    ];
  }

  List<String> _array(
    Map<String, Object?> schema,
    List<Object?> value,
    String at,
  ) {
    final unique = value.map(jsonEncode).toSet().length == value.length;
    return [
      if (schema['minItems'] case final int min when value.length < min)
        '$at: fewer than $min items',
      if (schema['uniqueItems'] == true && !unique) '$at: items repeat',
      if (schema['items'] case final Map<String, Object?> items)
        for (final (i, item) in value.indexed) ..._check(items, item, '$at/$i'),
    ];
  }

  List<String> _property(
    Map<String, Object?> properties,
    Map<String, Object?> patterns,
    Object? additional,
    String key,
    Object? item,
    String at,
  ) {
    final matching = [
      if (properties[key] case final Map<String, Object?> sub) sub,
      for (final MapEntry(key: pattern, value: sub) in patterns.entries)
        if (RegExp(pattern).hasMatch(key)) sub! as Map<String, Object?>,
    ];
    if (matching.isNotEmpty) {
      return [for (final sub in matching) ..._check(sub, item, '$at/$key')];
    }
    return switch (additional) {
      final Map<String, Object?> sub => _check(sub, item, '$at/$key'),
      false => ['$at: "$key" is not allowed'],
      _ => const <String>[],
    };
  }
}
