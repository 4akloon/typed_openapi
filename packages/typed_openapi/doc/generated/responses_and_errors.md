# Responses and errors

A generated method returns `Future<Result<T, E>>` and does not throw for a response. `T` is what the documented success returns, `E` the documented error body. Match the result with a `switch`; the runtime's `Result` is sealed.

```dart
final result = await client.books.getBook(isbn: isbn);
switch (result) {
  case Success(:final data):
    print('book: ${data.title}');
  case HttpError(:final body):          // a documented error status
    print('documented error: ${body.title}');
  case UndocumentedStatus(:final statusCode):
    print('undocumented status $statusCode');
  case DecodeError(:final error):       // the body did not match the schema
    print('decode error: $error');
  case Failure():                       // TransportError, Cancelled
    print('other failure: $result');
}
```

Real output of this code against a fake adapter (five canned answers):

```text
book: Dune, genre: GenreKnown.fiction
documented error: No such book
book: Odd, genre: GenreUnknown(poetry)
decode error: JsonDecodeException: expected a required property, got no value at /addedAt in Book
undocumented status 503
```

| Result | When |
| --- | --- |
| `Success(data, statusCode, headers)` | a documented 2xx |
| `HttpError(body, statusCode, headers)` | a documented error status; `body` is the decoded `E` |
| `UndocumentedStatus(statusCode, rawBody, headers)` | a status the spec does not document |
| `DecodeError(error, statusCode, rawBody, headers)` | the body did not decode; `error.pointer` says where |
| `TransportError(exception, stackTrace)` | network failure, timeout |
| `Cancelled(exception, stackTrace)` | the `CancelToken` was cancelled |

`Failure` is the sealed base of the last five. If a method has no documented errors, `E` is `Never`, but you still write `case Failure()`. The runtime reference is the [results and errors guide](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/results_and_errors.md).

## The success type

| Spec | `T` |
| --- | --- |
| one 2xx with a JSON body | the model, `List<Pet>`, a map, a scalar |
| 2xx with no body (`204`) | `void` |
| `text/plain` (`text/*`) | `String` |
| other media type (`image/png`, `application/octet-stream`, XML) | `Uint8List` |
| several 2xx with different bodies | a sealed type by status |
| no 2xx documented | `JsonValue` (`TOA653`) |
| wrapper object `{data: Pet}` | the `data` is returned, see below |

An inline envelope with a single `data` property is unwrapped: `getPet` returns `Pet`, not a class with `data`.

### Several successes: sealed status types

`createPet` documents `200` (`Pet`), `201` (`Job`) and `204` (no body), so `T` is a sealed `CreatePetResponse`:

```dart
sealed class CreatePetResponse { const CreatePetResponse(); }
class CreatePetResponseOk extends CreatePetResponse { const CreatePetResponseOk(this.body); final Pet body; }
class CreatePetResponseCreated extends CreatePetResponse { final Job body; /* ... */ }
class CreatePetResponseNoContent extends CreatePetResponse { const CreatePetResponseNoContent(); }
```

```dart
switch (await client.pets.createPet(body: pet)) {
  case Success(data: CreatePetResponseOk(:final body)):      /* body is a Pet */
  case Success(data: CreatePetResponseCreated(:final body)): /* body is a Job */
  case Success(data: CreatePetResponseNoContent()):          /* no body */
  case Failure(): /* ... */
}
```

Variants are named by the reason phrase of the status (`Ok`, `Created`, `NoContent`, `NotFound`, `ServiceUnavailable`, `ClientError` for `4XX`, `Other` for `default`) and are equal by value. They live in the group file after the class.

## Errors: `E`

- No documented error: `Never`.
- All documented errors have the same body type: that type (`Problem`).
- Different bodies: a sealed `<Method>Error` by status, as above. `createPet` documents `404` (`Problem`), `4XX` (`Job`) and `503` (no body):

```dart
switch (result) {
  case HttpError(body: CreatePetErrorNotFound(:final body)):          /* Problem */
  case HttpError(body: CreatePetErrorClientError(:final body)):       /* Job */
  case HttpError(body: CreatePetErrorServiceUnavailable()):           /* no body */
  ...
}
```

The status switch the generator writes (so you can predict it): exact codes first, then ranges, then `default`:

```dart
switch (r.statusCode) {
  200 => r.success(CreatePetResponseOk(Pet.fromJson(JsonReader.asObject(r.json)))),
  404 => r.error(CreatePetErrorNotFound(Problem.fromJson(JsonReader.asObject(r.json)))),
  503 => r.error(const CreatePetErrorServiceUnavailable()),
  >= 400 && < 500 => r.error(CreatePetErrorClientError(Job.fromJson(JsonReader.asObject(r.json)))),
  _ => r.undocumented(),
}
```

- A range `2XX`, `4XX`, `5XX` (either case) covers its hundred. `default` covers every status not matched and not 2xx (a `default` is never a success).
- Keys that are not a status, a range or `default` are `TOA657` and skipped; `1xx` and `3xx` are `TOA658` info and skipped (Dio follows redirects), so they arrive as `UndocumentedStatus`.
- An inline error body is named after the operation and, when several responses of a kind declare one, the status.

### `errors.default_schema`

Many frameworks do not document error bodies. Name the schema of your error type once and every error status without a documented body decodes to it:

```yaml
clients:
  shop:
    errors: {default_schema: Problem}
```

With it, `putPhoto` (no documented error) returns `Result<void, Problem>` and decodes `>= 400 && < 600` as `Problem`; `503` without a body in `createPet` now carries a `Problem` too. A key that is not in `components.schemas` is `TOA652` and ignored.

## Text and bytes

A success or an error body that is not JSON is read by its media type: `String` for `text/*` (an empty body is `''`), `Uint8List` for anything else, and the generated request uses `responseKind: .text` or `.bytes` so Dio does not decode it. An operation that documents a JSON error next to a binary success still decodes the error: the runtime parses it from the raw body (`r.parsedJson`). `UndocumentedStatus.rawBody` is the raw bytes in such operations. Form and multipart *responses* are bytes (`TOA650`); a `*/*` response is bytes too (`TOA601` warning: declare the real media type or override `contentType`). When a response offers several media types the client uses one (JSON first) and names the others it drops (`TOA651`).

## What `DecodeError` tells you

`error` is a `JsonDecodeException`: the JSON pointer of the first mismatch, what was expected, what the value was (a type, never the value), and the schema name. The status, raw body and headers are kept next to it. Use it in logs; to diagnose, see [Troubleshooting](../troubleshooting.md).

## See also

- [Operations](operations.md), [Request bodies](request_bodies.md).
- [Models](models.md) for how bodies are decoded and [Unions](unions.md) for error bodies that are unions.
- [Configuration](../configuration.md) for `errors`.
