import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/json_pointer.dart';
import '../load/openapi_version.dart';
import '../load/spec_document.dart';
import '../model/document.dart';
import '../model/security.dart';
import '../model/spec_node.dart';
import 'object_reader.dart';
import 'operation_parser.dart';
import 'parse_context.dart';
import 'schema_parser.dart';
import 'spec_feature.dart';

/// Reads a [SpecDocument] into the typed model.
///
/// Wrong JSON types, missing required fields and unknown keys are reported
/// to the [DiagnosticBag] and the rest of the document is still read. Every
/// node, `$ref` and version-specific construct goes into the [SpecIndex]
/// given to the constructor, which several parsers of one run share.
final class OpenApiParser {
  /// Creates a parser for [document].
  factory OpenApiParser(
    DiagnosticBag diagnostics,
    SpecDocument document,
    SpecIndex index,
  ) {
    final context = ParseContext(diagnostics, document, index);
    final schemas = SchemaParser(context);
    return OpenApiParser._(
      context,
      schemas,
      OperationParser(context, schemas),
    );
  }

  OpenApiParser._(this._context, this._schemas, this._operations);

  final ParseContext _context;
  final SchemaParser _schemas;
  final OperationParser _operations;

  /// Reads the whole document, which declares [version].
  OpenApiDocument parse(OpenApiVersion? version) {
    final r = ObjectReader(_context, _context.document.root, .root);
    final at = r.pointer;
    r.accept(const ['openapi', 'externalDocs']);
    if (r.has(r'$self')) {
      _context.note(.self, at.child(r'$self'));
      _context.report(
        .refBaseIgnored,
        r'"$self" changes the base URI of "$ref"s; they are resolved '
        'against the file location instead.',
        at.child(r'$self'),
      );
    }
    for (final (key, feature) in const [
      ('jsonSchemaDialect', SpecFeature.jsonSchemaDialect),
      ('webhooks', SpecFeature.webhooks),
    ]) {
      if (r.has(key)) _context.note(feature, at.child(key));
    }
    return _context.register(
      OpenApiDocument(
        location: r.location,
        version: version,
        self: r.string(r'$self'),
        info: r.requiredObject('info', _info),
        jsonSchemaDialect: r.string('jsonSchemaDialect'),
        servers: r.list('servers', _operations.server) ?? const [],
        paths:
            r.map('paths', _operations.pathItem, skipExtensions: true) ??
            const {},
        webhooks: r.map('webhooks', _operations.pathItem) ?? const {},
        components: r.object('components', _components),
        security: _operations.securityRequirements(r),
        tags: r.list('tags', _tag) ?? const [],
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  /// Reads the node at [pointer] as a [kind] node, for a `$ref` that points
  /// there; null after reporting when the node has the wrong shape.
  SpecNode? parseFragment(JsonPointer pointer, RefKind kind) {
    final raw = _context.document.valueAt(pointer)?.$1;
    final RefOr<SpecNode>? node = switch (kind) {
      .schema => null,
      .response => _operations.response(raw, pointer),
      .parameter => _operations.parameter(raw, pointer),
      .example => _operations.example(raw, pointer),
      .requestBody => _operations.requestBody(raw, pointer),
      .header => _operations.header(raw, pointer),
      .securityScheme => _securityScheme(raw, pointer),
      .pathItem => _operations.pathItem(raw, pointer),
      .mediaType => _operations.mediaType(raw, pointer),
    };
    return switch (node) {
      Ref() => node,
      Inline(:final value) => value,
      null => kind == .schema ? _schemas.parse(raw, pointer) : null,
    };
  }

  Info _info(ObjectReader r) {
    if (r.has('summary')) {
      _context.note(.infoSummary, r.pointer.child('summary'));
    }
    r.accept(const ['termsOfService', 'contact', 'license']);
    return _context.register(
      Info(
        location: r.location,
        title: r.requiredString('title'),
        summary: r.string('summary'),
        description: r.string('description'),
        version: r.requiredString('version'),
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  Tag? _tag(Object? raw, JsonPointer pointer) =>
      _context.node(raw, pointer, 'A tag', _tagNode);

  Tag _tagNode(ObjectReader r) {
    for (final key in const ['summary', 'parent', 'kind']) {
      if (r.has(key)) _context.note(.tagHierarchy, r.pointer.child(key));
    }
    r.accept(const ['externalDocs']);
    return _context.register(
      Tag(
        location: r.location,
        name: r.requiredString('name'),
        summary: r.string('summary'),
        description: r.string('description'),
        parent: r.string('parent'),
        kind: r.string('kind'),
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  Components _components(ObjectReader r) {
    for (final (key, feature) in const [
      ('pathItems', SpecFeature.componentPathItems),
      ('mediaTypes', SpecFeature.componentMediaTypes),
    ]) {
      if (r.has(key)) _context.note(feature, r.pointer.child(key));
    }
    r.accept(const ['links', 'callbacks']);
    return _context.register(
      Components(
        location: r.location,
        schemas: r.map('schemas', _schemas.parse) ?? const {},
        responses: r.map('responses', _operations.response) ?? const {},
        parameters: r.map('parameters', _operations.parameter) ?? const {},
        examples: r.map('examples', _operations.example) ?? const {},
        requestBodies:
            r.map('requestBodies', _operations.requestBody) ?? const {},
        headers: r.map('headers', _operations.header) ?? const {},
        securitySchemes: r.map('securitySchemes', _securityScheme) ?? const {},
        pathItems: r.map('pathItems', _operations.pathItem) ?? const {},
        mediaTypes: r.map('mediaTypes', _operations.mediaType) ?? const {},
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  RefOr<SecurityScheme>? _securityScheme(Object? raw, JsonPointer pointer) =>
      _context.refOr(raw, pointer, .securityScheme, (r) {
        final type = r.requiredChoice(
          'type',
          SecuritySchemeType.values.asNameMap(),
        );
        if (type == .mutualTLS) {
          _context.note(.mutualTls, r.pointer.child('type'));
        }
        for (final key in const ['deprecated', 'oauth2MetadataUrl']) {
          if (r.has(key)) {
            _context.note(.securitySchemeExtras, r.pointer.child(key));
          }
        }
        String? field(String key, SecuritySchemeType requiredFor) =>
            type == requiredFor ? r.requiredString(key) : r.string(key);
        return _context.register(
          SecurityScheme(
            location: r.location,
            type: type,
            description: r.string('description'),
            name: field('name', .apiKey),
            placement: type == .apiKey
                ? r.requiredChoice('in', ApiKeyLocation.values.asNameMap())
                : r.choice('in', ApiKeyLocation.values.asNameMap()),
            scheme: field('scheme', .http),
            bearerFormat: r.string('bearerFormat'),
            flows: type == .oauth2
                ? r.requiredObject('flows', _flows)
                : r.object('flows', _flows),
            openIdConnectUrl: field('openIdConnectUrl', .openIdConnect),
            oauth2MetadataUrl: r.string('oauth2MetadataUrl'),
            deprecated: r.boolean('deprecated') ?? false,
            extensions: r.extensions,
            unknownKeys: r.unknownKeys(),
          ),
        );
      });

  OAuthFlows _flows(ObjectReader r) {
    if (r.has('deviceAuthorization')) {
      _context.note(
        .deviceAuthorization,
        r.pointer.child('deviceAuthorization'),
      );
    }
    return _context.register(
      OAuthFlows(
        location: r.location,
        implicit: r.object('implicit', _flow),
        password: r.object('password', _flow),
        clientCredentials: r.object('clientCredentials', _flow),
        authorizationCode: r.object('authorizationCode', _flow),
        deviceAuthorization: r.object('deviceAuthorization', _flow),
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  OAuthFlow _flow(ObjectReader r) => _context.register(
    OAuthFlow(
      location: r.location,
      authorizationUrl: r.string('authorizationUrl'),
      deviceAuthorizationUrl: r.string('deviceAuthorizationUrl'),
      tokenUrl: r.string('tokenUrl'),
      refreshUrl: r.string('refreshUrl'),
      scopes: r.stringMap('scopes') ?? const {},
      extensions: r.extensions,
      unknownKeys: r.unknownKeys(),
    ),
  );
}
