# Contributing to typed_openapi

## Contents

- [Prerequisites](#prerequisites)
- [Getting the code](#getting-the-code)
- [Repository layout](#repository-layout)
- [Everyday commands](#everyday-commands)
- [Design rules](#design-rules)
- [Coding conventions](#coding-conventions)
- [Object-oriented code and Dart 3.10](#object-oriented-code-and-dart-310)
- [Tests](#tests)
- [Commits & pull requests](#commits--pull-requests)

## Prerequisites

- Dart SDK `>=3.10.0 <4.0.0`. Both packages are pure Dart; Flutter is not needed.

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
dependency of user apps; `typed_openapi_runtime` is the only package generated
clients depend on.

Requirements and research live in [docs/](docs/).

## Everyday commands

Run from the repo root unless noted otherwise:

```sh
dart analyze packages
dart format packages

cd packages/typed_openapi && dart test
cd packages/typed_openapi_runtime && dart test

# Before publishing a package:
cd packages/<package> && dart pub publish --dry-run
```

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
- **The user's HTTP client is not ours.** Generated code never mutates the Dio
  instance (`baseUrl`, interceptors, `validateStatus`); HTTP errors go through
  Dio's normal `onError` path and are typed afterwards.
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
