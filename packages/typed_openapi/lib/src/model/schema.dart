import 'spec_node.dart';

/// A JSON Schema: a [BooleanSchema] or a [SchemaObject].
///
/// The model is a superset of OpenAPI 3.0 schemas and JSON Schema 2020-12
/// (OpenAPI 3.1 and 3.2). Nothing is converted between the two: a 3.0
/// `nullable: true` and a 3.1 `type: [string, "null"]` are both kept as
/// written; the normalizer reconciles them later.
sealed class Schema extends SpecNode {
  /// Creates a schema.
  const Schema({
    required super.location,
    super.extensions,
    super.unknownKeys,
  });
}

/// `true` (any value) or `false` (no value) used as a schema.
final class BooleanSchema extends Schema {
  /// Creates a boolean schema.
  const BooleanSchema({required super.location, required this.value});

  /// Whether every value is valid.
  final bool value;
}

/// The JSON types a schema's `type` can name.
enum SchemaType {
  /// `string`.
  string('string'),

  /// `number`.
  number('number'),

  /// `integer`.
  integer('integer'),

  /// `boolean`.
  boolean('boolean'),

  /// `array`.
  array('array'),

  /// `object`.
  object('object'),

  /// `null` (JSON Schema 2020-12 only).
  nullType('null');

  const SchemaType(this.wire);

  /// The name used in specs.
  final String wire;

  /// The types by [wire] name.
  static final Map<String, SchemaType> byWire = Map.unmodifiable({
    for (final type in values) type.wire: type,
  });

  /// Whether the plain JSON [value] is of this type; `integer` accepts a
  /// whole number written as `3.0`.
  bool accepts(Object? value) => switch (this) {
    .string => value is String,
    .number => value is num,
    .integer =>
      value is int ||
          (value is double && value.isFinite && value == value.floorToDouble()),
    .boolean => value is bool,
    .array => value is List<Object?>,
    .object => value is Map<String, Object?>,
    .nullType => value == null,
  };
}

/// A Schema Object.
///
/// A raw value that may be `null` in the spec is kept as a one-element
/// record, so `default: null` reads as `(null,)` and a missing `default` as
/// `null`.
final class SchemaObject extends Schema {
  /// Creates a schema object.
  const SchemaObject({
    required super.location,
    this.ref,
    this.types = const [],
    this.nullable,
    this.format,
    this.title,
    this.description,
    this.deprecated = false,
    this.readOnly = false,
    this.writeOnly = false,
    this.defaultValue,
    this.constValue,
    this.enumValues,
    this.example,
    this.examples = const [],
    this.properties = const {},
    this.required = const [],
    this.additionalProperties,
    this.minProperties,
    this.maxProperties,
    this.items,
    this.prefixItems = const [],
    this.minItems,
    this.maxItems,
    this.uniqueItems = false,
    this.allOf = const [],
    this.oneOf = const [],
    this.anyOf = const [],
    this.not,
    this.discriminator,
    this.minimum,
    this.maximum,
    this.exclusiveMinimum,
    this.exclusiveMaximum,
    this.exclusiveMinimumFlag,
    this.exclusiveMaximumFlag,
    this.multipleOf,
    this.minLength,
    this.maxLength,
    this.pattern,
    this.contentMediaType,
    this.contentEncoding,
    this.contentSchema,
    this.otherKeywords = const {},
    super.extensions,
    super.unknownKeys,
  });

  /// The `$ref` keyword as written; the other keywords apply next to it.
  final String? ref;

  /// `type`, as a list even when the spec wrote a single string.
  final List<SchemaType> types;

  /// OpenAPI 3.0 `nullable`.
  final bool? nullable;

  /// `format`.
  final String? format;

  /// `title`.
  final String? title;

  /// `description`.
  final String? description;

  /// `deprecated`.
  final bool deprecated;

  /// `readOnly`.
  final bool readOnly;

  /// `writeOnly`.
  final bool writeOnly;

  /// `default`.
  final (Object?,)? defaultValue;

  /// `const`.
  final (Object?,)? constValue;

  /// `enum`.
  final List<Object?>? enumValues;

  /// `example` (deprecated in 3.1).
  final (Object?,)? example;

  /// `examples`, the JSON Schema list of examples.
  final List<Object?> examples;

  /// `properties`, in document order.
  final Map<String, Schema> properties;

  /// `required`.
  final List<String> required;

  /// `additionalProperties`; a [BooleanSchema] when the spec wrote a boolean.
  final Schema? additionalProperties;

  /// `minProperties`.
  final int? minProperties;

  /// `maxProperties`.
  final int? maxProperties;

  /// `items`.
  final Schema? items;

  /// `prefixItems`.
  final List<Schema> prefixItems;

  /// `minItems`.
  final int? minItems;

  /// `maxItems`.
  final int? maxItems;

  /// `uniqueItems`.
  final bool uniqueItems;

  /// `allOf`.
  final List<Schema> allOf;

  /// `oneOf`.
  final List<Schema> oneOf;

  /// `anyOf`.
  final List<Schema> anyOf;

  /// `not`.
  final Schema? not;

  /// `discriminator`.
  final Discriminator? discriminator;

  /// `minimum`.
  final num? minimum;

  /// `maximum`.
  final num? maximum;

  /// `exclusiveMinimum` written as a number (JSON Schema 2020-12).
  final num? exclusiveMinimum;

  /// `exclusiveMaximum` written as a number (JSON Schema 2020-12).
  final num? exclusiveMaximum;

  /// `exclusiveMinimum` written as a boolean (OpenAPI 3.0).
  final bool? exclusiveMinimumFlag;

  /// `exclusiveMaximum` written as a boolean (OpenAPI 3.0).
  final bool? exclusiveMaximumFlag;

  /// `multipleOf`.
  final num? multipleOf;

  /// `minLength`.
  final int? minLength;

  /// `maxLength`.
  final int? maxLength;

  /// `pattern`.
  final String? pattern;

  /// `contentMediaType`.
  final String? contentMediaType;

  /// `contentEncoding`.
  final String? contentEncoding;

  /// `contentSchema`.
  final Schema? contentSchema;

  /// JSON Schema 2020-12 keywords the model does not read yet, such as
  /// `$defs`, `if` or `patternProperties`, with their raw values.
  final Map<String, Object?> otherKeywords;
}

/// A Discriminator Object.
final class Discriminator extends SpecNode {
  /// Creates a discriminator.
  const Discriminator({
    required super.location,
    this.propertyName,
    this.mapping = const {},
    this.defaultMapping,
    super.extensions,
    super.unknownKeys,
  });

  /// `propertyName`; required by the spec.
  final String? propertyName;

  /// `mapping` from a property value to a schema name or `$ref`.
  final Map<String, String> mapping;

  /// `defaultMapping` (OpenAPI 3.2).
  final String? defaultMapping;
}
