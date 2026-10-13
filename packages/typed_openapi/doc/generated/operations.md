# Operations

Operations are generated into **group classes**, one plain class per group in `api/<group>.dart`, exported by `api.dart` and held by the root client as fields. A method has named arguments only and returns a `Future<Result<T, E>>`; it never throws for a response.

```dart
final client = PetstoreClient(dio);
final result = await client.pets.listPets(limit: 10, xTrace: 'abc');
```

## Groups

| Setting | Effect |
| --- | --- |
| `group_by: tag` (default) | a class per tag; an operation goes to its **first** tag (`TOA553` info when it has more) |
| `group_by: path` | a class per first path segment: `/pets/{id}` goes to `PetsService` |
| `group_by: single` | one class for everything |
| `naming.group` | the class name, `{Tag}Api` by default (`'{Tag}Service'`) |
| `naming.default_group` | the class of untagged operations, `DefaultApi` (`TOA554`) |
| override `group: Catalog` | puts one operation in another group (UpperCamelCase; `pet-store` is read as `PetStore`) |

Tags that differ only by case or separators are merged (`TOA555`). The field on the root client is the lowerCamelCase of the group. Settings are in [Configuration](../configuration.md).

## A method

From the `petstore` fixture (`listPets`, trimmed):

```dart
/// Lists pets.
///
/// `GET /pets` (`listPets`).
///
/// [limit], when not sent, is `20` on the server:
/// How many.
Future<Result<List<Pet>, Problem>> listPets({
  int? limit,
  List<String>? tags,
  List<StatusKnown>? status,
  Map<String, String>? filter,
  String? next,
  Map<String, int>? where,
  JsonValue extra = const JsonValue(null),
  required String xTrace,
  String? session,
  CallOptions? call,
})
```

- Every argument is named. Required ones are `required`; the request body is `body`; the last argument is `CallOptions? call`.
- Parameters are in location order (path, query, header, cookie), then in spec order. Names are lowerCamelCase of the parameter name (`X-Trace` is `xTrace`); an override `parameters: {header:X-Trace: {name: traceId}}` renames one. Names that clash with `body` or `call` get an underscore (`TOA550`).
- Enum parameters take the **known** type (`GenreKnown`), so an unlisted value cannot be sent.
- `summary`, `description` and parameter descriptions are in the doc comment; `deprecated: true` is `@Deprecated('Deprecated in the API spec.')` on the method.
- A parameter's `default` is documented, never sent. A required parameter's default is not documented.
- A parameter whose schema is any JSON is `JsonValue extra = const JsonValue(null)`: an unset one is not sent.
- Header parameters named `Accept`, `Content-Type` and `Authorization` are not generated, as OpenAPI says (use `CallOptions.headers` or an interceptor).

## Parameter styles

The runtime serialises each parameter by the OpenAPI `style` and `explode` of the spec. What the generator writes for the fixture above:

```dart
OperationRequest(
  _listPets,
  query: [
    QueryParameter('limit', limit),
    QueryParameter('tags', tags, style: .pipeDelimited),
    QueryParameter('status', status == null ? null : [for (final e0 in status) e0.toJson()], explode: false),
    QueryParameter('filter', filter, style: .deepObject, explode: true),
    QueryParameter('next', next, allowReserved: true),
    QueryParameter('where', where == null ? null : jsonEncode(where)),
  ],
  headers: [HeaderParameter('X-Trace', xTrace)],
  cookies: [CookieParameter('session', session)],
)
```

Path parameters use `PathParameter('petId', petId, style: .label)` or `.matrix`. A parameter described with `content` (`application/json`) is JSON-encoded. A style that its `in` does not allow falls back to the default (`TOA564`), and `in: querystring` is skipped (`TOA565`). Browsers drop the `Cookie` header, so cookie parameters do not work on the web. The encoding rules (RFC 6570 expansion, percent-encoding, and the `ArgumentError` for a path value that is empty, `.` or `..`) are in the [runtime guide on parameters](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/parameters.md).

## `CallOptions`

The last argument of every method:

| Field | Use |
| --- | --- |
| `cancelToken` | Dio `CancelToken`; a cancelled call is `Cancelled` |
| `headers` | extra headers for this call |
| `extra` | values for your interceptors in `RequestOptions.extra` |
| `onSendProgress`, `onReceiveProgress` | Dio progress callbacks |
| `sse` | `SseOptions` for [event streams](event_streams.md) |

```dart
final token = CancelToken();
await client.pets.getPet(petId: 1, call: CallOptions(cancelToken: token, headers: {'X-Request-Id': 'r1'}));
```

Every request also carries an `OperationInfo` in `RequestOptions.extra` (`OperationInfo.of(options)`): `operationId`, method, path template, tags and the [security requirements](security.md), for interceptors.

## Method names

The name is, in order: the `name` override, the `operationId` without the `naming.operation_prefix` match, or `METHOD /path` when there is no id (`GET /pets/{id}` is `getPetsById`, `TOA503`). `operation_prefix` is a regular expression removed only where its match starts at index 0 and is not empty:

```yaml
naming:
  operation_prefix: '^[A-Za-z]+Controller_'   # CatsController_findAll -> findAll
```

With `preset: nestjs` the prefix `^[A-Za-z0-9]*Controller_` is removed for you. A name that clashes within the group gets `2`, `3`... (`TOA551`), a reserved word an underscore (`TOA550`), and a repeated `operationId` is the error `TOA504` (the fix text suggests an override, but the error stays until you lower its level in `severity` or baseline it; the methods are still generated with distinct names).

## Choosing operations

```yaml
clients:
  shop:
    input: specs/petstore.yaml
    output: lib/api/shop
    include: {paths: ['/pets/**', '/pets']}
    exclude: {operations: [deletePet]}
```

- `include` is a union of `tags`, `operations` (the `operationId` as written, before the prefix is removed) and `paths`; empty means no filter. `exclude` wins. Path patterns: `*` is one segment, `**` any number (`/pets/**` does not match `/pets`, so list both).
- A pattern in both lists is `TOA558`; one that matches nothing is `TOA557`.
- An override `exclude: true` leaves one operation out; `sse.method: none` leaves out a stream-only one.
- If nothing is left, `TOA563` says why.

## Operations that are not generated

| Case | Diagnostic |
| --- | --- |
| Operation written as a `$ref` | `TOA107` |
| Path variable with no parameter | `TOA556` (error) |
| Event stream with conflicting shapes | `TOA654` |
| Callbacks, webhooks | `TOA567` (info) |
| Operation-level `servers` | `TOA566` (ignored) |

## See also

- [Responses and errors](responses_and_errors.md) for `Result<T, E>`.
- [Request bodies](request_bodies.md), [Security](security.md), [Event streams](event_streams.md).
- [Overrides](../overrides.md) for `name`, `group`, `exclude`.
