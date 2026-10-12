# 05. Prior art from other languages and commercial SDK generators

Date: 2026-10-11. Scope: concrete patterns that can be copied, for R2, R3, R4, R5, R6.2/R6.4, R7, R8, R9, R10.5/R10.8, R11, R12, R13.1 and R14. This is not a general overview of tools. The OpenAPI Generator normalizer is mentioned here only briefly, because a separate document covers it.

Method: official documentation, READMEs and source code (via gh api). Every claim has a reference. Where something could not be verified, this is stated directly. Markers: **✅ take**, **⚠️ adapt**, **❌ avoid**.

---

## 0. In brief: the 15 most valuable patterns

1. **Stainless diagnostics catalog** (R2.2). The code has the form `Category/Name`, for example `Schema/ArrayMissingItems` or `Name/Collision`. There are four levels: Fatal, Error, Warning, Note. The message text is a template with parameters and advice on what to do. It can be ignored in the config: `diagnostics.ignored: {code: [{location, reason}]}`.
2. **Fingerprint from oasdiff** (R2.3, R14). It is computed as `SHA256("{id}:{operation}:{path}:{args}")[:12]`. The message text is not part of the hash, so the fingerprint is the best key for a baseline.
3. **ESLint bulk suppressions** (R2.3, ratchet). The file has the form "file → rule → count". New violations break the build. If a suppression no longer triggers, the process exits with a non-zero code and recommends `--prune-suppressions`.
4. **`Transform/Useless` in Stainless and "does nothing" / "did not match any targets" in Speakeasy** (R3.2). An override that changed nothing or matched nothing produces a separate diagnostic.
5. **`strict: true` for the overlay in oapi-codegen** (R3.2/R3.3). The mode is on by default; it "highlights actions that change nothing".
6. **Stainless transformations with a mandatory `reason`** (R3). The operations are `update`, `append`, `merge`, `remove`, `copy` and `move`. `matches_schema` finds all schemas deeply equal to the template and replaces them with `$ref`. This is deduplication out of the box.
7. **Filters `GET /path` with regular expressions in hey-api and `#METHOD` in Kiota** (R4). `exclude` takes precedence. Orphan schemas are removed automatically as soon as any filter is set.
8. **Open enums: `x-speakeasy-unknown-values` / `forwardCompatibleEnumsByDefault` in Speakeasy and `Known`/`Value._UNKNOWN` in Stainless Java** (R8). The raw value is kept, while enums with a single value stay closed.
9. **`OptNil[T]` in ogen with an explicit table "required × nullable → decoder behavior"** (R6.1/R7). Alongside it: `Unset` in openapi-python-client, `Omit` in Stainless Python and `JsonField` (missing/null/value) in Stainless Java.
10. **`defaultMapping` in the discriminator of OAS 3.2** (R9). It is the standard way to set a fallback variant for an unknown or missing discriminator value. Speakeasy returns `{type: "UNKNOWN", raw}`.
11. **`undocumented(statusCode:, payload)` in swift-openapi-generator and `Error<E>` in progenitor** (R11). Transport failures, documented errors, decoding errors and undocumented responses are separate variants.
12. **Handler table `streaming.on_event` in Stainless** (R12). The handlers `event_type`, `data_starts_with` and `kind: fallthrough` have actions `yield | done | break | error`. Fern adds `resumable` (Last-Event-ID, `retry:`, a limit of 5 attempts with reset) and `terminator`.
13. **FastAPI already emits `itemSchema` for `text/event-stream`, although the document has `openapi: 3.1.0`** (R1.4/R12). The normalizer must accept a 3.2 key in 3.0 and 3.1 documents.
14. **Lock files of Kiota and Speakeasy** (R13.1/R14). They store the hash of the description, the hash of the config and the generator version. **Editions in Stainless** are versioned sets of output changes that break compatibility (relevant to R15.4).
15. **`--fail-on` and `--severity-levels` in oasdiff** (R14). The checks take into account the direction of the data (request or response). For Dart APIs there is a ready-made `dart_apitool diff`.

---

## R2. Normalizer, diagnostics, baseline, lint mode

### How others do it

**Stainless: diagnostics catalog.** The [Generator diagnostics](https://www.stainless.com/docs/reference/diagnostics/) reference is the closest analogue to what R2.2 requires.
- The code has the form `Category/Name`. Categories: `Schema`, `Name`, `Endpoint`, `Method`, `Parameter`, `Pagination`, `Streaming`, `Transform`, `OAS`, `Reference`, and, separately, language ones (`Go/…`, `Java/…`). Examples: `Schema/ArrayMissingItems`, `Schema/EnumDuplicateMembers`, `Schema/RequiredPropertyNotDefined`, `Schema/IsAmbiguous`, `Parameter/PathTemplateVariableMissing`, `Operation/PathTemplateVariableMissingParameter`, `Name/Collision`, `Transform/Useless`.
- Levels are tied to the release process: 💀 Fatal (generation impossible), ❌ Error ("fix before 0.0.1"), ⚠️ Warning ("before 1.0.0"), ✍️ Note ("consider before 1.0.0").
- Messages are templates with parameters (`{oas_path}`, `{endpoint}`, `{fallback_name}`), and each says how to fix the problem. Example `Schema/IsAmbiguous`: "the schema has no `type`, so we treat it as `unknown`… if it really accepts anything, add `x-stainless-any: true`… for many such schemas apply an `update` transformation with `matches_schema`". The diagnostic proposes a concrete action, as R2.5 requires.
- Suppression lives in the config ([DiagnosticsConfig](https://www.stainless.com/docs/reference/config/)): `diagnostics.ignored: Record<code, true | Array<{location, reason} | {target: language, reason}>>`. You can ignore either everything or individual locations, and each location has a mandatory `reason`.
- There is a [Language Server](https://www.stainless.com/docs/tools/stainless-language-server/), so diagnostics are visible right in the editor.

**Speakeasy: lint rules with categories** ([linting](https://www.speakeasy.com/docs/sdks/prep-openapi/linting)).
- IDs are in kebab-case with a category prefix: `generator-*` (SDK generation), `semantic-*`, `style-*`, `oas3-*`, `owasp-*`. Examples: `generator-duplicate-schema-name`, `generator-duplicate-path-params`, `generator-validate-enums`, `generator-duplicate-inline-schemas`.
- Rulesets are defined in `.speakeasy/lint.yaml` with `extends`. A rule is overridden via `id`, `severity: error|warn|hint`, `disabled: true` and `match` (a regular expression over the message text).
- The **`speakeasy-generation`** ruleset (32 rules, 26 of them `generator-*`) is always applied before generation, and it cannot be overridden. That is, some rules are by design never lowered.
- There is no baseline mechanism.

**Kiota: named validation rules** ([using](https://learn.microsoft.com/en-us/openapi/kiota/using)).
- Rules: `DivergentResponseSchema`, `GetWithBody`, `InconsistentTypeFormat`, `KnownAndNotSupportedFormats`, `MissingDiscriminator`, `MultipleServerEntries`, `NoContentWithBody`, `NoServerEntry`, `UrlFormEncodedComplex`.
- All of them emit a warning and are disabled by name: `--disable-validation-rules NoServerEntry` or `all`.

**OpenAPI Generator: normalizer** ([customization.md](https://github.com/OpenAPITools/openapi-generator/blob/master/docs/customization.md)). Named rules, each enabled separately via `--openapi-normalizer RULE=true`: `REF_AS_PARENT_IN_ALLOF`, `SIMPLIFY_ONEOF_ANYOF`, `SIMPLIFY_BOOLEAN_ENUM`, `FIX_DUPLICATED_OPERATIONID`, `REMOVE_X_INTERNAL`, `FILTER` and others. A detailed analysis is in a separate document.

**Redocly CLI** ([lint](https://redocly.com/docs/cli/commands/lint), [rules](https://redocly.com/docs/cli/configuration/reference/rules)).
- Levels: `error | warn | off`. Built-in rules have simple names (`security-defined`), configurable ones use the prefix `rule/…`, and plugin rules are `plugin/rule`.
- The JSON output contains `location[].pointer` (JSON Pointer), `source.ref`, `start`/`end` with `line`/`col`, and `reportOnKey`.
- **`--generate-ignore-file`** creates `.redocly.lint-ignore.yaml`. In essence, this is a baseline with the structure "file → ruleId → [JSON pointers]":
  ```yaml
  museum-with-errors.yaml:
    operation-operationId:
      - '#/paths/~1museum-hours/get/operationId'
  ```
- Ignored problems are still counted, and the output shows how many there are.
- Formats: `codeframe`, `stylish`, `json`, `checkstyle`, `codeclimate`, `github-actions`, `markdown`, `summary`, `junit`.

**Spectral** ([overrides](https://github.com/stoplightio/spectral/blob/develop/docs/guides/4d-overrides.md), [CLI](https://github.com/stoplightio/spectral/blob/develop/docs/guides/2-cli.md)).
- A rule can be turned off at a specific location: `overrides: [{files: ["legacy/**/*.oas.json#/paths/~1Pets~1%7BpetId%7D/get/parameters/0"], rules: {rule: "off"}}]`. This is a file glob plus a JSON Pointer.
- Caveat: overrides work only for root documents, not for external `$ref`s.
- `--fail-severity`. Formats include `sarif`, `github-actions`, `junit`, `gitlab`.

**vacuum** ([lint](https://quobix.com/vacuum/commands/lint/), [ignoring](https://quobix.com/vacuum/ignoring/)).
- `--ignore-file` is YAML in the form "rule id → [exact result paths or JSONPath expressions]". It is generated by the command `vacuum generate-ignorefile`.
- The built-in suppression `x-lint-ignore: rule-id | [ids]` applies to the object and its entire subtree.
- `--fail-severity error|warn|info|hint|none`.

**Zally** ([README](https://github.com/zalando/zally), [rules.md](https://github.com/zalando/zally/blob/main/server/rules.md)). Rule IDs have the form `M008`, `S005`, `H001`. There is an inline suppression `x-zally-ignore`, but there is also a separate rule H002, which reminds users to use it "sparingly, for temporary exceptions".

**Ratchet in code linters** — the best prototype for R2.3:
- **ESLint, bulk suppressions** (v9.24, [documentation](https://eslint.org/docs/latest/use/suppressions), [announcement](https://eslint.org/blog/2025/04/introducing-bulk-suppressions/)).
  - `eslint --suppress-all` writes `eslint-suppressions.json` in the form "file → rule → `{count}`".
  - `count` is a ceiling: if violations have increased, **all** are reported, not only the new ones.
  - If suppressions no longer trigger, the process exits with a non-zero code and the message "There are suppressions left that do not occur anymore. Consider re-running the command with `--prune-suppressions`".
  - This behavior can be disabled with the flag `--pass-on-unpruned-suppressions` (v9.28).
- **PHPStan** ([baseline](https://phpstan.org/user-guide/baseline)). `--generate-baseline` writes entries with `message` (a regular expression) + `count` + `path`. If an ignored error has disappeared, PHPStan reports it (`reportUnmatchedIgnoredErrors`).

**oasdiff: fingerprint** ([FINGERPRINT.md](https://github.com/oasdiff/oasdiff/blob/main/docs/FINGERPRINT.md)).
- Formula: `SHA256("{id}:{operation}:{path}:{args}")[:12]`, where `args` are the values the message is built from.
- The message text is not part of the hash, so rewording does not change the fingerprint.
- The documentation honestly lists when the fingerprint "drifts": positional names such as `oneOf[subschema #4]`, and renamings.

### What to take for Dart

- ✅ **Diagnostic record**:
  ```
  {code: "SG012", name: "array-missing-items", severity: warning,
   message: <template+args>, pointer: "#/components/schemas/Pet/properties/tags",
   source: {file, line, col}, fix: {text, override: <ready-made YAML fragment>},
   fingerprint: sha256(code|pointer|args)[:12]}
  ```
  The numeric code `SG012` is needed by R2.2, and a human-readable name in the Stainless style makes the code readable. The documentation catalog (R15.5) is generated from the same code registry, as the Stainless page is.
- ✅ **Levels with business semantics.** Give each level error/warning/info an explanation in the spirit of Stainless: "blocks generation", "generates, but the API gets worse", "hint". Add an internal fatal for "cannot continue".
- ✅ **Non-lowerable codes.** The `overridable: false` flag for codes without which generation is impossible (like the `speakeasy-generation` ruleset): an unresolvable `$ref`, a cycle with no way to break it, and so on.
- ✅ **Level override and point-specific suppression** in the config:
  `diagnostics: {SG012: warning, SG020: off, ignore: {SG031: [{pointer: "#/paths/~1legacy~1*", reason: "…"}]}}`.
  `reason` must be mandatory, as in Stainless. Pointers support globs, like overrides in Spectral.
- ✅ **Baseline** — a separate file, deterministically sorted:
  ```yaml
  # openapi_dart.baseline.yaml
  specs/api.yaml:
    SG012:
      - {fingerprint: a3f8c21b9d04, pointer: "#/components/schemas/Pet/properties/tags"}
    SG044: {count: 7}   # ESLint-style for "bulk" codes
  ```
  Behavior:
  - a new diagnostic that is not in the baseline, at a level not below `--fail-on` → error;
  - if a baseline entry no longer triggers → diagnostic `SG0xx stale-baseline-entry`, and CI fails until it is removed with the `baseline prune` command (as in ESLint). Optionally — `--allow-stale-baseline`;
  - commands: `baseline create | update | prune`.
- ✅ **Every normalizer firing is an info diagnostic** with its own code and pointer. Then the report, the baseline and the levels work the same way for fixes and for problems. Rule names are in kebab-case, as in Speakeasy. The set of rules follows OpenAPI Generator.
- ✅ **Output formats**: `text` (codeframe), `json` (with a published output JSON Schema, like `oasdiff schema`), `sarif` (GitHub code scanning), `github-actions`, `junit`. The `check` / `lint` command runs the same pipeline without generating code (R2.4).
- ⚠️ **Line/col positions** are possible only with YAML parsing that tracks positions. For JSON, oasdiff states plainly that there are no positions ([SOURCE-LOCATOR.md](https://github.com/oasdiff/oasdiff/blob/main/docs/SOURCE-LOCATOR.md)). The pointer must therefore be primary, and line/col secondary.
- ⚠️ **Inline suppression** (`x-<tool>-ignore: [SG012]`, as in vacuum and Zally) is worth supporting, but as a secondary mechanism: the spec is owned by the backend, so the main place for suppressions is the client config.
- ❌ **Do not use a regular expression over the message text as the suppression key** (`match` in Speakeasy, `message` in PHPStan). Such a key breaks on rewording. The key is the code plus a pointer or fingerprint.

---

## R3. Overrides and overlays

### How others do it

**OpenAPI Overlay — the standard** ([current version](https://spec.openapis.org/overlay/latest.html), [all versions](https://spec.openapis.org/overlay/)).
- Versions: 1.0.0 (schema 2024-10), 1.1.0 (`copy` added), 1.2.0 (September 2026).
- `Action` has the fields `target` (RFC 9535 JSONPath), `description`, `update`, `remove` and `copy`.
- Merge rules for `update`: objects are merged recursively, **arrays are concatenated**, primitives are replaced, and other combinations are an error.
- Under the specification, a target that selects no node is **not an error**: "the action succeeds without changing the target document".

**Speakeasy: overlay library** ([apply.go](https://github.com/speakeasy-api/openapi/blob/main/overlay/apply.go), [CLI](https://www.speakeasy.com/docs/speakeasy-reference/cli/overlay)).
- `ApplyToStrict` returns the error `selector "…" did not match any targets`. This is an "override of a non-existent element".
- Warnings are collected for each action. An `update` that changed nothing gives a warning **"does nothing"** (`didMakeChange == false`). This is exactly the R3.2 scenario: the override matched a spec that has already been fixed.
- `speakeasy overlay compare` builds an overlay from two versions of the spec (before and after). A convenient workflow: edit a copy of the spec and get the overlay automatically.

**oapi-codegen** ([README, Overlay section](https://github.com/oapi-codegen/oapi-codegen#modifying-the-input-openapi-specification-with-openapi-overlay), [configuration-schema.json](https://github.com/oapi-codegen/oapi-codegen/blob/main/configuration-schema.json)).
- The overlay is set via `output-options.overlay: {path, strict}`. `strict` defaults to `true` and "highlighting any actions that will not take any effect".
- The overlay is recommended precisely when the spec is owned by another team.
- At the same time, the documentation warns that JSONPath is hard to write and maintain.

**Fern: overrides.yml** ([overrides](https://buildwithfern.com/learn/api-definitions/openapi/overrides)).
- The file repeats the structure of the spec and deep-merges with it.
- Several files can be given; they are applied in turn, and later ones win.
- Overrides are applied **before** overlays.
- There is a scaffolding command `fern write-overrides`. Fern itself now recommends overlays as the more standard option.

**Stainless: transforms** ([config: OpenAPIConfig](https://www.stainless.com/docs/reference/config/), [transforms](https://www.stainless.com/docs/openapi/transforms/)).
- Commands: `update`, `append`, `merge`, `remove`, `copy`, `move`. Each has a **mandatory `reason`**. The target is set via JSONPath Plus.
- `update` "fails if path doesn't exist", and `append` fails if the property already exists.
- `matches_schema` finds all schemas deeply equal to the template and replaces them with `$ref`. This is deduplication of identical inline schemas.
- `{{value}}` provides string templating.
- Diagnostics: `Transform/Failed` and **`Transform/Useless`**: "Transformation {command} had no effect… and can safely be removed".

**Functional patches.**
- hey-api: `parser.patch.schemas.Foo = (schema) => {…}` before parsing ([parser](https://heyapi.dev/openapi-ts/configuration/parser)).
- orval: `input.override.transformer` — a function over the whole document that runs **before** validation, so it can be used to fix even invalid specs ([input.mdx](https://github.com/orval-labs/orval/blob/master/docs/content/docs/reference/configuration/input.mdx)).
- openapi-python-client: `class_overrides` (`class_name` + `module_name`) and `content_type_overrides` ([README](https://github.com/openapi-generators/openapi-python-client)).
- Redocly: decorators `filter-in`, `filter-out`, `remove-x-internal`, `remove-unused-components`, `*-override` during bundle ([decorators](https://redocly.com/docs/cli/decorators)).

**progenitor / typify (Rust)** ([lib.rs](https://github.com/oxidecomputer/progenitor/blob/main/progenitor-impl/src/lib.rs)). Overrides at the type level: `with_patch(type_name, TypePatch)` (renaming, derive), `with_replacement(schema_type, rust_type, impls)` and `with_conversion(schema, type, impls)`.

### What to take for Dart

- ✅ **Three layers in a fixed order** (as in Fern):
  1. the normalizer;
  2. raw spec patches: Overlay 1.0/1.1 and JSON Patch (R3.3);
  3. **a semantic overrides file** (R3.1).

  Diagnostics from all layers point to the **original** locations in the spec.
- ✅ **Semantic selectors instead of JSONPath** in the overrides file: `operation: getUser` or `GET /users/{id}`, `schema: Pet`, `property: Pet.tags`, `parameter: getUser.query.limit`. JSONPath is complex (even oapi-codegen admits it), and for generated specs it is also fragile. JSONPath stays only in the Overlay layer.
- ✅ **Each override entry has a `reason`.** Without it, it is a warning, as in Stainless.
- ✅ **Detection of stale overrides (R3.2)** — as in Speakeasy and Stainless:
  - target not found → warning `override-target-missing` ("did not match any targets");
  - applying it changed nothing (node before == node after) → info `override-redundant` ("can safely be removed"). This is checked by applying the override to the normalized spec and comparing the result before and after.

  The `strict` mode is enabled by default in CI (as `strict: true` in oapi-codegen): then warnings become errors.
- ✅ **The command `overrides diff spec.orig.yaml spec.fixed.yaml`**, which outputs a ready-made overrides file or overlay (like `speakeasy overlay compare`). This is the fastest path for teams working with NestJS or FastAPI: fix a copy by hand and get the override.
- ✅ **The deduplication operation `dedupe: {matches_schema: …}`.** It replaces deeply equal inline schemas with `$ref` and eliminates the typical DTO duplicates from NestJS.
- ⚠️ **The Overlay requires RFC 9535 JSONPath in Dart.** The package's conformance needs to be checked on pub.dev; at the time of the research this was not verified.
- ⚠️ **Functional hooks** (like hey-api `patch` or orval `transformer`) should be offered only in the programmatic API (R15.1), not as the main mechanism. They are non-declarative, cannot be diagnosed, and cannot be shown in the report.

---

## R4. Filtering and tree-shaking

### How others do it

- **Kiota** ([using](https://learn.microsoft.com/en-us/openapi/kiota/using)).
  - `--include-path` and `--exclude-path` accept globs, for example `**/users/**`. The `#METHOD` suffix filters by method: `**/users/**#GET`.
  - Semantics: an element is included if "(there is no include OR it matched an include) AND (there is no exclude OR it did not match an exclude)".
  - The parameters are stored in `kiota-lock.json`.
- **hey-api** ([parser.filters](https://heyapi.dev/openapi-ts/configuration/parser)).
  - Filters apply to `operations` (exact keys `'GET /api/v1/foo'` or regular expressions `'/^[A-Z]+ /api/v1//'`), `tags`, `deprecated: false`, and also `schemas`, `parameters`, `requestBodies` and `responses`.
  - `exclude` takes precedence over `include`.
  - `orphans: false` (remove orphan schemas) is enabled by default as soon as any other filter is set. This is tree-shaking.
  - `preserveOrder: true` keeps the order.
- **orval** ([input.mdx](https://github.com/orval-labs/orval/blob/master/docs/content/docs/reference/configuration/input.mdx)).
  - `filters: {mode: include|exclude, tags: [string|RegExp], schemas: […]}`.
  - If `tags` are set, the output is automatically limited to the schemas that the selected operations **transitively** reference. `includeUnreferencedSchemas: true` turns this restriction off.
  - Schemas reachable only through `$dynamicAnchor` bindings are also found automatically.
- **oapi-codegen**: `include-tags`, `exclude-tags`, `include-operation-ids`, `exclude-operation-ids`, `exclude-schemas`. Unused components are removed by default; `skip-prune` turns this off ([config schema](https://github.com/oapi-codegen/oapi-codegen/blob/main/configuration-schema.json)).
- **OpenAPI Generator**: the normalizer `FILTER="operationId:addPet|getPetById ; tag:store"` (also `method:` and `path:`) marks non-matching operations as `x-internal: true` ([customization.md](https://github.com/OpenAPITools/openapi-generator/blob/master/docs/customization.md)).
- **Stainless — opt-in model** ([diagnostics](https://www.stainless.com/docs/reference/diagnostics/)).
  - Only endpoints listed in `resources` are generated.
  - An endpoint from the spec that is missing from the config gives a note `Endpoint/NotConfigured`.
  - An explicit exclusion is set via `unspecified_endpoints: ["post /internal"]`.
  - An endpoint in the config that is no longer in the spec gives an error `Endpoint/NotFound`.
  - A conflict between the two lists gives `Endpoint/BothSpecifiedAndUnspecified`.
- **Markers in the spec**: `x-speakeasy-ignore: true` (on an operation or parameter) ([methods](https://www.speakeasy.com/docs/customize/methods)), `x-fern-ignore`, `x-internal` (Redocly `remove-x-internal`, OpenAPI Generator `REMOVE_X_INTERNAL`).

### What to take for Dart

- ✅ **A single grammar of selectors** for filters and overrides: `GET /users/**`, `* /admin/**`, `tag:Admin`, `op:getUser`, `/regex/`. Kiota semantics; `exclude` wins.
- ✅ **Tree-shaking by default** as soon as a filter is set (as in hey-api and orval). Reachability is computed through:
  - `$ref`;
  - `discriminator.mapping` targets;
  - parent schemas in `allOf`;
  - error schemas and SSE events;
  - `$dynamicRef`.

  Report: info "N operations filtered out, M schemas removed". Optionally, an `explain Schema` command that shows through what the schema is reachable.
- ✅ **Stale filters.** A selector that matches no operation gives a warning, like `Endpoint/NotFound` in Stainless. This is the same rule as for stale overrides in R3.2.
- ⚠️ **The Stainless opt-in model** ("generate only what is listed") is a useful separate mode for large specs, not the default mode. The note `operation-not-selected` gives visibility into what has not been generated.

---

## R5. Naming

### How others do it

- **Speakeasy**
  - `x-speakeasy-name-override` at the document root is a list of rules "regular expression over `operationId` → `methodNameOverride`", for example `^get.*` → `get`. The same extension at the operation level takes precedence ([methods](https://www.speakeasy.com/docs/customize/methods)).
  - Enum values are sanitized ([enums](https://www.speakeasy.com/docs/customize/data-model/enums)):
    - special characters are replaced with words: `+` → Plus, `-` → Minus, `.` → Dot;
    - collisions are resolved by a fixed strategy: `foo/Foo/FOO` → `FOO_LOWER/FOO_MIXED/FOO_UPPER`;
    - if a collision cannot be resolved, validation fails and asks for `x-speakeasy-enums` to be set.
  - For `x-speakeasy-enums` **the map form is recommended**, because an array breaks when its length does not match `enum`.
- **Stainless**
  - Naming is explicit: `resources.accounts.methods.retrieve: get /accounts/{account_id}` ([config](https://www.stainless.com/docs/reference/config/)).
  - The diagnostic **`Name/Collision`** lists the preferred names in the order tried, the reason each was rejected (with the location of the conflict), and the fallback name that was finally used. At the end, a hint: "if `{fallback_name}` is acceptable — ignore it, otherwise use `x-stainless-naming` or a transform".
  - Other codes: `Schema/CannotInferName`, `Model/GeneratedNameClash`, `Java/NameIsReserved`, `Python/NameNotAllowed`, `Schema/CannotInferEnumMemberName` ([diagnostics](https://www.stainless.com/docs/reference/diagnostics/)). For initialisms there is `custom_casings`.
- **oapi-codegen** ([configuration schema](https://github.com/oapi-codegen/oapi-codegen/blob/main/configuration-schema.json))
  - `name-normalizer`: `ToCamelCase | ToCamelCaseWithDigits | ToCamelCaseWithInitialisms`, together with `additional-initialisms`.
  - `resolve-type-name-collisions: true` adds a suffix based on the components section (schemas, parameters, requestBodies…). Without it, a collision is an **error**, and it has to be resolved by hand via `x-go-name`.
  - `generate-types-for-anonymous-schemas` gives inline schemas names derived from the path (`GetRolesIdResponseBody_Data`).
- **orval** ([output.mdx](https://github.com/orval-labs/orval/blob/master/docs/content/docs/reference/configuration/output.mdx))
  - `override.operationName(operation, route, verb)` returns a string **or a tuple `[methodName, typeNameBase]`**. The method name and the base of the type names (`*Params`, `*Body`, `*Error`) are then set independently. This is useful when identical methods from different services must get different type names.
  - `override.components.schemas: {prefix, suffix, itemPrefix}`; the prefix also applies to `$ref`.
- **hey-api** ([parser](https://heyapi.dev/openapi-ts/configuration/parser))
  - `transforms.schemaName` — a function or a template `'Api{{name}}'`.
  - If a renaming produces a collision, **it is skipped**. A silent fallback is the opposite of R2.5.
  - `hooks.symbols.getName`.
- **Kiota** ([models](https://learn.microsoft.com/en-us/openapi/kiota/models))
  - Names of inline schemas: `<last path segment><operation>RequestBody|Response` or `<Parent type><member><ordinal number>`.
  - Enum member names are taken from `x-ms-enum`.
- **openapi-python-client**: `class_overrides` and `use_path_prefixes_for_title_model_names` (long but unique names from the full path or `title`) ([README](https://github.com/openapi-generators/openapi-python-client)).
- **Fern and ogen**: `x-fern-sdk-method-name`, `x-fern-sdk-group-name`, `x-fern-type-name`, `x-fern-parameter-name`, `x-fern-property-name` ([extensions](https://buildwithfern.com/learn/api-definitions/openapi/extensions/overview)); `x-ogen-name`, `x-ogen-properties`, `x-ogen-operation-group` ([ogen extensions](https://github.com/ogen-go/web/blob/main/docs/spec/extensions.md)).

### What to take for Dart

- ✅ **The name pipeline is a pure deterministic function:**
  1. **a list of candidates in priority order**: override → `x-…-name` → `operationId`/schema key → `title` → path;
  2. sanitization (special characters become words, as in Speakeasy);
  3. case;
  4. a check for reserved words (Dart keywords and names from `dart:core`: `List`, `Map`, `Type`, `Object`, `Function`, `Error`, `Iterable`…);
  5. resolution of collisions with a stable tie-breaker: sorting by JSON pointer, not by traversal order;
  6. **a diagnostic, like `Name/Collision` in Stainless**: which names were tried, why each was rejected, where the conflict is, which name was chosen, and which override to set (R5.2 + R2.5).
- ✅ **Collision policy**: a suffix by components section (as `resolve-type-name-collisions`: `UserParam` / `UserBody`) **with a warning**. The `strict` mode makes this an error. Never fall back silently, as hey-api does.
- ✅ **The method name and the base of type names separately** (a tuple as in orval). This covers R5.1 and R5.3 when grouping by tags.
- ✅ **Inline schemas** are named `<Parent><Property>` by default; if that is not enough, by the name from the path. **Deduplication of inline enums by a structural hash** of the set of values (R5.4); this is the same mechanism as `matches_schema` in R3.
- ✅ **Overrides of enum member names** should be accepted in the form of a map (`value → name`), not an array (Speakeasy's experience). The `x-enum-varnames` array is also read, but its length is checked (a diagnostic).

---

## R6.2 / R6.4. Type fidelity, arbitrary JSON, envelopes and generics

### How others do it

**Arbitrary JSON as a separate type, not `dynamic`**
- **Kiota**: the `UntypedNode` hierarchy with the classes `UntypedObject`, `UntypedArray`, `UntypedString`, `UntypedBoolean`, `UntypedInteger`, `UntypedLong`, `UntypedFloat`, `UntypedDouble`, `UntypedDecimal`, `UntypedNull` ([kiota-dotnet, serialization](https://github.com/microsoft/kiota-dotnet/tree/main/src/abstractions/serialization)). Unknown properties go into `AdditionalData` ([models](https://learn.microsoft.com/en-us/openapi/kiota/models)).
- **Stainless Java** ([openai-java README, Undocumented API functionality](https://github.com/openai/openai-java#undocumented-api-functionality)): `JsonValue` with a `from(...)` factory and a `Visitor` (`visitNull`, `visitBoolean`, `visitNumber`, `visitString`, `visitArray`, `visitObject`, **`visitMissing`**). Unknown fields are accessible through `_additionalProperties()`.
- **ogen**: `jx.Raw` — raw bytes with a `.Type()` method ([any.md](https://github.com/ogen-go/web/blob/main/docs/types/any.md)).
- **progenitor**: `serde_json::Value`.
- **openapi-typescript**: `unknown`; the flag `--empty-objects-unknown` ([CLI](https://openapi-ts.dev/cli)).
- **Speakeasy**: `x-speakeasy-type-override: any` ([extensions](https://www.speakeasy.com/docs/speakeasy-reference/extensions)).
- **Stainless `Schema/IsAmbiguous`**: a schema without `type` is treated as unknown with a note; the intent is confirmed via `x-stainless-any: true`.

**Configurable type mapping**
- **oapi-codegen `type-mapping`** is merged on top of the default values:
  ```yaml
  output-options:
    type-mapping:
      string:
        formats:
          date-time: {type: time.Time, import: time}
          decimal:   {type: decimal.Decimal, import: github.com/shopspring/decimal}
  ```
  An individual schema has `x-go-type` / `x-go-type-import`.
- **progenitor**: `with_replacement` and `with_conversion`.
- **Kiota**: the `KnownAndNotSupportedFormats` rule warns when a format is known but not supported.

**Envelopes and generics**
- **Stainless**
  - `settings.unwrap_response_fields: [data]` is a global envelope; at the method level, `unwrap_response: <field> | false` ([config](https://www.stainless.com/docs/reference/config/)).
  - Diagnostics: `Method/MissingEnvelopeUnwrap` (listing the fields that were found, with the hint `unwrap_field: false`), `Method/AmbiguousEnvelopeUnwrap`, `Response/TypeNotObjectForEnvelope`.
  - Pagination is described by schemas with `type: cursor | cursor_id | cursor_url | offset | page_number | fake_page`. Fields are marked with `x-stainless-pagination-property.purpose`: `items`, `next_cursor_field`, `has_next_page`, `offset_total_count_field`… The output is generic page classes and an auto-iterator.
- **Speakeasy** `x-speakeasy-pagination`: `inputs` and `outputs` via JSONPath. **Fern** `x-fern-pagination`. **AutoRest** `x-ms-pageable: {itemName, nextLinkName, operationName}` ([autorest extensions](https://github.com/Azure/autorest/blob/main/docs/extensions/readme.md)).
- **orval + `$dynamicRef`/`$dynamicAnchor`** (OAS 3.1, [output.mdx](https://github.com/orval-labs/orval/blob/master/docs/content/docs/reference/configuration/output.mdx)): the template becomes `interface PaginatedResponse<itemType>`, and the bindings become aliases `type UserListResponse = PaginatedResponse<User>`.
  ```yaml
  PaginatedResponse:
    $defs: {itemType: {$dynamicAnchor: itemType, not: {}}}
    properties: {items: {type: array, items: {$dynamicRef: '#itemType'}}}
  UserListResponse:
    $defs: {itemType: {$dynamicAnchor: itemType, $ref: '#/components/schemas/User'}}
    $ref: '#/components/schemas/PaginatedResponse'
  ```
  **OAS 3.2 §4.24.6.2 explicitly recommends** (SHOULD) supporting generics via `$dynamicRef` ([OAS 3.2](https://spec.openapis.org/oas/v3.2.0.html)).

### What to take for Dart

- ✅ **`JsonValue` is a sealed hierarchy in the runtime package**: `JsonNull`, `JsonBool`, `JsonNumber`, `JsonString`, `JsonArray`, `JsonObject`. It has `fromJson(Object?)`, `toJson()`, and convenient `asString()` / `asMap()`. Pattern matching replaces Stainless's Visitor. A schema without `type` gives an info `untyped-schema` and the type `JsonValue`; the intent can be confirmed via `x-<tool>-any: true` or an override.
- ✅ **`type_mapping`, as in oapi-codegen, but with a converter.** json_serializable requires a `JsonConverter`, so a mapping entry contains both the type and the converter:
  ```yaml
  type_mapping:
    string:
      formats:
        date: {type: Date, import: "package:my_app/date.dart", converter: DateConverter}
        decimal: {type: Decimal, import: "package:decimal/decimal.dart", converter: DecimalConverter}
  ```
  An unknown format gives a diagnostic, like `KnownAndNotSupportedFormats` in Kiota.
- ✅ **Envelopes: three recognizers in priority order:**
  1. an override or config: `envelope: {field: data, siblings: [meta]}`, like `unwrap_response_fields` in Stainless;
  2. **`$dynamicRef`/`$dynamicAnchor`** (the standard, verified in orval);
  3. a structural heuristic: schemas with the same "sibling" fields that differ only in the type of `data`. It only **suggests** a generic through a diagnostic and a ready-made override, and never silently turns anything on (R2.5).

  An ambiguity gives a diagnostic such as `AmbiguousEnvelopeUnwrap`. For serialization, use `genericArgumentFactories` in json_serializable.
- ⚠️ **Design pagination as a separate feature** now, on the Stainless purpose vocabulary (`items`, `next_cursor_field`…), so that the config format does not break later.

---

## R7. Three states of a field in PATCH

### How others do it

- **ogen** ([optional.md](https://github.com/ogen-go/web/blob/main/docs/types/optional.md)). `OptNilString { Value string; Set bool; Null bool }` with the methods `IsSet()`, `IsNull()`, `Get()`, `Or()`, `SetTo()`, `Reset()`. The key point is an **explicit decoder behaviour matrix**, exactly what R6.1 requires:

  | Schema | absent | `null` | value |
  |---|---|---|---|
  | required | Error | Error | OK |
  | optional | `Set=false` | Error | `Set=true` |
  | nullable, required | Error | `Null=true` | OK |
  | optional & nullable | `Set=false` | `Set=true, Null=true` | `Set=true, Null=false` |

  For arrays there is a separate matrix, in which `nil` and `[]` are distinguished.
- **oapi-codegen** ([README, Nullable types](https://github.com/oapi-codegen/oapi-codegen#generating-nullable-types)). `output-options.nullable-type: true` generates `nullable.Nullable[T]` with the `omitempty` tag. Without this option, `*string` does not distinguish "not sent" from `null`, and the README explicitly acknowledges this.
- **openapi-python-client** ([types.py in the golden record](https://github.com/openapi-generators/openapi-python-client/tree/main/end_to_end_tests/golden-records)). A sentinel `class Unset: __bool__ → False; UNSET = Unset()`. Fields have the type `T | None | Unset = UNSET`, and `to_dict` skips `UNSET`.
- **Stainless Python** ([`_types.py`](https://github.com/openai/openai-python/blob/main/src/openai/_types.py)). Parameters look like `temperature: Optional[float] | Omit = omit`. `NotGiven` is used where `None` has a meaning of its own ("no timeout"). On the response side, `model_fields_set` distinguishes a missing field from `null` ([README](https://github.com/openai/openai-python#how-to-tell-whether-none-means-null-or-missing)).
- **Stainless Java** `JsonField<T>`: `isMissing()`, `isNull()`, the value, or `asUnknown()`. `JsonMissing.of()` forcibly removes even a required field. The FAQ explains the choice: "Representing absent vs explicitly null values" ([openai-java FAQ](https://github.com/openai/openai-java#why-do-you-represent-fields-using-jsonfieldt-instead-of-just-plain-t)).
- **Kiota BackingStore** (`--backing-store`) ([abstractions](https://learn.microsoft.com/en-us/openapi/kiota/abstractions), [models](https://learn.microsoft.com/en-us/openapi/kiota/models)). Values live in a store with **change tracking**: `InitializationCompleted`, `ReturnOnlyChangedValues`, `EnumerateKeysForValuesChangedToNull()`. Scenario: fetch an object via GET, change one field, and send a PATCH with only that field.

### What to take for Dart

- ✅ **A sealed type in the runtime package** (for example, `Patch<T>` / `Optional<T>`) with three states: `Absent`, `Null`, `Value(T)`. It is the direct counterpart of `OptNil` / `JsonField`, with exhaustive pattern matching in Dart 3. It is generated only for fields that pass the rule from R7.2 (by default, optional + nullable in the PATCH body).
- ✅ **Document the ogen matrix as a contract.** A separate table for the request, the response, and PATCH (R6.1), with the columns "absent / null / value" and a description of what the decoder does and what the encoder does.
- ⚠️ **json_serializable cannot "skip a key" from a converter.** `includeIfNull` does not distinguish Absent from Null. So for models with tri-state fields, the generator has to emit its own `toJson`: either a wrapper over `_$XToJson` that removes the keys holding the sentinel value (like `UNSET` in Python), or a fully custom one. This has to be decided in the serialization architecture.
- ✅ **R7.3** (a field with one state never sends null unless it is set): by default `includeIfNull: false` for optional request fields. This is the `omit` behaviour in Stainless.
- ⚠️ **Kiota's BackingStore** (change tracking) is an interesting alternative for "PATCH from a fetched object", but it is complex, and the models stop being simple. Do not make it the default; possibly later as a mode.
- ⚠️ **Do not expose tri-state on the response side by default.** An optional `fieldsSet` in the style of `model_fields_set` is enough for those who need it.

---

## R8. Open enums with a raw value

### How others do it

- **Speakeasy** ([enums](https://www.speakeasy.com/docs/customize/data-model/enums), [forward compatibility](https://www.speakeasy.com/docs/sdks/manage/forward-compatibility)).
  - A schema is opened or closed via `x-speakeasy-unknown-values: allow | disallow`.
  - The `forwardCompatibleEnumsByDefault` flag in `gen.yaml` appeared in [v1.661.0](https://www.speakeasy.com/changelog/release/v1.661.0) and is **enabled by default** (except for Terraform). **Enums with a single value are not opened automatically.**
  - Representations: TS — `"red" | "green" | Unrecognized<string>`; Python — `Union[Literal[...], UnrecognizedStr]`; Java — `BackgroundColor.of("purple")` with `isKnown()`.
  - Closed enums are kept deliberately: they "help catch API drift in tests".
- **Stainless Java/Kotlin** ([FinishReason.kt in openai-java](https://github.com/openai/openai-java/blob/main/openai-java-core/src/main/kotlin/com/openai/models/chat/completions/ChatCompletion.kt)). The generated class contains:
  - a private constructor over `JsonField<String>` and constants `STOP = of("stop")`;
  - `enum Known { STOP, … }` and `enum Value { STOP, …, _UNKNOWN }`;
  - `value()`, which returns `_UNKNOWN`; `known()`, which throws `InvalidDataException`; `asString()`, `validate()`, `isValid()`.

  The FAQ explains: "Java `enum` classes are not trivially forwards compatible".
- **OpenAPI Generator** (dart-dio, swift, kotlin): `enumUnknownDefaultCase=true` adds `unknown_default_open_api` ([dart-dio](https://openapi-generator.tech/docs/generators/dart-dio)). The raw value is **lost**; this is an anti-pattern for R8.1.
- **AutoRest** `x-ms-enum: {name, modelAsString, values: [{value, name, description}]}`. **`modelAsString: true` is the default**, and such an enum is considered extensible ([autorest extensions](https://github.com/Azure/autorest/blob/main/docs/extensions/readme.md)).
- **Zalando `x-extensible-enum`**: oasdiff separately knows that adding a value to such an enum in a response does not break compatibility ([BREAKING-CHANGES.md](https://github.com/oasdiff/oasdiff/blob/main/docs/BREAKING-CHANGES.md#breaking-changes-to-enum-values)).
- **Kiota does the opposite on purpose**: an unknown enum value throws an exception, to "fail as early as possible" ([models](https://learn.microsoft.com/en-us/openapi/kiota/models)). This is a counterexample for R8.1.
- **oapi-codegen**: enums are typed string constants (open by nature) with a `Valid()` method.

### What to take for Dart

- ✅ **Open enums in responses by default, closed in requests** (R8.1 + R8.2):
  - the request type is a plain Dart `enum Status` (closed; an unknown value cannot be sent);
  - the response field is `OpenEnum<Status>` = sealed `Known(Status)` | `Unknown(Object raw)`. This is the direct counterpart of `Known`/`Value._UNKNOWN` in Stainless.

  If the schema is shared by both directions, two kinds are generated. The `Unknown` constructor is not available in the request API.
- ✅ **Speakeasy rules**:
  - an enum with a single value stays closed (it is a constant);
  - an override at the schema level: `x-<tool>-unknown-values: allow | disallow`;
  - for compatibility, also read `x-extensible-enum`, `x-ms-enum.modelAsString` and `x-speakeasy-unknown-values`.
- ⚠️ **A conflict between R8 and R14.2 through exhaustiveness in Dart.** Adding a value to a Dart `enum`, or a subclass to a `sealed` hierarchy, **breaks compilation** of a consumer's `switch` if there is no `_`/`default` there ([exhaustiveness](https://dart.dev/language/branches#exhaustiveness-checking)). `Unknown` does not solve the problem, because a new *known* member also adds a case. Options:
  - (a) `enum_style: dart_enum`: convenient, but every new value is a breaking change of the Dart API, and R14 has to show this;
  - (b) `enum_style: open_class`: a class with `static const` instances (or an `extension type` over `String`); a `switch` over constants is not checked for exhaustiveness, so a new value breaks nothing.

  Recommendation: (b) for response enums by default, (a) as an option. This conclusion comes from Dart's language semantics and Stainless's experience (the FAQ about `enum`); it has not been verified on generators.

---

## R9. Polymorphism: a variant for an unknown type

### How others do it

- **Speakeasy** ([forward compatibility](https://www.speakeasy.com/docs/sdks/manage/forward-compatibility)).
  - `forwardCompatibleUnionsByDefault: tagged-only | false | true` appeared in [v1.663.0](https://www.speakeasy.com/changelog/release/v1.663.0). An unknown discriminator gives `{ type: "UNKNOWN"; raw: unknown }`.
  - For unions without a discriminator, `unionStrategy: populated-fields`: try all variants and take the one with the most populated fields; on a tie, the one with the fewest type casts.
- **OAS 3.2 `discriminator.defaultMapping`** ([OAS 3.2 §4.25](https://spec.openapis.org/oas/v3.2.0.html)). Required if the discriminator property is optional. It applies when the property is **absent or its value has no mapping**. This is the **standard** place for an "unknown" variant.
- **ogen** ([sumtype.md](https://github.com/ogen-go/web/blob/main/docs/types/sumtype.md), [features](https://github.com/ogen-go/web/blob/main/docs/02-features.mdx)). `oneOf` becomes a struct with a `Type` field (enum) and the variant fields. The discriminator is inferred **at generation time** by a ladder:
  1. an explicit `discriminator`;
  2. the JSON type (for primitives);
  3. **unique fields**;
  4. a shared field with different JSON types;
  5. a shared field with non-overlapping enum values.
- **Kiota** ([models](https://learn.microsoft.com/en-us/openapi/kiota/models)). `oneOf` is a wrapper with a separate property for each variant. If any variant is an object, the discriminator is "MUST"; the `MissingDiscriminator` rule gives a warning. Primitives are tried in turn.
- **Stainless**
  - Diagnostics ([diagnostics](https://www.stainless.com/docs/reference/diagnostics/)): `Java/SchemaUnionDiscriminatorMissing` ("each variant has to be tried in turn: inefficient or ambiguous if two variants have identical required fields"), `Go/DuplicateVariantDeserializationConditions`, `Schema/DiscriminatedUnionVariantMissingProperty`.
  - The Java union has `_json()` (raw JSON) and a `Visitor` with an `unknown(json: JsonValue?)` method, which by default throws an exception ([ChatCompletionMessageParam.kt](https://github.com/openai/openai-java/blob/main/openai-java-core/src/main/kotlin/com/openai/models/chat/completions/ChatCompletionMessageParam.kt)).
- **Fern** `x-fern-discriminator-context: data | protocol` distinguishes a discriminator inside the JSON from a discriminator in the protocol framing, like `event:` in SSE ([discriminator-context](https://buildwithfern.com/learn/api-definitions/openapi/extensions/discriminator-context)).

### What to take for Dart

- ✅ **A sealed hierarchy with a variant `XUnknown(String? discriminatorValue, Map<String, Object?> raw)`** (R9.1). Also take OAS 3.2's `defaultMapping` into account: if it is set, the schema it names becomes the fallback variant instead of `Unknown`.
- ✅ **`oneOf` without a discriminator (R9.2)**: a diagnostic with configurable behaviour `union_strategy: error | structural | raw` at the schema level.
  - `structural` is ogen's ladder, computed **at generation time**: type → unique required fields → field type → non-overlapping const/enum.
  - If the variants' conditions overlap, a diagnostic such as `DuplicateVariantDeserializationConditions` suggests a discriminator override.
  - Offer Speakeasy's runtime `populated-fields` heuristic only as an explicit option.
- ✅ **Mixed primitives (R9.3)** — a `StringOrInt` wrapper that distinguishes by JSON type (a type discriminator in ogen).
- ⚠️ **The protocol discriminator and the data discriminator** (Fern) must be taken into account for SSE in R12.
- ⚠️ **A reminder from R8 about exhaustiveness**: adding a variant to a sealed type is breaking for a consumer's `switch`. The `Unknown` variant does not prevent this.

---

## R10.5 / R10.8. Request metadata and security as metadata

### How others do it

- **progenitor** ([progenitor_client.rs](https://github.com/oxidecomputer/progenitor/blob/main/progenitor-client/src/progenitor_client.rs)): `OperationInfo { operation_id: &'static str }` is passed to `ClientHooks::pre(&mut request, &info)` and `post`.
- **openapi-fetch**: middleware `onRequest({ request, schemaPath, params, id, options })`. `schemaPath` is a path template such as `/projects/{project_id}`, and logic is routed by it ([middleware-auth](https://openapi-ts.dev/openapi-fetch/middleware-auth)).
- **hey-api** ([generated sdk.gen.ts](https://github.com/hey-api/openapi-ts/blob/main/examples/openapi-ts-fetch/src/client/sdk.gen.ts), [auth.gen.ts](https://github.com/hey-api/openapi-ts/blob/main/examples/openapi-ts-fetch/src/client/core/auth.gen.ts)).
  - Each call passes `security: [{ scheme: 'bearer', type: 'http' }]`.
  - The client calls `auth(auth: Auth)` with `{type, scheme, in, name, key}`. The token is "attached only to requests that require auth".
  - This is exactly R10.8: security is metadata, not code in the generated method.
- **Kiota** `RequestInformation.RequestOptions: IEnumerable<IRequestOption>` — middleware options at the request level ([abstractions](https://learn.microsoft.com/en-us/openapi/kiota/abstractions)).
- **Stainless**
  - TS: `{ maxRetries, timeout, signal, headers }` on each call, plus `.withResponse()` / `.asResponse()` ([openai-node](https://github.com/openai/openai-node)).
  - Python: `extra_headers`, `extra_query`, `extra_body`, `timeout`, `.with_raw_response`, `.with_options()` ([openai-python](https://github.com/openai/openai-python)).
  - Java: `RequestOptions.builder().responseValidation(true)`.
- **Speakeasy**: `x-speakeasy-retries` at the operation level and `retries` as a call argument ([retries](https://www.speakeasy.com/docs/customize/runtime/retries)).
- **ogen**: a typed `SecuritySource` interface ([features](https://github.com/ogen-go/web/blob/main/docs/02-features.mdx)).

### What to take for Dart (dio)

- ✅ **Operation metadata in `Options.extra` under a single key**, with typed access from the runtime package:
  ```dart
  // runtime
  final class OperationInfo {
    final String operationId, method, pathTemplate;
    final List<String> tags;
    final List<List<SecurityRequirement>> security; // OR of AND, as in OAS
    static OperationInfo? of(RequestOptions o) => o.extra[_key] as OperationInfo?;
  }
  ```
  Keep the `security` structure as in OAS: an array of alternatives, each of which is a set of schemes with `scopes`. hey-api simplifies this structure.
- ✅ **Per-call parameters**: `CancelToken`, `onSendProgress`, `onReceiveProgress`, `Map<String, Object?>? extra`, `Options? options` (merged, not replaced). The generated code adds nothing to the client (R10.1).
- ✅ **An optional `SecurityInterceptor`** in the runtime, like `auth` in hey-api: `resolve(SecurityScheme scheme) → FutureOr<String?>` supplies only the schemes that the operation requires. The generated code does **not** embed authorization.

---

## R11. Typed errors, Result or exceptions, undocumented status

### How others do it

- **Kiota: the algorithm for choosing the error type** ([errors](https://learn.microsoft.com/en-us/openapi/kiota/errors)):
  1. the exact code;
  2. the `4XX` / `5XX` range;
  3. `default`;
  4. the base `ApiException` with the message "The server returned an unexpected status code and no error factory is registered for this code".

  Other details:
  - `ResponseStatusCode` and `ResponseHeaders` are on the base class;
  - **`x-ms-primary-error-message: true`** marks the field the message text is taken from;
  - a mapping is considered valid only if the schema is an object with at least one field.
- **progenitor** — the cleanest separation of variants ([progenitor_client.rs](https://github.com/oxidecomputer/progenitor/blob/main/progenitor-client/src/progenitor_client.rs)):
  ```rust
  pub enum Error<E> {
    InvalidRequest(String), CommunicationError(reqwest::Error), InvalidUpgrade(..),
    ErrorResponse(ResponseValue<E>),            // documented error
    ResponseBodyError(reqwest::Error),
    InvalidResponsePayload(Bytes, serde_json::Error), // expected code, payload could not be decoded
    UnexpectedResponse(reqwest::Response),      // not described; "may represent a success or failure"
    Custom(String) }
  ```
- **swift-openapi-generator** ([SOAR-0007](https://github.com/apple/swift-openapi-generator/blob/main/Sources/swift-openapi-generator/Documentation.docc/Proposals/SOAR-0007.md)). `Output` is an enum with a case for each documented status, plus **`case undocumented(statusCode: Int, UndocumentedPayload)`**. Alongside it are **throwing getters**: `try await client.getGreeting().ok.body.json` throws an error if the status is not 200 or the body is not JSON. One model serves both styles: a Result-like `switch` and exceptions.
- **Stainless**
  - Hierarchy: `APIError` splits into `APIConnectionError` (with `APITimeoutError`) and `APIStatusError(status_code, response)`. From the latter: `BadRequestError` (400), `AuthenticationError` (401), `PermissionDeniedError` (403), `NotFoundError` (404), `UnprocessableEntityError` (422), `RateLimitError` (429), `InternalServerError` (≥500) ([openai-python](https://github.com/openai/openai-python#handling-errors)).
  - Java adds `UnexpectedStatusCodeException` for other statuses, `SseException` for errors "after a successful initial response", `IoException` and `InvalidDataException` (lazy validation: the exception is thrown only on access to a field) ([openai-java](https://github.com/openai/openai-java#error-handling)).
- **Speakeasy** ([errors](https://www.speakeasy.com/docs/customize/responses/errors)).
  - `x-speakeasy-errors: {statusCodes: [4XX, 5XX, …], override: true}`. `default` is not considered an error until it is listed.
  - Typed errors have "hoisted" properties.
  - `SDKError` (status, body as a string, raw response) — for undocumented statuses.
  - `SDKValidationError` with `rawValue` and `pretty()`, `HTTPClientError` — for network errors.
  - `x-speakeasy-error-message: true` sets the field with the message text.
- **openapi-python-client**: `Response[T]` with `parsed`; the `raise_on_unexpected_status` flag (default `False`) throws `UnexpectedStatus(status_code, content)`.
- **hey-api** ([types.gen.ts](https://github.com/hey-api/openapi-ts/blob/main/examples/openapi-ts-fetch/src/client/client/types.gen.ts)): the generic `ThrowOnError`. With `false`, the method returns `{data, error, response}` as a discriminated union; with `true`, it throws. The delivery model is chosen at the type level.
- **ogen, convenient errors** ([convenient_errors.md](https://github.com/ogen-go/web/blob/main/docs/concepts/convenient_errors.md)): if **every** operation has the same `default` response with a single JSON, one shared error type is generated. The switch is `convenient_errors: auto | on | off`.
- **openapi-fetch**: `onError` catches only `fetch` errors (network, abort), not 4xx/5xx. Transport is separated from HTTP.

### What to take for Dart

- ✅ **A sealed hierarchy in the runtime package** (R11.1, R11.3, R11.7, modelled on progenitor):
  ```
  ApiFailure<E>
   ├─ TransportFailure (DioException without response: connection, timeout, cancel)
   ├─ HttpFailure (status, headers, rawBody)
   │   ├─ DocumentedError<E>   // body E, per the status mapping
   │   └─ UndocumentedResponse // R11.3; may also be 2xx (as in progenitor)
   └─ DecodeFailure (status, raw, schema, jsonPath)  // InvalidResponsePayload; R6.5
  ```
- ✅ **Type selection order as in Kiota**: exact code → `4XX`/`5XX` → `default` → `UndocumentedResponse`.
- ✅ **A shared error schema is generated once** (R11.4): deduplication by `$ref`, plus ogen's heuristic for an identical `default` across all operations. The field carrying the message text is set via `x-<tool>-error-message` (by analogy with `x-ms-primary-error-message` and `x-speakeasy-error-message`).
- ✅ **Delivery model (R11.2) in the Swift style**: the method returns `Future<T>` and throws `ApiFailure`; alongside it is a variant (`…Result()` or an `.result` extension) that returns `Result<T, ApiFailure<E>>`. Dio errors take the regular path through `onError` interceptors (R10.2), and the generated code maps `DioException` to a typed error **after** the interceptor chain. Config: `errors: throw | result | both`.
- ⚠️ **Lazy validation** (`InvalidDataException` in Stainless Java) is interesting for forward compatibility, but contradicts R6.5 ("a clear decoding error immediately"). Keep strict decoding as the default.

---

## R12. SSE: typed events, `itemSchema`, reconnection

### How others do it

- **OAS 3.2** ([§4.14.4, §4.14.6.3](https://spec.openapis.org/oas/v3.2.0.html)).
  - `text/event-stream` is described via `itemSchema`.
  - A typical event schema: `{data: string (required), event: string, id: string, retry: integer ≥ 0}`.
  - JSON in `data` is described via `contentMediaType: application/json` + `contentSchema`. Event types are given through `oneOf` on `event` with `const`.
  - The stream is first parsed per WHATWG: comments and unknown fields are ignored, and multi-line `data` is joined with `\n`. Only then is the schema applied. `contentSchema` is not validated by default.
- **FastAPI already emits `itemSchema`** ([fastapi/openapi/utils.py](https://github.com/fastapi/fastapi/blob/master/fastapi/openapi/utils.py), [SSE reference](https://fastapi.tiangolo.com/reference/sse/)).
  - For SSE routes: `text/event-stream: {itemSchema: {…, data: {type: string, contentMediaType: application/json, contentSchema: <Model>}}}`.
  - For generators: `application/jsonl: {itemSchema: …}`.
  - At the same time, `openapi_version` defaults to `"3.1.0"`. So a 3.1 document contains a key from 3.2. orval explicitly mentions that for "FastAPI's `itemSchema`" validation has to be turned off ([input.mdx](https://github.com/orval-labs/orval/blob/master/docs/content/docs/reference/configuration/input.mdx)).
- **Speakeasy** ([SSE](https://www.speakeasy.com/docs/customize/runtime/server-sent-events)).
  - Only the fields `id`, `event`, `data`, `retry` are allowed in an event schema; anything else is a validation error.
  - Event types are given via `oneOf` + `discriminator.propertyName: event` with `const`.
  - **`x-speakeasy-sse-sentinel: '[DONE]'`** hides the sentinel and ends the iteration.
  - `inferSSEOverload` gives one method with a `stream: true` parameter. Separate methods can be obtained via a URL fragment (`/chat#streamed`).
- **Stainless** ([streaming](https://www.stainless.com/docs/sdks/configure/streaming/), [config](https://www.stainless.com/docs/reference/config/)).
  - `streaming.on_event` — **an ordered table of handlers**:
    ```yaml
    on_event:
      - data_starts_with: '[DONE]'
        handle: done            # read the stream to the end, ignoring the rest
      - event_type: error
        handle: error           # with error_property
      - event_type: [ping, heartbeat]
        handle: continue
      - kind: fallthrough       # catches everything, including future event types
        handle: yield
    ```
  - `event_type: null` catches events without an `event:` line.
  - `done` and `break` differ: `done` reads the connection to the end, `break` aborts immediately.
  - Diagnostics: `Streaming/DuplicateFallthroughEvents`, `Streaming/ConflictingEventTypeHandling`.
  - `param_discriminator` sets the `stream` parameter, and `stream_event_model` the event model.
- **Fern** ([SSE](https://buildwithfern.com/learn/api-definitions/openapi/endpoints/sse), [SSE metadata](https://buildwithfern.com/learn/sdks/deep-dives/sse-metadata)).
  - Syntax: `x-fern-streaming: {format: sse, terminator: "[DONE]", resumable: true, stream-condition: $request.stream, response, response-stream}`.
  - **`resumable`**: after a disconnect, the client reconnects and sends the last id in `Last-Event-ID`.
    - The delay is taken from `retry:`; if it is absent, it is 1 s, capped at 30 s.
    - **Up to 5 consecutive attempts; the counter resets with every event received.**
    - A `terminator` is required to tell a completed stream from an interrupted one.
  - `withMetadata()` gives access to `id`, `event` and `retry`.
- **ogen** ([README, SSE](https://github.com/ogen-go/ogen#server-sent-events)).
  - `x-ogen-sse-event-shape: data-only` (by default the schema describes only `data`) | `full` (the whole "envelope" event with a discriminator on `event`) | `full-array`.
  - An event is sent only if there is at least one `data:` line. The default `event` is `"message"`.
  - `id` and `retry` are updated even for events that were not sent.
  - Reconnection options: initial Last-Event-ID, delay, maximum attempts, buffer size, **maximum event size** (`ErrEventTooLarge`: the event is read to the end; the stream is not closed).
  - Interface: `Next`, `All`, `State`, `Close`.
- **hey-api** ([serverSentEvents.gen.ts](https://github.com/hey-api/openapi-ts/blob/main/examples/openapi-ts-fetch/src/client/core/serverSentEvents.gen.ts)): options `onSseEvent`, `onSseError`, `sseDefaultRetryDelay` (3000), `sseMaxRetryAttempts`, `sseMaxRetryDelay` (30000); exponential backoff and `Last-Event-ID`.
- **Stainless nuances**: openai-python **does not retry a stream automatically**, because "replaying a request could duplicate output already delivered" ([README](https://github.com/openai/openai-python#handling-errors)). openai-java has a separate `SseException` for errors after a 200.
- **swift-openapi-generator** ([Useful patterns](https://github.com/apple/swift-openapi-generator/blob/main/Sources/swift-openapi-generator/Documentation.docc/Articles/Useful-OpenAPI-patterns.md)): `asDecodedServerSentEventsWithJSONData(of:decoder:while:)`, where `while` is the termination condition, that is, the sentinel.

### What to take for Dart

- ✅ **The parser in the runtime package follows WHATWG strictly.**
  - Lines are split on CR, LF and CRLF; comments are ignored; `data` is joined.
  - An event is dispatched only if there is `data`. The default `event` is `message`.
  - `id` and `retry` are updated even without dispatch (as in ogen). There is an event size limit.
  - The output is `SseEvent {id, event, data, retry}`.
- ✅ **Sources of event schemas, by priority**:
  1. override;
  2. `itemSchema` — **in any declared OAS version**: the normalizer accepts it in 3.0/3.1 too, with an info diagnostic (the FastAPI case);
  3. compatible `x-` extensions (`x-<tool>-sse`, optionally reading `x-speakeasy-sse-sentinel` and `x-fern-streaming`);
  4. `schema` in "data-only" mode, as the default in ogen.
- ✅ **Typed events** — a sealed type with a variant `UnknownEvent(SseEvent raw)` (R12.2). The discriminator from the protocol framing (`event:`) is explicitly separated from the discriminator inside `data` (`x-fern-discriminator-context`).
- ✅ **A handler table as in Stainless**: the sentinel (`[DONE]`) gives `done`; an error-type event gives a typed `SseStreamError` (separate from HTTP errors, like `SseException` in Java); ping gives `skip`; fallthrough gives `yield Unknown`. Diagnostics for rule conflicts — as in Stainless.
- ✅ **Reconnection (R12.5)** — the Fern policy:
  - `Last-Event-ID` and `retry:` with a fallback value and a cap;
  - N consecutive attempts, with the counter reset on each event;
  - retry only when a `terminator` is present.

  **Disabled by default for POST**: a retry may duplicate the result (the openai-python argument). It is enabled with the `resumable` flag on the operation.
- ⚠️ **NDJSON/JSONL (R12.6)**: FastAPI already emits `application/jsonl` with `itemSchema`. The parser should be designed so that the framing format is pluggable (SSE or JSONL).

---

## R13.1. Deterministic output

### How others do it

- **Kiota** `kiota-lock.json`: all generation parameters and the **hash of the description**. If the description and the parameters have not changed, generation is skipped. The file is meant to be committed ([using](https://learn.microsoft.com/en-us/openapi/kiota/using)).
- **Speakeasy** `gen.lock`: `docChecksum`, `docVersion`, `speakeasyVersion`, `generationVersion`, `configChecksum`, `releaseVersion`, versions of the generator's features, and `releaseNotes` ([versioning](https://www.speakeasy.com/docs/sdks/manage/versioning)).
- **OpenAPI Generator**: option `hideGenerationTimestamp` (default `false` in Java), that is, **by default the output is not deterministic** ([java](https://openapi-generator.tech/docs/generators/java)). This is a ❌ example.
- **openapi-typescript**: `--alphabetize`. **hey-api**: `preserveOrder`; without it the order is not preserved "for performance reasons".
- **oasdiff**: an explicit selection rule "a shared schema is reported at the first property in alphabetical order": "The same comparison always reports the change at the same property".
- **Stainless editions**: `edition: "2025-10-08"` — "a versioned set of non-backwards-compatible changes" ([config](https://www.stainless.com/docs/reference/config/)). The generator changes the output, and the user switches to the new edition explicitly. This is the answer to R15.4: a change of output for the same input is a breaking change. **Kiota** similarly has `--exclude-backward-compatible`.

### What to take for Dart

- ✅ **The generated code has no time, absolute paths, or generator version.** The version lives only in the lock file. The header is a fixed phrase "GENERATED CODE — DO NOT EDIT".
- ✅ **`openapi_dart.lock`** contains the sha256 of the spec, config, overrides and baseline, the generator version, the edition, and the list of generated files with hashes. On it are built the `check --up-to-date` command for CI and the comparison base for R14.
- ✅ **A stable order everywhere**: sorting by a canonical key with a tie-break by JSON pointer. Every selection rule is written explicitly (as in oasdiff). No `HashSet` and `HashMap` in output collections. Golden tests are run twice (and on different OSes, with `\n`) and compared byte by byte.
- ✅ **`edition` in config** (Stainless idea). New output rules follow the new edition, and a generator change does not break the user without their consent.

---

## R14. Report on changes between regenerations, Dart API breaking changes

### How others do it

- **oasdiff** ([BREAKING-CHANGES.md](https://github.com/oasdiff/oasdiff/blob/main/docs/BREAKING-CHANGES.md)).
  - Commands `breaking` and `changelog`. Hundreds of checks with IDs such as `response-success-status-removed`, `request-property-became-nullable`, `api-security-removed`; levels `ERR`, `WARN`, `INFO`.
  - `--fail-on ERR|WARN|INFO` sets the level from which CI fails.
  - `--severity-levels file`: lines `check-id err|warn|info|none`.
  - `--err-ignore` / `--warn-ignore`: text files (markdown is allowed) with lines "METHOD /path + description".
  - Formats: `json`, `yaml`, `markdown`, `html`, `githubactions`, `junit`, `singleline`. `oasdiff schema` outputs the JSON Schema of the output. There is a fingerprint of the change and positions in the YAML source.
  - **Checks account for direction** ([NULLABILITY.md](https://github.com/oasdiff/oasdiff/blob/main/docs/NULLABILITY.md)): a request field that became nullable is not breaking; a response field that became nullable is breaking. All three forms of nullable (`nullable`, `type: [T, "null"]`, `oneOf` with null) are considered equivalent.
  - A change to a shared schema is reported once, with "also at …".
  - `x-extensible-enum` is handled separately.
- **Speakeasy** ([versioning](https://www.speakeasy.com/docs/sdks/manage/versioning), [SDK changelogs](https://www.speakeasy.com/docs/sdks/manage/sdk-changelogs), [breaking changes](https://www.speakeasy.com/docs/sdks/manage/breaking-changes)).
  - The version bump is computed from three independent sources: generator features in `gen.lock`, `info.version` or the spec checksum, and the config checksum. The maximum is taken.
  - Analysis of the **content** of the specification for breaking changes is marked "coming soon".
  - SDK changelog: added, removed and changed methods; removals are marked as breaking.
- **Fern** `--version AUTO` ([blog, August 2026](https://buildwithfern.com/post/automating-semantic-versioning-api-sdks-claude), [self-hosted](https://buildwithfern.com/learn/sdks/deep-dives/self-hosted-versioning)).
  - Compares the **generated SDK** of the previous and the new release. The result is major, minor, patch or no_change, plus changelog and PR summary. CI fails on major.
  - The alternative is `fern ir` + `fern diff` at the level of the intermediate representation (IR).
  - The documentation admits that the tool relies on "AI diff analysis", and honestly describes false positives (inserting a field into a Go struct).
  - It says directly: adding an enum value is "additive over HTTP but breaking in a closed-enum deserializer".
- **Stainless**: breaking change detection — a paid enterprise feature for GitHub CI ([docs](https://www.stainless.com/docs/enterprise/breaking-change-detection/)).
- **Dart: `dart_apitool diff --old <ref> --new <ref>`** ([pub.dev](https://pub.dev/packages/dart_apitool)). References can be a path, `pub://name/version` or `git://…`. There are `--version-check-mode none|fully|onlyBreakingChanges`, `--report-format cli|markdown|json`, and a non-zero exit code if semver is violated. It models the package's public API and compares two versions.

### What to take for Dart

- ✅ **Two levels of report (R14.1).**
  1. **Specification changes** on the normalized IR. Check IDs in the oasdiff style, necessarily **accounting for direction** (request or response). One can also run oasdiff itself as an external step, but our own diff on the IR is more precise, because it sees overrides.
  2. **Dart API changes**, computed from the generator's "surface model": classes, constructors (required or optional parameters), fields and types, enum members, sealed variants. They must be classified by Dart rules, not HTTP rules:
     - a new required constructor parameter of a request model — breaking;
     - a new `enum` member or `sealed` variant — breaking for an exhaustive `switch` (see R8/R9);
     - a new optional field — not breaking.

  As a safety net in CI — `dart_apitool diff` on the generated package.
- ✅ **Fingerprint and ignore for approved breaking changes** (oasdiff), `--fail-on`, `--severity-levels`. Formats markdown (for PRs) and json.
- ✅ **Compute the semantic version bump like Speakeasy**: the maximum of (generator or edition changes, spec changes, config changes). No LLM analysis, deterministic.
- ✅ **Check R14.2 automatically**: a golden test "added an enum value / union variant / optional field → the consumer's generated code from fixtures compiles". This catches the exhaustiveness conflict with R8 and R9.

---

## Table of de facto `x-` extensions

Notes: "read" means verified in the documentation or code via the links above. The "For Dart" column is a recommendation.

| Extension | Purpose | Who reads | Who generates | For Dart |
|---|---|---|---|---|
| `x-enum-varnames` | Names of enum members (array, length = `enum`) | OpenAPI Generator ([templating](https://github.com/OpenAPITools/openapi-generator/blob/master/docs/templating.md)), oapi-codegen, openapi-python-client, orval, openapi-typescript ([advanced](https://openapi-ts.dev/advanced)) | manually or via overlay | ✅ read (R8.4), check the length |
| `x-enumNames` | The same, "NSwag/NJsonSchema style" | oapi-codegen, orval, openapi-typescript | NSwag/NJsonSchema (ASP.NET); no automatic generation found in `@nestjs/swagger` | ✅ read as an alias |
| `x-enum-descriptions` / `x-enumDescriptions` | Description of each value | OpenAPI Generator, openapi-typescript, orval (also lowercase variants) | NJsonSchema / manually | ✅ read both forms → doc comments |
| OAS 3.1 `oneOf: [{const, title, description}]` | "Annotated enumerations" (OAS 3.2 §4.24.6.3, MAY) | oapi-codegen (enum-via-oneOf, `skip-enum-via-oneof`), orval | Pydantic/others manually | ✅ recognize as an enum with metadata |
| `x-extensible-enum` | Open enum (Zalando) | oasdiff, Zally | manually | ✅ treat as open enum |
| `x-ms-enum` `{name, modelAsString, values[{value,name,description}]}` | Name of the enum and its members; `modelAsString: true` (default) = extensible | AutoRest, Kiota (member names) | Azure specifications | ✅ read `name` and `values`; `modelAsString` → open |
| `x-speakeasy-unknown-values: allow\|disallow` | Open or closed enum/union | Speakeasy | — | ⚠️ read for compatibility |
| `x-speakeasy-enums` (map\|array), `x-speakeasy-enum-descriptions` | Names and descriptions of members | Speakeasy | — | ⚠️ optional |
| `x-nullable` | nullable from Swagger 2.0 | OpenAPI Generator (migration doc), AutoRest | Swashbuckle/NSwag in 2.0 | ✅ normalizer → `nullable` (info) |
| `x-internal` | Exclude from generation or publication | Redocly (`remove-x-internal`), OpenAPI Generator (`REMOVE_X_INTERNAL`, `FILTER`) | manually / normalizer | ✅ respect as exclude |
| `x-go-type` / `x-go-type-import` / `x-go-name` / `x-go-type-name` / `x-omitempty` / `x-order` / `x-deprecated-reason` | Type and name mapping for Go | oapi-codegen; ogen reads `x-oapi-codegen-extra-tags` | — | ❌ do not read; ✅ copy the design: `x-dart-type` + `x-dart-type-import` |
| `x-ogen-name`, `x-ogen-properties`, `x-ogen-operation-group`, `x-ogen-sse-event-shape` | Names, groups, SSE shape | ogen | — | ❌ / idea `event-shape` ✅ |
| `x-speakeasy-name-override`, `x-speakeasy-ignore`, `x-speakeasy-retries`, `x-speakeasy-pagination`, `x-speakeasy-errors`, `x-speakeasy-error-message`, `x-speakeasy-sse-sentinel`, `x-speakeasy-type-override: any`, `x-speakeasy-max-method-params` | Full set of SDK settings | Speakeasy | — | ⚠️ optionally read `sse-sentinel` and `error-message`; the rest are ideas for our own `x-` extensions |
| `x-fern-sdk-method-name`, `x-fern-sdk-group-name`, `x-fern-type-name`, `x-fern-ignore`, `x-fern-streaming`, `x-fern-discriminator-context`, `x-fern-pagination`, `x-fern-enum` | Names, groups, streams, pagination | Fern | — | ⚠️ ideas; `discriminator-context` ✅ as a concept |
| `x-stainless-pagination-property`, `x-stainless-any`, `x-stainless-naming` | Pagination, explicit any, names | Stainless | — | ✅ idea `x-<tool>-any` |
| `x-ms-primary-error-message` | Field with the error text | Kiota | Microsoft Graph | ✅ read (alias for our own) |
| `x-ms-pageable`, `x-ms-error-response`, `x-ms-client-name`, `x-ms-discriminator-value` | Pagination, "this is an error", name, discriminator value | AutoRest | Azure | ⚠️ `x-ms-client-name` can be read as the name |
| `x-lint-ignore` / `x-zally-ignore` | Built-in rule suppression | vacuum / Zally | manually | ⚠️ idea for `x-<tool>-ignore` |
| `x-oapi-codegen-extra-tags` | Arbitrary Go struct tags | oapi-codegen, ogen | — | ❌ |

Summary for the registry (R15.5): **read** the standard or widely used ones (`x-enum-varnames`, `x-enumNames`, `x-enum-descriptions`/`x-enumDescriptions`, `x-extensible-enum`, `x-ms-enum`, `x-nullable`, `x-internal`, annotated `oneOf+const`). **Our own** — one namespace `x-<tool>-*` following the example of Speakeasy, Fern and Stainless: `-name`, `-type`, `-type-import`, `-any`, `-unknown-values`, `-error-message`, `-sse`, `-ignore`, `-tristate`. Optional **compatibility aliases** (`x-speakeasy-sse-sentinel`, `x-ms-primary-error-message`) should also be recorded in the registry.

---

## Sources

**Speakeasy**
- Enums: https://www.speakeasy.com/docs/customize/data-model/enums
- Forward compatibility: https://www.speakeasy.com/docs/sdks/manage/forward-compatibility
- Changelog v1.661.0: https://www.speakeasy.com/changelog/release/v1.661.0 · v1.663.0: https://www.speakeasy.com/changelog/release/v1.663.0
- SSE: https://www.speakeasy.com/docs/customize/runtime/server-sent-events
- Errors: https://www.speakeasy.com/docs/customize/responses/errors
- Retries: https://www.speakeasy.com/docs/customize/runtime/retries
- Methods (name-override, ignore): https://www.speakeasy.com/docs/customize/methods
- Linting: https://www.speakeasy.com/docs/sdks/prep-openapi/linting
- Extensions: https://www.speakeasy.com/docs/speakeasy-reference/extensions
- Overlay CLI: https://www.speakeasy.com/docs/speakeasy-reference/cli/overlay
- Overlay apply (code): https://github.com/speakeasy-api/openapi/blob/main/overlay/apply.go
- Versioning / changelogs / breaking: https://www.speakeasy.com/docs/sdks/manage/versioning · https://www.speakeasy.com/docs/sdks/manage/sdk-changelogs · https://www.speakeasy.com/docs/sdks/manage/breaking-changes

**Stainless**
- Config reference: https://www.stainless.com/docs/reference/config/
- Diagnostics: https://www.stainless.com/docs/reference/diagnostics/
- Streaming: https://www.stainless.com/docs/sdks/configure/streaming/
- Transforms: https://www.stainless.com/docs/openapi/transforms/
- Breaking change detection: https://www.stainless.com/docs/enterprise/breaking-change-detection/
- LSP: https://www.stainless.com/docs/tools/stainless-language-server/
- SDKs generated by Stainless: https://github.com/openai/openai-java · https://github.com/openai/openai-python (`src/openai/_types.py`) · https://github.com/openai/openai-node

**Fern**
- Extensions overview: https://buildwithfern.com/learn/api-definitions/openapi/extensions/overview
- SSE: https://buildwithfern.com/learn/api-definitions/openapi/endpoints/sse
- SSE metadata and reconnection: https://buildwithfern.com/learn/sdks/deep-dives/sse-metadata
- Discriminator context: https://buildwithfern.com/learn/api-definitions/openapi/extensions/discriminator-context
- Overrides: https://buildwithfern.com/learn/api-definitions/openapi/overrides
- Versioning: https://buildwithfern.com/post/automating-semantic-versioning-api-sdks-claude · https://buildwithfern.com/learn/sdks/deep-dives/self-hosted-versioning

**TypeScript generators**
- hey-api parser: https://heyapi.dev/openapi-ts/configuration/parser
- hey-api fetch client: https://heyapi.dev/openapi-ts/clients/fetch
- hey-api example of a generated client: https://github.com/hey-api/openapi-ts/tree/main/examples/openapi-ts-fetch/src/client
- orval input/output/enums: https://github.com/orval-labs/orval/tree/master/docs/content/docs
- openapi-typescript CLI / advanced: https://openapi-ts.dev/cli · https://openapi-ts.dev/advanced
- openapi-fetch middleware: https://openapi-ts.dev/openapi-fetch/middleware-auth

**Kiota**
- Using (filters, lock, validation rules): https://learn.microsoft.com/en-us/openapi/kiota/using
- Errors: https://learn.microsoft.com/en-us/openapi/kiota/errors
- Abstractions (BackingStore, RequestOptions): https://learn.microsoft.com/en-us/openapi/kiota/abstractions
- Models (oneOf, enums, backing store, names): https://learn.microsoft.com/en-us/openapi/kiota/models
- UntypedNode: https://github.com/microsoft/kiota-dotnet/tree/main/src/abstractions/serialization

**Go / Python / Rust / Swift**
- oapi-codegen: https://github.com/oapi-codegen/oapi-codegen · https://github.com/oapi-codegen/oapi-codegen/blob/main/configuration-schema.json · https://github.com/oapi-codegen/nullable
- ogen: https://github.com/ogen-go/ogen · documentation: https://github.com/ogen-go/web/tree/main/docs (types/optional.md, types/sumtype.md, types/any.md, concepts/convenient_errors.md, spec/extensions.md, 02-features.mdx)
- openapi-python-client: https://github.com/openapi-generators/openapi-python-client
- progenitor: https://github.com/oxidecomputer/progenitor (progenitor-client/src/progenitor_client.rs, progenitor-impl/src/lib.rs)
- swift-openapi-generator: SOAR-0007 https://github.com/apple/swift-openapi-generator/blob/main/Sources/swift-openapi-generator/Documentation.docc/Proposals/SOAR-0007.md · Useful patterns https://github.com/apple/swift-openapi-generator/blob/main/Sources/swift-openapi-generator/Documentation.docc/Articles/Useful-OpenAPI-patterns.md

**OpenAPI Generator, AutoRest**
- Normalizer: https://github.com/OpenAPITools/openapi-generator/blob/master/docs/customization.md
- Templating (`x-enum-varnames`, `x-enum-descriptions`): https://github.com/OpenAPITools/openapi-generator/blob/master/docs/templating.md
- dart-dio `enumUnknownDefaultCase`: https://openapi-generator.tech/docs/generators/dart-dio
- java `hideGenerationTimestamp`: https://openapi-generator.tech/docs/generators/java
- AutoRest extensions: https://github.com/Azure/autorest/blob/main/docs/extensions/readme.md

**Tools for specifications**
- oasdiff: https://github.com/oasdiff/oasdiff/tree/main/docs (BREAKING-CHANGES.md, FINGERPRINT.md, SOURCE-LOCATOR.md, NULLABILITY.md)
- Spectral: https://github.com/stoplightio/spectral/blob/develop/docs/guides/4d-overrides.md · https://github.com/stoplightio/spectral/blob/develop/docs/guides/2-cli.md
- Redocly: https://redocly.com/docs/cli/commands/lint · https://redocly.com/docs/cli/configuration/reference/rules · https://redocly.com/docs/cli/decorators
- vacuum: https://quobix.com/vacuum/commands/lint/ · https://quobix.com/vacuum/ignoring/
- Zally: https://github.com/zalando/zally · https://github.com/zalando/zally/blob/main/server/rules.md

**Baseline and ratchet in code linters**
- ESLint suppressions: https://eslint.org/docs/latest/use/suppressions · https://eslint.org/blog/2025/04/introducing-bulk-suppressions/
- PHPStan baseline: https://phpstan.org/user-guide/baseline

**Standards and frameworks**
- OpenAPI 3.2.0: https://spec.openapis.org/oas/v3.2.0.html (§4.14.4, §4.14.6.3, §4.24.6.2, §4.24.6.3, §4.25 `defaultMapping`)
- Overlay: https://spec.openapis.org/overlay/latest.html · https://spec.openapis.org/overlay/
- FastAPI: https://github.com/fastapi/fastapi/blob/master/fastapi/openapi/utils.py · https://fastapi.tiangolo.com/reference/sse/

**Dart**
- dart_apitool: https://pub.dev/packages/dart_apitool
- Exhaustiveness checking: https://dart.dev/language/branches#exhaustiveness-checking

---

### What could not be verified

- Whether hey-api supports `x-enum-varnames` / `x-enumNames`: the code search hit the GitHub rate limit, so hey-api was not added to the table.
- Whether `@nestjs/swagger` generates `x-enumNames` automatically: no confirmation found.
- Which Dart library implements RFC 9535 JSONPath and how completely: not verified.
- Support of `extension type` in json_serializable (for option (b) in R8): not verified.
- The description of ogen ("the discriminator is inferred automatically") does not say explicitly what happens on ambiguity: a generation error or something else.
