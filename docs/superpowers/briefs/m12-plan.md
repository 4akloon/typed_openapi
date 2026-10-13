# Brief: write the M12 implementation plan for typed_openapi (API snapshot, change report, name lock)

## Output
Write the plan to `docs/superpowers/plans/2026-10-13-m12-evolution.md`. Write everything in English, as the repo rule in CLAUDE.md requires. Commit it on a branch `docs/m12-plan` in your worktree, with the message `docs: plan M12 API snapshot and change report`. Do not merge or push.

## Method
Use the superpowers:writing-plans skill: invoke it with the Skill tool and follow it exactly.

The repo rule "Rules for plans" in docs/roadmap.md requires every code block to be verified:
- Build each task on a scratch branch.
- After each task, run `dart test` in all workspace packages, including `packages/typed_openapi_tool` from M11, then `dart analyze packages` and `dart format`. A second format run must change 0 files.
- Replay all the tasks from `main` (MAIN_SHA) using only the plan's blocks, and record the test counts after each task.
- The plan branch holds only the plan file.

Use the M11 plan (docs/superpowers/plans/2026-10-13-m11-corpus.md) as the model for the format. Read only its header, its Global Constraints and one task.

## Read first
- **Spec (binding):** docs/superpowers/specs/2026-10-13-m12-evolution-design.md, 7 decisions made by the user.
- **Requirements:** docs/requirements.md, R14.1 and R14.2.
- **docs/roadmap.md:** the M12 row, every row parked for M12, and the "Parked from the M9/M10/M11 reviews" tables. Handle a row in a task if it falls under M12; otherwise re-park it with a reason.
- **CLAUDE.md:** all of it, especially:
  - the `ir/` naming (`NameScope`, `TypeClaims`, the order of claims);
  - `emit/`;
  - `generate/` (`OutputWriter`, the manifest, the lock file of the run, which is a different thing from the new name lock);
  - `config/`;
  - the code quality rules: the size ratchet, where allowlisted units never grow.
- **M11's tools:** `packages/typed_openapi_tool`, `corpus.lock` and the corpus job. M12 must keep them green. A change of generated output updates `corpus.lock`, with an "Output changes" CHANGELOG entry and a version bump, as the M11 semver check requires.

## Scope (from the spec)
1. **API snapshot from the IR.**
   - It covers types with their kind; fields and constructors, with types and required-ness; union variants; enum values; methods, with parameters, return types and status variants; and wire facts: JSON keys, path, method, style, media types and statuses.
   - Each entry has a stable identity: a spec location, or an operationId / `METHOD /path`.
   - The snapshot is deterministic and uses no analyzer.
2. **The five categories:** breaking, switch-breaking, additive, wire and docs. The classifier needs a complete rule table, with a test for each rule.
3. **`exhaustive: true|false` config key.**
   - It goes on a client or in `defaults`; the default is `true`.
   - With `false`, the bases of all enums, unions, status types and event unions become `abstract interface`.
   - A schema override still wins.
   - The diff knows the mode: a new variant of a non-exhaustive type is additive.
   - Check that generated code with `false` analyzes clean. A `switch` over a non-exhaustive type then needs a `default`.
4. **`typed_openapi diff [clients]`.**
   - It compares the lock with what the current spec would give, and writes nothing.
   - Formats: `text`, `json` and `markdown`.
   - `--fail-on breaking|switch-breaking|wire|any` controls the exit code; by default it only reports.
   - It can also compare two snapshot files directly.
   - `generate` prints one line per client with the count of changes in each category.
5. **The name lock.**
   - A locked name stays with its identity.
   - New identities take free names. A locked name that cannot be kept is a diagnostic: use the next free code in the naming area, and document it.
   - `--fresh-names` ignores the lock.
   - This touches the IR naming order. Make room first with refactors that leave the output byte-identical.
   - Prove the core property with a test: adding a schema to a spec never renames an existing type. Also prove it on the corpus: for several real specs, add an inline schema or operation and show that the snapshot keeps every old name.
6. **`typed_openapi.lock` next to the config.**
   - One file with a section per client. The format is deterministic and diffable.
   - `generate` updates it; `diff` compares against it.
   - `generate --locked` checks against the lock without writing it; a difference is an error.
   - Decide how the lock relates to the per-output manifest. Document it.
7. **A schema renamed in the spec** is reported as removed plus added (breaking), with a ready `name:` override that keeps the old Dart name.

## Gates
- Both or all suites, `analyze` and `format` after each task.
- The M11 corpus job runs end to end and its `check` passes:
  - `corpus.lock` is unchanged unless a task deliberately changes the output;
  - every generated client analyzes clean with `exhaustive: false` too, either through a scratch config or a temporary mode of the corpus tool.
- Run `diff` on real spec history. For 3–4 corpus specs, take two pinned versions from their repositories (for example two tags of the Stripe or GitHub spec) and report the category counts. Use those runs to sanity-check the classifier.
- The M11 fuzz stays green.

## Constraints
- Allowlisted units never grow; new code goes into new files.
- No `// ignore:`.
- Never use or look for the user's private company spec.
- English only.
- Do not dispatch subagents.
- Use the network only to download the public spec versions for the history check.
- Budget: about 5 hours. If time runs short, finish whole verified tasks in order and list the rest under a clear heading.

## Return
Return only:
- status, branch, commit and worktree;
- the task titles with test counts;
- the corpus numbers, and the `diff` history results by category;
- the defects found and fixed;
- open questions, each with the default you adopted.
