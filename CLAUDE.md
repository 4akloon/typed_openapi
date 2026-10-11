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
cd packages/<package> && dart pub publish --dry-run # before publishing
```

Git commands run from the repo root. Commit messages are Conventional Commits
(`feat(typed_openapi): ...`, `refactor(...)`, `docs: ...`).

## Architecture (`dart run typed_openapi check`)

All under `packages/typed_openapi/lib/src/`, one folder per stage:

- `diagnostics/` - `Diagnostic`, `DiagnosticCode` (stable `TOAnnn` catalog),
  `Severity`, `JsonPointer`, `DiagnosticBag`, and the reporters
  (`DiagnosticReporter`, `TextReporter`, `JsonReporter`, `ReportFormat`).
- `load/` - `SpecLoader` reads JSON/YAML into a `SpecDocument` (plain tree,
  absolute file URI, source spans by JSON pointer, `valueAt(pointer)`);
  `NestingScanner` rejects text nested deeper than 1000 levels before the
  recursive YAML parser sees it (it is YAML-context aware: quotes and brackets
  are syntax only at a value start, block scalars are skipped, `- `, `? ` and
  empty-key `: ` markers each nest one level; a root flow collection is level
  0, like a root block mapping). The same scan accepts an alias only as a
  block value (`key: *a`, `- *a`, nothing but blanks and a comment after it
  on the line) and reports any other alias with TOA008: in a flow collection,
  in key position, followed by text, alone on a line. In a document that has
  an alias it also reports an explicit `?` key; without aliases `?` keys are
  left alone. The YAML parser would otherwise expand such aliases (hash them
  as keys) before any later check. Aliases in values bypass the text scan,
  so `SpecLoader` also limits the conversion to a plain tree: deeper than
  1000 levels once aliases are expanded is TOA007; a budget of
  `max(16000000, 20 * text length)` characters, where each converted node
  (first visit or repeat) costs the length of its JSON pointer + 1 (the
  pointer is what it keeps in `spans`), is TOA008 when spent (an alias bomb,
  or very long keys); both return no document. `OpenApiVersionDetector`
  reads the version.
- `model/` - the immutable typed model, a superset of OAS 3.0/3.1/3.2:
  `SpecNode` (every node has a `SpecLocation` = file URI + pointer, `x-`
  `extensions` and reported `unknownKeys`), `RefOr<T>` = `Ref<T>` | `Inline<T>`,
  `Schema` = `BooleanSchema` | `SchemaObject` (`$ref` is a keyword there),
  `OpenApiDocument` and the other OAS objects.
- `parse/` - `OpenApiParser` (document, components, fragments for `$ref`
  targets), `OperationParser`, `SchemaParser`, all on `ObjectReader` (typed
  field access; wrong types and non-finite numbers -> TOA111, missing required
  -> TOA112, unknown keys -> TOA110). Parsers record nodes, `$ref`s and
  version-specific constructs (`SpecFeature`) in a shared `SpecIndex`, which
  also remembers every location a parser has read (`visited`): a location is
  read once, so a later read (a `$ref` into a region and then one to its
  parent) gets the first node and reports nothing again;
  `DialectChecker` turns the constructs into TOA020-TOA022.
- `resolve/` - `RefTarget` reads a `$ref` value (a query, a bad fragment or a
  file name that is not UTF-8 after percent-decoding -> TOA100, a host ->
  TOA102), `SpecDocuments` loads other local files once by
  URI, `RefResolver` follows every `$ref` (parsing each on-demand target once)
  and reports TOA100-TOA105, `SpecModel` answers `resolve`/`resolveSchema`;
  `SpecReader` runs parse -> resolve -> dialect check.
- `config/` - `ConfigLoader`, `ProjectConfig`, `ClientConfig`, `Preset`.
- `check/` - `SpecChecker`: config -> load -> version -> `SpecReader`.
- `cli/` - `TypedOpenApiCli` (`cli.dart`, owns the `CommandRunner` and maps
  usage errors to exit code 64) and `CheckCommand` (`check_command.dart`,
  options `--config/-c` and `--format`, client names as positional
  arguments); `bin/typed_openapi.dart` only calls `TypedOpenApiCli().run(args)`
  and sets `exitCode`.
- `lib/typed_openapi.dart` exports the public API, each with a `show` list:
  `SpecChecker`, `TypedOpenApiCli`, `ConfigLoader`, `ClientConfig`, `Preset`,
  `ProjectConfig`, the diagnostics (`Diagnostic`, `DiagnosticBag`,
  `DiagnosticCode`, `JsonPointer`, `Severity` and the reporters), the loader
  (`SpecLoader`, `SpecDocument`, `OpenApiVersion`, `OpenApiVersionDetector`),
  the whole `model/` (`SpecNode`, `SpecLocation`, `RefOr`, `Ref`, `Inline`,
  `RefKind`, `OpenApiDocument` and the other OAS objects) and the entry points
  `SpecReader` and `SpecModel`. Not exported: `CheckCommand`, the internals of
  `parse/` (`OpenApiParser`, `OperationParser`, `SchemaParser`, `ObjectReader`,
  `ParseContext`, `SpecIndex`, `DialectChecker`) and `resolve/` (`RefTarget`,
  `RefResolver`, `SpecDocuments`), and `NestingScanner`.

Data flows loader -> parser -> resolver -> checker, every stage writing
problems into one `DiagnosticBag`; reporters read the bag at the end.

Rules of the pipeline:

- Errors in user input (specs, config) are never thrown; they are reported to
  the `DiagnosticBag` and processing continues where possible.
- Reports are deterministic: diagnostics sort by file, position, pointer, code,
  message (`Diagnostic.compareTo`, `DiagnosticBag.sorted`). `DiagnosticBag`
  ignores a diagnostic equal to one it has (same code, severity, message, file,
  pointer and start position), so a region read twice reports once.
- The CLI never calls `exit()`; commands return the code. Reports go to
  stdout, usage errors to stderr. Codes: `0` ok, `1` errors found, `64` usage,
  `78` the config file could not be loaded (TOA904 and per-client TOA902 exit
  `1`).

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
