import '../model/schema.dart';
import 'ir_context.dart';
import 'schema_shapes.dart';

/// Reads the `default` of a schema the way a model field does (M6): the
/// first one wins among the schema's own keywords, the schema it stands for
/// (the one part of an `allOf`, the one branch of a nullable `anyOf` or
/// `oneOf`) and the schema a `$ref` names. The keywords written next to a
/// `$ref` count from OpenAPI 3.1; 3.0 ignores them.
final class SchemaDefaults {
  /// Creates the reader for the spec of [_context].
  SchemaDefaults(this._context);

  final IrContext _context;

  late final RefFollower _refs = RefFollower(
    (schema) => switch (_context.model.resolveSchema(schema)) {
      final SchemaObject object => object,
      _ => null,
    },
    siblings: _context.model.document.version != .v30,
  );

  /// The `default` of [schema], wrapped so that an explicit `null` default
  /// differs from none; null when [schema] is null or no source has one.
  (Object?,)? of(Schema? schema) {
    if (schema == null) return null;
    for (final source in SchemaShapes.annotationSources(schema, refs: _refs)) {
      if (source.ref != null && !_refs.siblings) continue;
      if (source.defaultValue case final value?) return value;
    }
    return null;
  }
}
