# 01 — OpenAPI Generator: `dart-dio` and `dart` generators and the `openapi_generator` wrapper for pub.dev

> Status as of 2026-10-11. Sources: code (`OpenAPITools/openapi-generator`, master at commit `9f6536e` from 2026-10-09, version `7.27.0-SNAPSHOT`; `gibahjoe/openapi-generator-dart` master), GitHub issues and PRs, pub.dev API.
> Abbreviations in links: **OAG** = `https://github.com/OpenAPITools/openapi-generator`. Paths to templates are given relative to `modules/openapi-generator/src/main/resources/`, paths to Java relative to `modules/openapi-generator/src/main/java/org/openapitools/codegen/`.
> Confidence marks: **(verified in code)** — I saw it in a template or Java code at the given commit; **(from an issue)** — described in an issue or PR, not reproduced in code; **(not verified)** — a generally known claim without a primary source.
> I did not run the generator itself: I deliberately did not do a Java build from the clone, and did not download the JAR. Conclusions were drawn from templates, Java code and the example generated sources committed to the repository (`samples/openapi3/client/petstore/dart-dio/*`).

---

## 1. Overview

### 1.1 What it is

| Component | What it does | Status |
|---|---|---|
| `dart-dio` (OAG) | Client on `dio ^5.7.0`. Serialization: `built_value` (default) or `json_serializable` (marked **[BETA]**) | `STABLE` ([docs/generators/dart-dio.md](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/docs/generators/dart-dio.md)) |
| `dart` (OAG) | Client on `package:http`, "native" serialization with handwritten `fromJson`/`toJson` in templates, **without build_runner** | `STABLE` ([docs/generators/dart.md](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/docs/generators/dart.md)) |
| `openapi_generator`, `openapi_generator_annotations`, `openapi_generator_cli` (pub.dev, repository gibahjoe/openapi-generator-dart) | Wrapper over the Java JAR: annotation `@Openapi(...)` and a builder for `build_runner`. The CLI downloads the JAR from Maven Central | v7.0.0 from 2026-05-31; publisher `devappliance.com`; 126 likes, ~11.5k downloads ([pub.dev](https://pub.dev/packages/openapi_generator)) |

### 1.2 Versions and release cadence
- The latest OAG version is **v7.26.0 from 2026-10-06** (`gh release list`). Over the last 12 months 10 minor releases came out: 7.17 (2025-10-29), 7.18 (12-22), 7.19 (2026-01-19), 7.20 (02-16), 7.21 (03-24), 7.22 (04-28), 7.23 (06-08), 7.24 (07-20), 7.25 (08-24), 7.26 (10-06). The rhythm is **roughly once every 4–7 weeks**.
- Important changes for Dart over the last year (from release notes):
  - 7.21: `Optional<T>` for the three states of a field (absent/null/value) in `dart` and `dart-dio`, options `useOptional` and `patchOnly` ([PR #22257](https://github.com/OpenAPITools/openapi-generator/pull/22257));
  - 7.22: methods for clearing auth tokens ([#23386](https://github.com/OpenAPITools/openapi-generator/pull/23386)), fix of `importMappings` ([#23571](https://github.com/OpenAPITools/openapi-generator/pull/23571));
  - 7.23: `abortTrigger` (cancellation of requests) in `dart` ([#23930](https://github.com/OpenAPITools/openapi-generator/pull/23930));
  - 7.25: tri-state for PATCH ([#23696](https://github.com/OpenAPITools/openapi-generator/pull/23696)), `anyOf` serialization in dart-dio ([#24605](https://github.com/OpenAPITools/openapi-generator/pull/24605)), a shift of `format: date` dates in time zones east of UTC ([#24706](https://github.com/OpenAPITools/openapi-generator/pull/24706));
  - 7.26: explode for object query parameters in `dart` ([#24868](https://github.com/OpenAPITools/openapi-generator/pull/24868)), `unknownEnumValue` for enum collections in json_serializable ([#24673](https://github.com/OpenAPITools/openapi-generator/pull/24673)), multi-line `x-enum-descriptions` ([#24881](https://github.com/OpenAPITools/openapi-generator/pull/24881); this bug broke generation in 7.25 — [#24858](https://github.com/OpenAPITools/openapi-generator/issues/24858)).

### 1.3 Who maintains the Dart generators
- The Dart technical committee in the README: `@jaumard (2018/09) @amondnet (2019/12) @sbu-WBT (2020/12) @kuhnroyal (2020/12) @agilob (2020/12) @ahmednfwela (2021/08)` ([README.md, line 1264](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/README.md)). The committee's activity is low (search `commenter:` since 2025-10-01): ahmednfwela — 11 comments, kuhnroyal — 5, jaumard and amondnet — 1 each, the rest — 0. None of them has opened any issue or PR since 2024-10. In July 2026 @josh-burton left the list of Dart maintainers ([#24352](https://github.com/OpenAPITools/openapi-generator/pull/24352)).
- **All 29 PRs with "dart" in the title merged since 2025-10-01 were merged by @wing328** (founder and core maintainer of OAG). The authors were mostly one-time contributors. In practice the Dart generators develop through external PRs, without an owner.
- Issues (search `dart in:title`, 2026-10-11): **134 open** (of them **70** with `dart-dio` in the title): **90 [BUG]**, **32 [REQ]**. By creation year of the open ones: 2019 — 7, 2020 — 13, 2021 — 10, 2022 — 23, 2023 — 35, 2024 — 19, 2025 — 24, 2026 — 3. The label `Client: Dart` is set rarely: only 9 open issues have it. The epic "Dart full OAS3 support" ([#8179](https://github.com/OpenAPITools/openapi-generator/issues/8179)) has been open since 2020.
- Overall for the repository: 26.8k stars and **5752 open issues and PRs**.

### 1.4 Dependency on Java
- Build for Java 11: `maven.compiler.source=11` ([pom.xml](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/pom.xml)). [docs/installation.md](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/docs/installation.md) says "Java 11 runtime at a minimum". Delivery methods: JAR, npm wrapper `@openapitools/openapi-generator-cli`, Docker, Homebrew, Maven and Gradle plugins, `pip install openapi-generator-cli[jdk4py]`.
- The README of gibahjoe's wrapper still requires "Java (version 8 or higher)" (`openapi-generator/README.md`, line 18) **(verified in code)**. On Java 8 users get `UnsupportedClassVersionError` ([#19024](https://github.com/OpenAPITools/openapi-generator/issues/19024)).

### 1.5 The `openapi_generator` wrapper (gibahjoe)
- 173 stars, 18 open issues and PRs, last push 2026-05-31. Three packages: annotations, builder (`openapi_generator`) and CLI.
- The CLI creates an `openapi_generator_cli` config. By default it downloads **OAG 7.17.0** (`openapi-generator-cli/lib/src/models.dart`, `openapiGeneratorVersion = '7.17.0'`), i.e. it lags behind the current 7.26.0 by 9 minor versions. Additionally it downloads an unofficial generator `openapi-dart-generator-7.2.jar` from bluetrainsoftware (`Generator.dioAlt`) **(verified in code)**.
- The annotation passes only some OAG flags: `--additional-properties --api-package --enum-name-mappings --generator-name --import-mappings --inline-schema-name-mappings --inline-schema-options --name-mappings --reserved-words-mappings --skip-validate-spec --type-mappings`. **There is no `--openapi-normalizer`, `--model-name-mappings`, `--parameter-name-mappings`, `--schema-mappings`, `--operation-id-name-mappings`, `--global-property`.** They can be passed only as a raw string through `additionalCommands` in the CLI's JSON config **(verified in code)**.
- After generation the wrapper by default runs `flutter pub get` (`fetchDependencies = true`) and a **nested** `build_runner` in the output directory (`runSourceGenOnOutput = true`). To force a re-run, `forceAlwaysRun` changes the user's annotated file.
- `openapi_generator` 7.0.0 declares the dependency `analyzer: '>5.12.0 <9.0.0'`, while modern Flutter resolves analyzer 10.x. Because of this the package does not install in new apps ([gibahjoe#201](https://github.com/gibahjoe/openapi-generator-dart/issues/201), open since 2026-04). The generator fails with an unclear message ([gibahjoe#202](https://github.com/gibahjoe/openapi-generator-dart/issues/202)) and conflicts with `mockito:mockBuilder` in CI ([gibahjoe#136](https://github.com/gibahjoe/openapi-generator-dart/issues/136)).

---

## 2. Output architecture

### 2.1 The OAG pipeline
`swagger-parser` (parsing and validation) → **OpenAPINormalizer** (rules, §4) → **InlineModelResolver** (moves inline schemas into named models) → `DefaultCodegen` + `AbstractDartCodegen`/`DartDioClientCodegen` (build the model for the templates) → **Mustache templates** → (optionally) post-processing of each `.dart` file with the command from the env `DART_POST_PROCESS_FILE`, if `--enable-post-process-file` is passed ([AbstractDartCodegen.java#L960-L976](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/java/org/openapitools/codegen/languages/AbstractDartCodegen.java#L960-L976)) → **the user runs `build_runner` themselves** (for dart-dio in both modes).

For OAS 3.1 the generator has no separate logic. `DefaultGenerator` enables the rule `NORMALIZE_31SPEC` (it is not described in the documentation), which reduces 3.1 constructs to 3.0 semantics ([DefaultGenerator.java#L263-L275](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/java/org/openapitools/codegen/DefaultGenerator.java#L263-L275)) **(verified in code)**.

### 2.2 `dart-dio`: file structure (from `DartDioClientCodegen.processOpts`, lines 210–296, and from examples)

```
pubspec.yaml, analysis_options.yaml, .gitignore, README.md
build.yaml                         # only json_serializable
lib/<pubName>.dart                 # barrel export
lib/src/api.dart                   # client class `Openapi` (clientName = camelize(pubName))
lib/src/api/<tag>_api.dart         # one class per tag
lib/src/model/*.dart               # + *.g.dart after build_runner
lib/src/auth/{auth,api_key_auth,basic_auth,bearer_auth,oauth}.dart
lib/src/serializers.dart, api_util.dart        # built_value
lib/src/deserialize.dart                        # json_serializable
lib/src/model/date.dart, date_serializer.dart   # built_value + dateLibrary=core
lib/src/optional.dart                           # if useOptional=true
doc/*.md                           # documentation for each API and each model
test/*_test.dart                   # test stubs `// TODO`
.openapi-generator/FILES, VERSION, .openapi-generator-ignore
```

Scale on the example `petstore_client_lib_fake` (built_value) **(verified in code)**: **217 files, of which 67 `doc/*.md`, 64 `test/*_test.dart` (empty `test('...', () async { // TODO })`) and only 78 files in `lib/`**. The json_serializable variant gives 215 files, of which 67 and 64 respectively.
→ **Clarification to R13.5.** By default dart-dio **generates** documentation and test stubs. They can be disabled only like this: `--global-property apiDocs=false,modelDocs=false,apiTests=false,modelTests=false` ([docs/customization.md, "Selective generation"](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/docs/customization.md)). The wording of R13.5 "(as in dart-dio)" should be read as "**unlike** dart-dio".
The `dart` generator also creates `git_push.sh` and `.travis.yml` ([DartClientCodegen.java#L97-L100](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/java/org/openapitools/codegen/languages/DartClientCodegen.java#L97-L100)) **(verified in code)**.

**The output is a separate pub package** (its own `pubspec.yaml`), which is connected as a path dependency. It can be embedded into an existing package only manually, via `sourceFolder`, `pubName` and `pubLibrary`.

### 2.3 API shape (`dart/libraries/dio/api.mustache`) **(verified in code)**
- A concrete class `class PetApi { final Dio _dio; const PetApi(this._dio, this._serializers); }`. There is no abstract interface. Mocks can be made through Dart's implicit interface (`implements PetApi` in mocktail).
- The method `Future<Response<T>> getPetById({required int petId, CancelToken? cancelToken, Map<String,dynamic>? headers, Map<String,dynamic>? extra, ValidateStatus? validateStatus, ProgressCallback? onSendProgress, ProgressCallback? onReceiveProgress})`. Returns a **dio `Response<T>`**, so headers and status are available.
- `Options.extra['secure']` — a list of `{type, scheme, name, keyName, where}` for each security requirement of the operation. It is read by the generated `AuthInterceptor` (`auth/auth.mustache`). **`operationId` does not get into `extra`.**
- `contentType` is taken only as the **first** of `prioritizedContentTypes` (line 81).
- Errors of (de)serialization are wrapped in `DioException(type: DioExceptionType.unknown, error: …)` (lines 102 and 127).
- `lib/src/api.dart` (`api_client.mustache`): if no `Dio` is passed, the client creates `Dio(BaseOptions(baseUrl: basePathOverride ?? basePath, connectTimeout: 5000ms, receiveTimeout: 3000ms))`. **If `interceptors == null`, it adds 4 auth interceptors even to a `Dio` passed in by the user** ([api_client.mustache#L26-L41](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/resources/dart/libraries/dio/api_client.mustache#L26-L41)).

### 2.4 Serialization
- **built_value (default):** `abstract class X implements Built<X, XBuilder>`, collections `BuiltList`/`BuiltMap`, `JsonObject` for any. A shared `standardSerializers`. For `oneOf`/`anyOf` the packages **`one_of` / `one_of_serializer` 1.5.0** are used, published **2022-05-10** with `sdk: '>=2.12.0 <3.0.0'` (pub.dev API). Enum — `EnumClass` with `BuiltSet values`, and besides each enum an "Angular mixin" (`enum.mustache`) is generated. Runtime dependencies: `dio`, `built_value`, `built_collection`, `one_of`, `one_of_serializer`.
- **json_serializable ([BETA]):** classes with `@JsonSerializable(checked: true, disallowUnrecognizedKeys: false, explicitToJson: true)`, with **`@CopyWith()` by default** (since 7.15.0, [PR #21667](https://github.com/OpenAPITools/openapi-generator/pull/21667)). Handwritten `==` and `hashCode` (the sum of the fields' `hashCode`) or `equatable`. The response is decoded by a **string-based type dispatcher** `deserialize<ReturnType, BaseType>(value, 'TypeName')` with a regex for `List<…>`/`Map<String,…>` and `throw Exception('Cannot deserialize')` at the end ([deserialize.mustache](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/resources/dart/libraries/dio/serialization/json_serializable/deserialize.mustache)). The request body is encoded through `jsonEncode(body)`. Dependencies: `dio`, `json_annotation ^4.9.0`, `copy_with_extension ^7.1.0` (+ dev: `json_serializable ^6.9.3`, `copy_with_extension_gen ^7.1.0`, `build_runner: any`).
- **`dart` (native):** one library with `part` files, without build_runner. A global variable `var defaultApiClient = ApiClient();` ([apilib.mustache#L32](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/resources/dart2/apilib.mustache)) and `import 'dart:io'` (line 6). Each operation has a pair of methods: `xxxWithHttpInfo()` returns the raw `Response`, `xxx()` returns the decoded value. For status ≥ 400 an `ApiException(code, String body)` is thrown.

---

## 3. Requirements coverage table

The status is given for **`dart-dio` + json_serializable** (the target configuration). If built_value or `dart` behave differently, this is noted in the "Evidence" column.
✅ — present; ⚠️ — partial, with bugs or only manually; ❌ — absent.

| R-ID | Status | Evidence |
|---|---|---|
| R0.1 OAS 3.0 / 3.1, pure Dart | ⚠️ | 3.0 is supported. 3.1 — **"beta support"** ([README.md L168](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/README.md)), works by downgrading to 3.0 (`NORMALIZE_31SPEC`). Bugs are still open: inline `type: ["object","null"]` gives a non-null field ([#23866](https://github.com/OpenAPITools/openapi-generator/issues/23866), 2026-05); fixes for 3.1 nullable were in 7.24–7.26. dart-dio is pure Dart. **`dart` imports `dart:io`** (apilib.mustache L6), so it does not work on web (checked in the code; the consequence for web is my conclusion) |
| R0.2 tolerance to defects | ⚠️ | There is a Normalizer (§4), but it works silently, without a report |
| R1.1 local file / URL with auth | ⚠️ | `-i <file\|url>`, `-a/--auth name:header` ([docs/usage.md](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/docs/usage.md)). There is no concept of a "snapshot". The wrapper has `RemoteSpec` + `headerDelegate` |
| R1.2 `$ref` between files, cycles | ⚠️ | External `$ref`s are resolved by swagger-parser. Self-references in an array, `oneOf`, `anyOf` and `additionalProperties` are "fixed" by **replacing them with any or removing the variant** (`OpenAPINormalizer.fixSelfReferenceSchema`, ~L910–945, only `LOGGER.error`) (checked in the code) |
| R1.3 several specifications | ✅ | The `batch` command (YAML/JSON configs), several `@Openapi` in the wrapper |
| R1.4 OAS 3.2 `itemSchema` | ❌ | [#22728](https://github.com/OpenAPITools/openapi-generator/issues/22728) is open; depends on swagger-parser#2248. Unknown operations (for example `query`) **silently disappear** with `--skip-validate-spec` ([#24212](https://github.com/OpenAPITools/openapi-generator/issues/24212)) |
| R2.1 named normalizer rules, report | ⚠️ | 25 rules, each switched on separately, `DISABLE_ALL` (§4). There are **no** separate rules for `required: bool`, an empty `$ref`, an array without `items`, undeclared path parameters, `examples` in 3.0 and duplicate enums. There is no report of rule firings |
| R2.2 codes, levels, JSON pointer | ❌ | Only slf4j logs without codes and without a pointer to the location (19 `LOGGER` calls in 2809 lines of `OpenAPINormalizer.java`) |
| R2.3 baseline/ratchet | ❌ | — |
| R2.4 check mode | ⚠️ | `openapi-generator-cli validate -i … [--recommend]`. This is only swagger-parser validation (example output: `-attribute info is missing`), with no generator-specific checks |
| R2.5 do not guess silently | ❌ | A map without a value type → `String` ([AbstractDartCodegen.java#L585-L588](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/java/org/openapitools/codegen/languages/AbstractDartCodegen.java#L585-L588)). Unsupported `allOf` subschemas are removed with a **DEBUG**-level log (`OpenAPINormalizer.java` L1293). An exception in the normalizer is caught and generation continues (`DefaultGenerator` L273–275). With no 2xx response, the success type becomes `default`. Cookie parameters are dropped (see the lines below) |
| R3.1 override file with addressing | ❌ | There are only **global** mappings by name: `nameMappings`, `parameterNameMappings`, `modelNameMappings`, `enumNameMappings`, `operationIdNameMappings`, `inlineSchemaNameMappings`, `schemaMappings`, `typeMappings`, `importMappings` (§4) |
| R3.2 stale override → warning | ❌ | Mappings are only checked through `containsKey` (`toVarName`, `toParamName`, `toModelName`, `toEnumVarName`). An unused key is never reported (checked in the Dart codegen) |
| R3.3 JSON Patch / Overlay | ❌ | A request for a preprocessor or Overlay ([#22744](https://github.com/OpenAPITools/openapi-generator/issues/22744), 2026-01) is open |
| R4.1 filter by tags, operationId, paths | ⚠️ | The rule `FILTER="operationId:a\|b ; tag:x ; path:/v1 ; method:get"` marks the remaining operations `x-internal: true`. **Include-only** mode. A path is matched by prefix, not by glob. Also `--global-property apis=Pet:Store` |
| R4.2 model tree-shaking | ❌ | Models are generated for **all** `components.schemas`, regardless of the selected operations. There is only `--global-property models=A:B` and (not documented in docs/) `generateRecursiveDependentModels`, which pulls in dependencies **of models**, not of operations ([DefaultGenerator.java#L230, L533-L547](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/java/org/openapitools/codegen/DefaultGenerator.java)) |
| R4.3 coexistence with user code | ⚠️ | `--model-name-prefix/suffix`, a separate pub package. But dart-dio **modifies the passed `Dio`** (adds interceptors), and `dart` has a global `defaultApiClient` (checked in the code) |
| R5.1 operation names, transformations | ⚠️ | `operationId` → camelCase, `--remove-operation-id-prefix`, `operationIdNameMappings`. There are no regex transformations. Without `operationId` the name is built from the path and the method |
| R5.2 collisions | ⚠️ | Reserved words and types from `typeMapping` get the `Model` prefix (`ModelClient`, `ModelFile`, `ModelList`, `ModelReturn`) — only with `LOGGER.warn`. `ensureUniqueParams` works for parameters. **Property collisions are not detected:** a leading `_` is stripped (`_type` → `type`) ([AbstractDartCodegen.java#L419-L457](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/java/org/openapitools/codegen/languages/AbstractDartCodegen.java#L419-L457)). An example of a collision is in the docs themselves ([customization.md "Name Mapping"](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/docs/customization.md)). See also #9029, #20910, #12127 |
| R5.3 grouping by tag, tag normalization | ✅/⚠️ | A class per tag. Rules `KEEP_ONLY_FIRST_TAG_IN_OPERATION`, `SET_TAGS_FOR_ALL_OPERATIONS`, `SET_TAGS_TO_OPERATIONID`, `SET_TAGS_TO_VENDOR_EXTENSION`. There is no mapping "dirty tag → name" |
| R5.4 naming of inline schemas | ⚠️ | `title`, otherwise `{operationId}_request`, `{operationId}_{code}_response`, `{Parent}_{prop}`, `_inner` for an array element, `inline_object`, **numeric suffixes `_1`, `_2`** ([InlineModelResolver.java L630, L688, L842-L943](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/java/org/openapitools/codegen/InlineModelResolver.java)). Renaming is done with `inlineSchemaNameMappings`, where the key is the **generated** name. `inlineSchemaOptions`: `ARRAY_ITEM_SUFFIX`, `MAP_ITEM_SUFFIX`, `RESOLVE_INLINE_ENUMS`, `SKIP_SCHEMA_REUSE` |
| R6.1 required × nullable matrix | ⚠️ | json_serializable: `required` → `required:true`, `includeIfNull` depends on nullable. An optional field is always `T?`. Many open bugs (§5, P9). There is no separate mode for request and response |
| R6.2 types and `format` | ⚠️ | `int64` → `int` (on web precision is lost, [#14522](https://github.com/OpenAPITools/openapi-generator/issues/14522)). **`decimal` → `double`**, `uuid` → `String`, `byte` → `String`, `binary` → `MultipartFile` (in json_serializable even for a response, [#20682](https://github.com/OpenAPITools/openapi-generator/issues/20682)), any/object → `Object` (json_ser) or `JsonObject` (built_value) ([AbstractDartCodegen.java#L153-L178](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/java/org/openapitools/codegen/languages/AbstractDartCodegen.java#L153-L178)). Custom types — via `typeMappings` + `importMappings`. `disallowAdditionalPropertiesIfNotPresent=true` by default keeps the old, incorrect interpretation of `additionalProperties` |
| R6.3 `allOf` | ⚠️ | built_value: inheritance via `implements` + `$Parent`. json_serializable: the model is **flattened, there is no hierarchy** ([#21318](https://github.com/OpenAPITools/openapi-generator/issues/21318), [#22547](https://github.com/OpenAPITools/openapi-generator/issues/22547)). A single `$ref` in `allOf` is handled (the examples include `AllOfWithSingleRef`) |
| R6.4 envelopes and generics | ❌ | Not supported. Each `{data: T}` becomes a separate model |
| R6.5 extra fields / error for a missing field | ⚠️ | Extra fields are ignored (`disallowUnrecognizedKeys: false`), although `build.yaml` has `disallow_unrecognized_keys: true`, which is misleading. For a missing field with `checked: true` it throws `CheckedFromJsonException` with the key name, but without a path in the JSON, wrapped in `DioException.unknown`. In `dart` the required-check exists only in an **`assert`** (stripped in release mode, checked in the code) |
| R6.6 `==`, `copyWith`, `toString` | ✅ | `==`/`hashCode` (or equatable), `copyWith` (`copy_with_extension`), `toString()` = `toJson().toString()` |
| R6.7 constraints | ⚠️ | `minimum`/`maximum` only as comments `// minimum:` in json_serializable. There is no validation |
| R7.1–R7.3 PATCH, three states | ⚠️ | Since 7.21 there is `useOptional` (`Optional<T>` with `Absent`/`Present`, `readValue: readOptionalValue` with a sentinel) and `patchOnly`. `patchOnly` triggers **only for PATCH bodies through `$ref`**, inline schemas are ignored ([AbstractDartCodegen.preprocessOpenAPI](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/java/org/openapitools/codegen/languages/AbstractDartCodegen.java)). Without `useOptional`, optional fields are not sent when they equal null (`includeIfNull: false`), so an explicit null cannot be sent. R7.3 ✅ |
| R8.1 unknown enum value, raw value | ❌ | `enumUnknownDefaultCase=false` by default. If it is enabled, the value becomes `unknownDefaultOpenApi`, and **the raw value is lost**. In `dart` an unknown value becomes `null` (`decode(allowNull=true)`) |
| R8.2 unknown cannot be sent | ❌ | The sentinel is a real wire value `'unknown_default_open_api'` or **`11184809`** for numbers ([DefaultCodegen.java#L7315-L7333](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/java/org/openapitools/codegen/DefaultCodegen.java#L7315-L7333)), so it can be serialized and sent to the server |
| R8.3 string, numeric, boolean enums | ⚠️ | In json_serializable an `enum` for numeric values keeps `final String value` (`'1'`) (checked in the code). For boolean enums the rule `SIMPLIFY_BOOLEAN_ENUM` (on by default) turns them into a plain `bool`. Invalid identifiers: `number1`, `number_negative1`, `empty` |
| R8.4 `x-enum-varnames`, `x-enum-descriptions` | ✅ | Through `DefaultCodegen.updateEnumVarsWithExtensions`. Plus `x-enum-values` with `useEnumExtension`, but then `enumUnknownDefaultCase` breaks ([#21411](https://github.com/OpenAPITools/openapi-generator/issues/21411)) |
| R9.1 oneOf/anyOf + discriminator → closed hierarchy + Unknown | ❌ / ⚠️ | json_serializable: **there is no polymorphism at all** (`class.mustache` has no branch for oneOf/anyOf/discriminator — checked in the code; [#21318](https://github.com/OpenAPITools/openapi-generator/issues/21318); the item "Add polymorphism support to json_serializable" from [#13372](https://github.com/OpenAPITools/openapi-generator/issues/13372) has been open since 2022). built_value: a wrapper `OneOf get oneOf` with `Object value` (not sealed). An unknown discriminator → `throw UnsupportedError("Couldn't deserialize oneOf for the discriminator value…")` (`class_serializer.mustache` L164) |
| R9.2 oneOf without discriminator | ❌ / ⚠️ | built_value: `OneOfSerializer` tries the types in turn, sometimes "more than one match found" ([#15373](https://github.com/OpenAPITools/openapi-generator/issues/15373)). There is no diagnostic |
| R9.3 mixed primitives | ⚠️ | built_value through `OneOf`/`AnyOf` with primitives (there is an example `oneof_primitive`). The FastAPI template `loc: array<anyOf[string,integer]>` produced an invalid `ValidationErrorLocInner` ([#13302](https://github.com/OpenAPITools/openapi-generator/issues/13302) is open, [#18913](https://github.com/OpenAPITools/openapi-generator/issues/18913)) |
| R10.1 own Dio, the generator adds nothing | ⚠️ | `Openapi(dio: myDio)` is accepted, but without `interceptors:` **4 auth interceptors are added to it**. If no Dio is passed — hard-coded timeouts of 5 s and 3 s |
| R10.2 HTTP errors through `onError` | ✅ | `_dio.request<Object>` with the user's `validateStatus`, so errors go through the normal Dio path |
| R10.3 path/query/header/cookie; styles | ⚠️ | built_value: `ListParam` with `ListFormat.{csv,ssv,tsv,pipes,multi}`. json_serializable: query values are passed **as is** (`query_param.mustache` = `{{paramName}}`) and `collectionFormat` is ignored. **There is no deepObject** ([#13584](https://github.com/OpenAPITools/openapi-generator/issues/13584); in `dart` a Map goes through `parameterToString` → `toString()`). **There are no cookie parameters either in the signature or in the request** (there is no `isCookieParam` in the templates — checked in the code), although the feature table claims `Cookie ✓`. The docs table: `ParameterStyling ✗` |
| R10.4 JSON, multipart, urlencoded, binary | ⚠️ | multipart through `FormData.fromMap`. The content-type of parts (`encoding`) is not supported. In json_serializable, models end up in FormData without encoding ([#19420](https://github.com/OpenAPITools/openapi-generator/issues/19420), [#14472](https://github.com/OpenAPITools/openapi-generator/issues/14472)). Binary response: `ResponseType.bytes` → `Uint8List` (built_value), in json_ser — `MultipartFile` |
| R10.5 cancellation, progress, headers, `extra`, operationId | ⚠️ | `cancelToken`, `onSend/ReceiveProgress`, `headers`, `extra` — ✅. **`operationId` is not in the request.** A timeout cannot be passed for a single request ([#12645](https://github.com/OpenAPITools/openapi-generator/issues/12645)) |
| R10.6 several 2xx, 204, non-JSON | ⚠️ | The return type is taken from the **smallest 2xx code, and if there is no 2xx — from `default`** ([DefaultCodegen.java#L4850-L4860](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/java/org/openapitools/codegen/DefaultCodegen.java#L4850-L4860)). `text/plain` breaks ([#14904](https://github.com/OpenAPITools/openapi-generator/issues/14904)). The new opt-in `--global-property splitOperationsByContentType=true` generates separate `With<Subtype>`/`As<Subtype>` methods ([docs/global-properties.md](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/docs/global-properties.md)) |
| R10.7 abstract API | ⚠️ | Classes are concrete, but they are mocked through an implicit interface without code generation |
| R10.8 security as metadata | ✅/⚠️ | `extra['secure']` is a good prior art. But the AND/OR semantics of `security` requirements is flattened into a plain list ([#7057](https://github.com/OpenAPITools/openapi-generator/issues/7057)) |
| R10.9 several `servers`, variables | ❌ | Only the first server is taken (`basePath`), `basePathOverride`. In docs: `MultiServer ✗`, `ParameterizedServer ✗`. There is a CLI option `--server-variables` (substitution at generation time) |
| R11.1–R11.7 typed errors | ❌ | The error body is the raw `DioException.response.data`. A decoding error cannot be told apart from a transport error (both are `DioExceptionType.unknown`). In `dart` a decoding error becomes `ApiException(500, …)` — **a fake HTTP status** (checked in the code) |
| R12.x SSE | ❌ | No support. A request for stream responses has been open since 2020 ([#6750](https://github.com/OpenAPITools/openapi-generator/issues/6750)) |
| R13.1 determinism | ⚠️ | The templates are deterministic (header without date and version). But the names of inline models depend on the traversal order (`_1`, `_2`) and on deduplication, and the deduplication behaviour changed in 7.23 ([#24177](https://github.com/OpenAPITools/openapi-generator/issues/24177)). The rule `SORT_MODEL_PROPERTIES` (opt-in) orders the properties |
| R13.2 lints and format | ❌ | See §5, P20. `dart format` only through an env variable + a flag |
| R13.3 small runtime package | ❌ | There is no separate runtime. Helpers are copied into every generated package. External dependencies are outdated (`one_of` since 2022) |
| R13.4 doc comments, `@Deprecated` | ✅ | `summary`/`notes` → `///`. `@Deprecated` on operations, parameters, models and fields |
| R13.5 no stubs | ❌ | See §2.2: 67 doc + 64 test stubs in 78 lib files |
| R14.1 change report | ❌ | There is only `--dry-run` (changes at the file level) and `.openapi-generator/FILES`. Stale files are not deleted: in the example `petstore_client_lib_fake` there are `cat_all_of.dart`, `dog_all_of.dart`, `inline_response_default.dart`, which are not in `FILES` (checked in the code) |
| R14.2 evolution compatibility | ⚠️ | A new union variant with a known discriminator in built_value — `UnsupportedError`. A new enum — an error or loss of a value |
| R15.1 CLI and programmatic API | ⚠️ | Java CLI, Maven/Gradle plugins, a wrapper through build_runner. There is no native Dart API |
| R15.2 config with a schema | ⚠️ | `-c config.{json,yaml}` (additional properties), `batch`. There is no validation of the config against a schema (not checked for the npm wrapper) |
| R15.3 golden tests | ⚠️ | `samples/` + `bin/configs/dart*.yaml` (10 configs) serve as goldens in CI. Test schemas are scattered ([#15449](https://github.com/OpenAPITools/openapi-generator/issues/15449)) |
| R15.4 semver | ❌ | The output changes in minor releases (§5, P25) |
| R15.5 documentation, matrix | ⚠️ | There is a generator page with a feature table, but the table **diverges from the code** (Cookie ✓ — in fact it is not; [#17677](https://github.com/OpenAPITools/openapi-generator/issues/17677) claims that `modelNameMappings` does not exist, while in the code it does) |
| R15.6 lint for backend | ⚠️ | Only `validate --recommend` |

---

## 4. Normalizer and mappings as prior art (R2, R3, R4, R5)

### 4.1 OpenAPI Normalizer — the full list of rules (master `9f6536e`)
Source: [docs/customization.md, "OpenAPI Normalizer"](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/docs/customization.md) and [OpenAPINormalizer.java L65-L175, L250-L280](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/java/org/openapitools/codegen/OpenAPINormalizer.java). Syntax: `--openapi-normalizer RULE=true,RULE2=value` (CLI) or `openapiNormalizer` in plugins.

| Rule | Default | What it does |
|---|---|---|
| `SIMPLIFY_ONEOF_ANYOF` | **on** | Removes `null`/`enum:[null]` from oneOf/anyOf and sets `nullable: true`. Unwraps oneOf/anyOf with a single variant |
| `SIMPLIFY_BOOLEAN_ENUM` | **on** | Boolean enum → `boolean` |
| `SIMPLIFY_ONEOF_ANYOF_ENUM` | **on** | oneOf/anyOf with enum-only subschemas → one enum |
| `REFACTOR_ALLOF_WITH_PROPERTIES_ONLY` | **on** | `allOf` + `properties` at the same level → `allOf` with a new subschema |
| `REF_AS_PARENT_IN_ALLOF` | off | A `$ref` in `allOf` is treated as the parent class (inheritance) |
| `REMOVE_ANYOF_ONEOF_AND_KEEP_PROPERTIES_ONLY` | off | Removes oneOf/anyOf that only list required, and keeps the properties |
| `SIMPLIFY_ANYOF_STRING_AND_ENUM_STRING` | off | `anyOf[string, enum<string>]` → `string` |
| `REPLACE_ONE_OF_BY_DISCRIMINATOR_MAPPING` | off | Replaces `oneOf` with `discriminator.mapping` (new in 7.22; the docs have a before/after diff) |
| `KEEP_ONLY_FIRST_TAG_IN_OPERATION` | off | Keeps only the first tag of an operation |
| `SET_TAGS_FOR_ALL_OPERATIONS=<tag>` | off | Sets one tag on all operations |
| `SET_TAGS_TO_OPERATIONID` | off | Tag = operationId |
| `SET_TAGS_TO_VENDOR_EXTENSION=<x-…>` | off | The tag is taken from an `x-` extension |
| `FIX_DUPLICATED_OPERATIONID` | off | Adds the suffixes `_0`, `_1` to duplicate operationIds |
| `ADD_UNSIGNED_TO_INTEGER_WITH_INVALID_MAX_VALUE` | off | For `maximum: 2^32-1` / `2^64-1` adds `x-unsigned` |
| `REMOVE_PROPERTIES_FROM_TYPE_OTHER_THAN_OBJECT` | off | Removes `properties` from schemas that are not objects |
| `REMOVE_X_INTERNAL` | off | Turns off hiding of elements with `x-internal` |
| `FILTER="operationId:a\|b ; tag:x ; path:/v1 ; method:get"` | off | Operations that did not match the filter get `x-internal: true` and are not generated |
| `SECURITY_SCHEMES_FILTER="key:… ; type:…"` | off | Removes security schemes that did not match the filter, and references to them |
| `SET_CONTAINER_TO_NULLABLE=array\|set\|map` | off | Mass `nullable: true` for containers |
| `SET_PRIMITIVE_TYPES_TO_NULLABLE=string\|integer\|number\|boolean` | off | Mass `nullable: true` for primitives |
| `SET_BEARER_AUTH_FOR_NAME=<name>` | off | Converts a Swagger 2 securityDefinition to `http bearer` |
| `SORT_MODEL_PROPERTIES` | off | Sorts properties alphabetically (for determinism) |
| `LOOSE_NULL_DEFINITIONS` | off | More forms in 3.0 are treated as `null` (new in 7.23) |
| `NORMALIZE_31SPEC` | auto for ≥3.1 | Downgrade 3.1 → 3.0 (not described in the docs; enabled in `DefaultGenerator` L268) |
| `NORMALIZER_CLASS=<FQCN>` | — | A custom Java subclass of the normalizer (plugin) |
| `ENABLE_ALL` / `DISABLE_ALL` | — | Bulk enabling or disabling |

Not a rule, but the same in essence: **`fixSelfReferenceSchema`** always runs and replaces self-references with any or removes the variant.

### 4.2 Mappings and other mechanisms
| Mechanism | Key | How it works |
|---|---|---|
| `nameMappings` | **raw property name** (`_type=underscoreType`) | Global for **all** schemas, without `Schema.prop` addressing |
| `parameterNameMappings` | raw parameter name | Global for all operations |
| `modelNameMappings` | schema name (`Tag=Label`) | Model renaming |
| `enumNameMappings` | **enum value** (`sold=UNAVAILABLE`) | Global for all enums with that value |
| `operationIdNameMappings` | operationId | Method name |
| `inlineSchemaNameMappings` | **generated** name (`meta_200_response=MetaObject`) | First the generation has to be run to learn the name. An INFO log hints: "Inline schema created as … To have complete control of the model name, set the `title` field or use the inlineSchemaNameMapping option" |
| `inlineSchemaOptions` | `ARRAY_ITEM_SUFFIX`, `MAP_ITEM_SUFFIX`, `SKIP_SCHEMA_REUSE`, `REFACTOR_ALLOF_INLINE_SCHEMAS`, `RESOLVE_INLINE_ENUMS` | Global settings of the resolver |
| `schemaMappings` | schema name → external type | The model is not generated, the user's type is used ("bring your own model") |
| `typeMappings` + `importMappings` | OpenAPI type (`DateTime`, `string+binary`) → Dart type + import | Global type replacement. For Dart **both** mappings are needed |
| `reservedWordsMappings` | word → replacement | |
| `--skip-validate-spec` | — | Skips swagger-parser validation (may silently lose unknown constructs, [#24212](https://github.com/OpenAPITools/openapi-generator/issues/24212)) |
| `--global-property apis=Pet:Store,models=User:Pet,apiTests=false,…` | API or model name | Selective generation. **Without tree-shaking** |
| `.openapi-generator-ignore` | glob patterns of **file** paths | Do not overwrite or do not generate files. `--openapi-generator-ignore-list` fills it from the CLI |
| `.openapi-generator/FILES` | — | Manifest of generated files (for cleaning up stale ones, but the generator itself does not clean up) |
| `--minimal-update`, `--dry-run` | — | Writes only changed files / shows what will change |
| `x-internal: true` in the spec | element | Excludes an operation or model from generation |

### 4.3 Weak points that the new tool has to close
1. **No addressing.** Mappings are bound to the raw name, not to a place in the spec (JSON pointer, `operationId`, `Schema.property`). `nameMappings _type=…` applies to all schemas at once. `enumNameMappings` — to all enums with that value. Renaming a field in just one schema is impossible (checked in the code: `toVarName` and `toParamName` only do `nameMapping.containsKey(name)`).
2. **The keys of `inlineSchemaNameMappings` are unstable.** The key is a name the generator invented itself (`getPets_200_response`). It changes when the `operationId` changes, when the traversal order changes (`_1`), or when the deduplication rules change (change in 7.23, [#24177](https://github.com/OpenAPITools/openapi-generator/issues/24177)).
3. **Everything happens silently.** Rule firings are only logged (INFO/WARN/DEBUG), without a code, without a JSON pointer and without a machine-readable report. An unknown rule name gives only `WARN "Invalid openapi-normalizer rule name"`. **An exception inside the normalizer is caught and generation continues** with a half-normalized spec (`DefaultGenerator` L273–275).
4. **Stale overrides are not detected.** A mapping to a name that no longer exists is simply ignored (R3.2).
5. **Mappings bypass validation.** The docs explicitly warn that mappings are not checked at all, so the result may fail to compile if, for example, the new name is a reserved word.
6. **Rules are "big hammers".** `SET_TAGS_FOR_ALL_OPERATIONS` and `SET_PRIMITIVE_TYPES_TO_NULLABLE` act on the whole spec, and `REF_AS_PARENT_IN_ALLOF` changes the semantics of all `allOf`. There is no "only here" precision.
7. **The behaviour of rules changes between minor releases:** 4 rules became on by default in 7.0.0; a regression of `REF_AS_PARENT_IN_ALLOF` in 7.16 ([#22043](https://github.com/OpenAPITools/openapi-generator/issues/22043)); `fix(normalizer): restore behavior…` in 7.25 ([#24585](https://github.com/OpenAPITools/openapi-generator/pull/24585)).
8. **No rules for the typical defects of R2.1.** There are no rules for `required: bool`, an empty `$ref`, an array without `items`, undeclared path parameters, `examples` in 3.0 and duplicate enums. Some of them are "fixed" implicitly by swagger-parser (not verified), some break the generation.
9. **`FILTER` is include-only, without glob, and does not remove models** (there is no tree-shaking).
10. **Extension through `NORMALIZER_CLASS`** — a Java class on the classpath. This is powerful, but unavailable to a Dart developer.
11. There is no Overlay or JSON Patch: users ask for a preprocessor ([#22744](https://github.com/OpenAPITools/openapi-generator/issues/22744)).

---

## 5. Problems (with references and a "lesson")

### A. Naming
**P1. Inline names are generated from operationId and the HTTP code, and renames have already broken APIs.** Names look like `GetPets200Response`, `CreateUserRequest`, `FooGetDefaultResponse`, `…Inner`, `InlineObject1`. In v6.0.0 the naming scheme changed (`InlineResponse200` → `{OperationId}200Response`). PR [#12353](https://github.com/OpenAPITools/openapi-generator/pull/12353) carried the label **"Breaking change (without fallback)"**. The OAG examples still contain the outdated `inline_response_default.dart`. **(from the PR + checked in the code)**
→ **Lesson:** names from context (`<Parent><Property>`, `<Operation>Response`), without the HTTP code in the name, by default. A stable key for an override is the **place in the spec** (pointer), not the generated name. Any numeric suffix is a diagnostic with an override suggestion (R5.4, R2.5).

**P2. The FastAPI validation error model breaks the generator.** `ValidationError.loc: array<anyOf[string, integer]>` turns into an empty or invalid `ValidationErrorLocInner` ([#13302](https://github.com/OpenAPITools/openapi-generator/issues/13302) open since 2022, [#18913](https://github.com/OpenAPITools/openapi-generator/issues/18913)). **(from the issue)**
→ **Lesson:** primitive unions (R9.3) are needed from day one. It is worth having a built-in "FastAPI recipe" with a golden test on `HTTPValidationError`.

**P3. Deduplication of inline schemas changed the output in a minor release.** In 7.23.0 some of the previously generated files disappeared ([#24177](https://github.com/OpenAPITools/openapi-generator/issues/24177), open). There was also a regression there: inline enums with equal values on different properties were silently merged into one type ([#23978](https://github.com/OpenAPITools/openapi-generator/issues/23978), closed 2026-08). Now structural merging is limited to schemas with a `title` that are not enums (comments in `InlineModelResolver.matchGenerated`). **(from the issue + checked in the code)**
→ **Lesson:** deduplication must be explicit. Each merge is an info diagnostic with a list of locations. Changing the deduplication algorithm is a breaking change (R5.4, R15.4).

**P4. Name collisions are resolved silently or not at all.** A leading `_` is stripped, so `_type` and `type` give the same field (the OAG documentation itself gives this example). Reserved words and types from the mapping get the `Model` prefix (`ModelClient`, `ModelFile`, `ModelList`, `ModelReturn` — in the examples), only with a WARN log. Conflicts with `dart:core` and with members of base classes: `Type` ([#9029](https://github.com/OpenAPITools/openapi-generator/issues/9029)), static `name` in `EnumClass` ([#20910](https://github.com/OpenAPITools/openapi-generator/issues/20910), open), the `json` field shadowed in `toJson` ([#12127](https://github.com/OpenAPITools/openapi-generator/issues/12127)), "The name 'xxx' is defined in the libraries" ([#13931](https://github.com/OpenAPITools/openapi-generator/issues/13931)). **(checked in the code + from the issue)**
→ **Lesson:** deterministic collision resolution with a diagnostic code for each case (R5.2). Check conflicts with `dart:core`, with the members of `Object` and `Enum` (`name`, `index`, `values`, `hashCode`, `toString`, `runtimeType`) and with the model's own methods (`toJson`, `fromJson`, `copyWith`). Overrides also pass this check, unlike in OAG.

**P5. The documentation and the feature table do not match the code.** The table claims `Cookie ✓`, but cookie parameters are dropped. Issue [#17677](https://github.com/OpenAPITools/openapi-generator/issues/17677) says that `modelNameMappings` for dart-dio does not exist, although `AbstractDartCodegen.toModelName` supports it. **(checked in the code)**
→ **Lesson:** generate the support matrix (R15.5) from golden tests and fixtures, do not write it by hand.

### B. Polymorphism
**P6. In json_serializable mode there is no polymorphism.** `oneOf`, `anyOf`, `discriminator` and inheritance are not supported: `class Dog {}` instead of `Dog extends Pet` ([#21318](https://github.com/OpenAPITools/openapi-generator/issues/21318)), the properties of the parent are lost ([#22547](https://github.com/OpenAPITools/openapi-generator/issues/22547)). The item "Add polymorphism support to json_serializable" in [#13372](https://github.com/OpenAPITools/openapi-generator/issues/13372) has been open since 2022. `class.mustache` for json_serializable has no branch for `oneOf`/`anyOf`/`discriminator` at all **(checked in the code)**. Requests for freezed ([#19284](https://github.com/OpenAPITools/openapi-generator/issues/19284) — 14 reactions, [#21837](https://github.com/OpenAPITools/openapi-generator/issues/21837)) are open, and the PR with freezed ([#13047](https://github.com/OpenAPITools/openapi-generator/pull/13047)) was closed without merging.
→ **Lesson:** this exact gap is closed by the new tool (dio + json_serializable). A sealed hierarchy with an `Unknown(raw JSON)` variant (R9.1) and our own `fromJson` dispatcher by discriminator on top of json_serializable for the variants.

**P7. built_value polymorphism is inconvenient and fragile.** `OneOf get oneOf` has `Object value` and `isType(T)`, not sealed classes. An unknown discriminator gives `UnsupportedError` (`class_serializer.mustache` L164, **checked in the code**). Without a discriminator, "more than one match found" occurs ([#15373](https://github.com/OpenAPITools/openapi-generator/issues/15373)). `oneOf` + `allOf` loses properties ([#18380](https://github.com/OpenAPITools/openapi-generator/issues/18380)). A polymorphic request body is not serialized ([#16708](https://github.com/OpenAPITools/openapi-generator/issues/16708)). An enum as discriminator does not compile ([#21570](https://github.com/OpenAPITools/openapi-generator/issues/21570)). Java and Dart behave differently ([#21297](https://github.com/OpenAPITools/openapi-generator/issues/21297)). The problem "Polymorphism for dart-dio broken" ([#6160](https://github.com/OpenAPITools/openapi-generator/issues/6160)) has been open since 2020. **(from the issue)**
→ **Lesson:** exhaustive `switch` over sealed classes. An unknown type never throws an exception during decoding. A discriminator of any type (string, enum). Serializing a subtype automatically sets the discriminator.

**P8. Runtime dependency on dead packages.** `one_of` and `one_of_serializer` 1.5.0 were published on 2022-05-10 with `sdk <3.0.0`. Dart 3 resolves them only thanks to the SDK compatibility rule for SDK ≥2.12. **(checked via the pub.dev API)**
→ **Lesson:** R13.3 — our own small runtime without third-party "union" packages. Generate union types as sealed classes in code.

### C. Nullability / required
**P9. The required × nullable matrix is the main source of bugs.** Inline `type: ["object","null"]` in 3.1 gives a non-null field ([#23866](https://github.com/OpenAPITools/openapi-generator/issues/23866), 2026-05). `nullable: false` next to `$ref` (the typical ASP.NET output) is ignored ([#21565](https://github.com/OpenAPITools/openapi-generator/issues/21565)). There are other open items: "incorrect nullable when required" ([#21510](https://github.com/OpenAPITools/openapi-generator/issues/21510)), `includeIfNull` wrong for required ([#21508](https://github.com/OpenAPITools/openapi-generator/issues/21508)), a non-required non-nullable field gets null ([#18647](https://github.com/OpenAPITools/openapi-generator/issues/18647)), non-nullable fields become nullable ([#14320](https://github.com/OpenAPITools/openapi-generator/issues/14320)), a discussion "non-nullable without default → required?" ([#10972](https://github.com/OpenAPITools/openapi-generator/issues/10972)), the comment "This property should have been non-nullable!" in every field of `dart` ([#17222](https://github.com/OpenAPITools/openapi-generator/issues/17222), template `native_class.mustache` L27). **(from the issue + checked in the code)**
→ **Lesson:** R6.1 — an explicit documented table (required, nullable, default, request/response direction) → Dart type, with golden tests for every cell. Ambiguous cases — a diagnostic with an override. Handle separately `$ref` with sibling keys in 3.0 and `allOf:[$ref] + nullable` (NestJS, ASP.NET).

**P10. Checks that disappear in release.** In `dart`, the presence of required keys is checked only in `assert(...)` ("Note 2: this code is stripped in release mode!"). An unknown enum silently becomes `null` (`decode(allowNull = true)`). **(checked in the code)**
→ **Lesson:** R6.5 — the decoding error is always raised, in any build mode, with the path `Schema.field` and a JSON path.

### D. Enum
**P11. Unknown enum values are not solved.** `enumUnknownDefaultCase` is disabled by default. The sentinel is a real wire value (`'unknown_default_open_api'` / `11184809`), so the raw value is lost and the sentinel can be sent to the server (**checked in the code**, `DefaultCodegen` L7315). The option breaks with `useEnumExtension` ([#21411](https://github.com/OpenAPITools/openapi-generator/issues/21411)). For collections the enum was fixed only in 7.26 ([#22160](https://github.com/OpenAPITools/openapi-generator/issues/22160) → [#24673](https://github.com/OpenAPITools/openapi-generator/pull/24673)). An enum with `default` does not compile ([#20495](https://github.com/OpenAPITools/openapi-generator/issues/20495); regression in 7.16 — [#22120](https://github.com/OpenAPITools/openapi-generator/issues/22120); [#22561](https://github.com/OpenAPITools/openapi-generator/issues/22561)). Uppercase enums are not serialized ([#22399](https://github.com/OpenAPITools/openapi-generator/issues/22399)). Numeric enums are stored as `String value` (checked in the code).
→ **Lesson:** R8.1/R8.2 — a separate type for an unknown value with the raw value, which **cannot be passed in a request** (for example, `sealed` with `Known`/`Unknown` for responses and a closed `enum` for requests). A typed `value` (int/String/bool).

### E. Transport
**P12. The generator modifies the user's Dio.** Without `interceptors:`, `OAuthInterceptor`, `BasicAuthInterceptor`, `BearerAuthInterceptor`, `ApiKeyAuthInterceptor` are added to the passed `Dio`. If no Dio is passed, timeouts are hard-coded: 5 s and 3 s ([api_client.mustache#L26-L41](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/resources/dart/libraries/dio/api_client.mustache#L26-L41)). **(checked in the code)**
→ **Lesson:** R10.1 — accept only a ready `Dio` and change nothing in it. Hand auth to the user, but pass **metadata** (`extra`).

**P13. One response type, one content-type.** The smallest 2xx is taken. **If there is no 2xx, the success type becomes `default`**, which real specifications usually use to describe an error (checked in the code). For a body only the first content-type is taken. `text/plain` breaks the method ([#14904](https://github.com/OpenAPITools/openapi-generator/issues/14904)). A binary response is a `MultipartFile` ([#12161](https://github.com/OpenAPITools/openapi-generator/issues/12161), [#20682](https://github.com/OpenAPITools/openapi-generator/issues/20682)). Stream is not supported ([#6750](https://github.com/OpenAPITools/openapi-generator/issues/6750)).
→ **Lesson:** R10.6 — a union of successful responses by status. Treat `default` as an error unless there is an explicit override. A decoder by media type. A diagnostic if there are several content-types.

**P14. Errors are not typed.** HTTP, decoding and transport errors arrive as `DioException`. For decoding — `DioExceptionType.unknown` (checked in the code). In `dart` a decoding error is `ApiException(HttpStatus.internalServerError, …)`, a fake 500 (checked in the code).
→ **Lesson:** R11.1/R11.7 — separate types for `HttpError<E>` (with status and typed body), `DecodingError` (with a path) and `TransportError`.

**P15. Parameters.** deepObject is not supported ([#13584](https://github.com/OpenAPITools/openapi-generator/issues/13584), open). Cookie parameters are dropped: the templates do not handle `isCookieParam`, and [#12489](https://github.com/OpenAPITools/openapi-generator/issues/12489) was closed without a fix (checked in the code). In json_serializable `collectionFormat` is ignored. An optional nullable query parameter was sent empty instead of being omitted ([#24736](https://github.com/OpenAPITools/openapi-generator/issues/24736), closed 2026-08).
→ **Lesson:** R10.3 — a parameter serializer in the runtime package, covered by tests for all combinations of `style` × `explode` × type from the OAS table.

**P16. Multipart.** In json_serializable, models are passed to `FormData` without encoding ([#19420](https://github.com/OpenAPITools/openapi-generator/issues/19420), [#14472](https://github.com/OpenAPITools/openapi-generator/issues/14472)). Null fields are sent ([#10295](https://github.com/OpenAPITools/openapi-generator/issues/10295)). The content-type of parts (`encoding`) is not supported (checked in the code).
→ **Lesson:** R10.4 — typed parts with a content-type, JSON parts encoded explicitly.

**P17. The request is not tagged with `operationId`.** `extra` contains only `secure` (checked in the code). A timeout cannot be set for a single request ([#12645](https://github.com/OpenAPITools/openapi-generator/issues/12645), 11 reactions).
→ **Lesson:** R10.5 — `extra['openapi.operationId']`, `security`, the tag. A separate `Options` parameter to change anything, including timeouts.

**P18. Only the first `servers`** (`basePath`). In docs: `MultiServer ✗`, `ParameterizedServer ✗`. Open: [#7310](https://github.com/OpenAPITools/openapi-generator/issues/7310).
→ **Lesson:** R10.9 — generate constants or enums of servers with variables, but **do not** impose `baseUrl`.

**P19. Loss of type precision.** `decimal` → `double` (checked in the code). `int64` → `int` (on web 53 bits, [#14522](https://github.com/OpenAPITools/openapi-generator/issues/14522)). `string+int64` is not mapped to `BigInt` ([#21473](https://github.com/OpenAPITools/openapi-generator/issues/21473)). `uuid` → `String`. `format: date` → `DateTime` with a time zone shift bug ([#24703](https://github.com/OpenAPITools/openapi-generator/issues/24703), fixed in 7.25).
→ **Lesson:** R6.2 — a separate `Date` type (without time). For `decimal` by default — `String` or a diagnostic with a mapping suggestion. For int64 on web — a diagnostic or an option.

### F. Output quality and DX
**P20. The output is not clean under `package:lints/recommended`** (checked in the templates; membership of the rules checked in `lints-6.1.0/lib/recommended.yaml`):
- `/** … */` for enum descriptions → `slash_for_doc_comments`;
- `this.dio.interceptors` → `unnecessary_this`;
- `'Bearer ${token}'` → `unnecessary_brace_in_string_interps`;
- local `_path`, `_options`, `_response` → `no_leading_underscores_for_local_identifiers`;
- `import 'package:equatable/src/equatable_utils.dart'` → `implementation_imports`;
- `bool operator ==` without `@override` in the equatable branch → `annotate_overrides`;
- `@JsonKey(ignore: true)` — a deprecated json_annotation API.

The generated `analysis_options.yaml` excludes `test/*.dart` and `*.g.dart` and ignores `deprecated_member_use_from_same_package`. The `dart`/`dart-dio` templates contain about 27 `// ignore` / `ignore_for_file` directives. `dart format` runs only with `DART_POST_PROCESS_FILE` + `--enable-post-process-file`.
→ **Lesson:** R13.2 — a golden test "`dart analyze` with recommended + flutter_lints = 0 warnings" on a corpus of specifications. Formatting is built in (through `dart_style` as a library). No `ignore_for_file` for the whole file.

**P21. Extra files and accumulation of stale ones.** Documentation stubs, tests, README and pubspec are generated by default: 131 of the 217 files in the example are in `doc/` and `test/`. `dart` adds `git_push.sh` and `.travis.yml`. Stale files are not deleted: the OAG example contains `cat_all_of.dart`, `dog_all_of.dart`, `inline_response_default.dart`, which are not in `.openapi-generator/FILES` (checked in the code).
→ **Lesson:** R13.5 — generate only `lib`. The tool fully controls the output directory through a manifest and removes stale files (or asks).

**P22. build_runner is needed, and it is inconvenient to work with.** Both dart-dio modes require the user to run it. The request to run it automatically ([#15448](https://github.com/OpenAPITools/openapi-generator/issues/15448), 17 comments) is open. A syntax error in the generated code blocks build_runner on a large specification (Twitter v2, [#12306](https://github.com/OpenAPITools/openapi-generator/issues/12306)). The wrapper runs a nested `build_runner`. Slow generation of built_value on hundreds of models is a common community complaint **(not verified; I did not find a separate issue in the OAG tracker)**.
→ **Lesson:** open decision 1 — the `dart` generator proves that output without build_runner (handwritten `fromJson`) is real. If json_serializable stays, it is better to generate `.g.dart` ourselves (or drop build_runner entirely), so the output is ready immediately.

**P23. Two serialization backends are interwoven in one set of templates.** The API templates know about the serializer ([#15477](https://github.com/OpenAPITools/openapi-generator/issues/15477)). json_serializable has been in "[BETA]" status for years. The PRs to unify `dart`/`dart-dio` ([#14346](https://github.com/OpenAPITools/openapi-generator/pull/14346)) and for freezed ([#13047](https://github.com/OpenAPITools/openapi-generator/pull/13047)) were closed without merging. Test schemas are scattered ([#15449](https://github.com/OpenAPITools/openapi-generator/issues/15449)).
→ **Lesson:** one serialization backend, or a clear IR → emitter boundary (open decisions 2, 5, 6).

**P24. A type dispatcher by string at runtime.** `deserialize<T, B>(value, 'List<Pet>')` with `RegExp(r'^List<(.*)>$')` and `throw Exception('Cannot deserialize')` (checked in the code).
→ **Lesson:** generate direct calls `Pet.fromJson`. Errors — with type and path.

**P25. The output changes in minor releases.**
- 7.15.0: `copy_with_extension` added by default ([#21667](https://github.com/OpenAPITools/openapi-generator/pull/21667), labelled only "Enhancement"). Builds failed because the package required Dart ^3.8 while the pubspec set 3.5.0 ([#21815](https://github.com/OpenAPITools/openapi-generator/issues/21815)).
- 7.16: regression of the enum default ([#22120](https://github.com/OpenAPITools/openapi-generator/issues/22120)).
- 7.23: changes in deduplication ([#24177](https://github.com/OpenAPITools/openapi-generator/issues/24177)).
- 7.25: multi-line `x-enum-descriptions` produced invalid code ([#24858](https://github.com/OpenAPITools/openapi-generator/issues/24858)).

**(from the issue + PR)**
→ **Lesson:** R15.4 — a golden diff on a corpus of specifications in CI. Any output change is a major release or an opt-in flag.

**P26. Pinned dependency versions go stale.** The template has `copy_with_extension(_gen) ^7.1.0`, while on pub.dev it is 18.0.0 (2026-09-26). `equatable ^2.0.7` — on pub.dev 3.0.0, and besides, the import is from `src/`. `time_machine` — 2022. `one_of` — 2022. `dart`: `test: '>=1.21.6 <1.22.0'`, `intl: any` (checked in the code and through the pub.dev API).
→ **Lesson:** R13.3 — minimal dependencies, and the versions in the generated pubspec (if there is one) should be tested in CI against current packages.

**P27. Java.** OAG requires Java 11+, and the wrapper says Java 8 → `UnsupportedClassVersionError` ([#19024](https://github.com/OpenAPITools/openapi-generator/issues/19024)). On large specifications — `OutOfMemoryError` ([#11195](https://github.com/OpenAPITools/openapi-generator/issues/11195)). For Flutter teams, Java is an unnecessary dependency in CI.
→ **Lesson:** a clean Dart CLI (`dart run` / `dart pub global activate`).

**P28. The pub.dev wrapper lags behind and breaks resolution.** It bundles OAG 7.17.0 by default. `analyzer <9` conflicts with Flutter ([gibahjoe#201](https://github.com/gibahjoe/openapi-generator-dart/issues/201)). Error messages are unclear ([#202](https://github.com/gibahjoe/openapi-generator-dart/issues/202)). Normalizer flags are unavailable.
→ **Lesson:** R15.1 — do not make the generator depend on `analyzer` on the ordinary path (CLI-first). If there is a build_runner integration, it must be thin and versioned separately.

**P29. Global state and `dart:io` in `dart`.** `var defaultApiClient = ApiClient();`, `import 'dart:io'` (checked in the code).
→ **Lesson:** R4.3 — no global variables. Platform-independent code.

**P30. OAS 3.1 is in "beta", 3.2 is not supported, and unknown things are silently dropped** ([#22728](https://github.com/OpenAPITools/openapi-generator/issues/22728), [#24212](https://github.com/OpenAPITools/openapi-generator/issues/24212)).
→ **Lesson:** R0.1/R1.4/R2.5 — our own specification model with full 3.1 semantics (rather than a downgrade to 3.0). Unknown keys or methods — a warning with a pointer.

**P31. The normalizer guesses silently.** Self-references are replaced with any. Unsupported `allOf` subschemas are removed with a DEBUG log. A map without a value type becomes `String`. Normalizer exceptions are swallowed (checked in the code).
→ **Lesson:** R2.2/R2.5 — every such action is a diagnostic with a code and a pointer, and has a level that can be overridden.

---

## 6. What is worth borrowing

| Idea from OAG | For which requirement | How to improve |
|---|---|---|
| Named normalizer rules that are switched on individually, with an "on by default" set and `DISABLE_ALL` | R2.1 | Add the code, pointer, report and level. Document each rule with a **before/after diff**, as the docs do for `REPLACE_ONE_OF_BY_DISCRIMINATOR_MAPPING` |
| Specific rules: `SIMPLIFY_ONEOF_ANYOF` (null variant → nullable, a single variant → the schema itself), `SIMPLIFY_ONEOF_ANYOF_ENUM`, `REFACTOR_ALLOF_WITH_PROPERTIES_ONLY`, `FIX_DUPLICATED_OPERATIONID`, `REMOVE_PROPERTIES_FROM_TYPE_OTHER_THAN_OBJECT`, `LOOSE_NULL_DEFINITIONS`, `ADD_UNSIGNED_…` | R2.1, R5.2 | Take as the starting catalog of rules. Each firing is an info diagnostic |
| `FILTER` with the syntax `operationId:a\|b ; tag:x ; path:/v1 ; method:get` and the `x-internal` marker | R4.1 | Add exclude, glob and **tree-shaking of models** |
| `SET_TAGS_TO_VENDOR_EXTENSION`, `KEEP_ONLY_FIRST_TAG_IN_OPERATION` | R5.3 | Plus a mapping "tag → class name" in the overrides |
| A family of mappings (`name`, `parameterName`, `modelName`, `enumName`, `operationIdName`, `inlineSchemaName`, `schemaMappings`, `typeMappings` + `importMappings`) | R3.1, R6.2 | Merge into **a single overrides file addressed by pointer / operationId / `Schema.prop`**. An unused override → warning; an override that matches the spec → hint (R3.2). Check the result for reserved words |
| `schemaMappings` ("bring your own model") | R6.2, R6.4 | Override "type = external Dart type + import", in particular for envelopes and generics |
| `inlineSchemaOptions` (`ARRAY_ITEM_SUFFIX`, `MAP_ITEM_SUFFIX`, `RESOLVE_INLINE_ENUMS`, `SKIP_SCHEMA_REUSE`) and the priority of `title` | R5.4 | The same settings, but deduplication by default only for enums with an identical set of values, and with a diagnostic |
| A hint in the log "set the `title` field or use inlineSchemaNameMapping" | R2.5 | Turn it into a diagnostic with a ready-made YAML override snippet |
| `extra['secure']` with a security description for interceptors | R10.8 | Add `operationId`, the tag, and the AND/OR semantics of requirements. Do not impose interceptors |
| Method signature: `cancelToken`, `headers`, `extra`, `validateStatus`, `onSendProgress`, `onReceiveProgress` + returning `Response<T>` | R10.5, R10.6 | Add `Options? options` (timeouts) |
| The pair `xxx()` / `xxxWithHttpInfo()` in `dart` | R10.6, R11.2 | An analogue: `xxx()` returns T, `xxxRaw()` / `Result` gives full access |
| `Optional<T>` (`Absent`/`Present`) + the trick `@JsonKey(readValue: readOptionalValue)` with a sentinel to tell an absent key from null in json_serializable; `patchOnly` | R7.1–R7.3, open decision 7 | Make it `sealed`. Support inline PATCH bodies as well. The tri-state rule is configurable (R7.2) |
| `enumUnknownDefaultCase` as a concept (in built_value it is `fallback: true`) | R8.1 | But keep the raw value and forbid sending it |
| `splitOperationsByContentType` with deterministic naming `With<Subtype>` / `As<Subtype>` | R10.4, R10.6 | Take the naming scheme for operations with several media types |
| `.openapi-generator/FILES` + `--minimal-update` + `--dry-run` | R13.1, R14.1 | A manifest for removing stale files. Write only the changed files (friendly to IDEs and build_runner). `--dry-run` → a full diff and a report of breaking changes |
| `--global-property debugOpenAPI / debugModels / debugOperations` (a dump of the normalized spec and the intermediate model to JSON) | R15.3, R2 | The `inspect` command / `--emit-ir` for debugging and IR golden tests |
| `validate --recommend` | R2.4, R15.6 | A `check` mode with the same diagnostics as generation |
| `batch` with `!include` | R1.3 | One config with several specs |
| `bin/configs/*.yaml` + committed `samples/` as goldens in CI | R15.3 | Plus `dart analyze` and runtime decoding tests on every golden |
| `x-enum-varnames` / `x-enum-descriptions` / `x-enum-values` | R8.4 | Support them and document them in the `x-` registry |
| `--model-name-prefix/suffix`, `--remove-operation-id-prefix` | R4.3, R5.1 | Generalize to regex transformations |
| `NORMALIZER_CLASS` (a custom normalizer as a plugin) | Open decision 6 | If extensibility is needed, a Dart API for rules, but only after declarative overrides |

### What to definitely **not** repeat (briefly)
1. Silent fixes and logs without codes (P31).
2. Mappings by raw name without addressing and without detection of stale ones (§4.3).
3. Changing the user's `Dio` and hardcoded timeouts (P12).
4. `default` as a successful response (P13).
5. A sentinel unknown enum value as a real wire value (P11).
6. Checks in `assert` (P10).
7. Two serialization backends in the same templates (P23).
8. Docs/test stubs by default (P21).
9. Changes to output in minor releases (P25).
10. Java (P27).

---

## 7. Sources

**OAG code (master `9f6536eca424fd3ca139f01b7d1727d5912f396f`, 2026-10-09):**
- `docs/generators/dart-dio.md`, `docs/generators/dart.md`, `docs/customization.md` (Selective generation, Ignore file, Name/Schema Mapping, Inline Schema Naming, OpenAPI Normalizer), `docs/usage.md` (`validate`, `generate`, `batch`), `docs/global-properties.md`, `docs/installation.md`, `README.md` (L168 — 3.1 beta; L1264 — Dart TC), `pom.xml` (L1250 — Java 11)
- `resources/dart/libraries/dio/{api,api_client,pubspec,analysis_options,optional,model,class,header,lib}.mustache`, `auth/*.mustache`
- `resources/dart/libraries/dio/serialization/json_serializable/{class,enum,enum_inline,dart_constructor,deserialize,build.yaml}.mustache`, `api/{serialize,deserialize,query_param,imports,constructor}.mustache`
- `resources/dart/libraries/dio/serialization/built_value/{class,class_serializer,class_members,enum,api_util}.mustache`, `api/*.mustache`
- `resources/dart2/{apilib,api,api_client,api_helper,api_exception,pubspec}.mustache`, `serialization/native/{native_class,native_enum}.mustache`
- `java/.../languages/{AbstractDartCodegen,DartDioClientCodegen,DartClientCodegen}.java`, `java/.../{OpenAPINormalizer,InlineModelResolver,DefaultGenerator,DefaultCodegen}.java`
- `samples/openapi3/client/petstore/dart-dio/{petstore_client_lib_fake,petstore_client_lib_fake-json_serializable,oneof,anyof,oneof_polymorphism_and_inheritance}`; `bin/configs/dart*.yaml`

**Releases:** https://github.com/OpenAPITools/openapi-generator/releases (v7.17.0–v7.26.0); v6.0.0 (breaking changes Inline model resolver).

**Issues/PR OAG** (https://github.com/OpenAPITools/openapi-generator/issues/N): #6123, #6160, #6750, #7057, #7310, #8179, #9029, #10295, #10972, #11195, #12127, #12161, #12306, #12489, #12645, #13302, #13372, #13584, #13931, #14320, #14472, #14522, #14904, #15373, #15448, #15449, #15477, #16708, #17222, #17677, #18380, #18647, #18913, #19024, #19284, #19420, #20495, #20682, #20910, #21297, #21318, #21411, #21473, #21508, #21510, #21565, #21570, #21815, #21826, #21837, #22043, #22120, #22160, #22399, #22547, #22561, #22728, #22744, #23665, #23866, #23978, #24177, #24212, #24703, #24736, #24858.
PR: #12104, #12295, #12353, #13047, #14346, #21667, #22257, #23386, #23571, #23696, #23930, #24352, #24585, #24605, #24673, #24706, #24868, #24881.

**Wrapper:** https://github.com/gibahjoe/openapi-generator-dart (master; `openapi-generator-cli/lib/src/models.dart`, `openapi-generator-cli/bin/main.dart`, `openapi-generator-annotations/lib/src/openapi_generator_annotations_base.dart`, `openapi-generator/lib/src/openapi_generator_runner.dart`, CHANGELOGs, `openapi-generator/README.md`); issues #136, #151, #201, #202; https://pub.dev/packages/openapi_generator.

**pub.dev API** (`https://pub.dev/api/packages/<name>`, 2026-10-11): `one_of` 1.5.0 (2022-05-10), `one_of_serializer` 1.5.0 (2022-05-10), `openapi_generator*` 7.0.0 (2026-05-31), `copy_with_extension(_gen)` 18.0.0 (2026-09-26), `equatable` 3.0.0, `dio` 5.11.1, `json_serializable` 6.14.1, `built_value` 8.13.0, `time_machine` 0.9.17 (2022-04-16).

**Lints:** `package:lints` 6.1.0 `lib/recommended.yaml` (local pub-cache) — whether the rules `slash_for_doc_comments`, `unnecessary_this`, `unnecessary_brace_in_string_interps`, `no_leading_underscores_for_local_identifiers`, `implementation_imports`, `annotate_overrides` belong to it.
