import '../model/schema.dart';
import '../model/spec_node.dart';
import 'dart_type.dart';
import 'enum_mapper.dart';
import 'ir.dart' show JsonKind;
import 'mapping_tools.dart';
import 'schema_shapes.dart';

/// Which JSON type a schema's values have, and which branches of a union a
/// value's JSON type cannot tell apart (R9.2).
final class JsonKinds {
  /// Questions about JSON types for the mapping of [_tools].
  JsonKinds(this._tools);

  final MappingTools _tools;

  /// The branches of a union without a discriminator that the JSON type of
  /// a value cannot tell apart, by index, with their JSON type (null for a
  /// branch of any JSON value, which every other branch conflicts with),
  /// and how many distinct branches there are. A branch that is the same
  /// schema as an earlier one is a duplicate (TOA454): neither a conflict
  /// nor counted. `integer` and `number` are told apart by the value.
  (Map<int, JsonKind?>, int) conflicts(List<Schema> branches) {
    final kinds = <int, JsonKind?>{};
    final seen = <SpecLocation>{};
    for (final (i, branch) in branches.indexed) {
      final location = _tools.queries.resolved(branch)?.location;
      if (location != null && !seen.add(location)) continue;
      kinds[i] = ofSchema(branch, {});
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
  JsonKind? ofType(DartType type) => switch (type) {
    CoreType(:final kind) => switch (kind) {
      .string || .dateTime || .date || .bytes || .binary => .string,
      .integer => .integer,
      .float || .number => .number,
      .boolean => .boolean,
      .json => null,
    },
    ListType() => .array,
    MapType() => .object,
    CustomType(:final json) => ofType(json),
    PatchType(:final value) => ofType(value),
    NamedType(:final id) => _tools.state.pending[id]?.jsonKind,
  };

  /// The JSON type every value of [schema] has, or null when it may have
  /// several (or any); [seen] stops a cycle.
  JsonKind? ofSchema(Schema schema, Set<SpecLocation> seen) {
    final queries = _tools.queries;
    final object = queries.resolved(schema);
    if (object == null || !seen.add(object.location)) return null;
    if (SchemaShapes.enumValues(object) case final values?) {
      return _enumKind(object, values);
    }
    // A union is an object when a discriminator picks its variant; any
    // other union may hold values of several types.
    if (queries.branches(object) != null) {
      return object.discriminator?.propertyName != null ? .object : null;
    }
    if (SchemaShapes.singleOf(object, refs: queries.refs) case final single?) {
      return ofSchema(single, seen);
    }
    if (object.properties.isNotEmpty || object.allOf.isNotEmpty) {
      return .object;
    }
    return _declaredKind(object);
  }

  JsonKind? _enumKind(SchemaObject schema, List<Object?> values) =>
      switch (EnumMapper.kindOf(schema, values)) {
        .string => .string,
        .integer => .integer,
        .number => .number,
        .boolean => .boolean,
        null => null,
      };

  /// The JSON type that the `type` of [schema], its items or its
  /// `additionalProperties` give; null when it has several or none.
  JsonKind? _declaredKind(SchemaObject schema) {
    final types = [
      for (final type in schema.types)
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
        schema.items != null
            ? .array
            : schema.additionalProperties != null
            ? .object
            : null,
    };
  }
}
