# Client defaults and stream open retry (0.3.0)

Status: draft for the owner's review. Release: 0.3.0 of the four packages
(lockstep). The owner has said that backward compatibility does not matter
for this release, so this design changes the API and the generated output
where that gives a cleaner result.

## Why

The Zeely app (Flutter, Dio, one DI module that builds the transport and
every generated client) reads long-lived SSE streams through clients
generated against `typed_openapi_client` 0.2.0. Two problems remain:

1. It passes the same `SseOptions` to every stream call: `reconnect: true`,
   unlimited attempts, jitter 0.2, a cooldown of 5 min after 10 failed
   attempts, `idleTimeout` 60 s, `handshakeTimeout` 30 s, and `onTrace`
   sending to a debug panel.
2. It wraps every stream in a loop of its own, for two reasons. When the
   first attempt fails, the call returns a `Failure` and never retries. When
   a reconnection gets a status that is not a stream (502 from a load
   balancer, say), the stream ends. Each of these loops leaves out the
   library's backoff, jitter, cooldown and tracing.

Success: the app passes its options once, in its DI module, and deletes
every reopen loop. The library then keeps a stream alive through transient
failures, both when it opens and when it reconnects. It stops on failures
that retrying cannot fix (401, 404, ...), and those stay visible as typed
results.

## Goals, non-goals, anti-goals

Goals:

- Default `CallOptions` given once per client, merged with each call's
  options field by field.
- `SseTrace` names the operation, so one shared `onTrace` can tell the
  streams apart.
- Opening a stream is retried on transient failures, with the backoff,
  jitter, cooldown and attempt limit that reconnection already uses.
- One classification decides "transient or final", the same for opening and
  for reconnecting. The user can override it.

Non-goals:

- Retrying plain (non-stream) requests. `ClientSender` still never retries
  a request; that belongs to the transport, for example a Dio interceptor.
- Per-operation defaults (a different `SseOptions` per stream). A call can
  still pass its own options. See the alternatives below.
- Token refresh on 401. That belongs to the transport's interceptors.

Anti-goals (the design fails if any of these happens):

- The stream emits an error, or a `Future` completes with an error, for
  anything other than an `Error` thrown by user code.
- Cancelling waits for a backoff or a handshake to finish.
- A stream retries forever on a failure that retrying can never fix: a 401,
  a bad certificate, or Dio refusing event streams on the web.
- A non-idempotent request is sent again without the user's opt-in (POST
  streams).
- A `null` in user code silently changes meaning between 0.2.0 and 0.3.0.

## Current behaviour (facts, `main` at 887e4b7)

- A stream method returns `Future<Result<Stream<SseItem<T>>, E>>`, built as
  `_sender.openEvents(OperationRequest(_op, ...), decode, decodeError, call: call)`.
  Group classes are `Group(ClientTransport transport) : _sender = ClientSender(transport)`.
  The root class is `Root(ClientTransport transport) : a = A(transport), ...`.
- Every operation has a `static const OperationInfo` with `operationId`,
  `method`, `pathTemplate`, `tags` and `security`.
- `EventOpener._openReconnecting` (event_opener.dart:212) wraps the stream in
  `SseReconnector` only when the first result is a `Success` that is not a
  204 and the policy reconnects. Any other first result is returned as it
  is: no retry.
- On a reconnection (`SseReconnector._resume`, sse_reconnector.dart:176):
  - A `TransportError` of any kind is retried.
  - `Cancelled` ends the stream.
  - Any other `Failure` (`HttpError`, `UndocumentedStatus`, `DecodeError`)
    ends it with `SseDisconnected(cause: failure)`. This includes 408, 429
    and 5xx.
- `ReconnectionPlan` counts failed attempts. A connection that delivered a
  message resets the count. A server `retry:` replaces the base delay, and
  jitter is not applied while it is in effect. The cooldown resets the
  count.
- `SseTrace` has `kind`, `streamId` (a process-wide counter), `attempt`,
  `statusCode`, `event`, `eventId`, `delay`, `error` and `stackTrace`. It
  does not name the operation. A first result that is a failure is traced
  as `error` then `closed`.
- `HttpError` and `UndocumentedStatus` carry `statusCode` and `headers`
  (lower-case names). `DecodeError` carries `statusCode?` and `headers`.
- `DioTransport` throws `TransportException(.other, webStreamingMessage)`
  when the web default adapter is asked for an event stream. Dio's
  `badCertificate`, `badResponse` and `unknown` errors also map to `.other`.
- No merge code and no client-level defaults exist.

## Part 1: default call options

### Where the defaults live

Approaches considered:

| | Approach | For | Against |
| --- | --- | --- | --- |
| A | A capability interface on the transport (`DioTransport(dio, defaults:)`; `ClientSender` checks `transport is CallDefaults`) | Generated code unchanged | Puts client semantics (SSE policy, operation headers) into the HTTP layer. Hidden `is` check. Every transport must implement it. Two clients over one Dio cannot have different defaults. |
| B | **A constructor parameter of the generated root and group classes**, passed to `ClientSender` | Explicit and typed. Lives where the semantics live. Per client. No `is` check. The transport stays the user's HTTP client. | Changes the generated output: two lines per group and the root. Every client regenerates. |
| C | A wrapper transport (`DefaultedTransport(inner, defaults)`) | Generated code unchanged | The owner rejected wrappers. Same layering problem as A. |
| D | A resolver `CallOptions Function(OperationInfo)` instead of a value | Per-operation defaults | No user needs it yet. A plain value covers Zeely. It can be added later as a second constructor without breaking the first. |
| E | Global or zone-based defaults | None | Hidden state across clients and tests. |

Decision (recommended, pending the owner): **B**. Backward compatibility is
not a constraint, and the app builds clients in one DI module, so the
constructor is the natural place. Generated shape:

```dart
class CoreApiClient {
  CoreApiClient(ClientTransport transport, {CallOptions defaults = const CallOptions()})
    : pets = PetsApi(transport, defaults: defaults), ...;
}

class PetsApi {
  PetsApi(ClientTransport transport, {CallOptions defaults = const CallOptions()})
    : _sender = ClientSender(transport, defaults: defaults);
}
```

`ClientSender(transport, {defaults, boundary})` merges once per call, at the
top of `send` and `openEvents`. `RequestBuilder` and everything after it
receive the merged `CallOptions` and do not change. An `implements` fake of a
group class is not affected. `DioTransport` does not change, so
`typed_openapi_dio` 0.3.0 is again a version-only release (lockstep).

### Merge rules

One rule everywhere: **a value the call sets wins; a value it leaves unset
falls back to the default**. Maps are merged key by key.

| Field | Merge |
| --- | --- |
| `cancel` | `call.cancel ?? defaults.cancel`. A default signal cancels every call that does not bring its own, for example on logout. It is not combined with the call's signal: a combined signal needs a listener on the long-lived default signal for each call, which leaks unless removed. |
| `headers` | Union. The call wins per name, case-insensitively, and keeps its own spelling. A `null` value in the call removes a default header, which matches the existing rule that a `null` header is not sent. |
| `extra` | Union. The call wins per key. A `null` value is a value: `extra` is opaque to the client. |
| `onSendProgress`, `onReceiveProgress` | `call ?? defaults`. |
| `sse` | `SseOptions.merge`, field by field, below. A plain request ignores `sse`. |

### `SseOptions`: unset versus value

Merging field by field needs every field to tell "not set" from a value.
Today `delay`, `maxDelay`, `maxAttempts` and `jitter` have non-null defaults,
and `maxAttempts: null` means "never give up".

Design:

- Every field is nullable and `null` means unset. The resolved settings
  (`SseSettings`, internal) apply the built-in defaults once, after merging:
  `delay` 1 s, `maxDelay` 30 s, `maxAttempts` 5, `jitter` 0. The public
  fields hold what the user wrote.
- `maxAttempts`: the owner agreed to keep `maxAttempts: null` meaning
  "never give up", so code written for 0.2.0 keeps its meaning. Leaving the
  parameter out is "unset". This uses a private sentinel default value,
  which the resolved settings never expose. It is the one field where an
  explicit `null` is a value. (Alternative: `null` means unset and
  `SseOptions.unlimited` means never. It is cleaner, but code that passes
  `maxAttempts: null` today would silently get 5 attempts, which the
  anti-goals forbid.)
- Merging `maxAttempts`:
  - a call that passes `null` wins (unlimited), and so does a call that
    passes an int;
  - a call that leaves it out inherits the default's value, unlimited
    included.

  The public `maxAttempts` field returns what the user wrote. A private
  flag tells "left out" from "`null`", and the resolved settings read that
  flag.
- `retryOpen` and `retryWhen` merge like every other field. A call cannot
  unset a default `retryWhen`, but it can pass `SseRetry.isTransient`,
  which is the built-in classifier.
- A call that needs to switch off a default writes the "off" value:
  - `Duration.zero` for `idleTimeout` and `handshakeTimeout`;
  - `jitter: 0`;
  - `SseCooldown.none` (new) for `cooldown`;
  - `retryOpen: false`.

  `onTrace`, `random` and `wait` have no off value; a call that wants no
  trace passes `(_) {}`.

### The operation in the trace

`SseTrace.operation` (`OperationInfo`: `operationId`, `method`,
`pathTemplate`, `tags`). `SseTracer` receives `request.operation` from the
`EventCall`. `streamId` still tells apart two streams of one operation.
`toString` gains `operationId`.

Considered and left out: the resolved target path (`/users/42/inbox`). It
can carry identifiers into a log, and `streamId` already separates the
streams. Easy to add later.

## Part 2: retrying the opening of a stream

### The shape of the result

| | Approach | For | Against |
| --- | --- | --- | --- |
| P1 | **The `Future` waits**: it completes when the stream opens, on a final failure (typed `Failure`), or with `Cancelled` | The brief asks for it. Keeps the typed result of the opening, which one-shot POST streams (LLM chat) want. No change to the return type. | While it retries, the caller sees progress only through `onTrace`. Cancelling during that time is only possible through `call.cancel`, because there is no listener yet. A 401 when opening and a 401 when reconnecting arrive in two places (`Failure` and `SseDisconnected.cause`). |
| P2 | Stream first: the method returns a stream at once (or the `Future` resolves at once). Open failures become items (`SseReconnecting`, then `SseDisconnected(cause: Failure)`). | One state machine. The UI sees the retries. A listener cancel works during the open. One place for a 401. | Loses the typed open `Result`, which hurts request-like streams. Changes every stream method's return type and every consumer. Opens on listen. |

Decision (recommended): **P1**. Its one real cost, cancelling through
`call.cancel` only, is acceptable: the app already holds a signal per
stream. The docs show the pattern. A default `cancel` (merge rules) covers
"cancel everything".

### When the opening is retried

- `SseOptions.retryOpen` is a `bool?`. When it is unset, it follows the
  reconnection policy: the opening is retried exactly when the stream would
  reconnect (`SseReconnection.reconnects(settings)`). The app's defaults
  (`reconnect: true`) therefore turn on both, and a stream that reconnects
  after a drop also survives a bad first attempt. `retryOpen: false` keeps
  the 0.2.0 fail-fast opening, for example to report a misconfigured
  endpoint at startup.
- An opening is never retried on a stream whose policy does not reconnect:
  a POST without the `reconnect` override, `.off`. That holds even with
  `retryOpen: true`, because the server may have received the request
  (idempotency). `.off` wins silently, with no assert: shared defaults
  reach every stream, POST streams included, and must not throw there. The
  docs say so.
- An opening is never retried, and a stream never reconnects, when the
  request body cannot be sent twice: a `FileUpload.stream` body, or a
  multipart part with one. The failure is returned, or the stream ends. A
  second send would read a single-subscription stream again and throw a
  `StateError`. The check reads the `OperationRequest` body; a test covers
  it.
- Default change: a GET stream with `reconnect: true` now also retries its
  opening. The owner allows this.

### Classification: transient or final

One classifier, `SseRetry.isTransient(Failure failure)` (public static, so a
user override can extend it rather than restate it), used for every failed
attempt: the opening and every reconnection.

| Failure | Default | Why |
| --- | --- | --- |
| `Cancelled` | final, never classified | A cancel is not a failure. `retryWhen` never sees it. |
| `TransportError`, kind `connection` | transient | Network down or reset. |
| `TransportError`, kind `timeout` (handshake timeout, the transport's own timeouts, an idle timeout during the opening) | transient | |
| `TransportError`, kind `other` | **final** | Dio's `badCertificate`, `badResponse`, `unknown`, and the web refusal of event streams. Retrying cannot fix them, and with unlimited attempts they would loop forever. This changes reconnection, which retries every `TransportError` today. |
| status 408, 429 | transient | |
| status 500, 502, 503, 504 and other 5xx | transient | |
| status 501, 505 | final | Not implemented, HTTP version not supported: retrying cannot help. |
| any other status (400, 401, 403, 404, 409, 410, 422, a 2xx or 3xx that is not a stream status) | final | |

- The status is read from `HttpError`, `UndocumentedStatus` and
  `DecodeError`. A `DecodeError` with a status is classified by that status:
  a 503 from a load balancer with an HTML body, on an operation that
  documents 503 as JSON, is a `DecodeError(statusCode: 503)` and must be
  transient.
- A documented 5xx (`HttpError`) is transient by its status. The brief says
  "documented errors are final", but a 503 in the spec and a 503 from a
  proxy are the same event.
- A `DecodeError` without a status (a decoder that failed on a 2xx body) is
  final.
- The classifier sees only failed attempts to open a connection: the first
  one and every reopen. A connection that opened and then ended (the server
  closed it, the body failed, the idle timeout expired) is not classified.
  It reconnects as in 0.2.0.
- A 204 that is a stream status is not a failure. It ends the stream as
  today and is never retried.

`SseOptions.retryWhen: bool Function(Failure<Object?> failure)?` replaces the
default when set. Example: `retryWhen: (f) => SseRetry.isTransient(f) || f is TransportError`.
An `Exception` thrown by `retryWhen` is swallowed and counts as final (the
failure is returned or ends the stream). An `Error` propagates as it does
for every user callback.

### Delays: backoff, jitter, cooldown, `Retry-After`

- Opening and reconnection share one `ReconnectionPlan` per call: one
  count of failed attempts, one cooldown. A failed opening is a failed
  attempt. A connection that delivers a message resets the count, as today.
- `attempt` (in `SseTrace` and `SseReconnecting`) is the plan's count of
  failed attempts in a row, as today, so it restarts at 1 after a message.
  `maxAttempts` is the number of retries after a failure: with 5, an
  opening is tried at most 1 + 5 times. A drop is followed by at most 5
  reopens, as in 0.2.0. When it is used up, the opening completes with the
  last `Failure` (not the first) and a reconnection ends with
  `SseDisconnected(cause: last failure)`.
- `Retry-After` is read on any transient status that carries it (429, 503,
  and any other):
  - It can be delta-seconds, or an HTTP-date in any of the three forms RFC
    9110 requires recipients to accept (IMF-fixdate, RFC 850, asctime). It
    is parsed by a small parser in `sse/`; `HttpDate` is `dart:io` and does
    not work on the web.
  - A date is measured against the response's `Date` header, which avoids
    clock skew, or against `DateTime.now()` when there is none.
  - The delay of that attempt is `max(Retry-After, the backoff delay)`. The
    backoff is computed as usual, jitter included. A server that says "not
    before" is honoured, and a herd of clients still spreads out.
  - `maxDelay` does not cap it, as it does not cap `retry:`.
  - It applies to that attempt only; it does not stick the way `retry:`
    does.
  - A value that cannot be parsed, or that is zero or in the past, falls
    back to the backoff delay.
- The server's `retry:` keeps its meaning.

### Tracing the attempts of an opening

For each failed attempt: `connect(attempt)`, then `open(status)` when a
status arrived, then `error(failure)`, then `reconnecting(attempt, delay)`.
On success, the stream's traces follow under the same `streamId`. On a
final failure or when attempts run out: `error`, then `closed`. A cancel
during the backoff: `closed`.

### Cancel

- During the backoff of an opening, `call.cancel` (or the default
  `cancel`) completes the `Future` with `Cancelled` at once. The wait's
  timer is stopped, as `CancellableWait` does today.
- During a handshake, the request is cancelled at once (`Handshake` already
  races `whenCancelled`).
- After the stream opened, the existing rules apply: a listener cancel
  aborts the request and the waits.

### Other cases

- **Request bodies.** A POST stream that reconnects (override `on`) sends
  its body again on every attempt. A `FileUpload.stream` body can be read
  once, so the first attempt that consumed it makes the next attempt fail.
  The builder must check what reconnection does today. Recommended: an
  operation whose body cannot be replayed is not retried (the failure is
  returned or ends the stream), and the docs say so.
- **The user's `Last-Event-ID`** is sent on every attempt of the opening.
- **`onSendProgress`** starts again on each attempt.
- **Dio retry interceptors** (dio_smart_retry and similar) would multiply
  the attempts. The docs advise leaving event streams out of them.
- **The web**: Dio's default adapter refusal is `.other`, which is final,
  so it does not loop.
- **`maxAttempts: 0`**: no retries. The opening behaves as in 0.2.0, and a
  drop ends the stream.

## API summary (what the app writes)

```dart
final client = CoreApiClient(
  DioTransport(dio),
  defaults: CallOptions(
    sse: SseOptions(
      reconnect: true,
      maxAttempts: null, // never give up
      jitter: 0.2,
      cooldown: SseCooldown(after: 10, duration: Duration(minutes: 5)),
      idleTimeout: Duration(seconds: 60),
      handshakeTimeout: Duration(seconds: 30),
      onTrace: (t) => debugPanel.add('${t.operation.operationId} $t'),
      // retryOpen: unset, follows reconnect -> on
    ),
  ),
);

// A call: no options, or only what differs.
final result = await client.customerEvents.inboxUnreadCount(call: CallOptions(cancel: signal));
switch (result) {
  case Success(:final data): ... // the stream; reconnects and retries inside
  case Failure() : ...          // final: 401, 404, attempts used up
}
```

The app deletes its per-call options and its reopen loop.

## Changes by package

- `typed_openapi_client`:
  - `CallOptions.merge`;
  - `SseOptions`: nullable fields, `merge`, `retryOpen`, `retryWhen`;
  - `SseCooldown.none`, `SseRetry` (the classifier), the `Retry-After`
    parser, and `SseSettings` (internal);
  - `SseTrace.operation`;
  - `ClientSender(defaults:)`;
  - `EventOpener`: the opening goes through the plan;
  - `SseReconnector`: classified failures.

  `event_opener.dart` (196) and `sse_reconnector.dart` (222) must not grow
  past 300: the opening loop goes into a collaborator (for example
  `StreamOpening`).
- `typed_openapi` (generator):
  - The root and group constructors take `defaults` (`api_library.dart`,
    `operation_emitter.dart` at 287 lines: extract first).
  - The output changes, so `corpus.lock` is updated and the CHANGELOG gets
    `### Output changes`.
  - `pets_api.dart` and the docs of the generated client are updated.
- `typed_openapi_core`:
  - `RootNames` and the group constructor reserve `defaults`, as `transport`
    is reserved, so that a group named `defaults` gets a suffix (TOA551) and
    never shadows the parameter;
  - `DartNames.takenTypeNames` reserves the new public client types
    (`SseRetry` and any other).
- `typed_openapi_dio`: version only.
- Docs:
  - `doc/sse.md` gets defaults, merge rules, the opening retry, the
    classification table, `Retry-After`, the trace operation, and the
    cancel pattern;
  - `doc/generated/event_streams.md` (reconnection section) and the
    generated-client docs (`getting_started.md`) cover the constructor
    `defaults`;
  - CHANGELOGs; all four packages go to 0.3.0.
- Rides along (the owner asked for no separate tidy PRs):
  - the ubuntu-24.04 pin (commit c12489f);
  - the schema URLs move from `typed_openapi-v0.1.0` to
    `typed_openapi-v0.2.0`.

## Tests (deterministic: fake or scripted transport, fakeAsync)

Defaults and merge:

- defaults applied with no call options;
- a call that sets only `reconnect: false` keeps the default timeouts;
- headers merged case-insensitively, and a `null` call value removes a
  default header;
- `extra` merged;
- `cancel` fallback;
- `Duration.zero` switches off a default timeout;
- `SseCooldown.none`;
- `maxAttempts`: omitted inherits, `null` means unlimited.

Trace: the trace carries the operation.

Opening:

- retried on 503 and on a connection error, then opens;
- 404 returned without retry, 401 too;
- 429 with `Retry-After` in seconds and as a date (against `Date`);
- a past date falls back to the backoff;
- `DecodeError(503)` is transient;
- 501 is final;
- `TransportError(.other)` is final;
- `maxAttempts` used up returns the last failure;
- the cooldown applies at the opening;
- a cancel during the backoff completes with `Cancelled` at once (no
  timer left);
- `retryOpen: false` fails fast;
- a POST with `.off` is never retried, even with `retryOpen: true`;
- a `FileUpload.stream` body is never sent twice;
- `retryWhen` replaces the default, and one that throws an `Exception`
  counts as final;
- the trace sequence of a retried opening.

Reconnection:

- 502 continues;
- 401 ends with `SseDisconnected(cause: HttpError)`;
- `Retry-After` on a reconnection;
- `.other` ends.

Generated: `generated_client_test` (constructor `defaults`, `implements`
fake), corpus, fuzz.

## Decisions for the owner

1. Where the defaults live: **B**, the generated constructors (output
   change), rather than A, the transport.
2. The shape of the opening: **P1**, the `Future` waits, rather than P2,
   stream first.
3. `retryOpen` unset follows the reconnection policy, so `reconnect: true`
   also retries the opening.
4. `TransportError(.other)` is final by default (changes reconnection).

## Left to the builder

- Names of the internal classes, and how the opening loop and the
  reconnector share the plan.
- The exact parser of `Retry-After`.
- The wording of the docs.
- The order of the commits (a refactor commit before any growth of a file
  near the limit).
