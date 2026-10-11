import '../config/project_config.dart';
import '../diagnostics/diagnostic.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../load/openapi_version.dart';
import '../load/spec_document.dart';
import '../load/spec_loader.dart';
import '../resolve/spec_documents.dart';
import '../resolve/spec_model.dart';
import '../resolve/spec_reader.dart';
import 'normalizer_rule.dart';
import 'rules/bool_required_to_array.dart';
import 'rules/drop_invalid_default.dart';
import 'rules/enum_rules.dart';
import 'rules/path_param_rules.dart';
import 'rules/schema_shape_rules.dart';
import 'spec_edit.dart';

/// The result of normalizing a spec.
final class NormalizedSpec {
  /// Creates a result.
  const NormalizedSpec(this.model, this.documents);

  /// The model of the last pass.
  final SpecModel model;

  /// The files of the last pass, with every fix applied.
  final SpecDocuments documents;
}

/// Reads a spec into the model, runs the rules over it, applies their fixes
/// to the plain trees and reads it again, until no rule has a fix or
/// [maxPasses] passes have run.
///
/// The report holds what the parser and resolver say about the last pass,
/// every finding of a rule that fixed something in a pass, and the findings
/// of the last pass's rules.
/// Problems go to the [DiagnosticBag] given to the constructor; files are
/// loaded once, with their loading problems reported there too.
final class Normalizer {
  /// Creates a normalizer that reports to [_diagnostics] and runs [rules]
  /// (by default every rule) in order, except the [disabled] names; a
  /// [preset] adds framework hints to the findings.
  Normalizer(
    this._diagnostics, {
    List<NormalizerRule>? rules,
    Set<String> disabled = const {},
    this.preset,
  }) : _rules = [
         for (final rule in rules ?? Normalizer.rules)
           if (!disabled.contains(rule.name)) rule,
       ];

  /// How many times the model is read at most.
  static const maxPasses = 3;

  /// Every rule, in the order it runs; an earlier rule's fix wins a
  /// conflict.
  static final List<NormalizerRule> rules = List.unmodifiable(
    <NormalizerRule>[
      const BoolRequiredToArray(),
      const DropInvalidDefault(),
      const ArrayWithoutItems(),
      const DoubleArray(),
      const FormatOnArray(),
      const BinaryObject(),
      const ContradictoryObjectType(),
      const ExampleTypeMismatch(),
      const DedupeEnumValues(),
      const NullableEnumOneOf(),
      const DeclareMissingPathParams(),
      const PathParamNotInTemplate(),
    ],
  );

  /// The names of [rules].
  static Set<String> get ruleNames => {for (final rule in rules) rule.name};

  final DiagnosticBag _diagnostics;
  final List<NormalizerRule> _rules;

  /// The framework whose hints the findings carry.
  final Preset? preset;

  /// Normalizes [document], which declares [version].
  NormalizedSpec normalize(SpecDocument document, OpenApiVersion version) {
    final loader = SpecLoader(_diagnostics);
    var root = document;
    var others = const <SpecDocument>[];
    for (var pass = 1; ; pass++) {
      final scratch = DiagnosticBag();
      final documents = SpecDocuments(loader, root, others: others);
      final model = SpecReader(scratch).read(
        root,
        version,
        documents: documents,
      );
      final context = RuleContext(model, documents, version);
      final found = [
        for (final rule in _rules)
          for (final finding in rule.check(context)) (rule, finding),
      ];
      final hasEdits = found.any((f) => f.$2.edits.isNotEmpty);
      if (!hasEdits || pass == maxPasses) {
        scratch.all.forEach(_diagnostics.add);
        for (final (rule, finding) in found) {
          _report(rule, finding);
          for (final edit in finding.edits) {
            _notApplied(
              documents,
              rule,
              edit,
              'the spec still changed after $maxPasses passes',
            );
          }
        }
        return NormalizedSpec(model, documents);
      }
      // Every finding of a rule that fixes something in this pass is part of
      // that fix (a rule may put one edit on the first of several
      // findings); the other rules' findings come again in the last pass.
      final fixing = {
        for (final (rule, finding) in found)
          if (finding.edits.isNotEmpty) rule,
      };
      for (final (rule, finding) in found) {
        if (fixing.contains(rule)) _report(rule, finding);
      }
      final edited = _apply(documents, found);
      root = edited[root.uri] ?? root;
      others = [
        for (final loaded in documents.loaded)
          if (loaded.uri != root.uri) edited[loaded.uri] ?? loaded,
      ];
    }
  }

  /// Applies the edits of [found] in order, skipping any that overlaps an
  /// earlier one; returns the edited documents by URI.
  Map<Uri, SpecDocument> _apply(
    SpecDocuments documents,
    List<(NormalizerRule, Finding)> found,
  ) {
    final accepted = <(NormalizerRule, SpecEdit)>[];
    final editors = <Uri, TreeEditor>{};
    for (final (rule, finding) in found) {
      for (final edit in finding.edits) {
        final earlier = accepted.where((a) => a.$2.overlaps(edit)).firstOrNull;
        if (earlier != null) {
          _notApplied(
            documents,
            rule,
            edit,
            'it overlaps a fix of rule "${earlier.$1.name}"',
          );
          continue;
        }
        final uri = edit.location.document;
        final document = documents[uri];
        if (document == null) {
          _notApplied(documents, rule, edit, 'its file cannot be read');
          continue;
        }
        final editor = editors[uri] ??= TreeEditor(document.root);
        final problem = editor.apply(edit);
        if (problem != null) {
          _notApplied(documents, rule, edit, problem);
          continue;
        }
        accepted.add((rule, edit));
      }
    }
    return {
      for (final MapEntry(key: uri, value: editor) in editors.entries)
        uri: documents[uri]!.withRoot(editor.root),
    };
  }

  void _report(NormalizerRule rule, Finding finding) {
    final d = finding.diagnostic;
    final hint = switch (preset) {
      final preset? => rule.hint(d.code, preset),
      null => null,
    };
    _diagnostics.add(
      hint == null
          ? d
          : Diagnostic(
              code: d.code,
              severity: d.severity,
              message: d.message,
              file: d.file,
              pointer: d.pointer,
              span: d.span,
              fix: d.fix == null ? hint : '${d.fix} $hint',
            ),
    );
  }

  void _notApplied(
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
