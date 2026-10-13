import 'dart:convert';

/// A validator for the part of JSON Schema draft-04 that the SARIF 2.1.0
/// schema uses: `type`, `enum`, `properties`, `additionalProperties`,
/// `required`, `items`, `minItems`, `uniqueItems`, `minimum`, `maximum`,
/// `pattern`, `anyOf`, `oneOf` and local `$ref`s (`#/definitions/...`).
/// `format`, `default` and the annotations are not checked. Tests only:
/// nothing ships it.
final class JsonSchema {
  /// Creates the validator of the schema [root].
  const JsonSchema(this.root);

  /// The schema, as decoded JSON.
  final Map<String, Object?> root;

  /// The problems of [value], each with its JSON pointer; empty when the
  /// value is valid.
  List<String> validate(Object? value) => _check(root, value, '');

  List<String> _check(Map<String, Object?> schema, Object? value, String at) {
    if (schema[r'$ref'] case final String ref) {
      return _check(_resolve(ref), value, at);
    }
    final problems = [
      if (schema['type'] case final Object type when !_hasType(value, type))
        '$at: expected $type, got ${jsonEncode(value)}',
      if (schema['enum'] case final List<Object?> values
          when !values.contains(value))
        '$at: ${jsonEncode(value)} is not one of $values',
      ..._number(schema, value, at),
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
    return [
      for (final key in schema['required'] as List<Object?>? ?? const [])
        if (!value.containsKey(key)) '$at: "$key" is required',
      for (final MapEntry(:key, value: item) in value.entries)
        ...switch (properties[key] ?? additional) {
          final Map<String, Object?> sub => _check(sub, item, '$at/$key'),
          false => ['$at: "$key" is not allowed'],
          _ => const <String>[],
        },
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
}
