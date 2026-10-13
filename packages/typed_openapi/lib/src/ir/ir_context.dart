import '../config/generation_config.dart';
import '../config/project_config.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/json_pointer.dart';
import '../diagnostics/message_text.dart';
import '../diagnostics/severity.dart';
import '../model/spec_node.dart';
import '../normalize/normalizer.dart';
import '../overrides/override_resolver.dart';
import '../overrides/override_set.dart';
import '../overrides/override_snippet.dart';
import '../resolve/spec_documents.dart';
import '../resolve/spec_model.dart';
import 'names.dart';

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

  /// The custom Dart types the overrides give to schemas, properties and
  /// parameters.
  Iterable<DartTypeOverride> get dartTypes sync* {
    for (final entry in _entries.values) {
      final custom = switch (entry) {
        SchemaOverride(:final dartType) ||
        PropertyOverride(:final dartType) ||
        ParameterOverride(:final dartType) => dartType,
        _ => null,
      };
      if (custom != null) yield custom;
    }
  }

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

  /// `errors.default_schema` when `components.schemas` has the key; else
  /// null, with TOA652 reported the first time this is read.
  late final String? defaultErrorSchema = _checkedDefaultErrorSchema();

  static const _names = DartNames();

  /// The spec model.
  SpecModel get model => spec.model;

  /// The spec files.
  SpecDocuments get documents => spec.documents;

  /// The generation settings.
  GenerationConfig get config => client.generation;

  /// The names of the custom Dart types of the config (`types.formats`,
  /// `types.schemas`) and of the overrides (`dartType`), in order.
  late final List<String> customTypeNames = {
    for (final custom in [
      ...config.formats.values,
      ...config.schemas.values,
      ...overrides.dartTypes,
    ])
      custom.type,
  }.toList()..sort();

  /// Reports [code] at [at], with the code's own severity unless [severity]
  /// is given; [override] is an override to copy into the overrides file,
  /// added to [fix].
  void report(
    DiagnosticCode code,
    String message,
    SpecLocation at, {
    Severity? severity,
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
      severity: severity,
      file: documents.displayPath(at.document),
      pointer: at.pointer,
      span: documents[at.document]?.spanOf(at.pointer),
      fix: text,
    );
  }

  String? _checkedDefaultErrorSchema() {
    final key = config.defaultErrorSchema;
    if (key == null) return null;
    if (model.document.components?.schemas.containsKey(key) ?? false) {
      return key;
    }
    final pointer = config.defaultErrorSchemaPointer;
    diagnostics.report(
      .defaultErrorSchemaMissing,
      'errors.default_schema names "$key", which is not in '
      'components.schemas; the setting is ignored.',
      file: config.file,
      pointer: pointer,
      span: config.defaultErrorSchemaSpan,
      fix: 'Name a key of components.schemas, or remove the setting.',
    );
    return null;
  }

  /// Whether an override leaves the property schema written at [location]
  /// out of its model.
  bool isPropertyExcluded(SpecLocation location) =>
      overrides.propertyAt(location)?.exclude ?? false;

  /// Reports [code] at the `field` of the override [entry], in the
  /// overrides file.
  void reportAtOverride(
    DiagnosticCode code,
    String message,
    OverrideEntry entry,
    String field, {
    String? fix,
  }) => reportAtPointer(code, message, entry.pointer.child(field), fix: fix);

  /// Reports [code] at [pointer] of the overrides file.
  void reportAtPointer(
    DiagnosticCode code,
    String message,
    JsonPointer pointer, {
    String? fix,
  }) {
    final set = spec.overrides;
    if (set == null) return;
    diagnostics.report(
      code,
      message,
      file: set.file,
      pointer: pointer,
      span: set.spanOf(pointer),
      fix: fix,
    );
  }

  /// The Dart name of [kind] that the override [entry] gives with its
  /// `field` set to [value] ([what] says what it names, such as `type`).
  /// [value] when it is a valid name; else the name made from it, reported
  /// as TOA560; null, with the same report, when nothing can be made of it
  /// and the override is ignored.
  String? checkedOverrideName(
    OverrideEntry entry,
    String field,
    String? value,
    NameKind kind, {
    required String what,
  }) {
    if (value == null || _names.isValid(value, kind)) return value;
    final name = _names.sanitize(value, kind);
    reportAtOverride(
      .overrideNameInvalid,
      name == null
          ? 'The $field "$value" of this override is not a valid Dart $what '
                'name and has no ASCII letter or digit; the override is '
                'ignored.'
          : 'The $field "$value" of this override is not a valid Dart $what '
                'name; "$name" is used.',
      entry,
      field,
      fix: kind == .type
          ? 'Write an UpperCamelCase Dart identifier that does not start '
                'with an underscore.'
          : 'Write a lowerCamelCase Dart identifier that does not start with '
                'an underscore.',
    );
    return name;
  }

  /// Reports TOA559 at [at] when [name], made from the spec's [source], lost
  /// characters; [what] says what [source] names (`Property`). [override]
  /// is an override that names it.
  void checkLossyName(
    String source,
    String name,
    SpecLocation at, {
    required String what,
    String? override,
    String fix = 'Name it explicitly to keep the meaning.',
  }) {
    if (!_names.dropsLetters(source)) return;
    report(
      .nameLossy,
      '$what ${MessageText.quote(source)} lost characters when it became the '
      'Dart name '
      '"$name": letters outside ASCII are dropped.',
      at,
      fix: fix,
      override: override,
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
