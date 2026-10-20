# Handoff: where typed_openapi stands and how to continue

Last updated: 2026-10-20 (M13 done on its branch). Read this first on a new device or in a new Claude session. Session memory and scratch directories do not travel; this file and the repository hold everything needed.

## State

| Milestone | Design | Plan | Code |
|---|---|---|---|
| M1–M11 | merged | merged | **merged** |
| M11b transport split: client core, `typed_openapi_dio`, conformance suite | [spec](specs/2026-10-19-m11b-transport-split-design.md) | [plan](plans/2026-10-19-m11b-transport-split.md) | merged (`6d1d7d2`) |
| M12 evolution: API snapshot, change report, name lock | [spec](specs/2026-10-13-m12-evolution-design.md) | [plan](plans/2026-10-13-m12-evolution.md) | merged (`92007c1`) |
| M12b core split: `typed_openapi_core` (engine), `typed_openapi` (generator, CLI), `typed_openapi_test_support` | [spec](specs/2026-10-20-m12b-core-split-design.md) | [plan](plans/2026-10-20-m12b-core-split.md) | merged (`7de073d`) |
| M13 documentation, lint, distribution, 0.1.0 readiness | [spec](specs/2026-10-13-m13-product-design.md) | [plan](plans/2026-10-20-m13-product.md) | **done on branch `feat/m13-product`; not merged until the owner says so** |

## M13: where it stands

M13 is implemented on `feat/m13-product` (worktree `.claude/worktrees/m13-impl`). Nothing is merged to `main`, pushed, tagged or published. It adds: the `x-` registry and the config and overrides key catalogs with their generated JSON Schemas; the generated diagnostics and extensions references (`docs.dart`); `typed_openapi lint` with preset detection; the support matrix, the four framework recipes, the automation and grund guides; the release binaries, the composite action and `release.yml`; release readiness for `0.1.0` (pubspecs, examples, CHANGELOGs headed `## 0.1.0 - Unreleased`). Counts of the last full run: core +1961, generator +364 ~1, client +305, dio +54, tool +280.

**What remains for the owner** (all outward actions need an explicit yes):

1. Merge `feat/m13-product` into `main` (or open the pull request).
2. Release `0.1.0` by hand with [docs/release-checklist.md](../release-checklist.md): version and `Unreleased` headings, the "not on pub.dev" text (a grep step), the schema URLs pinned to the tag, the dry runs, the first publish by hand in the order core, client, `typed_openapi`, Dio, the tags, and the check of the binaries. Nothing in the repository tags or publishes by itself.
3. The SchemaStore submission (the text is in the checklist) is the owner's outward action; it waits for the tag.
4. The vendored YAML scanner: the linear-time fix is proposed upstream as dart-lang/tools#2658. A maintainer approved it, it waits for the upstream merge, and the CLA is signed. After the merge and a release, update `packages/typed_openapi_core/lib/src/load/yaml/` and the note in its `analysis_options.yaml`.
5. Required status checks: the ruleset "Protect main" has none yet; add the CI job names (now also `docs`, `actionlint` and `binary`).

**Verified and not verified.** Checked on Linux, by the test suites and by running the commands (the whole-branch gates run once more before the merge): the analyzer and formatter, the five test suites, `corpus check` and `corpus lint`, the fuzz, `docs.dart check`, the publish dry runs of the four packages, actionlint 1.7.12 (a pinned container image), `package.sh`, `install.sh` and `run.sh` through `release_scripts_test`. Never exercised: the macOS, Windows and arm64 builds of `release.yml`, and `release.yml` itself (it runs only on a real `typed_openapi-v*` tag), and the CI jobs added in M13 (`docs`, `actionlint`, `binary`, the corpus lint step), which have not run on GitHub yet, the composite action on GitHub, `install.sh` on macOS, the pub.dev sign-in and automated-publishing flow, the git-dependency install text, and the Chrome suites for this branch (only pubspecs and examples changed in the client and Dio packages). The framework hints cite sources read once on 2026-10-20 (dotnet/aspnetcore#60469, `@nestjs/swagger` 12.0.0 notes); re-read them before the release. `helpUri` is a fixed URL on `main`, not pinned to a tag. The `README.ua.md` files lack the new guides.

**Open questions of the plan (the default adopted in each case; the owner can overrule).** 15 of the plan's 17 are carried; items 16 and 17 are obsolete (the two Task 1 commits exist, and the counts are in the ledger of this branch).

1. Lint reports the codes of the loader, the version detector and the normalizer; the IR-stage codes (TOA453, TOA553, TOA651 ...) need a config and belong to `check`.
2. The NestJS `oneOf` plus `enum: [null]` shape (TOA303): its origin in `@nestjs/swagger` 11.2.0 was not verified in the source, so the hint states only what the 12.0.0 notes and the documentation say.
3. The `JsonReader.constant` version gate is parked again after `0.1.0`, with the reason in the roadmap. Lockstep versions are pinned by `lockstep_versions_test`.
4. The recipe-coverage test has no generic allowlist: every code that fires on a framework spec of the corpus is named in its recipe.
5. Schema URLs point at `main` in the docs and are pinned to the tag at release (a checklist step). `schema/` ships in the pub tarball.
6. CHANGELOG headings are `## 0.1.0 - Unreleased`; the checklist drops ` - Unreleased` at tagging.
7. "Not on pub.dev yet" stays in the docs; flipping it is a checklist step with a grep command.
8. The first publish is manual (automated publishing needs an existing package). For the first release only the tag `typed_openapi-v0.1.0` is pushed, for the binaries; its `publish.yml` run fails harmlessly.
9. Every archive is a `.tar.gz`, Windows included.
10. `linux-arm64` is cross-compiled on `ubuntu-24.04`; its smoke test is skipped.
11. The action needs `version` or `executable`; there is no "latest".
12. The SchemaStore overrides entry has an empty `fileMatch`, because the file can have any name.
13. The Chrome suites were not rerun for the release-readiness task.
14. The Swashbuckle corpus spec has no `ProblemDetails` schema, so it is not detected (`detects: false`); ASP.NET detection is 1 of 2, as the corpus expects.
15. Upload size: the dry runs include each package's `test/` directory (about 455 KB for the core); whether a `.pubignore` should leave it out is undecided (see the checklist).

**Other open work.**
- **M11 plan, Task 14.** The SARIF schema is fetched and pinned by hash, never vendored, because its OASIS license does not clearly allow redistribution.
- **`README.ua.md`** is not translated for the new guides.

## How a milestone is done

This process worked for M8–M10. It uses the superpowers skills: `writing-plans` and `subagent-driven-development`.

1. **Design.** Grill the user, one question at a time, each with a recommended option, in Ukrainian. Write the spec in English under `docs/superpowers/specs/` and commit it on main.
2. **Plan.**
   - An Opus agent in an isolated worktree writes the plan from a brief: see `briefs/`, and fill in `MAIN_SHA`.
   - Every block is verified, and all tasks are replayed from main using only the plan's blocks.
   - Bring the plan's open questions to the user. Then merge the plan into main.
3. **SDD.**
   - **Setup.** Create a worktree from main on a branch such as `feat/m11-corpus`. The workspace is `.superpowers/sdd/<plan>/` (git-ignored). It holds `progress.md` as the ledger, `global-constraints.md` copied from the plan, and `implementer-rules.md` from [briefs/sdd-implementer-rules.md](briefs/sdd-implementer-rules.md).
   - **Implement.** For each task, run the skill's `task-brief` script to make the brief, then dispatch a Sonnet implementer that transcribes it. One implementer at a time.
   - **Review.** Run each task review with Sonnet, on a frozen detached worktree of the task's head, in parallel with the next implementer. Give the reviewer named adversarial risks: injection and escaping, crashes on unresolved `$ref`s, silent fallbacks, determinism, the size ratchet.
   - **Harden.** Findings go to hardening tasks after the plan tasks (`9a`, `9b`, `9c`…), split by area. You write those briefs; they hold no pre-verified code. A finding that arrives while a hardening implementer runs is sent to it as an added item.
   - **Final review.** An Opus final review covers the whole branch and re-runs the corpus, the fuzz, and a comparison of operations lost from the previous milestone. Then one fix round and a scoped Sonnet re-review. Residuals are parked in `docs/roadmap.md` with a reason.
   - **Merge.** `git merge --no-ff` into main, re-run the tests on the merged tree, remove the worktree and the branch. Keep a copy of the ledger somewhere if you want it.
4. **Record every ruling** in the ledger as `Ruling: <what> — <why> — <cost if wrong>`.

## Rules the user set

- **Merging.** Merge a milestone into the local main as soon as its final review and fix round are clean, without asking again. Then write the next plan.
- **Outward actions need the user's explicit yes.** These include pushing to GitHub, tags, publishing to pub.dev, the SchemaStore submission, and creating issues or PRs. The user asked for the public repo and for the protection settings, and both are done.
- **Never use or look for the user's private company spec.** Fixtures are invented. The corpus uses only the public specs pinned in `corpus.yaml`, from M11 on.
- **Models.** Sonnet for implementers and reviewers, never Haiku. Opus for designs, plans and final reviews.
- **Language.** Talk with the user in Ukrainian. Write everything in the repository in English, except the intentional `README.ua.md` translations.
- **Code quality.** CLAUDE.md is binding. The size ratchet means `lib` files are at most 300 lines, test files at most 500, and methods at most 40. Allowlisted units never grow. No `// ignore:` anywhere.

## Repository

- **Public repo:** https://github.com/4akloon/typed_openapi. `main` is pushed; `feat/m13-product` is not.
- **Ruleset "Protect main":**
  - deleting `main` and force-pushing to it are blocked;
  - changes go through a PR: 0 approvals required, review threads must be resolved, merge or squash only;
  - admins bypass, so the owner's direct pushes still work.
- **Ruleset "Protect release tags":** tags matching `v*` and `typed_openapi*` can be created, updated or deleted only by admins.
- **Security:**
  - Dependabot alerts and security updates are on;
  - secret scanning and push protection are on;
  - the Actions token is read-only;
  - workflows on PRs from forks need approval.
