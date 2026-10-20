import '../load/openapi_version.dart';

/// A construct that only some OpenAPI versions define.
///
/// The parser reads every construct whatever version a document declares and
/// notes the version-specific ones; `DialectChecker` then reports those the
/// declared version does not have.
enum SpecFeature {
  /// `type` written as a list.
  typeList('"type" as a list', since: .v31),

  /// `type: "null"`.
  nullType('type "null"', since: .v31),

  /// `const`.
  constKeyword('"const"', since: .v31),

  /// `prefixItems`.
  prefixItems('"prefixItems"', since: .v31),

  /// `examples` (a list) in a schema.
  schemaExamples('"examples" in a schema', since: .v31),

  /// `exclusiveMinimum` or `exclusiveMaximum` written as a number.
  numericExclusiveBound(
    'a numeric "exclusiveMinimum" or "exclusiveMaximum"',
    since: .v31,
  ),

  /// `true` or `false` as a schema, other than in `additionalProperties`.
  booleanSchema('a boolean schema', since: .v31),

  /// `contentMediaType`, `contentEncoding` or `contentSchema`.
  contentKeywords(
    '"contentMediaType", "contentEncoding" or "contentSchema"',
    since: .v31,
  ),

  /// A JSON Schema 2020-12 keyword the model keeps raw, such as `$defs`.
  jsonSchemaKeyword(
    r'a JSON Schema keyword such as "$defs" or "if"',
    since: .v31,
  ),

  /// `webhooks`.
  webhooks('"webhooks"', since: .v31),

  /// `jsonSchemaDialect`.
  jsonSchemaDialect('"jsonSchemaDialect"', since: .v31),

  /// `summary` in the Info Object.
  infoSummary('"summary" in "info"', since: .v31),

  /// `pathItems` in the Components Object.
  componentPathItems('"components/pathItems"', since: .v31),

  /// The `mutualTLS` security scheme type.
  mutualTls('the "mutualTLS" security scheme', since: .v31),

  /// `itemSchema` in a media type.
  itemSchema('"itemSchema"', since: .v32),

  /// `prefixEncoding` or `itemEncoding` in a media type.
  sequentialEncoding('"prefixEncoding" or "itemEncoding"', since: .v32),

  /// The `query` operation of a path item.
  queryOperation('the "query" operation', since: .v32),

  /// `additionalOperations` in a path item.
  additionalOperations('"additionalOperations"', since: .v32),

  /// A parameter with `in: querystring`.
  querystringParameter('"in: querystring"', since: .v32),

  /// `style: cookie`.
  cookieStyle('"style: cookie"', since: .v32),

  /// `summary`, `parent` or `kind` in a tag.
  tagHierarchy('"summary", "parent" or "kind" in a tag', since: .v32),

  /// `defaultMapping` in a discriminator.
  defaultMapping('"defaultMapping"', since: .v32),

  /// `mediaTypes` in the Components Object.
  componentMediaTypes('"components/mediaTypes"', since: .v32),

  /// A `$ref` in place of a Media Type Object.
  mediaTypeRef(r'a "$ref" to a media type', since: .v32),

  /// `$self` at the document root.
  self(r'"$self"', since: .v32),

  /// `summary` in a response.
  responseSummary('"summary" in a response', since: .v32),

  /// `name` in a server.
  serverName('"name" in a server', since: .v32),

  /// `dataValue` or `serializedValue` in an example.
  exampleValues('"dataValue" or "serializedValue"', since: .v32),

  /// `deprecated` or `oauth2MetadataUrl` in a security scheme.
  securitySchemeExtras(
    '"deprecated" or "oauth2MetadataUrl" in a security scheme',
    since: .v32,
  ),

  /// The `deviceAuthorization` OAuth flow.
  deviceAuthorization('the "deviceAuthorization" OAuth flow', since: .v32),

  /// `nullable`, which JSON Schema 2020-12 replaced with `type: "null"`.
  nullable('"nullable"', until: .v31);

  const SpecFeature(this.label, {this.since, this.until});

  /// How diagnostics name the construct.
  final String label;

  /// The first version that has the construct, or null for all.
  final OpenApiVersion? since;

  /// The first version that no longer has the construct, or null for none.
  final OpenApiVersion? until;
}
