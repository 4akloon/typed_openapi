/// OpenAPI 3.x to Dart client generator.
///
/// The programmatic API mirrors the CLI: load a config, check specs, report
/// diagnostics. [SpecReader] reads a loaded spec into the typed model
/// ([SpecModel]) with its `$ref`s resolved; [OverrideLoader] reads a
/// client's overrides file; [Normalizer] applies its spec fields, runs the
/// named rules over the spec and applies their fixes.
library;

export 'src/check/spec_checker.dart' show SpecChecker;
export 'src/cli/cli.dart' show TypedOpenApiCli;
export 'src/config/config_loader.dart' show ConfigLoader;
export 'src/config/project_config.dart'
    show ClientConfig, Preset, ProjectConfig;
export 'src/diagnostics/diagnostic.dart' show Diagnostic, RelatedLocation;
export 'src/diagnostics/diagnostic_bag.dart' show DiagnosticBag;
export 'src/diagnostics/diagnostic_code.dart' show DiagnosticCode;
export 'src/diagnostics/github_actions_reporter.dart'
    show GitHubActionsReporter;
export 'src/diagnostics/json_pointer.dart' show JsonPointer;
export 'src/diagnostics/reporters.dart'
    show DiagnosticReporter, JsonReporter, ReportFormat, TextReporter;
export 'src/diagnostics/sarif_reporter.dart' show SarifReporter;
export 'src/diagnostics/severity.dart' show Severity;
export 'src/load/openapi_version.dart'
    show OpenApiVersion, OpenApiVersionDetector;
export 'src/load/spec_document.dart' show SpecDocument;
export 'src/load/spec_loader.dart' show SpecLoader;
export 'src/model/document.dart' show Components, Info, OpenApiDocument, Tag;
export 'src/model/operation.dart'
    show
        Encoding,
        Example,
        Header,
        MediaType,
        Operation,
        Parameter,
        ParameterLocation,
        ParameterStyle,
        PathItem,
        RequestBody,
        Response,
        SecurityRequirement,
        Server,
        ServerVariable;
export 'src/model/schema.dart'
    show BooleanSchema, Discriminator, Schema, SchemaObject, SchemaType;
export 'src/model/security.dart'
    show
        ApiKeyLocation,
        OAuthFlow,
        OAuthFlows,
        SecurityScheme,
        SecuritySchemeType;
export 'src/model/spec_node.dart'
    show Inline, Ref, RefKind, RefOr, SpecLocation, SpecNode;
export 'src/normalize/normalizer.dart' show NormalizedSpec, Normalizer;
export 'src/normalize/normalizer_rule.dart'
    show Finding, NormalizerRule, RuleContext;
export 'src/normalize/spec_edit.dart' show EditOperation, SpecEdit;
export 'src/overrides/override_loader.dart' show OverrideLoader;
export 'src/overrides/override_set.dart'
    show
        BodyOverride,
        DartTypeOverride,
        OperationOverride,
        OverrideEntry,
        OverrideSet,
        ParameterOverride,
        PropertyOverride,
        ResponseOverride,
        SchemaOverride;
export 'src/resolve/spec_documents.dart' show SpecDocuments;
export 'src/resolve/spec_model.dart' show SpecModel;
export 'src/resolve/spec_reader.dart' show SpecReader;
