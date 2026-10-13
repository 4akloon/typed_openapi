import '../model/schema.dart';
import 'dart_type.dart';
import 'mapping_scope.dart';
import 'pending_declaration.dart';

/// How the parts of the schema mapper map the schemas inside what they map:
/// the properties of a model, the branches of a union, the items of a list.
///
/// The functions are the schema mapper's own, so a part never holds the
/// mapper itself.
final class TypeRecursion {
  /// A recursion made of the three mapping functions.
  const TypeRecursion({
    required this.map,
    required this.component,
    required this.replaced,
  });

  /// The type of a schema written inline or as a `$ref`, an inline
  /// declaration it needs named by the hint.
  final DartType Function(Schema schema, NameHint hint, MappingScope scope) map;

  /// The type of a schema a `$ref` points to.
  final DartType Function(SchemaObject schema, MappingScope scope) component;

  /// The JSON side of a schema a custom type replaces.
  final DartType Function(Schema schema, NameHint hint, MappingScope scope)
  replaced;
}
