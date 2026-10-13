import 'dart:convert';

import '../diagnostics/json_pointer.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';
import '../overrides/override_set.dart';
import 'dart_type.dart';
import 'declaration_names.dart';
import 'direction_index.dart';
import 'enum_mapper.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'mapping_scope.dart';
import 'mapping_state.dart';
import 'names.dart';
import 'override_notices.dart';
import 'pending_declaration.dart';
import 'ref_follower.dart';
import 'schema_queries.dart';
import 'schema_shapes.dart';

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
  static const triStateExtension = 'x-typed-tri-state';

  final IrContext _context;
  final DirectionIndex _directions;

  // The collaborators are lazy because a field initializer cannot read the
  // other fields.
  late final SchemaQueries _queries = SchemaQueries(_context);
  late final DeclarationNames _declNames = DeclarationNames(_context);
  late final OverrideNotices _notices = OverrideNotices(_context);
  late final EnumMapper _enums = EnumMapper(_context, _declNames, _notices);

  // The four fields below are shared mutable state: every call during one
  // mapping reads and writes the same collections, so they cannot be passed
  // down as a scope.

  /// Every declaration created so far, by identity: reaching one again gives
  /// it back.
  final Map<DeclId, PendingDeclaration> _pending = {};

  /// The inline enums created so far, by their values, so an equal one is
  /// the same declaration.
  final Map<String, PendingDeclaration> _inlineEnums = {};

  /// The subtypes found of each polymorphic base, by its location.
  final Map<SpecLocation, List<SchemaObject>> _subtypesOf = {};

  /// The structural aliases being mapped, innermost last, since the last
  /// declaration was entered: meeting one again is a cycle no declaration
  /// breaks.
  final Set<SpecLocation> _aliases = {};

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
  /// first, then component keys, then inline names, each by location. A
  /// declaration named already keeps its name.
  void nameDeclarations(NameScope scope) {
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

  List<PendingDeclaration> get _ordered =>
      DeclarationNames.inClaimOrder(_pending.values);

  DartType _map(Schema schema, NameHint hint, MappingScope scope) {
    if (schema is BooleanSchema) return const CoreType(.json);
    final object = schema as SchemaObject;
    if (object.ref != null) {
      final target = _context.model.resolveSchema(object);
      // A broken `$ref` is reported by the resolver (TOA101).
      if (target is! SchemaObject) return const CoreType(.json);
      final type = _component(target, scope);
      return type.withNullable(type.nullable || _isNullable(object));
    }
    return _inline(object, hint, scope);
  }

  /// The type of a schema a `$ref` points to.
  DartType _component(SchemaObject schema, MappingScope scope) {
    if (!scope.replacing) {
      final custom = _customSchemaType(schema, scope);
      final excluded =
          _context.overrides.schemaAt(schema.location)?.exclude ?? false;
      if (custom != null) {
        if (excluded) {
          _context.report(
            .excludedSchemaReferenced,
            'This schema is excluded by an override, but it also has a custom '
            'Dart type; the type is used and the exclude has no effect.',
            schema.location,
            fix: 'Remove the exclude, or the custom type.',
          );
        }
        return custom;
      }
      if (excluded) {
        _context.report(
          .excludedSchemaReferenced,
          'This schema is excluded by an override, but a generated type uses '
          'it; the use is generated as JsonValue.',
          schema.location,
          fix:
              'Exclude what uses the schema too, or give the schema a Dart '
              'type instead of excluding it.',
        );
        return const CoreType(.json);
      }
    }
    final (id, inner) = _idOf(schema, scope);
    // A schema that extends a polymorphic base with `allOf` and adds nothing
    // is a subtype, not a reference to the base (which is the union).
    final single = switch (SchemaShapes.singleOf(schema, refs: _refs)) {
      final part? when schema.allOf.contains(part) && _isBase(part) => null,
      final part => part,
    };
    if (single == null && _declares(schema)) {
      if (inner.replacing) return _nothingDeclared(schema);
      return _declareNamed(schema, id, inner);
    }
    // A structural schema (array, map, scalar) has no declaration of its
    // own: each use gets its type. One that refers back to itself without
    // a declaration in between cannot be spelled out.
    if (!inner.replacing) _notices.aliasHasNoEffect(schema);
    if (!_enterAlias(schema.location, inner)) return const CoreType(.json);
    try {
      final hint = NameHint(
        _names.pascal(DeclarationNames.referenceName(schema.location)) ??
            DeclarationNames.fallbackName,
        '',
      );
      if (single != null) {
        _reportSubsumed(schema, inner, collapsed: true);
        final type = _map(single, hint, inner);
        return type.withNullable(type.nullable || _isNullable(schema));
      }
      return _structural(schema, hint, inner);
    } finally {
      _aliases.remove(schema.location);
    }
  }

  /// The declaration of the component [schema], named by its key or override.
  DartType _declareNamed(SchemaObject schema, DeclId id, MappingScope scope) {
    final key = DeclarationNames.referenceName(schema.location);
    final override = _context.overrides.schemaAt(schema.location);
    return _declare(
      schema,
      id,
      scope,
      componentKey: key,
      overrideName: override == null
          ? null
          : _context.checkedOverrideName(
              override,
              'name',
              override.name,
              .type,
              what: 'type',
            ),
    );
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

  DartType _inline(SchemaObject schema, NameHint hint, MappingScope scope) {
    final single = SchemaShapes.singleOf(schema, refs: _refs);
    if (single != null) {
      _reportSubsumed(schema, scope, collapsed: true);
      final type = _map(single, hint, scope);
      return type.withNullable(type.nullable || _isNullable(schema));
    }
    if (_declares(schema)) {
      if (scope.replacing) return _nothingDeclared(schema);
      final (id, inner) = _idOf(schema, scope);
      return _declare(schema, id, inner, hint: hint);
    }
    return _structural(schema, hint, scope);
  }

  /// Reports the branches of [schema] that add no value to another branch
  /// (TOA455), unless a custom type replaces [schema]. [collapsed] says the
  /// union is left with one branch, which is then its type.
  void _reportSubsumed(
    SchemaObject schema,
    MappingScope scope, {
    required bool collapsed,
  }) {
    if (scope.replacing) return;
    for (final MapEntry(key: branch, value: kind)
        in SchemaShapes.subsumedBranches(schema, refs: _refs).entries) {
      final values = SchemaShapes.enumValues(branch)!;
      final shown = [
        for (final value in values.take(3)) _valueText(value),
        if (values.length > 3) '...',
      ].join(', ');
      _context.report(
        .unionBranchSubsumed,
        'The enum [$shown] branch adds no value to the ${kind.name} branch; '
        '${collapsed ? 'the schema is generated as the ${kind.name} branch '
                  'alone.' : 'it is dropped from the union.'}',
        branch.location,
        fix:
            'Remove the enum branch at the source, or leave it for the '
            'documentation.',
      );
    }
  }

  /// [value] of an enum as it is written in a Dart list, for a message.
  static String _valueText(Object? value) =>
      value is String ? "'${value.replaceAll("'", r"\'")}'" : '$value';

  /// The type of a declaring [schema] inside a replaced schema: nothing is
  /// declared, so the type is that of its JSON value (a map for an object,
  /// a scalar for an enum), which the custom type's `fromJson` takes;
  /// `JsonValue` when the schema may hold values of several JSON types.
  DartType _nothingDeclared(SchemaObject schema) =>
      switch (_jsonKind(schema, {})) {
        .object => const MapType(CoreType(.json)),
        .string => const CoreType(.string),
        .integer => const CoreType(.integer),
        .number => const CoreType(.number),
        .boolean => const CoreType(.boolean),
        _ => const CoreType(.json),
      }.withNullable(_isNullable(schema));

  /// The JSON side of [schema], which a custom type replaces (R6.8): scalars,
  /// lists and maps; a schema that would be a declaration is `JsonValue`, so
  /// nothing under the replaced schema is declared or reported (R4.2).
  DartType _replaced(Schema schema, NameHint hint, MappingScope scope) =>
      _map(schema, hint, scope.replaced());

  /// Whether [schema] gets a declaration: an enum, a union, an object with
  /// properties or the merge of an `allOf`.
  bool _declares(SchemaObject schema) =>
      SchemaShapes.enumValues(schema) != null ||
      _branches(schema) != null ||
      _subtypes(schema).isNotEmpty ||
      schema.properties.isNotEmpty ||
      schema.allOf.isNotEmpty;

  /// The declaration of [schema] with identity [id]: the one it has already
  /// when it is reached again, else a new one named by [hint] (an inline
  /// schema) or by [componentKey] and [overrideName]. An inline enum equal
  /// to an earlier one is that enum.
  DartType _declare(
    SchemaObject schema,
    DeclId id,
    MappingScope scope, {
    NameHint? hint,
    String? componentKey,
    String? overrideName,
  }) {
    final nullable = _isNullable(schema);
    if (_pending.containsKey(id)) return NamedType(id, nullable: nullable);
    final values = SchemaShapes.enumValues(schema);
    final kind = values == null ? null : EnumMapper.kindOf(schema, values);
    if (values != null && kind == null) {
      _context.report(
        .enumMixedValues,
        'The values of this enum are not all strings, all numbers or all '
        'booleans; it is generated as JsonValue.',
        schema.location,
        fix: 'Give the enum values of one JSON type at the source.',
      );
      return const CoreType(.json);
    }
    if (values == null) {
      if (_branches(schema) case (
        _,
        final branches,
      ) when _isRawUnion(schema, branches)) {
        return const CoreType(.json);
      }
    }
    final (List<String>?, List<String?>?) labels = values == null
        ? (null, null)
        : _enums.labels(schema, values);
    final enumKey = values == null || kind == null || componentKey != null
        ? null
        : jsonEncode([kind.name, values, labels.$1, labels.$2]);
    if (enumKey != null) {
      final known = _inlineEnums[enumKey];
      if (known != null) return NamedType(known.id, nullable: nullable);
    }
    final pending = PendingDeclaration(id)
      ..hint = hint
      ..componentKey = componentKey
      ..overrideName = overrideName
      ..jsonKind = switch (kind) {
        .string => .string,
        .integer => .integer,
        .number => .number,
        .boolean => .boolean,
        null =>
          _branches(schema) == null ||
                  schema.discriminator?.propertyName != null
              ? .object
              : null,
      };
    pending.depth = (hint?.parent?.depth ?? -1) + 1;
    _pending[id] = pending;
    if (enumKey != null) _inlineEnums[enumKey] = pending;
    // A cycle that goes through this declaration ends at it, so what is
    // mapped below starts with no alias open.
    final aliases = {..._aliases};
    _aliases.clear();
    try {
      if (values != null && kind != null) {
        _enums.declare(schema, pending, values, kind, labels);
      } else if (_branches(schema) case (final kind, final branches)) {
        _union(schema, pending, kind, branches, scope);
      } else if (_subtypes(schema) case final subtypes
          when subtypes.isNotEmpty) {
        _union(schema, pending, .oneOf, subtypes, scope, subtypes: true);
      } else {
        if (schema.discriminator case final discriminator?
            when discriminator.propertyName != null) {
          _context.report(
            .discriminatorWithoutSubtypes,
            'This discriminator is on a schema that is not a oneOf or anyOf '
            'union and that no schema extends with allOf, so it picks '
            'nothing; the schema is generated as a model.',
            discriminator.location,
            fix:
                'Extend the schema with allOf in its subtypes, or list them '
                'in a oneOf.',
          );
        }
        _model(schema, pending, scope);
      }
    } finally {
      _aliases
        ..clear()
        ..addAll(aliases);
    }
    return NamedType(id, nullable: nullable);
  }

  /// Whether the union [schema] of [branches] is generated as `JsonValue`
  /// (R9.2): it has no discriminator, no variant has a JSON type of its own
  /// ([_conflicts]), and its override `union` (or else the config's) is
  /// `raw`. Reported, with the override that changes it (TOA453).
  bool _isRawUnion(SchemaObject schema, List<Schema> branches) {
    if (schema.discriminator?.propertyName != null) return false;
    if (_unionMode(schema) == .structural) return false;
    final (conflicts, distinct) = _conflicts(branches);
    if (conflicts.length < distinct) return false;
    final kind = schema.oneOf.isNotEmpty ? 'oneOf' : 'anyOf';
    // A variant without one JSON type conflicts with every other variant.
    final reason = conflicts.values.contains(null)
        ? 'a variant that can hold values of several JSON types (a union '
              'without a discriminator, or a schema without a type)'
        : 'variants that share a JSON type';
    _context.report(
      .unionUndiscriminated,
      'This $kind has no discriminator and $reason, so a value cannot be '
      'told apart by its type; it is generated as JsonValue.',
      schema.location,
      fix:
          'Add a discriminator at the source, or generate a union that tries '
          'the variants with union: structural (an override of the schema, '
          'or the config key for every such union).',
      override: _context.schemaOverride(schema.location, {
        'union': 'structural',
      }),
    );
    return true;
  }

  /// The `union` of [schema]: its override, else the override of the
  /// property it is written in, else the config's.
  UnionMode _unionMode(SchemaObject schema) {
    final overrides = _context.overrides;
    return overrides.schemaAt(schema.location)?.union ??
        overrides.propertyAt(schema.location)?.union ??
        _context.config.union;
  }

  /// The branches of a union without a discriminator that the JSON type of
  /// a value cannot tell apart, by index, with their JSON type (null for a
  /// branch of any JSON value, which every other branch conflicts with),
  /// and how many distinct branches there are. A branch that is the same
  /// schema as an earlier one is a duplicate (TOA454): neither a conflict
  /// nor counted. `integer` and `number` are told apart by the value.
  (Map<int, JsonKind?>, int) _conflicts(List<Schema> branches) {
    final kinds = <int, JsonKind?>{};
    final seen = <SpecLocation>{};
    for (final (i, branch) in branches.indexed) {
      final location = _resolved(branch)?.location;
      if (location != null && !seen.add(location)) continue;
      kinds[i] = _jsonKind(branch, {});
    }
    if (kinds.values.contains(null)) return (kinds, kinds.length);
    final counts = <JsonKind, int>{};
    for (final kind in kinds.values) {
      counts[kind!] = (counts[kind] ?? 0) + 1;
    }
    return (
      {
        for (final MapEntry(:key, :value) in kinds.entries)
          if (counts[value]! > 1) key: value,
      },
      kinds.length,
    );
  }

  /// The JSON type of every value of [type], or null when it takes values
  /// of several types.
  JsonKind? _typeKind(DartType type) => switch (type) {
    CoreType(:final kind) => switch (kind) {
      .string || .dateTime || .date || .bytes || .binary => .string,
      .integer => .integer,
      .float || .number => .number,
      .boolean => .boolean,
      .json => null,
    },
    ListType() => .array,
    MapType() => .object,
    CustomType(:final json) => _typeKind(json),
    PatchType(:final value) => _typeKind(value),
    NamedType(:final id) => _pending[id]?.jsonKind,
  };

  /// The JSON type every value of [schema] has, or null when it may have
  /// several (or any); [seen] stops a cycle.
  JsonKind? _jsonKind(Schema schema, Set<SpecLocation> seen) {
    final object = _resolved(schema);
    if (object == null || !seen.add(object.location)) return null;
    if (SchemaShapes.enumValues(object) case final values?) {
      return switch (EnumMapper.kindOf(object, values)) {
        .string => .string,
        .integer => .integer,
        .number => .number,
        .boolean => .boolean,
        null => null,
      };
    }
    // A union is an object when a discriminator picks its variant; any
    // other union may hold values of several types.
    if (_branches(object) != null) {
      return object.discriminator?.propertyName != null ? .object : null;
    }
    if (SchemaShapes.singleOf(object, refs: _refs) case final single?) {
      return _jsonKind(single, seen);
    }
    if (object.properties.isNotEmpty || object.allOf.isNotEmpty) {
      return .object;
    }
    final types = [
      for (final type in object.types)
        if (type != SchemaType.nullType) type,
    ];
    if (types.length > 1) return null;
    return switch (types.firstOrNull) {
      .string => .string,
      .integer => .integer,
      .number => .number,
      .boolean => .boolean,
      .array => .array,
      .object => .object,
      null || SchemaType.nullType =>
        object.items != null
            ? .array
            : object.additionalProperties != null
            ? .object
            : null,
    };
  }

  /// Maps the fields of the model [schema], and sets how [pending] is built
  /// once it is named.
  void _model(
    SchemaObject schema,
    PendingDeclaration pending,
    MappingScope scope,
  ) {
    final parts = _merged(schema);
    _reportIneffectiveOverrides(schema);
    final site = ModelSite(
      schema,
      pending,
      _modelDirection(schema, pending),
      scope,
    );
    final fields = _fields(site, parts);
    final additionalSchema = parts.additional;
    final draft = ModelDraft(
      site: site,
      fields: fields,
      additionalSchema: additionalSchema,
      additional: additionalSchema == null || additionalSchema is BooleanSchema
          ? null
          : _map(additionalSchema, NameHint.under(pending, 'Value'), scope),
    );
    pending.build = (name, types) => _buildModel(draft, name, types);
  }

  /// Reports what the schema of a model says that is ignored: branches
  /// beside the model, and the overrides that only a union or an enum has.
  void _reportIneffectiveOverrides(SchemaObject schema) {
    _reportBranchesBesideModel(schema);
    _notices.unionHasNoEffect(schema, 'the schema is a model, not a union');
    _notices.exhaustiveOnModel(schema);
  }

  /// Where the model of [schema] is used, which leaves out the `readOnly` or
  /// `writeOnly` properties.
  ModelDirection _modelDirection(
    SchemaObject schema,
    PendingDeclaration pending,
  ) => pending.id.variant != .base
      ? .request
      : _directions.splits(schema)
      ? .response
      : _directions.onlyDirection(schema) ?? .both;

  /// The fields of the model at [site], one for each property of [parts]
  /// that the direction and the overrides do not leave out.
  List<FieldDraft> _fields(ModelSite site, ModelParts parts) => [
    for (final MapEntry(key: json, value: property) in parts.properties.entries)
      ?_field(site, json, property, isRequired: parts.required.contains(json)),
  ];

  /// The field of [property], or null when the model leaves it out.
  FieldDraft? _field(
    ModelSite site,
    String json,
    Schema property, {
    required bool isRequired,
  }) {
    final override = _context.overrides.propertyAt(property.location);
    if (override?.exclude ?? false) return null;
    _reportTriStateOverride(site, override);
    final notes = _notesOf(property);
    if (site.direction == .request && notes.readOnly) return null;
    if (site.direction == .response && notes.writeOnly) return null;
    final custom = override?.dartType;
    final hint = NameHint.under(site.pending, _names.pascal(json) ?? 'Field');
    final (mapped, constant) = _fieldType(property, custom, hint, site.scope);
    return FieldDraft(
      json: json,
      override: override,
      location: property.location,
      valueType: custom == null ? mapped : _custom(custom, mapped),
      constValue: constant?.$1,
      notes: notes,
      // A union that stays `JsonValue` accepts anything, and no TOA455
      // says a branch was dropped: it lists no values.
      knownValues: mapped is CoreType && mapped.kind == .json
          ? const []
          : notes.knownValues,
      sensitive:
          notes.writeOnly ||
          notes.secret ||
          _rawSecret(property, custom == null ? mapped : null),
      required: isRequired,
      marked:
          property is SchemaObject &&
          property.extensions[triStateExtension] == true,
    );
  }

  /// Reports the `triState` of the override of a property of a model used
  /// in responses only.
  void _reportTriStateOverride(ModelSite site, PropertyOverride? override) {
    if (override != null &&
        override.triState != null &&
        site.direction == .response &&
        !_directions.splits(site.schema)) {
      _notices.triStateOnResponseModel(override);
    }
  }

  /// The type of a property in [scope] (the JSON side of it when a custom
  /// type [custom] replaces it), and its constant, if it has one.
  (DartType, (Object, DartType)?) _fieldType(
    Schema property,
    DartTypeOverride? custom,
    NameHint hint,
    MappingScope scope,
  ) {
    final constant = custom == null ? _constantOf(property, scope) : null;
    final mapped = constant != null
        ? constant.$2
        : custom == null
        ? _map(property, hint, scope)
        : _replaced(property, hint, scope);
    return (mapped, constant);
  }

  /// The declaration of the model [draft], with the fields and the
  /// `additionalProperties` field named in [types].
  ModelDecl _buildModel(ModelDraft draft, String name, NameScope types) {
    final site = draft.site;
    final scope = _memberScope(types);
    final named = [
      for (final field in draft.fields)
        (
          field,
          _declNames.memberName(
            scope,
            field.json,
            field.override,
            field.location,
            owner: name,
          ),
        ),
    ];
    final extraName = draft.additional == null
        ? null
        : _declNames.additionalName(scope, name, site.schema.location);
    return ModelDecl(
      id: site.pending.id,
      name: name,
      description: site.schema.description,
      deprecated: site.schema.deprecated,
      additionalProperties: draft.additional,
      additionalPropertiesName: extraName ?? 'additionalProperties',
      additionalSensitive: _additionalIsSecret(draft),
      direction: site.direction,
      fields: [
        for (final (field, fieldName) in named)
          _fieldIr(field, fieldName, site),
      ],
    );
  }

  /// The names of the members of a model, where the types of the library
  /// [types] are reserved: a field named like one would hide the type inside
  /// the class (`other is $2Fa`), and only a name that starts with `$` is
  /// both.
  NameScope _memberScope(NameScope types) => NameScope(
    reserved: {
      ...DartNames.reservedWords,
      ...DartNames.modelMembers,
      ...types.taken,
    },
    reservedSuffix: '_',
  );

  /// Whether the values of `additionalProperties` are secrets.
  bool _additionalIsSecret(ModelDraft draft) {
    final schema = draft.additionalSchema;
    return schema != null &&
        (SchemaShapes.carriesSecret(schema, refs: _refs) ||
            _rawSecret(schema, draft.additional));
  }

  /// The field [name] of [field] in the model at [site].
  FieldIr _fieldIr(FieldDraft field, String name, ModelSite site) {
    final notes = field.notes;
    return FieldIr(
      name: name,
      jsonKey: field.json,
      valueType: field.valueType,
      location: field.location,
      required: field.required,
      // A constant is not a parameter, so it is never tri-state, whatever
      // the rule or the override says.
      triState:
          site.direction != .response &&
          field.constValue == null &&
          (field.override?.triState ?? _isTriState(field, site.pending)),
      readOnly: notes.readOnly,
      writeOnly: notes.writeOnly,
      defaultValue: notes.defaultValue,
      description: notes.description,
      deprecated: notes.deprecated,
      constValue: field.constValue,
      constraints: notes.constraints,
      knownValues: field.knownValues,
      sensitive: field.sensitive,
    );
  }

  /// The one value of a property that can hold no other, with the type of
  /// the value: a `const` or a one-value enum written inline, not nullable,
  /// of one JSON type (decision 8 of M8). Its field is a constant.
  (Object, DartType)? _constantOf(Schema property, MappingScope scope) {
    if (property is! SchemaObject || property.ref != null || scope.replacing) {
      return null;
    }
    if (_isNullable(property)) return null;
    final values = SchemaShapes.enumValues(property);
    if (values == null || values.length != 1) return null;
    final value = values.single!;
    return switch (EnumMapper.kindOf(property, values)) {
      .string => (value, const CoreType(.string)),
      .integer => (value, const CoreType(.integer)),
      .number => (value, const CoreType(.number)),
      .boolean => (value, const CoreType(.boolean)),
      null => null,
    };
  }

  /// What the schema of a property says about its field.
  ///
  /// The sources are the property's own keywords, the annotation-only
  /// `allOf` parts next to the one part it stands for
  /// (`allOf: [{$ref: Pet}, {description: ...}]`), and the schema it refers
  /// to, in this order: the first `description` and `default` win, and the
  /// field is deprecated, `readOnly` or `writeOnly` when any source says so.
  /// In OpenAPI 3.0 a `$ref` has no siblings, so only the target gives the
  /// description, default and deprecation; 3.1 and 3.2 take the property's
  /// own keywords before the target's (a written `deprecated: false` cannot
  /// be told from a missing one, so it does not override a deprecated
  /// target).
  FieldNotes _notesOf(Schema property) {
    if (property is! SchemaObject) return const FieldNotes();
    final parts = property.ref == null
        ? SchemaShapes.annotationParts(property)
        : const <SchemaObject>[];
    final target = switch (property.ref) {
      null => switch (SchemaShapes.singleOf(property)) {
        final single? when property.allOf.contains(single) => _resolved(
          single,
        ),
        _ => null,
      },
      _ => _resolved(property),
    };
    final siblings =
        property.ref == null || _context.model.document.version != .v30;
    final written = [if (siblings) property, ...parts, ?target];
    final sources = SchemaShapes.annotationSources(
      property,
      refs: _refs,
    );
    final known = <Object?>[];
    for (final schema in sources) {
      for (final branch in SchemaShapes.subsumedBranches(
        schema,
        refs: _refs,
      ).keys) {
        for (final value in SchemaShapes.enumValues(branch) ?? const []) {
          if (!known.contains(value)) known.add(value);
        }
      }
    }
    return FieldNotes(
      knownValues: known,
      constraints: _constraintsOf(written),
      description: written
          .map((s) => s.description)
          .firstWhere((d) => d != null, orElse: () => null),
      defaultValue: written
          .map((s) => s.defaultValue)
          .firstWhere((d) => d != null, orElse: () => null),
      deprecated: written.any((s) => s.deprecated),
      readOnly: sources.any((s) => s.readOnly),
      writeOnly: sources.any((s) => s.writeOnly),
      secret: SchemaShapes.carriesSecret(property, refs: _refs),
    );
  }

  /// The constraints of a field from the schemas [written] for it, the first
  /// that sets each one winning (R6.7). A 3.0 boolean `exclusiveMinimum`
  /// makes `minimum` exclusive, and the same for the maximum.
  static ConstraintsIr _constraintsOf(List<SchemaObject> written) {
    T? first<T extends Object>(T? Function(SchemaObject s) read) {
      for (final schema in written) {
        if (read(schema) case final value?) return value;
      }
      return null;
    }

    final minimum = first((s) => s.minimum);
    final maximum = first((s) => s.maximum);
    final minExclusive = first((s) => s.exclusiveMinimumFlag) ?? false;
    final maxExclusive = first((s) => s.exclusiveMaximumFlag) ?? false;
    return ConstraintsIr(
      minLength: first((s) => s.minLength),
      maxLength: first((s) => s.maxLength),
      pattern: first((s) => s.pattern),
      minimum: minExclusive ? null : minimum,
      maximum: maxExclusive ? null : maximum,
      exclusiveMinimum:
          first((s) => s.exclusiveMinimum) ?? (minExclusive ? minimum : null),
      exclusiveMaximum:
          first((s) => s.exclusiveMaximum) ?? (maxExclusive ? maximum : null),
      multipleOf: first((s) => s.multipleOf),
      minItems: first((s) => s.minItems),
      maxItems: first((s) => s.maxItems),
      uniqueItems: written.any((s) => s.uniqueItems),
      minProperties: first((s) => s.minProperties),
      maxProperties: first((s) => s.maxProperties),
    );
  }

  /// Whether [field] tells "absent" from `null` by the config's rule (R7.2).
  /// A field of any JSON value (`JsonValue`) allows `null` too.
  bool _isTriState(FieldDraft field, PendingDeclaration pending) =>
      switch (_context.config.triState) {
        .patch =>
          pending.patchBody &&
              !field.required &&
              (field.valueType.nullable ||
                  field.valueType == const CoreType(.json)),
        .optional => pending.patchBody && !field.required,
        .extension => field.marked,
      };

  /// The properties, required names and `additionalProperties` of [schema]
  /// with its `allOf` parts merged in, parts first and in order (R6.3). A
  /// property, or `additionalProperties`, that a later part defines again
  /// with another schema is reported; the later one is used. A part an
  /// override excludes is merged all the same, because the model is flat and
  /// the exclude only removes the part's own declaration (TOA254 says so).
  /// A discriminator on a part does not matter here: the part's subtypes
  /// are picked where the part is used as a type.
  ModelParts _merged(SchemaObject schema) {
    final properties = <String, Schema>{};
    final required = <String>{};
    final seen = <SpecLocation>{};
    Schema? additional;
    void add(SchemaObject part) {
      if (!seen.add(part.location)) return;
      for (final written in part.allOf) {
        // A part that only annotates adds no property: its `nullable` and
        // its description belong to the schema that has the `allOf`.
        if (SchemaShapes.isAnnotationOnly(written)) continue;
        final resolved = _resolved(written);
        if (resolved == null) continue;
        if (_context.overrides.schemaAt(resolved.location)?.exclude ?? false) {
          _context.report(
            .excludedSchemaReferenced,
            'This allOf part is excluded by an override, which only leaves '
            'out its own declaration; its properties are merged into this '
            'model, which does not refer to the part.',
            written.location,
            fix:
                'Exclude the properties that should not be here, or remove '
                'the exclude of the schema.',
          );
        }
        if (resolved.properties.isEmpty &&
            resolved.allOf.isEmpty &&
            (SchemaShapes.enumValues(resolved) != null ||
                _branches(resolved) != null ||
                resolved.types.any((t) => t != .object && t != .nullType))) {
          _context.report(
            .allOfPartIgnored,
            'This allOf part is not an object, so it cannot be merged into a '
            'model; it is ignored.',
            written.location,
            fix: 'Make every allOf part an object schema at the source.',
          );
          continue;
        }
        add(resolved);
        _reportBranchesBesideModel(resolved);
      }
      for (final MapEntry(key: name, value: property)
          in part.properties.entries) {
        final earlier = properties[name];
        if (earlier != null && !_same(earlier, property)) {
          _context.report(
            .allOfPropertyConflict,
            'Property "$name" is defined again by another allOf part; this '
            'definition is used.',
            property.location,
            fix: 'Define each property in one allOf part at the source.',
          );
        }
        properties[name] = property;
      }
      if (part.additionalProperties case final later?) {
        final earlier = additional;
        if (earlier != null && !_same(earlier, later)) {
          _context.report(
            .allOfPropertyConflict,
            'additionalProperties is defined again by another allOf part; '
            'this definition is used.',
            later.location,
            fix:
                'Define additionalProperties in one allOf part at the '
                'source.',
          );
        }
        additional = later;
      }
      required.addAll(part.required);
    }

    add(schema);
    return ModelParts(properties, required, additional);
  }

  /// Reports the `oneOf` and `anyOf` of [schema], which is generated as a
  /// model: branches that only add constraints are TOA255, others TOA256.
  void _reportBranchesBesideModel(SchemaObject schema) {
    for (final (key, branches) in [
      ('oneOf', schema.oneOf),
      ('anyOf', schema.anyOf),
    ]) {
      final real = [
        for (final branch in branches)
          if (!SchemaShapes.isNullOnly(branch)) branch,
      ];
      if (real.isEmpty) continue;
      if (real.every(_addsOnlyConstraints)) {
        _context.report(
          .oneOfConstraintsIgnored,
          'The $key of this schema only adds constraints to its properties; '
          'it is generated as a model and the branches are ignored.',
          schema.location.child(key),
          fix: 'Nothing to do; the constraints are not checked by the client.',
        );
      } else {
        _context.report(
          .compositionPartsIgnored,
          'The $key branches of this schema are ignored: it is generated as '
          'a model of its properties and allOf parts.',
          schema.location.child(key),
          fix:
              'Move the properties into the branches, or make the schema a '
              'plain union at the source.',
        );
      }
    }
  }

  /// Whether two property schemas are the same: one schema through
  /// `$ref`s, or equal as written.
  bool _same(Schema a, Schema b) {
    final x = _context.model.resolveSchema(a)?.location;
    final y = _context.model.resolveSchema(b)?.location;
    if (x == y) return true;
    if (x == null || y == null) return false;
    final raw = _context.documents[x.document]?.valueAt(x.pointer);
    final other = _context.documents[y.document]?.valueAt(y.pointer);
    return raw != null &&
        other != null &&
        jsonEncode(raw.$1) == jsonEncode(other.$1);
  }

  /// The union [schema] of [branches]: a `oneOf`/`anyOf`, or, with
  /// [subtypes], a base with a discriminator whose branches are the schemas
  /// that extend it with `allOf` (their flat models).
  void _union(
    SchemaObject schema,
    PendingDeclaration pending,
    UnionKind kind,
    List<Schema> branches,
    MappingScope scope, {
    bool subtypes = false,
  }) {
    if (!subtypes && schema.allOf.isNotEmpty) {
      _context.report(
        .compositionPartsIgnored,
        'The allOf parts of this schema are ignored: it is generated as the '
        'union of its ${kind.name} branches.',
        schema.location.child('allOf'),
        fix: 'Put the shared parts into every branch at the source.',
      );
    }
    // The discriminator property is what the union reads from every branch;
    // the properties of a base are in the models of its subtypes.
    final hasOthers = schema.properties.keys.any(
      (name) => name != schema.discriminator?.propertyName,
    );
    if (!subtypes && hasOthers) {
      _context.report(
        .compositionPartsIgnored,
        'The properties of this schema are ignored: it is generated as the '
        'union of its ${kind.name} branches.',
        schema.location.child('properties'),
        fix: 'Put the shared properties into every branch at the source.',
      );
    }
    if (!subtypes) _reportSubsumed(schema, scope, collapsed: false);
    final discriminator = schema.discriminator;
    final property = discriminator?.propertyName;
    final (allConflicts, _) = property != null
        ? (const <int, JsonKind?>{}, 0)
        : _conflicts(branches);
    final UnionDispatch dispatch;
    if (property != null) {
      dispatch = .discriminator;
    } else if (allConflicts.isEmpty) {
      dispatch = .jsonType;
    } else if (_unionMode(schema) == .structural) {
      dispatch = .structural;
    } else {
      dispatch = .jsonType;
    }
    // Branches of a JSON type others share are one variant of any JSON
    // value, unless the union tries them all.
    final Map<int, JsonKind?> conflicts = dispatch == .jsonType
        ? allConflicts
        : const {};
    final variants = <VariantDraft>[];
    var droppedDuplicate = false;
    VariantDraft? shared;
    void share(JsonKind kind, Schema branch, [int? at]) {
      if (shared == null) {
        shared = VariantDraft(const CoreType(.json), null, branch);
        variants.insert(at ?? variants.length, shared!);
      }
      if (!shared!.also.contains(branch)) shared!.also.add(branch);
      if (!shared!.kinds.contains(kind)) shared!.kinds.add(kind);
    }

    // A branch that is the same schema as a conflicting one is a duplicate
    // of it, not a variant of its own.
    final conflicting = {
      for (final i in conflicts.keys) ?_resolved(branches[i])?.location,
    };
    for (final (i, branch) in branches.indexed) {
      if (conflicts.containsKey(i)) {
        share(conflicts[i]!, branch);
        continue;
      }
      if (conflicting.contains(_resolved(branch)?.location)) {
        _context.report(
          .unionVariantDuplicate,
          'This variant is the same schema as an earlier variant of the '
          '${kind.name}; it is dropped, since a value could not be told '
          'apart between them.',
          branch.location,
          fix: 'Remove the duplicate variant at the source.',
        );
        droppedDuplicate = true;
        continue;
      }
      final type = subtypes
          ? _component(branch as SchemaObject, scope)
          : _map(branch, NameHint.under(pending, 'Variant${i + 1}'), scope);
      if (variants.any((v) => v.kinds.isEmpty && v.type == type)) {
        _context.report(
          .unionVariantDuplicate,
          'This variant has the same Dart type as an earlier variant of the '
          '${kind.name}; it is dropped, since a value could not be told '
          'apart between them.',
          branch.location,
          fix: 'Remove the duplicate variant at the source.',
        );
        droppedDuplicate = true;
        continue;
      }
      variants.add(
        VariantDraft(
          type,
          subtypes || (branch is SchemaObject && branch.ref != null)
              ? _resolved(branch)?.location
              : null,
          branch,
        ),
      );
    }
    if (dispatch == .jsonType) {
      // A variant that came out as a type of any JSON value (a schema
      // excluded or replaced, a recursive alias) is picked by its JSON type
      // no more: its values join the variant of any JSON value.
      for (final variant in [...variants]) {
        if (variant.kinds.isNotEmpty || _typeKind(variant.type) != null) {
          continue;
        }
        final at = variants.indexOf(variant);
        variants.remove(variant);
        if (_jsonKind(variant.branch, {}) case final kind?) {
          share(kind, variant.branch, at);
        }
      }
    }
    if (conflicts.isNotEmpty) {
      final names = [
        for (final (i, branch) in branches.indexed)
          if (conflicts.containsKey(i)) _branchName(branch, i),
      ];
      final shareds =
          (shared!.kinds.toList()..sort((a, b) => a.index - b.index))
              .map((k) => k.name)
              .join(', ');
      _context.report(
        .unionUndiscriminated,
        'Variants ${names.join(', ')} of this ${kind.name} share the JSON '
        'type $shareds, so a value of it cannot be told apart; such a value '
        'is kept as JsonValue in one variant.',
        schema.location,
        fix:
            'Add a discriminator at the source, or generate a union that '
            'tries the variants with union: structural (an override of the '
            'schema, or the config key for every such union).',
        override: _context.schemaOverride(schema.location, {
          'union': 'structural',
        }),
      );
    }
    if (dispatch == .discriminator || allConflicts.isEmpty) {
      _notices.unionHasNoEffect(
        schema,
        dispatch == .discriminator
            ? 'the union has a discriminator'
            : droppedDuplicate && variants.length < 2
            ? 'the duplicate variants were dropped (TOA454), and one variant '
                  'is left'
            : 'the variants of the union have JSON types of their own',
      );
    }
    final values = <SpecLocation, List<String>>{};
    DartType? fallback;
    if (discriminator != null && property != null) {
      final targets = {for (final v in variants) ?v.target};
      for (final MapEntry(key: value, value: ref)
          in discriminator.mapping.entries) {
        final target = _mappingTarget(ref, schema.location.document);
        if (target == null) continue;
        if (subtypes && target == schema.location) {
          _context.report(
            .discriminatorMappingNotVariant,
            'Discriminator value "$value" maps to the base schema itself, '
            'which is generated as the union of its subtypes; a value with '
            'it is decoded as unknown, with its JSON kept.',
            discriminator.location.child('mapping').child(value),
            fix: 'Map the value to a schema that extends the base.',
          );
          continue;
        }
        if (!targets.contains(target)) {
          _context.report(
            .discriminatorMappingNotVariant,
            'Discriminator value "$value" maps to a schema that is not a '
            'variant of this union; it is ignored.',
            discriminator.location.child('mapping').child(value),
            fix: "Map the value to one of the union's variants.",
          );
          continue;
        }
        (values[target] ??= []).add(value);
      }
      for (final variant in variants) {
        final target = variant.target;
        if (target == null) {
          // The value an inline variant's own discriminator property holds
          // selects it: the schema allows no other.
          if (_constantProperty(variant.branch, property, {})
              case final String v) {
            values[variant.branch.location] = [v];
            continue;
          }
          _context.report(
            .discriminatorValueMissing,
            'This variant is written inline, so no discriminator value '
            'selects it.',
            variant.branch.location,
            fix: r'Make the variant a component schema and $ref it.',
          );
          continue;
        }
        final key = DeclarationNames.componentKey(target);
        if (key != null && !values.containsKey(target)) values[target] = [key];
      }
      final owners = <String, VariantDraft>{};
      for (final variant in variants) {
        final key = variant.target ?? variant.branch.location;
        for (final value in values[key] ?? const <String>[]) {
          if (owners.putIfAbsent(value, () => variant) == variant) continue;
          _context.report(
            .discriminatorValueDuplicate,
            'Discriminator value "$value" also selects an earlier variant; '
            'the earlier one decodes it, so this variant is never picked by '
            'that value.',
            variant.branch.location,
            fix:
                'Give each variant its own discriminator value, in the '
                'mapping or in the const of the property.',
          );
        }
      }
      if (discriminator.defaultMapping case final ref?) {
        final target = _mappingTarget(ref, schema.location.document);
        for (final variant in variants) {
          if (variant.target != null && variant.target == target) {
            fallback = variant.type;
          }
        }
        if (fallback == null) {
          _context.report(
            .discriminatorMappingNotVariant,
            'The default mapping "$ref" is not a variant of this union; it '
            'is ignored.',
            discriminator.location.child('defaultMapping'),
            fix: "Map the default to one of the union's variants.",
          );
        }
      }
    }
    final exhaustive =
        _context.overrides.schemaAt(schema.location)?.exhaustive ?? true;
    pending.build = (name, types) {
      final classes = _variantClasses(name, [
        for (final variant in variants) variant.type,
      ]);
      return UnionDecl(
        id: pending.id,
        name: name,
        kind: kind,
        dispatch: dispatch,
        discriminator: property,
        defaultVariant: fallback,
        exhaustive: exhaustive,
        unknownSensitive: branches.any(
          (branch) => SchemaShapes.carriesSecret(
            branch,
            refs: _refs,
            intoProperties: true,
          ),
        ),
        description: schema.description,
        deprecated: schema.deprecated,
        variants: [
          for (final (i, variant) in variants.indexed)
            UnionVariantIr(
              variant.type,
              discriminatorValues: [
                ...?values[variant.target ?? variant.branch.location],
              ]..sort(),
              name: _declNames.helperName(
                types,
                classes[i],
                pending,
                'a variant class of $name',
              ),
              jsonKinds: [...variant.kinds]..sort((a, b) => a.index - b.index),
              sensitive:
                  SchemaShapes.carriesSecret(variant.branch, refs: _refs) ||
                  variant.type.holdsRawJson &&
                      [variant.branch, ...variant.also].any(
                        (branch) => _rawSecret(branch, variant.type),
                      ),
            ),
        ],
        unknownName: _declNames.helperName(
          types,
          '${name}Unknown',
          pending,
          'the unknown variant class of $name',
        ),
      );
    };
  }

  /// How a diagnostic names the branch [index] of a union: the schema it
  /// refers to, or its position.
  String _branchName(Schema branch, int index) =>
      branch is SchemaObject && branch.ref != null
      ? switch (_resolved(branch)) {
          final target? => DeclarationNames.referenceName(target.location),
          null => '#$index',
        }
      : '#$index';

  /// Whether [schema] is a polymorphic base: a schema with a discriminator
  /// that other schemas extend ([_subtypes]).
  bool _isBase(Schema schema) => switch (_resolved(schema)) {
    final base? => _subtypes(base).isNotEmpty,
    null => false,
  };

  /// The schemas that extend [base] with `allOf`, directly or through
  /// another subtype, in the order of `components.schemas` and then of the
  /// other files the spec reads, when [base]
  /// has a discriminator and is not a union or an enum: a polymorphic base
  /// (user decision for M8). A subtype an override excludes is left out.
  List<SchemaObject> _subtypes(SchemaObject base) {
    if (base.discriminator?.propertyName == null ||
        _branches(base) != null ||
        SchemaShapes.enumValues(base) != null) {
      return const [];
    }
    return _subtypesOf[base.location] ??= _findSubtypes(base);
  }

  /// The schemas of the other files the spec reads that a `$ref` can name:
  /// the root of a file and the entries of its `components.schemas`, in the
  /// order of their locations. A file nothing refers to is not read, so a
  /// subtype that only it has is not found.
  late final List<SchemaObject> _foreignSchemas = [
    for (final node in _context.model.nodes)
      if (node is SchemaObject &&
          node.ref == null &&
          node.location.document != _context.model.document.location.document &&
          (node.location.pointer.tokens.isEmpty ||
              DeclarationNames.componentKey(node.location) != null))
        node,
  ];

  List<SchemaObject> _findSubtypes(SchemaObject base) {
    final components = [
      for (final schema
          in _context.model.document.components?.schemas.values ??
              const <Schema>[])
        if (schema is SchemaObject && schema.ref == null) schema,
      ..._foreignSchemas,
    ];
    final found = {base.location};
    var grew = true;
    while (grew) {
      grew = false;
      for (final schema in components) {
        if (found.contains(schema.location)) continue;
        if (schema.allOf.any(
          (part) => found.contains(_resolved(part)?.location),
        )) {
          found.add(schema.location);
          grew = true;
        }
      }
    }
    return [
      for (final schema in components)
        if (schema.location != base.location &&
            found.contains(schema.location) &&
            !(_context.overrides.schemaAt(schema.location)?.exclude ?? false))
          schema,
    ];
  }

  /// The classes that wrap the variants of [types] in the union [union], in
  /// order: [_variantClass] names, except that variants whose short names
  /// are the same (a list of strings and a list of integers) are named by
  /// their whole type (`PetListString`, `PetListInt`).
  List<String> _variantClasses(String union, List<DartType> types) {
    final short = [for (final type in types) _variantClass(union, type)];
    return [
      for (final (i, type) in types.indexed)
        if (short.where((name) => name == short[i]).length > 1)
          _variantClass(union, type, deep: true)
        else
          short[i],
    ];
  }

  /// The class that wraps a variant of [type] in the union [union]: the
  /// union's name and the variant's (`PetCat`), or the variant's name and
  /// `Case` when it starts with the union's already (`PetVariant1Case` for
  /// an inline variant, `PetCatCase` for a variant named `PetCat`). A
  /// built-in type is named by its kind (`IdOrNameString`, `IdOrNameInt`);
  /// with [deep], a list or a map also by its element (`IdOrNameListInt`).
  String _variantClass(String union, DartType type, {bool deep = false}) {
    String label(DartType type) => switch (type) {
      NamedType(:final id) =>
        _pending[id]?.name ?? DeclarationNames.fallbackName,
      CustomType(:final type) => type,
      ListType(:final item) => deep ? 'List${label(item)}' : 'List',
      MapType(:final value) => deep ? 'Map${label(value)}' : 'Map',
      PatchType() => 'Patch',
      CoreType(:final kind) => switch (kind) {
        .integer => 'Int',
        .float => 'Double',
        .number => 'Num',
        .string => 'String',
        .boolean => 'Bool',
        .dateTime => 'DateTime',
        .date => 'Date',
        .bytes || .binary => 'Bytes',
        .json => 'Json',
      },
    };
    final name = label(type);
    return name.startsWith(union) ? '${name}Case' : '$union$name';
  }

  /// The one value the property [name] of [schema] can hold, when it is a
  /// `const` or a one-value enum, in the schema or one of its `allOf` parts;
  /// [seen] stops a cycle.
  Object? _constantProperty(
    Schema schema,
    String name,
    Set<SpecLocation> seen,
  ) {
    final object = _resolved(schema);
    if (object == null || !seen.add(object.location)) return null;
    if (object.properties[name] case final property?) {
      final resolved = _resolved(property);
      final values = resolved == null
          ? null
          : SchemaShapes.enumValues(resolved);
      return values != null && values.length == 1 ? values.single : null;
    }
    for (final part in object.allOf) {
      if (_constantProperty(part, name, seen) case final value?) return value;
    }
    return null;
  }

  /// The schema a discriminator `mapping` value names: a
  /// `components.schemas` key or a `$ref` in the document of the union.
  SpecLocation? _mappingTarget(String ref, Uri document) {
    final model = _context.model;
    final Schema? written;
    if (ref.startsWith('#/')) {
      final node = model.nodeAt(SpecLocation(document, JsonPointer.parse(ref)));
      written = node is Schema ? node : null;
    } else if (!ref.contains('#') && !ref.contains('/')) {
      written = model.document.components?.schemas[ref];
    } else {
      written = null;
    }
    return written == null ? null : model.resolveSchema(written)?.location;
  }

  /// The type of a schema without a declaration: a scalar, a list or a
  /// map.
  DartType _structural(SchemaObject schema, NameHint hint, MappingScope scope) {
    final nullable = _isNullable(schema);
    final types = [
      for (final type in schema.types)
        if (type != SchemaType.nullType) type,
    ];
    if (types.length > 1) {
      // A custom type replaces the schema, so it has nothing to report.
      if (!scope.replacing) {
        _context.report(
          .mixedTypeSchema,
          'This schema allows ${types.map((t) => t.wire).join(', ')}; it is '
          'generated as JsonValue.',
          schema.location,
          fix:
              'Give the schema one type at the source, or a Dart type with an '
              'override.',
          override: _context.schemaOverride(schema.location, {
            'dartType': {
              'type': 'MyType',
              'import': 'package:app/my_type.dart',
            },
          }),
        );
      }
      return const CoreType(.json);
    }
    final type =
        types.firstOrNull ??
        (schema.items != null
            ? SchemaType.array
            : schema.additionalProperties != null
            ? SchemaType.object
            : null);
    final DartType base = switch (type) {
      null || SchemaType.nullType => const CoreType(.json),
      .integer => const CoreType(.integer),
      .number => switch (schema.format) {
        'float' || 'double' => const CoreType(.float),
        _ => switch (_context.config.numberType) {
          'double' => const CoreType(.float),
          'int' => const CoreType(.integer),
          _ => const CoreType(.number),
        },
      },
      .boolean => const CoreType(.boolean),
      .string => switch (schema.format) {
        'date-time' => const CoreType(.dateTime),
        'date' => const CoreType(.date),
        'byte' => const CoreType(.bytes),
        'binary' => const CoreType(.binary),
        _ => const CoreType(.string),
      },
      .array => ListType(
        switch (schema.items) {
          final items? => _map(items, _suffixed(hint, 'Item'), scope),
          null => const CoreType(.json),
        },
      ),
      .object => MapType(
        switch (schema.additionalProperties) {
          final BooleanSchema _ || null => const CoreType(.json),
          final values => _map(values, _suffixed(hint, 'Value'), scope),
        },
      ),
    };
    final format = schema.format;
    final custom = format == null ? null : _context.config.formats[format];
    final mapped = custom == null ? base : _custom(custom, base);
    return mapped.withNullable(nullable);
  }

  static NameHint _suffixed(NameHint hint, String suffix) =>
      switch (hint.parent) {
        final parent? => NameHint.under(parent, '${hint.suffix}$suffix'),
        null => NameHint(hint.prefix!, '${hint.suffix}$suffix'),
      };

  /// The custom type every use of [schema] gets (R6.8): an override's
  /// `dartType` or `types.schemas` of the config.
  DartType? _customSchemaType(SchemaObject schema, MappingScope scope) {
    final override = _context.overrides.schemaAt(schema.location)?.dartType;
    final key = DeclarationNames.componentKey(schema.location);
    final custom =
        override ?? (key == null ? null : _context.config.schemas[key]);
    if (custom == null) return null;
    // The schema is an alias open while its JSON side is built, so a cycle
    // through it ends there.
    _aliases.add(schema.location);
    try {
      final json = _replaced(
        schema,
        NameHint(_names.pascal(key ?? '') ?? DeclarationNames.fallbackName, ''),
        scope,
      );
      return _custom(custom, json).withNullable(_isNullable(schema));
    } finally {
      _aliases.remove(schema.location);
    }
  }

  static CustomType _custom(DartTypeOverride custom, DartType json) =>
      CustomType(
        type: custom.type,
        import: custom.import,
        converter: custom.converter,
        json: json.withNullable(false),
        nullable: json.nullable,
      );

  // Forwards to [SchemaQueries], until the code that asks moves out too.
  RefFollower get _refs => _queries.refs;

  SchemaObject? _resolved(Schema schema) => _queries.resolved(schema);

  static bool _isNullable(SchemaObject schema) =>
      SchemaQueries.isNullable(schema);

  (UnionKind, List<Schema>)? _branches(SchemaObject schema) =>
      _queries.branches(schema);

  static bool _addsOnlyConstraints(Schema schema) =>
      SchemaQueries.addsOnlyConstraints(schema);

  bool _rawSecret(Schema schema, DartType? type) =>
      _queries.holdsRawSecret(schema, type);
}
