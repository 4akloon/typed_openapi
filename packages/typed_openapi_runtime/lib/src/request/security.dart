/// The `type` of a security scheme.
enum SecuritySchemeType {
  /// An API key in a header, query parameter or cookie.
  apiKey,

  /// HTTP authentication, such as `bearer` or `basic`.
  http,

  /// Mutual TLS.
  mutualTls,

  /// OAuth 2.
  oauth2,

  /// OpenID Connect.
  openIdConnect,
}

/// Where an API key is sent.
enum SecurityLocation {
  /// A query parameter.
  query,

  /// A header.
  header,

  /// A cookie.
  cookie,
}

/// A security scheme of the spec (`components.securitySchemes`), as
/// metadata for interceptors: the generated client sends no credentials.
final class SecurityScheme {
  /// Describes the scheme [name] of [type].
  const SecurityScheme(
    this.name,
    this.type, {
    this.parameterName,
    this.location,
    this.scheme,
    this.bearerFormat,
    this.openIdConnectUrl,
  });

  /// The key of the scheme in `components.securitySchemes`.
  final String name;

  /// The type of the scheme.
  final SecuritySchemeType type;

  /// The header, query parameter or cookie name of an API key.
  final String? parameterName;

  /// Where an API key is sent.
  final SecurityLocation? location;

  /// The HTTP authentication scheme, such as `bearer`, in lower case.
  final String? scheme;

  /// How a bearer token is formatted, such as `JWT`.
  final String? bearerFormat;

  /// The OpenID Connect discovery URL.
  final String? openIdConnectUrl;

  @override
  String toString() => 'SecurityScheme($name, ${type.name})';
}

/// A security scheme an operation requires, with the scopes it needs.
final class SecurityUse {
  /// Requires [scheme] with [scopes].
  const SecurityUse(this.scheme, [this.scopes = const []]);

  /// The scheme.
  final SecurityScheme scheme;

  /// The OAuth 2 or OpenID Connect scopes, or the roles of other schemes.
  final List<String> scopes;

  @override
  String toString() =>
      scopes.isEmpty ? scheme.name : '${scheme.name} ${scopes.join(' ')}';
}
