## 0.0.1 - Unreleased

### Added
- M11b: the package is renamed from `typed_openapi_runtime` and is Dio-free
  (it depends on `meta` only). `ClientTransport` is the contract a
  transport implements, with `TransportRequest` and `TransportResponse`
  (lower-case header names, a body stream read once); `ClientSender`
  replaces `DioRequestSender`; `CancelSignal` replaces Dio's `CancelToken`
  in `CallOptions.cancel`; `TransportException` has the kinds `timeout`,
  `connection`, `cancelled` and `other`, and `TransportError` and
  `Cancelled` carry one. The Dio adapter is the new `typed_openapi_dio`.
- Request body encoding (JSON, form, multipart, text, bytes) and the send
  and receive progress counting moved from the Dio adapter into the core
  (`BodyEncoder`, `MultipartEncoder`, `ProgressCounter`), so a request is
  the same on the wire through any transport. A multipart file part with no
  media type is sent as `application/octet-stream` (Dio guessed one from
  the file name).
- `JsonReader.constant` returns whether the constant was there, so a
  generated model can leave out of `toJson` an optional constant the JSON
  did not have (M11).
- `Patch<T>` for three-state request fields.
- `JsonReader`, `JsonDecodeException` and `JsonValue`: strict JSON decoding
  that reports the JSON pointer of the first mismatch.
- `Date` for `format: date`, with `JsonReader.asDate`.
- `Result<T, E>` with `Success`, `HttpError`, `UndocumentedStatus`,
  `DecodeError`, `TransportError` and `Cancelled`.
- Encoders for OpenAPI path, query, header and cookie parameter styles.
- `OperationInfo`, `OperationRequest` and `RawResponse`.
- `ClientSender` and `CallOptions`: requests through a `ClientTransport`.
- `SseDecoder` (WHATWG event stream format), `SseItemDecoder` and the
  `SseItem` stream items; `ClientSender.openEvents`.
- For generated models: `DeepEquality` (deep `==` and `hashCode` of lists,
  maps and patches), `JsonReader.constant`, `JsonReader.additional`,
  `JsonReader.asBytes`, and `immutable` re-exported from `package:meta`.
- For generated operations: `FileUpload` (bytes or a stream, with a file
  name and a media type), `FormBody` and `FormEncoding`
  (`application/x-www-form-urlencoded` with the spec's `encoding`),
  `MultipartBody` (also `MultipartBody.fromJson`) and `MultipartPart`
  (a file part takes the spec's media type when the file has none; the
  parts are sent in order, so a text part after a file or a typed part has
  `Content-Type: text/plain; charset=utf-8`, while one before them has no
  `Content-Type`; a value that cannot be a part is `ArgumentError`);
  `BodyEncoder` turns them into
  bytes, so generated signatures have no transport types.
- Security metadata for interceptors: `OperationInfo.security` with
  `SecurityUse`, `SecurityScheme`, `SecuritySchemeType` (with `unknown` for
  a scheme the spec names but does not define) and `SecurityLocation`.
- `RawResponse.parsedJson` (a JSON error body of a text or binary
  operation), `RawResponse.text` of a body read as bytes, a depth check in
  `RawResponse.parse`, and `OperationRequest.pathVariable`, the one pattern
  of a path variable (`{}` is a variable with an empty name).
- Event stream reconnection (M10, R12.5): `SseOptions` (`reconnect`, `delay`,
  `maxDelay`, `maxAttempts`, `wait`) in the new `CallOptions.sse`,
  `SseReconnection` (what a generated method says: `off`, `onRequest`,
  `on`; the `reconnection` argument of `openEvents`), `SseReconnector` and
  `SseResume` (where a new connection starts), and the stream item
  `SseReconnecting`. A reconnecting stream sends the last event id as
  `Last-Event-ID`, waits the server's `retry` (else 1 s, doubling to a 30 s
  cap; a server `retry` over the cap is kept), and stops after 5 attempts in
  a row that bring no message (an event, one that does not decode, or one
  the program drops; comments, or blocks with only an `id:` or a `retry:`,
  are not messages). A 204, an error status and a cancel end the stream, a
  `TransportException` of any kind except cancelled is the next attempt;
  the stream forwards an error that a throwing `wait` or the transport
  raises, and carries a pause to the new
  connection. A listener that cancels aborts a request in flight and stops
  the wait.
- `SseEventIgnored`, which a generated decoder throws for an event the
  stream drops (`sse.unknown: ignore`); the dropped event's id and `retry`
  still count.
- `SseDisconnected.lastEventId` (a `String`; `''` is none), `retry` and
  `receivedMessage`. A block with only an `id:` or `retry:` sets them, as
  the WHATWG parser does at every empty line (`SseBlockDecoder`).
- `OperationRequest.accept`: the `Accept` of the method that returns the
  body of an operation that also returns events; a `CallOptions.headers`
  `Accept` (any case) still wins.
- A `Last-Event-ID` in `CallOptions.headers` starts the stream's last event
  id: it is sent with the first request and the reconnections until an event
  `id` replaces it, and an empty `id:` removes it. An id that is not
  printable ASCII is not sent, on the VM and on the web (the VM's
  `HttpClient` throws on it, which would fail every reconnection); the
  stream reconnects without `Last-Event-ID`.

### Changed
- `DecodeError` for invalid JSON carries the status and the body text.
- `OperationInfo.of` moved to `DioTransport.operationOf` in
  `typed_openapi_dio`; `OperationInfo` is in every `TransportRequest`.
- The hint of the `date` and `date-time` decode errors no longer names an
  internal requirement id; the `SseOptions.wait` doc comment describes the
  cancellable timer it uses by default.
- Breaking: `SseItem` has a new subtype, `SseReconnecting`, so an
  exhaustive `switch` over `SseItem` stops compiling until it handles it.
