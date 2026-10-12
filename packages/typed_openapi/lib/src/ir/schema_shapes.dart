import '../model/schema.dart';
import 'decimal.dart';
import 'ir.dart' show JsonKind;

/// How a schema question follows a `$ref`: [resolve] reaches the schema a
/// `$ref` names, and [siblings] says whether the keywords written next to a
/// `$ref` count (OpenAPI 3.1 and later; 3.0 ignores them).
final class RefFollower {
  /// Creates a follower.
  const RefFollower(this.resolve, {required this.siblings});

  /// The schema a `$ref` names, or null when it cannot be followed.
  final Schema? Function(Schema) resolve;

  /// Whether keywords beside a `$ref` are keywords of the schema.
  final bool siblings;
}

/// Questions about the shape of a schema that the schema mapper and the
/// direction index both ask: whether it is only `null`, what enum values it
/// has, which one schema it stands for.
final class SchemaShapes {
  const SchemaShapes._();

  /// The one schema [schema] stands for (R6.3, rules carried from M3): the
  /// part of an `allOf` with one part besides parts that only annotate
  /// ([isAnnotationOnly]), or the branch of a `oneOf`/`anyOf` with one branch
  /// besides `null` and the branches that add no value to another
  /// ([subsumedBranches]); null when there is none. A [refs] follows the
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
    final dropped = subsumedBranches(schema, refs: refs);
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
  static Map<SchemaObject, JsonKind> subsumedBranches(
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

  /// The schemas that say what the property [property] is, in the order they
  /// are met: the property, the annotation-only parts of its `allOf`
  /// ([annotationParts]), and the schema it stands for ([singleOf]: the one
  /// part of an `allOf`, or the one branch of a `oneOf`/`anyOf` besides
  /// `null`), each followed through its `$ref` ([refs]) and again through
  /// the one schema it stands for. `readOnly`, `writeOnly` and `format:
  /// password` are read from every one of them, so a nullable
  /// `anyOf: [{type: string, format: password}, {type: 'null'}]` (Pydantic's
  /// `Optional[SecretStr]`) is as much a secret as the plain string.
  static List<SchemaObject> annotationSources(
    Schema property, {
    required RefFollower refs,
  }) {
    final sources = <SchemaObject>[];
    final seen = <Object>{};
    void visit(Schema schema) {
      if (schema is! SchemaObject || !seen.add(schema.location)) return;
      sources.add(schema);
      if (schema.ref != null) {
        if (refs.resolve(schema) case final target?) visit(target);
        return;
      }
      sources.addAll(annotationParts(schema));
      if (singleOf(schema, refs: refs) case final single?) visit(single);
    }

    visit(property);
    return sources;
  }

  /// Whether a value of [schema] is a secret that must not be printed
  /// (`toString` writes `<redacted>`): a source of [annotationSources] is
  /// `writeOnly` or has `format: password`, or the value holds one: an
  /// array whose items are secrets, an object whose `additionalProperties`
  /// are, or a `oneOf`/`anyOf` with a secret branch (a union whose value may
  /// be the secret, also when it is not generated as a union).
  ///
  /// By default the properties of an object are not looked into: the model
  /// of the object redacts its own. With [intoProperties] they are, and so
  /// are the parts of an `allOf`, at any depth (a cycle is followed once):
  /// that is the question to ask of a value that stays raw JSON (`JsonValue`,
  /// the unknown variant of a union), which no model prints.
  static bool carriesSecret(
    Schema schema, {
    required RefFollower refs,
    bool intoProperties = false,
    Set<Object>? seen,
  }) {
    final visited = seen ?? <Object>{};
    if (schema is! SchemaObject || !visited.add(schema.location)) return false;
    for (final source in annotationSources(schema, refs: refs)) {
      if (source.writeOnly || source.format == 'password') return true;
      for (final inner in [
        ?source.items,
        ...source.prefixItems,
        ?source.additionalProperties,
        for (final branch in [...source.oneOf, ...source.anyOf])
          if (!isNullOnly(branch)) branch,
        if (intoProperties) ...source.properties.values,
        if (intoProperties) ...source.allOf,
      ]) {
        if (carriesSecret(
          inner,
          refs: refs,
          intoProperties: intoProperties,
          seen: visited,
        )) {
          return true;
        }
      }
    }
    return false;
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
