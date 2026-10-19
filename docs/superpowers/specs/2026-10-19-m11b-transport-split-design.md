# M11b: transport split — client core and Dio adapter — design

**Date:** 2026-10-19.

**Why now:** `typed_openapi_runtime` is the only package generated clients depend on, and it is welded to Dio: `Result`, `OperationInfo`, `CallOptions` and the SSE reconnector name Dio types in their public API, and every generated group takes a `Dio`. The package name also says nothing about what it is. Nothing is published yet, so the split costs a refactor now and a breaking release later. M12 (evolution) takes a snapshot of the generated API, so the API must be settled first.

**Roadmap:** a stage between M11 and M12; M12 and M13 keep their numbers.

**Earlier stages:**
- [M7](2026-10-12-m7-runtime-design.md): the runtime, `Result`, `JsonReader`, parameters.
- [M9](2026-10-13-m9-operations-design.md): `DioRequestSender`, `OperationRequest`, bodies.
- [M10](2026-10-13-m10-sse-design.md): SSE decoder, reconnection, `openEvents`.
- [M11](2026-10-13-m11-corpus-design.md): the corpus and `corpus.lock` this change will update.

The user took these decisions in a conversation; "my call" marks what the author chose.

## Goals

- A generated client does not depend on Dio. A new HTTP stack is a new adapter package, with no change to the generator or the core.
- Dio users keep what they use Dio for: interceptors, authorization, base URL, timeouts, retries and certificates stay in their `Dio`.
- Every transport behaves the same on the wire. The behaviour (URL building, body encoding, status mapping, SSE reconnection) lives once, in the core.

## Non-goals

- Shipping a second adapter (`package:http`, `dart:io`). The interface must allow one; writing it is later.
- A generator option that picks a transport. The generator emits the same code for all of them.
- Compatibility with `typed_openapi_runtime`: it was never published, so it is removed, not deprecated.

## Decisions

1. **Two packages replace `typed_openapi_runtime`.**
   - `typed_openapi_client` is the core. It depends on `meta` only.
   - `typed_openapi_dio` is the adapter. It depends on `typed_openapi_client` and `dio`.
   - Minimum SDK stays Dart 3.10; both work on the web (dart2js and dart2wasm).

2. **What stays in the core.** Everything that does not need Dio today: `json/`, `model/`, `params/`, `result/`, `request/` (`OperationRequest`, `OperationInfo`, `RawResponse`, `FileUpload`, `FormBody`, `MultipartBody`, `MediaTypeText`) and `sse/`. The files that import Dio today lose that import:
   - `Result`'s `TransportError` and `Cancelled` carry a `TransportException`, see 4.
   - `OperationInfo` is a field of the transport request, see 3, not an entry in Dio's `RequestOptions.extra`.
   - `SseReconnector` reasons about `TransportException` and `CancelSignal`.

3. **The transport is thin.** `ClientTransport` has one method, `Future<TransportResponse> send(TransportRequest request)`.
   - `TransportRequest` is the finished HTTP request: method, path with the query already built (the transport resolves it against its own base URL), headers, an optional body as `Stream<List<int>>` with a known length when there is one, the `CancelSignal`, the `OperationInfo` and the call's `extra`.
   - `TransportResponse` is the raw answer: status, headers (a name maps to a list of values), the body as `Stream<List<int>>`.
   - A unary operation reads the stream to the end in the core (`RawResponse`). An event stream hands it to the SSE decoder. No second method is needed.
   - The base URL, timeouts, retries, redirects, proxies and certificates belong to the transport, as they belong to the user's `Dio` today. The core never sets a base URL.
   - Name of the sender in the core: `ClientSender` (replaces `DioRequestSender`), with `send` and `openEvents`. It builds the request, calls the transport, picks the `Result` and drives SSE reconnection. Generated groups hold a `ClientSender`.

4. **Own cancellation and errors.**
   - `CancelSignal` replaces `CancelToken` in `CallOptions`: a signal with `cancel()`, `isCancelled` and a future for listeners.
   - `TransportException` replaces `DioException` in `TransportError` and `Cancelled`. It has a `kind` (`timeout`, `connection`, `cancelled`, `other`), a message and an opaque `cause: Object?`. `DioTransport` fills `cause` with the `DioException`. Code that needs Dio details casts it.
   - A transport maps its failures to `TransportException`; it never throws anything else for a failed request.

5. **`CallOptions` stays in the core, with general fields.** `headers`, `extra`, `sse`, `cancel` (a `CancelSignal`), `onSendProgress`, `onReceiveProgress`. Progress is counted in the core: it counts the bytes the transport pulls from the request stream and the bytes it reads from the response stream (the total comes from `Content-Length` when there is one). A transport implements nothing for progress. `extra` goes to the transport in `TransportRequest.extra`; `DioTransport` merges it into `RequestOptions.extra`. The signatures of generated methods do not change.

6. **The core encodes the body into bytes.** JSON, `application/x-www-form-urlencoded`, `multipart/form-data` (boundary, parts, per-part media types, `FileUpload` bytes and streams), text and bytes. This replaces `DioBody` and `MultipartForm`. The rules of M9 stay: the order of parts, a text part is a field only while no file or typed part precedes it, a value that cannot be written is an `ArgumentError`.
   - Consequence (my call, to confirm): a Dio interceptor sees the body as bytes, no longer as a `Map` or a `List`. This costs interceptors that log or sign a JSON body by reading `options.data`; the bytes carry the same information. The alternative, passing the JSON value next to the bytes, is not taken because it would make a second representation every adapter has to keep in sync.

7. **Generated code.** Groups and the root client take a `ClientTransport` instead of a `Dio`; the root keeps the constructor shape. A Dio user writes `PetsApi(DioTransport(dio))`. The generated files import `package:typed_openapi_client`, not `package:dio`. `DartNames.takenTypeNames` reserves the new core names the generated code uses and no longer needs to reserve Dio's. This changes the generated output of every client: it is a breaking change of the generator (CLAUDE.md), so `corpus.lock` is updated, the CHANGELOG has an "Output changes" entry and the version rises as the M11 semver check requires.

8. **The adapter** (`typed_openapi_dio`): `DioTransport(Dio dio, {bool? isWeb})`. It never mutates the user's `Dio`; it sends through `dio.request` with `ResponseType.stream`, maps `CancelSignal` to a `CancelToken`, maps `DioException` to `TransportException`, and passes `OperationInfo` and `extra` through `RequestOptions.extra` so interceptors can read the security metadata as they do today. On the web it needs a streaming adapter for SSE, as before (documented). Cookie parameters still do not work in a browser.

9. **Tests.**
   - Core tests use a fake `ClientTransport` (a function from request to response), not a Dio fake. They cover everything that moved: body encoding, URL building, status mapping, SSE decoding and reconnection, progress, cancellation.
   - The adapter is tested against a real HTTP server on loopback (`dart:io` `HttpServer`, an ephemeral port), not only against Dio's fake adapter. One conformance suite (`TransportConformance`) takes a `ClientTransport` factory and a base URL and runs the same cases against any adapter; `typed_openapi_dio` runs it, and a future adapter runs the same file.
   - The conformance server and suite live in a new workspace package `typed_openapi_transport_tests` (`publish_to: none` for now; it may be published for third-party adapters). Its dependencies are `test` and `typed_openapi_client`. The server is small: routes, no framework.
   - Cases the server must serve and the suite must check:
     - methods GET, POST, PUT, PATCH, DELETE, HEAD; path variables and query encoding echoed back;
     - request headers echoed, including repeated values and a header given by the call;
     - JSON, text and binary responses; an empty body and `204`; a large body (several MB) streamed in chunks;
     - statuses 200, 201, 204, 301/302 (redirect policy is the transport's, the case documents it), 400, 404, 422, 500, 503 and an undocumented one;
     - request bodies echoed back byte for byte: JSON, form-urlencoded, multipart with text, a file from bytes and a file from a stream, and a typed part;
     - `Content-Type`, `Content-Length` and `Transfer-Encoding` as received;
     - cancellation before the request, in flight and during the body;
     - a connection refused, a server that closes the socket, a timeout (the transport is configured with a short one);
     - an event stream: chunks split inside a line and inside a UTF-8 character, comments, `retry:`, ids, a server that closes and expects `Last-Event-ID` on reconnection, a `204` that ends the stream, an error status with a body, a listener that cancels mid-stream;
     - progress counts for upload and download.
   - Browser: the same suite runs in Chrome (dart2js and dart2wasm) with the server started through `spawnHybridUri`, as `cookie_server.dart` is today. A case the browser cannot do (a repeated request header, cookies, `HEAD` body rules) is skipped with a stated reason, not removed.
   - The generated-client test, the corpus and the fuzz run the new generated code; the programs that call the petstore client use a fake transport.

10. **CI and layout.**
    - `packages/typed_openapi_runtime` is renamed to `packages/typed_openapi_client` with `git mv`, so history follows. `packages/typed_openapi_dio` and `packages/typed_openapi_transport_tests` are new.
    - `.github/workflows/ci.yml` and `nightly.yml` run the new packages' tests, the web job runs both, `test/ci/workflows_test.dart` is updated. The publish dry-run covers `typed_openapi_client` and `typed_openapi_dio`.
    - Documentation: the runtime's README and `doc/` move to the core; the Dio-specific parts (setup, web, interceptors, cancellation) go to the adapter's README; `CLAUDE.md`, the generator's guides and `docs/roadmap.md` are updated. The two long files (`sse.md`, `event_streams.md`) are split while moving.

## Calls made after the builder check (author's calls)

- **Dio's error path is kept.** `DioTransport` does not force `validateStatus`: the user's setting decides, so Dio's `onError` interceptors (a 401 token refresh, for example) still run, as the design rule "HTTP errors go through Dio's `onError`" requires. A `DioException` of type `badResponse` is turned back into a `TransportResponse` with the status and the body stream; the other types become a `TransportException`. The price: a Dio response interceptor sees a `ResponseBody` stream, not parsed JSON, and a user `Transformer` or `responseDecoder` is bypassed because the core reads and decodes the bytes. Both are documented in the adapter's README.
- **`OperationRequest.responseKind` stays** (`json`, `text`, `bytes`) with a new meaning: how the core reads the response bytes into a `RawResponse`. Generated code is unchanged by it; only its doc comments stop naming Dio.
- **Headers.** The core sets `Content-Type` (the operation's own wins, M9), `Content-Length` when the length is known (in-memory bodies; a `FileUpload` stream only when the caller gives a length), `Accept` and the headers of the operation. It sets nothing else; `Accept-Encoding`, `User-Agent`, cookies and authorization belong to the transport. The multipart boundary comes from a generator the sender takes (`ClientSender(boundary: ...)`), random by default and fixed in tests, so the ported M9 tests and the conformance suite assert exact bytes.
- **The target.** `TransportRequest.target` is the path and the encoded query exactly as `OperationRequest.resolvePath` builds them today. The transport resolves it against its own base URL by its own rule; `DioTransport` passes it to `dio.request` unchanged, so a base URL with a path prefix and a `Dio` with no base URL behave as they do today.
- **Web uploads.** A browser adapter may buffer an upload. Send progress then reports once, and the conformance suite skips the in-flight progress and stream-upload cases on the web with a stated reason.
- **SSE reconnection** retries after every `TransportException` kind except `cancelled`, as it retries every failure but a cancel today.
- **Semver gate.** The generator's CHANGELOG top section is `0.0.1 - Unreleased` (never published), so an "Output changes" entry is enough, no version bump. The runtime's CHANGELOG moves with the package to `typed_openapi_client`.

## Constraints

- Generated output changes only as decision 7 says: the `Dio` import and constructor types, the sender name, the transport type. Nothing else in a generated file changes; a diff of the golden files shows that and nothing more.
- The behaviour of every operation on the wire does not change: the same URL, headers and bytes for the same call. The conformance suite and the existing runtime tests, ported, are the proof.
- Code rules of CLAUDE.md apply (file and method size, no `// ignore:`, allowlists never grow). Files that move keep their place in the exemption list under their new path.
- English only.

## Out of scope

- A `package:http` or `dart:io` adapter, and a generator key to select a transport.
- Retries or caching inside the core.
- Changing the SSE semantics of M10, or the body rules of M9.

## Left to the builder

- The exact shape of `TransportRequest` fields (a record or a class) and of the `CancelSignal` API, as long as decisions 3 to 5 hold.
- The order of the work. A natural order is: new package skeleton and CI; move the Dio-free files; the transport, `CancelSignal`, `TransportException` and the core encoding; `ClientSender`; the Dio adapter; the generator and goldens; the conformance suite; documentation and `corpus.lock`.
- How the existing runtime tests are ported to a fake transport, test by test.

## Open questions (author's defaults)

1. Interceptors see bytes, not a `Map` (decision 6). Default: bytes.
2. The package for the server and suite is separate and unpublished (decision 9). Default: separate.
3. `HEAD` and redirects: the suite documents each transport's behaviour. Default: Dio's own.
