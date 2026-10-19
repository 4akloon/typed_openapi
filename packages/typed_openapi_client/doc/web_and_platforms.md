# Web and platforms

The client core is pure Dart and runs on the Dart VM, compiled to JavaScript
(dart2js) and compiled to WebAssembly (dart2wasm). The same tests run on all
three, and the places where behavior differs are pinned by tests that assert
each platform's answer, so a change on one of them is noticed. This guide
lists the differences, the tests that pin them, and the SDK and dependency
floors.

## Differences at a glance

| Area | VM and dart2wasm | dart2js (JavaScript) | Pinned by |
| --- | --- | --- | --- |
| `QueryParameter('x', 1.0)` | `x=1.0` | `x=1` (`1.0` is the int `1`) | `test/platform/platform_semantics_test.dart` |
| `DeepEquality().equals([nan], [nan])` | `true` (`identical` compares bits) | `false` (`NaN !== NaN`) | `test/platform/platform_semantics_test.dart` |
| `JsonReader.asInt(1.0)` | rejected | accepted (it is the integer `1`) | `test/json/json_reader_test.dart` |
| Integers beyond 2^53 | exact up to int64 | lose precision | `test/json/json_reader_int64_test.dart` (VM only) |
| `Cookie` header from a cookie parameter | sent | **dropped by the browser** | `typed_openapi_dio`: `test/cookie_browser_test.dart` |
| `openEvents` through `DioTransport` with Dio's default adapter | streams | `TransportError` that explains how to fix it | `typed_openapi_dio`: `test/web_test.dart` |
| `FileUpload.stream` through `DioTransport` | streamed | buffered into one `Uint8List` by Dio's browser adapter | the doc comment of `FileUpload` |

dart2wasm keeps `0` and `0.0` apart, so it behaves like the VM everywhere in
the table. A malformed JSON body is parsed by the client, so its
`DecodeError` is the same on all three. The transport conformance suite
(`typed_openapi_transport_tests`) runs every transport against a loopback
server on the VM, dart2js and dart2wasm.

## Numbers

JavaScript has one number type. Three consequences:

- `1.0` and `1` are the same value. A double that prints as a whole number
  encodes without a fraction in a query (`x=1`), and `JsonReader.asInt(1.0)`
  succeeds, because there is no way to see the difference.
- `NaN` is not equal to itself in `DeepEquality`, because the first thing it
  does is `identical(a, b)`. JSON has no `NaN`, so a decoded value never
  holds one.
- An integer beyond 2^53 loses precision, since `int` is a JavaScript number.
  If the API has ids that large, map the property to your own type (`BigInt`
  or `String`) with a converter in the generator config (`types.formats` or a
  `dartType` override). `JsonReader.asString` rejects a JSON number, so a
  `String` id works only if the server sends a string.

> **Gotcha:** Do not write an int literal beyond 2^53 in code that must
> compile to JavaScript. `dart2js` rejects it. The client keeps such
> literals out of `lib/`, and the tests that need them are `@TestOn('vm')`.

## Cookies

Browsers do not let a page set the `Cookie` request header (`XMLHttpRequest`
and `fetch` ignore it), so **cookie parameters do not work on the web**: the
browser keeps its own cookies and sends them itself, subject to its
credentials settings. A test starts a local server, calls it from Chrome,
compiled to JavaScript and to Wasm, and checks that a `Cookie` header set
by a `CookieParameter` or directly in Dio's `Options`, never reaches the
server, while another header (`X-Probe`) of the same request does.

```sh
cd packages/typed_openapi_dio
dart test -p chrome test/cookie_browser_test.dart
dart test -p chrome --compiler dart2wasm test/cookie_browser_test.dart
```

Both print `All tests passed!`.

## Event streams

An event stream needs a transport that streams the body. Dio's default
browser adapter delivers a body only when the connection closes, so
`DioTransport` checks, before any request is sent, whether the Dio has the
default adapter on the web, and fails with a `TransportException` whose
message is `DioTransport.webStreamingMessage`:

```text
Server-sent events need a streaming HTTP adapter on the web: Dio's default
browser adapter delivers the body only when the connection closes. Set a
fetch-based adapter on your Dio, such as ConversionLayerAdapter from
package:dio_compatibility_layer with package:http's BrowserClient or
package:fetch_client.
```

`TransportError.exception.cause` is an `UnsupportedError`. A reconnecting
stream fails the same way: `openEvents` returns the `TransportError` before
any stream exists, so there is no wait and no reconnection. Once you set a
non-default adapter, the stream opens: `web_test.dart` of `typed_openapi_dio`
pins the refusal in a real browser, and its conformance suite runs the event
stream case on the VM.

For a cross-origin stream, the reconnection's `Last-Event-ID` is not a
CORS-safelisted request header: the server must list it in
`Access-Control-Allow-Headers`, or every reconnection that carries an id
fails with a `TransportError`. See [Server-Sent Events](sse.md).

## Detecting the web

`DioTransport` detects "web" with
`bool.fromEnvironment('dart.library.js_interop')`, true on dart2js and
dart2wasm; `DioTransport(dio).isWeb` exposes it, and a test can set
`isWeb:` to simulate a browser.

## Files and progress

`FileUpload.bytes` works everywhere. `FileUpload.stream` is sent as it is
read on the VM; Dio's browser adapter buffers a stream into one `Uint8List`,
so it is not streamed on the web through `DioTransport`. `onSendProgress`
and `onReceiveProgress` are counted by the client as the body bytes pass to
and from the transport, the same on every platform.

## Running the tests

```sh
cd packages/typed_openapi_client
dart test                                    # the VM
dart test -p chrome                          # dart2js (needs Chrome)
dart test -p chrome --compiler dart2wasm     # dart2wasm
```

A file that needs the VM (`dart:io`, int64 literals) carries `@TestOn('vm')`,
and a single test `testOn: 'vm'`. If Chrome is not found, set
`CHROME_EXECUTABLE`. `test/helpers/test_platform.dart` tells the platform to
assertions that differ (`isWeb`, and `isJavaScript` as `identical(0, 0.0)`).
The tests never touch the network; they send through `FakeTransport`.

## SDK and dependency floors

| | Floor |
| --- | --- |
| Dart SDK | `>=3.10.0 <4.0.0`, also for generated code |
| `meta` | `^1.15.0`, low enough that Flutter's pinned `meta` resolves |

The package is not Flutter-specific and has no Flutter dependency. It
re-exports `immutable` from `package:meta`, so generated code imports only
this package. `typed_openapi_dio` adds `dio` `^5.11.1`.

## See also

- [Parameters](parameters.md#cookie-parameters) - cookie encoding.
- [Server-Sent Events](sse.md) - streaming adapters and reconnection.
- [JSON decoding](json_decoding.md) - `asInt`, integers and dates.
- [Results and errors](results_and_errors.md) - the malformed-JSON `DecodeError`.
- [`typed_openapi_dio`](../../typed_openapi_dio/README.md) - the Dio transport on the web.
