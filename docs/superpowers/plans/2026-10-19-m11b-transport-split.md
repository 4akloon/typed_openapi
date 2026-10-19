# M11b plan: transport split, client core and Dio adapter

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status:** Tasks 1 to 6 were replayed from main (2d86694) on a scratch
> worktree, in this order, and each task's code is in this plan as the
> patch that was verified (new files in full, edits as unified diffs; apply
> with `git apply`, see "How to use the patches"). Tasks 7 to 9
> (conformance package, CI, documentation) were **not replayed**: they are
> designed down to files and cases, see "Not replayed" at the end.

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
- After every task: `dart pub get` and `dart analyze packages` (root, `No issues found!`); `dart test` in every workspace package (exception: between task 4 and task 6 the generator's `generated_client_test` is red, because the generated code still names `DioRequestSender`; land tasks 4 to 6 on one branch and merge them together); `dart test -p chrome` and `dart test -p chrome --compiler dart2wasm` in `typed_openapi_client` and `typed_openapi_dio`; `dart format lib test` (generator and tool: `lib test bin`) changes 0 files on a second run. Chrome: `CHROME_EXECUTABLE=/usr/bin/google-chrome` where it is not found.
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
| `packages/typed_openapi_client/lib/src/client/{client_sender,event_opener,event_call,connection_signals,request_builder,response_reader,progress_counter,client_results,call_options}.dart` | 4 | replaces `lib/src/dio/` |
| `packages/typed_openapi_client/lib/src/{result/result,request/operation_info,sse/sse_reconnector}.dart` | 4 | Dio types replaced |
| `packages/typed_openapi_client/test/helpers/fake_transport.dart`, `gated_transport.dart` | 4 | replace `fake_adapter.dart`, `gated_adapter.dart` |
| `packages/typed_openapi_client/test/client/*` | 4 | ports of `test/dio/*` |
| `packages/typed_openapi_dio/` | 5 | `DioTransport`, `DioFailures`, `QueryGuard`, Dio-specific, web, cookie and loopback tests |
| `packages/typed_openapi/lib/src/emit/{operation_emitter,api_library,decoder_writer}.dart`, `lib/src/ir/{names,operation_checks}.dart`, `lib/src/model/media_type_name.dart`, `lib/src/diagnostics/diagnostic_code.dart` | 6 | generated code takes `ClientTransport` |
| `packages/typed_openapi/test/emit/{programs/*,generated_client_test.dart}`, `test/ir/{transport_names_test,operation_contract_test}.dart`, goldens, `CHANGELOG.md` | 6 | |
| `packages/typed_openapi_tool/lib/src/{corpus/corpus_package,fuzz/fuzz_spec}.dart`, `corpus.lock` | 6 | |
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

// typed_openapi_dio (task 5)
final class DioTransport implements ClientTransport {
  DioTransport(Dio dio, {bool? isWeb});
  static const String webStreamingMessage;
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
- Task 7: the new packages get `test/quality/size_limits_test.dart` with empty allowlists (not replayed; the replayed `typed_openapi_dio` files are all below the limits: the longest is `dio_transport.dart`, 120 lines).

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

### Task 4: `ClientSender` replaces `DioRequestSender`

**Files:** create `lib/src/client/` (`client_sender`, `event_opener`, `event_call`, `connection_signals`, `request_builder`, `response_reader`, `progress_counter`, `client_results`, `call_options`); delete `lib/src/dio/`, `test/dio/`, `test/helpers/{fake_adapter,gated_adapter}.dart`; edit `result/result.dart`, `request/operation_info.dart` (drop `of` and the Dio import), `request/raw_response.dart` and `request/operation_request.dart` (doc comments), `sse/sse_reconnector.dart` (decision 10), the barrel, `pubspec.yaml` (drop `dio` and `stream_channel`), `test/quality/size_limits_test.dart` (drop the two entries of deleted files); `test/helpers/{fake_transport,gated_transport,pets_api,watch_stream}.dart`; port `test/dio/*` to `test/client/*`.

Port map: `bodies_send_test`, `json_body_test`, `multipart_send_test`, `accept_test`, `open_events_test` and the sender tests -> `test/client/*` against `FakeTransport` (expected bytes unchanged; the end causes are the kind names `connection` and `cancelled`); the Dio-specific cases (the `//` query guard, Dio unchanged, `onError` first, a resolved response, `validateStatus`, an `Error` in an interceptor, the interceptor's security metadata, the web tests and the cookie test) -> task 5.

New behaviour tests (in the patch): a documented error status is typed; transport failures keep the `TransportException`; an `Exception` while the body is read is a transport failure; invalid JSON is a `DecodeError` with the status and the text.

Defect found and fixed in this task during the replay: the multipart boundary was `Random().nextInt(1 << 32)`, which is `nextInt(0)` in JavaScript (`RangeError` on every multipart call in Chrome); the patch uses the literal `4294967296` with a comment.

- [ ] **Step 1: Apply the patch** below (it deletes `lib/src/dio/` and `test/dio/`).
- [ ] **Step 2: Verify**: client `+305` on the VM, `+289` in Chrome with dart2js and with dart2wasm; analyze clean; `RequestBuilder.build` and `EventOpener._connect` are under 40 lines (`_headers` and `_events` extracted). The generator's `generated_client_test` is red until task 6 (see Global Constraints).
- [ ] **Step 3: Commit** `feat(typed_openapi_client)!: send through a ClientTransport`.

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

### Task 5: `typed_openapi_dio`

**Files:** `packages/typed_openapi_dio/{pubspec.yaml,README.md,CHANGELOG.md,LICENSE}`, `lib/typed_openapi_dio.dart`, `lib/src/{dio_transport,dio_failures,query_guard}.dart`; tests `test/{dio_transport_test,loopback_test,web_test,cookie_browser_test,cookie_server}.dart`, `test/helpers/fake_adapter.dart`; root `pubspec.yaml` workspace entry.

Behaviour: `dio.request<ResponseBody>(QueryGuard(baseUrl).target(target), data: body, options: Options(method:, headers:, responseType: .stream, extra: {...extra, OperationInfo.extraKey: operation}), cancelToken:)`; a header with several values is joined with `, `; the `CancelSignal` cancels a `CancelToken` made per request; a `DioException` whose response holds a `ResponseBody` (an error status after `onError`) is a `TransportResponse`; an `unknown` one with an `Error` rethrows the `Error`; the others are a `TransportException` (decision 3) with the `DioException` as cause; the response body stream maps a `DioException` to a `TransportException` (decision 14).

Notes from the replay: the loopback SSE test's `HttpServer` must set `response.bufferOutput = false`, or the events never leave the server before the cancel (the test hangs 30 s); `web_test` changes as decision 8 says (malformed JSON keeps status `200` and the text on both compilers; a `FormatException` from an interceptor is a `TransportError`).

- [ ] **Step 1: Apply the patches** below (two commits).
- [ ] **Step 2: Verify**: `dart pub get` (adds `dio_web_adapter`); adapter `+11` on the VM (10 adapter cases and the loopback stream), `+21` in Chrome with dart2js and with dart2wasm (web and cookie tests); analyze clean.
- [ ] **Step 3: Commit** `feat(typed_openapi_dio): the Dio transport`.

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

### Task 6: Generated code takes a `ClientTransport`

**Files:** see the Files table (task 6).

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
- [ ] **Step 6: Commit** `feat(typed_openapi)!: generated clients take a ClientTransport`.

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

### Task 7: Conformance server and suite (not replayed)

**Files:** `packages/typed_openapi_transport_tests/` (`publish_to: none`): `lib/src/conformance_server.dart` (a `dart:io` `HttpServer` on `127.0.0.1:0`, routes per case), `lib/src/server_main.dart` (`hybridMain` for `spawnHybridUri`, so Chrome tests reach it), `lib/src/transport_conformance.dart` and one file per case group: methods, headers, statuses, bodies (JSON, form, multipart, file stream), cancellation (before send, in flight, mid-stream), failures (connection refused, timeout), events (stream, reconnect with `Last-Event-ID`), progress. `typed_openapi_dio/test/conformance_test.dart` runs it on the VM and in Chrome with stated skips (repeated request headers, cookies, `HEAD` body rules, in-flight upload progress and stream uploads on the web). The task 5 `loopback_test.dart` moves into the suite. Each new package gets `test/quality/size_limits_test.dart` with an empty allowlist.

Commit: `test(typed_openapi_transport_tests): transport conformance suite`.

### Task 8: CI, workspace, publish (not replayed)

`ci.yml`: tests of `typed_openapi_dio` and `typed_openapi_transport_tests` in the matrix; the web job runs the client and the adapter with both compilers; the publish dry-run covers `typed_openapi_client` and `typed_openapi_dio` (`dart pub publish --dry-run` of the adapter needs the client published first, or a `dependency_overrides` note). `nightly.yml` the same for the beta SDK. `workflows_test.dart` pins the new rows. `publish.yml` publishes the two packages, client first.

Commit: `ci: test and publish the client and the Dio adapter`.

### Task 9: Documentation (not replayed)

The runtime README and `doc/` stay with the client and lose the Dio setup; the Dio parts (setup, web, interceptors and `operationOf`, cancellation through `CancelSignal`, the bypassed `Transformer`, the bytes an interceptor sees) go to `typed_openapi_dio/README.md`; `sse.md` and `event_streams.md` split; `CLAUDE.md` (Project list with the new packages, the Runtime section rewritten for client + adapter + conformance, the emit/ text that says "Only `Dio` is imported", `DioRequestSender`, `FakeAdapter`), `docs/roadmap.md` (M11b row), `docs/superpowers/HANDOFF.md`, `docs/code-quality-review.md` (moved paths). The doc comments of the generator that still name Dio for history (`part_media_type.dart`: TOA661 says Dio's `DioMediaType.parse` would throw; the core's `ParsedMediaType` now does) are reworded here.

Commit: `docs: the client core and the Dio adapter`.

---

## Corpus run

- Task 1: `corpus update` regenerated every client of both modes: 40 clients (38 generated, 2 with expected check errors), 27759 files, about 9.5 minutes; only file hashes changed in `corpus.lock`; diagnostics and round-trip counts equal; round-trip failures 0.
- Task 6: `corpus update` (7 min 51 s): 40 clients, 38 generated, 27759 files; 652 lines of `corpus.lock` changed, all file hashes (the group and root files of every client in both modes); diagnostics and round-trip counts equal; round-trip failures 0; 222 spec defects reported, as before.

## Fuzz

Task 6: 200 seeds, 1200 builds, 10907 files, 17 sampled, 0 problems.

## Defects found

1. **The multipart boundary in JavaScript** (task 4, found in the replay, fixed in the patch): `Random().nextInt(1 << 32)` throws `RangeError` under dart2js and dart2wasm, since `1 << 32` is `0` there. Seven multipart tests failed in Chrome only.
2. **The fixture package cannot resolve `typed_openapi_dio`** (task 6): the adapter depends on the hosted `typed_openapi_client`, the fixture on the path one; `dependency_overrides` is required (the same holds for any user package that uses both path packages).
3. **Two generator tests pinned Dio's name** (`dio_names_test`, `operation_contract_test`'s `DioModel`) and the programs used `OperationInfo.of` and `CancelToken`: all in the task 6 patch.
4. Test-only: a `dart:io` test server buffers SSE writes unless `bufferOutput = false` (task 5).

None in the code on main.

## Deferred

- A `package:http` or `dart:io` adapter (spec, out of scope).

## Open questions

1. **A multipart file part with no media type** (the file gives none and the spec's `encoding` gives none): Dio guessed one from the file name (`x.gif` -> `image/gif`); the core depends on `meta` only and sends `application/octet-stream`. Default: `application/octet-stream` (a wire change for such parts, written in the client CHANGELOG).
2. Interceptors see bytes (spec open question 1). Default: bytes.
3. The conformance package is separate and unpublished (spec open question 2). Default: separate.
4. `HEAD` and redirects (spec open question 3). Default: Dio's own, documented by the suite.
5. The tool's `--runtime` option keeps its name (it now points at the client package). Default: kept.
6. The adapter depends on `typed_openapi_client: ^0.0.1` (hosted); inside the workspace it resolves to the path package, outside it needs both published or an override. Default: release the client first, then the adapter, from `publish.yml`.

## Not replayed

- Task 7 (conformance package), task 8 (CI and publish), task 9 (documentation): designed above, no code in this plan, not run.

## Self-review

- Spec coverage: decisions 1-10 map to tasks 1-9; the builder-check calls are decisions 3, 5, 6, 8, 10 here and task 5.
- Interfaces: names are the same in every task (`ClientSender`, `ClientTransport`, `CancelSignal`, `TransportException(kind, message, {cause, stackTrace})`, `DioTransport.operationOf`).
- The patches are the verified scratch commits; task 4's patch leaves the generator red until task 6, which the Global Constraints state.
