# M11b plan: transport split, client core and Dio adapter

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status: draft.** Task 1 was replayed from main (2d86694) on a scratch
> worktree. Tasks 2 to 10 are designed down to their interfaces, files and
> tests but were **not replayed**: their code blocks are not in this plan
> yet (see "Not replayed" at the end). An implementer of those tasks writes
> the code from the Interfaces block and the listed tests and runs the
> verification step; the roadmap rule "all the code, checked" holds for
> Task 1 only.

**Goal:** Generated clients stop depending on Dio: `typed_openapi_runtime` becomes `typed_openapi_client` (core, `meta` only) with a thin `ClientTransport`, `ClientSender` and its own body encoding, cancellation and errors; `typed_openapi_dio` adapts a user's `Dio`; a conformance package checks any transport against a loopback server; the generator emits `ClientTransport` groups.

**Architecture:** The core builds the finished request (target, headers, body bytes as a stream with a known length), calls `ClientTransport.send`, reads the response stream itself (`RawResponse`) or hands it to the SSE decoder, and maps everything to `Result`. `DioTransport` sends the finished request with `dio.request` and `ResponseType.stream`, keeps Dio's error path (a `badResponse` becomes a `TransportResponse` again) and maps every other `DioException` to a `TransportException`. `typed_openapi_transport_tests` holds a `dart:io` loopback server and the `TransportConformance` suite, run by the Dio package on the VM and in Chrome (dart2js, dart2wasm).

**Tech Stack:** Dart `>=3.10.0 <4.0.0`, pure Dart; `package:test`; Dio 5.11.1 (adapter only); Chrome for the web runs.

**Spec:** [docs/superpowers/specs/2026-10-19-m11b-transport-split-design.md](../specs/2026-10-19-m11b-transport-split-design.md), decisions 1-10 and the "Calls made after the builder check" (binding). Brief: [m11b-plan.md](../briefs/m11b-plan.md). Code rules and size limits: [CLAUDE.md](../../../CLAUDE.md), [code-quality-review.md](../../code-quality-review.md).

## Global Constraints

- SDK `>=3.10.0 <4.0.0` for every package and for generated code; the core and the adapter work on the VM, dart2js and dart2wasm.
- `typed_openapi_client` depends on `meta` only (`^1.15.0`). `typed_openapi_dio` depends on `typed_openapi_client` and `dio: ^5.11.1`. `typed_openapi_transport_tests` is `publish_to: none` and depends on `test` and `typed_openapi_client`.
- Generated output changes only as decision 7 says: the import of `package:dio` goes, the package import is `package:typed_openapi_client/typed_openapi_client.dart`, `Dio dio` becomes `ClientTransport transport`, `DioRequestSender` becomes `ClientSender`, and the doc comments that name Dio name the transport. A golden diff shows nothing else.
- The wire does not change: the same URL, headers and bytes for the same call. The ported M9/M10 tests keep their expected values; the generated-client programs (`calls`, `wire_calls`, `stream_calls`) keep their expected output files byte for byte. Known exception, an open question below: a multipart file part with no media type is `application/octet-stream` (Dio guessed one from the file name).
- Dart 3.10 features (dot shorthands, null-aware elements, patterns, records, class modifiers); OOP, no top-level functions except `main`; every public member has a doc comment; no `// ignore:`; no `!` where a pattern can promote.
- Size limits: `lib/` file 300 lines, test file 500, method 40, 5 parameters, 3 nesting levels; allowlisted units never grow; files that move keep their allowlist entry under the new path; the two new packages get the size ratchet test with empty allowlists.
- After every task: `dart pub get` and `dart analyze packages` (root, `No issues found!`); `dart test` in every workspace package; `dart test -p chrome` and `dart test -p chrome --compiler dart2wasm` in `typed_openapi_client` and `typed_openapi_dio`; `dart format lib test` (generator and tool: `lib test bin`) changes 0 files on a second run. Chrome: `CHROME_EXECUTABLE=/usr/bin/google-chrome` where it is not found.
- Every change of generated output runs `dart run bin/corpus.dart update` in the tool package; only the file hashes of `corpus.lock` change, the diagnostics and the round-trip counts stay equal (checked with `git diff` of the lock filtered to `diagnostics` and `values`).
- The generator's CHANGELOG top section is `0.0.1 - Unreleased`: an entry under `### Output changes` is enough, no version bump (spec, semver gate).
- Tests never touch the network; temp files only through `TempDir`. The conformance server binds `127.0.0.1` on port 0.
- Commits are Conventional Commits ending with the `Co-Authored-By` line of the model that does the task.

## Decisions taken

The spec leaves these to the plan.

1. **`TransportRequest` is a class**, not a record (it has a derived `contentLength` and doc comments per field): `method`, `target`, `operation` (`OperationInfo`, required), `headers` (`Map<String, List<String>>`, names as the core wrote them), `body` (`Stream<List<int>>?`), `cancel` (`CancelSignal?`), `extra` (`Map<String, Object?>`), `isEventStream` (`bool`, so an adapter can refuse SSE where it cannot stream). `contentLength` reads the `content-length` header.
2. **`CancelSignal`** is a final class over a `Completer<void>`: `cancel([Object? reason])`, `isCancelled`, `reason`, `whenCancelled` (`Future<void>`). A signal cancelled before a call makes the call `Cancelled` without calling the transport.
3. **`TransportException`** implements `Exception`: `kind` (`TransportExceptionKind.timeout`, `.connection`, `.cancelled`, `.other`), `message`, `cause` (`Object?`), `stackTrace` (`StackTrace?`); `toString()` is `TransportException(<kind>): <message>`. `TransportError.toString()` keeps its shape with the kind's name (`TransportError(timeout)`; Dio's `connectionTimeout`, `sendTimeout`, `receiveTimeout` all map to `timeout`, `connectionError` and `badCertificate` to `connection`, `cancel` to `cancelled`, `unknown` and `badResponse` without a response to `other`).
4. **Body encoding** lives in `request/`: `BodyEncoder` (one per `ClientSender`) returns an `EncodedBody` (bytes or a stream, its length when known, its media type); `MultipartEncoder` writes Dio's `FormData` wire format byte for byte (fields first while no file or typed part precedes them, `content-disposition: form-data; name="..."`, `%0D%0A` and `%22` escaping, `--<boundary>--\r\n` at the end); `ParsedMediaType` replaces `package:http_parser`'s `MediaType` for the charset of text parts. In-memory bodies are streamed in chunks of 1024 bytes, as Dio did, so send progress reports the same counts.
5. **Progress** is counted in the core (`ProgressCounter`): `onSendProgress` counts the chunks the transport pulls from the request stream against `contentLength` (`-1` when unknown); `onReceiveProgress` counts the response chunks against `content-length`. The callbacks are `void Function(int count, int total)?` (no typedef: `ProgressCallback` is Dio's name).
6. **Headers.** The core merges, in order, `Accept` (`OperationRequest.accept`; `text/event-stream` for events), the operation's headers, the call's `headers` (case-insensitive merge: the first spelling stays, the last value wins; a `null` value is not sent; a list is one value per item), `Last-Event-ID` for event streams, then `content-type` (the operation's; a call's `Content-Type` is dropped when the body has a type) and `content-length` when known.
7. **`OperationInfo.of(RequestOptions)` moves** to the adapter as `DioTransport.operationOf(RequestOptions options)`; `OperationInfo.extraKey` stays in the core (its value `typed_openapi.operation` does not change), so an interceptor reads the same key.
8. **The query guard** (a target whose query holds `//` is refused under a base URL, M9) and the **web check** (SSE through Dio's default browser adapter, which buffers) move into `DioTransport`; both become a `TransportException` of kind `other` with the M9/M10 message.
9. **Invalid JSON** is read by the core: `DecodeError` with the status and the body text (Dio dropped the response before; `statusCode` stays `int?` for source compatibility).
10. **`SseReconnector`** takes `cancel: CancelSignal?` in place of `cancelled: Future<DioException>?`; a `SseDisconnected` whose cause is a `TransportException` of kind `cancelled` ends the stream; a `TransportError` of any other kind reconnects.
11. **`DartNames.takenTypeNames`** loses `Dio` and `DioRequestSender` and gains every type the core exports (`runtime_names_test.dart` requires each exported type to be reserved): `CancelSignal`, `ClientSender`, `ClientTransport`, `TransportException`, `TransportExceptionKind`, `TransportRequest`, `TransportResponse`. `test/ir/dio_names_test.dart` changes: a schema named `Dio` keeps its name; a schema named `ClientTransport` becomes `ClientTransportModel` with TOA550.
12. **The generated-client programs** (`test/emit/programs/*.dart.txt`) replace their fake Dio adapter with a fake `ClientTransport` that prints the same lines; the expected output files do not change, which is the wire proof for the petstore client.
13. **The corpus package** (`CorpusPackage` pubspec template) drops `dio` and depends on `typed_openapi_client` by path.

## Files

| Path | Task | What |
| --- | --- | --- |
| `packages/typed_openapi_runtime/` -> `packages/typed_openapi_client/` | 1 | `git mv`; library `typed_openapi_client.dart` |
| `packages/typed_openapi_client/lib/src/transport/{cancel_signal,transport_exception,client_transport,transport_request,transport_response}.dart` | 2 | new types, exported |
| `packages/typed_openapi_client/lib/src/request/{parsed_media_type,encoded_body,multipart_encoder,body_encoder}.dart` | 3 | core body encoding |
| `packages/typed_openapi_client/lib/src/client/{client_sender,event_opener,event_call,connection_signals,request_builder,response_reader,progress_counter,client_results,call_options}.dart` | 4 | replaces `lib/src/dio/` |
| `packages/typed_openapi_client/lib/src/{result/result,request/operation_info,sse/sse_reconnector}.dart` | 4 | Dio types replaced |
| `packages/typed_openapi_client/test/helpers/fake_transport.dart`, `gated_transport.dart` | 4 | replace `fake_adapter.dart`, `gated_adapter.dart` |
| `packages/typed_openapi_client/test/client/*` | 4 | ports of `test/dio/*` |
| `packages/typed_openapi/lib/src/emit/{operation_emitter,api_library}.dart`, `lib/src/ir/{names,operation_checks}.dart` | 5 | generated code takes `ClientTransport` |
| `packages/typed_openapi/test/emit/programs/*`, goldens, `CHANGELOG.md` | 5 | |
| `packages/typed_openapi_tool/lib/src/corpus/corpus_package.dart`, `corpus.lock` | 5 | |
| `packages/typed_openapi_dio/` | 6 | `DioTransport`, Dio-specific tests |
| `packages/typed_openapi_transport_tests/` | 7 | `ConformanceServer`, `TransportConformance` |
| `.github/workflows/{ci,nightly,publish}.yml`, `packages/typed_openapi_tool/test/ci/workflows_test.dart`, `pubspec.yaml` | 8 | CI, workspace |
| READMEs, `doc/`, `CLAUDE.md`, `docs/roadmap.md`, `docs/superpowers/HANDOFF.md`, `docs/code-quality-review.md` | 9 | docs |

## Interfaces between tasks

```dart
// typed_openapi_client (task 2)
final class CancelSignal {
  CancelSignal();
  bool get isCancelled;
  Object? get reason;
  Future<void> get whenCancelled;
  void cancel([Object? reason]);
}
enum TransportExceptionKind { timeout, connection, cancelled, other }
final class TransportException implements Exception {
  const TransportException(this.kind, this.message, {this.cause, this.stackTrace});
  final TransportExceptionKind kind;
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;
}
abstract interface class ClientTransport {
  Future<TransportResponse> send(TransportRequest request);
}
final class TransportRequest {
  const TransportRequest({
    required this.method, required this.target, required this.operation,
    this.headers = const {}, this.body, this.cancel,
    this.extra = const {}, this.isEventStream = false,
  });
  int? get contentLength; // from the content-length header
}
final class TransportResponse {
  const TransportResponse({required this.statusCode, required this.body,
    this.headers = const {}}); // header names in lower case
  final Stream<List<int>> body;
}

// task 3
final class BodyEncoder {
  BodyEncoder(String Function() boundary);
  EncodedBody? encode(OperationRequest request);
}
final class EncodedBody {
  EncodedBody.bytes(Uint8List bytes, {String? contentType});
  EncodedBody.stream(Stream<List<int>> stream, {int? length, String? contentType});
  int? get length; String? get contentType;
  Stream<List<int>> read(); // 1024-byte chunks for bytes
}

// task 4
final class ClientSender {
  ClientSender(ClientTransport transport, {String Function()? boundary});
  Future<Result<T, E>> send<T, E>(OperationRequest request,
      Result<T, E> Function(RawResponse response) decode, {CallOptions? call});
  Future<Result<Stream<SseItem<T>>, E>> openEvents<T, E>(
      OperationRequest request, T Function(SseMessage message) decodeEvent,
      Result<Stream<SseItem<T>>, E> Function(RawResponse response) decodeError,
      {CallOptions? call, SseReconnection reconnection = .onRequest});
}
final class CallOptions {
  const CallOptions({this.cancel, this.headers = const {}, this.extra = const {},
    this.onSendProgress, this.onReceiveProgress, this.sse});
  final CancelSignal? cancel;
  final void Function(int count, int total)? onSendProgress;
  final void Function(int count, int total)? onReceiveProgress;
}
// TransportError(TransportException exception, StackTrace stackTrace)
// Cancelled(TransportException exception, StackTrace stackTrace)

// typed_openapi_dio (task 6)
final class DioTransport implements ClientTransport {
  DioTransport(Dio dio, {bool? isWeb});
  static OperationInfo? operationOf(RequestOptions options);
}

// typed_openapi_transport_tests (task 7)
final class TransportConformance {
  TransportConformance(ClientTransport Function(Uri baseUrl) transport,
      {Set<String> skips = const {}}); // case name -> stated reason in the map form
  void register(); // declares the test groups
}
```

## Size ratchet changes

- Task 1: every allowlist entry of the runtime keeps its value under `packages/typed_openapi_client/` (the ratchet test reads relative paths, so nothing changes in the file).
- Task 4: `test/dio/dio_request_sender_test.dart: 537` and `lib/src/dio/dio_request_sender.dart#DioRequestSender.openEvents: 51` are removed (the files are deleted; their ports are below the limits).
- Tasks 6, 7: the new packages get `test/quality/size_limits_test.dart` with empty allowlists.

---

### Task 1: Rename `typed_openapi_runtime` to `typed_openapi_client`

Replayed from main. No API change: only the package name, its library file and the generated import line.

**Files:** `packages/typed_openapi_runtime/` -> `packages/typed_openapi_client/` (`git mv`), `lib/typed_openapi_runtime.dart` -> `lib/typed_openapi_client.dart`; every `typed_openapi_runtime` in `pubspec.yaml`, `.github/workflows/`, and the `lib/`, `test/`, `bin/` and `pubspec.yaml` of each package; the client's pubspec description; 25 golden files; `packages/typed_openapi/CHANGELOG.md`; `packages/typed_openapi_tool/corpus.lock`.

- [ ] **Step 1: Move the package and rewrite the name** (from the root)

```sh
git mv packages/typed_openapi_runtime packages/typed_openapi_client
git mv packages/typed_openapi_client/lib/typed_openapi_runtime.dart \
  packages/typed_openapi_client/lib/typed_openapi_client.dart
git grep -l typed_openapi_runtime -- pubspec.yaml .github/workflows \
  'packages/*/lib/**' 'packages/*/test/**' 'packages/*/bin/**' \
  'packages/*/pubspec.yaml' \
  | xargs sed -i 's/typed_openapi_runtime/typed_openapi_client/g'
```

- [ ] **Step 2: Describe the package** in `packages/typed_openapi_client/pubspec.yaml`:

```yaml
description: >-
  The core of clients generated by typed_openapi: typed errors, Result,
  Patch for tri-state fields, JSON decoding with paths, parameter encoders
  and an SSE decoder.
```

- [ ] **Step 3: Regenerate the goldens** (the longer import line wraps differently)

```sh
dart pub get
cd packages/typed_openapi && UPDATE_GOLDENS=1 dart test \
  test/emit/api_library_test.dart test/emit/generated_code_test.dart \
  test/emit/event_stream_emit_test.dart
```

Expected: 25 golden files change, each only in its `import 'package:typed_openapi_client/...'` lines.

- [ ] **Step 4: Write the output change** at the top of the `0.0.1 - Unreleased` section of `packages/typed_openapi/CHANGELOG.md`, under `### Output changes`:

```markdown
- Generated files import `package:typed_openapi_client/typed_openapi_client.dart`
  in place of `package:typed_openapi_runtime/typed_openapi_runtime.dart`: the
  runtime package is renamed (M11b).
```

- [ ] **Step 5: Update the corpus lock**

```sh
cd packages/typed_openapi_tool && dart run bin/corpus.dart update
git diff -U0 corpus.lock | grep -E '^[-+] ' | grep -vE '"[0-9a-f]{64}"' | head
```

Expected: `update` writes the lock; the filtered diff is empty (only file hashes changed; diagnostics and round-trip counts are equal).

- [ ] **Step 6: Verify**

Expected counts: generator `+1376 ~1`, client `+287` (Chrome dart2js `+280`, dart2wasm `+280`), tool `+198`; analyze clean; format 0 changes.

- [ ] **Step 7: Commit**

```sh
git add -A && git commit -m "refactor: rename typed_openapi_runtime to typed_openapi_client"
```

---

### Task 2: Transport types in the core (additive)

**Files:** create `lib/src/transport/{cancel_signal,transport_exception,client_transport,transport_request,transport_response}.dart`, tests `test/transport/{cancel_signal_test,transport_request_test}.dart`; export the five files from `lib/typed_openapi_client.dart`; add the seven names to `DartNames.takenTypeNames` in `packages/typed_openapi/lib/src/ir/names.dart` (keep `Dio` and `DioRequestSender` until task 5).

Tests: `'a new signal is not cancelled'`; `'cancel completes whenCancelled and keeps the first reason'`; `'a second cancel does nothing'`; `'contentLength reads the content-length header'` (`null` without it); `'TransportException prints its kind and message'`.

Verification: client `+292`, generator `+1376 ~1` (runtime_names_test passes with the new names), tool `+198`; Chrome both compilers.

Commit: `feat(typed_openapi_client): transport types`.

### Task 3: Core body encoding

**Files:** create `lib/src/request/{parsed_media_type,encoded_body,multipart_encoder,body_encoder}.dart`; tests `test/request/{multipart_encoder_test,body_encoder_test,parsed_media_type_test}.dart`. Nothing uses them yet; `DioBody` and `MultipartForm` stay until task 4.

Rules (ported from `DioBody`, `MultipartForm` and Dio 5.11.1's `FormData`):
- JSON media types (`MediaTypeText.isJson`): `jsonEncode(body)` as UTF-8, `null` included (`'null'`); a `FormBody`: form text (as `DioBody` builds it today), `application/x-www-form-urlencoded`; a `MultipartBody`: `MultipartEncoder`; a `FileUpload`: its bytes or stream with its own length, its media type validated (`FormatException`) and sent as written; a `Uint8List`: raw; a `String` with a non-JSON type: UTF-8; `null` with a non-JSON type: no body.
- Multipart: `multipart/form-data; boundary=<boundary>`; per part `--<boundary>\r\n`, `content-disposition: form-data; name="<name>"` (+ `; filename="<file>"`), `\r\ncontent-type: <type>` for file and typed parts, `\r\n\r\n`, data, `\r\n`; end `--<boundary>--\r\n`; names and file names escape `\r\n`, `\r`, `\n` as `%0D%0A` and `"` as `%22`; a text part after a file or typed part is a `text/plain; charset=utf-8` part; a typed text part uses the charset of its media type (`Encoding.getByName`, UTF-8 when unknown) and writes it back into the type; the length is computed before sending.
- The `ArgumentError`s of `MultipartForm` stay word for word.

Proof of the wire: a scratch-only test (not committed) encodes the M9 cases with both `MultipartEncoder` and Dio's `FormData` (boundary fixed) and compares the bytes; the committed tests hold the expected bytes literally.

Verification: client count rises by the new tests; everything else unchanged. Commit: `feat(typed_openapi_client): encode request bodies in the core`.

### Task 4: `ClientSender` replaces `DioRequestSender`

**Files:** create `lib/src/client/` (see Files); delete `lib/src/dio/`; edit `lib/src/result/result.dart` (`TransportException` in `TransportError` and `Cancelled`), `lib/src/request/operation_info.dart` (drop `of` and the Dio import), `lib/src/sse/sse_reconnector.dart` (decision 10), `lib/typed_openapi_client.dart` (export `client/call_options.dart` and `client/client_sender.dart`; drop `dio/`), `pubspec.yaml` (drop `dio`); `test/helpers/{fake_transport,gated_transport,pets_api,watch_stream}.dart`; port `test/dio/*` to `test/client/*` and update the SSE and request tests that build Dio objects.

Port map (old -> new): `dio_request_sender_test` -> `client/send_test.dart` and `client/send_failures_test.dart` (split under 500 lines); `bodies_send_test`, `json_body_test`, `multipart_send_test` -> `client/*` with a fixed boundary `'b'` and the same expected bytes; `accept_test`, `open_events_test` -> `client/*`; `web_test` and `cookie_browser_test`/`cookie_server` -> moved to `typed_openapi_dio` in task 6 (they test Dio's browser adapter); cases that test Dio itself (interceptor sees `OperationInfo`, Dio not mutated, an `Error` in an interceptor, a resolved response, the `//` query guard) -> task 6.

New behaviour tests: `'a signal cancelled before the call returns Cancelled without sending'`; `'a JSON body that does not parse is a DecodeError with the status'`; `'send progress counts 1024-byte chunks against the length'`; `'receive progress counts against content-length'`; `'an Exception while reading the body is a TransportError of kind other'`.

Verification: client tests green on VM and Chrome; generator and tool untouched in this task except `names.dart` if a name moved. Commit: `feat(typed_openapi_client)!: send through a ClientTransport`.

### Task 5: Generated code takes a `ClientTransport`

**Files:** `packages/typed_openapi/lib/src/emit/operation_emitter.dart` (group constructor `PetsApi(ClientTransport transport) : _sender = ClientSender(transport);`, imports `ClientSender, ClientTransport` from the client package, no `package:dio`), `lib/src/emit/api_library.dart` (root: `(ClientTransport transport)`, `${group.name}(transport)`, doc "Set the base URL on your transport."), `lib/src/ir/names.dart` (decision 11), `lib/src/ir/operation_checks.dart` (TOA566 text: "base URL of your transport"), tests `test/ir/dio_names_test.dart` (renamed `transport_names_test.dart`), `test/emit/generated_client_test.dart` (pubspec without `dio`), the programs (decision 12), goldens, `CHANGELOG.md`; tool `lib/src/corpus/corpus_package.dart` (decision 13), `corpus.lock`.

Verification: golden diff limited to the Global Constraints list; `generated_client_test` passes with the expected program outputs unchanged; `corpus update` with only hashes changed; fuzz `dart run bin/fuzz.dart --seeds 200` green. Commit: `feat(typed_openapi)!: generated clients take a ClientTransport`.

### Task 6: `typed_openapi_dio`

**Files:** `packages/typed_openapi_dio/{pubspec.yaml,README.md,CHANGELOG.md,LICENSE,analysis_options.yaml,dart_test.yaml}`, `lib/typed_openapi_dio.dart`, `lib/src/{dio_transport,dio_exceptions,dio_request_options}.dart`, tests `test/{dio_transport_test,interceptor_test,web_test,cookie_browser_test,cookie_server}.dart`, `test/quality/size_limits_test.dart`; root `pubspec.yaml` workspace entry.

Behaviour: `dio.request<ResponseBody>(target, data: body, options: Options(method:, headers:, responseType: .stream, extra: {...extra, OperationInfo.extraKey: operation}), cancelToken:)`; the `CancelSignal` cancels a `CancelToken` made per request; `DioException.badResponse` with a `ResponseBody` -> `TransportResponse`; other types -> `TransportException` (decision 3) with `cause` the `DioException`; never mutates `dio` (`options`, `interceptors`, `transformer` compared before and after in a test).

Tests: the ported Dio-specific cases of task 4 and `'an onError interceptor that retries a 401 with a new token gets the 200'` against the loopback server of task 7 (this test lands in task 7 when the server exists).

Commit: `feat(typed_openapi_dio): the Dio transport`.

### Task 7: Conformance server and suite

**Files:** `packages/typed_openapi_transport_tests/` (`lib/src/conformance_server.dart` with `hybridMain` in `lib/src/server_main.dart` for `spawnHybridUri`, `lib/src/transport_conformance.dart` and one file per case group: methods, headers, responses, statuses, bodies, cancellation, failures, events, progress); `typed_openapi_dio/test/conformance_test.dart` runs it on the VM and in Chrome with the stated skips (repeated request headers, cookies, `HEAD` body rules, in-flight upload progress and stream uploads on the web).

Commit: `test(typed_openapi_transport_tests): transport conformance suite`.

### Task 8: CI, workspace, publish

`ci.yml`: tests of `typed_openapi_dio` and `typed_openapi_transport_tests` in the matrix; the web job runs the client and the adapter with both compilers; the publish dry-run step covers `typed_openapi_client` and `typed_openapi_dio`. `nightly.yml` the same for the beta SDK. `workflows_test.dart` pins the new rows. `publish.yml` publishes the two packages.

Commit: `ci: test and publish the client and the Dio adapter`.

### Task 9: Documentation

The runtime README and `doc/` move to the client; the Dio parts (setup, web, interceptors, cancellation, `operationOf`, the bypassed `Transformer`) go to `typed_openapi_dio/README.md`; `sse.md` and `event_streams.md` split; `CLAUDE.md` (Project, Runtime section rewritten for client + adapter + conformance), `docs/roadmap.md` (M11b row), `docs/superpowers/HANDOFF.md`, `docs/code-quality-review.md` (moved paths).

Commit: `docs: the client core and the Dio adapter`.

---

## Corpus run

Task 1 (replayed): `corpus update` regenerated every client of both modes; only file hashes changed in `corpus.lock`; diagnostics and round-trip counts equal; round-trip failures 0. Tasks 5 onwards: not run.

## Fuzz

Not run (task 5).

## Defects found

None in the code on main while replaying task 1.

## Deferred

- A `package:http` or `dart:io` adapter (spec, out of scope).

## Open questions

1. **A multipart file part with no media type** (the file gives none and the spec's `encoding` gives none): Dio guessed one from the file name (`x.gif` -> `image/gif`); the core depends on `meta` only and sends `application/octet-stream`. Default: `application/octet-stream` (a wire change for such parts, written in the client CHANGELOG).
2. Interceptors see bytes (spec open question 1). Default: bytes.
3. The conformance package is separate and unpublished (spec open question 2). Default: separate.
4. `HEAD` and redirects (spec open question 3). Default: Dio's own, documented by the suite.
5. The tool's `--runtime` option keeps its name (it now points at the client package). Default: kept.

## Not replayed

Tasks 2 to 9 were not replayed from main with code blocks from this plan. Staged, uncompiled drafts of the task 2-4 code exist only in the planning session's scratchpad and are not part of this plan.

## Self-review

- Spec coverage: decisions 1-10 map to tasks 1-9; the builder-check calls are decisions 3, 5, 6, 8, 10 here and task 6.
- Interfaces: names are the same in every task (`ClientSender`, `ClientTransport`, `CancelSignal`, `TransportException(kind, message, {cause, stackTrace})`, `DioTransport.operationOf`).
