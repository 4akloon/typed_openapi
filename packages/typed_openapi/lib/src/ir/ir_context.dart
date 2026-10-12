import '../config/generation_config.dart';
import '../config/project_config.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../model/spec_node.dart';
import '../normalize/normalizer.dart';
import '../overrides/override_resolver.dart';
import '../overrides/override_set.dart';
import '../overrides/override_snippet.dart';
import '../resolve/spec_documents.dart';
import '../resolve/spec_model.dart';

/// The generation fields of a client's overrides (M4), by the location of
/// the node each entry names.
///
/// Only entries the normalizer could apply are here: an entry whose target
/// is missing, ambiguous or in conflict (TOA804–TOA806) changes nothing.
final class IrOverrides {
  /// Indexes the overrides of [spec] that name a node of its model.
  factory IrOverrides(NormalizedSpec spec) {
    final overrides = spec.overrides;
    if (overrides == null || overrides.isEmpty) return IrOverrides.none();
    // The normalizer has reported what cannot be resolved already.
    final targets = OverrideResolver(
      DiagnosticBag(),
      overrides,
    ).resolve(spec.model, spec.documents);
    return IrOverrides._({
      for (final target in targets) target.node.location: target.entry,
    });
  }

  /// No overrides.
  IrOverrides.none() : this._(const {});

  IrOverrides._(this._entries);

  final Map<SpecLocation, OverrideEntry> _entries;

  /// The override of the schema at the end of a `components.schemas`
  /// key's `$ref` chain.
  SchemaOverride? schemaAt(SpecLocation location) =>
      switch (_entries[location]) {
        final SchemaOverride entry => entry,
        _ => null,
      };

  /// The override of the property schema written at [location].
  PropertyOverride? propertyAt(SpecLocation location) =>
      switch (_entries[location]) {
        final PropertyOverride entry => entry,
        _ => null,
      };

  /// The override of the Operation Object at [location].
  OperationOverride? operationAt(SpecLocation location) =>
      switch (_entries[location]) {
        final OperationOverride entry => entry,
        _ => null,
      };

  /// The override of the Parameter Object at [location].
  ParameterOverride? parameterAt(SpecLocation location) =>
      switch (_entries[location]) {
        final ParameterOverride entry => entry,
        _ => null,
      };
}

/// What every step of building the IR of a client reads, and where it
/// reports.
final class IrContext {
  /// Creates a context for [spec] generated as [client] says.
  IrContext(this.diagnostics, this.spec, this.client)
    : overrides = IrOverrides(spec);

  /// Where problems go.
  final DiagnosticBag diagnostics;

  /// The normalized spec.
  final NormalizedSpec spec;

  /// The client.
  final ClientConfig client;

  /// The generation fields of the client's overrides.
  final IrOverrides overrides;

  late final OverrideSnippet _snippets = OverrideSnippet(model);

  /// The spec model.
  SpecModel get model => spec.model;

  /// The spec files.
  SpecDocuments get documents => spec.documents;

  /// The generation settings.
  GenerationConfig get config => client.generation;

  /// Reports [code] at [at]; [override] is an override to copy into the
  /// overrides file, added to [fix].
  void report(
    DiagnosticCode code,
    String message,
    SpecLocation at, {
    String? fix,
    String? override,
  }) {
    final text = switch ((fix, override)) {
      (final fix?, final snippet?) => '$fix Override:\n$snippet',
      (null, final snippet?) => 'Override:\n$snippet',
      (final fix, null) => fix,
    };
    diagnostics.report(
      code,
      message,
      file: documents.displayPath(at.document),
      pointer: at.pointer,
      span: documents[at.document]?.spanOf(at.pointer),
      fix: text,
    );
  }

  /// The override of the schema at [location] that sets [fields], if the
  /// schema can be addressed.
  String? schemaOverride(SpecLocation location, Map<String, Object?> fields) =>
      _snippets.forSchema(location, fields);

  /// The override at [address] that sets [fields].
  String? overrideAt(List<String> address, Map<String, Object?> fields) =>
      _snippets.write(address, fields);
}
