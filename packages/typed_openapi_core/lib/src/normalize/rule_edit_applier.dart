import '../diagnostics/diagnostic_bag.dart';
import '../load/spec_document.dart';
import '../resolve/spec_documents.dart';
import 'normalizer_rule.dart';
import 'spec_edit.dart';

/// Applies the fixes the rules propose in one pass and reports those that
/// cannot be applied (TOA800).
final class RuleEditApplier {
  /// Creates an applier that reports to [_diagnostics].
  const RuleEditApplier(this._diagnostics);

  final DiagnosticBag _diagnostics;

  /// Applies the edits of [found] in order; returns the edited documents by
  /// URI.
  ///
  /// An edit equal to an applied one is skipped. An edit that overlaps an
  /// applied one waits: it is not reported, because its rule proposes it
  /// again in the next pass if it is still needed (and the last pass
  /// reports every edit that is still proposed).
  Map<Uri, SpecDocument> apply(
    SpecDocuments documents,
    List<(NormalizerRule, Finding)> found,
  ) {
    final accepted = <SpecEdit>[];
    final editors = <Uri, TreeEditor>{};
    for (final (rule, finding) in found) {
      for (final edit in finding.edits) {
        if (accepted.any(edit.sameAs)) continue;
        if (accepted.any((a) => a.overlaps(edit))) continue;
        final uri = edit.location.document;
        final document = documents[uri];
        if (document == null) {
          reportNotApplied(documents, rule, edit, 'its file cannot be read');
          continue;
        }
        final editor = editors[uri] ??= TreeEditor(document.root);
        final problem = editor.apply(edit);
        if (problem != null) {
          reportNotApplied(documents, rule, edit, problem);
          continue;
        }
        accepted.add(edit);
      }
    }
    return {
      for (final MapEntry(key: uri, value: editor) in editors.entries)
        uri: documents[uri]!.withRoot(editor.root),
    };
  }

  /// Reports that [rule]'s [edit] was not applied, for [reason].
  void reportNotApplied(
    SpecDocuments documents,
    NormalizerRule rule,
    SpecEdit edit,
    String reason,
  ) {
    final uri = edit.location.document;
    final pointer = edit.location.pointer;
    _diagnostics.report(
      .fixNotApplied,
      'A fix of rule "${rule.name}" was not applied: $reason.',
      file: documents.displayPath(uri),
      pointer: pointer,
      span: documents[uri]?.spanOf(pointer),
    );
  }
}
