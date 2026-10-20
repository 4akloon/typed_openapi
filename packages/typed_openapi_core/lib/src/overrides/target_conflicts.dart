import '../model/operation.dart';
import '../model/spec_node.dart';
import '../resolve/spec_documents.dart';
import '../resolve/spec_model.dart';
import 'override_target.dart';
import 'override_target_reporter.dart';

/// Finds the targets that clash: two overrides that name the same node
/// (`override-conflict`), and an override that changes a node shared with
/// other operations (`override-shared-target`).
final class TargetConflicts {
  /// Creates a finder that reports to [_reporter].
  const TargetConflicts(this._reporter);

  final OverrideTargetReporter _reporter;

  /// Reports [target] when it changes the spec at a node outside
  /// [operation].
  void reportShared(
    OverrideTarget target,
    Operation operation,
    SpecModel model,
    SpecDocuments documents,
  ) {
    if (target.entry.spec.isEmpty) return;
    final at = target.node.location;
    final inside =
        at.document == operation.location.document &&
        at.pointer.value.startsWith('${operation.pointer.value}/');
    if (inside) return;
    final where = at.document == model.document.location.document
        ? at.pointer.value
        : '${documents.displayPath(at.document)}${at.pointer.value}';
    _reporter.report(
      .overrideSharedTarget,
      target.entry,
      'This override changes the shared node at $where; the change applies '
      'to every operation that uses it.',
    );
  }

  /// [found] without the targets whose node another one names too; those
  /// are reported, each naming the others. Request bodies and responses are
  /// kept: they reach a shared node through different keys, and the edits
  /// they make are checked against each other later.
  List<(T, List<OverrideTarget>)> unique<T extends OverrideTarget>(
    List<(T, List<OverrideTarget>)> found,
  ) {
    final byNode = <SpecLocation, List<T>>{};
    for (final (target, _) in found) {
      (byNode[target.node.location] ??= []).add(target);
    }
    final unique = <(T, List<OverrideTarget>)>[];
    for (final (target, inner) in found) {
      final same = byNode[target.node.location]!;
      // Two status codes that `$ref` one component response are different
      // addresses of a shared node, not one address written twice.
      if (same.length == 1 || target is ContentTarget) {
        unique.add((target, inner));
      } else {
        _reportConflict(target, same);
      }
    }
    return unique;
  }

  /// [targets] without the ones whose node another one names too.
  List<OverrideTarget> uniqueTargets(List<OverrideTarget> targets) => [
    for (final (target, _) in unique([
      for (final target in targets) (target, const <OverrideTarget>[]),
    ]))
      target,
  ];

  /// Reports that [target] and the rest of [all] name the same node.
  void _reportConflict(OverrideTarget target, List<OverrideTarget> all) {
    final others = [
      for (final other in all)
        if (other != target) other.entry.pointer.value,
    ];
    _reporter.report(
      .overrideConflict,
      target.entry,
      'This override and the one at ${others.join(', ')} name the same '
      'node (${target.node.location.pointer.value}); neither is applied.',
      fix: 'Merge them into one override.',
    );
  }
}
