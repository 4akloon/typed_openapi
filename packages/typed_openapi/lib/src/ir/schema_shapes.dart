import '../model/schema.dart';
import 'ir.dart' show JsonKind;

/// Questions about the shape of a schema that the schema mapper and the
/// direction index both ask: whether it is only `null`, what enum values it
/// has, which one schema it stands for.
final class SchemaShapes {
  const SchemaShapes._();

  /// The one schema [schema] stands for (R6.3, rules carried from M3): the
  /// part of an `allOf` with one part besides parts that only annotate
  /// ([isAnnotationOnly]), or the branch of a `oneOf`/`anyOf` with one branch
  /// besides `null`; null when there is none.
  static Schema? singleOf(SchemaObject schema) {
    if (schema.properties.isNotEmpty || enumValues(schema) != null) {
      return null;
    }
    final branches = [...schema.oneOf, ...schema.anyOf];
    if (schema.allOf.isNotEmpty && branches.isEmpty) {
      final structural = [
        for (final part in schema.allOf)
          if (!isAnnotationOnly(part)) part,
      ];
      if (structural.length == 1) return structural.single;
      return schema.allOf.length == 1 ? schema.allOf.first : null;
    }
    if (schema.allOf.isNotEmpty) return null;
    final dropped = subsumedBranches(schema);
    final nonNull = [
      for (final branch in branches)
        if (!isNullOnly(branch) && !dropped.containsKey(branch)) branch,
    ];
    return nonNull.length == 1 && (schema.oneOf.isEmpty || schema.anyOf.isEmpty)
        ? nonNull.single
        : null;
  }

  /// The branches of the `oneOf` or `anyOf` of [schema] that add no value
  /// to another branch (TOA455), each with the JSON type of the branch that
  /// has its values: an enum or `const` of one primitive type next to a
  /// branch of that type with no constraint at all, in a union without a
  /// discriminator (`anyOf: [string, {enum: ['']}]`). An integer enum is
  /// also covered by a plain `number`; a number enum is not covered by an
  /// `integer`. Only branches written inline count, and a schema that is
  /// also a model or has an `allOf` has none.
  static Map<SchemaObject, JsonKind> subsumedBranches(SchemaObject schema) {
    if (schema.oneOf.isNotEmpty == schema.anyOf.isNotEmpty ||
        schema.properties.isNotEmpty ||
        schema.allOf.isNotEmpty ||
        schema.discriminator?.propertyName != null) {
      return const {};
    }
    final branches = [...schema.oneOf, ...schema.anyOf];
    final plain = {for (final branch in branches) ?_plainKind(branch)};
    final dropped = <SchemaObject, JsonKind>{};
    for (final branch in branches) {
      if (branch is! SchemaObject) continue;
      final kind = _valuesKind(branch);
      if (kind == null) continue;
      if (plain.contains(kind)) {
        dropped[branch] = kind;
      } else if (kind == .integer && plain.contains(JsonKind.number)) {
        dropped[branch] = .number;
      }
    }
    return dropped;
  }

  /// The JSON type of [schema] when it is written inline and allows every
  /// value of that type: a string, integer, number or boolean with no enum,
  /// `const`, format or other constraint.
  static JsonKind? _plainKind(Schema schema) {
    if (schema is! SchemaObject ||
        schema.ref != null ||
        schema.enumValues != null ||
        schema.constValue != null ||
        schema.format != null ||
        schema.pattern != null ||
        schema.minLength != null ||
        schema.maxLength != null ||
        schema.minimum != null ||
        schema.maximum != null ||
        schema.exclusiveMinimum != null ||
        schema.exclusiveMaximum != null ||
        schema.exclusiveMinimumFlag != null ||
        schema.exclusiveMaximumFlag != null ||
        schema.multipleOf != null ||
        schema.contentMediaType != null ||
        schema.contentEncoding != null ||
        schema.contentSchema != null ||
        schema.properties.isNotEmpty ||
        schema.items != null ||
        schema.prefixItems.isNotEmpty ||
        schema.additionalProperties != null ||
        schema.allOf.isNotEmpty ||
        schema.oneOf.isNotEmpty ||
        schema.anyOf.isNotEmpty ||
        schema.not != null ||
        schema.discriminator != null) {
      return null;
    }
    return _primitiveKind(schema);
  }

  /// The JSON type of the values of the enum or `const` [schema] written
  /// inline, when they are all non-null and of one primitive type that the
  /// `type` of [schema], if it has one, agrees with; null for any other
  /// schema.
  static JsonKind? _valuesKind(SchemaObject schema) {
    if (schema.ref != null ||
        schema.properties.isNotEmpty ||
        schema.allOf.isNotEmpty ||
        schema.oneOf.isNotEmpty ||
        schema.anyOf.isNotEmpty ||
        schema.nullable == true) {
      return null;
    }
    final values = schema.enumValues ?? [?schema.constValue?.$1];
    if (values.isEmpty || values.contains(null)) return null;
    final declared = _primitiveKind(schema);
    if (declared == null && schema.types.isNotEmpty) return null;
    final JsonKind? kind;
    if (values.every((v) => v is String)) {
      kind = .string;
    } else if (values.every((v) => v is bool)) {
      kind = .boolean;
    } else if (values.every((v) => v is int)) {
      kind = declared == .number ? .number : .integer;
    } else if (values.every((v) => v is num)) {
      kind = .number;
    } else {
      kind = null;
    }
    return declared == null || declared == kind ? kind : null;
  }

  /// The one JSON type of the `type` of [schema] besides `null` when it is
  /// a string, integer, number or boolean; null when it has none or
  /// several, or an other one.
  static JsonKind? _primitiveKind(SchemaObject schema) {
    final types = [
      for (final type in schema.types)
        if (type != SchemaType.nullType) type,
    ];
    if (types.length != 1) return null;
    return switch (types.single) {
      .string => .string,
      .integer => .integer,
      .number => .number,
      .boolean => .boolean,
      _ => null,
    };
  }

  /// Whether [schema] is written inline and adds no structure: no `$ref`, no
  /// type but `null`, no properties, `required`, items, `additionalProperties`,
  /// `format`, enum, `const`, `not`, discriminator or composition. What it
  /// has is annotations (`description`, `default`, `deprecated`, `title`,
  /// `readOnly`, `nullable`, ...) and constraints the client does not
  /// check; an `allOf` part like this is not merged into a model.
  static bool isAnnotationOnly(Schema schema) =>
      schema is SchemaObject &&
      schema.ref == null &&
      schema.types.every((t) => t == .nullType) &&
      schema.properties.isEmpty &&
      schema.required.isEmpty &&
      schema.items == null &&
      schema.prefixItems.isEmpty &&
      schema.additionalProperties == null &&
      schema.format == null &&
      (schema.enumValues == null || isNullOnly(schema)) &&
      (schema.constValue == null || isNullOnly(schema)) &&
      schema.allOf.isEmpty &&
      schema.oneOf.isEmpty &&
      schema.anyOf.isEmpty &&
      schema.not == null &&
      schema.discriminator == null;

  /// Whether an annotation-only `allOf` [part] says the value may be `null`:
  /// `nullable: true`, `type: 'null'` or a `null` enum or `const`.
  static bool allowsNull(SchemaObject part) =>
      (part.nullable ?? false) ||
      part.types.contains(SchemaType.nullType) ||
      isNullOnly(part);

  /// The parts of the `allOf` of [schema] that [singleOf] sets aside
  /// because they only annotate: empty unless [schema] stands for the one
  /// structural part of its `allOf`.
  static List<SchemaObject> annotationParts(SchemaObject schema) {
    final single = singleOf(schema);
    if (single == null || !schema.allOf.contains(single)) return const [];
    return [
      for (final part in schema.allOf)
        if (part is SchemaObject &&
            !identical(part, single) &&
            isAnnotationOnly(part))
          part,
    ];
  }

  /// Whether [schema] is written inline and allows only `null`.
  static bool isNullOnly(Schema schema) =>
      schema is SchemaObject &&
      schema.ref == null &&
      ((schema.types.length == 1 && schema.types.single == .nullType) ||
          (schema.enumValues != null &&
              schema.enumValues!.every((v) => v == null)) ||
          (schema.enumValues == null &&
              schema.constValue != null &&
              schema.constValue!.$1 == null));

  /// The non-null values of an enum, or null when [schema] is not one: its
  /// `enum`, its `const` as a one-value enum, or the values of a `oneOf` or
  /// `anyOf` whose branches are all `const`s or enums written inline
  /// (`oneOf: [{const: red}, {const: green}]`).
  static List<Object?>? enumValues(SchemaObject schema) =>
      _ownValues(schema) ?? _branchValues(schema);

  static List<Object?>? _ownValues(SchemaObject schema) {
    final values = [
      ...?schema.enumValues,
      if (schema.enumValues == null) ?schema.constValue?.$1,
    ];
    final nonNull = [for (final v in values) ?v];
    return nonNull.isEmpty ? null : nonNull;
  }

  static List<Object?>? _branchValues(SchemaObject schema) {
    if (schema.properties.isNotEmpty ||
        schema.allOf.isNotEmpty ||
        schema.oneOf.isNotEmpty == schema.anyOf.isNotEmpty) {
      return null;
    }
    final values = <Object?>[];
    for (final branch in [...schema.oneOf, ...schema.anyOf]) {
      if (isNullOnly(branch)) continue;
      if (branch is! SchemaObject || branch.ref != null) return null;
      if (branch.properties.isNotEmpty ||
          branch.allOf.isNotEmpty ||
          branch.oneOf.isNotEmpty ||
          branch.anyOf.isNotEmpty) {
        return null;
      }
      final own = _ownValues(branch);
      if (own == null) return null;
      for (final value in own) {
        if (!values.contains(value)) values.add(value);
      }
    }
    return values.isEmpty ? null : values;
  }
}
