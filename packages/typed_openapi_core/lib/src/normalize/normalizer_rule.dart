import '../config/project_config.dart';
import '../diagnostics/diagnostic.dart';
import '../diagnostics/diagnostic_code.dart';
import '../load/openapi_version.dart';
import '../model/spec_node.dart';
import '../overrides/override_snippet.dart';
import '../resolve/spec_documents.dart';
import '../resolve/spec_model.dart';
import 'spec_edit.dart';

/// What a rule found: a diagnostic, and for a fix the edits that make it.
final class Finding {
  /// Creates a finding.
  const Finding(this.diagnostic, {this.edits = const []});

  /// What is wrong and how to fix it at the source.
  final Diagnostic diagnostic;

  /// The edits that fix it; empty for a diagnostic-only finding.
  final List<SpecEdit> edits;
}

/// What a rule reads: the model of one pass and the files it came from.
final class RuleContext {
  /// Creates a context for [model], read from [documents] as [version].
  RuleContext(this.model, this.documents, this.version);

  /// The spec as the parser read it in this pass.
  final SpecModel model;

  /// The files of the spec, with their plain trees and positions.
  final SpecDocuments documents;

  /// The version the root document declares.
  final OpenApiVersion version;

  late final OverrideSnippet _snippets = OverrideSnippet(model);

  /// Every node of type [T], ordered by location.
  Iterable<T> nodes<T extends SpecNode>() => model.nodes.whereType<T>();

  /// The raw value at [location] as a one-element record, or null when
  /// nothing is there.
  (Object?,)? rawAt(SpecLocation location) =>
      documents[location.document]?.valueAt(location.pointer);

  /// The raw value at [location] when it is an object, else null.
  Map<String, Object?>? rawObject(SpecLocation location) =>
      switch (rawAt(location)) {
        (final Map<String, Object?> raw,) => raw,
        _ => null,
      };

  /// [fix] followed by the override of the schema at [schema] that sets
  /// [fields], to copy into the overrides file; [fix] alone when the schema
  /// has no override address, or when it is a `$ref` with siblings in a 3.0
  /// document, where an override of the siblings is not applied.
  String withOverride(
    String fix,
    SpecLocation schema,
    Map<String, Object?> fields,
  ) {
    if (version == .v30 &&
        rawObject(schema)?.containsKey(r'$ref') == true &&
        !fields.containsKey(r'$ref')) {
      return fix;
    }
    return switch (_snippets.forSchema(schema, fields)) {
      final snippet? => '$fix Override:\n$snippet',
      null => fix,
    };
  }

  /// A finding of [code] at [at], with [edits] when it is a fix.
  Finding finding(
    DiagnosticCode code,
    String message,
    SpecLocation at, {
    String? fix,
    List<SpecEdit> edits = const [],
  }) => Finding(
    Diagnostic(
      code: code,
      severity: code.defaultSeverity,
      message: message,
      file: documents.displayPath(at.document),
      pointer: at.pointer,
      span: documents[at.document]?.spanOf(at.pointer),
      fix: fix,
    ),
    edits: edits,
  );
}

/// A named check of the spec model: it finds a defect and either fixes it
/// with [SpecEdit]s, when the fix follows from the spec or the protocol, or
/// describes it.
///
/// Rules never change the model; the normalizer applies their edits to the
/// plain trees and reads the model again.
abstract base class NormalizerRule {
  /// Creates a rule.
  const NormalizerRule();

  /// The name used in the config, such as `bool-required-to-array`.
  String get name;

  /// The codes the rule reports.
  List<DiagnosticCode> get codes;

  /// The findings in [context], in a stable order.
  Iterable<Finding> check(RuleContext context);

  /// How to fix a [code] finding in the code of a [preset] framework, or
  /// null when there is no specific recipe.
  String? hint(DiagnosticCode code, Preset preset) => null;
}
