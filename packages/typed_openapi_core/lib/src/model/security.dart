import 'spec_node.dart';

/// The `type` of a security scheme.
enum SecuritySchemeType {
  /// An API key in a header, query parameter or cookie.
  apiKey,

  /// HTTP authentication, such as `bearer` or `basic`.
  http,

  /// Mutual TLS (OpenAPI 3.1).
  mutualTLS,

  /// OAuth 2.
  oauth2,

  /// OpenID Connect discovery.
  openIdConnect,
}

/// Where an API key is sent: the `in` field of an `apiKey` scheme.
enum ApiKeyLocation {
  /// A query parameter.
  query,

  /// A header.
  header,

  /// A cookie.
  cookie,
}

/// A Security Scheme Object.
final class SecurityScheme extends SpecNode {
  /// Creates a security scheme.
  const SecurityScheme({
    required super.location,
    this.type,
    this.description,
    this.name,
    this.placement,
    this.scheme,
    this.bearerFormat,
    this.flows,
    this.openIdConnectUrl,
    this.oauth2MetadataUrl,
    this.deprecated = false,
    super.extensions,
    super.unknownKeys,
  });

  /// `type`; required by the spec.
  final SecuritySchemeType? type;

  /// `description`.
  final String? description;

  /// `name` of the header, query parameter or cookie of an `apiKey`.
  final String? name;

  /// `in` of an `apiKey`.
  final ApiKeyLocation? placement;

  /// `scheme` of `http`, such as `bearer`.
  final String? scheme;

  /// `bearerFormat`.
  final String? bearerFormat;

  /// `flows` of `oauth2`.
  final OAuthFlows? flows;

  /// `openIdConnectUrl`.
  final String? openIdConnectUrl;

  /// `oauth2MetadataUrl` (OpenAPI 3.2).
  final String? oauth2MetadataUrl;

  /// `deprecated` (OpenAPI 3.2).
  final bool deprecated;
}

/// An OAuth Flows Object.
final class OAuthFlows extends SpecNode {
  /// Creates the flows.
  const OAuthFlows({
    required super.location,
    this.implicit,
    this.password,
    this.clientCredentials,
    this.authorizationCode,
    this.deviceAuthorization,
    super.extensions,
    super.unknownKeys,
  });

  /// `implicit`.
  final OAuthFlow? implicit;

  /// `password`.
  final OAuthFlow? password;

  /// `clientCredentials`.
  final OAuthFlow? clientCredentials;

  /// `authorizationCode`.
  final OAuthFlow? authorizationCode;

  /// `deviceAuthorization` (OpenAPI 3.2).
  final OAuthFlow? deviceAuthorization;
}

/// An OAuth Flow Object.
final class OAuthFlow extends SpecNode {
  /// Creates a flow.
  const OAuthFlow({
    required super.location,
    this.authorizationUrl,
    this.deviceAuthorizationUrl,
    this.tokenUrl,
    this.refreshUrl,
    this.scopes = const {},
    super.extensions,
    super.unknownKeys,
  });

  /// `authorizationUrl`.
  final String? authorizationUrl;

  /// `deviceAuthorizationUrl` (OpenAPI 3.2).
  final String? deviceAuthorizationUrl;

  /// `tokenUrl`.
  final String? tokenUrl;

  /// `refreshUrl`.
  final String? refreshUrl;

  /// `scopes`: scope name to description.
  final Map<String, String> scopes;
}
