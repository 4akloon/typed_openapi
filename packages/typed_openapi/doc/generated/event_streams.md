# Event streams

An operation whose success response is `text/event-stream` (server-sent events) is generated as a method that returns `Future<Result<Stream<SseItem<T>>, E>>`. The stream is opened, decoded, and optionally reconnected by the runtime; this guide shows what the generator writes for each shape of spec and how to steer it.

The examples use the `chat.yaml` and `chat.overrides.yaml` test fixtures (OpenAPI 3.2, because `itemSchema` is a 3.2 keyword), generated into a client named `chat`. Generated code is trimmed.

## Consuming a stream

```dart
import 'package:dio/dio.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';
import 'package:typed_openapi_dio/typed_openapi_dio.dart';
import 'package:my_app/chat/chat.dart';

Future<void> main() async {
  final chat = ChatApi(
    DioTransport(Dio(BaseOptions(baseUrl: 'https://api.example.com'))),
  );

  final result = await chat.followChat(chatId: 'c1');
  switch (result) {
    case Success(data: final events):
      await for (final item in events) {
        switch (item) {
          case SseEvent(data: final FollowChatEventDelta d):
            print(d.data.part);
          case SseEvent(data: final FollowChatEventUsage u):
            print('tokens: ${u.data.tokens}');
          case SseEvent(data: FollowChatEventNote() || FollowChatEventDone()):
            break;
          case SseDecodeError(:final error):
            print('bad event: $error');
          case SseReconnecting(:final attempt, :final delay):
            print('reconnecting #$attempt in $delay');
          case SseDisconnected(:final cause, :final lastEventId):
            print('closed ($cause), last id "$lastEventId"');
        }
      }
    case Failure():
      print('could not open the stream: $result');
  }
}
```

This sample was analysed with `dart analyze --fatal-infos` against the generated `chat` client.

The method first returns a `Result`: a status the spec does not list as a stream (a `404` with a JSON body, say) is a `Failure` and no stream exists. A `Success` carries the stream. Its items are `SseItem<T>`:

| Item | When |
| --- | --- |
| `SseEvent<T>` | An event whose data decoded as `T`. It also has `event` (the name, `message` by default), `id` (the stream's last event id so far) and `retry`. |
| `SseDecodeError<T>` | One event whose data did not match its schema. `error` says where; `message` is the event as received. The stream goes on. |
| `SseReconnecting<T>` | The connection ended and a new attempt starts after `delay`. |
| `SseDisconnected<T>` | Always the last item: the server closed the stream (`cause` is `null`) or it failed. It carries `lastEventId`, `retry` and `receivedMessage`. |

The stream never emits errors; problems are items. The full runtime behaviour (WHATWG parsing, `Last-Event-ID`, backoff, cancellation, web adapters) is in the runtime guide, [SSE](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/sse.md). For a stream that runs for hours it also documents the idle and handshake timeouts, unbounded reconnection with jitter and a cooldown, and the `onTrace` hook ([Long-lived streams](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/sse.md#long-lived-streams), [Tracing](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/sse.md#tracing)); all are options of `CallOptions.sse`, so the generated methods do not change. On the web, the default Dio adapter delivers the body only when the connection closes, so use a streaming adapter there.

> **Note:** `openEvents` needs its stream listened to or cancelled. Cancelling the listener cancels the request. To cancel from outside, pass a `CancelToken` in `CallOptions`, see [Operations](operations.md).

## What the data type is

The generator reads the event data from the response's media type object, in this order: an `sse.data`/`sse.events` override, then `itemSchema` (OpenAPI 3.2), then `schema`.

| Spec | Data type | Decoder in the method |
| --- | --- | --- |
| `schema: {$ref: Thread}` or an object | The model | `(m) => Thread.fromJson(JsonReader.asObject(m.json))` |
| `schema: {type: string}` (also a nullable or enum string) | `String` | `(m) => m.data` |
| `itemSchema` with a `data` property that is a string with `contentMediaType: application/json` and a `contentSchema` | The `contentSchema` type | as for a model |
| `itemSchema` with a plain string `data`, or no usable `data` | `String` | `(m) => m.data` |
| `schema` that is an array of items | The item type | as for a model, TOA664 |
| `itemSchema` whose `oneOf` branches fix `event` | An [event union](#event-unions) | `<Union>.fromEvent` |

An event stream with a text or unreadable `itemSchema` is `String` data with `TOA666` (a warning) when the schema is not understood. `TOA664` (info) says an array `schema` was read as "one item per event", which is how code-first frameworks write streams.

## Stream shapes

What a spec gets depends on what the 2xx responses offer next to `text/event-stream`.

| Shape | The spec | The generator writes |
| --- | --- | --- |
| Stream only | Every success with a body is only a stream | One method that returns the events. |
| Both | A success offers a body (JSON, text, bytes, XML) and the stream | The method of the body, as without the stream, plus a second method for the events (`TOA663`, info). |
| Body only | Every stream success also offers a body, but another 2xx has a body and no stream | The method of the body only; the stream method is not generated and `TOA654` names the statuses. |
| Mixed | Some successes are only a stream, others only a body | Nothing: the operation is skipped with `TOA654` (warning). |
| Excluded | `sse.method: none` on a stream-only operation | Nothing, and no diagnostic. |

### Both: a method for the body and one for the events

`GET /bytes` in the `event_bodies.yaml` fixture offers `application/octet-stream` and `text/event-stream` on one `200`. With `naming.stream_suffix: Events` in the config (the default is `Stream`) the generator writes two methods:

```text
info TOA663 event-stream-method-added: This operation returns a body or an event stream; "download" returns the body and "downloadEvents" the events.
  at #/paths/~1bytes/get
  fix: Set naming.stream_suffix in the config to name it otherwise.
```

```dart
/// `GET /bytes` (`download`).
Future<Result<Uint8List, Never>> download({
  CallOptions? call,
}) => _sender.send(
  OperationRequest(
    _download,
    responseKind: .bytes,
    accept: 'application/octet-stream',
  ),
  _decodeDownload,
  call: call,
);

/// Returns the events of `text/event-stream` as they arrive; ...
///
/// `GET /bytes` (`download`).
Future<Result<Stream<SseItem<String>>, Never>> downloadEvents({
  CallOptions? call,
}) => _sender.openEvents(
  OperationRequest(
    _downloadEvents,
    streamStatuses: {200},
  ),
  (m) => m.data,
  _decodeDownloadEvents,
  call: call,
);
```

- **The body method sends `accept:`.** It lists the base media types of the operation's 2xx bodies (`application/json`, `application/vnd.api+json`, `text/plain`, each once), so a server that can answer either way does not pick the stream. A call's own `Accept` header in `CallOptions.headers` wins. The stream-only method has no `accept:`. Bytes and XML bodies get their `accept:` too, as the sample shows.
- **The name** of the second method is the first one plus `naming.stream_suffix` (letters and digits, starting with an uppercase letter or a digit): `chat` and `chatStream`. A reserved word keeps its stem, so a method `class_` gets `classStream`. The stream method's name is claimed after every other method of the group; if it equals one, the collision is `TOA551`, and a name Dart already has is `TOA550`.
- If the stream-only and body-only successes disagree about the data type, nothing is generated for the stream (`TOA654`, see [Skipped streams](#skipped-streams-toa654)).

### Forcing a shape with `sse.method`

The `sse.method` override of an operation (see [Overrides](../overrides.md)) picks the shape:

| Value | Effect |
| --- | --- |
| `stream` | Same as not setting it: the shape above follows from the spec. |
| `only` | One method that returns the events. The bodies of the operation are dropped, with `TOA651` naming the media types. |
| `none` | The event stream is not generated. A stream-only operation is left out with no diagnostic; with a body, only the body method is written. |

In the `chat` fixture, `POST /chat` offers JSON and a stream; `sse: {method: only}` makes `chat` return the stream:

```text
info TOA651 media-types-dropped: sse.method: only returns the events of the response; "application/json" is dropped.
  at #/paths/~1chat/post/responses/200/content
  fix: Remove sse.method: only to keep the body in a method too.
```

```dart
/// Answers a prompt, whole or as it is written.
///
/// Returns the events of `text/event-stream` as they arrive; the stream ends
/// with `SseDisconnected`. It does not reconnect unless the operation's
/// `sse.reconnect` override enables it.
///
/// `POST /chat` (`chat`).
Future<Result<Stream<SseItem<Delta>>, Problem>> chat({
  required Prompt body,
  CallOptions? call,
}) => _sender.openEvents(
  OperationRequest(
    _chat,
    body: body.toJson(),
    contentType: 'application/json',
    streamStatuses: {200},
  ),
  (m) => Delta.fromJson(JsonReader.asObject(m.json)),
  _decodeChat,
  call: call,
  reconnection: .off,
);
```

The request body is sent as for any operation; see [Request bodies](request_bodies.md).

## Which statuses open a stream

`streamStatuses` lists the 2xx statuses that carry an event stream; a range is written once. `GET /threads/{threadId}/events` declares a `200` stream and a `204` (the thread is closed), so it uses `streamStatuses: {200, 204}`: a `204` ends the stream at once. Any other status goes through the usual decoder, and its error body is typed as for any operation (`404 => r.error(Problem.fromJson(...))`), see [Responses and errors](responses_and_errors.md). The decoder of a stream method has error arms only.

A `text/event-stream` response on an error status (or `default`) of an operation that does not return events is read as text, like any non-JSON error body (`TOA671`, info):

```text
info TOA671 event-stream-error-as-text: The error response is "text/event-stream", but only a success is an event stream: its body is read as text.
  at #/paths/~1errors/get/responses/500/content/text~1event-stream
  fix: Use a JSON media type for errors at the source if the schema matters.
```

## Event unions

When the `itemSchema` is a `oneOf` (or `anyOf`) whose branches each fix `event` to a string `const` (or a one-value `enum`), the generator writes a sealed class `<Method>Event` with one variant per event name. This is the typed way to use a stream that carries several kinds of events. The spec (`followChat` in `chat.yaml`):

```yaml
itemSchema:
  oneOf:
    - type: object
      required: [event, data]
      properties:
        event: {const: delta}
        data: {type: string, contentMediaType: application/json, contentSchema: {$ref: '#/components/schemas/Delta'}}
    - type: object
      properties:
        event: {enum: [usage]}
        data: {type: string, contentMediaType: application/json, contentSchema: {$ref: '#/components/schemas/Usage'}}
    - type: object
      properties:
        event: {const: note}
        data: {type: string}
    - type: object
      properties:
        event: {const: done}
```

The generated union (trimmed to its first variant):

```dart
/// The events of [ChatApi.followChat], by their event name: a `switch` names
/// every one.
@immutable
sealed class FollowChatEvent {
  const FollowChatEvent();

  /// Decodes [message] by its event name.
  static FollowChatEvent fromEvent(SseMessage message) => switch (message.event) {
    'delta' => FollowChatEventDelta(Delta.fromJson(JsonReader.asObject(message.json))),
    'usage' => FollowChatEventUsage(Usage.fromJson(JsonReader.asObject(message.json))),
    'note' => FollowChatEventNote(message.data),
    'done' => const FollowChatEventDone(),
    _ => throw const SseEventIgnored(),
  };
}

/// The `delta` event of [ChatApi.followChat].
class FollowChatEventDelta extends FollowChatEvent {
  const FollowChatEventDelta(this.data);
  final Delta data;
  // == and hashCode by value; toString prints the data
}

/// The `done` event of [ChatApi.followChat], which has no data.
class FollowChatEventDone extends FollowChatEvent {
  const FollowChatEventDone();
}
```

- **One class per event name.** The class is `<Union><EventName>` (`FollowChatEventDelta`). A variant with a `data` has a `data` field of the data type; one without `data` has none. A name with no letter or digit gets a name by its place and `TOA668` (info); a clash with another type gets a `2` and `TOA551`.
- **The union lives in the group file**, after the class and the status types, not in `models/`. Variants are equal by value; a secret in the data prints as `<redacted>` in `toString`.
- **The method** passes `FollowChatEvent.fromEvent` as the event decoder and returns `Stream<SseItem<FollowChatEvent>>`. Switch on `SseEvent(data: ...)` as in the example at the top.
- **Duplicates and bad names.** If two branches fix the same name, the first one is kept and the rest are dropped with `TOA667` (warning). An empty name (the wire reads an empty `event:` as `message`) or a name with a line break can never be selected, so it is left out with `TOA670` (warning):

```text
warning TOA670 event-name-unreachable: The event name is empty, and an empty "event:" is read as "message", so no event can select this variant; it is left out.
  at #/paths/~1feed/get/responses/200/content/text~1event-stream/itemSchema/oneOf/0
  fix: Name the event with a non-empty name without line breaks at the source.
```

- **A branch that does not fix a name** (a nested `oneOf`, an `allOf` branch, a `data` that is neither text nor JSON with a `contentSchema`) makes the whole data text and is `TOA666` (warning) at that branch. Write `properties.event.const` in the branch itself:

```text
warning TOA666 event-item-schema-unread: This branch of the itemSchema does not fix its "event" to a string constant (const, or an enum of one value), so the events cannot be told apart by name; the data is read as text.
  at #/paths/~1nested/get/responses/200/content/text~1event-stream/itemSchema/oneOf/1
  fix: Write properties.event.const in the branch itself: a branch written with allOf does not count.
```

### Unknown events

What happens to an event whose name no branch fixes depends on the `sse.unknown` override of the operation:

| `unknown` | The union | An event with another name |
| --- | --- | --- |
| `keep` (default) | Has a last variant `<Union>Unknown(event, data)` | `<Union>Unknown` with the name and the data text. |
| `ignore` | No unknown variant | `fromEvent` throws `SseEventIgnored`; the stream drops the event (no item). Its `id:` and `retry:` still count, so `Last-Event-ID` stays right. |

`followChat` has `sse: {unknown: ignore}` (the `_ => throw const SseEventIgnored()` arm above). `tailLog` keeps the default and has this last variant, whose `toString` prints `<redacted>` if any branch carries a secret:

```dart
/// An event of [ThreadsApi.tailLog] whose name no other variant has, with its
/// data as text.
class TailLogEventUnknown extends TailLogEvent {
  const TailLogEventUnknown(this.event, this.data);
  final String event;
  final String data;
}
```

Because of that last variant, `switch (item.data)` over the union stays exhaustive when the server adds an event.

## Reconnection

The generator decides, per method, whether and how the stream reconnects after the connection ends. The runtime does the work: it sends `Last-Event-ID`, waits the server's `retry` (or 1 s, doubling to 30 s), reports `SseReconnecting` before each attempt, and gives up after 5 attempts in a row without a message. All of this is tunable per call with `CallOptions(sse: SseOptions(...))`; see the runtime guide.

| Operation | `reconnection:` argument | Behaviour |
| --- | --- | --- |
| `GET`, default | none (`onRequest`) | Reconnects only when the call asks: `CallOptions(sse: SseOptions(reconnect: true))`. |
| `GET`, `sse.reconnect: true` in the config or the override | `.on` | Reconnects unless the call says `reconnect: false`. |
| Not `GET`, default | `.off` | Never reconnects: repeating the request may not be safe. A `true` in a call has no effect. |
| Not `GET`, `sse.reconnect: true` in its override | `.on` | Reconnects. |
| Any, `sse.reconnect: false` in its override | `.off` | Never reconnects. |

`tailLog` has `sse: {reconnect: true}` in its override and so `reconnection: .on` and the doc line "reconnects with `Last-Event-ID` unless `call.sse` says no". `chat` is a `POST` and has `.off`.

The config key `sse.reconnect: true` (in `defaults` or a client; see [Configuration](../configuration.md)) turns reconnection on for the GET streams of the client. It cannot turn it on for other methods; an operation that this leaves out is reported once with `TOA665` (info), but only when the config asked:

```text
info TOA665 event-stream-reconnect-off: sse.reconnect in the config applies to GET event streams only, so this POST operation does not reconnect: repeating the request may not be safe.
  at #/paths/~1post/post
  fix: Enable it for this operation if the request can be repeated. Override: ...
```

Options you give every stream (reconnection, jitter, timeouts, `onTrace`) go once into the constructor of the client, `PetstoreClient(transport, defaults: CallOptions(sse: SseOptions(...)))`; a call's own options win field by field. A GET stream that reconnects also retries its opening on transient failures (408, 429, most 5xx, a refused or timed-out connection), and a `Retry-After` header lengthens the wait. A stream whose reconnection is `.off` is never retried. See the runtime guide, "Defaults for every call" and "Retrying the opening".

A listener cancel, a final error status (the `Failure` is the stream's `cause`) and a `204` end the stream instead of reconnecting. A transient error status (408, 429, 5xx except 501 and 505) is retried; see `SseRetry` and `retryWhen` in the runtime guide.

## The `sse` overrides

An operation entry in the [overrides file](../overrides.md) has an `sse` map. This is the fixture's `chat.overrides.yaml`:

```yaml
operations:
  followChat:
    sse: {unknown: ignore}
  tailLog:
    sse:
      events:
        line: {type: string}
        stats: Usage
        eof: null
      reconnect: true
  chat:
    sse: {method: only}
```

| Key | Value | Effect |
| --- | --- | --- |
| `data` | A `components.schemas` key (becomes a `$ref`) or an inline schema | The schema of the event data, written as the `schema` of every written `text/event-stream` 2xx response of the operation; any `itemSchema` there is removed. `TOA807` (info) if the spec already has one. |
| `events` | A map of event name to a component name, an inline schema or `null` (an event with no data) | A union: written as an object whose properties are the events, read as an event union with the events in this order. `data` and `events` together are `TOA802`. |
| `unknown` | `keep` or `ignore` | What a union does with an unnamed event, see [Unknown events](#unknown-events). |
| `reconnect` | `true` or `false` | The method's reconnection, see [Reconnection](#reconnection). |
| `method` | `stream`, `only`, `none` | The shape, see [Forcing a shape](#forcing-a-shape-with-ssemethod). |

`tailLog` is the spec's plain `text/event-stream` with `schema: {type: string}` and so `String` data. The `events` override above turns it into the `TailLogEvent` union shown earlier (`line` text, `stats` a `Usage` model, `eof` without data).

> **Gotcha:** `data` and `events` change only a response that is written in the operation. A response that is a `$ref` to `components.responses` is shared and is left alone; `TOA669` (warning) says so and `TOA654` says "the shared response was not overridden" if the event types then differ. Override the schema the response uses by its component name, or write the response in the operation.

`TOA669` (warning) names the exact part of the `sse` map that did nothing:

```text
warning TOA669 sse-override-not-applied: The operation has no 2xx response with content text/event-stream, so "reconnect" of "sse" changes nothing.
  at #/operations/plain/sse
  fix: Remove "sse".
```

## Skipped streams (TOA654)

An operation that cannot be expressed as one stream is not generated, and the diagnostic is `TOA654` (warning). The two causes:

```text
warning TOA654 event-stream-not-generated: Some successes of this operation are event streams and others have a body that is not, so neither a method that returns the body nor one that returns the events covers them; the operation is not generated.
  at #/paths/~1mixed/get/responses
  fix: Offer text/event-stream on every success with a body.
```

```text
warning TOA654 event-stream-not-generated: The event-stream successes of this operation have different event types, so one stream cannot hold them; the operation is not generated.
  at #/paths/~1disagree/get/responses
  fix: Give every event-stream success the same schema at the source.
```

A skipped operation declares no types and claims no method name. Two successes have "the same event types" when their schemas are the same after annotations, a `null` in `type`, and wrappers that add nothing are set aside. If your spec has an operation like this, align the successes, or exclude the operation with an override `exclude: true`; see [Overrides](../overrides.md).

## Diagnostics

| Code | Level | Meaning |
| --- | --- | --- |
| `TOA651` | info | `sse.method: only` dropped a body media type. |
| `TOA654` | warning | A stream the generator cannot express, or a stream method not generated in the body-only shape. |
| `TOA663` | info | A second, suffixed method was added for the events. |
| `TOA664` | info | An array `schema` was read as one item per event. |
| `TOA665` | info | The config asked for reconnection but this non-GET stream does not reconnect. |
| `TOA666` | warning | The data of an event or a branch is read as text. |
| `TOA667` | warning | Two branches fix the same event name; the later is left out. |
| `TOA668` | info | An event name has no letter or digit; its class is named by its place. |
| `TOA669` | warning | A part of the `sse` override changed nothing. |
| `TOA670` | warning | An event name can never be sent; its variant is left out. |
| `TOA671` | info | A `text/event-stream` error body is read as text. |

The full catalog, with levels you can change, is in [Diagnostics](../diagnostics.md).

## See also

- [Operations](operations.md) and [Responses and errors](responses_and_errors.md): how the other methods are written.
- [Overrides](../overrides.md) and [Configuration](../configuration.md): `sse`, `naming.stream_suffix`.
- [Security](security.md): sending a token with a stream request.
- Runtime: [SSE](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/sse.md).
