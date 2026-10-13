import '../model/schema.dart';
import '../resolve/spec_model.dart';

/// How a schema question follows a `$ref`: [resolve] reaches the schema a
/// `$ref` names, and [siblings] says whether the keywords written next to a
/// `$ref` count (OpenAPI 3.1 and later; 3.0 ignores them).
final class RefFollower {
  /// Creates a follower.
  const RefFollower(this.resolve, {required this.siblings});

  /// The follower of [model]: it follows a `$ref` to a [SchemaObject], and
  /// the keywords next to a `$ref` count from OpenAPI 3.1.
  factory RefFollower.of(SpecModel model) => RefFollower(
    (schema) => switch (model.resolveSchema(schema)) {
      final SchemaObject object => object,
      _ => null,
    },
    siblings: model.document.version != .v30,
  );

  /// The schema a `$ref` names, or null when it cannot be followed.
  final Schema? Function(Schema) resolve;

  /// Whether keywords beside a `$ref` are keywords of the schema.
  final bool siblings;
}
