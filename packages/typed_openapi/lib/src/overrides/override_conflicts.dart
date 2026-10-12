import 'override_edit.dart';
import 'override_edit_context.dart';

/// Drops the edits that touch a node another override's different edit
/// touches, and reports them.
final class OverrideConflicts {
  /// Creates a filter that reports in [_context].
  const OverrideConflicts(this._context);

  final OverrideEditContext _context;

  /// [edits] without the ones that touch a node another override's
  /// different edit touches; those are reported. One edit asked for by
  /// several overrides is made once.
  List<OverrideEdit> without(List<OverrideEdit> edits) {
    final dropped = <OverrideEdit>{};
    final kept = <OverrideEdit>[];
    for (var i = 0; i < edits.length; i++) {
      final a = edits[i];
      if (kept.any((k) => k.edit.sameAs(a.edit))) continue;
      for (var j = 0; j < edits.length; j++) {
        final b = edits[j];
        if (i == j || b.edit.sameAs(a.edit) || !a.edit.overlaps(b.edit)) {
          continue;
        }
        dropped.add(a);
        _report(a, b);
        break;
      }
      if (!dropped.contains(a)) kept.add(a);
    }
    return kept;
  }

  /// Reports the sources of [a], which changes a node [b] changes too.
  void _report(OverrideEdit a, OverrideEdit b) {
    for (final (entry, field) in a.sources) {
      final other = b.sources.first.$1.pointer.child(b.sources.first.$2);
      _context.report(
        .overrideConflict,
        entry,
        field,
        'This changes ${a.edit.location.pointer.value}, which the '
        'override at ${other.value} changes too; neither is applied.',
        fix: 'Keep one of them.',
      );
    }
  }
}
