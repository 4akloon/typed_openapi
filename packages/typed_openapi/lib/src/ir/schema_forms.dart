import '../model/schema.dart';
import 'ref_follower.dart';
import 'subsumed_branches.dart';

/// What form a schema has: whether it is only `null`, an enum, an annotation
/// beside the schema it stands for, or a wrapper of one other schema.
final class SchemaForms {
  const SchemaForms._();

  /// The one schema [schema] stands for (R6.3, rules carried from M3): the
  /// part of an `allOf` with one part besides parts that only annotate
  /// ([isAnnotationOnly]), or the branch of a `oneOf`/`anyOf` with one branch
  /// besides `null` and the branches that add no value to another
  /// ([SubsumedBranches.of]); null when there is none. A [refs] follows the
  /// `$ref` of a branch.
  static Schema? singleOf(SchemaObject schema, {RefFollower? refs}) {
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
    final dropped = SubsumedBranches.of(schema, refs: refs);
    final nonNull = [
      for (final branch in branches)
        if (!isNullOnly(branch) && !dropped.containsKey(branch)) branch,
    ];
    return nonNull.length == 1 && (schema.oneOf.isEmpty || schema.anyOf.isEmpty)
        ? nonNull.single
        : null;
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
