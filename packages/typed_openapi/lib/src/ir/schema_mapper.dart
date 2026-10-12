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
    : _directions = directions ?? DirectionIndex(_context.model);

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
    _patchTarget = patchBody
        ? _context.model.resolveSchema(schema)?.location
        : null;
    final type = _map(schema, hint);
    _patchTarget = null;
    if (patchBody && type is NamedType) _pending[type.id]?.patchBody = true;
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

  /// The declarations created so far, named in [scope]: overridden names
  /// first, then component keys, then inline names, each by location.
  List<Declaration> declarations(NameScope scope) {
    final ordered = _pending.values.toList()
      ..sort((a, b) {
        final byRank = a.rank.compareTo(b.rank);
        if (byRank != 0) return byRank;
        final byDepth = a.depth.compareTo(b.depth);
        if (byDepth != 0) return byDepth;
        return a.id.compareTo(b.id);
      });
    for (final pending in ordered) {
      _claim(scope, pending);
    }
    return [
      for (final pending in ordered) pending.build(_claim(scope, pending)),
    ];
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
      final start = parent != null
          ? _claim(scope, parent)
          : hint?.prefix ?? _fallbackName;
      candidate = '$start${hint?.suffix ?? ''}$suffix';
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
      if (custom != null) return custom;
      if (_context.overrides.schemaAt(schema.location)?.exclude ?? false) {
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
    final single = _single(schema);
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
    if (!_enterAlias(schema.location)) return const CoreType(.json);
    try {
      final hint = NameHint(
        _names.pascal(_referenceName(schema.location)) ?? _fallbackName,
        '',
      );
      if (single != null) {
        final type = _map(single, hint);
        return type.withNullable(type.nullable || _isNullable(schema));
      }
      return _structural(schema, hint);
    } finally {
      _aliases.remove(schema.location);
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
    final single = _single(schema);
    if (single != null) {
      final type = _map(single, hint);
      return type.withNullable(type.nullable || _isNullable(schema));
    }
    if (_declares(schema)) {
      if (_replacing) return _nothingDeclared(schema);
      return _declare(schema, _idOf(schema), hint: hint);
    }
    return _structural(schema, hint);
  }

  /// The type of a declaring [schema] inside a replaced schema: `JsonValue`.
  DartType _nothingDeclared(SchemaObject schema) =>
      const CoreType(.json).withNullable(_isNullable(schema));

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
      _enumValues(schema) != null ||
      _branches(schema) != null ||
      schema.properties.isNotEmpty ||
      schema.allOf.isNotEmpty;

  /// The one schema [schema] stands for (R6.3, rules carried from M3): the
  /// part of an `allOf` with one part, or the branch of a `oneOf`/`anyOf`
  /// with one branch besides `null`; null when there is none.
  Schema? _single(SchemaObject schema) {
    if (schema.properties.isNotEmpty || _enumValues(schema) != null) {
      return null;
    }
    final branches = [...schema.oneOf, ...schema.anyOf];
    if (schema.allOf.length == 1 && branches.isEmpty) return schema.allOf.first;
    if (schema.allOf.isNotEmpty) return null;
    final nonNull = [
      for (final branch in branches)
        if (!_isNullOnly(branch)) branch,
    ];
    return nonNull.length == 1 && (schema.oneOf.isEmpty || schema.anyOf.isEmpty)
        ? nonNull.single
        : null;
  }

  /// The kind and the non-null branches of a union: a `oneOf` (or else an
  /// `anyOf`) with more than one branch besides `null`.
  (UnionKind, List<Schema>)? _branches(SchemaObject schema) {
    final (kind, branches) = schema.oneOf.isNotEmpty
        ? (UnionKind.oneOf, schema.oneOf)
        : (UnionKind.anyOf, schema.anyOf);
    final nonNull = [
      for (final branch in branches)
        if (!_isNullOnly(branch)) branch,
    ];
    return nonNull.length > 1 ? (kind, nonNull) : null;
  }

  static bool _isNullOnly(Schema schema) =>
      schema is SchemaObject &&
      schema.ref == null &&
      ((schema.types.length == 1 && schema.types.single == .nullType) ||
          (schema.enumValues != null &&
              schema.enumValues!.every((v) => v == null)));

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
    final values = _enumValues(schema);
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
      ..overrideName = overrideName;
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
      } else {
        _model(schema, pending);
      }
    } finally {
      _aliases
        ..clear()
        ..addAll(aliases);
    }
    return NamedType(id, nullable: nullable);
  }

  void _model(SchemaObject schema, _Pending pending) {
    final fields = <_Field>[];
    final (properties, required) = _merged(schema);
    final direction = pending.id.variant != .base
        ? ModelDirection.request
        : _directions.splits(schema)
        ? ModelDirection.response
        : _directions.onlyDirection(schema) ?? ModelDirection.both;
    for (final MapEntry(key: json, value: property) in properties.entries) {
      final override = _context.overrides.propertyAt(property.location);
      if (override?.exclude ?? false) continue;
      final resolved = _resolved(property);
      final readOnly =
          (resolved?.readOnly ?? false) ||
          (property is SchemaObject && property.readOnly);
      final writeOnly =
          (resolved?.writeOnly ?? false) ||
          (property is SchemaObject && property.writeOnly);
      if (direction == .request && readOnly) continue;
      if (direction == .response && writeOnly) continue;
      final suffix = _names.pascal(json) ?? 'Field';
      final custom = override?.dartType;
      final hint = NameHint._under(pending, suffix);
      final mapped = custom == null
          ? _map(property, hint)
          : _replaced(property, hint);
      fields.add(
        _Field(
          json: json,
          override: override,
          location: property.location,
          valueType: custom == null ? mapped : _custom(custom, mapped),
          required: required.contains(json),
          readOnly: readOnly,
          writeOnly: writeOnly,
          marked:
              property is SchemaObject &&
              property.extensions[triStateExtension] == true,
          defaultValue: resolved?.defaultValue,
          description: resolved?.description,
          deprecated: resolved?.deprecated ?? false,
        ),
      );
    }
    final extra = schema.additionalProperties;
    final additional = extra == null || extra is BooleanSchema
        ? null
        : _map(extra, NameHint._under(pending, 'Value'));
    pending.build = (name) {
      final scope = NameScope(
        reserved: {...DartNames.reservedWords, ...DartNames.modelMembers},
        reservedSuffix: '_',
      );
      return ModelDecl(
        id: pending.id,
        name: name,
        description: schema.description,
        deprecated: schema.deprecated,
        additionalProperties: additional,
        direction: direction,
        fields: [
          for (final field in fields)
            FieldIr(
              name: _memberName(
                scope,
                field.json,
                field.override,
                field.location,
                owner: name,
              ),
              jsonKey: field.json,
              valueType: field.valueType,
              location: field.location,
              required: field.required,
              triState: field.override?.triState ?? _isTriState(field, pending),
              readOnly: field.readOnly,
              writeOnly: field.writeOnly,
              defaultValue: field.defaultValue,
              description: field.description,
              deprecated: field.deprecated,
            ),
        ],
      );
    };
  }

  /// Whether [field] tells "absent" from `null` by the config's rule (R7.2).
  bool _isTriState(_Field field, _Pending pending) =>
      switch (_context.config.triState) {
        .patch =>
          pending.patchBody && !field.required && field.valueType.nullable,
        .optional => pending.patchBody && !field.required,
        .extension => field.marked,
      };

  /// The properties and required names of [schema] with its `allOf` parts
  /// merged in, parts first and in order (R6.3). A property that a later
  /// part defines again with another schema is reported; the later one is
  /// used.
  (Map<String, Schema>, Set<String>) _merged(SchemaObject schema) {
    final properties = <String, Schema>{};
    final required = <String>{};
    final seen = <SpecLocation>{};
    void add(SchemaObject part) {
      if (!seen.add(part.location)) return;
      for (final written in part.allOf) {
        final resolved = _resolved(written);
        if (resolved == null) continue;
        if (resolved.properties.isEmpty &&
            resolved.allOf.isEmpty &&
            (_enumValues(resolved) != null ||
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
      required.addAll(part.required);
    }

    add(schema);
    return (properties, required);
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

  void _union(
    SchemaObject schema,
    _Pending pending,
    UnionKind kind,
    List<Schema> branches,
  ) {
    final variants = <(DartType, SpecLocation?, SpecLocation)>[
      for (final (i, branch) in branches.indexed)
        (
          _map(branch, NameHint._under(pending, 'Variant${i + 1}')),
          branch is SchemaObject && branch.ref != null
              ? _resolved(branch)?.location
              : null,
          branch.location,
        ),
    ];
    final discriminator = schema.discriminator;
    final property = discriminator?.propertyName;
    final values = <SpecLocation, List<String>>{};
    DartType? fallback;
    if (discriminator != null && property != null) {
      final targets = {for (final (_, target, _) in variants) ?target};
      for (final MapEntry(key: value, value: ref)
          in discriminator.mapping.entries) {
        final target = _mappingTarget(ref, schema.location.document);
        if (target == null) continue;
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
      for (final (_, target, at) in variants) {
        if (target == null) {
          _context.report(
            .discriminatorValueMissing,
            'This variant is written inline, so no discriminator value '
            'selects it.',
            at,
            fix: r'Make the variant a component schema and $ref it.',
          );
          continue;
        }
        if (values.containsKey(target)) continue;
        if (_componentKey(target) case final key?) values[target] = [key];
      }
      if (discriminator.defaultMapping case final ref?) {
        final target = _mappingTarget(ref, schema.location.document);
        for (final (type, at, _) in variants) {
          if (at != null && at == target) fallback = type;
        }
      }
    }
    final exhaustive =
        _context.overrides.schemaAt(schema.location)?.exhaustive ?? true;
    pending.build = (name) => UnionDecl(
      id: pending.id,
      name: name,
      kind: kind,
      discriminator: property,
      defaultVariant: fallback,
      exhaustive: exhaustive,
      description: schema.description,
      deprecated: schema.deprecated,
      variants: [
        for (final (type, target, _) in variants)
          UnionVariantIr(
            type,
            discriminatorValues: [...?values[target]]..sort(),
          ),
      ],
    );
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
  /// the extension is missing or malformed (TOA351). An enum that has `null`
  /// among its written values may list it too.
  (List<String>?, List<String>?) _enumLabels(
    SchemaObject schema,
    List<Object?> values,
  ) {
    List<String>? labels(String key) {
      final written = schema.extensions[key];
      if (written == null) return null;
      final all = schema.enumValues;
      if (written is List<Object?> && written.every((e) => e is String)) {
        final strings = written.cast<String>();
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

    return (labels('x-enum-varnames'), labels('x-enum-descriptions'));
  }

  void _enum(
    SchemaObject schema,
    _Pending pending,
    List<Object?> values,
    EnumKind kind,
    List<String>? names,
    List<String>? descriptions,
  ) {
    final exhaustive =
        _context.overrides.schemaAt(schema.location)?.exhaustive ?? true;
    pending.build = (name) {
      final scope = NameScope(
        reserved: {...DartNames.reservedWords, ...DartNames.enumMembers},
        reservedSuffix: '_',
      );
      return EnumDecl(
        id: pending.id,
        name: name,
        kind: kind,
        exhaustive: exhaustive,
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
    if (candidate == null || change != null) {
      _context.report(
        candidate == null
            ? .nameUnrepresentable
            : change == .reserved
            ? .nameReserved
            : .nameCollision,
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
        fix: 'Write a name with a letter or digit in x-enum-varnames.',
      );
    }
    if (candidate != null && value is! num) {
      _context.checkLossyName(
        fromName == null ? text : named!,
        name,
        location,
        what: 'Value',
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

  /// The non-null values of an enum (`enum`, or `const` as a one-value
  /// enum), or null when [schema] is not one.
  static List<Object?>? _enumValues(SchemaObject schema) {
    final values = [
      ...?schema.enumValues,
      if (schema.enumValues == null) ?schema.constValue?.$1,
    ];
    final nonNull = [for (final v in values) ?v];
    return nonNull.isEmpty ? null : nonNull;
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

  SchemaObject? _resolved(Schema schema) =>
      switch (_context.model.resolveSchema(schema)) {
        final SchemaObject object => object,
        _ => null,
      };

  /// The name of a schema a `$ref` points to: its `components.schemas` key,
  /// else the last token of its pointer (`#/definitions/Pet`), else its file
  /// name without the extension (`pet.yaml`).
  static String _referenceName(SpecLocation location) {
    final key = _componentKey(location);
    if (key != null) return key;
    final tokens = location.pointer.tokens;
    if (tokens.isNotEmpty) return tokens.last;
    final file = location.document.pathSegments.lastOrNull ?? '';
    final dot = file.lastIndexOf('.');
    return dot > 0 ? file.substring(0, dot) : file;
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

  /// Whether [schema] allows `null`: 3.0 `nullable`, `null` in `type`, or
  /// `null` among the `enum` values.
  static bool _isNullable(SchemaObject schema) =>
      (schema.nullable ?? false) ||
      schema.types.contains(SchemaType.nullType) ||
      (schema.enumValues?.contains(null) ?? false) ||
      schema.oneOf.any(_isNullOnly) ||
      schema.anyOf.any(_isNullOnly);
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
  late Declaration Function(String name) build;

  /// Overridden names are claimed first, then component keys, then inline
  /// names.
  int get rank => overrideName != null
      ? 0
      : componentKey != null
      ? 1
      : 2;
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
}
