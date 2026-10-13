# M13: documentation and product — design

**Date:** 2026-10-13.

**Requirements:** see [requirements.md](../../requirements.md).
- R15.1 [MUST]: CLI and programmatic API; `build_runner` is an open question.
- R15.2 [MUST]: a config with a JSON Schema and clear validation errors.
- R15.5 [MUST]: documentation: an OpenAPI support matrix, an `x-` registry, a catalog of diagnostic codes, and recipes for NestJS, FastAPI and Spring.
- R15.6 [SHOULD]: an advisory `lint` for the backend.

**Roadmap:**
- the M13 row;
- the parked rows targeted at M13: the preset hints for aspnet (TOA401) and nestjs (TOA303), and an invalid client value that falls back to the built-in default.

**Earlier stages:**
- [M3](2026-10-11-m3-normalizer-design.md): presets and hints.
- [M5](2026-10-12-m5-baseline-severity-design.md): `check`, reporters, SARIF.
- [M11](2026-10-13-m11-corpus-design.md): the corpus that the recipes draw on.
- [M12](2026-10-13-m12-evolution-design.md): `generate --locked`.

These decisions were taken by the user in a grilling session.

## Decisions

1. **Documentation is Markdown in the repository, and what code can derive is generated from it.**
   - The documents live in the package's `doc/`, and they render on GitHub and on pub.dev.
   - A tool generates three of them, and CI fails when a generated file is stale:
     - **the catalog of diagnostic codes**, from `DiagnosticCode`: code, slug, default level, what it means, an example, and how to fix it at the source or by override;
     - **the `x-` registry**: every extension the generator reads, with its effect;
     - **the JSON Schemas of the config and the overrides file** (decision 6).
   - The OpenAPI support matrix and the recipes are written by hand. Each support-matrix row points at the fixture or test that proves it, and a test checks that every referenced fixture or test exists.

2. **No `build_runner` before 1.0 (R15.1).**
   - The product is the CLI plus the programmatic API.
   - A recipe shows `typed_openapi generate` run by hand, in CI, or in a pre-commit hook, with `generate --locked` (M12) as the CI check.
   - The generator owns its output (the manifest, the lock, the atomic swap). That model does not fit a builder, so `build_runner` goes to the roadmap as after 1.0, on request.

3. **`typed_openapi lint <spec>` for the backend (R15.6).**
   - It works with no `typed_openapi.yaml`.
   - The preset is detected from the framework's traces in the spec, or given with `--preset`.
   - It writes the same formats as `check`: `text`, `json`, `sarif` and `github-actions`.
   - Each diagnostic shows the recipe for the backend framework, not a Dart override.
   - It is advisory by default and exits with 0. `--fail-on error|warning` makes it strict.

4. **Distribution to backend teams without a Dart SDK.**
   - On a release tag, CI builds `dart compile exe` binaries for linux-x64, linux-arm64, macos-x64, macos-arm64 and windows-x64. They are attached to the GitHub Release with their sha256.
   - A small GitHub Action downloads the binary, runs `lint` or `check`, and outputs annotations or SARIF.
   - Dart users install as before, with pub or `dart install`.

5. **The recipes are grounded in the corpus and cite their sources.**
   - For NestJS, FastAPI, Spring (springdoc) and ASP.NET (Swashbuckle), the recipes cover the codes that actually fire on that framework's specs in the M11 corpus.
   - Each recipe gives the fix in the backend code, with a primary source: the framework's documentation or its library code, with the version.
   - The preset hints in diagnostics are aligned with the recipes. This closes the parked rows on the aspnet and nestjs hints.
   - Backend toolchains are not run in CI.

6. **The JSON Schemas are generated from one catalog of keys (R15.2).**
   - The keys of the config and of the overrides file are declared once in code, each with its name, type, allowed values, default and description.
   - `typed_openapi.schema.json` and `typed_openapi.overrides.schema.json` are generated from that catalog.
   - A test checks that `ConfigLoader` and `OverrideLoader` accept exactly what the schemas describe. A key without a schema fails that test.
   - The documentation shows the `# yaml-language-server: $schema=...` line, and the schemas are submitted to SchemaStore. That submission is an outward action, so the user confirms it.

7. **An invalid client value falls back to `defaults`.**
   - An invalid value in a client acts as if the key were absent from the client. The value from `defaults` applies, and if `defaults` has none, the built-in default applies.
   - TOA902 names the value that was applied.
   - This changes behaviour for configs that already have such an error, so it goes in the CHANGELOG.

8. **M13 ends with readiness for 0.1.0, not 1.0.**
   - The deliverables are:
     - a release checklist;
     - a clean `dart pub publish --dry-run` for both packages at 0.1.0;
     - the release workflow, which builds the binaries and the Action.
   - The tag and the publication are done by the user.
   - 1.0 comes after feedback from the first users and after the decision on an HTTP abstraction beyond Dio, which the roadmap lists as "before 1.0".

## Out of scope

- `build_runner`.
- A documentation website.
- Docker images.
- Running backend frameworks in CI.
- The 1.0 release.
