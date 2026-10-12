# 03. New Dart-native generators: tonik, swagger_to_dart, space_gen

Status as of **2026-10-11**. Comparison with the requirements from `../requirements.md` (R0.1…R15.6 and open decisions 1–7).

**Method.** The repositories were cloned (`git clone`) and read without running their code. Key findings about tonik and swagger_to_dart were also checked against the published versions in the pub cache (`tonik_generate-0.10.0`, `tonik_parse-0.10.0`, `tonik_core-0.10.0`, `swagger_to_dart-6.0.0`). The generators were not run. The generated code is taken from the golden files and the unit-test expectations of the repositories themselves.

| Repository | Commit the code was read at |
|---|---|
| tonik (`t-unit/tonik`) | `f58c84a9` (2026-10-06), 30 commits newer than the v0.10.0 tag |
| swagger_to_dart (`masreplay/api_spec_to_dart`) | `fb1e11b6` (2026-10-06) = 6.0.0 |
| space_gen (`eseidel/space_gen`) | `983088e8` (2026-07-21), main after 1.4.0 |

Links in the format `tonik:path#Lx-Ly` point to the file at this commit. The base URLs are in the "Sources" section.

**Marks:** ✅ present and meets the requirement · ⚠️ partially present or with a caveat · ❌ absent or contradicts the requirement.
**Confidence:** **(code)** checked in the code · **(docs)** taken from the README, CHANGELOG, an issue or a PR · **(not verified)** this is a conclusion not confirmed in the code.

---

## 0. In brief

| | tonik 0.10.0 | swagger_to_dart 6.0.0 | space_gen 1.4.0 |
|---|---|---|---|
| Output | ready-made package without build_runner | annotated code (freezed + json_serializable + retrofit) + build_runner | ready-made package without build_runner |
| HTTP | Dio (by default) or `package:http` | Dio through retrofit | only `package:http` |
| Serialization | custom (code_builder) | json_serializable + freezed | custom (Mustache templates) |
| Runtime | `tonik_util` (~6.4k LOC, 0.x, version shared with the generator) | no own one; retrofit, freezed_annotation, json_annotation | no separate package: `api_client.dart` and others are copied into every generated package |
| Main strength | typed responses for each status; all parameter styles; a corpus of integration tests | a wide input (Swagger 2, Postman, JSON Schema); generics of FastAPI/.NET/ABP; `@Extras` with operationId | a clean architecture of phases; JSON Pointer on every node; round-trip tests on GitHub and Discord |
| Main weakness for R0.2 | fails on the first defect without indicating the location; no type/required overrides; no tree-shaking | null in JSON bodies; the enum `unknown` can be sent; cookies go as a header | no Dio; an enum throws an exception; no config (filters, overrides); a transport failure → `ApiException(400)` |

**Verdicts on the author's claims:**
- **(a) `validateStatus: (_) => true` in tonik.** **True**, but only for HTTP statuses 4xx/5xx. Transport failures (timeout, connection, cancellation) still go through `onError`. The user cannot fix this through `BaseOptions`, because request options take priority.
- **(b) Explicit `null` for unset optional fields.**
  - **tonik: partially.** An optional non-nullable field is omitted. An optional nullable field is always sent as `"x": null`. This is exactly the FastAPI `Optional[X] = None` and NestJS `@ApiPropertyOptional() x?: T | null` pattern.
  - **swagger_to_dart: true** for JSON bodies with the documented configuration. Null is sent for **all** unset optional fields, both nullable and non-nullable. A field with `default` sends the default value. Form and multipart do not send null (since 6.0.0).
- **(c) tonik loses the raw value of an unknown enum.** **True.** By default (`generateUnknownCase: false`) an unknown value breaks the decoding of the whole response altogether. With the option it becomes a fixed `unknown` (`'unknown'` or `-1`), and the raw value is lost. `unknown` cannot be sent: `toJson` throws `EncodingException`, that is, R8.2 ✅.

**Decision 5: reuse `tonik_parse` / `tonik_core`?** **No, not as a foundation.** The packages are explicitly marked as internal, are at version 0.x and break in almost every minor release. The parser fails on the first defect, has no JSON Pointer or source spans, drops constraints, `x-*` and external `$ref`. The model is a mutable IR tailored to tonik and even tied to its runtime. The ideas and the test corpus are worth taking (details in section 4).

---

## 1. tonik

### 1.1 Overview

| Parameter | Value | Source |
|---|---|---|
| Latest version | 0.10.0, 2026-09-07. All 5 packages (`tonik`, `tonik_core`, `tonik_parse`, `tonik_generate`, `tonik_util`) share one version and are released together (melos) | pub.dev API; CHANGELOG |
| First release | 0.0.1, 2025-04-17. 21 versions in total; minor releases roughly once a month (0.6 in March, 0.7 in April, 0.8 in June, 0.9 in July, 0.10 in September) | pub.dev API |
| Popularity | 12★ and 4 forks on GitHub; 8 likes, ~2.0k downloads in the last 30 days, 160/160 pub points. `tonik_parse` and `tonik_core` have ~2.05k downloads each, that is, almost as many as `tonik`: in practice nobody uses them separately. A search for `dependency:tonik_parse` finds only `tonik` | GitHub API, pub.dev |
| Maintenance | Very active: 1663 commits, ~320 PRs, last push 2026-10-10. Open PRs #324 (typed NDJSON/JSONL/SSE streams) and #325 (JSON-seq) were created on 2026-10-10. Issues are almost unused (5 in total), the work goes through PRs | GitHub |
| License | MIT | LICENSE |
| SDK | **Dart ≥ 3.13** for both the generator and the **generated package** (primary constructors, `class const Foo(...)`) | `tonik:packages/tonik_generate/lib/src/pubspec_generator.dart#L50-L62` (code) |
| Maturity | 0.x. Tests: ~6.2k unit tests, 41 integration packages per backend (per the description of PR #324). Integration specs: asana, cloudflare, figma, github, kubernetes, openai, shopify, stripe, twilio, petstore, and others (`integration_test/`). Tests use the Imposter mock server. There are examples with real servers: FastAPI, NestJS, Fastify, Spring Boot, Rails (`examples/`) | (code/docs) |

### 1.2 Architecture

- **Packages and layers.**
  - `tonik` — CLI and file loading.
  - `tonik_parse` — raw OpenAPI DTOs and an `Importer` that converts them into an `ApiDocument` from `tonik_core`.
  - `tonik_core` — IR (`ClassModel`, `AllOfModel`, `OneOfModel`, `AnyOfModel`, `EnumModel`, `Property`…), config and transformers (filters, name overrides, deprecation, allOf normalization).
  - `tonik_generate` — generation via `code_builder` and formatting via `dart_style`.
  - `tonik_util` — runtime (parameter style codecs, `TonikResult`, `Date`, `OffsetDateTime`, `ServerConfig`, multipart, charset).
- **Flow in the CLI.** `loadOpenApiDocument` → `Importer.import` → `ContentTypeNormalizer` → `ConfigTransformer` → `Generator`. Each step is wrapped in `on Object catch` with an exit via `exit(1)` and a generic message "Unexpected error…" (`tonik:packages/tonik/bin/tonik.dart#L114-L195`) (code).
- **Output.** A full package: `pubspec.yaml`, its own `analysis_options.yaml`, `lib/src/{model,operation,api_client,server,response,…}`. A separate class is generated for each operation, plus one more API class per tag. `build_runner` is not needed (docs `features.md`, code).
- **Serialization.** Custom. Each model can `toJson`/`fromJson`, and also `toSimple`, `toForm`, `toLabel`, `toMatrix`, `toDeepObject`. That is, a model is serialized in all parameter contexts, not only in JSON. Type names are qualified through `DartEmitter.scoped()`, so schemas named `Error`, `List` or `Response` do not conflict with `dart:core` (docs, code).
- **HTTP.** Dio (by default) or `package:http`, chosen at generation time. The request goes through `client.requestUri(absoluteUri, …)` with `responseType: bytes` and `validateStatus: (_) => true` (`tonik:packages/tonik_generate/lib/src/operation/dio_operation_base_generator.dart#L340-L355`) (code).
- **Dependencies of the generated package.** `big_decimal`, `collection`, `dio` or `http`, `meta`, `tonik_util: ^0.10.0`, optionally `fast_immutable_collections`. `tonik_util` itself depends on `big_decimal`, `charset`, `collection`, `http_parser`, `meta` (code).

### 1.3 Requirements coverage

| ID | Status | Details and evidence |
|---|---|---|
| R0.1 OAS 3.0 | ✅ | `features.md`: "Fully Supported" (docs) |
| R0.1 OAS 3.1 | ⚠️ | Present: `$ref` with sibling keys, `$defs`, boolean schemas, `type: [T, "null"]`, `contentEncoding`. Missing: `const`, `if/then/else`, `prefixItems`, `patternProperties`, `$id`/`$anchor`/`$dynamicRef`, `unevaluated*`. `not` is ignored with a warning (`roadmap.md`; `model_importer.dart#L932-L937`) (docs/code) |
| OAS 3.2 | ❌ | `features.md`: "Planned". Although the repository description on GitHub claims "3.0/3.1/3.2". For 3.2, `Importer` only writes a warning "attempting to parse permissively" (`tonik:packages/tonik_parse/lib/src/importer.dart#L108-L119`). There are separate pieces of 3.2, for example `dataValue` in the examples (docs/code) |
| R1.1 | ✅ | Local JSON/YAML only (`tonik:packages/tonik/lib/src/openapi_loader.dart`) (code) |
| R1.2 external `$ref` | ❌ | This is explicitly a non-goal in the roadmap. Code: `throw UnimplementedError('Only local schema references are supported…')` (`tonik_parse/lib/src/model_importer.dart#L539-L544`). A direct self-ref gives `ArgumentError` (`#L549-L552`) (code) |
| R1.3 | ✅ | `--config`/`-c` on every run (`tonik/lib/src/config/cli_parser.dart`) (code) |
| R1.4 `itemSchema` | ❌ (⚠️ in progress) | Only in open PR #324 (docs) |
| R2.1 normalizer | ❌ | There are no named rules. Some defects are silently "swallowed": an array without `items` becomes `AnyModel` without a warning (`model_importer.dart#L908-L913`). Other defects break generation: `required: true` in a schema gives a `TypeError` at `map['required'] as List<dynamic>?` (`tonik_parse/lib/src/model/schema.dart#L102-L104`) (code) |
| R2.2 diagnostics | ❌ | Only `package:logging` (`log.warning`), without codes and JSON Pointer. On any parsing error the CLI prints one generic "Unexpected error while parsing…"; details are visible only at the `fine` level (`bin/tonik.dart#L132-L147`) (code) |
| R2.3–R2.4 | ❌ | There is neither a baseline nor a check mode (code, docs) |
| R2.5 | ❌ | The tool guesses silently. Unknown discriminator: all variants are tried, and the first one that parses wins (`composite_data_types.md`; `one_of_generator.dart#L434-L446`, `#L531-L566`). Name collisions are resolved with a numeric suffix, logged at the `fine` level (code) |
| R3.1 overrides | ⚠️ | `nameOverrides` for schemas, properties, operations, parameters, enums, tags, as well as `x-dart-name` and `x-dart-enum`. `typeOverrides` is marked "Reserved for future use". There are no overrides for required/nullable/format/discriminator/content-type (`configuration.md`) (docs) |
| R3.2 | ❌ | `name_override_applier.dart` does not log an override whose target is not found (code) |
| R3.3 | ❌ | — |
| R4.1 | ⚠️ | There are `includeTags`, `excludeTags`, `excludeOperations`, `excludeSchemas`. There is no include by `operationId`, no filter by paths and glob (`filter_applier.dart`) (code) |
| R4.2 tree-shaking | ❌ | Filters change only `document.operations`; models are not pruned (`tonik_core/lib/src/transformer/config_transformer.dart#L43-L65`) (code) |
| R4.3 | ✅ | Separate package; scoped imports (code) |
| R5.1 | ⚠️ | Names come from `operationId` plus override. There are no regex transformations (docs) |
| R5.2 | ⚠️ | Scoped emission and numeric suffixes work, but without diagnostics (code) |
| R5.3 | ✅ | A class per tag; override of the tag name (docs) |
| R5.4 | ✅/⚠️ | Inline names are taken from the position in the document. Deduplication of identical inline enums was not found (not verified) |
| R6.1 matrix | ⚠️ | 3 of 4 cells are correct (see 1.4b). There is no separate mode for PATCH. `readOnly` is excluded from the request, `writeOnly` from the response (docs, code) |
| R6.2 types | ⚠️ | `date-time` → `OffsetDateTime`, `date` → `Date`, `decimal` → `BigDecimal`, `uri` → `Uri`, `binary` → `List<int>`, `byte` → `String`, any value → `Object?`. A custom mapping of primitives is not possible (`typeOverrides` is reserved) (`data_types.md`) |
| R6.3 allOf | ⚠️ | A single member collapses into an alias (`AllOfNormalizer`). Several members give a **composition** class with a field for each part, not a flat model (`composite_data_types.md`) (docs/code) |
| R6.4 generics | ❌ | — |
| R6.5 | ⚠️ | Extra fields are ignored unless there is `additionalProperties`. A decoding error has `context: 'User.name'` (schema and field), but not the path in the JSON (`class_json_generator_test.dart#L793`) (code) |
| R6.6 | ✅ | `==`, `hashCode`, `copyWith`, `toString` (tests `class_equals/hash_code/copy_with_*`) (code) |
| R6.7 constraints | ❌ | They are not parsed **at all**: the comment "We ignore … maxLength, minLength, pattern" (`tonik_parse/lib/src/model/schema.dart#L153-L155`). The statement in `features.md` "parsed but not enforced" is inaccurate (code) |
| R7.1–R7.2 three states | ❌ | There is neither an `Optional`/`Undefined` type nor a separate PATCH mode (code) |
| R7.3 | ⚠️ | See 1.4b |
| R8.1 | ❌ | See 1.4c |
| R8.2 | ✅ | `toJson` for `unknown` throws `EncodingException` (`enum_generator.dart#L436-L452`) (code) |
| R8.3 | ⚠️ | String and int enums are present. Boolean ones are absent: the generator throws `ArgumentError` for a type other than `String`/`int` (`enum_generator.dart#L52-L57`) (code) |
| R8.4 | ❌ | Only the custom `x-dart-enum` is supported, `x-enum-varnames` is not (code) |
| R9.1 | ⚠️ | `oneOf` becomes a sealed class, and the discriminator dispatches in O(1). There is **no** variant for "unknown type with raw JSON"; with an unknown discriminator, all variants are tried (code) |
| R9.2 | ❌ | Without a discriminator, the variants are tried silently in "stable semantic order", without diagnostics (`one_of_generator.dart#L494-L566`) (code) |
| R9.3 | ✅ | Mixed primitives are dispatched by runtime type (`one_of_generator.dart#L455-L492`) (code) |
| `anyOf` | ⚠️ | A class with a nullable field for each alternative, not a sealed hierarchy (docs) |
| R10.1 | ❌ | You can pass your own `Dio` (`ServerConfig.client(dio)`), but the generated server **mutates it**: `resolvedDio.options.baseUrl = baseUrl;` runs even for a client that was passed in (`tonik_generate/lib/src/transport/dio_backend_generator.dart#L247-L255`). Moreover, each request has its own `Options` (`responseType: bytes`, `validateStatus`, `Accept`) (code) |
| R10.2 | ❌ | See 1.4a |
| R10.3 styles | ✅ | Path: `simple`, `label`, `matrix`. Query: `form`, `spaceDelimited`, `pipeDelimited`, `deepObject`. Header and cookie are there too. Plus `allowReserved` (`tonik_parse/lib/src/model/serialization_style.dart`; `request_parameter_importer.dart#L334-L390`; codecs in `tonik_util/lib/src/encoding/*`). Parameters via `content` are not supported (non-goal). An unknown `style` gives `FormatException` and breaks generation (code) |
| R10.4 | ✅/⚠️ | JSON, multipart (typed parts, `encoding`, files), `x-www-form-urlencoded` (flat schemas only), `octet-stream`, `text/plain`, mapping of custom content types (docs) |
| R10.5 | ⚠️ | Cancellation is there (`TonikCancellation`). There is **no** progress, no extra headers per call, no `extra` or `operationId` tag for interceptors: `Options` has no `extra` (`dio_options_generator.dart#L25-L34`); the only method parameter is `cancellation` (`api_client_generator_test.dart#L1926-L1931`) (code) |
| R10.6 | ✅ | A separate variant for each pair of status + content type, plus `2XX` and `default`. 204 gives `void`. Response headers are typed. The native response is available in `TonikSuccess.response`. Charset for text (docs) |
| R10.7 | ⚠️ | The API class is concrete (`class UsersApi`); it can be mocked only through `implements` or mocktail (code) |
| R10.8 | ⚠️ | Security ends up only in doc comments (`authentication.md`) (docs) |
| R10.9 | ✅ | Typed server classes, variables, enums for variables, `CustomServer` (docs) |
| R11.1 | ✅ | Typed by each status (docs, code) |
| R11.2 | ⚠️ | There is only `TonikResult`; there is no exception-based mode. HTTP errors arrive on the **success** channel (`TonikSuccess(value: Response404)`) (docs) |
| R11.3 | ⚠️ | An undocumented status gives `ResponseDecodingException`, and then `TonikError(type: decoding, response: …)`. That is, it is mixed up with real decoding errors (`parse_generator.dart#L94-L117`) (code) |
| R11.7 | ✅ | `TonikErrorType.network/cancelled/encoding/decoding/other`, separate from the response variants (`tonik_util/lib/src/tonik_result.dart`) (code) |
| R12 SSE | ❌ (⚠️ in progress) | Not released yet; PR #324 generates `Stream<TonikResult<T,R>>` for NDJSON/JSONL/SSE with `itemSchema` (docs) |
| R13.1 | ⚠️ | There is stable sorting (`stable_model_key.dart`) and parallel isolates. The generated output is not committed, so there is no byte-level golden check of the whole output (not verified) |
| R13.2 | ⚠️ | Generates its own `analysis_options.yaml`: `lints/recommended` plus **13 disabled rules** (`unused_import`, `dead_code`, `lines_longer_than_80_chars`…) (`analysis_options_generator.dart`) (code) |
| R13.3 | ⚠️ | The runtime is sizeable (~6.4k LOC) and is versioned together with the generator (`^0.10.0`); in 0.x every minor breaks compatibility. Issue #59 is exactly about a mismatch of the `tonik_util` version in the generated pubspec (code/docs) |
| R13.4 | ✅ | Descriptions, examples, `deprecated` (annotate/exclude/ignore) (docs) |
| R13.5 | ⚠️ | There are no test stubs. But without tree-shaking the size is not proportional to the selected operations (code) |
| R14.1–R14.2 | ❌/⚠️ | There is no change report. A new status in the spec breaks an exhaustive `switch` in the consumer (this is by design). An old client gets `TonikError(decoding)` (docs/code) |
| R15.1 | ⚠️ | There is a CLI. The programmatic API is available through internal packages (docs) |
| R15.2 | ❌ | There is no JSON Schema for `tonik.yaml` (code) |
| R15.3 | ✅ | The strongest side (see 1.6) |
| R15.4 | ⚠️ | 0.x, breaking changes in 0.9 and 0.10 (CHANGELOG) |

### 1.4 Verification of the author's claims

#### (a) `validateStatus: (_) => true` → HTTP errors bypass `onError` (R10.2) — **TRUE (code)**

Options generator for Dio (`tonik:packages/tonik_generate/lib/src/transport/dio/dio_options_generator.dart#L25-L34`, `#L60-L65`; identical in the published `tonik_generate-0.10.0`):

```dart
final options = refer('Options', 'package:dio/dio.dart').call([], {
  'method': literalString(_methodName(operation.method)),
  'headers': refer(r'_$headers'),
  'contentType': ?generated.contentType,
  'responseType': refer('ResponseType', 'package:dio/dio.dart').property('bytes'),
  'validateStatus': _validateStatus(),          // ← (_) => true
});
...
Expression _validateStatus() => Method((b) => b
  ..lambda = true
  ..requiredParameters.add(Parameter((b) => b..name = '_'))
  ..body = literalBool(true).code).closure;
```

Expected generated code from the unit test (`tonik_generate/test/src/operation/options_generator_test.dart#L52-L62`):

```dart
Options _options() {
  final _$headers = <String, dynamic>{};
  _$headers['Accept'] = r'*/*';
  return Options(
    method: 'GET',
    headers: _$headers,
    responseType: ResponseType.bytes,
    validateStatus: (_) => true,
  );
}
```

Clarifications to the claim:
1. Dio treats **any** status as success. Responses 401, 404 and 500 pass through `onResponse`, not `onError`. The typical `QueuedInterceptor.onError` for 401 → token refresh will **not** fire. Loggers or Sentry hooked to `onError` will not see HTTP errors.
2. Transport failures (connection, timeout, cancel) **still** go through `onError`. tonik catches `DioException` and returns `TonikError(type: network|cancelled)` (`dio_operation_base_generator.dart#L347-L420`). That is, the claim is true for HTTP statuses, not for all errors.
3. This cannot be fixed globally. When merging, Dio takes `validateStatus` from the request's `Options` before the client's `BaseOptions`.
4. A workaround is an interceptor that calls `reject(...)` in `onResponse` for 4xx/5xx. But then tonik gets a `DioException` and returns `TonikError(network)`, and the typed `Response404` variant is lost. The tonik model "an HTTP error is a successful response of the required type" is fundamentally incompatible with R10.2. This is a consequence of the design, not an oversight.
5. In addition, `responseType: ResponseType.bytes` means that interceptors see bytes in `response.data`, not JSON. Usual loggers and interceptors that parse the error body become useless.
6. **Another finding: violation of R10.1 (code).** `resolvedDio.options.baseUrl = baseUrl;` runs even for a client that the user passed in (`dio_backend_generator.dart#L247-L255`). If one `Dio` is shared by several APIs or parts of the application, tonik silently changes its `baseUrl`.

#### (b) Explicit `null` for unset optional fields (R7.3) — **PARTLY TRUE (code)**

`tonik:packages/tonik_generate/lib/src/model/class_generator.dart#L864-L875`:

```dart
final keyLiteral = specLiteralStringCode(property.name);
if (!requiredInRequest && !property.isNullable) {
  mapEntries..add(Code('if ($name != null) $keyLiteral: '))   // omitted
  ...
} else {
  mapEntries..add(Code('$keyLiteral: '))                      // always present
  ...
}
```

Expected output in the tests (`tonik_generate/test/src/model/class_json_generator_test.dart#L130-L210`):

```dart
// bio: isRequired: false, isNullable: true
Object? toJson() => {r'name': name, r'bio': bio};                        // bio == null → "bio": null
// nickname: isRequired: false, isNullable: false
Object? toJson() => {r'name': name, if (nickname != null) r'nickname': nickname};
```

| required | nullable | tonik behavior | Verdict |
|---|---|---|---|
| yes | no | value | ✅ |
| yes | yes | `"x": null` allowed | ✅ |
| no | no | key is omitted if null | ✅ (guard is present) |
| no | **yes** | **`"x": null` always**, even if the field was not set | ❌ clobbering |

So, "tonik sends null" is true only for optional + nullable fields. However, for the target audience (R0.2) this is the most frequent case: FastAPI `Optional[str] = None` generates `anyOf: [{type: string}, {type: null}]` without `required`. There is no tri-state representation.

#### (c) tonik loses the raw value of an unknown enum (R8.1) — **TRUE (code)**

- By default `generateUnknownCase: false` (`tonik/lib/src/config/config_loader.dart#L338`). `fromJson` throws `JsonDecodingException('No matching … for value')`, and the response becomes entirely `TonikError(decoding)`. There is no raw value, because there is no value at all.
- With `generateUnknownCase: true` the transformer adds **one fixed** variant for **all** enums of the document: `EnumEntry(value: 'unknown')` for string ones and `value: -1` for int ones (`tonik_core/lib/src/transformer/config_transformer.dart#L169-L183`). The generated `fromJson` (expectations from `enum_generator_test.dart#L2198-L2210`):

```dart
factory Status.fromJson(dynamic value) {
  if (value is! String) { throw JsonDecodingException(...); }
  return values.firstWhere(
    (e) => e._$rawValue == value,
    orElse: () => Status.unknown,   // ← incoming 'archived' lost; _$rawValue == 'unknown'
  );
}
```

A Dart `enum` is a set of singletons, so the incoming value cannot be kept in this form. On the plus side, `toJson` for `unknown` throws `EncodingException`, so R8.2 is met. In addition, the setting is global: it cannot be enabled for a single enum.

### 1.5 Tracker and code problems and lessons

| Problem | Link | Lesson for the new tool |
|---|---|---|
| The runtime rejected `Content-Type: application/json; charset=utf-8` with the error "Unexpected content type". Fixed in 0.8.0 | [#165](https://github.com/t-unit/tonik/issues/165) | Compare media types without parameters and `+json` suffixes; a test for `charset` and `version=` |
| `anyOf` with `{enum: [null]}` from fastify-type-provider-zod generated an empty class | [#31](https://github.com/t-unit/tonik/issues/31) | The normalizer (R2.1) must know the `null` idioms of different generators: `{enum:[null]}`, `{type:'null'}`, `nullable` next to a `$ref` |
| A line break inside a string from the spec produced an invalid raw literal | [#88](https://github.com/t-unit/tonik/issues/88) | One escaping helper for all literals plus fuzz tests (tonik later got an integration package `adversarial_strings`) |
| The generated pubspec referred to an outdated `tonik_util` version | [#59](https://github.com/t-unit/tonik/issues/59) | Version the runtime separately and stably (R13.3); check the compatibility of the generator and runtime in CI |
| Crash on the first defect, a generic "Unexpected error" | `bin/tonik.dart#L132-L147` (code) | Collect diagnostics instead of throwing an exception; every message with a code and a pointer (R2.2) |
| YAML becomes a `Map` without source spans; `Context` is the path for names with `/` replaced by `-` | `openapi_loader.dart#L59-L69`; `tonik_core/lib/src/util/context.dart#L5-L15,#L40-L44` (code) | Keep `YamlNode.span` and the RFC 6901 pointer separate from the naming logic |
| Silent heuristics: an unknown discriminator, trying the variants of oneOf, name suffixes | (code, see the table) | R2.5: every heuristic is either disabled by default, or gives a diagnostic with an override suggestion |
| `validateStatus` + `bytes` + mutation of `baseUrl` | 1.4a (code) | Do not touch the user's transport; let HTTP errors go through `onError` and type them only after that (R10.1, R10.2, R11.2) |
| The generated package requires Dart ≥ 3.13 | `pubspec_generator.dart` (code) | The minimum SDK for generated code must be conservative and configurable |
| The documentation diverges from the code: "constraints parsed", "3.2" in the repository description | (code) | The support matrix (R15.5) must be generated or checked by tests |

### 1.6 What is worth borrowing

1. **A response as a sealed class for each pair of status + content type**, with an exhaustive `switch`. This is a good basis for R11.1 and R10.6. But **on top of** the usual Dio error path, not instead of it.
2. **Codecs for all parameter styles** (`tonik_util/lib/src/encoding/*`: `simple`, `label`, `matrix`, `form`, `deepObject`, `pipe` and `spaceDelimited`, `allowReserved`, encoding of object keys). This is a good "oracle" for the R10.3 tests. The MIT license allows adaptation with attribution.
3. **Scoped emission** (`DartEmitter.scoped()`): automatic import prefixing removes a whole class of collisions with `dart:core` and Dio (R5.2).
4. **A corpus of integration tests**: ~40 specs (github, stripe, kubernetes, openai, cloudflare, twilio, shopify, asana, figma, `adversarial_strings`, `naming`, `nullable_bodies`, `fastify_type_provider_zod`…) with the Imposter mock server (`integration_test/`).
5. **Examples with real servers**: docker compose with FastAPI, NestJS, Fastify, Spring Boot and Rails. The spec is fetched live, the client is generated, and assertions are run (`examples/README.md`). A ready-made template for the R15.5 recipes and for R0.2.
6. **`ServerConfig.client` / `.clientFactory` with explicit ownership of the client** (who closes the `Dio`): good lifecycle semantics. But without mutating the client.
7. Charset decoding of text responses; support for `type/*` and `*/*`; `TonikCancellation`, independent of the backend.

---

## 2. swagger_to_dart (repository `masreplay/api_spec_to_dart`)

### 2.1 Overview

| Parameter | Value | Source |
|---|---|---|
| Latest version | **6.0.0, 2026-10-06** (5.0.0 was released 2026-09-30, that is, two major releases in one week). 58 versions in total since 2024-11-21 | pub.dev API, CHANGELOG |
| Popularity | 11★ and 4 forks; 26 likes, ~2.05k downloads in the last 30 days. Pub points per the API are 70/160 with the tag `has:error`; probably the analysis of 6.0.0 has not finished yet | GitHub, pub.dev |
| Maintenance | Active in bursts: a large series of fixes in 5.0.0 closed most of the old issues (#49–#64). There are no open issues | GitHub |
| License | MIT | LICENSE |
| Input | OpenAPI 3.0, 3.1, 3.2; Swagger 2.0 (converted to 3.0.3); Postman v1, v2.x, v3; JSON Schema (models only); JSON or YAML; a file or a URL | README (docs) |
| SDK | Generator: Dart ≥ 3.9. Consumer: ≥ 3.8 (via json_serializable ≥ 6.10) | README |

### 2.2 Architecture

- **Input.** `readSpecSync` or `loadSpec` → `toOpenApiJson` (converters from Swagger 2, Postman and JSON Schema into OAS3 JSON) → freezed OpenAPI models (`lib/src/schema/openapi/v3/*`; the parser itself is also built on freezed and json_serializable) → generation "strategies" (regular, enum, union, typedef, generic) → `code_builder` → `dart_style` (code).
- **Output.** Annotated code, which is then processed by `build_runner`:
  - `models/*.dart` — `@freezed` and `@jsonSerializable`;
  - `api_client/*_client.dart` — `@RestApi()` from retrofit;
  - `custom_api_client.dart`, `exports.dart`, `gen.dart`.

  The consumer needs the dev dependencies `build_runner`, `freezed`, `json_serializable`, `retrofit_generator` and a `build.yaml` with the order of builders (README).
- **HTTP.** Dio via retrofit: `abstract class XClient { factory XClient(Dio dio, {String? baseUrl, ParseErrorLogger? errorLogger}) = _XClient; }`. The method returns `Future<HttpResponse<T>>` (access to the status and headers), has `CancelToken`, `onSendProgress`, `onReceiveProgress` and `@Extras()` (golden `example/lib/src/gen/api_client/basic_client.dart`) (code).
- **Runtime.** There is no package of its own. Dependencies: `dio`, `retrofit`, `freezed_annotation`, `json_annotation`.
- **Output size.** Every model and enum has the full JSON schema as a doc comment. In `example/`, 20,425 of 41,488 model lines are `///`. `@Extras` embeds the operation metadata (parameters, responses with schemas) into each method as a `const` map (code).

### 2.3 Requirements coverage

| ID | Status | Details and evidence |
|---|---|---|
| R0.1 3.0 / 3.1 / 3.2 | ✅/⚠️ | Parsing of 3.x, type arrays, nullable enum. For 3.2 there is a `query` method and `additionalOperations` → `@Method`. No `itemSchema` (CHANGELOG 5.0, 6.0) |
| R1.1 | ⚠️ | `url` is supported; after it the local `input_directory` is automatically **overwritten**. If the network is unavailable, the old copy is used with a loud warning. The build is reproducible only when `url` is not set (README) |
| R1.2 | ⚠️ | Local `$ref` and pointer refs inside schemas work, and parameter cycles are caught. **External** `$ref` → `FormatException('Cannot resolve $ref')`, because `target = ref.startsWith('#/') ? spec : null` (`swagger_to_dart:packages/swagger_to_dart/lib/src/schema/openapi/v3/open_api.dart#L111-L125`) (code) |
| R1.3 | ✅ | `--config` (README) |
| R2.1 | ⚠️ | Some defects are silently swallowed: "a stray `required: true` is ignored" (`open_api_schema.dart#L19-L21`), Swashbuckle `additionalProperties: {}`, content without a schema (code/docs) |
| R2.2–R2.4 | ❌ | There is only `print('swagger_to_dart: warning: …')`, without codes and pointers (`lib/src/utils/warning.dart`) (code) |
| R2.5 | ⚠️ | Some collisions give a warning. But a union without a discriminator is structurally guessed by default, and `enum_fallback_type: first/last` silently substitutes a real value (README) |
| R3.1 | ⚠️ | Present: renaming of enum members (`model.enums`), `remove_model_prefixes`, `class_prefix`, `skipped_parameters`. There are no overrides for types, required/nullable and the discriminator (README) |
| R4.1–R4.2 | ❌ | There are no filters by tags or operations; no tree-shaking (README, config) |
| R4.3 | ✅ | `class_prefix`, own directory (README) |
| R5.1–R5.4 | ✅/⚠️ | Duplicate `operationId`s get numeric suffixes. Collisions with Dio, retrofit and `dart:core` give `Response2`. Reserved members (`hashCode`, `toJson`, …) are handled. Inline models are named from the context (`GetUserResponseAddress`), a client is created for each tag, non-ASCII tags are supported. There are no regex transformations (CHANGELOG 5.0/6.0) |
| R6.1 | ⚠️ | An optional without a default becomes `T?`. An optional with a default becomes non-nullable `@Default(v)`. It is impossible to tell "absent" apart from `null` (`property_generator_strategy.dart#L39-L60`) (code) |
| R6.2 | ⚠️ | There is `DateTime`, and `binary` becomes `MultipartFile` (a Dio type in the model). For FastAPI there are `Color` and `TimeOfDay` in Flutter. Mixed primitives (`string|integer`) become **`dynamic`** (README) |
| R6.3 | ✅ | `allOf` merges properties and `required` (recursively, with protection against cycles); a single `$ref` is expanded into a type (CHANGELOG 5.0) |
| R6.4 | ✅/⚠️ | Real generics `class Foo<T>`, recognized by the framework's naming convention: FastAPI `Page[User]`, .NET `PagedResult<User>`, ABP with backticks. This is opt-in via `support_generic_arguments` and `generation_source` (`lib/src/generator/model/strategy/*_generic_parser.dart`) (code) |
| R6.5 | ⚠️ | json_serializable ignores extra fields. Decoding errors are standard cast errors, without a path (not verified) |
| R6.6 | ✅ | freezed (`==`, `copyWith`, `toString`) |
| R6.7 | ❌ | Constraints are not generated |
| R7.1–R7.3 | ❌ | See 2.4b |
| R8.1 | ❌ | `unknown`, `first`, `last` — the raw value is lost (golden `enum_fallback_unknown/golden/models/status.dart.golden`) (code) |
| R8.2 | ❌ | `Status.unknown.toJson()` gives `'unknown'`, and `Level.unknown.toJson()` gives `-1` (min − 1). This **can be sent** in a request. With `first`/`last`, a foreign valid value is sent (code) |
| R8.3 | ⚠️ | String and int are present. Names for invalid identifiers: `value1`, `value2`… by position (CHANGELOG 6.0) |
| R8.4 | ❌ | `x-enum-varnames` is parsed, but the generator does not use it (`open_api_components.dart#L42`; there are no other uses of `xEnumVarnames`) (code) |
| R9.1 | ✅ | Sealed classes with flat JSON. The opt-in fallback variant (`union_class_fallback_name`) **keeps the raw `Map`** (README "Unions") (docs) |
| R9.2 | ⚠️ | Without a discriminator, the variant is chosen **structurally by default** (the one with the most keys wins; "No try-and-catch guessing"), not via opt-in (README) |
| R9.3 | ⚠️ | Mixing with an array or an object gives a sealed class. `string|integer` gives `dynamic`. Mixed unions in parameters and bodies are also `dynamic` (README) |
| R10.1 | ✅/⚠️ | The user passes `Dio` and `baseUrl`; retrofit mutates nothing. **But** `servers` at the operation or path level are embedded as an absolute URL, and `baseUrl` is ignored for them (CHANGELOG 6.0, G7) |
| R10.2 | ✅ | retrofit does not set `validateStatus`, so the Dio default applies and 4xx/5xx give `DioException`, and with it `onError`. `retrofit_generator-10.2.9/lib/src/generator.dart#L1941-L1962` only passes on the `validateStatus` that the user set (retrofit code) |
| R10.3 | ❌ | Path, query and header are present. **A cookie parameter is generated as `@Header('<cookie name>')`**, that is, it goes on the wire as a header named after the cookie, not as `Cookie: k=v` (`swagger_to_dart:…/api_client/api_client_generator.dart#L658-L671`). `style` and `explode` are ignored (arrays are encoded by Dio with its own `ListFormat`); there is no `deepObject` (code) |
| R10.4 | ✅ | JSON, multipart (`MultipartFile`), urlencoded (`@Body(nullToAbsent: true)`), binary data (`Uint8List`), `text/*` (CHANGELOG 5.0) |
| R10.5 | ⚠️ | There is `CancelToken`, progress, and `@Extras` with `operationId` (`include_openapi_extras: true`). **But** `extras` is a parameter with a default value. If the user passes their own `extras`, the `operationId` disappears. There are no extra headers per call (code, golden) |
| R10.6 | ⚠️ | `HttpResponse<T>` gives the status and headers. Only the **smallest 2xx** is typed, and `application/json` beats `text/plain` (CHANGELOG 5.0) |
| R10.7 | ✅ | `abstract class` from retrofit |
| R10.8 | ⚠️ | Security only as part of `@Extras` or docs (not verified) |
| R10.9 | ⚠️ | Server variables are substituted from their default values (CHANGELOG 6.0) |
| R11.1–R11.6 | ❌ | There are no typed errors, only `DioException` |
| R11.7 | ⚠️ | Distinguished by `DioExceptionType`, but not at the type level |
| R12 | ❌ | — |
| R13.1 | ✅ | Golden snapshots for each fixture; `Recase` was made stateless (previously shared state between runs affected names, #63) |
| R13.2 | ⚠️ | The user must add exclusions for `*.g.dart` and `*.freezed.dart` and `invalid_annotation_target: ignore` to `analysis_options` themselves (README) |
| R13.3 | ⚠️ | There is no separate runtime, but the consumer pulls in retrofit, freezed and json_serializable together with build_runner |
| R13.4–R13.5 | ⚠️ | Descriptions are present, but plus a dump of JSON schemas (~50% of model lines) and full operation metadata in `@Extras` |
| R14 | ❌ | — |
| R15.1 | ⚠️ | There is a CLI, the library API is exported (`loadSpec`, `toOpenApiJson`). Requires build_runner |
| R15.3 | ✅ | Fixture cycle: golden plus e2e compilation (`build_runner` + `analyze`) plus `roundtrip_test.dart.tmpl`. For Postman: every saved example response must decode and encode back. The tests validate the input and output of the converters against the official JSON Schemas of OAS 2.0, 3.0, 3.1, 3.2 (`schemas/README.md`) (docs) |
| R15.4 | ⚠️ | Semver is followed, but major releases are frequent (5.0 and 6.0 in one week) |

### 2.4 Verification of the author's claims

#### (b) Explicit `null` for unset optional fields — **TRUE for JSON bodies (code)**

1. A global annotation applied to all models (`swagger_to_dart:packages/swagger_to_dart/lib/src/generator/model/json_serialization_convertor_generator.dart#L47-L50`):
   ```dart
   const jsonSerializable = JsonSerializable(
     converters: jsonSerializableConverters,
     explicitToJson: true,
   );                       // includeIfNull not set → default json_serializable = true
   ```
2. Field: `@JsonKey(name: …)` without `includeIfNull`; the optional field becomes `T?` (`property_generator_strategy.dart#L39-L60`).
3. Request body: for JSON, `@Body()` is used, and `nullToAbsent: true` applies only to urlencoded (`api_client_generator.dart#L330-L336`). CHANGELOG 6.0.0 states it directly: "urlencoded … and multipart bodies no longer send the model's null fields. **JSON bodies are unchanged** (null and absent can differ there)".
4. Evidence from tests. The E2E project is built with `build.yaml` exactly as in the README, without `include_if_null` (`packages/swagger_to_dart_e2e/build.yaml`). The round-trip in `test/fixtures/class_prefix/roundtrip_test.dart.tmpl#L13-L24,#L39` expects `toJson()` to return `'info': null, 'auth': null, 'run': null, …` for an element where `Item.required == ['name']`. That is, optional fields are serialized as `null`.

An example of a model generated from FastAPI (`example/lib/src/gen/models/conditional_body.dart`): the fields `int? itemId` and `String? itemName` (in the schema `anyOf: [T, null]`, not required). `ConditionalBody(itemName: 'x').toJson()` gives `{"item_id": null, "item_name": "x"}`, and PATCH clears `item_id`.

Clarifications:
- Unlike tonik, null is sent also for optional **non-nullable** fields, because they too become `T?`.
- A field with `default` is generated as `@Default(v) T`. If it is not set, the default value goes into the body, which is another way to overwrite data.
- If the user enables `include_if_null: false` in `build.yaml` (as is done in the repository's own `example/build.yaml`), nulls disappear **everywhere**. Then a required + nullable field cannot send an explicit `null`. There is no tri-state under any setting. The user in [#50](https://github.com/masreplay/api_spec_to_dart/issues/50) explicitly asked to make this configurable: "backend accepting null, and others preferring no field".

#### (a) and (c) in swagger_to_dart

- (a) does not apply: R10.2 ✅.
- An unknown enum behaves the same as in tonik (raw is lost), but worse with respect to R8.2: `unknown` can be sent (golden `status.dart.golden`).

### 2.5 Issue tracker problems

| Issue | Gist | Lesson |
|---|---|---|
| [#50](https://github.com/masreplay/api_spec_to_dart/issues/50), [#52](https://github.com/masreplay/api_spec_to_dart/issues/52) | Before 5.0, **all** fields were `required` and non-null regardless of `required` in the schema | The required × nullable matrix is the main requirement, not a detail (R6.1). Tests are needed for every cell |
| [#55](https://github.com/masreplay/api_spec_to_dart/issues/55), [#61](https://github.com/masreplay/api_spec_to_dart/issues/61) | `Null check operator` on an inline enum without `title` (a spec with 342 endpoints) | Inline entities need a deterministic name derived from context (R5.4); `!` on spec data is forbidden |
| [#59](https://github.com/masreplay/api_spec_to_dart/issues/59), [#60](https://github.com/masreplay/api_spec_to_dart/issues/60), [#64](https://github.com/masreplay/api_spec_to_dart/issues/64) | `'` and `\n` in descriptions produced invalid code in `@Extras` and literals | One escaping helper for all literals plus tests on "hostile" strings |
| [#49](https://github.com/masreplay/api_spec_to_dart/issues/49), [#58](https://github.com/masreplay/api_spec_to_dart/issues/58) | The freezed union expected an envelope `{"value": …}`; the union worked only at the root of the schema | Do not use third-party union code generation for the wire format; build the union ourselves and keep it flat |
| [#56](https://github.com/masreplay/api_spec_to_dart/issues/56), [#54](https://github.com/masreplay/api_spec_to_dart/issues/54) | `text/plain` and `image/*` broke generation | An unknown content type should produce a diagnostic and fall back to `bytes`/`String`, not crash |
| [#63](https://github.com/masreplay/api_spec_to_dart/issues/63) | Stateful `Recase`: the name `id` became `iD` after the generator had met `userID` | Name normalization must be a pure function of its input (R13.1) |
| CHANGELOG 6.0 (G7) | Operation-level servers break the user's `baseUrl` | Expose operation servers as metadata or a parameter, not hardcode an absolute URL |
| Code (2.3 R10.3) | Cookies are sent as a header named cookie | Wire-level tests for every parameter location |

### 2.6 What is worth borrowing

1. **Fixture cycle**: a minimal spec for one feature or issue, a golden snapshot, E2E compilation with `analyze`, and `roundtrip_test.dart.tmpl` run against the compiled output (`CONTRIBUTING.md`).
2. **Round-trip on examples from the spec itself**: every response `example` must decode and then encode back. Free runtime tests for R15.3.
3. **Validating converters against the official OAS JSON Schemas** (2.0, 3.0, 3.1, 3.2) in tests.
4. **`@Extras` with `operationId` and tags** as the mechanism for R10.5. But without embedding the whole operation, and so that user `extras` **merge** with the metadata instead of replacing it.
5. **Recognizing generics by framework conventions** (FastAPI `Page[User]`, .NET `<T>`, ABP backtick). Directly answers R6.4 for the target audience.
6. **A union fallback variant with a raw `Map`**: almost R9.1, it only needs to be enabled by default.
7. Detailed migration notes in the CHANGELOG for every breaking change in the output (R15.4).

---

## 3. space_gen (`eseidel/space_gen`)

### 3.1 Overview

| Parameter | Value | Source |
|---|---|---|
| Latest version | **1.4.0, 2026-07-19**. 8 versions; 1.0.0 was released 2025-09-04. The project has been a hobby since August 2023 | pub.dev, README |
| Popularity | **56★**, 5 forks, 26 open issues. 3 likes, but **~39k downloads in 30 days**, probably from CI: the package is used by Shorebird (`shorebird_code_push_protocol`) and `quickpatch_code_push_protocol` (not verified). 130/160 pub points | GitHub, pub.dev, README |
| Maintenance | Main has not changed since 2026-07-21. Open PRs from contributors (#374 on unknown enum from 2026-09-10, #376 from 2026-10-01) are not merged. High engineering quality: ~96.7% coverage (codecov), detailed ARCHITECTURE.md and CHANGELOG | GitHub |
| License | MIT | LICENSE |
| SDK | Generator ≥ 3.8; generated package ≥ 3.10 (null-aware elements, dot shorthands) | `lib/templates/pubspec.mustache`, PR #321 |

### 3.2 Author's philosophy (Eric Seidel) and architecture

Values from the README:
- the highest-quality modern Dart, "as if written by hand";
- zero errors from the analyzer, formatter and linter;
- clear error messages;
- the aim to cover the whole of OpenAPI 3.x;
- tested code.

Principles stated explicitly:
- **"Great Dart first; OpenAPI-Generator-shaped when convenient".** The openapi-generator shape is only a fallback to ease migration. For migration there are "quirks": `--openapi` enables `SCREAMING_CAPS` enums, mutable models, "lists default to `[]`" and so on.
- **"We own the directories we declare, and nothing else".** Only `generatedDirs` are cleaned; README, LICENSE and `.github` are not written; there is `--no-clear`.
- **"Lint suppression lives in the generated `.dart` files"**: targeted `// ignore_for_file:` comments, not a global disabling of rules, because the consumer may not take the generated `analysis_options`.
- **The pipeline phases are pure functions; I/O only in Load.**

Phases (ARCHITECTURE.md):
1. **Load** — `file:` and `http(s)`, cache.
2. **Parse** — a typed `Spec` tree. **Every `HasPointer` node carries a `JsonPointer`**, `$ref` stays as `RefOr<T>`. The parser counts the keys used (`markUsed`), and the unused ones go into the log "Unused: … in <pointer>" (`parser.dart#L220-L245`).
3. **Resolve** — `ResolvedSpec`, `RefRegistry` keyed by "absolute URI", cycles via `ResolvedRecursiveRef`.
4. **Dispatch** — a separate phase for `oneOf`/`anyOf`. The result is a sealed `DispatchDecision` (`Discriminator`, `Shape`, `Hybrid`, `Predicate`, `NoDispatch`) with an IR of predicates (`KeyExists`, `ArrayElementHasKey`, `Always`).
5. **Naming** (in progress) — a **global** pass that builds `Map<JsonPointer, String>`; "the resolver stays Dart-blind".
6. **Render** — `RenderSpec` and Mustache templates. Types are a structured `DartType`; for expressions a dedicated IR is planned, and `code_builder` was considered and rejected (`doc/dart_expression.md`).

Output: a ready package without build_runner. The runtime helpers (`api_client.dart`, `api_exception.dart`, `auth.dart`, `model_helpers.dart`, `date.dart`) are **copied** into the package with rewritten imports (`file_renderer.dart#L608`). Package dependencies: `collection`, `http`, `meta`, `uri`; lints: `very_good_analysis`.

### 3.3 Requirements coverage

| ID | Status | Details and evidence |
|---|---|---|
| R0.1 3.0 / 3.1 | ✅/⚠️ | The core is there: type arrays; the idiom `oneOf: [{type: null}, T]` collapses to `T?` (1.3.0); `const` (1.4.0). OAS 3.2 is not supported |
| R1.1 | ⚠️ | A path or URL, but there is no local snapshot |
| R1.2 | ✅/⚠️ | **External `$ref`**, including split specs, a ref to a whole file and an arbitrary pointer (1.4.0, #315, #319). Open problem: identical `#/components/schemas/Foo` in two documents merge into one type ([#358](https://github.com/eseidel/space_gen/issues/358); only a warning exists) |
| R2.1 | ⚠️ | Some defects are handled with a warning: `required` naming a non-existent property is dropped (`parser.dart#L1622-L1640`); an invalid enum default (#353). But the parser is **strict**: `_expectType` throws a `FormatException` on the first mismatch ("Path parameters must be required" is also an error) |
| R2.2 | ⚠️ | **Every message has a pointer**: `throw FormatException('$message in ${context.pointer}')` (`parser.dart#L212-L218`). There are no stable codes and no configurable levels. It stops at the first error |
| R2.5 | ⚠️ | Unsupported `style`, `explode` and `allowReserved` give a warning "not honored…" (`parser.dart#L324-L358`). But a `oneOf` without a dispatch method generates `throw UnimplementedError` in `fromJson`, that is, a crash at runtime (6 such stubs remain in Discord) |
| R3, R4 | ❌ | The CLI has only `-i`, `-o`, `-v`, `--openapi`, `--clear` (`cli.dart#L42-L60`). Customization is done by subclassing `FileRenderer`. There are no filters, overrides or tree-shaking |
| R5.2 | ⚠️ | A `_1` suffix with a warning. A global naming pass is in progress (ARCHITECTURE "Phase 4.5") |
| R6.1 | ✅/⚠️ | **Full 8-row matrix** (required × nullable × default) in 1.4.0, PR [#321](https://github.com/eseidel/space_gen/pull/321). Optional non-nullable is omitted via `'x': ?x`. **Optional + nullable stays conflated**: `'omitWhenNull': dartIsNullable && !property.common.nullable` (`render_tree.dart#L4540`), that is, an unset field goes out as `null`, the same as in tonik. Tri-state was moved to [#213](https://github.com/eseidel/space_gen/issues/213) |
| R6.2 | ✅/⚠️ | **A separate `Date` type for `format: date`** (1.3.0); `byte` gives `Uint8List`. `int64` on web is an open problem ([#185](https://github.com/eseidel/space_gen/issues/185)) |
| R6.3 | ✅ | `allOf` is merged into one class, including nested `allOf` and open or map members (1.3.0, 1.4.0) |
| R6.6–R6.7 | ✅ | `==` and `hashCode` (Equatable-like); `validate()` for `min`/`max`/`pattern`/`minItems`/… (`templates/api_exception.dart`, extensions `ValidateNumber`, `ValidateString`, `ValidateArray`) |
| R7 | ❌/⚠️ | See R6.1; #213 is open |
| R8.1–R8.2 | ❌ | An unknown value: `orElse: () => throw FormatException('Unknown … value')` (`templates/schema_enum.mustache#L9-L16`); [#373](https://github.com/eseidel/space_gen/issues/373) is open. PR #374 proposes a sealed `StatusKnown`/`StatusUnknown(raw)`, where `toJson()` **returns raw**. This deliberately contradicts R8.2: "GET then PUT does not overwrite" |
| R8.4 | ⚠️ | `x-enum-descriptions` ✅; `x-enum-varnames` only in a TODO (`parser.dart#L226, #L1027`) |
| R9.1 | ⚠️ | A discriminator gives a sealed class, but an unknown value is a `FormatException`; there is no unknown variant (`schema_one_of.mustache#L5-L14`) |
| R9.2–R9.3 | ⚠️ | Without a discriminator, structural dispatch (shape/predicate) works **by default**, with no diagnostics; if dispatch is impossible, a `UnimplementedError` stub is generated |
| `anyOf` | ⚠️ | Rendered as `oneOf`. A code comment says: "For multiple schemas, we just generate a oneOf, which is wrong" (`render_tree.dart#L866-L880`) |
| `readOnly`/`writeOnly` | ❌ | Ignored (`parser.dart#L1615-L1616`); [#186](https://github.com/eseidel/space_gen/issues/186) |
| R10 transport | ❌ for dio | Only `package:http`. `ApiClient({Uri? baseUri, Client? client, defaultHeaders, readSecret})` mutates nothing ✅. There is no cancellation, progress, operationId or per-call headers. Only 5 methods (`delete`, `get`, `patch`, `post`, `put`) (`templates/api_client.dart`) |
| R10.3 | ❌/⚠️ | Only `form` + `explode` true/false is supported for query; the other styles give a warning ([#100](https://github.com/eseidel/space_gen/issues/100)) |
| R10.4 | ✅ | JSON, multipart, octet-stream, text, form-urlencoded (1.4.0) |
| R10.6 | ⚠️ | Several statuses — via `multiStatus` and `switch`. But only the body is returned; there are no headers or status (`templates/api.mustache`) |
| R10.8 | ✅ | `security` is turned into a **structural** `AuthRequest` per operation (`HttpAuth`, `ApiKeyAuth`, `OneOfAuth`, `AllOfAuth`); secrets are obtained via `readSecret` (`gen_tests/security/lib/api/default_api.dart`) |
| R11.1 | ⚠️ | `ApiException<T>` with a body typed only for the `default`/error response |
| R11.7 | ❌ | **A transport failure becomes an `ApiException` with code 400**: `on SocketException … throw ApiException.withInner(HttpStatus.badRequest, …)` (`templates/api_client.dart#L150-L188`) |
| R12 | ❌ | — |
| R13.1 | ⚠️ | The generated output for GitHub (~1000 operations) and Discord is committed, and CI fails on any diff ✅. But generation runs `dart pub get` (network!), `dart format` and `dart fix --apply` (`render/formatting.dart#L475-L488`), so the result depends on the SDK version on the machine |
| R13.2 | ✅ | `very_good_analysis`, targeted ignores; 1.4.0 cut the number of lints `dart fix` finds on the GitHub regeneration by an order of magnitude |
| R13.5 | ⚠️ | **Generates round-trip tests** for every schema in `test/gen/`. Useful, but contradicts R13.5 "no test stubs by default" |
| R15.3 | ✅ | Real specs: GitHub, Discord (~511 schemas), SpaceTraders, Train Travel, Backstage, Petstore. Each must pass `dart analyze` and synthesized round-trip tests (README "Tested specs") |

### 3.4 Verification of the author's claims

There are no claims to check in the space_gen assignment. But the R7.3 finding is worth attention: up to 1.4.0 space_gen likewise sent `{"x": null}` for **all** optional fields, and the author described this as "we produced the invalid payload automatically" (PR #321). After the fix, the behaviour matches tonik: optional + nullable fields still send `null`.

### 3.5 Issue tracker problems and lessons

| Issue | Gist | Lesson |
|---|---|---|
| [#213](https://github.com/eseidel/space_gen/issues/213) | RFC 7396: how to tell "leave unchanged" from "clear" in PATCH. The author: only one cell of the eight has three states, and `T?` cannot hold it | Confirms R7.1–R7.2. A separate type (such as `Optional<T?>`) or a PATCH mode limited to exactly this cell is needed |
| [#373](https://github.com/eseidel/space_gen/issues/373) and PR #374 | Users need resilience to new enum values; the PR proposes a sealed `Known`/`Unknown(raw)` | Confirms R8.1. Open decision 7: whether to allow sending `raw`. The PR chooses "yes" for the sake of the GET→PUT round-trip; R8.2 says "no". It is worth making this a policy with the default "forbidden" |
| [#100](https://github.com/eseidel/space_gen/issues/100) | `style` and `explode` were dropped: "silently producing wrong URLs… the API just 400s" | R10.3 is needed from the start, and what is unsupported must produce a diagnostic |
| [#358](https://github.com/eseidel/space_gen/issues/358) | Two documents with the same `#/components/schemas/Foo` merge | A schema's identity is the **absolute URI of the document + pointer**, not a pointer within the document |
| [#185](https://github.com/eseidel/space_gen/issues/185) | `int64` on web (dart2js) loses precision above 2^53 | A configurable `int64` mapping (`int`, `BigInt`, `String`) is needed; relates to R6.2 |
| [#186](https://github.com/eseidel/space_gen/issues/186) | Because `readOnly` is ignored, the request has to carry fields the server fills in (there are 81 such in GitHub) | Separate the request and response shapes, or at least do not require `readOnly` fields in the request constructor (R6.1) |
| [#372](https://github.com/eseidel/space_gen/issues/372) | A `oneOf` with shape dispatch is unreachable through a parent property | Test not only decoding of a union directly, but also a union as a field, a list element, a body |
| [#271](https://github.com/eseidel/space_gen/issues/271), [#375](https://github.com/eseidel/space_gen/issues/375) | Unused imports and `public_member_api_docs` in the consumer | R13.2: test the output under several lint sets, not only under one's own |
| Code | Transport → `ApiException(400)`; `dart pub get` during generation; `UnimplementedError` stubs | R11.7; R13.1 (do not depend on the network or `dart fix`); R2.5 (instead of a runtime stub, a diagnostic with an override) |

### 3.6 What is worth borrowing

1. **The phase architecture** Load → Parse (with pointer) → Resolve → Dispatch → Naming → Render. The phases are pure, I/O only at the input. The resolver knows nothing about Dart. This is practically a ready answer to decision 5 on "isolating the spec model from generation".
2. **A JsonPointer on every node** and **tracking of unused keys** (`markUsed` / `_warnUnused`). The latter is a cheap way to find unsupported keywords and `x-*` (R2.2, R15.5 "support matrix").
3. **Dispatch as a separate phase with an IR of predicates**. A good basis for R9.2: "error / structural (opt-in) / raw" are simply different `DispatchDecision`s.
4. **A global naming pass** `Map<JsonPointer, String>` (R5.2, R5.4, R13.1).
5. **An explicit required × nullable × default matrix with 8 rows** and a test for every cell (PR #321). It is worth taking as the specification of R6.1 and extending it with a ninth "tri-state" cell.
6. **A separate `Date` type** for `format: date`; **`AuthRequest` as structured metadata** per operation (R10.8; for Dio, via `extra`).
7. **The policy "we own only our own directories"** and **ignores in the files themselves** instead of global ones (R4.3, R13.2).
8. **Regenerating real specs in the repository with a diff gate in CI** (R13.1, R15.3). But without `dart fix` and without the network during generation.

---

## 4. Can `tonik_parse` / `tonik_core` be reused (decision 5)

**Conclusion: no, as the parser and spec model of the new tool. Yes, as a source of ideas, a test oracle and a corpus.**

| Criterion | What tonik has | Consequence for the new tool |
|---|---|---|
| API status | The READMEs of both packages: "This is an internal package used by Tonik's code generation pipeline" (documentation). The public surface of `tonik_parse` is one class `Importer({contentTypes, contentMediaTypes}).import(Map<String, dynamic>) → core.ApiDocument` (`tonik_parse/lib/tonik_parse.dart`, `importer.dart#L17-L106`) | There is no stability contract. There are no third-party consumers on pub.dev |
| Versioning | 0.x; all 5 packages are released together; breaking changes in `tonik_parse`: 0.2.0, 0.9.0, **0.10.0 (3 of them)**; in `tonik_core`: 0.2.0, **0.10.0 (2 of them)** (CHANGELOG). New minor releases every month | One would have to pin an exact version and rewrite the adapter in almost every release |
| SDK | `sdk: '>=3.13.0 <4.0.0'`, primary constructors everywhere (`class Importer({…})`) | If the new tool is added as a `dev_dependency` in a Flutter project, the Dart ≥ 3.13 requirement passes on to all users |
| Tolerance to defects | Parsing via strict `as` casts: `json['openapi'] as String`, `(json['paths'] as Map<String, dynamic>)`, `(map['required'] as List<dynamic>?)` (`open_api_object.dart#L19-L39`, `schema.dart#L98-L141`). About 45 `throw` (`UnimplementedError`, `ArgumentError`, `FormatException`) and only ~15 `log.warning` calls in the whole package. **The first error stops the whole import** | R2.1–R2.5 are impossible without a fork. Typical defects from NestJS, FastAPI or ASP.NET (`required: true`, unknown `style`, external ref) break generation |
| Source locations | YAML is turned into a plain `Map` (spans are lost, `openapi_loader.dart#L59-L69`). `Context` is the path for **names**: it strips leading `/`, replaces `/` with `-`, and does not escape `~` (`context.dart#L40-L44`) | A JSON Pointer and line/column for R2.2 and R3.1 (addressing overrides) would have to be added to every DTO |
| Model completeness | Dropped: `minLength`, `pattern`, `minimum`… (`schema.dart#L153-L155`), schema `title`, `xml`, `externalDocs`, all `x-*` except `x-dart-name` and `x-dart-enum`, root `security` ("We ignore security properties", `open_api_object.dart#L41`), `webhooks` | Blocked: R6.7, R8.4, R6.4 (via `x-`), R12.2 (via `x-`), and normalizer rules that need raw data |
| 3.1 and 3.2 | 3.1 partially (see 1.3); 3.2 is not supported, `itemSchema` only in PR #324; external `$ref` is explicitly listed among the non-goals | R1.2 ❌, R1.4 ❌ |
| Coupling to the tonik generator | `tonik_core` is a **lowered IR**, not a spec model: `ClassModel`, `AllOfModel`, `AnyOfModel` with tonik's decisions (allOf as composition, anyOf as nullable fields), `Property.isRequired/isNullable`. The fields are **mutable** (`required var Set<Model> models`; transformers change them in place, `api_document.dart`, `allof_normalizer.dart`). The model imports the **runtime** `tonik_util` (`EncodingShape` in `model.dart#L7,#L11-L12`). The tonik config (`FilterConfig`, `NameOverridesConfig`, `EnumConfig`) and the transformers also live in `tonik_core` | One would have either to live with tonik's architectural decisions, which diverge from R6.3 and R9, or to take on extra dependencies. The isolation between "spec model" and "generation" (the essence of decision 5) is absent here |
| License | MIT | A fork is legal; but fork + divergence = our own parser with someone else's history |

**What exactly to take from tonik:**
1. **The `integration_test/*` corpus** and the scenarios `adversarial_strings`, `naming`, `nullable_bodies`, `ref_siblings`, `type_arrays`, `boolean_schemas`, `fastify_type_provider_zod`. Before copying, check the licenses of the specs themselves.
2. **Runtime codecs for parameter styles** (`tonik_util/lib/src/encoding/*`) as a reference for comparison tests.
3. The list of edge cases from CHANGELOG 0.9 and 0.10: empty arrays in query, `allowReserved`, encoding of object keys in form, charset. It is a ready checklist for the R10.3 and R10.4 tests.

**Recommendation for decision 5.** Our own parser in the spirit of space_gen:
- a **lossless** DTO layer with `JsonPointer` + `SourceSpan` + `extensions: Map<String, Object?>` on every node;
- **collection** of diagnostics instead of exceptions;
- a separate resolver keyed by "absolute URI + pointer";
- a separate **immutable** semantic IR that contains nothing about Dart;
- dispatch and naming phases as separate pure passes;
- the normalizer (R2.1) and overrides (R3) work at the level of the lossless DTO or an overlay **before** resolution. Then the pointer from a diagnostic addresses the override directly.

---

## 5. Summary matrix by key requirements

| Requirement | tonik | swagger_to_dart | space_gen |
|---|---|---|---|
| R1.2 external `$ref` | ❌ | ❌ | ✅ (#358) |
| R2.2 diagnostic with pointer | ❌ | ❌ | ⚠️ (has pointer, no codes, first error only) |
| R3 overrides | ⚠️ names only | ⚠️ names/prefixes only | ❌ |
| R4.2 tree-shaking | ❌ | ❌ | ❌ |
| R6.1 matrix | ⚠️ 3/4 | ⚠️ | ✅ 7/8 (no tri-state) |
| R6.3 allOf flat | ⚠️ composition | ✅ | ✅ |
| R6.4 generics | ❌ | ✅ (framework conventions) | ❌ |
| R7.3 do not send null | ⚠️ (opt+nullable sends) | ❌ (sends all) | ⚠️ (opt+nullable sends) |
| R8.1 raw enum | ❌ | ❌ | ❌ (PR #374) |
| R8.2 do not send unknown | ✅ | ❌ | — (throws on decoding) |
| R9.1 unknown variant with raw | ❌ | ✅ opt-in | ❌ |
| R10.1 do not mutate the client | ❌ (`baseUrl`) | ✅ | ✅ |
| R10.2 `onError` | ❌ | ✅ | — (http) |
| R10.3 styles | ✅ all | ❌ (+ cookie bug) | ⚠️ form/explode only |
| R10.5 operationId in the request | ❌ | ✅ (`@Extras`, with a caveat) | ❌ |
| R10.7 abstract API | ⚠️ | ✅ | ⚠️ |
| R11 typed errors | ✅ (in the success channel) | ❌ | ⚠️ (`default` only) |
| R11.7 transport ≠ HTTP | ✅ | ⚠️ | ❌ (400) |
| R12 SSE | ❌ (PR #324) | ❌ | ❌ |
| R13.1 determinism | ⚠️ | ✅ golden | ⚠️ (`dart fix` + network) |
| R15.3 real specs | ✅✅ | ✅ (fixtures) | ✅ (GitHub, Discord) |
| build_runner | no | yes | no |
| Dio | ✅ | ✅ | ❌ |

---

## 6. Sources

Base permalinks (all code links above are relative to them):
- tonik: `https://github.com/t-unit/tonik/blob/f58c84a9ec9b6b93f8b146b07b933c100e811a81/`
- swagger_to_dart: `https://github.com/masreplay/api_spec_to_dart/blob/fb1e11b66629817003d808f7e7a8f186809c41ac/`
- space_gen: `https://github.com/eseidel/space_gen/blob/983088e85fa239820604d1b39f4b71d4292f7a3d/`

Key files:
- tonik (a): [`packages/tonik_generate/lib/src/transport/dio/dio_options_generator.dart#L25-L65`](https://github.com/t-unit/tonik/blob/f58c84a9ec9b6b93f8b146b07b933c100e811a81/packages/tonik_generate/lib/src/transport/dio/dio_options_generator.dart#L25-L65); [`packages/tonik_generate/test/src/operation/options_generator_test.dart#L52-L62`](https://github.com/t-unit/tonik/blob/f58c84a9ec9b6b93f8b146b07b933c100e811a81/packages/tonik_generate/test/src/operation/options_generator_test.dart#L52-L62); [`packages/tonik_generate/lib/src/transport/dio_backend_generator.dart#L229-L256`](https://github.com/t-unit/tonik/blob/f58c84a9ec9b6b93f8b146b07b933c100e811a81/packages/tonik_generate/lib/src/transport/dio_backend_generator.dart#L229-L256); [`packages/tonik_generate/lib/src/operation/dio_operation_base_generator.dart#L320-L460`](https://github.com/t-unit/tonik/blob/f58c84a9ec9b6b93f8b146b07b933c100e811a81/packages/tonik_generate/lib/src/operation/dio_operation_base_generator.dart#L320-L460)
- tonik (b): [`packages/tonik_generate/lib/src/model/class_generator.dart#L810-L878`](https://github.com/t-unit/tonik/blob/f58c84a9ec9b6b93f8b146b07b933c100e811a81/packages/tonik_generate/lib/src/model/class_generator.dart#L810-L878); [`packages/tonik_generate/test/src/model/class_json_generator_test.dart#L130-L210`](https://github.com/t-unit/tonik/blob/f58c84a9ec9b6b93f8b146b07b933c100e811a81/packages/tonik_generate/test/src/model/class_json_generator_test.dart#L130-L210)
- tonik (c): [`packages/tonik_generate/lib/src/model/enum_generator.dart#L290-L452`](https://github.com/t-unit/tonik/blob/f58c84a9ec9b6b93f8b146b07b933c100e811a81/packages/tonik_generate/lib/src/model/enum_generator.dart#L290-L452); [`packages/tonik_core/lib/src/transformer/config_transformer.dart#L162-L183`](https://github.com/t-unit/tonik/blob/f58c84a9ec9b6b93f8b146b07b933c100e811a81/packages/tonik_core/lib/src/transformer/config_transformer.dart#L162-L183); [`packages/tonik/lib/src/config/config_loader.dart#L338`](https://github.com/t-unit/tonik/blob/f58c84a9ec9b6b93f8b146b07b933c100e811a81/packages/tonik/lib/src/config/config_loader.dart#L338); [`packages/tonik_generate/test/src/model/enum_generator_test.dart#L2167-L2215`](https://github.com/t-unit/tonik/blob/f58c84a9ec9b6b93f8b146b07b933c100e811a81/packages/tonik_generate/test/src/model/enum_generator_test.dart#L2167-L2215)
- tonik parse/core: `packages/tonik_parse/lib/src/importer.dart`, `…/model/schema.dart`, `…/model/open_api_object.dart`, `…/model_importer.dart#L539-L557`, `packages/tonik_core/lib/src/util/context.dart`, `…/model/api_document.dart`, `…/model/model.dart`, `packages/tonik/lib/src/openapi_loader.dart`, `packages/tonik/bin/tonik.dart#L114-L195`
- tonik docs: `README.md`, `docs/features.md`, `docs/configuration.md`, `docs/roadmap.md`, `docs/http_backends.md`, `docs/authentication.md`, `docs/composite_data_types.md`, `docs/additional_properties.md`, `CHANGELOG.md`, `examples/README.md`
- tonik issues and PRs: [#31](https://github.com/t-unit/tonik/issues/31), [#59](https://github.com/t-unit/tonik/issues/59), [#88](https://github.com/t-unit/tonik/issues/88), [#165](https://github.com/t-unit/tonik/issues/165), [PR #324](https://github.com/t-unit/tonik/pull/324), [PR #325](https://github.com/t-unit/tonik/pull/325)
- swagger_to_dart (b): [`packages/swagger_to_dart/lib/src/generator/model/json_serialization_convertor_generator.dart#L47-L50`](https://github.com/masreplay/api_spec_to_dart/blob/fb1e11b66629817003d808f7e7a8f186809c41ac/packages/swagger_to_dart/lib/src/generator/model/json_serialization_convertor_generator.dart#L47-L50); [`…/model/strategy/property_generator_strategy.dart#L39-L60`](https://github.com/masreplay/api_spec_to_dart/blob/fb1e11b66629817003d808f7e7a8f186809c41ac/packages/swagger_to_dart/lib/src/generator/model/strategy/property_generator_strategy.dart#L39-L60); [`…/api_client/api_client_generator.dart#L320-L345`](https://github.com/masreplay/api_spec_to_dart/blob/fb1e11b66629817003d808f7e7a8f186809c41ac/packages/swagger_to_dart/lib/src/generator/api_client/api_client_generator.dart#L320-L345); [`packages/swagger_to_dart/test/fixtures/class_prefix/roundtrip_test.dart.tmpl`](https://github.com/masreplay/api_spec_to_dart/blob/fb1e11b66629817003d808f7e7a8f186809c41ac/packages/swagger_to_dart/test/fixtures/class_prefix/roundtrip_test.dart.tmpl); `packages/swagger_to_dart_e2e/build.yaml`; `packages/swagger_to_dart/example/build.yaml`
- swagger_to_dart other: `…/api_client/api_client_generator.dart#L650-L680` (cookie → Header), `…/model/strategy/enum_model_generator_strategy.dart#L85-L170`, `test/fixtures/enum_fallback_unknown/*`, `…/schema/openapi/v3/open_api.dart#L111-L125`, `README.md`, `CHANGELOG.md` (5.0.0, 6.0.0), `CONTRIBUTING.md`, `schemas/README.md`
- swagger_to_dart issues: [#49](https://github.com/masreplay/api_spec_to_dart/issues/49), [#50](https://github.com/masreplay/api_spec_to_dart/issues/50), [#52](https://github.com/masreplay/api_spec_to_dart/issues/52), [#54](https://github.com/masreplay/api_spec_to_dart/issues/54), [#55](https://github.com/masreplay/api_spec_to_dart/issues/55), [#56](https://github.com/masreplay/api_spec_to_dart/issues/56), [#58](https://github.com/masreplay/api_spec_to_dart/issues/58), [#59](https://github.com/masreplay/api_spec_to_dart/issues/59), [#60](https://github.com/masreplay/api_spec_to_dart/issues/60), [#61](https://github.com/masreplay/api_spec_to_dart/issues/61), [#63](https://github.com/masreplay/api_spec_to_dart/issues/63), [#64](https://github.com/masreplay/api_spec_to_dart/issues/64)
- retrofit_generator 10.2.9 (pub cache): `lib/src/generator.dart#L1941-L1962`
- space_gen: `README.md`, `ARCHITECTURE.md`, `CHANGELOG.md` (1.3.0, 1.4.0), `CLAUDE.md`, `lib/src/parser.dart#L212-L245,#L300-L358,#L1615-L1640`, `lib/src/render/render_tree.dart#L866-L880,#L4540`, `lib/src/render/formatting.dart#L455-L488`, `lib/src/cli.dart#L42-L60`, `lib/templates/{api_client.dart,api.mustache,schema_enum.mustache,schema_one_of.mustache,schema_object.mustache,pubspec.mustache,analysis_options.mustache}`, `gen_tests/security/lib/api/default_api.dart`, `gen_tests/third_party/`
- space_gen issues and PRs: [#100](https://github.com/eseidel/space_gen/issues/100), [#185](https://github.com/eseidel/space_gen/issues/185), [#186](https://github.com/eseidel/space_gen/issues/186), [#213](https://github.com/eseidel/space_gen/issues/213), [#271](https://github.com/eseidel/space_gen/issues/271), [#358](https://github.com/eseidel/space_gen/issues/358), [#372](https://github.com/eseidel/space_gen/issues/372), [#373](https://github.com/eseidel/space_gen/issues/373), [#375](https://github.com/eseidel/space_gen/issues/375), [PR #321](https://github.com/eseidel/space_gen/pull/321), [PR #374](https://github.com/eseidel/space_gen/pull/374)
- pub.dev API: `https://pub.dev/api/packages/{tonik,tonik_parse,tonik_core,tonik_generate,tonik_util,swagger_to_dart,space_gen}` and `/score`; `https://pub.dev/api/search?q=dependency:tonik_parse`
- GitHub API: `gh api repos/{t-unit/tonik, masreplay/api_spec_to_dart, eseidel/space_gen}`; `gh issue list` and `gh pr list` for each
