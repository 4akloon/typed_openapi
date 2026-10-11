import '../load/openapi_version.dart';
import 'operation.dart';
import 'schema.dart';
import 'security.dart';
import 'spec_node.dart';

/// An OpenAPI document read into the typed model.
///
/// The model is a superset of OpenAPI 3.0, 3.1 and 3.2: it holds what any of
/// them can say, whatever [version] the document declares. Keys the model
/// does not type, such as `externalDocs` or `links`, stay in the
/// `SpecDocument` under the node's pointer.
final class OpenApiDocument extends SpecNode {
  /// Creates a document.
  const OpenApiDocument({
    required super.location,
    this.version,
    this.self,
    this.info,
    this.jsonSchemaDialect,
    this.servers = const [],
    this.paths = const {},
    this.webhooks = const {},
    this.components,
    this.security,
    this.tags = const [],
    super.extensions,
    super.unknownKeys,
  });

  /// The OpenAPI line the document declares, or null when unknown.
  final OpenApiVersion? version;

  /// `$self` (OpenAPI 3.2).
  final String? self;

  /// `info`; required by the spec.
  final Info? info;

  /// `jsonSchemaDialect` (OpenAPI 3.1).
  final String? jsonSchemaDialect;

  /// `servers`.
  final List<Server> servers;

  /// `paths` by path template, in document order; `x-` keys of the Paths
  /// Object are not included.
  final Map<String, RefOr<PathItem>> paths;

  /// `webhooks` (OpenAPI 3.1).
  final Map<String, RefOr<PathItem>> webhooks;

  /// `components`.
  final Components? components;

  /// `security`; null when the document does not set it.
  final List<SecurityRequirement>? security;

  /// `tags`.
  final List<Tag> tags;
}

/// An Info Object.
final class Info extends SpecNode {
  /// Creates an info object.
  const Info({
    required super.location,
    this.title,
    this.summary,
    this.description,
    this.version,
    super.extensions,
    super.unknownKeys,
  });

  /// `title`; required by the spec.
  final String? title;

  /// `summary` (OpenAPI 3.1).
  final String? summary;

  /// `description`.
  final String? description;

  /// `version` of the API (not of OpenAPI); required by the spec.
  final String? version;
}

/// A Tag Object.
final class Tag extends SpecNode {
  /// Creates a tag.
  const Tag({
    required super.location,
    this.name,
    this.summary,
    this.description,
    this.parent,
    this.kind,
    super.extensions,
    super.unknownKeys,
  });

  /// `name`; required by the spec.
  final String? name;

  /// `summary` (OpenAPI 3.2).
  final String? summary;

  /// `description`.
  final String? description;

  /// `parent` tag name (OpenAPI 3.2).
  final String? parent;

  /// `kind`, such as `nav` (OpenAPI 3.2).
  final String? kind;
}

/// A Components Object.
final class Components extends SpecNode {
  /// Creates the components.
  const Components({
    required super.location,
    this.schemas = const {},
    this.responses = const {},
    this.parameters = const {},
    this.examples = const {},
    this.requestBodies = const {},
    this.headers = const {},
    this.securitySchemes = const {},
    this.pathItems = const {},
    this.mediaTypes = const {},
    super.extensions,
    super.unknownKeys,
  });

  /// `schemas`.
  final Map<String, Schema> schemas;

  /// `responses`.
  final Map<String, RefOr<Response>> responses;

  /// `parameters`.
  final Map<String, RefOr<Parameter>> parameters;

  /// `examples`.
  final Map<String, RefOr<Example>> examples;

  /// `requestBodies`.
  final Map<String, RefOr<RequestBody>> requestBodies;

  /// `headers`.
  final Map<String, RefOr<Header>> headers;

  /// `securitySchemes`.
  final Map<String, RefOr<SecurityScheme>> securitySchemes;

  /// `pathItems` (OpenAPI 3.1).
  final Map<String, RefOr<PathItem>> pathItems;

  /// `mediaTypes` (OpenAPI 3.2).
  final Map<String, RefOr<MediaType>> mediaTypes;
}
