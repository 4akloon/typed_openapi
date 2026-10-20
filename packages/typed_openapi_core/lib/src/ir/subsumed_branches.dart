import '../model/schema.dart';
import 'decimal.dart';
import 'ir.dart' show JsonKind;
import 'ref_follower.dart';

/// The branches of a union that add no value to another branch (TOA455):
/// an enum or `const` next to a plain branch of the same JSON type.
final class SubsumedBranches {
  const SubsumedBranches._();

  /// The branches of the `oneOf` or `anyOf` of [schema] that add no value
  /// to another branch (TOA455), each with the JSON type of the branch that
  /// has its values: an enum or `const` of one primitive type next to a
  /// branch of that type that has all its values, in a union without a
  /// discriminator (`anyOf: [string, {enum: ['']}]`). The other branch is
  /// plain: a string, integer, number or boolean written inline, or a
  /// `$ref` that [refs] follows to one, with no `enum`, `const`,
  /// `format`, `pattern` or keyword the rule does not model (`if`, `not`,
  /// `dependentSchemas`, ...); its length and range constraints
  /// (`maxLength`, `minimum`, `multipleOf`, ...) are met by every enum
  /// value. In OpenAPI 3.1 and later the keywords written next to the
  /// `$ref` of a branch are the branch's own: the same limits apply to
  /// them, and in 3.0 they are ignored. An integer
  /// enum is also covered by a plain `number`; a number enum is not covered
  /// by an `integer`. The enum branch is written inline; a schema that is
  /// also a model or has an `allOf` has none.
  static Map<SchemaObject, JsonKind> of(
    SchemaObject schema, {
    RefFollower? refs,
  }) {
    if (schema.oneOf.isNotEmpty == schema.anyOf.isNotEmpty ||
        schema.properties.isNotEmpty ||
        schema.allOf.isNotEmpty ||
        schema.discriminator?.propertyName != null) {
      return const {};
    }
    final branches = [...schema.oneOf, ...schema.anyOf];
    final plain = [
      for (final branch in branches) ?_plain(branch, refs),
    ];
    final dropped = <SchemaObject, JsonKind>{};
    if (plain.isEmpty) return dropped;
    for (final branch in branches) {
      if (branch is! SchemaObject) continue;
      final kind = _valuesKind(branch);
      if (kind == null) continue;
      final values = branch.enumValues ?? [?branch.constValue?.$1];
      for (final (plainKind, constraints) in plain) {
        if ((plainKind == kind ||
                (kind == .integer && plainKind == JsonKind.number)) &&
            _allows(constraints, values)) {
          dropped[branch] = plainKind;
          break;
        }
      }
    }
    return dropped;
  }

  /// The JSON type of [schema] and the schemas whose length and range
  /// constraints apply when it allows every value of that type but those
  /// the constraints cut: a string, integer, number or boolean with no enum,
  /// `const`, format, pattern, structure or keyword the rule does not model.
  /// A `$ref` is read through [refs]; from 3.1 its sibling keywords are
  /// checked like the target's and their constraints apply too.
  static (JsonKind, List<SchemaObject>)? _plain(
    Schema schema,
    RefFollower? refs,
  ) {
    var target = schema;
    final constraints = <SchemaObject>[];
    if (schema is SchemaObject && schema.ref != null) {
      if (refs == null) return null;
      target = refs.resolve(schema) ?? schema;
      if (refs.siblings) {
        if (!_isPlainShape(schema, allowRef: true)) return null;
        constraints.add(schema);
      }
    }
    if (target is! SchemaObject ||
        target.ref != null ||
        !_isPlainShape(target)) {
      return null;
    }
    constraints.add(target);
    final kind = _primitiveKind(target);
    if (kind == null) return null;
    // A sibling `type` that names another type leaves no value at all.
    for (final constraint in constraints) {
      final types = [
        for (final type in constraint.types)
          if (type != SchemaType.nullType) type,
      ];
      if (types.isNotEmpty && _primitiveKind(constraint) != kind) return null;
    }
    return (kind, constraints);
  }

  /// Keywords of [SchemaObject.otherKeywords] that only annotate or
  /// organise a schema, so a branch that has them is still plain.
  static const _inertKeywords = {
    r'$comment',
    r'$id',
    r'$schema',
    r'$anchor',
    r'$dynamicAnchor',
    r'$defs',
    r'$vocabulary',
  };

  /// Whether [schema] has none of the keywords that make a primitive branch
  /// more than "every value of its type, within the length and range
  /// limits": `enum`, `const`, `format`, `pattern`, `content*`, structure,
  /// composition, `not`, a discriminator, or a keyword the rule does not
  /// model (`if`/`then`/`else`, `dependentSchemas`, ...). With [allowRef],
  /// a `$ref` is not a reason (the branch is a `$ref` with siblings).
  static bool _isPlainShape(SchemaObject schema, {bool allowRef = false}) =>
      (allowRef || schema.ref == null) &&
      schema.enumValues == null &&
      schema.constValue == null &&
      schema.format == null &&
      schema.pattern == null &&
      schema.contentMediaType == null &&
      schema.contentEncoding == null &&
      schema.contentSchema == null &&
      schema.properties.isEmpty &&
      schema.items == null &&
      schema.prefixItems.isEmpty &&
      schema.additionalProperties == null &&
      schema.allOf.isEmpty &&
      schema.oneOf.isEmpty &&
      schema.anyOf.isEmpty &&
      schema.not == null &&
      schema.discriminator == null &&
      schema.otherKeywords.keys.every(_inertKeywords.contains);

  /// Whether every one of [values] (strings, numbers or booleans) meets the
  /// length and range constraints of every schema in [schemas].
  static bool _allows(List<SchemaObject> schemas, List<Object?> values) {
    for (final schema in schemas) {
      for (final value in values) {
        if (!_allowsOne(schema, value)) return false;
      }
    }
    return true;
  }

  static bool _allowsOne(SchemaObject schema, Object? value) {
    if (value is String) {
      final length = value.runes.length;
      return length >= (schema.minLength ?? 0) &&
          length <= (schema.maxLength ?? length);
    }
    if (value is! num) return true;
    final minimum = schema.minimum;
    final maximum = schema.maximum;
    if (minimum != null &&
        (schema.exclusiveMinimumFlag == true
            ? value <= minimum
            : value < minimum)) {
      return false;
    }
    if (maximum != null &&
        (schema.exclusiveMaximumFlag == true
            ? value >= maximum
            : value > maximum)) {
      return false;
    }
    if (schema.exclusiveMinimum case final bound? when value <= bound) {
      return false;
    }
    if (schema.exclusiveMaximum case final bound? when value >= bound) {
      return false;
    }
    if (schema.multipleOf case final step? when step > 0) {
      return Decimal.of(value).isMultipleOf(Decimal.of(step));
    }
    return true;
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
}
