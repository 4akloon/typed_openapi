import '../model/schema.dart';
import 'custom_types.dart';
import 'dart_type.dart';
import 'mapping_scope.dart';
import 'mapping_tools.dart';
import 'pending_declaration.dart';
import 'schema_queries.dart';
import 'type_recursion.dart';

/// Maps a schema without a declaration to its Dart type: a scalar, a list or
/// a map, and, inside a replaced schema, the JSON side of a declaring one.
final class StructuralMapper {
  /// A structural mapper that maps the items and values of a schema with
  /// [_types].
  const StructuralMapper(this._tools, this._types);

  final MappingTools _tools;
  final TypeRecursion _types;

  /// The type of a schema without a declaration: a scalar, a list or a
  /// map; `JsonValue` when it allows several types.
  DartType structural(SchemaObject schema, NameHint hint, MappingScope scope) {
    final types = [
      for (final type in schema.types)
        if (type != SchemaType.nullType) type,
    ];
    if (types.length > 1) {
      // A custom type replaces the schema, so it has nothing to report.
      if (!scope.replacing) _reportMixedTypes(schema, types);
      return const CoreType(.json);
    }
    final type =
        types.firstOrNull ??
        (schema.items != null
            ? SchemaType.array
            : schema.additionalProperties != null
            ? SchemaType.object
            : null);
    final base = _baseType(schema, type, hint, scope);
    final format = schema.format;
    final custom = format == null
        ? null
        : _tools.context.config.formats[format];
    final mapped = custom == null ? base : CustomTypes.of(custom, base);
    return mapped.withNullable(SchemaQueries.isNullable(schema));
  }

  void _reportMixedTypes(SchemaObject schema, List<SchemaType> types) {
    _tools.context.report(
      .mixedTypeSchema,
      'This schema allows ${types.map((t) => t.wire).join(', ')}; it is '
      'generated as JsonValue.',
      schema.location,
      fix:
          'Give the schema one type at the source, or a Dart type with an '
          'override.',
      override: _tools.context.schemaOverride(schema.location, {
        'dartType': {'type': 'MyType', 'import': 'package:app/my_type.dart'},
      }),
    );
  }

  /// The type of [schema] written as [type], before the config's custom
  /// type of its format.
  DartType _baseType(
    SchemaObject schema,
    SchemaType? type,
    NameHint hint,
    MappingScope scope,
  ) => switch (type) {
    null || SchemaType.nullType => const CoreType(.json),
    .integer => const CoreType(.integer),
    .number => _numberType(schema.format),
    .boolean => const CoreType(.boolean),
    .string => _stringType(schema.format),
    .array => ListType(switch (schema.items) {
      final items? => _types.map(items, _suffixed(hint, 'Item'), scope),
      null => const CoreType(.json),
    }),
    .object => MapType(switch (schema.additionalProperties) {
      final BooleanSchema _ || null => const CoreType(.json),
      final values => _types.map(values, _suffixed(hint, 'Value'), scope),
    }),
  };

  DartType _numberType(String? format) => switch (format) {
    'float' || 'double' => const CoreType(.float),
    _ => switch (_tools.context.config.numberType) {
      'double' => const CoreType(.float),
      'int' => const CoreType(.integer),
      _ => const CoreType(.number),
    },
  };

  DartType _stringType(String? format) => switch (format) {
    'date-time' => const CoreType(.dateTime),
    'date' => const CoreType(.date),
    'byte' => const CoreType(.bytes),
    'binary' => const CoreType(.binary),
    _ => const CoreType(.string),
  };

  static NameHint _suffixed(NameHint hint, String suffix) =>
      switch (hint.parent) {
        final parent? => NameHint.under(parent, '${hint.suffix}$suffix'),
        null => NameHint(hint.prefix!, '${hint.suffix}$suffix'),
      };

  /// The type of a declaring [schema] inside a replaced schema: nothing is
  /// declared, so the type is that of its JSON value (a map for an object,
  /// a scalar for an enum), which the custom type's `fromJson` takes;
  /// `JsonValue` when the schema may hold values of several JSON types.
  DartType nothingDeclared(SchemaObject schema) =>
      switch (_tools.kinds.ofSchema(schema, {})) {
        .object => const MapType(CoreType(.json)),
        .string => const CoreType(.string),
        .integer => const CoreType(.integer),
        .number => const CoreType(.number),
        .boolean => const CoreType(.boolean),
        _ => const CoreType(.json),
      }.withNullable(SchemaQueries.isNullable(schema));
}
