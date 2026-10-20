import 'package:typed_openapi_core/typed_openapi_core.dart';

import 'diagnostic_source.dart';
import 'diagnostics_page.dart';
import 'docs_problems.dart';
import 'extensions_page.dart';

/// The files that are generated from the code, by their path under the
/// packages directory.
final class GeneratedDocs {
  /// Creates the docs from the doc comments that [source] reads.
  const GeneratedDocs(this.source);

  /// Where the doc comments of the diagnostic codes are read.
  final DiagnosticSource source;

  /// The diagnostics reference.
  static const diagnosticsPath = 'typed_openapi/doc/diagnostics.md';

  /// The extensions reference.
  static const extensionsPath = 'typed_openapi/doc/extensions.md';

  /// The JSON Schema of `typed_openapi.yaml`.
  static const configSchemaPath =
      'typed_openapi/schema/typed_openapi.schema.json';

  /// The JSON Schema of an overrides file.
  static const overridesSchemaPath =
      'typed_openapi/schema/typed_openapi.overrides.schema.json';

  /// The text of every file, by path.
  ///
  /// Throws [DocsProblems] when a doc comment breaks the convention.
  Map<String, String> files() {
    final read = source.read();
    if (read.problems.isNotEmpty) throw DocsProblems(read.problems);
    return {
      diagnosticsPath: DiagnosticsPage(read.docs).render(),
      extensionsPath: const ExtensionsPage(SpecExtensions.all).render(),
      configSchemaPath: const ConfigSchema().toText(),
      overridesSchemaPath: const OverrideSchema().toText(),
    };
  }
}
