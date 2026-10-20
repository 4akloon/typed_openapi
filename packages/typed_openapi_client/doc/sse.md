# Server-Sent Events

An operation whose success is a `text/event-stream` is generated as a method
that returns `Future<Result<Stream<SseItem<T>>, E>>` and calls
`ClientSender.openEvents`. The `Result` tells you whether the stream
opened; the `Stream` is a sequence of typed items that follows the WHATWG
event-stream rules, optionally reconnects with `Last-Event-ID`, and always
ends with one `SseDisconnected`. Problems with the data are items, never
stream errors.

```dart
switch (await api.pets.watchPet(petId: 7)) {
  case Success(:final data):
    await for (final item in data) {
      switch (item) {
        case SseEvent(:final data):            // decoded event data
          show(data);
        case SseDecodeError(:final error):     // one bad event; the stream goes on
          log(error);
        case SseReconnecting(:final attempt):  // before each reconnection attempt
          showRetrying(attempt);
        case SseDisconnected():                // always the last item
          break;
      }
    }
  case Failure():                              // did not open
    handle();
}
```

## The call

```dart
Future<Result<Stream<SseItem<T>>, E>> openEvents<T, E>(
  OperationRequest request,
  T Function(SseMessage message) decodeEvent,
  Result<Stream<SseItem<T>>, E> Function(RawResponse response) decodeError, {
  CallOptions? call,
  SseReconnection reconnection = .onRequest,
})
```

A generated method passes `streamStatuses` (the documented 2xx statuses that
carry the stream; a range is expanded) in the `OperationRequest`.

- A status in `streamStatuses` gives `Success(stream)`; the request is sent
  with `Accept: text/event-stream` and read as a stream.
- Any other status reads the **whole body** and decodes it with
  `decodeError`, exactly like a normal response: `HttpError`,
  `UndocumentedStatus` or `DecodeError`. An error body is read to the end, so
  it must be finite.
- A `TransportException` of the transport is mapped as in
  [Results and errors](results_and_errors.md): `TransportError`, `Cancelled`.
- `streamStatuses` must not be empty (an `assert`): without it every status
  would be read to the end, and an endless stream would fill memory. A
  generated method always sets it.

> **Gotcha:** The stream holds the connection open. Listen to it or cancel
> it; an unlistened stream keeps the connection open. Cancelling the
> subscription closes the connection.

## The items

| Item | When | Fields |
| --- | --- | --- |
| `SseEvent<T>` | An event whose data decoded as `T` | `data`, `event` (default `message`), `id`, `retry` |
| `SseDecodeError<T>` | One event whose data does not match its schema; later events still come | `error` (`JsonDecodeException`), `message` (the `SseMessage` as received) |
| `SseReconnecting<T>` | The connection ended and the stream will reconnect after a wait | `attempt` (from 1), `delay`, `cause`, `stackTrace` |
| `SseDisconnected<T>` | The end; **always the last item** | `cause`, `stackTrace`, `lastEventId`, `retry`, `receivedMessage` |

`SseEvent.id` and `retry` are the stream's **last** id and retry, which
persist across events as WHATWG says, not the ones of that event alone.
`SseDisconnected.cause` is `null` when the server closed the connection, else
the error: usually a `TransportException` (kind `cancelled` for a cancelled request),
or, when a reconnection is answered with a final status that is not a
stream, the `Failure` of that answer (`UndocumentedStatus(404)`, an
`HttpError`, ...).
`SseDisconnected.lastEventId` is `''` when there was none and the same id a
reconnection would send as `Last-Event-ID`, so you can resume yourself.

The stream **never emits errors**, with one exception: an `Error` (a
`TypeError`, `StateError`) thrown by your event decoder is a bug of the
program, so it reaches the listener as a stream error and the stream closes.
A `FormatException` of a converter or `Date.parse` is data: an
`SseDecodeError`.

### Example

The server sends (comments, CRLF, an id, an ignored `ping` event, data on two
lines, a bad object, text, and a block with only `retry` and `id`):

```text
: heartbeat
id: 1
data: {"text": "hello"}

event: ping
data: {}

data: {"text":
data: "two lines"}

data: {"oops": 1}

data: not json

retry: 3000
id: 2

data: {"text": "unfinished"}
```

The decoder (`ping` is dropped with `SseEventIgnored`, see below) produces,
in a run against an in-memory adapter:

```text
SseEvent(hello, event=message, id="1")
SseEvent(two lines, event=message, id="1")
SseDecodeError(/text: expected a required property, got no value)
SseDecodeError(: expected JSON event data, got text that is not JSON)
SseDisconnected(cause=null, lastEventId="2", retry=0:00:03.000000, receivedMessage=true)
```

The last event had no blank line after it, so it was discarded when the
stream ended. The block with `retry` and `id` produced no item but moved the
stream's id and retry, which `SseDisconnected` reports.

## Decoding rules (WHATWG)

`SseDecoder` turns bytes into `SseMessage`s following HTML "Interpreting an
event stream":

- Bytes are UTF-8: invalid sequences become U+FFFD, a leading BOM is dropped,
  a character split between chunks is kept whole.
- Lines end with CRLF, LF or CR, also when the CR and LF arrive in different
  chunks.
- Fields: `event`, `data` (several lines are joined by `\n`), `id` (ignored
  when it contains U+0000) and `retry` (ASCII digits only, otherwise
  ignored, and capped at 9007199254740 ms so every platform agrees). Other
  fields are ignored. A line starting with `:` is a comment. One leading
  space of a value is dropped.
- An empty line dispatches the event unless no `data` was seen. A block
  without `data` dispatches nothing, but its `id` and `retry` still count.
- An event not finished by an empty line when the stream ends is discarded.
- Malformed input never throws; errors of the source stream pass through.

`SseMessage` holds `event` (default `message`), `data`, `id` and `retry`.
`message.json` parses `data` (text that is not JSON, or nesting deeper than
1000 levels, is a `JsonDecodeException`) and `message.jsonObject` requires an
object. Use `transformer.bind(stream)`, not `stream.transform(...)`: a
transport gives a `Stream<Uint8List>`, which does not accept a transformer of
`List<int>` at run time.

```dart
final messages = await const SseDecoder().bind(Stream.fromIterable(chunks)).toList();
// the chunks split "é" (0xC3 | 0xA9) and the CRLF (\r | \n) in two
// [SseMessage(event: message, data: heéllo, id: , retry: null)]
```

### Unknown events

A generated union decoder throws `SseEventIgnored` for an event the stream
drops (the generator's `sse.unknown: ignore`). `SseItemDecoder` then emits no
item. The event still counts as a message that the connection delivered, and
its id and `retry` still move the stream's, as WHATWG keeps them. See the
[event streams guide](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/event_streams.md)
for how the generator picks the decoder.

## Reconnection

Reconnection is **off unless the call or the operation turns it on**:

| `SseReconnection` | Who sets it | Reconnects |
| --- | --- | --- |
| `off` | A non-GET that does not enable it, or an operation whose override turns it off | never; `CallOptions(sse: SseOptions(reconnect: true))` has no effect |
| `onRequest` (the default) | A GET | when `SseOptions.reconnect` is `true` |
| `on` | An operation that enables it (the `sse.reconnect` config key or override) | unless `SseOptions.reconnect` is `false` |

A `POST` is never repeated by default, because repeating the request may not
be safe. A call can turn reconnection on or off with `CallOptions.sse`:

```dart
final result = await api.pets.watchPet(
  petId: 7,
  call: CallOptions(sse: SseOptions(reconnect: true)),
);
```

### `SseOptions`

| Field | Default | Meaning |
| --- | --- | --- |
| `reconnect` | `null` | `true` / `false` as above; `null` keeps the operation's setting |
| `delay` | 1 s | The first delay when the server sent no `retry` |
| `maxDelay` | 30 s | The longest delay a doubling reaches |
| `maxAttempts` | 5 | Retries after a failure, in a row without a message; `null` never gives up (see [Defaults](#defaults-for-every-call) for omitted versus `null`) |
| `jitter` | 0 | Share (0 to 1) by which each backoff delay is moved at random either way |
| `cooldown` | `null` | `SseCooldown(after:, duration:)`: a long pause after many failed attempts in a row; `SseCooldown.none` switches a default off |
| `retryOpen` | `null` | Whether a failed opening is retried; unset follows `reconnect`, see [Retrying the opening](#retrying-the-opening) |
| `retryWhen` | `null` | Replaces the transient-or-final classifier, see [Which failures are retried](#which-failures-are-retried) |
| `random` | `null` | The `Random` of the jitter; a seeded one makes delays repeatable |
| `idleTimeout` | `null` | Longest silence on a connected stream; see [Long-lived streams](#long-lived-streams) |
| `handshakeTimeout` | `null` | Longest wait for the response headers of an attempt |
| `onTrace` | `null` | `void Function(SseTrace)`; a step-by-step trace, see [Tracing](#tracing) |
| `wait` | `null` | `Future<void> Function(Duration)`; a timer when `null`. Tests pass one that does not sleep |

The delay before attempt *n* is the server's last `retry` (else `delay`),
doubled each attempt up to `maxDelay`: with the defaults 1, 2, 4, 8 and 16 s
for the five attempts (a larger `maxAttempts` continues 30, 30 s). A server
`retry` longer than `maxDelay` is kept as it is. The default wait is a timer
that a cancel stops, so a cancelled stream does not keep the program alive.

### What happens when a connection ends

The connection ended (the server closed it, or it failed):

1. The stream emits `SseReconnecting(attempt, delay, cause)`; `cause` is
   `null` when the server closed the connection, else the error.
2. It waits `delay`.
3. It opens the request again with `Last-Event-ID` set to the last id.
4. The new connection's items follow. A failed attempt that counts as
   transient (see [Which failures are retried](#which-failures-are-retried))
   is the next attempt.

```text
SseEvent(a, event=message, id="41")
SseReconnecting(attempt=1, delay=250ms, cause=null)              <- server closed; its retry: 250
SseReconnecting(attempt=2, delay=500ms, cause=connectionError)   <- refused
SseEvent(b, event=message, id="41")
SseReconnecting(attempt=1, delay=250ms, cause=null)              <- a message resets the count
SseDisconnected(cause=null, lastEventId="41", retry=0:00:00.250000, receivedMessage=false)
Last-Event-ID per request: [null, 41, 41, 41]
waits: [0:00:00.250000, 0:00:00.500000, 0:00:00.250000]
```

The last answer was `204 No Content` (a status in `streamStatuses`).

The stream **ends** with `SseDisconnected` when:

- `maxAttempts` attempts in a row bring no message. A *message* is an event,
  an event that did not decode, or one the decoder dropped; a message on a
  new connection starts the count again, so a stream of ignored heartbeats is
  not given up. A connection that brings only comments, or blocks with just
  `id:` or `retry:`, does not reset it.
- The request is cancelled (see below).
- The server answers an attempt with a status that is not a stream and the
  failure is final (a 401, 404, ...): the `Failure` is the `cause`. A
  transient status (408, 429, most 5xx) and a `TransportError` of kind
  `connection` or `timeout` are retried instead; a `TransportError` of kind
  `other` ends the stream. For example, with an adapter whose second answer
  is `404`:

  ```text
  SseEvent(a, event=message, id="")
  SseReconnecting(attempt=1, delay=1000ms, cause=null)
  SseDisconnected(cause=UndocumentedStatus(404), lastEventId="", retry=null, receivedMessage=false)
  ```

- The server answers `204 No Content`, which tells a client to stop
  reconnecting.
- Giving up after five failed attempts (default options, first connection
  fine, every reconnection refused):

  ```text
  SseEvent(a, event=message, id="")
  SseReconnecting(attempt=1, delay=1000ms, cause=null)
  SseReconnecting(attempt=2, delay=2000ms, cause=connectionError)
  SseReconnecting(attempt=3, delay=4000ms, cause=connectionError)
  SseReconnecting(attempt=4, delay=8000ms, cause=connectionError)
  SseReconnecting(attempt=5, delay=16000ms, cause=connectionError)
  SseDisconnected(cause=connectionError, lastEventId="", retry=null, receivedMessage=false)
  ```

  That is six requests: the first and five reconnections.

An exception or `Error` thrown on an attempt, by a `wait` or an interceptor,
is the stream's one error, never the zone's.

### Long-lived streams

A stream that never ends needs bounds the transport cannot give it: a Dio
with `receiveTimeout` disabled waits forever on a socket that died while the
app was in the background. These options are opt-in; the defaults are the
behaviour above.

```dart
final result = await api.customerEvents.inboxUnreadCount(
  call: CallOptions(
    sse: SseOptions(
      reconnect: true,
      idleTimeout: Duration(minutes: 3), // above the server's heartbeat
      handshakeTimeout: Duration(seconds: 30),
      maxAttempts: null, // never give up
      delay: Duration(seconds: 1),
      maxDelay: Duration(seconds: 30),
      jitter: 0.2, // 80% to 120% of each delay
      cooldown: SseCooldown(after: 10, duration: Duration(minutes: 5)),
    ),
  ),
);
```

**Idle timeout.** `idleTimeout` is the longest silence on a connected
stream. Any received bytes reset it: events, but also comments such as
`: ping`. When it runs out the connection is treated as dead: the request is
cancelled and the stream reconnects if reconnection is on, with
`SseReconnecting.cause` a `TransportException` of kind `timeout`; without
reconnection it ends with `SseDisconnected` and that `cause`. The timer
stops while the listener is paused (nothing is read then) and starts again
on resume. Choose a value above the server's heartbeat interval.

**Handshake timeout.** `handshakeTimeout` bounds the wait for the response
headers of each attempt, the first and every reconnection. When it runs out
the request is cancelled and the attempt fails with a `TransportException`
of kind `timeout`: a failed attempt is retried like a refused connection (kind `timeout` is
transient; see [Retrying the opening](#retrying-the-opening)). Only when the
opening is not retried is a failed first attempt the `TransportError` the
method returns. It does not
limit how long the body takes.

**Unbounded attempts.** `maxAttempts: null` reconnects until the call is
cancelled, the listener cancels or the server answers with a final status
(or `204`). Transient failures keep being retried.

**Backoff.** The delay before attempt *n* is computed as above, then moved
by `jitter`: with `jitter: 0.2` a 4 s delay is a random value from 3.2 to
4.8 s. `maxDelay` caps the delay before the jitter is applied. The jitter is
not applied while the server's `retry` is in effect: a server that names a
time gets that time (and its doublings) exactly. Pass `random: Random(seed)`
for repeatable delays in tests.

**Cooldown.** After `cooldown.after` failed attempts in a row the next wait
is `cooldown.duration` instead of the backoff delay (reported as
`SseReconnecting` with attempt `after + 1`), and the count starts again, so
the backoff restarts from `delay` and `maxAttempts` counts the attempts of
one cycle. A message resets the count before that, as always. The cooldown
is not jittered and does not use the server's `retry`. If `maxAttempts` is
not larger than `after`, the stream ends before a cooldown; a `maxAttempts`
larger than `after` is inert, because the cooldown resets the count and the
stream never ends.

### Tracing

`SseOptions.onTrace` receives an `SseTrace` for each step of the stream. It
is meant for a debug panel or a log and never changes the items the stream
emits.

| `SseTraceKind` | When | Fields set |
| --- | --- | --- |
| `connect` | A request is about to be sent | `attempt`: the number of the connection (1, then 2 for the first retry or reconnection) |
| `open` | The response headers arrived | `statusCode` |
| `event` | A message arrived, also one that does not decode or that is dropped | `event`, `eventId` |
| `heartbeat` | A comment line arrived | |
| `error` | A connection ended with an error, or an attempt failed | `error` (a `TransportException`, or the `Failure` of a status), `stackTrace` |
| `reconnecting` | The stream waits before an attempt | `attempt`, `delay` |
| `closed` | The stream is over: its last item went out, or the listener cancelled | |

Every trace has `streamId`, the correlation id of the call: the same on all
its connections, different for every call in the program. It also has
`operation` (`OperationInfo`: `operationId`, `method`, `pathTemplate`,
`tags`), so one `onTrace` shared through the defaults can tell the streams
apart; `toString` prints the `operationId`. A typical stream:
`connect 1`, `open 200`, `heartbeat`, `event`, `reconnecting 1`,
`connect 2`, `open 200`, ..., `closed`.

The callback runs synchronously; keep it short. An `Exception` it throws is
ignored so that tracing cannot break the stream; an `Error` is a bug of the
program and is not caught, as elsewhere in the client.

### `Last-Event-ID`

- A reconnection sends the stream's last id as `Last-Event-ID`.
- An id that is not printable ASCII, space or tab is **not sent**, on the web
  too: a browser would send UTF-8, but the VM's `HttpClient` rejects it and
  every reconnection would fail. The reconnection goes on without it.
- You can start a stream from an id of your own: a `Last-Event-ID` in
  `CallOptions.headers` (any case) goes with the first request and the
  reconnections until an event's `id` replaces it, as `EventSource` does; an
  empty `id:` removes it. The stream's id is sent, never both.

```dart
await api.pets.watchPet(
  petId: 7,
  call: const CallOptions(headers: {'Last-Event-ID': '100'}), // first request: 100
);
```

## Defaults for every call

Give the options once, when the client is built. The generated root and group
classes take `defaults`, which the client merges with each call's
`CallOptions` before anything else reads them:

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

// A call passes nothing, or only what differs.
final result = await client.customerEvents.inboxUnreadCount(call: CallOptions(cancel: signal));
```

A value the call sets wins; a value it leaves unset falls back to the
default. `CallOptions.merge` and `SseOptions.merge` do this.

| Field | Merge |
| --- | --- |
| `cancel` | `call.cancel ?? defaults.cancel`. A default signal cancels every call that brings no signal of its own (a logout); it is not combined with the call's |
| `headers` | Union. The call wins per name, case-insensitively, and keeps its spelling. A `null` value in the call removes a default header |
| `extra` | Union. The call wins per key; a `null` is a value |
| `onSendProgress`, `onReceiveProgress` | `call ?? defaults` |
| `sse` | `SseOptions.merge`, field by field: a field the call leaves `null` takes the default's |

Every `SseOptions` field is nullable and `null` means unset; the built-in
values apply after the merge (`delay` 1 s, `maxDelay` 30 s, `maxAttempts` 5,
`jitter` 0). To switch a default off in one call, write the off value:
`Duration.zero` for `idleTimeout` and `handshakeTimeout`, `jitter: 0`,
`SseCooldown.none`, `retryOpen: false`. `onTrace`, `random` and `wait` have no
off value; pass `(_) {}` for no trace.

`maxAttempts` is the one field where `null` is a value. Leaving the argument
out is unset and inherits the default; writing `maxAttempts: null` means
never give up and wins over a default of 5. A call that leaves it out
inherits an unlimited default too.

A plain request ignores `sse`. `ClientSender(transport, defaults: ...)` takes
the same value if you build a sender by hand.

## Retrying the opening

A stream that fails to open used to return the `Failure` at once. Now the
opening is retried on transient failures, with the same backoff, jitter,
cooldown and attempt limit as a reconnection, and the failed attempts count
together with the reconnections of that call.

- The `Future` **waits**: it completes when the stream opens, with a final
  `Failure` (the last one when `maxAttempts` is used up), or with
  `Cancelled`. The caller sees the retries only through `onTrace`.
- Cancel through `call.cancel` or a default `cancel`; there is no
  subscription yet. A cancel during a backoff completes the `Future` with
  `Cancelled` at once, and a cancel during a handshake aborts the request.
- `SseOptions.retryOpen` unset follows the reconnection policy: the opening
  is retried exactly when the stream would reconnect. So a GET with
  `reconnect: true` also survives a bad first attempt. `retryOpen: false`
  keeps the fail-fast opening, for example to report a wrong endpoint at
  startup.
- A stream whose policy is `SseReconnection.off` (a POST that does not enable
  reconnection) is never retried, even with `retryOpen: true`: the server may
  have received the request. This wins silently, so shared defaults never
  throw on a POST stream.
- A body that cannot be sent twice (`FileUpload.stream`, or a multipart part
  with a stream file) is never retried and the stream never reconnects: the
  failure is returned or the stream ends.
- A `Last-Event-ID` in `call.headers` goes with every attempt.
- `maxAttempts` counts retries after a failure: with 5 an opening is tried at
  most 6 times. `maxAttempts: 0` keeps the old fail-fast opening.
- Keep event streams out of Dio retry interceptors (`dio_smart_retry` and
  similar): they would multiply the attempts.

For each failed attempt the trace is `connect`, `open` (when a status
arrived), `error`, `reconnecting`. On a final failure or when the attempts
are used up it is `error`, then `closed`. A cancel during the backoff gives
`error`, `reconnecting`, `error` (the cancel), `closed`.

### Which failures are retried

One classifier, `SseRetry.isTransient`, decides for every failed attempt, the
opening and each reconnection:

| Failure | Result |
| --- | --- |
| `Cancelled` | final, never classified |
| `TransportError` kind `connection` or `timeout` | transient |
| `TransportError` kind `other` (Dio's `badCertificate`, `badResponse`, `unknown`, the web refusal of event streams) | final |
| status 408, 429 | transient |
| status 5xx except 501 and 505 | transient |
| any other status (400, 401, 403, 404, 409, 410, 422, a 2xx or 3xx that is not a stream status) | final |
| `DecodeError` with a status | classified by that status |
| `DecodeError` without a status | final |

The status is read from `HttpError`, `UndocumentedStatus` and `DecodeError`,
so a 503 from a proxy with an HTML body is transient. A connection that
opened and then ended is not classified; it reconnects as before. A `204`
ends the stream and is never retried.

`retryWhen` replaces the classifier. Extend it rather than restate it:

```dart
SseOptions(retryWhen: (f) => SseRetry.isTransient(f) || f is TransportError)
```

An `Exception` thrown by `retryWhen` counts as final; an `Error` propagates.

### Retry-After

On a failure that is retried (the classifier, or `retryWhen`, accepts it) and carries `Retry-After` (delta-seconds or an HTTP
date in IMF-fixdate, RFC 850 or asctime form) the delay of that attempt is the
larger of the header and the backoff delay, jitter included. A date is
measured against the response's `Date` header, else the clock. `maxDelay`
does not cap it, and it does not stick to later attempts. A value that
cannot be parsed, or that is zero or past, falls back to the backoff.

## Cancel and pause

- **Cancelling the subscription** (`subscription.cancel()`) cancels the
  request and closes the connection, also one a reconnection has in flight.
  Use it when the screen goes away.
- **Cancelling `call.cancel`** (a `CancelSignal`, or the default `cancel`) ends the stream with a last
  `SseDisconnected(cause: TransportException(kind: cancelled))`, also during a wait:

  ```text
  [SseEvent(y, ...), SseDisconnected(cause=cancel, lastEventId="", retry=null, receivedMessage=true)]
  ```

- **Pausing** the listener pauses the connection. A pause during a wait or a
  reopen holds the next connection until you resume.
- A final error status at open (`401`) is not a stream: it is decoded by
  `decodeError`, here `UndocumentedStatus(401)`. A transient one (408, 429,
  5xx) is retried first when the opening is retried.

## Web

On the web, Dio's default browser adapter delivers a body only when the
connection closes, so a stream cannot work with it. `openEvents` then returns
a `TransportError` whose `exception.message` is
`DioTransport.webStreamingMessage` and `exception.cause` is an
`UnsupportedError`, before any request is sent. Set a fetch-based adapter on
your `Dio`, such as `ConversionLayerAdapter` from `dio_compatibility_layer`
with `package:http`'s `BrowserClient`, or `fetch_client`. A reconnection
sends `Last-Event-ID`, which is not a CORS-safelisted request header: for a
cross-origin stream the server must allow it in
`Access-Control-Allow-Headers` in its preflight answer, or every reconnection
that carries an id fails with a `TransportError`. See
[Web and platforms](web_and_platforms.md).

## Testing with a fake stream

Through `DioTransport`, `openEvents` needs only an `HttpClientAdapter`, so a
test feeds it bytes (a fake `ClientTransport` works the same way):

```dart
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.respond);
  final ResponseBody Function(RequestOptions options) respond;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
          Future<void>? cancelFuture) async => respond(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody events(String text, [int status = 200]) => ResponseBody(
  Stream.value(Uint8List.fromList(utf8.encode(text))),
  status,
  headers: {Headers.contentTypeHeader: ['text/event-stream']},
);

final adapter = FakeAdapter((_) => events('id: 1\ndata: {"text": "hello"}\n\n'));
final dio = Dio()..httpClientAdapter = adapter;
final transport = DioTransport(dio);
```

To test reconnection without sleeping, pass
`SseOptions(reconnect: true, wait: (_) async {})`; answer the first request
with a stream that ends, and later ones in order. A `StreamController` as the
body lets a test hold a connection open, then `add` bytes and `cancel` the
subscription to see `cancelFuture` complete.

## See also

- [Results and errors](results_and_errors.md) - the `Result` around the stream.
- [JSON decoding](json_decoding.md) - `SseMessage.json`, `JsonDecodeException`.
- [Web and platforms](web_and_platforms.md) - streaming adapters.
- Generated event streams, unions and the `sse` config:
  [event streams](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/event_streams.md).
