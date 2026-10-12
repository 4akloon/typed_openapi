# typed_openapi: competitor and decision research

Date: **2026-10-11**. Compiled from 7 parallel studies. The primary sources (code at specific commits, issues, specifications) and the details are in the files `01…07` of this folder. Requirements: [../requirements.md](../requirements.md).

Legend: ✅ present / done · ⚠️ partial · ❌ absent or violated · ? not checked · — not applicable.

---

## 0. Briefly

1. **The niche is open.** Among ~25 Dart generators, none has a product layer for imperfect specifications: named normalization rules with diagnostic codes, an override file with addressing, a baseline. Those who generate large SDKs from OpenAPI patch it by hand: Matrix keeps 16 `.patch` files against the specification, Mastodon keeps `hacks.dart` on top of the generated code. This is direct confirmation of R0.2.
2. **The market is fragmented.**
   - Download leaders: swagger_parser (~66k/month, released by one person) and swagger_dart_code_generator (~63k/month, effectively abandoned).
   - The Dart generators of OpenAPI Generator have no owner.
   - 2026 brought a wave of small new generators. The closest in features is **degenerate**, but it violates R10.2 and has neither diagnostics nor overrides.
3. **Your claims from the technical brief were confirmed**, with clarifications (§4).
4. **Nobody combines:** R8.1 together with R8.2 (keep the raw enum value and forbid sending it); R10.2 together with typed errors (only florval does it); SSE on top of the user's client.
5. **json_serializable covers the models, R6.1, R6.4 and R7** (through your `explicitJsonNullWhenNonNullField`). It does not cover: the raw enum value, union, the JSON path for errors. **Decided:** the generator writes the code itself, compatible with the json_serializable contract (§7.2).
6. **The parser has to be our own**, on `package:yaml`, with JSON Pointer and `SourceSpan` on every node. `tonik_parse`/`tonik_core` are not suitable for this (§7.5).
7. **A conflict was found in the requirements: R14.2 against `sealed` and an exhaustive `switch`.** A new variant or value breaks an exhaustive `switch` in the consumer's code. Because of this, `openai_dart` released 11 major versions in 7 months (§7.8).

### Decisions made (2026-10-11)

| Question | Decision |
|---|---|
| Name | `typed_openapi` |
| Output type (1) | Ready-made code without a mandatory build_runner |
| Serialization (2) | Own emission, **compatible with the contract** of json_serializable (`fromJson`/`toJson`), without a dependency on it |
| HTTP layer (3) | In v1 only Dio through a narrow surface; decide the `ApiTransport` abstraction before 1.0 |
| Error model (4) | **No exceptions:** every method returns `ApiResult<T, E>` (§7.4) |
| Parser (5) | Our own; JSON and YAML are read through `package:yaml` with spans (§7.5) |
| Extensibility (6) | Config + overrides + typed hooks over the IR, no templates |
| Representation (7) | Tentatively: `Patch<T>?` for three states; enum as `sealed X` + `XKnown` / `XUnknown` |
| Several clients (R1.3) | One config with a `clients` section and shared `defaults`; each client has its own output, overrides, baseline and namespace; one shared runtime (details in [../requirements.md](../requirements.md)) |
| Grouping (R5.3) | A class per tag with the suffix `Api` (the pattern is configurable), a root client class with group fields. Ordinary classes without interfaces and without the `final`/`base`/`interface` modifiers, mocked through `implements` (R10.7) |
| Operation errors (R11.4) | One schema for all errors → the error type is that schema; sealed by status only when the schemas differ; bodies without a description — by `errors.default_schema` |
| Envelopes (R6.4) | `{data: T}` is unwrapped by default, the method returns `T` |
| Names (R5.1) | As in the schema: `operationId` → lowerCamelCase, schema names unchanged (`Dto` stays); transformations only explicit (config, preset) |
| Numbers (R6.2) | `integer` → `int`; `number` + `float`/`double` → `double`; `number` without a format → `num`; the mapping and overrides are configurable |
| Custom types (R6.8) | `types.formats` / `types.schemas` / override: `{type, import, converter?}`; without a converter — the `fromJson`/`toJson` contract, with a converter — a class with `fromJson`/`toJson`; no new dependencies |
| Exhaustiveness (8) | `exhaustive` by default for enums, unions, SSE events and operation errors; turned off at the schema level in overrides (`exhaustive: false`); the R14.1 report marks new values as source-breaking (§7.8) |

---

## 1. Name and packages

| Package | Role |
|---|---|
| `typed_openapi` | The generator's CLI + programmatic API. Distribute **as an isolated tool** (`dart install typed_openapi` / `dart run typed_openapi@x.y.z`), not as a `dev_dependency`, so that its `analyzer`/`dart_style` do not conflict with freezed, riverpod_generator and the like (analyzer released 5 major versions between January and June 2026) |
| `typed_openapi_runtime` | A small runtime: errors, `Result`, `Patch<T>`, JSON helpers with a path, parameter style codecs, the SSE parser. In v1 it depends only on `dio` + `meta`; logic not tied to the transport is kept separate from Dio (see §7.3) |
| `typed_openapi_dio` / `typed_openapi_http` | Separate adapters — **only if** an HTTP abstraction appears later (decision before 1.0, §7.3) |

The remaining names:
- **Files:** `typed_openapi.yaml` (config), `typed_openapi.overrides.yaml` (overrides), `typed_openapi.baseline.yaml` (baseline), `typed_openapi.lock` (see §5, R13/R14).
- **Diagnostic codes:** a prefix (for example `TOA`) and ranges by area, as proposed in [06 §C.0](06-spec-versions-and-defects.md):

  | Range | Area |
  |---|---|
  | 0xx | document and dialect |
  | 1xx | `$ref` |
  | 2xx | schemas |
  | 3xx | enum |
  | 4xx | polymorphism |
  | 5xx | operations and naming |
  | 6xx | media types and streams |
  | 7xx | output stability |
  | 8xx | overrides |

  Alongside the numeric code, it is worth adding a human-readable name in the Stainless style (`Schema/ArrayMissingItems`).
- **Custom `x-` extensions:** in one namespace, for example `x-typed-*`.

---

## 2. Landscape

### 2.1 Who is on the market

| Tool | Version (date) | Popularity | Status | Output / HTTP |
|---|---|---|---|---|
| OpenAPI Generator `dart-dio` / `dart` | 7.26.0 (2026-10-06) | — | Dart generators without an owner, 134 open issues with "dart" in the title, Java 11+ required | mustache → built_value / json_serializable + build_runner; Dio / http |
| `openapi_generator` (wrapper on pub) | 7.0.0 (2026-05) | — | `analyzer <9`: does not install with modern Flutter (gibahjoe#201) | — |
| swagger_parser | 1.45.0 (2026-09-25) | 124♥, ~65.6k/month | active, but released by one person; it is being forked (openapi_retrofit_generator → openapi_sdk_gen) | retrofit + json_serializable / freezed / dart_mappable, build_runner |
| swagger_dart_code_generator | 4.1.1 (2025-12-11) | 331♥, ~62.6k/month | effectively abandoned (#796 unanswered, 13 PRs pending) | chopper + json_serializable, build_runner |
| tonik | 0.10.0 (2026-09-07) | 8♥, ~2k/month | very active, 0.x, PR with SSE open | ready-made code; Dio or http; the generated package requires Dart ≥3.13 |
| swagger_to_dart | 6.0.0 (2026-10-06) | 26♥, ~2k/month | active in bursts, two major releases within a week | freezed + json_serializable + retrofit |
| space_gen | 1.4.0 (2026-07-19) | 56★, ~39k/month (probably Shorebird CI) | idle since July; the best architecture | ready-made code, only `package:http` |
| **degenerate** | 0.5.0 (2026-09-10) | 5♥, ~0.5k/month | active, one author | ready-made code, own `ApiClient` + dio/http adapters |
| florval | 0.4.1 (2026-07-10) | 4♥ | active | freezed + the user's Dio (through Riverpod) |
| Kiota (Dart) | abstractions 0.3.0 | — | preview | .NET CLI, `package:http`, mutable models |

About 10 more small ones (dart_openapi_generator, flap, koi_swagger_parser, openapi_flutter_gen under AGPL, and others) are analysed in [04](04-dart-long-tail.md).

**How large Dart SDKs are generated.**
- **By hand:** davidmigloz (`openai_dart`, `anthropic_sdk_dart`, `googleai_dart`) moved from openapi_spec+freezed to hand-written code with dependencies only on `http`, `logging`, `meta`. Supabase also writes by hand.
- **With an in-house generator:** Google, AWS, Appwrite, Matrix, Nextcloud.
- **Commercial generators** (Stainless, Speakeasy, Fern) do **not** support Dart.
- **What this means:** serious authors give up not on generation but on build_runner, freezed and unnecessary runtime dependencies.

### 2.2 Matrix by key requirements

| | R2 diagn. | R3 override | R4.2 tree-shake | R7 three states | R8.1 raw enum | R8.2 | R9.1 unknown | R10.2 onError | R11 typed errors | R12 SSE | build_runner |
|---|---|---|---|---|---|---|---|---|---|---|---|
| OAG dart-dio (json_ser.) | ⚠️ silent | ⚠️ global mappings | ❌ | ⚠️ only PATCH via `$ref` | ❌ | ❌ | ❌ no polymorphism | ✅ | ❌ | ❌ | yes |
| swagger_parser | ❌ | ⚠️ regex | ⚠️ | ❌ | ❌ | ❌ | ✅ (not for freezed) | ✅ | ❌ | ❌ | yes |
| swagger_dart_code_gen. | ❌ | ⚠️ | ❌ | ❌ | ❌ | ⚠️ | ❌ `dynamic` | — chopper | ❌ | ❌ | yes |
| tonik | ❌ | ⚠️ names | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ PR | no |
| swagger_to_dart | ❌ | ⚠️ names | ❌ | ❌ | ❌ | ❌ | ✅ opt-in | ✅ | ❌ | ❌ | yes |
| space_gen | ⚠️ pointer without codes | ❌ | ❌ | ❌ | ❌ throw | — | ❌ | — http | ⚠️ | ❌ | no |
| degenerate | ❌ plain strings | ❌ | ✅ | ✅ | ✅ | ? | ✅ | ❌ | ✅ | ✅ incomplete WHATWG | no |
| florval | ❌ | ❌ | ? | ✅ | ❌ | ? | ? | ✅ | ✅ | ❌ | yes |
| Kiota (Dart) | ⚠️ warnings only | ❌ | ? | ? | ❌ throw | — | ⚠️ | — http | ✅ | ? | no |
| **typed_openapi (target)** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | no/optional |

---

## 3. Competitor problems: what not to repeat

Each item contains the problem (where, and the evidence) and a lesson for typed_openapi.

**A. Silent guesses (R2.5)**
- **OAG** [01 P31, P13]:
  - an exception in the normalizer is swallowed, and generation continues;
  - parts of `allOf` are dropped with a DEBUG log;
  - a self-reference becomes `any`, a map without a value type becomes `String`;
  - if there is no 2xx, the success type becomes `default`.
- **Cookie parameters silently disappear** in OAG, swagger_parser and SDCG, although OAG's feature table claims `Cookie ✓`.
- **Trying variants with try/catch:** swagger_parser for `oneOf` without a discriminator, tonik for an unknown discriminator.
- **Stubs and degradation:** space_gen generates `throw UnimplementedError` in `fromJson`, flap degrades types to `dynamic`.
- **→ Lesson:** every such decision must become a diagnostic with a code, a pointer and a ready override snippet.

**B. Parsing through casts, crashing on the first defect (R1.2, R2)**
- **Casts before checks:** swagger_parser on path-level `parameters` (#374, the cast comes before the key check, still not fixed). tonik crashes with `TypeError` on `required: true` and ends with a generic "Unexpected error". `openapi_spec` and `openapi_spec_plus` crash on typical NestJS defects without a position.
- **`$ref` as the "last path segment"** (SP, SDCG): there are no external files, and a cycle gives a StackOverflow (SP #423).
- **→ Lesson:** a lossless DTO with a pointer; diagnostics are collected, not thrown; an operation with a defect is skipped with a diagnostic, rather than failing the whole generation.

**C. The required × nullable matrix is the main source of bugs (R6.1)**
- **Mass bugs:**
  - swagger_parser: #303, #358, #460, #443, #307;
  - OAG: #23866, #21565, #21510, #18647;
  - SDCG: #182, 28 comments.
- **Collapsing to "optional ⇒ nullable"** in SP and SDCG.
- **NestJS, SP #460:** a single `allOf` without `required` makes all fields required.
- **→ Lesson:** a separate module with an explicit table (in space_gen it is 8 rows, ogen documents the decoder's matrix), a golden test for each cell, separately for the request, the response and PATCH.

**D. Unknown enum values (R8)**
- **OAG:** the sentinel is a real wire value (`'unknown_default_open_api'` / `11184809`), so it can be sent.
- **swagger_parser:** `$unknown(null)` loses the raw value, and json_serializable sends `"$unknown"` to the server.
- **SDCG:** in nullable fields an unknown value becomes `null`.
- **tonik:** the `generateUnknownCase` option is global, the raw value is lost, and without it decoding of the whole response fails.
- **space_gen and Kiota:** throw an exception (in Kiota, deliberately).
- **→ Lesson:** a separate type for an unknown value with the raw value, and it must not be accepted in requests (§7.7).

**E. Interfering with the user's transport (R10.1, R10.2)**
- **OAG:** without explicit `interceptors:` it adds 4 auth interceptors to the passed `Dio`, without Dio it sets hard timeouts of 5/3 s.
- **tonik:** `validateStatus: (_) => true`, the body goes to the interceptors as bytes, and `baseUrl` is overwritten even in the user's Dio.
- **degenerate:** the same `validateStatus: (_) => true` in the Dio adapter.
- **False HTTP statuses:** space_gen turns a transport failure into `ApiException(400)`, OAG `dart` turns a decoding error into `ApiException(500)`.
- **→ Lesson:** do not touch the client; an HTTP error takes its native path (for Dio, `onError`) and is typed only after it, as in florval.

**F. Overwriting data with nulls (R7.3)**
- **swagger_to_dart:** sends `null` for all unset optional fields, plus default values.
- **tonik and space_gen:** send `null` for optional + nullable (exactly the kind of field FastAPI produces with `Optional[X] = None`).
- **→ Lesson:** a field with a single state does not get a key when it has no value; three states only under the R7.2 rule.

**G. Neither typed errors nor several 2xx (R10.6, R11)**
- **OAG, SP, SDCG:** have neither.
- **retrofit:** this is an architectural ceiling — one `T` per method; the issue about typed error bodies (#168) has been open since 2020.
- **→ Lesson:** do not generate on top of retrofit; methods call the transport directly.

**H. Naming (R5)**
- **Unstable inline names:** with HTTP codes (`GetPets200Response`) and suffixes `_1`, `_2`. OAG changed the naming scheme without a fallback (6.0) and the deduplication logic (7.23).
- **Renaming with a regex over the raw text** of the spec: swagger_parser this way turned **API paths** into PascalCase.
- **Collisions:** with `dart:core`, with `Options` from Dio, with the members of `Enum` (`name`, `index`, `values`).
- **The keys of `inlineSchemaNameMappings` in OAG are generated names**, so they "drift".
- **→ Lesson:** a global naming pass over `Map<JsonPointer, String>` (as in space_gen) and import prefixes (as `DartEmitter.scoped()` in tonik). The override key is the location in the spec, not the generated name.

**I. Output changes in minor releases (R15.4)**
- **OAG:**
  - 7.15 — `copy_with_extension` was added by default, builds broke;
  - 7.23 — deduplication was changed;
  - 7.25 — multi-line descriptions produced invalid code.
- **swagger_parser 1.42:** the binary response became `Stream<String>`, and it cannot be turned off.
- **space_gen:** during generation it runs `dart pub get` and `dart fix`, so the result depends on the network and the SDK version.
- **→ Lesson:** a golden diff in CI over a corpus of specs; any change of output is a major change (in dynamite this is a written policy) or an opt-in flag.

**J. Output quality (R13.2, R13.5)**
- **Lints:** OAG does not pass `lints/recommended` (`/** */`, `unnecessary_this`, an import from `equatable/src`). SP and SDCG turn lints off entirely through `ignore_for_file: type=lint`. degenerate does not format the output.
- **Superfluous files:**
  - OAG: 131 of 217 files are documentation and test stubs, and stale files are not deleted;
  - swagger_to_dart: half of the model lines are a dump of the JSON schema in comments;
  - space_gen: generates round-trip tests.
- **→ Lesson:** only `lib`, a manifest of output files with removal of stale ones, targeted ignores in the files themselves.

**K. build_runner and dependencies (decision 1)**
- **Dependency conflicts:** the top issue of SDCG (#812, 17 reactions) — version conflicts of `build` / `dart_style` / `chopper`. The OAG wrapper is blocked by `analyzer <9`.
- **Errors are visible only after the second phase** (SP #380, #411, #462).
- **Dead runtime dependencies:** `one_of` was last published in 2022.
- **→ Lesson:** the generator must not live in the user's dependency graph; the runtime is minimal.

**L. Code injection through spec strings**
- **Problem:** any string from the spec substituted into the generated code is a potential injection (degenerate #15, #18; tonik #88 — a line break produced an invalid raw literal).
- **→ Lesson:** one escaping helper for all substitution sites, a wrapper type `SpecString`, fuzz tests (tonik has a corpus `adversarial_strings`).

**M. Documentation diverges from the code (R15.5)**
- **Examples:** OAG claims `Cookie ✓`; the swagger_parser README has `put_in_folder`, which is not in the code; tonik claims "3.2" in the repository description.
- **→ Lesson:** generate the support matrix from golden fixtures.

**N. Bus factor**
- **Examples:** SDCG is abandoned; SP is released by one person; the Dart generators of OAG have no owner.
- **→ Lesson:** a public roadmap, automatic releases, several maintainers.

---

## 4. Checking the claims from the brief

| Claim | Verdict | Evidence |
|---|---|---|
| tonik: `validateStatus: (_) => true` breaks `onError` (R10.2) | ✅ **true** | `tonik_generate/.../dio_options_generator.dart#L25-L65`. Transport failures still go to `onError`, but 4xx/5xx do not. It cannot be fixed via `BaseOptions`, because request options take precedence. Separately, tonik overwrites `baseUrl` in the passed Dio. The same problem exists in **degenerate** [03 §1.4a, 04 §2.1] |
| tonik and swagger_to_dart overwrite data with nulls (R7.3) | ⚠️ **tonik — partly**, ✅ **swagger_to_dart — true** | tonik sends `null` only for optional + nullable (`class_generator.dart#L864-L875`). swagger_to_dart does so for all optional fields in JSON bodies, because it generates without `includeIfNull`. space_gen behaves like tonik [03 §1.4b, §2.4] |
| swagger_parser loses the raw value of an unknown enum (R8.1) | ✅ **true** + R8.2 violated | `dart_enum_dto_template.dart` L131-142: `$unknown(null)`. The value is sent as `"$unknown"`; with `enums_to_json` it throws `StateError` [02 §1.5] |
| tonik loses the raw value of an enum (R8.1) | ✅ **true** | Without the option — a decoding error for the whole response. With `generateUnknownCase` — a fixed `unknown` value. R8.2 at the same time ✅: `toJson` throws [03 §1.4c] |
| dart-dio generates stubs (R13.5) | ✅ | 131 of the 217 files of the Petstore example are `doc/` and `test/`. Stale files are not deleted [01 §2.2]. *Earlier in the chat I wrongly called this a "correction" of the R13.5 wording. The wording is correct* |

---

## 5. What to borrow (by requirement area)

| Area | Idea | Source |
|---|---|---|
| **R2.1** normalizer | 25 named rules, each switched on separately, a set "on by default", `DISABLE_ALL`. Each rule's docs carry a before/after diff. **Add** codes, a pointer and a report | OAG normalizer [01 §4.1] |
| **R2.1** catalog | 48 defects of NestJS / FastAPI / springdoc / ASP.NET → rule names, codes, auto-fix. Presets `preset: nestjs | fastapi | springdoc | aspnet | generic` | [06 §C] |
| **R2.2** diagnostics | A catalog of `Category/Name`, severity levels with business semantics, message templates that say how to fix the problem. Codes that cannot be lowered (ruleset `speakeasy-generation`) | Stainless, Speakeasy [05 R2] |
| **R2.2** output | `text`, `json` (with the JSON Schema of the output), `sarif`, `github-actions`, `junit`. The pointer is the primary address; line/col are additional | Redocly, Spectral, oasdiff |
| **R2.2** unsupported | Tracking of unused keys (`markUsed`) → automatic detection of unsupported keywords and `x-*` | space_gen [03 §3.6] |
| **R2.3** baseline | The key is a fingerprint `sha256(code|anchor|args)[:12]` without the message text (oasdiff). `count` as a ceiling for mass codes. An entry that no longer fires fails CI with a hint to `baseline prune` (ESLint bulk suppressions) | oasdiff, ESLint, Redocly ignore-file |
| **R3** overrides | A mandatory `reason`; `matches_schema` (find structurally equal schemas → `$ref`); diagnostic `Transform/Useless` / "did not match any targets"; overlay `strict: true` by default | Stainless, Speakeasy, oapi-codegen |
| **R3** types | `scalars` (format → type + serialization functions), `overriden_models`, `response_override_value_map` — these are user requests that are worth covering with addressed overrides | SDCG [02 §2.7] |
| **R4** filters | Selectors `'GET /path'` + regex, `exclude` takes priority, orphan schemas are removed automatically; glob with the suffix `#METHOD`; normalization of tags (case, `_`, `-`) | hey-api, Kiota, degenerate |
| **R5** names | A global pass over `Map<JsonPointer, String>`; scoped imports; a doc comment "Original name: `x`" on a forced rename; naming `With<Subtype>` / `As<Subtype>` for several media types | space_gen, tonik, SP, OAG |
| **R6** model | An 8-row matrix; a separate `Date` type; `JsonValue` as an extension type; `fieldOrDefault`; models by direction (readOnly / writeOnly); `--unwrap-fields` for envelopes | space_gen, ogen, degenerate |
| **R7** three states | Modes `nullable | all | off` (≈ R7.2); `Patch<T>?` + `explicitJsonNullWhenNonNullField` (checked on 6.14.1) | degenerate `Omittable`, [07 §A.2] |
| **R8** enum | `sealed X` + `enum XKnown implements X` + `XUnknown(raw)`; an enum with one value stays closed; read `x-extensible-enum`, `x-ms-enum.modelAsString`, `x-enum-varnames`, `x-enumNames` | [07 §C.3], Speakeasy, Stainless Java |
| **R9** union | OAS 3.2 `discriminator.defaultMapping` as the standard fallback. For `oneOf` without a discriminator — ogen's ladder **during generation**: JSON type → unique required fields → field type → non-intersecting const/enum. A diagnostic when the conditions intersect. The dispatcher — as in freezed (switch on the key, variants via `fromJson`), but with the raw JSON in `Unknown` | ogen, Stainless, freezed 4.0.2 |
| **R10.5/10.8** metadata | `OperationInfo` (operationId, method, pathTemplate, tags, security) in every request, merged into the user's `extra`. Security — structural metadata (AND / OR) | SDCG `SwaggerMetaData`, space_gen `AuthRequest`, hey-api |
| **R10.2** Dio | Do not touch `validateStatus`; catch `DioException` with `response` and map it to a typed variant. The generated code calls `dio.request` (`fetch` with a "bare" `RequestOptions` skips `BaseOptions`). An interceptor may `resolve` a non-2xx response, so the status is always checked through `switch` | florval, [07 §B] |
| **R10.3** styles | Codecs for all styles (simple, label, matrix, form, deepObject, pipe, space, `allowReserved`) as a reference for comparison tests (MIT) | `tonik_util/lib/src/encoding` |
| **R11** errors | Selection order: exact code → `4XX`/`5XX` → `default` → base. Separate variants: transport, documented error, decoding error, undocumented status | Kiota, progenitor, swift-openapi-generator |
| **R12** SSE | A table of event handlers (`[DONE]`, error event, fallthrough); `resumable` (Last-Event-ID, `retry:`, up to 5 attempts with a reset) + `terminator`; no automatic retry of POST streams by default. Parser references: `sse_parser`, LaunchDarkly (17/17 WHATWG cases) | Stainless, Fern, openai-python, [04 §5] |
| **R13/R14** stability | Lock file (hash of the spec + hash of the config + generator version); file manifest + `--dry-run`; "we own only our own directories"; `edition`s for deliberate output changes; `oasdiff --fail-on`; `dart_apitool diff` for the Dart API | Kiota, Speakeasy, OAG, space_gen, Stainless |
| **R15.3** corpus | ~40 integration specs from tonik + Imposter mock server + docker examples with real FastAPI / NestJS / Spring; degenerate snapshots (Stripe, GitHub, K8s, OpenAI, Cloudflare) with `dart analyze`; GitHub and Discord from space_gen; golden for FastAPI `HTTPValidationError` | tonik, degenerate, space_gen, OAG #13302 |
| **Marketing** | Web playground: a core without `dart:io` gives generation in the browser | swagger_parser |

---

## 6. Proposed changes to requirements

| R-ID | What to change | Why |
|---|---|---|
| R0.1 | The internal model is a superset of OAS 3.2; **the dialect is determined by the content**, not by the `openapi` field | NestJS ≤11 writes `nullable` into 3.1 documents; FastAPI puts `itemSchema` into a `3.1.0` document; .NET 3.0 removes `type` from numbers [06 §A.3] |
| R1.4 | Accept `itemSchema` in documents of any version | FastAPI ≥0.135 generates SSE this way |
| R1.2 | Schema identity = absolute URI of the document + pointer; take `$id` and `$self` (3.2) into account | space_gen #358: identical `#/components/schemas/Foo` from two files were merged |
| R2.3 | The baseline key is the code + fingerprint (a semantic anchor), not a raw pointer with array indexes; a stale entry fails CI until `baseline prune` | indexes shift; ESLint / oasdiff experience |
| R2 (new) | **R2.6:** every string from the spec that reaches the code passes through one escaper; fuzz tests | code injection (degenerate #15) |
| R3.2 | Overlay treats an action with no matches as **successful**, and JSON Patch is atomic → an own diagnostic "override found no target" and a "soft" mode for applying patches are needed | Overlay spec, RFC 6902 [06 §B] |
| R3.3 | The current Overlay version is **1.2.0** (1.1 added `copy`, 1.2 — reusable actions) | [06 §A.0] |
| R6.5 | Clarify: "a clear error" = schema + field + JSON pointer + expected / actual type, in **any** build mode (OAG `dart` checks required only in `assert`) | OAG P10 |
| R8.2 | The mechanism is at the type level (`XKnown` in parameters and request constructors). Separately decide the policy for a GET→PUT round-trip of an unknown value: forbidden by default, with opt-in per schema | space_gen PR #374 chooses the opposite |
| R10.1 | Generated code calls `dio.request`, not `fetch`: `fetch` with bare `RequestOptions` skips the user's `BaseOptions`. If an abstraction appears later (§7.3) — "the adapter uses the user's client as is" | [07 §B.1] |
| R10.2 | Add: an interceptor may `resolve` an error into a non-2xx response → generated code always parses the status | [07 §B.2] |
| R10.7 | Document mocktail / fakes: mockito for null-safe mocks requires build_runner | [07 §C.4] |
| R11.7 | Dio 5.11 has 9 exception types (`transformTimeout` added); `cancel` is a separate variant, not a transport failure | [07 §B.3] |
| R12.4 | On Flutter Web the standard Dio adapter (XHR) **does not stream**: SSE arrives in one chunk. Document `ConversionLayerAdapter(FetchClient)`; the browser's `EventSource` does not fit (GET only, no headers) | dio#1859, #1740 open since 2023 |
| R12.5 | Reconnection is **disabled by default for non-idempotent** (POST) streams | openai-python: a repeated POST may duplicate the result |
| R13.1 | Pin `dart_style`; `// dart format width=N` in every file; imports are already grouped (then the output of 3.12 and 3.13 matches); `lineEnding: '\n'`; no network and no `dart fix` during generation | formatter drift [07 §D.2], space_gen |
| R13.5 | No change (the wording is correct) | — |
| R14.1 | A separate category **"source-breaking for exhaustive switch"** (a new enum value or union variant) | §7.8 |
| R14.2 | Clarify: `Unknown` variants protect **already compiled** code (old client, new server), but **not** the source code after regeneration if the `switch` is exhaustive | Dart semantics; `openai_dart` |
| R15.1 | Distribution as an isolated tool, not a `dev_dependency` | analyzer lock-step |
| R15.3 | Concrete corpus sources: tonik, degenerate, space_gen (§5) | — |

---

## 7. Open decisions: recommendations

### 7.1 Output type (decision 1)

**Ready code without a mandatory build_runner**; integration with build_runner is an optional thin `Builder` over the same programmatic API.
- **Pro:** the output depends only on the generator's version (R13.1, R15.4); golden tests = direct comparison; no ~12 s cold AOT compilation of builders on CI; no lock-step with `analyzer`. Macros were cancelled (2025-01); as of 2026-10 augmentations have not shipped, and build_runner is not going away in any case.
- **Con:** more code in the generator.
- **Mitigation:** generated types follow the json_serializable contract (`factory X.fromJson(Map<String, dynamic>)`, `toJson()`), so they fit into the user's `@JsonSerializable` classes and vice versa (verified).

### 7.2 Serialization (decision 2): the main question

What json_serializable 6.14 covers and what it does not (verified on 6.14.1):

| Requirement | json_serializable | Details |
|---|---|---|
| Ordinary models, R6.1, extra fields | ✅ | |
| R6.4 generics | ✅ | `genericArgumentFactories` |
| R7 three states | ✅ | `explicitJsonNullWhenNonNullField` + `Patch<T>?` |
| R6.5 clear errors | ⚠️ | `checked: true` gives the class + key, without a path; ≈25× slower than unchecked; without checked — a bare `TypeError` |
| R8.1 / R8.2 | ❌ | Dart `enum` cannot hold a raw value; `$unknown` is sent |
| R9 union | ❌ natively | Workaround: the generator writes the sealed base with a dispatcher itself (as freezed does), variants are `@JsonSerializable` |

> Reports 02 and 05 say that three states via json_serializable are impossible. This has been **outdated** since 6.14.0; report 07 verified that it works.

**Option A — hybrid.** json_serializable for object models; the generator itself emits sealed enums, union dispatchers, `Patch<T>`, typed errors.
- **Pro:**
  - literally matches the requirements;
  - a familiar code shape;
  - your expertise in json_serializable — the R6.5 gaps can be closed upstream (for example, a JSON path in `CheckedFromJsonException`).
- **Con:**
  - build_runner in the user's project;
  - errors are visible only after the second phase (SP #380);
  - minimum `json_serializable: ^6.14.0` and Dart ≥3.8;
  - the final `.g.dart` depends on the json_serializable version in the user's lockfile. R13.1 is formally met (the generator's output is deterministic), but the actual code is not.

**Option B — own emission with the json_serializable contract.** The generator writes `fromJson`/`toJson` itself; runtime helpers give errors with a JSON pointer.
- **Pro:**
  - R6.5 and R13.1 fully;
  - no build_runner;
  - prototype: ≈2.2× slower than unchecked json_serializable and ≈10× faster than checked;
  - compatibility with the user's `@JsonSerializable` classes in both directions.
- **Con:** ~300–500 lines of a simple emitter; "does not use" json_serializable.

**Decision (2026-10-11): option B.** "Works on json_serializable" means **compatibility with the contract**, not a dependency:
- the generator writes `fromJson`/`toJson` itself;
- the public signatures are the same as json_serializable's: `factory X.fromJson(Map<String, dynamic> json)` and `Map<String, dynamic> toJson()`;
- runtime helpers give decoding errors with a JSON pointer;
- generated types fit into the user's `@JsonSerializable` classes and vice versa.

A test of this nesting must be part of the golden set (R15.3).

### 7.3 HTTP layer (decision 3): in v1 only Dio, postpone the abstraction but lay a seam

**Recommendation: in v1 only Dio** (`PetsApi(Dio dio)`), postponing full independence from the HTTP client. Conditions:
1. **Generated code touches Dio through a narrow surface:** `dio.request`, `Options`, `CancelToken`, `DioException`, `FormData`/`MultipartFile`, `ResponseBody`. The logic (parameter encoding, status parsing, SSE parser) lives in the runtime and does not depend on Dio. Then the switch to an abstraction later becomes a mechanical change.
2. **Make the decision before 1.0.** Changing the constructor `PetsApi(Dio)` → `PetsApi(ApiTransport)` changes the generator's output, which is a breaking change (R15.4). Before 1.0 this is acceptable.
3. **Other HTTP clients are already available through Dio.** `dio_compatibility_layer` plugs any `package:http` client (`cronet_http`, `cupertino_http`, `fetch_client`) in as the Dio transport. Without a Dio dependency, what remains are only those who do not want Dio in the project at all.

**Why postponing is safe.** The abstraction itself costs little: an interface + an adapter, a few hundred lines. What is more expensive is:
- own cancellation and progress types with bridges to Dio;
- an escape hatch for Dio-specific options;
- the absence of interceptors in `package:http`, so R10.2 means something else for it;
- a double set of tests.

None of this is needed while there is no real user without Dio.

**What the abstraction will look like when it comes.** A thin transport interface in the runtime and adapters in separate packages:

```dart
// typed_openapi_runtime: without dio
abstract interface class ApiTransport {
  /// Sends the request by the client's OWN path (interceptors, auth, retries).
  /// Any HTTP status is returned as a [RawResponse] — AFTER
  /// the client has handled the error its own way (for Dio — through onError).
  /// A transport failure → ApiTransportException, cancellation → ApiCancelledException.
  Future<RawResponse> send(ApiRequest request);
}

final class ApiRequest {
  final OperationInfo operation;      // operationId, method, pathTemplate, tags, security
  final String method;
  final String path;                  // already encoded by style
  final List<(String, String)> query; // already encoded by style/explode
  final Map<String, String> headers;
  final ApiBody? body;                // json | formUrlEncoded | multipart | bytes
  final ResponseKind expect;          // json | text | bytes | stream
  final ApiCallOptions? options;      // cancel, progress, headers, extra, timeout
  // ...
}

// typed_openapi_dio
final class DioTransport implements ApiTransport {
  DioTransport(this._dio);            // the user's Dio; we change nothing (R10.1)
  final Dio _dio;

  @override
  Future<RawResponse> send(ApiRequest r) async {
    try {
      final res = await _dio.request<Object?>(          // request, not fetch: merges BaseOptions
        r.path,
        queryParameters: ...,
        data: ...,
        options: Options(method: r.method, headers: r.headers,
            extra: {...?r.options?.extra, OperationInfo.key: r.operation}),   // R10.5
        cancelToken: bridgeCancel(r.options?.cancel),
      );
      return RawResponse.fromDio(res);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.badResponse && e.response != null) {
        return RawResponse.fromDio(e.response!, cause: e);  // onError has already run (R10.2)
      }
      throw mapTransportFailure(e);                         // R11.7
    }
  }
}

// usage
final pets = PetsApi(DioTransport(dio));
```

- **Pro:**
  - the generated code does not import `dio`, so a `package:http` adapter is added without changing the API shape;
  - tests can be mocked at the transport level;
  - R10.2 is met in each adapter in its "native" way.
- **Con:**
  - own cancellation and progress types with bridges;
  - Dio-specific things (own `Options`) — through `extra` or an escape hatch;
  - the query is encoded by the generator (it is needed anyway for label / matrix / deepObject / `allowReserved`, which Dio cannot do), so interceptors that read `options.queryParameters` will see a ready URI.
- **Lesson from degenerate:** it has the same scheme, but its Dio adapter set `validateStatus: (_) => true` and broke `onError`. The adapter contract must explicitly require the native error path.

### 7.4 Error model (decision 4)

**Decision (2026-10-11): no exceptions.** Each generated method returns `Future<ApiResult<T, E>>`, where `E` is the sealed type of the operation's documented errors. Expected failures (HTTP error, transport, cancellation, decoding) become values, not exceptions.

```dart
// typed_openapi_runtime
sealed class ApiResult<T, E> { const ApiResult(); }
final class ApiSuccess<T, E> extends ApiResult<T, E> {        // 2xx; status and headers are available
  const ApiSuccess(this.data, this.statusCode, this.headers);
  final T data; final int statusCode; final Map<String, List<String>> headers;
}
sealed class ApiFailure<T, E> extends ApiResult<T, E> { const ApiFailure(); }
final class ApiHttpError<T, E> extends ApiFailure<T, E> {     // documented 4xx/5xx/default (R11.1)
  const ApiHttpError(this.statusCode, this.body, this.headers);
  final int statusCode; final E body; final Map<String, List<String>> headers;
}
final class ApiUndocumentedStatus<T, E> extends ApiFailure<T, E> { /* statusCode, rawBody */ }  // R11.3
final class ApiTransportError<T, E> extends ApiFailure<T, E> { /* kind, cause */ }              // R11.7
final class ApiCancelled<T, E> extends ApiFailure<T, E> { /* cause */ }
final class ApiDecodeError<T, E> extends ApiFailure<T, E> { /* pointer, schema, message */ }    // R6.5

// usage
switch (await pets.getPetById(petId: 1)) {
  case ApiSuccess(:final data): show(data);
  case ApiHttpError(body: GetPetByIdError404()): showNotFound();
  case ApiHttpError(:final body): showError(body);
  case ApiUndocumentedStatus() || ApiTransportError() || ApiCancelled() || ApiDecodeError(): retryLater();
}
```

Rules:
- **R10.2 is not violated.** Dio throws a `DioException`, interceptors see it in `onError`, and only then the generated method catches it and converts it to `ApiFailure`.
- **Bugs are not hidden.** `Error` (`StateError`, `TypeError` in user code, and so on) propagates as before: catching it would mean masking programmer errors.
- **Ergonomics in the runtime:** `dataOrNull`, `fold`/`when`, `map`. For places where the framework expects an exception (`AsyncValue.guard` in Riverpod), an explicit `getOrThrow()` can be provided on the caller's side. The generated code itself throws no exceptions.
- **Mocking (R10.7):** one method per operation; the mock returns `ApiSuccess`/`ApiFailure`.
- **R11.2 ("the model is configurable"):** in v1 only `Result`. An exceptions mode — later, if a request appears.
- **Open question for streams (R12):** a failure after the stream has started (a break, an invalid event) should arrive as an element of the stream, not as an exception. The form has to be designed separately.

The shared error schema is generated once (R11.4); the operation's errors are sealed by status.

### 7.5 Parser (decision 5)

**Own.** `tonik_parse`/`tonik_core` are not suitable:
- marked as internal, 0.x, with breaking changes in every minor release;
- fail on the first defect;
- have no pointers and spans;
- discard constraints, `x-*` and external `$ref`s;
- `tonik_core` is a mutable IR tied to the tonik runtime.

The architecture in the spirit of space_gen:

```
load (I/O only here) → lossless-DTO (JsonPointer + SourceSpan + extensions on every node)
  → normalizer (R2.1) → overrides / overlay (R3) → resolve (absolute URI + pointer, cycles)
  → dispatch (oneOf/anyOf as a separate phase with an IR of predicates) → naming (Map<JsonPointer, String>)
  → immutable IR with no knowledge of Dart → Dart mapping → emitter
```

- **The basis is `package:yaml`, for JSON and YAML alike.** JSON is a subset of YAML 1.2, so one parser gives spans (line and column) for both formats. It parses the 4.7 MB OpenAI spec in 225 ms versus 25 ms for `jsonDecode`, but `jsonDecode` gives no positions, and without them there is no diagnostic for R2.2.
- **Duplicate keys.** `jsonDecode` silently takes the last value, while `package:yaml` throws an error. The loading layer must catch it and turn it into a diagnostic with a position, rather than fail. The YAML coercions (the next point) apply only to YAML files.
- **YAML coercions need separate rules:** `200:` becomes an int key, `1.0` a double, `0x1F` a number, and duplicate keys throw an error.
- **Helper packages:** `rfc_6901`, `rfc_6902`, `json_path` (for Overlay; there is no Overlay implementation on pub), `source_span`, `yaml_edit` (baseline), `json_schema` + `checked_yaml` (config validation).

### 7.6 Extensibility (decision 6)

**Config + overrides + typed hooks over the IR** (type mapping, naming, filters) through the programmatic API. **No templates.**
- Every template change becomes breaking (R15.4), breaks the lint guarantees (R13.2), and users fork templates.
- The practice of SP and SDCG shows that the config hooks are the ones really used (`field_parsers`, `scalars`, `custom_annotations`).

### 7.7 Representation (decision 7)

- **Three states:** `Patch<T>?`, where `null` means "the key is absent", plus `Patch.value(x)` / `Patch.nullValue()`. Consistent with R7.3: everywhere in the model `null` means "do not send". Ergonomics with dot shorthands: `UpdatePet(name: .value('Rex'), tag: .nullValue())`.
- **Enum:** `sealed class X` + `enum XKnown implements X` + `class XUnknown` with a private constructor and static aliases `X.available`.
  - A model field has type `X`; **operation parameters and request constructors accept only `XKnown`**, so R8.2 is checked by the compiler.
  - `switch` exhaustiveness is preserved.
  - Extension types were **rejected**: any string can be cast (`'hacked' as Color`), and exhaustiveness is lost (verified).
- **Union:** a sealed base with a dispatcher by discriminator (as in freezed) + `XUnknown(discriminator, Map json)`, whose `toJson` returns the raw JSON. Use `defaultMapping` from 3.2 when it is set.

Code sketches: [07 §E.2–E.6](07-dart-building-blocks.md).

### 7.8 New decision: exhaustiveness versus R14.2

Adding a value to an `enum` or a subclass to a `sealed` breaks the consumer's **source code** with an exhaustive `switch`, and the `Unknown` variant does not save it from this. Dart has no analogue of Swift's `@unknown default`.

Example. The backend added the value `pending` to `PetStatus`, and the client was regenerated.

```dart
// exhaustive: PetStatusKnown — Dart enum, PetStatus — sealed
final label = switch (pet.status) {
  PetStatus.available => 'In stock',
  PetStatus.sold => 'Sold',
  PetStatusUnknown(:final value) => value,
};
// after regeneration: compile error non_exhaustive_switch_expression,
// because `pending` is not handled. The developer must decide what to show.

// open: PetStatus is an ordinary class with static const, not an enum or sealed
final label = switch (pet.status) {
  PetStatus.available => 'In stock',
  PetStatus.sold => 'Sold',
  _ => pet.status.value,      // the default branch is always required
};
// after regeneration: compiles without changes, `pending` falls into `_`.
```

In both modes an **already installed app** (old client, new server) does not crash: the unknown value is decoded into `PetStatusUnknown`. The mode affects only what happens during compilation after the client is regenerated.

Switching at the schema level is done in the overrides:

```yaml
# typed_openapi.overrides.yaml
schemas:
  ChatEvent:          # union of SSE events, which often grows
    exhaustive: false
```

| Mode | Behavior | For whom |
|---|---|---|
| `exhaustive` (sealed / enum) | The compiler forces handling of a new value; the R14.1 report marks the change as source-breaking | **Your audience:** product teams with their own backend, where "a new status → it must be handled" is a useful error |
| `open` (class with static constants, `switch` requires `_`) | A new value breaks nothing | Public SDKs, event streams that often grow |

**Decision (2026-10-11):**
- `exhaustive` by default, with an override `exhaustive: false` on the schema;
- there is no separate `open` default for SSE events: if needed, it is turned off by the same override;
- the R14.1 report shows new enum values and union variants as a separate category of changes ("source-breaking for an exhaustive `switch`").

---

## 8. Risks

1. **Scope.** The requirements are very numerous. The most expensive parts: the R6.1 matrix with golden tests, the R10.3 style codecs, SSE on web.
2. **Pace of Dart toolchain changes.** analyzer changes its major version every 1–2 months, and `dart_style` changes style even in patch releases. Protection: isolated distribution, pinned `dart_style`, a CI matrix with the oldest and newest SDK.
3. **Dio does not stream on web.** SSE on Flutter Web works only with `ConversionLayerAdapter(FetchClient)`, and then cancellation does not interrupt the fetch.
4. **Competitors are moving.** degenerate quickly adds features; tonik has an open PR with SSE. The differentiation must be exactly in R2/R3, not only in models.
5. **Licenses.** The code of openapi_flutter_gen (AGPL or commercial) and of the dynamite generator (AGPL) must not be copied. tonik, degenerate, Kiota, space_gen and sse_parser (MIT) and LaunchDarkly SSE (Apache-2.0) may be taken as references with attribution.
6. **Bus factor** — the main reason for the death of SDCG and a risk for SP.

---

## 9. Detailed reports

| File | Contents |
|---|---|
| [../requirements.md](../requirements.md) | Requirements (source) |
| [01-openapi-generator.md](01-openapi-generator.md) | OAG `dart-dio` / `dart`: coverage of R-IDs, full list of normalizer rules and mappings, 31 problems with lessons |
| [02-swagger-parser-and-sdcg.md](02-swagger-parser-and-sdcg.md) | swagger_parser and swagger_dart_code_generator: config as prior art, issues, check of R8.1 |
| [03-tonik-swagger-to-dart-space-gen.md](03-tonik-swagger-to-dart-space-gen.md) | tonik, swagger_to_dart, space_gen: verdicts on claims, assessment of `tonik_parse` |
| [04-dart-long-tail.md](04-dart-long-tail.md) | 17 other generators, large SDKs, packages for the parser, a test of SSE packages against WHATWG |
| [05-cross-language-prior-art.md](05-cross-language-prior-art.md) | Speakeasy, Stainless, Fern, hey-api, Kiota, ogen, oapi-codegen, oasdiff, linters: patterns for R2–R14, table of `x-` extensions |
| [06-spec-versions-and-defects.md](06-spec-versions-and-defects.md) | OAS 3.0 → 3.1 → 3.2, Overlay / JSON Patch / Pointer, catalog of 48 defects, recipes for backends |
| [07-dart-building-blocks.md](07-dart-building-blocks.md) | json_serializable, build_runner, Dio, language features, dart_style; recommendations 1–7 with code sketches |
