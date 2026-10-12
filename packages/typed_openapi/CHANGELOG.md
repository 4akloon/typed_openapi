## 0.0.1 - Unreleased

### Added
- Models (M8): `generate` writes the models of every client without check
  errors into its `output` directory: a file per model, enum and union in
  `models/` and the barrel `models.dart`, all starting with
  `// dart format off` and clean under `package:lints/recommended` and
  `flutter_lints`. Models are `final` and `@immutable`, with `fromJson`,
  `toJson`, deep `==`/`hashCode` and `toString`; a `const` property is a
  constant getter, `additionalProperties` a map field, constraints, defaults
  and descriptions doc comments, `deprecated` `@Deprecated`. Enums are open
  (`Status`, `StatusKnown`, `StatusUnknown`); request models take only known
  values. Unions wrap their variants (`PetCat(Cat value)`) and pick one by
  the discriminator, by the JSON type, or, with `union: structural` (config
  key or schema override), by trying them; a union whose variants cannot be
  told apart is `JsonValue` (TOA453). The output directory is owned by the
  generator: files it did not write are deleted, a directory that holds a
  package, an input or foreign files is refused (TOA830), and
  `.typed_openapi.json` lists the generator, a hash of the inputs and the
  files.
- A schema with a discriminator that other schemas extend with `allOf` is
  a union of their models where it is used as a type. A union without a
  discriminator dispatches the variants whose JSON type is their own and
  keeps the rest in one `JsonValue` variant (`PetJson`, TOA453). A wrapper
  writes back the discriminator value it was decoded with, so aliases
  survive a round trip. `toString` does not print `writeOnly` and
  `format: password` fields.
- A `oneOf` or `anyOf` without a discriminator drops an inline enum or
  `const` of a primitive type (string, integer, number, boolean) when
  another inline branch is that type with no constraint, as in Stripe's
  `anyOf: [string, {enum: ['']}]` (TOA455, info); a union left with one
  branch is that branch's type (`String`) and no longer `JsonValue`
  (TOA453). An integer enum is also covered by a plain `number`.
- Semantic IR (M6): `check` builds each client's IR (`IrBuilder`,
  `ClientIr`) from the normalized spec and reports naming and mapping
  problems. Types follow R6.2 (`integer` -> `int`, `number` -> `num` or
  `double` with `float`/`double`, `date-time` -> `DateTime`, `date` ->
  `Date`, `byte` -> `Uint8List`, a schema without constraints -> `JsonValue`,
  `additionalProperties` -> `Map<String, T>`); custom types come from
  `types.formats`, `types.schemas` and the overrides' `dartType`. Fields
  follow the required x nullable matrix; optional nullable properties of
  PATCH bodies are `Patch<T>?` (`tri_state: patch|optional|extension`,
  `x-typed-tri-state`, override `triState`). A schema with `readOnly` or
  `writeOnly` properties used in requests and responses becomes `Pet` and
  `PetInput` (`naming.input_suffix`); a PATCH body schema that is also used
  elsewhere gets its own model `PetPatch` (`naming.patch_suffix`) with the
  tri-state fields. `allOf` parts merge into one model,
  one `$ref` stays a reference (also nullable, and also with parts that only
  annotate: `allOf: [{$ref: Pet}, {nullable: true, description: ...}]`; the
  annotations go to the field), `oneOf`/`anyOf` with one
  branch besides `null` is that branch, nullable; other `oneOf`/`anyOf` are
  unions with their discriminator mapping resolved. `{data: T}` envelopes of
  success responses are unwrapped. Documented errors give `Never`, one
  schema, or a schema per status (`errors.default_schema` for bodies the
  spec does not document).
- Names (R5): schemas keep their key in UpperCamelCase, inline schemas are
  named `<Parent><Property>` (inline enums with the same values share one),
  bodies `<Method>Request`, `<Method>Response` and `<Method>Error` (with the
  status only when several responses of that kind have a body),
  properties and methods are lowerCamelCase (`naming.operation_prefix`; the
  `nestjs` preset removes `XController_`; without `operationId`,
  `GET /users/{userId}/posts/{postId}` is `getUsersPostsByUserIdAndPostId`),
  operations are grouped by first
  tag into `{Tag}Api` (`naming.group`, `naming.default_group`, `group_by:
  tag|path|single`, override `group`; a spec without any tag gets one
  TOA554, otherwise each untagged operation does). Reserved and `dart:core` names get
  `Model` (types) or `_` (members), collisions `2`, `3`... with TOA550 /
  TOA551 and the override to pin the name; unrepresentable names are TOA552
  (an info for enum values: name them with `x-enum-varnames` in the spec).
  The value name `unknown` is reserved in enums (`unknown_`), as the emitters
  add an `unknown` member. The names of custom types (`types.formats`,
  `types.schemas`, `dartType`) are taken in the library's type scope, so a
  generated type of the same name gets a suffix (TOA551).
- In OpenAPI 3.1 and later the `description`, `default` and `deprecated`
  written beside a `$ref` win over the target's for that field; in 3.0 a
  `$ref` has no siblings and the target's are used.
- Header parameters named `Accept`, `Content-Type` and `Authorization` (any
  case) are not generated: OpenAPI says to ignore them.
- Filters (R4): `include` / `exclude` by `tags`, `operations` and path
  globs, override `exclude` on operations, schemas and properties; only
  schemas the selected operations reach are generated.
- New codes: TOA250 mixed-type-schema, TOA251 recursive-alias, TOA252
  allof-property-conflict, TOA253 allof-part-ignored, TOA254
  excluded-schema-referenced, TOA350 enum-mixed-values, TOA450
  discriminator-value-missing, TOA451 discriminator-mapping-not-variant,
  TOA550 name-reserved, TOA551 name-collision, TOA552 name-unrepresentable,
  TOA553 operation-multiple-tags, TOA554 operation-untagged, TOA555
  tags-merged, TOA556 path-variable-unbound, TOA557 filter-matches-nothing,
  TOA558 filter-conflict.
- More M6 codes, with their default level:
  - TOA255 oneof-constraints-ignored (info): `oneOf`/`anyOf` branches that
    only add constraints to an object with `properties` are ignored.
  - TOA256 composition-parts-ignored (warning): `allOf` parts or properties
    beside a union, or the union's branches beside a model, are ignored.
  - TOA351 enum-varnames-invalid (warning): `x-enum-varnames` or
    `x-enum-descriptions` is not a list of strings as long as the enum; it is
    ignored.
  - TOA452 inheritance-polymorphism-deferred (info): a discriminator on an
    `allOf` base is not used to decode the subtypes yet.
  - TOA559 name-lossy (info): a schema, property, enum value, tag,
    `operationId` or parameter name lost letters outside ASCII.
  - TOA560 override-name-invalid (warning): an override `name` or `group` is
    not a valid Dart name; the name made from it is used, or the override is
    ignored when nothing is left.
  - TOA561 media-type-as-bytes (info): a body whose media type is not JSON, a
    form, `multipart/form-data`, `text/*` or `text/event-stream` is bytes
    and its schema is not used; also names the media types of an operation
    that are dropped for the chosen one (variants of the chosen media type
    and other JSON types are not reported).
  - TOA562 default-error-schema-missing (warning): `errors.default_schema` is
    not a key of `components.schemas`; the setting is ignored.
  - TOA563 client-empty (warning): no operation of the client is generated
    (filtered out, written as `$ref`, or an unbound path variable).
  - TOA564 parameter-style-invalid (warning): a parameter `style` that its
    `in` does not allow (path: `simple`, `label`, `matrix`; query: `form`,
    `spaceDelimited`, `pipeDelimited`, `deepObject`; header: `simple`;
    cookie: `form`, `cookie`) falls back to the default style of the placement; an
    `in: querystring` parameter (OpenAPI 3.2) is not generated.
- An `allOf` parent that an override excludes is still merged into the flat
  child: the exclude only removes the parent's own declaration, and TOA254
  (info) says so.
- `naming.default_group` may not be a reserved word and `naming.input_suffix`
  and `naming.patch_suffix` must differ (TOA902).
  `naming.operation_prefix` is removed only from the start of an
  `operationId`, and not when its match is empty.
- Hidden `typed_openapi ir [client...]` prints the IR as JSON for debugging;
  its errors and warnings go to stderr as text, the infos are only counted,
  and its exit code is the one `check` gives. Its format may change in any
  release.
- `typed_openapi check`: reads every client from `typed_openapi.yaml`, loads
  its spec (JSON or YAML) with source positions, detects the OpenAPI version
  and reports diagnostics with stable codes and JSON pointers, as text or JSON.
- Programmatic API: `ConfigLoader`, `SpecLoader`, `OpenApiVersionDetector`,
  `SpecChecker`, `TextReporter`, `JsonReporter`, `TypedOpenApiCli`.
- `check` reads each spec into a typed model that is a superset of OpenAPI
  3.0, 3.1 and 3.2 (`SpecReader`, `SpecModel`) and reports unknown keys
  (TOA110), wrong value types (TOA111) and missing required fields (TOA112).
- `$ref` resolution inside a document and across local files, keyed by file
  URI and JSON pointer: invalid or truncated refs (TOA100), unresolved refs
  (TOA101), remote refs (TOA102), reference loops (TOA103), refs to the wrong
  kind of node (TOA104), ignored `$id`/`$self` (TOA105).
- The dialect is detected by content: 3.1 constructs in a 3.0 document
  (TOA020), `nullable` in 3.1+ (TOA021), 3.2 constructs in older documents
  (TOA022).
- Loading: YAML and JSON are read by `YamlComposer` from the events of a
  copy of package:yaml's parser, in one iterative pass. Nesting deeper than
  1000 levels, also once aliases are expanded, is TOA007; an alias bomb or
  very long keys (JSON pointers of all built nodes above
  `max(16000000, 20 * text length)` characters) are TOA008. A collection as a
  mapping key is TOA113 and is never built, so a key cannot hide an alias
  bomb; a null key is TOA114. Keys are their text (`200:` is `"200"`); keys
  that are one JSON key are TOA002, the last value wins. YAML tags outside
  the JSON Schema ruleset (`!!timestamp`, `!!binary`, `!custom`) are TOA009
  and the value is read as text; parser warnings are TOA015. The copied
  scanner is linear on long flow lines (dart-lang/tools#2657), so hostile
  one-line files are rejected in moments. A directory given as the spec or
  the config is reported as such; package:yaml is no longer a runtime
  dependency (it is used by tests only).
- `$ref` where OpenAPI does not accept a Reference Object (an operation,
  `description`) is TOA107 with a hint to bundle the spec (`redocly bundle`);
  `$ref: #/...` without quotes, which YAML reads as a comment, is TOA108; the
  YAML merge key `<<` is TOA109.
- Normalizer: `check` runs named rules over the model and applies the fixes
  that follow from the spec or the protocol, reading the spec again (at most
  3 passes; a fix that cannot be applied is TOA800). Fixes:
  `bool-required-to-array` (TOA201), `drop-invalid-default` (TOA211),
  `dedupe-enum-values` (TOA301), `declare-missing-path-params` (TOA501).
  Diagnostics: arrays without `items` in 3.0 (TOA202), double arrays (TOA203),
  `format` on an array (TOA204), binary objects (TOA205), `type: object`
  against non-object branches (TOA206), examples of the wrong type (TOA207),
  nullable enums through `oneOf` (TOA303), discriminator property not
  required (TOA401), unresolved discriminator mapping (TOA402), path
  parameters not in the template (TOA502), missing and duplicate
  `operationId` (TOA503, TOA504), `*/*` media types (TOA601), component keys
  with invalid characters (TOA106), and an example of another scalar type
  (TOA208, info). Presets add framework recipes to the hints;
  `rules: {<name>: false}` in `defaults` or a client turns a rule off. The
  rule names are `array-without-items`, `binary-object`,
  `bool-required-to-array`, `component-key-characters`,
  `contradictory-object-type`, `declare-missing-path-params`,
  `dedupe-enum-values`, `discriminator-mapping-target`,
  `discriminator-property-required`, `double-array`,
  `drop-invalid-default`, `duplicate-operation-id`,
  `example-type-mismatch`, `format-on-array`, `missing-operation-id`,
  `nullable-enum-one-of`, `path-param-not-in-template` and
  `wildcard-media-type`. An unknown name is TOA903 (the message lists the
  known ones); a `rules` value that is not a map, or a rule set to anything
  but `true` or `false`, is TOA902.
- Programmatic API: `Normalizer`, `NormalizedSpec`, `NormalizerRule`,
  `RuleContext`, `Finding`, `SpecEdit`, `EditOperation`, `SpecDocuments`.
- A region of a spec that several `$ref`s, enclosing nodes or clients reach is
  read once, and an identical diagnostic is reported once.
- Overrides: `clients.<name>.overrides` names a JSON or YAML file that
  addresses operations (`operationId` or `METHOD /path`), their parameters
  (`name` or `in:name`), request body and responses, and schemas of
  `components.schemas` with their properties. Spec fields (`type`,
  `format`, `nullable`, `required`, `items`, `additionalProperties`, `enum`,
  `discriminator`, `$ref`, parameter `required`/`schema`, body and response
  `contentType`/`schema`) replace the spec's values before the normalizer
  runs (`null` removes a field; `nullable` follows the document's dialect:
  from 3.1 a schema whose `anyOf` or `oneOf` has a null branch and one or
  more other branches, with or without siblings, is nullable, and
  `nullable: false` removes the null branch (one branch left is unwrapped)
  and keeps the siblings; a `nullable` override
  without `$ref` keeps the other keys of a `$ref` node; `type: null` on a
  nullable 3.1 schema drops its nullability, TOA809 info; in OpenAPI 3.0 a
  field other than `nullable` (and a property's `required`) that would sit
  beside a `$ref` is not written, TOA800: override the referenced schema by
  name). Generation fields (`name`, `exclude`, `group`, `exhaustive`,
  `dartType`, `triState`) are checked and kept for the generator. Every
  entry may have a `reason`, printed in diagnostics about it. An empty file
  is no overrides. A missing overrides file is TOA801, a directory or an
  invalid value TOA802, an unknown key the error TOA803 (with "did you
  mean" for a close known key), an override whose target is gone TOA804
  (warning), an ambiguous address TOA805, two overrides of one node TOA806,
  an override the spec already matches TOA807 (info, "can be removed"), and
  a change through an operation of a node other operations share TOA808
  (info). An overrides file that cannot be used is an error and the spec is
  checked without it.
- The fixes of `double-array`, `format-on-array`, `binary-object`,
  `contradictory-object-type` and `nullable-enum-one-of` end with the
  override to copy into the overrides file, when the schema is in
  `components.schemas` or is one of its properties (`format-on-array` only
  for a format whose element type is known; none for a schema with `$ref` in
  OpenAPI 3.0 or a value YAML cannot carry).
- Programmatic API: `OverrideLoader`, `OverrideSet`, `OverrideEntry`,
  `OperationOverride`, `ParameterOverride`, `BodyOverride`,
  `ResponseOverride`, `SchemaOverride`, `PropertyOverride`,
  `DartTypeOverride`; `Normalizer.normalize` takes `overrides:` and
  `NormalizedSpec.overrides` is the set, or null without an overrides file.
- Paths in reports are relative to the working directory, in every format
  and for every file (the config, specs, files reached through `$ref`,
  overrides and baseline files); a file outside it is named by its absolute
  path (`DisplayPaths`). `TypedOpenApiCli(workingDirectory:)` sets the
  directory for tests and tools.
- Levels in the config: `severity: {<code or name>: error|warning|info|off}`
  in `defaults` and per client (a client overrides `defaults` code by code)
  changes the report and the exit code. An unknown code is TOA903; a bad
  level and a code named twice are TOA902. The config codes (TOA901-TOA904)
  cannot be changed at all. The codes of `DiagnosticCode.fixedCodes` (a spec,
  overrides or baseline file cannot be read: TOA001, TOA003, TOA004,
  TOA006-TOA008, TOA010, TOA011, TOA801-TOA803, TOA820, TOA821, TOA823) can
  be raised but not lowered or turned off, which is TOA902. Any other code
  may be raised, lowered or turned off.
- Baseline (R2.3): `clients.<name>.baseline` names a YAML file written by
  `typed_openapi baseline create [client...]` from the client's errors and
  warnings (infos are always shown); `check` then hides the diagnostics it
  accepts and counts them (`baselined: N`), lists them marked
  with `--show-baselined`, and reports an entry that matches nothing (or
  fewer diagnostics than its `count`) as TOA822 (warning, an error with
  `--strict-baseline`) with a hint to run `typed_openapi baseline prune`;
  `--strict-baseline` applies after the configured levels, so TOA822 is an
  error even if the config lowered it.
  Entries are keyed by a fingerprint: the first 12 hex digits of SHA-256 of
  `[code, anchor, args]`, where the anchor is the logical address of the
  place (operation `METHOD /path`, `in:name` parameter, components schema,
  property) or the file (relative to the baseline file) and JSON pointer;
  message text and positions are not part of it. A missing baseline file
  is TOA820, an unreadable one or a bad entry TOA821, a file that cannot be
  written TOA823; two clients naming one baseline file is TOA902. The
  file starts with `version: 1` (it must be the integer 1) and its entries
  are sorted. `baseline create` and `baseline prune` write it atomically
  (a temporary file, then a rename), and skip a client whose spec, or a
  file it is read with (a `$ref` to a file that does not exist is TOA004),
  cannot be read: its baseline is left as it is, the error is printed and
  the exit code is `1`. `baseline prune` also keeps a baseline that has an
  entry it rejected (TOA821), and neither command writes a baseline file
  that two clients share. `check` reports no stale entries for a client
  whose spec cannot be read either.
- Report formats `sarif` (SARIF 2.1.0: rules, levels, relative URIs,
  logical locations, `relatedLocations`, baselined results as suppressed)
  and `github-actions` (workflow-command annotations).
- A problem an override introduces has a related location: the override
  field (text `related:`, JSON `related`, SARIF `relatedLocations`).
- Preset hints are kept apart (`Diagnostic.hints`): a finding two clients
  share keeps the hints of both presets instead of the first one's; with
  more than one, each starts with its preset's name (`nestjs: ...`).
- `Diagnostic.args` (part of the fingerprint): the field name of TOA112.
