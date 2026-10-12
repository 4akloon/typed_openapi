import '../diagnostics/diagnostic_bag.dart';
import '../load/openapi_version.dart';
import '../model/spec_node.dart';
import '../resolve/spec_documents.dart';
import 'operation_override_applier.dart';
import 'override_conflicts.dart';
import 'override_edit.dart';
import 'override_edit_context.dart';
import 'override_resolver.dart';
import 'override_set.dart';
import 'schema_override_applier.dart';

export 'override_edit.dart' show OverrideEdit;

/// Turns the spec fields of resolved overrides into [SpecEdit]s.
///
/// A field replaces the value of the spec (a list replaces the list, an
/// object the object) and `null` removes it. `nullable` follows the
/// document's dialect: `nullable: true` in 3.0, `null` in `type` from 3.1.
/// `$ref` makes the schema a reference; a nullable reference is
/// `allOf: [{$ref}]` with `nullable: true` in 3.0 and
/// `anyOf: [{$ref}, {type: 'null'}]` from 3.1.
///
/// A field whose value the spec already has is `override-unchanged`; two
/// different edits of one node by different overrides are
/// `override-conflict`, and neither is made.
final class OverrideApplier {
  /// Creates an applier of [overrides] to [documents], whose root declares
  /// [version]; it reports to [diagnostics].
  OverrideApplier(
    DiagnosticBag diagnostics,
    OverrideSet overrides,
    SpecDocuments documents,
    OpenApiVersion version,
  ) : this._(OverrideEditContext(diagnostics, overrides, documents, version));

  OverrideApplier._(OverrideEditContext context)
    : _operations = OperationOverrideApplier(context),
      _schemas = SchemaOverrideApplier(context),
      _conflicts = OverrideConflicts(context);

  final OperationOverrideApplier _operations;
  final SchemaOverrideApplier _schemas;
  final OverrideConflicts _conflicts;

  /// The edits of [targets], in their order.
  List<OverrideEdit> edits(List<OverrideTarget> targets) {
    final edits = <OverrideEdit>[];
    final required = <SpecLocation, List<PropertyTarget>>{};
    for (final target in targets) {
      switch (target) {
        case OperationTarget():
          break;
        case ParameterTarget():
          edits.addAll(_operations.parameter(target));
        case ContentTarget():
          edits.addAll(_operations.content(target));
        case SchemaTarget():
          edits.addAll(
            _schemas.edits(target.entry, target.node.location, property: false),
          );
        case PropertyTarget():
          edits.addAll(
            _schemas.edits(target.entry, target.node.location, property: true),
          );
          if (target.entry.spec.containsKey('required')) {
            (required[target.owner.location] ??= []).add(target);
          }
      }
    }
    for (final MapEntry(key: owner, value: properties) in required.entries) {
      edits.addAll(_schemas.required(owner, properties));
    }
    return _conflicts.without(edits);
  }
}
