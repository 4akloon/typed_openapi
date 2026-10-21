import '../model/schema.dart';
import 'dart_type.dart';
import 'declaration_names.dart';
import 'enum_mapper.dart';
import 'ir.dart' show EnumKind, JsonKind;
import 'mapping_scope.dart';
import 'mapping_state.dart';
import 'mapping_tools.dart';
import 'model_mapper.dart';
import 'pending_declaration.dart';
import 'schema_queries.dart';
import 'schema_shapes.dart';
import 'union_mapper.dart';
import 'union_state.dart';

/// Creates the declaration of a schema once, the first time it is reached,
/// and hands it to the mapper of its kind: an enum, a union or a model.
final class Declarer {
  /// A declarer that fills declarations in with the given mappers.
  Declarer(this._tools, this._enums, this._models, this._unions);

  final MappingTools _tools;
  final EnumMapper _enums;
  final ModelMapper _models;
  final UnionMapper _unions;

  /// The declaration of the component [schema] with identity [id], named by
  /// its key or by the `name` of its override.
  DartType declareComponent(
    SchemaObject schema,
    DeclId id,
    MappingScope scope,
  ) {
    final context = _tools.context;
    final override = context.overrides.schemaAt(schema.location);
    final seed = PendingDeclaration(id)
      ..componentKey = DeclarationNames.referenceName(schema.location)
      ..overrideName = override == null
          ? null
          : context.checkedOverrideName(
              override,
              'name',
              override.name,
              .type,
              what: 'type',
            );
    return declare(schema, scope, seed);
  }

  /// The declaration of the inline [schema] with identity [id], named by
  /// [hint].
  DartType declareInline(
    SchemaObject schema,
    DeclId id,
    MappingScope scope,
    NameHint hint,
  ) => declare(schema, scope, PendingDeclaration(id)..hint = hint);

  /// The declaration of [schema] that [seed] starts: the one it has already
  /// when it is reached again, else [seed], filled in. Every location has its
  /// own declaration, an inline enum too.
  DartType declare(
    SchemaObject schema,
    MappingScope scope,
    PendingDeclaration seed,
  ) {
    final id = seed.id;
    final state = _tools.state;
    final nullable = SchemaQueries.isNullable(schema);
    if (state.pending.containsKey(id)) return NamedType(id, nullable: nullable);
    final values = SchemaShapes.enumValues(schema);
    final kind = values == null ? null : SchemaQueries.enumKind(schema, values);
    if (_staysJsonValue(schema, values, kind)) return const CoreType(.json);
    final draft = values == null || kind == null
        ? null
        : EnumDraft.of(values, kind, _enums.labels(schema, values));
    _register(seed, schema, draft);
    _fill(schema, seed, scope, draft);
    return NamedType(id, nullable: nullable);
  }

  /// Whether [schema] is generated as `JsonValue`: an enum of mixed values,
  /// or a union that no variant's JSON type can tell apart.
  bool _staysJsonValue(
    SchemaObject schema,
    List<Object?>? values,
    EnumKind? kind,
  ) {
    if (values != null && kind == null) {
      _tools.context.report(
        .enumMixedValues,
        'The values of this enum are not all strings, all numbers or all '
        'booleans; it is generated as JsonValue.',
        schema.location,
        fix: 'Give the enum values of one JSON type at the source.',
      );
      return true;
    }
    if (values != null) return false;
    if (_tools.queries.branches(schema) case (_, final branches)) {
      return _unions.isRawUnion(schema, branches);
    }
    return false;
  }

  /// Records [pending], the declaration of [schema], so reaching the schema
  /// again gives it back.
  void _register(
    PendingDeclaration pending,
    SchemaObject schema,
    EnumDraft? draft,
  ) {
    final state = _tools.state;
    pending.jsonKind = switch (draft?.kind) {
      .string => .string,
      .integer => .integer,
      .number => .number,
      .boolean => .boolean,
      null => _objectKind(schema),
    };
    pending.depth = (pending.hint?.parent?.depth ?? -1) + 1;
    state.pending[pending.id] = pending;
  }

  /// The JSON type of the values of a declaration that is no enum: an object
  /// for a model and a union with a discriminator, none for another union.
  JsonKind? _objectKind(SchemaObject schema) =>
      _tools.queries.branches(schema) == null ||
          schema.discriminator?.propertyName != null
      ? .object
      : null;

  /// Fills in [pending], the declaration of [schema], with the mapper of its
  /// kind.
  void _fill(
    SchemaObject schema,
    PendingDeclaration pending,
    MappingScope scope,
    EnumDraft? draft,
  ) {
    // A cycle that goes through this declaration ends at it, so what is
    // mapped below starts with no alias open.
    final aliases = _tools.state.aliases;
    final outer = {...aliases};
    aliases.clear();
    try {
      _mapKind(schema, pending, scope, draft);
    } finally {
      aliases
        ..clear()
        ..addAll(outer);
    }
  }

  void _mapKind(
    SchemaObject schema,
    PendingDeclaration pending,
    MappingScope scope,
    EnumDraft? draft,
  ) {
    if (draft != null) {
      _enums.declare(schema, pending, draft);
    } else if (_tools.queries.branches(schema) case (final kind, final all)) {
      _unions.declare(UnionSite(schema, pending, kind, all, scope));
    } else if (_tools.subtypes.subtypes(schema) case final subtypes
        when subtypes.isNotEmpty) {
      _unions.declare(
        UnionSite(schema, pending, .oneOf, subtypes, scope, isSubtypes: true),
      );
    } else {
      _tools.unionNotices.discriminatorWithoutSubtypes(schema);
      _models.declare(schema, pending, scope);
    }
  }
}
