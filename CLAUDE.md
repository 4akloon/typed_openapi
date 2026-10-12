# CLAUDE.md

Guidance for working in this repository.

## Project

`typed_openapi` generates Dart clients from OpenAPI 3.x specs, aimed at
imperfect, code-first specs (NestJS, FastAPI, Spring, ASP.NET). It is a Dart
pub workspace with two pure-Dart packages (no Flutter):

- `packages/typed_openapi` - the generator: CLI and programmatic API. Never a
  runtime dependency of user apps.
- `packages/typed_openapi_runtime` - the only package generated clients depend
  on (typed errors, `Result`, `Patch`, JSON decoding with paths, encoders, SSE).

Minimum SDK: Dart 3.10 (`>=3.10.0 <4.0.0`), also for generated code.

## Commands

```sh
dart pub get                                 # repo root, once and after pubspec edits
dart analyze packages                        # repo root; must print "No issues found!"
cd packages/typed_openapi && dart test       # also in typed_openapi_runtime
cd packages/typed_openapi && dart format lib test bin   # a second run must change 0 files
cd packages/typed_openapi_runtime && dart format lib test # the same
cd packages/<package> && dart pub publish --dry-run # before publishing
```

Git commands run from the repo root. Commit messages are Conventional Commits
(`feat(typed_openapi): ...`, `refactor(...)`, `docs: ...`).

## Architecture (`dart run typed_openapi check`)

All under `packages/typed_openapi/lib/src/`, one folder per stage:

- `diagnostics/` - `Diagnostic` (with `RelatedLocation`s, preset `hints` as
  `(preset, text)` and fingerprint `args`), `DiagnosticCode` (stable `TOAnnn`
  catalog; the config codes TOA901-TOA904 cannot be changed at all, and
  `fixedCodes` - read errors, TOA801-TOA803, TOA820/821/823 - can be raised
  but not lowered), `Severity` (declared from most to least serious; level
  comparison uses its order), `SeverityLevels` (a client's `severity`
  config), `JsonPointer`, `DiagnosticBag` (baselined diagnostics kept
  apart), `DisplayPaths` (files relative to the working directory, absolute
  outside it), and the reporters (`DiagnosticReporter`, `TextReporter`,
  `JsonReporter`, `SarifReporter`, `GitHubActionsReporter`, `ReportFormat`).
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
  `OpenApiVersionDetector` reads the version.
- `model/` - the immutable typed model, a superset of OAS 3.0/3.1/3.2:
  `SpecNode` (every node has a `SpecLocation` = file URI + pointer, `x-`
  `extensions` and reported `unknownKeys`), `RefOr<T>` = `Ref<T>` | `Inline<T>`,
  `Schema` = `BooleanSchema` | `SchemaObject` (`$ref` is a keyword there),
  `OpenApiDocument` and the other OAS objects.
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
  `DialectChecker` turns the constructs into TOA020-TOA022.
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
  again. Parser diagnostics of intermediate passes go to a scratch bag; the
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
  (unknown names are TOA903). Rule behaviour worth knowing:
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
  `triState`) that M4 only keeps for the generator (`sse` is not accepted
  until M10 settles its shape). A missing file is TOA801, a directory or a
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
  a value cannot be written as YAML (non-finite numbers).
- `config/` - `ConfigLoader`, `ProjectConfig`, `ClientConfig`, `Preset`.
- `check/` - `SpecChecker`: config -> load -> version -> overrides ->
  `Normalizer` once per run (file, preset, rules, overrides file); an
  overrides file that cannot be used is reported (an error) and the spec is
  checked without it; `generate` (M9) must skip such a client. Each client
  then applies its levels (`checkClients` -> `ClientCheck`) and its baseline
  (`check`).
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
  `prune`); `bin/typed_openapi.dart` only calls `TypedOpenApiCli().run(args)`
  and sets `exitCode`.
- `lib/typed_openapi.dart` exports the public API, each with a `show` list:
  `SpecChecker`, `ClientCheck`, `TypedOpenApiCli`, `ConfigLoader`,
  `ClientConfig`, `Preset`, `ProjectConfig`, the diagnostics (`Diagnostic`,
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
  `DartTypeOverride`). Not exported: `CheckCommand`, `BaselineCommand`, the
  internals of `parse/` (`OpenApiParser`, `OperationParser`, `SchemaParser`,
  `ObjectReader`, `ParseContext`, `SpecIndex`, `DialectChecker`), `resolve/`
  (`RefTarget`, `RefResolver`), `normalize/` (`TreeEditor`, the rule
  classes), `overrides/` (`OverrideResolver`, `OverrideApplier`,
  `OverrideSnippet`), `YamlComposer` and `load/yaml/`.

Data flows loader -> parser -> resolver -> overrides -> normalizer ->
checker, every stage writing problems into one `DiagnosticBag`; reporters
read the bag at the end.

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

## Runtime (`packages/typed_openapi_runtime/lib/src/`)

The only package generated clients depend on (dependencies: `dio`, `meta`).
Pure Dart, works on the web except SSE with Dio's default browser adapter.
Generated code is expected to look like `test/helpers/pets_api.dart`
(illustrative, not a contract); `test/generated_client_test.dart` checks
that the API composes, including an `implements` fake of a tag class.

- `json/` - `JsonReader` (strict reads for generated `fromJson`: the only
  widening is int where a number is expected; `null` is an error only in a
  required non-nullable property, an optional one reads it as absent; RFC
  3339 date-times need an offset, dates are `Date`; a `FormatException` of a
  decoder becomes a `JsonDecodeException` at the property; `checkDepth`
  works without recursion, 1000 levels), `JsonDecodeException` (pointer,
  expected, actual, schema, hint; the first mismatch only, never the value),
  `JsonValue` (extension type over `Object?`, accessors never throw).
- `model/` - `Patch<T>` (`PatchValue`, `PatchNull`; a field is `Patch<T>?`),
  `Date` (`format: date`, no time or zone).
- `result/` - sealed `Result<T, E>`: `Success`, `Failure` (`HttpError`,
  `UndocumentedStatus`, `DecodeError`, `TransportError`, `Cancelled`); no
  helper methods, pattern matching only. `E = Never` still needs
  `case Failure()`.
- `params/` - `PathParameter`, `QueryParameter`, `HeaderParameter`,
  `CookieParameter` (OAS styles, RFC 6570 expansion, RFC 3986
  percent-encoding); internal `ParameterValue`, `PercentEncoder`.
- `request/` - `OperationInfo` (put into `RequestOptions.extra`),
  `OperationRequest` (resolves the path and the query itself;
  `streamStatuses` for event streams), `RawResponse` (what a generated
  decoder switches on).
- `dio/` - `DioRequestSender(dio, {isWeb})` (`send`, `openEvents`; requests
  only through `dio.request`, never mutates the user's Dio, never retries;
  decoding catches only `DioException`, `JsonDecodeException` and, from the
  user's decoder, `FormatException` (a converter or `Date.parse` rejecting
  the data: `DecodeError` at the root pointer, `SseDecodeError` in a
  stream), `openEvents` also turns an `Exception` raised while reading a non-stream
  body into `TransportError`, and an `Error` is never caught; the query is
  built by the runtime, so interceptors see an empty `queryParameters`),
  `CallOptions`. `openEvents` needs its stream listened to or cancelled; a
  listener cancel cancels the request.
- `sse/` - `SseDecoder` (WHATWG, bytes -> `SseMessage`), `SseItemDecoder`
  (-> `SseEvent` / `SseDecodeError` / `SseDisconnected`; data problems are
  items, an `Error` from the user's decoder is the only stream error). Use
  `transformer.bind(stream)`, not `stream.transform`: Dio gives a
  `Stream<Uint8List>`.

Runtime tests never touch the network: Dio gets `FakeAdapter`
(`test/helpers/fake_adapter.dart`).

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
  ...). Every public member has a doc comment. Formatting keeps trailing commas.
- Tests do not touch the network; temp files only through `TempDir` in
  `test/helpers/temp_dir.dart`.

## Design rules (from CONTRIBUTING.md)

- Nothing is guessed silently: every normalizer fix, fallback or skipped
  construct yields a diagnostic with a stable code and a JSON pointer.
- Deterministic output: same spec + same config -> byte-identical code. Sort
  everything; no hash-ordered iteration when emitting; no network or `dart fix`
  during generation.
- A change of generated output is a breaking change of the generator.
- The user's HTTP client is not ours: generated code never mutates the Dio
  instance; HTTP errors go through Dio's `onError` and are typed afterwards.
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
- `docs/research/` - competitor research (`README.md` summary, `01`-`07`
  detailed reports).
- `docs/superpowers/plans/` - step-by-step implementation plan per milestone
  (M1: `2026-10-11-m1-check-cli.md`).
- `CONTRIBUTING.md` - setup, conventions, commit rules.

## Language

Documents in `docs/` are written in Ukrainian. Code, code comments, doc
comments, diagnostics messages and commit messages are in English.
