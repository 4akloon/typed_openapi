# M9 plan: operation emitter and the whole client from `generate`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `typed_openapi generate` writes, for every client without `check` errors, the whole Dart client: the M8 models, an API class per group with typed methods (`Future<Result<T, E>>`), the sealed status types, the multipart parts classes and a root client with the servers, and the generated code is clean under `package:lints/recommended` and `flutter_lints` and really sends requests through Dio.

**Architecture:** The runtime gets the bodies a method sends (`FileUpload`, `FormBody`, `MultipartBody`), security metadata on `OperationInfo` and `RawResponse.parsedJson`; `DioBody` turns them into what Dio sends, so generated signatures have no Dio types (task 1). The IR gets what the emitter needs, in collaborators of `OperationBuilder` (`BodyEncoding`, `SecurityBuilder`, `PartsBuilder`, `OperationChecks`) and in `ApiNames`, which names the root client, the status types, their variants and the parts classes after the M8 names, so no model ever moves (tasks 2-3). A new emitter (`ApiLibrary`, `OperationEmitter`, `RequestWriter`, `DecoderWriter`, `StatusTypeEmitter`, `PartsEmitter`) prints the IR only (task 4); gates analyze generated clients and call one through a fake Dio adapter (task 5); `generate` writes the whole client (task 6); the corpus and the fuzz found five defects, fixed in task 7; task 8 records what M9 closed and deferred.

**Tech Stack:** Dart `>=3.10.0 <4.0.0`, pure Dart; runtime dependencies stay `dio` and `meta`; the generator gets `typed_openapi_runtime` as a dev dependency only (a test keeps the path-variable pattern equal); tests on `package:test`; the analyzer gate runs `dart analyze` in a subprocess on a generated package.

**Spec:** [docs/superpowers/specs/2026-10-13-m9-operations-design.md](../specs/2026-10-13-m9-operations-design.md), decisions 1-14 (binding). Requirements: R5.3, R10.1-R10.9, R11.1-R11.7 ([requirements.md](../../requirements.md)). Earlier designs: [M7 runtime](../specs/2026-10-12-m7-runtime-design.md), [M8 models](../specs/2026-10-12-m8-models-design.md) (decisions 15-18). Carried over: [roadmap](../../roadmap.md), the "Moved from M2" to "Moved from M8" sections, rows with M9. Code rules and size limits: [CLAUDE.md](../../../CLAUDE.md), [code-quality-review.md](../../code-quality-review.md).

## Global Constraints

- SDK `>=3.10.0 <4.0.0`; both packages pure Dart; generated code is Dart 3.10. Primary constructors (3.13) are not used.
- Dart 3.10 is used actively: dot shorthands, null-aware elements, switch expressions and patterns, records, class modifiers. In tests the arguments of `expect(...)` use full names.
- OOP, no top-level functions except `main` in `bin/` and tests (test helpers as in the existing tests). Components that report take a `DiagnosticBag` or an `IrContext`.
- The IR is the emitter's only input: the emitter never reads the spec; what it lacks is added to the IR.
- Nothing is guessed silently: every fallback is a diagnostic with a code and a JSON pointer, and an override snippet where the target is addressable.
- Deterministic output: the same spec and config give byte-identical files; everything is sorted.
- Every spec string is escaped at every sink: literals through `DartCode.string`, doc comments through `DartCode.docLines`, code spans through `DartCode.docSpan`, identifiers only from the IR.
- Generated code is clean under `package:lints/recommended` plus the `flutter_lints` rules, with no `ignore_for_file`; the first line after the header is `// dart format off`.
- The runtime depends on `dio` and `meta` only and works on the VM, dart2js and dart2wasm; new runtime code has browser tests (`dart test -p chrome`, also `--compiler dart2wasm`).
- Generated code never changes the user's Dio (R10.1): no `baseUrl`, no interceptor; HTTP errors go through Dio's `onError` (R10.2).
- Every new code is in `DiagnosticCode` with a doc comment, a kebab-case slug and a default level.
- Negative tests on valid specs: no new diagnostic where nothing is wrong.
- Fixtures are invented and small. The company's private spec is never used, not even as a source of fixtures. The public corpus is for runs only (outputs in the scratchpad).
- Lints: the root `analysis_options.yaml` (the stricter set of `146cddb`); `dart analyze packages` from the root prints `No issues found!`; no `// ignore:`.
- Size limits (CLAUDE.md, "Code quality rules"): a `lib/` file has at most 300 lines, a test file 500, a method 40; the ratchet tests `packages/*/test/quality/size_limits_test.dart` pass after every task. New code goes into new collaborator files; an allowlisted unit that must grow gets its entry raised in the same task, with a one-line `// M9:` comment directly above the entry (table "Size ratchet changes").
- `dart format lib test bin` (runtime: `lib test`) changes 0 files on a second run.
- Tests never touch the network (`dart pub get --offline` in subprocesses); temp files only through `test/helpers/temp_dir.dart`.
- `dart test` and `dart format` run from the package directory; `dart pub get`, `dart analyze packages`, `git apply` and `git` from the root. New files are created from their blocks in full; diffs are applied with `git apply` from the root.
- Every commit is a Conventional Commit and ends with the `Co-Authored-By` line of the model that does the task (the examples use `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`).
- Documents are in English; `README.ua.md` is the intentional Ukrainian translation of `README.md` and is kept in step with it.

## Decisions taken

The spec's decisions are binding. These are the technical choices the spec leaves to the plan; choices users see are under "Open questions", each with the default this plan implements.

1. **dio names (spec decision 12): `show Dio` only.** The API files and the root import only `Dio` from `package:dio`, so `Response`, `Options` and `Headers` stay free for schemas; `Dio` and the new runtime names (`FileUpload`, `FormBody`, `FormEncoding`, `MultipartBody`, `MultipartPart`, `SecurityScheme`, `SecuritySchemeType`, `SecurityLocation`, `SecurityUse`) join `DartNames.takenTypeNames`, so a schema with such a name gets `Model` (TOA550).
2. **One path-variable pattern:** `\{([^{}]*)\}`, as `OperationBuilder.pathVariable` and `OperationRequest.pathVariable`; a generator test compares them (the runtime is a dev dependency of the generator). `/c/{}` is a variable with an empty name: TOA556 in the IR, `ArgumentError` in the runtime.
3. **Codes (spec decision 14):** media types and errors move to 6xx, generator codes in the second half of the hundred: TOA561 became TOA650 `media-type-as-bytes` and TOA651 `media-types-dropped`, TOA562 became TOA652 `default-error-schema-missing`; the `querystring` half of TOA564 became TOA565. The codes are not published yet (catalog: M13).
4. **Names after the models (spec decisions 4, 18 of M8):** `ApiNames` claims, in the library scope after declarations, groups and the M8 helper types, the root client, then per operation (groups and operations by name) the sealed success type and its variants, the sealed error type and its variants, the parts class. Group files are `api/<snake of the class>.dart` in their own name scope, so model files never move.
5. **Status variants by reason phrase:** registered codes get their RFC 9110 phrase in the classic spelling the spec's examples use (`UnprocessableEntity`, `PayloadTooLarge`); ranges are `Informational`, `Success`, `Redirection`, `ClientError`, `ServerError`; `default` is `Other`; any other code is `Status499`.
6. **The decoder:** a static method per operation, a `switch` on the status: codes first, then ranges, then `default`, which takes every status but 2xx (an undocumented 2xx is not an error); `_ => r.undocumented()`. `SingleError` with no statuses takes every 4xx and 5xx.
7. **How Dio reads the body:** JSON unless every success with a body is text (`ResponseKind.text`) or any success is something else (`bytes`); then error bodies, and JSON successes of a mixed operation, are decoded from `RawResponse.parsedJson`, which parses text or bytes when the content type is JSON, with the depth check (closes the M7 row).
8. **Bodies in the runtime:** `FileUpload` (the user's decision, spec 8), `FormBody` with a `FormEncoding` per property (form style, explode, allowReserved, JSON), `MultipartBody` of `MultipartPart.value`/`.file`. `DioBody` (`dio/dio_body.dart`) builds Dio's data per request: form text, a fresh `FormData`, bytes or a stream with `Content-Length`; a file's own media type wins over the spec's.
9. **Multipart parts:** a multipart schema that is an object with properties gives a parts class (`<Operation>Request`) whose binary strings (and lists of them) are `FileUpload`s and whose `toParts()` lists the parts with the `encoding` media types; any other schema keeps its type and is sent with `MultipartBody.fromJson` (TOA655).
10. **No 2xx documented (spec decision 6):** TOA653, and any 2xx is a success with the body as `JsonValue` (nothing is lost; `void` would drop the body).
11. **Event streams:** an operation whose success is `text/event-stream` is not generated until M10 (TOA654), so no method reads an endless body to the end.
12. **What the client does not generate is reported:** servers of a path item or an operation (TOA566), `callbacks` and the document's `webhooks` (TOA567); a security requirement naming an unknown scheme (TOA568); part headers of a multipart `encoding` (TOA656).
13. **Size limits:** the M9 logic lives in new files within the limits; the allowlisted M6/M8 files that must take new fields or calls (`ir.dart`, `ir_builder.dart`, `operation_builder.dart`, `config_loader.dart`) grow with a raised entry and an `// M9:` reason; no M8 file is split here (the code-quality session owns that).

## New diagnostic codes

| Code | Slug | Level | When | Task |
|---|---|---|---|---|
| TOA565 | `querystring-not-generated` | warning | An `in: querystring` parameter (OpenAPI 3.2) is not generated (was TOA564) | 2 |
| TOA566 | `operation-servers-ignored` | warning | A path item or an operation has its own `servers`; requests go to the Dio base URL | 3 |
| TOA567 | `callbacks-not-generated` | info | An operation has `callbacks`, or the document has `webhooks` | 3 |
| TOA568 | `security-scheme-unknown` | warning | A security requirement names a scheme `components.securitySchemes` does not have | 3 |
| TOA650 | `media-type-as-bytes` | info | A body is bytes and its schema is not used, also a form or multipart response (was TOA561) | 2 |
| TOA651 | `media-types-dropped` | info | The media types of a body, response or parameter that are dropped (was TOA561) | 2 |
| TOA652 | `default-error-schema-missing` | warning | `errors.default_schema` is not a key of `components.schemas` (was TOA562) | 2 |
| TOA653 | `success-undocumented` | warning | No 2xx response: any 2xx is a success with the body as `JsonValue` | 3 |
| TOA654 | `event-stream-not-generated` | warning | A success is `text/event-stream`; the operation is generated from M10 | 3 |
| TOA655 | `multipart-not-object` | warning | A multipart body is not an object with properties: no parts class | 3 |
| TOA656 | `encoding-headers-ignored` | info | The `headers` of a multipart part's `encoding` are not sent | 2 |

Mapping of the renumbered codes: TOA561 -> TOA650 (bytes) and TOA651 (dropped alternatives); TOA562 -> TOA652; TOA564 (querystring) -> TOA565, TOA564 keeps the invalid style. TOA112 now also reports an `apiKey` scheme without `in` (task 2).

## New config keys

```yaml
# typed_openapi.yaml, in defaults or a client
naming:
  client: PetstoreClient   # the root client class; default: the client's name in UpperCamelCase + Client
```

An invalid value (not an identifier, a reserved word, or not starting with an uppercase letter or `$`) is TOA902 and the default is used. When `naming.client` is not set, `SpecChecker` keys a run by the client's name too, because the root class is named after it.

## Generated layout

```text
<output>/
  .typed_openapi.json      manifest (M8)
  models.dart, models/     M8
  api.dart                 exports api/*
  api/<group>.dart         a class per group, its status types and parts classes
  <client>.dart            the root client; exports api.dart and models.dart
                           (<client>_client.dart when the name is api or models)
```

## Files

Paths are relative to `packages/typed_openapi/` (runtime: `packages/typed_openapi_runtime/`).

| File | Responsibility | Task |
|---|---|---|
| runtime `lib/src/request/file_upload.dart`, `form_body.dart`, `multipart_body.dart`, `security.dart` | request bodies and security metadata | 1, 4 |
| runtime `lib/src/dio/dio_body.dart` | what Dio sends for a body, its headers and content type | 1 |
| runtime `lib/src/request/operation_info.dart`, `operation_request.dart`, `raw_response.dart`, `lib/src/dio/dio_request_sender.dart` | `security`, `pathVariable`, `parsedJson`, the use of `DioBody` | 1 |
| `lib/src/diagnostics/diagnostic_code.dart` | TOA565-TOA568, TOA650-TOA656 | 2, 3 |
| `lib/src/ir/api_ir.dart` | IR types only the API emitter reads (exported by `ir.dart`) | 2, 3 |
| `lib/src/ir/body_encoding.dart`, `security_builder.dart`, `parts_builder.dart`, `operation_checks.dart` | collaborators of `OperationBuilder` | 2, 3 |
| `lib/src/ir/api_names.dart` | names after the models, the root client and its members | 3 |
| `lib/src/ir/ir.dart`, `ir_builder.dart`, `operation_builder.dart`, `names.dart` | new IR fields and wiring | 2, 3, 6 |
| `lib/src/config/config_loader.dart`, `generation_config.dart`, `lib/src/check/spec_checker.dart` | `naming.client`, the run key | 3 |
| `lib/src/emit/api_library.dart`, `operation_emitter.dart`, `request_writer.dart`, `decoder_writer.dart`, `status_type_emitter.dart`, `parts_emitter.dart` | the API emitter | 4, 7 |
| `lib/src/cli/generate_command.dart` | `generate` writes the whole client | 6 |
| `test/emit/fixtures/petstore.yaml`, `hostile_operations.yaml`, `test/emit/goldens/petstore/` | fixtures and goldens | 4, 7 |
| `test/emit/generated_client_test.dart`, `test/emit/programs/calls.dart.txt` | analyzer gate and real calls | 5 |

## Size ratchet changes

`test/quality/size_limits_test.dart` of the generator (the runtime's needs no change: `dio_request_sender.dart` stays at 378 lines because `DioBody` takes the new code). Every raised entry has an `// M9:` comment with the reason directly above it.

| Entry | Before | After | Task | Reason |
|---|---|---|---|---|
| `lib/src/ir/ir.dart` | 733 | 747 (task 2), 814 (task 3) | 2, 3 | the operation IR classes take the fields the API emitter reads (`defaultValue`, `encoding`, `parts`, `security`, status types, `withTypes`, `root`, `field`); the new types themselves are in `api_ir.dart` |
| `lib/src/ir/operation_builder.dart` | 565 | 604 (task 2), 648 (task 3) | 2, 3 | the path-variable pattern, parameter defaults, the form-response check, the collaborators and the event-stream skip; their logic is in `BodyEncoding`, `SecurityBuilder`, `PartsBuilder`, `OperationChecks` |
| `lib/src/ir/operation_builder.dart#OperationBuilder._parameter` | 99 | 100 | 2 | the parameter keeps its schema's default (one argument line) |
| `lib/src/ir/ir_builder.dart` | 534 | 540 | 3 | event streams among the reasons of an empty client, the webhooks check; the group loop is shorter, the rest is in `ApiNames.client` |
| `lib/src/ir/ir_builder.dart#IrBuilder._reportEmpty` | 50 | 55 | 3 | event streams are a reason a client is empty |
| `lib/src/config/config_loader.dart` | 780 | 798 | 3 | `naming.client` is read with the other naming keys of `_GenerationReader` |

New files over a limit: none. Methods that would have gone over 40 lines were split (`OperationBuilder._bodyType`, `PartsEmitter._parameter`, `OperationEmitter._send`/`_types`/`_privateNames`, `ApiLibrary._constructor`/`_pieces`, `RequestWriter._value`); `IrBuilder.build` got shorter (95 -> 93).

## Interfaces between tasks

```dart
// runtime (task 1, 4)
final class FileUpload { FileUpload.bytes(Uint8List bytes, {String? filename, String? contentType});
  const FileUpload.stream(Stream<List<int>> stream, {required int length, String? filename, String? contentType}); }
final class FormEncoding { const FormEncoding({QueryStyle style = .form, bool? explode, bool allowReserved = false, bool json = false}); }
final class FormBody { const FormBody(Object? json, [Map<String, FormEncoding> encoding = const {}]); String encode(); }
final class MultipartPart { const MultipartPart.value(String name, Object? value, {String? contentType});
  const MultipartPart.file(String name, FileUpload file, {String? contentType}); }   // contentType of .file: task 4
final class MultipartBody { const MultipartBody(List<MultipartPart> parts); factory MultipartBody.fromJson(Object? json); } // fromJson: task 4
enum SecuritySchemeType { apiKey, http, mutualTls, oauth2, openIdConnect }
enum SecurityLocation { query, header, cookie }
final class SecurityScheme { const SecurityScheme(String name, SecuritySchemeType type, {String? parameterName, SecurityLocation? location, String? scheme, String? bearerFormat, String? openIdConnectUrl}); }
final class SecurityUse { const SecurityUse(SecurityScheme scheme, [List<String> scopes = const []]); }
OperationInfo({..., List<List<SecurityUse>> security = const []});
static final RegExp OperationRequest.pathVariable;   // \{([^{}]*)\}
Object? RawResponse.parsedJson; String RawResponse.text (also from bytes)
final class DioBody { const DioBody(); Object? data(Object? body); Map<String, String> headers(Object? body); String? contentType(OperationRequest request); }

// ir (tasks 2, 3)
static final RegExp OperationBuilder.pathVariable; static const OperationBuilder.allowedStyles;
ParameterIr({..., (Object?,)? defaultValue}); RequestBodyIr({..., List<EncodingIr> encoding = const [], List<PartIr>? parts});
final class EncodingIr { const EncodingIr(String property, {String? contentType, ParameterStyle? style, bool? explode, bool allowReserved = false}); }
final class PartIr { const PartIr({required String name, required String wireName, required DartType type, required SpecLocation location, bool required = false, String? contentType, String? description}); }
final class StatusTypeIr { const StatusTypeIr(String name, List<StatusCaseIr> cases); }
final class StatusCaseIr { const StatusCaseIr(String status, String name, DartType? type); }
final class RootIr { const RootIr(String name, {List<ServerIr> servers = const []}); }
final class ServerIr { const ServerIr({required String name, required String url, required SpecLocation location, String? description, List<ServerVariableIr> variables = const []}); }
final class ServerVariableIr { const ServerVariableIr({required String name, required String wireName, String? defaultValue, List<String> values = const [], String? description}); }
enum SecurityKind { apiKey, http, mutualTls, oauth2, openIdConnect }
final class SecuritySchemeIr { const SecuritySchemeIr(String name, SecurityKind kind, {String? parameterName, String? placement, String? scheme, String? bearerFormat, String? openIdConnectUrl}); }
final class SecurityUseIr { const SecurityUseIr(SecuritySchemeIr scheme, List<String> scopes); }
OperationIr({..., List<List<SecurityUseIr>> security = const [], StatusTypeIr? successType, StatusTypeIr? errorType, String? partsName});
OperationIr withTypes({StatusTypeIr? successType, StatusTypeIr? errorType, String? partsName}); String get OperationIr.overrideKey;
GroupIr(String name, List<OperationIr> operations, {String field = 'api'}); ClientIr({..., RootIr root = const RootIr('ApiClient')});
final class ApiNames { ApiNames(IrContext, NameScope types); static String variantOf(String status);
  ClientIr client(List<Declaration> declarations, Map<String, GroupIr> groups); String root(); OperationIr name(OperationIr); List<ServerIr> servers(NameScope members); }
GenerationConfig({..., String? clientClass});   // naming.client

// emit (task 4)
final class ApiLibrary { const ApiLibrary({int width = 80}); Map<String, String> files(ClientIr ir, {required String client});
  Map<String, String> fileNames(ClientIr ir); static String rootFile(String client); }
final class OperationEmitter { OperationEmitter(TypeCodec codec); void write(GroupIr group, DartWriter out); }
ModelLibrary.snake(String name); ModelLibrary.writeHeader(DartWriter out);   // made public for ApiLibrary
Map<String, String> emitClient(String fixture, {GenerationConfig generation});   // test/helpers/emit_fixture.dart
```

Every task was verified: built and checked on a scratch branch, then tasks 1-8 were replayed from `main` (`29ae2d3`) using only this plan's blocks (new files created whole, diffs applied with `git apply`, goldens written by the step that says so), and after each task `dart analyze packages` is clean, a second `dart format` changes 0 files, the size ratchet passes and `dart test` in both packages is green with the counts given in the task; the final tree equals the verified one. Before M9: 924 generator tests and 169 runtime tests.

---

### Task 1: Runtime: file uploads, form and multipart bodies, security metadata, JSON errors of text and binary operations

**Files:**
- Modify: `CLAUDE.md`
- Modify: `packages/typed_openapi_runtime/CHANGELOG.md`
- Create: `packages/typed_openapi_runtime/lib/src/dio/dio_body.dart`
- Modify: `packages/typed_openapi_runtime/lib/src/dio/dio_request_sender.dart`
- Create: `packages/typed_openapi_runtime/lib/src/request/file_upload.dart`
- Create: `packages/typed_openapi_runtime/lib/src/request/form_body.dart`
- Create: `packages/typed_openapi_runtime/lib/src/request/multipart_body.dart`
- Modify: `packages/typed_openapi_runtime/lib/src/request/operation_info.dart`
- Modify: `packages/typed_openapi_runtime/lib/src/request/operation_request.dart`
- Modify: `packages/typed_openapi_runtime/lib/src/request/raw_response.dart`
- Create: `packages/typed_openapi_runtime/lib/src/request/security.dart`
- Modify: `packages/typed_openapi_runtime/lib/typed_openapi_runtime.dart`
- Create: `packages/typed_openapi_runtime/test/dio/bodies_send_test.dart`
- Create: `packages/typed_openapi_runtime/test/request/bodies_test.dart`

**Interfaces:**
- Consumes: `OperationInfo`, `OperationRequest`, `RawResponse`, `QueryParameter`, `DioRequestSender`, `JsonReader.checkDepth` (M7).
- Produces: `FileUpload`, `FormBody`, `FormEncoding`, `MultipartBody`, `MultipartPart`, `SecurityScheme`, `SecuritySchemeType`, `SecurityLocation`, `SecurityUse` (barrel); `OperationInfo.security`; `OperationRequest.pathVariable`; `RawResponse.parsedJson`; `DioBody` (internal: `data`, `headers`, `contentType`).

Generated methods must take files and forms without Dio types in their signatures (spec decisions 7-8, user decision on `FileUpload`), carry security metadata for interceptors (R10.8, spec decision 10) and decode a JSON error of an operation whose success is text or bytes (spec decision 5, the M7 row). The runtime gets the body types; `DioBody` builds what Dio sends for each request (a `FormData` can be sent once, so it is built per request), sets `Content-Length` for a stream and lets a file's own media type win. `RawResponse.parse` gets the depth check it lacked, and `text` reads a body Dio read as bytes. The path-variable pattern becomes public (`pathVariable`, `[^{}]*`), the one definition the generator copies in task 2. The new code goes into new files, so `dio_request_sender.dart` (allowlisted at 378 lines) does not grow: its `_request` passes the body through `DioBody` and inlines `_guardQuery(...)`, and one doc paragraph is tightened.

- [ ] **Step 1: Write the failing tests**

**New file** `packages/typed_openapi_runtime/test/dio/bodies_send_test.dart`:

````dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:typed_openapi_runtime/typed_openapi_runtime.dart';

import '../helpers/fake_adapter.dart';

void main() {
  const upload = OperationInfo(
    operationId: 'upload',
    method: 'POST',
    pathTemplate: '/files',
  );

  Result<void, Never> decodeVoid(RawResponse r) =>
      r.statusCode == 204 ? r.success(null) : r.undocumented();

  (DioRequestSender, FakeAdapter) senderFor(FakeAdapter adapter) => (
    DioRequestSender(Dio()..httpClientAdapter = adapter),
    adapter,
  );

  FakeAdapter noContent() =>
      FakeAdapter((_) => ResponseBody.fromString('', 204));

  test('a form body is sent as text with its content type', () async {
    final (sender, adapter) = senderFor(noContent());
    final result = await sender.send(
      const OperationRequest(
        upload,
        body: FormBody({'name': 'a b', 'n': 1}),
        contentType: 'application/x-www-form-urlencoded',
      ),
      decodeVoid,
    );
    expect(result, isA<Success<void, Never>>());
    expect(adapter.bodies.single, 'name=a%20b&n=1');
    expect(
      adapter.requests.single.contentType,
      'application/x-www-form-urlencoded',
    );
  });

  test('a multipart body has text, JSON and file parts', () async {
    final (sender, adapter) = senderFor(noContent());
    await sender.send(
      OperationRequest(
        upload,
        body: MultipartBody([
          const MultipartPart.value('note', 'hi'),
          const MultipartPart.value('count', 2),
          const MultipartPart.value('meta', {'k': 'v'}),
          const MultipartPart.value('ids', [1, 2]),
          const MultipartPart.value('gone', null),
          const MultipartPart.value('raw', 'x', contentType: 'text/csv'),
          const MultipartPart.value(
            'quoted',
            'y',
            contentType: 'application/json',
          ),
          MultipartPart.file(
            'file',
            FileUpload.bytes(
              Uint8List.fromList(utf8.encode('abc')),
              filename: 'a.txt',
              contentType: 'text/plain',
            ),
          ),
          MultipartPart.file(
            'stream',
            FileUpload.stream(Stream.value(utf8.encode('de')), length: 2),
          ),
        ]),
        contentType: 'multipart/form-data',
      ),
      decodeVoid,
    );
    final type = adapter.requests.single.headers['content-type'] as String;
    expect(type, startsWith('multipart/form-data; boundary='));
    final body = adapter.bodies.single;
    expect(body, contains('name="note"\r\n\r\nhi\r\n'));
    expect(body, contains('name="count"\r\n\r\n2\r\n'));
    expect(
      body,
      contains(
        'name="meta"\r\ncontent-type: application/json; charset=utf-8\r\n'
        '\r\n{"k":"v"}\r\n',
      ),
    );
    expect('name="ids"'.allMatches(body), hasLength(2));
    expect(body, isNot(contains('gone')));
    expect(body, contains('name="raw"\r\ncontent-type: text/csv'));
    expect(body, contains('charset=utf-8\r\n\r\n"y"\r\n'));
    expect(
      body,
      contains(
        'name="file"; filename="a.txt"\r\ncontent-type: text/plain\r\n\r\n'
        'abc\r\n',
      ),
    );
    expect(
      body,
      contains(
        'name="stream"\r\ncontent-type: application/octet-stream\r\n\r\n'
        'de\r\n',
      ),
    );
  });

  test('a file body sends its bytes or stream and its own type', () async {
    final (sender, adapter) = senderFor(noContent());
    await sender.send(
      OperationRequest(
        upload,
        body: FileUpload.bytes(Uint8List.fromList(utf8.encode('png'))),
        contentType: 'application/octet-stream',
      ),
      decodeVoid,
    );
    await sender.send(
      OperationRequest(
        upload,
        body: FileUpload.stream(
          Stream.fromIterable([utf8.encode('a'), utf8.encode('bc')]),
          length: 3,
          contentType: 'image/png',
        ),
        contentType: 'application/octet-stream',
      ),
      decodeVoid,
    );
    expect(adapter.bodies, ['png', 'abc']);
    expect(adapter.requests.first.contentType, 'application/octet-stream');
    expect(adapter.requests.last.contentType, 'image/png');
    expect(adapter.requests.last.headers['content-length'], '3');
  });

  test('a binary operation decodes a JSON error body', () async {
    final sender = DioRequestSender(
      Dio()..httpClientAdapter = FakeAdapter.json(404, {'code': 'gone'}),
    );
    Result<Uint8List, Object?> decode(RawResponse r) => switch (r.statusCode) {
      200 => r.success(r.bytes),
      404 => r.error(JsonReader.asObject(r.parsedJson)['code']),
      _ => r.undocumented(),
    };
    final result = await sender.send(
      const OperationRequest(
        OperationInfo(
          operationId: 'download',
          method: 'GET',
          pathTemplate: '/files/a',
        ),
        responseKind: .bytes,
      ),
      decode,
    );
    expect(result, isA<HttpError<Uint8List, Object?>>());
    expect((result as HttpError<Uint8List, Object?>).body, 'gone');
  });
}
````

**New file** `packages/typed_openapi_runtime/test/request/bodies_test.dart`:

````dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:typed_openapi_runtime/typed_openapi_runtime.dart';

void main() {
  group('FormBody', () {
    test('writes each property like a form query parameter', () {
      const body = FormBody({
        'name': 'Rex Jr',
        'tags': ['a', 'b'],
        'gone': null,
        'age': 3,
      });
      expect(body.encode(), 'name=Rex%20Jr&tags=a&tags=b&age=3');
    });

    test('follows the encoding of each property', () {
      const body = FormBody(
        {
          'tags': ['a', 'b'],
          'meta': {'k': 'v', 'n': 1},
          'next': '/a/b?c',
          'filter': {'x': 1},
        },
        {
          'tags': FormEncoding(explode: false),
          'meta': FormEncoding(style: .deepObject),
          'next': FormEncoding(allowReserved: true),
          'filter': FormEncoding(json: true),
        },
      );
      expect(
        body.encode(),
        'tags=a,b&meta%5Bk%5D=v&meta%5Bn%5D=1&next=/a/b?c&'
        'filter=%7B%22x%22%3A1%7D',
      );
    });

    test('an empty or null object is an empty body', () {
      expect(const FormBody(null).encode(), '');
      expect(const FormBody(<String, Object?>{}).encode(), '');
    });

    test('a body that is not an object, or nested too deep, throws', () {
      expect(() => const FormBody([1]).encode(), throwsArgumentError);
      expect(
        () => const FormBody({
          'a': {
            'b': {'c': 1},
          },
        }).encode(),
        throwsArgumentError,
      );
    });
  });

  group('FileUpload', () {
    test('holds bytes or a stream with its length', () {
      final bytes = FileUpload.bytes(
        Uint8List.fromList([1, 2, 3]),
        filename: 'a.png',
        contentType: 'image/png',
      );
      expect(bytes.length, 3);
      expect(bytes.stream, isNull);
      expect('$bytes', 'FileUpload(a.png, 3 bytes, image/png)');
      final stream = FileUpload.stream(Stream.value([1]), length: 1);
      expect(stream.bytes, isNull);
      expect('$stream', 'FileUpload(unnamed, 1 bytes)');
    });
  });

  group('security metadata', () {
    test('an operation lists alternatives of required schemes', () {
      const bearer = SecurityScheme('bearer', .http, scheme: 'bearer');
      const key = SecurityScheme(
        'key',
        .apiKey,
        parameterName: 'X-Key',
        location: .header,
      );
      const info = OperationInfo(
        operationId: 'getPet',
        method: 'GET',
        pathTemplate: '/pets',
        security: [
          [
            SecurityUse(bearer, ['read']),
          ],
          [SecurityUse(key)],
          [],
        ],
      );
      expect(info.security, hasLength(3));
      expect('${info.security.first.single}', 'bearer read');
      expect('${info.security[1].single}', 'key');
      expect('$key', 'SecurityScheme(key, apiKey)');
      expect(
        const OperationInfo(
          operationId: 'x',
          method: 'GET',
          pathTemplate: '/',
        ).security,
        isEmpty,
      );
    });
  });

  group('RawResponse', () {
    const jsonHeaders = {
      'content-type': ['application/json'],
    };

    test('parses JSON a text or binary operation read as text or bytes', () {
      final bytes = RawResponse(
        statusCode: 404,
        body: Uint8List.fromList(utf8.encode('{"code":"gone"}')),
        headers: jsonHeaders,
      );
      expect(bytes.parsedJson, {'code': 'gone'});
      const text = RawResponse(
        statusCode: 404,
        body: '{"code":"gone"}',
        headers: jsonHeaders,
      );
      expect(text.parsedJson, {'code': 'gone'});
      const plain = RawResponse(statusCode: 404, body: 'gone');
      expect(plain.parsedJson, 'gone');
      const parsed = RawResponse(statusCode: 200, body: {'a': 1});
      expect(parsed.parsedJson, {'a': 1});
    });

    test('rejects JSON nested too deep when it parses it', () {
      final deep = '${'[' * 1001}${']' * 1001}';
      expect(
        () => RawResponse(
          statusCode: 404,
          body: Uint8List.fromList(utf8.encode(deep)),
          headers: jsonHeaders,
        ).parsedJson,
        throwsA(isA<JsonDecodeException>()),
      );
      expect(
        () => RawResponse.parse(
          Uint8List.fromList(utf8.encode(deep)),
          jsonHeaders,
        ),
        throwsA(isA<JsonDecodeException>()),
      );
    });

    test('reads the text of a body the client read as bytes', () {
      final response = RawResponse(
        statusCode: 200,
        body: Uint8List.fromList(utf8.encode('héllo')),
      );
      expect(response.text, 'héllo');
      expect(
        () => RawResponse(
          statusCode: 200,
          body: Uint8List.fromList([0xff]),
        ).text,
        throwsFormatException,
      );
    });
  });

  test('a path variable is any text between braces without a brace', () {
    String variables(String path) => [
      for (final m in OperationRequest.pathVariable.allMatches(path)) m[1],
    ].join('|');
    expect(variables('/a/{id}/{b-c}'), 'id|b-c');
    expect(variables('/c/{}'), '');
    expect(OperationRequest.pathVariable.allMatches('/c/{}'), hasLength(1));
    expect(variables('/x/{a{b}'), 'b');
    const request = OperationRequest(
      OperationInfo(operationId: 'x', method: 'GET', pathTemplate: '/c/{}'),
    );
    expect(request.resolvePath, throwsArgumentError);
  });
}
````

- [ ] **Step 2: Run the tests to see them fail**

Run from `packages/typed_openapi_runtime`: `dart test test/request/bodies_test.dart test/dio/bodies_send_test.dart`.
Expected: FAIL to load: `FormBody`, `FileUpload`, `SecurityScheme`, `OperationRequest.pathVariable` are not defined.

- [ ] **Step 3: Implement**

**New file** `packages/typed_openapi_runtime/lib/src/dio/dio_body.dart`:

````dart
import 'dart:convert';

import 'package:dio/dio.dart';

import '../request/file_upload.dart';
import '../request/form_body.dart';
import '../request/multipart_body.dart';
import '../request/operation_request.dart';

/// Turns the body of an `OperationRequest` into what Dio sends: form text,
/// `FormData` built for this request, the bytes or the stream of a file, or
/// the body as it is (JSON, text).
final class DioBody {
  /// Creates the converter.
  const DioBody();

  /// The headers [body] needs: Dio sends a stream as it is and needs its
  /// length.
  Map<String, String> headers(Object? body) => switch (body) {
    FileUpload(stream: _?, :final length) => {
      Headers.contentLengthHeader: '$length',
    },
    _ => const {},
  };

  /// The `Content-Type` of [request]: a file's own media type wins over the
  /// spec's, and Dio sets the one of form data with its boundary.
  String? contentType(OperationRequest request) => switch (request.body) {
    FileUpload(contentType: final type?) => type,
    MultipartBody() => null,
    _ => request.contentType,
  };

  /// What Dio sends for [body].
  Object? data(Object? body) => switch (body) {
    final FormBody form => form.encode(),
    final MultipartBody multipart => _formData(multipart),
    FileUpload(:final bytes?) => bytes,
    FileUpload(:final stream?) => stream,
    _ => body,
  };

  FormData _formData(MultipartBody body) {
    final data = FormData();
    for (final part in body.parts) {
      switch (part.file) {
        case final file?:
          data.files.add(MapEntry(part.name, _file(file, part.contentType)));
        case null:
          _addValue(data, part.name, part.value, part.contentType);
      }
    }
    return data;
  }

  /// A file part: the file's own media type wins over the spec's.
  static MultipartFile _file(FileUpload file, String? specType) {
    final type = file.contentType ?? specType;
    final contentType = type == null ? null : DioMediaType.parse(type);
    return switch (file) {
      FileUpload(:final bytes?) => MultipartFile.fromBytes(
        bytes,
        filename: file.filename,
        contentType: contentType,
      ),
      _ => MultipartFile.fromStream(
        () => file.stream!,
        file.length,
        filename: file.filename,
        contentType: contentType,
      ),
    };
  }

  /// Adds the value parts of [value]: none for `null`, a part per item of a
  /// list, JSON for an object or a JSON [contentType], text otherwise.
  static void _addValue(
    FormData data,
    String name,
    Object? value,
    String? contentType,
  ) {
    switch (value) {
      case null:
        return;
      case final List<Object?> items:
        for (final item in items) {
          _addValue(data, name, item, contentType);
        }
      case _ when contentType != null && _isJson(contentType):
        data.files.add(MapEntry(name, _text(jsonEncode(value), contentType)));
      case Map<Object?, Object?>():
        data.files.add(
          MapEntry(name, _text(jsonEncode(value), 'application/json')),
        );
      case _ when contentType != null:
        data.files.add(MapEntry(name, _text(_scalar(value), contentType)));
      default:
        data.fields.add(MapEntry(name, _scalar(value)));
    }
  }

  static MultipartFile _text(String text, String contentType) =>
      MultipartFile.fromString(
        text,
        contentType: DioMediaType.parse(contentType),
      );

  static bool _isJson(String contentType) {
    final type = contentType.split(';').first.trim().toLowerCase();
    return type == 'application/json' || type.endsWith('+json');
  }

  /// The text of a scalar JSON value of a part.
  static String _scalar(Object? value) => switch (value) {
    final String text => text,
    _ => '$value',
  };
}
````

**New file** `packages/typed_openapi_runtime/lib/src/request/file_upload.dart`:

````dart
import 'dart:typed_data';

/// A file a generated method sends: a binary request body, or a file part
/// of a `multipart/form-data` body.
///
/// Generated methods take a [FileUpload] instead of a type of the HTTP
/// client, so their signatures do not depend on Dio. [FileUpload.bytes]
/// works on every platform, the web included; [FileUpload.stream] sends the
/// data as it is read and can be sent once.
final class FileUpload {
  /// A file held in memory.
  FileUpload.bytes(Uint8List this.bytes, {this.filename, this.contentType})
    : stream = null,
      length = bytes.length;

  /// A file read from [stream], which has [length] bytes. A stream can be
  /// listened to once, so the upload can be sent once.
  const FileUpload.stream(
    Stream<List<int>> this.stream, {
    required this.length,
    this.filename,
    this.contentType,
  }) : bytes = null;

  /// The content of a file held in memory.
  final Uint8List? bytes;

  /// The content of a streamed file.
  final Stream<List<int>>? stream;

  /// The size in bytes.
  final int length;

  /// The file name sent with a multipart part.
  final String? filename;

  /// The media type, such as `image/png`; it wins over the media type of the
  /// spec. A value that is not a media type makes sending throw
  /// [FormatException].
  final String? contentType;

  @override
  String toString() =>
      'FileUpload(${filename ?? 'unnamed'}, $length bytes'
      '${contentType == null ? '' : ', $contentType'})';
}
````

**New file** `packages/typed_openapi_runtime/lib/src/request/form_body.dart`:

````dart
import 'dart:convert';

import '../params/parameters.dart';

/// How one property of an `application/x-www-form-urlencoded` body is
/// written: the `encoding` of the spec's media type for that property.
final class FormEncoding {
  /// Creates the encoding; OAS defaults are `form` with explode.
  const FormEncoding({
    this.style = .form,
    this.explode,
    this.allowReserved = false,
    this.json = false,
  });

  /// The serialization style, as for a query parameter.
  final QueryStyle style;

  /// Whether lists and objects are exploded; null for the default of the
  /// style.
  final bool? explode;

  /// Whether reserved characters are sent without percent-encoding.
  final bool allowReserved;

  /// Whether the value is sent as JSON text (`contentType:
  /// application/json` in the encoding).
  final bool json;
}

/// An `application/x-www-form-urlencoded` body: the properties of a JSON
/// object, each written like a query parameter (OAS 3 `encoding`).
///
/// A property without an [encoding] entry uses the `form` style with
/// explode; `null` values are not sent. Values nested deeper than the style
/// allows (an object inside an object for `form`) make [encode] throw
/// [ArgumentError], as query parameters do.
final class FormBody {
  /// Creates the body of [json], which must be a JSON object or `null`.
  const FormBody(this.json, [this.encoding = const {}]);

  /// The body as JSON (`toJson()` of the model).
  final Object? json;

  /// The encoding of properties by name.
  final Map<String, FormEncoding> encoding;

  /// The body text: `name=value` pairs joined by `&`.
  ///
  /// Throws [ArgumentError] when [json] is not an object.
  String encode() {
    final object = switch (json) {
      null => const <String, Object?>{},
      final Map<String, Object?> object => object,
      final other => throw ArgumentError.value(
        other,
        'json',
        'A form body must be a JSON object',
      ),
    };
    return [
      for (final MapEntry(:key, :value) in object.entries)
        _field(key, value, encoding[key] ?? const FormEncoding()),
    ].where((pair) => pair.isNotEmpty).join('&');
  }

  static String _field(String name, Object? value, FormEncoding encoding) =>
      QueryParameter(
        name,
        encoding.json && value != null ? jsonEncode(value) : value,
        style: encoding.style,
        explode: encoding.explode,
        allowReserved: encoding.allowReserved,
      ).encode();
}
````

**New file** `packages/typed_openapi_runtime/lib/src/request/multipart_body.dart`:

````dart
import 'file_upload.dart';

/// A part of a `multipart/form-data` body.
final class MultipartPart {
  /// A value part: [value] is the JSON form of a property (`toJson`
  /// applied). A string, number or boolean is sent as text; an object as
  /// JSON; each item of a list as a part of its own with this [name]; `null`
  /// is not sent. [contentType] is the `encoding` of the spec for the
  /// property: a JSON media type sends any value as JSON, another one is the
  /// media type of the text.
  const MultipartPart.value(this.name, this.value, {this.contentType})
    : file = null;

  /// A file part.
  const MultipartPart.file(this.name, FileUpload this.file)
    : value = null,
      contentType = null;

  /// The name of the part (the property name).
  final String name;

  /// The JSON form of a value part.
  final Object? value;

  /// The file of a file part.
  final FileUpload? file;

  /// The media type of a value part, from the spec's `encoding`.
  final String? contentType;
}

/// A `multipart/form-data` body: its parts in order. The request sender
/// builds the HTTP client's form data from it for each request.
final class MultipartBody {
  /// Creates the body.
  const MultipartBody(this.parts);

  /// The parts, in order.
  final List<MultipartPart> parts;
}
````

**New file** `packages/typed_openapi_runtime/lib/src/request/security.dart`:

````dart
/// The `type` of a security scheme.
enum SecuritySchemeType {
  /// An API key in a header, query parameter or cookie.
  apiKey,

  /// HTTP authentication, such as `bearer` or `basic`.
  http,

  /// Mutual TLS.
  mutualTls,

  /// OAuth 2.
  oauth2,

  /// OpenID Connect.
  openIdConnect,
}

/// Where an API key is sent.
enum SecurityLocation {
  /// A query parameter.
  query,

  /// A header.
  header,

  /// A cookie.
  cookie,
}

/// A security scheme of the spec (`components.securitySchemes`), as
/// metadata for interceptors: the generated client sends no credentials.
final class SecurityScheme {
  /// Describes the scheme [name] of [type].
  const SecurityScheme(
    this.name,
    this.type, {
    this.parameterName,
    this.location,
    this.scheme,
    this.bearerFormat,
    this.openIdConnectUrl,
  });

  /// The key of the scheme in `components.securitySchemes`.
  final String name;

  /// The type of the scheme.
  final SecuritySchemeType type;

  /// The header, query parameter or cookie name of an API key.
  final String? parameterName;

  /// Where an API key is sent.
  final SecurityLocation? location;

  /// The HTTP authentication scheme, such as `bearer`, in lower case.
  final String? scheme;

  /// How a bearer token is formatted, such as `JWT`.
  final String? bearerFormat;

  /// The OpenID Connect discovery URL.
  final String? openIdConnectUrl;

  @override
  String toString() => 'SecurityScheme($name, ${type.name})';
}

/// A security scheme an operation requires, with the scopes it needs.
final class SecurityUse {
  /// Requires [scheme] with [scopes].
  const SecurityUse(this.scheme, [this.scopes = const []]);

  /// The scheme.
  final SecurityScheme scheme;

  /// The OAuth 2 or OpenID Connect scopes, or the roles of other schemes.
  final List<String> scopes;

  @override
  String toString() =>
      scopes.isEmpty ? scheme.name : '${scheme.name} ${scopes.join(' ')}';
}
````

**Diff** (apply from the repository root with `git apply`):

````diff
diff --git a/packages/typed_openapi_runtime/lib/src/dio/dio_request_sender.dart b/packages/typed_openapi_runtime/lib/src/dio/dio_request_sender.dart
index f91e4ff..0a065af 100644
--- a/packages/typed_openapi_runtime/lib/src/dio/dio_request_sender.dart
+++ b/packages/typed_openapi_runtime/lib/src/dio/dio_request_sender.dart
@@ -12,6 +12,7 @@ import '../sse/sse_item.dart';
 import '../sse/sse_item_decoder.dart';
 import '../sse/sse_message.dart';
 import 'call_options.dart';
+import 'dio_body.dart';
 
 /// Sends an [OperationRequest] through the user's [Dio] and turns every
 /// outcome into a [Result].
@@ -179,7 +180,6 @@ final class DioRequestSender {
     bool events = false,
     CancelToken? cancelToken,
   }) {
-    final path = _guardQuery(request.resolvePath());
     final options = Options(
       method: request.operation.method,
       headers: {
@@ -187,9 +187,10 @@ final class DioRequestSender {
         ...request.resolveHeaders(),
         for (final MapEntry(:key, :value) in call?.headers.entries ?? const [])
           key: ?value,
+        ...const DioBody().headers(request.body),
       },
       extra: {...?call?.extra, OperationInfo.extraKey: request.operation},
-      contentType: request.contentType,
+      contentType: const DioBody().contentType(request),
       responseType: events
           ? .stream
           : switch (request.responseKind) {
@@ -201,8 +202,8 @@ final class DioRequestSender {
     // The type argument picks how Dio reads the body: Dio forces JSON for
     // any type but String, List<int> with bytes or ResponseBody with stream.
     Future<Response<R>> send<R>() => dio.request<R>(
-      path,
-      data: request.body,
+      _guardQuery(request.resolvePath()),
+      data: const DioBody().data(request.body),
       options: options,
       cancelToken: cancelToken ?? call?.cancelToken,
       onSendProgress: call?.onSendProgress,
@@ -220,10 +221,9 @@ final class DioRequestSender {
   /// `//` of the whole string, query included (`RequestOptions.uri`), which
   /// would change an `allowReserved` value such as `next=/a//b`. When the
   /// query holds `//`, the base URL is joined here, collapsing `//` in the
-  /// path part only, and the result is passed as an absolute URL, which Dio
-  /// leaves alone. Interceptors still see the finished URI. Otherwise the
+  /// path part only, and Dio leaves the absolute URL alone. Otherwise the
   /// relative path goes to Dio, so interceptors that change `baseUrl` keep
-  /// working.
+  /// working; interceptors see the finished URI either way.
   String _guardQuery(String path) {
     final queryStart = path.indexOf('?');
     final base = dio.options.baseUrl;
diff --git a/packages/typed_openapi_runtime/lib/src/request/operation_info.dart b/packages/typed_openapi_runtime/lib/src/request/operation_info.dart
index 4d97377..d8039c7 100644
--- a/packages/typed_openapi_runtime/lib/src/request/operation_info.dart
+++ b/packages/typed_openapi_runtime/lib/src/request/operation_info.dart
@@ -1,5 +1,7 @@
 import 'package:dio/dio.dart';
 
+import 'security.dart';
+
 /// What a request is: the operation of the spec it calls.
 ///
 /// The request sender puts it into `RequestOptions.extra` under
@@ -12,6 +14,7 @@ final class OperationInfo {
     required this.method,
     required this.pathTemplate,
     this.tags = const [],
+    this.security = const [],
   });
 
   /// The key of this object in the `extra` map of a request.
@@ -30,6 +33,13 @@ final class OperationInfo {
   /// The tags of the operation in spec order.
   final List<String> tags;
 
+  /// The security requirements of the operation (its own `security`, else
+  /// the document's): any one of the alternatives is enough, and every
+  /// scheme of an alternative is needed. An empty alternative makes
+  /// security optional; no alternatives mean no security. The client only
+  /// describes them: interceptors add the credentials.
+  final List<List<SecurityUse>> security;
+
   /// The operation of a request, or `null` for a request a generated
   /// client did not send.
   static OperationInfo? of(RequestOptions options) =>
diff --git a/packages/typed_openapi_runtime/lib/src/request/operation_request.dart b/packages/typed_openapi_runtime/lib/src/request/operation_request.dart
index b59c9df..f221667 100644
--- a/packages/typed_openapi_runtime/lib/src/request/operation_request.dart
+++ b/packages/typed_openapi_runtime/lib/src/request/operation_request.dart
@@ -1,4 +1,7 @@
 import '../params/parameters.dart';
+import 'file_upload.dart';
+import 'form_body.dart';
+import 'multipart_body.dart';
 import 'operation_info.dart';
 
 /// How the response body is read, by the content type of the spec.
@@ -44,8 +47,9 @@ final class OperationRequest {
   /// The cookie parameters, sent in one `Cookie` header in this order.
   final List<CookieParameter> cookies;
 
-  /// The body as the HTTP client sends it: a JSON value (`toJson()`), form
-  /// text, bytes; `null` for no body.
+  /// The body: a JSON value (`toJson()`), text, a [FormBody], a
+  /// [MultipartBody] or a [FileUpload]; `null` for no body. The request
+  /// sender turns the last three into what the HTTP client sends.
   final Object? body;
 
   /// The `Content-Type` of [body].
@@ -67,7 +71,7 @@ final class OperationRequest {
   String resolvePath() {
     final values = {for (final p in path) p.name: p};
     final resolved = operation.pathTemplate.replaceAllMapped(
-      _placeholder,
+      pathVariable,
       (match) {
         final name = match[1]!;
         final parameter = values[name];
@@ -99,5 +103,8 @@ final class OperationRequest {
     };
   }
 
-  static final RegExp _placeholder = RegExp(r'\{([^{}]+)\}');
+  /// A variable of a path template: `{name}`, where the name has no brace.
+  /// The generator reads templates with the same pattern, so an operation
+  /// it generates has a parameter for every variable this finds.
+  static final RegExp pathVariable = RegExp(r'\{([^{}]*)\}');
 }
diff --git a/packages/typed_openapi_runtime/lib/src/request/raw_response.dart b/packages/typed_openapi_runtime/lib/src/request/raw_response.dart
index 2da6778..11bc9d4 100644
--- a/packages/typed_openapi_runtime/lib/src/request/raw_response.dart
+++ b/packages/typed_openapi_runtime/lib/src/request/raw_response.dart
@@ -45,10 +45,29 @@ final class RawResponse {
   /// The body as a JSON object; anything else throws [JsonDecodeException].
   Map<String, Object?> get jsonObject => JsonReader.asObject(json);
 
-  /// The body of a text operation; no body is `''`.
+  /// The body as JSON when the HTTP client read it as text or bytes (an
+  /// operation whose success is text or binary): parsed when [headers] name
+  /// a JSON content type, else as it is. Nesting deeper than
+  /// [JsonReader.maxDepth] throws [JsonDecodeException].
+  Object? get parsedJson {
+    final value = switch (body) {
+      final Uint8List bytes => parse(bytes, headers),
+      final String text when isJson(headers) => parse(
+        utf8.encode(text),
+        headers,
+      ),
+      final other => other,
+    };
+    JsonReader.checkDepth(value);
+    return value;
+  }
+
+  /// The body of a text operation; no body is `''`, bytes are read as
+  /// UTF-8 (invalid UTF-8 throws [FormatException]).
   String get text => switch (body) {
     null => '',
     final String text => text,
+    final Uint8List bytes => utf8.decode(bytes),
     final other => throw JsonDecodeException(
       expected: 'a text body',
       actual: JsonDecodeException.describe(other),
@@ -82,14 +101,17 @@ final class RawResponse {
 
   /// Parses a body the HTTP client did not parse (an error body of a
   /// streaming operation): JSON when [headers] name a JSON content type,
-  /// UTF-8 text otherwise, `null` when empty. Text that is not JSON throws
+  /// UTF-8 text otherwise, `null` when empty. Text that is not JSON, or
+  /// JSON nested deeper than [JsonReader.maxDepth], throws
   /// [JsonDecodeException].
   static Object? parse(Uint8List bytes, Map<String, List<String>> headers) {
     if (bytes.isEmpty) return null;
     final text = utf8.decode(bytes, allowMalformed: true);
     if (!isJson(headers)) return text;
     try {
-      return jsonDecode(text);
+      final value = jsonDecode(text);
+      JsonReader.checkDepth(value);
+      return value;
     } on FormatException {
       throw JsonDecodeException(
         expected: 'a JSON body',
diff --git a/packages/typed_openapi_runtime/lib/typed_openapi_runtime.dart b/packages/typed_openapi_runtime/lib/typed_openapi_runtime.dart
index ccf73d8..09a7a35 100644
--- a/packages/typed_openapi_runtime/lib/typed_openapi_runtime.dart
+++ b/packages/typed_openapi_runtime/lib/typed_openapi_runtime.dart
@@ -19,9 +19,14 @@ export 'src/params/parameters.dart'
         PathStyle,
         QueryParameter,
         QueryStyle;
+export 'src/request/file_upload.dart' show FileUpload;
+export 'src/request/form_body.dart' show FormBody, FormEncoding;
+export 'src/request/multipart_body.dart' show MultipartBody, MultipartPart;
 export 'src/request/operation_info.dart' show OperationInfo;
 export 'src/request/operation_request.dart' show OperationRequest, ResponseKind;
 export 'src/request/raw_response.dart' show RawResponse;
+export 'src/request/security.dart'
+    show SecurityLocation, SecurityScheme, SecuritySchemeType, SecurityUse;
 export 'src/result/result.dart'
     show
         Cancelled,
````

- [ ] **Step 4: Update the documentation**

**Diff** (apply from the repository root with `git apply`):

````diff
diff --git a/CLAUDE.md b/CLAUDE.md
index b31a5cf..11dfc96 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -532,10 +532,16 @@ that the API composes, including an `implements` fake of a tag class.
   percent-encoding; a path expansion that is empty, `.` or `..` throws
   `ArgumentError`, as does a `.`/`..` value); internal `ParameterValue`,
   `PercentEncoder`.
-- `request/` - `OperationInfo` (put into `RequestOptions.extra`),
-  `OperationRequest` (resolves the path and the query itself;
-  `streamStatuses` for event streams), `RawResponse` (what a generated
-  decoder switches on).
+- `request/` - `OperationInfo` (put into `RequestOptions.extra`; its
+  `security` lists alternatives of `SecurityUse`s of `SecurityScheme`s,
+  metadata only), `OperationRequest` (resolves the path and the query
+  itself; `pathVariable` is the one pattern of a path variable, which the
+  generator copies; `streamStatuses` for event streams), `RawResponse` (what
+  a generated decoder switches on; `parsedJson` parses a JSON body that Dio
+  read as text or bytes), and the bodies `FileUpload` (bytes or a stream),
+  `FormBody`/`FormEncoding` and `MultipartBody`/`MultipartPart`, which
+  `DioRequestSender` turns into form text, `FormData` and bytes or a
+  stream.
 - `dio/` - `DioRequestSender(dio, {isWeb})` (`send`, `openEvents`; requests
   only through `dio.request`, never mutates the user's Dio, never retries;
   decoding catches only `DioException`, `JsonDecodeException` and, from the
diff --git a/packages/typed_openapi_runtime/CHANGELOG.md b/packages/typed_openapi_runtime/CHANGELOG.md
index ed81e3c..7dc841f 100644
--- a/packages/typed_openapi_runtime/CHANGELOG.md
+++ b/packages/typed_openapi_runtime/CHANGELOG.md
@@ -15,3 +15,15 @@
 - For generated models: `DeepEquality` (deep `==` and `hashCode` of lists,
   maps and patches), `JsonReader.constant`, `JsonReader.additional`,
   `JsonReader.asBytes`, and `immutable` re-exported from `package:meta`.
+- For generated operations: `FileUpload` (bytes or a stream, with a file
+  name and a media type), `FormBody` and `FormEncoding`
+  (`application/x-www-form-urlencoded` with the spec's `encoding`),
+  `MultipartBody` and `MultipartPart`; `DioRequestSender` turns them into
+  what Dio sends, so generated signatures have no Dio types.
+- Security metadata for interceptors: `OperationInfo.security` with
+  `SecurityUse`, `SecurityScheme`, `SecuritySchemeType` and
+  `SecurityLocation`.
+- `RawResponse.parsedJson` (a JSON error body of a text or binary
+  operation), `RawResponse.text` of a body read as bytes, a depth check in
+  `RawResponse.parse`, and `OperationRequest.pathVariable`, the one pattern
+  of a path variable (`{}` is a variable with an empty name).
````

- [ ] **Step 5: Verify**

Run from the root:

```bash
dart pub get
dart analyze packages        # No issues found!
```

From `packages/typed_openapi`: `dart format lib test bin` (a second run changes 0 files) and `dart test` (expected `+924: All tests passed!`, the size ratchet `test/quality/size_limits_test.dart` included). From `packages/typed_openapi_runtime`: `dart format lib test` (the same) and `dart test` (expected `+183: All tests passed!`).

Browser gates for the new code, from `packages/typed_openapi_runtime`: `dart test -p chrome test/request test/dio/bodies_send_test.dart` and the same with `--compiler dart2wasm` (both green; set `CHROME_EXECUTABLE` if Chrome is not found).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(typed_openapi_runtime): add file uploads, form and multipart bodies, security metadata

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Codes in 6xx and the operation IR contract: path variables, dio names, parameter defaults, body encoding

**Files:**
- Modify: `CLAUDE.md`
- Modify: `packages/typed_openapi/CHANGELOG.md`
- Modify: `packages/typed_openapi/README.md`
- Modify: `packages/typed_openapi/README.ua.md`
- Modify: `packages/typed_openapi/lib/src/config/generation_config.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`
- Create: `packages/typed_openapi/lib/src/ir/api_ir.dart`
- Create: `packages/typed_openapi/lib/src/ir/body_encoding.dart`
- Modify: `packages/typed_openapi/lib/src/ir/ir.dart`
- Modify: `packages/typed_openapi/lib/src/ir/ir_builder.dart`
- Modify: `packages/typed_openapi/lib/src/ir/ir_context.dart`
- Modify: `packages/typed_openapi/lib/src/ir/names.dart`
- Modify: `packages/typed_openapi/lib/src/ir/operation_builder.dart`
- Modify: `packages/typed_openapi/lib/src/parse/openapi_parser.dart`
- Modify: `packages/typed_openapi/pubspec.yaml`
- Modify: `packages/typed_openapi/test/ir/ir_builder_test.dart`
- Modify: `packages/typed_openapi/test/ir/operation_builder_test.dart`
- Create: `packages/typed_openapi/test/ir/operation_contract_test.dart`
- Modify: `packages/typed_openapi/test/parse/openapi_parser_test.dart`
- Modify: `packages/typed_openapi/test/quality/size_limits_test.dart`

**Interfaces:**
- Consumes: task 1: `OperationRequest.pathVariable`; M6: `OperationBuilder`, `ParameterIr`, `RequestBodyIr`, `DartNames.takenTypeNames`.
- Produces: `DiagnosticCode.mediaTypeAsBytes` (TOA650), `.mediaTypesDropped` (TOA651), `.defaultErrorSchemaMissing` (TOA652), `.querystringNotGenerated` (TOA565), `.encodingHeadersIgnored` (TOA656); `OperationBuilder.pathVariable`, `OperationBuilder.allowedStyles`; `ParameterIr.defaultValue`; `RequestBodyIr.encoding`; `EncodingIr` in `ir/api_ir.dart` (exported by `ir.dart`); `BodyEncoding(IrContext).of(MediaType, BodyKind)`.

Closes the "IR -> emitter" rows the M6 review left for M9 before any code is emitted. TOA561 covered two findings and TOA562 sat in 5xx: they become TOA650/TOA651/TOA652, and the `querystring` half of TOA564 becomes TOA565 (spec decision 14). The IR reads path templates with the runtime's pattern, and a test compares the two (the runtime becomes a dev dependency of the generator). The API files will import only `Dio` from `package:dio` (decision 1 above), so `Dio` and the runtime's new names are reserved and `Response`, `Options`, `Headers` stay free. A parameter keeps its schema's `default` (documented by the emitter, never sent). A form or multipart body keeps its `encoding` (`BodyEncoding`: a style a query parameter does not allow is TOA564, part headers TOA656); a form or multipart response is bytes (TOA650); a text request body is `String`. An `apiKey` scheme without `in` is TOA112 (the M2 row).

- [ ] **Step 1: Write the failing tests**

**New file** `packages/typed_openapi/test/ir/operation_contract_test.dart`:

````dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/ir/dart_type.dart';
import 'package:typed_openapi/src/ir/ir.dart';
import 'package:typed_openapi/src/ir/ir_builder.dart';
import 'package:typed_openapi/src/ir/operation_builder.dart';
import 'package:typed_openapi/src/model/operation.dart';
import 'package:typed_openapi_runtime/typed_openapi_runtime.dart'
    show OperationRequest;

import '../helpers/ir_fixture.dart';

ClientIr build(IrFixture fixture) => IrBuilder(
  fixture.diagnostics,
).build(fixture.context.spec, fixture.context.client);

List<Diagnostic> reported(IrFixture fixture, DiagnosticCode code) => [
  for (final d in fixture.reported)
    if (d.code == code) d,
];

OperationIr single(ClientIr ir) => ir.groups.single.operations.single;

void main() {
  test('the generator reads path variables as the runtime does', () {
    expect(
      OperationBuilder.pathVariable.pattern,
      OperationRequest.pathVariable.pattern,
    );
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /c/{}:
    get:
      operationId: empty
      tags: [t]
      responses: {"200": {description: ok}}
''');
    build(fixture);
    expect(
      reported(fixture, .pathVariableUnbound).single.message,
      contains('"{}"'),
    );
  });

  test('a parameter keeps the default of its schema', () {
    final ir = build(
      IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: list
      tags: [t]
      parameters:
        - {name: limit, in: query, schema: {type: integer, default: 20}}
        - {name: sort, in: query, schema: {$ref: '#/components/schemas/Sort'}}
        - {name: q, in: query, schema: {type: string}}
      responses: {"200": {description: ok}}
components:
  schemas:
    Sort: {type: string, enum: [asc, desc], default: asc}
'''),
    );
    expect(
      [for (final p in single(ir).parameters) p.defaultValue],
      [
        (20,),
        ('asc',),
        null,
      ],
    );
  });

  group('request bodies', () {
    test('a form body keeps the encoding of its properties', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    post:
      operationId: send
      tags: [t]
      requestBody:
        content:
          application/x-www-form-urlencoded:
            schema:
              type: object
              properties:
                tags: {type: array, items: {type: string}}
                meta: {type: object, additionalProperties: {type: string}}
                next: {type: string}
                bad: {type: string}
            encoding:
              tags: {style: form, explode: false}
              meta: {style: deepObject, explode: true}
              next: {allowReserved: true, contentType: application/json}
              bad: {style: matrix}
      responses: {"204": {description: ok}}
''');
      final body = single(build(fixture)).body!;
      expect(body.kind, BodyKind.form);
      expect(
        [
          for (final e in body.encoding)
            (e.property, e.style, e.explode, e.allowReserved, e.contentType),
        ],
        [
          ('bad', null, null, false, null),
          ('meta', ParameterStyle.deepObject, true, false, null),
          ('next', null, null, true, 'application/json'),
          ('tags', ParameterStyle.form, false, false, null),
        ],
      );
      final style = reported(fixture, .parameterStyleInvalid).single;
      expect(
        style.pointer?.value,
        '#/paths/~1a/post/requestBody/content/'
        'application~1x-www-form-urlencoded/encoding/bad/style',
      );
      expect(style.message, contains('"matrix"'));
      expect(fixture.reported, hasLength(1));
    });

    test('a multipart part keeps its media type; its headers are reported', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    post:
      operationId: upload
      tags: [t]
      requestBody:
        content:
          multipart/form-data:
            schema:
              type: object
              properties:
                file: {type: string, format: binary}
                meta: {type: object}
            encoding:
              file:
                contentType: image/png
                style: matrix
                headers:
                  X-Rate: {schema: {type: integer}}
              meta: {contentType: application/json}
      responses: {"204": {description: ok}}
''');
      final body = single(build(fixture)).body!;
      expect(body.kind, BodyKind.multipart);
      expect(
        [for (final e in body.encoding) (e.property, e.style, e.contentType)],
        [('file', null, 'image/png'), ('meta', null, 'application/json')],
      );
      final headers = reported(fixture, .encodingHeadersIgnored).single;
      expect(headers.severity, Severity.info);
      expect(
        headers.pointer?.value,
        '#/paths/~1a/post/requestBody/content/multipart~1form-data/'
        'encoding/file/headers',
      );
      // Styles are for forms only; a multipart body ignores them.
      expect(fixture.reported, hasLength(1));
    });

    test('a text body is a string, whatever its schema', () {
      final ir = build(
        IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    post:
      operationId: send
      tags: [t]
      requestBody:
        content:
          text/csv: {schema: {type: object, properties: {a: {type: string}}}}
      responses: {"204": {description: ok}}
'''),
      );
      expect(single(ir).body?.type, const CoreType(.string));
      expect(ir.declarations, isEmpty);
    });
  });

  test('a form or multipart response is read as bytes (TOA650)', () {
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: get
      tags: [t]
      responses:
        "200":
          description: ok
          content:
            multipart/form-data: {schema: {type: object, properties: {a: {type: string}}}}
''');
    final ir = build(fixture);
    final response = single(ir).responses.single;
    expect(response.kind, BodyKind.bytes);
    expect(response.type, const CoreType(.binary));
    expect(ir.declarations, isEmpty);
    expect(
      reported(fixture, .mediaTypeAsBytes).single.pointer?.value,
      '#/paths/~1a/get/responses/200/content/multipart~1form-data',
    );
  });

  group('names the API files import', () {
    test('a schema named like a dio export other than Dio keeps its name', () {
      final ir = build(
        IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: get
      tags: [t]
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema:
                type: object
                properties:
                  a: {$ref: '#/components/schemas/Response'}
                  b: {$ref: '#/components/schemas/Options'}
                  c: {$ref: '#/components/schemas/Headers'}
                  d: {$ref: '#/components/schemas/Dio'}
                  e: {$ref: '#/components/schemas/FileUpload'}
                  f: {$ref: '#/components/schemas/SecurityScheme'}
components:
  schemas:
    Response: {type: object, properties: {x: {type: string}}}
    Options: {type: object, properties: {x: {type: string}}}
    Headers: {type: object, properties: {x: {type: string}}}
    Dio: {type: object, properties: {x: {type: string}}}
    FileUpload: {type: object, properties: {x: {type: string}}}
    SecurityScheme: {type: object, properties: {x: {type: string}}}
'''),
      );
      expect(
        [for (final d in ir.declarations) d.name],
        containsAll([
          'Response',
          'Options',
          'Headers',
          'DioModel',
          'FileUploadModel',
          'SecuritySchemeModel',
        ]),
      );
    });
  });
}
````

**Diff** (apply from the repository root with `git apply`):

````diff
diff --git a/packages/typed_openapi/test/ir/ir_builder_test.dart b/packages/typed_openapi/test/ir/ir_builder_test.dart
index d18e083..b678265 100644
--- a/packages/typed_openapi/test/ir/ir_builder_test.dart
+++ b/packages/typed_openapi/test/ir/ir_builder_test.dart
@@ -269,7 +269,7 @@ components:
     // The text alternative of the request body is dropped.
     expect(fixture.codes, [
       (
-        DiagnosticCode.mediaTypeAsBytes,
+        DiagnosticCode.mediaTypesDropped,
         '#/paths/~1pets/post/requestBody/content',
       ),
     ]);
diff --git a/packages/typed_openapi/test/ir/operation_builder_test.dart b/packages/typed_openapi/test/ir/operation_builder_test.dart
index aba3d30..1e7a387 100644
--- a/packages/typed_openapi/test/ir/operation_builder_test.dart
+++ b/packages/typed_openapi/test/ir/operation_builder_test.dart
@@ -421,7 +421,7 @@ paths:
         [for (final p in ir.groups.single.operations.single.parameters) p.name],
         ['q'],
       );
-      final found = reported(fixture, .parameterStyleInvalid).single;
+      final found = reported(fixture, .querystringNotGenerated).single;
       expect(found.pointer?.value, '#/paths/~1a/get/parameters/0');
       expect(found.message, contains('querystring'));
       expect(found.message, contains('not generated'));
@@ -542,7 +542,7 @@ operations:
     });
   });
 
-  group('media types (TOA561)', () {
+  group('media types (TOA650, TOA651)', () {
     const xml = r'''
 openapi: 3.1.0
 info: {title: t, version: "1"}
@@ -629,7 +629,7 @@ paths:
         ir.groups.single.operations.single.body?.contentType,
         'application/json',
       );
-      final found = reported(fixture, .mediaTypeAsBytes);
+      final found = reported(fixture, .mediaTypesDropped);
       expect(
         found.single.pointer?.value,
         '#/paths/~1a/post/requestBody/content',
@@ -667,7 +667,7 @@ paths:
             application/json; profile="Pascal": {schema: {type: object}}
 ''');
       build(fixture);
-      final found = reported(fixture, .mediaTypeAsBytes);
+      final found = reported(fixture, .mediaTypesDropped);
       // The 200 response has only JSON variants (`text/json` too): nothing
       // is dropped. The 201 response drops the XML.
       expect(found.map((d) => d.pointer?.value), [
@@ -705,7 +705,7 @@ paths:
           .child('default_schema'),
     );
 
-    test('a key that is not in components.schemas is TOA562, ignored', () {
+    test('a key that is not in components.schemas is TOA652, ignored', () {
       final fixture = IrFixture(
         '''
 openapi: 3.1.0
diff --git a/packages/typed_openapi/test/parse/openapi_parser_test.dart b/packages/typed_openapi/test/parse/openapi_parser_test.dart
index 373a177..82ad96a 100644
--- a/packages/typed_openapi/test/parse/openapi_parser_test.dart
+++ b/packages/typed_openapi/test/parse/openapi_parser_test.dart
@@ -87,15 +87,18 @@ components:
 ''');
     expect(doc.info!.title, 'Pets');
     expect(doc.tags.single.description, 'No name.');
+    // An apiKey scheme needs `name` and `in`.
     expect(fixture.codes, [
       DiagnosticCode.missingRequiredField,
       DiagnosticCode.missingRequiredField,
       DiagnosticCode.missingRequiredField,
+      DiagnosticCode.missingRequiredField,
       DiagnosticCode.unknownKey,
     ]);
     expect(fixture.pointers, [
       '#/info',
       '#/components/securitySchemes/key',
+      '#/components/securitySchemes/key',
       '#/tags/0',
       '#/host',
     ]);
````

- [ ] **Step 2: Run the tests to see them fail**

Run from `packages/typed_openapi`: `dart test test/ir test/parse`.
Expected: FAIL: `operation_contract_test.dart` does not load (the runtime is not a dependency of the generator yet), `DiagnosticCode.mediaTypesDropped` and `querystringNotGenerated` are not defined, `OperationBuilder.pathVariable` is not defined, `ParameterIr.defaultValue` and `RequestBodyIr.encoding` do not exist; `openapi_parser_test` finds one TOA112 less.

- [ ] **Step 3: Implement**

The dev dependency comes in the diff of `pubspec.yaml` below; run `dart pub get` from the root right after applying it.

**New file** `packages/typed_openapi/lib/src/ir/api_ir.dart`:

````dart
import '../model/operation.dart';

// The parts of the IR that only the API emitter reads (M9). `ir.dart`
// exports them.

/// How one property of a form or multipart request body is sent: an entry
/// of the media type's `encoding`.
final class EncodingIr {
  /// Creates the encoding of [property].
  const EncodingIr(
    this.property, {
    this.contentType,
    this.style,
    this.explode,
    this.allowReserved = false,
  });

  /// The property name, as in the spec.
  final String property;

  /// `contentType`: the media type of a multipart part, or JSON text for a
  /// form property.
  final String? contentType;

  /// `style` of a form property; null for `form`. A style a query parameter
  /// does not allow is reported (TOA564) and left out.
  final ParameterStyle? style;

  /// `explode`; null for the default of the style.
  final bool? explode;

  /// `allowReserved`.
  final bool allowReserved;
}
````

**New file** `packages/typed_openapi/lib/src/ir/body_encoding.dart`:

````dart
import '../model/operation.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'operation_builder.dart';

/// Reads the `encoding` of a form or multipart request body.
final class BodyEncoding {
  /// Creates the reader; it reports through [_context].
  const BodyEncoding(this._context);

  final IrContext _context;

  /// The `encoding` of a form or multipart body, by property name. A style
  /// a query parameter does not allow is reported (TOA564) and left out;
  /// headers of a part cannot be sent and are reported (TOA656).
  List<EncodingIr> of(MediaType media, BodyKind kind) {
    final allowed = OperationBuilder.allowedStyles[ParameterLocation.query]!;
    return [
      for (final property in media.encoding.keys.toList()..sort())
        if (media.encoding[property] case final encoding?)
          EncodingIr(
            property,
            contentType: encoding.contentType,
            style: _encodingStyle(encoding, property, kind, allowed),
            explode: encoding.explode,
            allowReserved: encoding.allowReserved,
          ),
    ];
  }

  ParameterStyle? _encodingStyle(
    Encoding encoding,
    String property,
    BodyKind kind,
    List<ParameterStyle> allowed,
  ) {
    if (encoding.headers.isNotEmpty) {
      _context.report(
        .encodingHeadersIgnored,
        'The headers of part "$property" are not sent: the client sends a '
        'part with its name, media type and file name only.',
        encoding.location.child('headers'),
        fix: 'Send the headers another way, or remove them at the source.',
      );
    }
    final style = encoding.style;
    if (style == null || kind != .form || allowed.contains(style)) {
      return kind == .form ? style : null;
    }
    _context.report(
      .parameterStyleInvalid,
      'The style "${style.name}" is not allowed for a form property, which '
      'takes ${[for (final s in allowed) '"${s.name}"'].join(', ')}; the '
      'default style "form" is used for "$property".',
      encoding.location.child('style'),
      fix: 'Use one of these styles at the source.',
    );
    return null;
  }
}
````

**Diff** (apply from the repository root with `git apply`):

````diff
diff --git a/packages/typed_openapi/lib/src/config/generation_config.dart b/packages/typed_openapi/lib/src/config/generation_config.dart
index 90b0436..d56e510 100644
--- a/packages/typed_openapi/lib/src/config/generation_config.dart
+++ b/packages/typed_openapi/lib/src/config/generation_config.dart
@@ -194,7 +194,7 @@ final class GenerationConfig {
   /// key, so that the diagnostics about its patterns (TOA557, TOA558) and
   /// about an empty client (TOA563) are reported at its own place in the
   /// config, not at the place of another client that has the same settings;
-  /// the key has the place of `errors.default_schema` for TOA562 the same
+  /// the key has the place of `errors.default_schema` for TOA652 the same
   /// way.
   String get key => jsonEncode({
     'group': groupTemplate,
diff --git a/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart b/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart
index 56b702d..21f8ac4 100644
--- a/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart
+++ b/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart
@@ -352,21 +352,6 @@ enum DiagnosticCode {
   /// (`pet-store`) is not reported: it is used as `PetStore`.
   overrideNameInvalid('TOA560', 'override-name-invalid', .warning),
 
-  /// A request or response body has a media type that is not JSON, a form,
-  /// `multipart/form-data`, `text/*` or `text/event-stream`: it is sent or
-  /// read as bytes and its schema is not used. Also reported when an
-  /// operation offers several media types of a body and the others are
-  /// dropped; the message names the chosen one and the dropped ones.
-  mediaTypeAsBytes('TOA561', 'media-type-as-bytes', .info),
-
-  /// `errors.default_schema` names a key that is not in
-  /// `components.schemas`; the setting is ignored.
-  defaultErrorSchemaMissing(
-    'TOA562',
-    'default-error-schema-missing',
-    .warning,
-  ),
-
   /// No operation of a client is generated: all are filtered out, all are
   /// written as a `$ref` (TOA107), or all have an unbound path variable
   /// (TOA556). The message says why.
@@ -375,14 +360,39 @@ enum DiagnosticCode {
   /// A parameter's `style` is not allowed for its `in` (path takes `simple`,
   /// `label` or `matrix`; query `form`, `spaceDelimited`, `pipeDelimited` or
   /// `deepObject`; header `simple`; cookie `form` or `cookie`), so the
-  /// default style of the placement is used. Also reported for an `in: querystring`
-  /// parameter (OpenAPI 3.2), which the client cannot send: the parameter
-  /// is not generated.
+  /// default style of the placement is used.
   parameterStyleInvalid('TOA564', 'parameter-style-invalid', .warning),
 
+  /// A parameter is `in: querystring` (OpenAPI 3.2), which the client cannot
+  /// send yet: the parameter is not generated (TOA564 until M9).
+  querystringNotGenerated('TOA565', 'querystring-not-generated', .warning),
+
   /// `*/*` is used as a media type.
   wildcardMediaType('TOA601', 'wildcard-media-type', .warning),
 
+  /// A request or response body has a media type that is not JSON, a form,
+  /// `multipart/form-data`, `text/*` or `text/event-stream` (or is a form or
+  /// multipart response): it is sent or read as bytes and its schema is not
+  /// used (TOA561 until M9).
+  mediaTypeAsBytes('TOA650', 'media-type-as-bytes', .info),
+
+  /// A request body, a response or a parameter offers several media types;
+  /// the client uses one and the message names the ones it drops (TOA561
+  /// until M9).
+  mediaTypesDropped('TOA651', 'media-types-dropped', .info),
+
+  /// `errors.default_schema` names a key that is not in
+  /// `components.schemas`; the setting is ignored (TOA562 until M9).
+  defaultErrorSchemaMissing(
+    'TOA652',
+    'default-error-schema-missing',
+    .warning,
+  ),
+
+  /// An `encoding` entry of a multipart or form body has `headers`, which
+  /// the client does not send.
+  encodingHeadersIgnored('TOA656', 'encoding-headers-ignored', .info),
+
   /// A normalizer fix or an override was not applied: its file cannot be
   /// read, its target is gone, the spec kept changing after the last pass, or
   /// the change would have no effect in the spec's dialect.
diff --git a/packages/typed_openapi/lib/src/ir/ir.dart b/packages/typed_openapi/lib/src/ir/ir.dart
index f73a856..7a2ae28 100644
--- a/packages/typed_openapi/lib/src/ir/ir.dart
+++ b/packages/typed_openapi/lib/src/ir/ir.dart
@@ -1,7 +1,10 @@
 import '../model/operation.dart';
 import '../model/spec_node.dart';
+import 'api_ir.dart';
 import 'dart_type.dart';
 
+export 'api_ir.dart';
+
 /// The semantic IR of one client: what the emitters print, with Dart names
 /// and types already chosen.
 ///
@@ -560,6 +563,7 @@ final class ParameterIr {
     this.contentType,
     this.description,
     this.deprecated = false,
+    this.defaultValue,
   });
 
   /// The Dart name of the argument.
@@ -598,6 +602,11 @@ final class ParameterIr {
 
   /// `deprecated`.
   final bool deprecated;
+
+  /// `default` of the parameter's schema, as a one-element record: the
+  /// value the server uses when the argument is not sent. It is documented,
+  /// not sent.
+  final (Object?,)? defaultValue;
 }
 
 /// How a body is encoded.
@@ -634,6 +643,7 @@ final class RequestBodyIr {
     this.type,
     this.required = false,
     this.description,
+    this.encoding = const [],
   });
 
   /// How the body is encoded.
@@ -653,6 +663,10 @@ final class RequestBodyIr {
 
   /// `description`.
   final String? description;
+
+  /// The `encoding` of the properties of a form or multipart body, by
+  /// property name.
+  final List<EncodingIr> encoding;
 }
 
 /// A response of an operation.
diff --git a/packages/typed_openapi/lib/src/ir/ir_builder.dart b/packages/typed_openapi/lib/src/ir/ir_builder.dart
index e72a7af..a3b9262 100644
--- a/packages/typed_openapi/lib/src/ir/ir_builder.dart
+++ b/packages/typed_openapi/lib/src/ir/ir_builder.dart
@@ -29,8 +29,6 @@ final class IrBuilder {
   /// `UserController_get` → `get`.
   static final nestjsPrefix = RegExp('^[A-Za-z0-9]*Controller_');
 
-  static final _variable = RegExp(r'\{([^}]*)\}');
-
   final DiagnosticBag _diagnostics;
 
   /// The IR of [spec] generated as [client] says.
@@ -419,7 +417,9 @@ final class IrBuilder {
   /// `getPetsById`.
   static String _pathName(String method, String path) {
     final variables = <String>[];
-    final literal = path.replaceAllMapped(_variable, (match) {
+    final literal = path.replaceAllMapped(OperationBuilder.pathVariable, (
+      match,
+    ) {
       variables.add(match[1]!);
       return ' ';
     });
diff --git a/packages/typed_openapi/lib/src/ir/ir_context.dart b/packages/typed_openapi/lib/src/ir/ir_context.dart
index 79a20bd..1e3fdb4 100644
--- a/packages/typed_openapi/lib/src/ir/ir_context.dart
+++ b/packages/typed_openapi/lib/src/ir/ir_context.dart
@@ -105,7 +105,7 @@ final class IrContext {
   late final OverrideSnippet _snippets = OverrideSnippet(model);
 
   /// `errors.default_schema` when `components.schemas` has the key; else
-  /// null, with TOA562 reported the first time this is read.
+  /// null, with TOA652 reported the first time this is read.
   late final String? defaultErrorSchema = _checkedDefaultErrorSchema();
 
   static const _names = DartNames();
diff --git a/packages/typed_openapi/lib/src/ir/names.dart b/packages/typed_openapi/lib/src/ir/names.dart
index 1bc0e7a..c6332c7 100644
--- a/packages/typed_openapi/lib/src/ir/names.dart
+++ b/packages/typed_openapi/lib/src/ir/names.dart
@@ -49,8 +49,10 @@ final class DartNames {
   };
 
   /// Type names a generated library sees without importing them: those of
-  /// `dart:core`, `Uint8List` of `dart:typed_data`, and the names of
-  /// `typed_openapi_runtime` that generated code uses.
+  /// `dart:core`, `Uint8List` of `dart:typed_data`, the names of
+  /// `typed_openapi_runtime` that generated code uses, and `Dio`, the one
+  /// name the API files import from `package:dio` (so its other exports,
+  /// such as `Response`, `Options` and `Headers`, stay free for schemas).
   static const takenTypeNames = {
     // dart:core
     'ArgumentError', 'AssertionError', 'BigInt', 'BidirectionalIterator',
@@ -68,13 +70,18 @@ final class DartNames {
     // typed_openapi_runtime
     'CallOptions', 'Cancelled', 'CookieParameter', 'Date', 'DecodeError',
     'DeepEquality',
-    'DioRequestSender', 'Failure', 'HeaderParameter', 'HttpError',
-    'JsonDecodeException', 'JsonReader', 'JsonValue', 'OperationInfo',
+    'DioRequestSender', 'Failure', 'FileUpload', 'FormBody', 'FormEncoding',
+    'HeaderParameter', 'HttpError',
+    'JsonDecodeException', 'JsonReader', 'JsonValue', 'MultipartBody',
+    'MultipartPart', 'OperationInfo',
     'OperationRequest', 'Patch', 'PatchNull', 'PatchValue', 'PathParameter',
     'PathStyle', 'QueryParameter', 'QueryStyle', 'RawResponse',
-    'ResponseKind', 'Result', 'SseDecoder', 'SseDecodeError',
+    'ResponseKind', 'Result', 'SecurityLocation', 'SecurityScheme',
+    'SecuritySchemeType', 'SecurityUse', 'SseDecoder', 'SseDecodeError',
     'SseDisconnected', 'SseEvent', 'SseItem', 'SseItemDecoder', 'SseMessage',
     'Success', 'TransportError', 'UndocumentedStatus',
+    // package:dio, which the API files import with `show Dio` only.
+    'Dio',
   };
 
   /// Members every Dart object has.
diff --git a/packages/typed_openapi/lib/src/ir/operation_builder.dart b/packages/typed_openapi/lib/src/ir/operation_builder.dart
index dd18dc3..a47117e 100644
--- a/packages/typed_openapi/lib/src/ir/operation_builder.dart
+++ b/packages/typed_openapi/lib/src/ir/operation_builder.dart
@@ -1,6 +1,7 @@
 import '../model/operation.dart';
 import '../model/schema.dart';
 import '../model/spec_node.dart';
+import 'body_encoding.dart';
 import 'dart_type.dart';
 import 'ir.dart';
 import 'ir_context.dart';
@@ -35,10 +36,16 @@ final class SpecOperation {
 /// (R10.3, R10.4, R10.6, R11.4); types come from a [SchemaMapper].
 final class OperationBuilder {
   /// Creates a builder that maps types with [_mapper].
-  OperationBuilder(this._context, this._mapper);
+  OperationBuilder(this._context, this._mapper)
+    : _encoding = BodyEncoding(_context);
 
   static const _names = DartNames();
-  static final _variable = RegExp(r'\{([^}]*)\}');
+
+  /// A variable of a path template: `{name}`, where the name has no brace
+  /// (`{}` is a variable with an empty name). The runtime resolves paths
+  /// with the same pattern (`OperationRequest.pathVariable`), so every
+  /// variable it finds has a parameter.
+  static final pathVariable = RegExp(r'\{([^{}]*)\}');
 
   /// The header parameters OpenAPI says to ignore: the request's own
   /// `Accept`, `Content-Type` and `Authorization` (compared in lower case).
@@ -47,7 +54,7 @@ final class OperationBuilder {
   /// The styles OpenAPI allows for each placement, the default style
   /// first (`style: cookie` is OpenAPI 3.2's second style for cookies); a
   /// `querystring` parameter has none.
-  static const _allowedStyles = {
+  static const allowedStyles = {
     ParameterLocation.path: [
       ParameterStyle.simple,
       ParameterStyle.label,
@@ -65,6 +72,7 @@ final class OperationBuilder {
 
   final IrContext _context;
   final SchemaMapper _mapper;
+  final BodyEncoding _encoding;
 
   /// The IR of [entry], named [name]; null when its path template cannot
   /// be filled.
@@ -114,7 +122,7 @@ final class OperationBuilder {
       byKey[(placement, parameter.name)] = (placement, parameter);
     }
     final variables = [
-      for (final match in _variable.allMatches(entry.path)) match[1]!,
+      for (final match in pathVariable.allMatches(entry.path)) match[1]!,
     ];
     var bound = true;
     for (final variable in variables) {
@@ -167,7 +175,7 @@ final class OperationBuilder {
   }
 
   /// Whether a parameter of [placement] can be sent; a `querystring`
-  /// parameter cannot, and is reported (TOA564).
+  /// parameter cannot, and is reported (TOA565).
   bool _isSendable(
     ParameterLocation placement,
     Parameter parameter,
@@ -175,7 +183,7 @@ final class OperationBuilder {
   ) {
     if (placement != .querystring) return true;
     _context.report(
-      .parameterStyleInvalid,
+      .querystringNotGenerated,
       'Parameter "$wire" is in: querystring (OpenAPI 3.2), which the client '
       'cannot send; the parameter is not generated.',
       parameter.location,
@@ -193,7 +201,7 @@ final class OperationBuilder {
     String wire,
   ) {
     final style = parameter.style;
-    final allowed = _allowedStyles[placement];
+    final allowed = allowedStyles[placement];
     if (style == null || allowed == null || allowed.contains(style)) {
       return style;
     }
@@ -307,9 +315,19 @@ final class OperationBuilder {
       contentType: contentType,
       description: parameter.description,
       deprecated: parameter.deprecated,
+      defaultValue: _defaultOf(schema),
     );
   }
 
+  /// `default` of a parameter's [schema], also through a `$ref`.
+  (Object?,)? _defaultOf(Schema? schema) => switch (schema) {
+    null => null,
+    final schema => switch (_context.model.resolveSchema(schema)) {
+      final SchemaObject target => target.defaultValue,
+      _ => null,
+    },
+  };
+
   RequestBodyIr? _body(Operation operation, String method, String prefix) {
     final written = operation.requestBody;
     if (written == null) return null;
@@ -322,9 +340,10 @@ final class OperationBuilder {
     );
     final kind = contentType == null ? BodyKind.none : _kind(contentType);
     final schema = media?.schema;
-    // Raw bytes have no model, as in responses.
+    // Raw bytes have no model, as in responses; text is a string.
     final DartType? type = switch ((schema, kind)) {
       (_, .bytes) => const CoreType(.binary),
+      (_, .text || .eventStream) => const CoreType(.string),
       (null, _) => null,
       (final schema?, _) => _mapper.typeOf(
         schema,
@@ -340,6 +359,9 @@ final class OperationBuilder {
       type: type,
       required: body.required,
       description: body.description,
+      encoding: kind == .form || kind == .multipart
+          ? _encoding.of(media!, kind)
+          : const [],
     );
   }
 
@@ -364,7 +386,7 @@ final class OperationBuilder {
     }
     final result = <ResponseIr>[];
     for (final (status, response, (contentType, media)) in responses) {
-      final kind = contentType == null ? BodyKind.none : _kind(contentType);
+      final kind = _responseKind(contentType, response);
       final success = status.startsWith('2');
       final base = _nameBase(status);
       final suffix = (withBody[base] ?? 0) > 1
@@ -401,6 +423,23 @@ final class OperationBuilder {
     return result;
   }
 
+  /// How the body of [response] in [contentType] is read: a form or a
+  /// multipart response is bytes (TOA650), since a client does not read
+  /// forms.
+  BodyKind _responseKind(String? contentType, Response response) {
+    if (contentType == null) return .none;
+    final kind = _kind(contentType);
+    if (kind != .form && kind != .multipart) return kind;
+    _context.report(
+      .mediaTypeAsBytes,
+      'The response is "$contentType", which the client reads as bytes; its '
+      'schema is not used.',
+      response.location.child('content').child(contentType),
+      fix: 'Use a JSON media type at the source if the schema matters.',
+    );
+    return .bytes;
+  }
+
   /// How inline types of a response with [status] are named: `Response`
   /// for 2xx, `Error` for 4xx, 5xx and `default`, `Response` with the status
   /// for the rest.
@@ -459,8 +498,8 @@ final class OperationBuilder {
   /// The media type the client uses: JSON first, then forms, text, event
   /// streams and anything else, each in document order. [location] is the
   /// object that has [content] and [what] says what it is. The media types
-  /// that are dropped are reported, and so is a chosen one that becomes
-  /// bytes and takes its schema with it (TOA561).
+  /// that are dropped are reported (TOA651), and so is a chosen one that
+  /// becomes bytes and takes its schema with it (TOA650).
   (String?, MediaType?) _pick(
     Map<String, RefOr<MediaType>> content,
     SpecLocation location,
@@ -491,7 +530,7 @@ final class OperationBuilder {
         ];
         if (dropped.isNotEmpty) {
           _context.report(
-            .mediaTypeAsBytes,
+            .mediaTypesDropped,
             'The $what offers ${content.length} media types; "$type" is '
             'used and ${_quoted(dropped)} '
             '${dropped.length == 1 ? 'is' : 'are'} dropped.',
diff --git a/packages/typed_openapi/lib/src/parse/openapi_parser.dart b/packages/typed_openapi/lib/src/parse/openapi_parser.dart
index 8b5e201..cc508ef 100644
--- a/packages/typed_openapi/lib/src/parse/openapi_parser.dart
+++ b/packages/typed_openapi/lib/src/parse/openapi_parser.dart
@@ -191,7 +191,9 @@ final class OpenApiParser {
             type: type,
             description: r.string('description'),
             name: field('name', .apiKey),
-            placement: r.choice('in', ApiKeyLocation.values.asNameMap()),
+            placement: type == .apiKey
+                ? r.requiredChoice('in', ApiKeyLocation.values.asNameMap())
+                : r.choice('in', ApiKeyLocation.values.asNameMap()),
             scheme: field('scheme', .http),
             bearerFormat: r.string('bearerFormat'),
             flows: type == .oauth2
diff --git a/packages/typed_openapi/pubspec.yaml b/packages/typed_openapi/pubspec.yaml
index e96c2b7..7ade544 100644
--- a/packages/typed_openapi/pubspec.yaml
+++ b/packages/typed_openapi/pubspec.yaml
@@ -27,6 +27,9 @@ dependencies:
 
 dev_dependencies:
   test: ^1.24.0
+  # A test checks that the generator reads path templates as the runtime
+  # does.
+  typed_openapi_runtime: ^0.0.1
   # Tests compare the composer with package:yaml's loader.
   yaml: ^3.1.4
 
````

- [ ] **Step 4: Get the new dev dependency**

Run from the root: `dart pub get`.

- [ ] **Step 5: Update the size ratchet**

`ir.dart` and `operation_builder.dart` take new fields and calls (their logic is in `api_ir.dart` and `body_encoding.dart`), and `_parameter` one argument line: the entries are raised with their reasons (table "Size ratchet changes").

**Diff** (apply from the repository root with `git apply`):

````diff
diff --git a/packages/typed_openapi/test/quality/size_limits_test.dart b/packages/typed_openapi/test/quality/size_limits_test.dart
index cb20f27..10601d8 100644
--- a/packages/typed_openapi/test/quality/size_limits_test.dart
+++ b/packages/typed_openapi/test/quality/size_limits_test.dart
@@ -20,9 +20,11 @@ const Map<String, int> _fileAllowlist = {
   'lib/src/emit/model_emitter.dart': 379,
   'lib/src/emit/union_emitter.dart': 416,
   'lib/src/generate/output_writer.dart': 896,
-  'lib/src/ir/ir.dart': 733,
+  // M9: the fields the API emitter reads on the operation IR classes.
+  'lib/src/ir/ir.dart': 747,
   'lib/src/ir/ir_builder.dart': 534,
-  'lib/src/ir/operation_builder.dart': 565,
+  // M9: the path variable pattern, parameter defaults, encodings, statuses.
+  'lib/src/ir/operation_builder.dart': 604,
   'lib/src/ir/schema_mapper.dart': 2196,
   'lib/src/ir/schema_shapes.dart': 446,
   'test/check/spec_checker_test.dart': 705,
@@ -70,7 +72,8 @@ const Map<String, int> _methodAllowlist = {
   'lib/src/ir/ir_builder.dart#IrBuilder._methodName': 50,
   'lib/src/ir/ir_builder.dart#IrBuilder._reportEmpty': 50,
   'lib/src/ir/ir_builder.dart#IrBuilder.build': 95,
-  'lib/src/ir/operation_builder.dart#OperationBuilder._parameter': 99,
+  // M9: a parameter keeps its schema's default.
+  'lib/src/ir/operation_builder.dart#OperationBuilder._parameter': 100,
   'lib/src/ir/operation_builder.dart#OperationBuilder._parameters': 74,
   'lib/src/ir/operation_builder.dart#OperationBuilder._pick': 58,
   'lib/src/ir/operation_builder.dart#OperationBuilder._responses': 57,
````

- [ ] **Step 6: Update the documentation**

**Diff** (apply from the repository root with `git apply`):

````diff
diff --git a/CLAUDE.md b/CLAUDE.md
index 11dfc96..599a1ae 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -205,7 +205,7 @@ All under `packages/typed_openapi/lib/src/`, one folder per stage:
   their defaults). `operation_prefix` applies only where its match starts at
   index 0 and is not empty. `GenerationConfig.key` is the run key: custom
   types are sorted, and a client with a filter or an `errors.default_schema`
-  is keyed by where the config has it, so TOA557, TOA558, TOA562 and TOA563
+  is keyed by where the config has it, so TOA557, TOA558, TOA652 and TOA563
   are reported at its own place, not at that of a client with equal
   settings.
 - `ir/` - the semantic IR (M6): `ir.dart` (`ClientIr`, sealed `Declaration`
@@ -223,7 +223,7 @@ All under `packages/typed_openapi/lib/src/`, one folder per stage:
   `checkedOverrideName` validates an override name, TOA560, and
   `checkLossyName` reports letters a name lost, TOA559; `defaultErrorSchema`
   is `errors.default_schema` if `components.schemas` has the key, else
-  TOA562), `SchemaShapes` (shape questions the mapper and `DirectionIndex`
+  TOA652), `SchemaShapes` (shape questions the mapper and `DirectionIndex`
   share: null-only, enum values, the one schema a wrapper stands for; an
   `allOf` part with no structure, only annotations and `nullable`, is not a
   merge part and is set aside next to the one `$ref`),
@@ -251,12 +251,19 @@ All under `packages/typed_openapi/lib/src/`, one folder per stage:
   (parameters in location order and then spec order, the names overrides give
   claimed first; a body is JSON first, then multipart, form, text, event
   stream; any other media type is bytes (`Uint8List`) without its schema and
-  the media types that are dropped are named, TOA561, except variants of the
-  chosen type and other JSON types; envelopes; errors, with
+  the media types that are dropped are named, TOA651, except variants of the
+  chosen type and other JSON types; a form or multipart response is bytes,
+  TOA650; a text request body is `String`; the `encoding` of a form or
+  multipart body (`EncodingIr`, a style a query does not allow is TOA564,
+  part headers TOA656); a parameter keeps its schema's `default`
+  (`ParameterIr.defaultValue`, documented only); envelopes; errors, with
   `errors.default_schema` for statuses without a body; header parameters
   `Accept`, `Content-Type` and `Authorization` are dropped as OpenAPI says;
-  a parameter style its `in` does not allow falls back to the default, and
-  an `in: querystring` parameter is skipped, TOA564) and `IrBuilder`
+  a parameter style its `in` does not allow falls back to the default,
+  TOA564, and an `in: querystring` parameter is skipped, TOA565; path
+  variables are `OperationBuilder.pathVariable`, the runtime's
+  `OperationRequest.pathVariable`, which a test keeps equal) and
+  `IrBuilder`
   (operations written as a `$ref` are skipped (TOA107); groups by tag, path
   or one class, with an override `group` (UpperCamelCase, or a value that
   differs only by case or separators) and TOA553-TOA555; the names of custom
@@ -268,7 +275,9 @@ All under `packages/typed_openapi/lib/src/`, one folder per stage:
   out, else at `#/paths`; then everything above). `IrJson` dumps an IR; the
   hidden `typed_openapi ir` command prints it. Naming and mapping codes use
   the second half of each area's hundred: TOA250-TOA256, TOA350-TOA351,
-  TOA450-TOA456, TOA550-TOA564; `generate` has TOA830 (output not owned),
+  TOA450-TOA456, TOA550-TOA565, and media types and errors TOA650-TOA656
+  (TOA561 became TOA650 and TOA651, TOA562 TOA652, the querystring half of
+  TOA564 TOA565); `generate` has TOA830 (output not owned),
   TOA831 (output not written, or its lock held) and TOA832 (an interrupted
   run recovered, or a lock taken over; info). TOA552 on an enum value is an info (an override cannot name enum
   values; `x-enum-varnames` in the spec does), and `unknown` is reserved in
diff --git a/packages/typed_openapi/CHANGELOG.md b/packages/typed_openapi/CHANGELOG.md
index 90c7a20..622301c 100644
--- a/packages/typed_openapi/CHANGELOG.md
+++ b/packages/typed_openapi/CHANGELOG.md
@@ -158,20 +158,32 @@
   - TOA560 override-name-invalid (warning): an override `name` or `group` is
     not a valid Dart name; the name made from it is used, or the override is
     ignored when nothing is left.
-  - TOA561 media-type-as-bytes (info): a body whose media type is not JSON, a
-    form, `multipart/form-data`, `text/*` or `text/event-stream` is bytes
-    and its schema is not used; also names the media types of an operation
-    that are dropped for the chosen one (variants of the chosen media type
-    and other JSON types are not reported).
-  - TOA562 default-error-schema-missing (warning): `errors.default_schema` is
-    not a key of `components.schemas`; the setting is ignored.
   - TOA563 client-empty (warning): no operation of the client is generated
     (filtered out, written as `$ref`, or an unbound path variable).
   - TOA564 parameter-style-invalid (warning): a parameter `style` that its
     `in` does not allow (path: `simple`, `label`, `matrix`; query: `form`,
     `spaceDelimited`, `pipeDelimited`, `deepObject`; header: `simple`;
-    cookie: `form`, `cookie`) falls back to the default style of the placement; an
-    `in: querystring` parameter (OpenAPI 3.2) is not generated.
+    cookie: `form`, `cookie`) falls back to the default style of the
+    placement; also a form property's `encoding` style.
+  - TOA565 querystring-not-generated (warning): an `in: querystring`
+    parameter (OpenAPI 3.2) is not generated (TOA564 before M9).
+  - TOA650 media-type-as-bytes (info): a body whose media type is not JSON, a
+    form, `multipart/form-data`, `text/*` or `text/event-stream`, or a form
+    or multipart response, is bytes and its schema is not used (TOA561
+    before M9).
+  - TOA651 media-types-dropped (info): the media types of a body, response
+    or parameter that are dropped for the chosen one (variants of the chosen
+    media type and other JSON types are not reported; TOA561 before M9).
+  - TOA652 default-error-schema-missing (warning): `errors.default_schema` is
+    not a key of `components.schemas`; the setting is ignored (TOA562 before
+    M9).
+  - TOA656 encoding-headers-ignored (info): the `headers` of a multipart
+    part's `encoding` are not sent.
+- An `apiKey` security scheme without `in` is TOA112, as one without `name`.
+- Schemas named `Dio` or like the runtime's new names (`FileUpload`,
+  `FormBody`, `MultipartBody`, `SecurityScheme`, ...) get the `Model` suffix
+  (TOA550); `Response`, `Options` and `Headers` keep their names, because the
+  API files import only `Dio` from `package:dio`.
 - An `allOf` parent that an override excludes is still merged into the flat
   child: the exclude only removes the parent's own declaration, and TOA254
   (info) says so.
diff --git a/packages/typed_openapi/README.md b/packages/typed_openapi/README.md
index a16bd3f..5907eb8 100644
--- a/packages/typed_openapi/README.md
+++ b/packages/typed_openapi/README.md
@@ -224,13 +224,13 @@ Other things `check` tells you instead of guessing: a client that generates
 no operation (everything filtered out, written as `$ref`, or with a path
 variable without a parameter) is a warning `TOA563` that says why; a body
 with a media type that is not JSON, a form, text or an event stream is sent
-and read as bytes without its schema (info `TOA561`, which also names the
-other media types of an operation that are dropped); an
+and read as bytes without its schema (info `TOA650`; the other media types
+of an operation that are dropped are info `TOA651`); an
 `errors.default_schema` that is not a key of `components.schemas` is a
-warning `TOA562` and is ignored; a parameter `style` that its `in` does not
+warning `TOA652` and is ignored; a parameter `style` that its `in` does not
 allow (path `form`, query `matrix`, ...) is a warning `TOA564` and the default
-style is used, and an `in: querystring` parameter (OpenAPI 3.2) is `TOA564`
-too and is not generated. Header parameters named `Accept`, `Content-Type`
+style is used, and an `in: querystring` parameter (OpenAPI 3.2) is a warning
+`TOA565` and is not generated. Header parameters named `Accept`, `Content-Type`
 or `Authorization` are not generated, as OpenAPI says to ignore them.
 
 Every finding has a stable code (`TOA011`), a JSON pointer into the spec and,
diff --git a/packages/typed_openapi/README.ua.md b/packages/typed_openapi/README.ua.md
index c397b63..c91d739 100644
--- a/packages/typed_openapi/README.ua.md
+++ b/packages/typed_openapi/README.ua.md
@@ -224,12 +224,12 @@ defaults:
 жодної операції (усе відфільтровано, записано як `$ref` або шлях має
 змінну без параметра), — warning `TOA563` з причиною; тіло з медіатипом, що
 не JSON, не форма, не текст і не потік подій, надсилається і читається як
-байти без своєї схеми (info `TOA561`, який також називає інші медіатипи
-операції, що відкинуто); `errors.default_schema`, якого немає серед ключів
-`components.schemas`, — warning `TOA562`, налаштування ігнорується;
+байти без своєї схеми (info `TOA650`; інші медіатипи операції, що
+відкинуто, — info `TOA651`); `errors.default_schema`, якого немає серед
+ключів `components.schemas`, — warning `TOA652`, налаштування ігнорується;
 `style` параметра, який його `in` не дозволяє (path `form`, query `matrix`,
 ...), — warning `TOA564`, береться style за замовчуванням, а параметр
-`in: querystring` (OpenAPI 3.2) — теж `TOA564` і не генерується. Параметри
+`in: querystring` (OpenAPI 3.2) — warning `TOA565`, він не генерується. Параметри
 заголовків `Accept`, `Content-Type` і `Authorization` не генеруються: OpenAPI
 каже їх ігнорувати.
 
````

- [ ] **Step 7: Verify**

Run from the root:

```bash
dart pub get
dart analyze packages        # No issues found!
```

From `packages/typed_openapi`: `dart format lib test bin` (a second run changes 0 files) and `dart test` (expected `+931: All tests passed!`, the size ratchet `test/quality/size_limits_test.dart` included). From `packages/typed_openapi_runtime`: `dart format lib test` (the same) and `dart test` (expected `+183: All tests passed!`).

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor(typed_openapi): number media type and error codes in 6xx and complete the operation IR

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: IR: the root client, status types, parts, servers and security, named after the models

**Files:**
- Modify: `CLAUDE.md`
- Modify: `packages/typed_openapi/CHANGELOG.md`
- Modify: `packages/typed_openapi/README.md`
- Modify: `packages/typed_openapi/README.ua.md`
- Modify: `packages/typed_openapi/lib/src/check/spec_checker.dart`
- Modify: `packages/typed_openapi/lib/src/config/config_loader.dart`
- Modify: `packages/typed_openapi/lib/src/config/generation_config.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`
- Modify: `packages/typed_openapi/lib/src/ir/api_ir.dart`
- Create: `packages/typed_openapi/lib/src/ir/api_names.dart`
- Modify: `packages/typed_openapi/lib/src/ir/ir.dart`
- Modify: `packages/typed_openapi/lib/src/ir/ir_builder.dart`
- Modify: `packages/typed_openapi/lib/src/ir/operation_builder.dart`
- Create: `packages/typed_openapi/lib/src/ir/operation_checks.dart`
- Create: `packages/typed_openapi/lib/src/ir/parts_builder.dart`
- Create: `packages/typed_openapi/lib/src/ir/security_builder.dart`
- Create: `packages/typed_openapi/test/check/client_runs_test.dart`
- Modify: `packages/typed_openapi/test/check/spec_checker_test.dart`
- Create: `packages/typed_openapi/test/ir/api_names_test.dart`
- Create: `packages/typed_openapi/test/ir/operation_metadata_test.dart`
- Modify: `packages/typed_openapi/test/quality/size_limits_test.dart`

**Interfaces:**
- Consumes: task 2: `api_ir.dart`, `BodyEncoding`, `OperationBuilder.allowedStyles`; M6/M8: `NameScope`, `SchemaMapper.declarations`, `IrContext.report`/`overrideAt`.
- Produces: `ApiNames` (`client`, `root`, `name`, `servers`, `variantOf`); `StatusTypeIr`, `StatusCaseIr`, `RootIr`, `ServerIr`, `ServerVariableIr`, `SecurityKind`, `SecuritySchemeIr`, `SecurityUseIr`, `PartIr`; `OperationIr.security`/`successType`/`errorType`/`partsName`/`withTypes`/`overrideKey`; `GroupIr.field`; `ClientIr.root`; `RequestBodyIr.parts`; `SecurityBuilder`, `PartsBuilder`, `OperationChecks`; `OperationBuilder.streams`/`unbound`; `GenerationConfig.clientClass` (`naming.client`); TOA566-TOA568, TOA653-TOA655.

Everything the emitter names comes from the IR (decision 4 above). `ApiNames.client` names, after the declarations, the groups and the M8 helper types, the root client (`naming.client`, else `<Client>Client`; spec decision 3), the fields of the groups and the servers in the root's member scope, and for each operation the sealed success type when 2xx bodies differ (`CreatePetResponse`, variants `Ok`, `Created`), the sealed error type for `ErrorsByStatus` (`CreatePetError`, `NotFound`, `ClientError`, `Other`, `Status499`; M8 decision 18) and the parts class (`UploadPhotoRequest`). When the operation's own inline body already has the sealed name (`GetPetError` for one inline error body), the plural is used (open question 1); any other change is TOA550/TOA551 with an override of the operation's name. `OperationBuilder` gets collaborators: `SecurityBuilder` (the operation's `security`, else the document's; TOA568), `PartsBuilder` (TOA655 for a schema that is not an object), `OperationChecks` (TOA653, TOA654 skips the operation, TOA566, TOA567). The run key of `SpecChecker` includes the client's name unless `naming.client` is set. The new tests on the run key live in a new file, so `spec_checker_test.dart` (allowlisted) does not grow.

- [ ] **Step 1: Write the failing tests**

**New file** `packages/typed_openapi/test/check/client_runs_test.dart`:

````dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/check/spec_checker.dart';
import 'package:typed_openapi/src/config/config_loader.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/display_paths.dart';

import '../helpers/temp_dir.dart';

const _spec = '''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /lists:
    get:
      operationId: getLists
      tags: [lists]
      responses:
        "200": {description: ok}
''';

List<ClientCheck> _check(String clients) {
  final dir = TempDir();
  dir.write('api.yaml', _spec);
  final path = dir.write('typed_openapi.yaml', clients);
  final bag = DiagnosticBag();
  return SpecChecker(
    bag,
    DisplayPaths(dir.path),
  ).checkClients(ConfigLoader(bag).load(path)!);
}

void main() {
  test('clients whose root client is named after them do not share a run', () {
    final checks = _check('''
clients:
  a: {input: api.yaml, output: lib/a}
  b: {input: api.yaml, output: lib/b}
''');
    expect(identical(checks[0].ir, checks[1].ir), isFalse);
    expect([for (final c in checks) c.ir?.root.name], ['AClient', 'BClient']);
  });

  test('naming.client names the root client of every client it is set for', () {
    final checks = _check('''
defaults: {naming: {client: Api}}
clients:
  a: {input: api.yaml, output: lib/a}
  b: {input: api.yaml, output: lib/b}
''');
    expect(identical(checks[0].ir, checks[1].ir), isTrue);
    expect(checks[0].ir?.root.name, 'Api');
  });
}
````

**New file** `packages/typed_openapi/test/ir/api_names_test.dart`:

````dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/config/config_loader.dart';
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/ir/api_names.dart';
import 'package:typed_openapi/src/ir/ir.dart';
import 'package:typed_openapi/src/ir/ir_builder.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/temp_dir.dart';

ClientIr build(IrFixture fixture) => IrBuilder(
  fixture.diagnostics,
).build(fixture.context.spec, fixture.context.client);

List<Diagnostic> reported(IrFixture fixture, DiagnosticCode code) => [
  for (final d in fixture.reported)
    if (d.code == code) d,
];

OperationIr operation(ClientIr ir, String name) => [
  for (final group in ir.groups)
    for (final operation in group.operations)
      if (operation.name == name) operation,
].single;

List<(String, String, String?)> cases(StatusTypeIr? type, ClientIr ir) => [
  for (final c in type!.cases) (c.status, c.name, c.type?.code(ir.nameOf)),
];

const petstore = r'''
openapi: 3.1.0
info: {title: Pets, version: "1"}
servers:
  - url: https://pets.example.com/v1
paths:
  /pets:
    post:
      operationId: createPet
      tags: [pets]
      requestBody:
        content:
          application/json: {schema: {$ref: '#/components/schemas/Pet'}}
      responses:
        "200": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/Pet'}}}}
        "202": {description: queued, content: {application/json: {schema: {$ref: '#/components/schemas/Job'}}}}
        "404": {description: no, content: {application/json: {schema: {$ref: '#/components/schemas/Problem'}}}}
        "4XX": {description: bad, content: {application/json: {schema: {$ref: '#/components/schemas/Job'}}}}
        "499": {description: odd}
        default: {description: other, content: {application/json: {schema: {$ref: '#/components/schemas/Problem'}}}}
  /pets/{id}:
    get:
      operationId: getPet
      tags: [pets]
      parameters: [{name: id, in: path, required: true, schema: {type: integer}}]
      responses:
        "200": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/Pet'}}}}
        "201": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/Pet'}}}}
        "404": {description: no, content: {application/json: {schema: {$ref: '#/components/schemas/Problem'}}}}
components:
  schemas:
    Pet: {type: object, properties: {name: {type: string}}}
    Job: {type: object, properties: {id: {type: string}}}
    Problem: {type: object, properties: {code: {type: string}}}
''';

void main() {
  test('a status variant is named by the HTTP reason phrase', () {
    expect(
      [
        for (final status in [
          '200', '201', '204', '404', '422', '413', '4XX', '5xx', '2XX', //
          '1XX', 'default', '499', '299', '6XX',
        ])
          ApiNames.variantOf(status),
      ],
      [
        'Ok', 'Created', 'NoContent', 'NotFound', 'UnprocessableEntity', //
        'PayloadTooLarge', 'ClientError', 'ServerError', 'Success',
        'Informational', 'Other', 'Status499', 'Status299', 'Status6XX',
      ],
    );
  });

  test(
    'statuses with different bodies get sealed types; equal ones do not',
    () {
      final fixture = IrFixture(petstore);
      final ir = build(fixture);
      expect(fixture.reported, isEmpty);
      final create = operation(ir, 'createPet');
      expect(create.successType?.name, 'CreatePetResponse');
      expect(cases(create.successType, ir), [
        ('200', 'CreatePetResponseOk', 'Pet'),
        ('202', 'CreatePetResponseAccepted', 'Job'),
      ]);
      expect(create.errorType?.name, 'CreatePetError');
      expect(cases(create.errorType, ir), [
        ('404', 'CreatePetErrorNotFound', 'Problem'),
        ('4XX', 'CreatePetErrorClientError', 'Job'),
        ('499', 'CreatePetErrorStatus499', null),
        ('default', 'CreatePetErrorOther', 'Problem'),
      ]);
      final get = operation(ir, 'getPet');
      expect(get.successType, isNull);
      expect(get.errorType, isNull);
      expect(ir.root.name, 'ApiClient');
      expect(
        [for (final g in ir.groups) (g.name, g.field)],
        [
          ('PetsApi', 'pets'),
        ],
      );
      expect(
        [for (final s in ir.root.servers) (s.name, s.url, s.variables.length)],
        [('server', 'https://pets.example.com/v1', 0)],
      );
    },
  );

  test('the names are claimed after the models, which never move', () {
    // Models named like these types, reached from a property of Job.
    final fixture = IrFixture(
      petstore.replaceFirst(
        '    Job: {type: object, properties: {id: {type: string}}}',
        r'''
    Job:
      type: object
      properties:
        a: {$ref: '#/components/schemas/CreatePetError'}
        b: {$ref: '#/components/schemas/CreatePetErrors'}
        c: {$ref: '#/components/schemas/CreatePetResponse'}
        d: {$ref: '#/components/schemas/ApiClient'}
    CreatePetError: {type: object, properties: {a: {type: string}}}
    CreatePetErrors: {type: object, properties: {a: {type: string}}}
    CreatePetResponse: {type: object, properties: {a: {type: string}}}
    ApiClient: {type: object, properties: {a: {type: string}}}''',
      ),
    );
    final ir = build(fixture);
    expect(
      [for (final d in ir.declarations) d.name],
      containsAll([
        'ApiClient',
        'CreatePetError',
        'CreatePetErrors',
        'CreatePetResponse',
      ]),
    );
    expect(ir.root.name, 'ApiClient2');
    final create = operation(ir, 'createPet');
    expect(create.successType?.name, 'CreatePetResponses');
    expect(create.errorType?.name, 'CreatePetError2');
    expect(create.errorType?.cases.first.name, 'CreatePetError2NotFound');
    final collisions = reported(fixture, .nameCollision);
    expect(collisions.map((d) => d.message), [
      contains('the root client is named "ApiClient2"'),
      contains(
        'the sealed type of the errors of createPet is named '
        '"CreatePetError2"',
      ),
    ]);
    expect(collisions.last.fix, contains('operations:'));
    expect(collisions.last.severity, Severity.info);
  });

  test('an inline body named like the sealed type gives the plural', () {
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: getPet
      tags: [pets]
      responses:
        "200": {description: ok, content: {application/json: {schema: {type: object, properties: {a: {type: string}}}}}}
        "204": {description: none}
        "404": {description: no, content: {application/json: {schema: {type: object, properties: {b: {type: string}}}}}}
        "500": {description: down}
''');
    final ir = build(fixture);
    expect(fixture.reported, isEmpty);
    final get = operation(ir, 'getPet');
    expect(get.successType?.name, 'GetPetResponses');
    expect(cases(get.successType, ir), [
      ('200', 'GetPetResponsesOk', 'GetPetResponse'),
      ('204', 'GetPetResponsesNoContent', null),
    ]);
    expect(get.errorType?.name, 'GetPetErrors');
  });

  test('naming.client names the root client', () {
    final ir = build(
      IrFixture(
        petstore,
        generation: const GenerationConfig(clientClass: 'PetStore'),
      ),
    );
    expect(ir.root.name, 'PetStore');
  });

  test('naming.client must be a class name', () {
    final dir = TempDir();
    final path = dir.write('typed_openapi.yaml', '''
clients:
  a: {input: a.yaml, output: lib/a, naming: {client: Shop}}
  b: {input: a.yaml, output: lib/b, naming: {client: class}}
  c: {input: a.yaml, output: lib/c, naming: {client: shop}}
''');
    final bag = DiagnosticBag();
    final config = ConfigLoader(bag).load(path)!;
    expect(
      [for (final c in config.clients) c.generation.clientClass],
      [
        'Shop',
        null,
        null,
      ],
    );
    expect(bag.all.map((d) => (d.code, d.pointer?.value)), [
      (DiagnosticCode.configInvalid, '#/clients/b/naming/client'),
      (DiagnosticCode.configInvalid, '#/clients/c/naming/client'),
    ]);
  });

  test('group fields and servers are members of the root client', () {
    final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
servers:
  - url: https://{region}.example.com/{class}
    description: Production
    variables:
      region: {default: eu, enum: [eu, us], description: Where.}
      class: {default: v1}
  - url: /local
paths:
  /a:
    get:
      operationId: a
      tags: [class]
      responses: {"200": {description: ok}}
  /b:
    get:
      operationId: b
      responses: {"200": {description: ok}}
  /c:
    get:
      operationId: c
      tags: [hash code]
      responses: {"200": {description: ok}}
''');
    final ir = build(fixture);
    expect(
      [for (final g in ir.groups) (g.name, g.field)],
      [
        ('ClassApi', 'class_'),
        ('DefaultApi', 'defaultApi'),
        ('HashCodeApi', 'hashCode_'),
      ],
    );
    final [production, local] = ir.root.servers;
    expect(production.name, 'server1');
    expect(production.description, 'Production');
    expect(
      [
        for (final v in production.variables)
          (v.name, v.wireName, v.defaultValue, v.values.join('|')),
      ],
      [('region', 'region', 'eu', 'eu|us'), ('class_', 'class', 'v1', '')],
    );
    expect((local.name, local.url), ('server2', '/local'));
  });

  test('the names are the same on every build', () {
    String names(ClientIr ir) => [
      ir.root.name,
      for (final g in ir.groups)
        for (final o in g.operations) ...[
          ?o.successType?.name,
          ?o.errorType?.name,
          for (final c in [...?o.successType?.cases, ...?o.errorType?.cases])
            c.name,
        ],
    ].join(',');
    expect(
      names(build(IrFixture(petstore))),
      names(build(IrFixture(petstore))),
    );
  });
}
````

**New file** `packages/typed_openapi/test/ir/operation_metadata_test.dart`:

````dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/ir/dart_type.dart';
import 'package:typed_openapi/src/ir/ir.dart';
import 'package:typed_openapi/src/ir/ir_builder.dart';

import '../helpers/ir_fixture.dart';

ClientIr build(IrFixture fixture) => IrBuilder(
  fixture.diagnostics,
).build(fixture.context.spec, fixture.context.client);

List<Diagnostic> reported(IrFixture fixture, DiagnosticCode code) => [
  for (final d in fixture.reported)
    if (d.code == code) d,
];

OperationIr operation(ClientIr ir, String name) => [
  for (final group in ir.groups)
    for (final operation in group.operations)
      if (operation.name == name) operation,
].single;

void main() {
  group('security metadata (R10.8)', () {
    const spec = '''
openapi: 3.1.0
info: {title: t, version: "1"}
security: [{bearer: []}]
paths:
  /inherit:
    get:
      operationId: inherit
      tags: [t]
      responses: {"200": {description: ok}}
  /own:
    get:
      operationId: own
      tags: [t]
      security: [{oauth: [read, write], key: []}, {}]
      responses: {"200": {description: ok}}
  /none:
    get:
      operationId: none
      tags: [t]
      security: []
      responses: {"200": {description: ok}}
  /unknown:
    get:
      operationId: unknown
      tags: [t]
      security: [{nope: []}]
      responses: {"200": {description: ok}}
components:
  securitySchemes:
    bearer: {type: http, scheme: Bearer, bearerFormat: JWT}
    key: {type: apiKey, name: X-Key, in: header}
    oauth:
      type: oauth2
      flows: {clientCredentials: {tokenUrl: https://a.example/token, scopes: {}}}
''';

    List<List<String>> uses(ClientIr ir, String name) => [
      for (final alternative in operation(ir, name).security)
        [
          for (final use in alternative)
            '${use.scheme.name}:${use.scheme.kind.name}:'
                '${use.scopes.join(',')}',
        ],
    ];

    test('an operation has its own requirements or the document\'s', () {
      final fixture = IrFixture(spec);
      final ir = build(fixture);
      expect(uses(ir, 'inherit'), [
        ['bearer:http:'],
      ]);
      expect(uses(ir, 'own'), [
        ['oauth:oauth2:read,write', 'key:apiKey:'],
        <String>[],
      ]);
      expect(uses(ir, 'none'), isEmpty);
      final bearer = operation(ir, 'inherit').security.single.single.scheme;
      expect((bearer.scheme, bearer.bearerFormat), ('bearer', 'JWT'));
      final key = operation(ir, 'own').security.first.last.scheme;
      expect((key.parameterName, key.placement), ('X-Key', 'header'));
      final unknown = reported(fixture, .securitySchemeUnknown).single;
      expect(unknown.pointer?.value, '#/paths/~1unknown/get/security/0');
      expect(uses(ir, 'unknown'), [<String>[]]);
      expect(fixture.reported, hasLength(1));
    });
  });

  group('what the client does not generate', () {
    test('servers of a path item or an operation are reported (TOA566)', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    servers: [{url: https://a.example.com}]
    get:
      operationId: a
      tags: [t]
      servers: [{url: https://b.example.com}]
      responses: {"200": {description: ok}}
    post:
      operationId: b
      tags: [t]
      responses: {"200": {description: ok}}
''');
      build(fixture);
      expect(
        reported(
          fixture,
          .operationServersIgnored,
        ).map((d) => d.pointer?.value),
        ['#/paths/~1a/servers', '#/paths/~1a/get/servers'],
      );
    });

    test('callbacks and webhooks are reported (TOA567)', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    post:
      operationId: subscribe
      tags: [t]
      callbacks:
        onEvent:
          '{$request.body#/url}':
            post: {responses: {"200": {description: ok}}}
      responses: {"200": {description: ok}}
webhooks:
  newPet:
    post: {responses: {"200": {description: ok}}}
''');
      build(fixture);
      final found = reported(fixture, .callbacksNotGenerated);
      expect(found.map((d) => d.pointer?.value), [
        '#/paths/~1a/post/callbacks',
        '#/webhooks',
      ]);
      expect(found.first.message, contains('onEvent'));
      expect(found.last.message, contains('newPet'));
      expect(found.first.severity, Severity.info);
    });

    test('an operation without a 2xx response is reported (TOA653)', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: a
      tags: [t]
      responses:
        default: {description: any, content: {application/json: {schema: {type: object, properties: {a: {type: string}}}}}}
''');
      final ir = build(fixture);
      expect(operation(ir, 'a').successes, isEmpty);
      expect(
        reported(fixture, .successUndocumented).single.pointer?.value,
        '#/paths/~1a/get/responses',
      );
    });

    test('an event stream is generated from M10 (TOA654)', () {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    get:
      operationId: watch
      tags: [t]
      responses:
        "200": {description: ok, content: {text/event-stream: {schema: {type: string}}}}
''');
      final ir = build(fixture);
      expect(ir.groups, isEmpty);
      expect(
        reported(fixture, .eventStreamNotGenerated).single.pointer?.value,
        '#/paths/~1a/get/responses/200',
      );
      expect(
        reported(fixture, .clientEmpty).single.message,
        contains('1 is an event stream, generated from M10 (TOA654)'),
      );
    });
  });

  group('multipart parts', () {
    test('the properties of an object are the parts; files are binary', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    post:
      operationId: upload
      tags: [t]
      requestBody:
        content:
          multipart/form-data:
            schema: {$ref: '#/components/schemas/Upload'}
            encoding: {file: {contentType: image/png}}
      responses: {"204": {description: ok}}
components:
  schemas:
    Upload:
      type: object
      required: [file]
      properties:
        file: {type: string, format: binary, description: The image.}
        files: {type: array, items: {type: string, format: binary}}
        class: {type: string}
        toParts: {type: integer}
        id: {type: string, readOnly: true}
        meta: {type: object, properties: {a: {type: string}}}
''');
      final ir = build(fixture);
      expect(fixture.reported, isEmpty);
      final upload = operation(ir, 'upload');
      expect(upload.partsName, 'UploadRequest');
      expect(upload.body?.type, isNull);
      expect(
        [
          for (final p in upload.body!.parts!)
            (
              p.name,
              p.wireName,
              p.type.code(ir.nameOf),
              p.required,
              p.contentType,
            ),
        ],
        [
          ('file', 'file', 'Uint8List', true, 'image/png'),
          ('files', 'files', 'List<Uint8List>?', false, null),
          ('class_', 'class', 'String?', false, null),
          ('toParts_', 'toParts', 'int?', false, null),
          ('meta', 'meta', 'UploadRequestMeta?', false, null),
        ],
      );
      expect(upload.body!.parts!.first.description, 'The image.');
      // The schema itself is not a model: its parts are.
      expect([for (final d in ir.declarations) d.name], ['UploadRequestMeta']);
    });

    test('another schema has no parts (TOA655)', () {
      final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /a:
    post:
      operationId: upload
      tags: [t]
      requestBody:
        content:
          multipart/form-data:
            schema:
              oneOf: [{$ref: '#/components/schemas/A'}, {type: string}]
      responses: {"204": {description: ok}}
components:
  schemas:
    A: {type: object, properties: {a: {type: string}}}
''');
      final ir = build(fixture);
      final upload = operation(ir, 'upload');
      expect(upload.body?.parts, isNull);
      expect(upload.partsName, isNull);
      expect(upload.body?.type, isA<NamedType>());
      expect(
        reported(fixture, .multipartNotObject).single.pointer?.value,
        '#/paths/~1a/post/requestBody/content/multipart~1form-data/schema',
      );
    });
  });
}
````

**Diff** (apply from the repository root with `git apply`):

````diff
diff --git a/packages/typed_openapi/test/check/spec_checker_test.dart b/packages/typed_openapi/test/check/spec_checker_test.dart
index 874c7b3..13720b0 100644
--- a/packages/typed_openapi/test/check/spec_checker_test.dart
+++ b/packages/typed_openapi/test/check/spec_checker_test.dart
@@ -677,8 +677,8 @@ paths:
     test('clients with identical settings share one run', () {
       final checks = check('''
 clients:
-  a: {input: api.yaml, output: lib/a}
-  b: {input: api.yaml, output: lib/b}
+  a: {input: api.yaml, output: lib/a, naming: {client: Api}}
+  b: {input: api.yaml, output: lib/b, naming: {client: Api}}
 ''');
       expect(identical(checks[0].ir, checks[1].ir), isTrue);
     });
````

- [ ] **Step 2: Run the tests to see them fail**

Run from `packages/typed_openapi`: `dart test test/ir/api_names_test.dart test/ir/operation_metadata_test.dart test/check`.
Expected: FAIL to load: `ApiNames`, `StatusTypeIr`, `GenerationConfig.clientClass`, `ClientIr.root` and the new `DiagnosticCode` values are not defined.

- [ ] **Step 3: Implement**

**New file** `packages/typed_openapi/lib/src/ir/api_names.dart`:

````dart
import '../diagnostics/json_pointer.dart';
import '../model/operation.dart';
import '../model/spec_node.dart';
import 'dart_type.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'names.dart';

/// Names the types the API emitter declares (M9) in the library scope, after
/// the declarations, the groups and the types M8 adds, so that a model or
/// a group is never renamed by them: the root client, then for each
/// operation (groups and operations by name) the sealed type of its
/// successes and its variants, the sealed type of its errors and its
/// variants, and the class of its multipart parts. A sealed type is
/// `<Operation>Response` or `<Operation>Error`, or the plural when an
/// inline body has that name; any other change is reported (TOA550,
/// TOA551).
final class ApiNames {
  /// Creates the namer for [_context], claiming in the library scope
  /// [_types].
  ApiNames(this._context, this._types);

  static const _names = DartNames();

  /// The HTTP reason phrases of the statuses with a registered meaning, as
  /// variant names (RFC 9110 and the earlier names it renamed, such as
  /// `UnprocessableEntity`).
  static const reasons = {
    100: 'Continue', 101: 'SwitchingProtocols', 102: 'Processing', //
    103: 'EarlyHints', 200: 'Ok', 201: 'Created', 202: 'Accepted',
    203: 'NonAuthoritativeInformation', 204: 'NoContent',
    205: 'ResetContent', 206: 'PartialContent', 207: 'MultiStatus',
    208: 'AlreadyReported', 226: 'ImUsed', 300: 'MultipleChoices',
    301: 'MovedPermanently', 302: 'Found', 303: 'SeeOther',
    304: 'NotModified', 305: 'UseProxy', 307: 'TemporaryRedirect',
    308: 'PermanentRedirect', 400: 'BadRequest', 401: 'Unauthorized',
    402: 'PaymentRequired', 403: 'Forbidden', 404: 'NotFound',
    405: 'MethodNotAllowed', 406: 'NotAcceptable',
    407: 'ProxyAuthenticationRequired', 408: 'RequestTimeout',
    409: 'Conflict', 410: 'Gone', 411: 'LengthRequired',
    412: 'PreconditionFailed', 413: 'PayloadTooLarge', 414: 'UriTooLong',
    415: 'UnsupportedMediaType', 416: 'RangeNotSatisfiable',
    417: 'ExpectationFailed', 421: 'MisdirectedRequest',
    422: 'UnprocessableEntity', 423: 'Locked', 424: 'FailedDependency',
    425: 'TooEarly', 426: 'UpgradeRequired', 428: 'PreconditionRequired',
    429: 'TooManyRequests', 431: 'RequestHeaderFieldsTooLarge',
    451: 'UnavailableForLegalReasons', 500: 'InternalServerError',
    501: 'NotImplemented', 502: 'BadGateway', 503: 'ServiceUnavailable',
    504: 'GatewayTimeout', 505: 'HttpVersionNotSupported',
    506: 'VariantAlsoNegotiates', 507: 'InsufficientStorage',
    508: 'LoopDetected', 510: 'NotExtended',
    511: 'NetworkAuthenticationRequired',
  };

  /// The names of status ranges.
  static const ranges = {
    '1': 'Informational', '2': 'Success', '3': 'Redirection', //
    '4': 'ClientError', '5': 'ServerError',
  };

  final IrContext _context;
  final NameScope _types;

  /// The variant name of [status]: the reason phrase of a code, the name of
  /// a range (`4XX` is `ClientError`), `Other` for `default`, and `Status`
  /// with the code for a code without a registered meaning (`Status499`).
  static String variantOf(String status) {
    if (status == 'default') return 'Other';
    final code = int.tryParse(status);
    if (code != null) return reasons[code] ?? 'Status$status';
    if (status.length == 3 && status.substring(1).toUpperCase() == 'XX') {
      final range = ranges[status[0]];
      if (range != null) return range;
    }
    return 'Status${status.toUpperCase().replaceAll(_notAlphanumeric, '')}';
  }

  static final _notAlphanumeric = RegExp('[^0-9A-Z]');

  /// The IR of the client: [declarations] and the groups by their word
  /// ([groups], the tag or path segment in UpperCamelCase, `''` for the
  /// default group), with the root client, the fields of the groups in it
  /// and the servers, and the types of every operation named.
  ClientIr client(
    List<Declaration> declarations,
    Map<String, GroupIr> groups,
  ) {
    final root = this.root();
    // The root client's members: a field per group, then the servers.
    final members = NameScope(
      reserved: {...DartNames.reservedWords, ...DartNames.objectMembers},
      reservedSuffix: '_',
    );
    final defaultGroup = _context.config.defaultGroup;
    return ClientIr(
      declarations: declarations,
      groups: [
        for (final MapEntry(key: word, value: group) in groups.entries)
          GroupIr(
            group.name,
            [for (final operation in group.operations) name(operation)],
            field: members
                .claim(
                  _names.camel(word.isEmpty ? defaultGroup : word) ?? 'api',
                )
                .$1,
          ),
      ],
      root: RootIr(root, servers: servers(members)),
    );
  }

  /// The root client class: `naming.client`, else the client's name in
  /// UpperCamelCase with `Client`.
  String root() {
    final candidate =
        _context.config.clientClass ??
        '${_names.pascal(_context.client.name) ?? 'Api'}Client';
    return _claim(
      candidate,
      'the root client',
      SpecLocation(
        _context.model.document.location.document,
        JsonPointer.root,
      ),
      fix: 'Set naming.client in the config.',
    );
  }

  /// [operation] with the names of the types the emitter declares for it.
  OperationIr name(OperationIr operation) {
    final prefix = _names.pascal(operation.name) ?? 'Operation';
    final bodies = {for (final s in operation.successes) s.type};
    final successType = bodies.length > 1
        ? _statusType(operation, '${prefix}Response', [
            for (final s in operation.successes) (s.status, s.type),
          ], 'successes')
        : null;
    final errorType = switch (operation.errors) {
      ErrorsByStatus(:final cases) => _statusType(
        operation,
        '${prefix}Error',
        cases,
        'errors',
      ),
      _ => null,
    };
    final partsName = operation.body?.parts == null
        ? null
        : _claim(
            '${prefix}Request',
            'the class of the parts of ${operation.name}',
            operation.location,
            override: operation,
          );
    return operation.withTypes(
      successType: successType,
      errorType: errorType,
      partsName: partsName,
    );
  }

  StatusTypeIr _statusType(
    OperationIr operation,
    String candidate,
    List<(String, DartType?)> cases,
    String what,
  ) {
    // The one body of the operation's successes or errors may have the
    // name already (an inline schema of one 2xx or one error response is
    // `GetPetResponse` or `GetPetError`): the plural is the documented
    // second choice.
    final plural = '${candidate}s';
    final name = _claim(
      _types.isTaken(candidate) && !_types.isTaken(plural) ? plural : candidate,
      'the sealed type of the $what of ${operation.name}',
      operation.location,
      override: operation,
    );
    return StatusTypeIr(name, [
      for (final (status, type) in cases)
        StatusCaseIr(
          status,
          _claim(
            '$name${variantOf(status)}',
            'the variant of $status',
            operation.location,
            override: operation,
          ),
          type,
        ),
    ]);
  }

  /// Claims [candidate] for [what] in the library scope; a name that
  /// differs is reported at [at], with an override of the operation's name
  /// when [override] is given.
  String _claim(
    String candidate,
    String what,
    SpecLocation at, {
    OperationIr? override,
    String? fix,
  }) {
    final (name, change) = _types.claim(candidate);
    if (change == null) return name;
    _context.report(
      change == .reserved ? .nameReserved : .nameCollision,
      change == .reserved
          ? '"$candidate" is a name Dart already has; $what is named "$name".'
          : 'Another type is named "$candidate"; $what is named "$name".',
      at,
      fix:
          fix ??
          'Rename the other type, or name the operation explicitly: its '
              'name starts the name of the type.',
      override: override == null
          ? null
          : _context.overrideAt(
              ['operations', override.overrideKey],
              {'name': override.name},
            ),
    );
    return name;
  }

  /// The servers of the document as members of the root client, claimed
  /// in [members] after the group fields: `server` for one, `server1`,
  /// `server2`, ... for several.
  List<ServerIr> servers(NameScope members) {
    final servers = _context.model.document.servers;
    return [
      for (final (i, server) in servers.indexed)
        if (server.url case final url?)
          ServerIr(
            name: members
                .claim(servers.length == 1 ? 'server' : 'server${i + 1}')
                .$1,
            url: url,
            location: server.location,
            description: server.description,
            variables: _serverVariables(server.variables),
          ),
    ];
  }

  static List<ServerVariableIr> _serverVariables(
    Map<String, ServerVariable> variables,
  ) {
    final scope = NameScope(
      reserved: DartNames.reservedWords,
      reservedSuffix: '_',
    );
    return [
      for (final MapEntry(key: wire, :value) in variables.entries)
        ServerVariableIr(
          name: scope.claim(_names.camel(wire) ?? 'value').$1,
          wireName: wire,
          defaultValue: value.defaultValue,
          values: value.enumValues ?? const [],
          description: value.description,
        ),
    ];
  }
}
````

**New file** `packages/typed_openapi/lib/src/ir/operation_checks.dart`:

````dart
import '../diagnostics/json_pointer.dart';
import '../model/operation.dart';
import '../model/spec_node.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'operation_builder.dart';

/// Reports what an operation has that the client does not generate (M9):
/// event streams (until M10), a missing 2xx, servers of a path item or an
/// operation, callbacks and the document's webhooks.
final class OperationChecks {
  /// Creates the checks; they report through [_context].
  const OperationChecks(this._context);

  final IrContext _context;

  /// Whether a success of [responses] is an event stream, which is
  /// reported (TOA654): such an operation is generated from M10.
  bool isEventStream(List<ResponseIr> responses) {
    final stream = responses
        .where((r) => r.isSuccess && r.kind == .eventStream)
        .firstOrNull;
    if (stream == null) return false;
    _context.report(
      .eventStreamNotGenerated,
      'The ${stream.status} response is "${stream.contentType}": event '
      'streams are generated from M10, so the operation is not generated.',
      stream.location,
      fix: 'Leave it out with exclude until then.',
    );
    return true;
  }

  /// Reports an operation without a 2xx response (TOA653); a 2xx response
  /// that cannot be resolved is reported already.
  void successes(Operation operation) {
    if (operation.responses.keys.any((status) => status.startsWith('2'))) {
      return;
    }
    _context.report(
      .successUndocumented,
      'No 2xx response is documented, so any 2xx is a success whose value '
      'is the body as JsonValue.',
      operation.location.child('responses'),
      fix: 'Document the success response at the source.',
    );
  }

  /// Reports `servers` of the path item and of the operation (TOA566): the
  /// client sends every request to the Dio base URL.
  void servers(SpecOperation entry) {
    for (final (node, servers, what) in [
      (entry.item, entry.item.servers, 'path item'),
      (entry.operation, entry.operation.servers, 'operation'),
    ]) {
      if (servers.isEmpty) continue;
      _context.report(
        .operationServersIgnored,
        'The $what has servers of its own; the client sends its requests to '
        'the base URL of your Dio.',
        node.location.child('servers'),
        fix:
            'Set the base URL for these requests in an interceptor, or move '
            'the servers to the document.',
      );
    }
  }

  /// Reports `callbacks` (TOA567): requests the server makes.
  void callbacks(Operation operation) {
    final at = operation.location.child('callbacks');
    final value = _context.documents[at.document]?.valueAt(at.pointer);
    if (value case (
      final Map<String, Object?> callbacks,
    ) when callbacks.isNotEmpty) {
      _context.report(
        .callbacksNotGenerated,
        'The operation has callbacks (${callbacks.keys.join(', ')}): requests '
        'the server makes, which the client does not generate.',
        at,
      );
    }
  }

  /// Reports the document's `webhooks` (TOA567): requests the server
  /// makes, which the client does not generate.
  void webhooks() {
    final webhooks = _context.model.document.webhooks;
    if (webhooks.isEmpty) return;
    _context.report(
      .callbacksNotGenerated,
      'The document has webhooks (${webhooks.keys.join(', ')}): requests the '
      'server makes, which the client does not generate.',
      SpecLocation(
        _context.model.document.location.document,
        JsonPointer.root.child('webhooks'),
      ),
    );
  }
}
````

**New file** `packages/typed_openapi/lib/src/ir/parts_builder.dart`:

````dart
import '../model/operation.dart';
import '../model/schema.dart';
import 'dart_type.dart';
import 'ir.dart';
import 'ir_context.dart';
import 'names.dart';
import 'schema_mapper.dart';

/// Builds the parts of a multipart body (R10.4) whose schema is an object:
/// a part per property, each mapped as a request type.
final class PartsBuilder {
  /// Creates the builder; it maps types with [_mapper].
  const PartsBuilder(this._context, this._mapper);

  static const _names = DartNames();

  final IrContext _context;
  final SchemaMapper _mapper;

  /// The parts of a multipart body whose [schema] is an object with
  /// properties, each mapped as a request type; read-only properties are
  /// left out. Another schema is reported (TOA655) and gives null.
  List<PartIr>? of(Schema schema, MediaType media, String prefix) {
    final resolved = _context.model.resolveSchema(schema);
    if (resolved is! SchemaObject || !_hasParts(resolved)) {
      _context.report(
        .multipartNotObject,
        'The multipart body is not an object with properties, so it has no '
        'class of parts: each property of its JSON is sent as a part, and '
        'binary strings as base64 text.',
        schema.location,
        fix:
            'Describe the body as an object with a property for each part at '
            'the source.',
      );
      return null;
    }
    final scope = NameScope(
      reserved: {
        ...DartNames.reservedWords,
        ...DartNames.objectMembers,
        ...DartNames.lowercaseTypes,
        'toParts',
      },
      reservedSuffix: '_',
    );
    return [
      for (final MapEntry(key: wire, value: property)
          in resolved.properties.entries)
        if (!_isReadOnly(property))
          PartIr(
            name: scope.claim(_names.camel(wire) ?? 'part').$1,
            wireName: wire,
            type: _partType(property, prefix, wire, resolved),
            location: property.location,
            required: resolved.required.contains(wire),
            contentType: media.encoding[wire]?.contentType,
            description: _description(property),
          ),
    ];
  }

  /// Whether [schema] is a plain object with properties.
  static bool _hasParts(SchemaObject schema) =>
      schema.properties.isNotEmpty &&
      schema.allOf.isEmpty &&
      schema.oneOf.isEmpty &&
      schema.anyOf.isEmpty &&
      schema.types.every((t) => t == .object || t == .nullType);

  DartType _partType(
    Schema property,
    String prefix,
    String wire,
    SchemaObject parent,
  ) {
    final type = _mapper.typeOf(
      property,
      NameHint(prefix, 'Request${_names.pascal(wire) ?? ''}'),
      direction: .request,
    );
    return parent.required.contains(wire) ? type : type.withNullable(true);
  }

  String? _description(Schema property) =>
      switch (_context.model.resolveSchema(property)) {
        final SchemaObject target => target.description,
        _ => null,
      };

  bool _isReadOnly(Schema property) =>
      switch (_context.model.resolveSchema(property)) {
        final SchemaObject target => target.readOnly,
        _ => false,
      };
}
````

**New file** `packages/typed_openapi/lib/src/ir/security_builder.dart`:

````dart
import '../model/operation.dart';
import '../model/security.dart';
import '../model/spec_node.dart';
import 'ir.dart';
import 'ir_context.dart';

/// Reads the security requirements of an operation (R10.8) with the schemes
/// they name, as metadata for interceptors.
final class SecurityBuilder {
  /// Creates the builder; it reports through [_context].
  const SecurityBuilder(this._context);

  final IrContext _context;

  /// The security requirements of [operation]: its own, else the
  /// document's. A scheme `components.securitySchemes` does not have is
  /// reported (TOA568) and left out.
  List<List<SecurityUseIr>> of(Operation operation) {
    final requirements =
        operation.security ?? _context.model.document.security ?? const [];
    final schemes = _context.model.document.components?.securitySchemes;
    return [
      for (final requirement in requirements)
        [
          for (final MapEntry(key: name, value: scopes)
              in requirement.schemes.entries)
            if (_scheme(name, schemes, requirement.location) case final s?)
              SecurityUseIr(s, scopes),
        ],
    ];
  }

  SecuritySchemeIr? _scheme(
    String name,
    Map<String, RefOr<SecurityScheme>>? schemes,
    SpecLocation at,
  ) {
    final written = schemes?[name];
    final scheme = written == null ? null : _context.model.resolve(written);
    final type = scheme?.type;
    if (scheme == null || type == null) {
      _context.report(
        .securitySchemeUnknown,
        'The security requirement names "$name", which '
        'components.securitySchemes does not define; it is left out of the '
        'metadata.',
        at,
        fix: 'Define the scheme at the source, or fix its name.',
      );
      return null;
    }
    return SecuritySchemeIr(
      name,
      switch (type) {
        .apiKey => .apiKey,
        .http => .http,
        .mutualTLS => .mutualTls,
        .oauth2 => .oauth2,
        .openIdConnect => .openIdConnect,
      },
      parameterName: type == .apiKey ? scheme.name : null,
      placement: type == .apiKey ? scheme.placement?.name : null,
      scheme: type == .http ? scheme.scheme?.toLowerCase() : null,
      bearerFormat: type == .http ? scheme.bearerFormat : null,
      openIdConnectUrl: type == .openIdConnect ? scheme.openIdConnectUrl : null,
    );
  }
}
````

**Diff** (apply from the repository root with `git apply`):

````diff
diff --git a/packages/typed_openapi/lib/src/check/spec_checker.dart b/packages/typed_openapi/lib/src/check/spec_checker.dart
index 6bdd03a..1df9085 100644
--- a/packages/typed_openapi/lib/src/check/spec_checker.dart
+++ b/packages/typed_openapi/lib/src/check/spec_checker.dart
@@ -199,7 +199,10 @@ final class SpecChecker {
   }) {
     // A run is a file with a preset, a set of disabled rules, overrides and
     // generation settings.
-    final runs = <(String, Preset?, String, String?, String), ClientCheck>{};
+    // The root client is named after the client unless naming.client
+    // names it, so the name is part of the run.
+    final runs =
+        <(String, Preset?, String, String?, String, String?), ClientCheck>{};
     return [
       for (final client in config.clients)
         if (only.isEmpty || only.contains(client.name))
@@ -211,6 +214,7 @@ final class SpecChecker {
               (client.disabledRules.toList()..sort()).join(','),
               client.overrides,
               client.generation.key,
+              client.generation.clientClass == null ? client.name : null,
             )] ??= _run(
               client,
             ),
diff --git a/packages/typed_openapi/lib/src/config/config_loader.dart b/packages/typed_openapi/lib/src/config/config_loader.dart
index 3554a27..6b8d330 100644
--- a/packages/typed_openapi/lib/src/config/config_loader.dart
+++ b/packages/typed_openapi/lib/src/config/config_loader.dart
@@ -494,6 +494,7 @@ final class _GenerationReader {
   _GenerationReader(this._reader, this._sources);
 
   static const _namingKeys = {
+    'client',
     'group',
     'default_group',
     'input_suffix',
@@ -531,6 +532,7 @@ final class _GenerationReader {
       inputSuffix: suffixes.$1,
       patchSuffix: suffixes.$2,
       operationPrefix: _pattern(),
+      clientClass: _clientClass(),
       groupBy: _choice('group_by', GroupBy.values) ?? .tag,
       include: _filter('include'),
       exclude: _filter('exclude'),
@@ -611,6 +613,22 @@ final class _GenerationReader {
     );
   }
 
+  /// `client` is the name of a class, as `default_group` is.
+  String? _clientClass() {
+    final name = _identifierAt('client');
+    if (name == null) return null;
+    if (!DartNames.reservedWords.contains(name) &&
+        !DartNames.builtInIdentifiers.contains(name) &&
+        name.startsWith(RegExp(r'[A-Z$]'))) {
+      return name;
+    }
+    return _invalid(
+      '"client" is the name of a class: an identifier that starts with an '
+      'uppercase letter and is not a reserved word in Dart.',
+      _pick('client', 'naming')!.$2,
+    );
+  }
+
   /// `input_suffix` and `patch_suffix`: two model names made from one schema
   /// must differ, so equal suffixes are an error, reported at the later
   /// key, and both go back to their defaults.
diff --git a/packages/typed_openapi/lib/src/config/generation_config.dart b/packages/typed_openapi/lib/src/config/generation_config.dart
index d56e510..17becaf 100644
--- a/packages/typed_openapi/lib/src/config/generation_config.dart
+++ b/packages/typed_openapi/lib/src/config/generation_config.dart
@@ -87,6 +87,7 @@ final class GenerationConfig {
     this.inputSuffix = defaultInputSuffix,
     this.patchSuffix = defaultPatchSuffix,
     this.operationPrefix,
+    this.clientClass,
     this.groupBy = .tag,
     this.include = const OperationFilter(),
     this.exclude = const OperationFilter(),
@@ -139,6 +140,11 @@ final class GenerationConfig {
   /// empty string (`.*`) and does not match anything at the start.
   final RegExp? operationPrefix;
 
+  /// `naming.client`: the class name of the root client; null for the
+  /// client's name in UpperCamelCase with `Client` (`petstore` gives
+  /// `PetstoreClient`).
+  final String? clientClass;
+
   /// `group_by`.
   final GroupBy groupBy;
 
@@ -202,6 +208,7 @@ final class GenerationConfig {
     'input_suffix': inputSuffix,
     'patch_suffix': patchSuffix,
     'operation_prefix': operationPrefix?.pattern,
+    'client_class': clientClass,
     'group_by': groupBy.name,
     'include': include.toJson(),
     'exclude': exclude.toJson(),
diff --git a/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart b/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart
index 21f8ac4..123cafb 100644
--- a/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart
+++ b/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart
@@ -367,6 +367,18 @@ enum DiagnosticCode {
   /// send yet: the parameter is not generated (TOA564 until M9).
   querystringNotGenerated('TOA565', 'querystring-not-generated', .warning),
 
+  /// A path item or an operation has its own `servers`; the client sends
+  /// every request to the base URL of the user's Dio.
+  operationServersIgnored('TOA566', 'operation-servers-ignored', .warning),
+
+  /// An operation has `callbacks`, or the document has `webhooks`: requests
+  /// the server makes, which the client does not generate.
+  callbacksNotGenerated('TOA567', 'callbacks-not-generated', .info),
+
+  /// A security requirement names a scheme that `components.securitySchemes`
+  /// does not have; the scheme is left out of the operation's metadata.
+  securitySchemeUnknown('TOA568', 'security-scheme-unknown', .warning),
+
   /// `*/*` is used as a media type.
   wildcardMediaType('TOA601', 'wildcard-media-type', .warning),
 
@@ -389,6 +401,20 @@ enum DiagnosticCode {
     .warning,
   ),
 
+  /// An operation documents no 2xx response: any 2xx is a success whose
+  /// value is the body as `JsonValue`.
+  successUndocumented('TOA653', 'success-undocumented', .warning),
+
+  /// A success of an operation is `text/event-stream`; the operation is not
+  /// generated until M10 generates event streams.
+  eventStreamNotGenerated('TOA654', 'event-stream-not-generated', .warning),
+
+  /// The schema of a multipart body is not an object with properties (a
+  /// union, an `allOf`, a map): there is no class of parts, the body is the
+  /// schema's type, each property of its JSON is a part, and a binary
+  /// string is sent as base64 text, not as a file.
+  multipartNotObject('TOA655', 'multipart-not-object', .warning),
+
   /// An `encoding` entry of a multipart or form body has `headers`, which
   /// the client does not send.
   encodingHeadersIgnored('TOA656', 'encoding-headers-ignored', .info),
diff --git a/packages/typed_openapi/lib/src/ir/api_ir.dart b/packages/typed_openapi/lib/src/ir/api_ir.dart
index 2dd5ed8..d73a2c4 100644
--- a/packages/typed_openapi/lib/src/ir/api_ir.dart
+++ b/packages/typed_openapi/lib/src/ir/api_ir.dart
@@ -1,6 +1,9 @@
 import '../model/operation.dart';
+import '../model/spec_node.dart';
+import 'dart_type.dart';
 
-// The parts of the IR that only the API emitter reads (M9). `ir.dart`
+// The parts of the IR that only the API emitter reads (M9): body encodings
+// and parts, status types, the root client, servers and security. `ir.dart`
 // exports them.
 
 /// How one property of a form or multipart request body is sent: an entry
@@ -32,3 +35,199 @@ final class EncodingIr {
   /// `allowReserved`.
   final bool allowReserved;
 }
+
+/// A part of a multipart body: a property of its schema.
+final class PartIr {
+  /// Creates a part.
+  const PartIr({
+    required this.name,
+    required this.wireName,
+    required this.type,
+    required this.location,
+    this.required = false,
+    this.contentType,
+    this.description,
+  });
+
+  /// The Dart name of the field.
+  final String name;
+
+  /// The property name, which names the part.
+  final String wireName;
+
+  /// The type of the value; `Uint8List` (a binary string) and a list of it
+  /// are files.
+  final DartType type;
+
+  /// Where the property schema is.
+  final SpecLocation location;
+
+  /// Whether the property is required.
+  final bool required;
+
+  /// The media type of the part, from the `encoding`.
+  final String? contentType;
+
+  /// `description`.
+  final String? description;
+}
+
+/// A sealed type of an operation: its successes or its errors when the
+/// statuses have different bodies (decision 18 of M8).
+final class StatusTypeIr {
+  /// Creates the type [name] with a variant for each of [cases].
+  const StatusTypeIr(this.name, this.cases);
+
+  /// The Dart name of the sealed class.
+  final String name;
+
+  /// The variants, in the order of the responses.
+  final List<StatusCaseIr> cases;
+}
+
+/// A variant of a [StatusTypeIr]: one status.
+final class StatusCaseIr {
+  /// Creates the variant [name] of [status] with a body of [type].
+  const StatusCaseIr(this.status, this.name, this.type);
+
+  /// The status as in the spec: a code, a range such as `4XX`, `default`.
+  final String status;
+
+  /// The Dart name of the variant class (`CreatePetErrorNotFound`).
+  final String name;
+
+  /// The type of the body; null for a status without a body.
+  final DartType? type;
+}
+
+/// The root client: a field for each group and the servers (R10.9).
+final class RootIr {
+  /// Creates the root class [name].
+  const RootIr(this.name, {this.servers = const []});
+
+  /// The Dart name of the class (`PetstoreClient`).
+  final String name;
+
+  /// The servers of the document, in order.
+  final List<ServerIr> servers;
+}
+
+/// A server of the document: a constant of the root client, or a static
+/// method when the URL has variables.
+final class ServerIr {
+  /// Creates the server [name] at [url].
+  const ServerIr({
+    required this.name,
+    required this.url,
+    required this.location,
+    this.description,
+    this.variables = const [],
+  });
+
+  /// The Dart name of the member.
+  final String name;
+
+  /// The URL template, as in the spec.
+  final String url;
+
+  /// Where the Server Object is.
+  final SpecLocation location;
+
+  /// `description`.
+  final String? description;
+
+  /// The variables, in the order of the spec.
+  final List<ServerVariableIr> variables;
+}
+
+/// A variable of a server URL: an argument of its method.
+final class ServerVariableIr {
+  /// Creates the variable [wireName], an argument named [name].
+  const ServerVariableIr({
+    required this.name,
+    required this.wireName,
+    this.defaultValue,
+    this.values = const [],
+    this.description,
+  });
+
+  /// The Dart name of the argument.
+  final String name;
+
+  /// The name in the URL template.
+  final String wireName;
+
+  /// `default`; the argument is required without one.
+  final String? defaultValue;
+
+  /// `enum`: the values the server takes.
+  final List<String> values;
+
+  /// `description`.
+  final String? description;
+}
+
+/// The `type` of a security scheme, as the runtime names it.
+enum SecurityKind {
+  /// An API key.
+  apiKey,
+
+  /// HTTP authentication.
+  http,
+
+  /// Mutual TLS.
+  mutualTls,
+
+  /// OAuth 2.
+  oauth2,
+
+  /// OpenID Connect.
+  openIdConnect,
+}
+
+/// A security scheme of `components.securitySchemes` (R10.8).
+final class SecuritySchemeIr {
+  /// Creates the scheme [name] of [kind].
+  const SecuritySchemeIr(
+    this.name,
+    this.kind, {
+    this.parameterName,
+    this.placement,
+    this.scheme,
+    this.bearerFormat,
+    this.openIdConnectUrl,
+  });
+
+  /// The key in `components.securitySchemes`.
+  final String name;
+
+  /// The type of the scheme.
+  final SecurityKind kind;
+
+  /// The header, query parameter or cookie name of an API key.
+  final String? parameterName;
+
+  /// Where an API key is sent: `query`, `header` or `cookie`.
+  final String? placement;
+
+  /// The HTTP authentication scheme, in lower case.
+  final String? scheme;
+
+  /// `bearerFormat`.
+  final String? bearerFormat;
+
+  /// `openIdConnectUrl`.
+  final String? openIdConnectUrl;
+}
+
+/// A scheme a security requirement names, with its scopes.
+final class SecurityUseIr {
+  /// Requires [scheme] with [scopes].
+  const SecurityUseIr(this.scheme, this.scopes);
+
+  /// The scheme.
+  final SecuritySchemeIr scheme;
+
+  /// The scopes, as in the spec.
+  final List<String> scopes;
+}
diff --git a/packages/typed_openapi/lib/src/ir/ir.dart b/packages/typed_openapi/lib/src/ir/ir.dart
index 7a2ae28..b98b44a 100644
--- a/packages/typed_openapi/lib/src/ir/ir.dart
+++ b/packages/typed_openapi/lib/src/ir/ir.dart
@@ -14,6 +14,7 @@ final class ClientIr {
   ClientIr({
     required List<Declaration> declarations,
     required List<GroupIr> groups,
+    this.root = const RootIr('ApiClient'),
   }) : declarations = List.unmodifiable(
          declarations.toList()..sort((a, b) => a.name.compareTo(b.name)),
        ),
@@ -27,6 +28,9 @@ final class ClientIr {
   /// The API classes, by name.
   final List<GroupIr> groups;
 
+  /// The root client class.
+  final RootIr root;
+
   late final Map<DeclId, Declaration> _byId = {
     for (final declaration in declarations) declaration.id: declaration,
   };
@@ -469,7 +473,7 @@ final class UnionVariantIr {
 /// (R5.3).
 final class GroupIr {
   /// Creates a group; [operations] are sorted by name.
-  GroupIr(this.name, List<OperationIr> operations)
+  GroupIr(this.name, List<OperationIr> operations, {this.field = 'api'})
     : operations = List.unmodifiable(
         operations.toList()..sort((a, b) => a.name.compareTo(b.name)),
       );
@@ -477,6 +481,10 @@ final class GroupIr {
   /// The Dart name of the class.
   final String name;
 
+  /// The name of the group's field in the root client (`pets` for
+  /// `PetsApi`).
+  final String field;
+
   /// The operations, by method name.
   final List<OperationIr> operations;
 }
@@ -498,8 +506,38 @@ final class OperationIr {
     this.summary,
     this.description,
     this.deprecated = false,
+    this.security = const [],
+    this.successType,
+    this.errorType,
+    this.partsName,
   });
 
+  /// This operation with the names of the types the API emitter declares
+  /// for it, given after the declarations.
+  OperationIr withTypes({
+    StatusTypeIr? successType,
+    StatusTypeIr? errorType,
+    String? partsName,
+  }) => OperationIr(
+    location: location,
+    name: name,
+    method: method,
+    path: path,
+    parameters: parameters,
+    responses: responses,
+    errors: errors,
+    operationId: operationId,
+    tags: tags,
+    body: body,
+    summary: summary,
+    description: description,
+    deprecated: deprecated,
+    security: security,
+    successType: successType,
+    errorType: errorType,
+    partsName: partsName,
+  );
+
   /// Where the Operation Object is.
   final SpecLocation location;
 
@@ -540,6 +578,27 @@ final class OperationIr {
   /// `deprecated`.
   final bool deprecated;
 
+  /// The security requirements (R10.8): the operation's `security`, else
+  /// the document's. Any one alternative is enough; every scheme of an
+  /// alternative is needed; an empty alternative makes security optional.
+  final List<List<SecurityUseIr>> security;
+
+  /// The sealed type of the successes, when 2xx responses have different
+  /// bodies (decision 18 of M8). Without it the success type is the one
+  /// body type, `void` without a body, and `JsonValue` when no 2xx is
+  /// documented (TOA653).
+  final StatusTypeIr? successType;
+
+  /// The sealed type of the errors, for [ErrorsByStatus].
+  final StatusTypeIr? errorType;
+
+  /// The class of the parts of a multipart body ([RequestBodyIr.parts]).
+  final String? partsName;
+
+  /// The key of the operation in the overrides file: its `operationId`,
+  /// or `METHOD /path`.
+  String get overrideKey => operationId ?? '$method $path';
+
   /// The responses with a 2xx status.
   List<ResponseIr> get successes => [
     for (final response in responses)
@@ -644,6 +703,7 @@ final class RequestBodyIr {
     this.required = false,
     this.description,
     this.encoding = const [],
+    this.parts,
   });
 
   /// How the body is encoded.
@@ -667,6 +727,13 @@ final class RequestBodyIr {
   /// The `encoding` of the properties of a form or multipart body, by
   /// property name.
   final List<EncodingIr> encoding;
+
+  /// The parts of a multipart body whose schema is an object: the
+  /// properties, each a field of a class of its own
+  /// ([OperationIr.partsName]) whose files are `FileUpload`s. Null for
+  /// other bodies and for a multipart body of another schema, whose [type]
+  /// is sent part by part from its JSON (TOA655).
+  final List<PartIr>? parts;
 }
 
 /// A response of an operation.
diff --git a/packages/typed_openapi/lib/src/ir/ir_builder.dart b/packages/typed_openapi/lib/src/ir/ir_builder.dart
index a3b9262..23a7191 100644
--- a/packages/typed_openapi/lib/src/ir/ir_builder.dart
+++ b/packages/typed_openapi/lib/src/ir/ir_builder.dart
@@ -4,11 +4,13 @@ import '../diagnostics/json_pointer.dart';
 import '../model/operation.dart';
 import '../model/spec_node.dart';
 import '../normalize/normalizer.dart';
+import 'api_names.dart';
 import 'direction_index.dart';
 import 'ir.dart';
 import 'ir_context.dart';
 import 'names.dart';
 import 'operation_builder.dart';
+import 'operation_checks.dart';
 import 'operation_selector.dart';
 import 'schema_mapper.dart';
 
@@ -71,7 +73,6 @@ final class IrBuilder {
     }
     _reportUntagged(context, selected, untagged);
     final built = <String, List<OperationIr>>{};
-    var unbound = 0;
     for (final group in groups.keys.toList()..sort()) {
       final scope = NameScope(
         reserved: {...DartNames.reservedWords, ...DartNames.objectMembers},
@@ -79,10 +80,7 @@ final class IrBuilder {
       );
       final names = _methodNames(context, groups[group]!, scope);
       for (final entry in groups[group]!) {
-        final operation = operations.build(entry, names[entry]!);
-        if (operation == null) {
-          unbound++;
-        } else {
+        if (operations.build(entry, names[entry]!) case final operation?) {
           (built[group] ??= []).add(operation);
         }
       }
@@ -92,9 +90,11 @@ final class IrBuilder {
         context,
         refs: refs,
         filtered: all.length - selected.length,
-        unbound: unbound,
+        unbound: operations.unbound,
+        streams: operations.streams,
       );
     }
+    OperationChecks(context).webhooks();
     final types = NameScope(
       reserved: {
         ...DartNames.reservedWords,
@@ -110,9 +110,9 @@ final class IrBuilder {
     }
     mapper.nameDeclarations(types);
     final groupClasses = <String>{};
-    final groupIrs = [
+    final groupIrs = {
       for (final group in built.keys.toList()..sort())
-        GroupIr(
+        group: GroupIr(
           _groupName(
             context,
             types,
@@ -122,10 +122,11 @@ final class IrBuilder {
           ),
           built[group]!,
         ),
-    ];
+    };
     // The types the emitters add for declarations are named after the
-    // groups, so they never rename a group or a declaration.
-    return ClientIr(declarations: mapper.declarations(types), groups: groupIrs);
+    // groups, so they never rename a group or a declaration; M9's are last.
+    final declarations = mapper.declarations(types);
+    return ApiNames(context, types).client(declarations, groupIrs);
   }
 
   /// Reports operations without a group: one TOA554 when no generated
@@ -179,8 +180,9 @@ final class IrBuilder {
     required int refs,
     required int filtered,
     required int unbound,
+    required int streams,
   }) {
-    if (refs + filtered + unbound == 0) return;
+    if (refs + filtered + unbound + streams == 0) return;
     final reasons = [
       if (filtered > 0)
         '$filtered ${filtered == 1 ? 'is' : 'are'} left out by the include '
@@ -190,11 +192,15 @@ final class IrBuilder {
       if (unbound > 0)
         '$unbound ${unbound == 1 ? 'has' : 'have'} a path variable without a '
             'parameter (TOA556)',
+      if (streams > 0)
+        '$streams ${streams == 1 ? 'is an event stream' : 'are event '
+                  'streams'}, generated from M10 (TOA654)',
     ];
     final fixes = [
       if (filtered > 0) 'Check include, exclude and the overrides.',
       if (refs > 0) 'Write the operations inline at the source.',
       if (unbound > 0) 'Declare the path parameters at the source.',
+      if (streams > 0) 'Leave the event streams out with exclude.',
     ];
     final config = context.config;
     final byFilter =
diff --git a/packages/typed_openapi/lib/src/ir/operation_builder.dart b/packages/typed_openapi/lib/src/ir/operation_builder.dart
index a47117e..66a2ac8 100644
--- a/packages/typed_openapi/lib/src/ir/operation_builder.dart
+++ b/packages/typed_openapi/lib/src/ir/operation_builder.dart
@@ -6,7 +6,10 @@ import 'dart_type.dart';
 import 'ir.dart';
 import 'ir_context.dart';
 import 'names.dart';
+import 'operation_checks.dart';
+import 'parts_builder.dart';
 import 'schema_mapper.dart';
+import 'security_builder.dart';
 
 /// An operation of the spec with its method and path.
 final class SpecOperation {
@@ -37,7 +40,10 @@ final class SpecOperation {
 final class OperationBuilder {
   /// Creates a builder that maps types with [_mapper].
   OperationBuilder(this._context, this._mapper)
-    : _encoding = BodyEncoding(_context);
+    : _checks = OperationChecks(_context),
+      _security = SecurityBuilder(_context),
+      _parts = PartsBuilder(_context, _mapper),
+      _encoding = BodyEncoding(_context);
 
   static const _names = DartNames();
 
@@ -72,16 +78,38 @@ final class OperationBuilder {
 
   final IrContext _context;
   final SchemaMapper _mapper;
+  final OperationChecks _checks;
+  final SecurityBuilder _security;
+  final PartsBuilder _parts;
   final BodyEncoding _encoding;
 
+  /// How many operations [build] left out because a success is an event
+  /// stream (TOA654).
+  int streams = 0;
+
+  /// How many operations [build] left out because a path variable has no
+  /// parameter (TOA556).
+  int unbound = 0;
+
   /// The IR of [entry], named [name]; null when its path template cannot
-  /// be filled.
+  /// be filled, or when a success is an event stream (counted in
+  /// [streams]).
   OperationIr? build(SpecOperation entry, String name) {
     final operation = entry.operation;
     final prefix = _names.pascal(name) ?? name;
     final parameters = _parameters(entry, prefix);
-    if (parameters == null) return null;
+    if (parameters == null) {
+      unbound++;
+      return null;
+    }
     final responses = _responses(operation, prefix);
+    if (_checks.isEventStream(responses)) {
+      streams++;
+      return null;
+    }
+    _checks.successes(operation);
+    _checks.servers(entry);
+    _checks.callbacks(operation);
     return OperationIr(
       location: operation.location,
       name: name,
@@ -96,6 +124,7 @@ final class OperationBuilder {
       body: _body(operation, entry.method, prefix),
       responses: responses,
       errors: _errors(responses),
+      security: _security.of(operation),
     );
   }
 
@@ -340,18 +369,11 @@ final class OperationBuilder {
     );
     final kind = contentType == null ? BodyKind.none : _kind(contentType);
     final schema = media?.schema;
-    // Raw bytes have no model, as in responses; text is a string.
-    final DartType? type = switch ((schema, kind)) {
-      (_, .bytes) => const CoreType(.binary),
-      (_, .text || .eventStream) => const CoreType(.string),
-      (null, _) => null,
-      (final schema?, _) => _mapper.typeOf(
-        schema,
-        NameHint(prefix, 'Request'),
-        direction: .request,
-        patchBody: method.toLowerCase() == 'patch',
-      ),
-    };
+    final parts = kind == .multipart && schema != null
+        ? _parts.of(schema, media!, prefix)
+        : null;
+    // Parts are a class of their own.
+    final type = parts == null ? _bodyType(schema, kind, prefix, method) : null;
     return RequestBodyIr(
       kind: kind,
       location: body.location,
@@ -362,9 +384,31 @@ final class OperationBuilder {
       encoding: kind == .form || kind == .multipart
           ? _encoding.of(media!, kind)
           : const [],
+      parts: parts,
     );
   }
 
+  /// The type of a request body of [kind]: raw bytes have no model, as in
+  /// responses, and text is a string.
+  DartType? _bodyType(
+    Schema? schema,
+    BodyKind kind,
+    String prefix,
+    String method,
+  ) {
+    return switch ((schema, kind)) {
+      (_, .bytes) => const CoreType(.binary),
+      (_, .text || .eventStream) => const CoreType(.string),
+      (null, _) => null,
+      (final schema?, _) => _mapper.typeOf(
+        schema,
+        NameHint(prefix, 'Request'),
+        direction: .request,
+        patchBody: method.toLowerCase() == 'patch',
+      ),
+    };
+  }
+
   List<ResponseIr> _responses(Operation operation, String prefix) {
     final responses = [
       for (final MapEntry(key: status, value: written)
````

- [ ] **Step 4: Update the size ratchet**

`ir.dart`, `ir_builder.dart`, `operation_builder.dart`, `IrBuilder._reportEmpty` and `config_loader.dart` take the wiring; `IrBuilder.build` gets shorter (the counting moved into `OperationBuilder`, the assembly into `ApiNames.client`). Raised entries with reasons, as in the table.

**Diff** (apply from the repository root with `git apply`):

````diff
diff --git a/packages/typed_openapi/test/quality/size_limits_test.dart b/packages/typed_openapi/test/quality/size_limits_test.dart
index 10601d8..c854a54 100644
--- a/packages/typed_openapi/test/quality/size_limits_test.dart
+++ b/packages/typed_openapi/test/quality/size_limits_test.dart
@@ -16,15 +16,17 @@ import '../helpers/size_limits.dart';
 /// Files over their limit, with the number of lines (`wc -l`) they had when
 /// they were listed. Keep the entries sorted.
 const Map<String, int> _fileAllowlist = {
-  'lib/src/config/config_loader.dart': 780,
+  // M9: naming.client is read with the other naming keys.
+  'lib/src/config/config_loader.dart': 798,
   'lib/src/emit/model_emitter.dart': 379,
   'lib/src/emit/union_emitter.dart': 416,
   'lib/src/generate/output_writer.dart': 896,
   // M9: the fields the API emitter reads on the operation IR classes.
-  'lib/src/ir/ir.dart': 747,
-  'lib/src/ir/ir_builder.dart': 534,
+  'lib/src/ir/ir.dart': 814,
+  // M9: event streams in the empty-client report; webhooks checked.
+  'lib/src/ir/ir_builder.dart': 540,
   // M9: the path variable pattern, parameter defaults, encodings, statuses.
-  'lib/src/ir/operation_builder.dart': 604,
+  'lib/src/ir/operation_builder.dart': 648,
   'lib/src/ir/schema_mapper.dart': 2196,
   'lib/src/ir/schema_shapes.dart': 446,
   'test/check/spec_checker_test.dart': 705,
@@ -70,7 +72,8 @@ const Map<String, int> _methodAllowlist = {
   'lib/src/generate/output_writer.dart#OutputWriter.write': 111,
   'lib/src/ir/ir_builder.dart#IrBuilder._group': 112,
   'lib/src/ir/ir_builder.dart#IrBuilder._methodName': 50,
-  'lib/src/ir/ir_builder.dart#IrBuilder._reportEmpty': 50,
+  // M9: event streams are a reason a client is empty.
+  'lib/src/ir/ir_builder.dart#IrBuilder._reportEmpty': 55,
   'lib/src/ir/ir_builder.dart#IrBuilder.build': 95,
   // M9: a parameter keeps its schema's default.
   'lib/src/ir/operation_builder.dart#OperationBuilder._parameter': 100,
````

- [ ] **Step 5: Update the documentation**

**Diff** (apply from the repository root with `git apply`):

````diff
diff --git a/CLAUDE.md b/CLAUDE.md
index 599a1ae..e012711 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -268,7 +268,18 @@ All under `packages/typed_openapi/lib/src/`, one folder per stage:
   or one class, with an override `group` (UpperCamelCase, or a value that
   differs only by case or separators) and TOA553-TOA555; the names of custom
   types are taken in the type scope first, so a declaration named like one
-  gets a suffix, TOA551; method names,
+  gets a suffix, TOA551; `ApiNames` names, after the declarations, groups
+  and M8 helper types, the root client (`ClientIr.root`: `naming.client`
+  or the client name with `Client`, so `SpecChecker` keys a run by the
+  client name when `naming.client` is unset; group fields and servers are
+  its members), the sealed `StatusTypeIr`s of successes with different
+  bodies and of `ErrorsByStatus` (variants by reason phrase, `ApiNames.
+  variantOf`; the plural when an inline body has the name) and the class of
+  multipart parts (`RequestBodyIr.parts`, TOA655 when the schema is not an
+  object); `OperationBuilder` keeps security requirements (TOA568 for an
+  unknown scheme), skips event-stream operations (TOA654) and reports
+  operation servers (TOA566), callbacks and webhooks (TOA567) and a missing
+  2xx (TOA653); method names,
   override names first, then
   `operationId` without the `operation_prefix`, then the path; TOA563 when
   no operation is generated, at the config client if filters left some
diff --git a/packages/typed_openapi/CHANGELOG.md b/packages/typed_openapi/CHANGELOG.md
index 622301c..5585f5f 100644
--- a/packages/typed_openapi/CHANGELOG.md
+++ b/packages/typed_openapi/CHANGELOG.md
@@ -167,6 +167,18 @@
     placement; also a form property's `encoding` style.
   - TOA565 querystring-not-generated (warning): an `in: querystring`
     parameter (OpenAPI 3.2) is not generated (TOA564 before M9).
+  - TOA566 operation-servers-ignored (warning): a path item or operation has
+    its own `servers`; requests go to the Dio base URL.
+  - TOA567 callbacks-not-generated (info): `callbacks` of an operation and
+    the document's `webhooks` are not generated.
+  - TOA568 security-scheme-unknown (warning): a security requirement names
+    a scheme `components.securitySchemes` does not have.
+  - TOA653 success-undocumented (warning): no 2xx response; any 2xx is a
+    success with the body as `JsonValue`.
+  - TOA654 event-stream-not-generated (warning): an operation whose success
+    is `text/event-stream` is not generated until M10.
+  - TOA655 multipart-not-object (warning): a multipart body that is not an
+    object with properties has no class of parts.
   - TOA650 media-type-as-bytes (info): a body whose media type is not JSON, a
     form, `multipart/form-data`, `text/*` or `text/event-stream`, or a form
     or multipart response, is bytes and its schema is not used (TOA561
@@ -179,6 +191,14 @@
     M9).
   - TOA656 encoding-headers-ignored (info): the `headers` of a multipart
     part's `encoding` are not sent.
+- The IR names what the API emitter declares, after the models (which never
+  move): the root client (`naming.client`, else the client name with
+  `Client`), the sealed types of successes and errors with variants named by
+  the HTTP reason phrase (`CreatePetErrorNotFound`, `…ClientError` for
+  `4XX`, `…Other` for `default`, `…Status499`; the plural `GetPetErrors`
+  when an inline body is `GetPetError`), the classes of multipart parts
+  (`UploadRequest`), the group fields and the servers of the root client;
+  and it keeps security requirements with their schemes.
 - An `apiKey` security scheme without `in` is TOA112, as one without `name`.
 - Schemas named `Dio` or like the runtime's new names (`FileUpload`,
   `FormBody`, `MultipartBody`, `SecurityScheme`, ...) get the `Model` suffix
diff --git a/packages/typed_openapi/README.md b/packages/typed_openapi/README.md
index 5907eb8..4c32355 100644
--- a/packages/typed_openapi/README.md
+++ b/packages/typed_openapi/README.md
@@ -189,6 +189,7 @@ generate and how in `defaults` or per client:
 ```yaml
 defaults:
   naming:
+    client: PetstoreClient       # root client class; default: client name + Client
     group: '{Tag}Api'            # class per tag; group_by: tag|path|single
     patch_suffix: Patch          # PetPatch: PATCH body of a schema used elsewhere too
     operation_prefix: '^v1_'     # removed from operationIds (nestjs: XController_)
diff --git a/packages/typed_openapi/README.ua.md b/packages/typed_openapi/README.ua.md
index c91d739..db0b3c5 100644
--- a/packages/typed_openapi/README.ua.md
+++ b/packages/typed_openapi/README.ua.md
@@ -189,6 +189,7 @@ Override, ціль якого зникла, дає warning, той, з яким
 ```yaml
 defaults:
   naming:
+    client: PetstoreClient       # кореневий клас; за замовчуванням ім'я клієнта + Client
     group: '{Tag}Api'            # клас на тег; group_by: tag|path|single
     patch_suffix: Patch          # PetPatch: тіло PATCH схеми, вжитої ще деінде
     operation_prefix: '^v1_'     # зрізається з operationId (nestjs: XController_)
````

- [ ] **Step 6: Verify**

Run from the root:

```bash
dart pub get
dart analyze packages        # No issues found!
```

From `packages/typed_openapi`: `dart format lib test bin` (a second run changes 0 files) and `dart test` (expected `+948: All tests passed!`, the size ratchet `test/quality/size_limits_test.dart` included). From `packages/typed_openapi_runtime`: `dart format lib test` (the same) and `dart test` (expected `+183: All tests passed!`).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(typed_openapi): name the root client, status types, parts and servers in the IR

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>

# Conflicts:
#	packages/typed_openapi/lib/src/ir/operation_builder.dart"
```

---

### Task 4: Emitter: API classes, status types, parts classes and the root client

**Files:**
- Modify: `CLAUDE.md`
- Modify: `packages/typed_openapi/CHANGELOG.md`
- Create: `packages/typed_openapi/lib/src/emit/api_library.dart`
- Create: `packages/typed_openapi/lib/src/emit/decoder_writer.dart`
- Modify: `packages/typed_openapi/lib/src/emit/model_library.dart`
- Create: `packages/typed_openapi/lib/src/emit/operation_emitter.dart`
- Create: `packages/typed_openapi/lib/src/emit/parts_emitter.dart`
- Create: `packages/typed_openapi/lib/src/emit/request_writer.dart`
- Create: `packages/typed_openapi/lib/src/emit/status_type_emitter.dart`
- Create: `packages/typed_openapi/test/emit/api_library_test.dart`
- Create: `packages/typed_openapi/test/emit/fixtures/hostile_operations.yaml`
- Create: `packages/typed_openapi/test/emit/fixtures/petstore.yaml`
- Modify: `packages/typed_openapi/test/helpers/emit_fixture.dart`
- Modify: `packages/typed_openapi_runtime/CHANGELOG.md`
- Modify: `packages/typed_openapi_runtime/lib/src/request/multipart_body.dart`
- Modify: `packages/typed_openapi_runtime/test/dio/bodies_send_test.dart`
- Modify: `packages/typed_openapi_runtime/test/request/bodies_test.dart`
- Generated: 13 golden files under `packages/typed_openapi/test/emit/goldens/petstore/` (`UPDATE_GOLDENS=1`)

**Interfaces:**
- Consumes: tasks 1-3; M8: `TypeCodec`, `DartWriter`, `DartCode`, `Imports`, `ModelLibrary`.
- Produces: `ApiLibrary`, `OperationEmitter`, `RequestWriter`, `DecoderWriter`, `StatusTypeEmitter`, `PartsEmitter`; `ModelLibrary.snake`/`writeHeader` (public); `emitClient` test helper; `MultipartBody.fromJson`, `MultipartPart.file(..., contentType:)` in the runtime.

The emitter prints the IR only. A group is a plain `class` with `PetsApi(Dio dio)` (R10.7, spec decision 3), a private `OperationInfo` per operation (tags, security uses as `const` objects) and a static decoder; methods take named arguments only (`required` when required; enum arguments take the known values, R8.2), `body`, then `CallOptions? call`, and return `Future<Result<T, E>>` from `DioRequestSender.send` (spec decisions 1-2). Parameters are written in their JSON form with their style (`PathParameter('petId', petId, style: .label)`); a JSON `content` parameter is JSON text. Bodies: JSON (`toJson`), `FormBody` with `FormEncoding`s, the parts class (`toParts()`), `MultipartBody.fromJson` (TOA655), `FileUpload` for binary, `String` for text; a wildcard media type is sent as a concrete one. The decoder follows decisions 6-7 above. After the class come the sealed status types (variants wrap `body`, equal by value) and the parts classes. `ApiLibrary` writes the models, `api/<group>.dart`, `api.dart` and the root `<client>.dart` with the servers as `static const` or a `static String` method of the URL variables (spec decision 10). Fixtures: `petstore.yaml` (every parameter style, every body kind, 200/201/204, `4XX`, `default`, envelope, text, binary, security, servers, deprecations) and `hostile_operations.yaml` (newline, `*/`, `{@`, bidi, `$`, Dart keywords, `body`/`call` as parameter names, dio names, an empty and a 20-value enum, recursion, unions in bodies and responses).

- [ ] **Step 1: Write the failing tests**

**New file** `packages/typed_openapi/test/emit/api_library_test.dart`:

````dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/emit/api_library.dart';
import 'package:typed_openapi/src/ir/ir.dart';
import 'package:typed_openapi/src/overrides/override_set.dart';

import '../helpers/emit_fixture.dart';

void main() {
  test('the petstore fixture matches its goldens (R15.3)', () {
    final files = emitClient('petstore.yaml');
    final goldens = p.join('test', 'emit', 'goldens', 'petstore');
    if (Platform.environment['UPDATE_GOLDENS'] == '1') {
      for (final MapEntry(:key, :value) in files.entries) {
        File(p.join(goldens, '$key.golden'))
          ..createSync(recursive: true)
          ..writeAsStringSync(value);
      }
    }
    final expected = {
      for (final file in Directory(
        goldens,
      ).listSync(recursive: true).whereType<File>())
        p
            .relative(file.path, from: goldens)
            .replaceAll(r'\', '/')
            .replaceAll(RegExp(r'\.golden$'), ''): file
            .readAsStringSync(),
    };
    expect(files.keys.toSet(), expected.keys.toSet());
    for (final MapEntry(:key, :value) in files.entries) {
      expect(value, expected[key], reason: key);
    }
  });

  test('a client is its models, a file per group and the root', () {
    final files = emitClient('petstore.yaml');
    expect(
      files.keys.where((f) => !f.startsWith('models')),
      [
        'api.dart',
        'api/default_api.dart',
        'api/pets_api.dart',
        'api/store_api.dart',
        'api_client.dart',
      ],
    );
    expect(files['api.dart'], contains("export 'api/pets_api.dart';"));
    expect(files['api_client.dart'], contains("export 'models.dart';"));
    expect(files['api_client.dart'], contains("export 'api.dart';"));
    for (final MapEntry(:key, :value) in files.entries) {
      expect(
        value,
        startsWith(
          '// GENERATED CODE - DO NOT MODIFY BY HAND.\n// dart format off\n',
        ),
        reason: key,
      );
    }
  });

  test('the root file is named after the client, apart from the barrels', () {
    expect(ApiLibrary.rootFile('petstore'), 'petstore.dart');
    expect(ApiLibrary.rootFile('my-shop'), 'my_shop.dart');
    expect(ApiLibrary.rootFile('api'), 'api_client.dart');
    expect(ApiLibrary.rootFile('models'), 'models_client.dart');
    expect(ApiLibrary.rootFile('2fa'), 'type_2_fa.dart');
    expect(ApiLibrary.rootFile('ü'), 'api_client.dart');
  });

  test('group files that would share a name get 2, 3, ...', () {
    final ir = ClientIr(
      declarations: const [],
      groups: [
        GroupIr('UserDTOApi', const []),
        GroupIr('UserDtoApi', const []),
      ],
    );
    expect(const ApiLibrary().fileNames(ir), {
      'UserDTOApi': 'user_dto_api.dart',
      'UserDtoApi': 'user_dto_api2.dart',
    });
  });

  test('the same spec gives the same files', () {
    expect(emitClient('petstore.yaml'), emitClient('petstore.yaml'));
    expect(
      emitClient('hostile_operations.yaml'),
      emitClient('hostile_operations.yaml'),
    );
  });

  test('strings from the spec cannot leave their literal or comment', () {
    for (final mode in UnionMode.values) {
      final files = emitClient(
        'hostile_operations.yaml',
        generation: GenerationConfig(union: mode),
      );
      for (final MapEntry(:key, :value) in files.entries) {
        for (final line in value.split('\n')) {
          final code = line.trimLeft();
          expect(
            code.startsWith('injected') || code.startsWith('void injected'),
            isFalse,
            reason: '$key: $line',
          );
          if (!code.startsWith('///') && !code.startsWith('//')) {
            expect(code, isNot(startsWith('/*')), reason: '$key: $line');
          }
          expect(line, isNot(contains('\r')), reason: key);
        }
        expect(
          value,
          isNot(matches(RegExp('[\u202a-\u202e\u2066-\u2069\u2028\u2029]'))),
          reason: key,
        );
      }
    }
  });
}
````

**New file** `packages/typed_openapi/test/emit/fixtures/hostile_operations.yaml`:

````yaml
openapi: 3.1.0
info: {title: "t */ injected", version: "1"}
servers:
  - url: "https://x.example.com/'; injected(); '/{v}/{missing}"
    description: "*/ injected() /* {@macro x}"
    variables:
      v: {default: "'$x\n injected", enum: ["a'b", "‮"]}
      class: {description: "Line\ninjected();"}
security: [{"k'ey": ["scope'\n injected"]}]
paths:
  "/a/{id}/'$x":
    get:
      operationId: "get\ninjected(); //"
      summary: "Line one\n*/ injected() /* {@macro x} ‮"
      description: "[link] <b> $dollar \\ `code` ``` fence"
      tags: ["Pets\n injected", other]
      parameters:
        - {name: id, in: path, required: true, schema: {type: string}}
        - {name: class, in: query, schema: {type: string, default: "*/ injected"}, description: "*/ injected()"}
        - {name: body, in: query, schema: {type: string}}
        - {name: call, in: header, schema: {type: string}}
        - {name: "X-'$y\ninjected", in: header, schema: {type: string}}
        - {name: e, in: query, schema: {type: string, enum: []}}
        - {name: big, in: cookie, schema: {type: integer, enum: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]}}
      responses:
        "200": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/Response'}}}}
        "4XX": {description: bad, content: {application/json: {schema: {$ref: '#/components/schemas/Options'}}}}
        "5XX": {description: down, content: {application/json: {schema: {$ref: '#/components/schemas/Headers'}}}}
  /b:
    post:
      operationId: "$dollar"
      tags: [class]
      requestBody:
        required: true
        content: {application/json: {schema: {$ref: '#/components/schemas/Node'}}}
      responses:
        "201": {description: x, content: {application/json: {schema: {oneOf: [{type: string}, {type: integer}]}}}}
        "202": {description: y, content: {application/json: {schema: {$ref: '#/components/schemas/Node'}}}}
        "404": {description: z, content: {application/json: {schema: {$ref: '#/components/schemas/Dio'}}}}
        "500": {description: "*/ injected"}
  /c:
    put:
      operationId: toString
      tags: [class]
      requestBody:
        content:
          multipart/form-data:
            schema:
              type: object
              properties:
                "*/ injected": {type: string, format: binary}
                toParts: {type: string}
                hashCode: {type: integer}
      responses:
        "204": {description: ok}
components:
  securitySchemes:
    "k'ey": {type: apiKey, name: "X-'$k", in: header}
  schemas:
    Response: {type: object, properties: {a: {type: string}}}
    Options: {type: object, properties: {b: {type: string}}}
    Headers: {type: object, properties: {c: {type: string}}}
    Dio: {type: object, properties: {d: {type: string}}}
    Node:
      type: object
      properties:
        next: {$ref: '#/components/schemas/Node'}
        value: {type: string}
````

**New file** `packages/typed_openapi/test/emit/fixtures/petstore.yaml`:

````yaml
openapi: 3.1.0
info: {title: Petstore, version: "1"}
servers:
  - url: https://{region}.pets.example.com/v1
    description: Production.
    variables:
      region: {default: eu, enum: [eu, us], description: The region.}
  - url: http://localhost:8080
security: [{bearer: []}]
paths:
  /pets:
    get:
      operationId: listPets
      tags: [pets]
      summary: Lists pets.
      parameters:
        - {name: limit, in: query, schema: {type: integer, default: 20}, description: How many.}
        - {name: tags, in: query, style: pipeDelimited, schema: {type: array, items: {type: string}}}
        - {name: status, in: query, explode: false, schema: {type: array, items: {$ref: '#/components/schemas/Status'}}}
        - {name: filter, in: query, style: deepObject, explode: true, schema: {type: object, additionalProperties: {type: string}}}
        - {name: next, in: query, allowReserved: true, schema: {type: string}}
        - {name: where, in: query, content: {application/json: {schema: {type: object, additionalProperties: {type: integer}}}}}
        - {name: X-Trace, in: header, required: true, schema: {type: string}}
        - {name: session, in: cookie, schema: {type: string}}
      responses:
        "200":
          description: The pets.
          content:
            application/json:
              schema: {type: array, items: {$ref: '#/components/schemas/Pet'}}
        default:
          description: An error.
          content:
            application/json: {schema: {$ref: '#/components/schemas/Problem'}}
    post:
      operationId: createPet
      tags: [pets]
      requestBody:
        required: true
        content:
          application/json: {schema: {$ref: '#/components/schemas/Pet'}}
      responses:
        "200": {description: Exists., content: {application/json: {schema: {$ref: '#/components/schemas/Pet'}}}}
        "201": {description: Created., content: {application/json: {schema: {$ref: '#/components/schemas/Job'}}}}
        "204": {description: Queued.}
        "404": {description: Gone., content: {application/json: {schema: {$ref: '#/components/schemas/Problem'}}}}
        "4XX": {description: Bad., content: {application/json: {schema: {$ref: '#/components/schemas/Job'}}}}
        "503": {description: Down.}
  /pets/{petId}:
    parameters:
      - {name: petId, in: path, required: true, schema: {type: integer}}
    get:
      operationId: getPet
      tags: [pets]
      deprecated: true
      responses:
        "200":
          description: The pet, in an envelope.
          content:
            application/json:
              schema:
                type: object
                required: [data]
                properties:
                  data: {$ref: '#/components/schemas/Pet'}
        "404": {description: Gone., content: {application/json: {schema: {$ref: '#/components/schemas/Problem'}}}}
    delete:
      operationId: deletePet
      tags: [pets]
      security: []
      parameters:
        - {name: reason, in: header, schema: {type: string}, deprecated: true}
      responses:
        "204": {description: Deleted.}
  /pets/{petId}/photo:
    parameters:
      - {name: petId, in: path, required: true, style: label, schema: {type: integer}}
    get:
      operationId: getPhoto
      tags: [pets]
      responses:
        "200": {description: The photo., content: {image/png: {schema: {type: string, format: binary}}}}
        "404": {description: Gone., content: {application/json: {schema: {$ref: '#/components/schemas/Problem'}}}}
    put:
      operationId: putPhoto
      tags: [pets]
      requestBody:
        required: true
        content:
          image/*: {schema: {type: string, format: binary}}
      responses:
        "204": {description: Stored.}
    post:
      operationId: uploadPhoto
      tags: [pets]
      requestBody:
        required: true
        content:
          multipart/form-data:
            schema:
              type: object
              required: [file]
              properties:
                file: {type: string, format: binary, description: The photo.}
                extra: {type: array, items: {type: string, format: binary}}
                caption: {type: string}
                meta: {$ref: '#/components/schemas/Job'}
            encoding:
              file: {contentType: image/png}
      responses:
        "204": {description: Stored.}
  /pets/{petId}/note:
    get:
      operationId: getNote
      tags: [pets]
      parameters:
        - {name: petId, in: path, required: true, style: matrix, explode: true, schema: {type: array, items: {type: integer}}}
      responses:
        "200": {description: The note., content: {text/plain: {schema: {type: string}}}}
        "404": {description: Gone., content: {application/json: {schema: {$ref: '#/components/schemas/Problem'}}}}
  /store/orders:
    post:
      operationId: placeOrder
      tags: [store]
      security: [{apiKey: []}, {}]
      requestBody:
        content:
          application/x-www-form-urlencoded:
            schema:
              type: object
              properties:
                petId: {type: integer}
                tags: {type: array, items: {type: string}}
                meta: {type: object, additionalProperties: {type: string}}
            encoding:
              tags: {explode: false}
              meta: {style: deepObject, explode: true}
      responses:
        "200":
          description: The order.
          content:
            application/json:
              schema:
                type: object
                properties:
                  id: {type: integer}
                  status: {$ref: '#/components/schemas/Status'}
        "400": {description: Bad., content: {application/json: {schema: {$ref: '#/components/schemas/Problem'}}}}
  /store/notes:
    post:
      operationId: sendNote
      tags: [store]
      requestBody:
        content:
          text/plain: {schema: {type: string}}
      responses:
        default: {description: Anything., content: {application/json: {schema: {type: object, properties: {ok: {type: boolean}}}}}}
  /health:
    get:
      operationId: health
      responses:
        "200": {description: Up.}
components:
  securitySchemes:
    bearer: {type: http, scheme: bearer, bearerFormat: JWT}
    apiKey: {type: apiKey, name: X-Api-Key, in: header}
  schemas:
    Status:
      type: string
      enum: [available, sold]
    Pet:
      type: object
      required: [id, name]
      properties:
        id: {type: integer}
        name: {type: string}
        status: {$ref: '#/components/schemas/Status'}
    Job:
      type: object
      properties:
        id: {type: string}
    Problem:
      type: object
      required: [code]
      properties:
        code: {type: string}
````

**Diff** (apply from the repository root with `git apply`):

````diff
diff --git a/packages/typed_openapi/test/helpers/emit_fixture.dart b/packages/typed_openapi/test/helpers/emit_fixture.dart
index 598be86..a7d0f07 100644
--- a/packages/typed_openapi/test/helpers/emit_fixture.dart
+++ b/packages/typed_openapi/test/helpers/emit_fixture.dart
@@ -2,6 +2,7 @@ import 'dart:io';
 
 import 'package:path/path.dart' as p;
 import 'package:typed_openapi/src/config/generation_config.dart';
+import 'package:typed_openapi/src/emit/api_library.dart';
 import 'package:typed_openapi/src/emit/model_library.dart';
 import 'package:typed_openapi/src/ir/ir_builder.dart';
 
@@ -21,3 +22,19 @@ Map<String, String> emitFixture(
   ).build(fixture.context.spec, fixture.context.client);
   return const ModelLibrary().files(ir);
 }
+
+/// The files of the whole client of the fixture spec [name] in
+/// `test/emit/fixtures`: models, API and the root, for the client `api`.
+Map<String, String> emitClient(
+  String name, {
+  GenerationConfig generation = const GenerationConfig(),
+}) {
+  final fixture = IrFixture(
+    File(p.join('test', 'emit', 'fixtures', name)).readAsStringSync(),
+    generation: generation,
+  );
+  final ir = IrBuilder(
+    fixture.diagnostics,
+  ).build(fixture.context.spec, fixture.context.client);
+  return const ApiLibrary().files(ir, client: fixture.context.client.name);
+}
diff --git a/packages/typed_openapi_runtime/test/dio/bodies_send_test.dart b/packages/typed_openapi_runtime/test/dio/bodies_send_test.dart
index 9c45503..8b6de37 100644
--- a/packages/typed_openapi_runtime/test/dio/bodies_send_test.dart
+++ b/packages/typed_openapi_runtime/test/dio/bodies_send_test.dart
@@ -72,6 +72,19 @@ void main() {
             'stream',
             FileUpload.stream(Stream.value(utf8.encode('de')), length: 2),
           ),
+          MultipartPart.file(
+            'typed',
+            FileUpload.bytes(Uint8List.fromList(utf8.encode('f'))),
+            contentType: 'image/png',
+          ),
+          MultipartPart.file(
+            'own',
+            FileUpload.bytes(
+              Uint8List.fromList(utf8.encode('g')),
+              contentType: 'image/gif',
+            ),
+            contentType: 'image/png',
+          ),
         ]),
         contentType: 'multipart/form-data',
       ),
@@ -107,6 +120,8 @@ void main() {
         'de\r\n',
       ),
     );
+    expect(body, contains('name="typed"\r\ncontent-type: image/png\r\n'));
+    expect(body, contains('name="own"\r\ncontent-type: image/gif\r\n'));
   });
 
   test('a file body sends its bytes or stream and its own type', () async {
diff --git a/packages/typed_openapi_runtime/test/request/bodies_test.dart b/packages/typed_openapi_runtime/test/request/bodies_test.dart
index fc67509..a596c46 100644
--- a/packages/typed_openapi_runtime/test/request/bodies_test.dart
+++ b/packages/typed_openapi_runtime/test/request/bodies_test.dart
@@ -56,6 +56,25 @@ void main() {
     });
   });
 
+  group('MultipartBody', () {
+    test('a JSON object gives a value part per property', () {
+      final body = MultipartBody.fromJson({
+        'a': 1,
+        'b': [true],
+      });
+      expect([for (final p in body.parts) p.name], ['a', 'b']);
+      expect(
+        [for (final p in body.parts) p.value],
+        [
+          1,
+          [true],
+        ],
+      );
+      expect(MultipartBody.fromJson(null).parts, isEmpty);
+      expect(() => MultipartBody.fromJson([1]), throwsArgumentError);
+    });
+  });
+
   group('FileUpload', () {
     test('holds bytes or a stream with its length', () {
       final bytes = FileUpload.bytes(
````

- [ ] **Step 2: Run the tests to see them fail**

Run from `packages/typed_openapi`: `dart test test/emit/api_library_test.dart`; from `packages/typed_openapi_runtime`: `dart test test/request/bodies_test.dart test/dio/bodies_send_test.dart`.
Expected: FAIL to load: `ApiLibrary` and `emitClient` are not defined; `MultipartBody.fromJson` and the `contentType` of `MultipartPart.file` do not exist.

- [ ] **Step 3: Implement**

**New file** `packages/typed_openapi/lib/src/emit/api_library.dart`:

````dart
import '../ir/ir.dart';
import '../ir/names.dart';
import '../ir/operation_builder.dart';
import 'dart_code.dart';
import 'dart_writer.dart';
import 'imports.dart';
import 'model_library.dart';
import 'operation_emitter.dart';
import 'type_codec.dart';

/// The files of a whole client (decision 4 of M9): the models of
/// [ModelLibrary], a file per group in `api/` with the barrel `api.dart`,
/// and the root client in `<client>.dart`, which exports both barrels.
///
/// Group files are named after their class in snake case, in their own
/// directory and name scope, so they never move a model file.
final class ApiLibrary {
  /// Creates the library writer; lines are wrapped at [width].
  const ApiLibrary({this.width = 80});

  /// The line width.
  final int width;

  /// The directory of the group files, relative to the output directory.
  static const directory = 'api';

  /// The barrel of the group files, relative to the output directory.
  static const barrel = 'api.dart';

  static const _code = DartCode();
  static const _names = DartNames();

  /// The files of [ir], the IR of the client [client], by path relative to
  /// the output directory, sorted by path.
  Map<String, String> files(ClientIr ir, {required String client}) {
    final models = ModelLibrary(width: width);
    final modelFiles = models.fileNames(ir);
    final files = models.files(ir);
    final groupFiles = fileNames(ir);
    for (final group in ir.groups) {
      final file = groupFiles[group.name]!;
      final imports = Imports(file);
      final codec = TypeCodec(
        ir,
        imports,
        (id) => '../${ModelLibrary.directory}/${modelFiles[id]}',
      );
      final body = DartWriter(width);
      OperationEmitter(codec).write(group, body);
      final out = DartWriter(width);
      ModelLibrary.writeHeader(out);
      imports.write(out);
      files['$directory/$file'] = '${out.text}${body.text}';
    }
    final exports = DartWriter(width);
    ModelLibrary.writeHeader(exports);
    for (final group
        in ir.groups.map((g) => groupFiles[g.name]!).toList()..sort()) {
      exports.line('export ${_code.string('$directory/$group')};');
    }
    files[barrel] = exports.text;
    files[rootFile(client)] = _root(ir, groupFiles);
    return {for (final path in files.keys.toList()..sort()) path: files[path]!};
  }

  /// The file name of every group of [ir], by class name, without the
  /// directory.
  Map<String, String> fileNames(ClientIr ir) {
    final scope = NameScope(reserved: const {}, reservedSuffix: '');
    return {
      for (final group in ir.groups)
        group.name: '${scope.claim(ModelLibrary.snake(group.name)).$1}.dart',
    };
  }

  /// The file of the root client [client]: its name in snake case, or with
  /// `_client` when that would be a barrel's name.
  static String rootFile(String client) {
    final snake = ModelLibrary.snake(_names.pascal(client) ?? 'api');
    return switch ('$snake.dart') {
      ModelLibrary.barrel || barrel => '${snake}_client.dart',
      final file => file,
    };
  }

  String _root(ClientIr ir, Map<String, String> groupFiles) {
    final root = ir.root;
    final imports = Imports(rootFile(root.name))
      ..show('package:dio/dio.dart', 'Dio');
    for (final group in ir.groups) {
      imports.file('$directory/${groupFiles[group.name]}');
    }
    final out = DartWriter(width);
    ModelLibrary.writeHeader(out);
    imports.write(out);
    out
      ..line('export ${_code.string(barrel)};')
      ..line('export ${_code.string(ModelLibrary.barrel)};')
      ..line()
      ..prose(
        'The client of the API: a field for each group of operations, and '
        'the servers of the spec. Set the base URL on your Dio.',
      )
      ..block('class ${root.name}', () {
        _constructor(out, ir);
        for (final group in ir.groups) {
          out
            ..line()
            ..prose('The operations of [${group.name}].')
            ..line('final ${group.name} ${group.field};');
        }
        for (final server in root.servers) {
          out.line();
          _server(out, server);
        }
      });
    return out.text;
  }

  /// The constructor of the root client: a group per field, on one line
  /// when it fits.
  void _constructor(DartWriter out, ClientIr ir) {
    out.prose(
      'Creates the client: every group sends through [dio], which it uses '
      'as it is.',
    );
    final initializers = [
      for (final group in ir.groups) '${group.field} = ${group.name}(dio)',
    ];
    final head = '${ir.root.name}(Dio dio)';
    final flat = initializers.isEmpty
        ? '$head;'
        : '$head : ${initializers.join(', ')};';
    if (out.indent.length + flat.length <= width) {
      out.line(flat);
      return;
    }
    out.line(head);
    out.indented(() {
      for (final (i, initializer) in initializers.indexed) {
        final last = i == initializers.length - 1;
        out.line('${i == 0 ? ': ' : '  '}$initializer${last ? ';' : ','}');
      }
    });
  }

  void _server(DartWriter out, ServerIr server) {
    out.prose('`${_code.docSpan(server.url)}`.');
    if (server.description != null) out.line('///');
    out.doc(server.description);
    if (server.variables.isEmpty) {
      out.line('static const ${server.name} = ${_code.string(server.url)};');
      return;
    }
    for (final variable in server.variables) {
      final values = variable.values;
      if (variable.description == null && values.isEmpty) continue;
      out
        ..line('///')
        ..prose(
          '[${variable.name}]'
          '${values.isEmpty ? '' : ', one of '
                    '${values.map(_code.jsonSpan).join(', ')}'}'
          '${variable.description == null ? '.' : ':'}',
        )
        ..doc(variable.description);
    }
    out.list('static String ${server.name}({', [
      for (final v in server.variables)
        if (v.defaultValue case final value?)
          'String ${v.name} = ${_code.string(value)}'
        else
          'required String ${v.name}',
    ], '}) =>');
    out.indented(() {
      out.indented(() {
        out.list('[', _pieces(server), '].join();');
      });
    });
  }

  /// The URL of [server] as the items of a list to join: literals and the
  /// arguments of its variables.
  static List<String> _pieces(ServerIr server) {
    final byName = {for (final v in server.variables) v.wireName: v};
    final pieces = <String>[];
    var start = 0;
    for (final match in OperationBuilder.pathVariable.allMatches(server.url)) {
      final variable = byName[match[1]];
      if (variable == null) continue;
      if (match.start > start) {
        pieces.add(_code.string(server.url.substring(start, match.start)));
      }
      pieces.add(variable.name);
      start = match.end;
    }
    if (start < server.url.length) {
      pieces.add(_code.string(server.url.substring(start)));
    }
    return pieces;
  }
}
````

**New file** `packages/typed_openapi/lib/src/emit/decoder_writer.dart`:

````dart
import '../ir/dart_type.dart';
import '../ir/ir.dart';
import 'dart_code.dart';
import 'dart_writer.dart';
import 'type_codec.dart';

/// Writes the decoder of an operation (R10.6, R11): a `switch` on the status
/// that decodes successes and errors, and the types of both.
final class DecoderWriter {
  /// Creates a writer that writes with [_codec].
  const DecoderWriter(this._codec);

  final TypeCodec _codec;

  static const _code = DartCode();

  /// How Dio reads the body of every status: by the successes' media
  /// types; errors of a text or binary operation are parsed from it.
  static String responseKind(OperationIr operation) {
    final kinds = {
      for (final s in operation.successes)
        if (s.kind != .none) s.kind,
    };
    if (kinds.isEmpty || (kinds.length == 1 && kinds.single == .json)) {
      return 'json';
    }
    if (kinds.length == 1 && kinds.single == .text) return 'text';
    return 'bytes';
  }

  /// The success type `T` of [operation]: its sealed type, the one body
  /// type, `void` without a body, `JsonValue` without a 2xx (TOA653).
  String successType(OperationIr operation) {
    if (operation.successType case final sealed?) return sealed.name;
    final successes = operation.successes;
    if (successes.isEmpty) {
      _codec.imports.fromRuntime('JsonValue');
      return 'JsonValue';
    }
    final type = successes.first.type;
    return type == null ? 'void' : _codec.type(type);
  }

  /// The error type `E` of [operation]: `Never`, the one body type or the
  /// sealed type of its errors.
  String errorType(OperationIr operation) => switch (operation.errors) {
    NoErrors() => 'Never',
    SingleError(:final type) => _codec.type(type),
    ErrorsByStatus() => operation.errorType!.name,
  };

  /// Writes the static method [decoder] of [operation]: a `switch` on
  /// the status, `undocumented()` for any status it does not name.
  void write(DartWriter out, OperationIr operation, String decoder) {
    _codec.imports.fromRuntime('RawResponse');
    final result = 'Result<${successType(operation)}, ${errorType(operation)}>';
    final json = responseKind(operation) == 'json' ? 'r.json' : 'r.parsedJson';
    out.line('static $result $decoder(RawResponse r) =>');
    out.indented(() {
      out.indented(() {
        out.line('switch (r.statusCode) {');
        out.indented(() {
          for (final arm in [
            ..._successArms(operation, json),
            ..._errorArms(operation, json),
          ]) {
            out.line(arm);
          }
          out.line('_ => r.undocumented(),');
        });
        out.line('};');
      });
    });
  }

  List<String> _successArms(OperationIr operation, String json) {
    final successes = operation.successes;
    if (successes.isEmpty) {
      return ['>= 200 && < 300 => r.success(JsonValue($json)),'];
    }
    final sealed = operation.successType;
    final names = {
      for (final c in [...?sealed?.cases]) c.status: c.name,
    };
    return [
      for (final response in _ordered(successes, (r) => r.status))
        '${_pattern(response.status)} => r.success('
            '${_wrap(names[response.status], _value(response, json))}),',
    ];
  }

  List<String> _errorArms(OperationIr operation, String json) {
    switch (operation.errors) {
      case NoErrors():
        return const [];
      case SingleError(:final type, :final statuses):
        final patterns = statuses.isEmpty
            ? ['>= 400 && < 600']
            : [for (final s in _ordered(statuses, (s) => s)) _pattern(s)];
        final pattern = patterns.length == 1
            ? patterns.single
            : patterns.map((p) => p.contains(' ') ? '($p)' : p).join(' || ');
        return ['$pattern => r.error(${_decode(type, json)}),'];
      case ErrorsByStatus():
        final sealed = operation.errorType!;
        return [
          for (final c in _ordered(sealed.cases, (c) => c.status))
            '${_pattern(c.status)} => r.error(${_wrap(c.name, c.type == null ? null : _decode(c.type!, json))}),',
        ];
    }
  }

  /// [items] by status: codes first, then ranges, then `default`, each in
  /// the spec's order, so a code wins over its range.
  static List<T> _ordered<T>(List<T> items, String Function(T) status) {
    int rank(String s) => s == 'default'
        ? 2
        : int.tryParse(s) == null
        ? 1
        : 0;
    final indexed = items.indexed.toList()
      ..sort((a, b) {
        final byRank = rank(status(a.$2)).compareTo(rank(status(b.$2)));
        return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
      });
    return [for (final (_, item) in indexed) item];
  }

  /// The pattern of the status codes [status] stands for: a code, a range
  /// (`4XX`), or for `default` every status but 2xx (an undocumented 2xx is
  /// not an error).
  static String _pattern(String status) {
    if (status == 'default') return '< 200 || >= 300';
    final code = int.tryParse(status);
    if (code != null) return '$code';
    final hundred = int.parse(status[0]) * 100;
    return '>= $hundred && < ${hundred + 100}';
  }

  /// [value] in the variant [name] of a sealed type, or as it is.
  static String _wrap(String? name, String? value) => switch ((name, value)) {
    (null, final value?) => value,
    (null, null) => 'null',
    (final name?, null) => 'const $name()',
    (final name?, final value?) => '$name($value)',
  };

  /// The decoded body of a success, or null without one.
  String? _value(ResponseIr response, String json) {
    final type = response.type;
    if (type == null) return null;
    return switch (response.kind) {
      .text => 'r.text',
      .bytes => 'r.bytes',
      _ when response.envelopeKey != null => _envelope(
        type,
        response.envelopeKey!,
        json,
      ),
      _ => _decode(type, json),
    };
  }

  String _decode(DartType type, String json) {
    final code = type.nullable
        ? 'JsonReader.nullable(${_codec.decoder(type.withNullable(false))})'
              '($json)'
        : _codec.decodeValue(type, json);
    if (code.contains('JsonReader.')) _codec.imports.fromRuntime('JsonReader');
    return code;
  }

  String _envelope(DartType type, String key, String json) {
    _codec.imports.fromRuntime('JsonReader');
    final reader =
        "JsonReader.of($json, schema: 'envelope').${switch (type) {
          CoreType(kind: .json) => 'requiredValue(${_code.string(key)})',
          _ when type.nullable => 'requiredNullable(${_code.string(key)}, '
              '${_codec.decoder(type.withNullable(false))})',
          _ => 'required(${_code.string(key)}, ${_codec.decoder(type)})',
        }}";
    return reader;
  }
}
````

**New file** `packages/typed_openapi/lib/src/emit/operation_emitter.dart`:

````dart
import '../ir/ir.dart';
import '../ir/names.dart';
import 'dart_code.dart';
import 'dart_writer.dart';
import 'decoder_writer.dart';
import 'parts_emitter.dart';
import 'request_writer.dart';
import 'status_type_emitter.dart';
import 'type_codec.dart';

/// Writes the class of a [GroupIr] (decisions 1–3, 5–10 of M9): a plain
/// class, so `implements` mocks it (R10.7), with a method per operation that
/// builds an `OperationRequest` and sends it through `DioRequestSender`;
/// then the sealed types of the operations' statuses and the classes of
/// their multipart parts. [RequestWriter] writes the request,
/// [DecoderWriter] the decoder, [StatusTypeEmitter] and [PartsEmitter] the
/// types.
///
/// Every argument is named and the last one is `CallOptions? call`; a
/// method returns `Future<Result<T, E>>` and never throws for a response.
final class OperationEmitter {
  /// Creates an emitter that writes with [_codec].
  OperationEmitter(this._codec)
    : _request = RequestWriter(_codec),
      _decoder = DecoderWriter(_codec);

  final TypeCodec _codec;
  final RequestWriter _request;
  final DecoderWriter _decoder;

  static const _code = DartCode();
  static const _names = DartNames();

  /// The runtime library generated code imports.
  static const _dio = 'package:dio/dio.dart';

  /// Writes [group] and the types of its operations to [out].
  void write(GroupIr group, DartWriter out) {
    final name = group.name;
    _codec.imports
      ..show(_dio, 'Dio')
      ..fromRuntime('DioRequestSender');
    final members = _privateNames(group);
    out.prose('The operations of the `${_code.docSpan(name)}` group.');
    out.block('class $name', () {
      out
        ..prose('Sends the requests through [dio], which it uses as it is.')
        ..line('$name(Dio dio) : _sender = DioRequestSender(dio);')
        ..line()
        ..line('final DioRequestSender _sender;');
      for (final (operation, info, _) in members) {
        out.line();
        _info(out, operation, info);
      }
      for (final (operation, info, decoder) in members) {
        out.line();
        _method(out, operation, info, decoder);
        out.line();
        _decoder.write(out, operation, decoder);
      }
    });
    _types(out, group);
  }

  /// Writes the sealed status types and the parts classes of the
  /// operations of [group], after the group's class.
  void _types(DartWriter out, GroupIr group) {
    for (final operation in group.operations) {
      for (final (type, what) in [
        (operation.successType, 'successes'),
        (operation.errorType, 'errors'),
      ]) {
        if (type == null) continue;
        out.line();
        StatusTypeEmitter(_codec).write(out, type, operation, group, what);
      }
      if (operation.partsName case final parts?) {
        out.line();
        PartsEmitter(_codec).write(out, parts, operation, group);
      }
    }
  }

  /// The private members of [group]'s class: an `OperationInfo` and a
  /// decoder per operation, named apart from each other and from the
  /// sender.
  static List<(OperationIr, String, String)> _privateNames(GroupIr group) {
    final private = NameScope(reserved: const {}, reservedSuffix: '')
      ..reserve('_sender');
    return [
      for (final operation in group.operations)
        (
          operation,
          private.claim('_${operation.name}').$1,
          private.claim('_decode${_names.pascal(operation.name)}').$1,
        ),
    ];
  }

  void _info(DartWriter out, OperationIr operation, String info) {
    _codec.imports.fromRuntime('OperationInfo');
    out.line('static const $info = OperationInfo(');
    out.indented(() {
      out
        ..line(
          'operationId: '
          '${_code.string(operation.operationId ?? operation.name)},',
        )
        ..line('method: ${_code.string(operation.method)},')
        ..line('pathTemplate: ${_code.string(operation.path)},');
      if (operation.tags.isNotEmpty) {
        out.list('tags: [', [
          for (final tag in operation.tags) _code.string(tag),
        ], '],');
      }
      if (operation.security.isNotEmpty) {
        _codec.imports
          ..fromRuntime('SecurityUse')
          ..fromRuntime('SecurityScheme');
        out.line('security: [');
        out.indented(() {
          for (final alternative in operation.security) {
            out.list('[', [for (final use in alternative) _use(use)], '],');
          }
        });
        out.line('],');
      }
    });
    out.line(');');
  }

  String _use(SecurityUseIr use) {
    final scheme = use.scheme;
    final arguments = [
      _code.string(scheme.name),
      '.${scheme.kind.name}',
      if (scheme.parameterName case final v?)
        'parameterName: ${_code.string(v)}',
      if (scheme.placement case final v?) 'location: .$v',
      if (scheme.scheme case final v?) 'scheme: ${_code.string(v)}',
      if (scheme.bearerFormat case final v?) 'bearerFormat: ${_code.string(v)}',
      if (scheme.openIdConnectUrl case final v?)
        'openIdConnectUrl: ${_code.string(v)}',
    ];
    final scopes = use.scopes.isEmpty
        ? ''
        : ', [${use.scopes.map(_code.string).join(', ')}]';
    return 'SecurityUse(SecurityScheme(${arguments.join(', ')})$scopes)';
  }

  void _method(
    DartWriter out,
    OperationIr operation,
    String info,
    String decoder,
  ) {
    _codec.imports
      ..fromRuntime('Result')
      ..fromRuntime('CallOptions')
      ..fromRuntime('OperationRequest');
    _doc(out, operation);
    if (operation.deprecated) {
      out.line("@Deprecated('Deprecated in the API spec.')");
    }
    final arguments = [
      for (final parameter in operation.parameters)
        '${parameter.required ? 'required ' : ''}'
            '${_codec.known(parameter.type)} ${parameter.name}',
      if (_request.bodyType(operation) case final body?)
        '${operation.body!.required ? 'required ' : ''}$body body',
      'CallOptions? call',
    ];
    out.list(
      'Future<Result<${_decoder.successType(operation)}, '
          '${_decoder.errorType(operation)}>> '
          '${operation.name}({',
      arguments,
      '}) => _sender.send(',
    );
    out.indented(() => _send(out, operation, info, decoder));
    out.line(');');
  }

  /// The arguments of `_sender.send`: the request, the decoder and `call`.
  void _send(
    DartWriter out,
    OperationIr operation,
    String info,
    String decoder,
  ) {
    out.line('OperationRequest(');
    out.indented(() {
      out.line('$info,');
      _request.parameters(out, operation);
      _request.body(out, operation);
      final kind = DecoderWriter.responseKind(operation);
      if (kind != 'json') out.line('responseKind: .$kind,');
    });
    out
      ..line('),')
      ..line('$decoder,')
      ..line('call: call,');
  }

  /// The doc comment of a method: summary, description, method and path,
  /// and the parameters that have a description or a default.
  void _doc(DartWriter out, OperationIr operation) {
    out.doc(operation.summary);
    if (operation.summary != null && operation.description != null) {
      out.line('///');
    }
    out.doc(operation.description);
    if (operation.summary != null || operation.description != null) {
      out.line('///');
    }
    out.prose(
      '`${_code.docSpan('${operation.method} ${operation.path}')}`'
      '${operation.operationId == null ? '' : ' '
                '(`${_code.docSpan(operation.operationId!)}`)'}.',
    );
    for (final parameter in operation.parameters) {
      final defaultValue = parameter.defaultValue;
      if (parameter.description == null && defaultValue == null) continue;
      out
        ..line('///')
        ..prose(
          '[${parameter.name}]'
          '${parameter.deprecated ? ' (deprecated)' : ''}'
          '${defaultValue == null ? '' : ', when not sent, is '
                    '${_code.jsonSpan(defaultValue.$1)} on the server'}'
          '${parameter.description == null ? '.' : ':'}',
        )
        ..doc(parameter.description);
    }
  }
}
````

**New file** `packages/typed_openapi/lib/src/emit/parts_emitter.dart`:

````dart
import '../ir/dart_type.dart';
import '../ir/ir.dart';
import 'dart_code.dart';
import 'dart_writer.dart';
import 'type_codec.dart';

/// Writes the class of the parts of a multipart body (R10.4): a field per
/// part, `FileUpload` for files, and `toParts()`.
final class PartsEmitter {
  /// Creates an emitter that writes with [_codec].
  const PartsEmitter(this._codec);

  final TypeCodec _codec;

  static const _code = DartCode();

  /// Writes the class [name] of the parts of [operation] of [group].
  void write(
    DartWriter out,
    String name,
    OperationIr operation,
    GroupIr group,
  ) {
    final parts = operation.body!.parts!;
    _codec.imports
      ..fromRuntime('MultipartPart')
      ..fromRuntime('immutable');
    out
      ..prose(
        'The parts of the `multipart/form-data` body of '
        '[${group.name}.${operation.name}].',
      )
      ..line('@immutable')
      ..block('class $name', () {
        out
          ..prose('Creates the parts.')
          ..list('const $name({', [
            for (final p in parts)
              '${p.required ? 'required ' : ''}this.${p.name}',
          ], '});');
        for (final part in parts) {
          out.line();
          out.doc(part.description);
          out.line('final ${_partType(part.type)} ${part.name};');
        }
        out
          ..line()
          ..prose('The parts, in the order of the schema.')
          ..line('List<MultipartPart> toParts() => [');
        out.indented(() {
          for (final part in parts) {
            out.line('${_part(part)},');
          }
        });
        out.line('];');
      });
  }

  /// The Dart type of a part: a binary string is a `FileUpload`, also as
  /// the items of a list.
  String _partType(DartType type) {
    final mark = type.nullable ? '?' : '';
    if (_isFile(type)) {
      _codec.imports.fromRuntime('FileUpload');
      return 'FileUpload$mark';
    }
    if (type case ListType(:final item) when _isFile(item)) {
      _codec.imports.fromRuntime('FileUpload');
      return 'List<FileUpload${item.nullable ? '?' : ''}>$mark';
    }
    return _codec.known(type);
  }

  static bool _isFile(DartType type) =>
      type is CoreType && type.kind == CoreKind.binary;

  String _part(PartIr part) {
    final wire = _code.string(part.wireName);
    final type = part.type;
    final contentType = part.contentType == null
        ? ''
        : ', contentType: ${_code.string(part.contentType!)}';
    if (_isFile(type)) {
      return type.nullable
          ? 'if (${part.name} case final file?) '
                'MultipartPart.file($wire, file$contentType)'
          : 'MultipartPart.file($wire, ${part.name}$contentType)';
    }
    if (type case ListType(:final item) when _isFile(item)) {
      final files = type.nullable ? '...?${part.name}' : '...${part.name}';
      return 'for (final file in [$files]) '
          '${item.nullable ? 'if (file != null) ' : ''}'
          'MultipartPart.file($wire, file$contentType)';
    }
    return 'MultipartPart.value($wire, '
        '${_codec.encodeNullable(type, part.name)}$contentType)';
  }
}
````

**New file** `packages/typed_openapi/lib/src/emit/request_writer.dart`:

````dart
import '../ir/dart_type.dart';
import '../ir/ir.dart';
import '../model/operation.dart';
import 'dart_code.dart';
import 'dart_writer.dart';
import 'type_codec.dart';

/// Writes the request of an operation (R10.3, R10.4): its parameter lists
/// and its body, and the type of its `body` argument.
final class RequestWriter {
  /// Creates a writer that writes with [_codec].
  const RequestWriter(this._codec);

  final TypeCodec _codec;

  static const _code = DartCode();

  /// The parameter lists of the request: the JSON form of each value, with
  /// its style when it is not the default.
  void parameters(DartWriter out, OperationIr operation) {
    for (final (placement, list, runtime) in [
      (ParameterLocation.path, 'path', 'PathParameter'),
      (ParameterLocation.query, 'query', 'QueryParameter'),
      (ParameterLocation.header, 'headers', 'HeaderParameter'),
      (ParameterLocation.cookie, 'cookies', 'CookieParameter'),
    ]) {
      final parameters = [
        for (final p in operation.parameters)
          if (p.placement == placement) p,
      ];
      if (parameters.isEmpty) continue;
      _codec.imports.fromRuntime(runtime);
      out.list('$list: [', [
        for (final p in parameters) _parameter(p, runtime),
      ], '],');
    }
  }

  String _parameter(ParameterIr parameter, String runtime) {
    final value = _json(parameter.type, parameter.name);
    final style = parameter.style;
    final options = [
      if (style != null &&
          style != .simple &&
          style != .form &&
          style != .cookie)
        'style: .${style.name}',
      if (parameter.explode case final explode?) 'explode: $explode',
      if (parameter.allowReserved && parameter.placement == .query)
        'allowReserved: true',
    ];
    final encoded = switch (parameter.contentType) {
      final type? when _isJson(type) => _jsonText(
        value,
        parameter.type.nullable,
      ),
      _ => value,
    };
    return '$runtime(${[_code.string(parameter.wireName), encoded, ...options].join(', ')})';
  }

  /// The JSON form of [name], a value of [type].
  String _json(DartType type, String name) => _codec.encodeNullable(type, name);

  String _jsonText(String value, bool nullable) {
    _codec.imports.show('dart:convert', 'jsonEncode');
    return nullable
        ? '$value == null ? null : jsonEncode($value)'
        : 'jsonEncode($value)';
  }

  /// The type of the `body` argument; null without a body.
  String? bodyType(OperationIr operation) {
    final body = operation.body;
    if (body == null || body.kind == .none) return null;
    final mark = body.required ? '' : '?';
    if (operation.partsName case final parts?) return '$parts$mark';
    final type = body.type;
    if (type == null) return null;
    if (body.kind == .bytes) {
      _codec.imports.fromRuntime('FileUpload');
      return 'FileUpload$mark';
    }
    final shown = body.required ? type : type.withNullable(true);
    return _codec.known(shown);
  }

  /// Writes the body of the request and its `Content-Type`; nothing
  /// without a body.
  void body(DartWriter out, OperationIr operation) {
    final body = operation.body;
    if (bodyType(operation) == null) return;
    final value = _value(operation, body!);
    if (value == null) return;
    out
      ..line('body: $value,')
      ..line('contentType: ${_code.string(_contentType(body))},');
  }

  /// The expression of the body sent: `null` stays `null` for an optional
  /// body.
  String? _value(OperationIr operation, RequestBodyIr body) {
    final optional = !body.required;
    final type = body.type;
    final String value;
    switch (body.kind) {
      case .multipart when operation.partsName != null:
        _codec.imports.fromRuntime('MultipartBody');
        value = optional
            ? 'body == null ? null : MultipartBody(body.toParts())'
            : 'MultipartBody(body.toParts())';
      case .multipart:
        _codec.imports.fromRuntime('MultipartBody');
        final json = _json(type!, 'body');
        value = optional
            ? 'body == null ? null : MultipartBody.fromJson($json)'
            : 'MultipartBody.fromJson($json)';
      case .form:
        _codec.imports.fromRuntime('FormBody');
        final json = _json(type!, 'body');
        final encoding = [
          for (final e in body.encoding)
            if (_formEncoding(e) case final code?)
              '${_code.string(e.property)}: $code',
        ];
        final form = encoding.isEmpty
            ? 'FormBody($json)'
            : 'FormBody($json, {${encoding.join(', ')}})';
        value = optional ? 'body == null ? null : $form' : form;
      case .bytes || .text || .eventStream:
        value = 'body';
      case .json:
        value = _json(optional ? type!.withNullable(true) : type!, 'body');
      case .none:
        return null;
    }
    return value;
  }

  String? _formEncoding(EncodingIr encoding) {
    final arguments = [
      if (encoding.style case final style? when style != .form)
        'style: .${style.name}',
      if (encoding.explode case final explode?) 'explode: $explode',
      if (encoding.allowReserved) 'allowReserved: true',
      if (encoding.contentType case final type? when _isJson(type))
        'json: true',
    ];
    if (arguments.isEmpty) return null;
    _codec.imports.fromRuntime('FormEncoding');
    return 'FormEncoding(${arguments.join(', ')})';
  }

  /// The `Content-Type` of a body: its media type, or a concrete one for a
  /// wildcard (`*/*`, `image/*`).
  static String _contentType(RequestBodyIr body) {
    final type = body.contentType!;
    if (!type.contains('*')) return type;
    return switch (body.kind) {
      .json => 'application/json',
      .text || .eventStream => 'text/plain',
      _ => 'application/octet-stream',
    };
  }

  static bool _isJson(String contentType) {
    final type = contentType.split(';').first.trim().toLowerCase();
    return type == 'application/json' ||
        type == 'text/json' ||
        type.endsWith('+json');
  }
}
````

**New file** `packages/typed_openapi/lib/src/emit/status_type_emitter.dart`:

````dart
import '../ir/dart_type.dart';
import '../ir/ir.dart';
import 'dart_code.dart';
import 'dart_writer.dart';
import 'type_codec.dart';

/// Writes a sealed status type of an operation (decision 18 of M8): the
/// base, and a variant per status that wraps the body and is equal by value.
final class StatusTypeEmitter {
  /// Creates an emitter that writes with [_codec].
  const StatusTypeEmitter(this._codec);

  final TypeCodec _codec;

  static const _code = DartCode();

  /// Writes [type], the sealed type of the [what] of [operation] of
  /// [group].
  void write(
    DartWriter out,
    StatusTypeIr type,
    OperationIr operation,
    GroupIr group,
    String what,
  ) {
    final method = '${group.name}.${operation.name}';
    out
      ..prose(
        'The $what of [$method], by status: a `switch` names every one.',
      )
      ..block('sealed class ${type.name}', () {
        out
          ..prose('Creates the value.')
          ..line('const ${type.name}();');
      });
    for (final variant in type.cases) {
      out
        ..line()
        ..prose(
          'The `${_code.docSpan(variant.status)}` response of [$method]'
          '${variant.type == null ? ', which has no body.' : '.'}',
        )
        ..block('class ${variant.name} extends ${type.name}', () {
          switch (variant.type) {
            case final body?:
              _withBody(out, variant.name, body);
            case null:
              _withoutBody(out, variant.name);
          }
        });
    }
  }

  static void _withoutBody(DartWriter out, String name) {
    out
      ..prose('Creates the value.')
      ..line('const $name();')
      ..line()
      ..line('@override')
      ..line('bool operator ==(Object other) => other is $name;')
      ..line()
      ..line('@override')
      ..line('int get hashCode => ($name).hashCode;');
  }

  void _withBody(DartWriter out, String name, DartType body) {
    final deep = _codec.needsDeep(body);
    if (deep) _codec.imports.fromRuntime('DeepEquality');
    out
      ..prose('Wraps [body].')
      ..line('const $name(this.body);')
      ..line()
      ..prose('The body of the response.')
      ..line('final ${_codec.type(body)} body;')
      ..line()
      ..line('@override')
      ..chain('bool operator ==(Object other) =>', [
        'other is $name',
        if (deep)
          'const DeepEquality().equals(other.body, body)'
        else
          'other.body == body',
      ], '&&')
      ..line()
      ..line('@override')
      ..line(
        deep
            ? 'int get hashCode => const DeepEquality().hash(body);'
            : 'int get hashCode => body.hashCode;',
      );
  }
}
````

**Diff** (apply from the repository root with `git apply`):

````diff
diff --git a/packages/typed_openapi/lib/src/emit/model_library.dart b/packages/typed_openapi/lib/src/emit/model_library.dart
index 13a9f7b..3928db9 100644
--- a/packages/typed_openapi/lib/src/emit/model_library.dart
+++ b/packages/typed_openapi/lib/src/emit/model_library.dart
@@ -55,12 +55,12 @@ final class ModelLibrary {
           UnionEmitter(codec).write(decl, body);
       }
       final out = DartWriter(width);
-      _writeHeader(out);
+      writeHeader(out);
       imports.write(out);
       files['$directory/$file'] = '${out.text}${body.text}';
     }
     final exports = DartWriter(width);
-    _writeHeader(exports);
+    writeHeader(exports);
     final paths = files.keys.toList()..sort();
     for (final path in paths) {
       exports.line('export ${_code.string(path)};');
@@ -74,13 +74,13 @@ final class ModelLibrary {
     final scope = NameScope(reserved: const {}, reservedSuffix: '');
     return {
       for (final declaration in ir.declarations)
-        declaration.id: '${scope.claim(_snake(declaration.name)).$1}.dart',
+        declaration.id: '${scope.claim(snake(declaration.name)).$1}.dart',
     };
   }
 
   /// [name] in lower snake case; a name that does not start with a letter
   /// gets `type_` in front, as Dart file names must.
-  static String _snake(String name) {
+  static String snake(String name) {
     final snake = _names.words(name).map((w) => w.toLowerCase()).join('_');
     return snake.startsWith(RegExp('[a-z]')) ? snake : 'type_$snake';
   }
@@ -88,7 +88,7 @@ final class ModelLibrary {
   static const _code = DartCode();
 
   /// Writes [header] and an empty line.
-  static void _writeHeader(DartWriter out) {
+  static void writeHeader(DartWriter out) {
     header.trimRight().split('\n').forEach(out.line);
     out.line();
   }
diff --git a/packages/typed_openapi_runtime/lib/src/request/multipart_body.dart b/packages/typed_openapi_runtime/lib/src/request/multipart_body.dart
index 19afedd..0e6cbbe 100644
--- a/packages/typed_openapi_runtime/lib/src/request/multipart_body.dart
+++ b/packages/typed_openapi_runtime/lib/src/request/multipart_body.dart
@@ -11,10 +11,13 @@ final class MultipartPart {
   const MultipartPart.value(this.name, this.value, {this.contentType})
     : file = null;
 
-  /// A file part.
-  const MultipartPart.file(this.name, FileUpload this.file)
-    : value = null,
-      contentType = null;
+  /// A file part; [contentType], the spec's `encoding` for the property,
+  /// is the media type when [file] has none.
+  const MultipartPart.file(
+    this.name,
+    FileUpload this.file, {
+    this.contentType,
+  }) : value = null;
 
   /// The name of the part (the property name).
   final String name;
@@ -25,7 +28,7 @@ final class MultipartPart {
   /// The file of a file part.
   final FileUpload? file;
 
-  /// The media type of a value part, from the spec's `encoding`.
+  /// The media type of the part, from the spec's `encoding`.
   final String? contentType;
 }
 
@@ -35,6 +38,22 @@ final class MultipartBody {
   /// Creates the body.
   const MultipartBody(this.parts);
 
+  /// The body of [json], the JSON of a body whose schema has no parts of
+  /// its own: a value part for each property, in order; `null` has none.
+  /// Anything but an object throws [ArgumentError].
+  factory MultipartBody.fromJson(Object? json) => switch (json) {
+    null => const MultipartBody([]),
+    final Map<String, Object?> object => MultipartBody([
+      for (final MapEntry(:key, :value) in object.entries)
+        MultipartPart.value(key, value),
+    ]),
+    final other => throw ArgumentError.value(
+      other,
+      'json',
+      'A multipart body must be a JSON object',
+    ),
+  };
+
   /// The parts, in order.
   final List<MultipartPart> parts;
 }
````

- [ ] **Step 4: Write the goldens and read them**

From `packages/typed_openapi`: `UPDATE_GOLDENS=1 dart test test/emit/api_library_test.dart`, then `dart test test/emit/api_library_test.dart` (green). Read `test/emit/goldens/petstore/api/pets_api.dart.golden` and `api_client.dart.golden` before committing: they are the contract of the output (13 files: `api.dart`, `api/default_api.dart`, `api/pets_api.dart`, `api/store_api.dart`, `api_client.dart`, `models.dart` and 7 models).

- [ ] **Step 5: Update the documentation**

**Diff** (apply from the repository root with `git apply`):

````diff
diff --git a/CLAUDE.md b/CLAUDE.md
index e012711..f1c148c 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -375,6 +375,30 @@ All under `packages/typed_openapi/lib/src/`, one folder per stage:
   over every branch it keeps); `UnionDecl.unknownSensitive` (a secret
   anywhere in any branch) and a secret variant make the unknown variant
   print `<redacted>`.
+- `emit/` for operations (M9): `ApiLibrary` writes the whole client: the
+  files of `ModelLibrary`, a file per group in `api/` (snake case of the
+  class, its own name scope, so model files never move), the barrel
+  `api.dart` and the root `<client>.dart` (`_client` added when that is a
+  barrel's name), which exports both barrels and holds the root class
+  (`ClientIr.root`: a field per group, servers as `static const` or a
+  `static String` method of the URL variables; it never sets a base URL).
+  `OperationEmitter` writes a group: a plain `class` with
+  `{Group}(Dio dio)`, a private `OperationInfo` (tags, security) and a
+  static decoder per operation (private names apart in their own scope),
+  methods with named arguments only (`required` for required ones; enum
+  arguments take the known values), `body`, then `CallOptions? call`,
+  returning `Future<Result<T, E>>` from `DioRequestSender.send`; the
+  decoder switches on the status: codes, then ranges, then `default`
+  (every status but 2xx), `_` is `undocumented()`; Dio reads JSON unless
+  every success with a body is text (`text`) or something else is
+  (`bytes`), and then error bodies go through `RawResponse.parsedJson`.
+  Bodies: JSON (`toJson`), `FormBody` with `FormEncoding`s, the parts class
+  (`toParts()`, `FileUpload` for binary strings and lists of them,
+  `encoding` media types) or `MultipartBody.fromJson` (TOA655),
+  `FileUpload` for binary, `String` for text; a wildcard media type is sent
+  as a concrete one. It writes the sealed status types (variants extend the
+  base and wrap `body`, equal by value) and the parts classes after the
+  group class. Only `Dio` is imported from `package:dio`.
 - `generate/` - `OutputWriter` (atomic per run: the whole tree and the
   manifest `.typed_openapi.json` (generator, `format` 2, hash of the inputs,
   every file with its hash) are built in a staging directory next to the
diff --git a/packages/typed_openapi/CHANGELOG.md b/packages/typed_openapi/CHANGELOG.md
index 5585f5f..308d9cf 100644
--- a/packages/typed_openapi/CHANGELOG.md
+++ b/packages/typed_openapi/CHANGELOG.md
@@ -1,6 +1,17 @@
 ## 0.0.1 - Unreleased
 
 ### Added
+- Operations (M9): an API class per group in `api/` (`PetsApi(Dio dio)`, a
+  plain class that `implements` can mock), the barrel `api.dart` and the
+  root client in `<client>.dart` (`PetstoreClient(Dio dio)` with a field per
+  group, the servers as constants or methods of their variables), which
+  exports the models and the API. Methods take named arguments, `body` and
+  `CallOptions? call`, and return `Future<Result<T, E>>`: JSON, text and
+  binary successes, sealed types for several successes or errors with
+  different bodies, envelopes, typed errors, `UndocumentedStatus`; bodies
+  are JSON, forms with their `encoding`, multipart parts with `FileUpload`
+  files, binary `FileUpload`s and text. Every request carries its
+  `OperationInfo` with tags and security metadata.
 - Models (M8): `generate` writes the models of every client without check
   errors into its `output` directory: a file per model, enum and union in
   `models/` and the barrel `models.dart`. Every file starts with
diff --git a/packages/typed_openapi_runtime/CHANGELOG.md b/packages/typed_openapi_runtime/CHANGELOG.md
index 7dc841f..676e3d7 100644
--- a/packages/typed_openapi_runtime/CHANGELOG.md
+++ b/packages/typed_openapi_runtime/CHANGELOG.md
@@ -18,7 +18,9 @@
 - For generated operations: `FileUpload` (bytes or a stream, with a file
   name and a media type), `FormBody` and `FormEncoding`
   (`application/x-www-form-urlencoded` with the spec's `encoding`),
-  `MultipartBody` and `MultipartPart`; `DioRequestSender` turns them into
+  `MultipartBody` (also `MultipartBody.fromJson`) and `MultipartPart`
+  (a file part takes the spec's media type when the file has none);
+  `DioRequestSender` turns them into
   what Dio sends, so generated signatures have no Dio types.
 - Security metadata for interceptors: `OperationInfo.security` with
   `SecurityUse`, `SecurityScheme`, `SecuritySchemeType` and
````

- [ ] **Step 6: Verify**

Run from the root:

```bash
dart pub get
dart analyze packages        # No issues found!
```

From `packages/typed_openapi`: `dart format lib test bin` (a second run changes 0 files) and `dart test` (expected `+954: All tests passed!`, the size ratchet `test/quality/size_limits_test.dart` included). From `packages/typed_openapi_runtime`: `dart format lib test` (the same) and `dart test` (expected `+184: All tests passed!`).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(typed_openapi): emit API classes, the root client and status types

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>

# Conflicts:
#	packages/typed_openapi_runtime/lib/src/dio/dio_request_sender.dart"
```

---

### Task 5: Gates: dart analyze on generated clients and real calls through a fake Dio adapter

**Files:**
- Modify: `CLAUDE.md`
- Create: `packages/typed_openapi/test/emit/generated_client_test.dart`
- Create: `packages/typed_openapi/test/emit/programs/calls.dart.txt`

**Interfaces:**
- Consumes: task 4: `emitClient`, the fixtures; runtime `FileUpload`, `CallOptions`, `OperationInfo.of`.
- Produces: `test/emit/generated_client_test.dart`; `test/emit/programs/calls.dart.txt` (copied to `bin/calls.dart` of the generated package).

The analyzer gate builds one package from the clients of `petstore`, `hostile_operations` and the M8 fixtures in both `union` modes, with `dio` and the runtime by path, and runs `dart analyze --fatal-infos` under `package:lints/recommended` plus the `flutter_lints` rules (listed, so `pub get --offline` works). The calls program drives the petstore client through an in-memory Dio adapter: path parameters in `simple`, `label` and `matrix` (explode), query parameters in `form`, `pipeDelimited`, `deepObject` and with `allowReserved` (`//` kept under an absolute base URL), JSON `content`, a header and a cookie parameter; a JSON body, a form with `encoding`, multipart with `FileUpload` bytes and stream, a binary body with a file's own media type and a text body; 200/201/204 (sealed success type), a documented error per status (sealed error type, `4XX`, a body-less 503), `default`, an undocumented 302, decode errors at their pointer, an envelope, text and binary successes with JSON errors, cancellation, a transport error, `CallOptions` headers and receive progress, the security metadata seen by an interceptor, the root's server methods and a `FakePets implements PetsApi`. The program's file is `.txt` so the repository's analyzer does not read it.

- [ ] **Step 1: Write the failing tests**

**New file** `packages/typed_openapi/test/emit/generated_client_test.dart`:

````dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/config/generation_config.dart';
import 'package:typed_openapi/src/overrides/override_set.dart';

import '../helpers/emit_fixture.dart';
import '../helpers/temp_dir.dart';

/// Runs `dart` with [arguments] in [directory].
ProcessResult dart(List<String> arguments, String directory) => Process.runSync(
  Platform.resolvedExecutable,
  arguments,
  workingDirectory: directory,
);

void main() {
  group('a package of generated clients', () {
    late String package;

    setUpAll(() {
      final temp = TempDir();
      package = temp.path;
      final runtime = p.normalize(
        p.absolute(p.join('..', 'typed_openapi_runtime')),
      );
      temp
        ..write('pubspec.yaml', '''
name: fixture
publish_to: none
environment:
  sdk: ">=3.10.0 <4.0.0"
dependencies:
  dio: ^5.11.1
  typed_openapi_runtime:
    path: ${runtime.replaceAll(r'\', '/')}
dev_dependencies:
  lints: ^6.1.0
''')
        // package:lints/recommended and the rules flutter_lints adds.
        ..write('analysis_options.yaml', '''
include: package:lints/recommended.yaml
linter:
  rules:
    - avoid_print
    - avoid_unnecessary_containers
    - avoid_web_libraries_in_flutter
    - no_logic_in_create_state
    - prefer_const_constructors_in_immutables
    - sized_box_for_whitespace
    - sort_child_properties_last
    - use_build_context_synchronously
    - use_full_hex_values_for_flutter_colors
    - use_key_in_widget_constructors
''')
        ..write(
          'bin/calls.dart',
          File(
            p.join('test', 'emit', 'programs', 'calls.dart.txt'),
          ).readAsStringSync(),
        );
      for (final fixture in [
        'petstore',
        'hostile_operations',
        'pets',
        'everything',
        'hostile',
        'secrets',
        'hierarchy',
      ]) {
        for (final mode in UnionMode.values) {
          final files = emitClient(
            '$fixture.yaml',
            generation: GenerationConfig(union: mode),
          );
          for (final MapEntry(:key, :value) in files.entries) {
            temp.write(p.join('lib', '${fixture}_${mode.name}', key), value);
          }
        }
      }
      final get = dart(['pub', 'get', '--offline'], package);
      expect(get.exitCode, 0, reason: '${get.stdout}${get.stderr}');
    });

    test('passes dart analyze with the recommended lints (R13.2)', () {
      final result = dart(['analyze', '--fatal-infos'], package);
      expect(result.exitCode, 0, reason: '${result.stdout}');
    });

    test('sends requests and decodes every outcome (R10, R11)', () {
      final result = dart(['run', 'bin/calls.dart'], package);
      expect(result.stderr, '');
      expect(result.stdout, _calls);
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// What `bin/calls.dart` prints: each call's request and result.
const _calls = '''
server https://us.pets.example.com/v1 http://localhost:8080
success 200 Pets Rex
GET https://pets.example.com/v1/pets?limit=5&tags=a%20b%7Cc&status=available,sold&filter%5Bkind%5D=dog&next=/a//b?c&where=%7B%22age%22%3A3%7D [listPets; bearer]
headers t-1 session=s%201
error 500 Problem down
success 200 Ok Rex
success 201 Created job-1
success 204 NoContent
error 404 NotFound gone
error 422 ClientError bad
error 503 ServiceUnavailable
undocumented 302
decode /id an integer
body {"id":1,"name":"Rex","status":"available"}
success 200 Pet 7 Tom null
GET https://pets.example.com/v1/pets/7 [getPet; bearer]
success 204 null
DELETE https://pets.example.com/v1/pets/7 [deletePet; ] reason=old
success 200 bytes 3
received 3
GET https://pets.example.com/v1/pets/.7/photo [getPhoto; bearer]
error 404 Problem nophoto
success 200 text hello
GET https://pets.example.com/v1/pets/;petId=1;petId=2/note [getNote; bearer]
error 404 Problem nonote
success 204 null
application/octet-stream png
success 204 null
image/gif gif
success 204 null
multipart [true, true, true, true]
success 200 Order 3 pending
POST https://pets.example.com/v1/store/orders [placeOrder; apiKey|] application/x-www-form-urlencoded petId=1&tags=a,b&meta%5Bk%5D=v
success 200 json {"any":true}
text/plain note
error 400 json {"ok":false}
success 200 null
extra 1
cancelled
transport
decode /data/id an integer
''';
````

**New file** `packages/typed_openapi/test/emit/programs/calls.dart.txt`:

````dart
// A program that calls the petstore client generated from
// test/emit/fixtures/petstore.yaml through a Dio whose adapter answers from
// memory, and prints what was sent and what each call returned.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fixture/petstore_raw/api_client.dart';
import 'package:typed_openapi_runtime/typed_openapi_runtime.dart';

/// Answers each request with the next response of [answers].
final class Adapter implements HttpClientAdapter {
  final List<ResponseBody Function()> answers = [];
  final List<RequestOptions> requests = [];
  final List<String> bodies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
    }
    bodies.add(utf8.decode(bytes, allowMalformed: true));
    return answers.removeAt(0)();
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(int status, Object? body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

ResponseBody empty(int status) => ResponseBody.fromString('', status);

ResponseBody bytes(int status, List<int> data, String type) =>
    ResponseBody.fromBytes(
      data,
      status,
      headers: {
        Headers.contentTypeHeader: [type],
      },
    );

String show(Result<Object?, Object?> result) => switch (result) {
  Success(:final data, :final statusCode) => 'success $statusCode ${describe(data)}',
  HttpError(:final body, :final statusCode) => 'error $statusCode ${describe(body)}',
  UndocumentedStatus(:final statusCode) => 'undocumented $statusCode',
  DecodeError(:final error) => 'decode ${error.pointer} ${error.expected}',
  TransportError() => 'transport',
  Cancelled() => 'cancelled',
};

String describe(Object? value) => switch (value) {
  null => 'null',
  final Uint8List data => 'bytes ${data.length}',
  CreatePetResponseOk(:final body) => 'Ok ${body.name}',
  CreatePetResponseCreated(:final body) => 'Created ${body.id}',
  CreatePetResponseNoContent() => 'NoContent',
  CreatePetErrorNotFound(:final body) => 'NotFound ${body.code}',
  CreatePetErrorClientError(:final body) => 'ClientError ${body.id}',
  CreatePetErrorServiceUnavailable() => 'ServiceUnavailable',
  final Pet pet => 'Pet ${pet.id} ${pet.name} ${pet.status?.value}',
  final List<Pet> pets => 'Pets ${pets.map((p) => p.name).join(',')}',
  final Problem problem => 'Problem ${problem.code}',
  final PlaceOrderResponse order => 'Order ${order.id} ${order.status?.value}',
  final String text => 'text $text',
  // JsonValue and models.
  _ => 'json ${jsonEncode(value)}',
};

String request(Adapter adapter) {
  final options = adapter.requests.last;
  final info = OperationInfo.of(options);
  return '${options.method} ${options.uri} '
      '[${info?.operationId}; ${info?.security.map((a) => a.join('+')).join('|')}]';
}

Future<void> main() async {
  final adapter = Adapter();
  final dio = Dio(BaseOptions(baseUrl: 'https://pets.example.com/v1'))
    ..httpClientAdapter = adapter;
  final client = ApiClient(dio);
  final pets = client.pets;

  print('server ${ApiClient.server1(region: 'us')} ${ApiClient.server2}');

  adapter.answers.add(() => json(200, [{'id': 1, 'name': 'Rex', 'status': 'sold'}]));
  print(show(await pets.listPets(
    limit: 5,
    tags: ['a b', 'c'],
    status: [Status.available, Status.sold],
    filter: {'kind': 'dog'},
    next: '/a//b?c',
    where: {'age': 3},
    xTrace: 't-1',
    session: 's 1',
  )));
  print(request(adapter));
  final sent = adapter.requests.last.headers;
  print('headers ${sent['X-Trace']} ${sent['Cookie']}');

  adapter.answers.add(() => json(500, {'code': 'down'}));
  print(show(await pets.listPets(xTrace: 't')));

  for (final answer in [
    () => json(200, {'id': 1, 'name': 'Rex'}),
    () => json(201, {'id': 'job-1'}),
    () => empty(204),
    () => json(404, {'code': 'gone'}),
    () => json(422, {'id': 'bad'}),
    () => empty(503),
    () => empty(302),
    () => json(200, {'id': 'x'}),
  ]) {
    adapter.answers.add(answer);
    print(show(await pets.createPet(body: const Pet(id: 1, name: 'Rex', status: .available))));
  }
  print('body ${adapter.bodies.last}');

  adapter.answers.add(() => json(200, {'data': {'id': 7, 'name': 'Tom'}}));
  // ignore: deprecated_member_use_from_same_package
  print(show(await pets.getPet(petId: 7)));
  print(request(adapter));

  adapter.answers.add(() => empty(204));
  print(show(await pets.deletePet(petId: 7, reason: 'old')));
  print('${request(adapter)} reason=${adapter.requests.last.headers['reason']}');

  adapter.answers.add(() => bytes(200, [1, 2, 3], 'image/png'));
  var received = 0;
  print(show(await pets.getPhoto(
    petId: 7,
    call: CallOptions(onReceiveProgress: (count, _) => received = count),
  )));
  print('received $received');
  print(request(adapter));
  adapter.answers.add(() => bytes(404, utf8.encode('{"code":"nophoto"}'), 'application/json'));
  print(show(await pets.getPhoto(petId: 7)));

  adapter.answers.add(() => ResponseBody.fromString('hello', 200, headers: {
    Headers.contentTypeHeader: ['text/plain'],
  }));
  print(show(await pets.getNote(petId: [1, 2])));
  print(request(adapter));
  adapter.answers.add(() => json(404, {'code': 'nonote'}));
  print(show(await pets.getNote(petId: [1])));

  adapter.answers.add(() => empty(204));
  print(show(await pets.putPhoto(petId: 7, body: FileUpload.bytes(Uint8List.fromList(utf8.encode('png'))))));
  print('${adapter.requests.last.contentType} ${adapter.bodies.last}');
  adapter.answers.add(() => empty(204));
  print(show(await pets.putPhoto(
    petId: 7,
    body: FileUpload.stream(Stream.value(utf8.encode('gif')), length: 3, contentType: 'image/gif'),
  )));
  print('${adapter.requests.last.contentType} ${adapter.bodies.last}');

  adapter.answers.add(() => empty(204));
  print(show(await pets.uploadPhoto(
    petId: 7,
    body: UploadPhotoRequest(
      file: FileUpload.bytes(Uint8List.fromList(utf8.encode('img')), filename: 'a.png'),
      extra: [FileUpload.bytes(Uint8List.fromList(utf8.encode('x')), filename: 'x.bin')],
      caption: 'hi',
      meta: const Job(id: 'j'),
    ),
  )));
  final multipart = adapter.bodies.last;
  print('multipart ${[
    multipart.contains('name="file"; filename="a.png"\r\ncontent-type: image/png'),
    multipart.contains('name="extra"; filename="x.bin"\r\ncontent-type: application/octet-stream'),
    multipart.contains('name="caption"\r\n\r\nhi'),
    multipart.contains('name="meta"\r\ncontent-type: application/json'),
  ]}');

  final store = client.store;
  adapter.answers.add(() => json(200, {'id': 3, 'status': 'pending'}));
  print(show(await store.placeOrder(
    body: const PlaceOrderRequest(petId: 1, tags: ['a', 'b'], meta: {'k': 'v'}),
  )));
  print('${request(adapter)} ${adapter.requests.last.contentType} ${adapter.bodies.last}');

  adapter.answers.add(() => json(200, {'any': true}));
  print(show(await store.sendNote(body: 'note')));
  print('${adapter.requests.last.contentType} ${adapter.bodies.last}');
  adapter.answers.add(() => json(400, {'ok': false}));
  print(show(await store.sendNote()));

  adapter.answers.add(() => empty(200));
  print(show(await client.defaultApi.health(
    call: const CallOptions(headers: {'X-Extra': '1'}),
  )));
  print('extra ${adapter.requests.last.headers['X-Extra']}');

  final token = CancelToken()..cancel('stop');
  print(show(await client.defaultApi.health(call: CallOptions(cancelToken: token))));

  adapter.answers.add(() => throw DioException.connectionError(
    requestOptions: RequestOptions(),
    reason: 'offline',
  ));
  print(show(await client.defaultApi.health()));

  adapter.answers.add(() => json(200, {'data': {'id': 'x'}}));
  // ignore: deprecated_member_use_from_same_package
  print(show(await pets.getPet(petId: 1)));
}

/// A tag class can be faked with `implements` (R10.7).
class FakePets implements PetsApi {
  @override
  Future<Result<void, Never>> deletePet({
    required int petId,
    String? reason,
    CallOptions? call,
  }) async => const Success(null, statusCode: 204);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
````

- [ ] **Step 2: Run the tests to see them fail**

Run from `packages/typed_openapi`: `dart test test/emit/generated_client_test.dart`.
Expected: this task adds a gate on code that exists: it passes at once. To see it fail, change one expected line of `_calls` (it then fails with the difference) and revert.

- [ ] **Step 3: Implement**

- [ ] **Step 4: Update the documentation**

**Diff** (apply from the repository root with `git apply`):

````diff
diff --git a/CLAUDE.md b/CLAUDE.md
index f1c148c..54ead82 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -399,6 +399,11 @@ All under `packages/typed_openapi/lib/src/`, one folder per stage:
   as a concrete one. It writes the sealed status types (variants extend the
   base and wrap `body`, equal by value) and the parts classes after the
   group class. Only `Dio` is imported from `package:dio`.
+  `test/emit/generated_client_test.dart` builds a package of the clients
+  of the fixtures (both `union` modes), runs `dart analyze --fatal-infos`
+  on it and runs `test/emit/programs/calls.dart.txt` (`bin/calls.dart`
+  there), which calls the petstore client through a fake Dio adapter and
+  prints every request and result.
 - `generate/` - `OutputWriter` (atomic per run: the whole tree and the
   manifest `.typed_openapi.json` (generator, `format` 2, hash of the inputs,
   every file with its hash) are built in a staging directory next to the
````

- [ ] **Step 5: Verify**

Run from the root:

```bash
dart pub get
dart analyze packages        # No issues found!
```

From `packages/typed_openapi`: `dart format lib test bin` (a second run changes 0 files) and `dart test` (expected `+956: All tests passed!`, the size ratchet `test/quality/size_limits_test.dart` included). From `packages/typed_openapi_runtime`: `dart format lib test` (the same) and `dart test` (expected `+184: All tests passed!`).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "test(typed_openapi): analyze generated clients and call them through a fake adapter

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `generate` writes the whole client

**Files:**
- Modify: `CLAUDE.md`
- Modify: `packages/typed_openapi/README.md`
- Modify: `packages/typed_openapi/README.ua.md`
- Modify: `packages/typed_openapi/lib/src/cli/generate_command.dart`
- Modify: `packages/typed_openapi/lib/src/ir/ir.dart`
- Modify: `packages/typed_openapi/test/cli/generate_command_test.dart`

**Interfaces:**
- Consumes: task 4: `ApiLibrary`; M8: `GenerateCommand`, `OutputWriter`.
- Produces: `GenerateCommand` writes `ApiLibrary(width: client.lineWidth).files(ir, client: client.name)` through `_files`.

Spec decision 13: the models, the API and the root go through the same `OutputWriter`, so the manifest, `--force`, `--break-lock`, the lock and skipping a client with errors work as in M8 (including the M4 row: an unusable overrides file is an error, so the client is skipped). `GenerateCommand.run` stays at its allowlisted size (`_files` builds the files), and the expectations of `generate_command_test.dart` share one list of the written files, so the file shrinks. `SingleError`'s doc comment now says that no statuses mean every 4xx and 5xx (the M6 row). The README gets an "Operations" section with the `//` guard of the query (the M7 row); `README.ua.md` follows.

- [ ] **Step 1: Write the failing tests**

**Diff** (apply from the repository root with `git apply`):

````diff
diff --git a/packages/typed_openapi/test/cli/generate_command_test.dart b/packages/typed_openapi/test/cli/generate_command_test.dart
index f8c0d71..75d3b0d 100644
--- a/packages/typed_openapi/test/cli/generate_command_test.dart
+++ b/packages/typed_openapi/test/cli/generate_command_test.dart
@@ -29,6 +29,16 @@ components:
         status: {type: string, enum: [a, b]}
 ''';
 
+/// The files `generate` writes for [_spec]: models, API and the root.
+const _written = [
+  'api.dart',
+  'api/default_api.dart',
+  'models.dart',
+  'models/pet.dart',
+  'models/pet_status.dart',
+  'pets.dart',
+];
+
 void main() {
   late TempDir dir;
 
@@ -64,36 +74,27 @@ void main() {
     };
   }
 
-  test('writes the models and the manifest, then nothing new', () async {
+  test('writes the client and the manifest, then nothing new', () async {
     const client = '  pets: {input: specs/pets.yaml, output: gen/pets}\n';
     final (code, out) = await generate(client);
     expect(code, 0);
     expect(
       out,
       endsWith(
-        'Generated pets in ${p.join('gen', 'pets')}: 3 files, 3 written, '
+        'Generated pets in ${p.join('gen', 'pets')}: 6 files, 6 written, '
         '0 deleted.\n',
       ),
     );
     final first = tree('gen/pets');
-    expect(first.keys, [
-      '.typed_openapi.json',
-      'models.dart',
-      'models/pet.dart',
-      'models/pet_status.dart',
-    ]);
+    expect(first.keys, ['.typed_openapi.json', ..._written]);
     final manifest =
         jsonDecode(first['.typed_openapi.json']!) as Map<String, Object?>;
     expect(manifest['generator'], OutputWriter.generator);
     expect(manifest['inputs'], hasLength(64));
-    expect((manifest['files']! as Map<String, Object?>).keys, [
-      'models.dart',
-      'models/pet.dart',
-      'models/pet_status.dart',
-    ]);
+    expect((manifest['files']! as Map<String, Object?>).keys, _written);
     final (again, log) = await generate(client);
     expect(again, 0);
-    expect(log, contains('3 files, 0 written, 0 deleted.'));
+    expect(log, contains('6 files, 0 written, 0 deleted.'));
     expect(tree('gen/pets'), first);
   });
 
@@ -110,11 +111,14 @@ void main() {
     );
     final (code, out) = await generate(client);
     expect(code, 0);
-    expect(out, contains('2 files, 2 written, 1 deleted.'));
+    expect(out, contains('5 files, 2 written, 1 deleted.'));
     expect(tree('gen/pets').keys, [
       '.typed_openapi.json',
+      'api.dart',
+      'api/default_api.dart',
       'models.dart',
       'models/pet.dart',
+      'pets.dart',
     ]);
   });
 
@@ -126,7 +130,7 @@ void main() {
     ).createSync(recursive: true);
     final (code, out) = await generate(client);
     expect(code, 0);
-    expect(out, contains('3 files, 0 written, 0 deleted.'));
+    expect(out, contains('6 files, 0 written, 0 deleted.'));
     expect(Directory(p.join(dir.path, 'gen/pets/stale')).existsSync(), isFalse);
   });
 
@@ -311,12 +315,7 @@ void main() {
       expect(out, contains('info TOA833 output-file-replaced'));
       expect(out, contains('notes.txt'));
       expect(out, contains('models/pet.dart'));
-      expect(tree('gen/pets').keys, [
-        '.typed_openapi.json',
-        'models.dart',
-        'models/pet.dart',
-        'models/pet_status.dart',
-      ]);
+      expect(tree('gen/pets').keys, ['.typed_openapi.json', ..._written]);
       expect(tree('gen/pets')['models/pet.dart'], isNot('// my change\n'));
     });
 
@@ -326,7 +325,7 @@ void main() {
       final (code, out) = await generate(client, args: ['--force']);
       expect(code, 0);
       expect(out, isNot(contains('replaced')));
-      expect(out, contains('3 files, 0 written, 0 deleted.'));
+      expect(out, contains('6 files, 0 written, 0 deleted.'));
       expect(tree('gen/pets'), before);
     });
 
````

- [ ] **Step 2: Run the tests to see them fail**

Run from `packages/typed_openapi`: `dart test test/cli/generate_command_test.dart`.
Expected: FAIL: `generate` still writes 3 files (`Generated pets in gen/pets: 3 files`), the tests expect 6.

- [ ] **Step 3: Implement**

**Diff** (apply from the repository root with `git apply`):

````diff
diff --git a/packages/typed_openapi/lib/src/cli/generate_command.dart b/packages/typed_openapi/lib/src/cli/generate_command.dart
index 55aff00..493c0c4 100644
--- a/packages/typed_openapi/lib/src/cli/generate_command.dart
+++ b/packages/typed_openapi/lib/src/cli/generate_command.dart
@@ -11,14 +11,15 @@ import '../config/project_config.dart';
 import '../diagnostics/diagnostic_bag.dart';
 import '../diagnostics/display_paths.dart';
 import '../diagnostics/reporters.dart';
-import '../emit/model_library.dart';
+import '../emit/api_library.dart';
 import '../generate/output_writer.dart';
 import '../generate/real_paths.dart';
+import '../ir/ir.dart';
 import 'check_command.dart';
 
 /// `typed_openapi generate`: checks every client as `check` does and
-/// writes the models of each client without errors into its output
-/// directory (M8; operations come with M9).
+/// writes the whole client of each client without errors into its output
+/// directory: the models, the API classes and the root client (M8, M9).
 ///
 /// A client whose check reports an error, including an overrides file that
 /// cannot be used, is skipped; so is one whose output directory the
@@ -63,7 +64,7 @@ final class GenerateCommand extends Command<int> {
 
   @override
   String get description =>
-      'Check specs and generate the models of clients without errors.';
+      'Check specs and generate the clients without errors.';
 
   @override
   String get invocation =>
@@ -115,7 +116,7 @@ final class GenerateCommand extends Command<int> {
           );
           continue;
         }
-        final files = ModelLibrary(width: client.lineWidth).files(ir);
+        final files = _files(client, ir);
         final changes = writer.write(
           client,
           files,
@@ -144,6 +145,10 @@ final class GenerateCommand extends Command<int> {
         : ExitCode.success.code;
   }
 
+  /// The files of the whole client [client] with the IR [ir].
+  static Map<String, String> _files(ClientConfig client, ClientIr ir) =>
+      ApiLibrary(width: client.lineWidth).files(ir, client: client.name);
+
   /// The names of the clients whose output directory is, or is inside, that
   /// of another client, also through symbolic links or a different case.
   static Set<String> _overlapping(List<ClientConfig> clients) => {
diff --git a/packages/typed_openapi/lib/src/ir/ir.dart b/packages/typed_openapi/lib/src/ir/ir.dart
index b98b44a..2ec8450 100644
--- a/packages/typed_openapi/lib/src/ir/ir.dart
+++ b/packages/typed_openapi/lib/src/ir/ir.dart
@@ -800,7 +800,7 @@ final class SingleError extends ErrorsIr {
   /// The body type of every error.
   final DartType type;
 
-  /// The documented error statuses.
+  /// The documented error statuses; empty means every 4xx and 5xx one.
   final List<String> statuses;
 }
 
````

- [ ] **Step 4: Update the documentation**

**Diff** (apply from the repository root with `git apply`):

````diff
diff --git a/CLAUDE.md b/CLAUDE.md
index 54ead82..f97b70b 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -486,7 +486,7 @@ All under `packages/typed_openapi/lib/src/`, one folder per stage:
   `BaselineCommand` (`baseline_command.dart`, subcommands `create` and
   `prune`), `GenerateCommand` (`generate_command.dart`: checks like
   `check`, skips a client with errors (`ClientCheck.errors`) or an output
-  that overlaps another's, writes the models with `ModelLibrary` and
+  that overlaps another's, writes the whole client with `ApiLibrary` and
   `OutputWriter`, the inputs hash from `ClientCheck.sources` and the
   client's settings; text report, then a line per client; exit code as
   `check`) and the hidden `IrCommand` (`ir_command.dart`, prints the IR of
diff --git a/packages/typed_openapi/README.md b/packages/typed_openapi/README.md
index 4c32355..b36c484 100644
--- a/packages/typed_openapi/README.md
+++ b/packages/typed_openapi/README.md
@@ -31,7 +31,7 @@ dart run typed_openapi check core_api   # one client
 dart run typed_openapi check --format json   # also: sarif, github-actions
 ```
 
-Generate the models of the clients whose check has no errors (a client with
+Generate the clients whose check has no errors (a client with
 errors is skipped, and the exit code is the one `check` gives):
 
 ```sh
@@ -94,6 +94,51 @@ you can extend them); a union base is `sealed`.
   its schema could carry a secret: any model or union variant it may hold,
   at any depth, has a secret property.
 
+The operations of a client are in `api/<group>.dart`, one plain class per
+group (`PetsApi`), exported by `api.dart`; the root `<client>.dart`
+(`petstore.dart`, `api_client.dart` for a client named `api` or `models`)
+exports the models and the API and holds the root class:
+
+```dart
+final client = PetstoreClient(dio); // naming.client renames it
+switch (await client.pets.getPet(petId: 1)) {
+  case Success(:final data):
+    print(data.name);
+  case HttpError(:final body):
+    print(body.code);
+  case Failure():
+    print('another failure');
+}
+```
+
+- Every argument is named, required ones are `required`, the request body is
+  `body` and the last argument is `CallOptions? call` (cancel token, extra
+  headers, progress, `extra` for interceptors). A method returns
+  `Future<Result<T, E>>` and never throws for a response: a documented error
+  is `HttpError` with the decoded body, any other status
+  `UndocumentedStatus`, a body that does not decode `DecodeError`, a network
+  failure `TransportError`, a cancelled call `Cancelled`.
+- `T` is the one success body (`void` without one, `JsonValue` when no 2xx
+  is documented, TOA653), or a sealed type when 2xx responses differ
+  (`CreatePetResponseOk`, `...Created`). `E` is `Never` without documented
+  errors, the one error body, or a sealed type by status
+  (`CreatePetErrorNotFound`, `...ClientError` for `4XX`, `...Other` for
+  `default`). Text successes are `String`, binary ones `Uint8List`; their
+  JSON error bodies are decoded too.
+- Bodies: JSON models; forms with the spec's `encoding`; multipart parts as a
+  class (`UploadPhotoRequest`) whose binary properties are `FileUpload`s
+  (`FileUpload.bytes`, which works on the web, or `FileUpload.stream`); a
+  binary body is a `FileUpload`. Event streams come with M10 (TOA654).
+- The client never changes your Dio: set the base URL there, from the root
+  class's server constants (`PetstoreClient.server`, or a method such as
+  `PetstoreClient.server1(region: 'eu')` for a URL with variables). When the
+  query holds `//` (an `allowReserved` value) and the base URL is absolute,
+  the runtime joins them itself, because Dio would collapse the `//`; a
+  relative base URL is left to Dio, which then collapses it.
+- Every request carries an `OperationInfo` in `RequestOptions.extra`
+  (`OperationInfo.of(options)`): the `operationId`, tags and the security
+  requirements with their schemes, for an interceptor that adds credentials.
+
 `generate` writes each output directory as a whole. It builds the new tree and
 a manifest (`.typed_openapi.json`: the generator, the manifest format, a hash
 of the inputs and the hash of every file) next to the output and swaps it in,
diff --git a/packages/typed_openapi/README.ua.md b/packages/typed_openapi/README.ua.md
index db0b3c5..6280b21 100644
--- a/packages/typed_openapi/README.ua.md
+++ b/packages/typed_openapi/README.ua.md
@@ -32,7 +32,7 @@ dart run typed_openapi check core_api   # один клієнт
 dart run typed_openapi check --format json   # також: sarif, github-actions
 ```
 
-Згенеруй моделі клієнтів, у яких перевірка не знайшла помилок (клієнт з
+Згенеруй клієнти, у яких перевірка не знайшла помилок (клієнт з
 помилками пропускається, а код виходу такий, як у `check`):
 
 ```sh
@@ -95,6 +95,28 @@ union — `sealed`.
   містити секрет: будь-яка модель чи варіант union-а, які воно може
   тримати, на будь-якій глибині має секретну властивість.
 
+Операції клієнта — у `api/<група>.dart`, звичайний клас на групу
+(`PetsApi`), експортує їх `api.dart`; корінь `<клієнт>.dart` (`petstore.dart`,
+`api_client.dart` для клієнта `api` чи `models`) експортує моделі й API і
+містить кореневий клас `PetstoreClient(dio)` (`naming.client` його
+перейменовує) з полем на групу: `client.pets.getPet(petId: 1)`.
+
+- Усі аргументи іменовані, обов'язкові — `required`, тіло — `body`, останній
+  — `CallOptions? call`. Метод повертає `Future<Result<T, E>>` і не кидає
+  винятків на відповідь: задокументована помилка — `HttpError`, інший статус
+  — `UndocumentedStatus`, тіло, що не декодується, — `DecodeError`, мережа —
+  `TransportError`, скасування — `Cancelled`.
+- `T` — тіло успіху (`void` без тіла, `JsonValue`, коли 2xx не описано,
+  TOA653) або sealed-тип за статусом, коли 2xx різні; `E` — `Never`, тіло
+  помилки або sealed-тип за статусом (`CreatePetErrorNotFound`).
+- Тіла: JSON, форми з `encoding`, multipart-частини як клас, де файли —
+  `FileUpload`, бінарне тіло — `FileUpload`. Потоки подій — у M10 (TOA654).
+- Клієнт не змінює твій Dio: base URL задаєш ти, з констант серверів
+  кореневого класу. Коли query містить `//`, а base URL абсолютний, runtime
+  з'єднує їх сам; відносний base URL лишається Dio, який `//` схлопує.
+- Кожен запит несе `OperationInfo` у `RequestOptions.extra`: `operationId`,
+  теги й вимоги безпеки для інтерсептора, що додає облікові дані.
+
 `generate` пише каталог виходу цілим. Він будує нове дерево і маніфест
 (`.typed_openapi.json`: генератор, формат маніфесту, хеш входів і хеш кожного
 файлу) поруч із виходом і підміняє ним старий каталог, тож невдалий запуск
````

- [ ] **Step 5: Verify**

Run from the root:

```bash
dart pub get
dart analyze packages        # No issues found!
```

From `packages/typed_openapi`: `dart format lib test bin` (a second run changes 0 files) and `dart test` (expected `+956: All tests passed!`, the size ratchet `test/quality/size_limits_test.dart` included). From `packages/typed_openapi_runtime`: `dart format lib test` (the same) and `dart test` (expected `+184: All tests passed!`).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(typed_openapi): generate writes the whole client

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Fixes from the corpus run and the fuzz

**Files:**
- Modify: `packages/typed_openapi/lib/src/emit/dart_code.dart`
- Modify: `packages/typed_openapi/lib/src/emit/operation_emitter.dart`
- Modify: `packages/typed_openapi/lib/src/emit/parts_emitter.dart`
- Modify: `packages/typed_openapi/lib/src/emit/request_writer.dart`
- Modify: `packages/typed_openapi/lib/src/emit/union_emitter.dart`
- Modify: `packages/typed_openapi/test/emit/dart_writer_test.dart`
- Modify: `packages/typed_openapi/test/emit/fixtures/hostile_operations.yaml`
- Modify: `packages/typed_openapi/test/emit/fixtures/petstore.yaml`
- Generated: 1 golden files under `packages/typed_openapi/test/emit/goldens/petstore/` (`UPDATE_GOLDENS=1`)

**Interfaces:**
- Consumes: tasks 4-6.
- Produces: `OperationEmitter._argument`, `PartsEmitter._parameter`, `RequestWriter._jsonText(ParameterIr)`/`_bodyJson`; `DartCode.docLines` keeps code spans on one line.

The corpus run (14 clients, both `union` modes) and the fuzz (6000 seeds) found five defects; each now has a fixture line that fails without the fix (the analyzer gate of task 5 reports them):
- an optional `JsonValue` argument or part had no default (`missing_default_value_for_parameter`, airflow, medusa): it defaults to `const JsonValue(null)`;
- a nullable non-file part was read twice from a field (`unchecked_use_of_nullable_value`, openai): it is read into a local with `if (x case final value?)`;
- an optional form or multipart body with a nullable schema used `?.` inside its null check (`invalid_null_aware_operator`), and a JSON `content` parameter checked `null` twice (`unnecessary_null_comparison`): the value inside the check is encoded as non-null, and an absent `JsonValue` is not sent;
- `SecurityUse` was imported for operations whose only alternative is empty (`unused_shown_name`): it is imported where a use is written;
- an M8 union variant whose `$ref` target is nullable called `value.toJson()` (`unchecked_use_of_nullable_value`): `encodeNullable`;
- a long doc line broke a code span over two lines, and the analyzer read `<json-pointer>` in its second half as HTML (`unintended_html_in_doc_comment`, ditto): `docLines` wraps like `proseLines`, never inside a span.

- [ ] **Step 1: Write the failing tests**

**Diff** (apply from the repository root with `git apply`):

````diff
diff --git a/packages/typed_openapi/test/emit/dart_writer_test.dart b/packages/typed_openapi/test/emit/dart_writer_test.dart
index 91a7e34..0635cfd 100644
--- a/packages/typed_openapi/test/emit/dart_writer_test.dart
+++ b/packages/typed_openapi/test/emit/dart_writer_test.dart
@@ -70,6 +70,14 @@ void main() {
       expect(code.docLines('a\x01b', 80), ['ab']);
     });
 
+    test('never breaks a code span when it wraps (corpus: ditto)', () {
+      expect(code.docLines('Both `{{ thing-json:<json-pointer> }}` work', 24), [
+        'Both',
+        '`{{ thing-json:<json-pointer> }}`',
+        'work',
+      ]);
+    });
+
     test('neutralises doc directives', () {
       expect(code.docLines('See {@link Foo} and {@template t}', 80), [
         r'See \{@link Foo} and \{@template t}',
diff --git a/packages/typed_openapi/test/emit/fixtures/hostile_operations.yaml b/packages/typed_openapi/test/emit/fixtures/hostile_operations.yaml
index cd8fd17..704cefc 100644
--- a/packages/typed_openapi/test/emit/fixtures/hostile_operations.yaml
+++ b/packages/typed_openapi/test/emit/fixtures/hostile_operations.yaml
@@ -51,8 +51,38 @@ paths:
                 "*/ injected": {type: string, format: binary}
                 toParts: {type: string}
                 hashCode: {type: integer}
+                any: {}
       responses:
         "204": {description: ok}
+  /d:
+    get:
+      operationId: anonymous
+      tags: [anon]
+      security: [{}]
+      parameters:
+        - {name: j, in: query, content: {application/json: {schema: {type: object, properties: {a: {type: string}}}}}}
+        - {name: jv, in: query, content: {application/json: {schema: {}}}}
+        - {name: jr, in: query, required: true, content: {application/json: {schema: {$ref: '#/components/schemas/Node'}}}}
+      responses:
+        "200": {description: ok, content: {application/json: {schema: {$ref: '#/components/schemas/Maybe'}}}}
+    post:
+      operationId: optionalBodies
+      tags: [anon]
+      security: [{}]
+      requestBody:
+        content:
+          multipart/form-data:
+            schema: {oneOf: [{$ref: '#/components/schemas/Node'}, {type: string}]}
+      responses: {"204": {description: ok}}
+    put:
+      operationId: optionalForm
+      tags: [anon]
+      security: [{}]
+      requestBody:
+        content:
+          application/x-www-form-urlencoded:
+            schema: {type: [object, 'null'], properties: {a: {type: string}}}
+      responses: {"204": {description: ok}}
 components:
   securitySchemes:
     "k'ey": {type: apiKey, name: "X-'$k", in: header}
@@ -61,6 +91,13 @@ components:
     Options: {type: object, properties: {b: {type: string}}}
     Headers: {type: object, properties: {c: {type: string}}}
     Dio: {type: object, properties: {d: {type: string}}}
+    Maybe:
+      oneOf:
+        - $ref: '#/components/schemas/NullableNode'
+        - {type: string}
+    NullableNode:
+      type: [object, 'null']
+      properties: {a: {type: string}}
     Node:
       type: object
       properties:
diff --git a/packages/typed_openapi/test/emit/fixtures/petstore.yaml b/packages/typed_openapi/test/emit/fixtures/petstore.yaml
index e83b675..d06ebef 100644
--- a/packages/typed_openapi/test/emit/fixtures/petstore.yaml
+++ b/packages/typed_openapi/test/emit/fixtures/petstore.yaml
@@ -22,6 +22,7 @@ paths:
         - {name: where, in: query, content: {application/json: {schema: {type: object, additionalProperties: {type: integer}}}}}
         - {name: X-Trace, in: header, required: true, schema: {type: string}}
         - {name: session, in: cookie, schema: {type: string}}
+        - {name: extra, in: query, schema: {}, description: Any JSON; optional.}
       responses:
         "200":
           description: The pets.
````

- [ ] **Step 2: Run the tests to see them fail**

Run from `packages/typed_openapi`: `dart test test/emit/dart_writer_test.dart test/emit/generated_client_test.dart`.
Expected: FAIL: the new `docLines` test breaks the span; the analyzer gate reports `invalid_null_aware_operator`, `missing_default_value_for_parameter`, `unchecked_use_of_nullable_value` and `unused_shown_name` in `hostile_operations_*`.

- [ ] **Step 3: Implement**

**Diff** (apply from the repository root with `git apply`):

````diff
diff --git a/packages/typed_openapi/lib/src/emit/dart_code.dart b/packages/typed_openapi/lib/src/emit/dart_code.dart
index e29d2b1..1d3f4b5 100644
--- a/packages/typed_openapi/lib/src/emit/dart_code.dart
+++ b/packages/typed_openapi/lib/src/emit/dart_code.dart
@@ -95,7 +95,9 @@ final class DartCode {
         lines.add(line);
         continue;
       }
-      lines.addAll(_wrap(_escapeDoc(line), width < 20 ? 20 : width));
+      // A code span stays on one line: the analyzer reads the text of a
+      // span that starts on the line before as Markdown.
+      lines.addAll(proseLines(_escapeDoc(line), width));
     }
     while (lines.isNotEmpty && lines.last.isEmpty) {
       lines.removeLast();
diff --git a/packages/typed_openapi/lib/src/emit/operation_emitter.dart b/packages/typed_openapi/lib/src/emit/operation_emitter.dart
index 0a338c2..2617db4 100644
--- a/packages/typed_openapi/lib/src/emit/operation_emitter.dart
+++ b/packages/typed_openapi/lib/src/emit/operation_emitter.dart
@@ -114,9 +114,6 @@ final class OperationEmitter {
         ], '],');
       }
       if (operation.security.isNotEmpty) {
-        _codec.imports
-          ..fromRuntime('SecurityUse')
-          ..fromRuntime('SecurityScheme');
         out.line('security: [');
         out.indented(() {
           for (final alternative in operation.security) {
@@ -130,6 +127,9 @@ final class OperationEmitter {
   }
 
   String _use(SecurityUseIr use) {
+    _codec.imports
+      ..fromRuntime('SecurityUse')
+      ..fromRuntime('SecurityScheme');
     final scheme = use.scheme;
     final arguments = [
       _code.string(scheme.name),
@@ -164,10 +164,13 @@ final class OperationEmitter {
     }
     final arguments = [
       for (final parameter in operation.parameters)
-        '${parameter.required ? 'required ' : ''}'
-            '${_codec.known(parameter.type)} ${parameter.name}',
+        _argument(
+          _codec.known(parameter.type),
+          parameter.name,
+          isRequired: parameter.required,
+        ),
       if (_request.bodyType(operation) case final body?)
-        '${operation.body!.required ? 'required ' : ''}$body body',
+        _argument(body, 'body', isRequired: operation.body!.required),
       'CallOptions? call',
     ];
     out.list(
@@ -202,6 +205,19 @@ final class OperationEmitter {
       ..line('call: call,');
   }
 
+  /// The declaration of a named argument: `required` when it is, and
+  /// `JsonValue`, which is never nullable, defaults to JSON `null` when it
+  /// is optional.
+  static String _argument(
+    String type,
+    String name, {
+    required bool isRequired,
+  }) {
+    if (isRequired) return 'required $type $name';
+    if (type == 'JsonValue') return '$type $name = const JsonValue(null)';
+    return '$type $name';
+  }
+
   /// The doc comment of a method: summary, description, method and path,
   /// and the parameters that have a description or a default.
   void _doc(DartWriter out, OperationIr operation) {
diff --git a/packages/typed_openapi/lib/src/emit/parts_emitter.dart b/packages/typed_openapi/lib/src/emit/parts_emitter.dart
index 7b39812..b8f7852 100644
--- a/packages/typed_openapi/lib/src/emit/parts_emitter.dart
+++ b/packages/typed_openapi/lib/src/emit/parts_emitter.dart
@@ -35,8 +35,7 @@ final class PartsEmitter {
         out
           ..prose('Creates the parts.')
           ..list('const $name({', [
-            for (final p in parts)
-              '${p.required ? 'required ' : ''}this.${p.name}',
+            for (final part in parts) _parameter(part),
           ], '});');
         for (final part in parts) {
           out.line();
@@ -56,6 +55,16 @@ final class PartsEmitter {
       });
   }
 
+  /// The constructor parameter of [part]: `required` when it is, and a
+  /// `JsonValue`, which is never nullable, defaults to JSON `null`.
+  static String _parameter(PartIr part) {
+    if (part.required) return 'required this.${part.name}';
+    if (part.type case CoreType(kind: .json)) {
+      return 'this.${part.name} = const JsonValue(null)';
+    }
+    return 'this.${part.name}';
+  }
+
   /// The Dart type of a part: a binary string is a `FileUpload`, also as
   /// the items of a list.
   String _partType(DartType type) {
@@ -92,6 +101,12 @@ final class PartsEmitter {
           '${item.nullable ? 'if (file != null) ' : ''}'
           'MultipartPart.file($wire, file$contentType)';
     }
+    // A field is not promoted: a nullable one is read into a local.
+    if (type.nullable && !_codec.isIdentity(type)) {
+      return 'if (${part.name} case final value?) '
+          'MultipartPart.value($wire, '
+          '${_codec.encode(type.withNullable(false), 'value')}$contentType)';
+    }
     return 'MultipartPart.value($wire, '
         '${_codec.encodeNullable(type, part.name)}$contentType)';
   }
diff --git a/packages/typed_openapi/lib/src/emit/request_writer.dart b/packages/typed_openapi/lib/src/emit/request_writer.dart
index 154680e..f5fa792 100644
--- a/packages/typed_openapi/lib/src/emit/request_writer.dart
+++ b/packages/typed_openapi/lib/src/emit/request_writer.dart
@@ -50,10 +50,7 @@ final class RequestWriter {
         'allowReserved: true',
     ];
     final encoded = switch (parameter.contentType) {
-      final type? when _isJson(type) => _jsonText(
-        value,
-        parameter.type.nullable,
-      ),
+      final type? when _isJson(type) => _jsonText(parameter),
       _ => value,
     };
     return '$runtime(${[_code.string(parameter.wireName), encoded, ...options].join(', ')})';
@@ -62,13 +59,25 @@ final class RequestWriter {
   /// The JSON form of [name], a value of [type].
   String _json(DartType type, String name) => _codec.encodeNullable(type, name);
 
-  String _jsonText(String value, bool nullable) {
+  /// The JSON text of a parameter with a JSON `content`; an absent value
+  /// (`null`, also `JsonValue(null)`) is not sent.
+  String _jsonText(ParameterIr parameter) {
     _codec.imports.show('dart:convert', 'jsonEncode');
-    return nullable
-        ? '$value == null ? null : jsonEncode($value)'
-        : 'jsonEncode($value)';
+    final ParameterIr(:name, :type) = parameter;
+    if (type case CoreType(kind: .json)) {
+      return '$name.isNull ? null : jsonEncode($name)';
+    }
+    if (!type.nullable) return 'jsonEncode(${_codec.encode(type, name)})';
+    return '$name == null ? null : '
+        'jsonEncode(${_codec.encode(type.withNullable(false), name)})';
   }
 
+  /// The JSON form of the body inside its null check: an optional body is
+  /// not `null` there.
+  String _bodyJson(DartType type, {required bool isOptional}) => isOptional
+      ? _codec.encode(type.withNullable(false), 'body')
+      : _json(type, 'body');
+
   /// The type of the `body` argument; null without a body.
   String? bodyType(OperationIr operation) {
     final body = operation.body;
@@ -111,13 +120,13 @@ final class RequestWriter {
             : 'MultipartBody(body.toParts())';
       case .multipart:
         _codec.imports.fromRuntime('MultipartBody');
-        final json = _json(type!, 'body');
+        final json = _bodyJson(type!, isOptional: optional);
         value = optional
             ? 'body == null ? null : MultipartBody.fromJson($json)'
             : 'MultipartBody.fromJson($json)';
       case .form:
         _codec.imports.fromRuntime('FormBody');
-        final json = _json(type!, 'body');
+        final json = _bodyJson(type!, isOptional: optional);
         final encoding = [
           for (final e in body.encoding)
             if (_formEncoding(e) case final code?)
diff --git a/packages/typed_openapi/lib/src/emit/union_emitter.dart b/packages/typed_openapi/lib/src/emit/union_emitter.dart
index 8b87350..ada0238 100644
--- a/packages/typed_openapi/lib/src/emit/union_emitter.dart
+++ b/packages/typed_openapi/lib/src/emit/union_emitter.dart
@@ -358,7 +358,7 @@ final class UnionEmitter {
   /// object (the one it keeps as received may be anything), so the
   /// discriminator is added to an object only.
   String _toJson(UnionDecl decl, UnionVariantIr variant) {
-    final encoded = _codec.encode(variant.type, 'value');
+    final encoded = _codec.encodeNullable(variant.type, 'value');
     if (!_remembers(decl, variant)) return encoded;
     final key = _code.string(decl.discriminator!);
     final tag = switch (_firstValue(variant)) {
````

- [ ] **Step 4: Write the goldens and read them**

The petstore fixture has a new optional `JsonValue` parameter and the parts class reads `meta` into a local: from `packages/typed_openapi`, `UPDATE_GOLDENS=1 dart test test/emit/api_library_test.dart`; only `api/pets_api.dart.golden` changes.

- [ ] **Step 5: Verify**

Run from the root:

```bash
dart pub get
dart analyze packages        # No issues found!
```

From `packages/typed_openapi`: `dart format lib test bin` (a second run changes 0 files) and `dart test` (expected `+957: All tests passed!`, the size ratchet `test/quality/size_limits_test.dart` included). From `packages/typed_openapi_runtime`: `dart format lib test` (the same) and `dart test` (expected `+184: All tests passed!`).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "fix(typed_openapi): fix what the corpus and the fuzz found in generated operations

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Documentation: what M9 closed and what it deferred

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/roadmap.md`

**Interfaces:**
- Consumes: tasks 1-7.
- Produces: `docs/roadmap.md` (the M9 rows answered, "Moved from M9"), `CLAUDE.md` (the collaborators).

Every roadmap row with M9 as its target gets its answer: done (with the task) or moved with a reason (table "Carried over" below), and a "Moved from M9" section lists what M9 deferred. `CLAUDE.md` names the collaborators of the IR and the emitter.

- [ ] **Step 1: Implement**

- [ ] **Step 2: Update the documentation**

**Diff** (apply from the repository root with `git apply`):

````diff
diff --git a/CLAUDE.md b/CLAUDE.md
index f97b70b..6646322 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -279,7 +279,10 @@ All under `packages/typed_openapi/lib/src/`, one folder per stage:
   object); `OperationBuilder` keeps security requirements (TOA568 for an
   unknown scheme), skips event-stream operations (TOA654) and reports
   operation servers (TOA566), callbacks and webhooks (TOA567) and a missing
-  2xx (TOA653); method names,
+  2xx (TOA653) through collaborators (`SecurityBuilder`, `PartsBuilder`,
+  `BodyEncoding`, `OperationChecks`); `ApiNames.client` assembles the
+  `ClientIr`; the IR types only the API emitter reads are in `api_ir.dart`,
+  which `ir.dart` exports; method names,
   override names first, then
   `operationId` without the `operation_prefix`, then the path; TOA563 when
   no operation is generated, at the config client if filters left some
@@ -382,7 +385,9 @@ All under `packages/typed_openapi/lib/src/`, one folder per stage:
   barrel's name), which exports both barrels and holds the root class
   (`ClientIr.root`: a field per group, servers as `static const` or a
   `static String` method of the URL variables; it never sets a base URL).
-  `OperationEmitter` writes a group: a plain `class` with
+  `OperationEmitter` (with `RequestWriter` for parameters and bodies,
+  `DecoderWriter` for the status `switch`, `StatusTypeEmitter` and
+  `PartsEmitter` for the types after the class) writes a group: a plain `class` with
   `{Group}(Dio dio)`, a private `OperationInfo` (tags, security) and a
   static decoder per operation (private names apart in their own scope),
   methods with named arguments only (`required` for required ones; enum
@@ -589,8 +594,8 @@ that the API composes, including an `implements` fake of a tag class.
   a generated decoder switches on; `parsedJson` parses a JSON body that Dio
   read as text or bytes), and the bodies `FileUpload` (bytes or a stream),
   `FormBody`/`FormEncoding` and `MultipartBody`/`MultipartPart`, which
-  `DioRequestSender` turns into form text, `FormData` and bytes or a
-  stream.
+  `DioBody` (`dio/`) turns into form text, `FormData` and bytes or a
+  stream for `DioRequestSender`.
 - `dio/` - `DioRequestSender(dio, {isWeb})` (`send`, `openEvents`; requests
   only through `dio.request`, never mutates the user's Dio, never retries;
   decoding catches only `DioException`, `JsonDecodeException` and, from the
diff --git a/docs/roadmap.md b/docs/roadmap.md
index 707e5ae..dc91f7a 100644
--- a/docs/roadmap.md
+++ b/docs/roadmap.md
@@ -14,7 +14,7 @@ Date: 2026-10-11. Each stage is a separate plan in `superpowers/plans/`, and eac
 | M6 | Semantic IR and Dart mapping | Naming and collisions, inline schemas; filters and tree-shaking; required × nullable matrix; types and formats; `allOf`; envelopes; custom types and converters; tri-state rule | R4, R5, R6.1–R6.4, R6.8, R7.2 | M3, M4 |
 | M7 | Runtime | `ApiResult` and errors, `Patch<T>`, `JsonReader` with pointer, `JsonValue`, parameter style codecs, `sendRequest` on Dio, SSE decoder per WHATWG | R6.5, R7.1, R10.1–R10.3, R10.5, R11.2, R11.3, R11.7, R12.3 | — (in parallel with M2–M6) |
 | M8 | Model emitter | Classes (not `final`) with `fromJson`/`toJson`, deep `==`/`hashCode`, `toString` without secrets; open enum, union with unknown (discriminator, JSON type, `union: structural`), polymorphism via `allOf`, tri-state, constraints and values as doc comments, own code layout without `dart_style` (`// dart format off`), determinism, the `generate` command for models: atomic swap of the output directory and a file manifest. No `copyWith` | R6.5–R6.8, R7, R8, R9, R13 | M6, M7 |
-| M9 | Operation emitter and `generate` | Groups by tag, root client, parameters and bodies (JSON, multipart, form, binary), responses, typed errors, security metadata, servers; `generate` (which already writes models from M8) adds the operations | R5.3, R10.4, R10.6–R10.9, R11.1, R11.4–R11.6 | M8 |
+| M9 | Operation emitter and `generate` | Groups by tag, root client, parameters and bodies (JSON, multipart, form, binary), responses, typed errors, security metadata, servers; `generate` (which already writes models from M8) adds the operations. Plan: [2026-10-13-m9-operations.md](superpowers/plans/2026-10-13-m9-operations.md) | R5.3, R10.4, R10.6–R10.9, R11.1, R11.4–R11.6 | M8 |
 | M10 | SSE | Methods returning a `Stream` of events, schemas with `itemSchema`, `x-` or override, reconnection with `Last-Event-ID` | R12.1, R12.2, R12.4, R12.5 (R12.6 later) | M9, M7 |
 | M11 | Corpus and golden tests | Public specifications (Petstore, Stripe, GitHub, OpenAI, Kubernetes) compile and pass the analyzer; runtime decoding tests; matrix of SDK and formatter versions; fuzz of string escaping | R15.3, R15.4, R2.6 | M9 |
 | M12 | Evolution | `diff` between regenerations with change categories (including source-breaking for an exhaustive `switch`), lock file | R14 | M9 |
@@ -60,13 +60,13 @@ M2 review findings that were deliberately deferred:
 
 | What | Where |
 |---|---|
-| A `$ref` to `file:///` reads any local file without a directory or size limit | before `generate` (M9) and `diff` (M12); the size limit together with it |
-| Sibling keys next to `$ref` in a Path Item (allowed in OAS) are not merged with the target | M9 (operation emitter): M6 does not do this, because the M2 parser puts them into `Ref.unknownKeys` (TOA110) and merging requires a change to the parser |
+| A `$ref` to `file:///` reads any local file without a directory or size limit | after M9: `diff` (M12) or before 1.0; `generate` writes only into its own output and never deletes an input, and a `$ref` reads a file the user's own spec names (M9 plan, "Carried over") |
+| Sibling keys next to `$ref` in a Path Item (allowed in OAS) are not merged with the target | when needed: OAS leaves a conflict undefined and TOA110 reports every sibling, so nothing is lost silently; merging needs a change to the parser (M9 plan) |
 | Case-insensitive file systems: `A.yaml` and `a.yaml` are two documents | when needed (diagnostic or URI normalization) |
 | The YAML merge key `<<` gives no hint that OpenAPI tools often do not support it | M3 (a normalizer rule or a hint) |
 | The model is immutable only on the surface: lists and maps inside nodes are read-only, but not deeply | M3, when the normalizer starts building new nodes |
-| `$ref` in `callbacks` and `links` does not resolve | before the operation emitter (M9) |
-| `in` in an `apiKey` security scheme is not required when reading | before the security metadata (M9) |
+| `$ref` in `callbacks` and `links` does not resolve | with the generation of callbacks: M9 does not generate them and reports callbacks and webhooks (TOA567); links are never read (M9 plan) |
+| `in` in an `apiKey` security scheme is not required when reading | done in M9 (task 2: TOA112, as for `name`) |
 | Positions in diagnostics for files reached through `$ref` are relative paths, not absolute URIs | M5 (`sarif`, `github-actions` formats) |
 | A place read as nodes of two different types silently returns `null` for the second | M3 (diagnostic for a type conflict) |
 | A diagnostic on a node obtained through a YAML alias points to the anchor's position | when needed (a rare case) |
@@ -98,7 +98,7 @@ M4 review findings that were deliberately deferred:
 
 | What | Where |
 |---|---|
-| `NormalizedSpec.overrides` contains also entries that were not applied (TOA804/805/806), with their generation fields; `generate` does not distinguish "the overrides file is unusable" from "there are no overrides" | M9 (skipping a client in `generate`); the IR already takes only the entries that were applied (`IrOverrides`), and `check` checks the specification without the unusable file |
+| `NormalizedSpec.overrides` contains also entries that were not applied (TOA804/805/806), with their generation fields; `generate` does not distinguish "the overrides file is unusable" from "there are no overrides" | done: `generate` skips a client with errors, which an unusable overrides file always gives (TOA801-TOA803, TOA805, TOA806), and the IR reads only applied entries (`IrOverrides`); checked again in M9 |
 | Problems introduced by the override itself are reported at the specification's pointer, not at the override | M5 |
 | `_content`: with a `null` media object the value of another media type is taken | when needed (defective specifications only) |
 | 3.0: after expanding a nullable `$ref`, the sibling fields of `$ref` remain, but 3.0 ignores them; a schema with `anyOf` and `oneOf` containing null expands only `anyOf`; `type: 'null'` + override `type: null` → TOA807 unchanged | when needed |
@@ -127,15 +127,15 @@ M6 review findings and items deferred in the plan, which were deliberately left.
 
 | What | Where |
 |---|---|
-| Request body: the media type's `encoding` (for forms — `style`/`explode` of each property, for multipart — `contentType` and part headers, file name) is parsed, but the IR has none of it, and there is no diagnostic. In the corpus: 312 of 611 Stripe `x-www-form-urlencoded` bodies have `encoding` (deepObject/explode); file parts are `Uint8List` without a name or type (R10.4) | M9: add to `RequestBodyIr` or read explicitly from the specification by `location` |
-| Names of types that the emitter creates are not named in the IR: the sealed error type `ErrorsByStatus` and its variants (1047 operations of the corpus), the variant classes of a union and the unknown variant (R9.1), the success type when the 2xx bodies differ (31 operations, e.g. Discord `guildSearch`: 200 `GuildSearchResponse` / 202 `SearchIndexNotReadyResponse`). The natural names are already taken: for `getPet` with an inline 404 and a 500 without a body the inline model is `GetPetError`, so the sealed `GetPetError` would clash with it. `NameScope` is internal and `ClientIr` keeps only the final names, so the emitter would have to rebuild the namespace, the reserved sets and TOA550/551 itself | M8/M9: decide in the M8 plan — either name them in the IR (after the declarations, with diagnostics), or give the emitters the library's namespace |
-| Constraints (R6.7) are missing from `FieldIr`, `default` is in `ParameterIr`; the plan said "on the nodes", but that is inaccurate: M8 would have to derive them from the specification by `location`. The `description`, `deprecated`, `defaultValue` fields are there (3.1+: own ones next to `$ref` take precedence over the target's) | M8 (R6.7, doc comments, constructor default values); a parameter's `default` — M9 |
-| `in: querystring` parameter (OpenAPI 3.2) is skipped with TOA564, because the runtime has no "whole query string" parameter; `style` is checked against `in` (fixed in M6: TOA564, fallback — default style) | M9: support `querystring` when the runtime gets it |
-| `SingleError(type, const [])` — what an empty `statuses` list means: "all 4xx/5xx" (yes, when `errors.default_schema` is set and the operation has no described errors); `ir.dart` says only "documented statuses" | M9: describe it in the doc comment and read it as "all" |
-| An operation whose only response is `default` with a body has no success type (`default` is always an error); there is no such operation in the corpus | M9 |
-| The generated API library imports `package:dio`, and `Response`, `Options`, `Headers` are common schema names; `DartNames.takenTypeNames` does not reserve them | M9: either add `Dio` and fix the contract "import dio and `dart:typed_data` via `show`", or reserve the dio exports; record the choice |
-| The path variable pattern in the IR (`\{([^}]*)\}`, `ir_builder.dart`, `operation_builder.dart`) differs from the runtime (`\{([^{}]+)\}`): `/c/{}` is TOA556 in the IR, while the runtime reads `{}` as text | M9: one definition |
-| TOA561 `media-type-as-bytes` covers two findings (the body becomes bytes; alternative media types were dropped); all 57 corpus cases are the second, so `severity: {media-type-as-bytes: off}` also silences the first. Numbering: decision 3 of the plan put media types and errors in 6xx, while TOA561/TOA562 are in 5xx | M9: split the code and align the numbering, while the codes are not yet published (catalog — M13) |
+| Request body: the media type's `encoding` (for forms — `style`/`explode` of each property, for multipart — `contentType` and part headers, file name) is parsed, but the IR has none of it, and there is no diagnostic. In the corpus: 312 of 611 Stripe `x-www-form-urlencoded` bodies have `encoding` (deepObject/explode); file parts are `Uint8List` without a name or type (R10.4) | done in M9 (tasks 2-4: `EncodingIr`, `FormEncoding`, multipart part media types, `FileUpload` with a file name; part headers are TOA656) |
+| Names of types that the emitter creates are not named in the IR: the sealed error type `ErrorsByStatus` and its variants (1047 operations of the corpus), the variant classes of a union and the unknown variant (R9.1), the success type when the 2xx bodies differ (31 operations, e.g. Discord `guildSearch`: 200 `GuildSearchResponse` / 202 `SearchIndexNotReadyResponse`). The natural names are already taken: for `getPet` with an inline 404 and a 500 without a body the inline model is `GetPetError`, so the sealed `GetPetError` would clash with it. `NameScope` is internal and `ClientIr` keeps only the final names, so the emitter would have to rebuild the namespace, the reserved sets and TOA550/551 itself | done: M8 names the union and enum helpers; M9 names the status types, parts classes and the root client after them (task 3, `ApiNames`) |
+| Constraints (R6.7) are missing from `FieldIr`, `default` is in `ParameterIr`; the plan said "on the nodes", but that is inaccurate: M8 would have to derive them from the specification by `location`. The `description`, `deprecated`, `defaultValue` fields are there (3.1+: own ones next to `$ref` take precedence over the target's) | done (M8: constraints; M9 task 2: `ParameterIr.defaultValue`, in the method's doc comment) |
+| `in: querystring` parameter (OpenAPI 3.2) is skipped with TOA564, because the runtime has no "whole query string" parameter; `style` is checked against `in` (fixed in M6: TOA564, fallback — default style) | when needed: TOA565 (split from TOA564 in M9) says the parameter is not generated; no corpus spec has one |
+| `SingleError(type, const [])` — what an empty `statuses` list means: "all 4xx/5xx" (yes, when `errors.default_schema` is set and the operation has no described errors); `ir.dart` says only "documented statuses" | done in M9 (task 6: the doc comment says every 4xx and 5xx; the decoder reads it so) |
+| An operation whose only response is `default` with a body has no success type (`default` is always an error); there is no such operation in the corpus | done in M9 (task 3: TOA653; any 2xx is a success with the body as `JsonValue`) |
+| The generated API library imports `package:dio`, and `Response`, `Options`, `Headers` are common schema names; `DartNames.takenTypeNames` does not reserve them | done in M9 (task 2: the API files import only `Dio` with `show`; `Dio` and the new runtime names are reserved, `Response`, `Options` and `Headers` stay free) |
+| The path variable pattern in the IR (`\{([^}]*)\}`, `ir_builder.dart`, `operation_builder.dart`) differs from the runtime (`\{([^{}]+)\}`): `/c/{}` is TOA556 in the IR, while the runtime reads `{}` as text | done in M9 (task 2: `OperationBuilder.pathVariable` equals `OperationRequest.pathVariable`, a test keeps them equal) |
+| TOA561 `media-type-as-bytes` covers two findings (the body becomes bytes; alternative media types were dropped); all 57 corpus cases are the second, so `severity: {media-type-as-bytes: off}` also silences the first. Numbering: decision 3 of the plan put media types and errors in 6xx, while TOA561/TOA562 are in 5xx | done in M9 (task 2: TOA650 and TOA651; TOA562 became TOA652) |
 | Duplicate types of union variants remain silently: `anyOf: [string, {string, uuid}, $ref A, $ref A]` gives `String \| String \| A \| A`; without a discriminator the emitter cannot tell the variants apart | M8 (together with `oneOf` without a discriminator, R9.2) |
 | `{}` in a PATCH body is never tri-state (`JsonValue` is not nullable, and the `.patch` rule requires a nullable value): an explicit `null` for an arbitrary JSON field cannot be sent (R7.1) | M8 |
 | TOA450 on inline variants does not suggest a value that could be derived: when the variant's discriminator property is the only `const`/enum (OpenAI ×3) | M8 (R9) |
@@ -144,10 +144,10 @@ M6 review findings and items deferred in the plan, which were deliberately left.
 | Polymorphism through `allOf` (discriminator on the base, descendants — `allOf: [$ref: Base, …]`): the base stays a model, TOA452 | M8 (the hierarchy together with the unions, R9) |
 | `oneOf` without a discriminator (R9.2): the IR node exists, but there is no behavior or diagnostic yet | M8 |
 | The title of an enum value from a `const` branch (`title`/`description`, Discord `NO_BOT`) is not taken as the value's name | M8 |
-| The envelope mode "generic wrapper" and its config key | M9 |
-| Webhooks, `callbacks`, security metadata, `servers` | M9 (SSE events — M10) |
+| The envelope mode "generic wrapper" and its config key | when needed (M9 design, decision 11: envelopes are only unwrapped) |
+| Webhooks, `callbacks`, security metadata, `servers` | done in M9 (security metadata and servers, tasks 1, 3, 4); callbacks and webhooks are reported, not generated (TOA567); SSE events — M10 |
 | SSE: the IR takes `itemSchema` (or `schema`) for `text/event-stream` as the content type; in OAS 3.2 `itemSchema` describes the event as a whole (`data`/`event`/`id`), so the type may be an event envelope rather than the data; the 4 corpus streams have not been reviewed | M10 |
-| R5.3: "descriptive" tags (`Pet operations controller`) are not recognized (a warning only for tags without ASCII); renaming a tag with an override (`tags: {pet-controller: Pets}`) requires a `tags` section in the overrides file | M9 (group emitter) |
+| R5.3: "descriptive" tags (`Pet operations controller`) are not recognized (a warning only for tags without ASCII); renaming a tag with an override (`tags: {pet-controller: Pets}`) requires a `tags` section in the overrides file | when needed: a tag override needs a `tags` section in the overrides file, a format decision (M9 plan, open questions) |
 | Validation of `import`/`type` of custom types (R6.8); escaping in the emitter | M8 |
 | A path parameter with `required: false` is forcibly made required (the normalizer's territory, M3) | when needed |
 | `prefixItems` (tuples), `patternProperties`, `if/then/else`, `not` are not mapped (an array without `items` — `List<JsonValue>`) | when needed |
@@ -162,7 +162,7 @@ M6 review findings and items deferred in the plan, which were deliberately left.
 | `DirectionIndex` cached "not directional" inside a loop depending on the order of queries | done in M6 (10a): the answer depends only on the set of reachable schemas |
 | `deprecated: false` next to `$ref` does not cancel the target's mark (in the model it is a plain `bool`); a description of the target written in its own annotations-only `allOf` part does not reach the field | when needed (doc comments only) |
 | `IrJson` does not print descriptions, so the effect of annotations next to `$ref` is visible only in tests | M8 (if the dump is needed for doc comments) |
-| TOA561 and TOA564 each cover two different findings (dropped alternatives / bytes; invalid `style` / `querystring`) and sit in 5xx, although the plan allotted media types 6xx | before 1.0 (code catalog, M13) |
+| TOA561 and TOA564 each cover two different findings (dropped alternatives / bytes; invalid `style` / `querystring`) and sit in 5xx, although the plan allotted media types 6xx | done in M9 (task 2: TOA650/TOA651, and TOA565 for `querystring`) |
 
 Fixed in M6 following the final review: an `allOf` with one `$ref` and annotation-only parts — a reference to the target (nullable if a part says so); `description`, `default`, `deprecated` next to `$ref` in 3.1+ take precedence over the target's; TOA564; the `Accept`, `Content-Type`, `Authorization` headers are not generated; custom type names are reserved (TOA551); TOA552 for enum values is info with the hint `x-enum-varnames`; `unknown` is reserved among enum values (`unknown_`).
 
@@ -172,13 +172,13 @@ M8 findings and decisions that were deliberately deferred (plan: [2026-10-12-m8-
 
 | What | Where |
 |---|---|
-| Sealed types of operation statuses (`CreatePetError`, `CreatePetResponse`) and their variants | M9: names are allocated in the IR library's namespace after the M8 names, so no model name will change |
+| Sealed types of operation statuses (`CreatePetError`, `CreatePetResponse`) and their variants | done in M9 (tasks 3-4) |
 | Override address for inline type names (R5.4); the idea is a `typeName` field in a property entry (`schemas.Pet.properties.status.typeName: PetState`), with no address for array elements, map values, and union variants | when needed (the user's decision: deferred) |
 | The enum value name from a `const` branch's `title` (Discord `NO_BOT`) as `x-enum-varnames` | when needed (the user's decision: deferred) |
 | ~~Stripe: 390 fields `anyOf: [string, {enum: ['']}]`~~ | resolved in M8: the enum branch is dropped by TOA455 (info), the field is `String`, the dropped values go into the "Known values" doc comment; for `oneOf` the type also accepts a value that `oneOf` would reject — deliberately |
 | Subtypes of a polymorphic base are not counted in `DirectionIndex` (the split into `Pet`/`PetInput` is not done for them) | when needed |
 | `IrJson` does not print constants, constraints, helper type names | when needed |
-| `generate --format` (json, sarif) | M9, together with the operations |
+| `generate --format` (json, sarif) | after M9: where the per-client lines go next to a machine report is a user decision (M9 plan, open questions) |
 | The input hash does not account for the Dart SDK version and `dart_style` (not used) | when needed |
 | `union` keys on a property that an override cannot apply silently produce no diagnostic (TOA807 only for schemas) | when needed |
 | `IrJson` does not print the union variant selection method (`dispatch`) and the variant names | when needed |
@@ -189,8 +189,8 @@ M8 findings and decisions that were deliberately deferred (plan: [2026-10-12-m8-
 | "Known values" are not documented for a union that is an array element or a component alias (there is no field with a description there); long "Known values" lines wrap unevenly | when needed |
 | Long `toJson` lines in generated code are not wrapped (safe under `// dart format off`) | when needed |
 | A subtype of a polymorphic base that is only in a file nothing refers to is not found (the file is not read) | behavior by design; documented |
-| `generate`: `--dry-run`, a generator version constant (guarded by a test) | M9 or when needed |
-| Model file names (`ModelLibrary.fileNames`) are allocated in one scope in the order of `ir.declarations`, sorted by name. If M9 adds operation types to the same list or directory, a new type that sorts earlier and yields the same snake name will move an existing model to `x2.dart`: its file's `import` breaks, and the output changes | M9: operation files take names in their own directory and in their own scope (or after the models), so model files do not move |
+| `generate`: `--dry-run`, a generator version constant (guarded by a test) | when needed |
+| Model file names (`ModelLibrary.fileNames`) are allocated in one scope in the order of `ir.declarations`, sorted by name. If M9 adds operation types to the same list or directory, a new type that sorts earlier and yields the same snake name will move an existing model to `x2.dart`: its file's `import` breaks, and the output changes | done in M9 (task 4: group files in `api/`, named in their own scope) |
 | Swapping the output directory does not carry over the owner, ACLs and extended attributes of the old directory (the access mode is carried over) | when needed |
 | Case and hard-link tests have been checked only on macOS (APFS); Linux and Windows — in the M11 matrix | M11 |
 
@@ -201,8 +201,27 @@ M7 review findings that were deliberately deferred:
 | What | Where |
 |---|---|
 | `openEvents`: an error body with invalid UTF-8 is decoded leniently (`allowMalformed`), while `send` gives `DecodeError`; a response from a stream status without `ResponseBody` — `UndocumentedStatus` with an empty body; the size of the error body is not limited (as in `send`) | M10 (SSE) |
-| An operation with a binary/text success response and JSON errors has no direct decoding means; `RawResponse.parse` bypasses the depth check | M9 |
+| An operation with a binary/text success response and JSON errors has no direct decoding means; `RawResponse.parse` bypasses the depth check | done in M9 (task 1: `RawResponse.parsedJson` with the depth check, also in `RawResponse.parse`) |
 | A `double` `1.0` in a parameter: `x=1.0` on VM and Wasm, `x=1` on dart2js | M11 (platform matrix) |
 | The `whenCancel` chain leaves a closure on a long-lived user token for each `openEvents` call (of the same order as Dio itself) | when needed |
-| The README does not describe the `//` guard in the query for a relative `baseUrl` | M9 (`generate` documentation) |
+| The README does not describe the `//` guard in the query for a relative `baseUrl` | done in M9 (task 6: README, "Operations") |
 | The browser does not send the `Cookie` header (cookie parameters do not work on the web) — a claim from the documentation, not verified in a browser | M11 |
+
+## Moved from M9
+
+Findings and decisions of M9 that were deliberately deferred (plan:
+[2026-10-13-m9-operations.md](superpowers/plans/2026-10-13-m9-operations.md),
+"Deferred"):
+
+| What | Where |
+|---|---|
+| Event-stream operations are not generated (TOA654) | M10 |
+| `in: querystring` parameters are not generated (TOA565) | when needed |
+| The headers of a multipart part's `encoding` are not sent (TOA656) | when needed |
+| A form property nested deeper than its style allows (an object in an object for `form`) makes `FormBody.encode` throw `ArgumentError` at run time; the generator does not warn | when needed (a diagnostic, or the deepObject convention of Rails and Stripe) |
+| `style: cookie` (OpenAPI 3.2) is sent percent-encoded, like `form` | M11 (with the platform matrix) |
+| A documented 1xx or 3xx response is `UndocumentedStatus`; `default` never catches a 2xx | when needed |
+| `callbacks`, `links` and `webhooks` are not generated (TOA567 reports callbacks and webhooks) | when needed |
+| `generate --format` and the per-client lines next to a machine report | after a user decision |
+| Files over the size limits that M9 grew (see the allowlist comments in `test/quality/size_limits_test.dart`) | the code-quality plan |
+
````

- [ ] **Step 3: Verify**

Run from the root:

```bash
dart pub get
dart analyze packages        # No issues found!
```

From `packages/typed_openapi`: `dart format lib test bin` (a second run changes 0 files) and `dart test` (expected `+957: All tests passed!`, the size ratchet `test/quality/size_limits_test.dart` included). From `packages/typed_openapi_runtime`: `dart format lib test` (the same) and `dart test` (expected `+184: All tests passed!`).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "docs: record what M9 closed and deferred

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Corpus run

`generate` on the 14 public corpus clients after task 7 (config and output in the scratchpad, absolute `output` paths, one package per `union` mode with `dio` and the runtime by path, `dart pub get --offline`, `dart analyze --fatal-infos` under `package:lints/recommended` plus the `flutter_lints` rules):

| | `union: raw` (default) | `union: structural` |
|---|---|---|
| Clients generated | 13 of 14 (artemis skipped: its two TOA009 `!!timestamp` errors) | 13 of 14 |
| Files | 10,499 (stripe 6,445, openai 1,948, discord 353, jellyfin 346, medusa 338, grace 265, grace_bundle 263, airflow 203, ditto 137, googlemaps 104, tambo 89, efgs 5, digitalocean 3) | 11,436 |
| API files | 192 group files (jellyfin 46, openai 41, airflow 28, medusa 23, grace 12, grace_bundle 12, ditto 9, googlemaps 9, tambo 9, discord 1, efgs 1, stripe 1; digitalocean none: all its operations are `$ref`s, TOA563 as before) | the same |
| `dart analyze --fatal-infos` | 0 errors, 0 warnings, 0 infos | 0 errors, 0 warnings, 0 infos |
| Second `generate` | 0 files written | 0 files written |

The first run found the defects task 7 fixes (3 `missing_default_value_for_parameter`, 2 `unchecked_use_of_nullable_value`, 1 `unintended_html_in_doc_comment`). New diagnostics of `check` on the corpus: TOA651 x57 (all media types dropped next to JSON), TOA566 x19, TOA654 x4 (event streams), TOA655 x1, TOA567 x1, TOA653 x0; no TOA568, TOA650 or TOA656. Stripe and discord give one group class each (their operations have no tags; TOA554 as before). The browser runs of the runtime's new tests (`-p chrome`, also `--compiler dart2wasm`) are green.

## Fuzz

The M8 harness (`scratchpad/m8t10/h/bin/fuzz.dart`: random specs with cycles, `allOf`, unions, inline enums, three group and tri-state configurations) extended with operations: every parameter location and style, JSON `content` parameters, hostile names (`class`, `body`, `call`, newline, `*/`, `$`), an empty enum, request bodies of every kind (JSON, form with `encoding`, multipart with files and with a `$ref`, binary with a wildcard, text), 1-5 responses from 200/201/202/204/`2XX`/400/404/`4XX`/422/499/500/`5XX`/`default` with JSON, text, binary, form and multipart bodies, `security` (none, optional, a scheme, an unknown scheme), servers with variables, and component names that collide with the names M9 claims (`...Response`, `...Error`, `...Errors`, `...Request`, `...Client`, `Dio`). Each spec is built twice and `ApiLibrary.files` compared: 6,000 seeds x 3 configurations x 2 `union` modes = 36,000 builds, 0 crashes, 0 non-deterministic outputs, 321,648 files. A sample of 1,000 outputs (every 12th seed, one configuration, both modes) in one package with the analyzer gate's rules: the first run found 1,510 issues of six kinds (task 7), after the fix 0.

## Carried over from earlier milestones

Every roadmap row whose target was M9:

| Roadmap row | In M9 |
|---|---|
| M2: `$ref` to `file:///` reads any local file | Moved: `diff` (M12) or before 1.0. `generate` writes only into its own output and refuses one that holds an input; a `$ref` reads files the user's own spec names |
| M2: siblings of `$ref` in a Path Item are not merged | Moved (when needed): OAS leaves a conflict undefined, TOA110 reports every sibling, merging needs a parser change; no corpus spec has one |
| M2: `$ref` in `callbacks` and `links` | Moved to the generation of callbacks: M9 does not generate them and reports callbacks and webhooks (TOA567); links are never read |
| M2: `in` of an `apiKey` scheme not required | Task 2 (TOA112) |
| M4: unapplied override entries in `NormalizedSpec.overrides` | Closed: an unusable overrides file is an error, so `generate` skips the client (M8 test), and the IR reads applied entries only; task 6 keeps the behaviour |
| M6: the media type's `encoding` is not in the IR | Tasks 2-4 (`EncodingIr`, `FormEncoding`, part media types, `FileUpload` names); part headers TOA656 |
| M6: names of the types the emitter creates | Task 3 (`ApiNames`, after M8's names) |
| M6: `default` of a parameter | Task 2 (`ParameterIr.defaultValue`), task 4 (method doc) |
| M6: `in: querystring` | Moved (when needed): TOA565; no corpus spec has one |
| M6: an empty `SingleError.statuses` | Task 6 (doc comment), task 4 (`>= 400 && < 600`) |
| M6: an operation whose only response is `default` | Task 3 (TOA653, success `JsonValue`) |
| M6: dio export names vs schema names | Task 2 (`show Dio`, reserved names) |
| M6: one path-variable pattern | Tasks 1-2 |
| M6: TOA561 two findings, 6xx numbering; TOA561/TOA564 two findings each | Task 2 (TOA650, TOA651, TOA652, TOA565) |
| M6: the generic envelope mode | Moved (when needed): spec decision 11 |
| M6: webhooks, `callbacks`, security metadata, `servers` | Tasks 1, 3, 4 (security, servers); callbacks and webhooks reported (TOA567) |
| M6: descriptive tags, renaming a tag by override | Moved (when needed): a `tags` section in the overrides file is a format decision (open question 11) |
| M8: sealed status types | Tasks 3-4 |
| M8: `generate --format` | Moved: where the per-client lines go next to a machine report is a user decision (open question 10) |
| M8: `generate --dry-run`, a version constant | Moved (when needed) |
| M8: model file names vs operation files | Task 4 (`api/`, own scope) |
| M7: binary/text success with JSON errors; `RawResponse.parse` depth | Task 1 (`parsedJson`), task 4 (the decoder uses it) |
| M7: README on the `//` guard | Task 6 |

## Deferred

- Event-stream operations (TOA654): M10.
- `querystring` parameters (TOA565), part headers (TOA656), `callbacks`/`links`/`webhooks` (TOA567), the generic envelope, tag overrides, `generate --format`, `--dry-run`.
- A form property nested deeper than its style allows makes `FormBody.encode` throw `ArgumentError` at run time; no diagnostic yet.
- `style: cookie` (OpenAPI 3.2) is sent percent-encoded like `form` (M11, with the platform matrix).
- A documented 1xx or 3xx response is `UndocumentedStatus`.
- The allowlisted files M9 grew (table "Size ratchet changes"): the code-quality plan splits them.

## Self-review

Spec decisions: 1 - tasks 3-4 (`Result` only, `Never`, `void`); 2 - task 4 (named arguments, `body`, `call`); 3 - tasks 3-4 (plain classes, `PetsApi(Dio dio)`, root named after the client, `naming.client`, groups as fields, no change to Dio); 4 - tasks 3-4, 6 (`api/`, `<client>.dart`, names after the models, one manifest); 5 - tasks 1, 3-4 (single `T`, sealed successes, `void`, `Success` status and headers, text, bytes, JSON errors of text and binary operations); 6 - tasks 3-4 (`Never`, single type, sealed errors, empty `statuses`, `default`-only rule TOA653); 7 - tasks 2, 4 (JSON, form with `encoding`, multipart parts, binary); 8 - tasks 1, 4 (`FileUpload`, Dio types out of signatures, web); 9 - tasks 1-2, 4 (runtime codecs, `querystring` stays reported as TOA565, one pattern); 10 - tasks 1, 3-4 (security metadata, servers as constants); 11 - nothing to build (envelopes are unwrapped, M6); 12 - task 2 (`show Dio`); 13 - task 6; 14 - task 2. Out of scope: SSE (TOA654), callbacks/links/webhooks (TOA567). No placeholders; names and signatures between tasks were checked by the replay from `main`.

## Open questions

Each is a user-facing choice the spec leaves open; the plan implements the default given.

1. **A sealed type named like the operation's own inline body.** When one inline error body is `GetPetError` (M6 naming) and the errors need a sealed type, the sealed type is `GetPetErrors` (and `GetPetResponses` for successes), silently, as a documented rule; any other collision gets `2` with TOA551. Alternatives: always `2` with TOA551, or another word (`GetPetFailure`).
2. **The root file name.** `<client in snake case>.dart` (`petstore.dart`), `<client>_client.dart` when that is `api.dart` or `models.dart`. Alternative: the snake case of the root class (`petstore_client.dart`).
3. **Server member names.** `server` for one server, `server1`, `server2`, ... in spec order for several. Alternative: names from `description` (`production`).
4. **Server variables are `String` arguments** with the spec's default and the `enum` values in the doc comment. Alternative: an enum type per variable.
5. **No documented 2xx:** the success is `JsonValue` (the body kept), with TOA653. The spec allowed `void` too.
6. **`default` never catches a 2xx:** an undocumented 2xx next to a `default` response is `UndocumentedStatus`, not an error decoded with the `default` schema (OpenAPI would say `default`).
7. **Event-stream operations are not generated** before M10 (TOA654). Alternative: generate them now, reading the whole body as text.
8. **The parts class is `<Operation>Request`** (`UploadPhotoRequest`); a multipart schema that is not an object sends its JSON part by part, binary strings as base64 (TOA655).
9. **An optional `JsonValue` argument defaults to `const JsonValue(null)`** and is then not sent (a parameter) or sent as no body.
10. **`generate --format`** is deferred: with `json`/`sarif` on stdout, the per-client lines would have to go to stderr or into the report. Which?
11. **Renaming a tag by override** (`tags: {pet-controller: Pets}` in the overrides file) is deferred: it needs a new section in the overrides format.
12. **Status variants** are `class` (not `final`, like M8's generated classes), equal by value, with no `toString` override (a body may hold secrets the model redacts, but `JsonValue` and bytes would print raw).
13. **The default group's field** in the root client is `defaultApi` (from `naming.default_group`).
14. **Deprecated operations** get `@Deprecated('Deprecated in the API spec.')`; a deprecated parameter is only marked "(deprecated)" in the method's doc comment (an annotation on a parameter would warn at every call site in the generated code itself).
15. **A success media type mix** (JSON and binary successes in one operation) makes Dio read bytes and decode the JSON success from them; the alternative, separate methods per media type, is not done.
