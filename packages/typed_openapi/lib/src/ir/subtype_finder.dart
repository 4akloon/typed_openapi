import '../model/schema.dart';
import 'declaration_names.dart';
import 'mapping_tools.dart';
import 'schema_shapes.dart';

/// Finds the subtypes of a polymorphic base: the schemas that extend a
/// schema with a discriminator by `allOf` (user decision for M8).
final class SubtypeFinder {
  /// A finder for the spec of [_tools].
  SubtypeFinder(this._tools);

  final MappingTools _tools;

  /// The schemas that extend [base] with `allOf`, directly or through
  /// another subtype, in the order of `components.schemas` and then of the
  /// other files the spec reads, when [base] has a discriminator and is not
  /// a union or an enum: a polymorphic base. A subtype an override excludes
  /// is left out.
  List<SchemaObject> subtypes(SchemaObject base) {
    if (base.discriminator?.propertyName == null ||
        _tools.queries.branches(base) != null ||
        SchemaShapes.enumValues(base) != null) {
      return const [];
    }
    return _tools.state.subtypesOf[base.location] ??= _find(base);
  }

  /// Whether [schema] is a polymorphic base: a schema with a discriminator
  /// that other schemas extend ([subtypes]).
  bool isBase(Schema schema) => switch (_tools.queries.resolved(schema)) {
    final base? => subtypes(base).isNotEmpty,
    null => false,
  };

  /// The schemas of the other files the spec reads that a `$ref` can name:
  /// the root of a file and the entries of its `components.schemas`, in the
  /// order of their locations. A file nothing refers to is not read, so a
  /// subtype that only it has is not found.
  late final List<SchemaObject> _foreignSchemas = [
    for (final node in _tools.context.model.nodes)
      if (node is SchemaObject &&
          node.ref == null &&
          node.location.document !=
              _tools.context.model.document.location.document &&
          (node.location.pointer.tokens.isEmpty ||
              DeclarationNames.componentKey(node.location) != null))
        node,
  ];

  List<SchemaObject> _find(SchemaObject base) {
    final components = [
      for (final schema
          in _tools.context.model.document.components?.schemas.values ??
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
          (part) => found.contains(_tools.queries.resolved(part)?.location),
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
            !_isExcluded(schema))
          schema,
    ];
  }

  bool _isExcluded(SchemaObject schema) =>
      _tools.context.overrides.schemaAt(schema.location)?.exclude ?? false;
}
