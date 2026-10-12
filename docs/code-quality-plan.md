# Code quality cleanup plan

Date: 2026-10-12. Based on [code-quality-review.md](code-quality-review.md) (findings,
metrics, sources). The rules this plan enforces are in the "Code quality
rules" section of `CLAUDE.md`.

Goal: bring `lib/` and `test/` within the size limits (file 300 lines, test
file 500, method 40) by decomposition, with **no change in behaviour and no
change in generated output**, without getting in the way of the M9 work.

Non-goals: new features, new diagnostics, API changes, renaming public types,
formatting sweeps.

## Status

- **Phase 0 (guard rails) and phase 1 (safe now) are done** (2026-10-12):
  the ratchet tests (`test/quality/size_limits_test.dart` in both packages),
  `yaml_composer.dart` 810 -> 78 lines, `override_applier.dart` 667 -> 76,
  `override_loader.dart` 612 -> 116, `override_resolver.dart` 450 -> 98,
  `model/operation.dart` 467 -> 68, `normalizer.dart` 383 -> 202,
  `schema_shape_rules.dart` 341 -> 7 (one rule per file),
  `object_reader.dart` 342 -> 278, `operation_parser.dart` 314 -> 288, and
  the tests of `yaml_composer` and `override_applier` split. Test totals are
  unchanged (the ratchet adds two tests per package).
- **Files over the limit in `lib/`: 20 -> 11** (9 in the generator, 2 in the
  runtime; plus the permanent exemption `diagnostic_code.dart`). Methods over
  40 lines in the allowlists: 59 -> 48 in the generator.
- **Waiting for M9** (phase 2 and the rest of phase 1): everything under
  `ir/`, `emit/`, `config/`, `generate/` and the runtime `dio/`.

## 1. Coordination with the M9 session

M9 (the operation emitter) is owned by another session ("OpenAPI Dart codegen
research"). State as of 2026-10-12, from its reply:

- M9 is at the planning stage. Branch `m9-impl` in
  `.claude/worktrees/agent-aa53a6701e5825da8` is a scratch implementation that
  checks the plan and is never merged. Only branch `docs/m9-plan` goes to
  main, after the user approves the plan. M9 itself is built later from the
  plan in a new worktree; a merge happens only on the user's word. No ETA.
- Files M9 will probably touch, so **frozen for this plan until M9 merges**:
  `ir/{ir,ir_builder,ir_context,names,operation_builder,api_names}.dart`,
  `emit/*`, `config/{config_loader,generation_config}.dart`,
  `diagnostics/diagnostic_code.dart`, `check/spec_checker.dart`,
  `cli/generate_command.dart`, `parse/openapi_parser.dart`, the runtime
  `dio/`, `request/`, `params/`, and the tests next to them.
- Confirmed safe to start now: `load/yaml_composer.dart` and `overrides/*`.
- `generate/output_writer.dart` waits for the M9 session's confirmation: M9
  makes `generate` write the API files too.
- Rules of engagement: this plan never edits the M9 worktree; each phase below
  names the files it touches; the M9 session sends the list of its new files
  over the limits when it merges, and they go into the exemption list instead
  of being split mid-milestone.
- Both sessions edit `CLAUDE.md`. The docs changes of this plan (CLAUDE.md,
  `docs/**` translation, the review and this plan) are committed on `main`
  before M9 merges, with the user's approval, so that M9's fast-forward merges
  do not collide with uncommitted work.

## 2. Safety net (before any code moves)

A refactor here is correct only if all of these hold after each step:

1. `dart analyze packages` prints "No issues found!".
2. Tests of both packages pass (`dart test` in each; the runtime also with
   `-p chrome` for runtime changes).
3. `dart format lib test bin` changes 0 files on a second run.
4. Generated output is byte-identical. The existing golden tests
   (`test/emit/goldens`, `test/emit/generated_code_test.dart`) cover the
   emitters. For the IR stage, dump the IR of every fixture with the hidden
   `dart run typed_openapi ir` command before and after the step and `diff`
   the two files (fixtures: `test/emit/fixtures/*.yaml`).
5. Public API is unchanged: the `show` lists in `lib/typed_openapi.dart` and
   `lib/typed_openapi_runtime.dart` are not edited by a refactor commit.

A step that cannot meet 1-5 is not committed.

## 3. Phases

Effort: S under half a day, M about a day, L several days (one agent-session
each, including review).

### Phase 0: guard rails (new files only, safe now)

| Step | What | Files | Effort |
| --- | --- | --- | --- |
| 0.1 | Ratchet test: walks `lib/` and `test/`, fails on a file over its limit that is not in the allowlist, and on an allowlisted file that grew; the allowlist is a `const Map<String, int>` (path -> current lines) in the test. | new `packages/typed_openapi/test/quality/size_limits_test.dart` (a mirror for the runtime package) | S |
| 0.2 | Method-length check in the same test, approximated from indentation (a method ends at the closing brace with the same indent), with an allowlist for the 35 current offenders, same ratchet rule. | same file | S |
| 0.3 | After 0.1, the review's section 6 points at the test as the single source of the exemption list. | `docs/code-quality-review.md` | S |

The ratchet makes the rules hold: a file over the limit may only shrink, and
a new one over the limit cannot appear. The M9 session's new files get their
own allowlist entries once it merges.

### Phase 1: safe now (no overlap with M9)

| Step | Target (lines now) | Split into | Effort |
| --- | --- | --- | --- |
| 1.1 | `load/yaml_composer.dart` (810) | stack and node building; budget and depth accounting; keys and tags | M |
| 1.2 | `overrides/override_applier.dart` (667) | one applier per kind (operations, schemas, nullable handling) behind the same `OverrideApplier` | M |
| 1.3 | `overrides/override_loader.dart` (612) | readers per section (operations, schemas) | M |
| 1.4 | `overrides/override_resolver.dart` (450) | address resolution vs conflict detection | S |
| 1.5 | `model/operation.dart` (467), 14 types | one sealed family per file, `model/` barrel unchanged | S |
| 1.6 | `parse/object_reader.dart` (342), `parse/operation_parser.dart` (314) | extract what a method-length check flags first, then re-measure | S each |
| 1.7 | `normalize/normalizer.dart` (383), `normalize/rules/schema_shape_rules.dart` (341) | pass runner vs edit application; one rule per file | S each |
| 1.8 | Test files over 500 in these areas: `override_applier_test`, `yaml_composer_test` | split by behaviour, shared builders to `test/helpers/` | S each |

### Phase 2: after the M9 session confirms (frozen files)

| Step | Target | Gate | Effort |
| --- | --- | --- | --- |
| 2.1 | `generate/output_writer.dart` (896): `OutputLock`, `OutputRecovery`, `OutputInstaller`, `OutputManifest`, `OutputWriter` as the orchestrator | M9 confirms its changes to the writer, or M9 merged | L |
| 2.2 | `ir/ir.dart` (733): one family per file (`declaration`, `field_ir`, `operation_ir`, ...) | M9 merged | S |
| 2.3 | `ir/schema_mapper.dart` (2196): see section 4 | M9 merged | L |
| 2.4 | `config/config_loader.dart` (780): readers for `defaults`, a client, `severity`/`rules`/`types` | M9 merged | M |
| 2.5 | `ir/ir_builder.dart` (534), `ir/operation_builder.dart` (565), `ir/schema_shapes.dart` (446) | M9 merged | M each |
| 2.6 | `emit/union_emitter.dart` (416), `emit/model_emitter.dart` (379), `emit/enum_emitter.dart` (long `write`) | M9 merged | M each |
| 2.7 | Runtime: `json/json_reader.dart` (422), `dio/dio_request_sender.dart` (378) | M9 merged | M each |
| 2.8 | Remaining test files over 500 (`ir_builder_test`, `model_library_test`, `operation_builder_test`, `cli_test`, `generate_command_test`, ...) | M9 merged | S each |

Every step moves its target out of the allowlist (or lowers its number) in
the same commit.

### Phase 3: what is left

- Methods still over 40 lines after phase 2: take the list from the ratchet
  test (step 0.2), a loop with a `switch` with an `if` that builds a
  diagnostic inside is the usual shape; move the body of the branch into a
  method named for what it does.
- `!`, `late` and the three-level ternary chains from the review's P3.
- The staged lints from section 7 of the review (the list is at the bottom of
  `analysis_options.yaml`): enable one at a time, fix its findings in the same
  commit, keep `dart analyze packages` clean. The six `strict-*` findings and
  the `@immutable` annotations (24 findings) go first.

## 4. `SchemaMapper` sequence (step 2.3)

The riskiest step: 2196 lines, one class, state set in fields before a call.
Order matters; each sub-step is a separate commit that passes the safety net.

1. **State first, no moves.** Replace `_direction`, `_patchTarget` and
   `_replacing` with a small immutable `MappingScope` passed down as a
   parameter. Nothing else changes. If a field cannot be passed down (it is
   truly shared, like `_pending`), say so in a comment on the field.
2. **Helper classes out.** Move `_Pending`, `_Field`, `_FieldNotes`,
   `_Variant` to `mapping_state.dart` (public inside `src`, not exported).
3. **Naming out.** `declaration_names.dart`: `_claim`, `_helperName`,
   `_memberName`, `_additionalName`, `nameDeclarations`, `_referenceName`,
   `_tokensName`, `_componentKey`. Constructor takes what it needs, no
   back-reference to the mapper.
4. **Enum out.** `enum_mapper.dart`: `_enum`, `_valueName`, `_numberName`,
   `_enumKind`.
5. **Model out.** `model_mapper.dart`: first cut `_model` (151 lines) into
   steps (merge parts, report ineffective overrides, build fields, build
   the declaration), then move it with `_merged`, `_notesOf`, `_constraintsOf`,
   `_isTriState`.
6. **Union out.** `union_mapper.dart`: first cut `_union` (about 300 lines)
   into named steps (collect branches, choose dispatch, name variants, build),
   then move it with the subtype helpers.
7. **Facade.** What stays in `schema_mapper.dart` is `typeOf`,
   `typeOfComponent`, `_map`, `_component`, `_inline`, `_declare`: under 300
   lines. Update the architecture paragraph of `ir/` in `CLAUDE.md`.

Cutting a method into steps (5 and 6) is its own commit before the move, so
the diff of the move is pure relocation.

## 5. Per-step protocol

1. Check the step's files against the freeze list in section 1; if one is
   frozen, stop and ask the M9 session.
2. Run the safety net on the untouched tree and keep the IR dump / goldens.
3. Do the step as a separate `refactor(typed_openapi): ...` commit: no feature,
   no fix, no renamed public member, no reformatting of other code.
4. Run the safety net again and compare; update the allowlist and the
   architecture paragraph in `CLAUDE.md` if the structure changed.
5. Report: lines before/after of each touched file, longest method now.

Rollback: every step is one commit, so `git revert <sha>` undoes it. A step
whose output differs by a single byte is reverted, not patched forward.

## 6. Open decisions for the user

1. Commit the docs changes on `main` now (CLAUDE.md, the `docs/**` translation,
   the review and this plan), so the M9 merges are not blocked?
2. Start with phase 0 and phase 1 now (no overlap with M9)?
3. For files M9 will add over the limits: exempt them in the allowlist when it
   merges and split them in phase 3, or require M9 to meet the limits first?
