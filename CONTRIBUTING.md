# Contributing to typed_openapi

## Contents

- [Prerequisites](#prerequisites)
- [Getting the code](#getting-the-code)
- [Repository layout](#repository-layout)
- [Everyday commands](#everyday-commands)
- [Adding to the catalogs](#adding-to-the-catalogs)
- [Design rules](#design-rules)
- [Coding conventions](#coding-conventions)
- [Object-oriented code and Dart 3.10](#object-oriented-code-and-dart-310)
- [Tests](#tests)
- [Commits & pull requests](#commits--pull-requests)

## Prerequisites

- Dart SDK `>=3.10.0 <4.0.0`. All packages are pure Dart; Flutter is not needed.

## Getting the code

This repo is a [Dart pub workspace](https://dart.dev/tools/pub/workspaces):
all packages are resolved together from one lockfile. Run this once from the
repo root:

```sh
dart pub get
```

## Repository layout

See the [packages list in the root README](README.md#packages). In short:
`typed_openapi` is the generator (CLI + programmatic API) and is never a runtime
dependency of user apps; `typed_openapi_client` is the only package generated
clients depend on.

Requirements and research live in [docs/](docs/).

## Everyday commands

Run from the repo root unless noted otherwise:

```sh
dart analyze packages
dart format packages

cd packages/typed_openapi_core && dart test
cd packages/typed_openapi && dart test
cd packages/typed_openapi_client && dart test
cd packages/typed_openapi_tool && dart test

# Before publishing a package (the four share one version; publish in the
# order typed_openapi_core, typed_openapi_client, typed_openapi,
# typed_openapi_dio):
cd packages/<package> && dart pub publish --dry-run

# The public-spec corpus and the escaping fuzz (packages/typed_openapi_tool):
cd packages/typed_openapi_tool && dart run bin/corpus.dart check
cd packages/typed_openapi_tool && dart run bin/corpus.dart update   # after an intended output change
cd packages/typed_openapi_tool && dart run bin/fuzz.dart --seeds 200

# The corpus specs through `typed_openapi lint`, and the framework detection:
cd packages/typed_openapi_tool && dart run bin/corpus.dart lint

# The docs generated from the code (see "Adding to the catalogs"):
cd packages/typed_openapi_tool && dart run bin/docs.dart check
cd packages/typed_openapi_tool && dart run bin/docs.dart generate
```

A change that changes generated output (`corpus.lock` or a golden file)
goes with a `corpus update` in the same commit, an entry under
`### Output changes` in `packages/typed_openapi/CHANGELOG.md` and a raised
version (minor before 1.0, major after; no raise is needed while the base's
top CHANGELOG section is the `Unreleased` one of the current version); CI
checks it with
`dart run bin/corpus.dart semver`.

## Adding to the catalogs

Some documentation and the two JSON Schemas are generated from the code, so
they cannot drift from it. Never edit `packages/typed_openapi/doc/diagnostics.md`,
`doc/extensions.md` or `packages/typed_openapi/schema/*.json` by hand: change
the source below, run `dart run bin/docs.dart generate` in
`packages/typed_openapi_tool`, and commit the result with the change. A test
(`the generated docs of the repository are current`) and the CI job `docs`
fail while a generated file is stale.

- **A diagnostic code.** Add an entry to the `DiagnosticCode` enum in
  `packages/typed_openapi_core/lib/src/diagnostics/diagnostic_code.dart`:
  `name('TOAnnn', 'slug', .severity)`, in the hundred of the stage that
  reports it. Its doc comment is one or more paragraphs of meaning, then a
  paragraph that starts `Example: ` and one that starts `Fix: `, each ending
  with a full stop. A missing or incomplete comment fails
  `diagnostic_source_test`, and `docs.dart generate` stops with the entry's
  id. A code never changes meaning once released.
- **A config key.** Add a `KeySpec` (type, description, a valid `example`,
  `defaultValue`, `invalidExamples`) to the catalog in
  `packages/typed_openapi_core/lib/src/schema/`: `ConfigCatalog`, or
  `ConfigGenerationKeys` / `ConfigNamingKeys` for a generation setting. The
  loader's allowed keys (`ConfigKeys`) come from the catalog; read the value
  through `ConfigSources.resolve`, so an invalid client value falls back to
  `defaults` and TOA902 names the value applied. The schema tests in the core
  judge the catalog's examples with both the schema and the loader, and the
  two must agree. The overrides file works the same way through
  `OverrideCatalog`, `OverrideOperationKeys` and `OverrideSchemaKeys`.
- **An `x-` extension.** Add a `SpecExtension` (key, what it applies to,
  effect, an example, the diagnostics that report its wrong value) to
  `SpecExtensions` in `packages/typed_openapi_core/lib/src/extensions/`, and
  to `SpecExtensions.all`. Code reads it as `SpecExtensions.<name>.key`:
  `spec_extensions_test` fails when another file of `lib/` writes an `x-`
  literal.
- **A framework recipe.** The recipe of a framework is
  `packages/typed_openapi/doc/frameworks/<name>.md`, and its advice in the
  tool is `NormalizerRule.hint(code, preset)`. A recipe ends with a
  `## Sources` section that has at least three links, `Checked on <date>.`
  and `Versions:`; a hint states only what a source says.
  `framework_recipes_test` also fails when a code that fires on a corpus spec
  of that framework (`framework:` in `corpus.yaml`, counts in `corpus.lock`)
  is not named in the recipe. A finding whose text offers an override also
  needs a `backendFix:` that does not (`backend_fixes_test`), because
  `typed_openapi lint` never tells a backend team to write an override.

## Design rules

These come from the competitor research in [docs/](docs/); breaking them
reintroduces bugs other generators are known for.

- **Nothing is guessed silently.** Every normalizer fix, fallback or skipped
  construct produces a diagnostic with a stable code and a JSON pointer.
- **Deterministic output.** Same spec + same config → byte-identical code. Sort
  everything; never iterate hash-ordered collections when emitting; no network,
  `dart fix` or other SDK-dependent steps during generation.
- **A change to the generated output is a breaking change** of the generator
  and needs a major version (or an opt-in flag).
- **The user's HTTP client is not ours.** Generated code and `DioTransport`
  never mutate the Dio instance (`baseUrl`, interceptors, `validateStatus`);
  HTTP errors go through Dio's normal `onError` path and are typed afterwards.
- **No `analyzer` in the generator core.** Analyzer churns majors every month or
  two; tests run `dart analyze` on generated fixtures as a subprocess.
- **Escape every string taken from the spec** at every interpolation site.

## Coding conventions

Enforced via `analysis_options.yaml` (built on `package:lints/recommended.yaml`):

- `public_member_api_docs` — every public member needs a doc comment.
- `sort_constructors_first`, `prefer_final_locals`, and the other rules
  listed in `analysis_options.yaml`.

## Object-oriented code and Dart 3.10

- No top-level functions, except `main` in `bin/` and in tests. Private helpers
  are private methods (static if they need no state); constants live in the
  class they belong to.
- Components that report problems get a `DiagnosticBag` through the constructor
  and never throw on bad user input.
- Use language features from Dart 3.10 on: dot shorthands wherever the context
  type is known (`.error`, `severity: .error`), null-aware collection elements
  (`'k': ?v`), switch expressions and patterns, records, class modifiers
  (`final`, `sealed`, `interface`) and extension types. In tests, `expect(...)`
  arguments have no context type, so use full names there.
- Primary constructors (Dart 3.13) are not used, to keep the SDK floor at 3.10.

See [CLAUDE.md](CLAUDE.md) for the same rules in short form.

## Tests

- Golden tests: one fixture per OpenAPI construct, generated output compared
  byte for byte.
- Public specs (Petstore, Stripe, GitHub, OpenAI, Kubernetes): generated code
  must compile and pass the analyzer.
- Runtime decoding tests for generated models.

## Commits & pull requests

- Branch off `main`.
- Run `dart analyze packages` and the relevant test suite(s) before pushing.
- Update the affected package's `CHANGELOG.md` for any user-facing change.
