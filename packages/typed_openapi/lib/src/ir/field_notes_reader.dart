import '../model/schema.dart';
import 'ir.dart' show ConstraintsIr;
import 'ir_context.dart';
import 'mapping_state.dart';
import 'schema_queries.dart';
import 'schema_shapes.dart';

/// Reads what the schema of a property says about its field: description,
/// default, constraints, flags and secrecy (R6.7).
final class FieldNotesReader {
  /// A reader for the client of [_context].
  const FieldNotesReader(this._context, this._queries);

  final IrContext _context;
  final SchemaQueries _queries;

  /// What the schema of [property] says about its field.
  ///
  /// The sources are the property's own keywords, the annotation-only
  /// `allOf` parts next to the one part it stands for
  /// (`allOf: [{$ref: Pet}, {description: ...}]`), and the schema it refers
  /// to, in this order: the first `description` and `default` win, and the
  /// field is deprecated, `readOnly` or `writeOnly` when any source says so.
  /// In OpenAPI 3.0 a `$ref` has no siblings, so only the target gives the
  /// description, default and deprecation; 3.1 and 3.2 take the property's
  /// own keywords before the target's (a written `deprecated: false` cannot
  /// be told from a missing one, so it does not override a deprecated
  /// target).
  FieldNotes of(Schema property) {
    if (property is! SchemaObject) return const FieldNotes();
    final written = _written(property);
    final sources = SchemaShapes.annotationSources(
      property,
      refs: _queries.refs,
    );
    return FieldNotes(
      knownValues: _knownValues(sources),
      constraints: constraintsOf(written),
      description: written
          .map((s) => s.description)
          .firstWhere((d) => d != null, orElse: () => null),
      defaultValue: written
          .map((s) => s.defaultValue)
          .firstWhere((d) => d != null, orElse: () => null),
      deprecated: written.any((s) => s.deprecated),
      readOnly: sources.any((s) => s.readOnly),
      writeOnly: sources.any((s) => s.writeOnly),
      secret: SchemaShapes.carriesSecret(property, refs: _queries.refs),
    );
  }

  /// The schemas whose own keywords count for [property], in order: the
  /// property if its keywords count, the annotation-only parts of its
  /// `allOf`, and the schema it stands for.
  List<SchemaObject> _written(SchemaObject property) {
    final parts = property.ref == null
        ? SchemaShapes.annotationParts(property)
        : const <SchemaObject>[];
    final target = switch (property.ref) {
      null => switch (SchemaShapes.singleOf(property)) {
        final single? when property.allOf.contains(single) => _queries.resolved(
          single,
        ),
        _ => null,
      },
      _ => _queries.resolved(property),
    };
    final siblings =
        property.ref == null || _context.model.document.version != .v30;
    return [if (siblings) property, ...parts, ?target];
  }

  /// The enum values of the branches that [sources] drop as adding nothing
  /// (TOA455), for the doc comment of the field.
  List<Object?> _knownValues(List<SchemaObject> sources) {
    final known = <Object?>[];
    for (final schema in sources) {
      final dropped = SchemaShapes.subsumedBranches(
        schema,
        refs: _queries.refs,
      );
      for (final branch in dropped.keys) {
        for (final value in SchemaShapes.enumValues(branch) ?? const []) {
          if (!known.contains(value)) known.add(value);
        }
      }
    }
    return known;
  }

  /// The constraints of a field from the schemas [written] for it, the first
  /// that sets each one winning (R6.7). A 3.0 boolean `exclusiveMinimum`
  /// makes `minimum` exclusive, and the same for the maximum.
  static ConstraintsIr constraintsOf(List<SchemaObject> written) {
    T? first<T extends Object>(T? Function(SchemaObject s) read) {
      for (final schema in written) {
        if (read(schema) case final value?) return value;
      }
      return null;
    }

    final minimum = first((s) => s.minimum);
    final maximum = first((s) => s.maximum);
    final minExclusive = first((s) => s.exclusiveMinimumFlag) ?? false;
    final maxExclusive = first((s) => s.exclusiveMaximumFlag) ?? false;
    return ConstraintsIr(
      minLength: first((s) => s.minLength),
      maxLength: first((s) => s.maxLength),
      pattern: first((s) => s.pattern),
      minimum: minExclusive ? null : minimum,
      maximum: maxExclusive ? null : maximum,
      exclusiveMinimum:
          first((s) => s.exclusiveMinimum) ?? (minExclusive ? minimum : null),
      exclusiveMaximum:
          first((s) => s.exclusiveMaximum) ?? (maxExclusive ? maximum : null),
      multipleOf: first((s) => s.multipleOf),
      minItems: first((s) => s.minItems),
      maxItems: first((s) => s.maxItems),
      uniqueItems: written.any((s) => s.uniqueItems),
      minProperties: first((s) => s.minProperties),
      maxProperties: first((s) => s.maxProperties),
    );
  }
}
