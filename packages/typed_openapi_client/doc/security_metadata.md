# Security metadata

A generated client **describes** the security of an operation and sends no
credentials. The spec's `security` requirements travel with every request as
metadata, so one interceptor on your `Dio` can add the right token, key or
signature for the operation being called. This guide covers the metadata
types and a working interceptor.

## Where it is

The runtime puts an `OperationInfo` into `RequestOptions.extra` under
`OperationInfo.extraKey` (`typed_openapi.operation`). Read it with
`OperationInfo.of(options)`, which is `null` for a request a generated client
did not send:

```dart
class AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final operation = OperationInfo.of(options);
    if (operation == null) return handler.next(options); // not a generated call
    print('${operation.operationId}: ${operation.security}');
    // ...
    handler.next(options);
  }
}
```

`OperationInfo` has:

| Field | Meaning |
| --- | --- |
| `operationId` | The spec's `operationId`, or the name the generator gave the operation |
| `method` | The HTTP method in upper case |
| `pathTemplate` | The path as the spec writes it (`/pets/{petId}`) |
| `tags` | The operation's tags, in spec order |
| `security` | A list of alternatives, each a list of `SecurityUse` |

`CallOptions.extra` entries are merged into the same `extra` map, so your
code can pass hints to the interceptor next to the operation.

## Reading `security`

`security` is the operation's own `security` or else the document's. Its shape
is OpenAPI's:

- **Any one alternative is enough**; **every scheme inside an alternative is
  needed**.
- An **empty alternative** (`[]` inside the list) makes security optional.
- **No alternatives** (`security` is empty) means no security.

For this spec:

```yaml
security:
  - bearerAuth: []                       # the default for every operation
paths:
  /me:      {get: {operationId: getMe, ...}}                 # inherits bearerAuth
  /health:  {get: {operationId: getHealth, security: [], ...}}   # open
  /reports:
    get:
      operationId: getReports
      security:
        - apiKey: []
        - oauth: [reports.read]          # a second alternative
components:
  securitySchemes:
    bearerAuth: {type: http, scheme: bearer, bearerFormat: JWT}
    apiKey: {type: apiKey, in: header, name: X-Api-Key}
    oauth: {type: oauth2, flows: {...}}
```

the generator writes (trimmed):

```dart
static const _getMe = OperationInfo(
  operationId: 'getMe', method: 'GET', pathTemplate: '/me', tags: ['account'],
  security: [
    [SecurityUse(SecurityScheme('bearerAuth', .http, scheme: 'bearer', bearerFormat: 'JWT'))],
  ],
);

static const _getHealth = OperationInfo(
  operationId: 'getHealth', method: 'GET', pathTemplate: '/health',
);

static const _getReports = OperationInfo(
  operationId: 'getReports', method: 'GET', pathTemplate: '/reports',
  security: [
    [SecurityUse(SecurityScheme('apiKey', .apiKey, parameterName: 'X-Api-Key', location: .header))],
    [SecurityUse(SecurityScheme('oauth', .oauth2), ['reports.read'])],
  ],
);
```

and an interceptor that prints what it sees gets:

```text
getMe: [[bearerAuth]]
getHealth: []
getReports: [[apiKey], [oauth reports.read]]
```

## The types

`SecurityUse(scheme, [scopes])` is a scheme an operation requires, with the
OAuth 2 or OpenID Connect scopes, or the roles of other schemes.

`SecurityScheme(name, type, {...})` is a scheme of `components.securitySchemes`:

| Field | Meaning |
| --- | --- |
| `name` | The key in `components.securitySchemes` |
| `type` | A `SecuritySchemeType` |
| `parameterName` | The header, query parameter or cookie name of an API key |
| `location` | A `SecurityLocation` (`query`, `header`, `cookie`) for an API key |
| `scheme` | The HTTP authentication scheme in lower case (`bearer`, `basic`) |
| `bearerFormat` | How a bearer token is formatted (`JWT`) |
| `openIdConnectUrl` | The OpenID Connect discovery URL |

| `SecuritySchemeType` | Spec `type` |
| --- | --- |
| `apiKey` | An API key in a header, query parameter or cookie |
| `http` | HTTP authentication, such as `bearer` or `basic` |
| `mutualTls` | Mutual TLS |
| `oauth2` | OAuth 2 |
| `openIdConnect` | OpenID Connect |
| `unknown` | A scheme the spec names but does not define |

### `unknown`

A requirement can name a scheme that `components.securitySchemes` does not
define, or one that is malformed. The generator reports it and keeps the
requirement with `SecuritySchemeType.unknown`, so the metadata never says
less than the spec: **an operation is never read as open or as optional**
because a scheme was unreadable. An interceptor must treat `unknown` as "this
operation needs something I cannot supply" and not skip it:

```dart
const op = OperationInfo(
  operationId: 'x', method: 'GET', pathTemplate: '/x',
  security: [[SecurityUse(SecurityScheme('legacy', .unknown))]],
);
```

## An example interceptor

This interceptor adds a bearer token or an API key when an alternative can be
satisfied and rejects the request otherwise:

```dart
class AuthInterceptor extends Interceptor {
  AuthInterceptor({this.bearerToken, this.apiKey});

  final String? bearerToken;
  final String? apiKey;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final operation = OperationInfo.of(options);
    if (operation == null) return handler.next(options);

    final alternatives = operation.security;
    if (alternatives.isEmpty) return handler.next(options);      // open
    for (final alternative in alternatives) {
      if (alternative.isEmpty) return handler.next(options);     // optional
      if (alternative.every(_canSatisfy)) {
        alternative.forEach((use) => _apply(use, options));
        return handler.next(options);
      }
    }
    handler.reject(
      DioException(
        requestOptions: options,
        message: 'No credentials for ${operation.operationId}: $alternatives',
      ),
    );
  }

  bool _canSatisfy(SecurityUse use) => switch (use.scheme.type) {
    SecuritySchemeType.http when use.scheme.scheme == 'bearer' => bearerToken != null,
    SecuritySchemeType.apiKey => apiKey != null,
    _ => false, // oauth2, mutualTls, openIdConnect, unknown: not handled here
  };

  void _apply(SecurityUse use, RequestOptions options) {
    switch (use.scheme) {
      case SecurityScheme(type: .http, scheme: 'bearer'):
        options.headers['Authorization'] = 'Bearer $bearerToken';
      case SecurityScheme(type: .apiKey, :final parameterName?, location: .header):
        options.headers[parameterName] = apiKey;
      default:
    }
  }
}
```

Run against the generated `getMe`, `getHealth` and `getReports` with an
in-memory adapter:

```text
await api.account.getMe()            -> Success(200), Authorization: Bearer tkn
await api.defaultApi.getHealth()     -> Success(200), no Authorization (open)
await api.defaultApi.getReports()    -> TransportError (no apiKey, and oauth is not handled)
with AuthInterceptor(apiKey: 'k1')   -> getReports sends X-Api-Key: k1
```

> **Note:** A request that an interceptor rejects with `handler.reject` comes
> back as a `TransportError`, like any other failure without a response. Match
> on `exception.message` if you want to tell your own rejection apart.

## Limits

- The metadata is **descriptive**. The runtime and the generated client never
  read a token, refresh one or retry on `401`; that is interceptor work, which
  keeps the policy in your hands.
- Cookie API keys do not work in a browser
  ([Web and platforms](web_and_platforms.md#cookies)).
- OAuth flows, token URLs and scope descriptions are not carried; only the
  scheme, its type-specific fields and the scopes the operation needs.

## See also

- [Getting started](getting_started.md) - `CallOptions.extra`, interceptors.
- [Results and errors](results_and_errors.md) - how a rejection surfaces.
- How the generator builds security requirements:
  [generated security](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/security.md).
