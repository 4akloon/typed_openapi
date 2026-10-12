import '../model/schema.dart';
import '../model/spec_node.dart';
import '../overrides/override_set.dart';
import 'dart_type.dart';
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
/// reachable from what is mapped are generated (R4.2). Names are given at
/// the end ([declarations]): component schemas keep their key, inline
/// schemas are named after their parent, and collisions get a suffix with a
/// diagnostic (R5.2).
final class SchemaMapper {
  /// Creates a mapper for the spec of [_context].
  SchemaMapper(this._context);

  static const _names = DartNames();
  static const _fallbackName = 'Schema';

  final IrContext _context;
  final Map<DeclId, _Pending> _pending = {};
  final Map<String, _Pending> _inlineEnums = {};
  final Set<SpecLocation> _aliases = {};

  /// The type of [schema]; an inline declaration it needs is named by
  /// [hint].
  DartType typeOf(Schema schema, NameHint hint) => _map(schema, hint);

  /// The type of the `components.schemas` entry [schema], as a `$ref` to it
  /// would have.
  DartType typeOfComponent(Schema schema) =>
      switch (_context.model.resolveSchema(schema)) {
        final SchemaObject target => _component(target),
        _ => const CoreType(.json),
      };

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
      pending.name = _claim(scope, pending);
    }
    return [for (final pending in ordered) pending.build!(pending.name!)];
  }

  String _claim(NameScope scope, _Pending pending) {
    final overridden = pending.overrideName;
    final String? candidate;
    if (overridden != null) {
      candidate = overridden;
    } else if (pending.componentKey case final key?) {
      candidate = _names.pascal(key);
    } else {
      final parent = pending.hint!._parent?.name ?? pending.hint!.prefix!;
      candidate = '$parent${pending.hint!.suffix}';
    }
    if (candidate == null) {
      final (name, _) = scope.claim(_fallbackName);
      _context.report(
        .nameUnrepresentable,
        'Schema "${pending.componentKey}" has no ASCII letter or digit, so '
        'its type is named "$name".',
        pending.id.location,
        fix: 'Rename the schema at the source, or name its type.',
        override: _context.schemaOverride(pending.id.location, {'name': name}),
      );
      return name;
    }
    final (name, change) = scope.claim(candidate);
    if (change != null) {
      _context.report(
        change == .reserved ? .nameReserved : .nameCollision,
        change == .reserved
            ? '"$candidate" is a name Dart already has; the type is named '
                  '"$name".'
            : 'Another type is named "$candidate"; this one is named '
                  '"$name".',
        pending.id.location,
        fix: 'Name the type explicitly to keep the name stable.',
        override: _context.schemaOverride(pending.id.location, {'name': name}),
      );
    }
    return name;
  }

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
    final custom = _customSchemaType(schema);
    if (custom != null) return custom;
    final id = DeclId(schema.location);
    final pending = _pending[id];
    if (pending != null) return NamedType(id, nullable: _isNullable(schema));
    final key = _componentKey(schema.location);
    if (_declares(schema)) {
      return _declare(
        schema,
        id,
        (p) => p
          ..componentKey = key
          ..overrideName = _context.overrides.schemaAt(schema.location)?.name,
      );
    }
    // A structural schema (array, map, scalar) has no declaration of its
    // own: each use gets its type. One that refers back to itself cannot be
    // spelled out.
    if (!_aliases.add(schema.location)) {
      _context.report(
        .recursiveAlias,
        'This schema refers to itself without an object between; the '
        'reference is generated as JsonValue.',
        schema.location,
        fix: 'Make the recursive part an object schema at the source.',
      );
      return const CoreType(.json);
    }
    try {
      return _structural(
        schema,
        NameHint(_names.pascal(key ?? '') ?? _fallbackName, ''),
      );
    } finally {
      _aliases.remove(schema.location);
    }
  }

  DartType _inline(SchemaObject schema, NameHint hint) {
    if (_declares(schema)) {
      if (_enumValues(schema) case final values?) {
        final kind = _enumKind(schema, values);
        if (kind != null) {
          final key = '${kind.name}:${values.join('\u0000')}';
          final known = _inlineEnums[key];
          if (known != null) {
            return NamedType(known.id, nullable: _isNullable(schema));
          }
        }
      }
      return _declare(schema, DeclId(schema.location), (p) => p.hint = hint);
    }
    return _structural(schema, hint);
  }

  /// Whether [schema] gets a declaration: an object with properties or an
  /// enum.
  bool _declares(SchemaObject schema) =>
      _enumValues(schema) != null || schema.properties.isNotEmpty;

  DartType _declare(
    SchemaObject schema,
    DeclId id,
    void Function(_Pending) setUp,
  ) {
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
    final pending = _Pending(id);
    setUp(pending);
    final parent = pending.hint?._parent;
    pending.depth = parent == null ? 0 : parent.depth + 1;
    _pending[id] = pending;
    if (values != null && kind != null) {
      _enum(schema, pending, values, kind);
    } else {
      _model(schema, pending);
    }
    return NamedType(id, nullable: _isNullable(schema));
  }

  void _model(SchemaObject schema, _Pending pending) {
    final fields = <_Field>[];
    for (final MapEntry(key: json, value: property)
        in schema.properties.entries) {
      final override = _context.overrides.propertyAt(property.location);
      if (override?.exclude ?? false) continue;
      final resolved = _resolved(property);
      final suffix = _names.pascal(json) ?? 'Field';
      final custom = override?.dartType;
      final mapped = _map(property, NameHint._under(pending, suffix));
      fields.add(
        _Field(
          json: json,
          override: override,
          location: property.location,
          valueType: custom == null ? mapped : _custom(custom, mapped),
          required: schema.required.contains(json),
          readOnly: resolved?.readOnly ?? false,
          writeOnly: resolved?.writeOnly ?? false,
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
        fields: [
          for (final field in fields)
            FieldIr(
              name: _memberName(
                scope,
                field.json,
                field.override?.name,
                field.location,
                owner: name,
              ),
              jsonKey: field.json,
              valueType: field.valueType,
              location: field.location,
              required: field.required,
              triState: field.override?.triState ?? false,
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

  /// The Dart name of the member [json] of the type [owner], from [named]
  /// (an override) or [json].
  String _memberName(
    NameScope scope,
    String json,
    String? named,
    SpecLocation location, {
    required String owner,
  }) {
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
    return name;
  }

  void _enum(
    SchemaObject schema,
    _Pending pending,
    List<Object?> values,
    EnumKind kind,
  ) {
    if (pending.componentKey == null) {
      _inlineEnums['${kind.name}:${values.join('\u0000')}'] = pending;
    }
    final names = switch (schema.extensions['x-enum-varnames']) {
      final List<Object?> given
          when given.length == values.length &&
              given.every((n) => n is String) =>
        given.cast<String>(),
      _ => null,
    };
    final descriptions = switch (schema.extensions['x-enum-descriptions']) {
      final List<Object?> given when given.length == values.length => given,
      _ => null,
    };
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
              description: switch (descriptions?[i]) {
                final String text => text,
                _ => null,
              },
            ),
        ],
      );
    };
  }

  String _valueName(
    NameScope scope,
    String? named,
    Object value,
    SpecLocation location,
    String owner,
  ) {
    final candidate =
        (named == null ? null : _names.camel(named)) ??
        switch (value) {
          final num number =>
            'value${number < 0 ? 'Minus' : ''}'
                '${'${number.abs()}'.replaceAll('.', '_')}',
          _ => _names.camel('$value'),
        };
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
    return name;
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
      _context.report(
        .mixedTypeSchema,
        'This schema allows ${types.map((t) => t.wire).join(', ')}; it is '
        'generated as JsonValue.',
        schema.location,
        fix:
            'Give the schema one type at the source, or a Dart type with an '
            'override.',
        override: _context.schemaOverride(schema.location, {
          'dartType': {'type': 'MyType', 'import': 'package:app/my_type.dart'},
        }),
      );
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
    final json = _declares(schema)
        ? const CoreType(.json)
        : _structural(schema, NameHint(_names.pascal(key ?? '') ?? '', ''));
    return _custom(custom, json).withNullable(_isNullable(schema));
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
      (schema.enumValues?.contains(null) ?? false);
}

/// A declaration whose name is not given yet.
final class _Pending {
  _Pending(this.id);

  final DeclId id;
  String? componentKey;
  String? overrideName;
  NameHint? hint;
  int depth = 0;
  String? name;
  Declaration Function(String name)? build;

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
  final (Object?,)? defaultValue;
  final String? description;
  final bool deprecated;
}
