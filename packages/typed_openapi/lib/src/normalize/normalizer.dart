import '../config/project_config.dart';
import '../diagnostics/diagnostic.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/json_pointer.dart';
import '../load/openapi_version.dart';
import '../load/spec_document.dart';
import '../load/spec_loader.dart';
import '../overrides/override_applier.dart';
import '../overrides/override_resolver.dart';
import '../overrides/override_set.dart';
import '../resolve/spec_documents.dart';
import '../resolve/spec_model.dart';
import '../resolve/spec_reader.dart';
import 'normalizer_rule.dart';
import 'rules/bool_required_to_array.dart';
import 'rules/drop_invalid_default.dart';
import 'rules/enum_rules.dart';
import 'rules/operation_id_rules.dart';
import 'rules/path_param_rules.dart';
import 'rules/reference_shape_rules.dart';
import 'rules/schema_shape_rules.dart';
import 'spec_edit.dart';

/// The result of normalizing a spec.
final class NormalizedSpec {
  /// Creates a result.
  const NormalizedSpec(this.model, this.documents, {this.overrides});

  /// The model of the last pass.
  final SpecModel model;

  /// The files of the last pass, with every fix applied.
  final SpecDocuments documents;

  /// The client's overrides, whose spec fields are applied; their
  /// generation fields are for the generator.
  final OverrideSet? overrides;
}

/// Reads a spec into the model, applies the spec fields of the client's
/// overrides, then runs the rules over it, applies their fixes to the plain
/// trees and reads it again, until no rule has a fix or [maxPasses] passes
/// have run.
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
      const MissingOperationId(),
      const DuplicateOperationId(),
      const DiscriminatorPropertyRequired(),
      const DiscriminatorMappingTarget(),
      const WildcardMediaType(),
      const ComponentKeyCharacters(),
    ],
  );

  /// The names of [rules].
  static Set<String> get ruleNames => {for (final rule in rules) rule.name};

  final DiagnosticBag _diagnostics;
  final List<NormalizerRule> _rules;

  /// The framework whose hints the findings carry.
  final Preset? preset;

  /// Normalizes [document], which declares [version], after applying the
  /// spec fields of [overrides].
  NormalizedSpec normalize(
    SpecDocument document,
    OpenApiVersion version, {
    OverrideSet? overrides,
  }) {
    final loader = SpecLoader(_diagnostics);
    var root = document;
    var others = const <SpecDocument>[];
    _OverrideOrigins? origins;
    if (overrides != null && !overrides.isEmpty) {
      final documents = SpecDocuments(loader, root);
      final read = DiagnosticBag();
      final model = SpecReader(
        read,
      ).read(root, version, documents: documents);
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
      final applied = <OverrideEdit>[];
      final edited = _applyOverrides(documents, overrides, edits, applied);
      origins = _OverrideOrigins(
        overrides,
        before: [
          ...read.all,
          for (final rule in _rules)
            for (final finding in rule.check(
              RuleContext(model, documents, version),
            ))
              finding.diagnostic,
        ],
        changes: [
          for (final OverrideEdit(:edit, :sources) in applied)
            for (final (entry, field) in sources)
              (
                documents.displayPath(edit.location.document),
                _parentOf(edit.location.pointer),
                entry.pointer.child(field),
              ),
        ],
      );
      root = edited[root.uri] ?? root;
      others = [
        for (final loaded in documents.loaded)
          if (loaded.uri != root.uri) edited[loaded.uri] ?? loaded,
      ];
    }
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
        for (final diagnostic in scratch.all) {
          _diagnostics.add(origins?.attach(diagnostic) ?? diagnostic);
        }
        final reported = <SpecEdit>[];
        for (final (rule, finding) in found) {
          _report(rule, finding, origins);
          for (final edit in finding.edits) {
            // An edit proposed twice (a path item shared by several paths)
            // is one fix.
            if (reported.any(edit.sameAs)) continue;
            reported.add(edit);
            _notApplied(
              documents,
              rule,
              edit,
              'the spec still changed after $maxPasses passes',
            );
          }
        }
        return NormalizedSpec(model, documents, overrides: overrides);
      }
      // Every finding of a rule that fixes something in this pass is part of
      // that fix (a rule may put one edit on the first of several
      // findings); the other rules' findings come again in the last pass.
      final fixing = {
        for (final (rule, finding) in found)
          if (finding.edits.isNotEmpty) rule,
      };
      for (final (rule, finding) in found) {
        if (fixing.contains(rule)) _report(rule, finding, origins);
      }
      final edited = _apply(documents, found);
      root = edited[root.uri] ?? root;
      others = [
        for (final loaded in documents.loaded)
          if (loaded.uri != root.uri) edited[loaded.uri] ?? loaded,
      ];
    }
  }

  /// Applies the edits of [found] in order; returns the edited documents by
  /// URI.
  ///
  /// An edit equal to an applied one is skipped. An edit that overlaps an
  /// applied one waits: it is not reported, because its rule proposes it
  /// again in the next pass if it is still needed (and the last pass
  /// reports every edit that is still proposed).
  Map<Uri, SpecDocument> _apply(
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
          _notApplied(documents, rule, edit, 'its file cannot be read');
          continue;
        }
        final editor = editors[uri] ??= TreeEditor(document.root);
        final problem = editor.apply(edit);
        if (problem != null) {
          _notApplied(documents, rule, edit, problem);
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

  /// Applies the override [edits] in order and adds the applied ones to
  /// [applied]; returns the edited documents by URI. An edit that cannot be
  /// applied is reported at its override.
  Map<Uri, SpecDocument> _applyOverrides(
    SpecDocuments documents,
    OverrideSet overrides,
    List<OverrideEdit> edits,
    List<OverrideEdit> applied,
  ) {
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
    return {
      for (final MapEntry(key: uri, value: editor) in editors.entries)
        uri: documents[uri]!.withRoot(editor.root),
    };
  }

  void _report(
    NormalizerRule rule,
    Finding finding,
    _OverrideOrigins? origins,
  ) {
    final d = finding.diagnostic;
    final preset = this.preset;
    final hint = preset == null ? null : rule.hint(d.code, preset);
    final hinted = preset == null || hint == null
        ? d
        : d.withHints([...d.hints, (preset.name, hint)]);
    _diagnostics.add(origins?.attach(hinted) ?? hinted);
  }

  /// The node an edit at [pointer] changes: the object or list it sets a
  /// member of.
  static JsonPointer _parentOf(JsonPointer pointer) {
    final tokens = pointer.tokens;
    return tokens
        .take(tokens.isEmpty ? 0 : tokens.length - 1)
        .fold(JsonPointer.root, (at, token) => at.child(token));
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

/// Which problems of a spec its overrides introduced.
///
/// A problem is introduced when the spec as read, before the overrides,
/// did not have it (same code, file and pointer), and an applied override
/// changed a member of its node, of a node inside it or of a node around
/// it.
final class _OverrideOrigins {
  _OverrideOrigins(
    this._overrides, {
    required List<Diagnostic> before,
    required this.changes,
  }) : _before = {for (final d in before) _keyOf(d)};

  final OverrideSet _overrides;
  final Set<(DiagnosticCode, String?, String?)> _before;

  /// The changed nodes: the file as diagnostics name it, the pointer of the
  /// node an override set a member of, and the pointer of the override field
  /// that did.
  final List<(String, JsonPointer, JsonPointer)> changes;

  /// [diagnostic] with the overrides that introduced it as related
  /// locations.
  Diagnostic attach(Diagnostic diagnostic) {
    final pointer = diagnostic.pointer;
    if (pointer == null || _before.contains(_keyOf(diagnostic))) {
      return diagnostic;
    }
    final related = [
      for (final (file, at, field) in changes)
        if (file == diagnostic.file && _nested(pointer, at))
          RelatedLocation(
            message: 'Introduced by this override.',
            file: _overrides.file,
            pointer: field,
            span: _overrides.spanOf(field),
          ),
    ];
    if (related.isEmpty) return diagnostic;
    return diagnostic.withRelated([...diagnostic.related, ...related]);
  }

  static (DiagnosticCode, String?, String?) _keyOf(Diagnostic d) =>
      (d.code, d.file, d.pointer?.value);

  /// Whether one of [a] and [b] is the other or inside it.
  static bool _nested(JsonPointer a, JsonPointer b) {
    final x = a.tokens;
    final y = b.tokens;
    final length = x.length < y.length ? x.length : y.length;
    for (var i = 0; i < length; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }
}
