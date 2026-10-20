import '../model/schema.dart';
import '../model/spec_node.dart';
import 'custom_schemas.dart';
import 'dart_type.dart';
import 'declaration_names.dart';
import 'declarer.dart';
import 'direction_index.dart';
import 'enum_mapper.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'mapping_scope.dart';
import 'mapping_tools.dart';
import 'model_mapper.dart';
import 'names.dart';
import 'override_notices.dart';
import 'pending_declaration.dart';
import 'schema_queries.dart';
import 'schema_shapes.dart';
import 'structural_mapper.dart';
import 'subtype_finder.dart';
import 'type_recursion.dart';
import 'union_mapper.dart';
import 'union_notices.dart';

export 'pending_declaration.dart' show NameHint;

/// Maps schemas to Dart types and collects the declarations they need
/// (R6.1–R6.3, R6.8).
///
/// Declarations are created when a schema is first mapped, so only schemas
/// reachable from what is mapped are generated (R4.2). A declaration's
/// identity is its schema location and variant ([DeclId]): reaching it again
/// (a structural alias used twice, an `allOf` base merged into several
/// models, a path item parameter shared by operations) gives the same
/// declaration, named after the first use. Names are given at the end
/// ([declarations]): component schemas keep their key, inline schemas are
/// named after their parent, and collisions get a suffix with a diagnostic
/// (R5.2).
final class SchemaMapper {
  /// Creates a mapper for the spec of [_context]; [directions] tells which
  /// schemas are split into response and request models.
  SchemaMapper(this._context, [DirectionIndex? directions])
    : _directions =
          directions ??
          DirectionIndex(
            _context.model,
            isExcluded: _context.isPropertyExcluded,
          );

  static const _names = DartNames();

  /// The extension that makes a property tri-state with
  /// `tri_state: extension` (R7.2).
  static const triStateExtension = ModelMapper.triStateExtension;

  final IrContext _context;
  final DirectionIndex _directions;

  // The collaborators are lazy because a field initializer cannot read the
  // other fields.
  late final MappingTools _tools = MappingTools(_context, _directions);
  late final SchemaQueries _queries = _tools.queries;
  late final DeclarationNames _declNames = _tools.names;
  late final OverrideNotices _notices = _tools.notices;
  late final EnumMapper _enums = EnumMapper(_tools);
  late final SubtypeFinder _subtypeFinder = _tools.subtypes;
  late final UnionNotices _unionNotices = _tools.unionNotices;
  late final TypeRecursion _types = TypeRecursion(
    map: _map,
    component: _component,
    replaced: _replaced,
  );
  late final ModelMapper _models = ModelMapper(_tools, _types);
  late final Declarer _declarer = Declarer(_tools, _enums, _models, _unions);
  late final StructuralMapper _structural = StructuralMapper(_tools, _types);
  late final CustomSchemas _custom = CustomSchemas(_tools, _types);
  late final UnionMapper _unions = UnionMapper(_tools, _types);

  Map<DeclId, PendingDeclaration> get _pending => _tools.state.pending;
  Set<SpecLocation> get _aliases => _tools.state.aliases;

  /// The type of [schema] used in [direction]; an inline declaration it
  /// needs is named by [hint]. For the request body of a PATCH operation
  /// ([patchBody]), the model's fields follow the tri-state rule (R7.2); a
  /// schema also used elsewhere gets a model of its own for this
  /// (`PetPatch`).
  DartType typeOf(
    Schema schema,
    NameHint hint, {
    ModelDirection direction = .both,
    bool patchBody = false,
  }) {
    final scope = MappingScope(
      direction: direction,
      patchTarget: patchBody ? _directions.bodyTarget(schema)?.location : null,
    );
    final type = _map(schema, hint, scope);
    if (patchBody && type is NamedType) {
      // A schema that other uses share is not tri-state: only the PATCH
      // model made for the body, or a schema nothing else uses, is.
      final pending = _pending[type.id];
      if (pending != null &&
          (pending.id.variant == .patch ||
              _directions.isPatchOnly(type.id.location))) {
        pending.patchBody = true;
      }
    }
    return type;
  }

  /// The type of the `components.schemas` entry [schema] used in
  /// [direction], as a `$ref` to it would have.
  DartType typeOfComponent(
    Schema schema, {
    ModelDirection direction = .both,
  }) {
    final scope = MappingScope(direction: direction);
    return switch (_context.model.resolveSchema(schema)) {
      final SchemaObject target => _component(target, scope),
      _ => const CoreType(.json),
    };
  }

  /// The id of the declaration of [schema] in the direction of [scope], and
  /// the scope for what is below it: the PATCH body model when [schema] is
  /// the body and is used elsewhere too, the request model of a split schema
  /// in a request, the schema's own declaration otherwise.
  (DeclId, MappingScope) _idOf(SchemaObject schema, MappingScope scope) {
    final isPatchTarget = schema.location == scope.patchTarget;
    final inner = isPatchTarget ? scope.withoutPatchTarget() : scope;
    if (isPatchTarget && _directions.separatesPatch(schema)) {
      return (DeclId(schema.location, variant: .patch), inner);
    }
    final id = DeclId(
      schema.location,
      variant: scope.direction == .request && _directions.splits(schema)
          ? .input
          : .base,
    );
    return (id, inner);
  }

  /// Names the declarations created so far in [scope]: overridden names
  /// first, then component keys, then inline names, each by location; the
  /// API lock's names win (M12). A declaration named already keeps its name.
  void nameDeclarations(NameScope scope) {
    _declNames.locked.lockTypes(scope, _pending.values);
    for (final pending in _ordered) {
      _declNames.claim(scope, pending);
    }
  }

  /// The declarations created so far, named in [scope] as
  /// [nameDeclarations] does. The types the emitters add for a declaration
  /// (the known values and the unknown value of an enum, the variant
  /// classes and the unknown variant of a union) are named in [scope]
  /// afterwards, in the same order, so they never take a declaration's
  /// name; a caller that names other types in between (the groups) keeps
  /// them before these too.
  List<Declaration> declarations(NameScope scope) {
    nameDeclarations(scope);
    return [
      for (final pending in _ordered)
        pending.build(_declNames.claim(scope, pending), scope),
    ];
  }

  /// The declarations in the order their names are claimed.
  List<PendingDeclaration> get _ordered =>
      DeclarationNames.inClaimOrder(_pending.values);

  /// The type of [schema], written inline or as a `$ref`; an inline
  /// declaration it needs is named by [hint].
  DartType _map(Schema schema, NameHint hint, MappingScope scope) {
    if (schema is BooleanSchema) return const CoreType(.json);
    final object = schema as SchemaObject;
    if (object.ref != null) {
      final target = _context.model.resolveSchema(object);
      // A broken `$ref` is reported by the resolver (TOA101).
      if (target is! SchemaObject) return const CoreType(.json);
      final type = _component(target, scope);
      return type.withNullable(
        type.nullable || SchemaQueries.isNullable(object),
      );
    }
    return _inline(object, hint, scope);
  }

  /// The type of a schema a `$ref` points to.
  DartType _component(SchemaObject schema, MappingScope scope) {
    if (_custom.substitute(schema, scope) case final type?) return type;
    final (id, inner) = _idOf(schema, scope);
    // A schema that extends a polymorphic base with `allOf` and adds nothing
    // is a subtype, not a reference to the base (which is the union).
    final single = switch (SchemaShapes.singleOf(schema, refs: _queries.refs)) {
      final part?
          when schema.allOf.contains(part) && _subtypeFinder.isBase(part) =>
        null,
      final part => part,
    };
    if (single == null && _declares(schema)) {
      if (inner.replacing) return _structural.nothingDeclared(schema);
      return _declarer.declareComponent(schema, id, inner);
    }
    return _alias(schema, single, inner);
  }

  /// The type of the component [schema] that has no declaration of its own
  /// (an array, a map, a scalar), or that stands for the one schema [single]:
  /// each use gets its type. One that refers back to itself without a
  /// declaration in between cannot be spelled out.
  DartType _alias(SchemaObject schema, Schema? single, MappingScope scope) {
    if (!scope.replacing) _notices.aliasHasNoEffect(schema);
    if (!_enterAlias(schema.location, scope)) return const CoreType(.json);
    try {
      final hint = NameHint(
        _names.pascal(DeclarationNames.referenceName(schema.location)) ??
            DeclarationNames.fallbackName,
        '',
      );
      if (single == null) return _structural.structural(schema, hint, scope);
      _unionNotices.subsumedBranches(schema, scope, collapsed: true);
      final type = _map(single, hint, scope);
      return type.withNullable(
        type.nullable || SchemaQueries.isNullable(schema),
      );
    } finally {
      _aliases.remove(schema.location);
    }
  }

  /// Marks the structural alias at [location] as being mapped; false, with
  /// a report unless a custom type replaces it, when it already is.
  bool _enterAlias(SpecLocation location, MappingScope scope) {
    if (_aliases.add(location)) return true;
    if (!scope.replacing) {
      _context.report(
        .recursiveAlias,
        'This schema refers to itself without an object between; the '
        'reference is generated as JsonValue.',
        location,
        fix: 'Make the recursive part an object schema at the source.',
      );
    }
    return false;
  }

  /// The type of the schema written inline: the schema it stands for, a
  /// declaration of its own, or a scalar, a list or a map.
  DartType _inline(SchemaObject schema, NameHint hint, MappingScope scope) {
    final single = SchemaShapes.singleOf(schema, refs: _queries.refs);
    if (single != null) {
      _unionNotices.subsumedBranches(schema, scope, collapsed: true);
      final type = _map(single, hint, scope);
      return type.withNullable(
        type.nullable || SchemaQueries.isNullable(schema),
      );
    }
    if (_declares(schema)) {
      if (scope.replacing) return _structural.nothingDeclared(schema);
      final (id, inner) = _idOf(schema, scope);
      return _declarer.declareInline(schema, id, inner, hint);
    }
    return _structural.structural(schema, hint, scope);
  }

  /// The JSON side of [schema], which a custom type replaces (R6.8): scalars,
  /// lists and maps; a schema that would be a declaration is `JsonValue`, so
  /// nothing under the replaced schema is declared or reported (R4.2).
  DartType _replaced(Schema schema, NameHint hint, MappingScope scope) =>
      _map(schema, hint, scope.replaced());

  /// Whether [schema] gets a declaration: an enum, a union, an object with
  /// properties or the merge of an `allOf`.
  bool _declares(SchemaObject schema) =>
      SchemaShapes.enumValues(schema) != null ||
      _queries.branches(schema) != null ||
      _subtypeFinder.subtypes(schema).isNotEmpty ||
      schema.properties.isNotEmpty ||
      schema.allOf.isNotEmpty;
}
