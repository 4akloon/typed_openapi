import '../model/schema.dart';
import 'dart_type.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'schema_shapes.dart';

/// Tells which response bodies are secrets that no `toString` may print
/// (`<redacted>`), by the rule the models use for their fields: the schema
/// carries a secret (`writeOnly`, `format: password`, or a value that holds
/// one), or the body stays raw JSON (`JsonValue`) and a secret is anywhere
/// in its schema, since nothing prints the properties of raw JSON.
final class ResponseSecrets {
  /// Creates the questions for the spec of [_context].
  ResponseSecrets(this._context);

  final IrContext _context;

  // Lazy because a field initializer cannot read `_context`.
  late final RefFollower _refs = RefFollower(
    (schema) => switch (_context.model.resolveSchema(schema)) {
      final SchemaObject object => object,
      _ => null,
    },
    siblings: _context.model.document.version != .v30,
  );

  /// Whether a body of [type] mapped from [schema] is a secret; false
  /// without a [schema] or a [type].
  bool isSecret(Schema? schema, DartType? type) =>
      schema != null &&
      type != null &&
      (SchemaShapes.carriesSecret(schema, refs: _refs) ||
          (type.holdsRawJson &&
              SchemaShapes.carriesSecret(
                schema,
                refs: _refs,
                intoProperties: true,
              )));

  /// Whether the body of type [type] of the `errors.default_schema` is a
  /// secret.
  bool isDefaultErrorSecret(DartType? type) {
    final key = _context.defaultErrorSchema;
    final schema = key == null
        ? null
        : _context.model.document.components?.schemas[key];
    return isSecret(schema, type);
  }

  /// The statuses of the error [responses] whose body is a secret: a
  /// response without a body of its own has the body of [fallback] (the type
  /// of `errors.default_schema`), which counts when that schema is one.
  Set<String> errorStatuses(List<ResponseIr> responses, DartType? fallback) => {
    for (final response in responses)
      if (response.isError &&
          (response.type == null
              ? isDefaultErrorSecret(fallback)
              : response.sensitive))
        response.status,
  };
}
