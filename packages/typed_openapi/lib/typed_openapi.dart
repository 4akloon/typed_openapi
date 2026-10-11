/// OpenAPI 3.x to Dart client generator.
///
/// The programmatic API mirrors the CLI: load a config, check specs, report
/// diagnostics.
library;

export 'src/check/spec_checker.dart' show SpecChecker;
export 'src/cli/cli.dart' show TypedOpenApiCli;
export 'src/config/config_loader.dart' show ConfigLoader;
export 'src/config/project_config.dart'
    show ClientConfig, Preset, ProjectConfig;
export 'src/diagnostics/diagnostic.dart' show Diagnostic;
export 'src/diagnostics/diagnostic_bag.dart' show DiagnosticBag;
export 'src/diagnostics/diagnostic_code.dart' show DiagnosticCode;
export 'src/diagnostics/json_pointer.dart' show JsonPointer;
export 'src/diagnostics/reporters.dart'
    show DiagnosticReporter, JsonReporter, ReportFormat, TextReporter;
export 'src/diagnostics/severity.dart' show Severity;
export 'src/load/openapi_version.dart'
    show OpenApiVersion, OpenApiVersionDetector;
export 'src/load/spec_document.dart' show SpecDocument;
export 'src/load/spec_loader.dart' show SpecLoader;
