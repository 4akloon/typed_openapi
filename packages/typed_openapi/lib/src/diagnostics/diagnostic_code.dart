import 'severity.dart';

/// The catalog of diagnostic codes.
///
/// An [id] is stable: once released it never changes meaning.
enum DiagnosticCode {
  /// The document is not valid JSON or YAML.
  parseError('TOA001', 'parse-error', .error),

  /// A mapping repeats a key.
  duplicateKey('TOA002', 'duplicate-key', .warning),

  /// The document root is not an object.
  rootNotObject('TOA003', 'root-not-object', .error),

  /// The input file does not exist.
  inputNotFound('TOA004', 'input-not-found', .error),

  /// Source positions could not be recorded for a document.
  positionsUnavailable('TOA005', 'positions-unavailable', .info),

  /// The input file exists but cannot be read as UTF-8 text.
  inputUnreadable('TOA006', 'input-unreadable', .error),

  /// The document nests deeper than the parser can follow.
  nestingTooDeep('TOA007', 'nesting-too-deep', .error),

  /// The document has no `openapi` field.
  missingOpenApiVersion('TOA010', 'missing-openapi-version', .error),

  /// The document declares a version this tool does not read.
  unsupportedOpenApiVersion(
    'TOA011',
    'unsupported-openapi-version',
    .error,
  ),

  /// The document declares a 3.x minor version newer than 3.2.
  unknownOpenApiMinorVersion(
    'TOA012',
    'unknown-openapi-minor-version',
    .warning,
  ),

  /// The `openapi` field is not a string, so YAML may have changed it (3.10
  /// reads as 3.1).
  openApiVersionNotString(
    'TOA013',
    'openapi-version-not-string',
    .warning,
  ),

  /// `$id` or `$self` would change the base URI of `$ref`s; this tool
  /// resolves them against the file location instead.
  refBaseIgnored('TOA105', 'ref-base-ignored', .warning),

  /// An object has a key that no OpenAPI version defines; it is ignored.
  unknownKey('TOA110', 'unknown-key', .warning),

  /// A field has the wrong JSON type or a value the spec does not allow; it
  /// is ignored.
  invalidValue('TOA111', 'invalid-value', .warning),

  /// A field the spec requires is missing.
  missingRequiredField('TOA112', 'missing-required-field', .warning),

  /// The configuration file does not exist.
  configNotFound('TOA901', 'config-not-found', .error),

  /// The configuration file is malformed or has an invalid value.
  configInvalid('TOA902', 'config-invalid', .error),

  /// The configuration file has a key this tool does not know.
  configUnknownKey('TOA903', 'config-unknown-key', .warning),

  /// Two clients write to the same or nested output directories.
  outputOverlap('TOA904', 'output-overlap', .error);

  const DiagnosticCode(this.id, this.slug, this.defaultSeverity);

  /// The stable id, such as `TOA001`.
  final String id;

  /// The human-readable name, such as `parse-error`.
  final String slug;

  /// The severity used unless configuration overrides it.
  final Severity defaultSeverity;
}
