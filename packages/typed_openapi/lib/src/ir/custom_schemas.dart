import '../model/schema.dart';
import 'custom_types.dart';
import 'dart_type.dart';
import 'declaration_names.dart';
import 'mapping_scope.dart';
import 'mapping_tools.dart';
import 'names.dart';
import 'pending_declaration.dart';
import 'schema_queries.dart';
import 'type_recursion.dart';

/// The schemas that something else stands in for: a custom Dart type, or
/// `JsonValue` when an override excludes the schema (R4.2, R6.8).
final class CustomSchemas {
  /// Custom schemas of the client of [_tools]; the JSON side of a replaced
  /// schema is mapped with [_types].
  const CustomSchemas(this._tools, this._types);

  static const _names = DartNames();

  final MappingTools _tools;
  final TypeRecursion _types;

  /// The type every use of [schema] gets instead of a declaration: its
  /// custom type, or `JsonValue` when an override excludes it; null when it
  /// is generated as it is, or when [scope] is already a replaced schema.
  DartType? substitute(SchemaObject schema, MappingScope scope) {
    if (scope.replacing) return null;
    final custom = _customType(schema, scope);
    final excluded =
        _tools.context.overrides.schemaAt(schema.location)?.exclude ?? false;
    if (custom != null) {
      if (excluded) _reportExcludedButCustom(schema);
      return custom;
    }
    if (!excluded) return null;
    _reportExcludedButUsed(schema);
    return const CoreType(.json);
  }

  void _reportExcludedButCustom(SchemaObject schema) {
    _tools.context.report(
      .excludedSchemaReferenced,
      'This schema is excluded by an override, but it also has a custom '
      'Dart type; the type is used and the exclude has no effect.',
      schema.location,
      fix: 'Remove the exclude, or the custom type.',
    );
  }

  void _reportExcludedButUsed(SchemaObject schema) {
    _tools.context.report(
      .excludedSchemaReferenced,
      'This schema is excluded by an override, but a generated type uses '
      'it; the use is generated as JsonValue.',
      schema.location,
      fix:
          'Exclude what uses the schema too, or give the schema a Dart '
          'type instead of excluding it.',
    );
  }

  /// The custom type every use of [schema] gets (R6.8): an override's
  /// `dartType` or `types.schemas` of the config.
  DartType? _customType(SchemaObject schema, MappingScope scope) {
    final context = _tools.context;
    final override = context.overrides.schemaAt(schema.location)?.dartType;
    final key = DeclarationNames.componentKey(schema.location);
    final custom =
        override ?? (key == null ? null : context.config.schemas[key]);
    if (custom == null) return null;
    final aliases = _tools.state.aliases;
    // The schema is an alias open while its JSON side is built, so a cycle
    // through it ends there.
    aliases.add(schema.location);
    try {
      final json = _types.replaced(
        schema,
        NameHint(
          _names.pascal(key ?? '') ?? DeclarationNames.fallbackName,
          '',
        ),
        scope,
      );
      return CustomTypes.of(
        custom,
        json,
      ).withNullable(SchemaQueries.isNullable(schema));
    } finally {
      aliases.remove(schema.location);
    }
  }
}
