import '../config/project_config.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../load/openapi_version.dart';
import '../load/spec_document.dart';
import '../load/spec_loader.dart';
import '../overrides/override_set.dart';
import '../resolve/spec_documents.dart';
import '../resolve/spec_reader.dart';
import 'normalized_spec.dart';
import 'normalizer_rule.dart';
import 'override_origins.dart';
import 'override_stage.dart';
import 'rule_edit_applier.dart';
import 'rules/bool_required_to_array.dart';
import 'rules/drop_invalid_default.dart';
import 'rules/enum_rules.dart';
import 'rules/operation_id_rules.dart';
import 'rules/path_param_rules.dart';
import 'rules/reference_shape_rules.dart';
import 'rules/schema_shape_rules.dart';
import 'spec_edit.dart';
import 'spec_sources.dart';

export 'normalized_spec.dart';

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
       ],
       _edits = RuleEditApplier(_diagnostics);

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
  final RuleEditApplier _edits;

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
    var sources = SpecSources(document, const []);
    OverrideOrigins? origins;
    if (overrides != null && !overrides.isEmpty) {
      final staged = OverrideStage(
        _diagnostics,
        _rules,
        loader,
      ).apply(document, version, overrides);
      sources = staged.sources;
      origins = staged.origins;
    }
    for (var pass = 1; ; pass++) {
      final scratch = DiagnosticBag();
      final documents = SpecDocuments(
        loader,
        sources.root,
        others: sources.others,
      );
      final model = SpecReader(scratch).read(
        sources.root,
        version,
        documents: documents,
      );
      final found = _check(RuleContext(model, documents, version));
      final hasEdits = found.any((f) => f.$2.edits.isNotEmpty);
      if (!hasEdits || pass == maxPasses) {
        _reportLastPass(documents, scratch, found, origins);
        return NormalizedSpec(model, documents, overrides: overrides);
      }
      _reportFixing(found, origins);
      sources = SpecSources.edited(
        sources.root,
        documents,
        _edits.apply(documents, found),
      );
    }
  }

  /// Every finding of every rule, in rule order.
  List<(NormalizerRule, Finding)> _check(RuleContext context) => [
    for (final rule in _rules)
      for (final finding in rule.check(context)) (rule, finding),
  ];

  /// Reports what the last pass found: the parser's and resolver's problems
  /// of [scratch], every finding, and every edit that is still proposed.
  void _reportLastPass(
    SpecDocuments documents,
    DiagnosticBag scratch,
    List<(NormalizerRule, Finding)> found,
    OverrideOrigins? origins,
  ) {
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
        _edits.reportNotApplied(
          documents,
          rule,
          edit,
          'the spec still changed after $maxPasses passes',
        );
      }
    }
  }

  /// Reports the findings of the rules that fix something in a pass that is
  /// not the last.
  ///
  /// Every finding of such a rule is part of that fix (a rule may put one
  /// edit on the first of several findings); the other rules' findings come
  /// again in the last pass.
  void _reportFixing(
    List<(NormalizerRule, Finding)> found,
    OverrideOrigins? origins,
  ) {
    final fixing = {
      for (final (rule, finding) in found)
        if (finding.edits.isNotEmpty) rule,
    };
    for (final (rule, finding) in found) {
      if (fixing.contains(rule)) _report(rule, finding, origins);
    }
  }

  void _report(
    NormalizerRule rule,
    Finding finding,
    OverrideOrigins? origins,
  ) {
    final d = finding.diagnostic;
    final preset = this.preset;
    final hint = preset == null ? null : rule.hint(d.code, preset);
    final hinted = preset == null || hint == null
        ? d
        : d.withHints([...d.hints, (preset.name, hint)]);
    _diagnostics.add(origins?.attach(hinted) ?? hinted);
  }
}
