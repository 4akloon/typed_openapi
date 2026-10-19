# Results and errors

Every generated method returns `Future<Result<T, E>>`. `Result` is a sealed
class: `Success<T, E>` or one of five `Failure<T, E>` variants. A generated
method does not throw for an expected problem - an HTTP error, a timeout, a
cancel, a body that does not match the schema - it returns a value you match
with `switch`. There are no helper methods (`when`, `fold`, `getOrThrow`);
pattern matching is the API.

## The shape of a generated method

This is the generated `getPet` of the Petshop spec (trimmed to the
operation):

```dart
Future<Result<Pet, ApiError>> getPet({
  required int petId,
  List<String>? fields,
  CallOptions? call,
}) => _sender.send(
  OperationRequest(
    _getPet,
    path: [PathParameter('petId', petId)],
    query: [QueryParameter('fields', fields, explode: false)],
  ),
  _decodeGetPet,
  call: call,
);

static Result<Pet, ApiError> _decodeGetPet(RawResponse r) =>
    switch (r.statusCode) {
      200 => r.success(Pet.fromJson(JsonReader.asObject(r.json))),
      404 => r.error(ApiError.fromJson(JsonReader.asObject(r.json))),
      _ => r.undocumented(),
    };
```

`T` is the body of the documented success (`void` when it has none, a sealed
status type when several successes have different bodies), `E` is the body of
the documented errors (`Never` when there are none).

## The variants

| Variant | When | Carries |
| --- | --- | --- |
| `Success<T, E>` | A documented 2xx status whose body decoded | `data`, `statusCode`, `headers` |
| `HttpError<T, E>` | A documented error status (4xx, 5xx or `default`) whose body decoded as `E` | `body`, `statusCode`, `headers` |
| `UndocumentedStatus<T, E>` | A status the operation does not document | `statusCode`, `rawBody`, `headers` |
| `DecodeError<T, E>` | A body that does not match the schema, is not valid JSON, or is rejected by a decoder | `error` (a `JsonDecodeException`), `statusCode`, `rawBody`, `headers` |
| `TransportError<T, E>` | No complete response: timeout, connection or certificate problem, any other transport failure | `exception` (a `TransportException`), `stackTrace` |
| `Cancelled<T, E>` | The caller cancelled the request | `exception` (a `TransportException` of kind `cancelled`), `stackTrace` |

Header maps use lower-case names and `List<String>` values. `HttpError` and
`Success` never hold a raw body; `UndocumentedStatus` and `DecodeError` do.

Real output of each outcome from the generated `getPet`, produced with an
in-memory Dio adapter through `DioTransport` (`describe` is a `switch` over the six variants):

```text
200 ok            -> Success 200 Rex
404 documented    -> HttpError 404 code=not_found
404 wrong body    -> DecodeError status=404 pointer="/code" expected a required property, got no value rawBody={message: x}
500               -> UndocumentedStatus 500 rawBody={oops: true}
200 wrong type    -> DecodeError status=200 pointer="/id" expected an integer, got a string rawBody={id: one, name: Rex}
200 not json      -> DecodeError status=200 pointer="" expected a JSON body, got text that is not JSON rawBody=<html>
200 text/plain    -> DecodeError status=200 pointer="" expected an object, got a string rawBody={"id":1,"name":"Rex"}
timeout           -> TransportError timeout
cancel            -> Cancelled
```

## Matching

```dart
switch (await api.pets.getPet(petId: 7)) {
  case Success(:final data):
    print('${data.name}, born ${data.birthday}');
  case HttpError(:final body, :final statusCode):
    print('documented error $statusCode: ${body.code}');
  case DecodeError(:final error):
    print('the body does not match the schema at ${error.pointer}');
  case UndocumentedStatus() || TransportError() || Cancelled():
    print('retry later');
}
```

`Failure` is the sealed parent of the five failure variants, so
`case Failure():` matches all of them and keeps a `switch` short:

```dart
String label(Result<Pet, ApiError> result) => switch (result) {
  Success(:final data) => 'ok ${data.name}',
  HttpError(:final body) => 'http ${body.code}',
  Failure() => 'failure',
};
```

### `E = Never` and `T = void`

An operation without documented errors has `E = Never`. A `switch` over it
still needs `case Failure()` (which covers every failure) or a case for each
failure variant **including `HttpError()`**, because the other failures are
possible and the analyzer does not treat `HttpError<T, Never>` as
unreachable. `case Success` alone, or `Success` plus `HttpError()`, is a
`non_exhaustive_switch_statement` error.

```dart
switch (result) {                 // Result<int, Never>
  case Success(:final data): print(data);
  case Failure(): print('failure');
}
```

A success without a response body has `T = void`; match it with `Success()`.

## What triggers each variant

The transport sends the request first and owns its rules; with
`DioTransport` an error status goes through your interceptors' `onError`,
which may resolve it into a response of any status (see
[`typed_openapi_dio`](../../typed_openapi_dio/README.md)).

1. A response of any status is read whole and decoded by the generated
   switch on its final status: a documented success becomes `Success`, a
   documented error status `HttpError`, anything else
   `UndocumentedStatus`.
2. A body that is not valid JSON, or a decoder that rejects the body, gives
   `DecodeError`: a `JsonDecodeException` (type, missing property, bad
   date-time) or a `FormatException` thrown by a converter or
   `Date.parse`. A `FormatException` becomes a `DecodeError` at the root
   pointer `""`.
3. A request that gets no complete response fails with a
   `TransportException`: `Cancelled` for kind `cancelled`, `TransportError`
   for `timeout`, `connection` and `other`. `exception.cause` is the
   transport's own exception (a `DioException` for `DioTransport`), kept
   whole.

### Malformed JSON

The client parses JSON itself, by the `Content-Type` of the response. When
a body is not valid JSON, the `DecodeError` has the response's
`statusCode`, `error.pointer == ""`, `error.message` is
`expected a JSON body, got text that is not JSON`, and `rawBody` is the
whole body text, on every platform. A request that does not read JSON (a
text or binary operation) never gets this error.

### `rawBody` is best effort

`rawBody` of a `DecodeError` and of an `UndocumentedStatus` is the body as
the client read it: parsed JSON, text or bytes, and `null` when the
response had no body. When the operation reads bytes or text (a documented
binary or XML error makes the whole operation read bytes),
`UndocumentedStatus.rawBody` is the raw bytes, not parsed JSON. JSON sent
with a non-JSON content type (`text/plain`) is **not** guessed: a JSON
operation gets a `String`, which an object decoder rejects (the `200
text/plain` line above).

## What is never caught

The client catches `TransportException`, `JsonDecodeException` and, from a
decoder, `FormatException`; another `Exception` raised while a body is read
is a `TransportError` of kind `other`. Nothing else:

- **An `Error` is a bug and reaches the caller.** A `TypeError` or
  `StateError` thrown by a decoder, or by the transport (`DioTransport`
  rethrows one that your interceptors or adapter threw, which Dio wraps in
  an `unknown` `DioException`), reaches the caller with its original stack
  trace:

  ```text
  rethrown: Bad state: bug in interceptor
  ```

- **Wrong arguments throw `ArgumentError`**, an `Error`, before any request
  is sent: an empty or dot-segment path parameter, a value that is not a
  finite JSON scalar, a form body that is not an object, a multipart part
  that cannot be a part. See [Parameters](parameters.md) and
  [Request bodies](request_bodies.md). A media type that is not a media type
  throws `FormatException` from `send`.
- **An exception your interceptor throws** is a transport failure like any
  other: `TransportError`.

  ```dart
  // onRequest: (o, h) => throw const FormatException('Uri.parse failed')
  // -> TransportError (kind other)
  // handler.reject(DioException(...)) -> TransportError too
  ```

## Notes

- `Result` has the same name as `Result` in `package:async`. In a library
  that imports both, hide one:
  `import 'package:async/async.dart' hide Result;` or
  `import 'package:typed_openapi_client/typed_openapi_client.dart' hide Result;`,
  or import one with a prefix.
- `toString` is short and carries no body: `Success(200)`,
  `HttpError(404)`, `UndocumentedStatus(500)`, `TransportError(timeout)`,
  `Cancelled`. Print `rawBody` yourself if you want it, and mind private data.
- Retrying is yours: nothing in the client retries.

## See also

- [JSON decoding](json_decoding.md) - what `DecodeError.error` holds.
- [Getting started](getting_started.md) - `CallOptions`, `CancelSignal`.
- [Server-Sent Events](sse.md) - the result of `openEvents` and its stream.
- How the generator shapes `T` and `E`:
  [responses and errors](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/responses_and_errors.md).
