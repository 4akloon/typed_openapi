import '../model/schema.dart';
import '../resolve/spec_documents.dart';
import '../resolve/spec_model.dart';
import 'override_set.dart';
import 'override_target.dart';
import 'override_target_reporter.dart';

/// Finds the component schema a [SchemaOverride] names, and its properties.
final class SchemaTargetFinder {
  /// Creates a finder that reports to [_reporter].
  const SchemaTargetFinder(this._reporter);

  final OverrideTargetReporter _reporter;

  /// The schema `components.schemas` has under the key of [entry], where its
  /// `$ref` chain ends; null, after a report, when there is none.
  SchemaObject? schema(
    SchemaOverride entry,
    SpecModel model,
    SpecDocuments documents,
  ) {
    final written = model.document.components?.schemas[entry.key];
    if (written == null) {
      _reporter.notFound(
        entry,
        'No schema "${entry.key}" in components.schemas.',
      );
      return null;
    }
    final schema = model.resolveSchema(written);
    if (schema is SchemaObject) return schema;
    _reporter.notFound(
      entry,
      schema == null
          ? 'The \$ref of schema "${entry.key}" cannot be followed.'
          : 'Schema "${entry.key}" is the boolean schema '
                '${documents.displayPath(schema.location.document)}'
                '${schema.pointer.value}; '
                'it has no fields to change.',
    );
    return null;
  }

  /// The property [entry] names in the own `properties` of [owner]; null,
  /// after a report, when there is none.
  PropertyTarget? property(
    PropertyOverride entry,
    SchemaOverride parent,
    SchemaObject owner,
  ) {
    final property = owner.properties[entry.key];
    if (property != null) return PropertyTarget(entry, owner, property);
    _reporter.notFound(
      entry,
      'Schema "${parent.key}" has no property "${entry.key}" in its own '
      '"properties".',
    );
    return null;
  }
}
