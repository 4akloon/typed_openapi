## 0.3.0

### Added
- Default call options: `ClientSender(transport, defaults:)` and
  `CallOptions.merge`. A value the call sets wins, one it leaves unset falls
  back to the default; headers and `extra` are merged key by key. The
  generated root and group classes pass `defaults` down.
- `SseOptions.merge`, `SseOptions.retryOpen` and `SseOptions.retryWhen`,
  `SseCooldown.none`, and `SseRetry.isTransient`, the classifier of transient
  and final failures.
- A stream that fails to open is retried on transient failures, with the
  backoff, jitter, cooldown and attempt limit of a reconnection. The `Future`
  waits; a cancel through `CallOptions.cancel` ends it at once. `Retry-After`
  (delta-seconds or an HTTP date) lengthens the delay of one attempt.
- `SseTrace.operation`: the `OperationInfo` of the stream, so one shared
  `onTrace` can tell the streams apart.

### Changed
- Default headers sit under the operation's headers, the call's over them: a
  default `Accept` no longer replaces `text/event-stream`, and a default header
  does not beat the header argument of a method.
- `Retry-After` is cut to 24 hours.
- An `Exception` thrown by `SseOptions.wait` now ends the stream with
  `SseDisconnected` (an `Error` is still the stream's error).
- Every `SseOptions` field is nullable, `null` meaning unset; the built-in
  values apply after the merge. `maxAttempts: null` still means never give
  up, and leaving the argument out means unset.
- `SseOptions.delayBefore` is internal, and `SseReconnector` and `SseResume`
  are no longer exported.
- A GET stream with `reconnect: true` also retries its opening.
- A reconnection retries 408, 429 and 5xx statuses and stops on a
  `TransportError` of kind `other` (it retried every `TransportError`
  before); other statuses still end the stream.
- A request body that cannot be sent twice (`FileUpload.stream`, or a
  multipart part with a stream file) is never retried, and its stream no
  longer reconnects after it opened.

## 0.2.0

### Added
- Event stream resilience, all opt-in in `SseOptions` (the defaults are the
  0.1.0 behaviour); the generated output does not change.
  - `idleTimeout`: the longest silence on a connected stream. Any received
    bytes, comments included, reset it; on expiry the request is cancelled and
    the stream reconnects (or ends with `SseDisconnected`) with a
    `TransportException` of kind `timeout` as the cause.
  - `handshakeTimeout`: bounds the wait for the response headers of each
    attempt; a failed attempt, like a refused one.
  - `maxAttempts` may be `null` (never give up); `jitter`, `random` and
    `cooldown` (`SseCooldown`) shape the backoff: a long pause after many
    failed attempts in a row, after which the count starts again.
  - `onTrace` with `SseTrace` and `SseTraceKind`: connect, open, event,
    heartbeat, error, reconnecting and closed, with a correlation id per call.
    It does not change the items; an `Exception` it throws is ignored.
  - A delay that comes from the server's `retry` and the `cooldown` pause are
    not jittered. A `maxAttempts` larger than `cooldown.after` never ends the
    stream, because the cooldown starts the count again.
  - A cancel while the response headers are awaited ends the stream at once,
    also when the transport does not honour the cancel.
- `SseItemDecoder` takes `onMessage` and `onComment`.

### Changed
- `SseOptions.maxAttempts` is `int?`.

## 0.1.0

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
