# Security

A generated client describes the security of every operation and sends no credentials. The `securitySchemes` of the spec become metadata on each request, and you decide, in a Dio interceptor, which secret goes where. This guide shows the metadata, what each kind of scheme looks like, and a complete interceptor.

> **Note:** The generator never reads or writes a token, key or password, and the client never sets an `Authorization` header by itself. If you do nothing, requests go out without credentials.

## What is generated

Every group class declares a private `OperationInfo` per operation. For an operation with security, the info lists it. This spec (a trimmed version of the one used for this guide) has a document-level default, an operation that turns it off, two alternatives, an optional one and a scheme that is not defined:

```yaml
openapi: 3.0.3
info: {title: Vault, version: "1"}
security:
  - bearer: []
paths:
  /health:
    get: {operationId: health, tags: [public], security: [], responses: {"200": {description: ok}}}
  /items/{id}:
    delete:
      operationId: deleteItem
      tags: [items]
      security:
        - oauth: [items:write, items:delete]
        - apiKey: []
          signature: []
      # ...
  /me:
    get:
      operationId: me
      security:
        - {}
        - bearer: []
      # ...
  /legacy:
    get:
      operationId: legacy
      security:
        - basicAuth: []      # not in components.securitySchemes
      # ...
components:
  securitySchemes:
    bearer: {type: http, scheme: Bearer, bearerFormat: JWT}
    apiKey: {type: apiKey, in: header, name: X-Api-Key}
    signature: {type: apiKey, in: query, name: sig}
    oauth:
      type: oauth2
      flows:
        clientCredentials: {tokenUrl: 'https://auth.example.com/token', scopes: {'items:write': write, 'items:delete': delete}}
```

`typed_openapi generate` writes this (real output, trimmed to the infos):

```dart
static const _deleteItem = OperationInfo(
  operationId: 'deleteItem',
  method: 'DELETE',
  pathTemplate: '/items/{id}',
  tags: ['items'],
  security: [
    [
      SecurityUse(SecurityScheme('oauth', .oauth2), ['items:write', 'items:delete']),
    ],
    [
      SecurityUse(SecurityScheme('apiKey', .apiKey, parameterName: 'X-Api-Key', location: .header)),
      SecurityUse(SecurityScheme('signature', .apiKey, parameterName: 'sig', location: .query)),
    ],
  ],
);

static const _listItems = OperationInfo(
  // ...
  security: [
    [
      SecurityUse(SecurityScheme('bearer', .http, scheme: 'bearer', bearerFormat: 'JWT')),
    ],
  ],
);

static const _me = OperationInfo(
  // ...
  security: [
    [],
    [
      SecurityUse(SecurityScheme('bearer', .http, scheme: 'bearer', bearerFormat: 'JWT')),
    ],
  ],
);

static const _legacy = OperationInfo(
  // ...
  security: [
    [SecurityUse(SecurityScheme('basicAuth', .unknown))],
  ],
);
```

`/health` has `security: []` and its `OperationInfo` has no `security` argument at all. `/items` (no `security` of its own) inherits the document's `bearer`. The runtime types are `OperationInfo`, `SecurityUse` and `SecurityScheme`, documented in the runtime guide [Security metadata](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/security_metadata.md).

## Reading the list

`OperationInfo.security` is a list of alternatives, each a list of `SecurityUse`:

| Shape | Meaning |
| --- | --- |
| Empty list (the argument is absent) | No security: the operation is open. |
| `[[A]]` | `A` is required. |
| `[[A], [B]]` | Either `A` or `B` is enough (OR). |
| `[[A, B]]` | Both `A` and `B` are needed (AND). |
| `[[], [A]]` | Security is optional: an empty alternative is `{}` in the spec. |

An operation's own `security` replaces the document's; it does not add to it. Scopes (`oauth: [items:write]`) are in `SecurityUse.scopes`; for schemes that have no scopes, the list holds roles if the spec writes any.

## Scheme kinds

`SecurityScheme.type` is one of:

| `type` | From the spec | Other fields set |
| --- | --- | --- |
| `.http` | `type: http` | `scheme` (lower case: `bearer`, `basic`), `bearerFormat` |
| `.apiKey` | `type: apiKey` | `parameterName` (the header, query parameter or cookie name) and `location` (`.header`, `.query`, `.cookie`) |
| `.oauth2` | `type: oauth2` | none: the flows, URLs and scope descriptions are not carried |
| `.openIdConnect` | `type: openIdConnect` | `openIdConnectUrl` |
| `.mutualTls` | `type: mutualTLS` | none |
| `.unknown` | a name the spec uses but does not define, or defines without a usable type | none |

### Unknown schemes (TOA568)

A requirement that names a scheme which `components.securitySchemes` does not define, a scheme without a usable `type`, or a requirement that is not an object, is reported as `TOA568` (warning):

```text
warning TOA568 security-scheme-unknown: The security requirement names "basicAuth", which components.securitySchemes does not define; the metadata has it as an unknown scheme, so the operation is not read as open.
  --> spec.yaml:48:11
  at #/paths/~1legacy/get/security/0
  fix: Define the scheme at the source, or fix its name.
```

The alternative is left out of the metadata when another alternative can be described. When none can, every alternative stays, with `SecuritySchemeType.unknown`, so the metadata never says less than the spec: an operation that required something never reads as open or as optional. Treat `.unknown` as "credentials are needed but I do not know which". Fix the name at the source, or define the scheme.

## An interceptor that applies the metadata

Dio interceptors see the metadata through `DioTransport.operationOf(options)`, which returns `null` for a request that `DioTransport` did not send. The interceptor below picks the first alternative whose schemes it has secrets for, sets the headers or query parameter, and rejects the request when it cannot satisfy any alternative. It was run against the generated `vault` client above with a fake Dio adapter (output follows the code).

```dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';
import 'package:typed_openapi_dio/typed_openapi_dio.dart';

/// Thrown (inside a `DioException`, so the call returns `TransportError`)
/// when no alternative of an operation's security can be satisfied.
class MissingCredentials implements Exception {
  MissingCredentials(this.message);

  final String message;

  @override
  String toString() => 'MissingCredentials: $message';
}

/// Adds the credentials an operation's `security` metadata asks for.
///
/// [secrets] holds one secret per scheme name of `components.securitySchemes`:
/// a token, an API key, or `user:password` for HTTP basic.
class SecurityInterceptor extends Interceptor {
  SecurityInterceptor(this.secrets);

  final Map<String, String> secrets;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final info = DioTransport.operationOf(options);
    final alternatives = info?.security ?? const <List<SecurityUse>>[];
    if (alternatives.isEmpty) return handler.next(options); // open operation

    // Any one alternative is enough; its schemes are all needed. An empty
    // alternative means "no credentials", so credentials are used when we
    // have them and the request goes without when we do not.
    final tried = [
      ...alternatives.where((alternative) => alternative.isNotEmpty),
      ...alternatives.where((alternative) => alternative.isEmpty),
    ];
    for (final alternative in tried) {
      if (alternative.every(_canApply)) {
        for (final use in alternative) {
          _apply(options, use.scheme);
        }
        return handler.next(options);
      }
    }
    handler.reject(
      DioException(
        requestOptions: options,
        error: MissingCredentials('$info needs one of $alternatives'),
      ),
    );
  }

  bool _canApply(SecurityUse use) {
    final scheme = use.scheme;
    if (!secrets.containsKey(scheme.name)) return false;
    return switch (scheme.type) {
      .http || .oauth2 || .openIdConnect => true,
      .apiKey => scheme.location != null && scheme.parameterName != null,
      .mutualTls || .unknown => false, // the transport must handle it
    };
  }

  void _apply(RequestOptions options, SecurityScheme scheme) {
    final secret = secrets[scheme.name]!;
    switch (scheme.type) {
      case .http when scheme.scheme == 'basic':
        options.headers['Authorization'] =
            'Basic ${base64Encode(utf8.encode(secret))}';
      case .http || .oauth2 || .openIdConnect:
        options.headers['Authorization'] = 'Bearer $secret';
      case .apiKey:
        final name = scheme.parameterName!;
        switch (scheme.location!) {
          case .header:
            options.headers[name] = secret;
          case .query:
            options.queryParameters[name] = secret;
          case .cookie:
            // Browsers drop a script's Cookie header; this works on the VM.
            final existing = options.headers['Cookie'];
            options.headers['Cookie'] =
                '${existing == null ? '' : '$existing; '}$name=$secret';
        }
      case .mutualTls || .unknown:
        break;
    }
  }
}
```

Use it like this:

```dart
final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
  ..interceptors.add(
    SecurityInterceptor({'bearer': token, 'apiKey': apiKey, 'signature': sig}),
  );
final client = VaultClient(DioTransport(dio));
```

The fake-adapter run printed these requests (secrets shortened):

```text
GET https://api.example.com/health {}
GET https://api.example.com/items {Authorization: Bearer tok}
DELETE https://api.example.com/items/a?sig=s {X-Api-Key: k}
GET https://api.example.com/me {Authorization: Bearer tok}
TransportError(unknown)        <- /legacy: the scheme is unknown
```

- `/health` is open, so nothing is added.
- `deleteItem` has no `oauth` secret in the map, so the second alternative (`apiKey` and `signature`, both needed) is used.
- `/me` prefers `bearer` when the interceptor has a token and goes without one when it has none, because the empty alternative is tried last.
- `/legacy` can never be satisfied (`.unknown`), so the interceptor rejects it. The call returns a `TransportError` whose `exception.error` is the `MissingCredentials`; only an `Exception` is turned into a `TransportError`, a thrown `Error` would reach the caller.

## Notes and limits

- **Query keys.** The generated client builds the query itself and `DioTransport` passes Dio one finished path, so `options.queryParameters` is empty in an interceptor. Adding a key to it, as above, makes Dio append it to the URL (`?sig=s`).
- **Cookies.** A script on the web cannot set the `Cookie` header, so a `location: .cookie` scheme works on the Dart VM only.
- **OAuth.** The metadata carries the scopes an operation needs but not the token URL or flows; getting and refreshing a token is your code. A 401 reaches your interceptor's `onError` as for any Dio request.
- **Mutual TLS** is a transport setting: configure the `HttpClient` of your adapter.
- **Streams.** Event-stream methods go through the same interceptors for the first request and for each reconnection; see [Event streams](event_streams.md).

## See also

- [Operations](operations.md): the group classes and `CallOptions` (per-call headers).
- [Responses and errors](responses_and_errors.md): `HttpError` for a `401`.
- [Diagnostics](../diagnostics.md): `TOA568` and the other codes.
- Runtime: [Security metadata](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/security_metadata.md).
