# Handoff: where typed_openapi stands and how to continue

Last updated: 2026-10-13 (M11 merged). Read this first on a new device or in a new Claude session. Session memory and scratch directories do not travel; this file and the repository hold everything needed.

## State

| Milestone | Design | Plan | Code |
|---|---|---|---|
| M1–M11 | merged | merged | **merged** (M10: `bd1cdc3`, M11: `3842bd7`) |
| M11b transport split: client core, `typed_openapi_dio`, conformance suite | [spec](specs/2026-10-19-m11b-transport-split-design.md) | [plan](plans/2026-10-19-m11b-transport-split.md) | implemented on branch `feat/m11b-transport-split` (merge pending) |
| M12 evolution: API snapshot, change report, name lock | [spec](specs/2026-10-13-m12-evolution-design.md) | brief ready: [briefs/m12-plan.md](briefs/m12-plan.md); M12's spec still says `typed_openapi_runtime` (the spec: "the runtime package's own API", line 77) and need updating to `typed_openapi_client` before planning | next |
| M13 documentation, lint, distribution, 0.1.0 readiness | [spec](specs/2026-10-13-m13-product-design.md) | brief ready: [briefs/m13-plan.md](briefs/m13-plan.md) | after M12 |

**Other open work:**
- **Branch `fix/m9-residuals`** (pushed to origin) fixes three parked findings of the M9 final re-review:
  - a multipart media type with control characters;
  - a `security` field that is not a list;
  - date and date-time default ranges.

  It was reviewed and is clean. It branches from `1f6ee26`. Merge it now that M11 is merged, and resolve the roadmap rows if they conflict.
- **Branch `docs/full-guides`** (local, not pushed; worktree `../typed_openapi-docs`) holds the full user documentation: both package READMEs, the generator and runtime guides, the framework guides, the troubleshooting guide and the root README. It was checked against the code by two reviewers. Merging it is the user's decision; `README.ua.md` is not translated yet. Open points: `ApiLibrary` is not exported, so the programmatic API cannot write a whole client; `sse.md` and `event_streams.md` are over 300 lines; the real defects the writers found (TOA504 cannot be cleared by an override, the TOA203 hint is glued to the last line of a multi-line fix, `additionalProperties: true` makes no field, a `name` override on a multipart-only schema is ignored silently, internal id "R6.8" in the date-time decode hint, the `SseOptions.wait` doc comment says `Future.delayed`) are not fixed.
- **M11 plan, Task 14.** The SARIF schema is fetched and pinned by hash, never vendored, because its OASIS license does not clearly allow redistribution.
- **Required status checks.** The GitHub ruleset "Protect main" has none yet. M11 is merged: add its CI job names as required checks.

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

- **Public repo:** https://github.com/4akloon/typed_openapi. Only `main` and `fix/m9-residuals` are pushed.
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
