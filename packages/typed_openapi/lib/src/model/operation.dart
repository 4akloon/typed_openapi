import 'schema.dart';
import 'spec_node.dart';

/// A Path Item Object.
final class PathItem extends SpecNode {
  /// Creates a path item.
  const PathItem({
    required super.location,
    this.summary,
    this.description,
    this.operations = const {},
    this.additionalOperations = const {},
    this.servers = const [],
    this.parameters = const [],
    super.extensions,
    super.unknownKeys,
  });

  /// The fixed operation fields of a path item, in the order the spec lists
  /// them; `query` is OpenAPI 3.2.
  static const methods = [
    'get',
    'put',
    'post',
    'delete',
    'options',
    'head',
    'patch',
    'trace',
    'query',
  ];

  /// `summary`.
  final String? summary;

  /// `description`.
  final String? description;

  /// Operations by lowercase method from [methods], in the canonical order
  /// of [methods] (not document order).
  final Map<String, Operation> operations;

  /// `additionalOperations` (OpenAPI 3.2): operations by method, with the
  /// method's case as written.
  final Map<String, Operation> additionalOperations;

  /// `servers`.
  final List<Server> servers;

  /// `parameters` shared by every operation of the path.
  final List<RefOr<Parameter>> parameters;
}

/// An Operation Object.
final class Operation extends SpecNode {
  /// Creates an operation.
  const Operation({
    required super.location,
    this.tags = const [],
    this.summary,
    this.description,
    this.operationId,
    this.parameters = const [],
    this.requestBody,
    this.responses = const {},
    this.deprecated = false,
    this.security,
    this.servers = const [],
    super.extensions,
    super.unknownKeys,
  });

  /// `tags`.
  final List<String> tags;

  /// `summary`.
  final String? summary;

  /// `description`.
  final String? description;

  /// `operationId`.
  final String? operationId;

  /// `parameters`.
  final List<RefOr<Parameter>> parameters;

  /// `requestBody`.
  final RefOr<RequestBody>? requestBody;

  /// `responses` by status code, range (`2XX`) or `default`, in document
  /// order; `x-` keys of the Responses Object are not included.
  final Map<String, RefOr<Response>> responses;

  /// `deprecated`.
  final bool deprecated;

  /// `security`; null when the operation does not set it and inherits the
  /// document's.
  final List<SecurityRequirement>? security;

  /// `servers`.
  final List<Server> servers;
}

/// Where a parameter is sent: the `in` field.
enum ParameterLocation {
  /// A query parameter.
  query,

  /// The whole query string as one value (OpenAPI 3.2).
  querystring,

  /// A header.
  header,

  /// A path segment.
  path,

  /// A cookie.
  cookie,
}

/// How a parameter value is serialized: the `style` field.
enum ParameterStyle {
  /// `matrix`.
  matrix,

  /// `label`.
  label,

  /// `simple`.
  simple,

  /// `form`.
  form,

  /// `spaceDelimited`.
  spaceDelimited,

  /// `pipeDelimited`.
  pipeDelimited,

  /// `deepObject`.
  deepObject,

  /// `cookie` (OpenAPI 3.2).
  cookie,
}

/// A Parameter Object.
final class Parameter extends SpecNode {
  /// Creates a parameter.
  const Parameter({
    required super.location,
    this.name,
    this.placement,
    this.description,
    this.required = false,
    this.deprecated = false,
    this.allowEmptyValue = false,
    this.style,
    this.explode,
    this.allowReserved = false,
    this.schema,
    this.example,
    this.examples = const {},
    this.content = const {},
    super.extensions,
    super.unknownKeys,
  });

  /// `name`; required by the spec.
  final String? name;

  /// `in`; required by the spec.
  final ParameterLocation? placement;

  /// `description`.
  final String? description;

  /// `required`.
  final bool required;

  /// `deprecated`.
  final bool deprecated;

  /// `allowEmptyValue`.
  final bool allowEmptyValue;

  /// `style`.
  final ParameterStyle? style;

  /// `explode`; null when the spec leaves it to the style's default.
  final bool? explode;

  /// `allowReserved`.
  final bool allowReserved;

  /// `schema`.
  final Schema? schema;

  /// `example`.
  final (Object?,)? example;

  /// `examples`.
  final Map<String, RefOr<Example>> examples;

  /// `content`, used instead of [schema] for complex serialization.
  final Map<String, RefOr<MediaType>> content;
}

/// A Request Body Object.
final class RequestBody extends SpecNode {
  /// Creates a request body.
  const RequestBody({
    required super.location,
    this.description,
    this.content = const {},
    this.required = false,
    super.extensions,
    super.unknownKeys,
  });

  /// `description`.
  final String? description;

  /// `content` by media type, in document order.
  final Map<String, RefOr<MediaType>> content;

  /// `required`.
  final bool required;
}

/// A Response Object.
final class Response extends SpecNode {
  /// Creates a response.
  const Response({
    required super.location,
    this.summary,
    this.description,
    this.headers = const {},
    this.content = const {},
    super.extensions,
    super.unknownKeys,
  });

  /// `summary` (OpenAPI 3.2).
  final String? summary;

  /// `description`.
  final String? description;

  /// `headers`.
  final Map<String, RefOr<Header>> headers;

  /// `content` by media type, in document order.
  final Map<String, RefOr<MediaType>> content;
}

/// A Header Object.
final class Header extends SpecNode {
  /// Creates a header.
  const Header({
    required super.location,
    this.description,
    this.required = false,
    this.deprecated = false,
    this.style,
    this.explode,
    this.schema,
    this.example,
    this.examples = const {},
    this.content = const {},
    super.extensions,
    super.unknownKeys,
  });

  /// `description`.
  final String? description;

  /// `required`.
  final bool required;

  /// `deprecated`.
  final bool deprecated;

  /// `style`.
  final ParameterStyle? style;

  /// `explode`.
  final bool? explode;

  /// `schema`.
  final Schema? schema;

  /// `example`.
  final (Object?,)? example;

  /// `examples`.
  final Map<String, RefOr<Example>> examples;

  /// `content`.
  final Map<String, RefOr<MediaType>> content;
}

/// A Media Type Object.
final class MediaType extends SpecNode {
  /// Creates a media type.
  const MediaType({
    required super.location,
    this.schema,
    this.itemSchema,
    this.example,
    this.examples = const {},
    this.encoding = const {},
    this.prefixEncoding = const [],
    this.itemEncoding,
    super.extensions,
    super.unknownKeys,
  });

  /// `schema`.
  final Schema? schema;

  /// `itemSchema` (OpenAPI 3.2): the schema of each item of a sequential
  /// media type such as `text/event-stream`.
  final Schema? itemSchema;

  /// `example`.
  final (Object?,)? example;

  /// `examples`.
  final Map<String, RefOr<Example>> examples;

  /// `encoding` by property name.
  final Map<String, Encoding> encoding;

  /// `prefixEncoding` (OpenAPI 3.2).
  final List<Encoding> prefixEncoding;

  /// `itemEncoding` (OpenAPI 3.2).
  final Encoding? itemEncoding;
}

/// An Encoding Object.
final class Encoding extends SpecNode {
  /// Creates an encoding.
  const Encoding({
    required super.location,
    this.contentType,
    this.headers = const {},
    this.style,
    this.explode,
    this.allowReserved = false,
    super.extensions,
    super.unknownKeys,
  });

  /// `contentType`.
  final String? contentType;

  /// `headers`.
  final Map<String, RefOr<Header>> headers;

  /// `style`.
  final ParameterStyle? style;

  /// `explode`.
  final bool? explode;

  /// `allowReserved`.
  final bool allowReserved;
}

/// An Example Object.
final class Example extends SpecNode {
  /// Creates an example.
  const Example({
    required super.location,
    this.summary,
    this.description,
    this.value,
    this.dataValue,
    this.serializedValue,
    this.externalValue,
    super.extensions,
    super.unknownKeys,
  });

  /// `summary`.
  final String? summary;

  /// `description`.
  final String? description;

  /// `value`.
  final (Object?,)? value;

  /// `dataValue` (OpenAPI 3.2).
  final (Object?,)? dataValue;

  /// `serializedValue` (OpenAPI 3.2).
  final String? serializedValue;

  /// `externalValue`.
  final String? externalValue;
}

/// A Server Object.
final class Server extends SpecNode {
  /// Creates a server.
  const Server({
    required super.location,
    this.url,
    this.name,
    this.description,
    this.variables = const {},
    super.extensions,
    super.unknownKeys,
  });

  /// `url`, possibly with `{variables}`; required by the spec.
  final String? url;

  /// `name` (OpenAPI 3.2).
  final String? name;

  /// `description`.
  final String? description;

  /// `variables` by name.
  final Map<String, ServerVariable> variables;
}

/// A Server Variable Object.
final class ServerVariable extends SpecNode {
  /// Creates a server variable.
  const ServerVariable({
    required super.location,
    this.enumValues,
    this.defaultValue,
    this.description,
    super.extensions,
    super.unknownKeys,
  });

  /// `enum`.
  final List<String>? enumValues;

  /// `default`; required by the spec.
  final String? defaultValue;

  /// `description`.
  final String? description;
}

/// A Security Requirement Object: scheme names and the scopes each needs.
///
/// An empty requirement (`{}`) makes security optional.
final class SecurityRequirement extends SpecNode {
  /// Creates a requirement.
  const SecurityRequirement({required super.location, this.schemes = const {}});

  /// Scopes by security scheme name, in document order.
  final Map<String, List<String>> schemes;
}
