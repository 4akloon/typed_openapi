# 04. The "long tail" of the Dart ecosystem: other generators, large SDKs, building blocks, SSE

Status as of **2026-10-11**. Not included here are OpenAPI Generator (dart / dart-dio), swagger_parser, swagger_dart_code_generator, tonik, swagger_to_dart and space_gen: other documents cover them.

**How it was collected.** Searches on pub.dev for the queries `openapi`, `swagger`, `topic:openapi`, `openapi generator`, `kiota`, `chopper openapi`, `openapi freezed`, `openapi parser`, `server-sent events`, `topic:sse`, etc. Then the metadata from the pub.dev API and GitHub API, shallow clones of the repositories (reading code only), and four of our own experiments in a separate scratch project: parsing via `package:yaml`, how typed models react to defects, YAML coercions, and conformance of SSE parsers to WHATWG. The scripts are in `scratchpad/longtail-exp/bin/` (`exp.dart`, `defects.dart`, `yaml_gotchas.dart`, `sse_conf.dart`).

Notation: "dl/30d" — downloads over 30 days per the pub.dev search API; "♥" — likes on pub.dev.

---

## 1. Summary table of generators

| Generator | Latest version (date) | ♥ / dl/30d | Status | Output type | Models / serialization | HTTP | OAS | Why it is interesting to us |
|---|---|---|---|---|---|---|---|---|
| **degenerate** (blopker) | 0.5.0 (2026-09-10), first release 2026-03 | 5 / 517 | active, 1 author | ready code, CLI, no build_runner | own `final class`, hand-written `fromJson`, extension types | own `ApiClient` + adapters `degenerate_dio` / `degenerate_http` | 3.0, 3.1, partly 3.2 | `Omittable` (3 states), raw values of unknown enums, `$Unknown` in a union, unions by status, SSE/JSONL with `itemSchema`, tree-shaking by tag and path, golden tests on Stripe, GitHub, K8s, OpenAI, Cloudflare |
| **Kiota (Dart)** (Microsoft) | `microsoft_kiota_abstractions` 0.3.0 (2026-09-18) | 2 / ~21k | Dart in **preview** status | ready code, CLI on .NET | own `Parsable`, mutable models | `package:http` (`microsoft_kiota_http`) | 3.x (OpenAPI.NET) | A catalog of named validation rules, with individual rules switchable off; glob filters `--include-path`/`--exclude-path` with `#METHOD`; a lock file with a hash; the order of error mapping |
| **dynamite** (Nextcloud → provokateurin) | 0.6.0 (2026-03-27) | 2 / 165 | repository moved 2026-04, quiet since then | `build_runner` | `built_value` | `package:http` + `dynamite_runtime` | "a common subset" of 3.0/3.1 | The generator's major version grows on a breaking change in the generated code. The generator is under AGPL, the runtime under BSD |
| **openapi_spec** (tazatechnology) | 0.15.0 (2025-08-03) | 7 / 3 832 | stalled for ~14 months | Dart script / CLI | freezed + json_serializable | `package:http` | 3.0 (3.1 partly) | Earlier, davidmigloz's clients were built on it (via a fork). Model + parser + generator in one package |
| **openapi_code_builder + openapi_base** (hpoul) | 1.8.1+1 (2026-02-10); in git 1.8.2-dev.7 (2026-10-08) | 16 / 327 | alive but slow-moving | `build_runner` (`*.openapi.yaml`) | json_serializable | own `RequestSender` (http) | 3.0, YAML only | Generates both the client and server stubs (shelf). The response is a type for each status |
| **florval** (encer-jp) | 0.4.1 (2026-07-10), first release 2026-03 | 4 / 196 | active | CLI → freezed (then build_runner) | freezed 3 + json_serializable | **the user's Dio** (via a Riverpod provider) | 3.1, 3.0→3.1, 2.0 partly | a sealed union by status **without** `validateStatus: true` (catches `DioException`), `JsonOptional<T>` for PATCH, Riverpod |
| **dart_openapi_generator** (AngeloAvv) | 0.4.0 (2026-09-28), first release 2026-05 | 0 / 784 | active | `build_runner` (single-pass trick) | hand-written `final class` | Dio | 3.0–3.2, `$ref` only within a file, `anyOf` gives an error | `SourceMap`: JSON pointer → `SourceSpan` from `package:yaml` for diagnostics |
| **openapi_flutter_gen** (PurpleSoft) | 0.2.12 (2026-08-31) | 0 / 178 | active | CLI, no build_runner | hand-written immutable classes | Dio | 2.0, 3.x | Deserialization in an Isolate. **License: AGPL-3.0 or commercial** |
| **flap** (miracle101000) | 0.0.7 (2026-09-12) | 2 / 276 | early-stage | CLI binary in **Rust** | freezed + json_serializable | Dio or http | 2.0, 3.0, 3.1 | Jinja2 templates can be overridden. Unsupported constructs degrade to `dynamic` with a warning |
| **koi_swagger_parser** (mrkoi-is) | 0.2.0 (2026-07-31) | 0 / 39 | early-stage | CLI → Retrofit + freezed | freezed + json_serializable | Dio / Retrofit | 3.0, 3.1 | Mappings of models, fields and parameters with diagnostics for collisions. `x-enum-varnames` and a fallback for an unknown enum |
| **openapi_retrofit_generator** / **openapi_sdk_gen** | 2.0.4 (2026-01-08) / 2.6.3 (2026-09-24) | 5 / 1 911; 0 / 997 | forks of swagger_parser | CLI → Retrofit | json_serializable / freezed / dart_mappable | Retrofit + Dio | 2.0, 3.0, 3.1 | They show that swagger_parser is forked, because upstream cannot keep up with the fixes |
| **open_api_client_generator** (BreX900) | 1.5.0 (2026-09-26) | 1 / 553 | alive but slow-moving | CLI or Dart script | json_serializable and other "codec"s | Dio / http | 3.x | Pluggable `ClientCodec` and `SerializationCodec` |
| **dart_openapi_codegen** (famedly, Matrix) | not on pub, git | — | alive (2026-09) | CLI | own | own | 3.x, JSON only | **A rules file** (exclude, voidResponse, imports) and a set of `.patch` files for the spec |
| **@sdk-it/dart** (npm) | 0.46.8 (2026-10-08) | 541 dl/month on npm | active | Node CLI | own | — | 3.x | A generator in TypeScript; for Dart it is rather an exotic choice |
| **openapi_to_retrofit** (Seuketchi) | 0.1.0 (2026-08-14) | 0 / 53 | just appeared, 0 pub points | CLI → Retrofit | json_serializable | Retrofit | 3.x | Moves spec constraints into the decoders (R6.7) |
| openapi_freezed_dio_builder (jonasbark) | 0.9.7 (2024-06-05) | 29 / 28 | **dead** (fork of hpoul) | build_runner | freezed | Dio | 3.0 | — |
| openapi_dart_common (dart-ogurets) | 5.1.2 (2026-06-25) | 4 / 2 101 | alive | runtime for the Java/Maven generator | — | — | — | A separate Java generation branch, not relevant to us |

Besides these, pub.dev has "noise": generators of clean-architecture scaffolds from Swagger. These are `flutter_feature_generator`, `swagger_dart_generator`, `api_generator`, `clean_api_codegen`, `nebula_api_studio` and `dart_swagger_to_models` (models only). Each has fewer than 130 dl/30d. The utility `openapi_enum_patch` (1.3.1, 2026-09-19) is a pre/post-processor for swagger_parser that gives names to integer enums. The very fact of its appearance shows demand for overrides (R3) and `x-enum-varnames` (R8.4).

**The main observation.** In 2026 a wave of new generators appeared: degenerate, florval, dart_openapi_generator, openapi_flutter_gen, flap, koi_swagger_parser, openapi_to_retrofit, and forks of swagger_parser. Almost all have a single author and fewer than 1k downloads per 30 days, and some were clearly written with the help of AI agents. **None of them builds a product around imperfect specs**: there are no named normalization rules with diagnostic codes, no overrides file with addressing of elements, and no baseline/ratchet. Closest in idea are Kiota's validation rules and famedly's rules file plus patches.

---

## 2. Short profiles

### 2.1 degenerate — the closest by features (in detail)

Sources: [pub](https://pub.dev/packages/degenerate), [GitHub](https://github.com/blopker/degenerate), README, TODO.md and the code in the clone.

- **Architecture.** Pipeline `parse → normalize → lower to IR → emit` on top of `code_builder`. The parser is its own: `yaml` + its own `ref_inliner` with support for external files and cycles; remote `$ref` are not supported. The normalizer flattens `allOf`, builds separate models for the request and the response by `readOnly`/`writeOnly`, and determines discriminators ([structure of lib/src](https://github.com/blopker/degenerate/tree/main/packages/degenerate/lib/src)). The generator is about 11k lines.
- **Data model.** Generates `final class` with a `const` constructor, `fromJson`/`toJson`, `copyWith`, `==`/`hashCode` and an overflow map for `additionalProperties`. Named primitives become **extension types** (`extension type const UserId(String value)`). An enum is a `final class` with static constants, where `fromJson` for an unknown value **keeps the raw string** (`isUnknown`). For discriminated unions a `sealed` class is generated with `X$Unknown(json)`. For non-discriminated `oneOf` (2–9 variants) — `typedef X = OneOf2<A,B>` from the runtime container. `anyOf` — a class with several "views" and the stored raw JSON ([README: Data Classes / Enums / Unions](https://github.com/blopker/degenerate#data-classes)).
- **Three states (R7).** An optional + nullable field becomes `Omittable<T?>`: absent, `Omittable(null)` or a value. There is a flag `--omittable=nullable|all|off` as an "escape hatch" for servers that do not follow the spec ([README: Omittable](https://github.com/blopker/degenerate#omittable-fields-json-merge-patch)). This is almost verbatim R7.2. A `default` value from the schema does **not** make the field present: for it there is a separate getter `fieldOrDefault`.
- **Responses.** `ApiResult<T,E>` with variants `ApiSuccess`, `ApiError`, `ApiParseException` and `ApiException`. If there are several responses, a sealed union by status and media type is generated (`PostAuthSuccess200`, `…Success2xx`, `…SuccessUnknown(response)`) ([README](https://github.com/blopker/degenerate#request-and-response-models)). This covers R10.6, R11.1 and R11.3.
- **SSE / JSONL.** For `text/event-stream` and `application/jsonl` with `itemSchema` the method returns `Stream<T>` ([README: Streaming](https://github.com/blopker/degenerate#streaming)). This is the only generator in my long tail with SSE support.
- **Filters.** `--tag` and `--path` with tree-shaking of unused types. Tags are compared case-insensitively, ignoring spaces, `_` and `-` (R4.1, R4.2, R5.3). There is also `--unwrap-fields=result` to unwrap envelopes (R6.4, partly).
- **Testing.** Snapshot tests (golden) of public specs: Cloudflare, GitHub 3.1, Kubernetes, OpenAI, Shopify, Stripe, Twilio, "unhinged" 3.2. For them `dart analyze` is run; separately there are runtime wire tests ([Makefile](https://github.com/blopker/degenerate/blob/main/Makefile), [snapshots/public](https://github.com/blopker/degenerate/tree/main/snapshots/public)). This is practically a ready recipe for R15.3.
- **Generation safety.** Issues [#15](https://github.com/blopker/degenerate/issues/15) ("Escape spec-controlled strings at every code interpolation site") and [#18](https://github.com/blopker/degenerate/issues/18) ("SpecString": spec text as a separate type). Any string from the spec in a template is a potential code injection.
- **Problems relative to our requirements.**
  - The Dio adapter calls `requestUri(..., validateStatus: (_) => true)` ([dio_api_client.dart](https://github.com/blopker/degenerate/blob/main/packages/degenerate_dio/lib/src/dio_api_client.dart)). This is the same problem as in tonik: Dio interceptors' `onError` does not fire for 4xx/5xx (**R10.2 ✗**). The interceptors in degenerate are their own, in OkHttp style, not Dio's.
  - Diagnostics are only `List<String> warnings` lines and `--verbose`. No codes, JSON pointers or levels (**R2.2 ✗**). No overrides (**R3 ✗**).
  - Serialization is custom, not json_serializable. The output, per the README "not formatted", requires running dart format (R13.2).
  - The SSE parser does not handle `retry`, does not reconnect, accepts an `id` with NUL and yields an incomplete event at the end of the stream. See §5.
- **What to copy:** the semantics of `Omittable` with its modes, `fieldOrDefault`, naming of status variants, models by direction (readOnly/writeOnly), the set of snapshot specs with the scorecard "0 issues", the `SpecString` discipline and `--unwrap-fields`.

### 2.2 Kiota (Microsoft) — a product "for imperfect specifications" in a different style (in detail)

Sources: [kiota README](https://github.com/microsoft/kiota), [kiota-dart](https://github.com/microsoft/kiota-dart), docs [using](https://learn.microsoft.com/en-us/openapi/kiota/using), [errors](https://learn.microsoft.com/en-us/openapi/kiota/errors) and [Dart quickstart](https://learn.microsoft.com/en-us/openapi/kiota/quickstarts/dart).

- **Dart status.** In the README's table of supported languages, 🛠️ "in preview" is marked for generation, abstractions, serialization and HTTP. The runtime packages have versions 0.0.x–0.3.0; serialization/http have about 20k downloads/30d. There are open Dart bugs: [#7807](https://github.com/microsoft/kiota/issues/7807) (code for the Notion API does not compile) and [#7997](https://github.com/microsoft/kiota/issues/7997) (non-deterministic generation on binary unions — a mirror of our R13.1).
- **API shape.** Request builders repeat the URL structure: `client.posts.byPostId(5).getAsync()`. Models are mutable (`Post()..title = …`), responses are nullable, transport is `package:http` only ([quickstart](https://learn.microsoft.com/en-us/openapi/kiota/quickstarts/dart)). For Flutter teams on Dio this does not fit. However, one public Stripe client for Dart, [stripe_api_client](https://pub.dev/packages/stripe_api_client), is built on Kiota.
- **What to copy.**
  1. **Named validation rules.** Each rule can be turned off separately: `--disable-validation-rules <Name>|all`. Rules: `DivergentResponseSchema`, `GetWithBody`, `InconsistentTypeFormat`, `KnownAndNotSupportedFormats`, `MissingDiscriminator`, `MultipleServerEntries`, `NoContentWithBody`, `NoServerEntry`, `UrlFormEncodedComplex` ([using](https://learn.microsoft.com/en-us/openapi/kiota/using#--disable-validation-rules---dvr)). This is a direct prototype of R2.1 and R2.2, although in Kiota a rule only warns and fixes nothing.
  2. **Path filters.** `--include-path`/`--exclude-path` — glob patterns with a `#GET` suffix. Semantics: "(no include OR a match with include) AND (no exclude OR no match with exclude)" (R4.1).
  3. **`kiota-lock.json`.** Stores all generation parameters and a hash of the spec; without changes generation is skipped. The command `kiota update` regenerates everything from the lock files (R13.1, R1.3).
  4. **Error mapping order.** Exact code, then range `4XX`/`5XX`, then `default`, then the base `ApiException` with status and headers. For an undocumented status there is a stable message ([errors](https://learn.microsoft.com/en-us/openapi/kiota/errors)) (R11.1, R11.3). The extension `x-ms-primary-error-message` marks the field with the error text (an idea for the `x-` registry, R15.5).
  5. `--structured-mime-types` with q-weights per RFC 9110 decides for which content-type to build models (R10.4, R3.1 "content-type of the body").

### 2.3 florval — the right pattern for Dio

- Does not create its own HTTP client: it generates a Riverpod provider `apiDioProvider`, which the user overrides with their own Dio ([README: Wire up your Dio](https://github.com/encer-jp/florval#5-wire-up-your-dio)) (R10.1).
- The generated method does not turn off `validateStatus`. It wraps the call in `try { … } on DioException catch (e) { if (e.response != null) → typed variant; else rethrow; }` ([client_generator.dart](https://github.com/encer-jp/florval/blob/main/lib/src/generator/client_generator.dart)). Dio interceptors see the error in `onError`, and the user gets a sealed union by status with `…Unknown(statusCode, body)`. **This is exactly the behaviour that R10.2 and R11.3 require.**
- Other features: `JsonOptional<T>` for PUT/PATCH (R7), cursor pagination, `@Deprecated`, doc comments. As its parser it uses `openapi_spec_plus`.
- Downsides: mandatory coupling to Riverpod for the Dio provider, freezed plus build_runner, no SSE. In the generator I did not find a fallback for unknown enums (`unknownEnumValue`), so decoding probably fails (R8.1 ✗).

### 2.4 dart_openapi_generator (AngeloAvv)

- `SourceMap`: walks the `YamlNode` tree before conversion to a `Map` and indexes `SourceSpan` by JSON pointer (RFC 6901 with escaping `~0`/`~1`) ([source_map.dart](https://github.com/AngeloAvv/dart_openapi_generator/blob/main/lib/src/parser/source_map.dart)). Parser errors carry sourceSpan. The author believes there are no spans for JSON, but `loadYamlNode` gives them for JSON too (verified, see §4).
- build_runner in "single-pass" mode: the builder factory parses the spec in advance and returns the real `buildExtensions`, so that build_runner knows all the output files ([README: How it works](https://github.com/AngeloAvv/dart_openapi_generator#how-it-works)). This is a clear illustration of the friction between build_runner and a "one input → many files" generator (open decision 1).
- Unknown enum or discriminator → `ArgumentError` (R8.1 ✗, R9.1 ✗). `anyOf` produces a build error. Cookie parameters are not supported; a warning is issued.

### 2.5 dynamite (Nextcloud)

- build_runner + built_value. Its own OpenAPI/JSON Schema models on built_value, `rfc_6901` for pointers, `pattern_check.dart` for checking `pattern` (R6.7) ([pubspec](https://github.com/provokateurin/dynamite/blob/main/packages/dynamite/pubspec.yaml)).
- Versioning: "if there is a breaking change in the generated code the major version of this package will be updated" ([README](https://pub.dev/packages/dynamite)). This is our R15.4.
- The generator is under AGPL-3.0, the runtime under BSD-3, and the generated code is not covered by the license. In April 2026 dynamite and the nextcloud client were moved out of nextcloud/neon into the author's personal repositories ([neon PR #3205](https://github.com/nextcloud/neon/pull/3205)). The last push was 2026-04-26, so the risk of stagnation is high.

### 2.6 openapi_spec (tazatechnology) and the related davidmigloz history

- The package combines spec models (freezed), a parser and schema generators, a client (package:http) and a server. Last release 2025-08-03. Open issues: "LateInitializationError" ([#84](https://github.com/tazatechnology/openapi_spec/issues/84)), compile error for object with `default: {}` ([#85](https://github.com/tazatechnology/openapi_spec/issues/85)) and a request "Replace freezed with dart_mappable" ([#74](https://github.com/tazatechnology/openapi_spec/issues/74)).
- davidmigloz generated `openai_dart`, `googleai_dart` and other clients in `langchain_dart` through **his own fork** of `davidmigloz/openapi_spec` (a git dependency in the [root pubspec](https://github.com/davidmigloz/langchain_dart/blob/main/pubspec.yaml)). He has now **dropped** it, see §3.

### 2.7 The rest briefly

- **openapi_code_builder** (hpoul) ([GitHub](https://github.com/hpoul/openapi_dart)): the oldest native Dart generator (since 2020), build_runner, YAML only, client and server (shelf). Open bugs from 2022–2025 about additionalProperties: true, a spec without components and string:binary. Slowly alive: two fixes in September–October 2026.
- **openapi_flutter_gen**: Isolate-based deserialization and sealed responses. **AGPL or commercial license** ([README](https://github.com/PurpleSoftSrl/openapi_flutter_gen#license)), so the code cannot be copied. Unknown enum → ArgumentError.
- **flap**: a generator in Rust (`flap-spec` → `flap-ir` → `flap-emit-dart`), binaries for five platforms, template overrides via minijinja, a lock file with the SHA-256 of the spec, "lenient loading" with degradation to `dynamic` ([README](https://github.com/miracle101000/flap-dart#crate-responsibilities)). Silent degradation to `dynamic` contradicts R2.5. The lock-file idea is the same as in Kiota.
- **koi_swagger_parser**: claims a separation into load, `$ref`, validation, IR, rendering and "safe incremental writes", mappings of models, fields and parameters "with collision diagnostics", x-enumNames/x-enum-varnames, unknown enum fallback ([README](https://github.com/mrkoi-is/koi_swagger_parser)). The package is new, 39 downloads/30d, so take its claims with caution.
- **openapi_retrofit_generator → openapi_sdk_gen**: "complete rework of swagger_parser", and then a fork of that fork. Open bugs "Nullable not respected" and "nullable: true ignored for single-ref allOf/oneOf" ([issues](https://github.com/westito/openapi_retrofit_generator/issues)). This is exactly the pain point we close in R6.1 and R6.3.
- **open_api_client_generator** (BreX900): pluggable `ClientCodec` (Dio/http) and `SerializationCodec` (json_serializable and others) through a Dart API ([README](https://github.com/BreX900/mek-packages/tree/main/shelf_packages/open_api_client_generator)). Close to our open decision 6 on extensibility, but weakly developed.
- **dart_openapi_codegen** (famedly): generates `matrix_api_lite`. Generation is driven by [`rules/matrix.yaml`](https://github.com/famedly/dart_openapi_codegen/blob/main/rules/matrix.yaml) (sections `exclude`, `voidResponse`, `imports`) and **16 `.patch` files** to the Matrix spec in [`scripts/`](https://github.com/famedly/dart_openapi_codegen/tree/main/scripts) (`no-one-of.patch`, `additional-properties.patch`, etc.). This is a live example that "overrides + spec patches" are needed even for a high-quality spec.

---

## 3. How large Dart SDKs are generated

| SDK | How it is made | Details | Source |
|---|---|---|---|
| `openai_dart` 11.0.0, `anthropic_sdk_dart` 9.0.0, `googleai_dart` 13.0.0, `mistralai_dart` 8.1.0, `ollama_dart` 4.0.0 (davidmigloz) | **By hand, with AI agents**, from the spec. Earlier — openapi_spec (fork) + freezed | The new monorepo `ai_clients_dart` was created 2025-12-19. Versions 1.0.0 — "complete reimplementation… Hand-crafted models (no code generation)", dependencies only `http`, `logging`, `meta`. Python toolkit `api_toolkit` with commands `fetch`, `review` ("diff canonical vs candidate specs and report implementation gaps"), `scaffold` and `verify` | [ai_clients_dart](https://github.com/davidmigloz/ai_clients_dart), [spec-core.md](https://github.com/davidmigloz/ai_clients_dart/blob/main/docs/spec-core.md), [api-toolkit README](https://github.com/davidmigloz/ai_clients_dart/blob/main/.agents/shared/api-toolkit/README.md), [MIGRATION.md](https://github.com/davidmigloz/ai_clients_dart/blob/main/packages/openai_dart/MIGRATION.md), [old location](https://github.com/davidmigloz/langchain_dart/tree/main/packages/openai_dart) |
| `googleapis` | Own generator `discoveryapis_generator` from Google **Discovery** docs, not from OpenAPI | The generated code is committed to the repository | [google/googleapis.dart](https://github.com/google/googleapis.dart) |
| `aws_client` (agilord, community) | Own generator from the JSON models of AWS SDK for JavaScript | The generated code is committed | [agilord/aws_client](https://github.com/agilord/aws_client) |
| Appwrite (`appwrite` 27.0.0, Flutter SDK) | Own `sdk-generator` in PHP with Twig templates. The `utopia-php/openapi` parser reduces OAS 2.0/3.0/3.1 to one canonical model | Templates for each language | [appwrite/sdk-generator](https://github.com/appwrite/sdk-generator) |
| Supabase (`supabase` 2.16.4 and others) | **By hand** (postgrest, auth, storage, realtime, functions). The new `supabase_typegen` generates types from the **DB schema**, not from OpenAPI | Strings are zero-cost **extension types** over the decoded JSON map. Separate `Insert`/`Update` types | [supabase-flutter](https://github.com/supabase/supabase-flutter), [supabase_typegen](https://github.com/supabase/supabase-flutter/tree/main/packages/supabase_typegen) |
| `matrix` 14.0.0 (famedly) | Own `dart_openapi_codegen` + rules + `.patch` files to the spec | See §2.7 | [famedly/dart_openapi_codegen](https://github.com/famedly/dart_openapi_codegen) |
| `nextcloud` 9.0.0 | Own `dynamite` (build_runner, built_value) | See §2.5 | [provokateurin/dynamite](https://github.com/provokateurin/dynamite) |
| `mastodon` 1.1.0 (abraham) | `openapi_generator` (a wrapper over OpenAPI Generator) + **`lib/hacks.dart`**: patches over the generated code | "patches applied to the generated code to fix issues with the OpenAPI spec or the generator" | [mastodon_generator](https://github.com/abraham/mastodon_dart/tree/main/packages/mastodon_generator) |
| Stripe (no official Dart SDK) | `client_stripe` (Celest) generated from `spec3.sdk.json` by an in-house generator. `stripe_api_client` (univelop) generated by Kiota | Both with low popularity (up to 210 downloads/30d) | [celest-dev/dart-api-clients](https://github.com/celest-dev/dart-api-clients/tree/main/clients/stripe), [stripe_api_client](https://pub.dev/packages/stripe_api_client) |
| `pinecone` (tazatechnology) | openapi_spec | Last release 2023-11 | [openapi_spec README](https://github.com/tazatechnology/openapi_spec) |
| Commercial vendors | **Nobody supports Dart** | Fern: TS, Python, Go, Java, C#, PHP, Ruby, Swift, Rust. Stainless: TS, Python, Go, Java, Kotlin, Ruby, PHP, C#, SQL. Speakeasy has no Dart in its docs | [Fern](https://buildwithfern.com/learn/sdks/introduction/overview), [Stainless](https://www.stainless.com/docs/), [Speakeasy](https://www.speakeasy.com/docs/sdks/create-client-sdks) |

**What this shows.**

1. Serious authors **do not use** universal Dart generators. They either write code by hand (davidmigloz, Supabase), or write their own generator for their own format (Google, AWS, Appwrite, Matrix, Nextcloud).
2. Those who still generate from OpenAPI **necessarily patch** either the spec (Matrix: rules plus 16 patches) or the generated code (Mastodon: `hacks.dart`). This is direct confirmation that R2 and R3 are the product's main value.
3. **davidmigloz's arguments** for hand-written code are recorded in [spec-core.md](https://github.com/davidmigloz/ai_clients_dart/blob/main/docs/spec-core.md):
   - minimal dependencies ("Runtime dependencies limited to `http` and `logging` ONLY");
   - "Manual Serialization (No Codegen)… explicit control over wire formats";
   - resource-based grouping of methods;
   - `copyWith` with a sentinel `unsetCopyWithValue`;
   - enum with a mandatory fallback.

   So serious authors reject not generation as such, but build_runner, freezed and superfluous runtime dependencies. A generator that emits ready, clean code with a minimal runtime (R13.3) addresses exactly these reasons.
4. **Lesson on sealed and semver.** `openai_dart` released **11 major versions** between 2026-03-03 and 2026-10-11, `googleai_dart` — 11 major (3→13), `anthropic_sdk_dart` — 9 (data from [pub.dev versions](https://pub.dev/packages/openai_dart/versions)). The cause is visible in MIGRATION.md: "Adding variants to an existing sealed class can break an otherwise unchanged exhaustive switch". Every new event or variant in the spec breaks consumer code, and this directly concerns R14.2.
5. The "spec diff → gap report" scheme from davidmigloz's toolkit is a manual analogue of our R14.1.

---

## 4. Building blocks for the parser (open decision 5)

### 4.1 Packages

| Package | Version (date) | Role | Positions (line/col) | Comment |
|---|---|---|---|---|
| [`yaml`](https://pub.dev/packages/yaml) | 3.1.4 (2026-08-28), dart-lang | Parsing YAML **and JSON** into `YamlNode` | **Yes**: `YamlNode.span` (`SourceSpan`) for every node, including keys | See the experiments below |
| [`source_span`](https://pub.dev/packages/source_span) | 1.10.2 (2026-02-05) | `SourceSpan.message()` prints a snippet with underlining (rustc style) | — | A ready format for human-readable output, R2.2 |
| [`yaml_edit`](https://pub.dev/packages/yaml_edit) | 2.2.4 (2026-02-13) | Editing YAML while preserving comments and indentation | yes | Automatic updating of baseline or override files (R2.3, R3.2: "can be removed") |
| [`checked_yaml`](https://pub.dev/packages/checked_yaml) | 2.0.4 (2025-06-05) | Config decoding errors from json_serializable with spans | yes | R15.2: clear config errors |
| [`json_schema`](https://pub.dev/packages/json_schema) (Workiva) | 5.2.2 (2025-10-08), ♥45 | JSON Schema validator for drafts 4/6/7/2019-09/2020-12 (`constants.dart` has definitions up to `draft2020_12`), `ValidationError` with `instancePath`/`schemaPath` | no (pointer only) | Config validation against JSON Schema (R15.2). An optional check of the spec against the OAS meta-schema is possible |
| [`json_schema_builder`](https://pub.dev/packages/json_schema_builder) (flutter/genui) | 0.1.7 (2026-09-01), ~125k downloads/30d | Building and validating 2020-12, errors with `path` | no | An alternative from labs.flutter.dev, still 0.x |
| [`rfc_6901`](https://pub.dev/packages/rfc_6901) (f3ath) | 0.2.1 (2025-10-17) | JSON Pointer: reading and writing | — | Used by dynamite. [`json_pointer`](https://pub.dev/packages/json_pointer) (2019) is dead |
| [`rfc_6902`](https://pub.dev/packages/rfc_6902) (f3ath) | 0.3.1 (2025-11-04) | JSON Patch: add, remove, replace, move, copy, test | — | R3.3. [`json_patch`](https://pub.dev/packages/json_patch) (2021) is outdated |
| [`json_path`](https://pub.dev/packages/json_path) (f3ath) | 0.9.0 (2025-12-11) | JSONPath per **RFC 9535**, run through the Compliance Test Suite | — | **Needed for Overlay 1.0**: `target` per the spec is "RFC9535 JSONPath" (`specs/overlay-1.0.0.md`). No ready Overlay implementation for Dart was found on pub.dev |
| [`code_builder`](https://pub.dev/packages/code_builder) / [`dart_style`](https://pub.dev/packages/dart_style) | 4.12.0 / 3.1.13 | Code emission and formatting | — | They are used by degenerate, dynamite, dart_openapi_generator |
| OpenAPI models: [`openapi_spec`](https://pub.dev/packages/openapi_spec) 0.15.0, [`openapi_spec_plus`](https://pub.dev/packages/openapi_spec_plus) 0.6.0, [`conduit_open_api`](https://pub.dev/packages/conduit_open_api) 7.0.0, [`open_api_forked`](https://pub.dev/packages/open_api_forked) (2022), [`open_api_specification`](https://pub.dev/packages/open_api_specification) 4.1.0, [`openapi_dart`](https://pub.dev/packages/openapi_dart) 0.2.0 | — | Typed spec models | **none of them** | `openapi_spec_plus`: separate freezed models for v20, v30 and v31 (no 3.2), `x-*` stored in `extensions`, `$ref` kept as a raw string with no resolver. `tonik_parse`/`tonik_core` 0.10.0 is described in the tonik document |

### 4.2 Experiments

**(a) `package:yaml` on JSON** (`bin/exp.dart`). Input — the OpenAI spec from `ai_clients_dart`, 4.77 MB JSON, Dart 3.13.1 JIT on macOS arm64:

- `jsonDecode` — **25 ms**, `loadYamlNode` — **225 ms**. Spans for JSON exist: the key `"/agents"` was found at `line 89375, column 5`, and `span.message(...)` prints a snippet with underlining.
- **Duplicate keys**: `loadYamlNode('{"a":1,"a":2}')` throws `YamlException: Duplicate mapping key` with a position, while `jsonDecode` silently takes the last value. For a tolerant tool this is a separate normalizer rule: a diagnostic plus "last one wins".

**(b) YAML 1.2 coercions** (`bin/yaml_gotchas.dart`):

| What is in YAML | What `package:yaml` returns |
|---|---|
| `responses: 200:` | **`int` 200** as the key (`default` stays a `String`) |
| `info.version: 1.0` | **`double` 1.0** |
| enum `0x1F` | **`int` 31** |
| enum `1e3` | **`double` 1000.0** |
| `yes`, `no`, `on`, `off` | `String` (YAML 1.2 semantics; tools on YAML 1.1 will see bool) |
| `2024-01-01` | `String` |

Each row of the table is a candidate for a named normalizer rule with a warning. The original token can be recovered from `YamlScalar.span.text`.

**(c) Typed models on defects** (`bin/defects.dart`):

| Defect | `openapi_spec_plus` 0.6.0 | `openapi_spec` 0.15.0 |
|---|---|---|
| `required: true` on a property (NestJS style) | **throws** `_TypeError: bool is not a subtype of List<dynamic>?` | OK (silently) |
| array without `items` | OK | **throws** `Failed to parse Schema: {type: array}` |
| `type: [string, null]` + `nullable: true` | OK | **throws** |
| `info.version: 1.0` (number) | **throws** `_TypeError` | **throws** |
| empty `$ref`, duplicates in enum | OK (silently) | OK (silently) |

No error contains either a JSON pointer or a line in the file.

**Conclusion for decision 5.** There is no ready Dart package with an OpenAPI model, source positions and tolerance to defects. The proposed architecture:

1. Raw layer: `loadYamlNode` for YAML and JSON + a JSON-pointer index → `SourceSpan`, following the `SourceMap` sample from dart_openapi_generator.
2. The normalizer (R2.1) works on the raw tree: type fixes, duplicates, required: bool, YAML coercions. Each firing produces a diagnostic with a pointer and span.
3. Only after normalization is the tree mapped into our own typed model or IR, isolated from generation.
4. `$ref` (R1.2) — our own resolver on `rfc_6901`. JSON Patch — `rfc_6902`, Overlay — `json_path`. The config is checked via `json_schema` + `checked_yaml`, the baseline is edited via `yaml_edit`.

---

## 5. SSE packages for Dart (R12)

### 5.1 Overview

| Package | Version (date) | ♥ / dl/30d | Transport | User's Dio? | Web | Reconnect / `Last-Event-ID` / `retry` | Score (17 WHATWG tests) | Notes |
|---|---|---|---|---|---|---|---|---|
| [`sse_parser`](https://pub.dev/packages/sse_parser) | 0.1.0 (2026-05-31) | 0 / 562 | **parser only**, 0 dependencies | yes: you feed it bytes from `ResponseBody.stream` | yes (pure Dart) | — / keeps lastId / `onRetry` callback | **17/17** | Push API (`feed`) and Stream API. `close(dispatchPending: true)` enables a lenient mode. MIT. Low popularity, 1 release |
| [`launchdarkly_event_source_client`](https://pub.dev/packages/launchdarkly_event_source_client) | 3.0.0 (2026-06-25) | 3 / ~102k | `package:http` | no | via the browser `EventSource`: **method, body and headers are dropped** ("dropping unsupported configuration options") | backoff with jitter / **yes** (`Last-Event-ID`) / ignores the `retry` field | **17/17** | Parser in `src/` (not public API), run through LaunchDarkly's contract tests. Intended for LaunchDarkly's own SDKs |
| [`simple_sse`](https://pub.dev/packages/simple_sse) + [`simple_sse_dio`](https://pub.dev/packages/simple_sse_dio) | 2.0.0 / 1.0.1 (2025-11-11) | 1 / 178 (dio) | Dio or http | **yes** (`DioSseClient([Dio? dio])`) | as in Dio (see below) | no / keeps id / stores it in the event | 16/17 | Trims **all** trailing \n in data. **Bug:** the Dio client does `.map(utf8.decode)` on each chunk, so a multi-byte character at a chunk boundary will throw `FormatException` ([dio_sse_client.dart](https://github.com/andyhorn/sse_client/blob/main/packages/simple_sse_dio/lib/src/dio_sse_client.dart)) |
| [`eventflux`](https://pub.dev/packages/eventflux) | 3.0.2 (2026-09-25) | **97 / ~20k** | `package:http`, on web `fetch_client` | no (adapter on `http.BaseRequest`) | yes (fetch) | yes / yes / yes | not run: depends on **Flutter** | Dispatches an event on each empty line, even without data. Removes U+2028/2029 from lines. Pure Dart not supported |
| [`flutter_client_sse`](https://pub.dev/packages/flutter_client_sse) | 2.0.3 (2024-08-28) | **110 / ~44k** | `package:http`, **static global client** | no | — | fixed 5 s / no / no | not run (Flutter) | `substring(5)` leaves a leading space in data, does not trim the trailing \n. An unknown field → print and **reconnect**. The most popular and the worst in quality |
| [`sse_channel`](https://pub.dev/packages/sse_channel) | 0.2.2 (2025-10-07) | 16 / ~99k | `http.Client` (you can pass your own) | no | yes | yes / yes / yes | — | A `StreamChannel` wrapper, tailored to the `package:sse` protocol |
| [`sse`](https://pub.dev/packages/sse) (dart-lang) | 4.2.0 (2026-04-08) | 93 / 8.5M | its own bidirectional SSE+POST protocol | — | — | — | — | The docs state: "not intended to be a general purpose SSE package". Used by DWDS |
| [`eventsource`](https://pub.dev/packages/eventsource) | 0.4.0 (2022-03-23) | 30 / 843 | http | no | — | yes | — | Dead |
| `degenerate_runtime.parseSseStream` | 0.5.0 | — | parser | yes | yes | no / yes / ignores | 15/17 | Accepts an `id` with NUL. Dispatches an incomplete event at the end of the stream |
| `openai_dart` `SseParser.parseRaw` (hand-written) | 11.0.0 | — | parser | — | — | — | **9/17** | `trim()` of values, `id` is not kept between events, `data` with no value is ignored. A typical example of a "home-rolled" parser |

### 5.2 WHATWG test

The script `bin/sse_conf.dart` compares the parsers on 17 cases per the [WHATWG algorithm](https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation):

- multi-line `data`;
- trimming of only one space after the colon; preserving trailing spaces;
- comments `:`;
- lines ending in CR only; CRLF split between chunks;
- UTF-8 character split between chunks;
- BOM;
- `data` with no value → `""`;
- `event` without `data` is not dispatched;
- `id` is kept between events; `id` with NUL is ignored;
- an unknown field is ignored;
- `event` type;
- an incomplete event at the end of the stream is discarded;
- `[DONE]` passes through as ordinary data;
- `data:\ndata:` → `"\n"`.

Summary: `sse_parser` 17, `launchdarkly` 17, `simple_sse` 16, `degenerate_runtime` 15, hand-written `openai_dart` parser 9.

Incidental observation: the BOM is handled correctly in all of them, even in parsers with no explicit BOM code. It seems the `utf8.decoder` in the test pipeline strips the BOM at the start by itself.

### 5.3 Dio and web — an important gap

- `dio_web_adapter` 2.2.2 (2026-09-04) is still built on `XMLHttpRequest` with `responseType = 'arraybuffer'` ([adapter_impl.dart](https://github.com/cfug/dio/blob/main/plugins/web_adapter/lib/src/adapter_impl.dart)). Therefore `ResponseType.stream` on web gives the response entirely after completion ([dio#2268](https://github.com/cfug/dio/issues/2268), [#1795](https://github.com/cfug/dio/issues/1795)). Issues "ServerSendEvent support for Flutter Web" ([#1859](https://github.com/cfug/dio/issues/1859)) and "Use modern Fetch API" ([#1740](https://github.com/cfug/dio/issues/1740)) are open.
- The workaround the maintainers themselves suggest: `Dio()..httpClientAdapter = ConversionLayerAdapter(FetchClient(...))` from [`dio_compatibility_layer`](https://pub.dev/packages/dio_compatibility_layer) 0.1.1 and [`fetch_client`](https://pub.dev/packages/fetch_client) 1.2.1. `fetch_client` supports a streaming response.
- Consequence for R12.4 "transport via the user's Dio": on mobile and desktop `ResponseType.stream` is enough, while on Flutter Web a documented requirement on the Dio adapter is needed. Otherwise the stream "works", but without incrementality.

### 5.4 Gaps

**No single package combines all of this:**

1. full WHATWG conformance;
2. working on top of the user's Dio, so that interceptors, auth and `onError` fire;
3. a reconnection policy with `Last-Event-ID` and `retry` that can be turned off;
4. pure Dart without Flutter;
5. streaming on web.

**Recommendation.** The runtime package needs its own small parser (~150–250 lines). One can take [`sse_parser`](https://pub.dev/packages/sse_parser) (MIT) or LaunchDarkly's parser (Apache-2.0) as a reference and run our 17 cases together with LaunchDarkly's SSE contract tests. Reconnection is our own loop over `dio.request(..., responseType: stream)`.

---

## 6. Conclusions

1. **The niche is free.** The Dart generator market in 2026 is fragmented: many new but small projects (degenerate, florval, dart_openapi_generator, openapi_flutter_gen, flap, koi_swagger_parser, forks of swagger_parser). **No one** offers a product layer for imperfect specs: named normalization rules with codes, an override file with element addressing, baseline/ratchet and a `check` mode. The closest precedents are Kiota's validation rules (R2.1, R2.2), and famedly's rules and patches (R3). Positioning per R0.2 is competitively justified.
2. **What to take from degenerate:**
   - `Omittable` with the `nullable|all|off` modes → R7.2;
   - enum as a `final class` with the raw value → R8.1;
   - `$Unknown` in a union → R9.1;
   - sealed unions of responses by status and media type → R10.6, R11.3;
   - SSE with `itemSchema` → R12.2;
   - tree-shaking by tag and path → R4.2;
   - the snapshot corpus of public specs → R15.3;
   - the escaping discipline for strings from the spec (`SpecString`).

   **What not to take:** `validateStatus: (_) => true` and custom interceptors in place of Dio-native ones.
3. **What to take from florval for R10.2:** do not touch `validateStatus`, but catch `DioException` with a `response` and map it to a typed variant or exception. Then Dio interceptors receive `onError`, and the user gets a typed result. The user wires in Dio, the generator configures nothing (R10.1).
4. **What to take from Kiota:**
   - a catalog of rules with names and --disable-validation-rules;
   - glob filters with `#METHOD` and clear include/exclude semantics;
   - a lock file with a hash of the spec and parameters (R13.1, R14.1);
   - the error-mapping order "code → range → default → base" (R11.1);
   - `x-ms-primary-error-message` as an idea for the `x-` registry (R15.5).

   Kiota Dart by itself is not a competitor: it is in preview, supports only `http`, and its models are mutable.
5. **Large SDKs** are either written by hand (davidmigloz, Supabase) or built with an in-house generator (Google, AWS, Appwrite, Matrix, Nextcloud). Those who generate from OpenAPI patch either the spec or the output. The main complaint of serious authors is dependencies and build_runner, not generation as such. Hence the argument for open decisions 1 and 2: **ready code without a mandatory build_runner on the consumer side** and a minimal runtime (R13.3). json_serializable is justified only because the brief requires it; we should plan for the fact that part of the audience will want output without build_runner.
6. **Sealed and semver (R14.2, open decision 7).** The experience of openai_dart (11 major versions in 7 months) shows that if open sets (event and response unions) are generated as `sealed`, every addition to the spec becomes a breaking change for the consumer. Options:
   - generate open hierarchies not as `sealed` but as `abstract`/`base`, so that the compiler requires a default branch;
   - or provide an `exhaustive: true|false` flag at the config or override level;
   - and in any case reflect this in the breaking-changes report (R14.1).
7. **Parser (open decision 5).** Build our own raw layer over `package:yaml`: spans for both YAML and JSON, ~0.2 s for 4.7 MB. Normalize on the raw tree, and only then build a typed model. Ready models such as openapi_spec or openapi_spec_plus throw exceptions without a position even on typical NestJS defects. Tools alongside: `rfc_6901`, `rfc_6902`, `json_path` (Overlay), `json_schema` + `checked_yaml` (config), `source_span` (output), `yaml_edit` (baseline). YAML coercions (integer status keys, `version: 1.0`, `0x…` in an enum) and duplicate keys should be made into separate named normalizer rules.
8. **SSE (R12).** Write our own parser in the runtime and test it on the WHATWG cases and LaunchDarkly's contract tests. Transport — `ResponseType.stream` on the user's Dio; reconnection with `Last-Event-ID` and `retry`, which can be turned off. For Flutter Web, document the requirement `ConversionLayerAdapter(FetchClient)`, because `dio_web_adapter` on XHR does not stream.
9. **Licenses.** Do not copy the code of openapi_flutter_gen (AGPL or commercial) and the dynamite generator (AGPL). degenerate (MIT), Kiota (MIT), sse_parser (MIT) and LaunchDarkly SSE (Apache-2.0) may be used as references with attribution.

---

## 7. Sources

**Generators**
- degenerate: https://pub.dev/packages/degenerate · https://github.com/blopker/degenerate · https://github.com/blopker/degenerate/blob/main/TODO.md · https://github.com/blopker/degenerate/blob/main/packages/degenerate_dio/lib/src/dio_api_client.dart · https://github.com/blopker/degenerate/blob/main/packages/degenerate_runtime/lib/src/sse.dart · https://github.com/blopker/degenerate/issues/15 · https://github.com/blopker/degenerate/issues/18 · https://github.com/blopker/degenerate/blob/main/Makefile
- Kiota: https://github.com/microsoft/kiota · https://github.com/microsoft/kiota-dart · https://pub.dev/packages/microsoft_kiota_abstractions · https://learn.microsoft.com/en-us/openapi/kiota/using · https://learn.microsoft.com/en-us/openapi/kiota/errors · https://learn.microsoft.com/en-us/openapi/kiota/quickstarts/dart · https://github.com/microsoft/kiota/issues/7807 · https://github.com/microsoft/kiota/issues/7997 · https://pub.dev/packages/stripe_api_client
- dynamite: https://pub.dev/packages/dynamite · https://github.com/provokateurin/dynamite · https://github.com/nextcloud/neon/pull/3205
- openapi_spec: https://pub.dev/packages/openapi_spec · https://github.com/tazatechnology/openapi_spec · https://github.com/tazatechnology/openapi_spec/issues/84 · https://github.com/tazatechnology/openapi_spec/issues/85 · https://github.com/tazatechnology/openapi_spec/issues/74 · https://github.com/davidmigloz/openapi_spec
- hpoul: https://pub.dev/packages/openapi_code_builder · https://pub.dev/packages/openapi_base · https://github.com/hpoul/openapi_dart
- florval: https://pub.dev/packages/florval · https://github.com/encer-jp/florval · https://github.com/encer-jp/florval/blob/main/lib/src/generator/client_generator.dart
- dart_openapi_generator: https://pub.dev/packages/dart_openapi_generator · https://github.com/AngeloAvv/dart_openapi_generator · https://github.com/AngeloAvv/dart_openapi_generator/blob/main/lib/src/parser/source_map.dart
- openapi_flutter_gen: https://pub.dev/packages/openapi_flutter_gen · https://github.com/PurpleSoftSrl/openapi_flutter_gen
- flap: https://pub.dev/packages/flap · https://github.com/miracle101000/flap-dart
- koi_swagger_parser: https://pub.dev/packages/koi_swagger_parser · https://github.com/mrkoi-is/koi_swagger_parser
- openapi_retrofit_generator / openapi_sdk_gen: https://pub.dev/packages/openapi_retrofit_generator · https://github.com/westito/openapi_retrofit_generator · https://pub.dev/packages/openapi_sdk_gen · https://github.com/fluxerapp/openapi_sdk_gen_dart
- open_api_client_generator: https://pub.dev/packages/open_api_client_generator · https://github.com/BreX900/mek-packages
- openapi_freezed_dio_builder: https://pub.dev/packages/openapi_freezed_dio_builder
- openapi_to_retrofit: https://pub.dev/packages/openapi_to_retrofit
- openapi_dart_common / dart-openapi-maven: https://pub.dev/packages/openapi_dart_common · https://github.com/dart-ogurets/dart-openapi-maven
- openapi_enum_patch: https://pub.dev/packages/openapi_enum_patch
- famedly: https://github.com/famedly/dart_openapi_codegen · https://github.com/famedly/dart_openapi_codegen/blob/main/rules/matrix.yaml
- @sdk-it/dart: https://www.npmjs.com/package/@sdk-it/dart · https://github.com/JanuaryLabs/sdk-it

**Large SDKs**
- https://github.com/davidmigloz/ai_clients_dart · https://github.com/davidmigloz/ai_clients_dart/blob/main/docs/spec-core.md · https://github.com/davidmigloz/ai_clients_dart/blob/main/docs/new_dart_api_client.md · https://github.com/davidmigloz/ai_clients_dart/blob/main/.agents/shared/api-toolkit/README.md · https://github.com/davidmigloz/ai_clients_dart/blob/main/packages/openai_dart/MIGRATION.md · https://github.com/davidmigloz/ai_clients_dart/blob/main/packages/openai_dart/CHANGELOG.md · https://github.com/davidmigloz/langchain_dart/tree/main/packages/openai_dart · https://github.com/davidmigloz/langchain_dart/blob/main/pubspec.yaml · https://pub.dev/packages/openai_dart/versions · https://pub.dev/packages/anthropic_sdk_dart · https://pub.dev/packages/googleai_dart
- https://github.com/google/googleapis.dart · https://github.com/agilord/aws_client · https://github.com/appwrite/sdk-generator · https://github.com/supabase/supabase-flutter · https://github.com/supabase/supabase-flutter/tree/main/packages/supabase_typegen · https://github.com/abraham/mastodon_dart/tree/main/packages/mastodon_generator · https://github.com/celest-dev/dart-api-clients/tree/main/clients/stripe · https://pub.dev/packages/pinecone
- Vendors: https://buildwithfern.com/learn/sdks/introduction/overview · https://www.stainless.com/docs/ · https://www.speakeasy.com/docs/sdks/create-client-sdks

**Building blocks**
- https://pub.dev/packages/yaml · https://pub.dev/packages/source_span · https://pub.dev/packages/yaml_edit · https://pub.dev/packages/checked_yaml · https://pub.dev/packages/json_schema · https://github.com/workiva/json_schema · https://pub.dev/packages/json_schema_builder · https://pub.dev/packages/rfc_6901 · https://pub.dev/packages/json_pointer · https://pub.dev/packages/rfc_6902 · https://pub.dev/packages/json_patch · https://pub.dev/packages/json_path · https://github.com/f3ath/jessie · https://pub.dev/packages/code_builder · https://pub.dev/packages/dart_style
- https://pub.dev/packages/openapi_spec_plus · https://pub.dev/packages/conduit_open_api · https://pub.dev/packages/open_api_forked · https://pub.dev/packages/open_api_specification · https://pub.dev/packages/openapi_dart · https://pub.dev/packages/tonik_parse · https://pub.dev/packages/tonik_core
- OpenAPI Overlay 1.0.0: https://spec.openapis.org/overlay/v1.0.0.html (local copy `scratchpad/specs/overlay-1.0.0.md`)

**SSE**
- WHATWG: https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation
- https://pub.dev/packages/sse_parser · https://github.com/guillaumegay13/sse_parser
- https://pub.dev/packages/launchdarkly_event_source_client · https://github.com/launchdarkly/flutter-client-sdk/tree/main/packages/event_source_client
- https://pub.dev/packages/simple_sse · https://pub.dev/packages/simple_sse_dio · https://github.com/andyhorn/sse_client
- https://pub.dev/packages/eventflux · https://github.com/Imgkl/EventFlux
- https://pub.dev/packages/flutter_client_sse · https://github.com/pratikbaid3/flutter_client_sse
- https://pub.dev/packages/sse_channel · https://pub.dev/packages/sse · https://pub.dev/packages/eventsource
- https://github.com/davidmigloz/ai_clients_dart/blob/main/packages/openai_dart/lib/src/utils/streaming_parser.dart
- Dio web: https://github.com/cfug/dio/issues/2268 · https://github.com/cfug/dio/issues/1795 · https://github.com/cfug/dio/issues/1859 · https://github.com/cfug/dio/issues/1740 · https://github.com/cfug/dio/pull/2376 · https://github.com/cfug/dio/blob/main/plugins/web_adapter/lib/src/adapter_impl.dart · https://pub.dev/packages/dio_compatibility_layer · https://pub.dev/packages/fetch_client

**Own experiments** (repeatable): `scratchpad/longtail-exp/bin/exp.dart` (yaml on JSON, spans, duplicates), `yaml_gotchas.dart` (coercions), `defects.dart` (typed models on defects), `sse_conf.dart` (17 WHATWG cases). Dart 3.13.1; package versions are pinned in `scratchpad/longtail-exp/pubspec.lock`.
