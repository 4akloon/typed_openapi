import '../model/schema.dart';
import '../resolve/spec_model.dart';
import 'ref_follower.dart';
import 'schema_shapes.dart';

/// Takes off the wrappers that add nothing to the one schema they stand for
/// (an annotation-only `allOf`, a nullable `anyOf`), following `$ref`s.
final class SchemaUnwrapper {
  /// Creates an unwrapper that reads schemas through [_model].
  const SchemaUnwrapper(this._model);

  /// The most wrappers [unwrap] takes off a schema: a `$ref` cycle of
  /// wrappers ends there.
  static const _maxWrappers = 16;

  final SpecModel _model;

  /// [schema] at the end of its wrappers; null when a `$ref` on the way is
  /// broken.
  Schema? unwrap(Schema? schema) {
    final refs = RefFollower.of(_model);
    var current = schema;
    for (var i = 0; i < _maxWrappers; i++) {
      if (current is! SchemaObject) return current;
      final single = SchemaShapes.singleOf(current, refs: refs);
      if (single == null) return current;
      current = _model.resolveSchema(single);
    }
    return current;
  }
}
