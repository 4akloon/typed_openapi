# Requirements for an OpenAPI → Dart code generator (from the project author)

Goal: an in-house OpenAPI codegen for Dart that covers the features of competitors and all capabilities of OpenAPI ≥ 3.0, works on **dio** and **json_serializable**.

## 0. Positioning and non-goals

* R0.1 [MUST] Generates a client for Dart and Flutter from OpenAPI 3.0 and 3.1. The generated code is plain Dart, without Flutter.
* R0.2 [MUST] The target audience is teams whose spec is imperfect: generated from code (NestJS, FastAPI, Spring, ASP.NET) and containing defects. For this reason, tolerance of defects and the override mechanism are one of the main capabilities, not a minor detail.
* R0.3 Non-goals: server stubs, Swagger 2.0 (at least at the start), generation of domain models and repositories, a mock server.

## 1. Input and spec parsing

* R1.1 [MUST] Input is a local JSON or YAML file. A URL with authorization is supported only as an optional download, and generation always runs from a local snapshot so that the build is reproducible.
* R1.2 [MUST] Resolves `$ref` inside the document and to other files, and catches circular references.
* R1.3 [MUST] Several specs in one project, each with its own config and output directory. One run generates several clients.
   * One config file with a `clients` section; shared settings are set once and inherited, and each client can override them (like `schemes:` in swagger_parser).
   * Each client has its own overrides, baseline, entry in the lock file and diagnostics.
   * Each client is a separate library with its own namespace: identical model names (`User`) in two clients do not conflict (R4.3), and there is no shared barrel file between clients.
   * Output directories of different clients cannot overlap: this is an error diagnostic (in swagger_parser, several `schemes` overwrite a shared `export.dart`, #405).
   * The CLI generates or checks all clients together or one by name.
   * All clients use the same `typed_openapi_runtime`.
   * Shared models between clients (for example, one error schema for several services) are not in v1.

   ```yaml
   # typed_openapi.yaml
   defaults:
     line_width: 100
     preset: nestjs
   clients:
     core_api:
       input: specs/core_api.json
       output: lib/src/api/core_api
       overrides: specs/core_api.overrides.yaml
     payments:
       input: specs/payments.yaml
       output: lib/src/api/payments
       preset: fastapi
   ```
* R1.4 [SHOULD] OAS 3.2 at least in the `itemSchema` part for streams. The rest of 3.2 can be added later.

## 2. Tolerance of defects and diagnostics

* R2.1 [MUST] Specification normalizer. A set of named rules finds typical defects. Unambiguous ones (the answer follows from the spec or the protocol: `required: bool` in a schema, duplicate enum values, undeclared path parameters) are fixed by the rule; the rest are a diagnostic explaining what to fix in the source, plus a ready-made override (R2.5). Constructs outside OpenAPI (`$ref` in disallowed places, YAML 1.1 tags) are not supported, only diagnosed. Each rule is turned on and off separately. Every firing goes into the report. Design: [superpowers/specs/2026-10-11-m3-normalizer-design.md](superpowers/specs/2026-10-11-m3-normalizer-design.md).
* R2.2 [MUST] Diagnostics with levels error, warning and info. Each message has a stable code (like `SG012`), a JSON pointer to the place in the spec, and an explanation of what to fix in the source. The level of each code can be overridden in the config.
* R2.3 [MUST] Baseline / ratchet. Existing violations can be recorded in a file. New ones that are not in the baseline fail generation. When a violation disappears, the tool suggests removing it from the baseline.
* R2.4 [SHOULD] "Check only" mode (`check`/`lint`): the same analysis without generation. The backend team's CI can use it.
* R2.5 [MUST] Never guess silently. If the tool cannot generate code unambiguously, it issues a diagnostic and proposes a specific override.

## 3. Overrides

* R3.1 [MUST] A separate overrides file that addresses a place in the spec: an operation by `operationId` or path+method, a schema, a property or a parameter. With it one can change: the name; the type; `required` and `nullable`; the format; the `oneOf` discriminator; the body content type; the schemas of SSE events; exclusion of an element from generation.
* R3.2 [MUST] An override on an element that no longer exists gives a warning and does not break generation. An override that matches the fixed spec gives a hint that it can be removed.
* R3.3 [SHOULD] Overrides can also be given as JSON Patch or as an overlay (OpenAPI Overlay 1.0).

## 4. Choosing what to generate

* R4.1 [MUST] Filtering by tags, `operationId` and paths (glob), in include and exclude modes.
* R4.2 [MUST] Tree-shaking: only schemas reachable from the selected operations are generated.
* R4.3 [MUST] The output can be safely combined with the user's existing code: a prefix or a namespace, its own library, no global side effects.

## 5. Naming

* R5.1 [MUST] Operation names come from `operationId` or from path+method. Transformations: regex prefix, case, version suffix.
   * The method name follows the scheme: `operationId` in lowerCamelCase. The tool does not shorten anything or add anything by heuristics. Any transformation is only explicit, in the config or in a preset (e.g. the `nestjs` preset strips `XController_`: `UserController_get` → `get`; without the preset — `userControllerGet`).
   * Schema names are as in the spec: suffixes such as `Dto` are not removed automatically.
* R5.2 [MUST] Deterministic resolution of collisions with diagnostics: reserved words and names from `dart:core`; identical names in path and query; duplicate schema names; names that coincide after normalization.
* R5.3 [MUST] Grouping operations into classes by tag (configurable), with normalization of "dirty" tags.
   * A class per tag with the suffix `Api` (`UsersApi`); the name template is configurable (`naming.group: '{Tag}Api'`). The root client class has the groups as fields: `api.users.getUser()`.
   * An operation with several tags goes into the group of the first tag (without duplicating methods); the other tags get an info diagnostic.
   * Operations without a tag go into `DefaultApi` (the name is configurable) plus a diagnostic.
   * Tag normalization: case, spaces, `-`, `_`. Tags that coincide after normalization are merged with a diagnostic. Non-Latin or "descriptive" tags give a warning with a ready-made override of the group name.
   * `group_by` strategies: `tag` (default), `path` (the first path segment), `single` (one class).
   * Overrides: renaming a tag (`tags: {pet-controller: Pets}`) and moving an operation to another group (`operations.<id>.group`).
   * Nested groups (OAS 3.2 `tag.parent`, tags with a dot) — later.
* R5.4 [MUST] Naming of inline schemas and inline enums: from context (`<Parent><Property>`), with deduplication of identical value sets, and with overrides.

## 6. Data model

* R6.1 [MUST] An explicit `required` × `nullable` matrix, separately for requests and responses, with a separate mode for partial updates (R7).
* R6.2 [MUST] Type mapping: primitives, `format` (`date-time`, `date`, `uuid`, `byte`, `binary`, `int64`); `additionalProperties`; nested arrays; arbitrary JSON values as a separate type rather than `dynamic`. The mapping of primitives is configurable (`Decimal`, a custom `Date`).
   * Numbers: `type: integer` → `int`; `type: number` with `format: float`/`double` → `double`; `type: number` without a format → `num` (per the spec this is any number, whole or fractional). Decoding into `double` always goes through `(v as num).toDouble()`, because `jsonDecode('1')` gives `int`. The global mapping (`types: {number: double}`) and a field override (`type: integer`) are for backends that write `number` for whole values too (NestJS).
* R6.3 [MUST] `allOf`: several parts are merged into a flat model, and a single `$ref` (including a nullable one) becomes a reference to the type.
* R6.4 [MUST] Envelopes and generics (`{data: T}`, pagination) as generic types; recognition via `x-` or a pattern in the config.
   * By default the envelope `{data: T}` (the only required property `data`) is **unwrapped**: the method returns `T`. The alternative in the config is the generic `ApiData<T>`. Schemas with `data` and other fields (`{data, grantedCredits}`) remain ordinary models.
* R6.5 [MUST] Extra fields in a response are ignored. A missing required field is a clear decoding error (schema, field, path in the JSON).
* R6.6 [SHOULD] Optional: `==`/`hashCode`, `copyWith`, `toString`.
* R6.7 [SHOULD] Constraints (`minLength`, `pattern`, `minimum`) as metadata or optional validation (disabled by default).

* R6.8 [MUST] Custom types and converters. A type can be replaced with your own for a `format` (`types.formats`), for a schema (`types.schemas`: no model is generated, all `$ref`s point to this type) and for a field or parameter (override, R3.1). Entry: `{type, import, converter?}`.
   * Without `converter`, the type follows the json_serializable contract: `fromJson(S)` (a constructor or a static method) and `S toJson()`. Extension types also fit.
   * With `converter` — any class with a `const` constructor and methods `T fromJson(S)` / `S toJson(T)`. Implementing `JsonConverter` is not required, but classes that implement it also fit.
   * `S` is the JSON type: taken from the schema (`string` → `String`, `integer` → `int`, `object` → `Map<String, Object?>`) or given explicitly.
   * Path, query and header parameters are encoded through the result of `toJson` and the style codec (R10.3).
   * The generator adds no dependencies: neither `json_annotation`, nor a converter interface in the runtime. Signatures are checked by `dart analyze` on the generated code; an incomplete entry (without `type` or `import`) is a `check` diagnostic.

## 7. Partial updates (PATCH)

* R7.1 [MUST] Three states of a field in the request body: absent, explicit `null`, value — distinguished at the type level.
* R7.2 [MUST] The tri-state rule is configurable. Default: optional + nullable in the PATCH body. Alternatives: any optional, an `x-` extension, override.
* R7.3 [MUST] A field with one state never sends null unless it is set (protection against overwriting, as in tonik and swagger_to_dart).

## 8. Enum

* R8.1 [MUST] An unknown value does not break decoding; the raw value is available (rather than being lost, as in swagger_parser and tonik).
* R8.2 [MUST] An unknown value cannot be sent in a request.
* R8.3 [MUST] String, numeric and boolean enums; deterministic names for invalid identifiers.
* R8.4 [SHOULD] `x-enum-varnames`, `x-enum-descriptions`.

## 9. Polymorphism

* R9.1 [MUST] `oneOf`/`anyOf` with `discriminator` (with and without `mapping`) → a closed hierarchy with a variant for an unknown type that keeps the raw JSON.
* R9.2 [MUST] `oneOf` without a discriminator — a diagnostic with configured behaviour: error, choice by structure (opt-in), or the raw value.
* R9.3 [SHOULD] Mixed primitives (`string | number`, `string | Ref`) — a wrapper type.

## 10. Operations and transport

* R10.1 [MUST] The user passes their own HTTP client with interceptors. The generator does not overwrite settings (`baseUrl`) and adds nothing.
* R10.2 [MUST] HTTP-level errors pass through the client's normal path (for Dio — `onError`). With `validateStatus: (_) => true` in tonik this does not happen.
* R10.3 [MUST] Path, query, header and cookie parameters; styles `form`, `explode`, `deepObject`, `pipeDelimited`.
* R10.4 [MUST] Bodies: JSON, `multipart/form-data` (typed parts, files, content type of parts), `x-www-form-urlencoded`, binary.
* R10.5 [MUST] For each call: cancellation, progress, extra headers, metadata for interceptors. Each request is marked with its own `operationId`.
* R10.6 [MUST] Several 2xx, 204 without a body, access to headers/status; non-JSON bodies.
* R10.7 [MUST] The generated API can be mocked by any mock library without code generation. It is an ordinary class without the `final`/`base`/`interface` modifiers: Dart's implicit interface is enough for `implements` (mocktail, fakes). Separate abstract interfaces are not generated.
* R10.8 [SHOULD] `securitySchemes`/`security` as operation metadata for interceptors.
* R10.9 [SHOULD] Several `servers` and server variables.

## 11. Errors

* R11.1 [MUST] Errors are typed by 4xx/5xx/`default`.
* R11.2 [MUST] The delivery model is configurable: exception, `Result<T, E>` or both; compatible with R10.2.
* R11.3 [MUST] An undocumented status is a separate variant with the status and the raw body.
* R11.4 [MUST] A shared error schema is generated once.
   * If all documented errors of an operation have one schema, the operation's error type is that schema itself (`ApiResult<T, BaseErrorResponseDto>`). A sealed type by status is generated only when the statuses have different schemas.
   * 4xx/5xx responses without a body are decoded by `errors.default_schema` from the config.
* R11.5 [SHOULD] Error codes as a contract (an enum with unknown + a list of codes per operation).
* R11.6 [SHOULD] Polymorphic error details per R9.
* R11.7 [MUST] Transport failures are separated from HTTP errors in the types.

## 12. Streams (SSE)

* R12.1 [MUST] `text/event-stream` → a method that returns a `Stream` of typed events. GET and POST.
* R12.2 [MUST] Event schemas from OAS 3.2 `itemSchema`, `x-` extensions or override; an unknown event is a separate variant.
* R12.3 [MUST] The SSE protocol per WHATWG: `event`, multi-line `data`, `id`, `retry`, comments.
* R12.4 [MUST] Stream transport through the same user client.
* R12.5 [SHOULD] Reconnection with a policy and `Last-Event-ID`, can be turned off.
* R12.6 [LATER] NDJSON / JSONL.

## 13. Output code

* R13.1 [MUST] Deterministic output, byte for byte.
* R13.2 [MUST] Clean under `package:lints/recommended` and `flutter_lints`, `dart format`, line width configurable.
* R13.3 [MUST] Minimal runtime dependencies; the runtime package is small, stable, and versioned separately.
* R13.4 [SHOULD] `summary`/`description`/`deprecated` → doc comments and `@Deprecated`.
* R13.5 [SHOULD] The output size is proportional to the selected operations; no test/doc stubs by default (as in dart-dio).

## 14. Spec evolution

* R14.1 [MUST] A report of changes between regenerations; separately — breaking changes of the Dart API.
* R14.2 [SHOULD] A new enum value / union variant / optional field does not break the consumer's compiled code.

## 15. Product

* R15.1 [MUST] CLI and programmatic API; `build_runner` — an open question.
* R15.2 [MUST] Config with a JSON Schema, clear validation errors.
* R15.3 [MUST] Golden tests; public specs (Petstore, Stripe, GitHub, OpenAI, Kubernetes) compile and pass the analyzer; runtime decoding tests.
* R15.4 [MUST] Semver; a change of output for the same input = breaking change.
* R15.5 [MUST] Documentation: OpenAPI support matrix, `x-` registry, catalog of diagnostic codes, recipes for NestJS/FastAPI/Spring.
* R15.6 [SHOULD] An advisory `lint` for the backend.

## Open decisions

> **All eight decisions were made on 2026-10-11** (the seventh — provisionally). The summary is in [research/README.md](research/README.md#decisions-made-2026-10-11). Decision 8 (`switch` exhaustiveness) was added following the research.

1. Output type: annotated code + `build_runner` (retrofit, json_serializable) or ready code without `build_runner`.
2. Serialization: own, or json_serializable / dart_mappable / freezed.
3. HTTP layer: only Dio, or an abstraction with adapters (Dio, `package:http`).
4. Default error model: exception or `Result`.
5. Parser: own or existing (`tonik_parse`/`tonik_core` or another); isolation of the spec model from generation.
6. Extensibility: templates, generator plugins, or only config and overrides.
7. Representation of the three states (R7) and of the raw enum value (R8.1) in the public API.
