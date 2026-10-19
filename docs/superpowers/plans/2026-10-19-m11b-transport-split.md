# M11b plan: transport split, client core and Dio adapter

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status:** All seven tasks were replayed from main (2d86694) on a scratch
> worktree, in this order, and each task's code is in this plan as the
> patch that was verified (new files in full, edits as unified diffs; apply
> with `git apply`, see "How to use the patches"). Task 4 holds three parts
> (core sender, Dio adapter, generated code) that only pass together, so it
> has one gate and one commit; every task leaves every suite green.

**Goal:** Generated clients stop depending on Dio: `typed_openapi_runtime` becomes `typed_openapi_client` (core, `meta` only) with a thin `ClientTransport`, `ClientSender` and its own body encoding, cancellation and errors; `typed_openapi_dio` adapts a user's `Dio`; a conformance package checks any transport against a loopback server; the generator emits `ClientTransport` groups.

**Architecture:** The core builds the finished request (target, headers, body bytes as a stream with a known length), calls `ClientTransport.send`, reads the response stream itself (`RawResponse`) or hands it to the SSE decoder, and maps everything to `Result`. `DioTransport` sends the finished request with `dio.request` and `ResponseType.stream`, keeps Dio's error path (a `badResponse` becomes a `TransportResponse` again) and maps every other `DioException` to a `TransportException`. `typed_openapi_transport_tests` holds a `dart:io` loopback server and the `TransportConformance` suite, run by the Dio package on the VM and in Chrome (dart2js, dart2wasm).

**Tech Stack:** Dart `>=3.10.0 <4.0.0`, pure Dart; `package:test`; Dio 5.11.1 (adapter only); Chrome for the web runs.

**Spec:** [docs/superpowers/specs/2026-10-19-m11b-transport-split-design.md](../specs/2026-10-19-m11b-transport-split-design.md), decisions 1-10 and the "Calls made after the builder check" (binding). Brief: [m11b-plan.md](../briefs/m11b-plan.md). Code rules and size limits: [CLAUDE.md](../../../CLAUDE.md), [code-quality-review.md](../../code-quality-review.md).

## Global Constraints

- SDK `>=3.10.0 <4.0.0` for every package and for generated code; the core and the adapter work on the VM, dart2js and dart2wasm.
- `typed_openapi_client` depends on `meta` only (`^1.15.0`). `typed_openapi_dio` depends on `typed_openapi_client` and `dio: ^5.11.1`. `typed_openapi_transport_tests` is `publish_to: none` and depends on `test` and `typed_openapi_client`.
- Generated output changes only as decision 7 says: the import of `package:dio` goes, the package import is `package:typed_openapi_client/typed_openapi_client.dart`, `Dio dio` becomes `ClientTransport transport`, `DioRequestSender` becomes `ClientSender`, and the doc comments that name Dio name the transport. A golden diff shows nothing else.
- The wire does not change: the same URL, headers and bytes for the same call. The ported M9/M10 tests keep their expected values; the generated-client programs (`calls`, `wire_calls`, `union_calls`, `hostile_events`) keep their expected output byte for byte through `DioTransport`, and `stream_calls` changes only in the names of the end causes (`end connectionError` -> `end connection`, `end cancel` -> `end cancelled`: the kind of the `TransportException`). Known exception, open question 1: a multipart file part with no media type is `application/octet-stream` (Dio guessed one from the file name).
- Dart 3.10 features (dot shorthands, null-aware elements, patterns, records, class modifiers); OOP, no top-level functions except `main`; every public member has a doc comment; no `// ignore:`; no `!` where a pattern can promote.
- Size limits: `lib/` file 300 lines, test file 500, method 40, 5 parameters, 3 nesting levels; allowlisted units never grow; files that move keep their allowlist entry under the new path; the new packages get the size ratchet test with empty allowlists (task 7; not replayed).
- No int literal beyond 2^31 built by a shift in `lib/`: `1 << 32` is `0` in JavaScript (a defect the replay found in the multipart boundary, task 4).
- After every task: `dart pub get` and `dart analyze packages` (root, `No issues found!`); `dart test` in every workspace package (task 4 is one task for this reason: inside it, before part 4c, the generator's `generated_client_test` is red, because the generated code still names `DioRequestSender`); `dart test -p chrome` and `dart test -p chrome --compiler dart2wasm` in `typed_openapi_client` and `typed_openapi_dio`; `dart format lib test` (generator and tool: `lib test bin`) changes 0 files on a second run. Chrome: `CHROME_EXECUTABLE=/usr/bin/google-chrome` where it is not found.
- Every change of generated output runs `dart run bin/corpus.dart update` in the tool package; only the file hashes of `corpus.lock` change, the diagnostics and the round-trip counts stay equal (checked with `git diff` of the lock filtered to `diagnostics` and `values`).
- The generator's CHANGELOG top section is `0.0.1 - Unreleased`: an entry under `### Output changes` is enough, no version bump (spec, semver gate).
- Tests never touch the network; temp files only through `TempDir`. The conformance server binds `127.0.0.1` on port 0.
- Commits are Conventional Commits ending with the `Co-Authored-By` line of the model that does the task.

## Decisions taken

The spec leaves these to the plan.

1. **`TransportRequest` is a class**, not a record (it has a derived `contentLength` and doc comments per field): `method`, `target`, `operation` (`OperationInfo`, required), `headers` (`Map<String, List<String>>`, names as the core wrote them), `body` (`Stream<List<int>>?`), `cancel` (`CancelSignal?`), `extra` (`Map<String, Object?>`), `isEventStream` (`bool`, so an adapter can refuse SSE where it cannot stream). `contentLength` reads the `content-length` header.
2. **`CancelSignal`** is a `base class` (tests subclass it to count listeners) over a `Completer<void>`: `cancel([Object? reason])`, `isCancelled`, `reason`, `whenCancelled` (`Future<void>`). A signal cancelled before a call makes the call `Cancelled` without calling the transport.
3. **`TransportException`** implements `Exception`: `kind` (`TransportExceptionKind.timeout`, `.connection`, `.cancelled`, `.other`), `message`, `cause` (`Object?`), `stackTrace` (`StackTrace?`); `toString()` is `TransportException(<kind>): <message>`. `TransportError.toString()` keeps its shape with the kind's name (`TransportError(timeout)`; Dio's `connectionTimeout`, `sendTimeout`, `receiveTimeout` all map to `timeout`, `connectionError` and `badCertificate` to `connection`, `cancel` to `cancelled`, `unknown` and `badResponse` without a response to `other`).
4. **Body encoding** lives in `request/`: `BodyEncoder` (one per `ClientSender`) returns an `EncodedBody` (bytes or a stream, its length when known, its media type); `MultipartEncoder` writes Dio's `FormData` wire format byte for byte (fields first while no file or typed part precedes them, `content-disposition: form-data; name="..."`, `%0D%0A` and `%22` escaping, `--<boundary>--\r\n` at the end); `ParsedMediaType` replaces `package:http_parser`'s `MediaType` for the charset of text parts. In-memory bodies are streamed in chunks of 1024 bytes, as Dio did, so send progress reports the same counts.
5. **Progress** is counted in the core (`ProgressCounter`): `onSendProgress` counts the chunks the transport pulls from the request stream against `contentLength` (`-1` when unknown); `onReceiveProgress` counts the response chunks against `content-length`. The callbacks are `void Function(int count, int total)?` (no typedef: `ProgressCallback` is Dio's name).
6. **Headers.** The core merges, in order, `Accept` (`OperationRequest.accept`; `text/event-stream` for events), the operation's headers, the call's `headers` (case-insensitive merge: the first spelling stays, the last value wins; a `null` value is not sent; a list is one value per item), `Last-Event-ID` for event streams, then `content-type` (the operation's; a call's `Content-Type` is dropped when the body has a type) and `content-length` when known.
7. **`OperationInfo.of(RequestOptions)` moves** to the adapter as `DioTransport.operationOf(RequestOptions options)`; `OperationInfo.extraKey` stays in the core (its value `typed_openapi.operation` does not change), so an interceptor reads the same key.
8. **The query guard** (a target whose query holds `//` is joined to an absolute base URL here, so Dio does not collapse the `//`, M9) moves into the adapter as `QueryGuard`; the **web check** (SSE through Dio's default browser adapter, which buffers) moves into `DioTransport` and throws a `TransportException` of kind `other` with the M10 message (`DioTransport.webStreamingMessage`), its cause an `UnsupportedError`. A `FormatException` from an interceptor is no longer a `DecodeError` on the web: the core parses the JSON, so the two failures are told apart (web_test changes accordingly).
9. **Invalid JSON** is read by the core: `DecodeError` with the status and the body text (Dio dropped the response before; `statusCode` stays `int?` for source compatibility).
10. **`SseReconnector`** takes `cancel: CancelSignal?` in place of `cancelled: Future<DioException>?`; a `SseDisconnected` whose cause is a `TransportException` of kind `cancelled` ends the stream; a `TransportError` of any other kind reconnects.
11. **`DartNames.takenTypeNames`** loses `Dio` and `DioRequestSender` and gains every type the core exports (`runtime_names_test.dart` requires each exported type to be reserved): `CancelSignal`, `ClientSender`, `ClientTransport`, `TransportException`, `TransportExceptionKind`, `TransportRequest`, `TransportResponse` (added in task 2; no corpus schema has these names). `test/ir/dio_names_test.dart` becomes `transport_names_test.dart`: a schema named `Dio` keeps its name; a schema named `ClientTransport` becomes `ClientTransportModel` with TOA550 (`name-reserved`). `operation_contract_test.dart` pins `Dio` in place of `DioModel`.
12. **The generated-client programs** (`test/emit/programs/*.dart.txt`) keep their fake Dio adapter and wrap the `Dio` in `DioTransport`: the run goes through the real adapter, so the unchanged expected outputs prove the wire through Dio, not through a second fake. The fixture package depends on `typed_openapi_dio` by path and needs a `dependency_overrides:` entry for `typed_openapi_client` (the adapter depends on the hosted version; without it `pub get` fails). The order of tasks follows: the adapter (task 5) before the generator (task 6).
13. **The corpus package** (`CorpusPackage` pubspec template) drops `dio` and depends on `typed_openapi_client` by path; the fuzz's hostile name suffix `Dio` becomes `Transport`.
14. **Event-stream items keep their shape**: the core reads the response body chunks itself, so a `TransportResponse.body` error is mapped by the adapter (`DioFailures.body`: a `DioException` while reading becomes a `TransportException`, so a cancel mid-stream ends the stream as `cancelled`).

## Files

| Path | Task | What |
| --- | --- | --- |
| `packages/typed_openapi_runtime/` -> `packages/typed_openapi_client/` | 1 | `git mv`; library `typed_openapi_client.dart` |
| `packages/typed_openapi_client/lib/src/transport/{cancel_signal,transport_exception,client_transport,transport_request,transport_response}.dart` | 2 | new types, exported |
| `packages/typed_openapi_client/lib/src/request/{parsed_media_type,encoded_body,multipart_encoder,body_encoder}.dart` | 3 | core body encoding |
| `packages/typed_openapi_client/lib/src/client/{client_sender,event_opener,event_call,connection_signals,request_builder,response_reader,progress_counter,client_results,call_options}.dart` | 4a | replaces `lib/src/dio/` |
| `packages/typed_openapi_client/lib/src/{result/result,request/operation_info,sse/sse_reconnector}.dart` | 4a | Dio types replaced |
| `packages/typed_openapi_client/test/helpers/fake_transport.dart`, `gated_transport.dart` | 4a | replace `fake_adapter.dart`, `gated_adapter.dart` |
| `packages/typed_openapi_client/test/client/*` | 4a | ports of `test/dio/*` |
| `packages/typed_openapi_dio/` | 4b | `DioTransport`, `DioFailures`, `QueryGuard`, Dio-specific, web, cookie and loopback tests |
| `packages/typed_openapi/lib/src/emit/{operation_emitter,api_library,decoder_writer}.dart`, `lib/src/ir/{names,operation_checks}.dart`, `lib/src/model/media_type_name.dart`, `lib/src/diagnostics/diagnostic_code.dart` | 4c | generated code takes `ClientTransport` |
| `packages/typed_openapi/test/emit/{programs/*,generated_client_test.dart}`, `test/ir/{transport_names_test,operation_contract_test}.dart`, goldens, `CHANGELOG.md` | 4c | |
| `packages/typed_openapi_tool/lib/src/{corpus/corpus_package,fuzz/fuzz_spec}.dart`, `corpus.lock` | 4c | |
| `packages/typed_openapi_transport_tests/` | 5 | `ConformanceServer`, `TransportConformance` |
| `.github/workflows/{ci,nightly,publish}.yml`, `packages/typed_openapi_tool/test/ci/workflows_test.dart`, `pubspec.yaml` | 6 | CI, workspace |
| READMEs, `doc/`, `CLAUDE.md`, `docs/roadmap.md`, `docs/superpowers/HANDOFF.md`, `docs/code-quality-review.md` | 7 | docs |

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

// task 4a
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

// typed_openapi_dio (task 4b)
final class DioTransport implements ClientTransport {
  DioTransport(Dio dio, {bool? isWeb});
  static const String webStreamingMessage;
  static OperationInfo? operationOf(RequestOptions options);
}

// typed_openapi_transport_tests (task 5)
final class TransportConformance {
  TransportConformance(ClientTransport Function(Uri baseUrl) transport,
      {Set<String> skips = const {}}); // case name -> stated reason in the map form
  void register(); // declares the test groups
}
```

## Size ratchet changes

- Task 1: every allowlist entry of the runtime keeps its value under `packages/typed_openapi_client/` (the ratchet test reads relative paths, so nothing changes in the file).
- Task 4: `test/dio/dio_request_sender_test.dart: 537` and `lib/src/dio/dio_request_sender.dart#DioRequestSender.openEvents: 51` are removed (the files are deleted; their ports are below the limits).
- The new packages get no size ratchet test in M11b (see Deferred): every file of `typed_openapi_dio` and `typed_openapi_transport_tests` is below the limits; the longest `lib/` file is `dio_transport.dart`, 120 lines.

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

Expected counts: generator `+1376 ~1`, client `+287` (Chrome dart2js `+280`, dart2wasm `+280`), tool `+198`; analyze clean; format 0 changes. Corpus: 40 clients (38 generated, 2 with expected check errors), 27759 files, about 9.5 minutes.

- [ ] **Step 7: Commit**

```sh
git add -A && git commit -m "refactor: rename typed_openapi_runtime to typed_openapi_client"
```

---

### How to use the patches

Each replayed task below ends with the patch that was verified, produced with `git show --format= -M --diff-filter=d` (the files a task deletes are listed before the patch as a `git rm` command; run it first). To apply a patch, copy the diff block (fenced with four tildes) into a file and run `git apply --index <file>` from the repository root; then run the task's commands. `corpus.lock` and the golden files are left out of the patches: the task's commands regenerate them.

---

### Task 2: Transport types in the core (additive)

**Files:** create `lib/src/transport/{cancel_signal,transport_exception,client_transport,transport_request,transport_response}.dart` and tests `test/transport/{cancel_signal_test,transport_request_test}.dart` in `packages/typed_openapi_client`; export the five files from `lib/typed_openapi_client.dart`; add the seven names of decision 11 to `DartNames.takenTypeNames` (`packages/typed_openapi/lib/src/ir/names.dart`, keep `Dio` and `DioRequestSender` until task 6).

- [ ] **Step 1: Write the tests** (in the patch: a new signal is not cancelled; cancel completes `whenCancelled` and keeps the first reason; a second cancel does nothing; `contentLength` reads the `content-length` header in any case, `null` without it; `TransportException` prints its kind and message).
- [ ] **Step 2: Run them**: `cd packages/typed_openapi_client && dart test test/transport` fails (the files do not exist).
- [ ] **Step 3: Apply the patch** below.
- [ ] **Step 4: Verify**: client `+292` (Chrome dart2js and dart2wasm `+285`), generator `+1376 ~1` (`runtime_names_test` passes with the new names), tool `+198`; analyze clean; format 0 changes.
- [ ] **Step 5: Commit** `feat(typed_openapi_client): transport types`.

~~~~diff
diff --git a/packages/typed_openapi/lib/src/ir/names.dart b/packages/typed_openapi/lib/src/ir/names.dart
index 37748b1..03c01d8 100644
--- a/packages/typed_openapi/lib/src/ir/names.dart
+++ b/packages/typed_openapi/lib/src/ir/names.dart
@@ -68,7 +68,8 @@ final class DartNames {
     'UnimplementedError', 'UnsupportedError', 'Uri', 'WeakReference', 'bool',
     'double', 'int', 'num', 'Uint8List',
     // typed_openapi_client
-    'CallOptions', 'Cancelled', 'CookieParameter', 'Date', 'DecodeError',
+    'CallOptions', 'CancelSignal', 'Cancelled', 'ClientSender',
+    'ClientTransport', 'CookieParameter', 'Date', 'DecodeError',
     'DeepEquality',
     'DioRequestSender', 'Failure', 'FileUpload', 'FormBody', 'FormEncoding',
     'HeaderParameter', 'HttpError',
@@ -81,7 +82,9 @@ final class DartNames {
     'SseDisconnected', 'SseEvent', 'SseEventIgnored', 'SseItem',
     'SseItemDecoder', 'SseMessage', 'SseOptions', 'SseReconnecting',
     'SseReconnection', 'SseReconnector', 'SseResume',
-    'Success', 'TransportError', 'UndocumentedStatus',
+    'Success', 'TransportError', 'TransportException',
+    'TransportExceptionKind', 'TransportRequest', 'TransportResponse',
+    'UndocumentedStatus',
     // package:dio, which the API files import with `show Dio` only.
     'Dio',
   };
diff --git a/packages/typed_openapi_client/lib/src/transport/cancel_signal.dart b/packages/typed_openapi_client/lib/src/transport/cancel_signal.dart
new file mode 100644
index 0000000..16c1584
--- /dev/null
+++ b/packages/typed_openapi_client/lib/src/transport/cancel_signal.dart
@@ -0,0 +1,36 @@
+import 'dart:async';
+
+/// The cancellation of a call: the caller calls [cancel], and the sender
+/// and the transport listen to [whenCancelled].
+///
+/// One signal may serve several calls; a cancelled signal stays cancelled,
+/// so a call made with it afterwards is cancelled before it is sent.
+final class CancelSignal {
+  /// Creates a signal that is not cancelled.
+  CancelSignal();
+
+  final Completer<void> _cancelled = Completer<void>();
+  Object? _reason;
+
+  /// Whether [cancel] was called.
+  bool get isCancelled => _cancelled.isCompleted;
+
+  /// What the first [cancel] was given; null before it, or when it was
+  /// given nothing.
+  Object? get reason => _reason;
+
+  /// Completes when [cancel] is first called.
+  Future<void> get whenCancelled => _cancelled.future;
+
+  /// Cancels the calls that use this signal, for [reason]; a later call
+  /// does nothing.
+  void cancel([Object? reason]) {
+    if (isCancelled) return;
+    _reason = reason;
+    _cancelled.complete();
+  }
+
+  @override
+  String toString() =>
+      isCancelled ? 'CancelSignal(cancelled: $_reason)' : 'CancelSignal()';
+}
diff --git a/packages/typed_openapi_client/lib/src/transport/client_transport.dart b/packages/typed_openapi_client/lib/src/transport/client_transport.dart
new file mode 100644
index 0000000..23d2bbf
--- /dev/null
+++ b/packages/typed_openapi_client/lib/src/transport/client_transport.dart
@@ -0,0 +1,22 @@
+import 'transport_request.dart';
+import 'transport_response.dart';
+
+/// Sends finished HTTP requests: the one thing a generated client needs
+/// from an HTTP stack.
+///
+/// The client core builds the request (URL, headers, body bytes), reads the
+/// response and maps it to a `Result`, so every transport behaves the same
+/// on the wire. A transport owns what its HTTP stack owns: the base URL it
+/// resolves [TransportRequest.target] against, timeouts, retries, redirects,
+/// proxies, certificates, cookies and authorization. `typed_openapi_dio`
+/// is the transport over a `Dio`.
+abstract interface class ClientTransport {
+  /// Sends [request] and completes with the response of any status once its
+  /// headers arrived; the body is read from [TransportResponse.body].
+  ///
+  /// A request that gets no response, or whose body fails while it is read,
+  /// fails with a `TransportException`, of kind `cancelled` when
+  /// [TransportRequest.cancel] was cancelled; nothing else is thrown for a
+  /// failed request.
+  Future<TransportResponse> send(TransportRequest request);
+}
diff --git a/packages/typed_openapi_client/lib/src/transport/transport_exception.dart b/packages/typed_openapi_client/lib/src/transport/transport_exception.dart
new file mode 100644
index 0000000..d9ecfa1
--- /dev/null
+++ b/packages/typed_openapi_client/lib/src/transport/transport_exception.dart
@@ -0,0 +1,47 @@
+/// What kind of failure a [TransportException] reports.
+enum TransportExceptionKind {
+  /// A connect, send or receive timeout of the transport.
+  timeout,
+
+  /// The connection could not be made or broke: refused, reset, closed
+  /// early, a certificate the transport rejected.
+  connection,
+
+  /// The call's `CancelSignal` was cancelled.
+  cancelled,
+
+  /// Any other failure the transport reports.
+  other,
+}
+
+/// A request that got no complete response: what a `ClientTransport`
+/// throws, and what `TransportError` and `Cancelled` carry.
+///
+/// A transport maps its own failures to this type and throws nothing else
+/// for a failed request. [cause] is the transport's own exception (a
+/// `DioException` for `typed_openapi_dio`); code that needs its details
+/// casts it.
+final class TransportException implements Exception {
+  /// Creates the exception of a failure of [kind].
+  const TransportException(
+    this.kind,
+    this.message, {
+    this.cause,
+    this.stackTrace,
+  });
+
+  /// What kind of failure it is.
+  final TransportExceptionKind kind;
+
+  /// A description for people.
+  final String message;
+
+  /// The transport's own exception, or null.
+  final Object? cause;
+
+  /// Where [cause] was raised, or null.
+  final StackTrace? stackTrace;
+
+  @override
+  String toString() => 'TransportException(${kind.name}): $message';
+}
diff --git a/packages/typed_openapi_client/lib/src/transport/transport_request.dart b/packages/typed_openapi_client/lib/src/transport/transport_request.dart
new file mode 100644
index 0000000..9635cb4
--- /dev/null
+++ b/packages/typed_openapi_client/lib/src/transport/transport_request.dart
@@ -0,0 +1,60 @@
+import '../request/operation_info.dart';
+import 'cancel_signal.dart';
+
+/// A finished HTTP request, built by the client core for a
+/// `ClientTransport`.
+final class TransportRequest {
+  /// Creates a request of [operation].
+  const TransportRequest({
+    required this.method,
+    required this.target,
+    required this.operation,
+    this.headers = const {},
+    this.body,
+    this.cancel,
+    this.extra = const {},
+    this.isEventStream = false,
+  });
+
+  /// The HTTP method in upper case.
+  final String method;
+
+  /// The path with the encoded query, such as `/pets/7?fields=a,b`, exactly
+  /// as the core built it; the transport resolves it against its own base
+  /// URL.
+  final String target;
+
+  /// The operation of the spec this request calls, for the transport's
+  /// interceptors and logs (its tags and security metadata).
+  final OperationInfo operation;
+
+  /// The headers to send, in order: a name maps to its values, each sent as
+  /// given. `Content-Length` is here when the length of [body] is known.
+  final Map<String, List<String>> headers;
+
+  /// The body, read once; null for none.
+  final Stream<List<int>>? body;
+
+  /// Cancels the request; null when the call cannot be cancelled.
+  final CancelSignal? cancel;
+
+  /// Data of the call for the transport (`CallOptions.extra`).
+  final Map<String, Object?> extra;
+
+  /// Whether the response is an event stream, read as it arrives: a
+  /// transport that buffers whole responses cannot serve it.
+  final bool isEventStream;
+
+  /// The value of `Content-Length` in [headers], or null.
+  int? get contentLength {
+    for (final MapEntry(:key, :value) in headers.entries) {
+      if (key.toLowerCase() == 'content-length' && value.isNotEmpty) {
+        return int.tryParse(value.first);
+      }
+    }
+    return null;
+  }
+
+  @override
+  String toString() => '$method $target';
+}
diff --git a/packages/typed_openapi_client/lib/src/transport/transport_response.dart b/packages/typed_openapi_client/lib/src/transport/transport_response.dart
new file mode 100644
index 0000000..c65d209
--- /dev/null
+++ b/packages/typed_openapi_client/lib/src/transport/transport_response.dart
@@ -0,0 +1,22 @@
+/// The raw answer of a `ClientTransport`, of any status.
+final class TransportResponse {
+  /// Creates a response.
+  const TransportResponse({
+    required this.statusCode,
+    required this.body,
+    this.headers = const {},
+  });
+
+  /// The HTTP status code.
+  final int statusCode;
+
+  /// The response headers, names in lower case; a name maps to its values.
+  final Map<String, List<String>> headers;
+
+  /// The body, read once. A failure while it is read is a
+  /// `TransportException` error of the stream.
+  final Stream<List<int>> body;
+
+  @override
+  String toString() => 'TransportResponse($statusCode)';
+}
diff --git a/packages/typed_openapi_client/lib/typed_openapi_client.dart b/packages/typed_openapi_client/lib/typed_openapi_client.dart
index 5392fd5..694e904 100644
--- a/packages/typed_openapi_client/lib/typed_openapi_client.dart
+++ b/packages/typed_openapi_client/lib/typed_openapi_client.dart
@@ -45,3 +45,9 @@ export 'src/sse/sse_item_decoder.dart' show SseItemDecoder;
 export 'src/sse/sse_message.dart' show SseMessage;
 export 'src/sse/sse_options.dart' show SseOptions, SseReconnection;
 export 'src/sse/sse_reconnector.dart' show SseReconnector, SseResume;
+export 'src/transport/cancel_signal.dart' show CancelSignal;
+export 'src/transport/client_transport.dart' show ClientTransport;
+export 'src/transport/transport_exception.dart'
+    show TransportException, TransportExceptionKind;
+export 'src/transport/transport_request.dart' show TransportRequest;
+export 'src/transport/transport_response.dart' show TransportResponse;
diff --git a/packages/typed_openapi_client/test/transport/cancel_signal_test.dart b/packages/typed_openapi_client/test/transport/cancel_signal_test.dart
new file mode 100644
index 0000000..02afc78
--- /dev/null
+++ b/packages/typed_openapi_client/test/transport/cancel_signal_test.dart
@@ -0,0 +1,31 @@
+import 'package:test/test.dart';
+import 'package:typed_openapi_client/typed_openapi_client.dart';
+
+void main() {
+  test('a new signal is not cancelled and has no reason', () {
+    final signal = CancelSignal();
+    expect(signal.isCancelled, isFalse);
+    expect(signal.reason, isNull);
+  });
+
+  test('cancel completes whenCancelled and keeps the first reason', () async {
+    final signal = CancelSignal();
+    var completed = false;
+    signal.whenCancelled.then((_) => completed = true);
+    signal
+      ..cancel('first')
+      ..cancel('second');
+    await Future<void>.delayed(Duration.zero);
+    expect(completed, isTrue);
+    expect(signal.isCancelled, isTrue);
+    expect(signal.reason, 'first');
+  });
+
+  test('a TransportException names its kind', () {
+    const exception = TransportException(
+      TransportExceptionKind.timeout,
+      'no answer in 1 s',
+    );
+    expect('$exception', 'TransportException(timeout): no answer in 1 s');
+  });
+}
diff --git a/packages/typed_openapi_client/test/transport/transport_request_test.dart b/packages/typed_openapi_client/test/transport/transport_request_test.dart
new file mode 100644
index 0000000..81bac79
--- /dev/null
+++ b/packages/typed_openapi_client/test/transport/transport_request_test.dart
@@ -0,0 +1,32 @@
+import 'package:test/test.dart';
+import 'package:typed_openapi_client/typed_openapi_client.dart';
+
+void main() {
+  const operation = OperationInfo(
+    operationId: 'upload',
+    method: 'PUT',
+    pathTemplate: '/files',
+  );
+
+  test('contentLength reads Content-Length in any case', () {
+    const request = TransportRequest(
+      method: 'PUT',
+      target: '/files',
+      operation: operation,
+      headers: {
+        'content-length': ['12'],
+      },
+    );
+    expect(request.contentLength, 12);
+  });
+
+  test('contentLength is null without Content-Length', () {
+    const request = TransportRequest(
+      method: 'PUT',
+      target: '/files?a=1',
+      operation: operation,
+    );
+    expect(request.contentLength, isNull);
+    expect('$request', 'PUT /files?a=1');
+  });
+}
~~~~

### Task 3: Core body encoding

**Files:** create `lib/src/request/{parsed_media_type,encoded_body,multipart_encoder,body_encoder}.dart` and their tests in `packages/typed_openapi_client`. Nothing uses them yet; `DioBody` and `MultipartForm` stay until task 4.

Rules (ported from `DioBody`, `MultipartForm` and Dio 5.11.1's `FormData`, decision 4): JSON media types (`MediaTypeText.isJson`) are `jsonEncode(body)` as UTF-8, `null` included; a `FormBody` is form text, `application/x-www-form-urlencoded`; a `MultipartBody` goes through `MultipartEncoder`; a `FileUpload` is its bytes or stream with its own length, its media type validated (`FormatException`); a `Uint8List` is raw; a `String` with a non-JSON type is UTF-8; `null` with a non-JSON type is no body. The `ArgumentError`s of `MultipartForm` stay word for word.

Proof of the wire (run during the replay, not committed): a scratch test encoded the M9 multipart cases with `MultipartEncoder` and with Dio's `FormData` (same boundary) and compared the bytes: equal in every case except a file with a file name and no media type (open question 1). The committed tests hold the expected bytes literally.

- [ ] **Step 1: Write the tests** (in the patch), run them, see them fail.
- [ ] **Step 2: Apply the patch** below.
- [ ] **Step 3: Verify**: client `+316` (Chrome dart2js and dart2wasm `+309`); generator and tool unchanged.
- [ ] **Step 4: Commit** `feat(typed_openapi_client): encode request bodies in the core`.

~~~~diff
diff --git a/packages/typed_openapi_client/lib/src/request/body_encoder.dart b/packages/typed_openapi_client/lib/src/request/body_encoder.dart
new file mode 100644
index 0000000..90959fc
--- /dev/null
+++ b/packages/typed_openapi_client/lib/src/request/body_encoder.dart
@@ -0,0 +1,82 @@
+import 'dart:convert';
+import 'dart:typed_data';
+
+import 'encoded_body.dart';
+import 'file_upload.dart';
+import 'form_body.dart';
+import 'media_type_text.dart';
+import 'multipart_body.dart';
+import 'multipart_encoder.dart';
+import 'operation_request.dart';
+import 'parsed_media_type.dart';
+
+/// Turns the body of an [OperationRequest] into the bytes every transport
+/// sends: form text, `multipart/form-data`, the bytes or the stream of a
+/// file, JSON text, or text.
+final class BodyEncoder {
+  /// Creates the encoder; [boundary] gives the boundary of each multipart
+  /// body.
+  const BodyEncoder(this.boundary);
+
+  /// Makes the boundary of a multipart body.
+  final String Function() boundary;
+
+  /// The encoded body of [request], or null when nothing is sent.
+  ///
+  /// - A [FormBody] is its text, a [MultipartBody] its parts, a
+  ///   [FileUpload] its bytes or its stream, with the file's own media type
+  ///   when it has one (a value that is not a media type throws
+  ///   [FormatException]).
+  /// - With a JSON `Content-Type` (`application/json`, `text/json` or a
+  ///   `+json` type) any value is JSON text: a string is quoted, and `null`
+  ///   is the JSON value `null` of a required nullable body.
+  /// - Without one, `null` sends nothing, [Uint8List] is sent as it is and
+  ///   any other value as its text in UTF-8.
+  EncodedBody? encode(OperationRequest request) {
+    final contentType = request.contentType;
+    final isJson = contentType != null && MediaTypeText(contentType).isJson;
+    return switch (request.body) {
+      final FormBody form => EncodedBody.bytes(
+        utf8.encode(form.encode()),
+        contentType: contentType,
+      ),
+      final MultipartBody multipart => MultipartEncoder(
+        boundary(),
+      ).encode(multipart),
+      final FileUpload file => _file(file, contentType),
+      final body when isJson => EncodedBody.bytes(
+        utf8.encode(jsonEncode(body)),
+        contentType: contentType,
+      ),
+      null => null,
+      final Uint8List bytes => EncodedBody.bytes(
+        bytes,
+        contentType: contentType,
+      ),
+      final body => EncodedBody.bytes(
+        utf8.encode('$body'),
+        contentType: contentType,
+      ),
+    };
+  }
+
+  /// A file body: the file's own media type wins over the spec's, and is
+  /// sent as written once it reads as a media type.
+  static EncodedBody _file(FileUpload file, String? specType) {
+    final type = file.contentType;
+    if (type != null) ParsedMediaType.parse(type);
+    final contentType = type ?? specType;
+    return switch (file) {
+      FileUpload(:final bytes?) => EncodedBody.bytes(
+        bytes,
+        contentType: contentType,
+      ),
+      FileUpload(:final stream?) => EncodedBody.stream(
+        stream,
+        length: file.length,
+        contentType: contentType,
+      ),
+      _ => EncodedBody.bytes(Uint8List(0), contentType: contentType),
+    };
+  }
+}
diff --git a/packages/typed_openapi_client/lib/src/request/encoded_body.dart b/packages/typed_openapi_client/lib/src/request/encoded_body.dart
new file mode 100644
index 0000000..3194ec1
--- /dev/null
+++ b/packages/typed_openapi_client/lib/src/request/encoded_body.dart
@@ -0,0 +1,43 @@
+import 'dart:typed_data';
+
+/// The bytes of a request body, its length and its `Content-Type`.
+final class EncodedBody {
+  /// A body held in memory.
+  EncodedBody.bytes(Uint8List this._bytes, {this.contentType})
+    : _stream = null,
+      length = _bytes.length;
+
+  /// A body read from [stream], which has [length] bytes.
+  const EncodedBody.stream(
+    Stream<List<int>> this._stream, {
+    required this.length,
+    this.contentType,
+  }) : _bytes = null;
+
+  /// The size of the body in bytes.
+  final int length;
+
+  /// The `Content-Type` to send, or null for none.
+  final String? contentType;
+
+  final Uint8List? _bytes;
+  final Stream<List<int>>? _stream;
+
+  /// Bytes held in memory are sent in chunks of this size, as Dio sent
+  /// them, so send progress moves in steps.
+  static const int chunkSize = 1024;
+
+  /// The body as it is sent; a body read from a stream can be read once.
+  Stream<List<int>> read() => switch ((_stream, _bytes)) {
+    (final stream?, _) => stream,
+    (_, final bytes?) => Stream.fromIterable([
+      for (var start = 0; start < bytes.length; start += chunkSize)
+        Uint8List.sublistView(
+          bytes,
+          start,
+          start + chunkSize < bytes.length ? start + chunkSize : bytes.length,
+        ),
+    ]),
+    _ => const Stream.empty(),
+  };
+}
diff --git a/packages/typed_openapi_client/lib/src/request/multipart_encoder.dart b/packages/typed_openapi_client/lib/src/request/multipart_encoder.dart
new file mode 100644
index 0000000..7cef345
--- /dev/null
+++ b/packages/typed_openapi_client/lib/src/request/multipart_encoder.dart
@@ -0,0 +1,206 @@
+import 'dart:convert';
+import 'dart:typed_data';
+
+import 'encoded_body.dart';
+import 'file_upload.dart';
+import 'media_type_text.dart';
+import 'multipart_body.dart';
+import 'parsed_media_type.dart';
+
+/// One part on the wire: its header lines, its content (bytes or a file)
+/// and whether it is a plain field, without a `Content-Type`.
+typedef _WirePart = ({
+  String head,
+  Uint8List? bytes,
+  FileUpload? file,
+  bool isField,
+});
+
+/// Writes a [MultipartBody] as `multipart/form-data` bytes, in the order of
+/// its parts, byte for byte as Dio's `FormData` wrote it.
+///
+/// A plain text part (a value without a media type) has no `Content-Type`
+/// while no file or typed part precedes it, the usual shape (values first,
+/// files last). After the first file or typed part, text parts are sent as
+/// `text/plain; charset=utf-8` parts. A file part without a media type of
+/// its own or of the spec is `application/octet-stream`.
+final class MultipartEncoder {
+  /// Creates the encoder of one request, whose parts are separated by
+  /// [boundary].
+  const MultipartEncoder(this.boundary);
+
+  /// The boundary between the parts.
+  final String boundary;
+
+  /// The `Content-Type` of the body.
+  String get contentType => 'multipart/form-data; boundary=$boundary';
+
+  /// The bytes of [body].
+  ///
+  /// Throws [ArgumentError] for a value that cannot be a part (not a finite
+  /// JSON scalar, a list inside a list, a non-JSON value in a JSON part, an
+  /// object with a media type that is not JSON) and [FormatException] for a
+  /// media type that is not one.
+  EncodedBody encode(MultipartBody body) {
+    final parts = <_WirePart>[];
+    for (final part in body.parts) {
+      switch (part.file) {
+        case final file?:
+          parts.add(_file(part.name, file, part.contentType));
+        case null:
+          _addValue(parts, part.name, part.value, part.contentType);
+      }
+    }
+    var length = utf8.encode('--$boundary--\r\n').length;
+    for (final part in parts) {
+      length +=
+          utf8.encode('--$boundary\r\n${part.head}').length +
+          (part.bytes?.length ?? part.file?.length ?? 0) +
+          2;
+    }
+    return EncodedBody.stream(
+      _write(parts),
+      length: length,
+      contentType: contentType,
+    );
+  }
+
+  Stream<List<int>> _write(List<_WirePart> parts) async* {
+    for (final part in parts) {
+      yield utf8.encode('--$boundary\r\n${part.head}');
+      if (part.bytes ?? part.file?.bytes case final bytes?) {
+        yield bytes;
+      } else if (part.file?.stream case final stream?) {
+        yield* stream;
+      }
+      yield const [13, 10];
+    }
+    yield utf8.encode('--$boundary--\r\n');
+  }
+
+  /// A file part: the file's own media type wins over the spec's.
+  static _WirePart _file(String name, FileUpload file, String? specType) {
+    final type = file.contentType ?? specType;
+    final contentType = type == null
+        ? 'application/octet-stream'
+        : '${ParsedMediaType.parse(type)}';
+    final filename = switch (file.filename) {
+      final filename? => '; filename="${_escape(filename)}"',
+      null => '',
+    };
+    return (
+      head:
+          'content-disposition: form-data; name="${_escape(name)}"$filename'
+          '\r\ncontent-type: $contentType\r\n\r\n',
+      bytes: null,
+      file: file,
+      isField: false,
+    );
+  }
+
+  /// Adds the parts of [value]: none for `null`, a part per item of a list,
+  /// JSON for an object or a JSON [contentType], text otherwise.
+  static void _addValue(
+    List<_WirePart> parts,
+    String name,
+    Object? value,
+    String? contentType,
+  ) {
+    switch (value) {
+      case null:
+        return;
+      case final List<Object?> items:
+        for (final item in items) {
+          if (item is List<Object?>) {
+            throw _notAPart(name, item, 'a nested list');
+          }
+          _addValue(parts, name, item, contentType);
+        }
+      case _ when contentType != null && MediaTypeText(contentType).isJson:
+        parts.add(_text(name, _json(name, value), contentType));
+      case Map<Object?, Object?>() when contentType != null:
+        throw ArgumentError.value(
+          value,
+          name,
+          'An object part cannot be sent as "$contentType": only JSON '
+          'media types carry an object',
+        );
+      case Map<Object?, Object?>():
+        parts.add(_text(name, _json(name, value), 'application/json'));
+      default:
+        parts.add(_scalar(parts, name, _scalarText(name, value), contentType));
+    }
+  }
+
+  /// A scalar part: a plain field while only plain fields precede it.
+  static _WirePart _scalar(
+    List<_WirePart> parts,
+    String name,
+    String text,
+    String? contentType,
+  ) {
+    if (contentType != null) return _text(name, text, contentType);
+    if (parts.any((part) => !part.isField)) {
+      return _text(name, text, 'text/plain');
+    }
+    return (
+      head: 'content-disposition: form-data; name="${_escape(name)}"\r\n\r\n',
+      bytes: utf8.encode(text),
+      file: null,
+      isField: true,
+    );
+  }
+
+  /// A text part in the charset of [contentType] (UTF-8 when it names none
+  /// or one that is unknown), which then names that charset.
+  static _WirePart _text(String name, String text, String contentType) {
+    final type = ParsedMediaType.parse(contentType);
+    final encoding =
+        Encoding.getByName(type.parameter('charset') ?? 'utf-8') ?? utf8;
+    final named = type.withParameter('charset', encoding.name);
+    return (
+      head:
+          'content-disposition: form-data; name="${_escape(name)}"'
+          '\r\ncontent-type: $named\r\n\r\n',
+      bytes: Uint8List.fromList(encoding.encode(text)),
+      file: null,
+      isField: false,
+    );
+  }
+
+  /// [value] as Dio wrote it into a header: line breaks and quotes cannot
+  /// end the header line or the quoted name.
+  static String _escape(String value) =>
+      value.replaceAll(RegExp('\r\n|\r|\n'), '%0D%0A').replaceAll('"', '%22');
+
+  /// The text of a scalar JSON value of a part.
+  static String _scalarText(String name, Object? value) => switch (value) {
+    final String text => text,
+    final bool flag => '$flag',
+    final num number when number.isFinite => '$number',
+    _ => throw _notAPart(name, value, 'not a finite JSON scalar'),
+  };
+
+  /// The JSON text of [value], which must be made of JSON values only.
+  static String _json(String name, Object? value) {
+    if (!_isJson(value)) throw _notAPart(name, value, 'not JSON');
+    return jsonEncode(value);
+  }
+
+  static bool _isJson(Object? value) => switch (value) {
+    null || String() || bool() => true,
+    final num number => number.isFinite,
+    final List<Object?> items => items.every(_isJson),
+    final Map<Object?, Object?> map =>
+      map.keys.every((key) => key is String) && map.values.every(_isJson),
+    _ => false,
+  };
+
+  static ArgumentError _notAPart(String name, Object? value, String why) =>
+      ArgumentError.value(
+        value,
+        name,
+        'Cannot be sent as a multipart part ($why); convert values with '
+        'toJson',
+      );
+}
diff --git a/packages/typed_openapi_client/lib/src/request/parsed_media_type.dart b/packages/typed_openapi_client/lib/src/request/parsed_media_type.dart
new file mode 100644
index 0000000..c8f7640
--- /dev/null
+++ b/packages/typed_openapi_client/lib/src/request/parsed_media_type.dart
@@ -0,0 +1,123 @@
+/// A media type read by the rules of RFC 9110 (a type, a subtype and
+/// parameters), written back in one canonical form.
+///
+/// It reads and writes media types exactly as `package:http_parser` does
+/// (which Dio used), so a part's `Content-Type` keeps its bytes: the type
+/// and subtype in lower case, parameters in order with their names as
+/// given, a value quoted only when it is not a token.
+final class ParsedMediaType {
+  const ParsedMediaType._(this.type, this.subtype, this._parameters);
+
+  /// Reads [text]; throws [FormatException] when it is not a media type.
+  factory ParsedMediaType.parse(String text) {
+    final reader = _Reader(text)..skip(_whitespace);
+    final type = reader.expect(_token, 'a type');
+    reader.expect(RegExp('/'), '"/"');
+    final subtype = reader.expect(_token, 'a subtype');
+    reader.skip(_whitespace);
+    final parameters = <String, (String, String)>{};
+    while (reader.skip(RegExp(';'))) {
+      reader.skip(_whitespace);
+      final name = reader.expect(_token, 'a parameter name');
+      reader.expect(RegExp('='), '"="');
+      final value = reader.skip(_token)
+          ? reader.last
+          : _unquote(reader.expect(_quoted, 'a quoted string'));
+      reader.skip(_whitespace);
+      parameters[name.toLowerCase()] = (name, value);
+    }
+    reader.done();
+    return ParsedMediaType._(
+      type.toLowerCase(),
+      subtype.toLowerCase(),
+      parameters,
+    );
+  }
+
+  /// The type in lower case, such as `text`.
+  final String type;
+
+  /// The subtype in lower case, such as `plain`.
+  final String subtype;
+
+  /// Parameters by lower-case name: the name as written and the value.
+  final Map<String, (String, String)> _parameters;
+
+  /// The value of the parameter [name] (in any case), or null.
+  String? parameter(String name) => _parameters[name.toLowerCase()]?.$2;
+
+  /// This media type with the parameter [name] set to [value]: it keeps the
+  /// place of a parameter of that name and takes the new spelling.
+  ParsedMediaType withParameter(String name, String value) =>
+      ParsedMediaType._(type, subtype, {
+        ..._parameters,
+        name.toLowerCase(): (name, value),
+      });
+
+  @override
+  String toString() {
+    final text = StringBuffer('$type/$subtype');
+    for (final (name, value) in _parameters.values) {
+      text.write('; $name=');
+      if (_nonToken.hasMatch(value)) {
+        final escaped = value.replaceAllMapped(_escaped, (m) => '\\${m[0]}');
+        text.write('"$escaped"');
+      } else {
+        text.write(value);
+      }
+    }
+    return '$text';
+  }
+
+  static String _unquote(String quoted) => quoted
+      .substring(1, quoted.length - 1)
+      .replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1]!);
+
+  static final RegExp _token = RegExp(
+    r'[^()<>@,;:"\\/[\]?={} \t\x00-\x1F\x7F]+',
+  );
+  static final RegExp _nonToken = RegExp(
+    r'[()<>@,;:"\\/\[\]?={} \t\x00-\x1F\x7F]',
+  );
+  static final RegExp _whitespace = RegExp(r'(?:(?:\r\n)?[ \t]+)*');
+  static final RegExp _quoted = RegExp(r'"(?:[^"\x00-\x1F\x7F\\]|\\.)*"');
+  static final RegExp _escaped = RegExp(r'["\x00-\x1F\x7F]');
+}
+
+/// Reads a string from left to right with patterns.
+final class _Reader {
+  _Reader(this._text);
+
+  final String _text;
+  int _position = 0;
+  String _last = '';
+
+  /// The text the last successful match read.
+  String get last => _last;
+
+  /// Reads [pattern] at the position; whether it matched.
+  bool skip(RegExp pattern) {
+    final match = pattern.matchAsPrefix(_text, _position);
+    if (match == null) return false;
+    _last = match[0]!;
+    _position = match.end;
+    return true;
+  }
+
+  /// Reads [pattern], or throws [FormatException] naming [what].
+  String expect(RegExp pattern, String what) {
+    if (!skip(pattern)) throw _error('expected $what');
+    return _last;
+  }
+
+  /// Throws [FormatException] when text is left.
+  void done() {
+    if (_position < _text.length) throw _error('expected no more input');
+  }
+
+  FormatException _error(String message) => FormatException(
+    'Invalid media type "$_text": $message',
+    _text,
+    _position,
+  );
+}
diff --git a/packages/typed_openapi_client/test/request/body_encoder_test.dart b/packages/typed_openapi_client/test/request/body_encoder_test.dart
new file mode 100644
index 0000000..080a1d4
--- /dev/null
+++ b/packages/typed_openapi_client/test/request/body_encoder_test.dart
@@ -0,0 +1,126 @@
+import 'dart:convert';
+import 'dart:typed_data';
+
+import 'package:test/test.dart';
+import 'package:typed_openapi_client/src/request/body_encoder.dart';
+import 'package:typed_openapi_client/typed_openapi_client.dart';
+
+const _upload = OperationInfo(
+  operationId: 'upload',
+  method: 'POST',
+  pathTemplate: '/files',
+);
+
+/// The encoded body of [body] sent as [contentType]: its media type and
+/// text, or null when nothing is sent.
+Future<(String?, String)?> encode(Object? body, String? contentType) async {
+  final encoded = BodyEncoder(() => 'b').encode(
+    OperationRequest(_upload, body: body, contentType: contentType),
+  );
+  if (encoded == null) return null;
+  final bytes = await encoded.read().expand((chunk) => chunk).toList();
+  expect(encoded.length, bytes.length);
+  return (encoded.contentType, utf8.decode(bytes));
+}
+
+void main() {
+  group('a JSON content type makes any value JSON text', () {
+    for (final (value, text) in [
+      ({'a': 1}, '{"a":1}'),
+      ([1, 'x'], '[1,"x"]'),
+      ('a"b', r'"a\"b"'),
+      (3, '3'),
+      (true, 'true'),
+      (null, 'null'),
+      ('é', '"é"'),
+    ]) {
+      test('$value', () async {
+        expect(await encode(value, 'application/json'), (
+          'application/json',
+          text,
+        ));
+      });
+    }
+
+    test('text/json and +json types too', () async {
+      expect(await encode('s', 'text/json'), ('text/json', '"s"'));
+      expect(await encode('s', 'application/problem+json'), (
+        'application/problem+json',
+        '"s"',
+      ));
+    });
+  });
+
+  test('text is sent as it is, in UTF-8', () async {
+    expect(await encode('plain "t" é', 'text/plain'), (
+      'text/plain',
+      'plain "t" é',
+    ));
+  });
+
+  test('no body and a content type that is not JSON sends nothing', () async {
+    expect(await encode(null, 'text/plain'), isNull);
+    expect(await encode(null, null), isNull);
+  });
+
+  test('a form body is its text with its content type', () async {
+    expect(
+      await encode(
+        const FormBody({'name': 'a b', 'n': 1}),
+        'application/x-www-form-urlencoded',
+      ),
+      ('application/x-www-form-urlencoded', 'name=a%20b&n=1'),
+    );
+  });
+
+  test('a multipart body names its boundary', () async {
+    expect(
+      await encode(
+        const MultipartBody([MultipartPart.value('a', 'b')]),
+        'multipart/form-data',
+      ),
+      (
+        'multipart/form-data; boundary=b',
+        '--b\r\ncontent-disposition: form-data; name="a"\r\n\r\nb\r\n--b--\r\n',
+      ),
+    );
+  });
+
+  test('a file body has its own media type, else the spec\'s', () async {
+    final png = Uint8List.fromList(utf8.encode('png'));
+    expect(await encode(FileUpload.bytes(png), 'application/octet-stream'), (
+      'application/octet-stream',
+      'png',
+    ));
+    expect(
+      await encode(
+        FileUpload.stream(
+          Stream.value(utf8.encode('gif')),
+          length: 3,
+          contentType: 'image/GIF',
+        ),
+        'application/octet-stream',
+      ),
+      ('image/GIF', 'gif'),
+    );
+    expect(
+      () => encode(FileUpload.bytes(png, contentType: 'png'), null),
+      throwsFormatException,
+    );
+  });
+
+  test('bytes held in memory are read in chunks of 1024 bytes', () async {
+    final encoded = BodyEncoder(() => 'b').encode(
+      OperationRequest(
+        _upload,
+        body: FileUpload.bytes(Uint8List(2500)),
+        contentType: 'application/octet-stream',
+      ),
+    );
+    expect(await encoded!.read().map((c) => c.length).toList(), [
+      1024,
+      1024,
+      452,
+    ]);
+  });
+}
diff --git a/packages/typed_openapi_client/test/request/multipart_encoder_test.dart b/packages/typed_openapi_client/test/request/multipart_encoder_test.dart
new file mode 100644
index 0000000..f592c31
--- /dev/null
+++ b/packages/typed_openapi_client/test/request/multipart_encoder_test.dart
@@ -0,0 +1,171 @@
+import 'dart:convert';
+import 'dart:typed_data';
+
+import 'package:test/test.dart';
+import 'package:typed_openapi_client/src/request/multipart_encoder.dart';
+import 'package:typed_openapi_client/typed_openapi_client.dart';
+
+/// The text [body] encodes to with the boundary `b`, and its length.
+Future<(String, int)> encoded(List<MultipartPart> parts) async {
+  final body = const MultipartEncoder('b').encode(MultipartBody(parts));
+  final bytes = await body.read().expand((chunk) => chunk).toList();
+  expect(body.length, bytes.length, reason: 'the length is the byte count');
+  return (utf8.decode(bytes, allowMalformed: true), body.length);
+}
+
+void main() {
+  test('the content type names the boundary', () {
+    expect(
+      const MultipartEncoder('x-1').contentType,
+      'multipart/form-data; boundary=x-1',
+    );
+  });
+
+  test('values, JSON, lists and files are written as Dio wrote them', () async {
+    final (text, _) = await encoded([
+      const MultipartPart.value('note', 'hi'),
+      const MultipartPart.value('count', 2),
+      const MultipartPart.value('ids', [1, 2]),
+      const MultipartPart.value('gone', null),
+      const MultipartPart.value('meta', {'k': 'v'}),
+      const MultipartPart.value('raw', 'x', contentType: 'text/csv'),
+      const MultipartPart.value('quoted', 'y', contentType: 'application/json'),
+      const MultipartPart.value('late', 'z'),
+      MultipartPart.file(
+        'file',
+        FileUpload.bytes(
+          Uint8List.fromList(utf8.encode('abc')),
+          filename: 'a.txt',
+          contentType: 'TEXT/Plain',
+        ),
+      ),
+      MultipartPart.file(
+        'stream',
+        FileUpload.stream(Stream.value(utf8.encode('de')), length: 2),
+      ),
+      MultipartPart.file(
+        'own',
+        FileUpload.bytes(
+          Uint8List.fromList(utf8.encode('g')),
+          contentType: 'image/gif',
+        ),
+        contentType: 'image/png',
+      ),
+    ]);
+    expect(
+      text,
+      '--b\r\ncontent-disposition: form-data; name="note"\r\n\r\nhi\r\n'
+      '--b\r\ncontent-disposition: form-data; name="count"\r\n\r\n2\r\n'
+      '--b\r\ncontent-disposition: form-data; name="ids"\r\n\r\n1\r\n'
+      '--b\r\ncontent-disposition: form-data; name="ids"\r\n\r\n2\r\n'
+      '--b\r\ncontent-disposition: form-data; name="meta"\r\n'
+      'content-type: application/json; charset=utf-8\r\n\r\n{"k":"v"}\r\n'
+      '--b\r\ncontent-disposition: form-data; name="raw"\r\n'
+      'content-type: text/csv; charset=utf-8\r\n\r\nx\r\n'
+      '--b\r\ncontent-disposition: form-data; name="quoted"\r\n'
+      'content-type: application/json; charset=utf-8\r\n\r\n"y"\r\n'
+      '--b\r\ncontent-disposition: form-data; name="late"\r\n'
+      'content-type: text/plain; charset=utf-8\r\n\r\nz\r\n'
+      '--b\r\ncontent-disposition: form-data; name="file"; '
+      'filename="a.txt"\r\ncontent-type: text/plain\r\n\r\nabc\r\n'
+      '--b\r\ncontent-disposition: form-data; name="stream"\r\n'
+      'content-type: application/octet-stream\r\n\r\nde\r\n'
+      '--b\r\ncontent-disposition: form-data; name="own"\r\n'
+      'content-type: image/gif\r\n\r\ng\r\n'
+      '--b--\r\n',
+    );
+  });
+
+  test(
+    'a charset of the part is kept and used, by its canonical name',
+    () async {
+      final (text, length) = await encoded([
+        const MultipartPart.value(
+          'latin',
+          'é',
+          contentType: 'text/plain; Charset=ISO-8859-1; a="b c"',
+        ),
+      ]);
+      expect(
+        text,
+        isNot(contains('é')),
+        reason: 'é is one byte in ISO-8859-1, not UTF-8',
+      );
+      expect(
+        text,
+        contains('content-type: text/plain; charset=iso-8859-1; a="b c"\r\n'),
+      );
+      expect(length, 118);
+    },
+  );
+
+  test('names and file names never end the header line', () async {
+    final (text, _) = await encoded([
+      MultipartPart.file(
+        'a"b\r\nc',
+        FileUpload.bytes(Uint8List(0), filename: 'x\ny".txt'),
+      ),
+    ]);
+    expect(
+      text,
+      contains(
+        'name="a%22b%0D%0Ac"; filename="x%0D%0Ay%22.txt"\r\n'
+        'content-type: application/octet-stream\r\n',
+      ),
+    );
+  });
+
+  group('a part that cannot be sent throws ArgumentError', () {
+    for (final (name, value) in [
+      ('NaN', double.nan),
+      (
+        'a nested list',
+        [
+          [1],
+        ],
+      ),
+      ('an object that is not JSON', {'k': Object()}),
+      ('a value that is not JSON', Object()),
+    ]) {
+      test(name, () {
+        expect(
+          () => encoded([MultipartPart.value('v', value)]),
+          throwsArgumentError,
+        );
+      });
+    }
+
+    test('a map with a text media type', () {
+      expect(
+        () => encoded([
+          const MultipartPart.value('m', {'k': 1}, contentType: 'text/plain'),
+        ]),
+        throwsA(
+          isA<ArgumentError>().having(
+            (e) => e.message,
+            'message',
+            contains('"text/plain"'),
+          ),
+        ),
+      );
+    });
+  });
+
+  test('a media type that is not one throws FormatException', () {
+    expect(
+      () => encoded([
+        MultipartPart.file(
+          'f',
+          FileUpload.bytes(Uint8List(0), contentType: 'not a type'),
+        ),
+      ]),
+      throwsFormatException,
+    );
+    expect(
+      () => encoded([
+        const MultipartPart.value('v', 'x', contentType: 'text/'),
+      ]),
+      throwsFormatException,
+    );
+  });
+}
~~~~

### Task 4: Transport split (core sender, Dio adapter, generated code)

The three parts below change the core's public API, add the adapter and move the generated code onto it. Between them the generator's `generated_client_test` is red (the generated code names the sender of the part before), so they are one task: apply the three patches in order, run the gate once at the end (Part 4c, Steps 3 to 5), and make one commit, `feat!: send through a ClientTransport` with the body naming the three packages. The part gates below are what each part was checked against in the replay; they are progress checks, not commit points.

#### Part 4a: `ClientSender` replaces `DioRequestSender`

**Files:** create `lib/src/client/` (`client_sender`, `event_opener`, `event_call`, `connection_signals`, `request_builder`, `response_reader`, `progress_counter`, `client_results`, `call_options`); delete `lib/src/dio/`, `test/dio/`, `test/helpers/{fake_adapter,gated_adapter}.dart`; edit `result/result.dart`, `request/operation_info.dart` (drop `of` and the Dio import), `request/raw_response.dart` and `request/operation_request.dart` (doc comments), `sse/sse_reconnector.dart` (decision 10), the barrel, `pubspec.yaml` (drop `dio` and `stream_channel`), `test/quality/size_limits_test.dart` (drop the two entries of deleted files); `test/helpers/{fake_transport,gated_transport,pets_api,watch_stream}.dart`; port `test/dio/*` to `test/client/*`.

Port map: `bodies_send_test`, `json_body_test`, `multipart_send_test`, `accept_test`, `open_events_test` and the sender tests -> `test/client/*` against `FakeTransport` (expected bytes unchanged; the end causes are the kind names `connection` and `cancelled`); the Dio-specific cases (the `//` query guard, Dio unchanged, `onError` first, a resolved response, `validateStatus`, an `Error` in an interceptor, the interceptor's security metadata, the web tests and the cookie test) -> task 5.

New behaviour tests (in the patch): a documented error status is typed; transport failures keep the `TransportException`; an `Exception` while the body is read is a transport failure; invalid JSON is a `DecodeError` with the status and the text.

Defect found and fixed in this task during the replay: the multipart boundary was `Random().nextInt(1 << 32)`, which is `nextInt(0)` in JavaScript (`RangeError` on every multipart call in Chrome); the patch uses the literal `4294967296` with a comment.

- [ ] **Step 1: Apply the patch** below (it deletes `lib/src/dio/` and `test/dio/`).
- [ ] **Step 2: Verify**: client `+305` on the VM, `+289` in Chrome with dart2js and with dart2wasm; analyze clean; `RequestBuilder.build` and `EventOpener._connect` are under 40 lines (`_headers` and `_events` extracted). The generator's `generated_client_test` is red until task 6 (see Global Constraints).
- [ ] **Step 3: No commit yet**: go on with Part 4b.

Delete first:

```sh
git rm -q -r \
  packages/typed_openapi_client/lib/src/dio/connection_tokens.dart \
  packages/typed_openapi_client/lib/src/dio/dio_body.dart \
  packages/typed_openapi_client/lib/src/dio/dio_call.dart \
  packages/typed_openapi_client/lib/src/dio/dio_request_sender.dart \
  packages/typed_openapi_client/lib/src/dio/dio_results.dart \
  packages/typed_openapi_client/lib/src/dio/multipart_form.dart \
  packages/typed_openapi_client/test/dio/cookie_browser_test.dart \
  packages/typed_openapi_client/test/dio/cookie_server.dart \
  packages/typed_openapi_client/test/dio/dio_request_sender_test.dart \
  packages/typed_openapi_client/test/dio/web_test.dart \
  packages/typed_openapi_client/test/helpers/fake_adapter.dart \
  packages/typed_openapi_client/test/helpers/gated_adapter.dart
```

~~~~diff
diff --git a/packages/typed_openapi_client/lib/src/dio/call_options.dart b/packages/typed_openapi_client/lib/src/client/call_options.dart
similarity index 60%
rename from packages/typed_openapi_client/lib/src/dio/call_options.dart
rename to packages/typed_openapi_client/lib/src/client/call_options.dart
index c523f67..9455ffe 100644
--- a/packages/typed_openapi_client/lib/src/dio/call_options.dart
+++ b/packages/typed_openapi_client/lib/src/client/call_options.dart
@@ -1,18 +1,16 @@
-import 'package:dio/dio.dart';
-
 import '../sse/sse_options.dart';
+import '../transport/cancel_signal.dart';
 
 /// Per-call options: the optional `call` parameter of every generated
 /// method.
 ///
 /// One object instead of many named parameters, so that a new option does
 /// not change the signature of generated methods (and of user fakes that
-/// implement them). Base URL, timeouts and retries belong to the user's
-/// Dio and its interceptors.
+/// implement them). Base URL, timeouts and retries belong to the transport.
 final class CallOptions {
   /// Creates per-call options.
   const CallOptions({
-    this.cancelToken,
+    this.cancel,
     this.headers = const {},
     this.extra = const {},
     this.onSendProgress,
@@ -20,12 +18,14 @@ final class CallOptions {
     this.sse,
   });
 
-  /// Cancels the request; the operation then returns `Cancelled`.
-  final CancelToken? cancelToken;
+  /// Cancels the call; the operation then returns `Cancelled`, and an event
+  /// stream ends with `SseDisconnected`.
+  final CancelSignal? cancel;
 
   /// Headers added to the request; they win over the headers the operation
-  /// sends for its header parameters, case-insensitively. The one exception
-  /// is `Content-Type`: the operation's own content type
+  /// sends for its header parameters, case-insensitively. A value that is a
+  /// list is sent as one value per item; a `null` value is not sent. The
+  /// one exception is `Content-Type`: the operation's own content type
   /// (`OperationRequest.contentType`, set for a request body) wins over a
   /// `Content-Type` given here, so it cannot be used to pick another media
   /// type such as `application/merge-patch+json`.
@@ -37,14 +37,16 @@ final class CallOptions {
   /// header value (printable ASCII).
   final Map<String, Object?> headers;
 
-  /// Data for interceptors, merged into `RequestOptions.extra`.
+  /// Data for the transport (`TransportRequest.extra`); `typed_openapi_dio`
+  /// merges it into `RequestOptions.extra` for interceptors.
   final Map<String, Object?> extra;
 
-  /// Reports sent bytes.
-  final ProgressCallback? onSendProgress;
+  /// Reports the bytes of the request body sent so far and its length.
+  final void Function(int count, int total)? onSendProgress;
 
-  /// Reports received bytes.
-  final ProgressCallback? onReceiveProgress;
+  /// Reports the bytes of the response body received so far and its
+  /// `Content-Length`, `-1` without one.
+  final void Function(int count, int total)? onReceiveProgress;
 
   /// How an event stream reconnects; null for the defaults of
   /// [SseOptions]. Other operations ignore it.
diff --git a/packages/typed_openapi_client/lib/src/client/client_results.dart b/packages/typed_openapi_client/lib/src/client/client_results.dart
new file mode 100644
index 0000000..13a4b48
--- /dev/null
+++ b/packages/typed_openapi_client/lib/src/client/client_results.dart
@@ -0,0 +1,92 @@
+import 'dart:convert';
+import 'dart:typed_data';
+
+import '../json/json_decode_exception.dart';
+import '../request/raw_response.dart';
+import '../result/result.dart';
+import '../transport/cancel_signal.dart';
+import '../transport/transport_exception.dart';
+
+/// Turns what a transport gives `ClientSender` (a response, or a
+/// [TransportException]) into a [Result].
+final class ClientResults {
+  /// Creates the mapping.
+  const ClientResults();
+
+  /// [raw] decoded with [decode]; a [JsonDecodeException] or a
+  /// [FormatException] it throws is a [DecodeError].
+  Result<T, E> decode<T, E>(
+    RawResponse raw,
+    Result<T, E> Function(RawResponse response) decode,
+  ) {
+    try {
+      return decode(raw);
+    } on JsonDecodeException catch (e) {
+      return decodeError(e, raw.statusCode, raw.body, raw.headers);
+    } on FormatException catch (e) {
+      // A user converter (R6.8) or `Date.parse` rejecting server data.
+      return decodeError(
+        JsonDecodeException.fromFormatException(e),
+        raw.statusCode,
+        raw.body,
+        raw.headers,
+      );
+    }
+  }
+
+  /// The [DecodeError] of a body that did not read or decode; [body] is
+  /// kept, as text when it is bytes.
+  DecodeError<T, E> decodeError<T, E>(
+    JsonDecodeException error,
+    int statusCode,
+    Object? body,
+    Map<String, List<String>> headers,
+  ) => DecodeError(
+    error,
+    statusCode: statusCode,
+    rawBody: switch (body) {
+      final Uint8List bytes => utf8.decode(bytes, allowMalformed: true),
+      final other => other,
+    },
+    headers: headers,
+  );
+
+  /// The failure of [exception]: [Cancelled] for a cancel, else
+  /// [TransportError].
+  Failure<T, E> failure<T, E>(
+    TransportException exception,
+    StackTrace stackTrace,
+  ) => switch (exception.kind) {
+    .cancelled => Cancelled(exception, exception.stackTrace ?? stackTrace),
+    _ => TransportError(exception, exception.stackTrace ?? stackTrace),
+  };
+
+  /// The failure of an [Exception] that is not a [TransportException],
+  /// raised while a body was read: a transport failure of kind
+  /// [TransportExceptionKind.other] whose cause it is.
+  Failure<T, E> unexpected<T, E>(Exception exception, StackTrace stackTrace) =>
+      TransportError(
+        TransportException(
+          .other,
+          '$exception',
+          cause: exception,
+          stackTrace: stackTrace,
+        ),
+        stackTrace,
+      );
+
+  /// The [Cancelled] of a call whose [signal] was cancelled before its
+  /// request was sent; the transport is not called.
+  Failure<T, E> cancelledBefore<T, E>(CancelSignal signal) {
+    final stackTrace = StackTrace.current;
+    return Cancelled(
+      TransportException(
+        .cancelled,
+        'The call was cancelled before it was sent.',
+        cause: signal.reason,
+        stackTrace: stackTrace,
+      ),
+      stackTrace,
+    );
+  }
+}
diff --git a/packages/typed_openapi_client/lib/src/client/client_sender.dart b/packages/typed_openapi_client/lib/src/client/client_sender.dart
new file mode 100644
index 0000000..46c9acd
--- /dev/null
+++ b/packages/typed_openapi_client/lib/src/client/client_sender.dart
@@ -0,0 +1,152 @@
+import 'dart:math';
+import 'dart:typed_data';
+
+import '../json/json_decode_exception.dart';
+import '../request/body_encoder.dart';
+import '../request/operation_request.dart';
+import '../request/raw_response.dart';
+import '../result/result.dart';
+import '../sse/sse_item.dart';
+import '../sse/sse_message.dart';
+import '../sse/sse_options.dart';
+import '../transport/client_transport.dart';
+import '../transport/transport_exception.dart';
+import '../transport/transport_response.dart';
+import 'call_options.dart';
+import 'client_results.dart';
+import 'event_opener.dart';
+import 'request_builder.dart';
+import 'response_reader.dart';
+
+/// Sends an [OperationRequest] through a [ClientTransport] and turns every
+/// outcome into a [Result]: what every generated group holds.
+///
+/// - The core builds the request: the path and the query string (one
+///   finished target, resolved by the transport against its base URL), the
+///   headers and the body bytes. The transport is used as it is, and nothing
+///   is retried.
+/// - A response of any status is read to the end and decoded here: the
+///   decoder switches on the status, so a transport whose interceptors turn
+///   an error into another response still gets a typed result.
+/// - A cancel is [Cancelled], another [TransportException] is
+///   [TransportError], a body the decoder rejects with
+///   [JsonDecodeException] is [DecodeError], and so is a [FormatException]
+///   it throws (a user converter or `Date.parse` rejecting the data), at the
+///   root pointer, and a JSON body that does not parse. Nothing else is
+///   caught: an [Error] thrown by the decoder or the transport reaches the
+///   caller.
+final class ClientSender {
+  /// Sends requests through [transport]; [boundary] makes the boundary of
+  /// each multipart body (random by default, fixed in tests).
+  ClientSender(this.transport, {String Function()? boundary})
+    : _builder = RequestBuilder(BodyEncoder(boundary ?? _randomBoundary));
+
+  /// The transport every request goes through.
+  final ClientTransport transport;
+
+  final RequestBuilder _builder;
+
+  static const _results = ClientResults();
+
+  /// Sends [request] and decodes the response of any status with [decode].
+  Future<Result<T, E>> send<T, E>(
+    OperationRequest request,
+    Result<T, E> Function(RawResponse response) decode, {
+    CallOptions? call,
+  }) async {
+    final sent = _builder.build(request, call);
+    if (call?.cancel case final cancel? when cancel.isCancelled) {
+      return _results.cancelledBefore(cancel);
+    }
+    final TransportResponse response;
+    try {
+      response = await transport.send(sent);
+    } on TransportException catch (e, stackTrace) {
+      return _results.failure(e, stackTrace);
+    }
+    return _read(response, request.responseKind, call, decode);
+  }
+
+  /// Opens a `text/event-stream` operation. A status in
+  /// [OperationRequest.streamStatuses] gives a [Success] whose stream reads
+  /// every event with [decodeEvent]; any other status reads the whole body
+  /// and decodes it with [decodeError] (which returns a documented error or
+  /// an undocumented status).
+  ///
+  /// The stream of a [Success] holds the connection open: listen to it, or
+  /// the connection stays open. Cancelling the subscription closes the
+  /// connection, as does cancelling `call.cancel` (the stream then ends with
+  /// [SseDisconnected]). The stream never emits errors, with one exception:
+  /// an [Error] thrown by [decodeEvent] is a bug of the program, so it
+  /// reaches the listener as a stream error and the stream closes. Problems
+  /// with the data are items ([SseDecodeError]), never errors.
+  ///
+  /// The stream reconnects (R12.5) when [reconnection] and `call.sse` say
+  /// so (see [SseReconnection], [SseOptions] and `SseReconnector`); a 204
+  /// No Content never reconnects.
+  ///
+  /// [OperationRequest.streamStatuses] must not be empty (checked by an
+  /// `assert`): a generated method always sets it.
+  Future<Result<Stream<SseItem<T>>, E>> openEvents<T, E>(
+    OperationRequest request,
+    T Function(SseMessage message) decodeEvent,
+    Result<Stream<SseItem<T>>, E> Function(RawResponse response) decodeError, {
+    CallOptions? call,
+    SseReconnection reconnection = .onRequest,
+  }) async {
+    assert(
+      request.streamStatuses.isNotEmpty,
+      'openEvents needs OperationRequest.streamStatuses (the documented '
+      'success statuses of the event stream): without them every status is '
+      'read to the end as an error body, so an endless stream would fill '
+      'memory. This is a bug of the generated code.',
+    );
+    return EventOpener(transport, _builder).open(
+      request,
+      decodeEvent,
+      decodeError,
+      call: call,
+      reconnection: reconnection,
+    );
+  }
+
+  /// Reads [response] to the end as [kind] says and decodes it.
+  Future<Result<T, E>> _read<T, E>(
+    TransportResponse response,
+    ResponseKind kind,
+    CallOptions? call,
+    Result<T, E> Function(RawResponse response) decode,
+  ) async {
+    final Uint8List bytes;
+    try {
+      bytes = await ResponseReader(call?.onReceiveProgress).readAll(response);
+    } on TransportException catch (e, stackTrace) {
+      return _results.failure(e, stackTrace);
+    } on Exception catch (e, stackTrace) {
+      return _results.unexpected(e, stackTrace);
+    }
+    final RawResponse raw;
+    try {
+      raw = ResponseReader.raw(response, bytes, kind);
+    } on JsonDecodeException catch (e) {
+      return _results.decodeError(
+        e,
+        response.statusCode,
+        bytes,
+        response.headers,
+      );
+    }
+    return _results.decode(raw, decode);
+  }
+
+  /// A boundary of 10 random digits after a fixed prefix, as Dio made one.
+  static String _randomBoundary() =>
+      '--typed-openapi-boundary-'
+      '${_random.nextInt(_boundaryRange).toString().padLeft(10, '0')}';
+
+  // 2^32 as a literal: `1 << 32` is 0 when compiled to JavaScript, whose
+  // shifts work on 32 bits.
+  static const _boundaryRange = 4294967296;
+
+  static final Random _random = Random();
+}
diff --git a/packages/typed_openapi_client/lib/src/client/connection_signals.dart b/packages/typed_openapi_client/lib/src/client/connection_signals.dart
new file mode 100644
index 0000000..c275ba8
--- /dev/null
+++ b/packages/typed_openapi_client/lib/src/client/connection_signals.dart
@@ -0,0 +1,31 @@
+import '../transport/cancel_signal.dart';
+
+/// The cancel signals of the connections of one event-stream call.
+///
+/// Each connection has a signal of its own, so closing a stream cancels its
+/// connection and not the call's signal; the call's signal ([outer])
+/// cancels whichever connection is current. The call's signal gets one
+/// listener, not one per connection.
+final class ConnectionSignals {
+  /// Links the connections of a call whose cancel signal is [outer].
+  ConnectionSignals(this._outer) {
+    final outer = _outer;
+    outer?.whenCancelled.then((_) => cancel(outer.reason));
+  }
+
+  final CancelSignal? _outer;
+  CancelSignal? _current;
+
+  /// The signal of a new connection, which becomes the current one.
+  CancelSignal next() {
+    final signal = CancelSignal();
+    if (_outer case final outer? when outer.isCancelled) {
+      signal.cancel(outer.reason);
+    }
+    return _current = signal;
+  }
+
+  /// Cancels the current connection, for [reason]: the listener of the
+  /// stream cancelled, or the call's signal did.
+  void cancel([Object? reason]) => _current?.cancel(reason);
+}
diff --git a/packages/typed_openapi_client/lib/src/dio/event_call.dart b/packages/typed_openapi_client/lib/src/client/event_call.dart
similarity index 81%
rename from packages/typed_openapi_client/lib/src/dio/event_call.dart
rename to packages/typed_openapi_client/lib/src/client/event_call.dart
index 3c767bc..64cea1f 100644
--- a/packages/typed_openapi_client/lib/src/dio/event_call.dart
+++ b/packages/typed_openapi_client/lib/src/client/event_call.dart
@@ -4,15 +4,15 @@ import '../result/result.dart';
 import '../sse/sse_item.dart';
 import '../sse/sse_message.dart';
 import 'call_options.dart';
-import 'connection_tokens.dart';
+import 'connection_signals.dart';
 
 /// What every connection of one event-stream call shares: the request, how
 /// it decodes events and error responses, the call's options and its
-/// connections' cancel tokens.
+/// connections' cancel signals.
 final class EventCall<T, E> {
-  /// Creates the call; its connections are linked to `call.cancelToken`.
+  /// Creates the call; its connections are linked to `call.cancel`.
   EventCall(this.request, this.decodeEvent, this.decodeError, this.call)
-    : tokens = ConnectionTokens(call?.cancelToken);
+    : signals = ConnectionSignals(call?.cancel);
 
   /// The request every connection sends.
   final OperationRequest request;
@@ -27,6 +27,6 @@ final class EventCall<T, E> {
   /// The options of the call.
   final CallOptions? call;
 
-  /// The cancel tokens of the connections.
-  final ConnectionTokens tokens;
+  /// The cancel signals of the connections.
+  final ConnectionSignals signals;
 }
diff --git a/packages/typed_openapi_client/lib/src/client/event_opener.dart b/packages/typed_openapi_client/lib/src/client/event_opener.dart
new file mode 100644
index 0000000..0764931
--- /dev/null
+++ b/packages/typed_openapi_client/lib/src/client/event_opener.dart
@@ -0,0 +1,164 @@
+import 'dart:typed_data';
+
+import '../json/json_decode_exception.dart';
+import '../request/operation_request.dart';
+import '../request/raw_response.dart';
+import '../result/result.dart';
+import '../sse/sse_item.dart';
+import '../sse/sse_item_decoder.dart';
+import '../sse/sse_message.dart';
+import '../sse/sse_options.dart';
+import '../sse/sse_reconnector.dart';
+import '../transport/cancel_signal.dart';
+import '../transport/client_transport.dart';
+import '../transport/transport_exception.dart';
+import '../transport/transport_response.dart';
+import 'call_options.dart';
+import 'client_results.dart';
+import 'event_call.dart';
+import 'progress_counter.dart';
+import 'request_builder.dart';
+import 'response_reader.dart';
+
+/// Opens the event streams of `ClientSender.openEvents`: the first
+/// connection, the reconnections, and the error responses that are read to
+/// the end.
+final class EventOpener {
+  /// Creates the opener over [transport], building requests with
+  /// [builder].
+  const EventOpener(this.transport, this.builder);
+
+  /// The transport every connection goes through.
+  final ClientTransport transport;
+
+  /// Builds the request of each connection.
+  final RequestBuilder builder;
+
+  static const _results = ClientResults();
+
+  /// Opens [request] as `ClientSender.openEvents` describes.
+  Future<Result<Stream<SseItem<T>>, E>> open<T, E>(
+    OperationRequest request,
+    T Function(SseMessage message) decodeEvent,
+    Result<Stream<SseItem<T>>, E> Function(RawResponse response) decodeError, {
+    required CallOptions? call,
+    required SseReconnection reconnection,
+  }) async {
+    final event = EventCall(request, decodeEvent, decodeError, call);
+    final first = await _connect(event, (
+      lastEventId: RequestBuilder.userLastEventId(call?.headers),
+      retry: null,
+    ));
+    final options = call?.sse ?? const SseOptions();
+    if (first case Success(
+      :final data,
+      :final statusCode,
+      :final headers,
+    ) when statusCode != 204 && reconnection.reconnects(options)) {
+      return Success(
+        SseReconnector<T>(
+          options,
+          (resume) => _connect(event, resume),
+          cancel: call?.cancel,
+          onCancel: event.signals.cancel,
+        ).bind(data),
+        statusCode: statusCode,
+        headers: headers,
+      );
+    }
+    return first;
+  }
+
+  /// One connection: it sends `Last-Event-ID` and starts the decoder from
+  /// [resume].
+  Future<Result<Stream<SseItem<T>>, E>> _connect<T, E>(
+    EventCall<T, E> event,
+    SseResume resume,
+  ) async {
+    final signal = event.signals.next();
+    final sent = builder.build(
+      event.request,
+      event.call,
+      events: true,
+      cancel: signal,
+      lastEventId: resume.lastEventId,
+    );
+    if (signal.isCancelled) return _results.cancelledBefore(signal);
+    final TransportResponse response;
+    try {
+      response = await transport.send(sent);
+    } on TransportException catch (e, stackTrace) {
+      return _results.failure(e, stackTrace);
+    }
+    if (!event.request.streamStatuses.contains(response.statusCode)) {
+      return _openFailed(response, event);
+    }
+    return _events(response, event, signal, resume);
+  }
+
+  /// The [Success] of an opened stream: its items, decoded from the body of
+  /// [response]; the end of the stream cancels [signal], closing the
+  /// connection.
+  Success<Stream<SseItem<T>>, E> _events<T, E>(
+    TransportResponse response,
+    EventCall<T, E> event,
+    CancelSignal signal,
+    SseResume resume,
+  ) {
+    final body = ProgressCounter(
+      event.call?.onReceiveProgress,
+    ).count(response.body, ResponseReader.totalOf(response));
+    final items = SseItemDecoder<T>(
+      event.decodeEvent,
+      onClose: () => signal.cancel('the event stream was closed'),
+      lastEventId: resume.lastEventId,
+      retry: resume.retry,
+    ).bind(body);
+    return Success(
+      items,
+      statusCode: response.statusCode,
+      headers: response.headers,
+    );
+  }
+
+  /// Reads the whole body of an event-stream response that did not open,
+  /// parses it (JSON by content type) and decodes it with the error decoder
+  /// of [event].
+  Future<Result<Stream<SseItem<T>>, E>> _openFailed<T, E>(
+    TransportResponse response,
+    EventCall<T, E> event,
+  ) async {
+    final Uint8List bytes;
+    try {
+      bytes = await ResponseReader(
+        event.call?.onReceiveProgress,
+      ).readAll(response);
+    } on TransportException catch (e, stackTrace) {
+      return _results.failure(e, stackTrace);
+    } on Exception catch (e, stackTrace) {
+      // The transport's own exception while reading the body breaks its
+      // contract; it is still a transport failure. An Error reaches the
+      // caller.
+      return _results.unexpected(e, stackTrace);
+    }
+    final Object? body;
+    try {
+      body = RawResponse.parse(bytes, response.headers);
+    } on JsonDecodeException catch (e) {
+      return _results.decodeError(
+        e,
+        response.statusCode,
+        bytes,
+        response.headers,
+      );
+    }
+    return _results.decode(
+      RawResponse(
+        statusCode: response.statusCode,
+        body: body,
+        headers: response.headers,
+      ),
+      event.decodeError,
+    );
+  }
+}
diff --git a/packages/typed_openapi_client/lib/src/client/progress_counter.dart b/packages/typed_openapi_client/lib/src/client/progress_counter.dart
new file mode 100644
index 0000000..ba62d1b
--- /dev/null
+++ b/packages/typed_openapi_client/lib/src/client/progress_counter.dart
@@ -0,0 +1,22 @@
+/// Reports the bytes of a request or response body as they pass, as
+/// `CallOptions.onSendProgress` and `onReceiveProgress` want them.
+final class ProgressCounter {
+  /// Reports to [onProgress]; null counts nothing.
+  const ProgressCounter(this.onProgress);
+
+  /// Called with the bytes so far and the total.
+  final void Function(int count, int total)? onProgress;
+
+  /// [stream], reporting after each chunk the bytes so far and [total]
+  /// (`-1` when the total is not known).
+  Stream<List<int>> count(Stream<List<int>> stream, int total) {
+    final report = onProgress;
+    if (report == null) return stream;
+    var count = 0;
+    return stream.map((chunk) {
+      count += chunk.length;
+      report(count, total);
+      return chunk;
+    });
+  }
+}
diff --git a/packages/typed_openapi_client/lib/src/client/request_builder.dart b/packages/typed_openapi_client/lib/src/client/request_builder.dart
new file mode 100644
index 0000000..b3744d1
--- /dev/null
+++ b/packages/typed_openapi_client/lib/src/client/request_builder.dart
@@ -0,0 +1,132 @@
+import '../request/body_encoder.dart';
+import '../request/encoded_body.dart';
+import '../request/operation_request.dart';
+import '../transport/cancel_signal.dart';
+import '../transport/transport_request.dart';
+import 'call_options.dart';
+import 'progress_counter.dart';
+
+/// Builds the [TransportRequest] of an [OperationRequest]: the target, the
+/// headers in order and the body bytes. It sets `Accept`, the operation's
+/// headers, `Content-Type` and `Content-Length`, and nothing else.
+final class RequestBuilder {
+  /// Creates the builder, which encodes bodies with [encoder].
+  const RequestBuilder(this.encoder);
+
+  /// Encodes request bodies.
+  final BodyEncoder encoder;
+
+  /// The request of [request] with [call]: for an event stream ([events])
+  /// with `Accept: text/event-stream` and, when it is not empty and a valid
+  /// header value, [lastEventId] as `Last-Event-ID`. [cancel] wins over the
+  /// call's signal.
+  ///
+  /// Throws what encoding the body throws ([ArgumentError],
+  /// [FormatException]) and [ArgumentError] for a path without a value.
+  TransportRequest build(
+    OperationRequest request,
+    CallOptions? call, {
+    bool events = false,
+    CancelSignal? cancel,
+    String lastEventId = '',
+  }) {
+    final body = encoder.encode(request);
+    final headers = _headers(request, call, body, events, lastEventId);
+    return TransportRequest(
+      method: request.operation.method,
+      target: request.resolvePath(),
+      operation: request.operation,
+      headers: headers,
+      body: switch (body) {
+        final body? => ProgressCounter(
+          call?.onSendProgress,
+        ).count(body.read(), body.length),
+        null => null,
+      },
+      cancel: cancel ?? call?.cancel,
+      extra: {...?call?.extra},
+      isEventStream: events,
+    );
+  }
+
+  /// The headers of [request]: `Accept`, the operation's, the call's, the
+  /// stream's `Last-Event-ID`, then the body's type and length.
+  static Map<String, List<String>> _headers(
+    OperationRequest request,
+    CallOptions? call,
+    EncodedBody? body,
+    bool events,
+    String lastEventId,
+  ) {
+    final headers = _HeaderList()
+      ..add('Accept', events ? 'text/event-stream' : request.accept);
+    for (final MapEntry(:key, :value) in request.resolveHeaders().entries) {
+      headers.add(key, value);
+    }
+    for (final MapEntry(:key, :value) in call?.headers.entries ?? const []) {
+      // The stream's last event id replaces the user's `Last-Event-ID`.
+      if (!events || !_isLastEventId(key)) headers.add(key, value);
+    }
+    if (events && _isHeaderValue(lastEventId)) {
+      headers.add('Last-Event-ID', lastEventId);
+    }
+    if (body?.contentType case final type?) {
+      headers
+        ..remove('content-type')
+        ..add('content-type', type);
+    }
+    if (body != null) headers.add('content-length', '${body.length}');
+    return headers.values;
+  }
+
+  /// The `Last-Event-ID` that the user's [headers] set (in any case), which
+  /// is where the stream's last event id starts: it is sent with the first
+  /// request, the ids of the events replace it, and an `id:` that resets it
+  /// leaves it gone, as `EventSource` does. Empty when there is none.
+  static String userLastEventId(Map<String, Object?>? headers) {
+    for (final MapEntry(:key, :value) in headers?.entries ?? const []) {
+      if (_isLastEventId(key) && value != null) return '$value';
+    }
+    return '';
+  }
+
+  static bool _isLastEventId(String header) =>
+      header.toLowerCase() == 'last-event-id';
+
+  /// Whether [id] is a non-empty header value that every HTTP client sends:
+  /// printable ASCII, spaces and tabs. The VM's `HttpClient` throws on any
+  /// other character, which would fail every reconnection; a browser sends
+  /// UTF-8, so the id is dropped on both and the stream reconnects without
+  /// `Last-Event-ID`.
+  static bool _isHeaderValue(String id) =>
+      id.isNotEmpty &&
+      id.codeUnits.every((c) => c == 0x09 || (c >= 0x20 && c <= 0x7E));
+}
+
+/// Headers by name, case-insensitively: a name keeps its first spelling and
+/// place, and a later value replaces an earlier one, as Dio's header map
+/// did.
+final class _HeaderList {
+  final Map<String, (String, List<String>)> _byName = {};
+
+  /// Sets [name] to [value]: nothing for `null`, one value per item of a
+  /// list, else its text.
+  void add(String name, Object? value) {
+    final values = switch (value) {
+      null => null,
+      final List<Object?> items => [for (final item in items) '$item'],
+      final other => ['$other'],
+    };
+    if (values == null) return;
+    final key = name.toLowerCase();
+    _byName[key] = (_byName[key]?.$1 ?? name, values);
+  }
+
+  /// Removes [name] in any case.
+  void remove(String name) => _byName.remove(name.toLowerCase());
+
+  /// The headers, by their first spelling.
+  Map<String, List<String>> get values => {
+    for (final (name, values) in _byName.values) name: values,
+  };
+}
diff --git a/packages/typed_openapi_client/lib/src/client/response_reader.dart b/packages/typed_openapi_client/lib/src/client/response_reader.dart
new file mode 100644
index 0000000..6e55b45
--- /dev/null
+++ b/packages/typed_openapi_client/lib/src/client/response_reader.dart
@@ -0,0 +1,75 @@
+import 'dart:convert';
+import 'dart:typed_data';
+
+import '../json/json_decode_exception.dart';
+import '../request/operation_request.dart';
+import '../request/raw_response.dart';
+import '../transport/transport_response.dart';
+import 'progress_counter.dart';
+
+/// Reads the body of a [TransportResponse] into what a generated decoder
+/// switches on, by the [ResponseKind] of the operation.
+final class ResponseReader {
+  /// Creates the reader; [onProgress] gets the received bytes.
+  const ResponseReader(this.onProgress);
+
+  /// Called with the received bytes and the `Content-Length`, `-1` without
+  /// one.
+  final void Function(int count, int total)? onProgress;
+
+  /// [response] read to the end, the bytes counted for [onProgress].
+  Future<Uint8List> readAll(TransportResponse response) async {
+    final bytes = BytesBuilder(copy: false);
+    await ProgressCounter(
+      onProgress,
+    ).count(response.body, totalOf(response)).forEach(bytes.add);
+    return bytes.takeBytes();
+  }
+
+  /// The `Content-Length` of [response], `-1` without a valid one.
+  static int totalOf(TransportResponse response) =>
+      switch (response.headers['content-length']) {
+        [final length, ...] => int.tryParse(length) ?? -1,
+        _ => -1,
+      };
+
+  /// The [RawResponse] of [response], whose body is [bytes], read as
+  /// [kind] says:
+  ///
+  /// - [ResponseKind.json]: parsed JSON when the headers name a JSON media
+  ///   type, else the text; `null` when empty. Text that is not JSON, or not
+  ///   UTF-8, throws [JsonDecodeException].
+  /// - [ResponseKind.text]: the text, invalid UTF-8 replaced.
+  /// - [ResponseKind.bytes]: the bytes.
+  static RawResponse raw(
+    TransportResponse response,
+    Uint8List bytes,
+    ResponseKind kind,
+  ) => RawResponse(
+    statusCode: response.statusCode,
+    body: switch (kind) {
+      .json => _json(bytes, response.headers),
+      .text => utf8.decode(bytes, allowMalformed: true),
+      .bytes => bytes,
+    },
+    headers: response.headers,
+  );
+
+  static Object? _json(Uint8List bytes, Map<String, List<String>> headers) {
+    if (bytes.isEmpty) return null;
+    if (!RawResponse.isJson(headers)) {
+      return utf8.decode(bytes, allowMalformed: true);
+    }
+    try {
+      return _utf8Json.convert(bytes);
+    } on FormatException {
+      throw JsonDecodeException(
+        expected: 'a JSON body',
+        actual: 'text that is not JSON',
+      );
+    }
+  }
+
+  static final Converter<List<int>, Object?> _utf8Json = const Utf8Decoder()
+      .fuse(const JsonDecoder());
+}
diff --git a/packages/typed_openapi_client/lib/src/request/operation_info.dart b/packages/typed_openapi_client/lib/src/request/operation_info.dart
index d8039c7..30842ac 100644
--- a/packages/typed_openapi_client/lib/src/request/operation_info.dart
+++ b/packages/typed_openapi_client/lib/src/request/operation_info.dart
@@ -1,12 +1,10 @@
-import 'package:dio/dio.dart';
-
 import 'security.dart';
 
 /// What a request is: the operation of the spec it calls.
 ///
-/// The request sender puts it into `RequestOptions.extra` under
-/// [extraKey], so interceptors can tell operations apart
-/// (`OperationInfo.of(options)?.operationId`).
+/// Every `TransportRequest` carries it, so a transport can tell operations
+/// apart; the Dio transport puts it into `RequestOptions.extra` under
+/// [extraKey] for interceptors.
 final class OperationInfo {
   /// Describes one operation.
   const OperationInfo({
@@ -40,14 +38,6 @@ final class OperationInfo {
   /// describes them: interceptors add the credentials.
   final List<List<SecurityUse>> security;
 
-  /// The operation of a request, or `null` for a request a generated
-  /// client did not send.
-  static OperationInfo? of(RequestOptions options) =>
-      switch (options.extra[extraKey]) {
-        final OperationInfo info => info,
-        _ => null,
-      };
-
   @override
   String toString() => '$method $pathTemplate ($operationId)';
 }
diff --git a/packages/typed_openapi_client/lib/src/request/operation_request.dart b/packages/typed_openapi_client/lib/src/request/operation_request.dart
index 09387cf..c3a6a65 100644
--- a/packages/typed_openapi_client/lib/src/request/operation_request.dart
+++ b/packages/typed_openapi_client/lib/src/request/operation_request.dart
@@ -6,7 +6,7 @@ import 'operation_info.dart';
 
 /// How the response body is read, by the content type of the spec.
 enum ResponseKind {
-  /// JSON, parsed by Dio (`ResponseType.json`).
+  /// JSON, parsed by the client when the response names a JSON type.
   json,
 
   /// Text.
diff --git a/packages/typed_openapi_client/lib/src/request/raw_response.dart b/packages/typed_openapi_client/lib/src/request/raw_response.dart
index 803fda1..41b3421 100644
--- a/packages/typed_openapi_client/lib/src/request/raw_response.dart
+++ b/packages/typed_openapi_client/lib/src/request/raw_response.dart
@@ -27,7 +27,7 @@ final class RawResponse {
   /// The HTTP status code.
   final int statusCode;
 
-  /// The body as the HTTP client returned it: JSON parsed by Dio, a
+  /// The body as the HTTP client returned it: parsed JSON, a
   /// [String], bytes ([Uint8List]) or `null`.
   final Object? body;
 
@@ -122,7 +122,7 @@ final class RawResponse {
   }
 
   /// Whether [headers] name a JSON content type (`application/json`,
-  /// `text/json`, `*/*+json`), as Dio decides.
+  /// `text/json`, `*/*+json`), as [MediaTypeText] decides.
   static bool isJson(Map<String, List<String>> headers) =>
       switch (headers['content-type']?.firstOrNull) {
         final type? => MediaTypeText(type).isJson,
diff --git a/packages/typed_openapi_client/lib/src/result/result.dart b/packages/typed_openapi_client/lib/src/result/result.dart
index ef0fa83..25d924b 100644
--- a/packages/typed_openapi_client/lib/src/result/result.dart
+++ b/packages/typed_openapi_client/lib/src/result/result.dart
@@ -1,6 +1,5 @@
-import 'package:dio/dio.dart';
-
 import '../json/json_decode_exception.dart';
+import '../transport/transport_exception.dart';
 
 /// The outcome of a generated operation: [Success] with the decoded body of
 /// type [T], or a [Failure] whose documented error body has type [E].
@@ -110,12 +109,12 @@ final class DecodeError<T, E> extends Failure<T, E> {
   /// What did not match and where (JSON pointer, expected, actual).
   final JsonDecodeException error;
 
-  /// The HTTP status code; `null` when Dio could not parse the JSON body
-  /// and dropped the response.
+  /// The HTTP status code; `null` only for a decode error made without a
+  /// response.
   final int? statusCode;
 
-  /// The body as the HTTP client returned it; for JSON Dio could not parse,
-  /// the text its parser reported.
+  /// The body: the text of a JSON body that does not parse, else the value
+  /// the decoder was given.
   final Object? rawBody;
 
   /// The response headers, names in lower case.
@@ -126,19 +125,19 @@ final class DecodeError<T, E> extends Failure<T, E> {
 }
 
 /// The request got no response: a timeout, a connection or certificate
-/// problem, or another failure Dio reports.
+/// problem, or another failure the transport reports.
 final class TransportError<T, E> extends Failure<T, E> {
   /// Creates a transport failure.
   const TransportError(this.exception, this.stackTrace);
 
-  /// What Dio reported; `exception.type` tells the kind.
-  final DioException exception;
+  /// What the transport reported; `exception.kind` tells the kind.
+  final TransportException exception;
 
   /// Where [exception] was thrown.
   final StackTrace stackTrace;
 
   @override
-  String toString() => 'TransportError(${exception.type.name})';
+  String toString() => 'TransportError(${exception.kind.name})';
 }
 
 /// The caller cancelled the request; not a failure of the server or the
@@ -147,8 +146,9 @@ final class Cancelled<T, E> extends Failure<T, E> {
   /// Creates a cancellation outcome.
   const Cancelled(this.exception, this.stackTrace);
 
-  /// What Dio reported (`DioExceptionType.cancel`).
-  final DioException exception;
+  /// What the sender or the transport reported
+  /// ([TransportExceptionKind.cancelled]).
+  final TransportException exception;
 
   /// Where [exception] was thrown.
   final StackTrace stackTrace;
diff --git a/packages/typed_openapi_client/lib/src/sse/sse_reconnector.dart b/packages/typed_openapi_client/lib/src/sse/sse_reconnector.dart
index ee29872..73d6421 100644
--- a/packages/typed_openapi_client/lib/src/sse/sse_reconnector.dart
+++ b/packages/typed_openapi_client/lib/src/sse/sse_reconnector.dart
@@ -1,8 +1,8 @@
 import 'dart:async';
 
-import 'package:dio/dio.dart';
-
 import '../result/result.dart';
+import '../transport/cancel_signal.dart';
+import '../transport/transport_exception.dart';
 import 'cancellable_wait.dart';
 import 'sse_item.dart';
 import 'sse_options.dart';
@@ -19,7 +19,7 @@ typedef SseResume = ({String lastEventId, Duration? retry});
 /// follow; a failed attempt (a [TransportError]) is the next attempt. The
 /// stream ends with [SseDisconnected] when [SseOptions.maxAttempts]
 /// attempts in a row bring no message, when the request is cancelled (the
-/// listener cancels, or [cancelled] completes, also during a wait), when
+/// listener cancels, or [cancel] is cancelled, also during a wait), when
 /// the server answers an attempt with a status that is not a stream (the
 /// `Failure` is the cause), or with 204 No Content, which tells a client
 /// to stop reconnecting.
@@ -29,7 +29,7 @@ final class SseReconnector<T>
   const SseReconnector(
     this.options,
     this.reopen, {
-    this.cancelled,
+    this.cancel,
     this.onCancel,
   });
 
@@ -40,8 +40,8 @@ final class SseReconnector<T>
   final Future<Result<Stream<SseItem<T>>, Object?>> Function(SseResume resume)
   reopen;
 
-  /// Completes when the call's cancel token is cancelled.
-  final Future<DioException>? cancelled;
+  /// The call's cancel signal.
+  final CancelSignal? cancel;
 
   /// Called when the listener cancels the stream, to abort a request that
   /// [reopen] has in flight.
@@ -65,11 +65,20 @@ final class _Reconnection<T> {
   Duration? _retry;
   int _attempt = 0;
   bool _closed = false;
-  DioException? _cancel;
+  TransportException? _cancel;
+  // Read once: every wait races the same future, and a signal is asked for
+  // it once per call, not once per reconnection.
+  Future<void>? _cancelled;
 
   Stream<SseItem<T>> start(Stream<SseItem<T>> first) {
-    _owner.cancelled?.then((e) {
-      _cancel = e;
+    _cancelled = _owner.cancel?.whenCancelled;
+    _cancelled?.then((_) {
+      _cancel = TransportException(
+        .cancelled,
+        'The call was cancelled.',
+        cause: _owner.cancel?.reason,
+        stackTrace: StackTrace.current,
+      );
       _sleep.cancel();
     });
     _out = StreamController<SseItem<T>>(
@@ -114,7 +123,7 @@ final class _Reconnection<T> {
         _out.add(item);
       case SseReconnecting():
         _out.add(item);
-      case SseDisconnected(cause: DioException(type: .cancel)):
+      case SseDisconnected(cause: TransportException(kind: .cancelled)):
         _end(item);
       case SseDisconnected(:final cause, :final stackTrace):
         // A dropped event (SseEventIgnored) still moves the id and counts as
@@ -139,7 +148,7 @@ final class _Reconnection<T> {
     } on Object catch (error, trace) {
       // Not awaited by anyone: an escaping error would hang the stream and
       // reach the zone. It comes from user code (a `wait` or an interceptor)
-      // or from the Dio adapter, and is a bug as an Error in a decoder is.
+      // or from the transport, and is a bug as an Error in a decoder is.
       _fail(error, trace);
     }
   }
@@ -189,7 +198,7 @@ final class _Reconnection<T> {
 
   Future<void> _wait(Duration delay) {
     final wait = _sleep.wait(delay);
-    final cancelled = _owner.cancelled;
+    final cancelled = _cancelled;
     return cancelled == null ? wait : Future.any([wait, cancelled]);
   }
 
diff --git a/packages/typed_openapi_client/lib/src/transport/cancel_signal.dart b/packages/typed_openapi_client/lib/src/transport/cancel_signal.dart
index 16c1584..1a920e8 100644
--- a/packages/typed_openapi_client/lib/src/transport/cancel_signal.dart
+++ b/packages/typed_openapi_client/lib/src/transport/cancel_signal.dart
@@ -5,7 +5,7 @@ import 'dart:async';
 ///
 /// One signal may serve several calls; a cancelled signal stays cancelled,
 /// so a call made with it afterwards is cancelled before it is sent.
-final class CancelSignal {
+base class CancelSignal {
   /// Creates a signal that is not cancelled.
   CancelSignal();
 
diff --git a/packages/typed_openapi_client/lib/typed_openapi_client.dart b/packages/typed_openapi_client/lib/typed_openapi_client.dart
index 694e904..0bebf7a 100644
--- a/packages/typed_openapi_client/lib/typed_openapi_client.dart
+++ b/packages/typed_openapi_client/lib/typed_openapi_client.dart
@@ -3,8 +3,8 @@ library;
 
 export 'package:meta/meta.dart' show immutable;
 
-export 'src/dio/call_options.dart' show CallOptions;
-export 'src/dio/dio_request_sender.dart' show DioRequestSender;
+export 'src/client/call_options.dart' show CallOptions;
+export 'src/client/client_sender.dart' show ClientSender;
 export 'src/json/json_decode_exception.dart' show JsonDecodeException;
 export 'src/json/json_reader.dart' show JsonReader;
 export 'src/json/json_value.dart' show JsonValue;
diff --git a/packages/typed_openapi_client/pubspec.yaml b/packages/typed_openapi_client/pubspec.yaml
index bf6f7e3..471eff7 100644
--- a/packages/typed_openapi_client/pubspec.yaml
+++ b/packages/typed_openapi_client/pubspec.yaml
@@ -11,12 +11,9 @@ environment:
   sdk: ">=3.10.0 <4.0.0"
 
 dependencies:
-  dio: ^5.11.1
   meta: ^1.15.0
 
 dev_dependencies:
-  # The local server of the browser Cookie test (spawnHybridUri).
-  stream_channel: ^2.1.2
   test: ^1.24.0
 
 resolution: workspace
diff --git a/packages/typed_openapi_client/test/dio/accept_test.dart b/packages/typed_openapi_client/test/client/accept_test.dart
similarity index 73%
rename from packages/typed_openapi_client/test/dio/accept_test.dart
rename to packages/typed_openapi_client/test/client/accept_test.dart
index 48e2607..69b104e 100644
--- a/packages/typed_openapi_client/test/dio/accept_test.dart
+++ b/packages/typed_openapi_client/test/client/accept_test.dart
@@ -1,8 +1,7 @@
-import 'package:dio/dio.dart';
 import 'package:test/test.dart';
 import 'package:typed_openapi_client/typed_openapi_client.dart';
 
-import '../helpers/fake_adapter.dart';
+import '../helpers/fake_transport.dart';
 
 void main() {
   const chat = OperationInfo(
@@ -11,13 +10,13 @@ void main() {
     pathTemplate: '/chat',
   );
 
-  Future<RequestOptions> sent(
+  Future<TransportRequest> sent(
     OperationRequest request, {
     CallOptions? call,
   }) async {
-    final adapter = FakeAdapter.json(200, {'ok': true});
-    await DioRequestSender(
-      Dio()..httpClientAdapter = adapter,
+    final adapter = FakeTransport.json(200, {'ok': true});
+    await ClientSender(
+      adapter,
     ).send(request, (r) => r.success(r.json), call: call);
     return adapter.requests.single;
   }
@@ -26,13 +25,13 @@ void main() {
     final options = await sent(
       const OperationRequest(chat, accept: 'application/json'),
     );
-    expect(options.headers['Accept'], 'application/json');
+    expect(FakeTransport.header(options, 'Accept'), 'application/json');
   });
 
   test('a request without an accept sends no Accept', () async {
     final options = await sent(const OperationRequest(chat));
     expect(options.headers.keys.map((k) => k.toLowerCase()), isNot(['accept']));
-    expect(options.headers['Accept'], isNull);
+    expect(FakeTransport.header(options, 'Accept'), isNull);
   });
 
   test('an Accept of the call wins, and its map is not changed', () async {
@@ -41,7 +40,10 @@ void main() {
       const OperationRequest(chat, accept: 'application/json'),
       call: CallOptions(headers: headers),
     );
-    expect(options.headers['Accept'], 'application/vnd.custom+json');
+    expect(
+      FakeTransport.header(options, 'Accept'),
+      'application/vnd.custom+json',
+    );
     expect(headers, {'accept': 'application/vnd.custom+json'});
   });
 }
diff --git a/packages/typed_openapi_client/test/dio/bodies_send_test.dart b/packages/typed_openapi_client/test/client/bodies_send_test.dart
similarity index 70%
rename from packages/typed_openapi_client/test/dio/bodies_send_test.dart
rename to packages/typed_openapi_client/test/client/bodies_send_test.dart
index 782c024..a2abba9 100644
--- a/packages/typed_openapi_client/test/dio/bodies_send_test.dart
+++ b/packages/typed_openapi_client/test/client/bodies_send_test.dart
@@ -1,11 +1,10 @@
 import 'dart:convert';
 import 'dart:typed_data';
 
-import 'package:dio/dio.dart';
 import 'package:test/test.dart';
 import 'package:typed_openapi_client/typed_openapi_client.dart';
 
-import '../helpers/fake_adapter.dart';
+import '../helpers/fake_transport.dart';
 
 void main() {
   const upload = OperationInfo(
@@ -17,13 +16,13 @@ void main() {
   Result<void, Never> decodeVoid(RawResponse r) =>
       r.statusCode == 204 ? r.success(null) : r.undocumented();
 
-  (DioRequestSender, FakeAdapter) senderFor(FakeAdapter adapter) => (
-    DioRequestSender(Dio()..httpClientAdapter = adapter),
+  (ClientSender, FakeTransport) senderFor(FakeTransport adapter) => (
+    ClientSender(adapter),
     adapter,
   );
 
-  FakeAdapter noContent() =>
-      FakeAdapter((_) => ResponseBody.fromString('', 204));
+  FakeTransport noContent() =>
+      FakeTransport((_) => FakeTransport.response('', 204));
 
   test('a form body is sent as text with its content type', () async {
     final (sender, adapter) = senderFor(noContent());
@@ -38,7 +37,7 @@ void main() {
     expect(result, isA<Success<void, Never>>());
     expect(adapter.bodies.single, 'name=a%20b&n=1');
     expect(
-      adapter.requests.single.contentType,
+      FakeTransport.header(adapter.requests.single, 'content-type'),
       'application/x-www-form-urlencoded',
     );
   });
@@ -90,7 +89,8 @@ void main() {
       ),
       decodeVoid,
     );
-    final type = adapter.requests.single.headers['content-type'] as String;
+    final type =
+        FakeTransport.header(adapter.requests.single, 'content-type') as String;
     expect(type, startsWith('multipart/form-data; boundary='));
     final body = adapter.bodies.single;
     expect(body, contains('name="note"\r\n\r\nhi\r\n'));
@@ -147,15 +147,19 @@ void main() {
       decodeVoid,
     );
     expect(adapter.bodies, ['png', 'abc']);
-    expect(adapter.requests.first.contentType, 'application/octet-stream');
-    expect(adapter.requests.last.contentType, 'image/png');
-    expect(adapter.requests.last.headers['content-length'], '3');
+    expect(
+      FakeTransport.header(adapter.requests.first, 'content-type'),
+      'application/octet-stream',
+    );
+    expect(
+      FakeTransport.header(adapter.requests.last, 'content-type'),
+      'image/png',
+    );
+    expect(FakeTransport.header(adapter.requests.last, 'content-length'), '3');
   });
 
   test('a binary operation decodes a JSON error body', () async {
-    final sender = DioRequestSender(
-      Dio()..httpClientAdapter = FakeAdapter.json(404, {'code': 'gone'}),
-    );
+    final sender = ClientSender(FakeTransport.json(404, {'code': 'gone'}));
     Result<Uint8List, Object?> decode(RawResponse r) => switch (r.statusCode) {
       200 => r.success(r.bytes),
       404 => r.error(JsonReader.asObject(r.parsedJson)['code']),
@@ -175,49 +179,4 @@ void main() {
     expect(result, isA<HttpError<Uint8List, Object?>>());
     expect((result as HttpError<Uint8List, Object?>).body, 'gone');
   });
-
-  test('an interceptor reads the security metadata of the operation', () async {
-    const bearer = SecurityScheme('bearer', .http, scheme: 'bearer');
-    const key = SecurityScheme(
-      'key',
-      .apiKey,
-      location: .query,
-      parameterName: 'k',
-    );
-    const secured = OperationInfo(
-      operationId: 'secured',
-      method: 'GET',
-      pathTemplate: '/x',
-      security: [
-        [
-          SecurityUse(bearer, ['read']),
-        ],
-        [SecurityUse(key)],
-      ],
-    );
-    final seen = <String>[];
-    final dio = Dio()
-      ..httpClientAdapter = noContent()
-      ..interceptors.add(
-        InterceptorsWrapper(
-          onRequest: (options, handler) {
-            final info = OperationInfo.of(options)!;
-            for (final alternative in info.security) {
-              for (final use in alternative) {
-                seen.add(
-                  '${use.scheme.type.name} ${use.scheme.scheme ?? ''} '
-                  '${use.scheme.location?.name ?? ''} '
-                  '${use.scheme.parameterName ?? ''} ${use.scopes}',
-                );
-              }
-            }
-            handler.next(options);
-          },
-        ),
-      );
-    await DioRequestSender(
-      dio,
-    ).send(const OperationRequest(secured), decodeVoid);
-    expect(seen, ['http bearer   [read]', 'apiKey  query k []']);
-  });
 }
diff --git a/packages/typed_openapi_client/test/client/client_sender_test.dart b/packages/typed_openapi_client/test/client/client_sender_test.dart
new file mode 100644
index 0000000..e3b37cd
--- /dev/null
+++ b/packages/typed_openapi_client/test/client/client_sender_test.dart
@@ -0,0 +1,321 @@
+import 'dart:typed_data';
+
+import 'package:test/test.dart';
+import 'package:typed_openapi_client/typed_openapi_client.dart';
+
+import '../helpers/fake_transport.dart';
+
+/// A model the way generated code reads one.
+final class Pet {
+  const Pet(this.id, this.name);
+
+  factory Pet.fromJson(Map<String, Object?> json) {
+    final r = JsonReader(json, schema: 'Pet');
+    return Pet(
+      r.required('id', JsonReader.asInt),
+      r.required('name', JsonReader.asString),
+    );
+  }
+
+  final int id;
+  final String name;
+}
+
+/// A documented error body.
+final class Problem {
+  const Problem(this.code);
+
+  factory Problem.fromJson(Map<String, Object?> json) => Problem(
+    JsonReader(json, schema: 'Problem').required('code', JsonReader.asString),
+  );
+
+  final String code;
+}
+
+void main() {
+  const getPet = OperationInfo(
+    operationId: 'getPet',
+    method: 'GET',
+    pathTemplate: '/pets/{petId}',
+    tags: ['pets'],
+  );
+  const request = OperationRequest(
+    getPet,
+    path: [PathParameter('petId', 7)],
+    query: [
+      QueryParameter('fields', ['id', 'name'], explode: false),
+    ],
+    headers: [HeaderParameter('X-Trace', 't1')],
+  );
+
+  // The decoder a generated method passes: 200 is Pet, 404 is Problem.
+  Result<Pet, Problem> decodePet(RawResponse r) => switch (r.statusCode) {
+    200 => r.success(Pet.fromJson(r.jsonObject)),
+    404 => r.error(Problem.fromJson(r.jsonObject)),
+    _ => r.undocumented(),
+  };
+
+  test('a documented success decodes the body', () async {
+    final adapter = FakeTransport.json(200, {'id': 7, 'name': 'Rex'});
+    final result = await ClientSender(adapter).send(request, decodePet);
+    final success = result as Success<Pet, Problem>;
+    expect((success.data.id, success.data.name), (7, 'Rex'));
+    expect(success.statusCode, 200);
+    expect(success.headers['content-type'], ['application/json']);
+    final sent = adapter.requests.single;
+    expect(sent.target, '/pets/7?fields=id,name');
+    expect(sent.method, 'GET');
+    expect(sent.operation, getPet);
+  });
+
+  test('per-call headers win over header parameters', () async {
+    final adapter = FakeTransport.json(200, {'id': 7, 'name': 'Rex'});
+    await ClientSender(adapter).send(
+      request,
+      decodePet,
+      call: const CallOptions(headers: {'X-Trace': 'call'}),
+    );
+    expect(FakeTransport.header(adapter.requests.single, 'X-Trace'), 'call');
+  });
+
+  test('a documented error status is typed', () async {
+    final adapter = FakeTransport.json(404, {'code': 'gone'});
+    final result = await ClientSender(adapter).send(request, decodePet);
+    final error = result as HttpError<Pet, Problem>;
+    expect((error.statusCode, error.body.code), (404, 'gone'));
+  });
+
+  test('a documented error body that does not decode', () async {
+    final adapter = FakeTransport.json(404, {'message': 'gone'});
+    final result = await ClientSender(adapter).send(request, decodePet);
+    final error = result as DecodeError<Pet, Problem>;
+    expect(error.statusCode, 404);
+    expect(error.rawBody, {'message': 'gone'});
+    expect((error.error.schema, error.error.pointer), ('Problem', '/code'));
+  });
+
+  test('an undocumented status keeps the raw body', () async {
+    final adapter = FakeTransport.json(418, {'tea': true});
+    final result = await ClientSender(adapter).send(request, decodePet);
+    final undocumented = result as UndocumentedStatus<Pet, Problem>;
+    expect(undocumented.statusCode, 418);
+    expect(undocumented.rawBody, {'tea': true});
+  });
+
+  test('a body that does not match the schema is a decode error', () async {
+    final adapter = FakeTransport.json(200, {'id': 'seven', 'name': 'Rex'});
+    final result = await ClientSender(adapter).send(request, decodePet);
+    final error = result as DecodeError<Pet, Problem>;
+    expect(error.statusCode, 200);
+    expect(error.error.pointer, '/id');
+    expect(error.error.message, 'expected an integer, got a string');
+    expect(error.error.schema, 'Pet');
+    expect(error.rawBody, {'id': 'seven', 'name': 'Rex'});
+  });
+
+  test('malformed JSON is a decode error with its status', () async {
+    final broken = FakeTransport.text(200, '{"id": 7,', 'application/json');
+    final result = await ClientSender(broken).send(request, decodePet);
+    final error = result as DecodeError<Pet, Problem>;
+    expect(error.statusCode, 200);
+    expect(
+      error.error.message,
+      'expected a JSON body, got text that is not JSON',
+    );
+    expect(error.rawBody, '{"id": 7,');
+  });
+
+  test('JSON sent as text/plain is not guessed', () async {
+    final adapter = FakeTransport.text(
+      200,
+      '{"id": 7, "name": "Rex"}',
+      'text/plain',
+    );
+    final result = await ClientSender(adapter).send(request, decodePet);
+    final error = result as DecodeError<Pet, Problem>;
+    expect(error.error.message, 'expected an object, got a string');
+    expect(error.rawBody, '{"id": 7, "name": "Rex"}');
+  });
+
+  test('transport failures keep the TransportException', () async {
+    for (final kind in [
+      TransportExceptionKind.connection,
+      TransportExceptionKind.timeout,
+      TransportExceptionKind.other,
+    ]) {
+      final failure = TransportException(kind, 'failed', cause: 'adapter');
+      final adapter = FakeTransport((_) => throw failure);
+      final result = await ClientSender(adapter).send(request, decodePet);
+      final error = result as TransportError<Pet, Problem>;
+      expect(error.exception, same(failure));
+    }
+  });
+
+  test('an Exception while the body is read is a transport failure', () async {
+    final adapter = FakeTransport(
+      (_) => TransportResponse(
+        statusCode: 200,
+        body: Stream.error(const FormatException('broken')),
+      ),
+    );
+    final result = await ClientSender(adapter).send(request, decodePet);
+    final error = result as TransportError<Pet, Problem>;
+    expect(error.exception.kind, TransportExceptionKind.other);
+    expect(error.exception.cause, isA<FormatException>());
+  });
+
+  test('header entries with a null value are not sent', () async {
+    final adapter = FakeTransport.json(200, {'id': 7, 'name': 'Rex'});
+    await ClientSender(adapter).send(
+      request,
+      decodePet,
+      call: const CallOptions(headers: {'X-A': null, 'X-B': 'b'}),
+    );
+    final sent = adapter.requests.single;
+    expect(FakeTransport.header(sent, 'X-A'), isNull);
+    expect(FakeTransport.header(sent, 'X-B'), 'b');
+  });
+
+  test(
+    'the operation content type wins over one in CallOptions.headers',
+    () async {
+      final adapter = FakeTransport.json(200, {'id': 7, 'name': 'Rex'});
+      await ClientSender(adapter).send(
+        const OperationRequest(
+          getPet,
+          path: [PathParameter('petId', 7)],
+          body: {'name': 'Rex'},
+          contentType: 'application/json',
+        ),
+        decodePet,
+        call: const CallOptions(
+          headers: {'content-type': 'application/merge-patch+json', 'X-A': 'a'},
+        ),
+      );
+      final sent = adapter.requests.single;
+      expect(FakeTransport.header(sent, 'content-type'), 'application/json');
+      expect(FakeTransport.header(sent, 'X-A'), 'a');
+    },
+  );
+
+  test('cancellation is its own outcome', () async {
+    final adapter = FakeTransport.json(200, {'id': 7, 'name': 'Rex'});
+    final token = CancelSignal()..cancel('user left');
+    final result = await ClientSender(adapter).send(
+      request,
+      decodePet,
+      call: CallOptions(cancel: token),
+    );
+    expect(
+      (result as Cancelled<Pet, Problem>).exception.kind,
+      TransportExceptionKind.cancelled,
+    );
+    expect(adapter.requests, isEmpty);
+  });
+
+  test('bodies, content types, progress and response kinds', () async {
+    final adapter = FakeTransport.text(201, 'created', 'text/plain');
+    final sent = <int>[];
+    final result = await ClientSender(adapter).send(
+      const OperationRequest(
+        OperationInfo(
+          operationId: 'addPet',
+          method: 'POST',
+          pathTemplate: '/pets',
+        ),
+        body: {'name': 'Rex', 'tag': null},
+        contentType: 'application/json',
+        responseKind: .text,
+      ),
+      (r) => r.statusCode == 201
+          ? r.success<String, Never>(r.text)
+          : r.undocumented(),
+      call: CallOptions(onSendProgress: (count, _) => sent.add(count)),
+    );
+    expect((result as Success<String, Never>).data, 'created');
+    expect(adapter.bodies.single, '{"name":"Rex","tag":null}');
+    expect(adapter.requests.single.method, 'POST');
+    expect(
+      FakeTransport.header(adapter.requests.single, 'content-type'),
+      'application/json',
+    );
+    expect(sent, [25]);
+
+    final bytes = FakeTransport(
+      (_) => TransportResponse(
+        statusCode: 200,
+        body: Stream.value([1, 2, 3]),
+        headers: {
+          'content-type': ['application/octet-stream'],
+        },
+      ),
+    );
+    final download = await ClientSender(bytes).send(
+      const OperationRequest(
+        getPet,
+        path: [PathParameter('petId', 1)],
+        responseKind: .bytes,
+      ),
+      (r) => r.success<Uint8List, Never>(r.bytes),
+    );
+    expect((download as Success<Uint8List, Never>).data, [1, 2, 3]);
+  });
+
+  test('a success without a body has T = void', () async {
+    final adapter = FakeTransport((_) => FakeTransport.response('', 204));
+    final result = await ClientSender(adapter).send(
+      const OperationRequest(
+        OperationInfo(
+          operationId: 'deletePet',
+          method: 'DELETE',
+          pathTemplate: '/pets/1',
+        ),
+      ),
+      (r) =>
+          r.statusCode == 204 ? r.success<void, Never>(null) : r.undocumented(),
+    );
+    expect(result, isA<Success<void, Never>>());
+  });
+
+  test(
+    'a FormatException of the decoder is a decode error at the root',
+    () async {
+      // A user converter (R6.8) or Date.parse rejecting server data.
+      Result<DateTime, Problem> decode(RawResponse r) => switch (r.statusCode) {
+        200 => r.success(DateTime.parse(JsonReader.asString(r.json))),
+        404 => r.error(
+          Problem(int.parse(JsonReader.asString(r.json)).toString()),
+        ),
+        _ => r.undocumented(),
+      };
+      for (final (status, body) in [(200, 'soon'), (404, 'abc')]) {
+        final adapter = FakeTransport.json(status, body);
+        final result = await ClientSender(adapter).send(request, decode);
+        final error = result as DecodeError<DateTime, Problem>;
+        expect(error.statusCode, status);
+        expect(error.rawBody, body);
+        expect(error.error.pointer, '');
+        expect(error.error.expected, 'a value its decoder accepts');
+        expect(error.error.actual, startsWith('a value it rejected: '));
+        expect(error.headers, isNotEmpty);
+      }
+      final valid = await ClientSender(
+        FakeTransport.json(200, '2024-02-03T04:05:06Z'),
+      ).send(request, decode);
+      expect((valid as Success<DateTime, Problem>).data.year, 2024);
+    },
+  );
+
+  test('an Error of the decoder still reaches the caller', () async {
+    final adapter = FakeTransport.json(200, {'id': 7, 'name': 'Rex'});
+    final sender = ClientSender(adapter);
+    await expectLater(
+      sender.send<Pet, Problem>(request, (_) => throw StateError('bug')),
+      throwsA(isA<StateError>()),
+    );
+    await expectLater(
+      sender.send<Pet, Problem>(request, (_) => throw ArgumentError('bug')),
+      throwsA(isA<ArgumentError>()),
+    );
+  });
+}
diff --git a/packages/typed_openapi_client/test/dio/json_body_test.dart b/packages/typed_openapi_client/test/client/json_body_test.dart
similarity index 57%
rename from packages/typed_openapi_client/test/dio/json_body_test.dart
rename to packages/typed_openapi_client/test/client/json_body_test.dart
index cc33d04..7d7116c 100644
--- a/packages/typed_openapi_client/test/dio/json_body_test.dart
+++ b/packages/typed_openapi_client/test/client/json_body_test.dart
@@ -1,10 +1,9 @@
 import 'dart:convert';
 
-import 'package:dio/dio.dart';
 import 'package:test/test.dart';
 import 'package:typed_openapi_client/typed_openapi_client.dart';
 
-import '../helpers/fake_adapter.dart';
+import '../helpers/fake_transport.dart';
 
 void main() {
   const operation = OperationInfo(
@@ -17,11 +16,11 @@ void main() {
       r.statusCode == 204 ? r.success(null) : r.undocumented();
 
   /// Sends [body] as [contentType] and returns the adapter that saw it.
-  Future<FakeAdapter> send(Object? body, String? contentType) async {
-    final adapter = FakeAdapter(
-      (_) => ResponseBody.fromString('', 204),
+  Future<FakeTransport> send(Object? body, String? contentType) async {
+    final adapter = FakeTransport(
+      (_) => FakeTransport.response('', 204),
     );
-    await DioRequestSender(Dio()..httpClientAdapter = adapter).send(
+    await ClientSender(adapter).send(
       OperationRequest(operation, body: body, contentType: contentType),
       decodeVoid,
     );
@@ -52,14 +51,20 @@ void main() {
       test(name, () async {
         final adapter = await send(value, 'application/json');
         expect(adapter.bodies.single, jsonEncode(value));
-        expect(adapter.requests.single.contentType, 'application/json');
+        expect(
+          FakeTransport.header(adapter.requests.single, 'content-type'),
+          'application/json',
+        );
       });
     }
 
     test('a required nullable body that is null sends null', () async {
       final adapter = await send(null, 'application/json');
       expect(adapter.bodies.single, 'null');
-      expect(adapter.requests.single.contentType, 'application/json');
+      expect(
+        FakeTransport.header(adapter.requests.single, 'content-type'),
+        'application/json',
+      );
     });
 
     test('a +json media type is JSON as well', () async {
@@ -85,84 +90,16 @@ void main() {
     });
   });
 
-  group('Dio keeps what it encodes right', () {
-    test('an interceptor sees the map or list of a JSON body', () async {
-      final seen = <Object?>[];
-      final adapter = FakeAdapter((_) => ResponseBody.fromString('', 204));
-      final dio = Dio()
-        ..httpClientAdapter = adapter
-        ..interceptors.add(
-          InterceptorsWrapper(
-            onRequest: (options, handler) {
-              seen.add(options.data);
-              handler.next(options);
-            },
-          ),
-        );
-      final sender = DioRequestSender(dio);
-      for (final body in <Object?>[
-        {'name': 'Rex', 'tags': <Object?>[]},
-        [1, 2],
-        7,
-        true,
-      ]) {
-        await sender.send(
-          OperationRequest(
-            operation,
-            body: body,
-            contentType: 'application/merge-patch+json',
-          ),
-          decodeVoid,
-        );
-      }
-      expect(seen, [
-        {'name': 'Rex', 'tags': <Object?>[]},
-        [1, 2],
-        7,
-        true,
-      ]);
-      expect(adapter.bodies, [
-        '{"name":"Rex","tags":[]}',
-        '[1,2]',
-        '7',
-        'true',
-      ]);
-    });
-
-    test('an interceptor sees the string and null that are encoded', () async {
-      final seen = <Object?>[];
-      final dio = Dio()
-        ..httpClientAdapter = FakeAdapter(
-          (_) => ResponseBody.fromString('', 204),
-        )
-        ..interceptors.add(
-          InterceptorsWrapper(
-            onRequest: (options, handler) {
-              seen.add(options.data);
-              handler.next(options);
-            },
-          ),
-        );
-      final sender = DioRequestSender(dio);
-      for (final body in <Object?>['a"b', null]) {
-        await sender.send(
-          OperationRequest(
-            operation,
-            body: body,
-            contentType: 'application/json',
-          ),
-          decodeVoid,
-        );
-      }
-      expect(seen, [r'"a\"b"', 'null']);
-    });
-  });
+  group('Dio keeps what it encodes right', () {});
 
   group('a body that is not JSON stays as it is', () {
     test('text is sent unquoted', () async {
       final adapter = await send('hello "q"', 'text/plain');
       expect(adapter.bodies.single, 'hello "q"');
-      expect(adapter.requests.single.contentType, 'text/plain');
+      expect(
+        FakeTransport.header(adapter.requests.single, 'content-type'),
+        'text/plain',
+      );
     });
 
     for (final type in [
@@ -180,7 +117,10 @@ void main() {
           return;
         }
         expect(adapter.bodies.single, '');
-        expect(adapter.requests.single.contentType, isNull);
+        expect(
+          FakeTransport.header(adapter.requests.single, 'content-type'),
+          isNull,
+        );
         expect(
           adapter.requests.single.headers.keys,
           isNot(contains('content-type')),
@@ -191,7 +131,10 @@ void main() {
     test('no body and no content type sends nothing', () async {
       final adapter = await send(null, null);
       expect(adapter.bodies.single, '');
-      expect(adapter.requests.single.contentType, isNull);
+      expect(
+        FakeTransport.header(adapter.requests.single, 'content-type'),
+        isNull,
+      );
     });
   });
 }
diff --git a/packages/typed_openapi_client/test/dio/multipart_send_test.dart b/packages/typed_openapi_client/test/client/multipart_send_test.dart
similarity index 92%
rename from packages/typed_openapi_client/test/dio/multipart_send_test.dart
rename to packages/typed_openapi_client/test/client/multipart_send_test.dart
index ffd8a6b..db1b820 100644
--- a/packages/typed_openapi_client/test/dio/multipart_send_test.dart
+++ b/packages/typed_openapi_client/test/client/multipart_send_test.dart
@@ -1,11 +1,10 @@
 import 'dart:convert';
 import 'dart:typed_data';
 
-import 'package:dio/dio.dart';
 import 'package:test/test.dart';
 import 'package:typed_openapi_client/typed_openapi_client.dart';
 
-import '../helpers/fake_adapter.dart';
+import '../helpers/fake_transport.dart';
 
 void main() {
   const upload = OperationInfo(
@@ -17,13 +16,13 @@ void main() {
   Result<void, Never> decodeVoid(RawResponse r) =>
       r.statusCode == 204 ? r.success(null) : r.undocumented();
 
-  FakeAdapter noContent() =>
-      FakeAdapter((_) => ResponseBody.fromString('', 204));
+  FakeTransport noContent() =>
+      FakeTransport((_) => FakeTransport.response('', 204));
 
   /// Sends [parts] as a multipart body and returns the adapter that saw it.
-  Future<FakeAdapter> sendParts(List<MultipartPart> parts) async {
+  Future<FakeTransport> sendParts(List<MultipartPart> parts) async {
     final adapter = noContent();
-    await DioRequestSender(Dio()..httpClientAdapter = adapter).send(
+    await ClientSender(adapter).send(
       OperationRequest(
         upload,
         body: MultipartBody(parts),
@@ -35,9 +34,7 @@ void main() {
   }
 
   Future<Result<void, Never>> send(OperationRequest request) =>
-      DioRequestSender(
-        Dio()..httpClientAdapter = noContent(),
-      ).send(request, decodeVoid);
+      ClientSender(noContent()).send(request, decodeVoid);
 
   FileUpload file([String content = 'x', String? contentType]) =>
       FileUpload.bytes(
@@ -213,7 +210,7 @@ void main() {
   group('a form value', () {
     test('that is not ASCII or is reserved is percent-encoded', () async {
       final adapter = noContent();
-      await DioRequestSender(Dio()..httpClientAdapter = adapter).send(
+      await ClientSender(adapter).send(
         const OperationRequest(
           upload,
           body: FormBody({'q': 'Київ & co+1', 'r': 'a=b'}),
diff --git a/packages/typed_openapi_client/test/dio/open_events_test.dart b/packages/typed_openapi_client/test/client/open_events_test.dart
similarity index 67%
rename from packages/typed_openapi_client/test/dio/open_events_test.dart
rename to packages/typed_openapi_client/test/client/open_events_test.dart
index 65bc7d4..d943b1e 100644
--- a/packages/typed_openapi_client/test/dio/open_events_test.dart
+++ b/packages/typed_openapi_client/test/client/open_events_test.dart
@@ -6,11 +6,10 @@ import 'dart:convert';
 import 'dart:io';
 import 'dart:typed_data';
 
-import 'package:dio/dio.dart';
 import 'package:test/test.dart';
 import 'package:typed_openapi_client/typed_openapi_client.dart';
 
-import '../helpers/fake_adapter.dart';
+import '../helpers/fake_transport.dart';
 
 /// The data of one event.
 final class Delta {
@@ -53,21 +52,21 @@ void main() {
       };
 
   Future<Result<Stream<SseItem<Delta>>, Problem>> open(
-    FakeAdapter adapter, {
+    FakeTransport adapter, {
     CallOptions? call,
-  }) => DioRequestSender(Dio()..httpClientAdapter = adapter).openEvents(
+  }) => ClientSender(adapter).openEvents(
     chat,
     Delta.fromEvent,
     decodeError,
     call: call,
   );
 
-  ResponseBody eventStream(Stream<Uint8List> body, [int status = 200]) =>
-      ResponseBody(
-        body,
-        status,
+  TransportResponse eventStream(Stream<List<int>> body, [int status = 200]) =>
+      TransportResponse(
+        statusCode: status,
+        body: body,
         headers: {
-          Headers.contentTypeHeader: ['text/event-stream'],
+          'content-type': ['text/event-stream'],
         },
       );
 
@@ -75,13 +74,13 @@ void main() {
     SseEvent(:final data) => data.text,
     SseDecodeError(:final error) => 'error ${error.pointer}',
     SseReconnecting(:final attempt) => 'reconnecting $attempt',
-    SseDisconnected(cause: final DioException cause) =>
-      'end ${cause.type.name}',
+    SseDisconnected(cause: final TransportException cause) =>
+      'end ${cause.kind.name}',
     SseDisconnected(:final cause) => 'end ${cause ?? 'closed'}',
   };
 
   test('a 2xx opens a stream of decoded events', () async {
-    final adapter = FakeAdapter(
+    final adapter = FakeTransport(
       (_) => eventStream(
         Stream.value(
           utf8.encode(
@@ -100,15 +99,15 @@ void main() {
       'end closed',
     ]);
     final sent = adapter.requests.single;
-    expect(sent.headers['Accept'], 'text/event-stream');
-    expect(sent.responseType, ResponseType.stream);
-    expect(OperationInfo.of(sent)?.operationId, 'chat');
+    expect(FakeTransport.header(sent, 'Accept'), 'text/event-stream');
+    expect(sent.isEventStream, isTrue);
+    expect(sent.operation.operationId, 'chat');
     expect(adapter.bodies.single, '{"prompt":"hi"}');
   });
 
   test('a dropped connection is the last item, not an error', () async {
     final body = StreamController<Uint8List>();
-    final result = await open(FakeAdapter((_) => eventStream(body.stream)));
+    final result = await open(FakeTransport((_) => eventStream(body.stream)));
     final items = <String>[];
     final done = Completer<void>();
     (result as Success<Stream<SseItem<Delta>>, Problem>).data.listen(
@@ -126,10 +125,10 @@ void main() {
 
   test('cancelling the request ends the stream with the cancel', () async {
     final body = StreamController<Uint8List>();
-    final token = CancelToken();
+    final token = CancelSignal();
     final result = await open(
-      FakeAdapter((_) => eventStream(body.stream)),
-      call: CallOptions(cancelToken: token),
+      FakeTransport((_) => eventStream(body.stream)),
+      call: CallOptions(cancel: token),
     );
     final items = (result as Success<Stream<SseItem<Delta>>, Problem>).data
         .map(describe)
@@ -137,22 +136,16 @@ void main() {
     body.add(utf8.encode('data: {"text": "a"}\n\n'));
     await Future<void>.delayed(Duration.zero);
     token.cancel('user left');
-    expect(await items, ['a', 'end cancel']);
+    expect(await items, ['a', 'end cancelled']);
     await body.close();
   });
 
   test('error statuses read the whole body and decode it', () async {
-    ResponseBody errorBody(int status, String text, String type) =>
-        ResponseBody(
-          Stream.value(Uint8List.fromList(utf8.encode(text))),
-          status,
-          headers: {
-            Headers.contentTypeHeader: [type],
-          },
-        );
+    TransportResponse errorBody(int status, String text, String type) =>
+        FakeTransport.response(text, status, type);
 
     final documented = await open(
-      FakeAdapter(
+      FakeTransport(
         (_) => errorBody(404, '{"code": "NO_MODEL"}', 'application/json'),
       ),
     );
@@ -162,7 +155,7 @@ void main() {
     );
 
     final undocumented = await open(
-      FakeAdapter((_) => errorBody(502, 'Bad gateway', 'text/html')),
+      FakeTransport((_) => errorBody(502, 'Bad gateway', 'text/html')),
     );
     expect(
       (undocumented as UndocumentedStatus).rawBody,
@@ -170,20 +163,20 @@ void main() {
     );
 
     final malformed = await open(
-      FakeAdapter((_) => errorBody(404, '{"code":', 'application/json')),
+      FakeTransport((_) => errorBody(404, '{"code":', 'application/json')),
     );
     final error = malformed as DecodeError;
     expect((error.statusCode, error.rawBody), (404, '{"code":'));
 
     final mismatch = await open(
-      FakeAdapter((_) => errorBody(404, '{"code": 1}', 'application/json')),
+      FakeTransport((_) => errorBody(404, '{"code": 1}', 'application/json')),
     );
     expect((mismatch as DecodeError).error.pointer, '/code');
   });
 
   test('cancelling the subscription closes the connection', () async {
     final body = StreamController<Uint8List>();
-    final adapter = FakeAdapter((_) => eventStream(body.stream));
+    final adapter = FakeTransport((_) => eventStream(body.stream));
     final result = await open(adapter);
     final items = <String>[];
     final subscription = (result as Success<Stream<SseItem<Delta>>, Problem>)
@@ -203,36 +196,36 @@ void main() {
 
   test('a user cancel still ends the stream with SseDisconnected', () async {
     final body = StreamController<Uint8List>();
-    final token = CancelToken();
-    final adapter = FakeAdapter((_) => eventStream(body.stream));
-    final result = await open(adapter, call: CallOptions(cancelToken: token));
+    final token = CancelSignal();
+    final adapter = FakeTransport((_) => eventStream(body.stream));
+    final result = await open(adapter, call: CallOptions(cancel: token));
     final items = (result as Success<Stream<SseItem<Delta>>, Problem>).data
         .map(describe)
         .toList();
     token.cancel();
-    expect(await items, ['end cancel']);
+    expect(await items, ['end cancelled']);
     expect(adapter.cancelsFired.single, isTrue);
     await body.close();
   });
 
   test('a token cancelled before the call is Cancelled', () async {
-    final token = CancelToken()..cancel();
-    final adapter = FakeAdapter(
+    final token = CancelSignal()..cancel();
+    final adapter = FakeTransport(
       (_) => eventStream(Stream.value(utf8.encode('data: {}\n\n'))),
     );
-    final result = await open(adapter, call: CallOptions(cancelToken: token));
+    final result = await open(adapter, call: CallOptions(cancel: token));
     expect(result, isA<Cancelled>());
   });
 
   test('a body read failure on an error status is a TransportError', () async {
     final body = StreamController<Uint8List>();
     final pending = open(
-      FakeAdapter(
-        (_) => ResponseBody(
-          body.stream,
-          500,
+      FakeTransport(
+        (_) => TransportResponse(
+          statusCode: 500,
+          body: body.stream,
           headers: {
-            Headers.contentTypeHeader: ['text/html'],
+            'content-type': ['text/html'],
           },
         ),
       ),
@@ -242,15 +235,17 @@ void main() {
       ..addError(const SocketException('reset'));
     final result = await pending;
     final exception = (result as TransportError).exception;
-    expect(exception.type, DioExceptionType.unknown);
-    expect(exception.error, isA<SocketException>());
+    expect(exception.kind, TransportExceptionKind.other);
+    expect(exception.cause, isA<SocketException>());
     await body.close();
   });
 
   test('an Error while reading the body still propagates', () async {
     final body = StreamController<Uint8List>();
     final pending = open(
-      FakeAdapter((_) => ResponseBody(body.stream, 500)),
+      FakeTransport(
+        (_) => TransportResponse(statusCode: 500, body: body.stream),
+      ),
     );
     body.addError(StateError('bug'));
     await expectLater(pending, throwsStateError);
@@ -259,13 +254,12 @@ void main() {
 
   test('an Error in decodeEvent is a stream error and closes it', () async {
     final body = StreamController<Uint8List>();
-    final adapter = FakeAdapter((_) => eventStream(body.stream));
-    final result = await DioRequestSender(Dio()..httpClientAdapter = adapter)
-        .openEvents<Delta, Problem>(
-          chat,
-          (message) => throw StateError('bug'),
-          decodeError,
-        );
+    final adapter = FakeTransport((_) => eventStream(body.stream));
+    final result = await ClientSender(adapter).openEvents<Delta, Problem>(
+      chat,
+      (message) => throw StateError('bug'),
+      decodeError,
+    );
     final items = <SseItem<Delta>>[];
     final errors = <Object>[];
     final done = Completer<void>();
@@ -285,7 +279,7 @@ void main() {
 
   test('a status outside streamStatuses is decoded like a response', () async {
     final result = await open(
-      FakeAdapter(
+      FakeTransport(
         (_) => eventStream(
           Stream.value(utf8.encode('data: {"text": "a"}\n\n')),
           201,
@@ -299,24 +293,21 @@ void main() {
 
   test('transport failures before the stream opens', () async {
     final result = await open(
-      FakeAdapter(
-        (o) => throw DioException.connectionError(
-          requestOptions: o,
-          reason: 'refused',
-        ),
+      FakeTransport(
+        (_) => throw const TransportException(.connection, 'refused'),
       ),
     );
     expect(
-      (result as TransportError).exception.type,
-      DioExceptionType.connectionError,
+      (result as TransportError).exception.kind,
+      TransportExceptionKind.connection,
     );
   });
 
   test('an empty streamStatuses is a bug of the generated code', () async {
-    final adapter = FakeAdapter((_) => eventStream(const Stream.empty()));
+    final adapter = FakeTransport((_) => eventStream(const Stream.empty()));
     await expectLater(
-      DioRequestSender(
-        Dio()..httpClientAdapter = adapter,
+      ClientSender(
+        adapter,
       ).openEvents<Delta, Problem>(
         const OperationRequest(
           OperationInfo(
@@ -338,34 +329,4 @@ void main() {
     );
     expect(adapter.requests, isEmpty);
   });
-
-  test(
-    'on the web the default adapter is refused with an explanation',
-    () async {
-      final web = DioRequestSender(Dio(), isWeb: true);
-      final result = await web.openEvents(chat, Delta.fromEvent, decodeError);
-      final error = result as TransportError;
-      expect(error.exception.message, DioRequestSender.webStreamingMessage);
-      expect(error.exception.error, isA<UnsupportedError>());
-      expect(
-        OperationInfo.of(error.exception.requestOptions)?.operationId,
-        'chat',
-      );
-
-      final adapter = FakeAdapter(
-        (_) =>
-            eventStream(Stream.value(utf8.encode('data: {"text": "a"}\n\n'))),
-      );
-      final custom = DioRequestSender(
-        Dio()..httpClientAdapter = adapter,
-        isWeb: true,
-      );
-      final opened = await custom.openEvents(
-        chat,
-        Delta.fromEvent,
-        decodeError,
-      );
-      expect(opened, isA<Success<Stream<SseItem<Delta>>, Problem>>());
-    },
-  );
 }
diff --git a/packages/typed_openapi_client/test/generated_client_test.dart b/packages/typed_openapi_client/test/generated_client_test.dart
index 315a071..451b8b2 100644
--- a/packages/typed_openapi_client/test/generated_client_test.dart
+++ b/packages/typed_openapi_client/test/generated_client_test.dart
@@ -1,10 +1,9 @@
 import 'dart:convert';
 
-import 'package:dio/dio.dart';
 import 'package:test/test.dart';
 import 'package:typed_openapi_client/typed_openapi_client.dart';
 
-import 'helpers/fake_adapter.dart';
+import 'helpers/fake_transport.dart';
 import 'helpers/pets_api.dart';
 
 /// A hand-written fake in another library, as a user test writes one.
@@ -51,13 +50,9 @@ void main() {
     'unknown': 'ignored',
   };
 
-  Dio dioWith(FakeAdapter adapter) =>
-      Dio(BaseOptions(baseUrl: 'https://api.test'))
-        ..httpClientAdapter = adapter;
-
   test('a generated GET decodes a model and its nested values', () async {
-    final adapter = FakeAdapter.json(200, petJson);
-    final api = PetsApi(dioWith(adapter));
+    final adapter = FakeTransport.json(200, petJson);
+    final api = PetsApi(adapter);
     final result = await api.getPetById(petId: 7, fields: ['id', 'name']);
     final pet = switch (result) {
       Success(:final data) => data,
@@ -72,17 +67,17 @@ void main() {
       '"tags":[{"name":"good"}],"metadata":{"source":"shelter","score":1.5}}',
     );
     expect(
-      adapter.requests.single.uri.toString(),
-      'https://api.test/pets/7?fields=id,name',
+      adapter.requests.single.target,
+      '/pets/7?fields=id,name',
     );
   });
 
   test('a date property decodes and encodes as a full-date', () async {
-    final adapter = FakeAdapter.json(200, {
+    final adapter = FakeTransport.json(200, {
       ...petJson,
       'birthday': '2019-12-31',
     });
-    final result = await PetsApi(dioWith(adapter)).getPetById(petId: 7);
+    final result = await PetsApi(adapter).getPetById(petId: 7);
     final pet = switch (result) {
       Success(:final data) => data,
       Failure() => fail('expected a success, got $result'),
@@ -94,11 +89,11 @@ void main() {
   test(
     'a date-time sent for a date is a decode error at the property',
     () async {
-      final adapter = FakeAdapter.json(200, {
+      final adapter = FakeTransport.json(200, {
         ...petJson,
         'birthday': '2019-12-31T00:00:00Z',
       });
-      final result = await PetsApi(dioWith(adapter)).getPetById(petId: 7);
+      final result = await PetsApi(adapter).getPetById(petId: 7);
       expect(
         result,
         isA<DecodeError<Pet, ApiError>>()
@@ -111,11 +106,11 @@ void main() {
   );
 
   test('the caller switches over every outcome', () async {
-    final adapter = FakeAdapter.json(200, {
+    final adapter = FakeTransport.json(200, {
       ...petJson,
       'tags': [{}],
     });
-    final result = await PetsApi(dioWith(adapter)).getPetById(petId: 7);
+    final result = await PetsApi(adapter).getPetById(petId: 7);
     final message = switch (result) {
       Success(:final data) => data.name,
       HttpError(:final body) => body.code,
@@ -126,8 +121,8 @@ void main() {
   });
 
   test('a generated PATCH sends only the fields that are set', () async {
-    final adapter = FakeAdapter((_) => ResponseBody.fromString('', 204));
-    final result = await PetsApi(dioWith(adapter)).updatePet(
+    final adapter = FakeTransport((_) => FakeTransport.response('', 204));
+    final result = await PetsApi(adapter).updatePet(
       petId: 7,
       body: const UpdatePet(name: .value('Rex'), tag: .nullValue()),
     );
@@ -137,25 +132,23 @@ void main() {
   });
 
   test('a documented error status is typed', () async {
-    final adapter = FakeAdapter.json(409, {'code': 'CONFLICT'});
+    final adapter = FakeTransport.json(409, {'code': 'CONFLICT'});
     final result = await PetsApi(
-      dioWith(adapter),
+      adapter,
     ).updatePet(petId: 7, body: const UpdatePet());
     expect((result as HttpError<void, ApiError>).body.code, 'CONFLICT');
     expect(adapter.bodies.single, '{}');
   });
 
   test('a generated event stream yields typed items', () async {
-    final adapter = FakeAdapter(
-      (_) => ResponseBody(
-        Stream.value(utf8.encode('data: {"name": "Max"}\n\n')),
+    final adapter = FakeTransport(
+      (_) => FakeTransport.response(
+        'data: {"name": "Max"}\n\n',
         200,
-        headers: {
-          Headers.contentTypeHeader: ['text/event-stream'],
-        },
+        'text/event-stream',
       ),
     );
-    final result = await PetsApi(dioWith(adapter)).watchPet(petId: 7);
+    final result = await PetsApi(adapter).watchPet(petId: 7);
     final names = switch (result) {
       Success(:final data) =>
         await data
@@ -174,8 +167,8 @@ void main() {
   });
 
   test('an operation without documented errors still has failures', () async {
-    final adapter = FakeAdapter.json(503, {'message': 'down'});
-    final result = await PetsApi(dioWith(adapter)).watchPet(petId: 7);
+    final adapter = FakeTransport.json(503, {'message': 'down'});
+    final result = await PetsApi(adapter).watchPet(petId: 7);
     final outcome = switch (result) {
       Success() => 'stream',
       Failure() => 'failed',
diff --git a/packages/typed_openapi_client/test/helpers/fake_transport.dart b/packages/typed_openapi_client/test/helpers/fake_transport.dart
new file mode 100644
index 0000000..498de80
--- /dev/null
+++ b/packages/typed_openapi_client/test/helpers/fake_transport.dart
@@ -0,0 +1,107 @@
+import 'dart:async';
+import 'dart:convert';
+
+import 'package:typed_openapi_client/typed_openapi_client.dart';
+
+/// A transport that answers from memory, so tests never touch the network.
+/// It records every request with its body text.
+final class FakeTransport implements ClientTransport {
+  /// Answers every request with [respond].
+  FakeTransport(this.respond);
+
+  /// A JSON response with [status].
+  factory FakeTransport.json(int status, Object? body) => FakeTransport(
+    (_) => response(jsonEncode(body), status, 'application/json'),
+  );
+
+  /// A response with [status], [text] and [contentType].
+  factory FakeTransport.text(int status, String text, String contentType) =>
+      FakeTransport((_) => response(text, status, contentType));
+
+  /// A response with [status] whose body is [text] in UTF-8, of
+  /// [contentType] when it is given.
+  static TransportResponse response(
+    String text,
+    int status, [
+    String? contentType,
+  ]) => TransportResponse(
+    statusCode: status,
+    body: Stream.value(utf8.encode(text)),
+    headers: {
+      'content-type': ?(contentType == null ? null : [contentType]),
+    },
+  );
+
+  /// The value of the header [name] of [request] (any case), its values
+  /// joined with `, `; null when the request has none.
+  static String? header(TransportRequest request, String name) {
+    for (final MapEntry(:key, :value) in request.headers.entries) {
+      if (key.toLowerCase() == name.toLowerCase()) return value.join(', ');
+    }
+    return null;
+  }
+
+  /// Builds the response, or throws a [TransportException].
+  final TransportResponse Function(TransportRequest request) respond;
+
+  /// The requests seen, in order.
+  final List<TransportRequest> requests = [];
+
+  /// The request bodies seen, as text.
+  final List<String> bodies = [];
+
+  /// Per request, whether its cancel signal fired: the request was
+  /// cancelled and a real transport would close the connection.
+  final List<bool> cancelsFired = [];
+
+  @override
+  Future<TransportResponse> send(TransportRequest request) async {
+    requests.add(request);
+    final index = cancelsFired.length;
+    cancelsFired.add(false);
+    request.cancel?.whenCancelled.then((_) => cancelsFired[index] = true);
+    final bytes = <int>[];
+    if (request.body case final body?) {
+      await for (final chunk in body) {
+        bytes.addAll(chunk);
+      }
+    }
+    bodies.add(utf8.decode(bytes, allowMalformed: true));
+    return cancellable(respond(request), request.cancel);
+  }
+
+  /// [response] whose body fails with a [TransportException] of kind
+  /// cancelled when [cancel] fires before it ends, as a real transport
+  /// aborts the connection.
+  static TransportResponse cancellable(
+    TransportResponse response,
+    CancelSignal? cancel,
+  ) {
+    if (cancel == null) return response;
+    final body = StreamController<List<int>>(sync: true);
+    StreamSubscription<List<int>>? source;
+    body
+      ..onListen = () {
+        source = response.body.listen(
+          body.add,
+          onError: body.addError,
+          onDone: body.close,
+        );
+        cancel.whenCancelled.then((_) {
+          if (body.isClosed) return;
+          source?.cancel();
+          body
+            ..addError(const TransportException(.cancelled, 'cancelled'))
+            ..close();
+        });
+      }
+      ..onPause = (() => source?.pause())
+      ..onResume = (() => source?.resume())
+      ..onCancel = (() => source?.cancel());
+    return TransportResponse(
+      statusCode: response.statusCode,
+      headers: response.headers,
+      body: body.stream,
+    );
+  }
+}
diff --git a/packages/typed_openapi_client/test/helpers/gated_transport.dart b/packages/typed_openapi_client/test/helpers/gated_transport.dart
new file mode 100644
index 0000000..61476dd
--- /dev/null
+++ b/packages/typed_openapi_client/test/helpers/gated_transport.dart
@@ -0,0 +1,50 @@
+import 'dart:async';
+
+import 'package:typed_openapi_client/typed_openapi_client.dart';
+
+import 'fake_transport.dart';
+
+/// A transport whose answers a test can hold back: [respond] is called
+/// with the request and its index and may wait on a gate. It tells when a
+/// request started and whether it was cancelled, and a cancel before the
+/// answer fails the request as a real transport does.
+final class GatedTransport implements ClientTransport {
+  /// Answers the request number `index` with the future [respond] returns.
+  GatedTransport(this.respond);
+
+  /// Builds the response of a request, possibly later.
+  final Future<TransportResponse> Function(TransportRequest request, int index)
+  respond;
+
+  /// The requests seen, in order.
+  final List<TransportRequest> requests = [];
+
+  /// Per request, whether its cancel signal fired.
+  final List<bool> cancelsFired = [];
+
+  final Map<int, Completer<void>> _started = {};
+
+  /// Completes when the request number [index] reaches the transport.
+  Future<void> started(int index) =>
+      (_started[index] ??= Completer<void>()).future;
+
+  @override
+  Future<TransportResponse> send(TransportRequest request) {
+    final index = requests.length;
+    requests.add(request);
+    cancelsFired.add(false);
+    final started = _started[index] ??= Completer<void>();
+    if (!started.isCompleted) started.complete();
+    final answer = respond(
+      request,
+      index,
+    ).then((r) => FakeTransport.cancellable(r, request.cancel));
+    final cancel = request.cancel;
+    if (cancel == null) return answer;
+    final cancelled = cancel.whenCancelled.then<TransportResponse>((_) {
+      cancelsFired[index] = true;
+      throw TransportException(.cancelled, 'cancelled: ${cancel.reason}');
+    });
+    return Future.any([answer, cancelled]);
+  }
+}
diff --git a/packages/typed_openapi_client/test/helpers/pets_api.dart b/packages/typed_openapi_client/test/helpers/pets_api.dart
index 3715469..e089aad 100644
--- a/packages/typed_openapi_client/test/helpers/pets_api.dart
+++ b/packages/typed_openapi_client/test/helpers/pets_api.dart
@@ -1,6 +1,5 @@
 // Code in the shape the generator (M8, M9, M10) is expected to emit, to
 // check that the runtime API composes. Illustrative, not a contract.
-import 'package:dio/dio.dart';
 import 'package:typed_openapi_client/typed_openapi_client.dart';
 
 /// `components.schemas.Tag`.
@@ -128,10 +127,10 @@ final class PetChange {
 
 /// The `pets` tag: a plain class, so `implements PetsApi` mocks it (R10.7).
 class PetsApi {
-  /// Calls the API through [dio], used as is.
-  PetsApi(Dio dio) : _sender = DioRequestSender(dio);
+  /// Calls the API through [transport].
+  PetsApi(ClientTransport transport) : _sender = ClientSender(transport);
 
-  final DioRequestSender _sender;
+  final ClientSender _sender;
 
   static const _getPetById = OperationInfo(
     operationId: 'getPetById',
diff --git a/packages/typed_openapi_client/test/helpers/watch_stream.dart b/packages/typed_openapi_client/test/helpers/watch_stream.dart
index 2a9022a..b4bec24 100644
--- a/packages/typed_openapi_client/test/helpers/watch_stream.dart
+++ b/packages/typed_openapi_client/test/helpers/watch_stream.dart
@@ -1,10 +1,6 @@
-import 'dart:convert';
-import 'dart:typed_data';
-
-import 'package:dio/dio.dart';
 import 'package:typed_openapi_client/typed_openapi_client.dart';
 
-import 'fake_adapter.dart';
+import 'fake_transport.dart';
 
 /// Opens event streams of a `GET /w` operation, for tests of reconnection.
 final class WatchStream {
@@ -13,16 +9,11 @@ final class WatchStream {
   WatchStream(this.adapter, {this.maxAttempts = 5, this.ignorePings = false});
 
   /// An event-stream response with [text] that then closes.
-  static ResponseBody response(String text, [int status = 200]) => ResponseBody(
-    Stream.value(Uint8List.fromList(utf8.encode(text))),
-    status,
-    headers: {
-      Headers.contentTypeHeader: ['text/event-stream'],
-    },
-  );
+  static TransportResponse response(String text, [int status = 200]) =>
+      FakeTransport.response(text, status, 'text/event-stream');
 
-  /// The adapter every connection goes through.
-  final FakeAdapter adapter;
+  /// The transport every connection goes through.
+  final FakeTransport adapter;
 
   /// [SseOptions.maxAttempts] of the call.
   final int maxAttempts;
@@ -36,34 +27,34 @@ final class WatchStream {
 
   /// The items of the stream, opened with reconnection on.
   Future<List<SseItem<String>>> items() async {
-    final result = await DioRequestSender(Dio()..httpClientAdapter = adapter)
-        .openEvents<String, Never>(
-          const OperationRequest(
-            OperationInfo(operationId: 'w', method: 'GET', pathTemplate: '/w'),
-            streamStatuses: {200, 204},
-          ),
-          (m) => switch (m.event) {
-            'ping' when ignorePings => throw const SseEventIgnored(),
-            'bad' => throw JsonDecodeException(
-              expected: 'a good event',
-              actual: 'a bad one',
-            ),
-            _ => m.data,
-          },
-          (r) => r.undocumented(),
-          call: CallOptions(
-            sse: SseOptions(
-              reconnect: true,
-              maxAttempts: maxAttempts,
-              wait: (delay) async => waits.add(delay),
-            ),
-          ),
-        );
+    final result = await ClientSender(adapter).openEvents<String, Never>(
+      const OperationRequest(
+        OperationInfo(operationId: 'w', method: 'GET', pathTemplate: '/w'),
+        streamStatuses: {200, 204},
+      ),
+      (m) => switch (m.event) {
+        'ping' when ignorePings => throw const SseEventIgnored(),
+        'bad' => throw JsonDecodeException(
+          expected: 'a good event',
+          actual: 'a bad one',
+        ),
+        _ => m.data,
+      },
+      (r) => r.undocumented(),
+      call: CallOptions(
+        sse: SseOptions(
+          reconnect: true,
+          maxAttempts: maxAttempts,
+          wait: (delay) async => waits.add(delay),
+        ),
+      ),
+    );
     return (result as Success<Stream<SseItem<String>>, Never>).data.toList();
   }
 
   /// The `Last-Event-ID` header of each request, null when absent.
   List<Object?> get lastEventIds => [
-    for (final request in adapter.requests) request.headers['Last-Event-ID'],
+    for (final request in adapter.requests)
+      FakeTransport.header(request, 'Last-Event-ID'),
   ];
 }
diff --git a/packages/typed_openapi_client/test/quality/size_limits_test.dart b/packages/typed_openapi_client/test/quality/size_limits_test.dart
index 8672952..b1edbd5 100644
--- a/packages/typed_openapi_client/test/quality/size_limits_test.dart
+++ b/packages/typed_openapi_client/test/quality/size_limits_test.dart
@@ -20,7 +20,6 @@ import '../helpers/size_limits.dart';
 /// they were listed. Keep the entries sorted.
 const Map<String, int> _fileAllowlist = {
   'lib/src/json/json_reader.dart': 422,
-  'test/dio/dio_request_sender_test.dart': 537,
   'test/json/json_reader_test.dart': 531,
 };
 
@@ -30,7 +29,6 @@ const Set<String> _permanent = {};
 /// Methods over 40 lines (`path#Type.name`), with the lines they had when
 /// they were listed. Keep the entries sorted.
 const Map<String, int> _methodAllowlist = {
-  'lib/src/dio/dio_request_sender.dart#DioRequestSender.openEvents': 51,
   'lib/src/json/json_reader.dart#JsonReader.listOf': 48,
 };
 
diff --git a/packages/typed_openapi_client/test/request/operation_request_test.dart b/packages/typed_openapi_client/test/request/operation_request_test.dart
index 217c17b..39a4d60 100644
--- a/packages/typed_openapi_client/test/request/operation_request_test.dart
+++ b/packages/typed_openapi_client/test/request/operation_request_test.dart
@@ -1,7 +1,6 @@
 import 'dart:convert';
 import 'dart:typed_data';
 
-import 'package:dio/dio.dart';
 import 'package:test/test.dart';
 import 'package:typed_openapi_client/typed_openapi_client.dart';
 
@@ -14,18 +13,7 @@ void main() {
   );
 
   group('OperationInfo', () {
-    test('is found in the extra map of a request', () {
-      expect(
-        OperationInfo.of(
-          RequestOptions(extra: {OperationInfo.extraKey: operation}),
-        ),
-        operation,
-      );
-      expect(OperationInfo.of(RequestOptions(extra: {'other': 1})), isNull);
-      expect(
-        OperationInfo.of(RequestOptions(extra: {OperationInfo.extraKey: 'x'})),
-        isNull,
-      );
+    test('prints its method, path and id', () {
       expect(
         '$operation',
         'GET /pets/{petId}/tags{;filter}/{kind} (listPetTags)',
diff --git a/packages/typed_openapi_client/test/result/result_test.dart b/packages/typed_openapi_client/test/result/result_test.dart
index f669e4f..146605c 100644
--- a/packages/typed_openapi_client/test/result/result_test.dart
+++ b/packages/typed_openapi_client/test/result/result_test.dart
@@ -1,9 +1,7 @@
-import 'package:dio/dio.dart';
 import 'package:test/test.dart';
 import 'package:typed_openapi_client/typed_openapi_client.dart';
 
 void main() {
-  final options = RequestOptions(path: '/pets');
   final failures = <Failure<int, String>>[
     const HttpError('not found', statusCode: 404),
     const UndocumentedStatus(statusCode: 418, rawBody: 'teapot'),
@@ -17,12 +15,12 @@ void main() {
       statusCode: 200,
       rawBody: {'id': 'x'},
     ),
-    TransportError(
-      DioException.connectionError(requestOptions: options, reason: 'refused'),
+    const TransportError(
+      TransportException(.connection, 'refused'),
       StackTrace.empty,
     ),
-    Cancelled(
-      DioException.requestCancelled(requestOptions: options, reason: 'left'),
+    const Cancelled(
+      TransportException(.cancelled, 'left'),
       StackTrace.empty,
     ),
   ];
@@ -32,7 +30,7 @@ void main() {
     HttpError(:final statusCode, :final body) => '$statusCode $body',
     UndocumentedStatus(:final statusCode) => 'undocumented $statusCode',
     DecodeError(:final error) => 'decode ${error.pointer}',
-    TransportError(:final exception) => 'transport ${exception.type.name}',
+    TransportError(:final exception) => 'transport ${exception.kind.name}',
     Cancelled() => 'cancelled',
   };
 
@@ -49,7 +47,7 @@ void main() {
       '404 not found',
       'undocumented 418',
       'decode /id',
-      'transport connectionError',
+      'transport connection',
       'cancelled',
     ]);
   });
@@ -67,7 +65,7 @@ void main() {
       'UndocumentedStatus(418)',
       'DecodeError(200: JsonDecodeException: expected an integer, '
           'got a string at /id in Pet)',
-      'TransportError(connectionError)',
+      'TransportError(connection)',
       'Cancelled',
     ]);
   });
diff --git a/packages/typed_openapi_client/test/sse/sse_event_id_test.dart b/packages/typed_openapi_client/test/sse/sse_event_id_test.dart
index 3b12bc4..da3863c 100644
--- a/packages/typed_openapi_client/test/sse/sse_event_id_test.dart
+++ b/packages/typed_openapi_client/test/sse/sse_event_id_test.dart
@@ -1,7 +1,7 @@
 import 'package:test/test.dart';
 import 'package:typed_openapi_client/typed_openapi_client.dart';
 
-import '../helpers/fake_adapter.dart';
+import '../helpers/fake_transport.dart';
 import '../helpers/watch_stream.dart';
 
 void main() {
@@ -17,7 +17,7 @@ void main() {
   WatchStream watch(List<String> bodies, {int maxAttempts = 5}) {
     var next = 0;
     return WatchStream(
-      FakeAdapter(
+      FakeTransport(
         (_) => next < bodies.length
             ? WatchStream.response(bodies[next++])
             : WatchStream.response('', 204),
diff --git a/packages/typed_openapi_client/test/sse/sse_event_ignored_test.dart b/packages/typed_openapi_client/test/sse/sse_event_ignored_test.dart
index d810653..8356bfc 100644
--- a/packages/typed_openapi_client/test/sse/sse_event_ignored_test.dart
+++ b/packages/typed_openapi_client/test/sse/sse_event_ignored_test.dart
@@ -1,21 +1,13 @@
 import 'dart:convert';
-import 'dart:typed_data';
-
-import 'package:dio/dio.dart';
 
 import 'package:test/test.dart';
 import 'package:typed_openapi_client/typed_openapi_client.dart';
 
-import '../helpers/fake_adapter.dart';
+import '../helpers/fake_transport.dart';
 
 /// An event-stream response with [text] that then closes.
-ResponseBody _stream(String text, [int status = 200]) => ResponseBody(
-  Stream.value(Uint8List.fromList(utf8.encode(text))),
-  status,
-  headers: {
-    Headers.contentTypeHeader: ['text/event-stream'],
-  },
-);
+TransportResponse _stream(String text, [int status = 200]) =>
+    FakeTransport.response(text, status, 'text/event-stream');
 
 void main() {
   test('an event the decoder ignores is not an item', () async {
@@ -44,29 +36,28 @@ void main() {
 
   test('the id of an ignored event is the one a reconnection sends', () async {
     var next = 0;
-    final adapter = FakeAdapter(
+    final adapter = FakeTransport(
       (_) => [
         _stream('id: 1\ndata: a\n\nid: 2\nevent: ping\ndata: x\n\n'),
         _stream('', 204),
       ][next++],
     );
-    final result = await DioRequestSender(Dio()..httpClientAdapter = adapter)
-        .openEvents<String, Never>(
-          const OperationRequest(
-            OperationInfo(operationId: 'w', method: 'GET', pathTemplate: '/w'),
-            streamStatuses: {200, 204},
-          ),
-          (m) => m.event == 'ping' ? throw const SseEventIgnored() : m.data,
-          (r) => r.undocumented(),
-          call: CallOptions(
-            sse: SseOptions(reconnect: true, wait: (_) async {}),
-          ),
-        );
+    final result = await ClientSender(adapter).openEvents<String, Never>(
+      const OperationRequest(
+        OperationInfo(operationId: 'w', method: 'GET', pathTemplate: '/w'),
+        streamStatuses: {200, 204},
+      ),
+      (m) => m.event == 'ping' ? throw const SseEventIgnored() : m.data,
+      (r) => r.undocumented(),
+      call: CallOptions(
+        sse: SseOptions(reconnect: true, wait: (_) async {}),
+      ),
+    );
     final items = await (result as Success<Stream<SseItem<String>>, Never>).data
         .toList();
     expect(items.whereType<SseEvent<String>>().map((e) => e.data), ['a']);
     expect(items.whereType<SseReconnecting<String>>(), hasLength(1));
-    expect(adapter.requests[1].headers['Last-Event-ID'], '2');
+    expect(FakeTransport.header(adapter.requests[1], 'Last-Event-ID'), '2');
   });
 
   test(
diff --git a/packages/typed_openapi_client/test/sse/sse_reconnect_cancel_test.dart b/packages/typed_openapi_client/test/sse/sse_reconnect_cancel_test.dart
index e031ef9..0513437 100644
--- a/packages/typed_openapi_client/test/sse/sse_reconnect_cancel_test.dart
+++ b/packages/typed_openapi_client/test/sse/sse_reconnect_cancel_test.dart
@@ -1,30 +1,23 @@
 import 'dart:async';
-import 'dart:convert';
-import 'dart:typed_data';
 
-import 'package:dio/dio.dart';
 import 'package:test/test.dart';
 import 'package:typed_openapi_client/typed_openapi_client.dart';
 
-import '../helpers/gated_adapter.dart';
+import '../helpers/fake_transport.dart';
+import '../helpers/gated_transport.dart';
 
 /// An event-stream response with [text] that then closes.
-ResponseBody _stream(String text) => ResponseBody(
-  Stream.value(Uint8List.fromList(utf8.encode(text))),
-  200,
-  headers: {
-    Headers.contentTypeHeader: ['text/event-stream'],
-  },
-);
-
-/// A token that counts how often a listener is attached to it.
-final class _CountingToken extends CancelToken {
-  int whenCancelCalls = 0;
+TransportResponse _stream(String text) =>
+    FakeTransport.response(text, 200, 'text/event-stream');
+
+/// A signal that counts how often a listener is attached to it.
+final class _CountingSignal extends CancelSignal {
+  int whenCancelledCalls = 0;
 
   @override
-  Future<DioException> get whenCancel {
-    whenCancelCalls++;
-    return super.whenCancel;
+  Future<void> get whenCancelled {
+    whenCancelledCalls++;
+    return super.whenCancelled;
   }
 }
 
@@ -38,27 +31,26 @@ void main() {
       r.undocumented();
 
   Future<Stream<SseItem<String>>> open(
-    GatedAdapter adapter, {
+    GatedTransport adapter, {
     SseOptions? sse,
-    CancelToken? token,
+    CancelSignal? token,
   }) async {
-    final result = await DioRequestSender(Dio()..httpClientAdapter = adapter)
-        .openEvents(
-          watch,
-          (m) => m.data,
-          decodeError,
-          call: CallOptions(
-            sse: sse ?? SseOptions(wait: (_) async {}),
-            cancelToken: token,
-          ),
-          reconnection: .onRequest,
-        );
+    final result = await ClientSender(adapter).openEvents(
+      watch,
+      (m) => m.data,
+      decodeError,
+      call: CallOptions(
+        sse: sse ?? SseOptions(wait: (_) async {}),
+        cancel: token,
+      ),
+      reconnection: .onRequest,
+    );
     return (result as Success<Stream<SseItem<String>>, String>).data;
   }
 
   test('a listener that cancels during a reopen aborts that request', () async {
     final gate = Completer<void>();
-    final adapter = GatedAdapter((options, index) async {
+    final adapter = GatedTransport((options, index) async {
       if (index == 0) return _stream('data: a\n\n');
       await gate.future;
       return _stream('data: b\n\n');
@@ -81,7 +73,7 @@ void main() {
     'a listener that cancels during the default wait stops its timer',
     () async {
       final timers = <Duration, bool>{};
-      final adapter = GatedAdapter(
+      final adapter = GatedTransport(
         (options, index) async => _stream('data: a\n\n'),
       );
       await runZoned(
@@ -117,11 +109,11 @@ void main() {
 
   test('a reconnecting call listens to its cancel token once', () async {
     var next = 0;
-    final adapter = GatedAdapter(
+    final adapter = GatedTransport(
       (options, index) async =>
           next++ < 4 ? _stream('data: a\n\n') : _stream('data: z\n\n'),
     );
-    final token = _CountingToken();
+    final token = _CountingSignal();
     final stream = await open(
       adapter,
       sse: SseOptions(wait: (_) async {}, reconnect: true, maxAttempts: 2),
@@ -131,7 +123,7 @@ void main() {
     await adapter.started(4);
     await subscription.cancel();
     // The reconnector's own listener and the one that links the connections.
-    expect(token.whenCancelCalls, lessThanOrEqualTo(2));
+    expect(token.whenCancelledCalls, lessThanOrEqualTo(2));
   });
 }
 
diff --git a/packages/typed_openapi_client/test/sse/sse_reconnect_errors_test.dart b/packages/typed_openapi_client/test/sse/sse_reconnect_errors_test.dart
index ad6eba3..f09ca8e 100644
--- a/packages/typed_openapi_client/test/sse/sse_reconnect_errors_test.dart
+++ b/packages/typed_openapi_client/test/sse/sse_reconnect_errors_test.dart
@@ -1,26 +1,20 @@
 import 'dart:async';
-import 'dart:convert';
-import 'dart:typed_data';
 
-import 'package:dio/dio.dart';
 import 'package:test/test.dart';
 import 'package:typed_openapi_client/typed_openapi_client.dart';
 
-import '../helpers/fake_adapter.dart';
+import '../helpers/fake_transport.dart';
 
 /// An event-stream response with [text] that then closes.
-ResponseBody _stream(String text) => ResponseBody(
-  Stream.value(Uint8List.fromList(utf8.encode(text))),
-  200,
-  headers: {
-    Headers.contentTypeHeader: ['text/event-stream'],
-  },
-);
+TransportResponse _stream(String text) =>
+    FakeTransport.response(text, 200, 'text/event-stream');
 
 /// Answers the requests in order with [answers]; the last one repeats.
-FakeAdapter _adapter(List<ResponseBody Function(RequestOptions)> answers) {
+FakeTransport _adapter(
+  List<TransportResponse Function(TransportRequest)> answers,
+) {
   var next = 0;
-  return FakeAdapter(
+  return FakeTransport(
     (options) => answers[next < answers.length - 1 ? next++ : next](options),
   );
 }
@@ -44,17 +38,16 @@ void main() {
 
   /// The stream of a [watch] that reconnects, opened through [adapter].
   Future<Stream<SseItem<String>>> open(
-    FakeAdapter adapter, {
+    FakeTransport adapter, {
     SseOptions options = const SseOptions(reconnect: true),
   }) async {
-    final result = await DioRequestSender(Dio()..httpClientAdapter = adapter)
-        .openEvents(
-          watch,
-          (m) => m.data,
-          decodeError,
-          call: CallOptions(sse: options),
-          reconnection: SseReconnection.on,
-        );
+    final result = await ClientSender(adapter).openEvents(
+      watch,
+      (m) => m.data,
+      decodeError,
+      call: CallOptions(sse: options),
+      reconnection: SseReconnection.on,
+    );
     return (result as Success<Stream<SseItem<String>>, String>).data;
   }
 
@@ -133,7 +126,7 @@ void main() {
     final adapter = _adapter([
       (_) => _stream('data: a\n\n'),
       (_) => _stream('data: b\n\n'),
-      (_) => ResponseBody.fromString('', 204),
+      (_) => FakeTransport.response('', 204),
     ]);
     final stream = await open(
       adapter,
@@ -162,7 +155,7 @@ void main() {
     final adapter = _adapter([
       (_) => _stream('id: ідентифікатор\ndata: a\n\n'),
       (_) => _stream('data: b\n\n'),
-      (_) => ResponseBody.fromString('', 204),
+      (_) => FakeTransport.response('', 204),
     ]);
     final stream = await open(
       adapter,
@@ -176,7 +169,7 @@ void main() {
       'end closed',
     ]);
     for (final request in adapter.requests) {
-      expect(request.headers.keys, isNot(contains('Last-Event-ID')));
+      expect(FakeTransport.header(request, 'Last-Event-ID'), isNull);
     }
     expect(adapter.requests, hasLength(3));
   });
@@ -184,13 +177,13 @@ void main() {
   test('an event id of printable ASCII is sent as it is', () async {
     final adapter = _adapter([
       (_) => _stream('id: a b~9\ndata: a\n\n'),
-      (_) => ResponseBody.fromString('', 204),
+      (_) => FakeTransport.response('', 204),
     ]);
     final stream = await open(
       adapter,
       options: SseOptions(reconnect: true, wait: (_) async {}),
     );
     await stream.toList();
-    expect(adapter.requests[1].headers['Last-Event-ID'], 'a b~9');
+    expect(FakeTransport.header(adapter.requests[1], 'Last-Event-ID'), 'a b~9');
   });
 }
diff --git a/packages/typed_openapi_client/test/sse/sse_reconnect_gaps_test.dart b/packages/typed_openapi_client/test/sse/sse_reconnect_gaps_test.dart
index ca7efc3..5ab57cd 100644
--- a/packages/typed_openapi_client/test/sse/sse_reconnect_gaps_test.dart
+++ b/packages/typed_openapi_client/test/sse/sse_reconnect_gaps_test.dart
@@ -1,27 +1,21 @@
 import 'dart:async';
-import 'dart:convert';
-import 'dart:typed_data';
 
-import 'package:dio/dio.dart';
 import 'package:test/test.dart';
 import 'package:typed_openapi_client/typed_openapi_client.dart';
 
-import '../helpers/fake_adapter.dart';
-import '../helpers/gated_adapter.dart';
+import '../helpers/fake_transport.dart';
+import '../helpers/gated_transport.dart';
 
 /// An event-stream response with [text] that then closes.
-ResponseBody _stream(String text, [int status = 200]) => ResponseBody(
-  Stream.value(Uint8List.fromList(utf8.encode(text))),
-  status,
-  headers: {
-    Headers.contentTypeHeader: ['text/event-stream'],
-  },
-);
+TransportResponse _stream(String text, [int status = 200]) =>
+    FakeTransport.response(text, status, 'text/event-stream');
 
 /// Answers the requests in order with [answers]; the last one repeats.
-FakeAdapter _adapter(List<ResponseBody Function(RequestOptions)> answers) {
+FakeTransport _adapter(
+  List<TransportResponse Function(TransportRequest)> answers,
+) {
   var next = 0;
-  return FakeAdapter(
+  return FakeTransport(
     (options) => answers[next < answers.length - 1 ? next++ : next](options),
   );
 }
@@ -45,17 +39,16 @@ void main() {
 
   /// The stream of a [watch] that reconnects, opened through [adapter].
   Future<Stream<SseItem<String>>> open(
-    HttpClientAdapter adapter,
+    ClientTransport adapter,
     SseOptions options,
   ) async {
-    final result = await DioRequestSender(Dio()..httpClientAdapter = adapter)
-        .openEvents(
-          watch,
-          (m) => m.data,
-          decodeError,
-          call: CallOptions(sse: options),
-          reconnection: SseReconnection.on,
-        );
+    final result = await ClientSender(adapter).openEvents(
+      watch,
+      (m) => m.data,
+      decodeError,
+      call: CallOptions(sse: options),
+      reconnection: SseReconnection.on,
+    );
     return (result as Success<Stream<SseItem<String>>, String>).data;
   }
 
@@ -105,7 +98,10 @@ void main() {
         (_) => _stream('', 204),
       ]);
       await items(await open(adapter, options()));
-      return [for (final r in adapter.requests) r.headers['Last-Event-ID']];
+      return [
+        for (final r in adapter.requests)
+          FakeTransport.header(r, 'Last-Event-ID'),
+      ];
     }
 
     test('ignores an id with a NUL', () async {
@@ -164,7 +160,7 @@ void main() {
 
   test('a pause during the reopen holds the next connection', () async {
     final gate = Completer<void>();
-    final adapter = GatedAdapter((options, index) async {
+    final adapter = GatedTransport((options, index) async {
       if (index == 0) return _stream('data: a\n\n');
       if (index == 1) {
         await gate.future;
diff --git a/packages/typed_openapi_client/test/sse/sse_reconnect_progress_test.dart b/packages/typed_openapi_client/test/sse/sse_reconnect_progress_test.dart
index c03a790..2bc4bdf 100644
--- a/packages/typed_openapi_client/test/sse/sse_reconnect_progress_test.dart
+++ b/packages/typed_openapi_client/test/sse/sse_reconnect_progress_test.dart
@@ -1,7 +1,7 @@
 import 'package:test/test.dart';
 import 'package:typed_openapi_client/typed_openapi_client.dart';
 
-import '../helpers/fake_adapter.dart';
+import '../helpers/fake_transport.dart';
 import '../helpers/watch_stream.dart';
 
 void main() {
@@ -9,7 +9,7 @@ void main() {
   WatchStream watch(List<String> bodies, {int maxAttempts = 5}) {
     var next = 0;
     return WatchStream(
-      FakeAdapter(
+      FakeTransport(
         (_) => next < bodies.length
             ? WatchStream.response(bodies[next++])
             : WatchStream.response('', 204),
diff --git a/packages/typed_openapi_client/test/sse/sse_reconnect_test.dart b/packages/typed_openapi_client/test/sse/sse_reconnect_test.dart
index 573d6bc..2a38695 100644
--- a/packages/typed_openapi_client/test/sse/sse_reconnect_test.dart
+++ b/packages/typed_openapi_client/test/sse/sse_reconnect_test.dart
@@ -2,32 +2,25 @@ import 'dart:async';
 import 'dart:convert';
 import 'dart:typed_data';
 
-import 'package:dio/dio.dart';
 import 'package:test/test.dart';
 import 'package:typed_openapi_client/typed_openapi_client.dart';
 
-import '../helpers/fake_adapter.dart';
+import '../helpers/fake_transport.dart';
 
 /// An event-stream response with [text] that then closes.
-ResponseBody _stream(String text, [int status = 200]) => ResponseBody(
-  Stream.value(Uint8List.fromList(utf8.encode(text))),
-  status,
-  headers: {
-    Headers.contentTypeHeader: ['text/event-stream'],
-  },
-);
+TransportResponse _stream(String text, [int status = 200]) =>
+    FakeTransport.response(text, status, 'text/event-stream');
 
 /// A connection that fails before any response.
-ResponseBody _refused(RequestOptions options) => throw DioException(
-  requestOptions: options,
-  type: DioExceptionType.connectionError,
-  message: 'refused',
-);
+TransportResponse _refused(TransportRequest request) =>
+    throw const TransportException(.connection, 'refused');
 
 /// Answers the requests in order with [answers]; the last one repeats.
-FakeAdapter _adapter(List<ResponseBody Function(RequestOptions)> answers) {
+FakeTransport _adapter(
+  List<TransportResponse Function(TransportRequest)> answers,
+) {
   var next = 0;
-  return FakeAdapter(
+  return FakeTransport(
     (options) => answers[next < answers.length - 1 ? next++ : next](options),
   );
 }
@@ -49,7 +42,8 @@ void main() {
     SseDecodeError() => 'decode error',
     SseReconnecting(:final attempt, :final delay) =>
       'reconnecting $attempt after ${delay.inMilliseconds}ms',
-    SseDisconnected(cause: DioException(:final type)) => 'end ${type.name}',
+    SseDisconnected(cause: TransportException(:final kind)) =>
+      'end ${kind.name}',
     SseDisconnected(cause: HttpError(:final statusCode)) =>
       'end http $statusCode',
     SseDisconnected(:final cause) => 'end ${cause ?? 'closed'}',
@@ -57,7 +51,7 @@ void main() {
 
   /// The items of a [watch] stream opened through [adapter].
   Future<List<String>> items(
-    FakeAdapter adapter, {
+    FakeTransport adapter, {
     SseReconnection reconnection = SseReconnection.onRequest,
     SseOptions? sse,
     List<Duration>? waits,
@@ -69,14 +63,13 @@ void main() {
       maxDelay: sse?.maxDelay ?? const Duration(seconds: 30),
       wait: (delay) async => waits?.add(delay),
     );
-    final result = await DioRequestSender(Dio()..httpClientAdapter = adapter)
-        .openEvents(
-          watch,
-          (m) => m.data,
-          decodeError,
-          call: CallOptions(sse: options),
-          reconnection: reconnection,
-        );
+    final result = await ClientSender(adapter).openEvents(
+      watch,
+      (m) => m.data,
+      decodeError,
+      call: CallOptions(sse: options),
+      reconnection: reconnection,
+    );
     final stream = (result as Success<Stream<SseItem<String>>, String>).data;
     return (await stream.toList()).map(describe).toList();
   }
@@ -148,8 +141,8 @@ void main() {
       ['event a #7', 'reconnecting 1 after 2500ms', 'end closed'],
     );
     expect(waits, [const Duration(milliseconds: 2500)]);
-    expect(adapter.requests[0].headers['Last-Event-ID'], isNull);
-    expect(adapter.requests[1].headers['Last-Event-ID'], '7');
+    expect(FakeTransport.header(adapter.requests[0], 'Last-Event-ID'), isNull);
+    expect(FakeTransport.header(adapter.requests[1], 'Last-Event-ID'), '7');
   });
 
   test('the event id carries over to the next connection', () async {
@@ -168,7 +161,7 @@ void main() {
         'end closed',
       ],
     );
-    expect(adapter.requests[2].headers['Last-Event-ID'], '7');
+    expect(FakeTransport.header(adapter.requests[2], 'Last-Event-ID'), '7');
   });
 
   test(
@@ -192,7 +185,7 @@ void main() {
           'reconnecting 2 after 2000ms',
           'reconnecting 3 after 3000ms',
           'reconnecting 4 after 3000ms',
-          'end connectionError',
+          'end connection',
         ],
       );
       expect(adapter.requests, hasLength(5));
@@ -214,7 +207,7 @@ void main() {
   test('an attempt answered with an error status ends the stream', () async {
     final adapter = _adapter([
       (_) => _stream('data: a\n\n'),
-      (_) => ResponseBody.fromString('gone', 404),
+      (_) => FakeTransport.response('gone', 404),
     ]);
     expect(await items(adapter, reconnection: SseReconnection.on), [
       'event a #',
@@ -226,21 +219,20 @@ void main() {
   test(
     'cancelling during the wait ends the stream, no request follows',
     () async {
-      final token = CancelToken();
+      final token = CancelSignal();
       final adapter = _adapter([(_) => _stream('data: a\n\n')]);
-      final result = await DioRequestSender(Dio()..httpClientAdapter = adapter)
-          .openEvents(
-            watch,
-            (m) => m.data,
-            decodeError,
-            call: CallOptions(
-              cancelToken: token,
-              sse: SseOptions(
-                reconnect: true,
-                wait: (_) => Completer<void>().future,
-              ),
-            ),
-          );
+      final result = await ClientSender(adapter).openEvents(
+        watch,
+        (m) => m.data,
+        decodeError,
+        call: CallOptions(
+          cancel: token,
+          sse: SseOptions(
+            reconnect: true,
+            wait: (_) => Completer<void>().future,
+          ),
+        ),
+      );
       final stream = (result as Success<Stream<SseItem<String>>, String>).data;
       final seen = <String>[];
       final done = Completer<void>();
@@ -249,7 +241,11 @@ void main() {
         if (item is SseReconnecting) token.cancel();
       }, onDone: done.complete);
       await done.future;
-      expect(seen, ['event a #', 'reconnecting 1 after 1000ms', 'end cancel']);
+      expect(seen, [
+        'event a #',
+        'reconnecting 1 after 1000ms',
+        'end cancelled',
+      ]);
       expect(adapter.requests, hasLength(1));
     },
   );
@@ -257,15 +253,14 @@ void main() {
   test('a listener that cancels during the wait stops the attempts', () async {
     final wait = Completer<void>();
     final adapter = _adapter([(_) => _stream('data: a\n\n')]);
-    final result = await DioRequestSender(Dio()..httpClientAdapter = adapter)
-        .openEvents(
-          watch,
-          (m) => m.data,
-          decodeError,
-          call: CallOptions(
-            sse: SseOptions(reconnect: true, wait: (_) => wait.future),
-          ),
-        );
+    final result = await ClientSender(adapter).openEvents(
+      watch,
+      (m) => m.data,
+      decodeError,
+      call: CallOptions(
+        sse: SseOptions(reconnect: true, wait: (_) => wait.future),
+      ),
+    );
     final stream = (result as Success<Stream<SseItem<String>>, String>).data;
     late final StreamSubscription<SseItem<String>> subscription;
     subscription = stream.listen((item) {
@@ -278,26 +273,25 @@ void main() {
   });
 
   test('cancelling during the stream ends it without a reconnect', () async {
-    final token = CancelToken();
+    final token = CancelSignal();
     final body = StreamController<Uint8List>();
     addTearDown(body.close);
     final adapter = _adapter([
-      (_) => ResponseBody(
-        body.stream,
-        200,
+      (_) => TransportResponse(
+        statusCode: 200,
+        body: body.stream,
         headers: {
-          Headers.contentTypeHeader: ['text/event-stream'],
+          'content-type': ['text/event-stream'],
         },
       ),
     ]);
-    final result = await DioRequestSender(Dio()..httpClientAdapter = adapter)
-        .openEvents(
-          watch,
-          (m) => m.data,
-          decodeError,
-          call: CallOptions(cancelToken: token),
-          reconnection: SseReconnection.on,
-        );
+    final result = await ClientSender(adapter).openEvents(
+      watch,
+      (m) => m.data,
+      decodeError,
+      call: CallOptions(cancel: token),
+      reconnection: SseReconnection.on,
+    );
     final stream = (result as Success<Stream<SseItem<String>>, String>).data;
     final seen = <String>[];
     final done = Completer<void>();
@@ -307,7 +301,7 @@ void main() {
     }, onDone: done.complete);
     body.add(Uint8List.fromList(utf8.encode('data: a\n\n')));
     await done.future;
-    expect(seen, ['event a #', 'end cancel']);
+    expect(seen, ['event a #', 'end cancelled']);
     expect(adapter.requests, hasLength(1));
   });
 }
diff --git a/packages/typed_openapi_client/test/sse/sse_user_last_event_id_test.dart b/packages/typed_openapi_client/test/sse/sse_user_last_event_id_test.dart
index 939d085..9ad6bdf 100644
--- a/packages/typed_openapi_client/test/sse/sse_user_last_event_id_test.dart
+++ b/packages/typed_openapi_client/test/sse/sse_user_last_event_id_test.dart
@@ -1,20 +1,11 @@
-import 'dart:convert';
-import 'dart:typed_data';
-
-import 'package:dio/dio.dart';
 import 'package:test/test.dart';
 import 'package:typed_openapi_client/typed_openapi_client.dart';
 
-import '../helpers/fake_adapter.dart';
+import '../helpers/fake_transport.dart';
 
 /// An event-stream response with [text] that then closes.
-ResponseBody _stream(String text, [int status = 200]) => ResponseBody(
-  Stream.value(Uint8List.fromList(utf8.encode(text))),
-  status,
-  headers: {
-    Headers.contentTypeHeader: ['text/event-stream'],
-  },
-);
+TransportResponse _stream(String text, [int status = 200]) =>
+    FakeTransport.response(text, status, 'text/event-stream');
 
 void main() {
   const watch = OperationRequest(
@@ -32,24 +23,24 @@ void main() {
     Map<String, Object?> headers,
   ) async {
     var next = 0;
-    final adapter = FakeAdapter(
+    final adapter = FakeTransport(
       (_) => next < bodies.length ? _stream(bodies[next++]) : _stream('', 204),
     );
-    final result = await DioRequestSender(Dio()..httpClientAdapter = adapter)
-        .openEvents(
-          watch,
-          (m) => m.data,
-          decodeError,
-          call: CallOptions(
-            headers: headers,
-            sse: SseOptions(reconnect: true, wait: (_) async {}),
-          ),
-        );
+    final result = await ClientSender(adapter).openEvents(
+      watch,
+      (m) => m.data,
+      decodeError,
+      call: CallOptions(
+        headers: headers,
+        sse: SseOptions(reconnect: true, wait: (_) async {}),
+      ),
+    );
     await (result as Success<Stream<SseItem<String>>, String>).data
         .drain<void>();
     return [
       for (final request in adapter.requests)
-        request.headers['Last-Event-ID'] ?? request.headers['last-event-id'],
+        FakeTransport.header(request, 'Last-Event-ID') ??
+            FakeTransport.header(request, 'last-event-id'),
     ];
   }
 
~~~~

#### Part 4b: `typed_openapi_dio`

**Files:** `packages/typed_openapi_dio/{pubspec.yaml,README.md,CHANGELOG.md,LICENSE}`, `lib/typed_openapi_dio.dart`, `lib/src/{dio_transport,dio_failures,query_guard}.dart`; tests `test/{dio_transport_test,loopback_test,web_test,cookie_browser_test,cookie_server}.dart`, `test/helpers/fake_adapter.dart`; root `pubspec.yaml` workspace entry.

Behaviour: `dio.request<ResponseBody>(QueryGuard(baseUrl).target(target), data: body, options: Options(method:, headers:, responseType: .stream, extra: {...extra, OperationInfo.extraKey: operation}), cancelToken:)`; a header with several values is joined with `, `; the `CancelSignal` cancels a `CancelToken` made per request; a `DioException` whose response holds a `ResponseBody` (an error status after `onError`) is a `TransportResponse`; an `unknown` one with an `Error` rethrows the `Error`; the others are a `TransportException` (decision 3) with the `DioException` as cause; the response body stream maps a `DioException` to a `TransportException` (decision 14).

Notes from the replay: the loopback SSE test's `HttpServer` must set `response.bufferOutput = false`, or the events never leave the server before the cancel (the test hangs 30 s); `web_test` changes as decision 8 says (malformed JSON keeps status `200` and the text on both compilers; a `FormatException` from an interceptor is a `TransportError`).

- [ ] **Step 1: Apply the patch** below (the two replayed commits, the package and `operationOf`, in one diff), after the `git rm` before it (the generator test that pinned the name `Dio`).
- [ ] **Step 2: Verify**: `dart pub get` (adds `dio_web_adapter`); adapter `+11` on the VM (10 adapter cases and the loopback stream), `+21` in Chrome with dart2js and with dart2wasm (web and cookie tests); analyze clean.
- [ ] **Step 3: No commit yet**: go on with Part 4c.

Delete first:

```sh
git rm -q -r \
  packages/typed_openapi/test/ir/dio_names_test.dart
```

~~~~diff
diff --git a/packages/typed_openapi_dio/CHANGELOG.md b/packages/typed_openapi_dio/CHANGELOG.md
new file mode 100644
index 0000000..e6a0cad
--- /dev/null
+++ b/packages/typed_openapi_dio/CHANGELOG.md
@@ -0,0 +1,4 @@
+## 0.0.1
+
+- First version: `DioTransport`, the Dio transport of clients generated by
+  typed_openapi.
diff --git a/packages/typed_openapi_dio/LICENSE b/packages/typed_openapi_dio/LICENSE
new file mode 100644
index 0000000..dbebdef
--- /dev/null
+++ b/packages/typed_openapi_dio/LICENSE
@@ -0,0 +1,21 @@
+MIT License
+
+Copyright (c) 2026 Yevhenii Aleksiuk
+
+Permission is hereby granted, free of charge, to any person obtaining a copy
+of this software and associated documentation files (the "Software"), to deal
+in the Software without restriction, including without limitation the rights
+to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
+copies of the Software, and to permit persons to whom the Software is
+furnished to do so, subject to the following conditions:
+
+The above copyright notice and this permission notice shall be included in all
+copies or substantial portions of the Software.
+
+THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
+IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
+FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
+AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
+LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
+OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
+SOFTWARE.
diff --git a/packages/typed_openapi_dio/README.md b/packages/typed_openapi_dio/README.md
new file mode 100644
index 0000000..80af6a2
--- /dev/null
+++ b/packages/typed_openapi_dio/README.md
@@ -0,0 +1,13 @@
+# typed_openapi_dio
+
+The Dio transport of clients generated by typed_openapi.
+
+```dart
+final api = PetsApi(DioTransport(Dio(BaseOptions(baseUrl: url))));
+```
+
+Your `Dio` keeps its base URL, interceptors, timeouts and adapter. Dio
+reads every response as a stream and the client decodes the bytes, so a
+`Transformer` or `responseDecoder` is not used, and a request interceptor
+sees the body as bytes. Server-sent events in a browser need a streaming
+adapter (see `DioTransport.webStreamingMessage`).
diff --git a/packages/typed_openapi_dio/lib/src/dio_failures.dart b/packages/typed_openapi_dio/lib/src/dio_failures.dart
new file mode 100644
index 0000000..1cc3b7e
--- /dev/null
+++ b/packages/typed_openapi_dio/lib/src/dio_failures.dart
@@ -0,0 +1,42 @@
+import 'dart:async';
+import 'dart:typed_data';
+
+import 'package:dio/dio.dart';
+import 'package:typed_openapi_client/typed_openapi_client.dart';
+
+/// Turns Dio's failures into the client's [TransportException]s.
+final class DioFailures {
+  const DioFailures._();
+
+  /// The [TransportException] of [e], with [e] as its cause. An [Error]
+  /// that an interceptor or the adapter threw (Dio wraps it into an
+  /// `unknown` [DioException]) is thrown again: it is a bug, not a
+  /// transport failure.
+  static TransportException exception(DioException e, StackTrace stackTrace) {
+    if (e case DioException(type: .unknown, error: final Error cause)) {
+      Error.throwWithStackTrace(cause, e.stackTrace);
+    }
+    return TransportException(
+      switch (e.type) {
+        .connectionTimeout || .sendTimeout || .receiveTimeout => .timeout,
+        .connectionError => .connection,
+        .cancel => .cancelled,
+        _ => .other,
+      },
+      e.message ?? '${e.type.name}: ${e.error}',
+      cause: e,
+      stackTrace: stackTrace,
+    );
+  }
+
+  /// [body] with each [DioException] it emits (a timeout or a cancel while
+  /// it is read) turned into a [TransportException].
+  static Stream<List<int>> body(Stream<Uint8List> body) => body.transform(
+    StreamTransformer<Uint8List, List<int>>.fromHandlers(
+      handleError: (error, stackTrace, sink) => sink.addError(
+        error is DioException ? exception(error, stackTrace) : error,
+        stackTrace,
+      ),
+    ),
+  );
+}
diff --git a/packages/typed_openapi_dio/lib/src/dio_transport.dart b/packages/typed_openapi_dio/lib/src/dio_transport.dart
new file mode 100644
index 0000000..650556e
--- /dev/null
+++ b/packages/typed_openapi_dio/lib/src/dio_transport.dart
@@ -0,0 +1,103 @@
+import 'dart:async';
+
+import 'package:dio/dio.dart';
+import 'package:typed_openapi_client/typed_openapi_client.dart';
+
+import 'dio_failures.dart';
+import 'query_guard.dart';
+
+/// A [ClientTransport] that sends through the user's [Dio], which it uses
+/// as it is: its base URL, interceptors, timeouts and adapter apply, and
+/// it is never changed.
+///
+/// Dio reads every response as a stream; the client reads and decodes the
+/// bytes, so a `Transformer` or `responseDecoder` of the Dio is not used.
+/// An error status goes through Dio's `onError` interceptors first (a
+/// token refresh still works) and then reaches the client as a response.
+final class DioTransport implements ClientTransport {
+  /// Creates the transport over [dio]. [isWeb] tells whether the program
+  /// runs in a browser (dart2js or dart2wasm); it is found out when not
+  /// given.
+  DioTransport(this.dio, {bool? isWeb}) : isWeb = isWeb ?? _runsOnWeb;
+
+  /// The user's Dio instance.
+  final Dio dio;
+
+  /// Whether the program runs in a browser, where Dio's default adapter
+  /// cannot stream an event stream.
+  final bool isWeb;
+
+  static const bool _runsOnWeb = bool.fromEnvironment(
+    'dart.library.js_interop',
+  );
+
+  /// Explains why server-sent events cannot stream on the web with the
+  /// default Dio adapter.
+  static const String webStreamingMessage =
+      'Server-sent events need a streaming HTTP adapter on the web: Dio\'s '
+      'default browser adapter delivers the body only when the connection '
+      'closes. Set a fetch-based adapter on your Dio, such as '
+      'ConversionLayerAdapter from package:dio_compatibility_layer with '
+      'package:http\'s BrowserClient or package:fetch_client.';
+
+  @override
+  Future<TransportResponse> send(TransportRequest request) async {
+    if (request.isEventStream && isWeb && _hasDefaultAdapter) {
+      throw TransportException(
+        .other,
+        webStreamingMessage,
+        cause: UnsupportedError(webStreamingMessage),
+      );
+    }
+    try {
+      return _response(
+        await dio.request<ResponseBody>(
+          QueryGuard(dio.options.baseUrl).target(request.target),
+          data: request.body,
+          options: _options(request),
+          cancelToken: _token(request.cancel),
+        ),
+      );
+    } on DioException catch (e, stackTrace) {
+      if (e.response case final Response<Object?> response?
+          when response.data is ResponseBody) {
+        return _response(response);
+      }
+      throw DioFailures.exception(e, stackTrace);
+    }
+  }
+
+  Options _options(TransportRequest request) => Options(
+    method: request.method,
+    headers: {
+      for (final MapEntry(:key, :value) in request.headers.entries)
+        key: value.length == 1 ? value.single : value.join(', '),
+    },
+    extra: {...request.extra, OperationInfo.extraKey: request.operation},
+    responseType: .stream,
+  );
+
+  /// A Dio token that is cancelled with [signal].
+  static CancelToken? _token(CancelSignal? signal) {
+    if (signal == null) return null;
+    final token = CancelToken();
+    if (signal.isCancelled) {
+      token.cancel(signal.reason);
+    } else {
+      unawaited(signal.whenCancelled.then((_) => token.cancel(signal.reason)));
+    }
+    return token;
+  }
+
+  static TransportResponse _response(Response<Object?> response) {
+    final body = response.data as ResponseBody;
+    return TransportResponse(
+      statusCode: response.statusCode ?? body.statusCode,
+      headers: response.headers.map,
+      body: DioFailures.body(body.stream),
+    );
+  }
+
+  bool get _hasDefaultAdapter =>
+      dio.httpClientAdapter.runtimeType == HttpClientAdapter().runtimeType;
+}
diff --git a/packages/typed_openapi_dio/lib/src/query_guard.dart b/packages/typed_openapi_dio/lib/src/query_guard.dart
new file mode 100644
index 0000000..82b6e03
--- /dev/null
+++ b/packages/typed_openapi_dio/lib/src/query_guard.dart
@@ -0,0 +1,32 @@
+/// Keeps a `//` in the query of a request target from Dio, which joins the
+/// base URL and a relative path and then collapses every `//` of the whole
+/// string, query included (`RequestOptions.uri`): an `allowReserved` value
+/// such as `next=/a//b` would change.
+final class QueryGuard {
+  /// Creates the guard for the Dio's [baseUrl].
+  const QueryGuard(this.baseUrl);
+
+  /// The base URL of the user's Dio.
+  final String baseUrl;
+
+  /// What to pass to Dio for [target]: when its query holds `//`, the base
+  /// URL is joined here, collapsing `//` in the path part only, and Dio
+  /// leaves the absolute URL alone. Otherwise the relative target, so
+  /// interceptors that change `baseUrl` keep working; interceptors see the
+  /// finished URI either way.
+  String target(String target) {
+    final queryStart = target.indexOf('?');
+    if (queryStart < 0 ||
+        !target.substring(queryStart).contains('//') ||
+        !_absolute.hasMatch(baseUrl)) {
+      return target;
+    }
+    final joined = (baseUrl + target.substring(0, queryStart)).split(':/');
+    final path = joined.length == 2
+        ? '${joined[0]}:/${joined[1].replaceAll('//', '/')}'
+        : joined.join(':/');
+    return path + target.substring(queryStart);
+  }
+
+  static final RegExp _absolute = RegExp('^https?:');
+}
diff --git a/packages/typed_openapi_dio/lib/typed_openapi_dio.dart b/packages/typed_openapi_dio/lib/typed_openapi_dio.dart
new file mode 100644
index 0000000..57513c8
--- /dev/null
+++ b/packages/typed_openapi_dio/lib/typed_openapi_dio.dart
@@ -0,0 +1,4 @@
+/// The Dio transport of clients generated by typed_openapi.
+library;
+
+export 'src/dio_transport.dart' show DioTransport;
diff --git a/packages/typed_openapi_dio/pubspec.yaml b/packages/typed_openapi_dio/pubspec.yaml
new file mode 100644
index 0000000..2fe0caa
--- /dev/null
+++ b/packages/typed_openapi_dio/pubspec.yaml
@@ -0,0 +1,20 @@
+name: typed_openapi_dio
+description: >
+  The Dio transport of clients generated by typed_openapi: sends their
+  requests through your Dio, with its interceptors, base URL and timeouts.
+version: 0.0.1
+homepage: https://github.com/4akLoon/typed_openapi
+repository: https://github.com/4akLoon/typed_openapi
+
+environment:
+  sdk: ">=3.10.0 <4.0.0"
+
+dependencies:
+  dio: ^5.11.1
+  typed_openapi_client: ^0.0.1
+
+dev_dependencies:
+  stream_channel: ^2.1.0
+  test: ^1.24.0
+
+resolution: workspace
diff --git a/packages/typed_openapi_dio/test/cookie_browser_test.dart b/packages/typed_openapi_dio/test/cookie_browser_test.dart
new file mode 100644
index 0000000..8f478af
--- /dev/null
+++ b/packages/typed_openapi_dio/test/cookie_browser_test.dart
@@ -0,0 +1,72 @@
+/// Whether a `Cookie` header set through Dio reaches the server from a
+/// browser (M11, spec decision 8): run with `dart test -p chrome` and
+/// `--compiler dart2wasm`. The server is `cookie_server.dart`, started on
+/// the loopback by `spawnHybridUri`.
+@TestOn('browser')
+library;
+
+import 'package:dio/dio.dart';
+import 'package:test/test.dart';
+import 'package:typed_openapi_client/typed_openapi_client.dart';
+import 'package:typed_openapi_dio/typed_openapi_dio.dart';
+
+void main() {
+  late Dio dio;
+
+  /// The `Cookie` header of each request as the interceptors saw it, before
+  /// the browser dropped it.
+  final cookiesSet = <Object?>[];
+  setUp(cookiesSet.clear);
+  setUpAll(() async {
+    final channel = spawnHybridUri('cookie_server.dart');
+    // The port crosses as JSON: dart2wasm reads the number as a double.
+    final port = (await channel.stream.first as num).toInt();
+    dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:$port'))
+      ..interceptors.add(
+        InterceptorsWrapper(
+          onRequest: (options, handler) {
+            cookiesSet.add(options.headers['Cookie']);
+            handler.next(options);
+          },
+        ),
+      );
+  });
+
+  const probe = OperationInfo(
+    operationId: 'probe',
+    method: 'GET',
+    pathTemplate: '/probe',
+  );
+
+  Result<Object?, Never> decode(RawResponse r) => switch (r.statusCode) {
+    200 => r.success(r.json),
+    _ => r.undocumented(),
+  };
+
+  test('the browser drops a Cookie header and sends the others', () async {
+    final result = await ClientSender(DioTransport(dio)).send(
+      const OperationRequest(
+        probe,
+        headers: [HeaderParameter('X-Probe', 'sent')],
+        cookies: [CookieParameter('session', 'abc')],
+      ),
+      decode,
+    );
+    // The sender produced the header; only the browser dropped it.
+    expect(cookiesSet, ['session=abc']);
+    final received = (result as Success<Object?, Never>).data! as Map;
+    expect(received['probe'], 'sent');
+    // `Cookie` is a forbidden request header: XMLHttpRequest and fetch
+    // ignore it, so a cookie parameter never reaches the server.
+    expect(received['cookie'], isNull);
+  });
+
+  test('a Cookie header set on Dio directly is dropped too', () async {
+    final response = await dio.get<Map<String, Object?>>(
+      '/probe',
+      options: Options(headers: {'Cookie': 'session=abc', 'X-Probe': 'raw'}),
+    );
+    expect(response.data?['probe'], 'raw');
+    expect(response.data?['cookie'], isNull);
+  });
+}
diff --git a/packages/typed_openapi_dio/test/cookie_server.dart b/packages/typed_openapi_dio/test/cookie_server.dart
new file mode 100644
index 0000000..9bd10f6
--- /dev/null
+++ b/packages/typed_openapi_dio/test/cookie_server.dart
@@ -0,0 +1,43 @@
+// A local HTTP server for `cookie_browser_test.dart`, started in the VM by
+// `spawnHybridUri`: it answers every request with the `Cookie` and
+// `X-Probe` headers it received, and allows any origin (CORS), so a page
+// in Chrome can call it. It listens on the loopback only; no external
+// network is used.
+import 'dart:convert';
+import 'dart:io';
+
+import 'package:stream_channel/stream_channel.dart';
+
+/// Starts the server and sends its port on [channel]; the server closes
+/// when the channel does.
+Future<void> hybridMain(StreamChannel<Object?> channel) async {
+  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
+  server.listen((request) {
+    final response = request.response;
+    response.headers
+      ..set(
+        'Access-Control-Allow-Origin',
+        request.headers.value('origin') ?? '*',
+      )
+      ..set(
+        'Access-Control-Allow-Headers',
+        request.headers.value('access-control-request-headers') ?? '*',
+      );
+    if (request.method == 'OPTIONS') {
+      response.close();
+      return;
+    }
+    response
+      ..headers.contentType = ContentType.json
+      ..write(
+        jsonEncode({
+          'cookie': request.headers.value('cookie'),
+          'probe': request.headers.value('x-probe'),
+        }),
+      )
+      ..close();
+  });
+  channel.sink.add(server.port);
+  await channel.stream.drain<void>();
+  await server.close(force: true);
+}
diff --git a/packages/typed_openapi_dio/test/dio_transport_test.dart b/packages/typed_openapi_dio/test/dio_transport_test.dart
new file mode 100644
index 0000000..45c7453
--- /dev/null
+++ b/packages/typed_openapi_dio/test/dio_transport_test.dart
@@ -0,0 +1,189 @@
+import 'dart:async';
+
+import 'package:dio/dio.dart';
+import 'package:test/test.dart';
+import 'package:typed_openapi_client/typed_openapi_client.dart';
+import 'package:typed_openapi_dio/typed_openapi_dio.dart';
+
+import 'helpers/fake_adapter.dart';
+
+/// A documented error body.
+final class Problem {
+  const Problem(this.code);
+
+  factory Problem.fromJson(Map<String, Object?> json) => Problem(
+    JsonReader(json, schema: 'Problem').required('code', JsonReader.asString),
+  );
+
+  final String code;
+}
+
+void main() {
+  const getPet = OperationInfo(
+    operationId: 'getPet',
+    method: 'GET',
+    pathTemplate: '/pets/{petId}',
+    tags: ['pets'],
+  );
+  const request = OperationRequest(
+    getPet,
+    path: [PathParameter('petId', 7)],
+    headers: [HeaderParameter('X-Trace', 't1')],
+  );
+
+  Result<Object?, Problem> decode(RawResponse r) => switch (r.statusCode) {
+    200 => r.success(r.json),
+    404 => r.error(Problem.fromJson(r.jsonObject)),
+    _ => r.undocumented(),
+  };
+
+  Dio dioWith(HttpClientAdapter adapter) =>
+      Dio(BaseOptions(baseUrl: 'https://api.test/v1'))
+        ..httpClientAdapter = adapter;
+
+  Future<Result<Object?, Problem>> send(
+    Dio dio, {
+    OperationRequest operation = request,
+    CallOptions? call,
+  }) => ClientSender(DioTransport(dio)).send(operation, decode, call: call);
+
+  test('the request reaches Dio with its path, headers and metadata', () async {
+    final adapter = FakeAdapter.json(200, {'id': 7});
+    final result = await send(dioWith(adapter));
+    expect((result as Success<Object?, Problem>).data, {'id': 7});
+    final sent = adapter.requests.single;
+    expect(sent.uri.toString(), 'https://api.test/v1/pets/7');
+    expect((sent.method, sent.headers['X-Trace']), ('GET', 't1'));
+    expect(sent.extra[OperationInfo.extraKey], getPet);
+  });
+
+  test('the query keeps // under a base URL (allowReserved)', () async {
+    final adapter = FakeAdapter.json(200, null);
+    await send(
+      dioWith(adapter),
+      operation: const OperationRequest(
+        getPet,
+        path: [PathParameter('petId', 7)],
+        query: [QueryParameter('next', '/a//b', allowReserved: true)],
+      ),
+    );
+    expect(
+      adapter.requests.single.uri.toString(),
+      'https://api.test/v1/pets/7?next=/a//b',
+    );
+  });
+
+  test('the Dio instance is used as it is and never changed', () async {
+    final dio = dioWith(FakeAdapter.json(200, null));
+    final before = (dio.options.headers.length, dio.interceptors.length);
+    await send(dio, call: const CallOptions(headers: {'X-Call': '1'}));
+    expect((dio.options.headers.length, dio.interceptors.length), before);
+  });
+
+  test('an error status passes onError first, then is typed', () async {
+    final seen = <int?>[];
+    final dio = dioWith(FakeAdapter.json(404, {'code': 'gone'}))
+      ..interceptors.add(
+        InterceptorsWrapper(
+          onError: (e, handler) {
+            seen.add(e.response?.statusCode);
+            handler.next(e);
+          },
+        ),
+      );
+    final result = await send(dio);
+    expect((result as HttpError<Object?, Problem>).body.code, 'gone');
+    expect(seen, [404]);
+  });
+
+  test('a validateStatus that accepts errors gives the same result', () async {
+    final dio = dioWith(FakeAdapter.json(404, {'code': 'gone'}))
+      ..options.validateStatus = (_) => true;
+    final result = await send(dio);
+    expect((result as HttpError<Object?, Problem>).statusCode, 404);
+  });
+
+  test('a response resolved by an interceptor is read as a stream', () async {
+    final dio = dioWith(FakeAdapter.json(500, null))
+      ..interceptors.add(
+        InterceptorsWrapper(
+          onRequest: (options, handler) => handler.resolve(
+            Response(
+              requestOptions: options,
+              statusCode: 200,
+              data: ResponseBody.fromString(
+                '{"id":1}',
+                200,
+                headers: {
+                  Headers.contentTypeHeader: ['application/json'],
+                },
+              ),
+              headers: Headers.fromMap({
+                Headers.contentTypeHeader: ['application/json'],
+              }),
+            ),
+          ),
+        ),
+      );
+    final result = await send(dio);
+    expect((result as Success<Object?, Problem>).data, {'id': 1});
+  });
+
+  test('a connection error is a transport failure with its cause', () async {
+    final dio = dioWith(FakeAdapter.json(200, null))
+      ..interceptors.add(
+        InterceptorsWrapper(
+          onRequest: (options, handler) => handler.reject(
+            DioException.connectionError(
+              requestOptions: options,
+              reason: 'refused',
+            ),
+          ),
+        ),
+      );
+    final result = await send(dio);
+    final failure = result as TransportError<Object?, Problem>;
+    expect(failure.exception.kind, TransportExceptionKind.connection);
+    expect(failure.exception.cause, isA<DioException>());
+  });
+
+  test('a timeout is a transport failure of kind timeout', () async {
+    final dio = dioWith(FakeAdapter.json(200, null))
+      ..interceptors.add(
+        InterceptorsWrapper(
+          onRequest: (options, handler) => handler.reject(
+            DioException.receiveTimeout(
+              timeout: const Duration(seconds: 1),
+              requestOptions: options,
+            ),
+          ),
+        ),
+      );
+    final result = await send(dio);
+    final failure = result as TransportError<Object?, Problem>;
+    expect(failure.exception.kind, TransportExceptionKind.timeout);
+  });
+
+  test('an Error thrown in an interceptor is rethrown', () async {
+    final dio = dioWith(FakeAdapter.json(200, null))
+      ..interceptors.add(
+        InterceptorsWrapper(
+          onRequest: (options, handler) => throw StateError('bug'),
+        ),
+      );
+    await expectLater(send(dio), throwsStateError);
+  });
+
+  test('a cancel signal cancels the Dio request', () async {
+    final signal = CancelSignal();
+    final adapter = FakeAdapter((_) {
+      signal.cancel('stop');
+      return ResponseBody.fromString('', 200);
+    });
+    final result = await send(
+      dioWith(adapter),
+      call: CallOptions(cancel: signal),
+    );
+    expect(result, isA<Cancelled<Object?, Problem>>());
+  });
+}
diff --git a/packages/typed_openapi_dio/test/helpers/fake_adapter.dart b/packages/typed_openapi_dio/test/helpers/fake_adapter.dart
new file mode 100644
index 0000000..a447e63
--- /dev/null
+++ b/packages/typed_openapi_dio/test/helpers/fake_adapter.dart
@@ -0,0 +1,73 @@
+import 'dart:convert';
+import 'dart:typed_data';
+
+import 'package:dio/dio.dart';
+
+/// A Dio adapter that answers from memory, so tests never touch the
+/// network. It records every request with its body text.
+final class FakeAdapter implements HttpClientAdapter {
+  /// Answers every request with [respond].
+  FakeAdapter(this.respond);
+
+  /// A JSON response with [status].
+  factory FakeAdapter.json(int status, Object? body) => FakeAdapter(
+    (_) => ResponseBody.fromString(
+      jsonEncode(body),
+      status,
+      headers: {
+        Headers.contentTypeHeader: ['application/json'],
+      },
+    ),
+  );
+
+  /// A response with [status], [text] and [contentType].
+  factory FakeAdapter.text(int status, String text, String contentType) =>
+      FakeAdapter(
+        (_) => ResponseBody.fromString(
+          text,
+          status,
+          headers: {
+            Headers.contentTypeHeader: [contentType],
+          },
+        ),
+      );
+
+  /// Builds the response, or throws a [DioException].
+  final ResponseBody Function(RequestOptions options) respond;
+
+  /// The requests seen, in order.
+  final List<RequestOptions> requests = [];
+
+  /// The request bodies seen, as text.
+  final List<String> bodies = [];
+
+  /// Per request, whether the `cancelFuture` Dio passed has completed: the
+  /// request was cancelled and a real adapter would close the connection.
+  final List<bool> cancelsFired = [];
+
+  @override
+  Future<ResponseBody> fetch(
+    RequestOptions options,
+    Stream<Uint8List>? requestStream,
+    Future<void>? cancelFuture,
+  ) async {
+    requests.add(options);
+    final index = cancelsFired.length;
+    cancelsFired.add(false);
+    cancelFuture?.then(
+      (_) => cancelsFired[index] = true,
+      onError: (Object _) => cancelsFired[index] = true,
+    );
+    final bytes = <int>[];
+    if (requestStream != null) {
+      await for (final chunk in requestStream) {
+        bytes.addAll(chunk);
+      }
+    }
+    bodies.add(utf8.decode(bytes));
+    return respond(options);
+  }
+
+  @override
+  void close({bool force = false}) {}
+}
diff --git a/packages/typed_openapi_dio/test/loopback_test.dart b/packages/typed_openapi_dio/test/loopback_test.dart
new file mode 100644
index 0000000..1114a8b
--- /dev/null
+++ b/packages/typed_openapi_dio/test/loopback_test.dart
@@ -0,0 +1,76 @@
+@TestOn('vm')
+library;
+
+import 'dart:async';
+import 'dart:convert';
+import 'dart:io';
+
+import 'package:dio/dio.dart';
+import 'package:test/test.dart';
+import 'package:typed_openapi_client/typed_openapi_client.dart';
+import 'package:typed_openapi_dio/typed_openapi_dio.dart';
+
+void main() {
+  const chat = OperationInfo(
+    operationId: 'chat',
+    method: 'POST',
+    pathTemplate: '/chat',
+  );
+  late HttpServer server;
+  late Dio dio;
+  final bodies = <String>[];
+
+  setUp(() async {
+    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
+    dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}'));
+    server.listen((request) async {
+      bodies.add(await utf8.decodeStream(request));
+      // Unbuffered, so each event leaves when it is written.
+      request.response.bufferOutput = false;
+      request.response.headers.contentType = ContentType(
+        'text',
+        'event-stream',
+      );
+      request.response
+        ..write('data: one\n\n')
+        ..write('data: two\n\n');
+      await request.response.flush();
+      // The connection stays open until the client cancels.
+    });
+  });
+
+  tearDown(() => server.close(force: true));
+
+  test(
+    'an event stream arrives over a real connection and is cancelled',
+    () async {
+      final signal = CancelSignal();
+      final result = await ClientSender(DioTransport(dio))
+          .openEvents<String, Never>(
+            const OperationRequest(
+              chat,
+              body: 'hi',
+              contentType: 'text/plain',
+              streamStatuses: {200},
+            ),
+            (message) => message.data,
+            (response) => response.undocumented(),
+            call: CallOptions(cancel: signal),
+          );
+      final items = <String>[];
+      await for (final item in (result as Success).data as Stream<SseItem>) {
+        switch (item) {
+          case SseEvent(:final data):
+            items.add('$data');
+            if (items.length == 2) signal.cancel();
+          case SseDisconnected(:final cause):
+            items.add('end ${(cause as TransportException?)?.kind.name}');
+          default:
+            items.add('$item');
+        }
+      }
+      expect(items, ['one', 'two', 'end cancelled']);
+      expect(bodies, ['hi']);
+    },
+  );
+}
diff --git a/packages/typed_openapi_dio/test/web_test.dart b/packages/typed_openapi_dio/test/web_test.dart
new file mode 100644
index 0000000..169dbdc
--- /dev/null
+++ b/packages/typed_openapi_dio/test/web_test.dart
@@ -0,0 +1,142 @@
+/// Behaviour that exists only in a browser, run with
+/// `dart test -p chrome` (dart2js) and
+/// `dart test -p chrome --compiler dart2wasm`, with no simulated platform.
+@TestOn('browser')
+library;
+
+import 'package:dio/dio.dart';
+import 'package:test/test.dart';
+import 'package:typed_openapi_client/typed_openapi_client.dart';
+import 'package:typed_openapi_dio/typed_openapi_dio.dart';
+
+import 'helpers/fake_adapter.dart';
+
+void main() {
+  const getPet = OperationInfo(
+    operationId: 'getPet',
+    method: 'GET',
+    pathTemplate: '/pets/{petId}',
+  );
+  const request = OperationRequest(
+    getPet,
+    path: [PathParameter('petId', 7)],
+  );
+
+  Result<Object?, Never> decode(RawResponse r) => switch (r.statusCode) {
+    200 => r.success(r.json),
+    _ => r.undocumented(),
+  };
+
+  Future<Result<Object?, Never>> send(
+    FakeAdapter adapter, {
+    OperationRequest operation = request,
+  }) => ClientSender(
+    DioTransport(
+      Dio(BaseOptions(baseUrl: 'https://api.test'))
+        ..httpClientAdapter = adapter,
+    ),
+  ).send(operation, decode);
+
+  test('the platform is detected without configuration', () {
+    expect(DioTransport(Dio()).isWeb, isTrue);
+  });
+
+  test('the default Dio adapter cannot stream events and says so', () async {
+    final result = await ClientSender(DioTransport(Dio()))
+        .openEvents<String, Never>(
+          const OperationRequest(
+            getPet,
+            path: [PathParameter('petId', 7)],
+            streamStatuses: {200},
+          ),
+          (message) => message.data,
+          (response) => response.undocumented(),
+        );
+    final error = result as TransportError<Stream<SseItem<String>>, Never>;
+    expect(error.exception.message, DioTransport.webStreamingMessage);
+    expect(error.exception.cause, isA<UnsupportedError>());
+  });
+
+  test(
+    'a reconnecting stream on the default adapter fails the same way',
+    () async {
+      var waits = 0;
+      final result = await ClientSender(DioTransport(Dio()))
+          .openEvents<String, Never>(
+            const OperationRequest(
+              getPet,
+              path: [PathParameter('petId', 7)],
+              streamStatuses: {200},
+            ),
+            (message) => message.data,
+            (response) => response.undocumented(),
+            call: CallOptions(
+              sse: SseOptions(reconnect: true, wait: (_) async => waits++),
+            ),
+            reconnection: SseReconnection.on,
+          );
+      final error = result as TransportError<Stream<SseItem<String>>, Never>;
+      expect(error.exception.message, DioTransport.webStreamingMessage);
+      expect(waits, 0);
+    },
+  );
+
+  group('malformed JSON', () {
+    // The client parses the bytes itself, so every compiler reports the
+    // same: the status and the text.
+    for (final body in ['{"id":', '<html>', '{"id": 7}x']) {
+      test('$body is a decode error with its status and text', () async {
+        final result = await send(
+          FakeAdapter.text(200, body, 'application/json'),
+        );
+        final error = result as DecodeError<Object?, Never>;
+        expect(error.statusCode, 200);
+        expect(error.error.pointer, '');
+        expect(
+          error.error.message,
+          'expected a JSON body, got text that is not JSON',
+        );
+        expect(error.rawBody, body);
+      });
+    }
+
+    test('a text operation never reads JSON, so a failure is transport', () {
+      final adapter = FakeAdapter((_) => throw const FormatException('x'));
+      return expectLater(
+        send(
+          adapter,
+          operation: const OperationRequest(
+            getPet,
+            path: [PathParameter('petId', 7)],
+            responseKind: .text,
+          ),
+        ),
+        completion(isA<TransportError<Object?, Never>>()),
+      );
+    });
+  });
+
+  test('a FormatException from an interceptor is a transport failure, never '
+      'a decode error', () async {
+    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
+      ..httpClientAdapter = FakeAdapter.json(200, {'id': 7})
+      ..interceptors.add(
+        InterceptorsWrapper(
+          onRequest: (options, handler) {
+            Uri.parse('http://[bad');
+          },
+        ),
+      );
+    final result = await ClientSender(DioTransport(dio)).send(request, decode);
+    expect(result, isA<TransportError<Object?, Never>>());
+  });
+
+  test('valid JSON and an empty body are not decode errors', () async {
+    final ok = await send(
+      FakeAdapter.json(200, {'id': 7, 'name': 'Rex'}),
+    );
+    expect((ok as Success<Object?, Never>).data, {'id': 7, 'name': 'Rex'});
+    final empty = await send(FakeAdapter.text(200, '', 'application/json'));
+    expect((empty as Success<Object?, Never>).data, isNull);
+  });
+}
diff --git a/pubspec.yaml b/pubspec.yaml
index 4c26e0c..411e2fb 100644
--- a/pubspec.yaml
+++ b/pubspec.yaml
@@ -11,4 +11,5 @@ dev_dependencies:
 workspace:
   - packages/typed_openapi
   - packages/typed_openapi_client
+  - packages/typed_openapi_dio
   - packages/typed_openapi_tool
diff --git a/packages/typed_openapi_dio/lib/src/dio_transport.dart b/packages/typed_openapi_dio/lib/src/dio_transport.dart
index 650556e..5d93391 100644
--- a/packages/typed_openapi_dio/lib/src/dio_transport.dart
+++ b/packages/typed_openapi_dio/lib/src/dio_transport.dart
@@ -40,6 +40,15 @@ final class DioTransport implements ClientTransport {
       'ConversionLayerAdapter from package:dio_compatibility_layer with '
       'package:http\'s BrowserClient or package:fetch_client.';
 
+  /// The [OperationInfo] of the request [options] describe, for an
+  /// interceptor: its tags and security; null for a request this transport
+  /// did not send.
+  static OperationInfo? operationOf(RequestOptions options) =>
+      switch (options.extra[OperationInfo.extraKey]) {
+        final OperationInfo info => info,
+        _ => null,
+      };
+
   @override
   Future<TransportResponse> send(TransportRequest request) async {
     if (request.isEventStream && isWeb && _hasDefaultAdapter) {
diff --git a/packages/typed_openapi_dio/test/dio_transport_test.dart b/packages/typed_openapi_dio/test/dio_transport_test.dart
index 45c7453..4771795 100644
--- a/packages/typed_openapi_dio/test/dio_transport_test.dart
+++ b/packages/typed_openapi_dio/test/dio_transport_test.dart
@@ -54,7 +54,8 @@ void main() {
     final sent = adapter.requests.single;
     expect(sent.uri.toString(), 'https://api.test/v1/pets/7');
     expect((sent.method, sent.headers['X-Trace']), ('GET', 't1'));
-    expect(sent.extra[OperationInfo.extraKey], getPet);
+    expect(DioTransport.operationOf(sent), getPet);
+    expect(DioTransport.operationOf(RequestOptions()), isNull);
   });
 
   test('the query keeps // under a base URL (allowReserved)', () async {
~~~~

#### Part 4c: Generated code takes a `ClientTransport`

**Files:** see the Files table (task 4, part c).

- [ ] **Step 1: Apply the patch** below.
- [ ] **Step 2: Regenerate the goldens**

```sh
cd packages/typed_openapi && UPDATE_GOLDENS=1 dart test \
  test/emit/api_library_test.dart test/emit/generated_code_test.dart \
  test/emit/event_stream_emit_test.dart
git diff -U0 -- '*golden*' | grep '^[-+] ' | sort | uniq -c | sort -rn
```

Expected: 7 golden files change (40 lines in, 38 out), only in the lines decision 7 names: `import 'package:dio/dio.dart' show Dio;` goes, `ClientSender` and `ClientTransport` join the client's `show` list (the root file imports `ClientTransport`), `PetsApi(ClientTransport transport) : _sender = ClientSender(transport);`, `final ClientSender _sender;`, the root `ApiClient(ClientTransport transport) : ... = PetsApi(transport)`, and the doc lines "Sends the requests through [transport].", "Creates the client: every group sends through [transport].", "... of the spec. The transport sets the base URL."

- [ ] **Step 3: Verify the generator**: `dart test` in `packages/typed_openapi` gives `+1376 ~1` (the generated-client package builds with `typed_openapi_dio` and passes `dart analyze --fatal-infos`; `calls`, `wire_calls`, `union_calls`, `hostile_events` print what they printed through `DioRequestSender`).
- [ ] **Step 4: Fuzz**: `cd packages/typed_openapi_tool && dart run bin/fuzz.dart --seeds 200` prints `200 seeds: 1200 builds, 10907 files, 17 sampled; 0 problems.`
- [ ] **Step 5: Corpus**: `dart run bin/corpus.dart update`, then the filtered diff of Task 1 Step 5 is empty (only file hashes change). Tool `+198`.
- [ ] **Step 6: Gate of task 4**: every suite of the Global Constraints green (generator `+1376 ~1`, client `+305` and `+289` in Chrome with both compilers, adapter `+11` and `+21`, tool `+198`), analyze clean, format 0 changes.
- [ ] **Step 7: Commit** the whole task: `feat!: send through a ClientTransport` (body: the client core sends through a `ClientTransport`, `typed_openapi_dio` adapts a `Dio`, generated clients take a transport).

~~~~diff
diff --git a/packages/typed_openapi/CHANGELOG.md b/packages/typed_openapi/CHANGELOG.md
index a1b383a..35286a4 100644
--- a/packages/typed_openapi/CHANGELOG.md
+++ b/packages/typed_openapi/CHANGELOG.md
@@ -4,6 +4,13 @@
 - Generated files import `package:typed_openapi_client/typed_openapi_client.dart`
   in place of `package:typed_openapi_runtime/typed_openapi_runtime.dart`: the
   runtime package is renamed (M11b).
+- Groups and the root client take a `ClientTransport` in place of a `Dio`
+  and send through `ClientSender` in place of `DioRequestSender`; generated
+  files no longer import `package:dio`. A Dio user writes
+  `ApiClient(DioTransport(dio))` with `package:typed_openapi_dio`. Schemas
+  named `Dio` keep their name; `ClientSender`, `ClientTransport`,
+  `CancelSignal` and the other transport types of the client are taken
+  (TOA551). TOA566 names the transport's base URL (M11b).
 - A model with an optional constant (a `const` or one-value `enum` the
   schema does not require) remembers which of them the decoded JSON did
   not have, in a private `_absent` list, and `toJson` leaves those out, so
diff --git a/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart b/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart
index 21434ed..4ed386b 100644
--- a/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart
+++ b/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart
@@ -387,7 +387,7 @@ enum DiagnosticCode {
   querystringNotGenerated('TOA565', 'querystring-not-generated', .warning),
 
   /// A path item or an operation has its own `servers`; the client sends
-  /// every request to the base URL of the user's Dio.
+  /// every request to the base URL of the user's transport.
   operationServersIgnored('TOA566', 'operation-servers-ignored', .warning),
 
   /// An operation has `callbacks`, or the document has `webhooks`: requests
diff --git a/packages/typed_openapi/lib/src/emit/api_library.dart b/packages/typed_openapi/lib/src/emit/api_library.dart
index e2fe203..484eabc 100644
--- a/packages/typed_openapi/lib/src/emit/api_library.dart
+++ b/packages/typed_openapi/lib/src/emit/api_library.dart
@@ -86,7 +86,7 @@ final class ApiLibrary {
   String _root(ClientIr ir, Map<String, String> groupFiles) {
     final root = ir.root;
     final imports = Imports(rootFile(root.name))
-      ..show('package:dio/dio.dart', 'Dio');
+      ..fromRuntime('ClientTransport');
     for (final group in ir.groups) {
       imports.file('$directory/${groupFiles[group.name]}');
     }
@@ -99,7 +99,7 @@ final class ApiLibrary {
       ..line()
       ..prose(
         'The client of the API: a field for each group of operations, and '
-        'the servers of the spec. Set the base URL on your Dio.',
+        'the servers of the spec. The transport sets the base URL.',
       )
       ..block('class ${root.name}', () {
         _constructor(out, ir);
@@ -121,13 +121,13 @@ final class ApiLibrary {
   /// when it fits.
   void _constructor(DartWriter out, ClientIr ir) {
     out.prose(
-      'Creates the client: every group sends through [dio], which it uses '
-      'as it is.',
+      'Creates the client: every group sends through [transport].',
     );
     final initializers = [
-      for (final group in ir.groups) '${group.field} = ${group.name}(dio)',
+      for (final group in ir.groups)
+        '${group.field} = ${group.name}(transport)',
     ];
-    final head = '${ir.root.name}(Dio dio)';
+    final head = '${ir.root.name}(ClientTransport transport)';
     final flat = initializers.isEmpty
         ? '$head;'
         : '$head : ${initializers.join(', ')};';
diff --git a/packages/typed_openapi/lib/src/emit/decoder_writer.dart b/packages/typed_openapi/lib/src/emit/decoder_writer.dart
index 15372b8..bbe9d13 100644
--- a/packages/typed_openapi/lib/src/emit/decoder_writer.dart
+++ b/packages/typed_openapi/lib/src/emit/decoder_writer.dart
@@ -14,10 +14,10 @@ final class DecoderWriter {
 
   static const _code = DartCode();
 
-  /// How Dio reads the body of every status: by the successes' media
+  /// How the client reads the body of every status: by the successes' media
   /// types; errors of a text or binary operation are parsed from it. A
-  /// binary error makes the whole operation bytes, since Dio would turn the
-  /// bytes of a JSON operation into text.
+  /// binary error makes the whole operation bytes, since the client would
+  /// turn the bytes of a JSON operation into text.
   static String responseKind(OperationIr operation) {
     // An event stream reads its body itself, and its error bodies parsed.
     if (operation.events != null) return 'json';
diff --git a/packages/typed_openapi/lib/src/emit/operation_emitter.dart b/packages/typed_openapi/lib/src/emit/operation_emitter.dart
index da98fe1..47886b0 100644
--- a/packages/typed_openapi/lib/src/emit/operation_emitter.dart
+++ b/packages/typed_openapi/lib/src/emit/operation_emitter.dart
@@ -13,7 +13,7 @@ import 'type_codec.dart';
 
 /// Writes the class of a [GroupIr] (decisions 1–3, 5–10 of M9): a plain
 /// class, so `implements` mocks it (R10.7), with a method per operation that
-/// builds an `OperationRequest` and sends it through `DioRequestSender`;
+/// builds an `OperationRequest` and sends it through `ClientSender`;
 /// then the sealed types of the operations' statuses and the classes of
 /// their multipart parts. [RequestWriter] writes the request,
 /// [DecoderWriter] the decoder, [StatusTypeEmitter] and [PartsEmitter] the
@@ -37,23 +37,22 @@ final class OperationEmitter {
   static const _code = DartCode();
   static const _names = DartNames();
 
-  /// The runtime library generated code imports.
-  static const _dio = 'package:dio/dio.dart';
-
   /// Writes [group] and the types of its operations to [out].
   void write(GroupIr group, DartWriter out) {
     final name = group.name;
     _codec.imports
-      ..show(_dio, 'Dio')
-      ..fromRuntime('DioRequestSender');
+      ..fromRuntime('ClientSender')
+      ..fromRuntime('ClientTransport');
     final members = _privateNames(group);
     out.prose('The operations of the `${_code.docSpan(name)}` group.');
     out.block('class $name', () {
       out
-        ..prose('Sends the requests through [dio], which it uses as it is.')
-        ..line('$name(Dio dio) : _sender = DioRequestSender(dio);')
+        ..prose('Sends the requests through [transport].')
+        ..line(
+          '$name(ClientTransport transport) : _sender = ClientSender(transport);',
+        )
         ..line()
-        ..line('final DioRequestSender _sender;');
+        ..line('final ClientSender _sender;');
       for (final (operation, info, _) in members) {
         out.line();
         _info(out, operation, info);
diff --git a/packages/typed_openapi/lib/src/ir/names.dart b/packages/typed_openapi/lib/src/ir/names.dart
index 03c01d8..46a6238 100644
--- a/packages/typed_openapi/lib/src/ir/names.dart
+++ b/packages/typed_openapi/lib/src/ir/names.dart
@@ -50,9 +50,9 @@ final class DartNames {
 
   /// Type names a generated library sees without importing them: those of
   /// `dart:core`, `Uint8List` of `dart:typed_data`, the names of
-  /// `typed_openapi_client` that generated code uses, and `Dio`, the one
-  /// name the API files import from `package:dio` (so its other exports,
-  /// such as `Response`, `Options` and `Headers`, stay free for schemas).
+  /// `typed_openapi_client` that generated code uses. Generated code imports
+  /// nothing from an HTTP client, so `Dio`, `Response` or `Options` stay
+  /// free for schemas.
   static const takenTypeNames = {
     // dart:core
     'ArgumentError', 'AssertionError', 'BigInt', 'BidirectionalIterator',
@@ -70,8 +70,7 @@ final class DartNames {
     // typed_openapi_client
     'CallOptions', 'CancelSignal', 'Cancelled', 'ClientSender',
     'ClientTransport', 'CookieParameter', 'Date', 'DecodeError',
-    'DeepEquality',
-    'DioRequestSender', 'Failure', 'FileUpload', 'FormBody', 'FormEncoding',
+    'DeepEquality', 'Failure', 'FileUpload', 'FormBody', 'FormEncoding',
     'HeaderParameter', 'HttpError',
     'JsonDecodeException', 'JsonReader', 'JsonValue', 'MultipartBody',
     'MultipartPart', 'OperationInfo',
@@ -85,8 +84,6 @@ final class DartNames {
     'Success', 'TransportError', 'TransportException',
     'TransportExceptionKind', 'TransportRequest', 'TransportResponse',
     'UndocumentedStatus',
-    // package:dio, which the API files import with `show Dio` only.
-    'Dio',
   };
 
   /// Members every Dart object has.
diff --git a/packages/typed_openapi/lib/src/ir/operation_checks.dart b/packages/typed_openapi/lib/src/ir/operation_checks.dart
index 941256e..c18f5d4 100644
--- a/packages/typed_openapi/lib/src/ir/operation_checks.dart
+++ b/packages/typed_openapi/lib/src/ir/operation_checks.dart
@@ -32,7 +32,7 @@ final class OperationChecks {
   }
 
   /// Reports `servers` of the path item and of the operation (TOA566): the
-  /// client sends every request to the Dio base URL.
+  /// client sends every request to the base URL of its transport.
   void servers(SpecOperation entry) {
     for (final (node, servers, what) in [
       (entry.item, entry.item.servers, 'path item'),
@@ -42,10 +42,10 @@ final class OperationChecks {
       _context.report(
         .operationServersIgnored,
         'The $what has servers of its own; the client sends its requests to '
-        'the base URL of your Dio.',
+        'the base URL of its transport.',
         node.location.child('servers'),
         fix:
-            'Set the base URL for these requests in an interceptor, or move '
+            'Send these requests through a transport with that base URL, or move '
             'the servers to the document.',
       );
     }
diff --git a/packages/typed_openapi/lib/src/model/media_type_name.dart b/packages/typed_openapi/lib/src/model/media_type_name.dart
index e0a45a1..fc925ae 100644
--- a/packages/typed_openapi/lib/src/model/media_type_name.dart
+++ b/packages/typed_openapi/lib/src/model/media_type_name.dart
@@ -2,7 +2,7 @@
 ///
 /// This is the one definition of a JSON media type the generator uses, for
 /// the kind of a body and for the encoding of a part. It is the runtime's
-/// (`MediaTypeText`): `text/json` is JSON, as Dio reads it.
+/// (`MediaTypeText`): `text/json` is JSON, as the client reads it.
 extension type const MediaTypeName(String value) {
   /// The type and subtype in lower case, without parameters.
   String get base => value.split(';').first.trim().toLowerCase();
diff --git a/packages/typed_openapi/test/emit/generated_client_test.dart b/packages/typed_openapi/test/emit/generated_client_test.dart
index 0382d6b..7220386 100644
--- a/packages/typed_openapi/test/emit/generated_client_test.dart
+++ b/packages/typed_openapi/test/emit/generated_client_test.dart
@@ -28,6 +28,7 @@ void main() {
       final runtime = p.normalize(
         p.absolute(p.join('..', 'typed_openapi_client')),
       );
+      final dio = p.normalize(p.absolute(p.join('..', 'typed_openapi_dio')));
       temp
         ..write('pubspec.yaml', '''
 name: fixture
@@ -38,6 +39,12 @@ dependencies:
   dio: ^5.11.1
   typed_openapi_client:
     path: ${runtime.replaceAll(r'\', '/')}
+  typed_openapi_dio:
+    path: ${dio.replaceAll(r'\', '/')}
+dependency_overrides:
+  # typed_openapi_dio depends on the hosted client; use the one here.
+  typed_openapi_client:
+    path: ${runtime.replaceAll(r'\', '/')}
 dev_dependencies:
   lints: ^6.1.0
 ''')
@@ -202,14 +209,14 @@ success 200
   reconnecting 1 after 1000ms
   reconnecting 2 after 1500ms
   reconnecting 3 after 1500ms
-  end connectionError
+  end connection
 waits [1000, 1500, 1500]
   event message # Thread(id: t1, replies: null)
   reconnecting 1 after 1000ms
-  end cancel
+  end cancelled
 requests 1
   event message # Thread(id: t1, replies: null)
-  end cancel
+  end cancelled
   delta Hi
   usage 3
   note plain text
diff --git a/packages/typed_openapi/test/emit/programs/calls.dart.txt b/packages/typed_openapi/test/emit/programs/calls.dart.txt
index a1c94b0..45a7f5f 100644
--- a/packages/typed_openapi/test/emit/programs/calls.dart.txt
+++ b/packages/typed_openapi/test/emit/programs/calls.dart.txt
@@ -8,6 +8,7 @@ import 'dart:convert';
 import 'dart:typed_data';
 
 import 'package:dio/dio.dart';
+import 'package:typed_openapi_dio/typed_openapi_dio.dart';
 import 'package:fixture/petstore_raw/api_client.dart';
 import 'package:typed_openapi_client/typed_openapi_client.dart';
 
@@ -86,7 +87,7 @@ String describe(Object? value) => switch (value) {
 
 String request(Adapter adapter) {
   final options = adapter.requests.last;
-  final info = OperationInfo.of(options);
+  final info = DioTransport.operationOf(options);
   return '${options.method} ${options.uri} '
       '[${info?.operationId}; ${info?.security.map((a) => a.join('+')).join('|')}]';
 }
@@ -95,7 +96,7 @@ Future<void> main() async {
   final adapter = Adapter();
   final dio = Dio(BaseOptions(baseUrl: 'https://pets.example.com/v1'))
     ..httpClientAdapter = adapter;
-  final client = ApiClient(dio);
+  final client = ApiClient(DioTransport(dio));
   final pets = client.pets;
 
   print('server ${ApiClient.server1(region: 'us')} ${ApiClient.server2}');
@@ -228,8 +229,8 @@ Future<void> main() async {
   )));
   print('extra ${adapter.requests.last.headers['X-Extra']}');
 
-  final token = CancelToken()..cancel('stop');
-  print(show(await client.defaultApi.health(call: CallOptions(cancelToken: token))));
+  final token = CancelSignal()..cancel('stop');
+  print(show(await client.defaultApi.health(call: CallOptions(cancel: token))));
 
   adapter.answers.add(() => throw DioException.connectionError(
     requestOptions: RequestOptions(),
diff --git a/packages/typed_openapi/test/emit/programs/hostile_events.dart.txt b/packages/typed_openapi/test/emit/programs/hostile_events.dart.txt
index 0efd9db..9830aa1 100644
--- a/packages/typed_openapi/test/emit/programs/hostile_events.dart.txt
+++ b/packages/typed_openapi/test/emit/programs/hostile_events.dart.txt
@@ -8,6 +8,7 @@ import 'dart:convert';
 import 'dart:typed_data';
 
 import 'package:dio/dio.dart';
+import 'package:typed_openapi_dio/typed_openapi_dio.dart';
 import 'package:fixture/events_hostile_raw/api_client.dart';
 import 'package:typed_openapi_client/typed_openapi_client.dart';
 
@@ -53,7 +54,7 @@ Future<void> main() async {
   }
   // No event field and an empty one are both `message`.
   text.write('data: plain\n\nevent:\ndata: empty\n\n');
-  final client = ApiClient(Dio()..httpClientAdapter = Adapter('$text'));
+  final client = ApiClient(DioTransport(Dio()..httpClientAdapter = Adapter('$text')));
   final result = await client.defaultApi.feed();
   if (result case Success(:final data)) {
     await for (final item in data) {
diff --git a/packages/typed_openapi/test/emit/programs/stream_calls.dart.txt b/packages/typed_openapi/test/emit/programs/stream_calls.dart.txt
index b9890ec..5b567ff 100644
--- a/packages/typed_openapi/test/emit/programs/stream_calls.dart.txt
+++ b/packages/typed_openapi/test/emit/programs/stream_calls.dart.txt
@@ -8,6 +8,7 @@ import 'dart:convert';
 import 'dart:typed_data';
 
 import 'package:dio/dio.dart';
+import 'package:typed_openapi_dio/typed_openapi_dio.dart';
 import 'package:fixture/chat_override_raw/api_client.dart' as overridden;
 import 'package:fixture/chat_raw/api_client.dart';
 import 'package:typed_openapi_client/typed_openapi_client.dart';
@@ -64,7 +65,7 @@ String describe<T>(SseItem<T> item) => switch (item) {
   SseDecodeError(:final error) => 'decode error ${error.pointer}',
   SseReconnecting(:final attempt, :final delay) =>
     'reconnecting $attempt after ${delay.inMilliseconds}ms',
-  SseDisconnected(cause: DioException(:final type)) => 'end ${type.name}',
+  SseDisconnected(cause: TransportException(:final kind)) => 'end ${kind.name}',
   SseDisconnected(cause: HttpError(:final statusCode)) => 'end http $statusCode',
   SseDisconnected(:final cause) => 'end ${cause ?? 'closed'}',
 };
@@ -84,8 +85,8 @@ Future<void> printAll<T, E>(Result<Stream<SseItem<T>>, E> result) async {
 }
 
 ApiClient client(Adapter adapter) =>
-    ApiClient(Dio(BaseOptions(baseUrl: 'https://chat.example.com'))
-      ..httpClientAdapter = adapter);
+    ApiClient(DioTransport(Dio(BaseOptions(baseUrl: 'https://chat.example.com'))
+      ..httpClientAdapter = adapter));
 
 Future<void> main() async {
   // Events of a JSON type, a decode error mid-stream, a disconnect.
@@ -175,12 +176,12 @@ Future<void> main() async {
   print('waits $waits');
 
   // Cancelling during the wait before an attempt ends the stream.
-  final token = CancelToken();
+  final token = CancelSignal();
   adapter = Adapter([(_) => events('data: {"id": "t1"}\n\n')]);
   final waiting = await client(adapter).threads.watchThread(
     threadId: 't',
     call: CallOptions(
-      cancelToken: token,
+      cancel: token,
       sse: SseOptions(reconnect: true, wait: (_) => Completer<void>().future),
     ),
   );
@@ -193,7 +194,7 @@ Future<void> main() async {
   print('requests ${adapter.requests.length}');
 
   // Cancelling while events arrive ends the stream without a reconnect.
-  final live = CancelToken();
+  final live = CancelSignal();
   final body = StreamController<Uint8List>();
   adapter = Adapter([
     (_) => ResponseBody(
@@ -207,7 +208,7 @@ Future<void> main() async {
   final open = await client(adapter).threads.watchThread(
     threadId: 't',
     call: CallOptions(
-      cancelToken: live,
+      cancel: live,
       sse: const SseOptions(reconnect: true),
     ),
   );
@@ -251,8 +252,8 @@ Future<void> main() async {
   // by default, only the stream method.
   print('overridden');
   overridden.ApiClient other(Adapter adapter) => overridden.ApiClient(
-    Dio(BaseOptions(baseUrl: 'https://chat.example.com'))
-      ..httpClientAdapter = adapter,
+    DioTransport(Dio(BaseOptions(baseUrl: 'https://chat.example.com'))
+      ..httpClientAdapter = adapter),
   );
   adapter = Adapter([
     (_) => events('event: ping\ndata: {}\n\nevent: done\ndata: \n\n'),
diff --git a/packages/typed_openapi/test/emit/programs/union_calls.dart.txt b/packages/typed_openapi/test/emit/programs/union_calls.dart.txt
index 0668486..bfdffe4 100644
--- a/packages/typed_openapi/test/emit/programs/union_calls.dart.txt
+++ b/packages/typed_openapi/test/emit/programs/union_calls.dart.txt
@@ -7,6 +7,7 @@
 import 'dart:convert';
 
 import 'package:dio/dio.dart';
+import 'package:typed_openapi_dio/typed_openapi_dio.dart';
 import 'package:fixture/discriminator_scalars_raw/api_client.dart';
 import 'package:fixture/optional_constant_structural/api_client.dart'
     as optional;
@@ -35,7 +36,7 @@ Future<void> main() async {
   final adapter = Adapter();
   final dio = Dio(BaseOptions(baseUrl: 'https://values.example.com'))
     ..httpClientAdapter = adapter;
-  final api = ApiClient(dio).defaultApi;
+  final api = ApiClient(DioTransport(dio)).defaultApi;
 
   // A value that is not an object has no discriminator property: it is
   // picked by its JSON type, an integer before a number, and the first
@@ -57,7 +58,7 @@ Future<void> main() async {
 
   // A model decoded without its optional constants writes none of them; one
   // made in code writes them all, so the two are not equal.
-  final facets = optional.ApiClient(dio).defaultApi;
+  final facets = optional.ApiClient(DioTransport(dio)).defaultApi;
   adapter.answers.add(() => json(200, {'field': 'f'}));
   print('facet -> ${show(await facets.getFacet())}');
   for (final body in [
diff --git a/packages/typed_openapi/test/emit/programs/wire_calls.dart.txt b/packages/typed_openapi/test/emit/programs/wire_calls.dart.txt
index 802732a..ab84aff 100644
--- a/packages/typed_openapi/test/emit/programs/wire_calls.dart.txt
+++ b/packages/typed_openapi/test/emit/programs/wire_calls.dart.txt
@@ -7,6 +7,7 @@ import 'dart:convert';
 import 'dart:typed_data';
 
 import 'package:dio/dio.dart';
+import 'package:typed_openapi_dio/typed_openapi_dio.dart';
 import 'package:fixture/wire_raw/api_client.dart';
 import 'package:typed_openapi_client/typed_openapi_client.dart';
 
@@ -36,7 +37,7 @@ Future<void> main() async {
   final adapter = Adapter();
   final dio = Dio(BaseOptions(baseUrl: 'https://wire.example.com'))
     ..httpClientAdapter = adapter;
-  final wire = ApiClient(dio).wire;
+  final wire = ApiClient(DioTransport(dio)).wire;
 
   // A parameter or a part named like a function the code calls is renamed.
   adapter.answers.add(() => empty(204));
diff --git a/packages/typed_openapi/test/ir/operation_contract_test.dart b/packages/typed_openapi/test/ir/operation_contract_test.dart
index 3d53037..a865bf4 100644
--- a/packages/typed_openapi/test/ir/operation_contract_test.dart
+++ b/packages/typed_openapi/test/ir/operation_contract_test.dart
@@ -218,7 +218,7 @@ paths:
   });
 
   group('names the API files import', () {
-    test('a schema named like a dio export other than Dio keeps its name', () {
+    test('a schema named like a Dio export keeps its name', () {
       final ir = build(
         IrFixture(r'''
 openapi: 3.1.0
@@ -258,7 +258,7 @@ components:
           'Response',
           'Options',
           'Headers',
-          'DioModel',
+          'Dio',
           'FileUploadModel',
           'SecuritySchemeModel',
         ]),
diff --git a/packages/typed_openapi/test/ir/transport_names_test.dart b/packages/typed_openapi/test/ir/transport_names_test.dart
new file mode 100644
index 0000000..19530ab
--- /dev/null
+++ b/packages/typed_openapi/test/ir/transport_names_test.dart
@@ -0,0 +1,42 @@
+import 'package:test/test.dart';
+import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
+
+import '../helpers/ir_fixture.dart';
+
+void main() {
+  test('Dio names stay free; the transport names of the client are taken', () {
+    final fixture = IrFixture(r'''
+openapi: 3.1.0
+info: {title: t, version: "1"}
+paths:
+  /a:
+    get:
+      operationId: read
+      responses:
+        "200":
+          description: ok
+          content:
+            application/json:
+              schema:
+                type: object
+                properties:
+                  r: {$ref: '#/components/schemas/Response'}
+                  d: {$ref: '#/components/schemas/Dio'}
+                  t: {$ref: '#/components/schemas/ClientTransport'}
+components:
+  schemas:
+    Response: {type: object, properties: {id: {type: string}}}
+    Dio: {type: object, properties: {id: {type: string}}}
+    ClientTransport: {type: object, properties: {id: {type: string}}}
+''');
+    final names = [for (final d in fixture.build().declarations) d.name];
+    expect(names, containsAll(['Response', 'Dio', 'ClientTransportModel']));
+    expect(
+      [
+        for (final d in fixture.reportedOf(DiagnosticCode.nameReserved))
+          d.pointer?.value,
+      ],
+      ['#/components/schemas/ClientTransport'],
+    );
+  });
+}
diff --git a/packages/typed_openapi_tool/lib/src/corpus/corpus_package.dart b/packages/typed_openapi_tool/lib/src/corpus/corpus_package.dart
index c2f05d7..93f767d 100644
--- a/packages/typed_openapi_tool/lib/src/corpus/corpus_package.dart
+++ b/packages/typed_openapi_tool/lib/src/corpus/corpus_package.dart
@@ -83,7 +83,6 @@ publish_to: none
 environment:
   sdk: ">=3.10.0 <4.0.0"
 dependencies:
-  dio: ^5.11.1
   typed_openapi_client:
     path: ${_quoted(runtime)}
 dev_dependencies:
diff --git a/packages/typed_openapi_tool/lib/src/fuzz/fuzz_spec.dart b/packages/typed_openapi_tool/lib/src/fuzz/fuzz_spec.dart
index 7b716ec..458312c 100644
--- a/packages/typed_openapi_tool/lib/src/fuzz/fuzz_spec.dart
+++ b/packages/typed_openapi_tool/lib/src/fuzz/fuzz_spec.dart
@@ -21,7 +21,7 @@ final class FuzzSpec {
     'Error',
     'Request',
     'Unknown',
-    'Dio',
+    'Transport',
   ];
   static const _methods = ['get', 'post', 'patch', 'put', 'delete'];
   static const _id = {
~~~~

### Task 5: Conformance server and suite

Replayed on the state after task 4 (scratch commit `6fbaad0`).

**Files:** `packages/typed_openapi_transport_tests/` (`publish_to: none`, `resolution: workspace`, added to the root workspace): `lib/src/conformance_server.dart` (`ConformanceServer.start()`: a `dart:io` `HttpServer` on `127.0.0.1:0` with CORS headers and `OPTIONS`, a `closedPort` for the refused case; routes `/echo`, `/status/<code>`, `/bytes`, `/large` (100000 bytes with `Content-Length`), `/slow` (5 s), `/events` (`bufferOutput = false`; without `Last-Event-ID` one event with `id: 1` and close, with it `data: after <id>` and the connection held)), `lib/src/server_main.dart` (`hybridMain` for `spawnHybridUri`, sends `[port, closedPort]`), `lib/src/transport_conformance.dart` (`TransportConformance(create, {skips}).register()`, plus the test "every skip names a case"), `lib/src/conformance_context.dart` and the case files `request_cases.dart` (7), `response_cases.dart` (5), `failure_cases.dart` (3), `event_cases.dart` (1). `typed_openapi_dio/test/conformance_test.dart` replaces task 5's `loopback_test.dart` and skips the event case in a browser (`DioTransport` refuses event streams with Dio's default browser adapter, decision 9).

Replay findings folded in:

- The form case expects `a=x%20y&b=1`: the core's `FormBody` encodes a space as `%20` (RFC 3986), as the runtime did.
- Under dart2wasm the ports cross the hybrid channel as doubles: `ConformanceContext.start` reads them as `num` and calls `toInt()`.
- The event case cancels on the event after `one` (a first draft cancelled on `seen.length == 2`, which the `reconnecting` item reached first, and hung). Dio's IO adapter does end an open body on cancel; no core change is needed (a defensive core wrapper was tried and dropped: the hang was the test's).
- Not done: a `test/quality/size_limits_test.dart` in the new packages (their files are all under 160 lines); listed under Deferred.

Steps: `git rm packages/typed_openapi_dio/test/loopback_test.dart`, apply the patch, `dart pub get` at the root.

~~~~diff
diff --git a/packages/typed_openapi_dio/pubspec.yaml b/packages/typed_openapi_dio/pubspec.yaml
index 2fe0caa..39f2e68 100644
--- a/packages/typed_openapi_dio/pubspec.yaml
+++ b/packages/typed_openapi_dio/pubspec.yaml
@@ -16,5 +16,6 @@ dependencies:
 dev_dependencies:
   stream_channel: ^2.1.0
   test: ^1.24.0
+  typed_openapi_transport_tests: any
 
 resolution: workspace
diff --git a/packages/typed_openapi_dio/test/conformance_test.dart b/packages/typed_openapi_dio/test/conformance_test.dart
new file mode 100644
index 0000000..951f019
--- /dev/null
+++ b/packages/typed_openapi_dio/test/conformance_test.dart
@@ -0,0 +1,16 @@
+import 'package:dio/dio.dart';
+import 'package:typed_openapi_dio/typed_openapi_dio.dart';
+import 'package:typed_openapi_transport_tests/typed_openapi_transport_tests.dart';
+
+void main() {
+  final isWeb = DioTransport(Dio()).isWeb;
+  TransportConformance(
+    (baseUrl) => DioTransport(Dio(BaseOptions(baseUrl: '$baseUrl'))),
+    skips: {
+      if (isWeb)
+        'events arrive, reconnect with Last-Event-ID and end on cancel':
+            "Dio's default browser adapter delivers a body only when the "
+            'connection closes, so DioTransport refuses event streams there.',
+    },
+  ).register();
+}
diff --git a/packages/typed_openapi_transport_tests/README.md b/packages/typed_openapi_transport_tests/README.md
new file mode 100644
index 0000000..8dd5d73
--- /dev/null
+++ b/packages/typed_openapi_transport_tests/README.md
@@ -0,0 +1,20 @@
+# typed_openapi_transport_tests
+
+The conformance suite of typed_openapi transports (not published). Every
+`ClientTransport` runs the same cases against a loopback HTTP server that
+the suite starts in a hybrid isolate, so the cases also run in a browser:
+
+```dart
+void main() {
+  TransportConformance(
+    (baseUrl) => DioTransport(Dio(BaseOptions(baseUrl: '$baseUrl'))),
+    skips: {'<case name>': '<why this transport cannot meet it>'},
+  ).register();
+}
+```
+
+A skip must name a case (a test checks it) and say why. The cases cover the
+method, target and headers, JSON, form, multipart and streamed bodies, send
+and receive progress, error and undocumented statuses, binary bodies, a
+refused connection, a cancel before and during a call, and an event stream
+that reconnects with `Last-Event-ID` and ends on cancel.
diff --git a/packages/typed_openapi_transport_tests/lib/src/conformance_context.dart b/packages/typed_openapi_transport_tests/lib/src/conformance_context.dart
new file mode 100644
index 0000000..7eff79a
--- /dev/null
+++ b/packages/typed_openapi_transport_tests/lib/src/conformance_context.dart
@@ -0,0 +1,86 @@
+import 'dart:async';
+
+import 'package:stream_channel/stream_channel.dart';
+import 'package:test/test.dart';
+import 'package:typed_openapi_client/typed_openapi_client.dart';
+
+/// What the cases share: the running server, the transport under test and
+/// the skips.
+final class ConformanceContext {
+  /// Creates the context for the transports [_create] makes.
+  ConformanceContext(this._create, this._skips);
+
+  final ClientTransport Function(Uri baseUrl) _create;
+  final Map<String, String> _skips;
+  final Set<String> _names = {};
+
+  // Set by [start], which `setUpAll` runs before any case reads them.
+  late StreamChannel<Object?> _channel;
+  late Uri _baseUrl;
+  late int _closedPort;
+
+  /// Starts the server in a hybrid isolate (the VM, also for a browser
+  /// test) and waits for its ports.
+  Future<void> start() async {
+    _channel = spawnHybridUri(
+      'package:typed_openapi_transport_tests/src/server_main.dart',
+    );
+    // Under dart2wasm a number from the hybrid isolate arrives as a double.
+    final [port as num, closed as num] =
+        await _channel.stream.first as List<Object?>;
+    _baseUrl = Uri.parse('http://127.0.0.1:${port.toInt()}');
+    _closedPort = closed.toInt();
+  }
+
+  /// Stops the server.
+  Future<void> stop() => _channel.sink.close();
+
+  /// A sender through a new transport for the server.
+  ClientSender get sender => ClientSender(_create(_baseUrl));
+
+  /// A sender through a transport for a port nothing listens on.
+  ClientSender get refusedSender =>
+      ClientSender(_create(_baseUrl.replace(port: _closedPort)));
+
+  /// Declares the case [name] as a test, skipped when the transport says
+  /// so.
+  void testCase(String name, Future<void> Function() body) {
+    _names.add(name);
+    test(name, body, skip: _skips[name]);
+  }
+
+  /// Fails when a skip names no case: a renamed case must not stay skipped.
+  void checkSkips() =>
+      expect(_skips.keys.where((name) => !_names.contains(name)), isEmpty);
+
+  /// The JSON object an `/echo` request answers with.
+  static Result<Map<String, Object?>, Never> echo(RawResponse response) =>
+      switch (response.statusCode) {
+        200 => response.success(response.jsonObject),
+        _ => response.undocumented(),
+      };
+
+  /// A request of [method] to [target] (path and query), with [body].
+  static OperationRequest request(
+    String target, {
+    String method = 'GET',
+    List<QueryParameter> query = const [],
+    List<HeaderParameter> headers = const [],
+    Object? body,
+    String? contentType,
+    ResponseKind responseKind = .json,
+    Set<int> streamStatuses = const {},
+  }) => OperationRequest(
+    OperationInfo(
+      operationId: 'conformance',
+      method: method,
+      pathTemplate: target,
+    ),
+    query: query,
+    headers: headers,
+    body: body,
+    contentType: contentType,
+    responseKind: responseKind,
+    streamStatuses: streamStatuses,
+  );
+}
diff --git a/packages/typed_openapi_transport_tests/lib/src/conformance_server.dart b/packages/typed_openapi_transport_tests/lib/src/conformance_server.dart
new file mode 100644
index 0000000..790a1e2
--- /dev/null
+++ b/packages/typed_openapi_transport_tests/lib/src/conformance_server.dart
@@ -0,0 +1,109 @@
+import 'dart:async';
+import 'dart:convert';
+import 'dart:io';
+
+/// The loopback HTTP server the conformance cases call: it echoes requests,
+/// answers with a status, bytes or a large body, holds a request back, and
+/// streams server-sent events. It runs on the VM, in the test's own process
+/// or, for a browser test, in a hybrid isolate (`server_main.dart`).
+final class ConformanceServer {
+  ConformanceServer._(this._server, this.closedPort);
+
+  /// Starts the server on `127.0.0.1` and an ephemeral port.
+  static Future<ConformanceServer> start() async {
+    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
+    final closedPort = closed.port;
+    await closed.close();
+    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
+    return ConformanceServer._(server, closedPort).._listen();
+  }
+
+  final HttpServer _server;
+
+  /// A port nothing listens on, for the connection-refused case.
+  final int closedPort;
+
+  /// The port the server listens on.
+  int get port => _server.port;
+
+  /// Stops the server and drops its open connections.
+  Future<void> close() => _server.close(force: true);
+
+  void _listen() => _server.listen((request) async {
+    final response = request.response;
+    // Browsers call from another origin: allow every method and header,
+    // and let the client read the headers the cases check.
+    response.headers
+      ..set('access-control-allow-origin', '*')
+      ..set('access-control-allow-methods', '*')
+      ..set('access-control-allow-headers', '*')
+      ..set('access-control-expose-headers', '*');
+    if (request.method == 'OPTIONS') return response.close();
+    final segments = request.uri.pathSegments;
+    switch (segments) {
+      case ['echo', ...]:
+        await _echo(request);
+      case ['status', final code]:
+        response.statusCode = int.parse(code);
+        _json(response, {'code': 'status $code'});
+        await response.close();
+      case ['bytes']:
+        response.headers.contentType = ContentType.binary;
+        response.add([0, 1, 2, 254, 255]);
+        await response.close();
+      case ['large']:
+        final body = List<int>.filled(100000, 0x61);
+        response.headers
+          ..contentType = ContentType.text
+          ..contentLength = body.length;
+        response.add(body);
+        await response.close();
+      case ['slow']:
+        await Future<void>.delayed(const Duration(seconds: 5));
+        await response.close();
+      case ['events']:
+        await _events(request);
+      default:
+        response.statusCode = 404;
+        await response.close();
+    }
+  });
+
+  static Future<void> _echo(HttpRequest request) async {
+    final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
+    final headers = <String, String>{};
+    request.headers.forEach((name, values) => headers[name] = values.join(','));
+    request.response.headers.set('x-answer', 'echoed');
+    _json(request.response, {
+      'method': request.method,
+      'target': '${request.uri}',
+      'headers': headers,
+      'body': utf8.decode(body, allowMalformed: true),
+      'length': body.length,
+    });
+    await request.response.close();
+  }
+
+  /// Without `Last-Event-ID`: an event with id `1`, then the connection
+  /// closes. With it: one event that names the id, then the connection
+  /// stays open until the client leaves.
+  static Future<void> _events(HttpRequest request) async {
+    final response = request.response
+      // Unbuffered, so each event leaves when it is written.
+      ..bufferOutput = false
+      ..headers.contentType = ContentType('text', 'event-stream');
+    final lastId = request.headers.value('last-event-id');
+    if (lastId == null) {
+      response.write('id: 1\ndata: one\n\n');
+      await response.close();
+      return;
+    }
+    response.write('data: after $lastId\n\n');
+    await response.flush();
+  }
+
+  static void _json(HttpResponse response, Object? body) {
+    response.headers.contentType = ContentType.json;
+    response.write(jsonEncode(body));
+  }
+}
diff --git a/packages/typed_openapi_transport_tests/lib/src/event_cases.dart b/packages/typed_openapi_transport_tests/lib/src/event_cases.dart
new file mode 100644
index 0000000..8e4ba22
--- /dev/null
+++ b/packages/typed_openapi_transport_tests/lib/src/event_cases.dart
@@ -0,0 +1,52 @@
+import 'package:test/test.dart';
+import 'package:typed_openapi_client/typed_openapi_client.dart';
+
+import 'conformance_context.dart';
+
+/// The cases of event streams: events arrive as they are written, a
+/// reconnection sends `Last-Event-ID`, a cancel ends the stream.
+final class EventCases {
+  /// Creates the cases on [context].
+  const EventCases(this.context);
+
+  /// The server and the transport under test.
+  final ConformanceContext context;
+
+  /// Declares the cases.
+  void register() {
+    context.testCase(
+      'events arrive, reconnect with Last-Event-ID and end on cancel',
+      _reconnect,
+    );
+  }
+
+  Future<void> _reconnect() async {
+    final signal = CancelSignal();
+    final result = await context.sender.openEvents<String, Never>(
+      ConformanceContext.request('/events', streamStatuses: {200}),
+      (message) => message.data,
+      (response) => response.undocumented(),
+      call: CallOptions(
+        cancel: signal,
+        sse: SseOptions(reconnect: true, wait: (_) async {}),
+      ),
+      reconnection: .on,
+    );
+    final seen = <String>[];
+    final items = (result as Success<Stream<SseItem<String>>, Never>).data;
+    await for (final item in items) {
+      switch (item) {
+        case SseEvent(:final data):
+          seen.add(data);
+          if (data != 'one') signal.cancel();
+        case SseReconnecting():
+          seen.add('reconnecting');
+        case SseDisconnected(cause: TransportException(:final kind)):
+          seen.add('end ${kind.name}');
+        case _:
+          seen.add('$item');
+      }
+    }
+    expect(seen, ['one', 'reconnecting', 'after 1', 'end cancelled']);
+  }
+}
diff --git a/packages/typed_openapi_transport_tests/lib/src/failure_cases.dart b/packages/typed_openapi_transport_tests/lib/src/failure_cases.dart
new file mode 100644
index 0000000..58bcd03
--- /dev/null
+++ b/packages/typed_openapi_transport_tests/lib/src/failure_cases.dart
@@ -0,0 +1,56 @@
+import 'dart:async';
+
+import 'package:test/test.dart';
+import 'package:typed_openapi_client/typed_openapi_client.dart';
+
+import 'conformance_context.dart';
+
+/// The cases of failures: a refused connection and cancellation before and
+/// during a call.
+final class FailureCases {
+  /// Creates the cases on [context].
+  const FailureCases(this.context);
+
+  /// The server and the transport under test.
+  final ConformanceContext context;
+
+  /// Declares the cases.
+  void register() {
+    context
+      ..testCase('a refused connection is a connection failure', _refused)
+      ..testCase('a cancel before the call sends nothing', _cancelBefore)
+      ..testCase('a cancel in flight is Cancelled', _cancelInFlight);
+  }
+
+  Future<void> _refused() async {
+    final result = await context.refusedSender.send(
+      ConformanceContext.request('/echo'),
+      ConformanceContext.echo,
+    );
+    final failure = result as TransportError<Map<String, Object?>, Never>;
+    expect(failure.exception.kind, TransportExceptionKind.connection);
+  }
+
+  Future<void> _cancelBefore() async {
+    final signal = CancelSignal()..cancel('early');
+    final result = await context.sender.send(
+      ConformanceContext.request('/echo'),
+      ConformanceContext.echo,
+      call: CallOptions(cancel: signal),
+    );
+    expect(result, isA<Cancelled<Map<String, Object?>, Never>>());
+  }
+
+  Future<void> _cancelInFlight() async {
+    final signal = CancelSignal();
+    final watch = Stopwatch()..start();
+    Timer(const Duration(milliseconds: 200), signal.cancel);
+    final result = await context.sender.send(
+      ConformanceContext.request('/slow'),
+      ConformanceContext.echo,
+      call: CallOptions(cancel: signal),
+    );
+    expect(result, isA<Cancelled<Map<String, Object?>, Never>>());
+    expect(watch.elapsed, lessThan(const Duration(seconds: 4)));
+  }
+}
diff --git a/packages/typed_openapi_transport_tests/lib/src/request_cases.dart b/packages/typed_openapi_transport_tests/lib/src/request_cases.dart
new file mode 100644
index 0000000..95bbbdc
--- /dev/null
+++ b/packages/typed_openapi_transport_tests/lib/src/request_cases.dart
@@ -0,0 +1,153 @@
+import 'dart:convert';
+import 'dart:typed_data';
+
+import 'package:test/test.dart';
+import 'package:typed_openapi_client/typed_openapi_client.dart';
+
+import 'conformance_context.dart';
+
+/// The cases of the request on the wire: method, target, headers, bodies
+/// and send progress, as the server's `/echo` saw them.
+final class RequestCases {
+  /// Creates the cases on [context].
+  const RequestCases(this.context);
+
+  /// The server and the transport under test.
+  final ConformanceContext context;
+
+  /// Declares the cases.
+  void register() {
+    context
+      ..testCase('the method, target and headers arrive', _target)
+      ..testCase('PUT, PATCH and DELETE keep their method', _methods)
+      ..testCase('a JSON body arrives with its type and length', _json)
+      ..testCase('a form body arrives', _form)
+      ..testCase('a multipart body arrives whole', _multipart)
+      ..testCase('a file stream arrives with its length', _stream)
+      ..testCase('send progress reaches the length', _sendProgress);
+  }
+
+  Future<Map<String, Object?>> _echo(
+    OperationRequest request, {
+    CallOptions? call,
+  }) async {
+    final result = await context.sender.send(
+      request,
+      ConformanceContext.echo,
+      call: call,
+    );
+    return (result as Success<Map<String, Object?>, Never>).data;
+  }
+
+  Future<void> _target() async {
+    final echo = await _echo(
+      ConformanceContext.request(
+        '/echo',
+        query: [const QueryParameter('q', 'a b/c')],
+        headers: [const HeaderParameter('X-Trace', 't1')],
+      ),
+      call: const CallOptions(headers: {'X-Call': 'c1'}),
+    );
+    expect(echo['method'], 'GET');
+    expect(echo['target'], '/echo?q=a%20b%2Fc');
+    final headers = echo['headers']! as Map<String, Object?>;
+    expect((headers['x-trace'], headers['x-call']), ('t1', 'c1'));
+  }
+
+  Future<void> _methods() async {
+    for (final method in ['PUT', 'PATCH', 'DELETE']) {
+      final echo = await _echo(
+        ConformanceContext.request('/echo', method: method),
+      );
+      expect(echo['method'], method);
+    }
+  }
+
+  Future<void> _json() async {
+    final echo = await _echo(
+      ConformanceContext.request(
+        '/echo',
+        method: 'POST',
+        body: {
+          'name': 'Rex',
+          'tags': ['a'],
+        },
+        contentType: 'application/json',
+      ),
+    );
+    expect(echo['body'], '{"name":"Rex","tags":["a"]}');
+    expect(echo['length'], 27);
+    final headers = echo['headers']! as Map<String, Object?>;
+    expect(headers['content-type'], startsWith('application/json'));
+  }
+
+  Future<void> _form() async {
+    final echo = await _echo(
+      ConformanceContext.request(
+        '/echo',
+        method: 'POST',
+        body: const FormBody({'a': 'x y', 'b': 1}),
+        contentType: 'application/x-www-form-urlencoded',
+      ),
+    );
+    expect(echo['body'], 'a=x%20y&b=1');
+  }
+
+  Future<void> _multipart() async {
+    final echo = await _echo(
+      ConformanceContext.request(
+        '/echo',
+        method: 'POST',
+        body: MultipartBody([
+          const MultipartPart.value('name', 'Rex'),
+          MultipartPart.file(
+            'photo',
+            FileUpload.bytes(
+              Uint8List.fromList([1, 2, 3]),
+              filename: 'p.bin',
+              contentType: 'application/octet-stream',
+            ),
+          ),
+        ]),
+        contentType: 'multipart/form-data',
+      ),
+    );
+    final body = echo['body']! as String;
+    expect(body, contains('name="name"\r\n\r\nRex\r\n'));
+    expect(body, contains('filename="p.bin"'));
+    expect(body.trimRight(), endsWith('--'));
+  }
+
+  Future<void> _stream() async {
+    final echo = await _echo(
+      ConformanceContext.request(
+        '/echo',
+        method: 'POST',
+        body: FileUpload.stream(
+          Stream.fromIterable([utf8.encode('ab'), utf8.encode('cd')]),
+          length: 4,
+        ),
+        contentType: 'application/octet-stream',
+      ),
+    );
+    expect((echo['body'], echo['length']), ('abcd', 4));
+  }
+
+  Future<void> _sendProgress() async {
+    final counts = <(int, int)>[];
+    await _echo(
+      ConformanceContext.request(
+        '/echo',
+        method: 'POST',
+        body: Uint8List(3000),
+        contentType: 'application/octet-stream',
+      ),
+      call: CallOptions(
+        onSendProgress: (sent, total) {
+          counts.add((sent, total));
+        },
+      ),
+    );
+    expect(counts.last, (3000, 3000));
+  }
+}
diff --git a/packages/typed_openapi_transport_tests/lib/src/response_cases.dart b/packages/typed_openapi_transport_tests/lib/src/response_cases.dart
new file mode 100644
index 0000000..c8f8d75
--- /dev/null
+++ b/packages/typed_openapi_transport_tests/lib/src/response_cases.dart
@@ -0,0 +1,89 @@
+import 'package:test/test.dart';
+import 'package:typed_openapi_client/typed_openapi_client.dart';
+
+import 'conformance_context.dart';
+
+/// The cases of the response as the client reads it: statuses, headers,
+/// bytes and receive progress.
+final class ResponseCases {
+  /// Creates the cases on [context].
+  const ResponseCases(this.context);
+
+  /// The server and the transport under test.
+  final ConformanceContext context;
+
+  /// Declares the cases.
+  void register() {
+    context
+      ..testCase('a documented error status is typed', _error)
+      ..testCase('an undocumented status keeps its body', _undocumented)
+      ..testCase('the response headers arrive', _headers)
+      ..testCase('a binary body arrives as it was sent', _bytes)
+      ..testCase('receive progress counts to the content length', _progress);
+  }
+
+  static Result<Object?, String> _decode(RawResponse r) =>
+      switch (r.statusCode) {
+        200 => r.success(r.body),
+        404 => r.error(r.jsonObject['code']! as String),
+        _ => r.undocumented(),
+      };
+
+  Future<void> _error() async {
+    final result = await context.sender.send(
+      ConformanceContext.request('/status/404'),
+      _decode,
+    );
+    final error = result as HttpError<Object?, String>;
+    expect((error.statusCode, error.body), (404, 'status 404'));
+  }
+
+  Future<void> _undocumented() async {
+    final result = await context.sender.send(
+      ConformanceContext.request('/status/418'),
+      _decode,
+    );
+    final undocumented = result as UndocumentedStatus<Object?, String>;
+    expect(undocumented.statusCode, 418);
+    expect(undocumented.rawBody, {'code': 'status 418'});
+  }
+
+  Future<void> _headers() async {
+    final result = await context.sender.send(
+      ConformanceContext.request('/echo'),
+      ConformanceContext.echo,
+    );
+    final success = result as Success<Map<String, Object?>, Never>;
+    expect(success.headers['x-answer'], ['echoed']);
+    expect(
+      success.headers['content-type']?.single,
+      startsWith('application/json'),
+    );
+  }
+
+  Future<void> _bytes() async {
+    final result = await context.sender.send(
+      ConformanceContext.request('/bytes', responseKind: .bytes),
+      _decode,
+    );
+    expect((result as Success<Object?, String>).data, [0, 1, 2, 254, 255]);
+  }
+
+  Future<void> _progress() async {
+    final counts = <(int, int)>[];
+    final result = await context.sender.send(
+      ConformanceContext.request('/large', responseKind: .text),
+      _decode,
+      call: CallOptions(
+        onReceiveProgress: (received, total) {
+          counts.add((received, total));
+        },
+      ),
+    );
+    expect(
+      ((result as Success<Object?, String>).data! as String).length,
+      100000,
+    );
+    expect(counts.last, (100000, 100000));
+  }
+}
diff --git a/packages/typed_openapi_transport_tests/lib/src/server_main.dart b/packages/typed_openapi_transport_tests/lib/src/server_main.dart
new file mode 100644
index 0000000..e089c62
--- /dev/null
+++ b/packages/typed_openapi_transport_tests/lib/src/server_main.dart
@@ -0,0 +1,15 @@
+import 'package:stream_channel/stream_channel.dart';
+
+import 'conformance_server.dart';
+
+/// Starts a [ConformanceServer] for `spawnHybridUri` and sends its port and
+/// a closed port; the server stops when the test closes the channel.
+///
+/// `package:test` calls this top-level function by its name, so it cannot
+/// be a method.
+Future<void> hybridMain(StreamChannel<Object?> channel) async {
+  final server = await ConformanceServer.start();
+  channel.sink.add([server.port, server.closedPort]);
+  await channel.stream.drain<void>();
+  await server.close();
+}
diff --git a/packages/typed_openapi_transport_tests/lib/src/transport_conformance.dart b/packages/typed_openapi_transport_tests/lib/src/transport_conformance.dart
new file mode 100644
index 0000000..109c221
--- /dev/null
+++ b/packages/typed_openapi_transport_tests/lib/src/transport_conformance.dart
@@ -0,0 +1,44 @@
+import 'package:test/test.dart';
+import 'package:typed_openapi_client/typed_openapi_client.dart';
+
+import 'conformance_context.dart';
+import 'event_cases.dart';
+import 'failure_cases.dart';
+import 'request_cases.dart';
+import 'response_cases.dart';
+
+/// The cases every [ClientTransport] runs against the loopback
+/// [ConformanceServer]: the request on the wire, the response as the
+/// client reads it, failures, cancellation, progress and event streams.
+///
+/// A transport package calls [register] from a test file:
+///
+/// ```dart
+/// void main() => TransportConformance(
+///   (baseUrl) => DioTransport(Dio(BaseOptions(baseUrl: '$baseUrl'))),
+/// ).register();
+/// ```
+final class TransportConformance {
+  /// Creates the suite for the transports [create] makes for a base URL.
+  /// [skips] maps a case name to the reason the transport does not meet
+  /// it on this platform; a name that is not a case throws.
+  TransportConformance(this.create, {this.skips = const {}});
+
+  /// Makes the transport under test for the server's base URL.
+  final ClientTransport Function(Uri baseUrl) create;
+
+  /// The cases skipped, by name, with the reason.
+  final Map<String, String> skips;
+
+  /// Declares the cases as tests, with a server started once for them.
+  void register() {
+    final context = ConformanceContext(create, skips);
+    setUpAll(context.start);
+    tearDownAll(context.stop);
+    group('requests', () => RequestCases(context).register());
+    group('responses', () => ResponseCases(context).register());
+    group('failures', () => FailureCases(context).register());
+    group('events', () => EventCases(context).register());
+    test('every skip names a case', context.checkSkips);
+  }
+}
diff --git a/packages/typed_openapi_transport_tests/lib/typed_openapi_transport_tests.dart b/packages/typed_openapi_transport_tests/lib/typed_openapi_transport_tests.dart
new file mode 100644
index 0000000..08b78a3
--- /dev/null
+++ b/packages/typed_openapi_transport_tests/lib/typed_openapi_transport_tests.dart
@@ -0,0 +1,4 @@
+/// The conformance suite of typed_openapi transports.
+library;
+
+export 'src/transport_conformance.dart' show TransportConformance;
diff --git a/packages/typed_openapi_transport_tests/pubspec.yaml b/packages/typed_openapi_transport_tests/pubspec.yaml
new file mode 100644
index 0000000..3fe92e9
--- /dev/null
+++ b/packages/typed_openapi_transport_tests/pubspec.yaml
@@ -0,0 +1,15 @@
+name: typed_openapi_transport_tests
+description: >
+  The conformance suite of typed_openapi transports: one set of cases that
+  any ClientTransport runs against a loopback HTTP server.
+publish_to: none
+
+environment:
+  sdk: ">=3.10.0 <4.0.0"
+
+dependencies:
+  stream_channel: ^2.1.2
+  test: ^1.24.0
+  typed_openapi_client: ^0.0.1
+
+resolution: workspace
diff --git a/pubspec.yaml b/pubspec.yaml
index 411e2fb..25d3eab 100644
--- a/pubspec.yaml
+++ b/pubspec.yaml
@@ -13,3 +13,4 @@ workspace:
   - packages/typed_openapi_client
   - packages/typed_openapi_dio
   - packages/typed_openapi_tool
+  - packages/typed_openapi_transport_tests
~~~~

**Gate:** `dart analyze packages` clean; `dart format` 0 changed; `cd packages/typed_openapi_dio && dart test` +27; `dart test -p chrome` +37 ~1; `dart test -p chrome --compiler dart2wasm` +37 ~1 (the skip is the event case). Client, generator and tool suites unchanged from task 4.

Commit: `test(typed_openapi_transport_tests): transport conformance suite`.

### Task 6: CI, workspace, publish

Replayed on the state after task 5 (scratch commit `6997d08`).

- `ci.yml`: `typed_openapi_dio` and `typed_openapi_transport_tests` in the format step; a `Test typed_openapi_dio` step (it runs the conformance suite; the suite package has no tests of its own) in the matrix; the web job (renamed "Client and Dio adapter on the web") runs the client and the adapter with both compilers; a dry-run of `typed_openapi_dio`. Inside the workspace the adapter's `typed_openapi_client: ^0.0.1` resolves to the path package (`resolution: workspace`), so its dry-run passes before the client is on pub.dev (0 warnings in the replay).
- `nightly.yml`: a beta-SDK step for `typed_openapi_dio` (`if: always()`).
- `publish.yml`: the tag pattern `typed_openapi_dio-v*` and a header note that a release needing a new client pushes the client's tag first, then the adapter's.
- `workflows_test.dart`: a `directoriesOf` helper and two tests (the adapter on the VM and in Chrome; its dry-run and publish tag).

~~~~diff
diff --git a/.github/workflows/ci.yml b/.github/workflows/ci.yml
index ac56402..519293c 100644
--- a/.github/workflows/ci.yml
+++ b/.github/workflows/ci.yml
@@ -12,7 +12,9 @@ permissions:
 # The platform and SDK matrix of M11 (spec decision 4), every PR:
 # - ubuntu with the minimum SDK (3.10.0) and stable runs every suite; macOS
 #   and Windows run them with stable;
-# - the runtime also runs in Chrome, compiled to JavaScript and to Wasm;
+# - the client core and the Dio adapter (with the transport conformance
+#   suite against its loopback server) also run in Chrome, compiled to
+#   JavaScript and to Wasm;
 # - the corpus job generates the public specs with both SDKs and compares
 #   the output with corpus.lock;
 # - the quick fuzz runs 200 seeds; the semver job checks that a change of
@@ -51,6 +53,8 @@ jobs:
           dart format --output=none --set-exit-if-changed
           packages/typed_openapi
           packages/typed_openapi_client
+          packages/typed_openapi_dio
+          packages/typed_openapi_transport_tests
           packages/typed_openapi_tool
 
       - name: Analyze
@@ -65,6 +69,11 @@ jobs:
         run: dart test
         working-directory: packages/typed_openapi_client
 
+      # The Dio adapter, with the transport conformance suite.
+      - name: Test typed_openapi_dio
+        run: dart test
+        working-directory: packages/typed_openapi_dio
+
       # The SARIF tests read the schema from the corpus cache and fail in CI
       # when it is missing.
       - name: Fetch the SARIF schema
@@ -76,7 +85,7 @@ jobs:
         working-directory: packages/typed_openapi_tool
 
   web:
-    name: Runtime on the web (${{ matrix.compiler }})
+    name: Client and Dio adapter on the web (${{ matrix.compiler }})
     timeout-minutes: 20
     runs-on: ubuntu-latest
     strategy:
@@ -93,10 +102,14 @@ jobs:
       - name: Install dependencies (workspace)
         run: dart pub get
 
-      - name: Test in Chrome
+      - name: Test typed_openapi_client in Chrome
         run: dart test -p chrome --compiler ${{ matrix.compiler }}
         working-directory: packages/typed_openapi_client
 
+      - name: Test typed_openapi_dio in Chrome
+        run: dart test -p chrome --compiler ${{ matrix.compiler }}
+        working-directory: packages/typed_openapi_dio
+
   corpus:
     name: Corpus (${{ matrix.sdk }})
     timeout-minutes: 30
@@ -198,3 +211,7 @@ jobs:
       - name: Dry-run typed_openapi_client
         run: dart pub publish --dry-run
         working-directory: packages/typed_openapi_client
+
+      - name: Dry-run typed_openapi_dio
+        run: dart pub publish --dry-run
+        working-directory: packages/typed_openapi_dio
diff --git a/.github/workflows/nightly.yml b/.github/workflows/nightly.yml
index 34c911c..2a6e9ed 100644
--- a/.github/workflows/nightly.yml
+++ b/.github/workflows/nightly.yml
@@ -41,6 +41,11 @@ jobs:
         run: dart test -p chrome
         working-directory: packages/typed_openapi_client
 
+      - name: Test typed_openapi_dio
+        if: always()
+        run: dart test
+        working-directory: packages/typed_openapi_dio
+
       - name: Check the corpus
         if: always()
         run: dart run bin/corpus.dart check
diff --git a/.github/workflows/publish.yml b/.github/workflows/publish.yml
index 2060295..dd3c4f9 100644
--- a/.github/workflows/publish.yml
+++ b/.github/workflows/publish.yml
@@ -3,6 +3,8 @@
 # Tag convention: <package>-v<version> (e.g. `typed_openapi-v0.1.0`,
 # `typed_openapi_client-v0.1.1`) — only the tagged package is published,
 # matching the repo's "bump only what changed" release policy.
+# typed_openapi_dio depends on typed_openapi_client: a release that needs a
+# new client publishes the client tag first, then the adapter's.
 #
 # Auth is pub.dev's GitHub Actions OIDC flow (no secrets): `dart-lang/setup-dart`
 # mints a temporary pub.dev credential from the job's `id-token`. For it to be
@@ -18,6 +20,7 @@ on:
     tags:
       - 'typed_openapi-v*'
       - 'typed_openapi_client-v*'
+      - 'typed_openapi_dio-v*'
 
 jobs:
   publish:
diff --git a/packages/typed_openapi_tool/test/ci/workflows_test.dart b/packages/typed_openapi_tool/test/ci/workflows_test.dart
index cfcd69c..bf06f7b 100644
--- a/packages/typed_openapi_tool/test/ci/workflows_test.dart
+++ b/packages/typed_openapi_tool/test/ci/workflows_test.dart
@@ -24,6 +24,13 @@ List<String> runsOf(String name, String job) => [
     if (step case {'run': final String run}) run,
 ];
 
+/// The distinct working directories of the steps of the job [job] of the
+/// workflow [name], in order.
+List<String> directoriesOf(String name, String job) => {
+  for (final step in at(name, ['jobs', job, 'steps']) as List<Object?>)
+    if (step case {'working-directory': final String directory}) directory,
+}.toList();
+
 void main() {
   test('every job of every workflow has a timeout', () {
     final folder = Directory(p.join('..', '..', '.github', 'workflows'));
@@ -62,6 +69,30 @@ void main() {
     ]);
   });
 
+  test('every PR tests the Dio adapter on the VM and in Chrome', () {
+    expect(directoriesOf('ci.yml', 'analyze-test'), [
+      'packages/typed_openapi',
+      'packages/typed_openapi_client',
+      'packages/typed_openapi_dio',
+      'packages/typed_openapi_tool',
+    ]);
+    expect(directoriesOf('ci.yml', 'web'), [
+      'packages/typed_openapi_client',
+      'packages/typed_openapi_dio',
+    ]);
+  });
+
+  test('the Dio adapter is dry-run and published by its tag', () {
+    expect(
+      directoriesOf('ci.yml', 'publish-dry-run'),
+      contains('packages/typed_openapi_dio'),
+    );
+    expect(
+      at('publish.yml', ['on', 'push', 'tags']),
+      contains('typed_openapi_dio-v*'),
+    );
+  });
+
   test('every PR checks the corpus with both SDKs, the fuzz and semver', () {
     expect(at('ci.yml', ['jobs', 'corpus', 'strategy', 'matrix', 'sdk']), [
       '3.10.0',
~~~~

**Gate:** `cd packages/typed_openapi_tool && dart test` +200 (198 + the two workflow tests); `dart analyze packages` clean; `cd packages/typed_openapi_dio && dart pub publish --dry-run` 0 warnings.

Commit: `ci: test and publish the client and the Dio adapter`.

### Task 7: Documentation

Replayed on the state after task 6 (scratch commit `f4715dc`).

What changes:

- `CLAUDE.md`: the Project list has the five packages; Commands test and format the adapter and the conformance package; the `emit/` text says groups take a `ClientTransport` (`{Group}(ClientTransport transport)`, `ClientSender.send`, `responseKind`), the generated code imports only the client, and the `calls` program runs through `DioTransport` with `dependency_overrides`; the Runtime section becomes three: "Client core", "Dio transport" and "Transport conformance"; the CI paragraph names the adapter steps; the design rule on the user's HTTP client names `DioTransport`.
- `typed_openapi_client` README (English and Ukrainian) and `doc/`: the setup is `PetshopClient(DioTransport(dio))`; `CallOptions.cancel` takes a `CancelSignal`; progress is counted by the client; `results_and_errors.md` gives `DecodeError` its status and the full text; `request_bodies.md` says the core encodes bodies and a file part without a media type is `application/octet-stream`; `security_metadata.md` reads the metadata with `DioTransport.operationOf`; `sse.md` names `TransportException` as the end cause; `web_and_platforms.md` points at the adapter's tests (the refusal of event streams with Dio's default browser adapter is pinned by `web_test.dart` in Chrome, not by a VM test).
- `typed_openapi_dio/README.md`: setup, interceptors and `operationOf`, cancellation, the failure table, the web, and the release order (the client first).
- The generator's README (English and Ukrainian) and `doc/`: dependencies add `typed_openapi_dio`, every example wraps the `Dio` in `DioTransport`, the root class takes a `ClientTransport`, the `CallOptions` table, `DioTransport.operationOf` in `security.md`, TOA566 and TOA658 say "the user's transport".
- Root README (setup and the package table with the adapter and the conformance package), `CONTRIBUTING.md`, `docs/requirements.md` (R0 names the client), `docs/roadmap.md` (M11b row: R10.1, R10.2, R12.4), `docs/superpowers/HANDOFF.md`, `docs/code-quality-review.md` (moved paths); the doc comment of `part_media_type.dart` names the core's `ParsedMediaType` instead of Dio's `DioMediaType.parse`.

- [ ] **Step 1: Apply the patch** below.
- [ ] **Step 2: Check** that no text outside `docs/superpowers/`, `docs/research/` and the CHANGELOGs names `DioRequestSender`, `typed_openapi_runtime`, `OperationInfo.of(` or `cancelToken`:

```sh
rg -n 'DioRequestSender|typed_openapi_runtime|OperationInfo\.of\(|cancelToken' --glob '*.md' \
  -g '!docs/superpowers/**' -g '!docs/research/**' -g '!**/CHANGELOG.md' -g '!docs/code-quality-plan.md' .
```

Expected: only `docs/roadmap.md` (the M11b row says what was renamed).

- [ ] **Step 3: Final gate** (the whole milestone): generator `+1376 ~1`; client `+305`, Chrome dart2js `+289`, dart2wasm `+289`; adapter `+27`, Chrome dart2js `+37 ~1`, dart2wasm `+37 ~1`; tool `+200`; `dart analyze packages` clean; `dart format` 0 changes in every package; fuzz `200 seeds: 1200 builds, 10907 files, 17 sampled; 0 problems.`; `corpus check` (5 min 35 s): `40 clients, 38 generated, 27759 files; 0 differences from the lock.` (the round-trip counts in the lock included), 224 spec defects listed
- [ ] **Step 4: Commit** `docs: the client core and the Dio adapter`.

~~~~diff
diff --git a/CLAUDE.md b/CLAUDE.md
index 98f7e82..b8bcf8c 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -6,12 +6,17 @@ Guidance for working in this repository.
 
 `typed_openapi` generates Dart clients from OpenAPI 3.x specs, aimed at
 imperfect, code-first specs (NestJS, FastAPI, Spring, ASP.NET). It is a Dart
-pub workspace with three pure-Dart packages (no Flutter):
+pub workspace with five pure-Dart packages (no Flutter):
 
 - `packages/typed_openapi` - the generator: CLI and programmatic API. Never a
   runtime dependency of user apps.
-- `packages/typed_openapi_runtime` - the only package generated clients depend
-  on (typed errors, `Result`, `Patch`, JSON decoding with paths, encoders, SSE).
+- `packages/typed_openapi_client` - the client core, the only package
+  generated clients depend on (typed errors, `Result`, `Patch`, JSON decoding
+  with paths, encoders, request bodies, SSE, the `ClientTransport` contract).
+- `packages/typed_openapi_dio` - `DioTransport`, the transport over the
+  user's `Dio` (M11b).
+- `packages/typed_openapi_transport_tests` - the transport conformance suite
+  and its loopback server. `publish_to: none`.
 - `packages/typed_openapi_tool` - repository tools (M11): the public-spec
   corpus and the escaping fuzz. `publish_to: none`; nothing depends on it.
 
@@ -22,12 +27,12 @@ Minimum SDK: Dart 3.10 (`>=3.10.0 <4.0.0`), also for generated code.
 ```sh
 dart pub get                                 # repo root, once and after pubspec edits
 dart analyze packages                        # repo root; must print "No issues found!"
-cd packages/typed_openapi && dart test       # also in typed_openapi_runtime
-cd packages/typed_openapi_runtime && dart test -p chrome                        # dart2js
-cd packages/typed_openapi_runtime && dart test -p chrome --compiler dart2wasm   # dart2wasm
+cd packages/typed_openapi && dart test       # also in typed_openapi_client, typed_openapi_dio
+cd packages/typed_openapi_client && dart test -p chrome                        # dart2js; also typed_openapi_dio
+cd packages/typed_openapi_client && dart test -p chrome --compiler dart2wasm   # dart2wasm; also typed_openapi_dio
 cd packages/typed_openapi && dart format lib test bin   # a second run must change 0 files
-cd packages/typed_openapi_runtime && dart format lib test # the same
-cd packages/<package> && dart pub publish --dry-run # before publishing
+cd packages/typed_openapi_client && dart format lib test # the same; also typed_openapi_dio, typed_openapi_transport_tests
+cd packages/<package> && dart pub publish --dry-run # before publishing (the client before the Dio transport)
 cd packages/typed_openapi_tool && dart test
 cd packages/typed_openapi_tool && dart format lib test bin # the same
 cd packages/typed_openapi_tool && dart run bin/corpus.dart check  # network on first fetch
@@ -340,8 +345,8 @@ All under `packages/typed_openapi/lib/src/`, one folder per stage:
   stream; any other media type is bytes (`Uint8List`) without its schema and
   the media types that are dropped are named, TOA651, except variants of the
   chosen type and other JSON types; `MediaTypeName.isJson` (`model/`) is
-  the one definition of a JSON media type, `text/json` included, as Dio
-  and the runtime read it; a form or multipart response is bytes,
+  the one definition of a JSON media type, `text/json` included, as the
+  client core reads it; a form or multipart response is bytes,
   TOA650; a text request body is `String`; the `encoding` of a form or
   multipart body (`EncodingIr`, a key that names no property of the body
   schema (also through `$ref`, `allOf`, `oneOf` and `anyOf`; not when the
@@ -374,7 +379,7 @@ All under `packages/typed_openapi/lib/src/`, one folder per stage:
   a parameter style its `in` does not allow falls back to the default,
   TOA564, and an `in: querystring` parameter is skipped, TOA565; path
   variables are `PathTemplate.variable` in `model/path_template.dart`, the
-  runtime's `OperationRequest.pathVariable`, which a test keeps equal) and
+  client's `OperationRequest.pathVariable`, which a test keeps equal) and
   `IrBuilder`
   (operations written as a `$ref` are skipped (TOA107); groups by tag, path
   or one class, with an override `group` (UpperCamelCase, or a value that
@@ -394,14 +399,14 @@ All under `packages/typed_openapi/lib/src/`, one folder per stage:
   object; `PartMediaType` makes each part's `encoding.contentType` one
   concrete type, TOA661 (a type is concrete when it is an RFC 9110 media
   type whose quoted strings hold no control character, a tab included:
-  Dio's `DioMediaType.parse` would throw at call time), and an object part
+  the client's `ParsedMediaType` would throw at call time), and an object part
   that is not JSON a `String` the caller supplies, TOA662); `OperationBuilder` keeps security requirements
   (an alternative that names a scheme `components.securitySchemes` does not
   define, or is not an object (`SecurityRequirement.isMalformed`, also
   TOA111; a `security` field that is not a list is one such requirement at
   the field), is TOA568 and left out as a whole when another alternative can be described;
   when none can, all stay with the scheme of kind `SecurityKind.unknown`
-  (the runtime's `SecuritySchemeType.unknown`), so the metadata never says
+  (the client's `SecuritySchemeType.unknown`), so the metadata never says
   less than the spec: no operation reads as open or as optional), skips
   event streams it cannot express (TOA654) and reports
   operation servers (TOA566), callbacks and webhooks (TOA567) and a missing
@@ -534,7 +539,7 @@ All under `packages/typed_openapi/lib/src/`, one folder per stage:
   a private `_absent` list, which `toJson` leaves out and `==` compares, so
   a decoded value is written back as it came, while a model made in code
   writes every constant, so the two are not equal when a constant was
-  absent; the generated `fromJson` needs a runtime whose
+  absent; the generated `fromJson` needs a client whose
   `JsonReader.constant` returns a bool), `EnumEmitter`, `UnionEmitter` and `ModelLibrary` (`models/<snake>.dart`
   per declaration, names that clash get `2`, `3`...; the barrel
   `models.dart`; the header is `// GENERATED CODE - DO NOT MODIFY BY HAND.`
@@ -626,11 +631,11 @@ All under `packages/typed_openapi/lib/src/`, one folder per stage:
   `OperationEmitter` (with `RequestWriter` for parameters and bodies,
   `DecoderWriter` for the status `switch`, `StatusTypeEmitter` and
   `PartsEmitter` for the types after the class) writes a group: a plain `class` with
-  `{Group}(Dio dio)`, a private `OperationInfo` (tags, security) and a
+  `{Group}(ClientTransport transport)` (a `ClientSender` over it), a private `OperationInfo` (tags, security) and a
   static decoder per operation (private names apart in their own scope),
   methods with named arguments only (`required` for required ones; enum
   arguments take the known values), `body`, then `CallOptions? call`,
-  returning `Future<Result<T, E>>` from `DioRequestSender.send` (a method
+  returning `Future<Result<T, E>>` from `ClientSender.send` (a method
   with `OperationIr.events` returns `Stream<SseItem<T>>` from `openEvents`
   through `EventStreamWriter`: `streamStatuses` are its 2xx statuses, a
   range written once as `for (var s = 200; s < 300; s++) s` and not next to
@@ -643,12 +648,12 @@ All under `packages/typed_openapi/lib/src/`, one folder per stage:
   name (escaped literals), plain variant classes equal by value with
   `<redacted>` for secrets, and the unknown variant `(event, data)`); the
   decoder switches on the status: codes, then ranges, then `default`
-  (every status but 2xx), `_` is `undocumented()`; Dio reads JSON unless
-  every success with a body is text (`text`) or something else is
-  (`bytes`), and then JSON bodies go through `RawResponse.parsedJson`; a
-  documented binary error (`application/octet-stream`, XML, any media type
-  that is not JSON or `text/*`) also makes the operation `bytes`, since Dio
-  would turn its bytes into text. An error body is decoded by the media
+  (every status but 2xx), `_` is `undocumented()`; the request's
+  `responseKind` is JSON unless every success with a body is text
+  (`text`) or something else is (`bytes`), and then JSON bodies go
+  through `RawResponse.parsedJson`; a documented binary error
+  (`application/octet-stream`, XML, any media type that is not JSON or
+  `text/*`) also makes the operation `bytes`, so its bytes are kept. An error body is decoded by the media
   type of its response, as a success is: `r.bytes` for bytes, `r.text` for
   text (an empty one is `''`), the type's decoder for JSON; errors that
   share one body type but not a media type (`text/plain` and JSON strings)
@@ -662,12 +667,15 @@ All under `packages/typed_openapi/lib/src/`, one folder per stage:
   base and wrap `body`, equal by value, with a `toString` that prints the
   body, `<redacted>` for a secret body (`ResponseIr.sensitive`, from
   `ResponseSecrets`) and `Uint8List(<length>)` for bytes) and the parts
-  classes after the group class. Only `Dio` is imported from `package:dio`.
+  classes after the group class. Generated code imports only
+  `package:typed_openapi_client`.
   `test/emit/generated_client_test.dart` builds a package of the clients
   of the fixtures (both `union` modes), runs `dart analyze --fatal-infos`
   on it and runs `test/emit/programs/calls.dart.txt` (`bin/calls.dart`
-  there), which calls the petstore client through a fake Dio adapter and
-  prints every request and result.
+  there), which calls the petstore client through `DioTransport` over a
+  fake Dio adapter and prints every request and result (the package has
+  `dependency_overrides` for `typed_openapi_client`, a path outside the
+  workspace).
 - `generate/` - `OutputWriter` (atomic per run: the whole tree and the
   manifest `.typed_openapi.json` (generator, `format` 2, hash of the inputs,
   every file with its hash) are built in a staging directory next to the
@@ -928,27 +936,39 @@ generator's public API only. Its network use is the `SpecCache` download
 - CI (`.github/workflows/ci.yml`, every PR, top-level `permissions:
   contents: read`): tests on ubuntu with 3.10.0 and stable, on macOS and
   Windows with stable (format and analyze on ubuntu/stable only); the
-  runtime in Chrome with dart2js and dart2wasm; the corpus job (both SDKs:
+  client and the Dio transport (with the conformance suite) in Chrome with
+  dart2js and dart2wasm; publish dry-runs of the generator, the client and
+  the Dio transport; the corpus job (both SDKs:
   `corpus check`, then `corpus fetch sarif_schema` and the SARIF test); 200
   fuzz seeds; semver (pull requests only, full history). Long jobs have
   `timeout-minutes`. `nightly.yml`: the beta SDK (steps with `if: always()`,
   a warning only), the corpus on Windows, 6000 seeds.
   `test/ci/workflows_test.dart` pins these layers.
 
-## Runtime (`packages/typed_openapi_runtime/lib/src/`)
+## Client core (`packages/typed_openapi_client/lib/src/`)
 
-The only package generated clients depend on (dependencies: `dio`, `meta`, floor `^1.15.0` so Flutter's pinned `meta` resolves).
-Pure Dart, works on the web (compiled to JS and to Wasm); SSE needs a
-streaming adapter there (Dio's default browser adapter delivers the body
-only when the connection closes), and cookie parameters do not work (browsers
-drop the `Cookie` header: `test/dio/cookie_browser_test.dart` checks it in
-Chrome against a loopback server, `cookie_server.dart`, started by
-`spawnHybridUri`; its `hybridMain` is the one top-level function a test
-helper has, as `package:test` requires).
-Generated code is expected to look like `test/helpers/pets_api.dart`
-(illustrative, not a contract); `test/generated_client_test.dart` checks
-that the API composes, including an `implements` fake of a tag class.
+The only package generated clients depend on (dependency: `meta`, floor
+`^1.15.0` so Flutter's pinned `meta` resolves). It builds every request and
+reads every response itself and hands finished bytes to a
+`ClientTransport`, so a request is the same on the wire through any
+transport. Pure Dart, works on the web (compiled to JS and to Wasm); SSE
+needs a transport that streams there, and cookie parameters do not work
+(browsers drop the `Cookie` header). Generated code is expected to look
+like `test/helpers/pets_api.dart` (illustrative, not a contract);
+`test/generated_client_test.dart` checks that the API composes, including an
+`implements` fake of a tag class.
 
+- `transport/` - `ClientTransport` (`send(TransportRequest)` completes with
+  a `TransportResponse` of any status once its headers arrived; a request
+  that gets no response, or a body that fails while it is read, is a
+  `TransportException`), `TransportRequest` (method, `target`: the path with
+  the encoded query, which the transport resolves against its own base URL,
+  `operation` (`OperationInfo`), ordered headers, body stream, `cancel`,
+  `extra`, `isEventStream`), `TransportResponse` (status, lower-case
+  headers, body stream read once), `TransportException(kind, message,
+  {cause, stackTrace})` with `TransportExceptionKind` `timeout`,
+  `connection`, `cancelled`, `other`, and `CancelSignal` (a base class: a
+  cancelled signal stays cancelled; `whenCancelled`, `reason`).
 - `json/` - `JsonReader` (strict reads for generated `fromJson`: the only
   widening is int where a number is expected; `null` is an error only in a
   required non-nullable property, an optional one reads it as absent; RFC
@@ -961,68 +981,76 @@ that the API composes, including an `implements` fake of a tag class.
   `Date` (`format: date`, no time or zone), `DeepEquality` (deep `==` and
   `hashCode` of lists, maps and patches for generated models). The barrel
   re-exports `immutable` from `package:meta`, so generated code imports only
-  the runtime. `JsonReader` also has `constant` (which says whether an
+  the client. `JsonReader` also has `constant` (which says whether an
   optional constant was there), `additional` (the keys a
   model does not list, as an unmodifiable map), `patchValue`, `asBytes` and
   `attempt` for generated code.
 - `result/` - sealed `Result<T, E>`: `Success`, `Failure` (`HttpError`,
-  `UndocumentedStatus`, `DecodeError`, `TransportError`, `Cancelled`); no
-  helper methods, pattern matching only. `E = Never` still needs
-  `case Failure()`.
+  `UndocumentedStatus`, `DecodeError`, `TransportError`, `Cancelled`, the
+  last two carrying the `TransportException`); no helper methods, pattern
+  matching only. `E = Never` still needs `case Failure()`.
 - `params/` - `PathParameter`, `QueryParameter`, `HeaderParameter`,
   `CookieParameter` (OAS styles, RFC 6570 expansion, RFC 3986
   percent-encoding; a path expansion that is empty, `.` or `..` throws
   `ArgumentError`, as does a `.`/`..` value); internal `ParameterValue`,
   `PercentEncoder`.
-- `request/` - `OperationInfo` (put into `RequestOptions.extra`; its
-  `security` lists alternatives of `SecurityUse`s of `SecurityScheme`s,
-  metadata only; `SecuritySchemeType.unknown` is a scheme the spec names
-  but does not define), `OperationRequest` (resolves the path and the query
-  itself; `pathVariable` is the one pattern of a path variable, which the
-  generator copies; `streamStatuses` for event streams; `accept` is the
+- `request/` - `OperationInfo` (in every `TransportRequest`; `extraKey` is
+  where the Dio transport puts it; its `security` lists alternatives of
+  `SecurityUse`s of `SecurityScheme`s, metadata only;
+  `SecuritySchemeType.unknown` is a scheme the spec names but does not
+  define), `OperationRequest` (resolves the path and the query itself;
+  `pathVariable` is the one pattern of a path variable, which the generator
+  copies; `responseKind` (`ResponseKind` `json`, `text`, `bytes`) says how
+  the body is read; `streamStatuses` for event streams; `accept` is the
   `Accept` of the method that returns the body of an operation that also
-  has an event-stream method, and a call's own `Accept` wins), `RawResponse` (what
-  a generated decoder switches on; `parsedJson` parses a JSON body that Dio
-  read as text or bytes), and the bodies `FileUpload` (bytes or a stream),
+  has an event-stream method, and a call's own `Accept` wins),
+  `RawResponse` (what a generated decoder switches on; `parse` reads JSON
+  by the content type, `parsedJson` parses a JSON body of a `text` or
+  `bytes` operation), and the bodies `FileUpload` (bytes or a stream),
   `FormBody`/`FormEncoding` and `MultipartBody`/`MultipartPart`, which
-  `DioBody` (`dio/`) turns into form text, `FormData` and bytes or a
-  stream for `DioRequestSender`. A body sent as `application/json` or
-  `+json` is encoded by `DioBody` only where Dio gets it wrong: a `String`
-  (Dio sends it unquoted) and a `null` (Dio sends no body) become JSON
-  text; a map, list, number or boolean stays Dio's data, so an interceptor
-  sees the object. A `null` body with a JSON `contentType` is the JSON
-  `null` of a required nullable body; a `null` body with any other
-  `contentType` sends no `Content-Type`, and a generated method passes no
-  `contentType` for an absent optional body. A file's own `contentType` is
-  checked as a media type (`FormatException`, also on a binary body).
-  `MediaTypeText` (`request/`) is the one definition of a JSON media type
-  (`application/json`, `text/json`, `+json`), also for `RawResponse.isJson`.
-  `MultipartForm` (`dio/`) builds the `FormData` in the order of the parts
-  (Dio writes fields before files, so a text part stays a field only while
-  no file or typed part precedes it; later text parts go as `text/plain`
-  parts); a value that is not a finite JSON scalar, a list in a list, a
-  non-JSON value in a JSON part, or an object with a media type that is not
-  JSON is `ArgumentError`, never stringified.
-- `dio/` - `DioRequestSender(dio, {isWeb})` (`send`, `openEvents`; requests
-  only through `dio.request` (`DioCall`), never mutates the user's Dio,
-  never retries a request (an event stream reconnects only as R12.5 says);
-  `DioResults` maps responses and Dio failures to `Result`s;
-  decoding catches only `DioException`, `JsonDecodeException` and, from the
-  user's decoder, `FormatException` (a converter or `Date.parse` rejecting
-  the data: `DecodeError` at the root pointer, `SseDecodeError` in a
-  stream), `openEvents` also turns an `Exception` raised while reading a
-  non-stream body into `TransportError`, and an `Error` is never caught; the
-  query is
-  built by the runtime, so interceptors see an empty `queryParameters`),
-  `CallOptions` (`sse`: `SseOptions`). `openEvents` needs its stream
+  `BodyEncoder` turns into an `EncodedBody` (bytes or a stream, its length
+  and `Content-Type`): form text, `multipart/form-data` written by
+  `MultipartEncoder` byte for byte as Dio's `FormData` wrote it (the
+  boundary from an injectable source; a text part has no `Content-Type`
+  while no file or typed part precedes it, later ones are `text/plain;
+  charset=utf-8`; a file part without a media type is
+  `application/octet-stream`), a file, JSON text or text. With a JSON
+  `Content-Type` any value is JSON text (a `String` is quoted, `null` is
+  `null`, the JSON `null` of a required nullable body); a `null` body with
+  any other `contentType` sends no `Content-Type`, and a generated method
+  passes no `contentType` for an absent optional body. A file's own
+  `contentType` is checked as a media type (`ParsedMediaType`, the rules
+  of `package:http_parser`; `FormatException`). `MediaTypeText` is the one
+  definition of a JSON media type (`application/json`, `text/json`,
+  `+json`). A value that is not a finite JSON scalar, a list in a list, a
+  non-JSON value in a JSON part, or an object with a media type that is
+  not JSON is `ArgumentError`, never stringified. Do not write a shift
+  past 31 bits or an int literal beyond 2^53 in `lib/`: neither works in
+  JavaScript (the boundary range is the literal `4294967296`).
+- `client/` - `ClientSender(transport)` (`send`, `openEvents`; never
+  retries a request (an event stream reconnects only as R12.5 says)):
+  `RequestBuilder` builds the `TransportRequest` (target, `Accept`, the
+  operation's headers, the call's, `Last-Event-ID`, `Content-Type` and
+  `Content-Length`, nothing else), `ResponseReader` reads the body by
+  `ResponseKind` and counts it for `onReceiveProgress` (`ProgressCounter`,
+  also for `onSendProgress`), `ClientResults` maps responses and
+  `TransportException`s to `Result`s (`Cancelled` for `cancelled`, else
+  `TransportError`); decoding catches only `TransportException`,
+  `JsonDecodeException` and, from the user's decoder, `FormatException` (a
+  converter or `Date.parse` rejecting the data: `DecodeError` at the root
+  pointer, `SseDecodeError` in a stream); another `Exception` while a body
+  is read is a `TransportError` of kind `other`, and an `Error` is never
+  caught. `CallOptions` (`cancel`: `CancelSignal`, `headers`, `extra` for
+  the transport, the progress callbacks, `sse`: `SseOptions`).
+  `EventOpener` opens event streams: `openEvents` needs its stream
   listened to or cancelled; a listener cancel cancels the request. An
   `EventCall` holds what every connection of one call shares, and its
-  `ConnectionTokens` give each connection a cancel token of its own and
-  put one listener, not one per reconnection, on the call's token. A
+  `ConnectionSignals` give each connection a `CancelSignal` of its own and
+  put one listener, not one per reconnection, on the call's signal. A
   `Last-Event-ID` in `call.headers` is where the stream's last event id
-  starts (`DioCall.userLastEventId`): it goes with the first request and the
-  reconnections until an event id replaces it, and an empty `id:` removes
-  it; `DioCall` sends the stream's id only, never both.
+  starts (`RequestBuilder.userLastEventId`): it goes with the first request
+  and the reconnections until an event id replaces it, and an empty `id:`
+  removes it; the stream's id only is sent, never both.
 - `sse/` - `SseDecoder` (WHATWG, bytes -> `SseMessage`; it may start from
   a last event id and retry; it keeps the messages of `SseBlockDecoder`,
   which reports every block, one `SseBlock` per empty line with the
@@ -1050,23 +1078,64 @@ that the API composes, including an `implements` fake of a tag class.
   end the stream; a listener cancel also aborts a request that is in flight
   (`SseReconnector.onCancel`); a pause of the listener, also during a wait
   or a reopen, holds the next connection; an exception or `Error` thrown on
-  an attempt, by a `wait` or an interceptor, is the stream's one error,
+  an attempt, by a `wait` or the transport, is the stream's one error,
   never the zone's. An event id that is not printable ASCII, space or tab is
   not sent as `Last-Event-ID`, on the web too (a browser would send UTF-8,
   but the VM's `HttpClient` rejects it and every reconnection would fail),
-  and the reconnection goes on without it. Use
-  `transformer.bind(stream)`, not `stream.transform`: Dio gives a
-  `Stream<Uint8List>`.
+  and the reconnection goes on without it. Use `transformer.bind(stream)`,
+  not `stream.transform`: a transport may give a `Stream<Uint8List>`.
 
-Runtime tests never touch the network: Dio gets `FakeAdapter`
-(`test/helpers/fake_adapter.dart`), or `GatedAdapter` when a test holds an
-answer back (`test/helpers/gated_adapter.dart`). They also run in Chrome (the two
-commands above; `CHROME_EXECUTABLE` if Chrome is not found): a file that
-needs the VM (`dart:io`, int64 literals, which dart2js rejects) carries
-`@TestOn('vm')`, a single test `testOn: 'vm'`, and `test/dio/web_test.dart`
-is `@TestOn('browser')`. `test/helpers/test_platform.dart` tells the platform
-for assertions that differ. Do not write an int literal beyond 2^53 in
-`lib/`: it does not compile to JavaScript.
+Client tests never touch the network: they send through `FakeTransport`
+(`test/helpers/fake_transport.dart`), or `GatedTransport` when a test holds
+an answer back (`test/helpers/gated_transport.dart`). They also run in
+Chrome (the commands above; `CHROME_EXECUTABLE` if Chrome is not found): a
+file that needs the VM (`dart:io`, int64 literals, which dart2js rejects)
+carries `@TestOn('vm')`, a single test `testOn: 'vm'`.
+`test/helpers/test_platform.dart` tells the platform for assertions that
+differ.
+
+## Dio transport (`packages/typed_openapi_dio/lib/src/`)
+
+`DioTransport(dio, {isWeb})` sends a `TransportRequest` through the user's
+`Dio` (`dio.request` only, never changed, never retried) with
+`ResponseType.stream`, so a `Transformer` or `responseDecoder` is not used
+and the client reads the bytes. An error status goes through the Dio's
+`onError` interceptors and comes back as a response (a `badResponse`
+`DioException` that carries a `ResponseBody`). `DioFailures` maps a
+`DioException` to a `TransportException` (timeouts `timeout`,
+`connectionError` `connection`, `cancel` `cancelled`, else `other`; the
+`DioException` is the cause) and does so for one raised while the body is
+read; an `Error` (Dio wraps it into an `unknown` `DioException`) is thrown
+again. A `CancelSignal` becomes a `CancelToken`; `CallOptions.extra` and the
+`OperationInfo` (`OperationInfo.extraKey`) go into `RequestOptions.extra`,
+and `DioTransport.operationOf(options)` reads it in an interceptor. The
+query is built by the client, so interceptors see an empty
+`queryParameters`; `QueryGuard` joins the base URL itself when the query
+holds `//`, which Dio would collapse. On the web with Dio's default adapter
+an event stream is refused with `webStreamingMessage` (the adapter delivers
+the body only when the connection closes). Inside the workspace its
+`typed_openapi_client: ^0.0.1` resolves to the package next to it
+(`resolution: workspace`); a release that needs a new client publishes the
+client first. Tests: `dio_transport_test.dart` (a fake adapter,
+`test/helpers/fake_adapter.dart`), `web_test.dart` (`@TestOn('browser')`),
+`cookie_browser_test.dart` (the `Cookie` header never reaches a loopback
+server from Chrome, `cookie_server.dart`, started by `spawnHybridUri`; its
+`hybridMain` is the one top-level function a test helper has, as
+`package:test` requires) and `conformance_test.dart`.
+
+## Transport conformance (`packages/typed_openapi_transport_tests/`)
+
+`publish_to: none`. `TransportConformance(create, {skips}).register()`
+declares the cases every `ClientTransport` must pass, against
+`ConformanceServer`, a loopback HTTP server that `server_main.dart`'s
+`hybridMain` starts in a hybrid isolate (so a browser test can use it; its
+ports arrive as numbers, doubles under dart2wasm): the method, target and
+headers, JSON, form, multipart and streamed bodies, send and receive
+progress, error and undocumented statuses, headers and binary bodies, a
+refused connection, a cancel before and during a call, and an event stream
+that reconnects with `Last-Event-ID` and ends on cancel. A skip names a
+case and says why (a test checks that every skip names one);
+`typed_openapi_dio` skips the event stream in a browser.
 
 ## Code rules
 
@@ -1212,8 +1281,9 @@ are not, so follow them by hand:
   everything; no hash-ordered iteration when emitting; no network or `dart fix`
   during generation.
 - A change of generated output is a breaking change of the generator.
-- The user's HTTP client is not ours: generated code never mutates the Dio
-  instance; HTTP errors go through Dio's `onError` and are typed afterwards.
+- The user's HTTP client is not ours: generated code talks to a
+  `ClientTransport` only; `DioTransport` never mutates the Dio instance, and
+  HTTP errors go through Dio's `onError` and are typed afterwards.
 - No `analyzer` dependency in the generator core; tests run `dart analyze` on
   generated fixtures as a subprocess.
 - Escape every string taken from the spec at every interpolation site.
diff --git a/CONTRIBUTING.md b/CONTRIBUTING.md
index 281978f..0941b63 100644
--- a/CONTRIBUTING.md
+++ b/CONTRIBUTING.md
@@ -30,7 +30,7 @@ dart pub get
 
 See the [packages list in the root README](README.md#packages). In short:
 `typed_openapi` is the generator (CLI + programmatic API) and is never a runtime
-dependency of user apps; `typed_openapi_runtime` is the only package generated
+dependency of user apps; `typed_openapi_client` is the only package generated
 clients depend on.
 
 Requirements and research live in [docs/](docs/).
@@ -44,7 +44,7 @@ dart analyze packages
 dart format packages
 
 cd packages/typed_openapi && dart test
-cd packages/typed_openapi_runtime && dart test
+cd packages/typed_openapi_client && dart test
 cd packages/typed_openapi_tool && dart test
 
 # Before publishing a package:
@@ -76,9 +76,9 @@ reintroduces bugs other generators are known for.
   `dart fix` or other SDK-dependent steps during generation.
 - **A change to the generated output is a breaking change** of the generator
   and needs a major version (or an opt-in flag).
-- **The user's HTTP client is not ours.** Generated code never mutates the Dio
-  instance (`baseUrl`, interceptors, `validateStatus`); HTTP errors go through
-  Dio's normal `onError` path and are typed afterwards.
+- **The user's HTTP client is not ours.** Generated code and `DioTransport`
+  never mutate the Dio instance (`baseUrl`, interceptors, `validateStatus`);
+  HTTP errors go through Dio's normal `onError` path and are typed afterwards.
 - **No `analyzer` in the generator core.** Analyzer churns majors every month or
   two; tests run `dart analyze` on generated fixtures as a subprocess.
 - **Escape every string taken from the spec** at every interpolation site.
diff --git a/README.md b/README.md
index 14f0dc5..64f7093 100644
--- a/README.md
+++ b/README.md
@@ -38,10 +38,14 @@ Five minutes, one spec. Add the packages (they are not on pub.dev yet; pin a `re
 ```yaml
 dependencies:
   dio: ^5.11.1
-  typed_openapi_runtime:
+  typed_openapi_client:
     git:
       url: https://github.com/4akloon/typed_openapi.git
-      path: packages/typed_openapi_runtime
+      path: packages/typed_openapi_client
+  typed_openapi_dio:
+    git:
+      url: https://github.com/4akloon/typed_openapi.git
+      path: packages/typed_openapi_dio
 dev_dependencies:
   typed_openapi:
     git:
@@ -109,17 +113,18 @@ errors: 0, warnings: 0, infos: 0
 Generated petstore in lib/src/petstore: 7 files, 7 written, 0 deleted.
 ```
 
-Use the client with your own Dio. The result is a sealed `Result`, so the 404 body arrives as a `Problem`, not as an exception:
+Use the client with your own Dio through `DioTransport`. The result is a sealed `Result`, so the 404 body arrives as a `Problem`, not as an exception:
 
 ```dart
 import 'package:dio/dio.dart';
-import 'package:typed_openapi_runtime/typed_openapi_runtime.dart';
+import 'package:typed_openapi_client/typed_openapi_client.dart';
+import 'package:typed_openapi_dio/typed_openapi_dio.dart';
 
 import 'src/petstore/petstore.dart';
 
 Future<void> main() async {
   final dio = Dio(BaseOptions(baseUrl: PetstoreClient.server));
-  final client = PetstoreClient(dio);
+  final client = PetstoreClient(DioTransport(dio));
 
   switch (await client.pets.getPet(id: 7)) {
     case Success(:final data):
@@ -146,11 +151,11 @@ Against a server that answers `{"id": 7, "name": "Rex", "status": "available"}`
 - **Security metadata** as data on each operation; it never signs a request: [Security](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/security.md).
 - **Works in CI:** exit codes, text, JSON, SARIF and GitHub annotations: [CI](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/ci.md).
 - **Deterministic output** written atomically; it replaces only files it wrote: [Generated output](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generate_output.md).
-- **Runtime on the VM, dart2js and dart2wasm**, with strict JSON decoding that names the JSON pointer of a mismatch: [typed_openapi_runtime](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/README.md).
+- **Runtime on the VM, dart2js and dart2wasm**, with strict JSON decoding that names the JSON pointer of a mismatch: [typed_openapi_client](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/README.md).
 
 ## Documentation
 
-Every guide of both packages. Package READMEs: [typed_openapi](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/README.md), [typed_openapi_runtime](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/README.md).
+Every guide of both packages. Package READMEs: [typed_openapi](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/README.md), [typed_openapi_client](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/README.md).
 
 **The generator, `typed_openapi`**
 
@@ -191,29 +196,31 @@ Every guide of both packages. Package READMEs: [typed_openapi](https://github.co
 | [Spring](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/frameworks/spring.md) | springdoc-openapi. |
 | [ASP.NET Core](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/frameworks/aspnet.md) | What an ASP.NET spec needs. |
 
-**The runtime, `typed_openapi_runtime`**
+**The runtime, `typed_openapi_client`**
 
 | Guide | What it covers |
 | --- | --- |
-| [Getting started](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/getting_started.md) | The runtime in a generated client. |
-| [Results and errors](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/results_and_errors.md) | `Result`, `Failure` and its cases. |
-| [JSON decoding](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/json_decoding.md) | Strict reads, `JsonDecodeException`. |
-| [Patch and nullability](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/patch_and_nullability.md) | Absent, `null`, value. |
-| [Parameters](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/parameters.md) | Styles, encoding, cookies. |
-| [Request bodies](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/request_bodies.md) | Forms, multipart, files. |
-| [Server-Sent Events](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/sse.md) | Decoder, reconnection, cancel. |
-| [Web and platforms](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/web_and_platforms.md) | dart2js, dart2wasm, differences. |
-| [Security metadata](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/security_metadata.md) | `OperationInfo` and schemes. |
+| [Getting started](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/getting_started.md) | The runtime in a generated client. |
+| [Results and errors](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/results_and_errors.md) | `Result`, `Failure` and its cases. |
+| [JSON decoding](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/json_decoding.md) | Strict reads, `JsonDecodeException`. |
+| [Patch and nullability](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/patch_and_nullability.md) | Absent, `null`, value. |
+| [Parameters](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/parameters.md) | Styles, encoding, cookies. |
+| [Request bodies](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/request_bodies.md) | Forms, multipart, files. |
+| [Server-Sent Events](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/sse.md) | Decoder, reconnection, cancel. |
+| [Web and platforms](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/web_and_platforms.md) | dart2js, dart2wasm, differences. |
+| [Security metadata](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/security_metadata.md) | `OperationInfo` and schemes. |
 
 ## Packages
 
 | Package | Role |
 | --- | --- |
 | [`typed_openapi`](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi) | The **generator**: CLI and programmatic API. A dev dependency, never a runtime dependency of your app. |
-| [`typed_openapi_runtime`](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime) | The **runtime** every generated client depends on (with `dio` and `meta`). |
+| [`typed_openapi_client`](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client) | The **client core** every generated client depends on (only `meta`): results, decoding, encoding, event streams, the `ClientTransport` interface. |
+| [`typed_openapi_dio`](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_dio) | The **Dio transport**: `DioTransport` over your own `Dio`. |
+| [`typed_openapi_transport_tests`](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_transport_tests) | The **transport conformance suite**, never published: every transport runs it. |
 | [`typed_openapi_tool`](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_tool) | **Repository tools**, never published: the public-spec corpus and the escaping fuzz. |
 
-The minimum SDK is Dart 3.10 for the generator and for generated code. Translations of the package READMEs: [typed_openapi (Українська)](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/README.ua.md), [typed_openapi_runtime (Українська)](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/README.ua.md).
+The minimum SDK is Dart 3.10 for the generator and for generated code. Translations of the package READMEs: [typed_openapi (Українська)](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/README.ua.md), [typed_openapi_client (Українська)](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/README.ua.md).
 
 ## Status and roadmap
 
diff --git a/docs/code-quality-review.md b/docs/code-quality-review.md
index 0a79fdf..363032e 100644
--- a/docs/code-quality-review.md
+++ b/docs/code-quality-review.md
@@ -110,7 +110,7 @@ In order of size: `yaml_composer.dart` 810, `ir.dart` 733,
 528, `model/operation.dart` 467, `override_resolver.dart` 450,
 `schema_shapes.dart` 446, `json_reader.dart` 422, `union_emitter.dart` 416,
 `normalizer.dart` 383, `model_emitter.dart` 379, `dio_request_sender.dart`
-378, `object_reader.dart` 342, `schema_shape_rules.dart` 341,
+378 (gone in M11b: `ClientSender` and `DioTransport` replace it), `object_reader.dart` 342, `schema_shape_rules.dart` 341,
 `operation_parser.dart` 314.
 
 Notes:
@@ -213,7 +213,7 @@ shrinks. The single source is now the allowlists in the ratchet tests, one per
 package:
 
 - `packages/typed_openapi/test/quality/size_limits_test.dart`
-- `packages/typed_openapi_runtime/test/quality/size_limits_test.dart`
+- `packages/typed_openapi_client/test/quality/size_limits_test.dart`
 
 Each holds a file allowlist (path -> lines), a method allowlist
 (`path#Type.name` -> lines, methods over 40 lines of `lib/`) and the
@@ -275,7 +275,7 @@ Result:
 
   | Rule or flag | Findings |
   | --- | --- |
-  | `strict-casts`, `strict-inference`, `strict-raw-types` | 6 (one in `dio_request_sender.dart`, one is a compile error in a test only strict-casts finds) |
+  | `strict-casts`, `strict-inference`, `strict-raw-types` | 6 (one in `dio_request_sender.dart`, gone in M11b, one is a compile error in a test only strict-casts finds) |
   | `avoid_equals_and_hash_code_on_mutable_classes` | 24 (add `@immutable`) |
   | `comment_references` | 16 |
   | `missing_whitespace_between_adjacent_strings` | 11 (a real bug class in messages) |
diff --git a/docs/requirements.md b/docs/requirements.md
index 4afc9e0..24d2c9a 100644
--- a/docs/requirements.md
+++ b/docs/requirements.md
@@ -18,7 +18,7 @@ Goal: an in-house OpenAPI codegen for Dart that covers the features of competito
    * Each client is a separate library with its own namespace: identical model names (`User`) in two clients do not conflict (R4.3), and there is no shared barrel file between clients.
    * Output directories of different clients cannot overlap: this is an error diagnostic (in swagger_parser, several `schemes` overwrite a shared `export.dart`, #405).
    * The CLI generates or checks all clients together or one by name.
-   * All clients use the same `typed_openapi_runtime`.
+   * All clients use the same `typed_openapi_client` (the runtime, renamed in M11b).
    * Shared models between clients (for example, one error schema for several services) are not in v1.
 
    ```yaml
diff --git a/docs/roadmap.md b/docs/roadmap.md
index 9166304..325ad14 100644
--- a/docs/roadmap.md
+++ b/docs/roadmap.md
@@ -17,6 +17,7 @@ Date: 2026-10-11. Each stage is a separate plan in `superpowers/plans/`, and eac
 | M9 | Operation emitter and `generate` | Groups by tag, root client, parameters and bodies (JSON, multipart, form, binary), responses, typed errors, security metadata, servers; `generate` (which already writes models from M8) adds the operations. Plan: [2026-10-13-m9-operations.md](superpowers/plans/2026-10-13-m9-operations.md) | R5.3, R10.4, R10.6–R10.9, R11.1, R11.4–R11.6 | M8 |
 | M10 | SSE | Methods returning a `Stream` of events, schemas with `itemSchema`, `x-` or override, reconnection with `Last-Event-ID`. Plan: [2026-10-13-m10-sse.md](superpowers/plans/2026-10-13-m10-sse.md) | R12.1, R12.2, R12.4, R12.5 (R12.6 later) | M9, M7 |
 | M11 | Corpus and golden tests | Public specifications (Petstore, Stripe, GitHub, OpenAI, Kubernetes) compile and pass the analyzer; runtime decoding tests; matrix of SDK and formatter versions; fuzz of string escaping. Plan: [2026-10-13-m11-corpus.md](superpowers/plans/2026-10-13-m11-corpus.md) | R15.3, R15.4, R2.6 | M9 |
+| M11b | Transport split | `typed_openapi_runtime` becomes `typed_openapi_client`, a core with no HTTP dependency that builds requests and reads responses itself; generated code takes a `ClientTransport`; `typed_openapi_dio` is the Dio transport; a conformance suite with a loopback server runs every transport on the VM, dart2js and dart2wasm. Plan: [2026-10-19-m11b-transport-split.md](superpowers/plans/2026-10-19-m11b-transport-split.md) | R10.1, R10.2, R12.4 | M11 |
 | M12 | Evolution | `diff` between regenerations with change categories (including source-breaking for an exhaustive `switch`), lock file | R14 | M9 |
 | M13 | Documentation and product | Support matrix, `x-` registry, code catalog, recipes for NestJS / FastAPI / Spring / ASP.NET, JSON Schema of the config, `lint` mode for the backend, optional `build_runner` | R15.2, R15.5, R15.6, R15.1 (partial) | all |
 
diff --git a/docs/superpowers/HANDOFF.md b/docs/superpowers/HANDOFF.md
index 97f450b..ae3d2b5 100644
--- a/docs/superpowers/HANDOFF.md
+++ b/docs/superpowers/HANDOFF.md
@@ -7,6 +7,7 @@ Last updated: 2026-10-13 (M11 merged). Read this first on a new device or in a n
 | Milestone | Design | Plan | Code |
 |---|---|---|---|
 | M1–M11 | merged | merged | **merged** (M10: `bd1cdc3`, M11: `3842bd7`) |
+| M11b transport split: client core, `typed_openapi_dio`, conformance suite | [spec](specs/2026-10-19-m11b-transport-split-design.md) | [plan](plans/2026-10-19-m11b-transport-split.md) | merged |
 | M12 evolution: API snapshot, change report, name lock | [spec](specs/2026-10-13-m12-evolution-design.md) | brief ready: [briefs/m12-plan.md](briefs/m12-plan.md) | next |
 | M13 documentation, lint, distribution, 0.1.0 readiness | [spec](specs/2026-10-13-m13-product-design.md) | brief ready: [briefs/m13-plan.md](briefs/m13-plan.md) | after M12 |
 
diff --git a/packages/typed_openapi/README.md b/packages/typed_openapi/README.md
index e0aa76f..2495baf 100644
--- a/packages/typed_openapi/README.md
+++ b/packages/typed_openapi/README.md
@@ -10,15 +10,19 @@
 
 ## Install
 
-`typed_openapi` is the generator: a dev dependency and a CLI, never a runtime dependency. The generated code depends only on [`typed_openapi_runtime`](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/README.md) and Dio. Neither package is on pub.dev yet, so use git (or a path to a checkout):
+`typed_openapi` is the generator: a dev dependency and a CLI, never a runtime dependency. The generated code depends only on [`typed_openapi_client`](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/README.md); the app adds a transport, such as [`typed_openapi_dio`](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_dio/README.md) over Dio. None of these packages is on pub.dev yet, so use git (or a path to a checkout):
 
 ```yaml
 dependencies:
   dio: ^5.11.1
-  typed_openapi_runtime:
+  typed_openapi_client:
     git:
       url: https://github.com/4akloon/typed_openapi.git
-      path: packages/typed_openapi_runtime
+      path: packages/typed_openapi_client
+  typed_openapi_dio:
+    git:
+      url: https://github.com/4akloon/typed_openapi.git
+      path: packages/typed_openapi_dio
 dev_dependencies:
   typed_openapi:
     git:
@@ -90,17 +94,18 @@ errors: 0, warnings: 0, infos: 0
 Generated petstore in lib/src/petstore: 7 files, 7 written, 0 deleted.
 ```
 
-Use the client with your own Dio. The result is a sealed `Result` you match on, so the 404 body arrives as a `Problem`, not as an exception:
+Use the client with your own Dio through `DioTransport`. The result is a sealed `Result` you match on, so the 404 body arrives as a `Problem`, not as an exception:
 
 ```dart
 import 'package:dio/dio.dart';
-import 'package:typed_openapi_runtime/typed_openapi_runtime.dart';
+import 'package:typed_openapi_client/typed_openapi_client.dart';
+import 'package:typed_openapi_dio/typed_openapi_dio.dart';
 
 import 'src/petstore/petstore.dart';
 
 Future<void> main() async {
   final dio = Dio(BaseOptions(baseUrl: PetstoreClient.server));
-  final client = PetstoreClient(dio);
+  final client = PetstoreClient(DioTransport(dio));
 
   switch (await client.pets.getPet(id: 7)) {
     case Success(:final data):
@@ -125,7 +130,7 @@ Against a server that answers `{"id": 7, "name": "Rex", "status": "available"}`
 - **Request bodies.** JSON, forms, multipart with typed parts, text, bytes and files: [Request bodies](doc/generated/request_bodies.md).
 - **Event streams.** `text/event-stream` operations become `Stream`s with reconnection and typed event unions: [Event streams](doc/generated/event_streams.md).
 - **Security metadata.** Each operation carries its security requirements as data; it never signs requests for you: [Security](doc/generated/security.md).
-- **Your Dio stays yours.** The client uses the `Dio` you pass as it is: interceptors, adapters and options are not touched.
+- **Your Dio stays yours.** `DioTransport` uses the `Dio` you pass as it is: interceptors, adapters and options are not touched.
 - **Safe to run in CI.** [`check`](doc/cli.md) exits non-zero on new errors, a [baseline](doc/baseline.md) accepts the old ones, and output is available as text, JSON, SARIF and GitHub annotations: [CI](doc/ci.md).
 - **Deterministic, and careful with your files.** The same spec and config give byte-identical code. `generate` replaces its output atomically and refuses to delete a file it did not write: [Generated output](doc/generate_output.md).
 
@@ -160,7 +165,7 @@ Exit code `0` means no errors, `1` errors, `64` a usage error and `78` a config
 | [Programmatic API](doc/programmatic_api.md) | Running the checker and the writer from Dart code. |
 | [Troubleshooting](doc/troubleshooting.md) | Common problems and what to do. |
 
-The runtime that generated code depends on has its own guides: [typed_openapi_runtime](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/README.md).
+The runtime that generated code depends on has its own guides: [typed_openapi_client](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/README.md).
 
 ## Contributing and license
 
diff --git a/packages/typed_openapi/README.ua.md b/packages/typed_openapi/README.ua.md
index 0635b24..60ab60a 100644
--- a/packages/typed_openapi/README.ua.md
+++ b/packages/typed_openapi/README.ua.md
@@ -5,7 +5,8 @@
 > **Статус:** рання стадія проєктування, пакет ще не опубліковано.
 
 - Вхід: локальний файл OpenAPI 3.0 / 3.1 / 3.2 (JSON або YAML).
-- Вихід: готовий Dart-код на Dio, без кроку `build_runner`.
+- Вихід: готовий Dart-код без кроку `build_runner`; HTTP іде через транспорт
+  (для Dio — `typed_openapi_dio`).
 - Моделі дотримуються контракту `json_serializable` (`fromJson` / `toJson`).
 - Дефекти специфікації виправляються іменованими правилами нормалізатора і
   потрапляють у звіт як діагностика зі стабільними кодами. Усе неоднозначне
@@ -114,7 +115,7 @@ union — `sealed`.
 містить кореневий клас:
 
 ```dart
-final client = PetstoreClient(dio); // naming.client його перейменовує
+final client = PetstoreClient(DioTransport(dio)); // naming.client його перейменовує
 switch (await client.pets.getPet(petId: 1)) {
   case Success(:final data):
     print(data.name);
@@ -186,7 +187,7 @@ switch (await client.pets.getPet(petId: 1)) {
   з'єднує їх сам, бо Dio схлопнув би `//`; відносний base URL лишається Dio,
   який `//` схлопує.
 - Кожен запит несе `OperationInfo` у `RequestOptions.extra`
-  (`OperationInfo.of(options)`): `operationId`, теги й вимоги безпеки з їхніми
+  (`DioTransport.operationOf(options)`): `operationId`, теги й вимоги безпеки з їхніми
   схемами, для інтерсептора, що додає облікові дані.
 
 `generate` пише каталог виходу цілим. Він будує нове дерево і маніфест
@@ -381,6 +382,6 @@ GitHub показує лише обмежену кількість анотац
 специфікації з багатьма знахідками спершу заведи baseline.
 
 Згенеровані клієнти залежать від
-[`typed_openapi_runtime`](../typed_openapi_runtime/README.ua.md).
+[`typed_openapi_client`](../typed_openapi_client/README.ua.md).
 
 [English version](README.md)
diff --git a/packages/typed_openapi/doc/diagnostics.md b/packages/typed_openapi/doc/diagnostics.md
index 7fffe62..a7a408b 100644
--- a/packages/typed_openapi/doc/diagnostics.md
+++ b/packages/typed_openapi/doc/diagnostics.md
@@ -161,7 +161,7 @@ Operation ids, parameters, groups and Dart names.
 | TOA563 | `client-empty` | warning | No operation of a client is generated: all are filtered out, all are written as a `$ref` (TOA107), or all have an unbound path variable (TOA556). The message says why. | See the message of the diagnostic. |
 | TOA564 | `parameter-style-invalid` | warning | A parameter's `style` is not allowed for its `in` (path takes `simple`, `label` or `matrix`; query `form`, `spaceDelimited`, `pipeDelimited` or `deepObject`; header `simple`; cookie `form` or `cookie`), or the `style` of the `encoding` of a form property is not one a query takes, so the default style is used. | Use one of these styles at the source. |
 | TOA565 | `querystring-not-generated` | warning | A parameter is `in: querystring` (OpenAPI 3.2), which the client cannot send yet: the parameter is not generated (TOA564 until M9). | Describe the query string as query parameters at the source. |
-| TOA566 | `operation-servers-ignored` | warning | A path item or an operation has its own `servers`; the client sends every request to the base URL of the user's Dio. | Set the base URL for these requests in an interceptor, or move the servers to the document. |
+| TOA566 | `operation-servers-ignored` | warning | A path item or an operation has its own `servers`; the client sends every request to the base URL of the user's transport. | Set the base URL for these requests in an interceptor, or move the servers to the document. |
 | TOA567 | `callbacks-not-generated` | info | An operation has `callbacks`, or the document has `webhooks`: requests the server makes, which the client does not generate. | See the message of the diagnostic. |
 | TOA568 | `security-scheme-unknown` | warning | A security requirement names a scheme that `components.securitySchemes` does not have (or defines without a valid type), or is not an object (a string, `null`; also TOA111): the alternative is left out of the operation's metadata when another one can be described, else it stays with a scheme of the kind unknown. | Write the requirement as an object at the source. |
 
@@ -180,7 +180,7 @@ Bodies, responses, defaults and Server-Sent Events.
 | TOA655 | `multipart-not-object` | warning | The schema of a multipart body is not an object with properties (a union, an `allOf`, a map): there is no class of parts, the body is the schema's type, each property of its JSON is a part, and a binary string is sent as base64 text, not as a file. | Describe the body as an object with a property for each part at the source. |
 | TOA656 | `encoding-headers-ignored` | info | An `encoding` entry of a multipart part or of a form property has `headers`, which the client does not send. | Send the headers another way, or remove them at the source. |
 | TOA657 | `response-status-invalid` | warning | A key of an operation's `responses` is not an HTTP status: OpenAPI allows a code from 100 to 599, a range (`1XX` to `5XX`, in either case) and `default`. The response is not generated, so a key written by a tool or by hand can never reach a name or an expression of the client. A key that repeats another one in a different case (`2xx` and `2XX`) is reported the same way. | Rename or remove the key at the source. |
-| TOA658 | `response-status-not-generated` | info | A response documents a 1xx or 3xx status. The client has no result for them (Dio follows redirects and the interim statuses are not responses), so the response is not generated; at run time the status is an undocumented one, or handled by the `default` response when the operation has one. | See the message of the diagnostic. |
+| TOA658 | `response-status-not-generated` | info | A response documents a 1xx or 3xx status. The client has no result for them (the transport follows redirects and the interim statuses are not responses), so the response is not generated; at run time the status is an undocumented one, or handled by the `default` response when the operation has one. | See the message of the diagnostic. |
 | TOA659 | `encoding-key-unknown` | warning | An `encoding` key of a form or multipart body names no property of the body's schema (a misspelled name, a property the schema does not have): the entry is ignored. | Use the name of a property of the schema, or remove the entry. |
 | TOA660 | `default-value-invalid` | warning | The `default` of a parameter does not match the parameter's `enum` or `format` (`default: other` for `enum: [a, b]`, a `format: date` default that is not a date): it is not documented as the default. | Use a default that fits the schema at the source. |
 | TOA661 | `part-media-type-chosen` | info | The `contentType` of an `encoding` entry of a multipart part is a list (`image/png, image/jpeg`), a wildcard (`image/*`) or no media type: the part is sent with one concrete type, the file's own when it has one, else the first concrete type of the list, else `application/octet-stream` for a file and no media type for text. | Name one concrete media type in the encoding at the source. |
diff --git a/packages/typed_openapi/doc/generate_output.md b/packages/typed_openapi/doc/generate_output.md
index 6713b9f..a28ea7e 100644
--- a/packages/typed_openapi/doc/generate_output.md
+++ b/packages/typed_openapi/doc/generate_output.md
@@ -173,7 +173,7 @@ Paths are not part of it, so a checkout in another directory gives the same hash
 .*.typed_openapi-*/
 ```
 
-> **Note:** The generated code imports only `package:typed_openapi_runtime` and `package:dio`. Add both to the app's `dependencies`; see the [runtime package](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/README.md).
+> **Note:** The generated code imports only `package:typed_openapi_client`. Add it and a transport (`typed_openapi_dio` with `dio`) to the app's `dependencies`; see the [runtime package](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/README.md).
 
 ## See also
 
diff --git a/packages/typed_openapi/doc/generated/event_streams.md b/packages/typed_openapi/doc/generated/event_streams.md
index e2be8eb..2d905ac 100644
--- a/packages/typed_openapi/doc/generated/event_streams.md
+++ b/packages/typed_openapi/doc/generated/event_streams.md
@@ -8,11 +8,14 @@ The examples use the `chat.yaml` and `chat.overrides.yaml` test fixtures (OpenAP
 
 ```dart
 import 'package:dio/dio.dart';
-import 'package:typed_openapi_runtime/typed_openapi_runtime.dart';
+import 'package:typed_openapi_client/typed_openapi_client.dart';
+import 'package:typed_openapi_dio/typed_openapi_dio.dart';
 import 'package:my_app/chat/chat.dart';
 
 Future<void> main() async {
-  final chat = ChatApi(Dio(BaseOptions(baseUrl: 'https://api.example.com')));
+  final chat = ChatApi(
+    DioTransport(Dio(BaseOptions(baseUrl: 'https://api.example.com'))),
+  );
 
   final result = await chat.followChat(chatId: 'c1');
   switch (result) {
@@ -50,7 +53,7 @@ The method first returns a `Result`: a status the spec does not list as a stream
 | `SseReconnecting<T>` | The connection ended and a new attempt starts after `delay`. |
 | `SseDisconnected<T>` | Always the last item: the server closed the stream (`cause` is `null`) or it failed. It carries `lastEventId`, `retry` and `receivedMessage`. |
 
-The stream never emits errors; problems are items. The full runtime behaviour (WHATWG parsing, `Last-Event-ID`, backoff, cancellation, web adapters) is in the runtime guide, [SSE](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/sse.md). On the web, the default Dio adapter delivers the body only when the connection closes, so use a streaming adapter there.
+The stream never emits errors; problems are items. The full runtime behaviour (WHATWG parsing, `Last-Event-ID`, backoff, cancellation, web adapters) is in the runtime guide, [SSE](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/sse.md). On the web, the default Dio adapter delivers the body only when the connection closes, so use a streaming adapter there.
 
 > **Note:** `openEvents` needs its stream listened to or cancelled. Cancelling the listener cancels the request. To cancel from outside, pass a `CancelToken` in `CallOptions`, see [Operations](operations.md).
 
@@ -385,4 +388,4 @@ The full catalog, with levels you can change, is in [Diagnostics](../diagnostics
 - [Operations](operations.md) and [Responses and errors](responses_and_errors.md): how the other methods are written.
 - [Overrides](../overrides.md) and [Configuration](../configuration.md): `sse`, `naming.stream_suffix`.
 - [Security](security.md): sending a token with a stream request.
-- Runtime: [SSE](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/sse.md).
+- Runtime: [SSE](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/sse.md).
diff --git a/packages/typed_openapi/doc/generated/models.md b/packages/typed_openapi/doc/generated/models.md
index 24c9a3c..a9dfcea 100644
--- a/packages/typed_openapi/doc/generated/models.md
+++ b/packages/typed_openapi/doc/generated/models.md
@@ -138,7 +138,7 @@ User.fromJson({'id': 1, 'name': 'A', 'createdAt': '2026-01-01T00:00:00'});
 // JsonDecodeException: expected an RFC 3339 date-time string, got a date-time without an offset at /createdAt in User. ...
 ```
 
-You rarely call `fromJson` yourself: a generated method catches the exception and returns it as a `DecodeError` (see [Responses and errors](responses_and_errors.md)). The only widening is an `int` where a number is expected. Details of the reader are in the [runtime guide on JSON decoding](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/json_decoding.md).
+You rarely call `fromJson` yourself: a generated method catches the exception and returns it as a `DecodeError` (see [Responses and errors](responses_and_errors.md)). The only widening is an `int` where a number is expected. Details of the reader are in the [runtime guide on JSON decoding](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/json_decoding.md).
 
 ## Required, optional, nullable
 
@@ -176,7 +176,7 @@ class UserPatch {
 }
 ```
 
-Only PATCH bodies are affected, and only their optional nullable properties. A PATCH body schema that other operations use too is generated as a separate class named with `naming.patch_suffix` (`Patch` by default, `PetPatch`), so the other uses keep plain fields. The override `triState` does the same for one schema or property. See the runtime guide on [patch and nullability](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/patch_and_nullability.md).
+Only PATCH bodies are affected, and only their optional nullable properties. A PATCH body schema that other operations use too is generated as a separate class named with `naming.patch_suffix` (`Patch` by default, `PetPatch`), so the other uses keep plain fields. The override `triState` does the same for one schema or property. See the runtime guide on [patch and nullability](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/patch_and_nullability.md).
 
 ## Constants and defaults
 
diff --git a/packages/typed_openapi/doc/generated/operations.md b/packages/typed_openapi/doc/generated/operations.md
index d4c8e98..712cec7 100644
--- a/packages/typed_openapi/doc/generated/operations.md
+++ b/packages/typed_openapi/doc/generated/operations.md
@@ -3,7 +3,7 @@
 Operations are generated into **group classes**, one plain class per group in `api/<group>.dart`, exported by `api.dart` and held by the root client as fields. A method has named arguments only and returns a `Future<Result<T, E>>`; it never throws for a response.
 
 ```dart
-final client = PetstoreClient(dio);
+final client = PetstoreClient(DioTransport(dio));
 final result = await client.pets.listPets(limit: 10, xTrace: 'abc');
 ```
 
@@ -73,7 +73,7 @@ OperationRequest(
 )
 ```
 
-Path parameters use `PathParameter('petId', petId, style: .label)` or `.matrix`. A parameter described with `content` (`application/json`) is JSON-encoded. A style that its `in` does not allow falls back to the default (`TOA564`), and `in: querystring` is skipped (`TOA565`). Browsers drop the `Cookie` header, so cookie parameters do not work on the web. The encoding rules (RFC 6570 expansion, percent-encoding, and the `ArgumentError` for a path value that is empty, `.` or `..`) are in the [runtime guide on parameters](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/parameters.md).
+Path parameters use `PathParameter('petId', petId, style: .label)` or `.matrix`. A parameter described with `content` (`application/json`) is JSON-encoded. A style that its `in` does not allow falls back to the default (`TOA564`), and `in: querystring` is skipped (`TOA565`). Browsers drop the `Cookie` header, so cookie parameters do not work on the web. The encoding rules (RFC 6570 expansion, percent-encoding, and the `ArgumentError` for a path value that is empty, `.` or `..`) are in the [runtime guide on parameters](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/parameters.md).
 
 ## `CallOptions`
 
@@ -81,18 +81,18 @@ The last argument of every method:
 
 | Field | Use |
 | --- | --- |
-| `cancelToken` | Dio `CancelToken`; a cancelled call is `Cancelled` |
+| `cancel` | `CancelSignal`; a cancelled call is `Cancelled` |
 | `headers` | extra headers for this call |
-| `extra` | values for your interceptors in `RequestOptions.extra` |
-| `onSendProgress`, `onReceiveProgress` | Dio progress callbacks |
+| `extra` | values for the transport (`TransportRequest.extra`; `DioTransport` puts them in `RequestOptions.extra`) |
+| `onSendProgress`, `onReceiveProgress` | progress of the bodies, counted by the client |
 | `sse` | `SseOptions` for [event streams](event_streams.md) |
 
 ```dart
-final token = CancelToken();
-await client.pets.getPet(petId: 1, call: CallOptions(cancelToken: token, headers: {'X-Request-Id': 'r1'}));
+final signal = CancelSignal();
+await client.pets.getPet(petId: 1, call: CallOptions(cancel: signal, headers: {'X-Request-Id': 'r1'}));
 ```
 
-Every request also carries an `OperationInfo` in `RequestOptions.extra` (`OperationInfo.of(options)`): `operationId`, method, path template, tags and the [security requirements](security.md), for interceptors.
+Every request also carries an `OperationInfo` (`TransportRequest.operation`; in a Dio interceptor `DioTransport.operationOf(options)`): `operationId`, method, path template, tags and the [security requirements](security.md), for interceptors.
 
 ## Method names
 
diff --git a/packages/typed_openapi/doc/generated/overview.md b/packages/typed_openapi/doc/generated/overview.md
index d99121e..723dc60 100644
--- a/packages/typed_openapi/doc/generated/overview.md
+++ b/packages/typed_openapi/doc/generated/overview.md
@@ -1,6 +1,6 @@
 # The generated client
 
-`typed_openapi generate` writes one Dart package-ready directory per client: models, one API class per group of operations, two barrel files and a root class. The code depends on `package:dio` and [`typed_openapi_runtime`](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/README.md) only, needs no `build_runner` step and is clean under `dart analyze --fatal-infos`.
+`typed_openapi generate` writes one Dart package-ready directory per client: models, one API class per group of operations, two barrel files and a root class. The code depends on `package:dio` and [`typed_openapi_client`](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/README.md) only, needs no `build_runner` step and is clean under `dart analyze --fatal-infos`.
 
 ## Layout
 
@@ -42,12 +42,11 @@ The root class has a field per group and the servers of the spec. It never sets
 
 ```dart
 class PetstoreClient {
-  /// Creates the client: every group sends through [dio], which it uses as it
-  /// is.
-  PetstoreClient(Dio dio)
-    : defaultApi = DefaultApi(dio),
-      pets = PetsApi(dio),
-      store = StoreApi(dio);
+  /// Creates the client: every group sends through [transport].
+  PetstoreClient(ClientTransport transport)
+    : defaultApi = DefaultApi(transport),
+      pets = PetsApi(transport),
+      store = StoreApi(transport);
 
   final DefaultApi defaultApi;
   final PetsApi pets;
@@ -62,11 +61,11 @@ class PetstoreClient {
 }
 ```
 
-Use a server as the base URL of your own `Dio`:
+Use a server as the base URL of your transport, here your own `Dio` through `typed_openapi_dio`:
 
 ```dart
 final dio = Dio(BaseOptions(baseUrl: PetstoreClient.server1(region: 'us')));
-final client = PetstoreClient(dio);
+final client = PetstoreClient(DioTransport(dio));
 ```
 
 | Servers in the spec | Generated |
@@ -77,7 +76,7 @@ final client = PetstoreClient(dio);
 
 A member that would collide with another member of the root class is renamed with a suffix and reported (`TOA551`, for example `server2` when a group field is called `server`). Servers on a single operation or path are not used (`TOA566`).
 
-The client never changes your `Dio`: interceptors, adapters, timeouts and the base URL stay yours. See [Operations](operations.md) for what a method looks like.
+The client and `DioTransport` never change your `Dio`: interceptors, adapters, timeouts and the base URL stay yours. See [Operations](operations.md) for what a method looks like.
 
 ## Naming rules
 
diff --git a/packages/typed_openapi/doc/generated/request_bodies.md b/packages/typed_openapi/doc/generated/request_bodies.md
index 66175b7..d6bd2e2 100644
--- a/packages/typed_openapi/doc/generated/request_bodies.md
+++ b/packages/typed_openapi/doc/generated/request_bodies.md
@@ -112,7 +112,7 @@ Future<Result<void, Never>> putPhoto({required int petId, required FileUpload bo
 Future<Result<JsonValue, SendNoteError>> sendNote({String? body, CallOptions? call}); // text/plain
 ```
 
-`FileUpload.bytes(...)` works everywhere including the web; `FileUpload.stream(...)` takes a stream, which Dio's browser adapter buffers. Constructors and the content-type check are in the [runtime guide on request bodies](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/request_bodies.md).
+`FileUpload.bytes(...)` works everywhere including the web; `FileUpload.stream(...)` takes a stream, which Dio's browser adapter buffers. Constructors and the content-type check are in the [runtime guide on request bodies](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/request_bodies.md).
 
 ## See also
 
diff --git a/packages/typed_openapi/doc/generated/responses_and_errors.md b/packages/typed_openapi/doc/generated/responses_and_errors.md
index 2767e9b..946f967 100644
--- a/packages/typed_openapi/doc/generated/responses_and_errors.md
+++ b/packages/typed_openapi/doc/generated/responses_and_errors.md
@@ -37,7 +37,7 @@ undocumented status 503
 | `TransportError(exception, stackTrace)` | network failure, timeout |
 | `Cancelled(exception, stackTrace)` | the `CancelToken` was cancelled |
 
-`Failure` is the sealed base of the last five. If a method has no documented errors, `E` is `Never`, but you still write `case Failure()`. The runtime reference is the [results and errors guide](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/results_and_errors.md).
+`Failure` is the sealed base of the last five. If a method has no documented errors, `E` is `Never`, but you still write `case Failure()`. The runtime reference is the [results and errors guide](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/results_and_errors.md).
 
 ## The success type
 
@@ -103,7 +103,7 @@ switch (r.statusCode) {
 ```
 
 - A range `2XX`, `4XX`, `5XX` (either case) covers its hundred. `default` covers every status not matched and not 2xx (a `default` is never a success).
-- Keys that are not a status, a range or `default` are `TOA657` and skipped; `1xx` and `3xx` are `TOA658` info and skipped (Dio follows redirects), so they arrive as `UndocumentedStatus`.
+- Keys that are not a status, a range or `default` are `TOA657` and skipped; `1xx` and `3xx` are `TOA658` info and skipped (the transport follows redirects), so they arrive as `UndocumentedStatus`.
 - An inline error body is named after the operation and, when several responses of a kind declare one, the status.
 
 ### `errors.default_schema`
diff --git a/packages/typed_openapi/doc/generated/security.md b/packages/typed_openapi/doc/generated/security.md
index bb070b5..52f9379 100644
--- a/packages/typed_openapi/doc/generated/security.md
+++ b/packages/typed_openapi/doc/generated/security.md
@@ -95,7 +95,7 @@ static const _legacy = OperationInfo(
 );
 ```
 
-`/health` has `security: []` and its `OperationInfo` has no `security` argument at all. `/items` (no `security` of its own) inherits the document's `bearer`. The runtime types are `OperationInfo`, `SecurityUse` and `SecurityScheme`, documented in the runtime guide [Security metadata](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/security_metadata.md).
+`/health` has `security: []` and its `OperationInfo` has no `security` argument at all. `/items` (no `security` of its own) inherits the document's `bearer`. The runtime types are `OperationInfo`, `SecurityUse` and `SecurityScheme`, documented in the runtime guide [Security metadata](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/security_metadata.md).
 
 ## Reading the list
 
@@ -139,13 +139,14 @@ The alternative is left out of the metadata when another alternative can be desc
 
 ## An interceptor that applies the metadata
 
-Dio interceptors see the metadata through `OperationInfo.of(options)`, which returns `null` for a request that a generated client did not send. The interceptor below picks the first alternative whose schemes it has secrets for, sets the headers or query parameter, and rejects the request when it cannot satisfy any alternative. It was run against the generated `vault` client above with a fake Dio adapter (output follows the code).
+Dio interceptors see the metadata through `DioTransport.operationOf(options)`, which returns `null` for a request that `DioTransport` did not send. The interceptor below picks the first alternative whose schemes it has secrets for, sets the headers or query parameter, and rejects the request when it cannot satisfy any alternative. It was run against the generated `vault` client above with a fake Dio adapter (output follows the code).
 
 ```dart
 import 'dart:convert';
 
 import 'package:dio/dio.dart';
-import 'package:typed_openapi_runtime/typed_openapi_runtime.dart';
+import 'package:typed_openapi_client/typed_openapi_client.dart';
+import 'package:typed_openapi_dio/typed_openapi_dio.dart';
 
 /// Thrown (inside a `DioException`, so the call returns `TransportError`)
 /// when no alternative of an operation's security can be satisfied.
@@ -169,7 +170,7 @@ class SecurityInterceptor extends Interceptor {
 
   @override
   void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
-    final info = OperationInfo.of(options);
+    final info = DioTransport.operationOf(options);
     final alternatives = info?.security ?? const <List<SecurityUse>>[];
     if (alternatives.isEmpty) return handler.next(options); // open operation
 
@@ -241,7 +242,7 @@ final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
   ..interceptors.add(
     SecurityInterceptor({'bearer': token, 'apiKey': apiKey, 'signature': sig}),
   );
-final client = VaultClient(dio);
+final client = VaultClient(DioTransport(dio));
 ```
 
 The fake-adapter run printed these requests (secrets shortened):
@@ -261,7 +262,7 @@ TransportError(unknown)        <- /legacy: the scheme is unknown
 
 ## Notes and limits
 
-- **Query keys.** The generated client builds the query itself and passes Dio one finished path, so `options.queryParameters` is empty in an interceptor. Adding a key to it, as above, makes Dio append it to the URL (`?sig=s`).
+- **Query keys.** The generated client builds the query itself and `DioTransport` passes Dio one finished path, so `options.queryParameters` is empty in an interceptor. Adding a key to it, as above, makes Dio append it to the URL (`?sig=s`).
 - **Cookies.** A script on the web cannot set the `Cookie` header, so a `location: .cookie` scheme works on the Dart VM only.
 - **OAuth.** The metadata carries the scopes an operation needs but not the token URL or flows; getting and refreshing a token is your code. A 401 reaches your interceptor's `onError` as for any Dio request.
 - **Mutual TLS** is a transport setting: configure the `HttpClient` of your adapter.
@@ -272,4 +273,4 @@ TransportError(unknown)        <- /legacy: the scheme is unknown
 - [Operations](operations.md): the group classes and `CallOptions` (per-call headers).
 - [Responses and errors](responses_and_errors.md): `HttpError` for a `401`.
 - [Diagnostics](../diagnostics.md): `TOA568` and the other codes.
-- Runtime: [Security metadata](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/security_metadata.md).
+- Runtime: [Security metadata](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/security_metadata.md).
diff --git a/packages/typed_openapi/doc/getting_started.md b/packages/typed_openapi/doc/getting_started.md
index 294c350..4b32d6f 100644
--- a/packages/typed_openapi/doc/getting_started.md
+++ b/packages/typed_openapi/doc/getting_started.md
@@ -1,16 +1,18 @@
 # Getting started
 
-This guide takes one NestJS-style spec from file to a working call: install, config, `check`, `generate`, and using the client with Dio. Everything below was run on the sample spec; the program at the end prints the line shown.
+This guide takes one NestJS-style spec from file to a working call: install, config, `check`, `generate`, and using the client with Dio through `typed_openapi_dio`. Everything below was run on the sample spec; the program at the end prints the line shown.
 
 ## Install
 
-`typed_openapi` is not published to pub.dev yet (version 0.0.1). Until it is, depend on it from the repository by git or path. The generator is a dev dependency; the generated client depends only on `typed_openapi_runtime` and Dio.
+`typed_openapi` is not published to pub.dev yet (version 0.0.1). Until it is, depend on it from the repository by git or path. The generator is a dev dependency; the generated client depends only on `typed_openapi_client`; the app adds a transport, here `typed_openapi_dio` and Dio.
 
 ```yaml
 dependencies:
   dio: ^5.11.1
-  typed_openapi_runtime:
-    path: ../typed_openapi/packages/typed_openapi_runtime
+  typed_openapi_client:
+    path: ../typed_openapi/packages/typed_openapi_client
+  typed_openapi_dio:
+    path: ../typed_openapi/packages/typed_openapi_dio
 dev_dependencies:
   typed_openapi:
     path: ../typed_openapi/packages/typed_openapi
@@ -113,11 +115,12 @@ Run it again and it writes `0 files`. Do not edit the tree by hand: the next run
 ```dart
 import 'package:dio/dio.dart';
 import 'package:shop_app/src/api/shop/shop.dart';
-import 'package:typed_openapi_runtime/typed_openapi_runtime.dart';
+import 'package:typed_openapi_client/typed_openapi_client.dart';
+import 'package:typed_openapi_dio/typed_openapi_dio.dart';
 
 Future<void> main() async {
   final dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
-  final client = ShopClient(dio);
+  final client = ShopClient(DioTransport(dio));
 
   final result = await client.products.findOne(id: '42');
   switch (result) {
@@ -141,9 +144,9 @@ found Hammer in CategoryUnknown(garden)
 
 `garden` is not in the enum the spec lists, so the open enum kept it as `CategoryUnknown` instead of failing. `dart analyze` reports no issues for the project.
 
-Every call returns `Result<T, E>`: a `Success`, or a `Failure` such as `HttpError`, `UndocumentedStatus`, `DecodeError`, `TransportError` or `Cancelled`. The generated client never mutates your Dio and sets no base URL; configure `Dio` as you like. The runtime guides explain results, JSON decoding and parameters: see [typed_openapi_runtime](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/README.md).
+Every call returns `Result<T, E>`: a `Success`, or a `Failure` such as `HttpError`, `UndocumentedStatus`, `DecodeError`, `TransportError` or `Cancelled`. The generated client never mutates your Dio and sets no base URL; configure `Dio` as you like. The runtime guides explain results, JSON decoding and parameters: see [typed_openapi_client](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/README.md).
 
-> **Note:** The generated `shop.dart` does not re-export the result types, so import `package:typed_openapi_runtime/typed_openapi_runtime.dart` where you `switch` on a result.
+> **Note:** The generated `shop.dart` does not re-export the result types, so import `package:typed_openapi_client/typed_openapi_client.dart` where you `switch` on a result.
 
 ## Next steps
 
diff --git a/packages/typed_openapi/doc/troubleshooting.md b/packages/typed_openapi/doc/troubleshooting.md
index b80de59..2c47a95 100644
--- a/packages/typed_openapi/doc/troubleshooting.md
+++ b/packages/typed_openapi/doc/troubleshooting.md
@@ -151,7 +151,7 @@ Generated names in lib/own: 5 files, 5 written, 0 deleted.
 
 Run `dart analyze` first: it names the file and line. If the error is in `lib/.../models/*.dart` or `api/*.dart`, it is a generator bug (the project analyses its own fixtures with `--fatal-infos`). Common non-bugs:
 
-- **`typed_openapi_runtime` or `dio` missing in `pubspec.yaml`.** The client depends on both. See [Getting started](getting_started.md#install).
+- **`typed_openapi_client` or the transport (`typed_openapi_dio` and `dio`) missing in `pubspec.yaml`.** The generated code imports the client; your code creates the transport. See [Getting started](getting_started.md#install).
 - **An old runtime.** Generator and runtime come from the same checkout; pin both to the same `ref`.
 - **A lower SDK.** The minimum SDK is Dart 3.10, for the generated code too.
 
@@ -177,7 +177,7 @@ Set `baseline:` on the client first; until the file exists `check` reports TOA82
 
 ### The output changed after an upgrade
 
-The manifest `.typed_openapi.json` records the generator version (`"generator": "typed_openapi 0.0.1"`). A new generator can write different code from the same spec and config; that is a change of the generator, not of your API. **Fix:** commit the generated tree, upgrade in a branch, and read the diff. Pin the version of `typed_openapi` and `typed_openapi_runtime` together with the same `ref`. If the diff is a change you did not expect, see [Reporting a bug](#reporting-a-bug). The same spec and config on the same version always give the same bytes. See [Determinism](generate_output.md#determinism).
+The manifest `.typed_openapi.json` records the generator version (`"generator": "typed_openapi 0.0.1"`). A new generator can write different code from the same spec and config; that is a change of the generator, not of your API. **Fix:** commit the generated tree, upgrade in a branch, and read the diff. Pin the version of `typed_openapi` and `typed_openapi_client` together with the same `ref`. If the diff is a change you did not expect, see [Reporting a bug](#reporting-a-bug). The same spec and config on the same version always give the same bytes. See [Determinism](generate_output.md#determinism).
 
 ## Using the client
 
@@ -189,7 +189,7 @@ JsonDecodeException: expected a string, got a number at /tags/1/name in Tag
 pointer /tags/1/name, expected a string, actual a number, schema Tag, field name
 ```
 
-**Cause:** the server's body does not match the spec; the first mismatch is reported, never the value. `pointer` is an RFC 6901 path into the body (`/tags/1/name` is the `name` of the second tag), `expected` is what the spec wants, `actual` is the JSON type that came, `schema` is the model that was reading. **Fix:** compare with the real body (`DecodeError.rawBody`). If the server is right, correct the schema at the source or with an [override](overrides.md) (`nullable: true`, a different `type`). If it is wrong, fix the server. See [JSON decoding](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/json_decoding.md#jsondecodeexception).
+**Cause:** the server's body does not match the spec; the first mismatch is reported, never the value. `pointer` is an RFC 6901 path into the body (`/tags/1/name` is the `name` of the second tag), `expected` is what the spec wants, `actual` is the JSON type that came, `schema` is the model that was reading. **Fix:** compare with the real body (`DecodeError.rawBody`). If the server is right, correct the schema at the source or with an [override](overrides.md) (`nullable: true`, a different `type`). If it is wrong, fix the server. See [JSON decoding](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/json_decoding.md#jsondecodeexception).
 
 ### `The type 'PetStatus' isn't exhaustively matched`
 
@@ -201,11 +201,11 @@ error - e.dart:3:26 - The type 'PetStatus' isn't exhaustively matched by the swi
 
 ### A field is nullable (or not) when I expected the opposite
 
-A field is `T x` only when it is in `required` and not nullable. Optional fields are `T?`, and a `null` value for an optional non-nullable field is read as absent. The rule `bool-required-to-array` repairs `required: true` on a property (TOA201). To change a field, use `nullable` in an [override](overrides.md); do not edit the generated file. The full table is in [Models](generated/models.md#required-optional-nullable); for PATCH bodies see [Patch and nullability](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/patch_and_nullability.md).
+A field is `T x` only when it is in `required` and not nullable. Optional fields are `T?`, and a `null` value for an optional non-nullable field is read as absent. The rule `bool-required-to-array` repairs `required: true` on a property (TOA201). To change a field, use `nullable` in an [override](overrides.md); do not edit the generated file. The full table is in [Models](generated/models.md#required-optional-nullable); for PATCH bodies see [Patch and nullability](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/patch_and_nullability.md).
 
 ### An event stream returns one error on the web
 
-**Cause:** Dio's default browser adapter delivers a response body only when the connection closes, so `openEvents` returns a `TransportError` before sending a request. **Fix:** set a fetch-based adapter on your `Dio`, then the stream opens. For a cross-origin stream the server must also list `Last-Event-ID` in `Access-Control-Allow-Headers`. The message and the adapters are in [Web and platforms](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/web_and_platforms.md#event-streams).
+**Cause:** Dio's default browser adapter delivers a response body only when the connection closes, so `openEvents` returns a `TransportError` before sending a request. **Fix:** set a fetch-based adapter on your `Dio`, then the stream opens. For a cross-origin stream the server must also list `Last-Event-ID` in `Access-Control-Allow-Headers`. The message and the adapters are in [Web and platforms](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/web_and_platforms.md#event-streams).
 
 ## Reporting a bug
 
diff --git a/packages/typed_openapi/lib/src/ir/part_media_type.dart b/packages/typed_openapi/lib/src/ir/part_media_type.dart
index b52bbe4..5acbc13 100644
--- a/packages/typed_openapi/lib/src/ir/part_media_type.dart
+++ b/packages/typed_openapi/lib/src/ir/part_media_type.dart
@@ -33,8 +33,9 @@ final class PartMediaType {
   static const _token = r"[0-9A-Za-z!#$%&'+.^_`|~-]+";
 
   /// A quoted string of RFC 9110 without a tab or any control character:
-  /// `qdtext` and `quoted-pair` allow a tab there, but Dio's parser does not,
-  /// and a line break in a header is never sent.
+  /// `qdtext` and `quoted-pair` allow a tab there, but the client's
+  /// `ParsedMediaType` (the rules of `package:http_parser`) does not, and a
+  /// line break in a header is never sent.
   static const _quotedString =
       r'"(?:[\x20\x21\x23-\x5B\x5D-\x7E\x80-\xFF]|\\[\x20-\x7E\x80-\xFF])*"';
   static final _concrete = RegExp(
diff --git a/packages/typed_openapi_client/README.md b/packages/typed_openapi_client/README.md
index 4608da3..fa8c20a 100644
--- a/packages/typed_openapi_client/README.md
+++ b/packages/typed_openapi_client/README.md
@@ -1,4 +1,4 @@
-# typed_openapi_runtime
+# typed_openapi_client
 
 ![Dart 3.10+](https://img.shields.io/badge/dart-%3E%3D3.10-0175C2)
 ![Platforms](https://img.shields.io/badge/platforms-VM%20%7C%20dart2js%20%7C%20dart2wasm-blue)
@@ -8,7 +8,9 @@
 [`typed_openapi`](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/README.md)
 depends on** - typed errors, `Result`, `Patch`, strict JSON decoding with
 JSON pointers, parameter encoders, request bodies and a Server-Sent Events
-decoder, all on top of your own `Dio`. Dependencies: `dio` and `meta`. The
+decoder. It builds every request and reads every response itself and hands
+the bytes to a `ClientTransport`; [`typed_openapi_dio`](../typed_openapi_dio/README.md)
+is the transport over your own `Dio`. Its one dependency is `meta`. The
 generator is never a runtime dependency of your app.
 
 > **Status:** in development, not published yet.
@@ -25,14 +27,15 @@ generator is never a runtime dependency of your app.
 
 ## Install
 
-Generated code imports `package:typed_openapi_runtime` and `package:dio`, so
-an app that uses a generated client lists both (the generator does not edit
-your `pubspec.yaml`):
+Generated code imports only `package:typed_openapi_client`. An app lists it
+and a transport, such as the Dio one (the generator does not edit your
+`pubspec.yaml`):
 
 ```yaml
 dependencies:
   dio: ^5.11.1
-  typed_openapi_runtime: ^0.0.1   # not on pub.dev yet; use a path or git dependency
+  typed_openapi_client: ^0.0.1   # not on pub.dev yet; use a path or git dependency
+  typed_openapi_dio: ^0.0.1
 ```
 
 The SDK floor is Dart 3.10 (`>=3.10.0 <4.0.0`), the same as for generated
@@ -42,7 +45,7 @@ code. `meta` is `^1.15.0` so that the version Flutter pins resolves.
 
 ```dart
 final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'));
-final api = PetshopClient(dio);          // generated; uses your Dio as it is
+final api = PetshopClient(DioTransport(dio)); // generated; your Dio as it is
 
 switch (await api.pets.getPet(petId: 7)) {
   case Success(:final data):             // Pet, decoded and typed
@@ -57,7 +60,7 @@ switch (await api.pets.getPet(petId: 7)) {
 ```
 
 Real output of the calls in [Getting started](doc/getting_started.md), run
-against an in-memory Dio adapter:
+against an in-memory Dio adapter through `DioTransport`:
 
 ```text
 200 Rex born 2021-04-09 [abc]
@@ -74,8 +77,8 @@ cancel, a body that does not match the schema). A bug in your code - an
 
 | Guide | What it covers |
 | --- | --- |
-| [Getting started](doc/getting_started.md) | Wire a `Dio`, call a method, read the `Result`, `CallOptions` |
-| [Results and errors](doc/results_and_errors.md) | Every `Result` variant, what triggers it, how Dio errors map, what is never caught |
+| [Getting started](doc/getting_started.md) | Pick a transport, call a method, read the `Result`, `CallOptions` |
+| [Results and errors](doc/results_and_errors.md) | Every `Result` variant, what triggers it, how transport failures map, what is never caught |
 | [JSON decoding](doc/json_decoding.md) | `JsonReader` strictness, dates, `JsonDecodeException`, `JsonValue`, `DeepEquality` |
 | [Patch and nullability](doc/patch_and_nullability.md) | `Patch<T>` for absent / `null` / value request fields |
 | [Parameters](doc/parameters.md) | Path, query, header and cookie encoding, every style, `ArgumentError` cases |
@@ -88,9 +91,12 @@ cancel, a body that does not match the schema). A bug in your code - an
 
 - **Typed outcomes.** `Success`, `HttpError`, `UndocumentedStatus`,
   `DecodeError`, `TransportError` and `Cancelled`, matched with `switch`.
-- **Your Dio, untouched.** No base URL, interceptor, transformer or
-  `validateStatus` is set or changed; nothing is retried. Interceptors see
-  the finished URL and an `OperationInfo` in `RequestOptions.extra`.
+- **One wire format for every transport.** The core encodes the path, the
+  query, the headers and the body, and reads the response bytes, so a
+  request is the same through any `ClientTransport`. The transport owns the
+  base URL, timeouts, retries, cookies and authorization; nothing is
+  retried by the core. `TransportRequest.operation` is the `OperationInfo`
+  of the call, for interceptors and logs.
 - **Strict decoding with paths.** A wrong type, a missing property or a bad
   date-time is a `DecodeError` carrying the JSON pointer of the first
   mismatch, never the value.
@@ -107,20 +113,22 @@ cancel, a body that does not match the schema). A bug in your code - an
 ## Platforms
 
 The Dart VM, dart2js and dart2wasm. The same test suite runs on all three
-(see [Development](#development)). Event streams need a streaming HTTP
-adapter in a browser, and cookie parameters cannot work there. The full
+(see [Development](#development)). Event streams need a transport that
+streams in a browser, and cookie parameters cannot work there. The full
 table is in [Web and platforms](doc/web_and_platforms.md).
 
 ## Known limits
 
 - A cookie parameter never reaches the server from a browser.
-- An event stream in a browser needs a fetch-based Dio adapter; with Dio's
-  default one `openEvents` returns a `TransportError` that says so.
+- An event stream in a browser needs a transport that streams the body;
+  `DioTransport` with Dio's default adapter returns a `TransportError` that
+  says so.
 - `int` is a JavaScript number on the web: integers beyond 2^53 lose
   precision there. Map such properties to `BigInt` or `String` in the
   generator config.
 - Per-call timeouts are not part of `CallOptions`; timeouts, base URL and
-  retries belong to your `Dio` and its interceptors.
+  retries belong to the transport (for Dio, your `Dio` and its
+  interceptors).
 - `Result` has the same name as `Result` in `package:async`; hide one of the
   two when a library imports both.
 
@@ -133,7 +141,9 @@ dart test -p chrome --compiler dart2wasm     # dart2wasm
 ```
 
 A test file that needs the VM (`dart:io`, int64 literals) carries
-`@TestOn('vm')`; `test/dio/web_test.dart` runs in a browser only. If Chrome
-is not found, set `CHROME_EXECUTABLE`. Runtime tests never touch the network.
+`@TestOn('vm')`. If Chrome is not found, set `CHROME_EXECUTABLE`. The tests
+never touch the network: they send through `FakeTransport`. Every transport
+also runs the conformance suite of `typed_openapi_transport_tests` against a
+loopback server.
 
 [Українська версія](README.ua.md)
diff --git a/packages/typed_openapi_client/README.ua.md b/packages/typed_openapi_client/README.ua.md
index 270148f..9d967a3 100644
--- a/packages/typed_openapi_client/README.ua.md
+++ b/packages/typed_openapi_client/README.ua.md
@@ -1,8 +1,10 @@
-# typed_openapi_runtime
+# typed_openapi_client
 
-Runtime для клієнтів, згенерованих
+Ядро клієнтів, згенерованих
 [`typed_openapi`](https://pub.dev/packages/typed_openapi): єдиний пакет, від якого
-залежить згенерований код. Залежності: `dio` і `meta`.
+залежить згенерований код. Воно саме будує кожен запит і читає кожну
+відповідь, а байти передає `ClientTransport`; транспорт поверх твого `Dio` —
+[`typed_openapi_dio`](../typed_openapi_dio/README.md). Залежність: `meta`.
 
 > **Статус:** у розробці, ще не опубліковано.
 
@@ -44,14 +46,14 @@ Runtime для клієнтів, згенерованих
 - Кодувальники стилів параметрів OpenAPI (`simple`, `label`, `matrix`,
   `form`, `spaceDelimited`, `pipeDelimited`, `deepObject`, заголовки,
   cookie) з percent-кодуванням за RFC 3986.
-- `DioRequestSender`: надсилає запит через твій `Dio` і типізує результат.
-  `CallOptions` несе токен скасування, заголовки, `extra` і колбеки прогресу
+- `ClientSender`: будує запит, надсилає його через `ClientTransport` і
+  типізує результат. `CallOptions` несе `CancelSignal`, заголовки, `extra` і колбеки прогресу
   для одного виклику. Заголовки з `CallOptions.headers` мають перевагу над
   заголовками-параметрами операції, але не над її `Content-Type`: тип вмісту
   тіла запиту (наприклад `application/json`) завжди виграє, тож
   `Content-Type`, заданий там, ігнорується, коли операція надсилає тіло.
 - Декодер потоку подій (`text/event-stream`) за WHATWG;
-  `DioRequestSender.openEvents` повертає `Result`, у `Success` якого лежить
+  `ClientSender.openEvents` повертає `Result`, у `Success` якого лежить
   потік із `SseEvent`, `SseDecodeError` (одна погана подія) і наприкінці
   `SseDisconnected`. Проблеми з даними — це елементи потоку, а не помилки
   потоку (єдиний виняток: `Error` з твого декодера подій — це баг програми,
@@ -75,34 +77,27 @@ Runtime для клієнтів, згенерованих
   потік одразу; останній елемент — завжди `SseDisconnected` з останнім id
   події та `retry`, тож можна відновитися самому.
 
-## Твій Dio використовується як є
+## Транспорт
 
-- У твоєму `Dio` нічого не змінюється: base URL, заголовки, таймаути,
-  інтерсептори, transformer і `validateStatus` лишаються твоїми. Повторів
-  немає: це справа твоїх інтерсепторів.
-- Помилкові статуси проходять через `onError` твоїх інтерсепторів, і лише
-  потім типізуються.
+- Ядро кодує шлях, query, заголовки й тіло і читає байти відповіді, тож
+  запит однаковий через будь-який `ClientTransport`. Base URL, таймаути,
+  повтори, cookie й авторизація належать транспорту; ядро нічого не
+  повторює.
 - Кожен запит несе свій `OperationInfo` (operation id, метод, шаблон шляху,
-  теги): `OperationInfo.of(options)` в інтерсепторі.
-- Шлях і query кодує runtime і передає Dio одним рядком, тож в
-  інтерсепторах `options.queryParameters` порожній; читай `options.uri`.
-  Dio стискає кожне `//` готового URL; коли значення query містить `//`
-  (значення з `allowReserved`, наприклад `next=/a//b`), а base URL
-  абсолютний, runtime сам з'єднує base URL зі шляхом, щоб значення
-  збереглося.
+  теги, безпека) у `TransportRequest.operation`; для Dio його читає
+  `DioTransport.operationOf(options)` в інтерсепторі.
+- Як поводиться твій `Dio` (інтерсептори, `onError`, `//` у query) описано
+  в README [`typed_openapi_dio`](../typed_openapi_dio/README.md).
 
 ## Нотатки
 
 - `Result` збігається з `Result` з `package:async`. У бібліотеці, що
   імпортує обидва, сховай один (`import 'package:async/async.dart' hide
-  Result;`, або `import 'package:typed_openapi_runtime/typed_openapi_runtime.dart'
+  Result;`, або `import 'package:typed_openapi_client/typed_openapi_client.dart'
   hide Result;`) або імпортуй один із префіксом.
-- JSON розбирає Dio. Коли тіло — невалідний JSON, Dio відкидає відповідь,
-  тож `DecodeError` не має `statusCode`, а його `rawBody` — текст, який
-  повідомив парсер Dio: усе тіло, коли Dio прочитав його одразу, і лише
-  чанк із помилкою, коли Dio його стрімив (був заголовок `Content-Length`).
-  Після компіляції в JavaScript Dio повідомляє лише текст `SyntaxError`
-  браузера, тож там `rawBody` — `null`.
+- JSON розбирає ядро. Коли тіло — невалідний JSON, `DecodeError` має
+  `statusCode` відповіді, а його `rawBody` — увесь текст тіла, на кожній
+  платформі.
 - `FormatException`, кинутий під час декодування (твій конвертер,
   `Date.parse`), — це проблема з даними: `DecodeError` у результаті,
   `SseDecodeError` у потоці подій. `Error` — це баг, його не ловлять.
@@ -110,8 +105,8 @@ Runtime для клієнтів, згенерованих
   (`''`, порожній список, `label` від `''`), кидає `ArgumentError`: клієнт
   прибрав би сегмент, і `/users/{id}/sessions` став би `/users/sessions`.
 - `rawBody` у `DecodeError` і `UndocumentedStatus` — за можливістю: це тіло
-  в тому вигляді, в якому його повернув Dio (розібраний JSON, текст або
-  байти), або `null`, коли відповідь без тіла чи Dio нічого не зберіг.
+  в тому вигляді, в якому його прочитало ядро (розібраний JSON, текст або
+  байти), або `null`, коли відповідь без тіла.
 - `date-time` має бути RFC 3339 зі зсувом (`2024-02-03T04:05:06Z`). Значення
   без зсуву — `DecodeError` з підказкою: для сервера, що пише інший формат,
   зістав формат зі своїм типом через конвертер (`types.formats`) або
@@ -125,12 +120,10 @@ Runtime для клієнтів, згенерованих
 ## Web
 
 Пакет працює на web, зібраний у JavaScript (dart2js) або в WebAssembly
-(dart2wasm). Потокам подій там потрібен потоковий адаптер: стандартний
-браузерний адаптер Dio віддає тіло лише після закриття з'єднання, тож
-операція з потоком подій повертає `TransportError` з поясненням
-(`DioRequestSender.webStreamingMessage`). Постав у свій Dio адаптер на
-fetch, наприклад `ConversionLayerAdapter` з `dio_compatibility_layer` з
-`BrowserClient` з `package:http` або `fetch_client`. Перепідключення надсилає
+(dart2wasm). Потокам подій там потрібен транспорт, що стрімить тіло:
+`DioTransport` зі стандартним браузерним адаптером Dio повертає
+`TransportError` з поясненням (`DioTransport.webStreamingMessage`); що
+поставити замість нього, описано в README `typed_openapi_dio`. Перепідключення надсилає
 `Last-Event-ID`, який не належить до заголовків запиту, дозволених CORS
 за замовчуванням: для потоку з іншого origin сервер має дозволити
 `Last-Event-ID` в `Access-Control-Allow-Headers` у відповіді на preflight,
@@ -140,7 +133,7 @@ fetch, наприклад `ConversionLayerAdapter` з `dio_compatibility_layer`
 cookie-параметри на web не працюють (браузер тримає свої cookie і надсилає
 їх сам, за своїми налаштуваннями credentials). Тест перевіряє це в Chrome,
 скомпільованому в JavaScript і в Wasm: заголовок `Cookie`, виставлений
-через Dio, cookie-параметром чи напряму, ніколи не доходить до сервера, а
+cookie-параметром чи напряму, ніколи не доходить до сервера, а
 інші заголовки того самого запиту доходять.
 
 ## Розробка
@@ -152,7 +145,9 @@ dart test -p chrome --compiler dart2wasm     # dart2wasm
 ```
 
 Файли й тести, що потребують VM (`dart:io`, літерали int64), позначені
-`@TestOn('vm')` або `testOn: 'vm'`; `test/dio/web_test.dart` працює лише в
-браузері. Якщо Chrome не знайдено, задай `CHROME_EXECUTABLE`.
+`@TestOn('vm')` або `testOn: 'vm'`. Якщо Chrome не знайдено, задай
+`CHROME_EXECUTABLE`. Тести не ходять у мережу: вони надсилають через
+`FakeTransport`. Кожен транспорт також проходить набір відповідності
+`typed_openapi_transport_tests` проти локального сервера.
 
 [English version](README.md)
diff --git a/packages/typed_openapi_client/doc/getting_started.md b/packages/typed_openapi_client/doc/getting_started.md
index 80ac644..16bfa6a 100644
--- a/packages/typed_openapi_client/doc/getting_started.md
+++ b/packages/typed_openapi_client/doc/getting_started.md
@@ -1,7 +1,8 @@
 # Getting started
 
-A generated client sends its requests through `DioRequestSender` and returns
-a `Result<T, E>` from every method. This guide wires a `Dio`, makes a call,
+A generated client builds its requests with `ClientSender`, hands them to a
+`ClientTransport` and returns a `Result<T, E>` from every method. This guide
+wires the Dio transport (`typed_openapi_dio`), makes a call,
 reads the result and shows what `CallOptions` can do. The client below is the
 one the generator writes for a two-operation Petshop spec (a `GET
 /pets/{petId}` and a `PATCH /pets/{petId}`); the trimmed generated method is
@@ -12,18 +13,21 @@ in [Results and errors](results_and_errors.md).
 ```yaml
 dependencies:
   dio: ^5.11.1
-  typed_openapi_runtime: ^0.0.1   # not on pub.dev yet; use a path or git dependency
+  typed_openapi_client: ^0.0.1   # not on pub.dev yet; use a path or git dependency
+  typed_openapi_dio: ^0.0.1      # the transport over your Dio; the same
 ```
 
-Generated files import `package:typed_openapi_runtime/typed_openapi_runtime.dart`
-and `package:dio/dio.dart` (only `Dio`). The generator itself
+Generated files import only
+`package:typed_openapi_client/typed_openapi_client.dart`; your app adds the
+transport (`typed_openapi_dio` and `dio`). The generator itself
 (`typed_openapi`) is a dev tool and never a dependency of your app.
 
 ## 2. Create the client
 
 ```dart
 import 'package:dio/dio.dart';
-import 'package:typed_openapi_runtime/typed_openapi_runtime.dart';
+import 'package:typed_openapi_client/typed_openapi_client.dart';
+import 'package:typed_openapi_dio/typed_openapi_dio.dart';
 
 import 'petshop/petshop.dart'; // generated
 
@@ -34,17 +38,17 @@ final dio = Dio(
     headers: {'User-Agent': 'petshop-app/1.0'},
   ),
 );
-final api = PetshopClient(dio);
+final api = PetshopClient(DioTransport(dio));
 ```
 
-The client uses your `Dio` as it is. It never sets a base URL, an
+`DioTransport` uses your `Dio` as it is. It never sets a base URL, an
 interceptor, a transformer or `validateStatus`, and it never retries; those
 belong to you. Authentication, logging, retries and per-call timeouts are
 interceptors on this `Dio` (see [Security metadata](security_metadata.md)).
 
 > **Note:** The root class has a field per group of operations (`api.pets`).
-> Each group is a plain `class` that takes the `Dio`, so you can `implements`
-> it in a test fake.
+> Each group is a plain `class` that takes the `ClientTransport`, so you can
+> `implements` it in a test fake, or give it a fake transport.
 
 ## 3. Call a method and read the result
 
@@ -84,7 +88,7 @@ User-Agent: petshop-app/1.0
 ```
 
 > **Gotcha:** `options.queryParameters` is empty in an interceptor. The
-> runtime encodes the path and the query itself and gives Dio one finished
+> client encodes the path and the query itself and gives the transport one finished
 > path, so read `options.uri` instead.
 
 ## 4. CallOptions
@@ -95,11 +99,11 @@ fake that implements it).
 
 | Field | Effect |
 | --- | --- |
-| `cancelToken` | A Dio `CancelToken`; cancelling gives `Cancelled` |
+| `cancel` | A `CancelSignal`; cancelling gives `Cancelled` |
 | `headers` | Added to the request; win over the operation's header parameters (case-insensitively) |
-| `extra` | Merged into `RequestOptions.extra`, for your interceptors |
-| `onSendProgress` | Dio's progress callback for the request body |
-| `onReceiveProgress` | Dio's progress callback for the response body |
+| `extra` | Given to the transport (`TransportRequest.extra`); `DioTransport` merges it into `RequestOptions.extra` |
+| `onSendProgress` | Bytes of the request body sent so far, counted by the client |
+| `onReceiveProgress` | Bytes of the response body received so far, counted by the client |
 | `sse` | `SseOptions` for an event stream (reconnection); other operations ignore it |
 
 ```dart
@@ -118,9 +122,9 @@ await api.pets.getPet(
 ### Cancelling
 
 ```dart
-final token = CancelToken();
-final pending = api.pets.getPet(petId: 7, call: CallOptions(cancelToken: token));
-token.cancel('user left the page');
+final signal = CancelSignal();
+final pending = api.pets.getPet(petId: 7, call: CallOptions(cancel: signal));
+signal.cancel('user left the page');
 print(await pending); // Cancelled
 ```
 
@@ -136,7 +140,7 @@ cannot use it to pick another media type such as
 
 ### Per-call timeouts
 
-Timeouts, the base URL and retries are Dio's. For a value that differs per
+Timeouts, the base URL and retries belong to the transport, here your Dio. For a value that differs per
 call, pass it in `extra` and apply it in an interceptor:
 
 ```dart
@@ -164,7 +168,7 @@ The runtime puts an `OperationInfo` (operation id, method, path template,
 tags, security) into `RequestOptions.extra`:
 
 ```dart
-final operation = OperationInfo.of(options); // null for a request the client did not send
+final operation = DioTransport.operationOf(options); // null for a request DioTransport did not send
 print(operation?.operationId);               // getPet
 ```
 
diff --git a/packages/typed_openapi_client/doc/parameters.md b/packages/typed_openapi_client/doc/parameters.md
index 7ca2d4c..94fe970 100644
--- a/packages/typed_openapi_client/doc/parameters.md
+++ b/packages/typed_openapi_client/doc/parameters.md
@@ -128,7 +128,7 @@ next=/a//b?x=1#frag[1]       -> next=/a//b?x%3D1%23frag%5B1%5D
 
 > **Note:** Dio collapses every `//` of the finished URL, query included.
 > When a query holds `//` (the `next=/a//b` above) and the base URL is
-> absolute, the runtime joins the base URL itself so the value is kept.
+> absolute, `DioTransport` joins the base URL itself so the value is kept.
 > Interceptors still see the finished URL.
 
 ## Header parameters
diff --git a/packages/typed_openapi_client/doc/request_bodies.md b/packages/typed_openapi_client/doc/request_bodies.md
index 188efb4..576fa2e 100644
--- a/packages/typed_openapi_client/doc/request_bodies.md
+++ b/packages/typed_openapi_client/doc/request_bodies.md
@@ -1,12 +1,14 @@
 # Request bodies
 
 A generated method puts its body into `OperationRequest.body` together with a
-`contentType`, and `DioRequestSender` turns it into what Dio sends. The body
+`contentType`, and `ClientSender` encodes it into the bytes every transport
+sends. The body
 is one of: a JSON value (the `toJson()` of a model, or a string, number,
 boolean, list or map), text, a `FormBody`, a `MultipartBody` or a
 `FileUpload`; `null` means no body. This guide lists what goes on the wire
-for each and which arguments throw. The bodies below were sent through an
-in-memory Dio adapter and are shown as it recorded them.
+for each and which arguments throw. The bodies below were sent through
+`DioTransport` over an in-memory Dio adapter and are shown as it recorded
+them.
 
 ## JSON
 
@@ -22,10 +24,9 @@ type (`application/vnd.api+json`) is JSON.
 | `null` | none (`contentType` is `null`) | no body, no `Content-Type` |
 | `null` | `text/plain` | no body, no `Content-Type` |
 
-The runtime encodes a JSON body itself only where Dio gets it wrong: Dio
-sends a `String` as it is, so the string `a"b` would go out unquoted, and it
-sends `null` as no body. A map, list, number or boolean stays Dio's data, so
-an interceptor sees the object, not a string.
+The client encodes every JSON body itself: a string is quoted and `null` is
+the JSON `null`. A transport gets the bytes, so a Dio interceptor sees the
+encoded body, not the object.
 
 > **Gotcha:** A `null` body with a JSON content type is the JSON value
 > `null`, and a generated method passes no `contentType` for an absent
@@ -37,7 +38,7 @@ an interceptor sees the object, not a string.
 A text body (`text/plain`) is sent as the `String` it is. A binary body is a
 `FileUpload` (below). A request is never given a type of the HTTP client:
 signatures use `FileUpload`, `FormBody` and `MultipartBody` so that they do
-not depend on Dio.
+not depend on a transport.
 
 ## `Content-Type` and `Accept`
 
@@ -46,7 +47,7 @@ not depend on Dio.
   ignored when the operation sends a body: it cannot pick
   `application/merge-patch+json`.
 - A `FileUpload` with its own `contentType` wins over the spec's, and a
-  multipart body gets `multipart/form-data; boundary=...` from Dio.
+  multipart body gets `multipart/form-data; boundary=...` from the client.
 - `Accept`: the `OperationRequest.accept` of an operation that has both a
   body method and an event-stream method (for example `application/json`),
   so a server that picks by `Accept` does not answer with the stream. `null`
@@ -108,12 +109,12 @@ FileUpload.stream(file.openRead(), length: await file.length());
 
 - `.bytes` holds the data in memory and works on every platform.
 - `.stream` sends the data as it is read and can be sent **once** (a stream
-  is listened to once); `length` is required, and the runtime sends it as
-  `Content-Length`, because Dio sends a stream as it is.
+  is listened to once); `length` is required, and the client sends it as
+  `Content-Length`.
 - `contentType` wins over the spec's; a value that is not a media type
   (`'nonsense'`) throws a `FormatException` when sending.
 - On the web, Dio's browser adapter buffers a stream into one `Uint8List`
-  before it sends, so a stream is not streamed there.
+  before it sends, so a stream is not streamed there with `DioTransport`.
 
 As a body of its own, a `FileUpload` is sent as the bytes or the stream with
 its `contentType` (or the operation's). `FileUpload(a.bin, 3 bytes, x/y)` is
@@ -134,7 +135,8 @@ MultipartBody([
 ])
 ```
 
-The wire body (boundary shortened, headers lower-cased as Dio writes them):
+The wire body (boundary shortened; the client writes it byte for byte as
+Dio's `FormData` did, headers lower-cased):
 
 ```text
 ----BOUNDARY
@@ -187,12 +189,15 @@ part for each property of the object, in order, `null` giving none
 
 ### The ordering rule
 
-Dio writes every plain field of a `FormData` before its files. A text part
+Dio's `FormData`, which this encoding keeps, writes every plain field
+before its files. A text part
 stays a plain field **while no file or typed part precedes it** (the usual
 shape: values first, files last), and sends no `Content-Type` for the text.
 After the first file or typed part, text parts are sent as
 `text/plain; charset=utf-8` parts (the `caption` above), so the wire order is
-always the order of `MultipartBody.parts`.
+always the order of `MultipartBody.parts`. A file part with no media type
+of its own or of the spec is sent as `application/octet-stream` (Dio's
+`FormData` guessed one from the file name; the client does not guess).
 
 ### Errors
 
@@ -212,9 +217,10 @@ with `toJson` first.
 
 ## Progress
 
-`CallOptions.onSendProgress` and `onReceiveProgress` are Dio's callbacks and
-are passed through. On the web `dio_web_adapter` reports send progress when
-the request has a body; see [Web and platforms](web_and_platforms.md).
+`CallOptions.onSendProgress` and `onReceiveProgress` are counted by the
+client as the body bytes pass to and from the transport: `(count, total)`,
+`total` the body length or the response's `Content-Length` (`-1` without
+one). See [Web and platforms](web_and_platforms.md).
 
 ## See also
 
diff --git a/packages/typed_openapi_client/doc/results_and_errors.md b/packages/typed_openapi_client/doc/results_and_errors.md
index 72e2fd2..944e1f4 100644
--- a/packages/typed_openapi_client/doc/results_and_errors.md
+++ b/packages/typed_openapi_client/doc/results_and_errors.md
@@ -47,14 +47,14 @@ the documented errors (`Never` when there are none).
 | `HttpError<T, E>` | A documented error status (4xx, 5xx or `default`) whose body decoded as `E` | `body`, `statusCode`, `headers` |
 | `UndocumentedStatus<T, E>` | A status the operation does not document | `statusCode`, `rawBody`, `headers` |
 | `DecodeError<T, E>` | A body that does not match the schema, is not valid JSON, or is rejected by a decoder | `error` (a `JsonDecodeException`), `statusCode`, `rawBody`, `headers` |
-| `TransportError<T, E>` | No response: timeout, connection or certificate problem, any other Dio failure | `exception` (a `DioException`), `stackTrace` |
-| `Cancelled<T, E>` | The caller cancelled the request | `exception` (a `DioException`, type `cancel`), `stackTrace` |
+| `TransportError<T, E>` | No complete response: timeout, connection or certificate problem, any other transport failure | `exception` (a `TransportException`), `stackTrace` |
+| `Cancelled<T, E>` | The caller cancelled the request | `exception` (a `TransportException` of kind `cancelled`), `stackTrace` |
 
 Header maps use lower-case names and `List<String>` values. `HttpError` and
 `Success` never hold a raw body; `UndocumentedStatus` and `DecodeError` do.
 
 Real output of each outcome from the generated `getPet`, produced with an
-in-memory Dio adapter (`describe` is a `switch` over the six variants):
+in-memory Dio adapter through `DioTransport` (`describe` is a `switch` over the six variants):
 
 ```text
 200 ok            -> Success 200 Rex
@@ -62,9 +62,9 @@ in-memory Dio adapter (`describe` is a `switch` over the six variants):
 404 wrong body    -> DecodeError status=404 pointer="/code" expected a required property, got no value rawBody={message: x}
 500               -> UndocumentedStatus 500 rawBody={oops: true}
 200 wrong type    -> DecodeError status=200 pointer="/id" expected an integer, got a string rawBody={id: one, name: Rex}
-200 not json      -> DecodeError status=null pointer="" expected a JSON body, got text that is not JSON rawBody=<html>
+200 not json      -> DecodeError status=200 pointer="" expected a JSON body, got text that is not JSON rawBody=<html>
 200 text/plain    -> DecodeError status=200 pointer="" expected an object, got a string rawBody={"id":1,"name":"Rex"}
-timeout           -> TransportError connectionTimeout
+timeout           -> TransportError timeout
 cancel            -> Cancelled
 ```
 
@@ -114,74 +114,57 @@ A success without a response body has `T = void`; match it with `Success()`.
 
 ## What triggers each variant
 
-Requests go through your `Dio`, so Dio's own rules apply first.
-
-1. **`validateStatus`** decides whether Dio treats a status as an error. An
-   error status goes through your interceptors' `onError`, which may resolve
-   it into a response of any status. The decoder then switches on the final
-   status, so a response an interceptor resolved is typed like any other.
-2. A response (a good status, or a `badResponse` that carries one) is decoded
-   by the generated switch: a documented success becomes `Success`, a
-   documented error status `HttpError`, anything else `UndocumentedStatus`.
-3. A decoder that rejects the body gives `DecodeError`: a
-   `JsonDecodeException` (type, missing property, bad date-time) or a
-   `FormatException` thrown by a converter or `Date.parse`. A
-   `FormatException` becomes a `DecodeError` at the root pointer `""`.
-4. A `DioException` without a response is mapped as in the next table.
-
-### How a `DioException` maps
-
-| `DioException.type` | Result |
-| --- | --- |
-| `cancel` | `Cancelled` |
-| `badResponse` with a response | decoded as in step 2 (so `HttpError`, `UndocumentedStatus` or `DecodeError`) |
-| `connectionTimeout`, `sendTimeout`, `receiveTimeout`, `connectionError`, `badCertificate`, `badResponse` without a response | `TransportError` |
-| `unknown` with an `Error` as its cause | rethrown (see below) |
-| `unknown` with a `FormatException` from Dio's JSON parser, on a request that reads JSON | `DecodeError` with no status |
-| `unknown` with any other cause (`SocketException`, `HandshakeException`, custom exceptions) | `TransportError` |
-
-`TransportError.exception.type` tells the kind (`connectionTimeout`,
-`receiveTimeout`, ...), and the original `DioException` is kept whole, so
-`exception.error` and `exception.message` are available.
+The transport sends the request first and owns its rules; with
+`DioTransport` an error status goes through your interceptors' `onError`,
+which may resolve it into a response of any status (see
+[`typed_openapi_dio`](../../typed_openapi_dio/README.md)).
+
+1. A response of any status is read whole and decoded by the generated
+   switch on its final status: a documented success becomes `Success`, a
+   documented error status `HttpError`, anything else
+   `UndocumentedStatus`.
+2. A body that is not valid JSON, or a decoder that rejects the body, gives
+   `DecodeError`: a `JsonDecodeException` (type, missing property, bad
+   date-time) or a `FormatException` thrown by a converter or
+   `Date.parse`. A `FormatException` becomes a `DecodeError` at the root
+   pointer `""`.
+3. A request that gets no complete response fails with a
+   `TransportException`: `Cancelled` for kind `cancelled`, `TransportError`
+   for `timeout`, `connection` and `other`. `exception.cause` is the
+   transport's own exception (a `DioException` for `DioTransport`), kept
+   whole.
 
 ### Malformed JSON
 
-Dio parses JSON itself. When a body is not valid JSON, Dio drops the
-response and throws, so there is no status: the `DecodeError` has
-`statusCode == null`, `error.pointer == ""`, and `error.message` is
-`expected a JSON body, got text that is not JSON`.
-
-- On the VM and dart2wasm, `rawBody` is the text Dio's parser reported:
-  the whole body when Dio read it at once, only the failing chunk when it
-  streamed it (a `Content-Length` header was present).
-- When compiled to JavaScript, Dio reports only the browser's `SyntaxError`
-  text, so `rawBody` is `null`.
-- On the VM, a `FormatException` from anywhere else (`Uri.parse` in an
-  interceptor, a custom transformer that reports text) stays a
-  `TransportError`; a request that does not read JSON (a text or binary
-  operation) never gets a decode error here.
-- In a browser the failures cannot be told apart, so a `FormatException`
-  thrown by an interceptor of a JSON request is also a `DecodeError` there.
+The client parses JSON itself, by the `Content-Type` of the response. When
+a body is not valid JSON, the `DecodeError` has the response's
+`statusCode`, `error.pointer == ""`, `error.message` is
+`expected a JSON body, got text that is not JSON`, and `rawBody` is the
+whole body text, on every platform. A request that does not read JSON (a
+text or binary operation) never gets this error.
 
 ### `rawBody` is best effort
 
 `rawBody` of a `DecodeError` and of an `UndocumentedStatus` is the body as
-Dio returned it: parsed JSON, text or bytes, and `null` when the response
-had no body. When the operation reads bytes or text (a documented binary or
-XML error makes the whole operation read bytes), `UndocumentedStatus.rawBody`
-is the raw bytes, not parsed JSON. JSON sent with a non-JSON content type
-(`text/plain`) is **not** guessed: a JSON operation gets a `String`, which an
-object decoder rejects (the `200 text/plain` line above).
+the client read it: parsed JSON, text or bytes, and `null` when the
+response had no body. When the operation reads bytes or text (a documented
+binary or XML error makes the whole operation read bytes),
+`UndocumentedStatus.rawBody` is the raw bytes, not parsed JSON. JSON sent
+with a non-JSON content type (`text/plain`) is **not** guessed: a JSON
+operation gets a `String`, which an object decoder rejects (the `200
+text/plain` line above).
 
 ## What is never caught
 
-The runtime catches `DioException`, `JsonDecodeException` and, from a
-decoder, `FormatException`. Nothing else:
+The client catches `TransportException`, `JsonDecodeException` and, from a
+decoder, `FormatException`; another `Exception` raised while a body is read
+is a `TransportError` of kind `other`. Nothing else:
 
 - **An `Error` is a bug and reaches the caller.** A `TypeError` or
-  `StateError` thrown by a decoder, or by one of your interceptors or
-  adapters (Dio wraps it in an `unknown` `DioException`), is rethrown with
-  its original stack trace:
+  `StateError` thrown by a decoder, or by the transport (`DioTransport`
+  rethrows one that your interceptors or adapter threw, which Dio wraps in
+  an `unknown` `DioException`), reaches the caller with its original stack
+  trace:
 
   ```text
   rethrown: Bad state: bug in interceptor
@@ -193,12 +176,12 @@ decoder, `FormatException`. Nothing else:
   that cannot be a part. See [Parameters](parameters.md) and
   [Request bodies](request_bodies.md). A media type that is not a media type
   throws `FormatException` from `send`.
-- **An exception your interceptor throws** is a Dio failure like any other:
-  `TransportError`.
+- **An exception your interceptor throws** is a transport failure like any
+  other: `TransportError`.
 
   ```dart
   // onRequest: (o, h) => throw const FormatException('Uri.parse failed')
-  // on the VM -> TransportError (type unknown)
+  // -> TransportError (kind other)
   // handler.reject(DioException(...)) -> TransportError too
   ```
 
@@ -207,12 +190,12 @@ decoder, `FormatException`. Nothing else:
 - `Result` has the same name as `Result` in `package:async`. In a library
   that imports both, hide one:
   `import 'package:async/async.dart' hide Result;` or
-  `import 'package:typed_openapi_runtime/typed_openapi_runtime.dart' hide Result;`,
+  `import 'package:typed_openapi_client/typed_openapi_client.dart' hide Result;`,
   or import one with a prefix.
 - `toString` is short and carries no body: `Success(200)`,
-  `HttpError(404)`, `UndocumentedStatus(500)`, `TransportError(connectionTimeout)`,
+  `HttpError(404)`, `UndocumentedStatus(500)`, `TransportError(timeout)`,
   `Cancelled`. Print `rawBody` yourself if you want it, and mind private data.
-- Retrying is yours: nothing in the runtime retries.
+- Retrying is yours: nothing in the client retries.
 
 ## See also
 
diff --git a/packages/typed_openapi_client/doc/security_metadata.md b/packages/typed_openapi_client/doc/security_metadata.md
index 3c64a34..59e9966 100644
--- a/packages/typed_openapi_client/doc/security_metadata.md
+++ b/packages/typed_openapi_client/doc/security_metadata.md
@@ -2,22 +2,23 @@
 
 A generated client **describes** the security of an operation and sends no
 credentials. The spec's `security` requirements travel with every request as
-metadata, so one interceptor on your `Dio` can add the right token, key or
+metadata, so one interceptor of your transport (here on your `Dio`) can add the right token, key or
 signature for the operation being called. This guide covers the metadata
 types and a working interceptor.
 
 ## Where it is
 
-The runtime puts an `OperationInfo` into `RequestOptions.extra` under
+The client puts an `OperationInfo` into `TransportRequest.operation`;
+`DioTransport` copies it into `RequestOptions.extra` under
 `OperationInfo.extraKey` (`typed_openapi.operation`). Read it with
-`OperationInfo.of(options)`, which is `null` for a request a generated client
-did not send:
+`DioTransport.operationOf(options)`, which is `null` for a request the
+transport did not send:
 
 ```dart
 class AuthInterceptor extends Interceptor {
   @override
   void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
-    final operation = OperationInfo.of(options);
+    final operation = DioTransport.operationOf(options);
     if (operation == null) return handler.next(options); // not a generated call
     print('${operation.operationId}: ${operation.security}');
     // ...
@@ -157,7 +158,7 @@ class AuthInterceptor extends Interceptor {
 
   @override
   void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
-    final operation = OperationInfo.of(options);
+    final operation = DioTransport.operationOf(options);
     if (operation == null) return handler.next(options);
 
     final alternatives = operation.security;
diff --git a/packages/typed_openapi_client/doc/sse.md b/packages/typed_openapi_client/doc/sse.md
index 43caa55..12dc86b 100644
--- a/packages/typed_openapi_client/doc/sse.md
+++ b/packages/typed_openapi_client/doc/sse.md
@@ -2,7 +2,7 @@
 
 An operation whose success is a `text/event-stream` is generated as a method
 that returns `Future<Result<Stream<SseItem<T>>, E>>` and calls
-`DioRequestSender.openEvents`. The `Result` tells you whether the stream
+`ClientSender.openEvents`. The `Result` tells you whether the stream
 opened; the `Stream` is a sequence of typed items that follows the WHATWG
 event-stream rules, optionally reconnects with `Last-Event-ID`, and always
 ends with one `SseDisconnected`. Problems with the data are items, never
@@ -49,8 +49,8 @@ carry the stream; a range is expanded) in the `OperationRequest`.
   `decodeError`, exactly like a normal response: `HttpError`,
   `UndocumentedStatus` or `DecodeError`. An error body is read to the end, so
   it must be finite.
-- A `DioException` is mapped as in [Results and errors](results_and_errors.md):
-  `TransportError`, `Cancelled`.
+- A `TransportException` of the transport is mapped as in
+  [Results and errors](results_and_errors.md): `TransportError`, `Cancelled`.
 - `streamStatuses` must not be empty (an `assert`): without it every status
   would be read to the end, and an endless stream would fill memory. A
   generated method always sets it.
@@ -71,7 +71,7 @@ carry the stream; a range is expanded) in the `OperationRequest`.
 `SseEvent.id` and `retry` are the stream's **last** id and retry, which
 persist across events as WHATWG says, not the ones of that event alone.
 `SseDisconnected.cause` is `null` when the server closed the connection, else
-the error: usually a `DioException` (also `cancel` for a cancelled request),
+the error: usually a `TransportException` (kind `cancelled` for a cancelled request),
 or, when a reconnection is answered with a status that is not a stream, the
 `Failure` of that answer (`UndocumentedStatus(503)`, an `HttpError`, ...).
 `SseDisconnected.lastEventId` is `''` when there was none and the same id a
@@ -146,8 +146,8 @@ event stream":
 `SseMessage` holds `event` (default `message`), `data`, `id` and `retry`.
 `message.json` parses `data` (text that is not JSON, or nesting deeper than
 1000 levels, is a `JsonDecodeException`) and `message.jsonObject` requires an
-object. Use `transformer.bind(stream)`, not `stream.transform(...)`: Dio
-gives a `Stream<Uint8List>`, which does not accept a transformer of
+object. Use `transformer.bind(stream)`, not `stream.transform(...)`: a
+transport gives a `Stream<Uint8List>`, which does not accept a transformer of
 `List<int>` at run time.
 
 ```dart
@@ -286,8 +286,8 @@ await api.pets.watchPet(
 - **Cancelling the subscription** (`subscription.cancel()`) cancels the
   request and closes the connection, also one a reconnection has in flight.
   Use it when the screen goes away.
-- **Cancelling `call.cancelToken`** ends the stream with a last
-  `SseDisconnected(cause: DioException(type: cancel))`, also during a wait:
+- **Cancelling `call.cancel`** (a `CancelSignal`) ends the stream with a last
+  `SseDisconnected(cause: TransportException(kind: cancelled))`, also during a wait:
 
   ```text
   [SseEvent(y, ...), SseDisconnected(cause=cancel, lastEventId="", retry=null, receivedMessage=true)]
@@ -303,7 +303,7 @@ await api.pets.watchPet(
 On the web, Dio's default browser adapter delivers a body only when the
 connection closes, so a stream cannot work with it. `openEvents` then returns
 a `TransportError` whose `exception.message` is
-`DioRequestSender.webStreamingMessage` and `exception.error` is an
+`DioTransport.webStreamingMessage` and `exception.error` is an
 `UnsupportedError`, before any request is sent. Set a fetch-based adapter on
 your `Dio`, such as `ConversionLayerAdapter` from `dio_compatibility_layer`
 with `package:http`'s `BrowserClient`, or `fetch_client`. A reconnection
@@ -315,7 +315,8 @@ that carries an id fails with a `TransportError`. See
 
 ## Testing with a fake stream
 
-`openEvents` needs only an `HttpClientAdapter`, so a test feeds it bytes:
+Through `DioTransport`, `openEvents` needs only an `HttpClientAdapter`, so a
+test feeds it bytes (a fake `ClientTransport` works the same way):
 
 ```dart
 class FakeAdapter implements HttpClientAdapter {
@@ -336,6 +337,7 @@ ResponseBody events(String text, [int status = 200]) => ResponseBody(
 
 final adapter = FakeAdapter((_) => events('id: 1\ndata: {"text": "hello"}\n\n'));
 final dio = Dio()..httpClientAdapter = adapter;
+final transport = DioTransport(dio);
 ```
 
 To test reconnection without sleeping, pass
diff --git a/packages/typed_openapi_client/doc/web_and_platforms.md b/packages/typed_openapi_client/doc/web_and_platforms.md
index ee67d7a..f8d121e 100644
--- a/packages/typed_openapi_client/doc/web_and_platforms.md
+++ b/packages/typed_openapi_client/doc/web_and_platforms.md
@@ -1,6 +1,6 @@
 # Web and platforms
 
-The runtime is pure Dart and runs on the Dart VM, compiled to JavaScript
+The client core is pure Dart and runs on the Dart VM, compiled to JavaScript
 (dart2js) and compiled to WebAssembly (dart2wasm). The same tests run on all
 three, and the places where behavior differs are pinned by tests that assert
 each platform's answer, so a change on one of them is noticed. This guide
@@ -15,15 +15,15 @@ floors.
 | `DeepEquality().equals([nan], [nan])` | `true` (`identical` compares bits) | `false` (`NaN !== NaN`) | `test/platform/platform_semantics_test.dart` |
 | `JsonReader.asInt(1.0)` | rejected | accepted (it is the integer `1`) | `test/json/json_reader_test.dart` |
 | Integers beyond 2^53 | exact up to int64 | lose precision | `test/json/json_reader_int64_test.dart` (VM only) |
-| Malformed JSON body: `DecodeError.rawBody` | the body text | `null` (only the browser's `SyntaxError`) | `test/dio/web_test.dart` |
-| `Cookie` header from a cookie parameter | sent | **dropped by the browser** | `test/dio/cookie_browser_test.dart` |
-| `openEvents` with Dio's default adapter | streams | `TransportError` that explains how to fix it | `test/dio/web_test.dart` |
-| `FileUpload.stream` | streamed | buffered into one `Uint8List` by Dio's browser adapter | the doc comment of `FileUpload` |
-| `onSendProgress` | reported | reported by `dio_web_adapter` 2.2.2 through `XMLHttpRequest.upload` when the request has a body | `test/dio/dio_request_sender_test.dart` (VM) |
+| `Cookie` header from a cookie parameter | sent | **dropped by the browser** | `typed_openapi_dio`: `test/cookie_browser_test.dart` |
+| `openEvents` through `DioTransport` with Dio's default adapter | streams | `TransportError` that explains how to fix it | `typed_openapi_dio`: `test/web_test.dart` |
+| `FileUpload.stream` through `DioTransport` | streamed | buffered into one `Uint8List` by Dio's browser adapter | the doc comment of `FileUpload` |
 
 dart2wasm keeps `0` and `0.0` apart, so it behaves like the VM everywhere in
-the table except the malformed-JSON `rawBody`, where the body bytes are
-available to dart2wasm but not to dart2js.
+the table. A malformed JSON body is parsed by the client, so its
+`DecodeError` is the same on all three. The transport conformance suite
+(`typed_openapi_transport_tests`) runs every transport against a loopback
+server on the VM, dart2js and dart2wasm.
 
 ## Numbers
 
@@ -42,7 +42,7 @@ JavaScript has one number type. Three consequences:
   `String` id works only if the server sends a string.
 
 > **Gotcha:** Do not write an int literal beyond 2^53 in code that must
-> compile to JavaScript. `dart2js` rejects it. The runtime keeps such
+> compile to JavaScript. `dart2js` rejects it. The client keeps such
 > literals out of `lib/`, and the tests that need them are `@TestOn('vm')`.
 
 ## Cookies
@@ -52,22 +52,24 @@ and `fetch` ignore it), so **cookie parameters do not work on the web**: the
 browser keeps its own cookies and sends them itself, subject to its
 credentials settings. A test starts a local server, calls it from Chrome,
 compiled to JavaScript and to Wasm, and checks that a `Cookie` header set
-through Dio, by a `CookieParameter` or directly in `Options`, never reaches
-the server, while another header (`X-Probe`) of the same request does.
+by a `CookieParameter` or directly in Dio's `Options`, never reaches the
+server, while another header (`X-Probe`) of the same request does.
 
 ```sh
-dart test -p chrome test/dio/cookie_browser_test.dart
-dart test -p chrome --compiler dart2wasm test/dio/cookie_browser_test.dart
+cd packages/typed_openapi_dio
+dart test -p chrome test/cookie_browser_test.dart
+dart test -p chrome --compiler dart2wasm test/cookie_browser_test.dart
 ```
 
 Both print `All tests passed!`.
 
 ## Event streams
 
-Dio's default browser adapter delivers a body only when the connection
-closes. `openEvents` therefore checks, before any request is sent, whether
-the Dio has the default adapter on the web, and returns a `TransportError`
-whose message is `DioRequestSender.webStreamingMessage`:
+An event stream needs a transport that streams the body. Dio's default
+browser adapter delivers a body only when the connection closes, so
+`DioTransport` checks, before any request is sent, whether the Dio has the
+default adapter on the web, and fails with a `TransportException` whose
+message is `DioTransport.webStreamingMessage`:
 
 ```text
 Server-sent events need a streaming HTTP adapter on the web: Dio's default
@@ -77,70 +79,58 @@ package:dio_compatibility_layer with package:http's BrowserClient or
 package:fetch_client.
 ```
 
-`TransportError.exception.error` is an `UnsupportedError`, and the request
-options carry the `OperationInfo`, so an error handler can name the
-operation. A reconnecting stream fails the same way: `openEvents` returns the `TransportError` before any stream exists, so there is no wait and no reconnection.
-Once you set a non-default adapter, the stream opens:
-`test/dio/open_events_test.dart` (VM, with `isWeb: true`) and
-`test/dio/web_test.dart` (a real browser) pin both halves.
+`TransportError.exception.cause` is an `UnsupportedError`. A reconnecting
+stream fails the same way: `openEvents` returns the `TransportError` before
+any stream exists, so there is no wait and no reconnection. Once you set a
+non-default adapter, the stream opens: `web_test.dart` of `typed_openapi_dio`
+pins the refusal in a real browser, and its conformance suite runs the event
+stream case on the VM.
 
 For a cross-origin stream, the reconnection's `Last-Event-ID` is not a
 CORS-safelisted request header: the server must list it in
 `Access-Control-Allow-Headers`, or every reconnection that carries an id
 fails with a `TransportError`. See [Server-Sent Events](sse.md).
 
-## Malformed JSON
+## Detecting the web
 
-Dio parses JSON itself and drops the response when it cannot. What it
-reports differs by compiler, and `test/dio/web_test.dart` asserts each:
-
-- dart2wasm and the VM: the body text, so `DecodeError.rawBody` is the body
-  (`{"id":`, `<html>`, `{"id": 7}x`).
-- dart2js: only the browser's `SyntaxError` message, so `rawBody` is `null`.
-
-The result is a `DecodeError` with no status and pointer `""` on all of them.
-The runtime's detection of "web" is `bool.fromEnvironment('dart.library.js_interop')`,
-true on dart2js and dart2wasm; `DioRequestSender(dio).isWeb` exposes it, and a
-test can set `isWeb:` to simulate a browser. A `FormatException` that an
-interceptor throws on a JSON request is also a `DecodeError` in a browser,
-because the two failures cannot be told apart there.
+`DioTransport` detects "web" with
+`bool.fromEnvironment('dart.library.js_interop')`, true on dart2js and
+dart2wasm; `DioTransport(dio).isWeb` exposes it, and a test can set
+`isWeb:` to simulate a browser.
 
 ## Files and progress
 
 `FileUpload.bytes` works everywhere. `FileUpload.stream` is sent as it is
 read on the VM; Dio's browser adapter buffers a stream into one `Uint8List`,
-so it is not streamed on the web. `onSendProgress` is passed to Dio. On the web
-`dio_web_adapter` 2.2.2 reports it through the upload events of the
-`XMLHttpRequest` when the request has a body, and only logs a warning when
-there is no body to report on.
+so it is not streamed on the web through `DioTransport`. `onSendProgress`
+and `onReceiveProgress` are counted by the client as the body bytes pass to
+and from the transport, the same on every platform.
 
 ## Running the tests
 
 ```sh
-cd packages/typed_openapi_runtime
+cd packages/typed_openapi_client
 dart test                                    # the VM
 dart test -p chrome                          # dart2js (needs Chrome)
 dart test -p chrome --compiler dart2wasm     # dart2wasm
 ```
 
 A file that needs the VM (`dart:io`, int64 literals) carries `@TestOn('vm')`,
-a single test `testOn: 'vm'`, and `test/dio/web_test.dart` is
-`@TestOn('browser')`. If Chrome is not found, set `CHROME_EXECUTABLE`.
-`test/helpers/test_platform.dart` tells the platform to assertions that
-differ (`isWeb`, and `isJavaScript` as `identical(0, 0.0)`). Runtime tests
-never touch the network; Dio gets a fake adapter.
+and a single test `testOn: 'vm'`. If Chrome is not found, set
+`CHROME_EXECUTABLE`. `test/helpers/test_platform.dart` tells the platform to
+assertions that differ (`isWeb`, and `isJavaScript` as `identical(0, 0.0)`).
+The tests never touch the network; they send through `FakeTransport`.
 
 ## SDK and dependency floors
 
 | | Floor |
 | --- | --- |
 | Dart SDK | `>=3.10.0 <4.0.0`, also for generated code |
-| `dio` | `^5.11.1` |
 | `meta` | `^1.15.0`, low enough that Flutter's pinned `meta` resolves |
 
-The package is not Flutter-specific and has no Flutter dependency. The
-runtime re-exports `immutable` from `package:meta`, so generated code imports
-only this package and `Dio`.
+The package is not Flutter-specific and has no Flutter dependency. It
+re-exports `immutable` from `package:meta`, so generated code imports only
+this package. `typed_openapi_dio` adds `dio` `^5.11.1`.
 
 ## See also
 
@@ -148,3 +138,4 @@ only this package and `Dio`.
 - [Server-Sent Events](sse.md) - streaming adapters and reconnection.
 - [JSON decoding](json_decoding.md) - `asInt`, integers and dates.
 - [Results and errors](results_and_errors.md) - the malformed-JSON `DecodeError`.
+- [`typed_openapi_dio`](../../typed_openapi_dio/README.md) - the Dio transport on the web.
diff --git a/packages/typed_openapi_dio/README.md b/packages/typed_openapi_dio/README.md
index 80af6a2..df7dd24 100644
--- a/packages/typed_openapi_dio/README.md
+++ b/packages/typed_openapi_dio/README.md
@@ -1,13 +1,138 @@
 # typed_openapi_dio
 
-The Dio transport of clients generated by typed_openapi.
+The [Dio](https://pub.dev/packages/dio) transport of clients generated by
+[`typed_openapi`](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/README.md).
+A generated client builds its requests and reads its responses with
+[`typed_openapi_client`](../typed_openapi_client/README.md); `DioTransport`
+sends them through your own `Dio`.
+
+> **Status:** in development, not published yet.
+
+## Install
+
+```yaml
+dependencies:
+  dio: ^5.11.1
+  typed_openapi_client: ^0.0.1   # not on pub.dev yet; use a path or git dependency
+  typed_openapi_dio: ^0.0.1
+```
+
+## Setup
 
 ```dart
-final api = PetsApi(DioTransport(Dio(BaseOptions(baseUrl: url))));
+import 'package:dio/dio.dart';
+import 'package:typed_openapi_dio/typed_openapi_dio.dart';
+
+import 'petshop/petshop.dart'; // generated
+
+final dio = Dio(
+  BaseOptions(
+    baseUrl: 'https://api.example.com', // the client never sets one
+    connectTimeout: const Duration(seconds: 5),
+  ),
+);
+final api = PetshopClient(DioTransport(dio));
 ```
 
-Your `Dio` keeps its base URL, interceptors, timeouts and adapter. Dio
-reads every response as a stream and the client decodes the bytes, so a
-`Transformer` or `responseDecoder` is not used, and a request interceptor
-sees the body as bytes. Server-sent events in a browser need a streaming
-adapter (see `DioTransport.webStreamingMessage`).
+## Your Dio, as it is
+
+- `DioTransport` never changes your `Dio`: its base URL, headers, timeouts,
+  interceptors, adapter and `validateStatus` stay yours. Nothing is retried;
+  retries are your interceptors' job.
+- Dio reads every response as a stream (`ResponseType.stream`) and the
+  client decodes the bytes, so a `Transformer` or `responseDecoder` of your
+  `Dio` is not used.
+- An error status goes through your `onError` interceptors first (a token
+  refresh still works) and then reaches the client as a response, which it
+  types as `HttpError` or `UndocumentedStatus`.
+- The path and the query are encoded by the client and given to Dio as one
+  finished target: in an interceptor `options.queryParameters` is empty;
+  read `options.uri`. Dio collapses every `//` of a finished URL, query
+  included; when a query value holds `//` (an `allowReserved` value such as
+  `next=/a//b`) and the base URL is absolute, the transport joins the base
+  URL itself so that the value survives.
+- A request interceptor sees the body as the bytes the client encoded (a
+  `Stream<List<int>>` with its `Content-Type` and `Content-Length`
+  headers), not as a map.
+- `CallOptions.extra` is merged into `RequestOptions.extra`.
+
+## Interceptors and security metadata
+
+`DioTransport.operationOf(options)` gives the `OperationInfo` of the
+request in an interceptor: its operation id, method, path template, tags
+and security requirements. One interceptor can add the right credential:
+
+```dart
+dio.interceptors.add(
+  InterceptorsWrapper(
+    onRequest: (options, handler) {
+      final operation = DioTransport.operationOf(options);
+      final needsKey = operation?.security.any(
+        (alternative) => alternative.any(
+          (use) => use.scheme.name == 'apiKey',
+        ),
+      );
+      if (needsKey ?? false) options.headers['X-Api-Key'] = apiKey;
+      handler.next(options);
+    },
+  ),
+);
+```
+
+See [Security metadata](../typed_openapi_client/doc/security_metadata.md).
+
+## Cancelling
+
+A call is cancelled through the client's `CancelSignal`, which the
+transport turns into a Dio `CancelToken`:
+
+```dart
+final cancel = CancelSignal();
+final pending = api.pets.getPet(petId: 7, call: CallOptions(cancel: cancel));
+cancel.cancel('user left the page');
+print(await pending); // Cancelled
+```
+
+## How Dio's failures map
+
+| `DioException.type` | `TransportException.kind` | Result |
+| --- | --- | --- |
+| `connectionTimeout`, `sendTimeout`, `receiveTimeout` | `timeout` | `TransportError` |
+| `connectionError` | `connection` | `TransportError` |
+| `cancel` | `cancelled` | `Cancelled` |
+| `badResponse` with a body | - | the response, typed by its status |
+| anything else | `other` | `TransportError` |
+
+The `DioException` is the `cause` of the `TransportException`, kept whole.
+An `Error` that an interceptor or the adapter throws (Dio wraps it into an
+`unknown` `DioException`) is thrown again: it is a bug, not a failure.
+
+## Web
+
+The transport works on dart2js and dart2wasm. Server-sent events need a
+streaming adapter there: Dio's default browser adapter delivers a body only
+when the connection closes, so with it an event-stream operation returns a
+`TransportError` whose message is `DioTransport.webStreamingMessage`. Set a
+fetch-based adapter on your `Dio`, such as `ConversionLayerAdapter` from
+`dio_compatibility_layer` with `package:http`'s `BrowserClient` or
+`fetch_client`. Dio's browser adapter also buffers a streamed file upload
+into one `Uint8List`. A `Cookie` header never reaches the server from a
+browser (`test/cookie_browser_test.dart`).
+
+## Development
+
+```sh
+dart test                                    # the VM
+dart test -p chrome                          # dart2js (needs Chrome)
+dart test -p chrome --compiler dart2wasm     # dart2wasm
+```
+
+`test/conformance_test.dart` runs the transport conformance suite of
+`typed_openapi_transport_tests` against its loopback server on all three; the
+event-stream case is skipped in a browser, where `DioTransport` refuses
+event streams with the default adapter.
+
+Inside the workspace `typed_openapi_client` resolves to the package next
+to this one (`resolution: workspace`). It is published from pub.dev, so a
+release that needs a new client publishes `typed_openapi_client` first and
+this package after it.
~~~~

---

## Corpus run

- Task 1: `corpus update` regenerated every client of both modes: 40 clients (38 generated, 2 with expected check errors), 27759 files, about 9.5 minutes; only file hashes changed in `corpus.lock`; diagnostics and round-trip counts equal; round-trip failures 0.
- Task 4 (part 4c): `corpus update` (7 min 51 s): 40 clients, 38 generated, 27759 files; 652 lines of `corpus.lock` changed, all file hashes (the group and root files of every client in both modes); diagnostics and round-trip counts equal; round-trip failures 0; 222 spec defects reported, as before (the final check lists 224: 4 printed and "220 more"; its counts equal the lock).

## Fuzz

Task 4 (part 4c): 200 seeds, 1200 builds, 10907 files, 17 sampled, 0 problems.

## Defects found

1. **The multipart boundary in JavaScript** (part 4a, found in the replay, fixed in the patch): `Random().nextInt(1 << 32)` throws `RangeError` under dart2js and dart2wasm, since `1 << 32` is `0` there. Seven multipart tests failed in Chrome only.
2. **The fixture package cannot resolve `typed_openapi_dio`** (part 4c): the adapter depends on the hosted `typed_openapi_client`, the fixture on the path one; `dependency_overrides` is required (the same holds for any user package that uses both path packages).
3. **Two generator tests pinned Dio's name** (`dio_names_test`, `operation_contract_test`'s `DioModel`) and the programs used `OperationInfo.of` and `CancelToken`: all in the part 4c patch.
4. Test-only: a `dart:io` test server buffers SSE writes unless `bufferOutput = false` (part 4b).
5. Test-only, task 5: under dart2wasm the ports the hybrid server sends over the channel arrive as `double`, so `ConformanceContext` reads them as `num` and calls `toInt()`.
6. Test-only, task 5: the form case expected `+` for a space; the core encodes `application/x-www-form-urlencoded` with `%20` (as the runtime and Dio did), so the expectation is `a=x%20y&b=1`.
7. Not a defect: a conformance event case that seemed to hang was the test cancelling after the second event of a stream that sends one; `DioTransport` cancels correctly and no core change was needed.

None in the code on main.

## Deferred

- A `package:http` or `dart:io` adapter (spec, out of scope).
- Size-limit ratchet tests (`test/quality/size_limits_test.dart`) for `typed_openapi_dio` and `typed_openapi_transport_tests`; every file of both is within the limits today.

## Open questions

1. **A multipart file part with no media type** (the file gives none and the spec's `encoding` gives none). **Decided:** the core sends `application/octet-stream` and does not guess. Dio 5.11.1 guessed from the file name (`x.gif` gave `image/gif`); the core has no MIME table (it depends on `meta` only), and a guess is a silent default. This is a wire change for such parts only: the client CHANGELOG says so, `request_bodies.md` documents it, and a caller who needs a type passes `FileUpload(contentType: ...)` or the spec's `encoding`.
2. Interceptors see bytes (spec open question 1). Default: bytes.
3. The conformance package is separate and unpublished (spec open question 2). Default: separate.
4. `HEAD` and redirects (spec open question 3). Default: Dio's own, documented by the suite.
5. The tool's `--runtime` option keeps its name (it now points at the client package). Default: kept.
6. **Publishing.** **Decided:** `typed_openapi_dio` depends on `typed_openapi_client: ^0.0.1` with `resolution: workspace`, so inside the repository it resolves to the path package and its dry-run passes before the client is on pub.dev. Outside the workspace it needs the client published (or a `dependency_overrides`, as the generator's fixture package has). So a release publishes `typed_openapi_client` first (its tag), then `typed_openapi_dio` (its own tag, `typed_openapi_dio-v*` in `publish.yml`); the workflow header and the adapter README say so.

## Self-review

- Spec coverage: decisions 1-10 map to tasks 1-7; the builder-check calls are decisions 3, 5, 6, 8, 10 here and task 5.
- Interfaces: names are the same in every task (`ClientSender`, `ClientTransport`, `CancelSignal`, `TransportException(kind, message, {cause, stackTrace})`, `DioTransport.operationOf`).
- The patches are the verified scratch commits. Every task leaves every suite green: tasks 4 to 6 of the first draft, whose first part left the generator red, are one task (task 4) with one gate and one commit.
- The patches re-apply: on a fresh worktree at the task 1 commit, the `git rm` blocks and the diffs of tasks 2 to 7 applied in plan order with `git apply --index` (and task 5's `git rm` step) give the scratch head's tree, except the 7 goldens and `corpus.lock` that the commands of part 4c regenerate.
