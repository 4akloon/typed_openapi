# M7: runtime (`typed_openapi_runtime`) — design

Date: 2026-10-12. Requirements: R6.5, R7.1, R10.1–R10.3, R10.5, R11.2, R11.3, R11.7, R12.3 ([requirements.md](../../requirements.md)). Research: [research/README](../../research/README.md) (the table of adopted decisions; §7.3 HTTP layer; §7.4 error model; §7.7 representation), [research/07](../../research/07-dart-building-blocks.md) (§B Dio 5.11, §C language, §E sketches). Decisions marked "(u. N)" were confirmed by the user on 2026-10-12 (N is the number in the user's list); "(a. N)" — answers of the user and the controller to the open questions of the first version of the design (N is the question number).

The runtime is the single package that the generated code depends on. There is no generated code yet (M8–M10), so the API is designed from the side of its calls; a sketch — at the end.

## Decisions

1. **Dependencies — only `dio` and `meta`** (R13.3; u. 15). `meta` provides `@visibleForTesting`. Logic that needs no transport does not depend on Dio (§7.3): `json/`, `model/`, `params/`, `OperationRequest`, `RawResponse`, the SSE decoder. Only `dio/` (`DioRequestSender`, `CallOptions`), `result/` (transport variants carry `DioException`, u. 5) and `OperationInfo.of(RequestOptions)` (u. 12) know Dio.
2. **`Result<T, E>` without exceptions** (§7.4; R11.1–R11.3, R11.7; u. 1.1, 7; a. 5). A sealed `Result<T, E>` = `Success<T, E>` (`data`, `statusCode`, `headers: Map<String, List<String>>`) | a sealed `Failure<T, E>` = `HttpError` (a documented 4xx/5xx/`default`; `statusCode`, `body: E`, `headers`) | `UndocumentedStatus` (`statusCode`, `rawBody`, `headers`) | `DecodeError` | `TransportError` | `Cancelled`. There is no `Api` prefix anywhere. There are no helper methods (`dataOrNull`, `map`, `getOrThrow`, `fold`): only pattern matching. R11.2 in v1 — only `Result` (§7.4). The name `Result` coincides with `Result` from `package:async`; this is accepted, and the README recommends `hide Result` or an import prefix.
3. **`E = Never`, `T = void`** (u. 4, 16). An operation without documented errors has `E = Never` (all non-2xx — `UndocumentedStatus`); with `errors.default_schema` in the config `E` is that schema (decided in M9). Success without a body — `T = void`.
4. **Transport and cancellation** (R11.7; research §6 R11.7; u. 5). `TransportError(DioException exception, StackTrace stackTrace)` without its own enum of kinds: the kind is `exception.type`. Cancellation — a separate variant `Cancelled(DioException, StackTrace)`. The `DioExceptionType` type, which Dio 5.11 does not have yet, is also `TransportError` (a switch with `_`, so that a new minor Dio does not break the runtime's compilation).
5. **Decoding: the json_serializable contract and one exception type** (R6.5; §7.2; u. 2, 3, 13; a. 4). The generated `Model.fromJson(Map<String, Object?>)` throws only `JsonDecodeException` (JSON pointer, `expected`, `actual`, `schema`), and only on the first mismatch — errors are not collected. The client catches only this type, `DioException`, and the decoder's `FormatException`; `Error` (`TypeError`, `StateError`) is not caught. The decoder's `FormatException` (`DateTime.parse`, the R6.8 converter) is a data failure, so it is converted into `JsonDecodeException` (`JsonDecodeException.fromFormatException`): `JsonReader` does this at the field's pointer, `DioRequestSender` — at the root (`DecodeError` with the status and `rawBody`), `SseItemDecoder` — into `SseDecodeError`, and the stream goes on. Otherwise the user's converter would throw out of the generated method, or as an unhandled zone error from SSE. The messages name the JSON types, not the values (values can be large or private). For an error that the server produces on purpose, the exception carries a `hint` — an explicit fix (see decision 6).
6. **Strictness** (u. 2; a. 3, 4). A value of another JSON type is an error; the only widening is an integer where a `number` is expected. `asInt` does not accept `1.0`; an integer above 2^63 `jsonDecode` gives as a `double`, so it is also an error (not a silent truncation by `toInt`). Infinity (`jsonDecode('1e400')`) is an error: `jsonEncode` would not write it back. `date-time` — only RFC 3339 with an offset; non-existent dates and second 60 are errors (`DateTime.parse` silently rolls them over). `date-time` without an offset (Spring `LocalDateTime`) — a `DecodeError` with `actual: a date-time without an offset` and a `hint`: map the format to one's own type through a converter (`types.formats`, R6.8) or override the property's `format` with an override. `null` is an error only in a required non-nullable property; an optional non-nullable property reads `null` as "absent" (the field in Dart is `T?` anyway).
7. **Read matrix** (R6.1, R7.1; a. 3). `JsonReader`: `required` (absent or `null` — an error), `requiredNullable` (absent — an error), `optional` (nullable or not: absent and `null` → `null`), `patch` (absent → `null`, `null` → `Patch.nullValue()`), `requiredValue` / `optionalValue` for schemas without constraints. Decoders are static functions `T Function(Object?)`: `asInt`, `asDouble`, `asNumber`, `asString`, `asBool`, `asDateTime`, `asObject`, `asList`, `asValue`, combinators `listOf`, `mapOf`, `objectOf`, `nullable`; the array index and the map key go into the pointer. Extra fields are ignored (R6.5).
8. **Input boundaries.** `jsonDecode` is iterative, while the recursive `fromJson` and `jsonEncode` are not (verified: 200 000 levels → `StackOverflowError` in `jsonEncode`). `RawResponse.json` and `SseMessage.json` check the depth without recursion (`JsonReader.checkDepth`, 1000 levels, like the generator's TOA007) and give a `DecodeError` with the pointer to the first too-deep container.
9. **`Patch<T>`** (§7.7, E.2; u. 8). A sealed `Patch<T>` = `PatchValue` | `PatchNull`, `const` factories `.value(x)` / `.nullValue()`, `toJson(encode)`; a field `Patch<T>?`, `null` = do not send (R7.3).
10. **`JsonValue`** (R6.2; §C.6; u. 9). `extension type const JsonValue(Object? raw)` with `asObject`, `asList`, `asString`, `asNumber`, `asBool`, `isNull`, `operator []` (a missing key or index — `JsonValue(null)`), `fromJson`/`toJson`. An extension type is erased: `JsonValue(null)` at run time is `null`, so `JsonValue?` would not distinguish "absent" from `null`; a schema field without constraints has type `JsonValue`, and an absent one reads as `JsonValue(null)`.
11. **Parameters are encoded by the runtime** (R10.3; §B.4; u. 10). `PathParameter` (`simple`, `label`, `matrix`), `QueryParameter` (`form`, `spaceDelimited`, `pipeDelimited`, `deepObject`, `allowReserved`), `HeaderParameter`, `CookieParameter` per RFC 6570 and RFC 3986. The values are in JSON form (`toJson` is already applied, R6.8). The order is the order of parameters in the spec; `null`, an empty list and an empty map are not sent (except for a path parameter: its ready expression that is empty or equals `.` or `..` throws `ArgumentError`, because Dio collapses `//` and removes `.` segments). `explode` by default as in OAS (`true` only for `form`). `allowReserved` leaves only the reserved characters that are safe in a query (OAS 3.2: `[ ] #` and `& = +` are always encoded); `[`, `]`, `|` are encoded, because `Uri.parse` in Dio would encode them anyway (verified). Headers are not percent-encoded, except control and non-ASCII characters (protection against CRLF injection). Cookies — `name=value` pairs joined with `; `. Dio gets the ready path with the query; interceptors see an empty `queryParameters` (read `options.uri`) — see the README. A non-JSON scalar (`DateTime`, a nested list, infinity) — `ArgumentError`: this is an error of the generated code, not of the data.
12. **The Dio flow** (R10.1, R10.2; §B.1, §B.2; the user's usual decisions). The request goes through `dio.request` (merging `BaseOptions`: base URL, headers, timeouts). The user's Dio is not changed, `validateStatus` is not touched, there are no retries (that is the job of interceptors). `DioException.badResponse` with a response is decoded the same way as a successful response: the generated decoder always switches on the status (an interceptor could have `resolve`d a 503, and the user's `validateStatus` could let a 404 through).
13. **Response bodies** (§B.1; u. 14; a. 2). JSON is parsed by Dio (`ResponseType.json`); the runtime decodes the already parsed object and parses nothing again: `text/plain` with JSON for a JSON operation — a `DecodeError` "expected an object, got a string". Non-JSON bodies — `ResponseKind.text` / `.bytes` (the type argument `request<String>` / `request<List<int>>`, because Dio forces JSON for other types). Invalid JSON: Dio throws `DioException.unknown` with a `FormatException` and discards the response, so the `DecodeError` has `statusCode: null` and `rawBody` — the text that the parser reported, best effort: the whole body when Dio read it in one chunk, and only the last chunk when Dio streamed the body (there is a `Content-Length`; verified). The full body and the status would be given only by `ResponseType.plain` with one's own `jsonDecode`, which contradicts u. 14; the limitation is described in the README.
14. **`CallOptions`** (R10.5; §C.4; u. 1). One optional parameter `call` in each generated method: `cancelToken`, `headers` (the parameter headers win), `extra` (for interceptors), `onSendProgress`, `onReceiveProgress`. There are no timeouts: they are in the user's Dio.
15. **`OperationInfo`** (R10.5; research R10.5/10.8; u. 12). `operationId`, `method`, `pathTemplate`, `tags` (security — in M9) live in `RequestOptions.extra` under `OperationInfo.extraKey`; `OperationInfo.of(RequestOptions)` returns `null` for requests that do not come from the generated client.
16. **SSE decoder per WHATWG** (R12.3; §B.6). `SseDecoder`: bytes → `SseMessage(event, data, id, retry)`; UTF-8 with replacement of invalid sequences; a BOM at the start is dropped; a character split between chunks stays whole; line endings CRLF/LF/CR (including CR and LF in different chunks); `data` is multi-line; an `id` with U+0000 is ignored, `id` and `retry` are kept between events; `retry` — ASCII digits only; comments; an unfinished event at the end is dropped. Use `bind`, not `stream.transform`: Dio gives a `Stream<Uint8List>`, and `transform` with a `List<int>` transformer fails at run time (found by a test).
17. **The event stream as a value** (§7.4, an open question about streams; u. 11; a. 6). `DioRequestSender.openEvents` returns `Result<Stream<SseItem<T>>, E>`: opening is a `Result`; then a sealed `SseItem<T>` = `SseEvent<T>` (`data`, `event`, `id`, `retry`) | `SseDecodeError` (one event did not decode, the stream goes on) | `SseDisconnected` (always the last; `cause` — the error, including a `DioException` of cancellation, or `null`, when the server closed the stream). The stream emits no errors and no exceptions. The stream is opened only for documented success statuses, which the generated call passes into `OperationRequest.streamStatuses` (in the same way as other responses switch by status); for any other status the body is read fully, JSON by content-type, and is decoded by the usual path of error or undocumented status. Reconnection — M10.
18. **Web** (R12.4; §B.6; u. 15). Everything works on the web except SSE with the standard browser adapter of Dio (XHR delivers the body only after the connection closes): there `openEvents` immediately returns `TransportError` with an explanation of how to plug a fetch adapter into one's own Dio (`ConversionLayerAdapter` from `dio_compatibility_layer` + `BrowserClient` or `fetch_client`). Web is detected by `bool.fromEnvironment('dart.library.js_interop')`; the standard adapter — by comparing `runtimeType` with `HttpClientAdapter()`; on the VM this is checked through the public parameter `DioRequestSender(dio, isWeb: true)` (its default value is `bool.fromEnvironment`, it is `true` both on dart2js and on dart2wasm; `identical(0, 0.0)` on wasm gives `false`, so it does not suit). The same `isWeb` decides that the `FormatException` of Dio's JSON parser for a JSON request is a `DecodeError` without a status (Dio discards the response): dart2js gives the text of the browser's `SyntaxError` without a `source`, so `rawBody` is `null` there, while dart2wasm and the VM give the bytes of the body. Tests in the browser: `dart test -p chrome` and `dart test -p chrome --compiler dart2wasm`; files and tests that need the VM (`dart:io`, int64 literals) are marked `@TestOn('vm')` or `testOn: 'vm'`. The browser forbids setting the `Cookie` header, so cookie parameters do not work on the web. The upper bound of the SSE `retry` — `9007199254740` ms (2^53 µs, the largest value that JavaScript holds exactly), the same on all platforms.

19. **Names** (a. 1): `DioRequestSender` with `send` / `openEvents`, `OperationRequest`, `RawResponse` (`success` / `error` / `undocumented`), `ResponseKind`, `JsonReader`, `SseMessage`, `SseItemDecoder` — as in this design.

### Sketch of the generated code (illustration, not a contract for M8)

Verified by the test `test/helpers/pets_api.dart` + `test/generated_client_test.dart` (the plan, task 8).

```dart
final class Pet {
  const Pet({required this.id, required this.name, this.tags, this.metadata = const JsonValue(null)});

  factory Pet.fromJson(Map<String, Object?> json) {
    final r = JsonReader(json, schema: 'Pet');
    return Pet(
      id: r.required('id', JsonReader.asInt),
      name: r.required('name', JsonReader.asString),
      tags: r.optional('tags', JsonReader.listOf(JsonReader.objectOf(Tag.fromJson))),
      metadata: r.optionalValue('metadata'),
    );
  }

  final int id;
  final String name;
  final List<Tag>? tags;
  final JsonValue metadata;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'tags': ?tags?.map((t) => t.toJson()).toList(),
    'metadata': ?metadata.raw,
  };
}

final class UpdatePet {                      // PATCH body (R7)
  const UpdatePet({this.name, this.tag});
  final Patch<String>? name;
  final Patch<String>? tag;
  Map<String, Object?> toJson() => {
    if (name case final v?) 'name': v.toJson((s) => s),
    if (tag case final v?) 'tag': v.toJson((s) => s),
  };
}

class PetsApi {                              // no modifiers: a mock through implements (R10.7)
  PetsApi(Dio dio) : _sender = DioRequestSender(dio);
  final DioRequestSender _sender;

  static const _getPetById = OperationInfo(
    operationId: 'getPetById', method: 'GET', pathTemplate: '/pets/{petId}', tags: ['pets']);

  Future<Result<Pet, ApiError>> getPetById({required int petId, List<String>? fields, CallOptions? call}) =>
      _sender.send(
        OperationRequest(
          _getPetById,
          path: [PathParameter('petId', petId)],
          query: [QueryParameter('fields', fields, explode: false)],
        ),
        (r) => switch (r.statusCode) {
          200 => r.success(Pet.fromJson(r.jsonObject)),
          >= 400 && < 600 => r.error(ApiError.fromJson(r.jsonObject)),
          _ => r.undocumented(),
        },
        call: call,
      );

  Future<Result<Stream<SseItem<PetChange>>, Never>> watchPet({required int petId, CallOptions? call}) =>
      _sender.openEvents(
        OperationRequest(_watchPet, path: [PathParameter('petId', petId)], streamStatuses: const {200}),
        PetChange.fromEvent,                 // SseMessage → PetChange, through message.jsonObject
        (r) => r.undocumented(),
        call: call,
      );
}

// call
switch (await pets.getPetById(petId: 7)) {
  case Success(:final data): show(data);
  case HttpError(:final body): showError(body.code);
  case DecodeError(:final error): log('${error.schema} ${error.pointer}');
  case UndocumentedStatus() || TransportError() || Cancelled(): retryLater();
}
```

## Out of scope

- SSE reconnection with `Last-Event-ID` and a policy (R12.5), the event dispatcher by `event` and `itemSchema` (R12.2) — M10.
- Request bodies `multipart/form-data` and `x-www-form-urlencoded` (R10.4) — M9; the runtime passes `body` and `contentType` to Dio as they are (a form can be assembled with `QueryParameter.encode`).
- Decoders for the formats `date`, `byte`, `uuid`, `int64` on the web — together with the type mapping (M6, M8).
- Security metadata in `OperationInfo` (R10.8) — M9; the field is added without breaking.
- The delivery mode of errors by exceptions (R11.2) — later, if a request appears (§7.4).
- One's own transport abstraction `ApiTransport` — a decision before 1.0 (§7.3).
- Validation of constraints (R6.7), NDJSON (R12.6).
- Size limits: an SSE line and the body of an SSE error are read into memory without a limit (like any body in Dio).
