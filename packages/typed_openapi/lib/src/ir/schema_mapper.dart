import 'dart:convert';

import '../diagnostics/json_pointer.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';
import '../overrides/override_set.dart';
import 'dart_type.dart';
import 'direction_index.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'names.dart';
import 'ref_follower.dart';
import 'schema_shapes.dart';

/// How an inline schema's declaration is named (R5.4): after its parent
/// declaration or a fixed prefix (an operation), followed by [suffix].
final class NameHint {
  /// A name made of [prefix] and [suffix], such as `CreatePet` + `Request`.
  const NameHint(String this.prefix, this.suffix) : _parent = null;

  const NameHint._under(_Pending this._parent, this.suffix) : prefix = null;

  /// The fixed start of the name, when there is no parent declaration.
  final String? prefix;

  /// The end of the name, such as a property name in UpperCamelCase.
  final String suffix;

  final _Pending? _parent;
}

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
  static const _fallbackName = 'Schema';

  /// The extension that makes a property tri-state with
  /// `tri_state: extension` (R7.2).
  static const triStateExtension = 'x-typed-tri-state';

  final IrContext _context;
  final DirectionIndex _directions;
  final Map<DeclId, _Pending> _pending = {};
  ModelDirection _direction = .both;
  SpecLocation? _patchTarget;
  final Map<String, _Pending> _inlineEnums = {};

  final Map<SpecLocation, List<SchemaObject>> _subtypesOf = {};

  /// The structural aliases being mapped, innermost last, since the last
  /// declaration was entered: meeting one again is a cycle no declaration
  /// breaks.
  final Set<SpecLocation> _aliases = {};

  /// Whether the schema being mapped is replaced by a custom type, so only
  /// the JSON side of it is wanted: nothing is declared, reported or
  /// replaced again (R4.2, R6.8).
  bool _replacing = false;

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
    _direction = direction;
    _patchTarget = patchBody ? _directions.bodyTarget(schema)?.location : null;
    final type = _map(schema, hint);
    _patchTarget = null;
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
    _direction = direction;
    return switch (_context.model.resolveSchema(schema)) {
      final SchemaObject target => _component(target),
      _ => const CoreType(.json),
    };
  }

  /// The id of the declaration of [schema] in the current direction: the
  /// PATCH body model when [schema] is the body being mapped and is used
  /// elsewhere too, the request model of a split schema in a request, the
  /// schema's own declaration otherwise.
  DeclId _idOf(SchemaObject schema) {
    if (schema.location == _patchTarget) {
      _patchTarget = null;
      if (_directions.separatesPatch(schema)) {
        return DeclId(schema.location, variant: .patch);
      }
    }
    return DeclId(
      schema.location,
      variant: _direction == .request && _directions.splits(schema)
          ? .input
          : .base,
    );
  }

  /// Names the declarations created so far in [scope]: overridden names
  /// first, then component keys, then inline names, each by location. A
  /// declaration named already keeps its name.
  void nameDeclarations(NameScope scope) {
    for (final pending in _ordered) {
      _claim(scope, pending);
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
        pending.build(_claim(scope, pending), scope),
    ];
  }

  List<_Pending> get _ordered => _pending.values.toList()
    ..sort((a, b) {
      final byRank = a.rank.compareTo(b.rank);
      if (byRank != 0) return byRank;
      final byDepth = a.depth.compareTo(b.depth);
      if (byDepth != 0) return byDepth;
      return a.id.compareTo(b.id);
    });

  /// Claims [candidate] in the library [scope] for a type the emitters add
  /// to the declaration [owner] ([what] says which); a name that differs
  /// is reported.
  String _helperName(
    NameScope scope,
    String candidate,
    _Pending owner,
    String what,
  ) {
    final (name, change) = scope.claim(candidate);
    if (change != null) {
      _context.report(
        change == .reserved ? .nameReserved : .nameCollision,
        change == .reserved
            ? '"$candidate" is a name Dart already has; $what is named '
                  '"$name".'
            : 'Another type is named "$candidate"; $what is named "$name".',
        owner.id.location,
        // No override: naming the owner would not change a helper's name.
        fix: 'Rename the other type, or rename this one.',
      );
    }
    return name;
  }

  /// Claims the name of [pending] once; an inline declaration's parent is
  /// named first, whatever the order.
  String _claim(NameScope scope, _Pending pending) {
    final named = pending.name;
    if (named != null) return named;
    final overridden = pending.overrideName;
    final suffix = switch (pending.id.variant) {
      .base => '',
      .input => _context.config.inputSuffix,
      .patch => _context.config.patchSuffix,
    };
    final String? candidate;
    if (overridden != null) {
      candidate = '$overridden$suffix';
    } else if (pending.componentKey case final key?) {
      candidate = switch (_names.pascal(key)) {
        final name? => '$name$suffix',
        null => null,
      };
    } else {
      final hint = pending.hint;
      final parent = hint?._parent;
      // The name of a parent model has its variant suffix already.
      candidate = parent != null
          ? '${_claim(scope, parent)}${hint!.suffix}'
          : '${hint?.prefix ?? _fallbackName}${hint?.suffix ?? ''}$suffix';
    }
    if (candidate == null) {
      final (name, _) = scope.claim(_fallbackName);
      _context.report(
        .nameUnrepresentable,
        'Schema "${pending.componentKey}" has no ASCII letter or digit, so '
        'its type is named "$name".',
        pending.id.location,
        fix: 'Rename the schema at the source, or name its type.',
        override: _typeOverride(pending, name),
      );
      return pending.name = name;
    }
    final (name, change) = scope.claim(candidate);
    final override = _typeOverride(pending, name);
    if (change != null) {
      _context.report(
        change == .reserved ? .nameReserved : .nameCollision,
        change == .reserved
            ? '"$candidate" is a name Dart already has; the type is named '
                  '"$name".'
            : 'Another type is named "$candidate"; this one is named '
                  '"$name".',
        pending.id.location,
        fix: override == null
            ? 'Move the schema to components.schemas and name it there, or '
                  'rename what it is named after at the source.'
            : 'Name the type explicitly to keep the name stable.',
        override: override,
      );
    }
    if (pending.componentKey case final key? when overridden == null) {
      _context.checkLossyName(
        key,
        name,
        pending.id.location,
        what: 'Schema',
        override: override,
      );
    }
    return pending.name = name;
  }

  /// The override that names the type of [pending] [name], when the schema
  /// has an address in the overrides file: a component's own type. The
  /// override `name` of a property names its field, an inline type has no
  /// address, and the PATCH and request models take their names from the
  /// schema's.
  String? _typeOverride(_Pending pending, String name) =>
      pending.id.variant == .base && _componentKey(pending.id.location) != null
      ? _context.schemaOverride(pending.id.location, {'name': name})
      : null;

  DartType _map(Schema schema, NameHint hint) {
    if (schema is BooleanSchema) return const CoreType(.json);
    final object = schema as SchemaObject;
    if (object.ref != null) {
      final target = _context.model.resolveSchema(object);
      // A broken `$ref` is reported by the resolver (TOA101).
      if (target is! SchemaObject) return const CoreType(.json);
      final type = _component(target);
      return type.withNullable(type.nullable || _isNullable(object));
    }
    return _inline(object, hint);
  }

  /// The type of a schema a `$ref` points to.
  DartType _component(SchemaObject schema) {
    if (!_replacing) {
      final custom = _customSchemaType(schema);
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
    final id = _idOf(schema);
    // A schema that extends a polymorphic base with `allOf` and adds nothing
    // is a subtype, not a reference to the base (which is the union).
    final single = switch (SchemaShapes.singleOf(schema, refs: _refs)) {
      final part? when schema.allOf.contains(part) && _isBase(part) => null,
      final part => part,
    };
    if (single == null && _declares(schema)) {
      if (_replacing) return _nothingDeclared(schema);
      final key = _referenceName(schema.location);
      final override = _context.overrides.schemaAt(schema.location);
      return _declare(
        schema,
        id,
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
    // A structural schema (array, map, scalar) has no declaration of its
    // own: each use gets its type. One that refers back to itself without
    // a declaration in between cannot be spelled out.
    if (!_replacing) _reportAliasOverride(schema);
    if (!_enterAlias(schema.location)) return const CoreType(.json);
    try {
      final hint = NameHint(
        _names.pascal(_referenceName(schema.location)) ?? _fallbackName,
        '',
      );
      if (single != null) {
        _reportSubsumed(schema, collapsed: true);
        final type = _map(single, hint);
        return type.withNullable(type.nullable || _isNullable(schema));
      }
      return _structural(schema, hint);
    } finally {
      _aliases.remove(schema.location);
    }
  }

  /// Reports the `name` and `exhaustive` of the override of [schema], an
  /// alias that is not a declaration: they would change a type it does not
  /// have (TOA807).
  void _reportAliasOverride(SchemaObject schema) {
    final entry = _context.overrides.schemaAt(schema.location);
    if (entry == null) return;
    for (final (field, written) in [
      ('name', entry.name),
      ('exhaustive', entry.exhaustive),
    ]) {
      if (written == null) continue;
      _context.reportAtOverride(
        .overrideUnchanged,
        'The $field of this override has no effect: the schema is not '
        'generated as a type of its own, its uses are the type of what it '
        'stands for.',
        entry,
        field,
        fix: 'Remove it, or override the schema this one refers to.',
      );
    }
  }

  /// Marks the structural alias at [location] as being mapped; false, with
  /// a report unless a custom type replaces it, when it already is.
  bool _enterAlias(SpecLocation location) {
    if (_aliases.add(location)) return true;
    if (!_replacing) {
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

  DartType _inline(SchemaObject schema, NameHint hint) {
    final single = SchemaShapes.singleOf(schema, refs: _refs);
    if (single != null) {
      _reportSubsumed(schema, collapsed: true);
      final type = _map(single, hint);
      return type.withNullable(type.nullable || _isNullable(schema));
    }
    if (_declares(schema)) {
      if (_replacing) return _nothingDeclared(schema);
      return _declare(schema, _idOf(schema), hint: hint);
    }
    return _structural(schema, hint);
  }

  /// Reports the branches of [schema] that add no value to another branch
  /// (TOA455), unless a custom type replaces [schema]. [collapsed] says the
  /// union is left with one branch, which is then its type.
  void _reportSubsumed(SchemaObject schema, {required bool collapsed}) {
    if (_replacing) return;
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
  DartType _replaced(Schema schema, NameHint hint) {
    final before = _replacing;
    _replacing = true;
    try {
      return _map(schema, hint);
    } finally {
      _replacing = before;
    }
  }

  /// Whether [schema] gets a declaration: an enum, a union, an object with
  /// properties or the merge of an `allOf`.
  bool _declares(SchemaObject schema) =>
      SchemaShapes.enumValues(schema) != null ||
      _branches(schema) != null ||
      _subtypes(schema).isNotEmpty ||
      schema.properties.isNotEmpty ||
      schema.allOf.isNotEmpty;

  /// The kind and the non-null branches of a union: a `oneOf` (or else an
  /// `anyOf`) with more than one branch besides `null` and the branches
  /// that add no value to another ([SchemaShapes.subsumedBranches]).
  (UnionKind, List<Schema>)? _branches(SchemaObject schema) {
    final (kind, branches) = schema.oneOf.isNotEmpty
        ? (UnionKind.oneOf, schema.oneOf)
        : (UnionKind.anyOf, schema.anyOf);
    final dropped = SchemaShapes.subsumedBranches(schema, refs: _refs);
    final nonNull = [
      for (final branch in branches)
        if (!SchemaShapes.isNullOnly(branch) && !dropped.containsKey(branch))
          branch,
    ];
    // Branches that only add constraints (`required`, ...) or only hold one
    // value each (an enum) do not make a union.
    if (nonNull.length < 2 ||
        nonNull.every(_addsOnlyConstraints) ||
        SchemaShapes.enumValues(schema) != null) {
      return null;
    }
    return (kind, nonNull);
  }

  /// Whether [schema] is written inline and only validates: `required`,
  /// `minProperties` and the like, with no `type` (or only `type: object`),
  /// `properties`, items, values, `allOf` or union of its own.
  static bool _addsOnlyConstraints(Schema schema) =>
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

  /// The declaration of [schema] with identity [id]: the one it has already
  /// when it is reached again, else a new one named by [hint] (an inline
  /// schema) or by [componentKey] and [overrideName]. An inline enum equal
  /// to an earlier one is that enum.
  DartType _declare(
    SchemaObject schema,
    DeclId id, {
    NameHint? hint,
    String? componentKey,
    String? overrideName,
  }) {
    final nullable = _isNullable(schema);
    final existing = _pending[id];
    if (existing != null) return NamedType(id, nullable: nullable);
    final values = SchemaShapes.enumValues(schema);
    final kind = values == null ? null : _enumKind(schema, values);
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
    final (names, descriptions) = values == null
        ? (null, null)
        : _enumLabels(schema, values);
    final enumKey = values == null || kind == null || componentKey != null
        ? null
        : jsonEncode([kind.name, values, names, descriptions]);
    if (enumKey != null) {
      final known = _inlineEnums[enumKey];
      if (known != null) return NamedType(known.id, nullable: nullable);
    }
    final pending = _Pending(id)
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
    pending.depth = (hint?._parent?.depth ?? -1) + 1;
    _pending[id] = pending;
    if (enumKey != null) _inlineEnums[enumKey] = pending;
    // A cycle that goes through this declaration ends at it, so what is
    // mapped below starts with no alias open.
    final aliases = {..._aliases};
    _aliases.clear();
    try {
      if (values != null && kind != null) {
        _enum(schema, pending, values, kind, names, descriptions);
      } else if (_branches(schema) case (final kind, final branches)) {
        _union(schema, pending, kind, branches);
      } else if (_subtypes(schema) case final subtypes
          when subtypes.isNotEmpty) {
        _union(schema, pending, .oneOf, subtypes, subtypes: true);
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
        _model(schema, pending);
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
      return switch (_enumKind(object, values)) {
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

  /// Reports the override `union` of [schema], which has no effect on
  /// [what].
  void _reportUnionOverride(SchemaObject schema, String what) {
    final entry = _context.overrides.schemaAt(schema.location);
    if (entry == null || entry.union == null) return;
    _context.reportAtOverride(
      .overrideUnchanged,
      'The union of this override has no effect: $what.',
      entry,
      'union',
      fix: 'Remove it.',
    );
  }

  void _model(SchemaObject schema, _Pending pending) {
    final fields = <_Field>[];
    final (properties, required, additionalSchema) = _merged(schema);
    _reportBranchesBesideModel(schema);
    _reportUnionOverride(schema, 'the schema is a model, not a union');
    if (_context.overrides.schemaAt(schema.location) case final entry?
        when entry.exhaustive != null) {
      _context.reportAtOverride(
        .overrideUnchanged,
        'The exhaustive of this override has no effect: only an enum or a '
            'union can be exhaustive, and this schema is a model.',
        entry,
        'exhaustive',
        fix: 'Remove it.',
      );
    }
    final direction = pending.id.variant != .base
        ? ModelDirection.request
        : _directions.splits(schema)
        ? ModelDirection.response
        : _directions.onlyDirection(schema) ?? ModelDirection.both;
    for (final MapEntry(key: json, value: property) in properties.entries) {
      final override = _context.overrides.propertyAt(property.location);
      if (override?.exclude ?? false) continue;
      if (override?.triState != null &&
          direction == .response &&
          !_directions.splits(schema)) {
        _context.reportAtOverride(
          .overrideUnchanged,
          'The triState of this override has no effect: the model is used in '
              'responses only, and only a request model has tri-state fields.',
          override!,
          'triState',
          fix: 'Remove it.',
        );
      }
      final notes = _notesOf(property);
      final readOnly = notes.readOnly;
      final writeOnly = notes.writeOnly;
      if (direction == .request && readOnly) continue;
      if (direction == .response && writeOnly) continue;
      final suffix = _names.pascal(json) ?? 'Field';
      final custom = override?.dartType;
      final hint = NameHint._under(pending, suffix);
      final constant = custom == null ? _constantOf(property) : null;
      final mapped = constant != null
          ? constant.$2
          : custom == null
          ? _map(property, hint)
          : _replaced(property, hint);
      fields.add(
        _Field(
          json: json,
          override: override,
          location: property.location,
          valueType: custom == null ? mapped : _custom(custom, mapped),
          constValue: constant?.$1,
          constraints: notes.constraints,
          // A union that stays `JsonValue` accepts anything, and no TOA455
          // says a branch was dropped: it lists no values.
          knownValues: mapped is CoreType && mapped.kind == .json
              ? const []
              : notes.knownValues,
          sensitive:
              writeOnly ||
              notes.secret ||
              _rawSecret(property, custom == null ? mapped : null),
          required: required.contains(json),
          readOnly: readOnly,
          writeOnly: writeOnly,
          marked:
              property is SchemaObject &&
              property.extensions[triStateExtension] == true,
          defaultValue: notes.defaultValue,
          description: notes.description,
          deprecated: notes.deprecated,
        ),
      );
    }
    final additional =
        additionalSchema == null || additionalSchema is BooleanSchema
        ? null
        : _map(additionalSchema, NameHint._under(pending, 'Value'));
    pending.build = (name, types) {
      // A field named like a type of the library (its own class, or one a
      // field has) would hide the type inside the class (`other is $2Fa`):
      // only a name that starts with `$` is both.
      final scope = NameScope(
        reserved: {
          ...DartNames.reservedWords,
          ...DartNames.modelMembers,
          ...types.taken,
        },
        reservedSuffix: '_',
      );
      final named = [
        for (final field in fields)
          (
            field,
            _memberName(
              scope,
              field.json,
              field.override,
              field.location,
              owner: name,
            ),
          ),
      ];
      final extraName = additional == null
          ? null
          : _additionalName(scope, name, schema.location);
      return ModelDecl(
        id: pending.id,
        name: name,
        description: schema.description,
        deprecated: schema.deprecated,
        additionalProperties: additional,
        additionalPropertiesName: extraName ?? 'additionalProperties',
        additionalSensitive:
            additionalSchema != null &&
            (SchemaShapes.carriesSecret(additionalSchema, refs: _refs) ||
                _rawSecret(additionalSchema, additional)),
        direction: direction,
        fields: [
          for (final (field, fieldName) in named)
            FieldIr(
              name: fieldName,
              jsonKey: field.json,
              valueType: field.valueType,
              location: field.location,
              required: field.required,
              // A constant is not a parameter, so it is never tri-state,
              // whatever the rule or the override says.
              triState:
                  direction != .response &&
                  field.constValue == null &&
                  (field.override?.triState ?? _isTriState(field, pending)),
              readOnly: field.readOnly,
              writeOnly: field.writeOnly,
              defaultValue: field.defaultValue,
              description: field.description,
              deprecated: field.deprecated,
              constValue: field.constValue,
              constraints: field.constraints,
              knownValues: field.knownValues,
              sensitive: field.sensitive,
            ),
        ],
      );
    };
  }

  /// Whether a value of [type], mapped from [schema], is raw JSON that could
  /// hold a secret: nothing prints the properties of raw JSON, so a secret
  /// anywhere in [schema] (its properties, the parts of its `allOf`, the
  /// branches of a union that stays `JsonValue`) makes the value print as
  /// `<redacted>`.
  bool _rawSecret(Schema schema, DartType? type) =>
      type != null &&
      type.holdsRawJson &&
      SchemaShapes.carriesSecret(schema, refs: _refs, intoProperties: true);

  /// The name of the field that holds a model's `additionalProperties`,
  /// claimed in the model's field [scope] after the properties, so a
  /// property keeps its name; a name that differs is reported.
  String _additionalName(NameScope scope, String owner, SpecLocation at) {
    const candidate = 'additionalProperties';
    final (name, change) = scope.claim(candidate);
    if (change != null) {
      _context.report(
        .nameCollision,
        'A property of $owner is named "$candidate"; the field that holds '
        'its additionalProperties is named "$name".',
        at,
        fix: 'Name the property explicitly to keep the names stable.',
      );
    }
    return name;
  }

  /// The one value of a property that can hold no other, with the type of
  /// the value: a `const` or a one-value enum written inline, not nullable,
  /// of one JSON type (decision 8 of M8). Its field is a constant.
  (Object, DartType)? _constantOf(Schema property) {
    if (property is! SchemaObject || property.ref != null || _replacing) {
      return null;
    }
    if (_isNullable(property)) return null;
    final values = SchemaShapes.enumValues(property);
    if (values == null || values.length != 1) return null;
    final value = values.single!;
    return switch (_enumKind(property, values)) {
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
  _FieldNotes _notesOf(Schema property) {
    if (property is! SchemaObject) return const _FieldNotes();
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
    return _FieldNotes(
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
  bool _isTriState(_Field field, _Pending pending) =>
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
  (Map<String, Schema>, Set<String>, Schema?) _merged(SchemaObject schema) {
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
    return (properties, required, additional);
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
    _Pending pending,
    UnionKind kind,
    List<Schema> branches, {
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
    final others = [
      for (final name in schema.properties.keys)
        if (name != schema.discriminator?.propertyName) name,
    ];
    if (!subtypes && others.isNotEmpty) {
      _context.report(
        .compositionPartsIgnored,
        'The properties of this schema are ignored: it is generated as the '
        'union of its ${kind.name} branches.',
        schema.location.child('properties'),
        fix: 'Put the shared properties into every branch at the source.',
      );
    }
    if (!subtypes) _reportSubsumed(schema, collapsed: false);
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
    final variants = <_Variant>[];
    var droppedDuplicate = false;
    _Variant? shared;
    void share(JsonKind kind, Schema branch, [int? at]) {
      if (shared == null) {
        shared = _Variant(const CoreType(.json), null, branch);
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
          ? _component(branch as SchemaObject)
          : _map(branch, NameHint._under(pending, 'Variant${i + 1}'));
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
        _Variant(
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
      _reportUnionOverride(
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
        if (values.containsKey(target)) continue;
        if (_componentKey(target) case final key?) values[target] = [key];
      }
      final owners = <String, _Variant>{};
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
              name: _helperName(
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
        unknownName: _helperName(
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
          final target? => _referenceName(target.location),
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
              _componentKey(node.location) != null))
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
      NamedType(:final id) => _pending[id]?.name ?? _fallbackName,
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

  /// The Dart name of the member [json] of the type [owner], from the name
  /// [override] gives or from [json].
  String _memberName(
    NameScope scope,
    String json,
    PropertyOverride? override,
    SpecLocation location, {
    required String owner,
  }) {
    final named = override == null
        ? null
        : _context.checkedOverrideName(
            override,
            'name',
            override.name,
            .member,
            what: 'field',
          );
    final candidate = named ?? _names.camel(json);
    if (candidate == null) {
      final (name, _) = scope.claim('field');
      _context.report(
        .nameUnrepresentable,
        'Property "$json" of $owner has no ASCII letter or digit, so its '
        'field is named "$name".',
        location,
        fix: 'Name the field explicitly.',
        override: _context.schemaOverride(location, {'name': name}),
      );
      return name;
    }
    final (name, change) = scope.claim(candidate);
    if (change != null) {
      _context.report(
        change == .reserved ? .nameReserved : .nameCollision,
        change == .reserved
            ? 'Property "$json" of $owner would be the Dart name '
                  '"$candidate"; its field is named "$name".'
            : 'Another field of $owner is named "$candidate"; the field of '
                  '"$json" is named "$name".',
        location,
        fix: 'Name the field explicitly to keep the name stable.',
        override: _context.schemaOverride(location, {'name': name}),
      );
    }
    if (named == null) {
      _context.checkLossyName(
        json,
        name,
        location,
        what: 'Property',
        override: _context.schemaOverride(location, {'name': name}),
      );
    }
    return name;
  }

  /// The `x-enum-varnames` and `x-enum-descriptions` of the enum [schema]
  /// with [values]: a list of strings with one entry per value, or null when
  /// the extension is missing or malformed (TOA351); a description may be
  /// `null`, which is no description. An enum that has `null` among its
  /// written values may list it too.
  (List<String>?, List<String?>?) _enumLabels(
    SchemaObject schema,
    List<Object?> values,
  ) {
    // A description may be `null`: that value has none.
    List<String?>? labels(String key, {bool allowNull = false}) {
      final written = schema.extensions[key];
      if (written == null) return null;
      final all = schema.enumValues;
      if (written is List<Object?> &&
          written.every((e) => e is String || (allowNull && e == null))) {
        final strings = written.cast<String?>();
        if (strings.length == values.length) return strings;
        if (all != null && strings.length == all.length) {
          return [
            for (final (i, value) in all.indexed)
              if (value != null) strings[i],
          ];
        }
      }
      _context.report(
        .enumVarnamesInvalid,
        '$key must be a list of strings with one entry per enum value '
        '(${values.length}); it is ignored.',
        schema.location.child(key),
        fix: 'Write one string for each value of the enum at the source.',
      );
      return null;
    }

    return (
      labels('x-enum-varnames')?.cast<String>(),
      labels('x-enum-descriptions', allowNull: true),
    );
  }

  void _enum(
    SchemaObject schema,
    _Pending pending,
    List<Object?> values,
    EnumKind kind,
    List<String>? names,
    List<String?>? descriptions,
  ) {
    final exhaustive =
        _context.overrides.schemaAt(schema.location)?.exhaustive ?? true;
    _reportUnionOverride(schema, 'the schema is an enum, not a union');
    pending.build = (name, types) {
      final scope = NameScope(
        reserved: {...DartNames.reservedWords, ...DartNames.enumMembers},
        reservedSuffix: '_',
      );
      return EnumDecl(
        id: pending.id,
        name: name,
        kind: kind,
        exhaustive: exhaustive,
        knownName: _helperName(
          types,
          '${name}Known',
          pending,
          'the enum of the known values of $name',
        ),
        unknownName: _helperName(
          types,
          '${name}Unknown',
          pending,
          'the class of an unknown value of $name',
        ),
        description: schema.description,
        deprecated: schema.deprecated,
        values: [
          for (final (i, value) in values.indexed)
            EnumValueIr(
              _valueName(scope, names?[i], value!, schema.location, name),
              value,
              description: descriptions?[i],
            ),
        ],
      );
    };
  }

  static final _numberText = RegExp(r'^-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$');

  /// The name of the enum value [value] of [owner]: from its
  /// `x-enum-varnames` entry [named], else from the value. A number, or a
  /// string that is one, is `value` and its digits (`valueMinus1`,
  /// `value0_5`, `value1eMinus7`).
  String _valueName(
    NameScope scope,
    String? named,
    Object value,
    SpecLocation location,
    String owner,
  ) {
    final fromName = named == null ? null : _names.camel(named);
    final text = '$value';
    final String? candidate;
    if (fromName != null) {
      candidate = fromName;
    } else if (value is num ||
        (value is String && _numberText.hasMatch(text))) {
      candidate = _numberName(text);
    } else {
      candidate = _names.camel(text);
    }
    final (name, change) = scope.claim(candidate ?? 'value');
    // A fallback name for an enum value is a naming decision, not a lost
    // type, so it is an info: an enum of a spec that is not yours can only
    // be named at the source.
    if (candidate == null) {
      _context.report(
        .nameUnrepresentable,
        'Value "$value" of enum $owner has no ASCII letter or digit, so it '
        'is named "$name". Add x-enum-varnames to the enum in the spec to '
        'name its values.',
        location,
        severity: .info,
        fix: 'Name the values with x-enum-varnames at the source.',
      );
    } else if (change != null) {
      _context.report(
        change == .reserved ? .nameReserved : .nameCollision,
        'Value "$value" of enum $owner is named "$name".',
        location,
        fix: 'Name the values with x-enum-varnames at the source.',
      );
    }
    if (named != null && fromName == null) {
      _context.report(
        .nameUnrepresentable,
        'The x-enum-varnames entry "$named" of enum $owner has no ASCII '
        'letter or digit, so the value "$value" is named "$name".',
        location,
        severity: .info,
        fix: 'Write a name with a letter or digit in x-enum-varnames.',
      );
    }
    if (candidate != null && value is! num) {
      _context.checkLossyName(
        fromName == null ? text : named!,
        name,
        location,
        what: 'Value',
        fix: 'Name it with x-enum-varnames at the source.',
      );
    }
    return name;
  }

  /// The identifier for the number written as [text]: `value`, `Minus` for
  /// a sign, `_` for the point, the exponent without a plus.
  static String _numberName(String text) {
    final negative = text.startsWith('-');
    final digits = (negative ? text.substring(1) : text)
        .replaceAll('.', '_')
        .replaceAllMapped(
          RegExp('([eE])([+-]?)'),
          (m) => '${m[1]}${m[2] == '-' ? 'Minus' : ''}',
        );
    return 'value${negative ? 'Minus' : ''}$digits';
  }

  static EnumKind? _enumKind(SchemaObject schema, List<Object?> values) {
    if (values.every((v) => v is String)) return .string;
    if (values.every((v) => v is bool)) return .boolean;
    if (values.every((v) => v is int)) {
      return schema.types.contains(SchemaType.number) ? .number : .integer;
    }
    if (values.every((v) => v is num)) return .number;
    return null;
  }

  /// The type of a schema without a declaration: a scalar, a list or a
  /// map.
  DartType _structural(SchemaObject schema, NameHint hint) {
    final nullable = _isNullable(schema);
    final types = [
      for (final type in schema.types)
        if (type != SchemaType.nullType) type,
    ];
    if (types.length > 1) {
      // A custom type replaces the schema, so it has nothing to report.
      if (!_replacing) {
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
          final items? => _map(items, _suffixed(hint, 'Item')),
          null => const CoreType(.json),
        },
      ),
      .object => MapType(
        switch (schema.additionalProperties) {
          final BooleanSchema _ || null => const CoreType(.json),
          final values => _map(values, _suffixed(hint, 'Value')),
        },
      ),
    };
    final format = schema.format;
    final custom = format == null ? null : _context.config.formats[format];
    final mapped = custom == null ? base : _custom(custom, base);
    return mapped.withNullable(nullable);
  }

  static NameHint _suffixed(NameHint hint, String suffix) =>
      switch (hint._parent) {
        final parent? => NameHint._under(parent, '${hint.suffix}$suffix'),
        null => NameHint(hint.prefix!, '${hint.suffix}$suffix'),
      };

  /// The custom type every use of [schema] gets (R6.8): an override's
  /// `dartType` or `types.schemas` of the config.
  DartType? _customSchemaType(SchemaObject schema) {
    final override = _context.overrides.schemaAt(schema.location)?.dartType;
    final key = _componentKey(schema.location);
    final custom =
        override ?? (key == null ? null : _context.config.schemas[key]);
    if (custom == null) return null;
    // The schema is an alias open while its JSON side is built, so a cycle
    // through it ends there.
    _aliases.add(schema.location);
    try {
      final json = _replaced(
        schema,
        NameHint(_names.pascal(key ?? '') ?? _fallbackName, ''),
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

  /// How the schema questions follow a `$ref`. Lazy because a field
  /// initializer cannot read `_context`.
  late final RefFollower _refs = RefFollower.of(_context.model);

  SchemaObject? _resolved(Schema schema) =>
      switch (_context.model.resolveSchema(schema)) {
        final SchemaObject object => object,
        _ => null,
      };

  /// The name of a schema a `$ref` points to: its `components.schemas` key,
  /// else the last token of its pointer (`#/definitions/Pet`), else its file
  /// name without the extension (`pet.yaml`). A branch of a union is named
  /// after the union (`PetVariant2` for `.../Pet/oneOf/1`).
  static String _referenceName(SpecLocation location) {
    final named = _tokensName(location.pointer.tokens);
    if (named != null) return named;
    final file = location.document.pathSegments.lastOrNull ?? '';
    final dot = file.lastIndexOf('.');
    return dot > 0 ? file.substring(0, dot) : file;
  }

  static String? _tokensName(List<String> tokens) {
    if (tokens.length == 3 && tokens[0] == 'components') {
      if (tokens[1] == 'schemas') return tokens[2];
    }
    if (tokens.isEmpty) return null;
    final index = int.tryParse(tokens.last);
    if (index == null || tokens.length < 2) return tokens.last;
    final owner = _tokensName(tokens.sublist(0, tokens.length - 2));
    if (owner == null) return null;
    final part = switch (tokens[tokens.length - 2]) {
      'oneOf' || 'anyOf' => 'Variant',
      'allOf' => 'Part',
      _ => 'Item',
    };
    return '$owner$part${index + 1}';
  }

  /// The key of the schema at [location] in `components.schemas` of its
  /// document, if it is one.
  static String? _componentKey(SpecLocation location) {
    final tokens = location.pointer.tokens;
    if (tokens.length == 3 &&
        tokens[0] == 'components' &&
        tokens[1] == 'schemas') {
      return tokens[2];
    }
    return null;
  }

  /// Whether [schema] allows `null`: 3.0 `nullable`, `null` in `type`,
  /// `null` among the `enum` values or a null branch, or an `allOf` part
  /// that only says so (`allOf: [{$ref: Pet}, {nullable: true}]`).
  static bool _isNullable(SchemaObject schema) =>
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
}

/// A variant of a union being built: its type, the schema a `$ref` branch
/// (or a subtype) is, the branch, and, for the variant of any JSON value,
/// the JSON types it takes.
final class _Variant {
  _Variant(this.type, this.target, this.branch);

  final DartType type;
  final SpecLocation? target;
  final Schema branch;
  final List<JsonKind> kinds = [];

  /// The other branches that make up a variant of any JSON value, besides
  /// [branch].
  final List<Schema> also = [];
}

/// A declaration whose name is not given yet.
final class _Pending {
  _Pending(this.id);

  final DeclId id;
  String? componentKey;
  String? overrideName;
  NameHint? hint;
  int depth = 0;
  bool patchBody = false;
  String? name;
  late Declaration Function(String name, NameScope scope) build;

  /// The JSON type of every value of the declaration: an object for a
  /// model and a union with a discriminator, the type of an enum's values;
  /// null for a union that may hold values of several types.
  JsonKind? jsonKind;

  /// Overridden names are claimed first, then component keys, then inline
  /// names.
  int get rank => overrideName != null
      ? 0
      : componentKey != null
      ? 1
      : 2;
}

/// What a property's schema says about its field (`SchemaMapper._notesOf`).
final class _FieldNotes {
  const _FieldNotes({
    this.knownValues = const [],
    this.constraints = const ConstraintsIr(),
    this.description,
    this.defaultValue,
    this.deprecated = false,
    this.readOnly = false,
    this.writeOnly = false,
    this.secret = false,
  });

  final List<Object?> knownValues;
  final ConstraintsIr constraints;
  final String? description;
  final (Object?,)? defaultValue;
  final bool deprecated;
  final bool readOnly;
  final bool writeOnly;
  final bool secret;
}

/// A property of a model, before field names are given.
final class _Field {
  _Field({
    required this.json,
    required this.override,
    required this.location,
    required this.valueType,
    required this.required,
    required this.readOnly,
    required this.writeOnly,
    required this.marked,
    required this.defaultValue,
    required this.description,
    required this.deprecated,
    required this.constValue,
    required this.constraints,
    required this.knownValues,
    required this.sensitive,
  });

  final String json;
  final PropertyOverride? override;
  final SpecLocation location;
  final DartType valueType;
  final bool required;
  final bool readOnly;
  final bool writeOnly;

  /// Whether the property has `x-typed-tri-state: true`.
  final bool marked;
  final (Object?,)? defaultValue;
  final String? description;
  final bool deprecated;
  final Object? constValue;
  final ConstraintsIr constraints;
  final List<Object?> knownValues;
  final bool sensitive;
}
