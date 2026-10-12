import '../ir/dart_type.dart';
import '../ir/ir.dart';
import 'imports.dart';

/// How generated code names, decodes, encodes and compares values of a
/// [DartType] in one file; every name it writes is imported into
/// [_imports].
final class TypeCodec {
  /// Creates the codec of a file of [_ir] with [_imports]; [_fileOf] gives
  /// the file that declares a declaration.
  TypeCodec(this._ir, this._imports, this._fileOf);

  final ClientIr _ir;
  final Imports _imports;
  final String Function(DeclId id) _fileOf;

  /// The imports of the file.
  Imports get imports => _imports;

  /// The declaration [id] names; every generated type has one.
  Declaration declaration(DeclId id) => _ir[id]!;

  /// [type] as Dart code.
  String type(DartType type) {
    _use(type);
    return type.code(_ir.nameOf);
  }

  /// [type] with the known values of every enum in it (`StatusKnown`
  /// for `Status`), for a constructor of a model sent in requests (R8.2).
  String known(DartType type) {
    final mark = type.nullable ? '?' : '';
    return switch (type) {
      NamedType(:final id) => switch (declaration(id)) {
        final EnumDecl e => _named(id, '${e.knownName}$mark'),
        _ => this.type(type),
      },
      ListType(:final item) => 'List<${known(item)}>$mark',
      MapType(:final value) => 'Map<String, ${known(value)}>$mark',
      PatchType(:final value) => _runtime(
        'Patch',
        'Patch<${known(value)}>$mark',
      ),
      _ => this.type(type),
    };
  }

  /// Whether [type] has an enum in it, so [known] differs from [type].
  bool hasEnum(DartType type) => switch (type) {
    NamedType(:final id) => declaration(id) is EnumDecl,
    ListType(:final item) => hasEnum(item),
    MapType(:final value) => hasEnum(value),
    PatchType(:final value) => hasEnum(value),
    _ => false,
  };

  /// A decoder of [type], `T Function(Object? value)`, for a value that
  /// is not `null` (a nullable item or map value is decoded by
  /// `JsonReader.nullable`).
  String decoder(DartType type) {
    _imports.fromRuntime('JsonReader');
    return switch (type) {
      CoreType(:final kind) => switch (kind) {
        .integer => 'JsonReader.asInt',
        .float => 'JsonReader.asDouble',
        .number => 'JsonReader.asNumber',
        .string => 'JsonReader.asString',
        .boolean => 'JsonReader.asBool',
        .dateTime => 'JsonReader.asDateTime',
        .date => 'JsonReader.asDate',
        .bytes || .binary => 'JsonReader.asBytes',
        .json => 'JsonReader.asValue',
      },
      ListType(:final item) => 'JsonReader.listOf(${_item(item)})',
      MapType(:final value) => 'JsonReader.mapOf(${_item(value)})',
      NamedType(:final id) => switch (declaration(id)) {
        ModelDecl(:final name) => _named(
          id,
          'JsonReader.objectOf($name.fromJson)',
        ),
        final other => _named(id, '${other.name}.fromJson'),
      },
      final CustomType custom => _custom(custom),
      PatchType(:final value) => decoder(value),
    };
  }

  String _item(DartType type) => type.nullable && !_isJson(type)
      ? 'JsonReader.nullable(${decoder(type)})'
      : decoder(type);

  String _custom(CustomType custom) =>
      '(value) => ${_customValue(custom, 'value')}';

  /// The value of the custom type [custom] decoded from [json], a JSON
  /// expression: its `fromJson`, or its converter's, of the JSON side.
  String _customValue(CustomType custom, String json) {
    final CustomType(:type, json: side) = custom;
    final converter = _converter(custom);
    final read = switch (side) {
      MapType(value: CoreType(kind: .json)) => 'JsonReader.asObject($json)',
      ListType(item: CoreType(kind: .json)) => 'JsonReader.asList($json)',
      CoreType(kind: .json) => json,
      _ => '${decoder(side)}($json)',
    };
    return converter == null
        ? '$type.fromJson($read)'
        : 'const $converter().fromJson($read)';
  }

  /// The value of [type] decoded from [json], a JSON expression that is
  /// not `null`.
  String decodeValue(DartType type, String json) => switch (type) {
    NamedType(:final id) when declaration(id) is ModelDecl =>
      '${this.type(type)}.fromJson(JsonReader.asObject($json))',
    final CustomType custom => _customValue(custom, json),
    _ => '${decoder(type)}($json)',
  };

  /// Whether a value of [type] is its own JSON (a scalar, `JsonValue`, or
  /// a list or map of them), so [encode] returns it as is.
  bool isIdentity(DartType type) => switch (type) {
    CoreType(:final kind) => switch (kind) {
      .integer || .float || .number || .string || .boolean || .json => true,
      _ => false,
    },
    ListType(:final item) => isIdentity(item),
    MapType(:final value) => isIdentity(value),
    _ => false,
  };

  /// The JSON of [value], an expression of [type] that is not `null`;
  /// [depth] keeps the names of nested loop variables apart.
  String encode(DartType type, String value, [int depth = 0]) {
    if (isIdentity(type)) return value;
    return switch (type) {
      CoreType(:final kind) => switch (kind) {
        .dateTime => '$value.toUtc().toIso8601String()',
        .bytes || .binary => _bytes(value),
        _ => '$value.toJson()',
      },
      ListType(:final item) =>
        '[for (final e$depth in $value) ${encodeNullable(item, 'e$depth', depth + 1)}]',
      MapType(value: final item) =>
        '$value.map((k$depth, v$depth) => MapEntry(k$depth, ${encodeNullable(item, 'v$depth', depth + 1)}))',
      final CustomType custom => switch (_converter(custom)) {
        null => '$value.toJson()',
        final converter => 'const $converter().toJson($value)',
      },
      PatchType(value: final inner) =>
        '$value.toJson((p$depth) => ${encode(inner, 'p$depth', depth + 1)})',
      NamedType() => '$value.toJson()',
    };
  }

  /// The JSON of [value], an expression of [type] that may be `null` when
  /// the type is nullable: `null` stays `null`.
  String encodeNullable(DartType type, String value, [int depth = 0]) {
    final code = encode(type, value, depth);
    if (!type.nullable || isIdentity(type)) return code;
    if (code.startsWith('$value.')) {
      return '$value?.${code.substring(value.length + 1)}';
    }
    return '$value == null ? null : $code';
  }

  /// Whether `==` of [type] compares by identity or shallowly, so a field
  /// of it needs `DeepEquality`: lists, maps, bytes, `JsonValue`, patches.
  bool needsDeep(DartType type) => switch (type) {
    CoreType(:final kind) => switch (kind) {
      .bytes || .binary || .json => true,
      _ => false,
    },
    ListType() || MapType() || PatchType() => true,
    NamedType() || CustomType() => false,
  };

  /// The pattern a `switch` on a JSON value uses for a variant of [type],
  /// such as `String()`; null for a type that takes any JSON.
  String? jsonPattern(DartType type) => switch (type) {
    CoreType(:final kind) => switch (kind) {
      .string || .dateTime || .date || .bytes || .binary => 'String',
      .integer => 'int',
      .float || .number => 'num',
      .boolean => 'bool',
      .json => null,
    },
    ListType() => 'List<Object?>',
    MapType() => 'Map<String, Object?>',
    CustomType(:final json) => jsonPattern(json),
    PatchType(:final value) => jsonPattern(value),
    NamedType(:final id) => switch (declaration(id)) {
      ModelDecl() => 'Map<String, Object?>',
      EnumDecl(:final kind) => switch (kind) {
        .string => 'String',
        .integer => 'int',
        .number => 'num',
        .boolean => 'bool',
      },
      UnionDecl(:final variants) => jsonPattern(variants.first.type),
    },
  };

  /// The converter of [custom], imported from the custom type's library.
  String? _converter(CustomType custom) {
    final converter = custom.converter;
    if (converter != null) _imports.show(custom.import, converter);
    return converter;
  }

  String _bytes(String value) {
    _imports.show('dart:convert', 'base64Encode');
    return 'base64Encode($value)';
  }

  String _runtime(String name, String code) {
    _imports.fromRuntime(name);
    return code;
  }

  String _named(DeclId id, String code) {
    _imports.file(_fileOf(id));
    return code;
  }

  static bool _isJson(DartType type) =>
      type is CoreType && type.kind == CoreKind.json;

  void _use(DartType type) {
    switch (type) {
      case CoreType(:final kind):
        switch (kind) {
          case .date:
            _imports.fromRuntime('Date');
          case .json:
            _imports.fromRuntime('JsonValue');
          case .bytes || .binary:
            _imports.show('dart:typed_data', 'Uint8List');
          default:
        }
      case ListType(:final item):
        _use(item);
      case MapType(:final value):
        _use(value);
      case PatchType(:final value):
        _imports.fromRuntime('Patch');
        _use(value);
      case NamedType(:final id):
        _imports.file(_fileOf(id));
      case CustomType(:final type, :final import):
        _imports.show(import, type);
    }
  }
}
