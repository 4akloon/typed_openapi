# CLAUDE.md

Guidance for working in this repository.

## Project

`typed_openapi` generates Dart clients from OpenAPI 3.x specs, aimed at
imperfect, code-first specs (NestJS, FastAPI, Spring, ASP.NET). It is a Dart
pub workspace with seven pure-Dart packages (no Flutter):

- `packages/typed_openapi_core` - the engine (M12b): load, normalize, check,
  the IR, baselines, the API snapshot and the diff. A tool that only checks
  specs (grund's CI) depends on it alone; no emitter, no code output.
- `packages/typed_openapi` - the generator: the emitters, the output writer
  and the CLI (`check`, `generate`, `baseline`, `diff` and, for the team that
  writes a spec, `lint`), on top of the core (it depends on
  `typed_openapi_core`). Never a runtime dependency of user apps. It also
  ships the two JSON Schemas under `schema/`, the guides under `doc/` and the
  `example/`.
- `packages/typed_openapi_client` - the client core, the only package
  generated clients depend on (typed errors, `Result`, `Patch`, JSON decoding
  with paths, encoders, request bodies, SSE, the `ClientTransport` contract).
- `packages/typed_openapi_dio` - `DioTransport`, the transport over the
  user's `Dio` (M11b).
- `packages/typed_openapi_transport_tests` - the transport conformance suite
  and its loopback server. `publish_to: none`.
- `packages/typed_openapi_tool` - repository tools (M11, M13): the
  public-spec corpus and the escaping fuzz, and the docs generated from the
  code (`bin/docs.dart`). `publish_to: none`; nothing depends on it.
- `packages/typed_openapi_test_support` - the fixtures and test helpers the
  core, the generator and the tool share (`TempDir`, `NormalizedFixture`,
  `JsonSchema`, the size-limit measuring code). `publish_to: none`; only dev dependencies use it.

Minimum SDK: Dart 3.10 (`>=3.10.0 <4.0.0`), also for generated code.

The four published packages (core, client, `typed_openapi`, Dio transport)
share one version, `0.3.1`, released by hand with
`docs/release-checklist.md` (the tags and the publish follow the merge); their
CHANGELOGs say `## 0.3.1 - Unreleased` until the release (a section titled
`## <version> - Unreleased` is a version not yet released).

## Commands

```sh
dart pub get                                 # repo root, once and after pubspec edits
dart analyze packages                        # repo root; must print "No issues found!"
cd packages/typed_openapi_core && dart test  # the engine; also in typed_openapi, typed_openapi_client, typed_openapi_dio
cd packages/typed_openapi_client && dart test -p chrome                        # dart2js; also typed_openapi_dio
cd packages/typed_openapi_client && dart test -p chrome --compiler dart2wasm   # dart2wasm; also typed_openapi_dio
cd packages/typed_openapi && dart format lib test bin   # a second run must change 0 files
cd packages/typed_openapi_core && dart format lib test  # the same
cd packages/typed_openapi_client && dart format lib test # the same; also typed_openapi_dio, typed_openapi_transport_tests
cd packages/typed_openapi_test_support && dart format lib # the same
cd packages/<package> && dart pub publish --dry-run # before publishing (the core before the generator, the client before the Dio transport)
cd packages/typed_openapi_tool && dart test
cd packages/typed_openapi_tool && dart format lib test bin # the same
cd packages/typed_openapi_tool && dart run bin/corpus.dart check  # network on first fetch
cd packages/typed_openapi_tool && dart run bin/corpus.dart lint   # lint the corpus, check the framework detection
cd packages/typed_openapi_tool && dart run bin/docs.dart check    # the generated docs are current (exit 1 when stale)
cd packages/typed_openapi_tool && dart run bin/docs.dart generate # rewrites the four generated files
cd packages/typed_openapi && dart run bin/typed_openapi.dart lint <spec>  # a spec checked without a config
cd packages/typed_openapi_tool && dart run bin/corpus.dart update # rewrites corpus.lock
cd packages/typed_openapi_tool && dart run bin/fuzz.dart --seeds 200
cd packages/typed_openapi_tool && dart run bin/corpus.dart semver --base main
```

**Documentation that is generated.** Never edit `packages/typed_openapi/doc/diagnostics.md`,
`doc/extensions.md` or `schema/*.json` by hand: change the doc comment of the
`DiagnosticCode` entry, the `x-` registry or the key catalog and run
`docs.dart generate` (a test and the CI job `docs` fail while a file is stale).
The other guides under `doc/` are written by hand; a test checks their
relative links, and the proofs of `support_matrix.md` and the `Sources` of the
framework recipes.

Git commands run from the repo root. Commit messages are Conventional Commits
(`feat(typed_openapi): ...`, `refactor(...)`, `docs: ...`).

## Architecture (`dart run typed_openapi check`)

Engine folders under `packages/typed_openapi_core/lib/src/`, generator folders
(`emit/`, `generate/`, `cli/`) under `packages/typed_openapi/lib/src/`, one folder per stage:

- `diagnostics/` - `Diagnostic` (with `RelatedLocation`s, preset `hints` as
  `(preset, text)`, fingerprint `args` and `backendFix`, the fix for a reader
  who owns the spec and cannot use an override; `forBackend()` is the
  diagnostic `lint` prints: its fix is `backendFix`, else the plain fix when it
  names no override, `typed_openapi.yaml`, severity, baseline or `rules:`, else
  none, and the hints stay), `DiagnosticCode` (stable `TOAnnn`
  catalog; the config codes TOA901-TOA904 cannot be changed at all, and
  `fixedCodes` - read errors, TOA801-TOA803, TOA820/821/823, TOA830-TOA835 -
  can be raised but not lowered), `Severity` (declared from most to least
  serious; level comparison uses its order), `SeverityLevels` (a client's
  `severity` config), `JsonPointer`, `DiagnosticBag` (baselined diagnostics kept
  apart), `DisplayPaths` (files relative to the working directory, absolute
  outside it, always with `/` separators, also on Windows, where an absolute
  path keeps its drive letter: `C:/work/api.yaml`), `MessageText` (spec text in a message: `quote` writes
  `"`, `\`, controls, bidirectional marks and lone surrogates as escapes
  (a lone surrogate as its code point, `\u{d800}`), as the event
  names of TOA551/TOA559/TOA667/TOA668 are; `neutralise` is what the text
  and GitHub reporters apply to every message, fix and related message, and
  to every pointer and file location they print, so an ESC byte or a
  `::error::` line from a spec never reaches a terminal or a CI log as
  such; the GitHub reporter also escapes `%`, CR and LF as the
  runner expects, and JSON and SARIF keep the text as it is), and the
  reporters (`DiagnosticReporter`, `TextReporter`, `JsonReporter`,
  `SarifReporter` (valid against the SARIF 2.1.0 schema, fetched and
  pinned by hash with `corpus fetch` and not vendored, and against GitHub
  code scanning's required properties, both checked by the tool package:
  rule descriptions and help (the help says whether the level can be
  lowered), a partial fingerprint per result, a region for every physical
  location, line 1 for a file without a position, and `defaultFile`, the
  config `check` passes, for a result without a file; every rule has a
  `helpUri`, `DiagnosticCode.helpUri`, a fixed URL on `main` to its entry in
  `doc/diagnostics.md` (`docsAnchor`, such as `toa001-parse-error`), not
  pinned to a tag; `isLint: true`, which `lint` passes, writes rule help that
  says nothing of the config file),
  `GitHubActionsReporter`, `ReportFormat`). The doc comment of every
  `DiagnosticCode` entry is meaning paragraphs, then `Example:` and `Fix:`
  paragraphs that end with a full stop: `doc/diagnostics.md` is generated
  from them.
- `load/` - `SpecLoader` reads JSON/YAML into a `SpecDocument` (plain tree,
  absolute file URI, source spans by JSON pointer, `valueAt(pointer)`,
  `withRoot`) through `YamlComposer`, which `ConfigLoader` uses too.
  `load/yaml/` is a copy of package:yaml 3.1.4's scanner and parser (MIT,
  see its `LICENSE` and `analysis_options.yaml` for the local changes: linear
  cost on long flow lines, dart-lang/tools#2657; the scanner assert is a
  syntax error; warnings go to a handler, never `print`). `YamlComposer`
  builds the plain tree from the parser's events with an explicit stack, in
  one pass: nesting deeper than 1000 levels (every collection the parser
  opens, keys included, and every collection an alias expands to; the root
  is level 0) is TOA007; a budget of `max(16000000, 20 * text length)`
  characters, each built node (first visit or through an alias) costing its
  JSON pointer length + 1, is TOA008 when spent; both return no document.
  Scalar keys are their text (YAML Failsafe: `200:` is `"200"`); a null key
  is TOA114 (warning), a collection key or an alias of one TOA113 (the entry
  is dropped and never built). Duplicate keys are TOA002, last value wins
  (error when YAML itself sees equal keys outside `.json`). Tags outside the
  JSON Schema ruleset are TOA009 (the value is read as its text); parser
  warnings are TOA015. A syntax error is returned to the caller, which
  reports TOA001 (`.json` falls back to `jsonDecode` without positions).
  `YamlComposer` (with `ComposedYaml`, re-exported from it) only wires one
  run of `YamlComposition` (the event loop, the stack and building nodes) to
  its collaborators: `YamlLimits` (depth and budget, TOA007/TOA008),
  `YamlAnchors` (anchors, span records and alias expansion; `YamlAnchor`),
  `YamlTags` (tags, scalar resolution; `YamlScalarText` is the extension
  type that resolves a scalar's text), `YamlFrame` (the collection being
  built and its keys) and `YamlReporter` (the key diagnostics and the
  generic report). `OpenApiVersionDetector` reads the version.
- `model/` - the immutable typed model, a superset of OAS 3.0/3.1/3.2:
  `SpecNode` (every node has a `SpecLocation` = file URI + pointer, `x-`
  `extensions` and reported `unknownKeys`), `RefOr<T>` = `Ref<T>` | `Inline<T>`,
  `Schema` = `BooleanSchema` | `SchemaObject` (`$ref` is a keyword there),
  `OpenApiDocument` and the other OAS objects, one file per object family
  (`operation.dart` keeps `Operation` and re-exports the others).
- `parse/` - `OpenApiParser` (document, components, fragments for `$ref`
  targets), `OperationParser`, `SchemaParser`, all on `ObjectReader` (typed
  field access; wrong types and non-finite numbers -> TOA111, missing required
  -> TOA112, unknown keys -> TOA110; a `$ref` where OAS accepts no Reference
  Object -> TOA107, `$ref: #/...` emptied by a YAML comment -> TOA108, the
  YAML merge key `<<` -> TOA109). Parsers record nodes, `$ref`s and
  version-specific constructs (`SpecFeature`) in a shared `SpecIndex`, which
  also remembers every location a parser has read (`visited`): a location is
  read once, so a later read (a `$ref` into a region and then one to its
  parent) gets the first node and reports nothing again;
  `DialectChecker` turns the constructs into TOA020-TOA022. `ObjectReader`
  reports `$ref` objects, commented-out `$ref`s and merge keys through
  `BundlerConstructs`; `OperationParser` reads servers through `ServerParser` and the `security` field
  through `SecurityParser` (a field that is not a list is one malformed
  requirement, `SecurityRequirement.isNotList`, with TOA111 kept).
- `paths/` - `RealPaths` compares paths with symbolic links resolved and case
  ignored where the file system ignores it; `ConfigLoader` (TOA904) and the
  generator's `OutputWriter` use it.
- `resolve/` - `RefTarget` reads a `$ref` value (a query, a bad fragment or a
  file name that is not UTF-8 after percent-decoding -> TOA100, a host ->
  TOA102), `SpecDocuments` loads other local files once by
  URI, `RefResolver` follows every `$ref` (parsing each on-demand target once)
  and reports TOA100-TOA105, `SpecModel` answers `resolve`/`resolveSchema`
  and lists `nodes` by location; `SpecReader` runs parse -> resolve ->
  dialect check.
- `normalize/` - `Normalizer` runs up to 3 passes of read (`SpecReader`) ->
  rules -> edits: a `NormalizerRule` reads the model through a
  `RuleContext` and returns `Finding`s (a diagnostic and, for a fix,
  `SpecEdit`s: document URI + pointer + add/replace/remove); `TreeEditor`
  applies edits copy-on-write to the plain trees and the model is read
  again (`Normalizer` runs the passes; `OverrideStage` applies the overrides
  once, `OverrideOrigins` attributes their problems, `RuleEditApplier`
  applies rule edits and reports TOA800, `SpecSources` carries the edited
  files; `rules/` has one rule per file). Parser diagnostics of intermediate passes go to a scratch bag; the
  report has the last pass's, every finding of a rule that fixed something,
  and the last pass's findings. An edit still proposed after 3 passes, or
  whose file cannot be read or whose target is gone, is TOA800. An edit equal
  to an applied one (same location, operation and value) is skipped, and one
  that overlaps an applied edit waits silently for the next pass, where its
  rule proposes it again if it is still needed. Edits overlap when they touch
  the same node or one lies inside the other, and also when one adds or
  removes a list element and the other's pointer passes through that list
  (indexes shift). Rules (`normalize/rules/`, in
  `Normalizer.rules` order) never change the model and never read text;
  presets only add framework recipes (`NormalizerRule.hint`). Config
  `rules: {<name>: false}` in `defaults` or a client turns a rule off
  (unknown names are TOA903). `PresetDetector.detect` (on the plain tree;
  only `SpecLinter` uses it, a config's `preset` is never replaced) finds
  the framework from its marks, as a `PresetDetection` (`preset`, `reason`,
  `isFramework`), and only when no other framework's marks are there (marks
  of two give `generic`, naming both; a value of the wrong type is no
  mark): NestJS (an `operationId` shaped `<Name>Controller_<method>`, or
  `info.contact` the empty object), FastAPI (`components.schemas` has
  `HTTPValidationError` and `ValidationError`), springdoc (`info.title` is
  `OpenAPI definition`, or a server described `Generated server url`),
  ASP.NET (a `ProblemDetails` schema and a `text/json` media type
  somewhere). `RuleContext.finding(backendFix:)` gives the fix without an
  override for a finding that offers one; `backend_fixes_test` scans the
  `finding(` calls of `rules/` and fails when one that mentions an override
  has no `backendFix:`. Rule behaviour worth knowing:
  `bool-required-to-array` leaves a parent whose `required` is not a list
  alone (TOA201 without an edit); TOA401 is not reported when the
  discriminator holder itself requires the property; a TOA402 mapping value
  without `#` or `/` is a component name, also with a dot, when it is a key
  of `components.schemas`, and a remote value says remote refs are not read;
  `SchemaType.integer.accepts` takes whole-number doubles beyond int64.
- `overrides/` - `OverrideLoader` reads a client's overrides file (JSON or
  YAML, through `SpecLoader`) into an immutable `OverrideSet`: operations
  (`operationId` or `METHOD /path`) with parameters (`name` or `in:name`),
  `requestBody` and `responses`, schemas (`components.schemas` keys) with
  their own `properties`. Keys are camelCase. An empty or comment-only file
  and a null section are no overrides (no diagnostic). Each entry splits
  into spec fields (`spec`, a map where `null` removes the field) and typed
  generation fields (`name`, `exclude`, `group`, `exhaustive`, `dartType`,
  `triState`, and `union`, `raw` or `structural`, on a schema or a property)
  that the IR builder reads (M6, M8), and on an operation `sse` (M10).
  `SseOverrideReader` reads `sse` into `SseOverride` (with `SseMethod`;
  both are exported like the other override types): `data` or `events` (a
  `components.schemas` key, which becomes a `$ref`, an inline schema, or
  for an event `null`; both together are TOA802), `unknown` (`keep` |
  `ignore`), `reconnect` and `method` (`stream` | `only` | `none`).
  `SseOverrideApplier` writes `data`, or an object whose properties are
  the events with data, as the `schema` of every `text/event-stream`
  media type of the 2xx responses written in the operation and removes
  their `itemSchema`. A `$ref`'d response is shared and not changed:
  `WrittenStreams` tells the written stream successes from the shared
  ones, `EventStreams.events` reads the first written one, TOA669 names a
  shared response that was left alone, and when the event types then
  differ TOA654 says that the shared response was not overridden (override
  the schema it uses by its component name, or write the response in the
  operation). A `data` the spec already has is TOA807; `events` never is,
  since the object it writes reads as a union and the same schema without
  it as a model. TOA669 names exactly the part that does not apply:
  `data`/`events` with no written event stream (the applier),
  `reconnect`/`method`/`unknown` on an operation with no event stream,
  `unknown` on a stream with no events by name, an event the reader
  dropped (`<<`, left out). `reconnect`, `method` and `unknown` otherwise
  apply to the operation whatever its responses are: `method: none` on a
  stream-only operation leaves it out (`StreamShape.excluded`, no
  diagnostic, as `exclude` does), and `method: only` on an operation that
  also offers bodies drops them and says so (TOA651). `OverrideEvents`
  reads the union of the events from that object in the override's order,
  with one union for every event-stream success; an event name that no
  `event:` line can carry (empty, or with a line break) is left out,
  TOA670. `unknown: ignore` makes the generated `fromEvent` throw
  `SseEventIgnored`, which `SseItemDecoder` drops; its id, like that of a
  block without data, still reaches `SseDisconnected.lastEventId` and so
  the `Last-Event-ID` of a reconnection, as WHATWG keeps it. A missing file
  is TOA801, a directory or a
  bad value TOA802 (the value is ignored), an unknown key the error TOA803
  with "did you mean" for a known key within Levenshtein distance 2.
  `OverrideResolver` maps entries to model nodes (`OverrideTarget`; a
  schema follows its `$ref` chain, a property does not, a parameter is the
  node that defines it): missing node TOA804 (warning), ambiguous address
  TOA805, two entries for one node TOA806 (none of them applies); a
  parameter, body or response override with spec fields whose node lies
  outside its operation (path-level, `$ref`'d, another file) is TOA808
  (info, names the shared node). Two keys of one operation that reach the
  same node through `$ref` (responses 400 and 422 sharing a component
  response) are not an address-level conflict: each gets TOA808, and
  `OverrideApplier` decides at apply time: the same value is applied once,
  one field with different values is TOA806 at both and neither applies,
  different fields both apply (except `contentType` + `schema` on a shared
  response, which conflict by design). `OverrideApplier` turns spec
  fields into `SpecEdit`s with set semantics (a value replaces the spec's
  value, `null` removes it), dialect-aware `nullable` (3.0 `nullable`, 3.1+
  `null` in `type`; a nullable reference is `allOf` + `nullable` in 3.0 and
  `anyOf` with `{type: 'null'}` from 3.1). From 3.1 a schema whose `anyOf`
  or `oneOf` has a null branch (`type: 'null'`, annotations allowed) and
  one or more other branches is nullable, with or without sibling keys
  (`default`, `title`, ...): `nullable: true` on it is TOA807,
  `nullable: false` removes the null branch, unwraps a single remaining
  branch and keeps the siblings except a `default: null`. A `nullable`
  override without `$ref` keeps every other key of a `$ref` node (the
  siblings stay next to the new nullable form); one with `$ref` replaces
  the node. `type: null` on a
  nullable 3.1 schema also drops its nullability (TOA809, info). A field the
  spec already has is TOA807 (info), and two different edits of one node by
  different entries are TOA806. In 3.0 a field other than `nullable` (and a
  property's `required`) that would sit beside a `$ref` is not written
  (TOA800 warning: override the referenced schema by name); 3.1+ writes it.
  A `$ref` that is not a string is no reference here (the parser reports
  it). `Normalizer.normalize(..., overrides:)` applies the edits once
  before its passes, so rules see the overridden spec; `NormalizedSpec`
  carries the `OverrideSet` (null without an overrides file).
  `OverrideSnippet` turns a schema location back into an override address
  and block YAML; rules use it through `RuleContext.withOverride`
  (TOA203-TOA206, TOA303; TOA204 only for a format whose element type is
  known), and `TextReporter` indents the lines of a multi-line fix. No
  snippet is offered when the flagged schema node has `$ref` in 3.0, or when
  a value cannot be written as YAML (non-finite numbers). Structure:
  `OverrideLoader` handles files and delegates to `OverrideDocumentReader`
  (the sections `operations`, `schemas`) with `OperationOverrideReader`,
  `SchemaOverrideReader`, `GenerationFieldReader` (`union`, `dartType`),
  `OverrideFieldReader` (typed access and TOA803) and `KeySuggestion`;
  `OverrideResolver` delegates to `OperationTargetFinder`,
  `SchemaTargetFinder` and `TargetConflicts` (TOA806, TOA808) and reports
  through `OverrideTargetReporter` (the targets are in `override_target.dart`,
  re-exported by the resolver); `DeadOverrides` (`ir/`, called at the end of
  `OperationSelector.select`) reports TOA810 (warning) once for an operation
  entry whose operation `include`/`exclude` dropped (not one with its own
  `exclude`, and one that resolved to nothing is TOA804); `OverrideApplier` delegates to
  `OperationOverrideApplier`, `SchemaOverrideApplier` (with
  `ReferenceOverrideApplier`, `TypeOverrideApplier` and `NullableShape`)
  and `OverrideConflicts`, sharing an `OverrideEditContext` (reporting,
  `set`); `OverrideEdit` is in `override_edit.dart`, re-exported by the
  applier.
- `config/` - `ConfigLoader`, `ProjectConfig`, `ClientConfig`, `Preset`,
  `GenerationConfig` (`naming` (also `stream_suffix`, default `Stream`,
  letters and digits from an uppercase letter or a digit; a method named
  `class_` gets `classStream`),
  `sse.reconnect` (GET event streams reconnect unless a call says no;
  `OperationSettingsReader` reads these and `operation_prefix`, each from
  the last of the `ConfigSources` that has it), `group_by`,
  `include`/`exclude`
  (`OperationFilter`, `FilterPattern`), `types`, `tri_state`, `union`
  (`raw`, the default, or `structural`: how a `oneOf`/`anyOf` without a
  discriminator whose variants share a JSON type is generated, TOA453; an
  override `union` wins), `errors`, `exhaustive` (R14.2, default true;
  false makes the bases of enums, unions, status types and event unions
  `abstract interface`; a schema override `exhaustive` wins; it is in
  `GenerationConfig.key` only when false, so the key of a config without it
  is unchanged); a client's key wins over `defaults`,
  `naming`/`types`/`errors` key by key). `ConfigLoader` reads the file and
  its clients through `ConfigReader` (typed access, `severityAt`),
  `ConfigKeys` (the allowed keys, TOA902; derived from `ConfigCatalog` in
  `schema/`, so the loader and the JSON Schema cannot differ) and
  `GenerationReader` (with `CustomTypesReader`, `NamingSettingsReader`,
  `OperationFilterReader` and `TypeSettingsReader`: `types.number` and
  `exhaustive`). `ConfigSources.resolve` reads a setting from the last of
  the sources (`defaults` first, the client last) whose value the setting's
  `ConfigReading` accepts (`ValidValue`, or `InvalidValue` with the problem
  and, for a bad item, the `child` key): an invalid client value acts as if
  it were absent, so the setting falls back to the value of `defaults`, then
  to the built-in default, and each TOA902 names the value applied ("The
  value from "defaults" (...) is used." or "The default (...) is used.") at
  the rejected value; the unknown keys of an `include`/`exclude` filter are
  reported for the filters up to the applied one.
  A bad value is TOA902 and falls back like that (a `default_group` that is
  a reserved word is one); equal `input_suffix` and `patch_suffix` are the
  exception: both go back to their built-in defaults. `operation_prefix` applies only where its match starts at
  index 0 and is not empty. `GenerationConfig.key` is the run key: custom
  types are sorted, and a client with a filter or an `errors.default_schema`
  is keyed by where the config has it, so TOA557, TOA558, TOA652 and TOA563
  are reported at its own place, not at that of a client with equal
  settings.
- `schema/` (M13) - the catalogs of the two files users write, and their JSON
  Schemas (draft-07). `KeySpec` is one key (name, `KeyType`, description,
  `example`, `defaultValue`, `isRequired`, `invalidExamples`;
  `KeySpec.object` for a section) and the sealed `KeyType` its kind of value
  (`BooleanKey`, `StringKey`, `IntegerKey`, `ChoiceKey`, `ListKey`,
  `ObjectKey`, `MapKey`, `NullableKey`, `OneOfKey`, `FreeObjectKey`,
  `AnyKey`, and `CodeLevelsKey` and `RuleFlagsKey` for `severity` and
  `rules`). `ConfigCatalog` (with `ConfigGenerationKeys` and
  `ConfigNamingKeys`) lists every key of `typed_openapi.yaml`, and
  `OverrideCatalog` (with `OverrideOperationKeys` and `OverrideSchemaKeys`)
  every key of an overrides file. `SchemaWriter` turns a key type into
  schema JSON, `ConfigSchema` and `OverrideSchema` assemble the schemas
  (`toJson`, `toText`, the published `url`; their doc comments list the gaps,
  where the loader rejects more than the schema says). `ConfigKeys` and
  `OverrideKeys` (the keys the loaders allow, TOA902/TOA803) are derived from
  the catalogs, so a reader cannot allow a key the schema lacks. The schema
  tests are under the core (`test/schema/`, with the case tables of
  `test/helpers/key_cases.dart`) and judge each case with both the schema
  (`JsonSchema` of the test support package) and the loader, which must
  agree. The published files are `packages/typed_openapi/schema/*.json`,
  written by `docs.dart`. A new config or overrides key goes into the catalog;
  the allowed keys (`ConfigKeys`), the schema and the schema tests follow
  from it; the code that reads the value is still written by hand, through
  `ConfigSources.resolve`.
- `extensions/` (M13) - `SpecExtension` (`key`, `appliesTo`, `effect`,
  `example`, `diagnostics`) and `SpecExtensions`, the registry of the `x-`
  keys the generator reads (`enumVarnames`, `enumDescriptions`, `triState`;
  `all` is the order the documentation lists them). Code that reads or
  names an extension uses `SpecExtensions.<name>.key`, and
  `spec_extensions_test` fails when another file of `lib/` (outside
  `load/yaml/`) writes an `x-` literal. `doc/extensions.md` is generated from
  the registry.
- `ir/` - the semantic IR (M6): `ir.dart` (`ClientIr`, sealed `Declaration`
  = `ModelDecl` | `EnumDecl` | `UnionDecl`, `FieldIr`, `GroupIr`; it
  exports the node files: `operation_ir.dart` (`OperationIr`),
  `parameter_ir.dart`, `body_kind.dart`, `request_body_ir.dart`,
  `response_ir.dart`, `errors_ir.dart` (sealed `ErrorsIr`),
  `api_ir.dart`, and the event-stream nodes `event_stream_ir.dart`,
  `event_union_ir.dart`, `event_variant_ir.dart`,
  `stream_reconnection.dart`; `operation_ir.dart` imports the node files,
  not `ir.dart`, so no import cycle), `dart_type.dart` (sealed
  `DartType`; `DeclId` = schema
  location + `DeclVariant` (`base`, `input` for the request model of a
  schema split by direction, `patch` for the PATCH body model of a schema
  also used elsewhere); types refer to declarations by id, and
  `CustomType.json` never names one), `names.dart` (`DartNames`: word
  splitting, case, reserved sets and the name check `NameKind`, `isValid`,
  `sanitize`, `dropsLetters`; it exports `name_scope.dart`: `NameScope`
  gives a name, a suffix for
  reserved names and `2`, `3`... for collisions, and keeps the names of the
  API lock (`lock`: a name kept for an identity is given to it when free,
  and never to another identity's normal claim; an override name
  (`isExplicit`) or `reserve` may take it, `NameChange.lockTaken`); the arguments of a method
  and the fields of a parts class, and the methods of a group class
  (`DartNames.methodNames`, which adds `int`, `bool`, `double` and `num`,
  types the class's other methods use), reserve `DartNames.helperFunctions`,
  `jsonEncode` and `base64Encode`, which the generated bodies call without
  a prefix, so `jsonEncode(jsonEncode)` is never written: the argument is
  `jsonEncode_`), `IrContext`/`IrOverrides`
  (generation fields of applied overrides by node location;
  `checkedOverrideName` validates an override name, TOA560, and
  `checkLossyName` reports letters a name lost, TOA559; `defaultErrorSchema`
  is `errors.default_schema` if `components.schemas` has the key, else
  TOA652), `SchemaShapes` (shape questions the mapper and `DirectionIndex`
  share: null-only, enum values, the one schema a wrapper stands for; an
  `allOf` part with no structure, only annotations and `nullable`, is not a
  merge part and is set aside next to the one `$ref`; its static API is
  thin delegates to `SchemaForms`, `SubsumedBranches` and `SecretDetection`),
  `SchemaMapper` (a facade: `typeOf`, `typeOfComponent` and the naming
  calls; the work is done by collaborators that never hold the mapper, only
  `MappingTools` (context, directions, queries, names, notices, the shared
  `MappingState`) and a `TypeRecursion` of its own mapping functions, with
  what a call depends on passed down as an immutable `MappingScope`
  (direction, PATCH target, replacing): `Declarer` creates a declaration once
  and hands it to `EnumMapper`, `ModelMapper` (`AllOfMerger`,
  `FieldNotesReader`) or `UnionMapper` (`VariantCollector`,
  `DiscriminatorReader`, `VariantNames`, `SubtypeFinder`, `JsonKinds`);
  `StructuralMapper`, `CustomSchemas`, `DeclarationNames`, `SchemaQueries`
  and the `*Notices` classes do the rest; types, models, enums, unions, `allOf` merge,
  single-schema collapse, custom types; a field's `description`, `default`,
  `deprecated` come from the property, then its annotation-only `allOf`
  parts, then the schema it refers to (3.0 ignores siblings of a `$ref`);
  declarations are created when first
  reached, so only reachable schemas exist, and named at the end: override
  names, then component keys, then inline names by depth. A declaration is
  its `DeclId`: reaching it again gives the same one, named after the first
  use. An inline enum is a declaration of its own site (a schema property
  or an operation parameter), never merged with an equal enum elsewhere
  (`Declarer`); with a lock the first owner keeps the locked name and the
  other sites get fresh ones. An inline name always resolves to a declaration of the set. A
  schema a custom type replaces declares and reports nothing: its JSON side
  is scalars, lists, maps and `JsonValue`. A structural alias that reaches
  itself with no declaration between is TOA251. An `allOf` parent that an
  override excludes is still merged into the flat child, TOA254 says so;
  `oneOf` branches that only add constraints leave a model, TOA255; parts or
  properties beside a union, or branches beside a model, are lost, TOA256),
  `DirectionIndex` (request/response uses for the readOnly/writeOnly split,
  independent of the order it is asked in), `OperationSelector` (`include`
  is a union of `tags`, `operations` and `paths`, empty means no filter;
  `exclude` wins, TOA558, a pattern that matches nothing is TOA557; `*` is
  one path segment, `**` any number; `operationId` filters match the raw
  id; tags are case-sensitive; overrides' `exclude`), `OperationBuilder`
  (parameters in location order and then spec order, the names overrides give
  claimed first; a body is JSON first, then multipart, form, text, event
  stream; any other media type is bytes (`Uint8List`) without its schema and
  the media types that are dropped are named, TOA651, except variants of the
  chosen type and other JSON types; `MediaTypeName.isJson` (`model/`) is
  the one definition of a JSON media type, `text/json` included, as the
  client core reads it; a form or multipart response is bytes,
  TOA650; a text request body is `String`; the `encoding` of a form or
  multipart body (`EncodingIr`, a key that names no property of the body
  schema (also through `$ref`, `allOf`, `oneOf` and `anyOf`; not when the
  schema has `additionalProperties`) is TOA659 and ignored, a style a query
  does not allow is TOA564, headers TOA656, worded for a form property or a
  part; a media type that is an unresolved `$ref` is
  reported by the resolver and leaves the body without schema, encoding and
  parts); a parameter keeps its schema's `default`
  (`ParameterIr.defaultValue`, documented only) by the rule of a model
  field (`SchemaDefaults`: the schema's own, then the schema it stands for
  through an `allOf` of one part or a nullable `anyOf`/`oneOf`, then the
  `$ref` target; a `default` beside a `$ref` counts from 3.1; one that does
  not fit the `enum` or the `format` (`date`, `date-time`, `uuid`, `int32`)
  of those schemas is TOA660 and not kept: `DefaultMatcher`, which checks
  the RFC 3339 fields of `date` and `date-time` by range, a leap year and a
  leap second (60) included, never through `DateTime.tryParse`, which rolls
  a month 13 over); envelopes; errors, with
  `errors.default_schema` for statuses without a body; the status goes into
  an inline body's name only when several responses of a kind declare one
  (`ResponseStatuses.bodyCounts`: a form, multipart, text or bytes response
  declares none); a required parameter's `default` is not documented; a `responses` key is
  generated only when it is a code 200-299 or 400-599, a range `2XX`, `4XX`
  or `5XX` (either case, kept upper case) or `default`
  (`ResponseStatuses`): any other key is TOA657 and its response is
  skipped (also a key that repeats another in a different case), a 1xx or
  3xx one is TOA658 (info) and skipped, and the name part a status gives
  an inline type goes through `DartNames.pascal`, so no key reaches an
  identifier raw; header parameters
  `Accept`, `Content-Type` and `Authorization` are dropped as OpenAPI says;
  a parameter style its `in` does not allow falls back to the default,
  TOA564, and an `in: querystring` parameter is skipped, TOA565; path
  variables are `PathTemplate.variable` in `model/path_template.dart`, the
  client's `OperationRequest.pathVariable`, which a test keeps equal) and
  `IrBuilder`
  (operations written as a `$ref` are skipped (TOA107); groups by tag, path
  or one class (`GroupNames`; `GroupIr`, in `group_ir.dart`, keeps the
  group's `key`, its identity in the API snapshot), with an override `group` (UpperCamelCase, or a value that
  differs only by case or separators) and TOA553-TOA555; the names of custom
  types are taken in the type scope first, so a declaration named like one
  gets a suffix, TOA551; `ApiNames` names, after the declarations, groups
  and M8 helper types, the root client (`ClientIr.root`: `naming.client`
  or the client name with `Client`, so `SpecChecker` keys a run by the
  client name when `naming.client` is unset; group fields and servers are
  its members), the sealed `StatusTypeIr`s of successes with different
  bodies and of `ErrorsByStatus` (variants by reason phrase, `ApiNames.
  variantOf`; the plural only when the operation's own inline response
  body has the name (`ResponseBodyNames`), any other taker of the name gives
  the suffix, TOA551) and the class of
  multipart parts (`RequestBodyIr.parts`, named after the operation, so a schema `name`
  override is TOA807; TOA655 when the schema is not an
  object; `PartMediaType` makes each part's `encoding.contentType` one
  concrete type, TOA661 (a type is concrete when it is an RFC 9110 media
  type whose quoted strings hold no control character, a tab included:
  the client's `ParsedMediaType` would throw at call time), and an object part
  that is not JSON a `String` the caller supplies, TOA662); `OperationBuilder` keeps security requirements
  (an alternative that names a scheme `components.securitySchemes` does not
  define, or is not an object (`SecurityRequirement.isMalformed`, also
  TOA111; a `security` field that is not a list is one such requirement at
  the field), is TOA568 and left out as a whole when another alternative can be described;
  when none can, all stay with the scheme of kind `SecurityKind.unknown`
  (the client's `SecuritySchemeType.unknown`), so the metadata never says
  less than the spec: no operation reads as open or as optional), skips
  event streams it cannot express (TOA654) and reports
  operation servers (TOA566), callbacks and webhooks (TOA567) and a missing
  2xx (TOA653) through collaborators (`SecurityBuilder`, `PartsBuilder`,
  `BodyEncoding`, `OperationChecks`, `MediaTypePicker`, which picks the media
  type of a body, response or parameter and tells its `BodyKind`); `ApiNames.client` assembles the
  `ClientIr`; `RootNames` names the root client (a client name that loses
  letters is TOA559, one with no letters TOA552 and `ApiClient`, one that
  starts with a digit gets `Api` in front, never `$1`, with TOA559), the group
  fields and the servers with their variables, and reports a member that is renamed (TOA550, TOA551); the
  fields of a multipart parts class and the variables of a server are reported
  like arguments (TOA550, TOA551, TOA552, TOA559); `TypeClaims` claims the library's type names; a
  security scheme that is defined without a usable type has its own TOA568
  text; the responses of an operation are picked (`MediaTypePicker`) and
  checked for an event stream before any type is mapped, so a skipped
  operation declares nothing; the IR types only the API emitter reads are in `api_ir.dart`,
  which `ir.dart` exports; method names (`MethodNames`),
  override names first, then
  `operationId` without the `operation_prefix`, then the path; TOA563 when
  no operation is generated, at the config client if filters left some
  out, else at `#/paths`; then everything above). Event streams (M10):
  `OperationBuilder` builds the parameters and hands an operation to
  `MethodBuilder` (`RequestBodyBuilder`, `ResponseBuilder`, `EventStreams`;
  `SpecOperation` is in `spec_operation.dart`). `EventStreams.shapeOf`
  gives a `StreamShape`: `none` (no stream), `only` (every success with a
  body is only a stream: one method that returns the events), `both` (the
  successes offer a body and a stream: the method of the body and a second
  one for the events), `bodyOnly` (every stream success offers a body, but
  another 2xx has a body and no stream: the method of the body, exactly as
  without the stream, and TOA654 for the stream method only, naming the
  statuses; `sse.method: none` reports nothing and is `none`), `mixed` (some
  successes are only a stream and others offer a body, TOA654, not
  generated) and `excluded` (`sse.method:
  none` on a stream-only operation: not generated, no diagnostic). The
  second method is named with `naming.stream_suffix` by `StreamMethodNames`
  (`chat` and
  `chatStream`; a reserved word keeps its stem, `classStream`), claimed
  after every other method of the group (TOA663; TOA550 when the name is
  one Dart has, TOA551 on a collision).
  The method that returns the body picks its media type as without the
  stream (bytes for `application/octet-stream` or `application/xml`, text,
  JSON: `MediaTypePicker` `chooseEvents: false` never chooses a success's
  event stream for it, `sse.method: none` too). Its `OperationIr.accept`
  lists the base media types of its 2xx bodies (`application/json`,
  `application/vnd.api+json`, `text/plain`, each once), which the emitter
  writes as `accept:` of the `OperationRequest` so the server does not
  answer with the stream; it is null when the stream method is not
  generated. `sse.method: only` drops the bodies with TOA651.
  A method that returns events has `OperationIr.events` (`EventStreamIr`:
  the data type, null for text, the union, and a `StreamReconnection`:
  `off` for a non-GET, with TOA665 only when the config's `sse.reconnect`
  asks for it, `onRequest` for a GET, `on` with the config's or the
  override's `sse.reconnect`); its event-stream successes are `String`
  responses and it has no sealed success type. An event stream on an error
  status is read as text, TOA671.
  `EventData` chooses between the override, `itemSchema` and `schema`;
  `EventDataReader` reads one event's data: a string, also with a
  `contentMediaType` that is not JSON, is text; `contentMediaType` JSON
  with a `contentSchema` is JSON, also when that is a string (the quotes are
  read off); wrappers that add nothing (annotation-only
  `allOf`, nullable `anyOf`, `SchemaUnwrapper`) are taken off; `data` may
  sit in an `allOf` part of the `itemSchema`; anything else is text with
  TOA666, which is not reported on top of the TOA101 of a reference that
  does not resolve. `schema` is the data's JSON, an array its items
  (TOA664), a string of any shape (nullable, a string enum, a `format`
  that stays a string) text, so no enum is declared for it.
  An `itemSchema` whose `oneOf` (or `anyOf`) branches each fix `event` to a
  string `const` (or a one-value `enum`) is an `EventUnionIr` (R12.2),
  read by `EventUnionReader`: a variant (`EventVariantIr`, with the
  `location` of its branch) per event name, `data` by the same rules, none
  without `data` or with a `null` one; a repeated name keeps the first
  branch (TOA667); a name no `event:` line can carry (empty, with a line
  break) is left out (TOA670, `EventNames`); a branch that fixes no name
  (nested `oneOf`, an `allOf` branch) makes the data text with TOA666 at
  that branch. `unknownSensitive` is set when any event's data carries a
  secret. `EventUnionNames` (from `ApiNames`, after the status types)
  names it `<Method>Event`, then `<Union>Unknown`, then `<Union><Event>`
  (the event name goes through `DartNames.eventPascal`, which lowercases the
  all-caps pieces of a name before `pascal`: `USER_CREATED` is
  `UserCreated`; `<Union>Event<n>` without letters or digits, TOA668; `2` on a
  collision, TOA551); TOA668 and TOA559 point at the branch. No
  `SchemaMapper` change: the variants' types come from `typeOf`.
  TOA654 is only an operation (or its event-stream method, in the `both`
  and `bodyOnly` shapes) whose event-stream successes disagree on the event
  type, or successes that mix a stream alone with a body; an operation that
  M9 generated is always generated as M9 did (`StreamSuccesses` counts the
  statuses by how they use the stream). `EventAgreement` decides
  "the same event types" from the spec before any type is mapped: the
  same `itemSchema` or `schema`; the schema at the end of the `$ref`s, one
  location or two written alike in one document by `JsonEquality`
  (which never throws on `.nan` or `.inf`) after `SchemaEssence` took off
  the annotations at every depth and the `null` of a type list (a
  property named `description` stays); else the same schema once the
  wrappers that add nothing are taken off, and for a `schema` the same text
  or scalar type and format (no schema and a plain string are both text).
  `MethodBuilder` asks it before it claims the stream method's name
  (TOA663, TOA551) or maps its events, so a stream that is not generated
  declares nothing, claims no name and reports only TOA654.
  `IrJson` dumps an IR (declarations through `IrDeclarationJson`, types
  through `IrTypeText`, operations through `IrOperationJson`): every field of
  every IR class an emitter reads, except locations (`IrJson.withoutLocations`
  leaves them out all together; the manifest's `inputs` hashes that dump) and
  a response's text and media type; `ir_json_test.dart` reads the fields of
  the IR classes with `dart:mirrors` and fails when one is missing from the
  dump or not exempt with a reason; the
  hidden `typed_openapi ir` command prints it. Naming and mapping codes use
  the second half of each area's hundred: TOA250-TOA256, TOA350-TOA351,
  TOA450-TOA458, TOA550-TOA571, and media types, errors and event streams
  TOA650-TOA671 (TOA654 and TOA663-TOA671 are event streams; TOA561 became
  TOA650 and TOA651, TOA562 TOA652, the querystring half of
  TOA564 TOA565; TOA569-TOA571 are the API lock's names); `generate` has TOA830 (output not owned),
  TOA831 (output not written, or its lock held), TOA832 (an interrupted
  run recovered, or a lock taken over; info), TOA834 (`--locked`: the API
  differs from `typed_openapi.lock`) and TOA835 (`typed_openapi.lock`
  cannot be read or written). TOA552 on an enum value is an info (an override cannot name enum
  values; `x-enum-varnames` in the spec does), and `unknown` is reserved in
  the enum value scope (`unknown_`).
  The name lock (M12, decision 5): `NameLock` (`name_lock.dart`, public)
  holds the names `typed_openapi.lock` keeps, types by
  `NameLock.declarationKey` (the schema's file relative to the spec's
  directory, its pointer, and `@input` or `@patch`) and methods by
  `NameLock.methodKey` (`METHOD /path`, `#stream` for the method that
  returns the events); `IrContext.names` carries it and
  `IrBuilder(bag, names:)` takes it. `LockedNames` locks the scopes before
  any claim: the type scope with the declarations the run has (a kept type
  the run does not declare is TOA571, info, and its name is free), each
  group's method scope with its operations; a claim that keeps a name a
  fresh run would not give is TOA570 (info), and a kept name an override
  name or a custom type took, or that is not a usable name for its kind
  (`DartNames.isValid`, not reserved in the scope: a lock is a file anyone
  edits), is TOA569 (warning) and the identity is named normally. An
  explicit claim (an override `name`) releases the identity's kept name.
  Messages quote strings read from the lock with `MessageText.quote`.
  Models, enums, unions and methods are kept; fields, enum values,
  arguments, group classes and the helper types are not.
- `emit/` - the model emitter (M8), whose only input is the IR (it never
  reads the spec): `DartCode` (string literals: `\`, `'`, `$`, line breaks
  including U+0085, U+2028 and U+2029, controls, bidirectional controls (also
  U+200E, U+200F and U+061C) and
  lone surrogates are escaped; one-line code spans `docSpan`/`jsonSpan`;
  `docLines` for spec text: `[`, `]`, `<`, `>`, `\` and `{@` escaped outside
  code spans, controls dropped, wrapped at the width (a span is never
  broken), fenced blocks kept but for `{@`, which dartdoc expands there
  too;
  `proseLines` for the generator's own sentences, which never breaks a code
  span), `DartWriter` (own layout: indentation, `doc`, `prose`,
  one-line-or-one-item-a-line lists, `&&` chains; `line` asserts that the
  text has no line break), `Imports` (`dart:`, `package:` with sorted `show`
  lists wrapped at the width, relative files), `TypeCodec` (type names,
  known-enum types for request constructors, decoders, encoders,
  `DeepEquality` need, JSON patterns of union variants), `ModelEmitter`
  (with `ModelConstructors`: the constructors and `fromJson`; a model with
  an optional constant keeps the keys of those the decoded JSON lacked in
  a private `_absent` list, which `toJson` leaves out and `==` compares, so
  a decoded value is written back as it came, while a model made in code
  writes every constant, so the two are not equal when a constant was
  absent; the generated `fromJson` needs a client whose
  `JsonReader.constant` returns a bool), `EnumEmitter`, `UnionEmitter` and `ModelLibrary` (`models/<snake>.dart`
  per declaration, names that clash get `2`, `3`...; the barrel
  `models.dart`; the header is `// GENERATED CODE - DO NOT MODIFY BY HAND.`
  then `// dart format off` and
  `// ignore_for_file: deprecated_member_use_from_same_package`). Generated classes are
  `class`, not `final class` (users may extend them); union bases are
  `sealed` (`abstract interface` when not exhaustive: a schema override
  `exhaustive`, else the config's `exhaustive`, which also decides
  `StatusTypeIr.exhaustive` and `EventUnionIr.exhaustive`) and every class is
  `@immutable`. Every spec string is escaped at every site it reaches: a
  literal, a comment or an identifier (names come from the IR only).
  Constants (`FieldIr.constValue`), constraints (`ConstraintsIr`), the name
  of the additional properties field and the helper types
  (`EnumDecl.knownName`/`unknownName`, `UnionVariantIr.name`,
  `UnionDecl.unknownName`, named after the groups) come from `SchemaMapper`.
  `UnionDispatch` is `discriminator` (`DiscriminatorDecoder`; a variant
  whose JSON is not an object, such as GitHub's directory listing array,
  is picked by its JSON type before the property is read; `UnionVariants`
  holds what the union writers share), `jsonType` (by JSON type, `int`
  before `num`; the variants of a JSON type several share are one variant
  of `JsonValue`, `UnionVariantIr.jsonKinds`, with TOA453) or `structural`
  (`union: structural`, tries the variants); a union where every variant
  shares its type is `JsonValue` (TOA453), also when a variant takes any
  JSON, which makes the union structural with TOA453; duplicate variant
  types are dropped (TOA454); two variants selected by one discriminator
  value are TOA456 (the earlier one decodes it). A variant the `mapping`
  does not name is selected by the value its discriminator property is
  fixed to (a `const` or a one-value `enum`, also through a `$ref` or an
  `allOf` part), else by its component name; TOA457 (info) reports a fixed
  value that differs from the name (OpenAI), and a `mapping` entry always
  wins. In a union with a discriminator a variant that is not an object is
  picked by its JSON type before the property is read, `int` before `num`
  whatever the order of the variants; a later variant of the same JSON type
  (a string enum after a string) is never produced, TOA458 (info,
  `UnionMapper._reportShadowed`). A nested union without a
  discriminator counts as holding several JSON types, also when the user
  made it `structural`. In a union without a discriminator an inline enum
  or `const` of a primitive type next to a branch of that type that has all
  its values (`anyOf: [string, {enum: ['']}]`) is dropped (TOA455, info;
  `SchemaShapes.subsumedBranches`, before the dispatch is decided), and a
  union left with one branch is that branch's type. The other branch is
  plain when it has no `format`, `pattern`, `enum`, `const` or keyword the
  rule does not model (`if`, `not`, `dependentSchemas`, ...), may be a
  `$ref`, and its length and range constraints are met by every enum value
  (`multipleOf` on the exact decimal numbers, `Decimal`); from 3.1 the
  keywords next to a `$ref` are the branch's own and held to the same rule
  (`RefFollower.siblings`; 3.0 ignores them). An integer enum is also
  covered by a plain `number`, not the other way round. For `oneOf` the
  collapse accepts a value both branches take, which the spec's `oneOf`
  would reject (the Stripe idiom). The dropped values go to
  `FieldIr.knownValues`, which the field's doc comment lists (`Known
  values: ...`), also through a wrapper of a `$ref` (`allOf`, a nullable
  `anyOf`) and not for a union that stays `JsonValue`.
  A component with a discriminator that other components extend with
  `allOf` (directly or deeper; the `components.schemas` of the root
  document, and the root and `components.schemas` of every other file the
  spec reads, so a file nothing refers to is not searched) is, where it is
  used as a type, a union of their models (`_subtypes`; a mapping to the base
  itself is TOA451 and decodes
  as unknown; a discriminator on a schema nothing extends is TOA452 and the
  schema stays a model); a subtype that is only `allOf: [$ref: Base]` stays
  a model. A wrapper whose variant has no discriminator property (a model
  without it, or a nested union that does not dispatch by the same
  property) keeps the value it was decoded with (`discriminator`) and
  writes it, next to an object only when the variant is a union; one made
  in code writes the first mapping value. Wrappers are equal when the
  effective value (the remembered one, else the first mapping value) is, so
  `PetCat(c) == Pet.fromJson(PetCat(c).toJson())`. A variant no value
  selects (TOA450) has no private constructor. `toString` prints
  `<redacted>` for a secret (`FieldIr.sensitive`,
  `ModelDecl.additionalSensitive`, `UnionVariantIr.sensitive`): `writeOnly` or
  `format: password` on the property, its `$ref` target, an annotation-only
  `allOf` part or the one non-null branch of a nullable `anyOf`/`oneOf`
  (Pydantic's `Optional[SecretStr]`), and a secret as array items, map
  values or a branch of a union (`SchemaShapes.annotationSources`,
  `carriesSecret`; the direction split reads the same flags). A value that
  stays raw JSON (`DartType.holdsRawJson`: `JsonValue` or a list, map or
  patch of it) is redacted when `carriesSecret(intoProperties: true)`, which
  also looks into properties and `allOf` parts at any depth (cycle-guarded
  by location), finds a secret in its schema (`SchemaQueries.holdsRawSecret`: a
  field, `additionalProperties`, the shared `JsonValue` variant of a union
  over every branch it keeps); `UnionDecl.unknownSensitive` (a secret
  anywhere in any branch) and a secret variant make the unknown variant
  print `<redacted>`.
- `emit/` for operations (M9): `ApiLibrary` writes the whole client: the
  files of `ModelLibrary`, a file per group in `api/` (snake case of the
  class, its own name scope, so model files never move), the barrel
  `api.dart` and the root `<client>.dart` (`_client` added when that is a
  barrel's name), which exports both barrels and holds the root class
  (`ClientIr.root`: a field per group, servers as `static const` or a
  `static String` method of the URL variables; it never sets a base URL; its
  constructor is `Root(ClientTransport transport, {CallOptions defaults =
  const CallOptions()})` and hands `defaults` to every group, so `RootNames`
  reserves `defaults` and a group named so gets a suffix, TOA551; the files
  import `CallOptions`).
  `OperationEmitter` (with `RequestWriter` for parameters and bodies,
  `DecoderWriter` for the status `switch`, `StatusTypeEmitter` and
  `PartsEmitter` for the types after the class) writes a group: a plain `class` with
  `{Group}(ClientTransport transport, {CallOptions defaults = const CallOptions()})` (a `ClientSender` over it, given the defaults), a private `OperationInfo` (tags, security) and a
  static decoder per operation (private names apart in their own scope),
  methods with named arguments only (`required` for required ones; enum
  arguments take the known values), `body`, then `CallOptions? call`,
  returning `Future<Result<T, E>>` from `ClientSender.send` (a method
  with `OperationIr.events` returns `Stream<SseItem<T>>` from `openEvents`
  through `EventStreamWriter`: `streamStatuses` are its 2xx statuses, a
  range written once as `for (var s = 200; s < 300; s++) s` and not next to
  the codes it holds; the event decoder `(m) => ...` reads `m.json` or
  `m.data` for text, a `reconnection:` argument unless `onRequest`, and its
  decoder has error arms only; the method that returns the body of such an
  operation passes `accept:` to the `OperationRequest`; an event union is
  written after the status types by `EventUnionEmitter`: an `@immutable
  sealed` class whose static `fromEvent(SseMessage)` switches on the event
  name (escaped literals), plain variant classes equal by value with
  `<redacted>` for secrets, and the unknown variant `(event, data)`); the
  decoder switches on the status: codes, then ranges, then `default`
  (every status but 2xx), `_` is `undocumented()`; the request's
  `responseKind` is JSON unless every success with a body is text
  (`text`) or something else is (`bytes`), and then JSON bodies go
  through `RawResponse.parsedJson`; a documented binary error
  (`application/octet-stream`, XML, any media type that is not JSON or
  `text/*`) also makes the operation `bytes`, so its bytes are kept. An error body is decoded by the media
  type of its response, as a success is: `r.bytes` for bytes, `r.text` for
  text (an empty one is `''`), the type's decoder for JSON; errors that
  share one body type but not a media type (`text/plain` and JSON strings)
  get an arm each. In such an operation `UndocumentedStatus.rawBody` is the
  raw bytes, not parsed JSON. `text/json` is JSON everywhere.
  Bodies: JSON (`toJson`), `FormBody` with `FormEncoding`s, the parts class
  (`toParts()`, `FileUpload` for binary strings and lists of them,
  `encoding` media types) or `MultipartBody.fromJson` (TOA655),
  `FileUpload` for binary, `String` for text; a wildcard media type is sent
  as a concrete one. It writes the sealed status types (variants extend the
  base and wrap `body`, equal by value, with a `toString` that prints the
  body, `<redacted>` for a secret body (`ResponseIr.sensitive`, from
  `ResponseSecrets`) and `Uint8List(<length>)` for bytes) and the parts
  classes after the group class. Generated code imports only
  `package:typed_openapi_client`.
  `test/emit/generated_client_test.dart` builds a package of the clients
  of the fixtures (both `union` modes), runs `dart analyze --fatal-infos`
  on it and runs `test/emit/programs/calls.dart.txt` (`bin/calls.dart`
  there), which calls the petstore client through `DioTransport` over a
  fake Dio adapter and prints every request and result (the package has
  `dependency_overrides` for `typed_openapi_client`, a path outside the
  workspace).
- `generate/` - `OutputWriter` (atomic per run: the whole tree and the
  manifest `.typed_openapi.json` (generator, `format` 2, hash of the inputs,
  every file with its hash) are built in a staging directory next to the
  output, made with the umask mode, then given the mode of the old output
  (`chmod`, only when the modes differ, after the files are written, so a
  read-only 0555 output works; the backup of such a directory is made
  writable before it is removed; a missing or failing `chmod` is TOA831),
  then the old directory is renamed to a backup, the staging one to the
  output, and the backup removed; a failure restores the backup, and when
  that fails too TOA831 names the backup that holds the old tree; a failed
  first run leaves nothing; a run that changes nothing does not swap.
  **It replaces only what it wrote** (decision 17): a file of the old
  directory that the manifest does not list, or whose SHA-256 differs from
  the manifest's, or that has no hash in it (a manifest before format 2), is
  a stray, unless it already holds what the run writes; with strays, or
  files and no manifest of this generator (a manifest that parses as JSON
  and names `typed_openapi`), the client is refused with TOA830 that names
  up to 8 files, and `generate --force` (`OutputChanges.forced` counts them)
  replaces them, and each file overwritten or deleted is reported as
  TOA833 (info, `output-file-replaced`) after the swap works. Whatever `force` says, TOA830 also refuses an output that
  holds a `pubspec.yaml`, is a package's `lib`, is or holds a symbolic link,
  is not a directory, or holds an input of the run; I/O errors, also an
  unreadable directory, are TOA831.
  **A lock** `.<output>.typed_openapi.lock` (JSON with pid, host and a
  random id) is created exclusively next to the output, resolved through
  symbolic links and lower-cased on a case-insensitive file system, before
  anything else is read and removed at the end (only if it still holds this
  run's text). A held lock is TOA831 and nothing is touched; a lock of a
  pid on this host that `kill -0` says is gone is taken over (TOA832); a lock whose process cannot be
  told (another host, unreadable, no `kill`, Windows) is held unless
  `--break-lock` (`breakLock`) takes it over (TOA832), which replaces no file;
  the lock of a running process is held whatever the flags, and `--force`
  never touches locks (the TOA831 message says to delete the lock file or
  use `--break-lock`, never `--force`).
  A run killed between the renames leaves `.<output>.typed_openapi-<8
  letters or digits>[-old]` directories. Under the lock, `OutputRecovery.leftovers` skips
  any that holds an input of the run (by location, by symbolic link and by
  file identity), `OutputInspector.inspect` checks the output (or the newest backup, when
  the output is missing) as above, and only then `OutputRecovery.recover` restores that
  backup and removes the other leftovers (a backup only once the output
  holds a manifest), reporting TOA832 (info). `OutputWriter.forTesting`
  (`@visibleForTesting`) takes the test hooks (`beforeInstall`, and `run`
  for `chmod`/`kill`); the public constructor has none.
  `RealPaths` (`paths/real_paths.dart` in the core, exported for this
  package) compares paths with symbolic links resolved and case ignored
  where the file system ignores it (found by a probe; `ConfigLoader` uses it
  for TOA904 too). An input of the run is also found by file identity
  (`FileSystemEntity.identical`) among the files in the output, so a hard
  link or a case-different name never gets an input deleted: this stays as
  the second line of defence. The protected files are those of every client
  in the config, also one that was not selected: the declared input,
  overrides and baseline, the `$ref`'d files of the clients that were
  checked, and the config itself. A client whose output overlaps another's
  (TOA904) is skipped by `generate`. `GenerateCommand` has `--config/-c`, `--force`,
  `--break-lock`, `--locked` and `--fresh-names` (M12). The output lock
  `.<output>.typed_openapi.lock` and the manifest belong to one output
  directory; `typed_openapi.lock` next to the config is the API lock
  (`snapshot/`), a different file. `OutputWriter` (`output_writer.dart`) only orchestrates a
  run, in this order: `OutputParents` (the missing directories above the
  output), `LockAcquirer` (`OutputLock`, `LockHolder`: the lock, its
  take-over), `GeneratedTree` (files, hashes, manifest text),
  `OutputRecovery` (leftovers, the restorable backup, recover),
  `OutputInspector` (`ExistingOutput`, `OutputStray`; the TOA830 checks),
  `OutputInstaller` (staging, mode copy, swap, `beforeInstall`) and
  `TreeRemover`; `OutputManifest` reads, hashes and renders `.typed_openapi.json`,
  `OutputTarget` is the client's output with the run's inputs, and
  `OutputChanges` lives in `output_changes.dart` (re-exported). The `run`
  hook of `forTesting` (`ProcessRunner`: `chmod`, `kill`) is handed to the
  collaborators that start processes.
- `check/` - `SpecChecker`: config -> load -> version -> overrides ->
  `Normalizer` -> `IrBuilder` once per run (file, preset, rules, overrides
  file, `GenerationConfig.key`); an overrides file that cannot be used is
  reported (an error) and the spec is checked without it; `generate` skips
  such a client. Each client then applies its levels
  (`checkClients` -> `ClientCheck`) and its baseline (`check`, which also
  returns the `ClientCheck`s). `SpecChecker` names types and methods as
  `typed_openapi.lock` keeps them (`ApiLockNames`; the `NameLock` is part
  of the run key); an unreadable lock is TOA835 (an error, exit `1`) for `check`,
  `ir`, `baseline` and `diff` too, since every command reads it; `SpecChecker.freshNames` ignores the lock.
  After the IR is built, `OutsideGeneratedApi` (TOA811) lowers to info the
  errors and warnings that lie outside the generated API: the dropped
  operations (`SpecOperations` and `OperationSelector` recomputed on a scratch
  bag) plus the nodes only they use, found by incoming `$ref`s, `discriminator`
  mappings and `allOf` subtypes of a discriminated base (`RefEdges`,
  `OutsideRegion`: candidates reached from the dropped operations lose a
  member while a node outside the region refers to it, to a fixpoint). It
  bypasses `fixedCodes` on purpose; a node nobody places keeps its level.
  `SpecLinter.lint(path, preset:)` (M13) checks one spec file with no config,
  no overrides, no baseline and no IR: it loads, detects the version, runs
  `Normalizer` with the chosen preset or the one `PresetDetector` found, and
  returns a `LintResult` (the diagnostics, each through
  `Diagnostic.forBackend`, the `PresetDetection`, `isChosen`, `isRead`).
  Codes that only the IR stage reports (TOA453, TOA553, TOA651 ...) belong
  to `check`, not to lint.
- `snapshot/` (M12) - the API snapshot of a client (decision 1):
  `ApiSnapshot` (`SnapshotType`s by identity, each with a `TypeKind`,
  `exhaustive`, facts and `SnapshotMember`s), built from the IR only by
  `SnapshotBuilder` (`DeclarationSnapshots`, `OperationSnapshots`,
  `SnapshotIdentities`: a schema is its file relative to the spec's
  directory and pointer, with `@input`/`@patch`; a group `group:<key>`; an
  operation its `operationId` when unique, else `METHOD /path`, with
  `#stream` for the events method). `SnapshotJson` writes and reads the
  lock text (sorted keys, a member per line, `version` 1); `ApiLock`
  reads and writes `typed_openapi.lock` next to the config (`pathFor`,
  TOA835; `SnapshotBuilder.rootOf` makes the spec's directory absolute); `SnapshotNameLock` turns a snapshot into the `NameLock` the IR
  builder keeps (models, enums, unions, methods), `ApiLockNames` reads it
  for a config.
- `diff/` (M12) - `ApiDiff.compare(before, after)` gives `ApiChange`s with
  a `ChangeCategory` (`breaking`, `switchBreaking`, `wire`, `additive`,
  `docs`; decision 2): types removed or added, `MemberChanges` (members
  removed, added, required, typed differently; a new variant, value or
  status of an exhaustive type is `switchBreaking`, of a non-exhaustive
  one `additive`; a type made sealed is `breaking`) and `FactChanges` (the
  rule table of facts: JSON keys, path, method, style, media types and
  statuses are `wire`, docs and `@Deprecated` `docs`). `RenameHints` adds
  the `name:` override that keeps the old Dart name of a removed component
  schema (decision 7). `ChangeCounts` are what `generate` prints and
  `--fail-on` decides by; the reports are `TextDiffReport`,
  `JsonDiffReport` and `MarkdownDiffReport` (spec text neutralised, and
  Markdown escaped in the last).
- `baseline/` - `AnchorIndex` (logical addresses of a spec's nodes:
  operation `METHOD /path`, `in:name` parameter, components schema,
  property), `Fingerprints` (anchor, `sha256([code, anchor, args])[:12]`),
  `Baseline`, `BaselineEntry`, `BaselineMatch` (match, prune, YAML; only
  errors and warnings of codes that are not fixed are accepted) and
  `BaselineLoader` (TOA820, TOA821; `version` must be the integer 1). The
  `baseline` subcommands write a file atomically (temp + rename) and skip a
  client whose spec could not be read (`ClientCheck.readErrors`, which
  includes a `$ref` to a missing file, TOA004: the file is untouched, the
  error printed, exit `1`), keep a baseline with a rejected entry and write
  nothing for clients that share a baseline file; `check` reports no stale
  entries for an unreadable spec. `--strict-baseline` applies after the
  configured levels.
- `cli/` - `TypedOpenApiCli` (`cli.dart`, owns the `CommandRunner` and maps
  usage errors to exit code 64; `workingDirectory` for tests),
  `CheckCommand` (`check_command.dart`, options `--config/-c`, `--format`
  (`text`, `json`, `sarif`, `github-actions`), `--show-baselined`,
  `--strict-baseline`, client names as positional arguments) and
  `BaselineCommand` (`baseline_command.dart`, subcommands `create` and
  `prune`), `GenerateCommand` (`generate_command.dart`: checks like
  `check`, skips a client with errors (`ClientCheck.errors`) or an output
  that overlaps another's, writes the whole client with `ApiLibrary` and
  `OutputWriter`, the inputs hash of `GenerationInputs` (the generator,
  the client's name and `line_width`, the IR without locations; not the
  text of the inputs); text report, then a line per client; exit code as
  `check`; `ClientWriter` writes each client, `ApiLockRun` prints its
  change counts since `typed_openapi.lock` and records its snapshot, or
  with `--locked` refuses a client whose API differs, TOA834, and writes
  no lock), `DiffCommand` (`diff_command.dart`, M12: `--config/-c`,
  `--format` (`text`, `json`, `markdown`), `--fail-on` (`breaking`,
  `switch-breaking`, `wire`, `any`; without it the exit code is `0`),
  `--from` and `--to` (two lock files, no spec read), client names; writes
  nothing) and the hidden `IrCommand` (`ir_command.dart`, prints the IR of
  clients as JSON alone on stdout; the errors and warnings of the run go to
  stderr as text with the count of the infos, a client with no IR is named
  there, and the exit code is the one `check` gives) and `LintCommand`
  (`lint_command.dart`, M13: `typed_openapi lint [options] <spec>`, exactly
  one spec file, no config; options `--preset` (`generic`, `nestjs`,
  `fastapi`, `springdoc`, `aspnet`; else the framework is detected),
  `--format` (as `check`) and `--fail-on` (`error` | `warning`); a note
  `Preset: <name> (...)` says what was used, as the first line of the text
  report and on stderr for `json`, `sarif` and `github-actions` so the
  document stays whole; SARIF is written with `isLint` and the spec as
  `defaultFile`; exit `0` for any findings unless `--fail-on` is reached,
  `1` for a spec that cannot be read or a reached `--fail-on`, `64` for
  usage, as for every command);
  `bin/typed_openapi.dart` only calls `TypedOpenApiCli().run(args)` and sets
  `exitCode`.
- `packages/typed_openapi_core/lib/typed_openapi_core.dart` exports the public
  API of the engine, each with a `show` list: `SpecChecker`, `ClientCheck`, `ConfigLoader`,
  `ClientConfig`, `Preset`, `ProjectConfig`, `GenerationConfig`, `GroupBy`,
  `TriStateRule`, `OperationFilter`, `FilterPattern`, the IR (`IrBuilder`,
  `IrJson`, `ClientIr` and its node classes, among them the M9 ones
  (`RootIr`, `ServerIr`, `ServerVariableIr`, `StatusTypeIr`, `StatusCaseIr`,
  `PartIr`, `EncodingIr`, `SecurityUseIr`, `SecuritySchemeIr`,
  `SecurityKind`) and the M10 ones (`EventStreamIr`, `EventUnionIr`,
  `EventVariantIr`, `StreamReconnection`), `DartType` and its
  subclasses, `DeclId`, `DeclVariant`, `UnionDispatch`, `UnionKind`,
  `UnionVariantIr`), the diagnostics (`Diagnostic`,
  `RelatedLocation`, `DiagnosticBag`, `DiagnosticCode`, `DisplayPaths`,
  `JsonPointer`, `Severity`, `SeverityLevels` and the reporters), the
  baseline (`AnchorIndex`, `Baseline`, `BaselineEntry`, `BaselineMatch`,
  `BaselineLoader`, `Fingerprints`), the loader
  (`SpecLoader`, `SpecDocument`, `OpenApiVersion`, `OpenApiVersionDetector`),
  the whole `model/` (`SpecNode`, `SpecLocation`, `RefOr`, `Ref`, `Inline`,
  `RefKind`, `OpenApiDocument` and the other OAS objects), the entry points
  `SpecReader`, `SpecModel` and `SpecDocuments`, and the normalizer
  (`Normalizer`, `NormalizedSpec`, `NormalizerRule`, `RuleContext`,
  `Finding`, `SpecEdit`, `EditOperation`) and the overrides file
  (`OverrideLoader`, `OverrideSet`, `OverrideEntry` and its subclasses,
  `DartTypeOverride`, `UnionMode`, `SseOverride`, `SseMethod`), and
  `NameLock` (M12: what `IrBuilder(names:)` takes). M12b adds what the
  generator needs and nothing else (decided per symbol, found with
  `dart analyze`, which fails on a `src` import across packages): `ApiLock`,
  `ApiSnapshot`, `SnapshotBuilder`, `SnapshotJson`, `ApiDiff`, `ApiChange`,
  `ChangeCategory`, `ChangeCounts`, `TextDiffReport`, `JsonDiffReport`,
  `MarkdownDiffReport`, `DartNames`, `NameScope`, `MediaTypeName`,
  `PathTemplate`, `JsonKind` (16) and `RealPaths`. M13 adds `SpecLinter`,
  `LintResult`, `PresetDetector`, `PresetDetection`, `SpecExtension`,
  `SpecExtensions`, `ConfigSchema` and `OverrideSchema`; the catalogs
  (`KeySpec`, `KeyType`, `SchemaWriter`, `ConfigCatalog`, `OverrideCatalog`)
  stay inside. Not
  exported: `LockedNames`, the rest of `snapshot/` and `diff/` (the lock's
  format is the file, not a Dart API), the
  internals of `parse/` (`OpenApiParser`, `OperationParser`, `SchemaParser`,
  `ObjectReader`, `ParseContext`, `SpecIndex`, `DialectChecker`), `resolve/`
  (`RefTarget`, `RefResolver`), `normalize/` (`TreeEditor`, the rule
  classes), `overrides/` (`OverrideResolver`, `OverrideApplier`,
  `OverrideSnippet`), `ir/` internals (`IrContext`, `IrOverrides`,
  `SchemaMapper` and its collaborators, `SchemaShapes` and its collaborators,
  `RefFollower`, `Decimal`, `NameHint`, `DirectionIndex`,
  `OperationSelector`, `OperationBuilder`, `SpecOperation`,
  `MediaTypePicker`, `RootNames`, `TypeClaims`, `PartsBuilder`,
  `BodyEncoding`, `SchemaDefaults`, `DefaultMatcher`), `YamlComposer` and `load/yaml/`.
- `packages/typed_openapi/lib/typed_openapi.dart` exports five symbols and
  re-exports nothing from the core: `TypedOpenApiCli`, `ApiLibrary` (M11:
  the fuzz of `packages/typed_openapi_tool` emits whole clients
  in-process), `ModelLibrary`, `OutputWriter` and `OutputChanges`. Not
  exported: `CheckCommand`, `BaselineCommand`, `GenerateCommand`,
  `DiffCommand`, `IrCommand`, `ClientWriter`, `ApiLockRun`, the emitters
  (`DartCode`, `DartWriter`, `Imports`, `TypeCodec`, `ModelEmitter`,
  `ModelConstructors`, `EnumEmitter`, `UnionEmitter`, `DiscriminatorDecoder`,
  `UnionVariants`, and the API emitters (`ApiLibrary` aside),
  `OperationEmitter`, `RequestWriter`, `DecoderWriter`, `PartsEmitter`,
  `StatusTypeEmitter`: `generate` runs them through `ApiLibrary`, the one
  public entry point). Code that needs `SpecChecker`, `ConfigLoader`,
  `DiagnosticBag` or the IR imports `package:typed_openapi_core/typed_openapi_core.dart`.

Data flows loader -> parser -> resolver -> overrides -> normalizer -> IR
builder -> checker, every stage writing problems into one `DiagnosticBag`;
reporters read the bag at the end.

Rules of the pipeline:

- Errors in user input (specs, config) are never thrown; they are reported to
  the `DiagnosticBag` and processing continues where possible.
- Reports are deterministic: diagnostics sort by file, position, pointer, code,
  message (`Diagnostic.compareTo`, `DiagnosticBag.sorted`). `DiagnosticBag`
  ignores a diagnostic equal to one it has (same code, severity, message, file,
  pointer and start position), so a region read twice reports once; only its
  new preset hints are added. Paths are relative to the working directory.
- The CLI never calls `exit()`; commands return the code. Reports go to
  stdout, usage errors to stderr. Codes: `0` ok, `1` errors found, `64` usage,
  `78` the config file could not be loaded (TOA904 and per-client TOA902 exit
  `1`). Diagnostics a baseline accepts do not count.

## Tools (`packages/typed_openapi_tool/`)

The corpus, golden tests and fuzz of M11 (R15.3, R15.4); the tool uses the
public APIs of the core and the generator only. Its network use is the `SpecCache` download
(`corpus fetch`, and `update`/`check`/`lint` for what the cache lacks) and the
`dart pub get` of `PackageGate`; no test touches the network.

- `corpus.yaml` pins each public spec (a URL fixed to a commit, a tag or a
  release; `url` for one file, `archive` + `root` + `entry` for a GitHub
  tarball of several), its SHA-256 (of the file, or `TreeHash` of the kept
  tree), license and expectation (`generate` or `{check-errors: [...]}`).
  Its `schemas:` section pins single files that offline tests read from the
  same cache (the SARIF 2.1.0 schema, `sarif_schema`): they are never kept
  in the repository, so there is no vendored schema or `NOTICE.md`.
  `corpus.lock` is JSON with sorted keys (`version`, `clients`): per
  `<union mode>/<client>` the SHA-256 of every generated file (the manifest
  left out), the hash of the whole output, the diagnostics by code, and the
  round-trip counts (`values`: `examples`, `examples_skipped`, `synthetic`,
  `synthetic_skipped`, `spec_defects`, `failures`). A text that is not JSON,
  or not a lock of version 1 with the right shapes, is a clean error (exit
  `1`), also in `check`, which reads the lock before the long run.
- `lib/src/corpus/` - `CorpusListReader` (`corpus.yaml`), `SpecCache`
  (downloads, verifies, `ArchiveExtractor` with the system `tar`;
  `fetchSchema` for `schemas:`),
  `CorpusRun` (per mode a `CorpusPackage`: `GenerateRun` runs `generate`
  twice through `TypedOpenApiCli` and `SpecChecker` once; the second run
  must write nothing; `PackageGate` runs `dart analyze --fatal-infos` and
  `dart format --set-exit-if-changed`; then a `RoundTrip` per client),
  `CorpusLock`/`ClientLock`, and the commands `fetch` (a name that is
  neither a spec nor a schema is a usage error, exit 64), `update`,
  `check` and `lint`, which `CorpusCli` runs with `semver`. `update` and `check` give
  an unknown name the same usage error; `update` takes no names (a partial
  update would drop the other clients from the lock), and `check` with
  names compares only the clients of those specs (`CorpusLock.only`).
  `tar` runs through `TarRunner` under a 2-minute timeout. `HttpDownload`
  also caps a download at 256 MiB (`maxBytes`): a larger `Content-Length`,
  or a running total past the cap, is a `CorpusException`.
  `update` writes no `corpus.lock` when a gate failed (an expectation that
  does not hold, a client not generated or written by a second run, `pub
  get`, `dart analyze`, `dart format`, a round trip that did not run) and
  says so; `update` and `check` print the first 50 spec defects (examples
  that do not match their schema), then "and N more". `PackageGate` and the
  round-trip program run under a 10-minute timeout; one that does not
  finish is killed, and a round trip that did not run (a crash or the
  timeout) is a gate failure, not a count. `CorpusCli`, `CorpusRun` and
  `FuzzRun` take `fetchesPackages` (default true; no CLI flag): false keeps
  `pub get` offline, as every test sets it.
  A round-trip failure is counted, not fatal by itself: the counts are in
  the lock (`failures` is 0 for every client) and `check` compares them
  like files and diagnostics, so a count that differs from the lock is a
  difference and `check` exits 1, naming the client and the count. A client
  that is skipped (artemis) has no counts, and gaining or losing them is a
  difference too.
  A spec may name its `framework` (a `Preset` name, default `generic`) and
  `detects: false` (only for a spec with a framework: its marks are not the
  ones `PresetDetector` reads, so the corpus expects `generic`;
  `CorpusSpec.expectedPreset`). `CorpusListReader` rejects an unknown
  framework and any other `detects`. `corpus lint [names]`
  (`CorpusLintCommand`, `SpecLintRow`, `CorpusLintReport`) runs `SpecLinter`
  on each spec of the cache (fetching what it lacks), prints a row per spec
  (framework, detected preset, counts of errors, warnings and infos, codes),
  the totals `By framework:` and `Detection: N of M as the corpus expects.`,
  and exits `1` when a detected preset differs from the expected one (or on a
  `CorpusException`); CI runs it in the corpus job after `corpus check`.
  `framework_recipes_test` reads `framework` and `corpus.lock`: every code
  that a framework's spec reports (the `raw/<name>` entry) must be named in
  that framework's recipe.
- `lib/src/docs/` (M13) - the docs generated from the code, run by
  `bin/docs.dart` (`DocsCli`: `generate` writes what differs and prints
  `Wrote <path>`; `check` prints `The generated docs are current.` or names
  the stale files and exits `1`; `--root <packages directory>` defaults to
  `..`; a usage error is `64`; a doc comment that breaks the convention is
  `1`). `GeneratedDocs.files()` gives the four files by path under
  `packages/`: `typed_openapi/doc/diagnostics.md` (`DiagnosticsPage`, with
  `DiagnosticsIntro` and `DiagnosticArea`), `typed_openapi/doc/extensions.md`
  (`ExtensionsPage`, from `SpecExtensions.all`) and the two files
  `typed_openapi/schema/typed_openapi.schema.json` and
  `typed_openapi.overrides.schema.json` (`ConfigSchema.toText`,
  `OverrideSchema.toText`); each Markdown file starts with
  `GeneratedNotice`. `DiagnosticSource` reads the text of the
  `DiagnosticCode` enum (no `analyzer`): the doc comment of each entry is
  meaning paragraphs, then `Example: ...` and `Fix: ...`, each ending with a
  full stop; a missing or incomplete one, an entry the enum lacks or an enum
  entry with no comment is a `DocsProblems` entry, and the page counts its
  codes. Tests (`test/docs/`): `docs_cli_test` fails while a generated file
  of the repository is stale (this is also the CI job `docs`),
  `doc_links_test` checks the relative links and anchors of every `.md`
  under a `doc/` directory and every README under `packages/` (`DocLinks`;
  `CLAUDE.md`, `CONTRIBUTING.md` and `docs/` are outside it),
  `support_matrix_test` (every row of `doc/support_matrix.md` has one of
  four statuses and at least one proof path that exists and is a test, a
  fixture or `corpus.yaml`) and `framework_recipes_test` (each recipe has a
  `## Sources` section with at least three links and the date they were
  read).
- `release/package.sh` (packs a binary and the licence into
  `typed_openapi-<version>-<target>.tar.gz` and writes its `.sha256`; exit 64
  for the wrong arguments), `action/` (the composite action: `action.yml`
  with the inputs `command` (`lint` | `check`), `spec`, `preset`, `fail-on`,
  `config`, `format`, `version`, `executable`, `working-directory`;
  `install.sh` downloads a release archive and checks it against
  `SHA256SUMS`; `run.sh` builds the argument array from the `INPUT_*`
  variables, with `--` before the spec, and refuses an option value that
  starts with a dash; there is no "latest": `version` or `executable` is
  required) and `.github/workflows/release.yml` (tag `typed_openapi-v*`:
  checks the tag against the generator's pubspec, compiles five targets
  (linux-x64, linux-arm64 cross-compiled and not smoke-tested, macos-x64,
  macos-arm64, windows-x64), packs them and creates a GitHub release with
  the archives and `SHA256SUMS`; only the `release` job may write). The
  scripts are tested on Linux by `release_scripts_test` through
  `ReleaseFixture`; `release_readiness_test` pins the pub.dev metadata, an
  example and the CHANGELOG head of each published package, and
  `lockstep_versions_test` the shared version. The macOS, Windows and arm64 builds of
  `release.yml`, and `release.yml` itself, have never run on GitHub (they run
  only on a real `typed_openapi-v*` tag), and the CI jobs added in M13 (`docs`,
  `actionlint`, `binary` and the corpus lint step) have not run there yet.
- `lib/src/roundtrip/` - `ExampleReader` (the `example`/`examples` of each
  declaration's schema and of JSON responses, at the locations the IR
  names; what it cannot read, such as a `null`, a `$ref` to another file, an
  entry without `value` or an `examples` of the wrong type, is counted as
  skipped; an example `jsonEncode` rejects is a spec defect), `SyntheticValues` (from the IR: required fields, all fields,
  first and last enum value, every union variant with its discriminator
  value), `RoundTripProgram` (a Dart program in the corpus package:
  `fromJson`, `toJson`, JSON text, `fromJson`, `==`), `RoundTrip`.
- `lib/src/fuzz/` - `FuzzSpec` (a spec and an overrides file per seed, with
  `FuzzSchemas`, `FuzzOperations`, `FuzzSecurity` (an API key, an OAuth 2
  and an HTTP scheme, each with hostile names, URLs and scopes) and the
  `Hostile` strings), `FuzzBuild` (six clients of one spec, in-process with
  `ApiLibrary`), `SeedBuilds` (runs the two builds of a seed and names the
  build when the generator crashes), `SeedChecks` (the two builds are
  equal, `LeakCheck` finds nothing), `LeakCheck` (no raw control, bidi
  character or lone surrogate in code or in the text report; no
  `injected` call, which the hostile texts write, anywhere in the code of
  a line outside comments and literals: `DartLiterals.masked` blanks them
  out, line breaks kept), `LiteralCheck` (`DartLiterals` finds the literals
  of a sampled output, the VM evaluates them, and every `SpecStrings`
  string of the IR must be among them), `FuzzRun`; `FuzzCli` prints a
  `CorpusException` or file-system error as one line and exits `1`. A work
  directory (`--work`) that is not empty and has no `.typed_openapi_work`
  marker (`CorpusPackage.marker`, written with the package) is refused, so
  a real package is never cleaned.
- `lib/src/semver/` - `SemverRule` and `corpus semver`: when `corpus.lock`
  (once the base has one) or a golden file changed since the base, the
  generator's CHANGELOG needs an entry under `### Output changes` in its
  top section and the version a minor (before 1.0) or major raise, unless
  the CHANGELOG's top section at the base commit is titled `Unreleased` for
  the version in the base pubspec (never published): then the entry is
  enough. Files are read at HEAD and at the base; a dirty working tree does
  not count.
- `test/sarif/` - the SARIF output of `SarifReporter` against the SARIF
  2.1.0 JSON schema (`JsonSchema`, in `typed_openapi_test_support`, a validator for
  the draft-04 and draft-07 subset the SARIF and config schemas use) and against GitHub code scanning's required properties
  (`CodeScanningRules`). The schema is not in the repository: `CachedSchema`
  reads it from the corpus cache (`corpus fetch sarif_schema`), checks its
  SHA-256 against the pin, skips the test when the cache lacks it locally
  and fails it in CI (`CI=true`), so a missing or altered schema never
  passes CI. The rule help differs by code: a fixed code can be raised but
  not lowered, a config code (TOA901-TOA904) cannot be changed.
- CI (`.github/workflows/ci.yml`, every PR and push to `main`, top-level
  `permissions: contents: read`): tests on ubuntu with 3.10.0 and stable, on
  macOS and Windows with stable (format and analyze on ubuntu/stable only);
  the client and the Dio transport (with the conformance suite) in Chrome with
  dart2js and dart2wasm; publish dry-runs of the core, the generator, the
  client and the Dio transport; the corpus job (both SDKs: `corpus check`,
  then `corpus lint`, then `corpus fetch sarif_schema` and the SARIF test);
  200 fuzz seeds; `docs` (`docs.dart check` on stable: the generated
  references and schemas are committed); `actionlint` (the pinned
  `rhysd/actionlint:1.7.12` image over the workflows); `binary` (compiles
  `typed_openapi`, packs it with `release/package.sh linux-x64 0.0.0-ci`,
  and runs the local `./action` with `command: lint` on the
  `backend_defects.yaml` fixture and `executable:`); semver (pull requests
  only, full history). Long jobs have `timeout-minutes`. `nightly.yml`: the
  beta SDK (steps with `if: always()`, a warning only), the corpus on
  Windows, 6000 seeds. `publish.yml` publishes one package on a tag
  `<package>-v<version>` (pub.dev OIDC, environment `pub.dev`); only
  `typed_openapi-v*` also starts `release.yml`.
  `test/ci/workflows_test.dart` pins these layers.

## Client core (`packages/typed_openapi_client/lib/src/`)

The only package generated clients depend on (dependency: `meta`, floor
`^1.15.0` so Flutter's pinned `meta` resolves). It builds every request and
reads every response itself and hands finished bytes to a
`ClientTransport`, so a request is the same on the wire through any
transport. Pure Dart, works on the web (compiled to JS and to Wasm); SSE
needs a transport that streams there, and cookie parameters do not work
(browsers drop the `Cookie` header). Generated code is expected to look
like `test/helpers/pets_api.dart` (illustrative, not a contract);
`test/generated_client_test.dart` checks that the API composes, including an
`implements` fake of a tag class.

- `transport/` - `ClientTransport` (`send(TransportRequest)` completes with
  a `TransportResponse` of any status once its headers arrived; a request
  that gets no response, or a body that fails while it is read, is a
  `TransportException`), `TransportRequest` (method, `target`: the path with
  the encoded query, which the transport resolves against its own base URL,
  `operation` (`OperationInfo`), ordered headers, body stream, `cancel`,
  `extra`, `isEventStream`), `TransportResponse` (status, lower-case
  headers, body stream read once), `TransportException(kind, message,
  {cause, stackTrace})` with `TransportExceptionKind` `timeout`,
  `connection`, `cancelled`, `other`, and `CancelSignal` (a base class: a
  cancelled signal stays cancelled; `whenCancelled`, `reason`).
- `json/` - `JsonReader` (strict reads for generated `fromJson`: the only
  widening is int where a number is expected; `null` is an error only in a
  required non-nullable property, an optional one reads it as absent; RFC
  3339 date-times need an offset, dates are `Date`; a `FormatException` of a
  decoder becomes a `JsonDecodeException` at the property; `checkDepth`
  works without recursion, 1000 levels), `JsonDecodeException` (pointer,
  expected, actual, schema, hint; the first mismatch only, never the value),
  `JsonValue` (extension type over `Object?`, accessors never throw).
- `model/` - `Patch<T>` (`PatchValue`, `PatchNull`; a field is `Patch<T>?`),
  `Date` (`format: date`, no time or zone), `DeepEquality` (deep `==` and
  `hashCode` of lists, maps and patches for generated models). The barrel
  re-exports `immutable` from `package:meta`, so generated code imports only
  the client. `JsonReader` also has `constant` (which says whether an
  optional constant was there), `additional` (the keys a
  model does not list, as an unmodifiable map), `patchValue`, `asBytes` and
  `attempt` for generated code.
- `result/` - sealed `Result<T, E>`: `Success`, `Failure` (`HttpError`,
  `UndocumentedStatus`, `DecodeError`, `TransportError`, `Cancelled`, the
  last two carrying the `TransportException`); no helper methods, pattern
  matching only. `E = Never` still needs `case Failure()`.
- `params/` - `PathParameter`, `QueryParameter`, `HeaderParameter`,
  `CookieParameter` (OAS styles, RFC 6570 expansion, RFC 3986
  percent-encoding; a path expansion that is empty, `.` or `..` throws
  `ArgumentError`, as does a `.`/`..` value); internal `ParameterValue`,
  `PercentEncoder`.
- `request/` - `OperationInfo` (in every `TransportRequest`; `extraKey` is
  where the Dio transport puts it; its `security` lists alternatives of
  `SecurityUse`s of `SecurityScheme`s, metadata only;
  `SecuritySchemeType.unknown` is a scheme the spec names but does not
  define), `OperationRequest` (resolves the path and the query itself;
  `pathVariable` is the one pattern of a path variable, which the generator
  copies; `responseKind` (`ResponseKind` `json`, `text`, `bytes`) says how
  the body is read; `streamStatuses` for event streams; `accept` is the
  `Accept` of the method that returns the body of an operation that also
  has an event-stream method, and a call's own `Accept` wins),
  `RawResponse` (what a generated decoder switches on; `parse` reads JSON
  by the content type, `parsedJson` parses a JSON body of a `text` or
  `bytes` operation), and the bodies `FileUpload` (bytes or a stream),
  `FormBody`/`FormEncoding` and `MultipartBody`/`MultipartPart`, which
  `BodyEncoder` turns into an `EncodedBody` (bytes or a stream, its length
  and `Content-Type`): form text, `multipart/form-data` written by
  `MultipartEncoder` byte for byte as Dio's `FormData` wrote it (the
  boundary from an injectable source; a text part has no `Content-Type`
  while no file or typed part precedes it, later ones are `text/plain;
  charset=utf-8`; a file part without a media type is
  `application/octet-stream`), a file, JSON text or text. With a JSON
  `Content-Type` any value is JSON text (a `String` is quoted, `null` is
  `null`, the JSON `null` of a required nullable body); a `null` body with
  any other `contentType` sends no `Content-Type`, and a generated method
  passes no `contentType` for an absent optional body. A file's own
  `contentType` is checked as a media type (`ParsedMediaType`, the rules
  of `package:http_parser`; `FormatException`). `MediaTypeText` is the one
  definition of a JSON media type (`application/json`, `text/json`,
  `+json`). A value that is not a finite JSON scalar, a list in a list, a
  non-JSON value in a JSON part, or an object with a media type that is
  not JSON is `ArgumentError`, never stringified. Do not write a shift
  past 31 bits or an int literal beyond 2^53 in `lib/`: neither works in
  JavaScript (the boundary range is the literal `4294967296`).
- `client/` - `ClientSender(transport)` (`send`, `openEvents`; never
  retries a request (an event stream reconnects only as R12.5 says)):
  `RequestBuilder` builds the `TransportRequest` (target, `Accept`, the
  operation's headers, the call's, `Last-Event-ID`, `Content-Type` and
  `Content-Length`, nothing else), `ResponseReader` reads the body by
  `ResponseKind` and counts it for `onReceiveProgress` (`ProgressCounter`,
  also for `onSendProgress`), `ClientResults` maps responses and
  `TransportException`s to `Result`s (`Cancelled` for `cancelled`, else
  `TransportError`); decoding catches only `TransportException`,
  `JsonDecodeException` and, from the user's decoder, `FormatException` (a
  converter or `Date.parse` rejecting the data: `DecodeError` at the root
  pointer, `SseDecodeError` in a stream); another `Exception` while a body
  is read is a `TransportError` of kind `other`, and an `Error` is never
  caught. `CallOptions` (`cancel`: `CancelSignal`, `headers`, `extra` for
  the transport, the progress callbacks, `sse`: `SseOptions`).
  `ClientSender(transport, {defaults})` merges the defaults with each call
  once, at the top of `send` and `openEvents` (`CallOptions.merge`: the
  call's value wins; `cancel` and the progress callbacks `call ?? defaults`;
  `extra` a union; `sse` through `SseOptions.merge`), so every later stage
  reads the merged value. The default headers are not merged into the
  call's: the sender merges its defaults without headers
  (`CallOptions.withoutHeaders`) and `RequestBuilder(defaultHeaders:)` layers
  them, lowest to highest, default headers, the operation's (`Accept`, header
  parameters, `Last-Event-ID`), the call's (case-insensitive; a `null` call
  value removes a default; a default `Last-Event-ID` is ignored on a
  stream). A default `cancel` lives as long as the client: every call adds a
  listener to it and, once it fires, every later call is `Cancelled`.
  Every `SseOptions` field is nullable (unset);
  `SseSettings` (internal) applies the built-in values after the merge, and
  `maxAttempts` keeps an explicit `null` as "never give up" apart from an
  omitted argument (a private flag). The opening of an event stream goes
  through `StreamOpening` (`client/`): a failed attempt that `SseRetry`
  (`SseOptions.retryWhen` replaces it) calls transient (`TransportError`
  `connection`/`timeout`, 408, 429, 5xx but 501 and 505; `Cancelled` is never
  classified; `TransportError` `other` is final) is traced, waited for and
  tried again on the call's one `ReconnectionPlan`, which `SseReconnector`
  shares; `retryOpen` unset follows the reconnection policy, `.off` wins
  silently, and a body that cannot be sent twice (`ReplayableBody`) is never
  retried or reconnected. `RetryAfter` (`sse/`, web-safe, with its own
  `HttpDate` in `sse/http_date.dart`, not `dart:io`'s)
  reads delta-seconds or an HTTP date against the response `Date`; the
  delay is `max(Retry-After, backoff)` for that attempt only, not capped by
  `maxDelay` but by `RetryAfter.maxWait` (24 hours).
  `SseTrace.operation` names the stream's `OperationInfo`.
  `EventOpener` opens event streams: `openEvents` needs its stream
  listened to or cancelled; a listener cancel cancels the request. An
  `EventCall` holds what every connection of one call shares, and its
  `ConnectionSignals` give each connection a `CancelSignal` of its own and
  put one listener, not one per reconnection, on the call's signal. A
  `Last-Event-ID` in `call.headers` is where the stream's last event id
  starts (`RequestBuilder.userLastEventId`): it goes with the first request
  and the reconnections until an event id replaces it, and an empty `id:`
  removes it; the stream's id only is sent, never both.
- `sse/` - `SseDecoder` (WHATWG, bytes -> `SseMessage`; it may start from
  a last event id and retry; it keeps the messages of `SseBlockDecoder`,
  which reports every block, one `SseBlock` per empty line with the
  stream's last id and retry, since WHATWG sets the id there also when
  the block has no `data`), `SseItemDecoder` (-> `SseEvent` /
  `SseDecodeError` / `SseDisconnected`; data problems are items, an
  `Error` from the user's decoder is the only stream error; the event
  decoder of a generated union throws `SseEventIgnored` for an event the
  stream drops, `sse.unknown: ignore`: no item, but its id and `retry`
  still move the stream's). `SseDisconnected` is always the last item and
  carries the stream's `lastEventId` (`''` when it had none, from a block
  without data too), its `retry` and `receivedMessage` (whether the
  connection delivered an event, a decode error or a dropped event; comments
  and blocks with only an `id:` or `retry:` are not messages, so such a
  connection is a failed attempt). `SseReconnector` (R12.5):
  `SseReconnecting(attempt, delay, cause)` before each attempt,
  `Last-Event-ID`, the server's `retry` (also above the cap) or 1 s
  doubling to 30 s, 5 attempts in a row without a message (a message resets
  the count: a stream of ignored heartbeats is not given up), all in
  `SseOptions` with an injectable `wait` (the default is a
  `CancellableWait`, a timer a cancel stops, so a cancelled stream does not
  keep the program alive). Opt-in resilience in `SseOptions` (defaults
  unchanged): `idleTimeout` (`IdleTimeout` wraps the connection's bytes; any
  chunk, comments included, resets it; expiry cancels the request and ends
  the body with a `TransportException` of kind `timeout`, so it is the cause
  of `SseReconnecting` or `SseDisconnected`; a paused listener stops the
  timer), `handshakeTimeout` (`Handshake` in `client/`: a timeout of the
  response headers of each attempt, which cancels the request and fails the
  attempt), `maxAttempts: null`, `jitter` + `random` + `cooldown`
  (`ReconnectionPlan` decides every attempt: no jitter while the server's
  `retry` is in effect, never on the cooldown; the cooldown wait is attempt
  `after + 1` and resets the count) and `onTrace` (`SseTrace`, sent by
  `SseTracer`; connect, open, event and heartbeat come from `EventOpener` and
  the decoder hooks `onMessage`/`onComment`, error, reconnecting and closed
  from `TracedItems` over the finished stream; an `Exception` from the
  callback is swallowed). Do not cancel a finished subscription again in a
  stream transformer: under `fakeAsync` that future completes outside the
  fake zone. `SseReconnection` is the operation's policy:
  `off` (a POST that does not enable it; the call cannot), `onRequest`
  (GET), `on`. Cancel, a final error status (the `Failure` is the cause)
  and 204 end the stream (a transient status, `SseRetry`/`retryWhen`, is
  retried); a listener cancel also aborts a request that is in flight
  (`SseReconnector.onCancel`); a pause of the listener, also during a wait
  or a reopen, holds the next connection; an `Exception` thrown by a `wait`
  ends the stream with `SseDisconnected` (an opening then returns the
  failure it was waiting after), and an `Error` thrown on an attempt, by a
  `wait` or the transport, is the stream's one error, never the zone's.
  An event id that is not printable ASCII, space or tab is
  not sent as `Last-Event-ID`, on the web too (a browser would send UTF-8,
  but the VM's `HttpClient` rejects it and every reconnection would fail),
  and the reconnection goes on without it. Use `transformer.bind(stream)`,
  not `stream.transform`: a transport may give a `Stream<Uint8List>`.

Client tests never touch the network: they send through `FakeTransport`
(`test/helpers/fake_transport.dart`), or `GatedTransport` when a test holds
an answer back (`test/helpers/gated_transport.dart`). They also run in
Chrome (the commands above; `CHROME_EXECUTABLE` if Chrome is not found): a
file that needs the VM (`dart:io`, int64 literals, which dart2js rejects)
carries `@TestOn('vm')`, a single test `testOn: 'vm'`.
`test/helpers/test_platform.dart` tells the platform for assertions that
differ.

## Dio transport (`packages/typed_openapi_dio/lib/src/`)

`DioTransport(dio, {isWeb})` sends a `TransportRequest` through the user's
`Dio` (`dio.request` only, never changed, never retried) with
`ResponseType.stream`, so a `Transformer` or `responseDecoder` is not used
and the client reads the bytes. An error status goes through the Dio's
`onError` interceptors and comes back as a response (a `badResponse`
`DioException` that carries a `ResponseBody`). `DioFailures` maps a
`DioException` to a `TransportException` (timeouts `timeout`,
`connectionError` `connection`, `cancel` `cancelled`, else `other`; the
`DioException` is the cause) and does so for one raised while the body is
read; an `Error` (Dio wraps it into an `unknown` `DioException`) is thrown
again. A `CancelSignal` becomes a `CancelToken`; `CallOptions.extra` and the
`OperationInfo` (`OperationInfo.extraKey`) go into `RequestOptions.extra`,
and `DioTransport.operationOf(options)` reads it in an interceptor. The
query is built by the client, so interceptors see an empty
`queryParameters`; `QueryGuard` joins the base URL itself when the query
holds `//`, which Dio would collapse. On the web with Dio's default adapter
an event stream is refused with `webStreamingMessage` (the adapter delivers
the body only when the connection closes). Inside the workspace its
`typed_openapi_client: ^0.3.1` resolves to the package next to it
(`resolution: workspace`); a release that needs a new client publishes the
client first. Tests: `dio_transport_test.dart` (a fake adapter,
`test/helpers/fake_adapter.dart`), `web_test.dart` (`@TestOn('browser')`),
`cookie_browser_test.dart` (the `Cookie` header never reaches a loopback
server from Chrome, `cookie_server.dart`, started by `spawnHybridUri`; its
`hybridMain` is the one top-level function a test helper has, as
`package:test` requires) and `conformance_test.dart`.

## Transport conformance (`packages/typed_openapi_transport_tests/`)

`publish_to: none`. `TransportConformance(create, {createWithTimeout, skips}).register()`
declares the cases every `ClientTransport` must pass, against
`ConformanceServer`, a loopback HTTP server that `server_main.dart`'s
`hybridMain` starts in a hybrid isolate (so a browser test can use it; its
ports arrive as numbers, doubles under dart2wasm). The cases: the method,
target and headers (a header given twice), PUT, PATCH, DELETE and `HEAD`,
JSON, form and streamed bodies, multipart with a fixed boundary and exact
bytes, send and receive progress, the statuses 200, 201, 204, 400, 404, 422,
500 and 503, undocumented statuses, binary bodies, redirects (a 301 and a 302
are followed: the policy is the transport's, the cases document a transport
that follows them), a 4 MiB chunked response, a refused connection, a closed
socket, a timeout (`createWithTimeout:` is optional; without it the case is
skipped), a cancel before a call, in flight and during the body, and event
streams (reconnection with `Last-Event-ID`, split lines and characters,
`retry:`, a 204, an error status, a listener cancel). Not covered: upload
and download progress beyond the counts, request `Transfer-Encoding` and
cookies. A skip names a case and says why (a test checks that every skip
names one). `typed_openapi_dio` skips seven cases in a browser, all the event
stream cases and "a cancel during the body", because Dio's default browser
adapter delivers a body only when the connection closes: the adapter runs
+47 on the VM and +51 ~7 in Chrome with dart2js and dart2wasm.

## Code rules

- **Dart 3.10 features are used actively:** dot shorthands wherever the context
  type is known (`.error`, `severity: .error`, `d.severity == .error`,
  `return .v32;`, `case .v30`), null-aware collection elements (`'k': ?v`),
  switch expressions and patterns, records, class modifiers (`final`, `sealed`,
  `interface`), extension types for zero-cost wrappers. In tests the arguments
  of `expect(...)` have no context type, so write full names there
  (`DiagnosticCode.parseError`). Primary constructors (Dart 3.13) are not used.
- **OOP, no top-level functions.** The only exceptions are `main` in `bin/` and
  in tests. Private helpers are private methods (static when they need no
  state). Constants live in the class they belong to. Components that report
  problems take a `DiagnosticBag` in the constructor (`SpecLoader(bag)`,
  `ConfigLoader(bag)`, `SpecChecker(bag)`).
- Lints come from `analysis_options.yaml` (`public_member_api_docs`,
  `sort_constructors_first`, `prefer_final_locals`, `require_trailing_commas`,
  ...). Every public member has a doc comment. Formatting keeps trailing
  commas. The rule list is grouped by purpose and explained in
  `docs/code-quality-review.md` (section 7); rules waiting for the M9 merge
  are listed at the bottom of the file.
- Tests do not touch the network; temp files only through `TempDir` of
  `typed_openapi_test_support`.

**Packages and tests (M12b).** The fixture specs (`lib/fixtures/`) and the
helpers several packages need (`TempDir`, `NormalizedFixture`, the size-limit
measuring code) live in `typed_openapi_test_support`; `IrFixture`, built on
`NormalizedFixture`, is in the core's `test/helpers/`. A test goes with the
code it tests: engine tests in the core, emitter, writer and CLI tests in the
generator. Each of the core, the generator and the client has its own ratchet
(`test/quality/size_limits_test.dart`, with its own allowlist). `ir_robustness_test`
scans the core's tests only. The four publishable packages carry one version
(lockstep, pinned by a tool test) and publish in the order core, client,
`typed_openapi`, Dio transport.

## Code quality rules (size, decomposition, readability)

Based on Google's code review standard (design, complexity, tests, naming,
comments) and Effective Dart. A reader must understand a unit quickly; if
not, decompose it. Review and sources: `docs/code-quality-review.md`.

**Limits** (all lines count, comments and blanks included: use `wc -l`):

| Unit | Limit | Notes |
| --- | --- | --- |
| File in `lib/` | 300 lines | |
| Test file | 500 lines | split by behaviour, helpers to `test/helpers/` |
| Method / function | 40 lines | Google reviews anything over ~40 |
| Parameters | 5 | past that, take a parameter object |
| Nesting | 3 levels of `if`/`for`/`switch`/`try` | early `continue`/`return`, extract |
| Class | one responsibility, ~15 members | not "and" in its one-line doc |
| Declarations per file | one public class or sealed family | small private helpers may share the file |

Exempt: `load/yaml/` (vendored), and a flat catalog with no logic
(`diagnostic_code.dart`). Nothing else is exempt without a line in the
exemption list of `docs/code-quality-review.md`.

**Before you write**

- Run `wc -l` on the file you are about to extend. If your change would take
  it past the limit, extract first (in its own commit), then add.
- A file already over the limit (the legacy list is in the review) **never
  grows**. When a task touches one, move the unit you are changing into a
  new file/class first, so each touch leaves the file shorter.
- A method over 40 lines: split it by what it does (named steps), not by
  line count. Each part gets a name that says what, not how (`_mergeParts`,
  not `_model2`).

**How to decompose**

- Split by responsibility into collaborator classes (composition), each in
  its own file under the stage folder. `part`/`part of`, mixins used only to
  spread one class across files, and `utils`/`helpers`/`common` files are
  not decomposition.
- A helper class made public to leave a file stays out of
  `lib/typed_openapi.dart` unless it is API: the `show` lists keep the
  surface small.
- No hidden state passed through fields. Do not set a field (`_direction`,
  `_patchTarget`, `_replacing`) before a call and read it deep inside:
  pass a parameter or a small immutable context object, so a method can be
  read and tested alone.
- A refactor changes no behaviour: generated output stays byte-identical
  (compare before and after on the fixtures), tests stay green, and it is a
  separate commit from any feature or fix (`refactor(...)`).
- Do not abstract for a future need (Google: solve the problem you know you
  have now). Three similar lines are better than a premature interface; an
  extension point needs a second user first.

**Readability**

- Names say what the thing is or does; no abbreviations, no `2`/`Impl`/
  `Helper`/`Manager` suffixes. Booleans read as a state (`isLossy`,
  `hasDefault`) in the positive form; no positional `bool` parameters.
- A comment explains why (a spec quirk, a requirement id, a trap), never what
  the next line does; if it needs to say what, rewrite the code. Delete a
  comment that the change made false.
- Prefer a `switch` over a sealed type or a record to a chain of `is`/`if`
  tests; prefer returning a value to mutating an argument or a collection
  passed in.
- No `!` where a pattern or an early return can promote the value; no
  `dynamic`, no `late` without a comment on why it is set before first read.
- Every user-input problem is a diagnostic, never a bare `catch` or a silent
  default (see the design rules below).

**Dart style (Effective Dart; the rules a lint cannot check)**

Naming, ordering, quotes, imports, `new`/`const`, collection and async idioms
are enforced by the lints in `analysis_options.yaml` and `dart format`. These
are not, so follow them by hand:

- Acronyms longer than two letters are words (`Uri`, `Json`, `Sse`, `Ir`);
  never a leading underscore on a non-private name, no Hungarian prefixes, an
  unused callback parameter is `_`.
- Doc comments use `///`, start with a one-sentence summary that is its own
  paragraph, and refer to identifiers in `[brackets]`. A boolean starts with
  "Whether", a non-boolean property is a noun phrase, a method with a side
  effect starts with a third-person verb. Prose describes parameters and
  returns, no `@param` tags. Do not repeat what the signature says. One doc
  comment for a getter/setter pair. The doc comment goes before annotations.
- `/* */` only to comment out code; comments are sentences with a capital
  letter and a full stop.
- No one-member abstract class where a function will do; no nullable
  `Future`, `Stream` or collection return (return an empty one); no
  positional `bool`; no `catch` without `on`, never catch `Error`, and
  `rethrow` keeps the stack trace.
- Never silence a lint: no `// ignore:` or `// ignore_for_file:` without a
  comment on why, and no rule removed from `analysis_options.yaml` to make a
  change pass. Generated files are the exception: each carries
  `// ignore_for_file: deprecated_member_use_from_same_package` in its header,
  because a model whose spec deprecates a member (field, enum value, type)
  uses it in its own
  `fromJson`/`==`/`toString` and the analyzer of Dart 3.10 reports that
  (stable does not). To enable a new lint: stable, available in the minimum SDK,
  zero findings (or fix them in the same change), no conflict with an enabled
  rule (`incompatible` in the lint catalog).

**Tests**

- Tests come in the same commit as the code; a new branch of logic has a test
  that fails without it.
- A test names the behaviour (`'a path expansion of ".." throws'`), builds its
  input in the test or a named helper, and checks one thing. Repeated set-up
  of more than ~5 lines becomes a helper in `test/helpers/`.

**Self-review before saying "done"**

1. `wc -l` of every file touched, and the longest method added: within limits?
2. Could a new reader of the diff say in one sentence what each new class and
   method is for? If not, rename or split.
3. Is there code, a parameter or a flag nothing uses yet? Remove it.
4. `dart analyze packages` clean, tests green, `dart format` changes 0 files,
   and `CLAUDE.md`/`docs/` updated if behaviour or structure changed.

## Design rules (from CONTRIBUTING.md)

- Nothing is guessed silently: every normalizer fix, fallback or skipped
  construct yields a diagnostic with a stable code and a JSON pointer.
- Deterministic output: same spec + same config + same `typed_openapi.lock` ->
  byte-identical code. Sort
  everything; no hash-ordered iteration when emitting; no network or `dart fix`
  during generation.
- A change of generated output is a breaking change of the generator.
- The user's HTTP client is not ours: generated code talks to a
  `ClientTransport` only; `DioTransport` never mutates the Dio instance, and
  HTTP errors go through Dio's `onError` and are typed afterwards.
- No `analyzer` dependency in the generator core; tests run `dart analyze` on
  generated fixtures as a subprocess.
- Escape every string taken from the spec at every interpolation site.
- No `package:yaml` import in `lib/`: the scanner and parser are vendored in
  `lib/src/load/yaml/` (MIT, local edits referencing dart-lang/tools#2657).
  `yaml` is a dev dependency only, for tests that compare `YamlComposer`
  with package:yaml's loader; keep every local edit documented in
  `lib/src/load/yaml/analysis_options.yaml`.

## Where things are

- `docs/requirements.md` - requirements R0-R15 and decisions on open questions.
- `docs/roadmap.md` - milestones M1-M13.
- `docs/release-checklist.md` - how to release the four packages and the
  binaries by hand, the SchemaStore text and the open items nobody could
  verify before the first release.
- `packages/typed_openapi/doc/` - the user guides (`support_matrix.md`,
  `frameworks/`, `automation.md`, `client_for_grund.md`, the generated
  `diagnostics.md` and `extensions.md`, ...) and `schema/`, the generated
  JSON Schemas; the package READMEs and `example/` directories are the
  pub.dev pages.
- `docs/code-quality-review.md` - quality review, the exemption list of files
  over the size limits, and the refactoring order.
- `docs/research/` - competitor research (`README.md` summary, `01`-`07`
  detailed reports).
- `docs/superpowers/HANDOFF.md` - current state and how to continue; read it
  first in a new session. `docs/superpowers/briefs/` - briefs for the next
  plans and the SDD implementer rules.
- `docs/superpowers/plans/` - step-by-step implementation plan per milestone
  (M1: `2026-10-11-m1-check-cli.md`).
- `CONTRIBUTING.md` - setup, conventions, commit rules.

## Language

Everything is in English: documents in `docs/`, `CLAUDE.md`, READMEs, code,
code comments, doc comments, diagnostics messages and commit messages. A new
or edited document is written in English. The only Ukrainian files are the
intentional user-facing `README.ua.md` translations (and a few Unicode test
strings in the M6 and M8 plans).
