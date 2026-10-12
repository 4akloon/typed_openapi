# 02. swagger_parser and swagger_dart_code_generator: prior art for the new generator

> Research date: **2026-10-11**. Primary sources: repository code (shallow clone), README/CHANGELOG, GitHub issues/PRs (via `gh`), pub.dev API.
> Code snapshots:
> * **swagger_parser (SP)**: `Carapacik/swagger_parser@be6df7c` (main, 2026-10-01), package `swagger_parser 1.45.0`.
> * **swagger_dart_code_generator (SDCG)**: `epam-cross-platform-lab/swagger-dart-code-generator@753bdeb` (master, 2025-12-11), package `4.1.1`.
> Confidence marks: **(code)** = verified by reading the code (not run), **(issue)** = from the words of the reporter/maintainer in the issue, **(unverified)** = a conclusion without direct evidence.
> Paths in the form `SP:lib/...:L10-20` are relative to `swagger_parser/` in the SP repo; `SDCG:lib/...` is relative to the root of the SDCG repo. Full base URLs are in the "Sources" section.

## TL;DR

1. **The author's claim about R8.1 is confirmed (code).** SP generates `$unknown(null)` as a separate Dart `enum` constant; `fromJson` returns `$unknown`, and the raw value is discarded. The same in SDCG (`swaggerGeneratedUnknown(null)`). A new finding: both also violate **R8.2**. In SP an unknown value can be sent back: json_serializable encodes it as the string `"$unknown"`, with `enums_to_json: true` it throws `StateError`, and in dart_mappable it becomes the string `"unknown"`. In SDCG an unknown value in a nullable field becomes `null` when decoded, so it cannot be told apart from a missing one.
2. Both tools **parse the spec as `Map<String, dynamic>` with casts** and have no model with JSON pointers. Hence they crash on "dirty" specs and report no diagnostics. Example: SP still crashes on `paths./x.parameters` at the path-item level, because the cast `requestPath as Map` comes **before** the key check (SP:open_api_parser.dart:L634 vs L641; [#374](https://github.com/Carapacik/swagger_parser/issues/374)). `$ref` in both is resolved as the "last path segment" (`p.basename` / `split('/').last`). There are no external files and no cycle detection.
3. **The required×nullable matrix** in both is collapsed into the rule "optional ⇒ nullable". There is neither tri-state for PATCH nor a split of request/response. In SP this is the largest cluster of bugs (#303, #358, #460, #443, #440, #307). #460 hits exactly the NestJS specs.
4. **Polymorphism:** SP has sealed classes for `oneOf`/`anyOf` with a discriminator and a `fallback_union` with raw JSON (except freezed). Without a discriminator SP tries the variants one after another via successive try/catch, that is, it silently guesses. SDCG does not support discriminators at all ([#563](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/563), open since 2023), and turns `oneOf`/`anyOf` into `dynamic`.
5. **None of them has typed errors, several 2xx responses, the SSE protocol, cookie parameters, or `style/explode/deepObject`.** Both silently drop cookie parameters (code).
6. **Activity:** SP is alive, maintained mainly by one person, releases roughly monthly (1.42→1.45 in 2026). SDCG is effectively stalled: last commit 2025-12-11, 13 open PRs, [#796 "Future of this project"](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/796) unanswered. Its most popular issues concern dependency conflicts with build_runner.
7. **What to take:** from SP — `schemes:` with inheritance, `replacement_rules`, tag and glob-path filters with tree-shaking, `fallback_union` with raw JSON, `add_openapi_metadata`, a doc comment "Original name: …" when renaming, e2e golden tests. From SDCG — a typed `SwaggerMetaData` in every request (operationId/security/tags), `scalars` (format→type+functions), `overriden_models`, `response_override_value_map`, `Wrapped<T>` for copyWith, `_dateToJson` for `format: date`, formatting via dart_style with page_width.

---

# 1. swagger_parser

## 1.1 Overview

| Parameter | Value | Source |
|---|---|---|
| Latest version | **1.45.0**, published 2026-09-25 | pub.dev API `/api/packages/swagger_parser` |
| Earlier releases in 2026 | 1.42.0 (02-02), 1.43.0 (03-03), 1.43.1 (04-21), 1.44.0 (06-22), 1.44.1 (08-02), 1.44.2 (09-01), 1.44.3 (09-05) | pub.dev API |
| Pub points / likes / downloads over 30 days | 160/160 · 124 likes · 65 650 | pub.dev `/score` |
| GitHub | 148★, 106 forks, MIT license, created 2022-10-02 | `gh repo view` |
| Issues | 71 open out of 218 (open PRs: 0) | `gh issue list` |
| Who maintains it | Carapacik (198 commits) plus contributors (StarProxima, vasilich6107, peter-trost, Sadhorsephile…). In 2026, dozens of merged PRs from the community | `gh api …/commits`, `/contributors` |
| Output languages | Dart (retrofit + json_serializable / freezed / dart_mappable) and Kotlin (retrofit + moshi) | README |
| Code size | ≈9.6 thousand lines; the parser core `open_api_parser.dart` has 2299 lines | `wc -l` |

Conclusion on maintenance: the project is active. Most features and fixes in 2026 came as PRs from the community. The bus factor is close to 1, because only the owner makes releases.

## 1.2 Architecture

* **Launch.** CLI `dart run swagger_parser` (SP:bin/swagger_parser.dart). The config is looked up in `swagger_parser.yaml` or in the `swagger_parser:` section of `pubspec.yaml`; the `-f` argument points to a different file (SP:lib/src/utils/file/io_file.dart:L11-25). There is also a programmatic API: `GenProcessor`, `SWPConfig` are exported from `lib/swagger_parser.dart`. On top of it a web interface `swagger_parser_pages` is built (Flutter Web, <https://carapacik.github.io/swagger_parser>).
* **Pipeline.** `OpenApiCorrector.correct()` (renaming schemas with text regex substitutions in raw JSON/YAML) → `OpenApiParser` (walking a `Map<String,dynamic>`) → the "universal" model (`UniversalDataClass`, `UniversalRestClient`, `UniversalType`) → line templates (`lib/src/generator/templates/*.dart`) → writing the files.
* **Output is annotated code that needs `build_runner`.** The client is generated as `@RestApi() abstract class XClient { factory XClient(Dio dio, {String? baseUrl}) = _XClient; ... }` (SP:dart_retrofit_client_template.dart:L52-62). Models are annotated with `@JsonSerializable` / `@Freezed` / `@MappableClass`. Then the user runs `dart run build_runner build`, and `retrofit_generator` with `json_serializable` / `freezed` / `dart_mappable_builder` generate `.g.dart`, `.freezed.dart`, `.mapper.dart`. For freezed+retrofit the README requires setting the order of the builders in `build.yaml`.
* **File layout.** `<output>/clients/*_client.dart`, `<output>/models/*.dart` (one model per file), an optional root client `rest_client.dart` (a concrete class with lazy getters of the clients by tag) and `export.dart`. `merge_outputs: true` merges everything into one file. `put_clients_in_folder` puts the clients into a separate folder.
* **File header:** `// coverage:ignore-file`, `// GENERATED CODE - DO NOT MODIFY BY HAND`, `// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import` (SP:lib/src/utils/base_utils.dart:L79-84). The lints are **silenced**, not satisfied.
* **Formatting.** The generator does not run `dart format`, because there is no dependency on `dart_style`. The golden tests format the output only after generation (SP:test/e2e/e2e_util.dart) (code).
* **Loading from a URL:** `schemaFromUrl` (SP:io_file.dart:L33-40). It is `HttpClient.getUrl` without authorization headers and without a status check. A copy is written to the project root under the URL's basename (`writeSchemaToFile`, L43-45, config_processor.dart:L118-142), and generation runs from the content just downloaded, not from a local snapshot (code).
* **Peculiarity of YAML input (code).** `YamlMapX.toMap()` converts **all scalars to strings** (`entry.value.toString()`, SP:open_api_corrector.dart:L309). For YAML specifications `true`, `1` and `null` become `"true"`, `"1"`, `"null"`, while for JSON the types are kept. Because of this the parser everywhere has `x.toString().toBool()`, and the behaviour of JSON and YAML can diverge.

## 1.3 Config as prior art

The full list of keys is taken from `SP:lib/src/config/swp_config.dart` (`yamlMap['…']`). The README diverges from the code: it still describes `put_in_folder`, although this option was removed in 1.18.0 (CHANGELOG:L469). `generate_validator` is in the code, but not documented in the README.

| Option (default) | What it does | Prior art for | Assessment |
|---|---|---|---|
| `schema_path` / `schema_url` | a local file or download by URL | R1.1 | URL without authorization; the snapshot is not used for generation |
| `schemes: [...]` | several specifications; each inherits the root parameters and can override them (config_processor.dart:L44-87) | **R1.3** | a good pattern; bug: `export.dart` is overwritten if the directory is shared ([#405](https://github.com/Carapacik/swagger_parser/issues/405)) |
| `output_directory`, `name`, `put_clients_in_folder`, `merge_outputs`, `export_file`, `root_client`, `root_client_name`, `client_postfix` (`Client`) | layout of the output files | R4.3 | `merge_outputs` was invented for compatibility with build_runner (one input → one output) |
| `language` (`dart`), `json_serializer` (`json_serializable` / `freezed` / `dart_mappable`) | choice of serializer | open decision 2 | three template branches mean a threefold surface of bugs (see 1.6) |
| `replacement_rules: [{pattern, replacement}]` | regex renaming of classes and enums, rules applied in turn | **R5.1** (regex prefix) | applied via text substitution in the raw spec (corrector) — fragile |
| `replacement_rules_for_raw_schema` (1.38.0) | regex over **raw** names before conversion to an identifier (`filters[name]` → `filters_name_`) | R2.1 (normalization), R5.2 | a useful idea of "pre-normalization" |
| `preserve_schema_casing` (`false`) | do not convert schema names to PascalCase | R5.1 | — |
| `path_method_name` (`false`) | method name from path+method instead of `operationId` | R5.1 | — |
| `include_tags` / `exclude_tags` | tag filter, case-insensitive; `include` takes priority over `exclude` (open_api_parser.dart:L2129-2152) | **R4.1** | no filter by `operationId` and no `exclude_paths` |
| `include_paths` (1.40.0) | glob `*` / `**` (lib/src/parser/utils/path_match.dart) | **R4.1** | include only |
| (implicit) filter of unused schemas (1.29.0, 1.44.2) | tree-shaking of schemas with a tag filter | **R4.2** | works for tag filters; for `include_paths` not verified |
| `fallback_client` (`fallback`), `merge_clients` (`false`) | client for operations without tags; one client for the whole specification | **R5.3** | — |
| `skipped_parameters: [names]` | remove parameters by name (for example `X-Some-Token`, which an interceptor adds) | R3.1 (exclusions), R10.1 | coarse addressing: by name, globally |
| `default_content_type` (`application/json`) | default content type | R10.4 | — |
| `extras_parameter_by_default`, `dio_options_parameter_by_default` (`false`) | add `@Extras() Map extras` and `@DioOptions() RequestOptions options` to **all** methods | **R10.5** | a global switch |
| `add_openapi_metadata` (1.36.0, `false`) | static constants `{tags, operationId, externalDocsUrl}` for each method; if extras are enabled, they become the default `extras` | **R10.5, R10.8** | if the user passes their own `extras`, the default is **replaced**, not merged |
| `original_http_response` (`false`) | return `HttpResponse<T>` (body, status, headers) | R10.6 | global |
| `generate_urls_constants` (1.40.0) | class `XClientUrls` with `static const` paths | (ergonomics) | — |
| `unknown_enum_value` (`true`) | adds `$unknown` / `unknown` to the enum | **R8.1** | the raw value is lost (see 1.5) |
| `enums_to_json` (`false`) | generates `toJson()` in the enum | R8 | `toJson()` on `$unknown` throws `StateError` |
| `enums_parent_prefix` (`true`) | prefix of the name of an inline enum from the parent schema | **R5.4** | — |
| `use_x_nullable` (`false`) | take `x-nullable` into account (Swagger 2) | R6.1 | — |
| `infer_required_from_nullable` (1.35.0, `false`) | if the schema has no `required` array, everything not nullable is considered required | **R2.1** (heuristic for ASP.NET) | the idea is good, but it is a hidden global mode with no report |
| `include_if_null` (`false`) | `@JsonKey(includeIfNull: …)` for nullable fields | R7.3 | global; tri-state does not solve it |
| `required_by_default` | **removed** in 1.18.0 | R6.1 | — |
| `field_parsers: [{apply_to_type, parser_name, parser_absolute_path}]` (1.41.0) | substitute a `JsonConverter` for a specific **Dart type** (json_serializable only) | **R6.2** (configurable mapping) | addressing by Dart type, not by format or location in the spec |
| `use_multipart_file` (`false`) | `MultipartFile` instead of `dart:io File` (for web) | R10.4, R0.1 | — |
| `use_freezed3`, `freezed_json_serialization` (1.45.0), `fallback_union` (`""`), `dart_mappable_convenient_when`, `use_dart_mappable_naming` | fine-tuning of serializers and unions | R9.1 | `fallback_union` see 1.5 |
| `use_flutter_compute` (1.37.0) | `@RestApi(parser: Parser.FlutterCompute)` and top-level (de)serializers for an isolate | (performance) | generated code depends on Flutter, not pure Dart (contradicts R0.1) |
| `generate_validator` (`false`, not in README) | for freezed: static `…Min/Max/…` and `bool validate()` | **R6.7** | freezed only |
| `mark_files_as_generated` (`true`) | the "GENERATED CODE" header | R13 | — |

## 1.4 Requirements coverage table

✅ present, ⚠️ partial or with defects, ❌ absent.

| Requirement | Status | Evidence / comment |
|---|---|---|
| R0.1 OAS 3.0 and 3.1, pure Dart | ⚠️ | README claims v2/3.0/3.1. 3.1 type arrays are handled only in the form `[T, "null"]`, otherwise it becomes `dynamic` (SP:parser/utils/type_utils.dart:L30-38). A `const` enum is not supported ([#121](https://github.com/Carapacik/swagger_parser/issues/121), [#342](https://github.com/Carapacik/swagger_parser/issues/342) are open). `use_flutter_compute` adds a dependency on Flutter (code) |
| R1.1 local file / URL | ⚠️ | A local JSON/YAML works. A URL is downloaded every time, without authorization; generation does not come from a snapshot (io_file.dart:L33-45) (code) |
| R1.2 `$ref` inside and between files, cycles | ❌ | `_formatRef` returns `p.basename(ref)` (open_api_parser.dart:L1170-1176): a JSON pointer is not parsed, external files are not loaded ([#120](https://github.com/Carapacik/swagger_parser/issues/120), [#366](https://github.com/Carapacik/swagger_parser/issues/366)). Cyclic schemas give a StackOverflow ([#423](https://github.com/Carapacik/swagger_parser/issues/423)) (code+issue) |
| R1.3 several specifications | ✅/⚠️ | `schemes:` with inheritance works; conflict on `export.dart` ([#405](https://github.com/Carapacik/swagger_parser/issues/405)) |
| R1.4 OAS 3.2 `itemSchema` | ❌ | — |
| R2.1 normalizer with named rules | ❌/⚠️ | There is only a "corrector" for renaming and a few global heuristics (`infer_required_from_nullable`). There is no report |
| R2.2 diagnostics with codes and pointers | ❌ | `print('Warning:…')` (L292-295), `stdout.writeln('Found duplicate object name')` (L1567). Any exception breaks the generation of the whole schema (bin/swagger_parser.dart:L25-41) |
| R2.3 / R2.4 baseline, `check` | ❌ | — |
| R2.5 do not guess silently | ❌ | Cookie parameters are dropped with a `print` (L288-295). The first 2xx is taken (http_utils.dart:L2-20), and the first content-type. A union without a discriminator is parsed with try/catch. Names `Object0` / `Enum0` (type_utils.dart:L65-87) (code) |
| R3.1–R3.3 override file, overlay | ❌ | There are only global regex rules and `skipped_parameters`; there are no address-based overrides |
| R4.1 filters tag / operationId / path | ⚠️ | tag include/exclude and path include (glob). No `operationId` and no `exclude_paths` |
| R4.2 tree-shaking | ⚠️ | For tag filters it exists since 1.29.0 (CHANGELOG), with fixes [#369](https://github.com/Carapacik/swagger_parser/issues/369) and 1.44.2. For `include_paths` not verified |
| R4.3 safe coexistence with the user's code | ⚠️ | A separate directory, no global side effects. There is no prefix for models: a clash with `Options` from dio ([#194](https://github.com/Carapacik/swagger_parser/issues/194), open) |
| R5.1 operation names | ⚠️ | `operationId.toCamel` or path+method. Regex rules apply only to classes |
| R5.2 deterministic collisions | ⚠️ | A list of keywords together with the `dart:core` types (parser/utils/dart_keywords.dart) gives the suffix `value`/`enum` and a doc comment with the original name (type_utils.dart:L191-240). Duplicates get a numeric suffix in traversal order (L1563-1569) |
| R5.3 grouping by tag | ✅ | The first tag defines the client; there are `fallback_client` and `merge_clients`; dirty tags go through `toPascal`/`toSnake`. Empty tags break ([#306](https://github.com/Carapacik/swagger_parser/issues/306), [#271](https://github.com/Carapacik/swagger_parser/issues/271)) |
| R5.4 inline schemas and inline enums | ⚠️ | `${Path}RequestBody`, `${Method}${Path}Response` (L649, L453); enums get the name `Parent+Prop`. Enums are deduplicated by name+values, objects are not ([#448](https://github.com/Carapacik/swagger_parser/issues/448)). There is no override ([#379](https://github.com/Carapacik/swagger_parser/issues/379), [#389](https://github.com/Carapacik/swagger_parser/issues/389)) |
| R6.1 required × nullable matrix | ❌ | `nullable: false => !isRequired` (L1606-1610): optional is always nullable. Request and response are not separated. If in an object without `required` at least one property has `allOf`, **all** become required (L775-777, L821-823; [#460](https://github.com/Carapacik/swagger_parser/issues/460)) (code) |
| R6.2 type mapping | ⚠️ | `date` and `date-time` → `DateTime` (date is serialized as date-time, [#463](https://github.com/Carapacik/swagger_parser/issues/463)); `int64` → `int`; `number` → `num`; `uuid` → `String`; `object` → `dynamic`; `additionalProperties` → `Map<String,T>` ✅. Customization only via `field_parsers` |
| R6.3 `allOf` | ⚠️ | Merging exists (1.23.0, 1.33.0); nullable with a single `$ref` fixed in 1.44.0. Open: [#239](https://github.com/Carapacik/swagger_parser/issues/239), [#358](https://github.com/Carapacik/swagger_parser/issues/358), [#204](https://github.com/Carapacik/swagger_parser/issues/204), [#381](https://github.com/Carapacik/swagger_parser/issues/381) |
| R6.4 generic envelopes | ❌ | [#218](https://github.com/Carapacik/swagger_parser/issues/218) |
| R6.5 extra fields / missing-field error | ⚠️ | Extra fields are ignored (json_serializable default). `@JsonSerializable()` is generated without `checked: true`, so a missing field gives a bare `TypeError` without a path (not verified at runtime) |
| R6.6 `==`, `copyWith`, `toString` | ⚠️ | Present via freezed and dart_mappable; not in json_serializable |
| R6.7 constraints | ⚠️ | `generate_validator`, freezed only |
| R7.1–R7.3 tri-state PATCH | ❌ | Only the global `include_if_null`; [#307](https://github.com/Carapacik/swagger_parser/issues/307) |
| **R8.1** raw enum value | ❌ | **Lost** (code, see 1.5) |
| **R8.2** unknown cannot be sent | ❌ | `"$unknown"` / `"unknown"` is sent, or `StateError` is thrown (code, see 1.5) |
| R8.3 string, numeric, boolean enums | ⚠️ | string, int and num are there; bool enum breaks ([#342](https://github.com/Carapacik/swagger_parser/issues/342)); invalid names are replaced with `value0`, `valueNull` |
| R8.4 `x-enum-varnames` / `x-enum-descriptions` | ⚠️ | Only `x-enumNames` (L71, L918). `x-enum-varnames` is absent ([#285](https://github.com/Carapacik/swagger_parser/issues/285)) |
| R9.1 discriminator → closed hierarchy + unknown | ⚠️ | `sealed class` + `tryDeserialize` by discriminator value. Without `fallback_union` an unknown value gives `FormatException` (json_serializable_dto_template.dart:L204-251). With `fallback_union` the raw JSON is kept in json_serializable and dart_mappable (L385-407), while in freezed the fallback is empty: `const factory X.unknown()` (freezed_dto_template.dart:L220-227) (code) |
| R9.2 `oneOf` without discriminator | ⚠️ | Sequential `try { return V.fromJson(json); } catch (_) {}` (L254-290): silently guesses the first one that parsed. No error / raw modes |
| R9.3 mixed primitives | ❌ | `tryDeserialize(Map<String, dynamic>)` accepts only objects (L145, L280) (code) |
| R10.1 own client, `baseUrl` not overwritten | ✅ | `factory X(Dio dio, {String? baseUrl})`, `@RestApi()` without baseUrl, `servers` is ignored |
| R10.2 HTTP errors go through `onError` | ✅ | Standard retrofit/Dio behaviour (DioException) |
| R10.3 path / query / header / cookie, styles | ⚠️ | Cookies silently disappear (L288-295). `style`, `explode`, `deepObject` are not read at all (grep is empty), so Dio's default `ListFormat` works (code) |
| R10.4 bodies | ⚠️ | JSON ✅, multipart ✅ (`@MultiPart`, `@Part`, File/MultipartFile), urlencoded ✅. For OAS3 bodies other than multipart/urlencoded, the **chosen content-type is not passed**: `resultContentType` stays the default (L346-362, L727), so `application/octet-stream` or `merge-patch+json` go with the `application/json` header (code). Nested object in multipart: [#444](https://github.com/Carapacik/swagger_parser/issues/444) |
| R10.5 cancellation / progress / headers / metadata / operationId | ⚠️ | `@Extras` and `@DioOptions` are enabled globally; `add_openapi_metadata` puts operationId into extras only as the default value of a parameter (dart_retrofit_client_template.dart:L225-256) |
| R10.6 several 2xx, 204, status and headers, non-JSON | ⚠️ | Only the first 2xx ([#385](https://github.com/Carapacik/swagger_parser/issues/385)); `original_http_response` gives `HttpResponse<T>`; any `format: binary` becomes `Stream<Uint8List|String>` (L136-152) |
| R10.7 abstract API | ✅ | An abstract retrofit class per tag; mocked via `implements`. The root client is concrete |
| R10.8 security as metadata | ❌ | `securitySchemes` are not read ([#388](https://github.com/Carapacik/swagger_parser/issues/388)) |
| R10.9 servers | ❌ | Ignored (L641) |
| R11.1–R11.7 typed errors | ❌ | 4xx/5xx/default schemas are ignored ([#367](https://github.com/Carapacik/swagger_parser/issues/367)) |
| R12.x SSE | ⚠️/❌ | "SSE" here means `@DioResponseType(ResponseType.stream)` → `Stream<String>` or `Stream<Uint8List>`. There is no parsing of the WHATWG protocol and no typed events. The trigger is `format: binary`, not `text/event-stream` (README; [#432](https://github.com/Carapacik/swagger_parser/issues/432)) |
| R13.1 determinism | ⚠️ | No timestamps, imports via `SplayTreeSet`. The suffixes `Name2` and `Object0` depend on the traversal order; the output is not formatted |
| R13.2 cleanliness under lints | ❌ | `ignore_for_file: type=lint …` (base_utils.dart:L84) |
| R13.3 minimal runtime | ⚠️ | runtime: dio + retrofit + json_annotation (+ freezed_annotation or dart_mappable); dev: build_runner, retrofit_generator, json_serializable (+ freezed). There is no own runtime package |
| R13.4 doc comments, `@Deprecated` | ✅/⚠️ | Descriptions and `@Deprecated` on methods and parameters are present; for fields only in freezed and dart_mappable |
| R13.5 output size | ✅ | There are no test or doc stubs |
| R14.1 / R14.2 evolution | ❌/⚠️ | There is no changelog report. `$unknown` and the fallback help with R14.2 |
| R15.1 CLI and API | ✅ | CLI, Dart API, Web UI. The output then goes through build_runner |
| R15.2 config with JSON Schema | ❌ | YAML with manual casts and `ConfigException`; the README lags behind the code |
| R15.3 tests | ⚠️ | e2e golden tests (`test/e2e/tests/*/expected_files`, 27 cases). CI **does not compile or analyze** the generated code (.github/workflows/tests.yml): `dart analyze` runs only over the package's own `lib/` |
| R15.4 semver | ⚠️ | Behaviour changes in minor versions: streaming in 1.42.0 ([#432](https://github.com/Carapacik/swagger_parser/issues/432)), enum regression in 1.43.0 ([#446](https://github.com/Carapacik/swagger_parser/issues/446)) |

## 1.5 Verification of the author's claims

### "swagger_parser loses the raw value of an unknown enum" (R8.1) — **CONFIRMED (code)**

**Generation path** (`unknown_enum_value: true` by default, SP:swp_config.dart:L28):

1. json_serializable and freezed use a shared enum template. [SP:lib/src/generator/templates/dart_enum_dto_template.dart](https://github.com/Carapacik/swagger_parser/blob/be6df7c11205d5e7dacf8cace6b07c7c5885c3fc/swagger_parser/lib/src/generator/templates/dart_enum_dto_template.dart):
   * L131-134 adds the constant `$unknown(null);`. Its `json` value is `null`, i.e. there is no place for the raw string.
   * L136-142: `factory X.fromJson(T json) => values.firstWhere((e) => e.json == json, orElse: () => $unknown);`. The incoming `json` is discarded after this.
   * L194-206 (`enums_to_json: true`): `toJson()` on `$unknown` throws `StateError(...)`.
   * L208-209: `toString()` for `$unknown` returns `super.toString()`, i.e. `"X.$unknown"`. The raw value is not even in the logs.
2. Annotation of the model fields (SP:dart_json_serializable_dto_template.dart:L438-461 `_jsonKey`) does **not** generate `@JsonKey(unknownEnumValue: …)`. The fallback works only because json_serializable 6.14.1 checks `JsonHelper` (the `fromJson` constructor) **before** `EnumHelper` (`json_serializable/lib/src/settings.dart`: `_typeHelpers` before `_coreHelpers`; `type_helpers/json_helper.dart` looks for `constructors.where((ce) => ce.name == 'fromJson')`). So the field is decoded as `X.fromJson(json['f'] as String)`, and the result is `$unknown` without the raw value.
3. **Encoding (R8.2), code.** When `enums_to_json: false` (default), there is no `toJson` in the enum, `JsonHelper` skips the type, and serialization is done by `EnumHelper` through `_$XEnumMap`. For `$unknown`, which has no `@JsonValue`, json_serializable takes the **field name** (`enum_utils.dart` `_generateEntry` → `encodedFieldName(fieldRename, field.name)`). So the map contains `X.$unknown: r'$unknown'`, and a model with an unknown value sent back to the server will send the string **`"$unknown"`**. With `enums_to_json: true` we get `StateError`. Separately, [#454](https://github.com/Carapacik/swagger_parser/issues/454) fixed this: such a `toJson()` did not compile when `unknown_enum_value: false`.
4. **dart_mappable** (the same file, L60-113): the value `@MappableValue('unknown') unknown` and `@MappableEnum(defaultValue: X.unknown)` are added. An unknown value is decoded into `unknown` without a raw string, and when encoding it goes to the server as `"unknown"`. For an integer enum it is literally the string literal `'unknown'` (L151-163).
5. How they came to this design: [#106](https://github.com/Carapacik/swagger_parser/issues/106). A collaborator proposed `@JsonValue(null) $unknown`, and `unknownEnumValue: null` in json_serializable did not work at the time.

**Consequences for the new generator.** In a Dart `enum` it is impossible to keep the raw value, because the constants are static. A different type is needed: a sealed class or an extension type with a variant `Unknown(String raw)`, or a wrapper class `{X? known; Object raw}` (open decision 7). R8.2 requires that the request type has no unknown variant, or that serialization on it fails at the type level, not at runtime.

### Additional claims checked along the way

* "Union fallback in SP keeps the raw JSON" — **partly (code).** True for json_serializable and dart_mappable (`json` getter, L385-407 and dart_mappable_dto_template.dart:L574, L788). Not for freezed: an empty `const factory X.unknown()`.
* "SP returns `ModelNameUnion` instead of `…Sealed`" — fixed in 1.39.1 ([#393](https://github.com/Carapacik/swagger_parser/issues/393)).

## 1.6 Known problems (issue tracker + code) and lessons

The most discussed (reactions ×2 + comments): #257, #5, #29, #25, #303, #225, #121, #251, #144, #340, #106, #78, #380, #279, #131, #444, #358. Below, grouped by topic.

| # | Essence | Lesson for a new tool |
|---|---|---|
| [#303](https://github.com/Carapacik/swagger_parser/issues/303) (8 reactions, open), [#251](https://github.com/Carapacik/swagger_parser/issues/251), [#358](https://github.com/Carapacik/swagger_parser/issues/358), [#460](https://github.com/Carapacik/swagger_parser/issues/460), [#443](https://github.com/Carapacik/swagger_parser/issues/443), [#440](https://github.com/Carapacik/swagger_parser/issues/440), [#363](https://github.com/Carapacik/swagger_parser/issues/363), [#307](https://github.com/Carapacik/swagger_parser/issues/307), [#257](https://github.com/Carapacik/swagger_parser/issues/257) (12 reactions) | Nullable `$ref` next to `nullable: true`; `allOf:[$ref]+nullable` (the ASP.NET and NestJS pattern); "one `allOf` makes all fields required"; optional is generated as required or the other way round | An explicit R6.1 matrix as a separate, tested module. A normalizer (R2.1) with rules `allof-single-ref-nullable` and `sibling-nullable-on-ref` with a report. Golden tests for the NestJS, FastAPI, Swashbuckle and Microsoft.AspNetCore.OpenApi patterns |
| [#374](https://github.com/Carapacik/swagger_parser/issues/374) (7 comments, still present in 1.42.0), [#442](https://github.com/Carapacik/swagger_parser/issues/442), [#375](https://github.com/Carapacik/swagger_parser/issues/375), [#321](https://github.com/Carapacik/swagger_parser/issues/321), [#296](https://github.com/Carapacik/swagger_parser/issues/296), [#110](https://github.com/Carapacik/swagger_parser/issues/110) | `type 'List<Object?>' is not a subtype of 'Map<String,dynamic>'` and similar. **Confirmed in code**: path-level `parameters` (List), `summary` or `description` (String) are cast to `Map` before the key is checked (open_api_parser.dart:L634 vs L641) | A typed specification model with tolerant parsing. An error in one operation gives a diagnostic with a JSON pointer and skips that operation, rather than failing the whole generation (R2.2, R2.5) |
| [#120](https://github.com/Carapacik/swagger_parser/issues/120), [#366](https://github.com/Carapacik/swagger_parser/issues/366), [#423](https://github.com/Carapacik/swagger_parser/issues/423) | No external `$ref`; cycles give a StackOverflow | A separate resolver: URI + JSON Pointer (with `~0`/`~1`), a document cache, cycle detection, lazy traversal (R1.2) |
| [#121](https://github.com/Carapacik/swagger_parser/issues/121) (5 reactions), [#342](https://github.com/Carapacik/swagger_parser/issues/342) | 3.1-style enum (`oneOf` + `const` + `title`) and bool-`const` are not supported | Include in the 3.1 support matrix (R15.5): `const`, `type` arrays, `oneOf[const]` as an enum with names from `title` |
| Code + [#106](https://github.com/Carapacik/swagger_parser/issues/106), [#351](https://github.com/Carapacik/swagger_parser/issues/351), [#454](https://github.com/Carapacik/swagger_parser/issues/454), [#446](https://github.com/Carapacik/swagger_parser/issues/446), [#462](https://github.com/Carapacik/swagger_parser/issues/462), [#414](https://github.com/Carapacik/swagger_parser/issues/414), [#441](https://github.com/Carapacik/swagger_parser/issues/441) | The raw enum value is lost; `$unknown` can be sent; regressions in `toString`/`toJson`/query-parameter defaults | A separate type for unknown with the raw value (R8.1). A request type without unknown (R8.2). One enum implementation instead of three serializer branches |
| [#385](https://github.com/Carapacik/swagger_parser/issues/385), [#367](https://github.com/Carapacik/swagger_parser/issues/367), [#273](https://github.com/Carapacik/swagger_parser/issues/273), [#312](https://github.com/Carapacik/swagger_parser/issues/312) | No several 2xx (on 204 it fails with `!`), error schemas are ignored, the type does not depend on the status | Return a union of responses (R10.6) and typed errors (R11). Retrofit here is an architectural ceiling: one type per method, a CallAdapter only as a workaround |
| [#194](https://github.com/Carapacik/swagger_parser/issues/194), [#409](https://github.com/Carapacik/swagger_parser/issues/409), [#429](https://github.com/Carapacik/swagger_parser/issues/429), [#448](https://github.com/Carapacik/swagger_parser/issues/448), [#379](https://github.com/Carapacik/swagger_parser/issues/379), [#389](https://github.com/Carapacik/swagger_parser/issues/389), [#140](https://github.com/Carapacik/swagger_parser/issues/140), [#235](https://github.com/Carapacik/swagger_parser/issues/235) | Clash with `Options` from dio; keyword fields in sealed classes lose `@JsonKey`; the corrector turned **API paths** into PascalCase (text substitution); duplicates `AspectRatio2`; long names without override | Renaming at the symbol-table level, not regex over text (SP:open_api_corrector.dart:L59-260). Reserved names must include the symbols of runtime imports, or use `import … as`. Deduplication of structurally identical inline schemas. Name override (R5.4) |
| [#380](https://github.com/Carapacik/swagger_parser/issues/380), [#411](https://github.com/Carapacik/swagger_parser/issues/411), [#462](https://github.com/Carapacik/swagger_parser/issues/462), [#454](https://github.com/Carapacik/swagger_parser/issues/454), [#408](https://github.com/Carapacik/swagger_parser/issues/408), [#326](https://github.com/Carapacik/swagger_parser/issues/326) | The generated code does not compile, and this is seen only after `build_runner` | In CI, compile and analyze the golden output plus runtime decoding tests (R15.3). Generate ready code so that the error is caught immediately, not in the second phase |
| [#432](https://github.com/Carapacik/swagger_parser/issues/432) | In minor 1.42.0 the binary response changed type to `Stream<String>`, and this cannot be turned off | A change of output is a breaking change (R15.4); introduce new modes as opt-in |
| [#340](https://github.com/Carapacik/swagger_parser/issues/340) (11 comments), [#444](https://github.com/Carapacik/swagger_parser/issues/444), [#249](https://github.com/Carapacik/swagger_parser/issues/249), [#272](https://github.com/Carapacik/swagger_parser/issues/272), [#154](https://github.com/Carapacik/swagger_parser/issues/154), [#144](https://github.com/Carapacik/swagger_parser/issues/144) | Multipart: `List<List<MultipartFile>>`, nested objects, nullable files, `$ref` | A separate model of multipart parts with `encoding` (the part's content-type), and objects in parts serialized as JSON (R10.4) |
| Code (L346-362, L727) | The content-type of an OAS3 body, other than multipart and urlencoded, does not reach the request | A test for each media type from the R10.4 matrix |
| Code (L288-295) | Cookie parameters are silently dropped | R2.5: either support them, or an error or warning with a code and an override |
| [#213](https://github.com/Carapacik/swagger_parser/issues/213), [#463](https://github.com/Carapacik/swagger_parser/issues/463), [#16](https://github.com/Carapacik/swagger_parser/issues/16) | `date` is serialized as date-time; the time zone offset is lost; there is no `x-dart-type` | A separate `Date` type for `format: date`, configurable mapping `format`→type (R6.2), and `x-dart-type` in the `x-` registry |
| [#218](https://github.com/Carapacik/swagger_parser/issues/218), [#415](https://github.com/Carapacik/swagger_parser/issues/415) | No generics and no shared interfaces | R6.4 (envelopes and pagination) |
| [#405](https://github.com/Carapacik/swagger_parser/issues/405) | Several `schemes` overwrite the shared `export.dart` | Check that the output paths of different configs do not intersect, and emit a diagnostic (R1.3) |
| [#279](https://github.com/Carapacik/swagger_parser/issues/279), [#302](https://github.com/Carapacik/swagger_parser/issues/302), [#355](https://github.com/Carapacik/swagger_parser/issues/355), [#369](https://github.com/Carapacik/swagger_parser/issues/369) | Users ask to exclude models and filter the output; tree-shaking appeared late and with bugs | Build filters and tree-shaking into the core from day one (R4.1, R4.2) |
| [#232](https://github.com/Carapacik/swagger_parser/issues/232) | The request body is a named parameter `body` | The body as a positional parameter, the rest as named (API ergonomics) |
| README and code | `put_in_folder` is described in the README, although it is absent from the code; `generate_validator` is not documented | Generate config documentation from JSON Schema (R15.2, R15.5) |

Separately about **build_runner**: no issues specifically about slowness were found in the trackers. The pain is different: the gap between the two phases (#380, #411 — the error is visible only after build_runner), the mandatory order of builders in `build.yaml` for freezed, dart_mappable and retrofit (README), and workarounds for retrofit limitations. An example of a workaround: a parameter containing `value` is renamed to `value_` via [retrofit#661](https://github.com/trevorwang/retrofit.dart/issues/661) (SP:dart_retrofit_client_template.dart:L277-282, code).

## 1.7 What to borrow

1. **`schemes:` with inheritance of root parameters** (config_processor.dart:L44-87): a simple and clear way to set several specifications (R1.3).
2. **`replacement_rules` and `replacement_rules_for_raw_schema`**: ordered regex rules, separately for raw names and for Dart names (R5.1, R2.1). Apply them to symbols, not to text, and show in the report which rule fired.
3. **Filters**: `include_tags`/`exclude_tags` case-insensitive, glob `*`/`**` for paths (path_match.dart), `fallback_client` for operations without a tag, `merge_clients` (R4.1, R5.3).
4. **`fallback_union` with raw JSON** (`json` getter) for an unknown discriminator (R9.1). Make this the default behaviour, for all representations.
5. **`add_openapi_metadata`**: a static metadata constant for each operation (tags, operationId, externalDocs). Improve: always add it to `RequestOptions.extra`, rather than substitute it as the parameter default (R10.5).
6. **Doc comment on a forced rename**: "The name has been replaced because it contains a keyword. Original name: `x`." (type_utils.dart:L191-240). This is cheap traceability, and it is worth supplementing with a diagnostic code (R2.2).
7. **`$valuesDefined`**: the list of enum values without unknown, convenient for UI selectors.
8. **`infer_required_from_nullable`** as a named normalizer rule for ASP.NET and NestJS, but with a record of each firing in the report (R2.1).
9. **`field_parsers`**: injection of a `JsonConverter` for a type (R6.2). Addressing is better done by `format`, `x-` or override than by the Dart type.
10. **`generate_validator`**: constraints as `static const` plus `validate()` (R6.7, optional).
11. **Test infrastructure**: `test/e2e/tests/<case>/{openapi.yaml, expected_files/}` and the flag `generateExpectedFiles` for regenerating golden files (e2e_util.dart). Add compilation and analysis.
12. **Web playground** (`swagger_parser_pages`): a core without `dart:io` allows trying generation in the browser, and this is a strong marketing move.
13. Statistics after generation (number of files, lines, time) and a banner.

---

# 2. swagger_dart_code_generator (SDCG)

## 2.1 Overview

| Parameter | Value | Source |
|---|---|---|
| Latest version | **4.1.1**, published 2025-12-11. Previous: 4.0.0 and 3.0.4 (2025-09-16), 4.0.1 and 4.0.2 (2025-09-29), 4.1.0 (2025-11-06) | pub.dev API |
| Pub points / likes / downloads in the last 30 days | **145/160** (−5: the CHANGELOG has no entry for 4.1.1; −10: web) · 331 likes · 62 634 | pub.dev `/score`, `/metrics` |
| GitHub | 303★, 161 forks, Apache-2.0, created 2020-09-08 | `gh repo view` |
| Issues / PRs | 55 open issues out of 398; **13 open PRs** (from 2026-01 to 2026-09, none merged) | `gh issue/pr list` |
| Activity | Last commit and release **2025-12-11**, 10 months of silence. Releases come in batches from a single maintainer (Vovanella95); [#796 "Future of this project"](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/796) (8 reactions) without a single reply | `gh api …/commits` |
| Code size | ≈7.5 thousand lines; `swagger_models_generator.dart` has 2033 lines, `swagger_requests_generator.dart` — 1421 | `wc -l` |

Conclusion: popular by likes and downloads (a legacy base), but **effectively unmaintained** since December 2025. The CHANGELOG is uninformative: "Various fixes", "Fixed some border cases".

## 2.2 Architecture

* **Launched only as a `build_runner` builder** (SDCG:build.yaml: `build_extensions "$lib$": [...]`, `build_to: source`, `runs_before: [chopper_generator, json_serializable]`). There is no CLI. The config is set in `build.yaml` → `targets.$default.builders.swagger_dart_code_generator.options` and deserialized through json_serializable (`GeneratorOptions`, SDCG:lib/src/models/generator_options.dart).
* **Input.** All `*.swagger`, `*.json`, `*.yaml` from `input_folder` (SDCG:lib/swagger_dart_code_generator.dart:L19, L36-40). `buildExtensions` is computed **by listing the file system** in the builder's constructor (L60-119), and the files are read through `dart:io File(...)`, bypassing `BuildStep.readAsString` (L166-167). Because of this build_runner does not see the real dependencies: cache problems ([#789](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/789)), Pub Workspaces ([#852](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/852)), crashes on `.DS_Store` ([#563](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/563)) (code).
* **`input_urls`** are downloaded **on every build** (`http.get` without headers and without a status check) into `input_folder` (L149-157, L397-401) (code).
* **Output per specification:** `<name>.swagger.dart` (the Chopper service, models, converter, all in one file), `<name>.enums.swagger.dart`, `<name>.metadata.swagger.dart`, optionally `<name>.models.swagger.dart` (`separate_models`). Plus the shared `client_index.dart` and `client_mapping.dart`. Then `chopper_generator` and `json_serializable` generate `.chopper.dart` and `.g.dart`.
* **HTTP layer is Chopper.** `abstract class XService extends ChopperService` with `static create({ChopperClient? client, http.Client? httpClient, Authenticator?, ErrorConverter?, Converter?, Uri? baseUrl, List<Interceptor>? interceptors})`. Public methods are concrete wrappers over private annotated `_method(...)` (SDCG:example/lib/swagger_generated_code/pet_service_json.swagger.dart:L29-79). It returns `Future<chopper.Response<T>>`; with `custom_return_type` you can set your own type.
* **Serialization.** json_serializable with `explicitToJson: true`. A global **runtime registry** of factories `generatedMapping` (`Map<Type, JsonFactory>`): each method runs `generatedMapping.putIfAbsent(Pet, () => Pet.fromJsonFactory)` (SDCG:swagger_requests_generator.dart:L474). Top-level `$jsonDecoder` and `$CustomJsonDecoder` (SDCG:swagger_additions_generator.dart:L154-232). `_decodeList` silently drops `null` elements (L204).
* **Metadata.** Each private method receives `@chopper.Tag() SwaggerMetaData swaggerMetaData = const SwaggerMetaData(summary, description, operationId, consumes, produces, security, tags, deprecated)` (SDCG:swagger_meta_data_generator.dart; example above). Through `Request.tag` the metadata is available to interceptors. It appeared in September 2025 ([PR #811](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/pull/811)).
* **Formatting** via `dart_style` with the `page_width` option; if formatting fails, only a warning is printed (L135-144, L317-327). Header `// ignore_for_file: type=lint`.
* **Models** contain `==` and `hashCode` (DeepCollectionEquality), `toString() => jsonEncode(this)`, and also an extension `copyWith` and **`copyWithWrapped`** with `Wrapped<T>` for an explicit `null` (SDCG:swagger_additions_generator.dart:L149-151).

## 2.3 Config as prior art

The full list from `GeneratorOptions` (generator_options.dart:L9-41). The README table is incomplete: it has no `model_postfix`, `custom_return_type`, `import_paths`, `page_width`, `generate_to_json_for`, `include_null_query_vars`, `urlencoded_file_type`, `custom_annotations`, `default_header_values_map`. `example/build.yaml` uses a nonexistent option `use_default_null_for_lists`, which the parser **silently ignores** ([#744](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/744)).

| Option (default) | What it does | Prior art for | Assessment |
|---|---|---|---|
| `input_folder`, `output_folder`, `input_urls: [{url, file_name}]` | input and output | R1.1, R1.3 | one configuration for all files ([#785](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/785)) |
| **`overriden_models: [{file_name, import_url, overriden_models: [..]}]`** | replace generated models with own classes from an import, separately for each spec file | **R3.1** (type override) | the mechanism closest to an override file |
| **`response_override_value_map: [{url, method, overridden_value}]`** | set the Dart response type for a path+method | **R3.1** (operation addressing) | the type is a raw Dart string, not checked |
| `nullable_models: [..]` | in the listed models all properties are nullable | R3.1 (`nullable`) | granularity is the model, not the property |
| `classes_with_nullabe_lists: [regex]` (yes, with a typo in the name) | lists in these classes default to `null`, not `[]` | R6.1 | — |
| `default_values_map: [{type_name, default_value}]` | `defaultValue:` for all fields of this type | (anti-pattern for R2.5 / R6.5) | silently substitutes `''` for a missing value (see `Pet.name` in the example) |
| **`scalars: {format: {type, deserialize, serialize}}`** + `import_paths` | mapping of `format` → own type with (de)serialization functions (for example `uuid` → `Uuid.parse`) | **R6.2** | a good pattern; a regression in 4.1.0 for nullable ([#840](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/840)) |
| `custom_annotations: [{type_name, swagger_key}]` | if a property has an `x-…` key, `@TypeName(value)` is generated | R6.7, `x-` registry | — |
| `include_paths` / `exclude_paths` | **regex** on the path (swagger_requests_generator.dart:L141-147) | R4.1 | no tags or operationId; schemas are not filtered (R4.2 ❌) |
| `use_path_for_request_names` (`true`) | method name from path+method; `false` takes `operationId` (L1044-1047) | R5.1 | the default gives names like `petPetIdGet` |
| `cut_from_model_names` (regex), `model_postfix` | cut a repeated prefix or add a suffix to models | R5.1, **R4.3** | — |
| `enums_case_sensitive` (`true`) | case-insensitive matching of enums | R8 | — |
| `with_base_url` (`true`), `add_base_path_to_requests` | bake `servers[0]` / `basePath` into `create()` | R10.1, R10.9 | the URL is baked in by default |
| `with_converter` (`true`), `build_only_models` (`false`), `separate_models` (`false`) | composition of the output | R13.5 | — |
| `ignore_headers`, `additional_headers: [..]`, `default_header_values_map`, `use_required_attribute_for_headers` | header control | R10.3, R10.5 | — |
| `include_if_null` (`null`) | global `includeIfNull` | R7.3 | global ([#806](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/806)) |
| `include_null_query_vars` (`false`) | `includeNullQueryVars` in Chopper | R10.3 | — |
| `generate_first_succeed_response` (`true`) | several 2xx: the first one or `dynamic` (L1305) | R10.6 | an explicit choice; good that it is visible |
| `multipart_file_type` (`List<int>`), `urlencoded_file_type` (`Map<String,String>`) | types for multipart and urlencoded | R10.4 | — |
| `custom_return_type` | `MyType<T>` instead of `Future<chopper.Response<T>>` | R11.2 (Result) | — |
| `generate_to_json_for: [..]` | `toJson` only for the listed models | R13.5 | — |
| `override_equals_and_hashcode` (`true`), `override_to_string` (`true`) | `==`, `hashCode`, `toString` | **R6.6** | — |
| `page_width` | line width for `dart_style` | **R13.2** | — |

## 2.4 Requirements coverage table

| Requirement | Status | Evidence / comment |
|---|---|---|
| R0.1 OAS 3.0 and 3.1, pure Dart | ⚠️ | Swagger 2.0 and OAS 3. From 3.1 only an array `type` containing `"null"` is handled (SDCG:swagger_schema.dart:L115-119). `oneOf:[{type:null},{$ref}]` is not supported ([#833](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/833)). The output is pure Dart with `http` and Chopper |
| R1.1 input | ⚠️ | Local files ✅. `input_urls` are downloaded on every build, without authorization (code) |
| R1.2 `$ref` | ❌ | `split('/').last` (string_extension.dart:L32-34; `definedParameters[par.ref.split('/').last]`). There are no external files |
| R1.3 multiple specifications | ⚠️ | Several files in one `input_folder`, but the config is shared by all ([#785](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/785)) |
| R2.1–R2.5 normalization and diagnostics | ❌ | Only `print` when formatting fails. Silent behavior: cookies are dropped, `default_values_map`, `oneOf` becomes `dynamic` |
| R3.1 overrides | ⚠️ | `overriden_models`, `response_override_value_map`, `nullable_models`, `scalars`. Addressing is not via JSON pointer; there are no warnings about deprecated overrides (R3.2 ❌) |
| R4.1 filters | ⚠️ | Only regex on the path (include and exclude) |
| R4.2 tree-shaking | ❌ | All component schemas are generated; the path filter applies only to inline responses (swagger_models_generator.dart:L209-220) |
| R4.3 safe coexistence | ❌ | A global mutable `generatedMapping` and top-level `$jsonDecoder` (code). Name collisions with Chopper names (`Query`: [#343](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/343)). `model_postfix` helps partially |
| R5.1 operation names | ⚠️ | By default from path+method; `operationId` optionally; regex `cut_from_model_names` for models |
| R5.2 collisions | ⚠️ | `exceptionWords` and the `$` prefix for duplicate enum values (enum_model.dart:L66-104). Duplicate methods: [#720](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/720) |
| R5.3 grouping by tag | ❌ | One service per spec file ([#739](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/739)) |
| R5.4 inline schemas | ⚠️ | Names like `X$Item`, `Path$Method$Response` (with the `$` sign). No override |
| R6.1 required × nullable matrix | ❌ | `isNullable = shouldBeNullable \|\| nullableModels \|\| !required` (swagger_models_generator.dart:L684-693): optional ⇒ nullable. required+nullable in the constructor is **not** required (L1663-1675). All method parameters are nullable ([#747](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/747)). Positive: `readOnly`/`writeOnly` → nullable (swagger_schema.dart:L115-119) |
| R6.2 type mapping | ⚠️ | `int64` → **`num`** (constants.dart:L64-76; loss of precision on web, [#285](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/285)). `format: date` is serialized as `yyyy-MM-dd` via `_dateToJson` ✅ (additions_generator.dart:L136-147). `additionalProperties` always gives `Map<String,dynamic>`, the value type is lost (swagger_schema.dart:L151, models_generator.dart:L1314-1315). `scalars` ✅ |
| R6.3 `allOf` | ⚠️ | Properties are merged into a flat model (L1929-1990); a single `$ref` becomes a reference to the type (L931-946). Bugs [#721](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/721), [#853](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/853) |
| R6.4 generics | ❌ | There is only an unmerged PR [#846](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/pull/846) |
| R6.5 extra and missing fields | ⚠️/❌ | Extra fields are ignored. Missing required ones often **silently** get a `defaultValue` (`''`, `[]`) |
| R6.6 `==`, `copyWith`, `toString` | ✅ | — |
| R6.7 constraints | ❌ | Only through `custom_annotations` |
| R7.1–R7.3 tri-state | ❌/⚠️ | `copyWithWrapped(Wrapped<T>?)` distinguishes "not passed" from "null" only in `copyWith`. Serialization is controlled by the global `includeIfNull` ([#768](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/768), [#806](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/806)) |
| **R8.1** raw enum value | ❌ | `swaggerGeneratedUnknown(null)` (enum_model.dart:L57-64). `…FromJson` returns `?? swaggerGeneratedUnknown` (L132). **In nullable fields an unknown value becomes `null`** (`…NullableFromJson` → `?? defaultValue`, L111-112, L134-142) (code) |
| R8.2 unknown is not sent | ⚠️ | `…ToJson` gives `value`, that is, `null`. `…ListToJson` calls `e.value!` and crashes (L148, L161) |
| R8.3 enum types | ⚠️ | Only string and int: `isInteger` is determined by the first value (swagger_enums_generator.dart:L285-286). Names are lowercased ([#743](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/743)) |
| R8.4 `x-enum-*` | ⚠️ | `x-enumNames`, `x-enum-varnames`, `x-ms-enum` (constants.dart:L95-96, swagger_schema.dart:L87, L140). There are no descriptions |
| R9.1–R9.3 polymorphism | ❌ | Discriminator is not supported ([#563](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/563)). A top-level `anyOf` becomes `typedef X = Map<String,dynamic>` or `Object` (L71-77). A property with `anyOf`/`oneOf` with ≥2 non-null variants becomes `dynamic` (L784-830) |
| R10.1 own client | ⚠️ | `create(client: myChopperClient)` takes the user's client. Without it the generator itself creates a `ChopperClient` with the URL from the spec baked in (`with_base_url: true`) |
| R10.2 errors go through the client's path | n/a / ⚠️ | Chopper does not throw on non-2xx: `Response.error` together with the global `ErrorConverter` |
| R10.3 parameters | ⚠️ | path/query/header ✅. Cookies are **silently filtered out** (requests_generator.dart:L740). `collectionFormat` is parsed but not used anywhere; style and explode are not supported |
| R10.4 bodies | ⚠️ | JSON, multipart (`@Part`/`@PartFile`), urlencoded. There is no typing of binary responses (unmerged PR [#854](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/pull/854)). Multipart for Swagger 2: [#726](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/726) (12 comments) |
| R10.5 metadata, cancellation | ⚠️ | **operationId, tags and security metadata are in every request** ✅. There is no cancellation or progress ([#843](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/843) about `@AbortTrigger`) |
| R10.6 several 2xx, 204, status | ⚠️ | `chopper.Response<T>` gives the status and headers; 204 with an empty body returns `null` (additions_generator.dart:L210-214). Several 2xx: the first one or `dynamic` |
| R10.7 abstract API | ⚠️ | An abstract `ChopperService`, but the public methods are concrete. Mocked through `implements` |
| R10.8 security as metadata | ✅/⚠️ | Security scheme names end up in `SwaggerMetaData.security` |
| R10.9 servers | ❌ | Only the first URL is taken |
| R11 typed errors | ❌ | — |
| R12 SSE | ❌ | — |
| R13.1 determinism | ✅/⚠️ | `dart_style` + order from the spec. Complaints about "different code from the same spec" ([#770](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/770)) are actually about changes between versions |
| R13.2 lints, formatting | ⚠️ | Formatting is present, but lints are suppressed by `type=lint` |
| R13.3 runtime dependencies | ⚠️ | runtime: chopper, json_annotation, http, collection. The generator itself pulls `build`, `dart_style`, `code_builder` into the user's dev dependency graph, hence the conflicts ([#812](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/812), [#817](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/817), [#800](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/800)) |
| R13.4 documentation in code | ⚠️ | `///@param …`; `@deprecated` without a message |
| R13.5 output size | ⚠️ | There are no stubs, but one huge build per specification without tree-shaking |
| R14 evolution | ❌ | — |
| R15.1 CLI and API | ⚠️ | Only a builder for build_runner |
| R15.2 config from JSON Schema | ❌ | Unknown keys are silently ignored ([#744](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/744)); config errors look like `type 'YamlMap' is not a subtype of 'bool?'` ([#208](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/208), 25 comments) and `'Null' is not a subtype of 'String'` ([#798](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/798)) |
| R15.3 tests | ⚠️ | 8 test files with string comparisons of fragments; the example is regenerated by hand |
| R15.4 semver | ⚠️ | The CHANGELOG has no entry for 4.1.1; regressions in minor releases ([#840](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/840)); 4.1.1 reverted PR #830 |

## 2.5 Verification of the author's claims

* R8.1 in the author's wording concerns swagger_parser and tonik, not SDCG. But SDCG **also loses the raw value (code)**. Worse: in nullable fields an unknown value becomes `null` (enum_model.dart:L134-142), and it cannot be told apart from a missing one. An additional complaint [#809](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/809): the extra constant `swaggerGeneratedUnknown` in **every** enum breaks mappers such as `auto_mappr`. This is an argument for keeping unknown **outside** the set of enum values, that is, for open decision 7.
* "SDCG has `overriden_models`, `response_override_value_map`, `default_values_map`, `include_if_null`, `enums_case_sensitive`, `classes_with_nullabe_lists`, `separate_models`, `use_path_for_request_names`, `exclude_paths`/`include_paths`, `with_converter`" — **confirmed (code)**: all these names are in `GeneratorOptions`. Clarification: `include_paths`/`exclude_paths` in SDCG are **regex**, not glob. swagger_parser has **no** `exclude_paths` (only `include_paths` with glob). `required_by_default` was removed from swagger_parser in 1.18.0.

## 2.6 Known problems (issue tracker + code) and lessons

| # | Essence | Lesson for a new tool |
|---|---|---|
| [#812](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/812) (**17 reactions**, the most popular), [#817](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/817), [#800](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/800), [#793](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/793), [#749](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/749) (16 comments), [#754](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/754), [#518](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/518) | Version conflicts of `build`, `dart_style`, `chopper`; major versions of Chopper broke the output | The generator must not live in the user's dependency graph: a CLI via `dart pub global activate` or `dart run`, built separately. The runtime package is minimal, with a CI matrix of dependency versions (R13.3, open decision 1) |
| [#796](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/796), 13 open PRs | The project is abandoned, bus factor 1 | Open governance: several maintainers, automatic releases, a public roadmap |
| [#182](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/182) (28 comments), [#324](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/324), [#506](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/506), [#650](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/650), [#747](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/747), [#806](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/806) | "Everything is nullable"; required and nullable get confused | R6.1: an explicit matrix, documented as a table in the README |
| [#410](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/410) (23 comments), [#436](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/436) (15), [#147](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/147), [#219](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/219), [#557](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/557), [#836](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/836) | "Could not find factory for type X" and cast errors in the runtime converter `Map<Type, factory>` | Decoding must be static at the call site (`Pet.fromJson`), without global registries and `Type` keys (R4.3) |
| [#563](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/563) (5 reactions, 2023), [#761](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/761), [#833](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/833), [#803](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/803), [#758](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/758) | No discriminator, `anyOf`/`oneOf` becomes `dynamic`; Microsoft.AspNetCore.OpenApi (.NET 10) generates `oneOf:[null,$ref]` | R9 from the first release. A normalizer rule `oneOf-null-ref → nullable ref` for .NET 10 (R2.1) |
| [#768](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/768), [#806](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/806) | PATCH: you cannot tell "do not send" from "send null" | R7: tri-state at the type level and a custom `toJson` for such models |
| [#285](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/285) (31 comments) | `int64` → `num` loses precision on web, and silently | The `int64` mapping is configurable (`int`, `BigInt`, `String`), with a diagnostic for the web target (R6.2) |
| [#343](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/343) (14 comments), [#720](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/720), [#188](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/188), [#743](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/743), [#827](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/827), [#847](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/847) | The `Query` schema conflicts with the Chopper annotation; duplicate function names; lowercase enums; `)` in enum names; a property named `type` | Reserved names include runtime symbols; prefixed imports; deterministic casing; fuzz tests for names (R5.2) |
| [#739](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/739) | One API class for the whole spec | Grouping by tag (R5.3) |
| [#852](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/852), [#789](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/789), [#277](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/277) (16), [#169](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/169), [#567](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/567), [#426](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/426), [#354](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/354) | The builder takes files from the file system through `dart:io`; cache, workspaces and output paths break | If integration with build_runner is done after all, then only as a thin wrapper that reads through `BuildStep`, over the same core as the CLI (R15.1) |
| [#770](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/770), [#840](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/840), [#354](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/354) | Output or behavior changes in minor versions, runtime crashes | Golden tests of the output + runtime decoding tests + the policy "a change of output = major" (R15.3, R15.4) |
| [#385](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/385) (20 comments), [#726](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/726) (12), [#760](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/760), [#799](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/799) | Multipart is not generated or is generated incorrectly | A model of multipart parts + tests for `$ref` schemas with files (R10.4) |
| [#208](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/208) (25), [#798](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/798), [#744](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/744), [#206](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/206), [#200](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/200) | Unclear config errors; unknown keys are silently ignored; options affect each other in non-obvious ways | A config with JSON Schema, a strict mode for unknown keys, human-readable messages (R15.2) |
| [#809](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/809), [#549](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/549) (16) | `swaggerGeneratedUnknown` gets in the way of mappers; `""` in an enum is treated as `null` | Keep unknown outside the set of enum values. An empty string is a normal value with a deterministic name (R8.1, R8.3) |
| Code | Cookies are dropped (L740); `collectionFormat` is ignored; `additionalProperties` loses its type | R2.5: every dropped construct must produce a diagnostic |

## 2.7 What is worth borrowing

1. **`SwaggerMetaData` in every request** via `@chopper.Tag()`: a typed const object with `operationId`, `summary`, `tags`, `security`, `consumes`, `produces`, `deprecated`. For Dio the analogue is `RequestOptions.extra['openapi'] = const OperationMeta(...)` in every call, merged into the user's `extra` (R10.5, R10.8). Stronger than `add_openapi_metadata` in SP, because it is always attached and is not overwritten.
2. **`scalars`**: `format` → `{type, deserialize, serialize}` + `import_paths` (R6.2). This is an almost ready design for a configurable mapping of primitives (`Decimal`, `Uuid`, a custom `Date`).
3. **`overriden_models`** (replace a model with an own class through an import) and **`response_override_value_map`** (path+method → type). They show that users really need type overrides at the model and operation level (R3.1). A new tool must do the same through pointer addressing, with validation and a warning about a deprecated override.
4. **`Wrapped<T>` in `copyWithWrapped`**: a proven way to represent "explicit null versus not passed" in Dart without code generation (open decision 7, R7). Extend it to the serialization of the request body.
5. **`_dateToJson`** for `format: date` as `yyyy-MM-dd` (R6.2): it directly addresses the pain of SP [#463](https://github.com/Carapacik/swagger_parser/issues/463).
6. **`readOnly`/`writeOnly` → nullable** as a pragmatic default (better: separate request/response representations, R6.1).
7. **`generate_first_succeed_response`**: an explicit switch instead of a hidden rule. A new tool is better off with a union, but the idea itself of "making the trade-off visible in the config" is right.
8. **`dart_style` + `page_width`** in the generator itself (R13.1, R13.2).
9. **`model_postfix`, `cut_from_model_names`, `generate_to_json_for`, `build_only_models`**: small but in-demand knobs for size and naming (R4.3, R13.5).
10. **`custom_annotations`** (`x-key` → annotation): a cheap extension mechanism through the `x-` registry (open decision 6).
11. Handling of 204 and an empty body in the converter (additions_generator.dart:L210-214).

---

# 3. Cross-cutting conclusions for open decisions (brief)

| Open decision | What SP and SDCG showed |
|---|---|
| 1. Annotated code + build_runner or ready-made code | Both require build_runner. SP: a CLI plus a second phase, and errors are visible only after it (#380, #411, #462). SDCG: the builder in the user's graph, hence dependency hell (#812 — top issue), cache and workspaces (#789, #852). **An argument for ready-made code without build_runner**, or at least for compiling the output in the generator's CI |
| 2. Serialization | json_serializable supports unknown enums only through the way helpers are chosen (`JsonHelper` before `EnumHelper`), and does not keep the raw value. `includeIfNull` is set statically per field, so tri-state through json_serializable without a custom `toJson` is impossible. Three serializer branches in SP multiply bugs (#409, #411, #462, #351). Conclusion: one serializer (json_serializable for ordinary models) and custom code for enums, unions and PATCH bodies |
| 3. HTTP layer | Retrofit in SP sets a ceiling: one response type per method (#385), no typed errors (#367), streaming only `String`/`Uint8List`, a `value_` hack. Chopper in SDCG does not throw on HTTP errors and has a global registry. Conclusion: generate direct `dio.fetch` calls, without retrofit |
| 4. Error model | Both have nothing. SDCG: `custom_return_type` and `ErrorConverter`. SP: `HttpResponse<T>`. There is plenty of room for differentiation |
| 5. Parser | Both walk `Map<String,dynamic>` with casts, hence crashes on dirty specs (SP #374, #375, #442). SP also rewrites the spec with regexes over the text (corrector) and stringifies YAML scalars. `$ref` is resolved as the "last segment". **A custom typed model with a JSON pointer in every node is needed**: it is the basis for R2.2 and R3.1 |
| 6. Extensibility | Nobody opens the templates. In practice the config hooks are used: `field_parsers` in SP; `scalars`, `custom_annotations`, `overriden_models` in SDCG. "Config + overrides + `x-` registry" covers the request |
| 7. Raw enum and tri-state | Both do "enum + unknown constant without raw", and SDCG in nullable fields also makes null. Complaints about the extra constant (SDCG #809) and the impossibility of seeing the raw value (SP #106) suggest taking a sealed type or an extension type with `Unknown(raw)`, and for tri-state a `Wrapped`/`Optional`-like type (prior art: SDCG `copyWithWrapped`) |

---

# Sources

**Code (shallow clone, 2026-10-11):**
* SP @ `be6df7c11205d5e7dacf8cace6b07c7c5885c3fc`: base URL `https://github.com/Carapacik/swagger_parser/blob/be6df7c11205d5e7dacf8cace6b07c7c5885c3fc/swagger_parser/`
  * `lib/src/generator/templates/dart_enum_dto_template.dart` (enum, R8.1)
  * `lib/src/generator/templates/dart_json_serializable_dto_template.dart` (union, fallback, `_jsonKey`)
  * `lib/src/generator/templates/dart_freezed_dto_template.dart` (freezed fallback, validator)
  * `lib/src/generator/templates/dart_dart_mappable_dto_template.dart`
  * `lib/src/generator/templates/dart_retrofit_client_template.dart` (client, stream, metadata, content-type)
  * `lib/src/generator/templates/dart_root_client_template.dart`
  * `lib/src/parser/parser/open_api_parser.dart` (required/nullable, `$ref`, cookie, content-type, path-item cast)
  * `lib/src/parser/corrector/open_api_corrector.dart` (text replacements, `YamlMapX.toMap`)
  * `lib/src/parser/utils/type_utils.dart`, `lib/src/parser/utils/http_utils.dart`, `lib/src/parser/utils/dart_keywords.dart`, `lib/src/parser/utils/path_match.dart`
  * `lib/src/config/swp_config.dart`, `lib/src/config/config_processor.dart`, `lib/src/utils/file/io_file.dart`, `lib/src/utils/base_utils.dart`
  * `test/e2e/e2e_util.dart`, `test/e2e/tests/**`, `.github/workflows/tests.yml`, `README.md`, `CHANGELOG.md`
* SDCG @ `753bdebea6774947c0b543c755af5448af85844d`: base URL `https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/blob/753bdebea6774947c0b543c755af5448af85844d/`
  * `lib/swagger_dart_code_generator.dart` (builder, dart:io, input_urls, formatter)
  * `lib/src/models/generator_options.dart` (all options)
  * `lib/src/code_generators/enum_model.dart` (enum, unknown)
  * `lib/src/code_generators/swagger_models_generator.dart`, `swagger_requests_generator.dart`, `swagger_additions_generator.dart`, `swagger_meta_data_generator.dart`, `constants.dart`
  * `lib/src/swagger_models/responses/swagger_schema.dart`, `lib/src/extensions/string_extension.dart`
  * `example/build.yaml`, `example/lib/swagger_generated_code/*.dart`, `README.md`, `CHANGELOG.md`, `build.yaml`
* json_serializable 6.14.1 (local pub cache, the same code as on pub.dev): `lib/src/settings.dart` (order of helpers), `lib/src/type_helpers/json_helper.dart` (constructor `fromJson`), `lib/src/type_helpers/enum_helper.dart`, `lib/src/enum_utils.dart` (`_generateEntry` → the field name without `@JsonValue`). json_annotation 4.12.0 `lib/src/enum_helpers.dart` (`$enumDecode`). Upstream: <https://github.com/google/json_serializable.dart>

**pub.dev API (2026-10-11):**
* <https://pub.dev/api/packages/swagger_parser>, `/score`
* <https://pub.dev/api/packages/swagger_dart_code_generator>, `/score`, `/metrics`

**GitHub (via `gh`, 2026-10-11):**
* Issues SP: <https://github.com/Carapacik/swagger_parser/issues> (218 in total, 71 open). Key: #106, #120, #121, #194, #213, #218, #232, #239, #251, #257, #271, #273, #279, #285, #302, #303, #304, #306, #307, #312, #321, #340, #342, #358, #363, #366, #367, #369, #374, #375, #379, #380, #381, #385, #388, #389, #393, #405, #408, #409, #411, #414, #415, #423, #429, #432, #440, #441, #442, #443, #444, #446, #448, #454, #460, #462, #463
* Issues/PR SDCG: <https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues> (398 in total, 55 open; 13 open PRs #832–#858). Key: #182, #188, #200, #206, #208, #219, #277, #285, #324, #343, #354, #385, #410, #426, #436, #506, #518, #549, #557, #563, #567, #650, #721, #726, #739, #743, #744, #747, #749, #754, #758, #760, #761, #768, #770, #785, #789, #793, #796, #798, #799, #800, #803, #806, #809, #811 (PR), #812, #817, #827, #833, #836, #840, #843, #846 (PR), #847, #852, #853, #854 (PR)
* Commit history: `gh api repos/<repo>/commits?since=…`, `/contributors`
* retrofit: [trevorwang/retrofit.dart#661](https://github.com/trevorwang/retrofit.dart/issues/661) (quoted in the SP code)
