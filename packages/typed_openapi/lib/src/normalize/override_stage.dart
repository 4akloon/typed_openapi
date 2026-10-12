import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/json_pointer.dart';
import '../load/openapi_version.dart';
import '../load/spec_document.dart';
import '../load/spec_loader.dart';
import '../overrides/override_applier.dart';
import '../overrides/override_resolver.dart';
import '../overrides/override_set.dart';
import '../resolve/spec_documents.dart';
import '../resolve/spec_reader.dart';
import 'normalizer_rule.dart';
import 'override_origins.dart';
import 'spec_edit.dart';
import 'spec_sources.dart';

/// Applies the spec fields of a client's overrides once, before the rules
/// run, so the rules see the overridden spec.
final class OverrideStage {
  /// Creates the stage; problems go to [_diagnostics], and [_rules] tell
  /// which problems the spec had before the overrides.
  const OverrideStage(this._diagnostics, this._rules, this._loader);

  final DiagnosticBag _diagnostics;
  final List<NormalizerRule> _rules;
  final SpecLoader _loader;

  /// Reads [root], applies [overrides] to it and returns the edited files
  /// and the record of what the overrides changed.
  ({SpecSources sources, OverrideOrigins origins}) apply(
    SpecDocument root,
    OpenApiVersion version,
    OverrideSet overrides,
  ) {
    final documents = SpecDocuments(_loader, root);
    final read = DiagnosticBag();
    final model = SpecReader(read).read(root, version, documents: documents);
    final targets = OverrideResolver(
      _diagnostics,
      overrides,
    ).resolve(model, documents);
    final edits = OverrideApplier(
      _diagnostics,
      overrides,
      documents,
      version,
    ).edits(targets);
    final (:edited, :applied) = _applyEdits(documents, overrides, edits);
    final origins = OverrideOrigins(
      overrides,
      before: [
        ...read.all,
        for (final rule in _rules)
          for (final finding in rule.check(
            RuleContext(model, documents, version),
          ))
            finding.diagnostic,
      ],
      changes: _changes(documents, applied),
    );
    return (
      sources: SpecSources.edited(root, documents, edited),
      origins: origins,
    );
  }

  /// Applies the override [edits] in order; returns the edited documents by
  /// URI and the edits that were applied. An edit that cannot be applied is
  /// reported at its override.
  ({Map<Uri, SpecDocument> edited, List<OverrideEdit> applied}) _applyEdits(
    SpecDocuments documents,
    OverrideSet overrides,
    List<OverrideEdit> edits,
  ) {
    final applied = <OverrideEdit>[];
    final editors = <Uri, TreeEditor>{};
    for (final override in edits) {
      final OverrideEdit(:edit, :sources) = override;
      final uri = edit.location.document;
      final document = documents[uri]!;
      final editor = editors[uri] ??= TreeEditor(document.root);
      final problem = editor.apply(edit);
      if (problem == null) {
        applied.add(override);
        continue;
      }
      for (final (entry, field) in sources) {
        final at = entry.pointer.child(field);
        _diagnostics.report(
          .fixNotApplied,
          'This override was not applied: $problem.',
          file: overrides.file,
          pointer: at,
          span: overrides.spanOf(at),
        );
      }
    }
    final edited = {
      for (final MapEntry(key: uri, value: editor) in editors.entries)
        uri: documents[uri]!.withRoot(editor.root),
    };
    return (edited: edited, applied: applied);
  }

  /// The nodes the [applied] edits changed, for [OverrideOrigins.changes].
  List<(String, JsonPointer, JsonPointer)> _changes(
    SpecDocuments documents,
    List<OverrideEdit> applied,
  ) => [
    for (final OverrideEdit(:edit, :sources) in applied)
      for (final (entry, field) in sources)
        (
          documents.displayPath(edit.location.document),
          _parentOf(edit.location.pointer),
          entry.pointer.child(field),
        ),
  ];

  /// The node an edit at [pointer] changes: the object or list it sets a
  /// member of.
  static JsonPointer _parentOf(JsonPointer pointer) {
    final tokens = pointer.tokens;
    return tokens
        .take(tokens.isEmpty ? 0 : tokens.length - 1)
        .fold(JsonPointer.root, (at, token) => at.child(token));
  }
}
