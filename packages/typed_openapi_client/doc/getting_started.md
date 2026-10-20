# Getting started

A generated client builds its requests with `ClientSender`, hands them to a
`ClientTransport` and returns a `Result<T, E>` from every method. This guide
wires the Dio transport (`typed_openapi_dio`), makes a call,
reads the result and shows what `CallOptions` can do. The client below is the
one the generator writes for a two-operation Petshop spec (a `GET
/pets/{petId}` and a `PATCH /pets/{petId}`); the trimmed generated method is
in [Results and errors](results_and_errors.md).

## 1. Dependencies

```yaml
dependencies:
  dio: ^5.11.1
  typed_openapi_client: ^0.2.0
  typed_openapi_dio: ^0.2.0      # the transport over your Dio
```

Generated files import only
`package:typed_openapi_client/typed_openapi_client.dart`; your app adds the
transport (`typed_openapi_dio` and `dio`). The generator itself
(`typed_openapi`) is a dev tool and never a dependency of your app.

## 2. Create the client

```dart
import 'package:dio/dio.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';
import 'package:typed_openapi_dio/typed_openapi_dio.dart';

import 'petshop/petshop.dart'; // generated

final dio = Dio(
  BaseOptions(
    baseUrl: 'https://api.example.com',      // the client never sets one
    connectTimeout: const Duration(seconds: 5),
    headers: {'User-Agent': 'petshop-app/1.0'},
  ),
);
final api = PetshopClient(DioTransport(dio));
```

`DioTransport` uses your `Dio` as it is. It never sets a base URL, an
interceptor, a transformer or `validateStatus`, and it never retries; those
belong to you. Authentication, logging, retries and per-call timeouts are
interceptors on this `Dio` (see [Security metadata](security_metadata.md)).

> **Note:** The root class has a field per group of operations (`api.pets`).
> Each group is a plain `class` that takes the `ClientTransport`, so you can
> `implements` it in a test fake, or give it a fake transport.

## 3. Call a method and read the result

```dart
switch (await api.pets.getPet(petId: 7, fields: ['id', 'name'])) {
  case Success(:final data, :final statusCode, :final headers):
    print('$statusCode ${data.name} born ${data.birthday} ${headers['x-request-id']}');
  case HttpError(:final body):
    print('error ${body.code}');
  case Failure():
    print('other failure');
}
```

Output, with an in-memory adapter that answers `200` with
`{"id":7,"name":"Rex","birthday":"2021-04-09"}` and an `x-request-id` header:

```text
200 Rex born 2021-04-09 [abc]
```

- Arguments are named; `required` ones are required. A path parameter is
  always required.
- `Success` carries the decoded body (`data`), the status code and the
  response headers (names in lower case, every value a `List<String>`).
- `Failure` is the sealed parent of the five failure variants, so
  `case Failure():` covers all of them at once. Exhaustive matching is
  described in [Results and errors](results_and_errors.md).
- A success without a body has `T = void`: match it with `Success()`. An
  operation without documented errors has `E = Never`.

Interceptors see the finished URL; the query string is already part of it:

```text
GET https://api.example.com/pets/7?fields=id,name
User-Agent: petshop-app/1.0
```

> **Gotcha:** `options.queryParameters` is empty in an interceptor. The
> client encodes the path and the query itself and gives the transport one finished
> path, so read `options.uri` instead.

## 4. CallOptions

Every generated method ends with an optional `CallOptions? call`. It is one
object so that new options never change the signature of a method (or of a
fake that implements it).

| Field | Effect |
| --- | --- |
| `cancel` | A `CancelSignal`; cancelling gives `Cancelled` |
| `headers` | Added to the request; win over the operation's header parameters (case-insensitively) |
| `extra` | Given to the transport (`TransportRequest.extra`); `DioTransport` merges it into `RequestOptions.extra` |
| `onSendProgress` | Bytes of the request body sent so far, counted by the client |
| `onReceiveProgress` | Bytes of the response body received so far, counted by the client |
| `sse` | `SseOptions` for an event stream (reconnection); other operations ignore it |

```dart
await api.pets.getPet(
  petId: 7,
  call: CallOptions(
    headers: {'X-Trace': 'abc123'},
    extra: {'attempt': 1},
    onReceiveProgress: (received, total) => print('received $received of $total'),
  ),
);
// received 45 of -1          (-1: the adapter reported no total length)
// the request carried X-Trace: abc123 and extra['attempt'] == 1
```

### Cancelling

```dart
final signal = CancelSignal();
final pending = api.pets.getPet(petId: 7, call: CallOptions(cancel: signal));
signal.cancel('user left the page');
print(await pending); // Cancelled
```

A cancel is its own outcome, `Cancelled`, not a `TransportError`.

### Content-Type is not overridable

`CallOptions.headers` wins over header parameters, but not over the
`Content-Type` of the request body: when the operation sends a body, its
content type is used and a `Content-Type` given in `headers` is ignored. You
cannot use it to pick another media type such as
`application/merge-patch+json`. See [Request bodies](request_bodies.md).

### Per-call timeouts

Timeouts, the base URL and retries belong to the transport, here your Dio. For a value that differs per
call, pass it in `extra` and apply it in an interceptor:

```dart
dio.interceptors.add(
  InterceptorsWrapper(
    onRequest: (options, handler) {
      if (options.extra['receiveTimeout'] case final Duration timeout) {
        options.receiveTimeout = timeout;
      }
      handler.next(options);
    },
  ),
);

await api.pets.getPet(
  petId: 1,
  call: const CallOptions(extra: {'receiveTimeout': Duration(seconds: 2)}),
);
// the adapter saw receiveTimeout == 0:00:02.000000
```

## 5. Tell operations apart in an interceptor

The runtime puts an `OperationInfo` (operation id, method, path template,
tags, security) into `RequestOptions.extra`:

```dart
final operation = DioTransport.operationOf(options); // null for a request DioTransport did not send
print(operation?.operationId);               // getPet
```

## Where to go next

- What every outcome carries: [Results and errors](results_and_errors.md).
- Send `null` versus nothing: [Patch and nullability](patch_and_nullability.md).
- Event streams: [Server-Sent Events](sse.md).

## See also

- [Web and platforms](web_and_platforms.md) - what differs in a browser.
- The generated code, group by group:
  [generated overview](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/overview.md).
- Wiring the generator itself:
  [generator getting started](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/getting_started.md).
