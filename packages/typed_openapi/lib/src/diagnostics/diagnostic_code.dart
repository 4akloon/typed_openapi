import 'severity.dart';

/// The catalog of diagnostic codes.
///
/// An [id] is stable: once released it never changes meaning.
enum DiagnosticCode {
  /// The document is not valid JSON or YAML.
  parseError('TOA001', 'parse-error', Severity.error),

  /// A mapping repeats a key.
  duplicateKey('TOA002', 'duplicate-key', Severity.warning),

  /// The document root is not an object.
  rootNotObject('TOA003', 'root-not-object', Severity.error),

  /// The input file does not exist.
  inputNotFound('TOA004', 'input-not-found', Severity.error),

  /// Source positions could not be recorded for a document.
  positionsUnavailable('TOA005', 'positions-unavailable', Severity.info),

  /// The document has no `openapi` field.
  missingOpenApiVersion('TOA010', 'missing-openapi-version', Severity.error),

  /// The document declares a version this tool does not read.
  unsupportedOpenApiVersion(
    'TOA011',
    'unsupported-openapi-version',
    Severity.error,
  ),

  /// The document declares a 3.x minor version newer than 3.2.
  unknownOpenApiMinorVersion(
    'TOA012',
    'unknown-openapi-minor-version',
    Severity.warning,
  ),

  /// The configuration file does not exist.
  configNotFound('TOA901', 'config-not-found', Severity.error),

  /// The configuration file is malformed or has an invalid value.
  configInvalid('TOA902', 'config-invalid', Severity.error),

  /// The configuration file has a key this tool does not know.
  configUnknownKey('TOA903', 'config-unknown-key', Severity.warning),

  /// Two clients write to the same or nested output directories.
  outputOverlap('TOA904', 'output-overlap', Severity.error);

  const DiagnosticCode(this.id, this.slug, this.defaultSeverity);

  /// The stable id, such as `TOA001`.
  final String id;

  /// The human-readable name, such as `parse-error`.
  final String slug;

  /// The severity used unless configuration overrides it.
  final Severity defaultSeverity;
}
