import '../model/schema.dart';
import 'dart_type.dart';
import 'ir.dart' show UnionKind;
import 'ir_context.dart';
import 'ref_follower.dart';
import 'schema_shapes.dart';

/// Questions the mappers ask about a schema that need the spec's `$ref`s:
/// what it resolves to, whether it is nullable, which branches make it a
/// union, whether it holds a secret in raw JSON.
final class SchemaQueries {
  /// Questions about the schemas of the spec of [_context].
  SchemaQueries(this._context);

  final IrContext _context;

  /// How the schema questions follow a `$ref`. Lazy because a field
  /// initializer cannot read `_context`.
  late final RefFollower refs = RefFollower.of(_context.model);

  /// The schema [schema] resolves to, or null when it cannot be followed or
  /// is not an object schema.
  SchemaObject? resolved(Schema schema) =>
      switch (_context.model.resolveSchema(schema)) {
        final SchemaObject object => object,
        _ => null,
      };

  /// Whether [schema] allows `null`: 3.0 `nullable`, `null` in `type`,
  /// `null` among the `enum` values or a null branch, or an `allOf` part
  /// that only says so (`allOf: [{$ref: Pet}, {nullable: true}]`).
  static bool isNullable(SchemaObject schema) =>
      (schema.nullable ?? false) ||
      schema.types.contains(SchemaType.nullType) ||
      (schema.enumValues?.contains(null) ?? false) ||
      schema.oneOf.any(SchemaShapes.isNullOnly) ||
      schema.anyOf.any(SchemaShapes.isNullOnly) ||
      schema.allOf.any(
        (part) =>
            part is SchemaObject &&
            SchemaShapes.isAnnotationOnly(part) &&
            SchemaShapes.allowsNull(part),
      );

  /// The kind and the non-null branches of a union: a `oneOf` (or else an
  /// `anyOf`) with more than one branch besides `null` and the branches
  /// that add no value to another ([SchemaShapes.subsumedBranches]).
  (UnionKind, List<Schema>)? branches(SchemaObject schema) {
    final (kind, branches) = schema.oneOf.isNotEmpty
        ? (UnionKind.oneOf, schema.oneOf)
        : (UnionKind.anyOf, schema.anyOf);
    final dropped = SchemaShapes.subsumedBranches(schema, refs: refs);
    final nonNull = [
      for (final branch in branches)
        if (!SchemaShapes.isNullOnly(branch) && !dropped.containsKey(branch))
          branch,
    ];
    // Branches that only add constraints (`required`, ...) or only hold one
    // value each (an enum) do not make a union.
    if (nonNull.length < 2 ||
        nonNull.every(addsOnlyConstraints) ||
        SchemaShapes.enumValues(schema) != null) {
      return null;
    }
    return (kind, nonNull);
  }

  /// Whether [schema] is written inline and only validates: `required`,
  /// `minProperties` and the like, with no `type` (or only `type: object`),
  /// `properties`, items, values, `allOf` or union of its own.
  static bool addsOnlyConstraints(Schema schema) =>
      schema is SchemaObject &&
      schema.ref == null &&
      schema.types.every((t) => t == .object) &&
      schema.properties.isEmpty &&
      schema.items == null &&
      schema.additionalProperties == null &&
      schema.format == null &&
      SchemaShapes.enumValues(schema) == null &&
      schema.allOf.isEmpty &&
      schema.oneOf.isEmpty &&
      schema.anyOf.isEmpty;

  /// Whether a value of [type], mapped from [schema], is raw JSON that could
  /// hold a secret: nothing prints the properties of raw JSON, so a secret
  /// anywhere in [schema] (its properties, the parts of its `allOf`, the
  /// branches of a union that stays `JsonValue`) makes the value print as
  /// `<redacted>`.
  bool holdsRawSecret(Schema schema, DartType? type) =>
      type != null &&
      type.holdsRawJson &&
      SchemaShapes.carriesSecret(schema, refs: refs, intoProperties: true);
}
