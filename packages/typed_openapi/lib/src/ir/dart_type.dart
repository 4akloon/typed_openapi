import '../model/spec_node.dart';

/// Which of the declarations of one schema an id names.
enum DeclVariant {
  /// The declaration of the schema; the response model of a split schema.
  base,

  /// The request model of a schema split by direction (`PetInput`).
  input,

  /// The PATCH body model of a schema also used elsewhere (`PetPatch`).
  patch,
}

/// The identity of a generated declaration: the location of the schema it
/// comes from and its [variant].
///
/// Types refer to declarations by id, so a declaration can be renamed
/// (collisions, overrides) without touching the types that use it.
final class DeclId implements Comparable<DeclId> {
  /// Creates the id of the declaration of the schema at [location].
  const DeclId(this.location, {this.variant = .base});

  /// Where the schema is.
  final SpecLocation location;

  /// Which declaration of the schema this is.
  final DeclVariant variant;

  @override
  bool operator ==(Object other) =>
      other is DeclId && other.location == location && other.variant == variant;

  @override
  int get hashCode => Object.hash(location, variant);

  @override
  int compareTo(DeclId other) {
    final byLocation = location.compareTo(other.location);
    if (byLocation != 0) return byLocation;
    return variant.index - other.variant.index;
  }

  @override
  String toString() =>
      variant == .base ? '$location' : '$location (${variant.name})';
}

/// A Dart type of a field, a parameter or a body.
sealed class DartType {
  /// Creates a type.
  const DartType({this.nullable = false});

  /// Whether the type is followed by `?`.
  final bool nullable;

  /// This type with [nullable] set to [value].
  DartType withNullable(bool value);

  /// The type as Dart code; [nameOf] gives the name of a declaration.
  String code(String Function(DeclId id) nameOf) =>
      nullable ? '${_code(nameOf)}?' : _code(nameOf);

  String _code(String Function(DeclId id) nameOf);
}

/// The built-in and runtime types a schema maps to.
enum CoreKind {
  /// `integer`.
  integer('int'),

  /// `number` with format `float` or `double`.
  float('double'),

  /// `number` without a format: any number.
  number('num'),

  /// `string`.
  string('String'),

  /// `boolean`.
  boolean('bool'),

  /// `string` with format `date-time`, in UTC.
  dateTime('DateTime'),

  /// `string` with format `date`: `Date` of `typed_openapi_runtime`.
  date('Date'),

  /// `string` with format `byte`: base64 in JSON.
  bytes('Uint8List'),

  /// `string` with format `binary`: raw bytes of a body or a part.
  binary('Uint8List'),

  /// A schema without constraints: `JsonValue` of `typed_openapi_runtime`.
  json('JsonValue');

  const CoreKind(this.dartName);

  /// The name of the Dart type.
  final String dartName;
}

/// A built-in or runtime type.
///
/// [CoreKind.json] is never nullable: `JsonValue(null)` already stands for
/// `null` and for a missing value.
final class CoreType extends DartType {
  /// Creates a type of [kind].
  const CoreType(this.kind, {super.nullable = false});

  /// Which type.
  final CoreKind kind;

  @override
  bool get nullable => kind != .json && super.nullable;

  @override
  CoreType withNullable(bool value) => CoreType(kind, nullable: value);

  @override
  String _code(String Function(DeclId id) nameOf) => kind.dartName;

  @override
  bool operator ==(Object other) =>
      other is CoreType && other.kind == kind && other.nullable == nullable;

  @override
  int get hashCode => Object.hash(CoreType, kind, nullable);
}

/// `List<T>`.
final class ListType extends DartType {
  /// Creates a list of [item].
  const ListType(this.item, {super.nullable = false});

  /// The type of the elements.
  final DartType item;

  @override
  ListType withNullable(bool value) => ListType(item, nullable: value);

  @override
  String _code(String Function(DeclId id) nameOf) =>
      'List<${item.code(nameOf)}>';

  @override
  bool operator ==(Object other) =>
      other is ListType && other.item == item && other.nullable == nullable;

  @override
  int get hashCode => Object.hash(ListType, item, nullable);
}

/// `Map<String, T>`.
final class MapType extends DartType {
  /// Creates a map with values of [value].
  const MapType(this.value, {super.nullable = false});

  /// The type of the values.
  final DartType value;

  @override
  MapType withNullable(bool value) => MapType(this.value, nullable: value);

  @override
  String _code(String Function(DeclId id) nameOf) =>
      'Map<String, ${value.code(nameOf)}>';

  @override
  bool operator ==(Object other) =>
      other is MapType && other.value == value && other.nullable == nullable;

  @override
  int get hashCode => Object.hash(MapType, value, nullable);
}

/// A generated model, enum or union.
final class NamedType extends DartType {
  /// Creates a reference to the declaration [id].
  const NamedType(this.id, {super.nullable = false});

  /// The declaration.
  final DeclId id;

  @override
  NamedType withNullable(bool value) => NamedType(id, nullable: value);

  @override
  String _code(String Function(DeclId id) nameOf) => nameOf(id);

  @override
  bool operator ==(Object other) =>
      other is NamedType && other.id == id && other.nullable == nullable;

  @override
  int get hashCode => Object.hash(NamedType, id, nullable);
}

/// A type of the user's code instead of a generated one (R6.8).
final class CustomType extends DartType {
  /// Creates a custom type.
  const CustomType({
    required this.type,
    required this.import,
    required this.json,
    this.converter,
    super.nullable = false,
  });

  /// The Dart type, such as `Money`.
  final String type;

  /// The library that declares [type].
  final String import;

  /// A class with `fromJson` and `toJson` that converts [type], if any.
  final String? converter;

  /// The type of the value in JSON, from the schema: `S` of `fromJson(S)`.
  final DartType json;

  @override
  CustomType withNullable(bool value) => CustomType(
    type: type,
    import: import,
    json: json,
    converter: converter,
    nullable: value,
  );

  @override
  String _code(String Function(DeclId id) nameOf) => type;

  @override
  bool operator ==(Object other) =>
      other is CustomType &&
      other.type == type &&
      other.import == import &&
      other.converter == converter &&
      other.json == json &&
      other.nullable == nullable;

  @override
  int get hashCode =>
      Object.hash(CustomType, type, import, converter, json, nullable);
}

/// `Patch<T>` of `typed_openapi_runtime`: a field that tells "absent"
/// from `null` (R7).
final class PatchType extends DartType {
  /// Creates a patch of [value].
  const PatchType(this.value, {super.nullable = false});

  /// The type of the value; never nullable.
  final DartType value;

  @override
  PatchType withNullable(bool value) => PatchType(this.value, nullable: value);

  @override
  String _code(String Function(DeclId id) nameOf) =>
      'Patch<${value.code(nameOf)}>';

  @override
  bool operator ==(Object other) =>
      other is PatchType && other.value == value && other.nullable == nullable;

  @override
  int get hashCode => Object.hash(PatchType, value, nullable);
}
