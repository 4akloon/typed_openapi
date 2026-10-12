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
cd packages/typed_openapi_runtime && dart test -p chrome                        # dart2js
cd packages/typed_openapi_runtime && dart test -p chrome --compiler dart2wasm   # dart2wasm
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
  `fixedCodes` - read errors, TOA801-TOA803, TOA820/821/823, TOA830-TOA833 -
  can be raised but not lowered), `Severity` (declared from most to least
  serious; level comparison uses its order), `SeverityLevels` (a client's
  `severity` config), `JsonPointer`, `DiagnosticBag` (baselined diagnostics kept
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
  `triState`, and `union`, `raw` or `structural`, on a schema or a property)
  that the IR builder reads (M6, M8; `sse` is not accepted until M10 settles
  its shape). A missing file is TOA801, a directory or a
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
- `config/` - `ConfigLoader`, `ProjectConfig`, `ClientConfig`, `Preset`,
  `GenerationConfig` (`naming`, `group_by`, `include`/`exclude`
  (`OperationFilter`, `FilterPattern`), `types`, `tri_state`, `union`
  (`raw`, the default, or `structural`: how a `oneOf`/`anyOf` without a
  discriminator whose variants share a JSON type is generated, TOA453; an
  override `union` wins), `errors`; a client's key wins over `defaults`,
  `naming`/`types`/`errors` key by key).
  A bad value is TOA902 and the default is used: a `default_group` that is a
  reserved word, equal `input_suffix` and `patch_suffix` (both go back to
  their defaults). `operation_prefix` applies only where its match starts at
  index 0 and is not empty. `GenerationConfig.key` is the run key: custom
  types are sorted, and a client with a filter or an `errors.default_schema`
  is keyed by where the config has it, so TOA557, TOA558, TOA562 and TOA563
  are reported at its own place, not at that of a client with equal
  settings.
- `ir/` - the semantic IR (M6): `ir.dart` (`ClientIr`, sealed `Declaration`
  = `ModelDecl` | `EnumDecl` | `UnionDecl`, `FieldIr`, `GroupIr`,
  `OperationIr`, `ParameterIr`, `RequestBodyIr`, `ResponseIr`, sealed
  `ErrorsIr`), `dart_type.dart` (sealed `DartType`; `DeclId` = schema
  location + `DeclVariant` (`base`, `input` for the request model of a
  schema split by direction, `patch` for the PATCH body model of a schema
  also used elsewhere); types refer to declarations by id, and
  `CustomType.json` never names one), `names.dart` (`DartNames`: word
  splitting, case, reserved sets and the name check `NameKind`, `isValid`,
  `sanitize`, `dropsLetters`; `NameScope` gives a name, a suffix for
  reserved names and `2`, `3`... for collisions), `IrContext`/`IrOverrides`
  (generation fields of applied overrides by node location;
  `checkedOverrideName` validates an override name, TOA560, and
  `checkLossyName` reports letters a name lost, TOA559; `defaultErrorSchema`
  is `errors.default_schema` if `components.schemas` has the key, else
  TOA562), `SchemaShapes` (shape questions the mapper and `DirectionIndex`
  share: null-only, enum values, the one schema a wrapper stands for; an
  `allOf` part with no structure, only annotations and `nullable`, is not a
  merge part and is set aside next to the one `$ref`),
  `SchemaMapper` (types, models, enums, unions, `allOf` merge,
  single-schema collapse, custom types; a field's `description`, `default`,
  `deprecated` come from the property, then its annotation-only `allOf`
  parts, then the schema it refers to (3.0 ignores siblings of a `$ref`);
  declarations are created when first
  reached, so only reachable schemas exist, and named at the end: override
  names, then component keys, then inline names by depth. A declaration is
  its `DeclId`: reaching it again gives the same one, named after the first
  use, and an inline name always resolves to a declaration of the set. A
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
  the media types that are dropped are named, TOA561, except variants of the
  chosen type and other JSON types; envelopes; errors, with
  `errors.default_schema` for statuses without a body; header parameters
  `Accept`, `Content-Type` and `Authorization` are dropped as OpenAPI says;
  a parameter style its `in` does not allow falls back to the default, and
  an `in: querystring` parameter is skipped, TOA564) and `IrBuilder`
  (operations written as a `$ref` are skipped (TOA107); groups by tag, path
  or one class, with an override `group` (UpperCamelCase, or a value that
  differs only by case or separators) and TOA553-TOA555; the names of custom
  types are taken in the type scope first, so a declaration named like one
  gets a suffix, TOA551; method names,
  override names first, then
  `operationId` without the `operation_prefix`, then the path; TOA563 when
  no operation is generated, at the config client if filters left some
  out, else at `#/paths`; then everything above). `IrJson` dumps an IR; the
  hidden `typed_openapi ir` command prints it. Naming and mapping codes use
  the second half of each area's hundred: TOA250-TOA256, TOA350-TOA351,
  TOA450-TOA456, TOA550-TOA564; `generate` has TOA830 (output not owned),
  TOA831 (output not written, or its lock held) and TOA832 (an interrupted
  run recovered, or a lock taken over; info). TOA552 on an enum value is an info (an override cannot name enum
  values; `x-enum-varnames` in the spec does), and `unknown` is reserved in
  the enum value scope (`unknown_`).
- `emit/` - the model emitter (M8), whose only input is the IR (it never
  reads the spec): `DartCode` (string literals: `\`, `'`, `$`, line breaks
  including U+0085, U+2028 and U+2029, controls, bidirectional controls and
  lone surrogates are escaped; one-line code spans `docSpan`/`jsonSpan`;
  `docLines` for spec text: `[`, `]`, `<`, `>`, `\` and `{@` escaped outside
  code spans, controls dropped, wrapped at the width, fenced blocks kept;
  `proseLines` for the generator's own sentences, which never breaks a code
  span), `DartWriter` (own layout: indentation, `doc`, `prose`,
  one-line-or-one-item-a-line lists, `&&` chains; `line` asserts that the
  text has no line break), `Imports` (`dart:`, `package:` with sorted `show`
  lists wrapped at the width, relative files), `TypeCodec` (type names,
  known-enum types for request constructors, decoders, encoders,
  `DeepEquality` need, JSON patterns of union variants), `ModelEmitter`,
  `EnumEmitter`, `UnionEmitter` and `ModelLibrary` (`models/<snake>.dart`
  per declaration, names that clash get `2`, `3`...; the barrel
  `models.dart`; the header is `// GENERATED CODE - DO NOT MODIFY BY HAND.`
  and, on the second line, `// dart format off`). Generated classes are
  `class`, not `final class` (users may extend them); union bases are
  `sealed` (`abstract interface` when not exhaustive) and every class is
  `@immutable`. Every spec string is escaped at every site it reaches: a
  literal, a comment or an identifier (names come from the IR only).
  Constants (`FieldIr.constValue`), constraints (`ConstraintsIr`), the name
  of the additional properties field and the helper types
  (`EnumDecl.knownName`/`unknownName`, `UnionVariantIr.name`,
  `UnionDecl.unknownName`, named after the groups) come from `SchemaMapper`.
  `UnionDispatch` is `discriminator`, `jsonType` (by JSON type, `int`
  before `num`; the variants of a JSON type several share are one variant
  of `JsonValue`, `UnionVariantIr.jsonKinds`, with TOA453) or `structural`
  (`union: structural`, tries the variants); a union where every variant
  shares its type is `JsonValue` (TOA453), also when a variant takes any
  JSON, which makes the union structural with TOA453; duplicate variant
  types are dropped (TOA454); two variants selected by one discriminator
  value are TOA456 (the earlier one decodes it). A nested union without a
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
  by location), finds a secret in its schema (`SchemaMapper._rawSecret`: a
  field, `additionalProperties`, the shared `JsonValue` variant of a union
  over every branch it keeps); `UnionDecl.unknownSensitive` (a secret
  anywhere in any branch) and a secret variant make the unknown variant
  print `<redacted>`.
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
  letters or digits>[-old]` directories. Under the lock, `_leftovers` skips
  any that holds an input of the run (by location, by symbolic link and by
  file identity), `_inspect` checks the output (or the newest backup, when
  the output is missing) as above, and only then `_recover` restores that
  backup and removes the other leftovers (a backup only once the output
  holds a manifest), reporting TOA832 (info). `OutputWriter.forTesting`
  (`@visibleForTesting`) takes the test hooks (`beforeInstall`, and `run`
  for `chmod`/`kill`); the public constructor has none.
  `RealPaths` compares paths with symbolic links resolved and case ignored
  where the file system ignores it (found by a probe; `ConfigLoader` uses it
  for TOA904 too). An input of the run is also found by file identity
  (`FileSystemEntity.identical`) among the files in the output, so a hard
  link or a case-different name never gets an input deleted: this stays as
  the second line of defence. The protected files are those of every client
  in the config, also one that was not selected: the declared input,
  overrides and baseline, the `$ref`'d files of the clients that were
  checked, and the config itself. A client whose output overlaps another's
  (TOA904) is skipped by `generate`. `GenerateCommand` has `--config/-c`, `--force` and
  `--break-lock`.
- `check/` - `SpecChecker`: config -> load -> version -> overrides ->
  `Normalizer` -> `IrBuilder` once per run (file, preset, rules, overrides
  file, `GenerationConfig.key`); an overrides file that cannot be used is
  reported (an error) and the spec is checked without it; `generate` skips
  such a client. Each client then applies its levels
  (`checkClients` -> `ClientCheck`) and its baseline (`check`, which also
  returns the `ClientCheck`s).
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
  that overlaps another's, writes the models with `ModelLibrary` and
  `OutputWriter`, the inputs hash from `ClientCheck.sources` and the
  client's settings; text report, then a line per client; exit code as
  `check`) and the hidden `IrCommand` (`ir_command.dart`, prints the IR of
  clients as JSON alone on stdout; the errors and warnings of the run go to
  stderr as text with the count of the infos, a client with no IR is named
  there, and the exit code is the one `check` gives);
  `bin/typed_openapi.dart` only calls `TypedOpenApiCli().run(args)` and sets
  `exitCode`.
- `lib/typed_openapi.dart` exports the public API, each with a `show` list:
  `SpecChecker`, `ClientCheck`, `TypedOpenApiCli`, `ConfigLoader`,
  `ClientConfig`, `Preset`, `ProjectConfig`, `GenerationConfig`, `GroupBy`,
  `TriStateRule`, `OperationFilter`, `FilterPattern`, `ModelLibrary`,
  `OutputWriter`, `OutputChanges`, the IR (`IrBuilder`,
  `IrJson`, `ClientIr` and its node classes, `DartType` and its
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
  `DartTypeOverride`, `UnionMode`). Not exported: `CheckCommand`,
  `BaselineCommand`, `GenerateCommand`, `RealPaths`, the emitters
  (`DartCode`, `DartWriter`, `Imports`, `TypeCodec`, `ModelEmitter`,
  `EnumEmitter`, `UnionEmitter`), the
  internals of `parse/` (`OpenApiParser`, `OperationParser`, `SchemaParser`,
  `ObjectReader`, `ParseContext`, `SpecIndex`, `DialectChecker`), `resolve/`
  (`RefTarget`, `RefResolver`), `normalize/` (`TreeEditor`, the rule
  classes), `overrides/` (`OverrideResolver`, `OverrideApplier`,
  `OverrideSnippet`), `ir/` internals (`IrContext`, `IrOverrides`,
  `SchemaMapper`, `SchemaShapes`, `RefFollower`, `Decimal`, `NameHint`,
  `DirectionIndex`,
  `OperationSelector`, `OperationBuilder`, `SpecOperation`, `DartNames`,
  `NameScope`), `IrCommand`, `YamlComposer` and `load/yaml/`.

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

## Runtime (`packages/typed_openapi_runtime/lib/src/`)

The only package generated clients depend on (dependencies: `dio`, `meta`, floor `^1.15.0` so Flutter's pinned `meta` resolves).
Pure Dart, works on the web (compiled to JS and to Wasm); SSE needs a
streaming adapter there (Dio's default browser adapter delivers the body
only when the connection closes), and cookie parameters do not work (browsers
drop the `Cookie` header).
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
  `Date` (`format: date`, no time or zone), `DeepEquality` (deep `==` and
  `hashCode` of lists, maps and patches for generated models). The barrel
  re-exports `immutable` from `package:meta`, so generated code imports only
  the runtime. `JsonReader` also has `constant`, `additional` (the keys a
  model does not list, as an unmodifiable map), `patchValue`, `asBytes` and
  `attempt` for generated code.
- `result/` - sealed `Result<T, E>`: `Success`, `Failure` (`HttpError`,
  `UndocumentedStatus`, `DecodeError`, `TransportError`, `Cancelled`); no
  helper methods, pattern matching only. `E = Never` still needs
  `case Failure()`.
- `params/` - `PathParameter`, `QueryParameter`, `HeaderParameter`,
  `CookieParameter` (OAS styles, RFC 6570 expansion, RFC 3986
  percent-encoding; a path expansion that is empty, `.` or `..` throws
  `ArgumentError`, as does a `.`/`..` value); internal `ParameterValue`,
  `PercentEncoder`.
- `request/` - `OperationInfo` (put into `RequestOptions.extra`),
  `OperationRequest` (resolves the path and the query itself;
  `streamStatuses` for event streams), `RawResponse` (what a generated
  decoder switches on).
- `dio/` - `DioRequestSender(dio, {isWeb})` (`send`, `openEvents`; requests
  only through `dio.request`, never mutates the user's Dio, never retries;
  decoding catches only `DioException`, `JsonDecodeException` and, from the
  user's decoder, `FormatException` (a converter or `Date.parse` rejecting
  the data: `DecodeError` at the root pointer, `SseDecodeError` in a
  stream), `openEvents` also turns an `Exception` raised while reading a
  non-stream body into `TransportError`, and an `Error` is never caught; the
  query is
  built by the runtime, so interceptors see an empty `queryParameters`),
  `CallOptions`. `openEvents` needs its stream listened to or cancelled; a
  listener cancel cancels the request.
- `sse/` - `SseDecoder` (WHATWG, bytes -> `SseMessage`), `SseItemDecoder`
  (-> `SseEvent` / `SseDecodeError` / `SseDisconnected`; data problems are
  items, an `Error` from the user's decoder is the only stream error). Use
  `transformer.bind(stream)`, not `stream.transform`: Dio gives a
  `Stream<Uint8List>`.

Runtime tests never touch the network: Dio gets `FakeAdapter`
(`test/helpers/fake_adapter.dart`). They also run in Chrome (the two
commands above; `CHROME_EXECUTABLE` if Chrome is not found): a file that
needs the VM (`dart:io`, int64 literals, which dart2js rejects) carries
`@TestOn('vm')`, a single test `testOn: 'vm'`, and `test/dio/web_test.dart`
is `@TestOn('browser')`. `test/helpers/test_platform.dart` tells the platform
for assertions that differ. Do not write an int literal beyond 2^53 in
`lib/`: it does not compile to JavaScript.

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
- `docs/code-quality-review.md` - quality review, the exemption list of files
  over the size limits, and the refactoring order.
- `docs/research/` - competitor research (`README.md` summary, `01`-`07`
  detailed reports).
- `docs/superpowers/plans/` - step-by-step implementation plan per milestone
  (M1: `2026-10-11-m1-check-cli.md`).
- `CONTRIBUTING.md` - setup, conventions, commit rules.

## Language

Everything is in English: documents in `docs/`, `CLAUDE.md`, READMEs, code,
code comments, doc comments, diagnostics messages and commit messages. A new
or edited document is written in English; a document still in Ukrainian
(see `docs/README.md`) is translated when it is next edited. The only
Ukrainian files are the intentional user-facing `README.ua.md` translations.
