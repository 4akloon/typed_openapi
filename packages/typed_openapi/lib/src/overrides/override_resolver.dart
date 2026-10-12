import '../diagnostics/diagnostic_bag.dart';
import '../resolve/spec_documents.dart';
import '../resolve/spec_model.dart';
import 'operation_index.dart';
import 'operation_target_finder.dart';
import 'override_set.dart';
import 'override_target.dart';
import 'override_target_reporter.dart';
import 'schema_target_finder.dart';
import 'target_conflicts.dart';

export 'override_target.dart';

/// Finds the node every override of an [OverrideSet] names.
///
/// An override whose node is missing is `override-target-not-found`; one
/// whose address names several nodes is `override-target-ambiguous`; two
/// overrides that name the same node (`getPet` and `GET /pets/{id}`, or `id`
/// and `path:id`) are `override-conflict`. None of them is a target; the
/// overrides inside such an operation or schema are not resolved.
///
/// A parameter, request body or response override with spec fields whose
/// node lies outside its operation (a path-level parameter, a `$ref`'d
/// component, a node in another file) is `override-shared-target`: the
/// change applies to every operation that uses the node.
final class OverrideResolver {
  /// Creates a resolver of [overrides] that reports to [diagnostics].
  OverrideResolver(DiagnosticBag diagnostics, OverrideSet overrides)
    : this._(overrides, OverrideTargetReporter(diagnostics, overrides));

  OverrideResolver._(this._overrides, OverrideTargetReporter reporter)
    : _operations = OperationTargetFinder(reporter),
      _schemas = SchemaTargetFinder(reporter),
      _conflicts = TargetConflicts(reporter);

  final OverrideSet _overrides;
  final OperationTargetFinder _operations;
  final SchemaTargetFinder _schemas;
  final TargetConflicts _conflicts;

  /// The targets in [model], read from [documents], in file order:
  /// operations with their parameters, request bodies and responses, then
  /// schemas with their properties.
  List<OverrideTarget> resolve(SpecModel model, SpecDocuments documents) => [
    ..._operationTargets(model, documents),
    ..._schemaTargets(model, documents),
  ];

  List<OverrideTarget> _operationTargets(
    SpecModel model,
    SpecDocuments documents,
  ) {
    final operations = OperationIndex(model);
    final targets = <OverrideTarget>[];
    final found = <(OperationTarget, List<OverrideTarget>)>[];
    for (final entry in _overrides.operations) {
      final operation = _operations.operation(entry, operations);
      if (operation == null) continue;
      final target = OperationTarget(entry, operation.$1);
      found.add((target, _operations.inside(entry, operation, model)));
    }
    for (final (target, inner) in _conflicts.unique(found)) {
      final unique = _conflicts.uniqueTargets(inner);
      targets
        ..add(target)
        ..addAll(unique);
      for (final t in unique) {
        _conflicts.reportShared(t, target.node, model, documents);
      }
    }
    return targets;
  }

  List<OverrideTarget> _schemaTargets(
    SpecModel model,
    SpecDocuments documents,
  ) {
    final targets = <OverrideTarget>[];
    final schemas = <(SchemaTarget, List<OverrideTarget>)>[];
    for (final entry in _overrides.schemas) {
      final schema = _schemas.schema(entry, model, documents);
      if (schema == null) continue;
      schemas.add((
        SchemaTarget(entry, schema),
        [
          for (final property in entry.properties)
            ?_schemas.property(property, entry, schema),
        ],
      ));
    }
    for (final (target, inner) in _conflicts.unique(schemas)) {
      targets
        ..add(target)
        ..addAll(_conflicts.uniqueTargets(inner));
    }
    return targets;
  }
}
