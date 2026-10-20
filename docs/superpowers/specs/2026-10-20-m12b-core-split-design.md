# M12b: core split — engine and generator — design

**Date:** 2026-10-20.

**Why now:** `packages/typed_openapi` holds two things that change for different reasons: the engine that reads, repairs and checks a spec and builds the semantic IR (30,460 lines in 243 files, 137 test files), and the generator that turns the IR into Dart and installs it (5,726 lines in 44 files, 31 test files). Everything a user installs in `dev_dependencies` today carries both. grund, a Dart backend platform in another repository, only needs the engine: its CI runs `SpecChecker` over its own spec (`docs/grund-roadmap.md`, T1) and must not depend on a code generator for that. M12 has just landed (snapshot, diff, lock), so the engine's public surface is as large as it will get before 0.1.0; splitting after publication would be a breaking release, splitting now is a refactor.

**Roadmap:** a stage between M12 and M13; M13 keeps its number.

**Earlier stages:**
- [M11b](2026-10-19-m11b-transport-split-design.md): the same kind of split for the runtime (`typed_openapi_client`, `typed_openapi_dio`, `typed_openapi_transport_tests`); its plan is the model for this one.
- [M12](2026-10-13-m12-evolution-design.md): `snapshot/` and `diff/`, whose symbols the generator's CLI uses.
- [M11](2026-10-13-m11-corpus-design.md): `corpus.lock` and `corpus check` are the proof that nothing changed.

The user took the decisions below in a conversation; they are recorded, not reopened. "Author's call" marks what the author of this document chose.

## Goals

- `typed_openapi_core` is a package of its own: load, repair, check and build the IR, with the diagnostics, config, overrides, baseline, snapshot and diff around them. A tool that only checks specs depends on it and not on the generator.
- `typed_openapi` keeps the commands and the writers: `emit/`, `generate/`, `cli/`, the executable, the user documentation.
- No behaviour changes. The generated code of every client is byte-identical, `corpus.lock` does not change, and every test that exists today exists afterwards and passes.

## Non-goals

- A server-spec package, or a spec writer in the model. grund generates its spec its own way; the model stays read-only.
- Re-exporting the core from `typed_openapi`. A user of the programmatic API imports both libraries.
- Changing any public symbol, diagnostic code, message or generated line. A symbol the generator needs from the core is exported as it is.
- Publishing. Nothing is on pub.dev yet; this stage only fixes the order and the dry-runs.

## Decisions

1. **Two published packages and one internal one.**
   - `typed_openapi_core` (new): the engine. Depends on `collection`, `crypto`, `path`, `source_span` and `string_scanner`; no Flutter, no `dart:mirrors` in `lib/`.
   - `typed_openapi` (kept): the generator and the CLI. Depends on `typed_openapi_core`, `args`, `crypto`, `io`, `meta` and `path`.
   - `typed_openapi_test_support` (new, `publish_to: none`): the fixtures and helpers both packages' tests share; it holds no tests. Dependencies by use: a package lists what its own `lib/` and `test/` import and nothing else.

2. **What moves to the core.** The `lib/src` folders `diagnostics`, `load` (with the vendored `load/yaml`), `model`, `parse`, `resolve`, `normalize`, `overrides`, `config`, `ir`, `baseline`, `snapshot`, `diff` and `check`, and `RealPaths` (see 3), in a new folder `paths`. The generator keeps `emit`, `generate`, `cli`, `bin/`, the `executables:` entry, `doc/`, both READMEs and the CHANGELOG. 243 files move; `git mv` keeps history.

3. **One dependency points the wrong way, and it is cut first.** Measured on 2026-10-20: of all imports across the old folder boundaries, exactly one goes from the engine to the generator side: `config/config_loader.dart` imports `generate/real_paths.dart` (`RealPaths`, which compares paths with symbolic links resolved; TOA904 uses it). `RealPaths` has no dependency on the rest of `generate/`, so it moves to `paths/` first, in its own commit, and goes with the engine; the generator imports it from the core barrel. Every other edge points from `emit`, `generate` and `cli` to the engine.

4. **No `src` import crosses a package.** The generator reaches the core through `package:typed_openapi_core/typed_openapi_core.dart` only; the lint `implementation_imports` (part of `lints/recommended`, already on) makes `dart analyze packages` prove it. Where the generator needs a symbol the barrel does not export, the symbol is exported, decided per symbol; no code is duplicated and none moves just to avoid an export. Measured: 16 symbols plus `RealPaths` are added to the barrel: `ApiLock`, `ApiSnapshot`, `SnapshotBuilder`, `SnapshotJson`, `ApiDiff`, `ApiChange`, `ChangeCategory`, `ChangeCounts`, `TextDiffReport`, `JsonDiffReport`, `MarkdownDiffReport`, `DartNames`, `NameScope`, `MediaTypeName`, `PathTemplate`, `JsonKind`. They are public API of the core from then on; the existing `show` lists stay.

5. **Two barrels, no overlap.** `lib/typed_openapi_core.dart` is the old `typed_openapi.dart` without `cli`, `emit` and `generate`, with `show` lists. `lib/typed_openapi.dart` exports five symbols: `TypedOpenApiCli`, `ApiLibrary`, `ModelLibrary`, `OutputWriter`, `OutputChanges`. A programmatic user imports the two libraries; `doc/programmatic_api.md` shows it.

6. **Tests follow the code.** The test folders of the moved `lib/src` folders move with them (137 files, 1,173 tests). `emit`, `generate`, `cli` and `quality` stay (31 files, 352 tests and one skip). Three tests sit in an engine folder but need the generator and move the other way: `ir/event_text_data_test.dart` to `emit/`, `check/spec_checker_names_test.dart` and `diagnostics/sarif_code_scanning_test.dart` to `cli/`. The generator's and the tool's tests depend on both packages.

7. **Shared test code lives in `typed_openapi_test_support`.**
   - `Fixtures`: the 20 YAML fixture specs and overrides files, moved from `test/emit/fixtures`, read with `Fixtures.read(name)` / `Fixtures.path(name)`. The directory is found through the package configuration (`Isolate.resolvePackageUriSync`), so it does not depend on the directory a test runs in. This works on the VM only; the tests that read fixtures are VM tests.
   - `TempDir`, and `SizeLimits` with its two helpers `MethodScanner` and `MeasuredMethod`. `SizeLimits` was 304 lines; as library code it must obey the 300-line limit, so it is split in its own commit before the move.
   - `NormalizedFixture`: a spec read from text and normalized for a client, through the core's public API only (`spec`, `client`, `diagnostics`, `build`, `reported`, `reportedOf`, `codes`). The engine's `IrFixture` extends it with the internal `IrContext` and `lockOf`; `IrContext` is not exported and is not going to be. The generator's tests use `NormalizedFixture` as `fixture.spec` and `fixture.client` where they used `fixture.context.spec`.
   - Dependencies: `test_support` depends on `typed_openapi_core`, and the core has `test_support` as a dev dependency. The cycle resolves in the workspace and the core's `pub publish --dry-run` accepts it (checked); pub ignores dev dependencies of a hosted package.

8. **A size ratchet per package.** Each package has `test/quality/size_limits_test.dart` with its own allowlists and the unchanged limits (300 lines in `lib/`, 500 in tests, 40 per method). The old allowlists are split by path: the core takes 4 files and 21 methods and the permanent exemption `diagnostics/diagnostic_code.dart`; the generator takes 3 files and 5 methods and an empty permanent set. That is 26 method entries, not 25 as the plan brief said; none is added or removed. The ratchet scans the package it runs in, so `test_support` is covered by review only (open question 3).

9. **`ir_robustness_test` scans its own package.** It extracts the spec literals of the test files to build IRs from them. In the core it sees the core's tests only: 218 of the 233 literals of today's single package, and its floors (80 probes, 120 fixtures, 80% of the counts when it was written) still hold. The 15 literals in the generator's tests are covered by those tests themselves. Documented in the test and in `CLAUDE.md`.

10. **Lockstep versions; publish order core, client, typed_openapi, dio.** The four publishable packages carry one version (0.0.1 now) and each asks for `^<that version>` of the others it uses. A tool test pins both (new, in `typed_openapi_tool`). `publish.yml` gains the tag `typed_openapi_core-v*`. Its comment "bump only what changed" is replaced: a release bumps all four. The generator's CHANGELOG is still the one `corpus semver` reads (output changes are the generator's); the core has its own short CHANGELOG.

11. **Documentation stays with the generator.** `doc/`, `README.md` and `README.ua.md` stay in `packages/typed_openapi`, which users install. The core gets a short README and CHANGELOG (what it is, who it is for, a `SpecChecker` example, the link to the generator). Only the two imports of `doc/programmatic_api.md` change.

12. **CI covers the new packages.** `ci.yml` formats, analyzes and tests `typed_openapi_core` and formats `typed_openapi_test_support`, dry-runs the core before the generator; `nightly.yml` tests the core on beta; `workflows_test.dart` pins both. The tool, the corpus, the fuzz and `corpus semver` run as before.

13. **Execution as small commits.** Each is a `refactor(...)` (or `test`, `ci`, `docs`), builds, passes `dart analyze packages` and its tests, is formatted, and leaves the generated output byte-identical. The one commit that moves 395 files is mechanical and scripted; it needs a transitional `export` of the core from `typed_openapi` so that the tool, which imports the generator barrel, still builds; the next commit moves the tool to the core and removes the export. The final state has no re-export. A refactor is never mixed with a behaviour change.

## Calls made after measuring (author's calls)

- **The move is scripted and was replayed.** The recipe in the plan (moves, import rewriting, the barrel loop) was run on a scratch copy of `main`: `dart analyze packages` clean, core +1173, generator +352 ~1 (1,525 together: today's 1,523 plus the two ratchet tests the split makes four from two), tool +206 (today's 203 plus three new tests), `corpus check` "40 clients, 38 generated, 27759 files; 0 differences from the lock." in 6 minutes, 200 fuzz seeds with 0 problems, and 186 files of the 20 fixture clients identical to `main`'s.
- **`NormalizedFixture` instead of exporting `IrContext`.** Exporting an internal context for the sake of one test helper would put it in the public API; a base class in `test_support` that uses public symbols only keeps the surface small and lets the generator's tests drop their dependency on the IR internals.
- **`Fixtures` by package URI, not by relative path.** The tests of two packages read the same files; a relative path would depend on the directory `dart test` runs in. The cost is that the reading tests cannot run in a browser; they never did (they read files).
- **The 16 symbols are listed, not derived.** They come from running `dart analyze` and exporting what the generator needs; the plan has the loop so that a symbol added later by a different order of work is found the same way.
- **Tests that duplicate the analyzer are not added.** Boundaries (no `src` import across packages, no import of the generator from the core) are checked by `implementation_imports` and by the dependency lists; a test would only repeat them.

## Constraints

- Dart 3.10 floor (`>=3.10.0 <4.0.0`) for all packages; no `Flutter`.
- CLAUDE.md quality limits (300 / 500 / 40 lines, 5 parameters, nesting 3), doc comments on every public member of `lib/` (including `test_support`), no `// ignore:`, English only.
- Deterministic output: a golden comparison of generated files before and after is part of the gates.
- `corpus.lock` is not edited; if `corpus check` reports a difference the change is wrong.
- Git history is kept: files move with `git mv` in a commit that changes them as little as possible.
- No network in tests; `corpus check` fetches specs on the first run only.

## Out of scope

- Moving the client core, the Dio transport or the conformance suite.
- A public API review of the core (which symbols should be public in 0.1.0). The split exports what the generator needs and what was exported before; trimming is M13.
- Publishing, tags and pub.dev automated publishing settings for the new package (done by hand with the first release, as the others).
- Translating the new README (`README.ua.md` for the core).

## Left to the builder

- The wording of the core's README, CHANGELOG and the doc-comment of the two barrels.
- The order of the lines inside a `show` list or an import block (the formatter and `directives_ordering` decide).
- Doc comments of the new library classes (`Fixtures`, `NormalizedFixture`) beyond the signature given in the plan.
- Whether a moved test file needs a new `import` line style for relative helpers; they keep their relative paths because tests and helpers move together.

## Open questions (author's defaults)

1. **Git consumers.** The README's quick start lists `typed_openapi_client` and `typed_openapi_dio` as git dependencies because neither is on pub.dev. The generator now needs `typed_openapi_core` the same way. Default: the README gets a third git block for the core; whether pub resolves a git package whose sibling is a hosted constraint is the same open point as for the client and Dio, and is settled at the first publication.
2. **Method entries.** The brief said 25 method allowlist entries; there are 26 (21 + 5). Default: keep all 26.
3. **`test_support` has no size test.** Default: the review checks `wc -l` of its files (the largest has 300 lines). Alternative: the core's ratchet also scans `../typed_openapi_test_support`, which adds one test.
4. **Should `corpus semver` also watch the core?** Default: no. An output change is a `corpus.lock` or golden change, which `semver` already sees whichever package caused it; the lockstep test keeps the versions equal.
5. **Unpublished sibling constraints.** Default: `^0.0.1` between published packages, `any` for packages that are `publish_to: none` or depend on an unpublished sibling only from `dev_dependencies` of the tool (as `typed_openapi: any` in the tool today).
6. **`HANDOFF.md` is dated 2026-10-13.** Default: add the M12b row and leave the rest stale as it is; refreshing it belongs to the M13 plan.
