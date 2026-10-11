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
cd packages/typed_openapi && dart format lib test   # a second run must change 0 files
cd packages/<package> && dart pub publish --dry-run # before publishing
```

Git commands run from the repo root. Commit messages are Conventional Commits
(`feat(typed_openapi): ...`, `refactor(...)`, `docs: ...`).

## Architecture of M1 (`dart run typed_openapi check`)

All under `packages/typed_openapi/lib/src/`, one folder per stage:

- `diagnostics/` - `Diagnostic`, `DiagnosticCode` (stable `TOAnnn` catalog),
  `Severity`, `JsonPointer`, `DiagnosticBag`, and the reporters
  (`DiagnosticReporter`, `TextReporter`, `JsonReporter`, `ReportFormat`).
- `load/` - `SpecLoader` reads JSON/YAML into a `SpecDocument` (plain tree plus
  source spans by JSON pointer).
- `config/` - `ConfigLoader`, `ProjectConfig`, `ClientConfig`, `Preset`.
- `check/` - `OpenApiVersionDetector`, `SpecChecker`.
- `cli/` - `TypedOpenApiCli` (`cli.dart`, owns the `CommandRunner` and maps
  usage errors to exit code 64) and `CheckCommand` (`check_command.dart`,
  options `--config/-c` and `--format`, client names as positional
  arguments); `bin/typed_openapi.dart` only calls `TypedOpenApiCli().run(args)`
  and sets `exitCode`.
- `lib/typed_openapi.dart` exports the public API: the classes above, each with
  a `show` list.

Data flows loader -> checker, every stage writing problems into one
`DiagnosticBag`; reporters read the bag at the end.

Rules of the pipeline:

- Errors in user input (specs, config) are never thrown; they are reported to
  the `DiagnosticBag` and processing continues where possible.
- Reports are deterministic: diagnostics sort by file, position, pointer, code,
  message (`Diagnostic.compareTo`, `DiagnosticBag.sorted`).
- The CLI never calls `exit()`; commands return the code. Reports go to
  stdout, usage errors to stderr. Codes: `0` ok, `1` errors found, `64` usage,
  `78` config error.

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
