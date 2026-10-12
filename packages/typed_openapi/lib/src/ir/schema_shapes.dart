import '../model/schema.dart';

/// Questions about the shape of a schema that the schema mapper and the
/// direction index both ask: whether it is only `null`, what enum values it
/// has, which one schema it stands for.
final class SchemaShapes {
  const SchemaShapes._();

  /// The one schema [schema] stands for (R6.3, rules carried from M3): the
  /// part of an `allOf` with one part, or the branch of a `oneOf`/`anyOf`
  /// with one branch besides `null`; null when there is none.
  static Schema? singleOf(SchemaObject schema) {
    if (schema.properties.isNotEmpty || enumValues(schema) != null) {
      return null;
    }
    final branches = [...schema.oneOf, ...schema.anyOf];
    if (schema.allOf.length == 1 && branches.isEmpty) return schema.allOf.first;
    if (schema.allOf.isNotEmpty) return null;
    final nonNull = [
      for (final branch in branches)
        if (!isNullOnly(branch)) branch,
    ];
    return nonNull.length == 1 && (schema.oneOf.isEmpty || schema.anyOf.isEmpty)
        ? nonNull.single
        : null;
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
