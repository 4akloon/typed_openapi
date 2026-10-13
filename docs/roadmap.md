# typed_openapi stage map

Date: 2026-10-11. Each stage is a separate plan in `superpowers/plans/`, and each delivers a working, tested result. Requirements: [requirements.md](requirements.md); accepted decisions: [research/README.md](research/README.md).

## Stages

| # | Stage | What appears | Requirements | Depends on |
|---|---|---|---|---|
| M1 | Skeleton and `check` | Diagnostics (stable codes, JSON pointer, positions, text/json formats), loading of JSON and YAML, config with several clients, CLI `check`, programmatic API. Plan: [2026-10-11-m1-check-cli.md](superpowers/plans/2026-10-11-m1-check-cli.md) | R1.1, R1.3, R2.2 (partial), R2.4, R15.1, R15.2 (partial) | — |
| M2 | Spec model and `$ref` | Lossless tree → typed model (a superset of OAS 3.2); `$ref` resolver within a document and between files, cycles; dialect detected from content (TOA020–022, in research — SG001–003); tracking of unknown keys. Plan: [2026-10-11-m2-spec-model-refs.md](superpowers/plans/2026-10-11-m2-spec-model-refs.md) | R0.1, R1.2, R1.4, R2.1 (partial) | M1 |
| M3 | Normalizer | Own YAML composer on parser events; rules over the model: unambiguous fixes, the rest as diagnostics ([design](superpowers/specs/2026-10-11-m3-normalizer-design.md)). First — tasks from the corpus run (see "Moved from M2"). Engine of named rules, each switched on separately, a report of every firing, presets; `generic` and `nestjs` rules (catalog in [research/06 §C](research/06-spec-versions-and-defects.md)) | R2.1, R2.5 | M2 |
| M4 | Overrides | `typed_openapi.overrides.yaml` with logical addressing (operation, schema, property, parameter); spec fields are applied to normalizer rules, generation fields are kept for M6; a stale or null override → diagnostic; M3 rule hints with a ready override snippet ([design](superpowers/specs/2026-10-12-m4-overrides-design.md)). Overlay 1.2 / JSON Patch — later | R3.1, R3.2, (R3.3) | M3 |
| M5 | Baseline and severity levels | Baseline with fingerprints, `baseline create` / `prune`, severity level overrides in the config (including `off`), `sarif` and `github-actions` formats, paths relative to the working directory ([design](superpowers/specs/2026-10-12-m5-baseline-severity-design.md)) | R2.3, R2.2 (rest) | M3 |
| M6 | Semantic IR and Dart mapping | Naming and collisions, inline schemas; filters and tree-shaking; required × nullable matrix; types and formats; `allOf`; envelopes; custom types and converters; tri-state rule | R4, R5, R6.1–R6.4, R6.8, R7.2 | M3, M4 |
| M7 | Runtime | `ApiResult` and errors, `Patch<T>`, `JsonReader` with pointer, `JsonValue`, parameter style codecs, `sendRequest` on Dio, SSE decoder per WHATWG | R6.5, R7.1, R10.1–R10.3, R10.5, R11.2, R11.3, R11.7, R12.3 | — (in parallel with M2–M6) |
| M8 | Model emitter | Classes (not `final`) with `fromJson`/`toJson`, deep `==`/`hashCode`, `toString` without secrets; open enum, union with unknown (discriminator, JSON type, `union: structural`), polymorphism via `allOf`, tri-state, constraints and values as doc comments, own code layout without `dart_style` (`// dart format off`), determinism, the `generate` command for models: atomic swap of the output directory and a file manifest. No `copyWith` | R6.5–R6.8, R7, R8, R9, R13 | M6, M7 |
| M9 | Operation emitter and `generate` | Groups by tag, root client, parameters and bodies (JSON, multipart, form, binary), responses, typed errors, security metadata, servers; `generate` (which already writes models from M8) adds the operations. Plan: [2026-10-13-m9-operations.md](superpowers/plans/2026-10-13-m9-operations.md) | R5.3, R10.4, R10.6–R10.9, R11.1, R11.4–R11.6 | M8 |
| M10 | SSE | Methods returning a `Stream` of events, schemas with `itemSchema`, `x-` or override, reconnection with `Last-Event-ID` | R12.1, R12.2, R12.4, R12.5 (R12.6 later) | M9, M7 |
| M11 | Corpus and golden tests | Public specifications (Petstore, Stripe, GitHub, OpenAI, Kubernetes) compile and pass the analyzer; runtime decoding tests; matrix of SDK and formatter versions; fuzz of string escaping | R15.3, R15.4, R2.6 | M9 |
| M12 | Evolution | `diff` between regenerations with change categories (including source-breaking for an exhaustive `switch`), lock file | R14 | M9 |
| M13 | Documentation and product | Support matrix, `x-` registry, code catalog, recipes for NestJS / FastAPI / Spring / ASP.NET, JSON Schema of the config, `lint` mode for the backend, optional `build_runner` | R15.2, R15.5, R15.6, R15.1 (partial) | all |

## Order

1. M1 → M2 → M3 — the critical path.
2. M7 (runtime) does not depend on the parser; it can be done in parallel with M2–M6.
3. M4 and M5 can be done in parallel after M3.
4. The first useful result: after M3 the `check` command already catches defects in real NestJS specifications ([research/06 §C.1a](research/06-spec-versions-and-defects.md)).
5. The first generated client — after M9.

## Rules for plans

- One plan = one stage. Tasks of 2–5 minutes each, TDD, one commit per task.
- The plan contains all the code, without stubs. The code is checked (tests, `dart analyze`, `dart format`) before it goes into the plan.
- New diagnostic codes are added to the `DiagnosticCode` catalog with a doc comment: M13 generates the public catalog from it.

## Moved from M1

M1 review findings that were deliberately deferred:

| What | Where |
|---|---|
| YAML keys `1` and `"1"` silently merge into one | M2, Task 1 of the plan (TOA002) |
| Paths in the report: the config as entered, specifications relative to the config; choose one base | before the `github-actions` format (M5) |
| Very deep nesting (20 000 levels) gives `StackOverflowError` | M2, Task 2 of the plan (TOA007) |
| `--help` prints via `print`, ignoring the passed `out` | when a help test is needed |
| A directory instead of a file in `input`/`--config` is described as "does not exist" | M2, Task 1 of the plan |
| `JsonPointer.parse` does not check the `~` escaping | when pointers start coming from the user (M4) |
| Order of TOA005/TOA003, and only TOA002 for a `.json` with a duplicate and a syntax error | M2, Task 1 of the plan |

## Moved from M2

The first M3 tasks come from the `check` run on the corpus ([research/08 §First run](research/08-test-corpus.md)); without them two of the 13 real specifications are in effect not checked:

1. YAML tags outside the JSON Schema ruleset (`!!timestamp`, `!!binary`, `!!set`, custom ones) — a clear error with a reference to the OAS rule; reading continues to show the remaining problems (Artemis, springdoc: `example: !!timestamp '…'`). There is no YAML 1.1 support: OAS requires YAML 1.2 with the JSON Schema ruleset.
2. `$ref` where OAS does not allow it (an operation, `description`): a separate diagnostic instead of TOA110, with the hint "the specification is meant for a bundler — build it with `redocly bundle`" (DigitalOcean). There is no substitution of "`$ref` anywhere": it is a bundler convention, not OpenAPI.
3. A hint for `$ref: #/...` without quotes in YAML (`#` starts a comment, the value becomes `null`; Grace).

M2 review findings that were deliberately deferred:

| What | Where |
|---|---|
| A `$ref` to `file:///` reads any local file without a directory or size limit | after M9: `diff` (M12) or before 1.0; `generate` writes only into its own output and never deletes an input, and a `$ref` reads a file the user's own spec names (M9 plan, "Carried over") |
| Sibling keys next to `$ref` in a Path Item (allowed in OAS) are not merged with the target | when needed: OAS leaves a conflict undefined and TOA110 reports every sibling, so nothing is lost silently; merging needs a change to the parser (M9 plan) |
| Case-insensitive file systems: `A.yaml` and `a.yaml` are two documents | when needed (diagnostic or URI normalization) |
| The YAML merge key `<<` gives no hint that OpenAPI tools often do not support it | M3 (a normalizer rule or a hint) |
| The model is immutable only on the surface: lists and maps inside nodes are read-only, but not deeply | M3, when the normalizer starts building new nodes |
| `$ref` in `callbacks` and `links` does not resolve | with the generation of callbacks: M9 does not generate them and reports callbacks and webhooks (TOA567); links are never read (M9 plan) |
| `in` in an `apiKey` security scheme is not required when reading | done in M9 (task 2: TOA112, as for `name`) |
| Positions in diagnostics for files reached through `$ref` are relative paths, not absolute URIs | M5 (`sarif`, `github-actions` formats) |
| A place read as nodes of two different types silently returns `null` for the second | M3 (diagnostic for a type conflict) |
| A diagnostic on a node obtained through a YAML alias points to the anchor's position | when needed (a rare case) |
| A deep document without aliases keeps a long pointer for each node (memory O(nodes × depth)) | when needed (pointers as a parent chain) |
| The `package:yaml` scanner is quadratic on a long flow line; brackets hidden in quotes (`["]",` × N) bypass the preliminary count: ~1 MB → ~57 s (no crash) | M3: own composer on an own copy of the scanner with two edits; upstream — [dart-lang/tools#2657](https://github.com/dart-lang/tools/issues/2657) |
| No tests for several YAML documents in one file and for the case with brackets in quotes | a parallel robustness track |
| The check on events catches only `YamlException`; a parser `assert` in checked mode may escape | M3 (own composer) |
| The check on events counts depth also in collection keys, the converter does not | M3 (own composer, a single depth) |

## Moved from M3

M3 review findings that were deliberately deferred (all of them are on invalid specifications or cosmetic; deterministic):

| What | Where |
|---|---|
| A `$ref` in place of a whole map (`paths: {$ref}`, `components.schemas: {$ref}`, `security: [{$ref}]`) gives TOA111, not TOA107 with a bundler hint | when needed |
| A Path Item shared by several paths (through `$ref`): duplicate TOA501, a misleading TOA502 with different variable names | done in M6: each path gets its own operations; identical method names — TOA551 with an override |
| Case sensitivity: `/{id}/{ID}` with one declared `id` reports nothing; OAS 3.2 `additionalOperations` are not checked | done in M6: a variable without a parameter with the exact name — TOA556 (error), the operation is not generated; `additionalOperations` enter the IR with the method as written |
| Enum dedup merges integers and fractions beyond 2^53 (`9007199254740993` and `9007199254740992.0`) | when needed |
| `DiagnosticBag` ignores `fix` during dedup: on a shared file the preset hint of the second client is lost | M5 (baseline and levels) |
| TOA402 accepts any existing node as a `mapping` target (including `#`) | when needed |
| URIs with percent-encoding in `SpecDocuments` keys vs `document.uri`; positions shift after list edits; a file that failed to load is re-read on every pass | not needed in either M4 or M6: when needed |
| Preset hints: aspnet for TOA401 (§D.4.5 instead of §D.4.4), nestjs for TOA303 does not remove defect C-54; several hints are only indirectly based on §D | M13 (recipes) |
| Test gaps: negative cases for the rules on schema shape, enum, path parameters, `operationId`, discriminator | together with the next changes to these rules |

## Moved from M4

M4 review findings that were deliberately deferred:

| What | Where |
|---|---|
| `NormalizedSpec.overrides` contains also entries that were not applied (TOA804/805/806), with their generation fields; `generate` does not distinguish "the overrides file is unusable" from "there are no overrides" | done: `generate` skips a client with errors, which an unusable overrides file always gives (TOA801-TOA803, TOA805, TOA806), and the IR reads only applied entries (`IrOverrides`); checked again in M9 |
| Problems introduced by the override itself are reported at the specification's pointer, not at the override | M5 |
| `_content`: with a `null` media object the value of another media type is taken | when needed (defective specifications only) |
| 3.0: after expanding a nullable `$ref`, the sibling fields of `$ref` remain, but 3.0 ignores them; a schema with `anyOf` and `oneOf` containing null expands only `anyOf`; `type: 'null'` + override `type: null` → TOA807 unchanged | when needed |
| Addressing: `{petId}` versus `{id}` without explanation; `2xx` in lower case; `QUERY` in 3.2 `additionalOperations`; an operation written as `$ref`; a Path Item shared through `$ref` without TOA808; nested TOA804/805 under entries with TOA806; an absolute `file:///` in the message about a boolean schema | when needed |
| Not addressable: webhooks, nested properties, properties inherited through `allOf` | not needed in M6 (fields from `allOf` parts take the overrides of their components by location): when needed |
| Override snippets: TOA203 on one flow line; no snippet for an alias with `$ref` siblings; round-trip tests only for 3.0 components | when needed |

## Moved from M5

M5 review findings that were deliberately deferred:

| What | Where |
|---|---|
| Windows: paths with a drive letter (`_fileName`, a dead `PathException` branch), `int` semantics on the web (dart2js) | M11 (platform matrix) |
| SARIF: results with a file but without a position (`region`), and without a file — check `upload-sarif` in GitHub code scanning | M11 |
| Path display: a file reached through `$ref` is absolute when the specification itself is outside the working directory; a symlinked directory (macOS `/tmp`) shows files as absolute | when needed (baseline matching is not affected) |
| Anchor: the first alias / the first shared Path Item wins; a parameter's anchor through `$ref` is by index | when needed |
| Attribution of an override's problem compares against the model before the normalizer's fixes; dedup keeps `related` of the first client | when needed (informational) |
| Duplicated merge code for "sorted + baselined" in 4 reporters; `RelatedLocation.location` duplicates `Diagnostic.location` | refactoring with the next changes to the reporters |
| `prune` always rewrites the file and says "removed 0" when it only decreased `count`; the fingerprint is computed twice in `create` | when needed |
| Tests: paths (symlink, spaces, non-ASCII), a different working directory for the baseline, escaping of GH properties, `addBaselined` | together with the next changes to these parts |

## Moved from M6

M6 review findings and items deferred in the plan, which were deliberately left. The first four rows are gaps in the "IR → emitter" contract: they must be closed in the M8/M9 plan, not reopened.

| What | Where |
|---|---|
| Request body: the media type's `encoding` (for forms — `style`/`explode` of each property, for multipart — `contentType` and part headers, file name) was parsed, but the IR had none of it, and there was no diagnostic. In the corpus: 312 of 611 Stripe `x-www-form-urlencoded` bodies have `encoding` (deepObject/explode); file parts are `Uint8List` without a name or type (R10.4) | done in M9 (tasks 2-4: `EncodingIr`, `FormEncoding`, multipart part media types, `FileUpload` with a file name; part headers are TOA656) |
| Names of types that the emitter creates are not named in the IR: the sealed error type `ErrorsByStatus` and its variants (1047 operations of the corpus), the variant classes of a union and the unknown variant (R9.1), the success type when the 2xx bodies differ (31 operations, e.g. Discord `guildSearch`: 200 `GuildSearchResponse` / 202 `SearchIndexNotReadyResponse`). The natural names are already taken: for `getPet` with an inline 404 and a 500 without a body the inline model is `GetPetError`, so the sealed `GetPetError` would clash with it. `NameScope` is internal and `ClientIr` keeps only the final names, so the emitter would have to rebuild the namespace, the reserved sets and TOA550/551 itself | done: M8 names the union and enum helpers; M9 names the status types, parts classes and the root client after them (task 3, `ApiNames`) |
| Constraints (R6.7) are missing from `FieldIr`, `default` is in `ParameterIr`; the plan said "on the nodes", but that is inaccurate: M8 would have to derive them from the specification by `location`. The `description`, `deprecated`, `defaultValue` fields are there (3.1+: own ones next to `$ref` take precedence over the target's) | done (M8: constraints; M9 task 2: `ParameterIr.defaultValue`, in the method's doc comment) |
| `in: querystring` parameter (OpenAPI 3.2) is skipped (TOA565, split from TOA564 in M9), because the runtime has no "whole query string" parameter; `style` is checked against `in` (fixed in M6: TOA564, fallback — default style) | when needed; no corpus spec has one |
| `SingleError(type, const [])` — what an empty `statuses` list means: "all 4xx/5xx" (yes, when `errors.default_schema` is set and the operation has no described errors); `ir.dart` says only "documented statuses" | done in M9 (task 6: the doc comment says every 4xx and 5xx; the decoder reads it so) |
| An operation whose only response is `default` with a body has no success type (`default` is always an error); there is no such operation in the corpus | done in M9 (task 3: TOA653; any 2xx is a success with the body as `JsonValue`) |
| The generated API library imports `package:dio`, and `Response`, `Options`, `Headers` are common schema names; `DartNames.takenTypeNames` does not reserve them | done in M9 (task 2: the API files import only `Dio` with `show`; `Dio` and the new runtime names are reserved, `Response`, `Options` and `Headers` stay free) |
| The path variable pattern in the IR (`\{([^}]*)\}`, `ir_builder.dart`, `operation_builder.dart`) differed from the runtime (`\{([^{}]+)\}`): `/c/{}` is TOA556 in the IR, while the runtime read `{}` as text | done in M9 (task 2, 10c: one `PathTemplate.variable` for the IR, the emitter and the path rules; a test keeps it equal to `OperationRequest.pathVariable`) |
| TOA561 `media-type-as-bytes` covered two findings (the body becomes bytes; alternative media types were dropped); all 57 corpus cases are the second, so `severity: {media-type-as-bytes: off}` also silences the first. Numbering: decision 3 of the plan put media types and errors in 6xx, while TOA561/TOA562 are in 5xx | done in M9 (task 2: TOA650 and TOA651; TOA562 became TOA652) |
| Duplicate types of union variants remain silently: `anyOf: [string, {string, uuid}, $ref A, $ref A]` gives `String \| String \| A \| A`; without a discriminator the emitter cannot tell the variants apart | M8 (together with `oneOf` without a discriminator, R9.2) |
| `{}` in a PATCH body is never tri-state (`JsonValue` is not nullable, and the `.patch` rule requires a nullable value): an explicit `null` for an arbitrary JSON field cannot be sent (R7.1) | M8 |
| TOA450 on inline variants does not suggest a value that could be derived: when the variant's discriminator property is the only `const`/enum (OpenAI ×3) | M8 (R9) |
| The override address for an inline type's name (R5.4 "with override"): the form depends on which inline types the model emitter prints (a field, an array element, a map value, a union variant); until then the name is fixed by renaming the parent | M8 |
| The first one to reach a shared inline declaration gives it its name (`first-use naming`) | M8, when the names reach the code |
| Polymorphism through `allOf` (discriminator on the base, descendants — `allOf: [$ref: Base, …]`): the base stays a model, TOA452 | M8 (the hierarchy together with the unions, R9) |
| `oneOf` without a discriminator (R9.2): the IR node exists, but there is no behavior or diagnostic yet | M8 |
| The title of an enum value from a `const` branch (`title`/`description`, Discord `NO_BOT`) is not taken as the value's name | M8 |
| The envelope mode "generic wrapper" and its config key | when needed (M9 design, decision 11: envelopes are only unwrapped) |
| Webhooks, `callbacks`, security metadata, `servers` | done in M9 (security metadata and servers, tasks 1, 3, 4); callbacks and webhooks are reported, not generated (TOA567); SSE events — M10 |
| SSE: the IR takes `itemSchema` (or `schema`) for `text/event-stream` as the content type; in OAS 3.2 `itemSchema` describes the event as a whole (`data`/`event`/`id`), so the type may be an event envelope rather than the data; the 4 corpus streams have not been reviewed | M10 |
| R5.3: "descriptive" tags (`Pet operations controller`) are not recognized (a warning only for tags without ASCII); renaming a tag with an override (`tags: {pet-controller: Pets}`) requires a `tags` section in the overrides file | when needed: a tag override needs a `tags` section in the overrides file, a format decision (M9 plan, open questions) |
| Validation of `import`/`type` of custom types (R6.8); escaping in the emitter | M8 |
| A path parameter with `required: false` is forcibly made required (the normalizer's territory, M3) | when needed |
| `prefixItems` (tuples), `patternProperties`, `if/then/else`, `not` are not mapped (an array without `items` — `List<JsonValue>`) | when needed |
| R5.1 "version suffix": `naming.operation_prefix` strips only the start of `operationId` | when needed (a real case) |
| `paths: {}` without operations is silent (a specification with webhooks or only components is legitimate) | when needed |
| An integer enum with a fractional number without a fraction (`type: integer, enum: [1.0, 2]`) — `EnumKind.number` with the name `value1_0` | when needed |
| A numeric property name is read as a list index in `_tokensName` (`SchemaMapper`) | when needed |
| A very long `$ref` chain (~1300) — stack depth and O(N²); unrealistic | when needed |
| `NameScope.claim('')`, gaps in the `dart:core` list in `takenTypeNames` (`RuneIterator`, `UriData`, …) | when needed |
| IR hygiene: nested lists are not `unmodifiable` (const constructors), `PatchType(String?)` is not enforced, a duplicate `DeclId` — the last one wins, `IrJson` does not print `import` | when needed (statuses and default values are printed since M9, 10c) |
| An invalid value in a client falls back to the built-in default value, not to `defaults` | M13 (config documentation) |
| `DirectionIndex` cached "not directional" inside a loop depending on the order of queries | done in M6 (10a): the answer depends only on the set of reachable schemas |
| `deprecated: false` next to `$ref` does not cancel the target's mark (in the model it is a plain `bool`); a description of the target written in its own annotations-only `allOf` part does not reach the field | when needed (doc comments only) |
| `IrJson` does not print descriptions, so the effect of annotations next to `$ref` is visible only in tests | M8 (if the dump is needed for doc comments) |
| TOA561 and TOA564 each covered two different findings (dropped alternatives / bytes; invalid `style` / `querystring`) and sat in 5xx, although the plan allotted media types 6xx | done in M9 (task 2: TOA650/TOA651, and TOA565 for `querystring`) |

Fixed in M6 following the final review: an `allOf` with one `$ref` and annotation-only parts — a reference to the target (nullable if a part says so); `description`, `default`, `deprecated` next to `$ref` in 3.1+ take precedence over the target's; TOA564; the `Accept`, `Content-Type`, `Authorization` headers are not generated; custom type names are reserved (TOA551); TOA552 for enum values is info with the hint `x-enum-varnames`; `unknown` is reserved among enum values (`unknown_`).

## Moved from M8

M8 findings and decisions that were deliberately deferred (plan: [2026-10-12-m8-models.md](superpowers/plans/2026-10-12-m8-models.md), section "Deferred"):

| What | Where |
|---|---|
| Sealed types of operation statuses (`CreatePetError`, `CreatePetResponse`) and their variants | done in M9 (tasks 3-4) |
| Override address for inline type names (R5.4); the idea is a `typeName` field in a property entry (`schemas.Pet.properties.status.typeName: PetState`), with no address for array elements, map values, and union variants | when needed (the user's decision: deferred) |
| The enum value name from a `const` branch's `title` (Discord `NO_BOT`) as `x-enum-varnames` | when needed (the user's decision: deferred) |
| ~~Stripe: 390 fields `anyOf: [string, {enum: ['']}]`~~ | resolved in M8: the enum branch is dropped by TOA455 (info), the field is `String`, the dropped values go into the "Known values" doc comment; for `oneOf` the type also accepts a value that `oneOf` would reject — deliberately |
| Subtypes of a polymorphic base are not counted in `DirectionIndex` (the split into `Pet`/`PetInput` is not done for them) | when needed |
| `IrJson` does not print constants, constraints, helper type names | when needed |
| `generate --format` (json, sarif) | after M9: where the per-client lines go next to a machine report is a user decision (M9 plan, open questions) |
| The input hash does not account for the Dart SDK version and `dart_style` (not used) | when needed |
| `union` keys on a property that an override cannot apply silently produce no diagnostic (TOA807 only for schemas) | when needed |
| `IrJson` does not print the union variant selection method (`dispatch`) and the variant names | when needed |
| Override `name` and `exhaustive` on fallback `JsonValue` have no effect (as in M6) | when needed |
| `declarations()` of the namespace is called once (only `IrBuilder` calls it) | when a second call appears |
| Constants with `null` are not distinguished from absent ones (no loss); constraints lost in `allOf`/`$ref` chains are only documented | when needed |
| `JsonReader.constant` does not match a non-scalar constant (the emitter calls it only with scalars); NaN in `DeepEquality` on dart2js differs from the VM (JSON has no NaN); `Set` is compared by identity | M11 (platform matrix) |
| "Known values" are not documented for a union that is an array element or a component alias (there is no field with a description there); long "Known values" lines wrap unevenly | when needed |
| Long `toJson` lines in generated code are not wrapped (safe under `// dart format off`) | when needed |
| A subtype of a polymorphic base that is only in a file nothing refers to is not found (the file is not read) | behavior by design; documented |
| `generate`: `--dry-run`, a generator version constant (guarded by a test) | when needed |
| Model file names (`ModelLibrary.fileNames`) are allocated in one scope in the order of `ir.declarations`, sorted by name. If M9 adds operation types to the same list or directory, a new type that sorts earlier and yields the same snake name will move an existing model to `x2.dart`: its file's `import` breaks, and the output changes | done in M9 (task 4: group files in `api/`, named in their own scope) |
| Swapping the output directory does not carry over the owner, ACLs and extended attributes of the old directory (the access mode is carried over) | when needed |
| Case and hard-link tests have been checked only on macOS (APFS); Linux and Windows — in the M11 matrix | M11 |

## Moved from M7

M7 review findings that were deliberately deferred:

| What | Where |
|---|---|
| `openEvents`: an error body with invalid UTF-8 is decoded leniently (`allowMalformed`), while `send` gives `DecodeError`; a response from a stream status without `ResponseBody` — `UndocumentedStatus` with an empty body; the size of the error body is not limited (as in `send`) | M10 (SSE) |
| An operation with a binary/text success response and JSON errors has no direct decoding means; `RawResponse.parse` bypasses the depth check | done in M9 (task 1: `RawResponse.parsedJson` with the depth check, also in `RawResponse.parse`) |
| A `double` `1.0` in a parameter: `x=1.0` on VM and Wasm, `x=1` on dart2js | M11 (platform matrix) |
| The `whenCancel` chain leaves a closure on a long-lived user token for each `openEvents` call (of the same order as Dio itself) | when needed |
| The README does not describe the `//` guard in the query for a relative `baseUrl` | done in M9 (task 6: README, "Operations") |
| The browser does not send the `Cookie` header (cookie parameters do not work on the web) — a claim from the documentation, not verified in a browser | M11 |

## Moved from M9

Findings and decisions of M9 that were deliberately deferred (plan:
[2026-10-13-m9-operations.md](superpowers/plans/2026-10-13-m9-operations.md),
"Deferred"):

| What | Where |
|---|---|
| Event-stream operations are not generated (TOA654) | M10 |
| `in: querystring` parameters are not generated (TOA565) | when needed |
| The headers of a multipart part's `encoding` are not sent (TOA656) | when needed |
| A form property nested deeper than its style allows (an object in an object for `form`) makes `FormBody.encode` throw `ArgumentError` at run time; the generator does not warn | when needed (a diagnostic, or the deepObject convention of Rails and Stripe) |
| `style: cookie` (OpenAPI 3.2) is sent percent-encoded, like `form` | M11 (with the platform matrix) |
| A documented 1xx or 3xx response is `UndocumentedStatus` (or the `default` response's type when there is one); `default` never catches a 2xx | when needed |
| `callbacks`, `links` and `webhooks` are not generated (TOA567 reports callbacks and webhooks) | when needed |
| `generate --format` and the per-client lines next to a machine report | after a user decision |
| Files over the size limits that M9 grew (see the allowlist comments in `test/quality/size_limits_test.dart`) | the code-quality plan |

## Parked from the M9 reviews

Findings of the M9 reviews that the fix tasks (10a, 10b, 10c) did not fix, with the review and the finding (`T<n>` is the review of task n; `T10b` the review of Task 10b). Everything else those reviews found is fixed.

| Finding | Review | Why it is parked |
|---|---|---|
| A client with no operations gets a root class whose `dio` is unused and a header-only `api.dart` | T6 M7 | harmless, analyzer clean; `TOA563` already warns |
| A tag or schema name of about 245 characters or more makes a file name over 255 and a `FileSystemException` at write (`api_library.dart`, `ModelLibrary.snake`, also models) | T4 minor 6 | no real spec has such a name; the writer should report TOA831 for it when it is met |
| `api_client.dart` does not re-export the runtime types the API uses (`Result`, `Success`, `CallOptions`, `FileUpload`, `Date`), so a caller needs a second import | T4 minor 8 | a design decision (a re-export would make the runtime part of the client's own API) |
| An explicit JSON `null` cannot be told from an absent value for a `JsonValue` parameter or part (an extension type over `Object?` erases): `JsonValue(null)` is "absent" for a required JSON-content parameter too | T7 minor 3 | the type cannot carry the difference; consistent with `QueryParameter('h', h)`; a wrapper type would change every signature |
| No runtime or calls test sends an omitted optional `JsonValue` in a JSON-content or form/multipart body position | T7 minor 3 | the analyzer gate covers the shape; add with the next change there |
| The `toString` of a status variant prints a raw JSON body with no secret in its schema in full (a free-form object may hold a token at run time) | T9 minor 1 | same rule as the model fields (M8); confirm the intent before changing it |
| Tests for secret shapes of status bodies: a `$ref` secret, a nullable `anyOf`, a map of secrets, an envelope (all work, nothing pins them) | T9 minor 5 | test gap only |
| A default of an array or object whose items do not fit their schema is not checked (only the `enum` and the `format` of the parameter's own schema: TOA660) | T2 minor 3 | needs a validator of values against schemas; the type mismatch is TOA211 |
| `EncodingIr.explode` and `allowReserved` are kept for multipart although only `contentType` is used there | T2 minor 7 | harmless; the emitter reads what it needs |
| A reserved-name test does not assert that `Response`, `Options` and `Headers` get no TOA550; tests for a default on a header, cookie or `content` parameter | T2 minor 7, 2b | test gaps; the behaviour is covered by the analyzer gate |
| Test gaps of the naming and security work: apiKey in a query or cookie, `http basic`, `mutualTLS`, `openIdConnect`; a variant and a parts-class collision (`UploadRequest2`); a lower-case `4xx`; two servers with one URL; the `naming.client` run key | T3 M5 | tests only; the reviewer verified the behaviour |
| The collision cases of the client name (`api`, `models`) are tested only on `ApiLibrary`, not through `generate` | T6 M5 | the layout is verified by the reviewer on 13 outputs |
| TOA568 for a scheme without a type is reported twice, with TOA111 or TOA112 at the same place | T10a M4 | each says something else (the spec is wrong; the metadata is `unknown`) |
| `UndocumentedStatus.rawBody` is raw bytes, not parsed JSON, in an operation with a binary error (the operation reads bytes) | T10b M1 | stated in the decoder rules of `CLAUDE.md`; a parse by `Content-Type` can be added to `RawResponse.undocumented` |
| `body(String schema)` in `response_status_test.dart` reads like an unused parameter | T10b M5 | style only |
| The new emitter code uses `!` where a pattern or an early return could promote the value (`decoder_writer.dart`, `request_writer.dart`, `operation_emitter.dart`, `api_library.dart`) | final review minor 9 | the values are IR-contract invariants and 54,000 fuzzed builds found no crash; style only |
| A multipart `encoding.contentType` with a control character inside a quoted parameter or a line break between parameters (`text/plain; x="a\nb"`) passes the generator's check (`ir/part_media_type.dart`) and Dio's `DioMediaType.parse` throws at call time | final re-review R1 | the media type is invalid per RFC 9110; tighten the pattern to RFC 9110 tokens and quoted strings and report TOA661 with the fallback; first item of the next change there |
| A `security` field that is not a list (`security: {bearer: []}`) is dropped with TOA111 only, so the metadata reads as open unless the document has its own requirement (`parse/operation_parser.dart`, `parse/openapi_parser.dart`) | final re-review R2 | an invalid spec that is already a warning; map it to one alternative of kind `unknown` with TOA568, like a malformed entry |
| `default: "2020-13-01T00:00:00Z"` on a `date-time` parameter gets no TOA660, because `DateTime.tryParse` normalises the month | final re-review R3 | check the RFC 3339 fields by range instead of `tryParse` |
