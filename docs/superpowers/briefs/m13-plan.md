# Brief: write the M13 implementation plan for typed_openapi (documentation, lint, distribution, release readiness)

## Output
Write the plan to `docs/superpowers/plans/<date>-m13-product.md`. Everything is in English, per the repo rule in CLAUDE.md. Commit it on a branch `docs/m13-plan` in your worktree as `docs: plan M13 documentation and product`. Do not merge or push.

## Method
Use the superpowers:writing-plans skill: invoke it with the Skill tool and follow it exactly.

Under "Rules for plans" in docs/roadmap.md, every code block must be verified before it goes into the plan:
- Build each task on a scratch branch.
- After each task, run `dart test` in every workspace package, `dart analyze packages` and `dart format`. A second format run must change 0 files.
- Replay all tasks from `main` (MAIN_SHA) using only the plan's blocks, and record the test counts after each task.
- The plan branch holds only the plan file.

Use the latest plan in docs/superpowers/plans/ as the format model. Read only its header, Global Constraints and one task.

## Read first
- **Spec (binding):** docs/superpowers/specs/2026-10-13-m13-product-design.md, with 8 decisions the user made.
- **Requirements:** docs/requirements.md R15.1, R15.2, R15.5, R15.6.
- **docs/roadmap.md:** every row parked for M13 and the "Parked from the … reviews" tables. Handle each row, or re-park it with a reason.
- **CLAUDE.md:** all of it, especially:
  - `config/`, `overrides/`, `diagnostics/`, the reporters and the presets (`normalize/`);
  - the code quality rules: the size ratchet, where allowlisted units never grow.
- **The tools from M11 and M12:** `packages/typed_openapi_tool`, `corpus.yaml`, `corpus.lock`, the CI layers, and `typed_openapi.lock`/`diff` from M12.

## Scope (from the spec)
1. **Docs generated from code**, with a CI check that they are fresh:
   - the catalog of diagnostic codes from `DiagnosticCode`;
   - the `x-` registry;
   - the JSON Schemas of the config and of the overrides file.

   The support matrix and the recipes are written by hand. Each support-matrix row points to its fixture or test, and a test checks that the referenced fixture or test exists.
2. **No `build_runner`.** Write a recipe for `generate` run by hand, in CI and in pre-commit, plus `generate --locked`. Add a roadmap row: "after 1.0".
3. **`typed_openapi lint <spec>`.**
   - It needs no config.
   - The preset is detected from the spec, or set with `--preset`.
   - It accepts the same formats as `check`.
   - Each diagnostic carries a backend recipe.
   - It is advisory by default (exit 0), and `--fail-on error|warning` makes it strict.
4. **Release workflow.** On a tag, build `dart compile exe` binaries for linux-x64, linux-arm64, macos-x64, macos-arm64 and windows-x64, and attach them with their sha256 to the GitHub Release. Add a GitHub Action that runs `lint` or `check` and emits annotations or SARIF. Validate the workflows with `actionlint`. Nothing is released or tagged by the plan.
5. **Recipes for NestJS, FastAPI, Spring (springdoc) and ASP.NET (Swashbuckle).**
   - Cover the codes that fire on each framework's specs in the M11 corpus.
   - Each recipe cites a primary source and its version.
   - Align the preset hints with the recipes; this closes the parked aspnet TOA401 and nestjs TOA303 rows.
6. **JSON Schemas generated from one catalog of keys.** A test checks that `ConfigLoader` and `OverrideLoader` accept exactly what the schemas describe. Document the `# yaml-language-server: $schema=` line. Do not submit to SchemaStore: that is an outward action left to the user, so write the submission text into the release checklist.
7. **An invalid client value falls back to `defaults`.** TOA902 names the value it applied. Add a CHANGELOG entry.
8. **Release readiness for 0.1.0.** Provide a release checklist in docs, and make `dart pub publish --dry-run` clean for both packages at 0.1.0. The version bump is part of the plan; the tag and the publish are left to the user.

## Gates
- All suites, `analyze` and `format` after each task.
- The M11 corpus job and the M12 `diff` stay green. Update `corpus.lock` and the CHANGELOG if output changes.
- Run `lint` on every corpus spec and report the counts by preset.
- Generated docs are fresh, and CI checks them.

## Constraints
- Allowlisted units never grow.
- No `// ignore:`.
- Never use or look for the user's private company spec.
- English only.
- Do not dispatch subagents.
- Use the network only for the public sources the recipes cite.
- Budget: about 5 hours. If time runs short, finish whole verified tasks in order and list the rest.

## Return
Return only:
- status, branch, commit and worktree;
- task titles with test counts;
- the corpus, lint and docs numbers;
- the defects found and fixed;
- open questions, each with the default you adopted.
