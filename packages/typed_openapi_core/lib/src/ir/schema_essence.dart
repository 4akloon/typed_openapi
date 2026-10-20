/// Reduces the plain tree of a schema to what makes it a type: the same
/// tree without the annotations at every depth and with nullability said
/// one way, so two schemas that only annotate differently, or one of which
/// spells `nullable` as a type list, are equal under `JsonEquality`.
///
/// Only keywords at a schema position are touched: a property named
/// `description` is a property, not an annotation.
final class SchemaEssence {
  const SchemaEssence._();

  /// Keywords that describe a schema without changing the type it is.
  static const _annotations = {
    r'$comment',
    'deprecated',
    'description',
    'example',
    'examples',
    'externalDocs',
    'nullable',
    'title',
  };

  /// Keywords whose value is a schema.
  static const _schemas = {
    'additionalProperties',
    'contains',
    'contentSchema',
    'else',
    'if',
    'items',
    'not',
    'propertyNames',
    'then',
    'unevaluatedItems',
    'unevaluatedProperties',
  };

  /// Keywords whose value is a map of schemas by name.
  static const _schemaMaps = {
    r'$defs',
    'definitions',
    'dependentSchemas',
    'patternProperties',
    'properties',
  };

  /// Keywords whose value is a list of schemas.
  static const _schemaLists = {'allOf', 'anyOf', 'oneOf', 'prefixItems'};

  /// The essence of [schema], a plain tree; anything that is not a map is
  /// returned as it is (a boolean schema).
  static Object? of(Object? schema) {
    if (schema is! Map<Object?, Object?>) return schema;
    return {
      for (final MapEntry(:key, :value) in schema.entries)
        if (!_annotations.contains(key))
          key: switch (key) {
            'type' => _type(value),
            final String name when _schemas.contains(name) => of(value),
            final String name when _schemaMaps.contains(name) => _each(
              value,
              of,
            ),
            final String name when _schemaLists.contains(name) =>
              value is List<Object?>
                  ? [for (final part in value) of(part)]
                  : value,
            _ => value,
          },
    };
  }

  /// A `type` without `null` (the 3.1 spelling of nullable), as the one
  /// type when one is left.
  static Object? _type(Object? type) {
    if (type is! List<Object?>) return type;
    final rest = [
      for (final item in type)
        if (item != 'null') item,
    ];
    return rest.length == 1 ? rest.single : rest;
  }

  static Object? _each(Object? map, Object? Function(Object?) read) =>
      map is Map<Object?, Object?>
      ? {for (final MapEntry(:key, :value) in map.entries) key: read(value)}
      : map;
}
