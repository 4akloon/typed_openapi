import '../model/schema.dart';
import 'ir_context.dart';
import 'schema_queries.dart';
import 'schema_shapes.dart';

/// Reports what a model's schema says that the model leaves out: allOf parts
/// that cannot be merged, properties defined twice, branches beside the
/// model.
final class ModelNotices {
  /// Reports for the client of [_context].
  const ModelNotices(this._context);

  final IrContext _context;

  /// Reports the allOf part [written], excluded by an override, whose
  /// properties are merged all the same: the model is flat and the exclude
  /// only removes the part's own declaration.
  void excludedPartMerged(Schema written) {
    _context.report(
      .excludedSchemaReferenced,
      'This allOf part is excluded by an override, which only leaves '
      'out its own declaration; its properties are merged into this '
      'model, which does not refer to the part.',
      written.location,
      fix:
          'Exclude the properties that should not be here, or remove '
          'the exclude of the schema.',
    );
  }

  /// Reports the allOf part [written], which is not an object and so is
  /// ignored.
  void partIgnored(Schema written) {
    _context.report(
      .allOfPartIgnored,
      'This allOf part is not an object, so it cannot be merged into a '
      'model; it is ignored.',
      written.location,
      fix: 'Make every allOf part an object schema at the source.',
    );
  }

  /// Reports the property [name], defined again by [property] in a later
  /// allOf part.
  void propertyConflict(String name, Schema property) {
    _context.report(
      .allOfPropertyConflict,
      'Property "$name" is defined again by another allOf part; this '
      'definition is used.',
      property.location,
      fix: 'Define each property in one allOf part at the source.',
    );
  }

  /// Reports the `additionalProperties` [later], defined again in a later
  /// allOf part.
  void additionalConflict(Schema later) {
    _context.report(
      .allOfPropertyConflict,
      'additionalProperties is defined again by another allOf part; '
      'this definition is used.',
      later.location,
      fix:
          'Define additionalProperties in one allOf part at the '
          'source.',
    );
  }

  /// Reports the `oneOf` and `anyOf` of [schema], which is generated as a
  /// model: branches that only add constraints are TOA255, others TOA256.
  void branchesBesideModel(SchemaObject schema) {
    for (final (key, branches) in [
      ('oneOf', schema.oneOf),
      ('anyOf', schema.anyOf),
    ]) {
      final real = [
        for (final branch in branches)
          if (!SchemaShapes.isNullOnly(branch)) branch,
      ];
      if (real.isEmpty) continue;
      if (real.every(SchemaQueries.addsOnlyConstraints)) {
        _context.report(
          .oneOfConstraintsIgnored,
          'The $key of this schema only adds constraints to its properties; '
          'it is generated as a model and the branches are ignored.',
          schema.location.child(key),
          fix: 'Nothing to do; the constraints are not checked by the client.',
        );
      } else {
        _context.report(
          .compositionPartsIgnored,
          'The $key branches of this schema are ignored: it is generated as '
          'a model of its properties and allOf parts.',
          schema.location.child(key),
          fix:
              'Move the properties into the branches, or make the schema a '
              'plain union at the source.',
        );
      }
    }
  }
}
