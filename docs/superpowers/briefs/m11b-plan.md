# Brief: write the M11b implementation plan for typed_openapi (transport split)

## Output
Write the plan to `docs/superpowers/plans/2026-10-19-m11b-transport-split.md`, in English. Commit it on the branch you are on (`docs/m11b-design`, worktree `.worktrees/m11b-design`) with the message `docs: plan M11b transport split`, ending with the line `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Do not merge or push.

## Method
Use the superpowers:writing-plans skill: invoke it with the Skill tool and follow it exactly.

The repo rule "Rules for plans" in docs/roadmap.md requires every code block to be verified:
- Build each task on a scratch branch (a scratch worktree under `.worktrees/m11b-scratch`, removed when done).
- After each task run `dart test` in every workspace package (`packages/typed_openapi`, the client core, the Dio adapter, the transport tests, `packages/typed_openapi_tool`), the Chrome runs (dart2js and dart2wasm) of the packages that have them, `dart analyze packages` and `dart format` (a second run must change 0 files).
- Replay all tasks from `main` (MAIN_SHA = `git rev-parse main` at the start) using only the plan's blocks, and record the test counts after each task.
- The plan branch holds only the plan (and the spec and brief already on it).
Use the M11 plan (docs/superpowers/plans/2026-10-13-m11-corpus.md) as the format model; read only its header, Global Constraints and one task.

## Read first
- **Spec (binding):** docs/superpowers/specs/2026-10-19-m11b-transport-split-design.md, approved by the user. Read all of it, including "Calls made after the builder check".
- **CLAUDE.md:** all of it, especially the Runtime section, `emit/` for operations, `generate/`, the code quality rules (size ratchet: allowlisted units never grow; files over 300 lines in `lib/`; no `// ignore:`), and the Tools section (`corpus.lock`, semver, the fuzz).
- **The current runtime:** packages/typed_openapi_runtime (lib/src/dio/*, request/*, result/*, sse/*, test/ and its helpers). Every file that imports `package:dio` must be accounted for in the plan: list them in a table (file, what it becomes, where it moves).
- **The generator side:** where generated code names `Dio`, `DioRequestSender`, `package:dio`, `DartNames.takenTypeNames`, the golden files and fixtures, `test/emit/programs/calls.dart.txt`, the generated-client test, `packages/typed_openapi_tool` (corpus package pubspec template, round trip, fuzz), CI workflows and `test/ci/workflows_test.dart`, docs and READMEs that name the runtime package (grep the whole repo for `typed_openapi_runtime`).
- **docs/roadmap.md:** the rows parked for the runtime, the exemption list in docs/code-quality-review.md (moved files keep their entry under the new path), the Windows and web notes.

## Scope (from the spec)
1. Rename `packages/typed_openapi_runtime` to `packages/typed_openapi_client` with `git mv`; remove its Dio dependency; `CancelSignal`, `TransportException`, `ClientTransport`, `TransportRequest`, `TransportResponse`, `ClientSender` (replaces `DioRequestSender`), core body encoding (JSON, form, multipart with an injectable boundary, text, bytes, `FileUpload`), core progress counting, SSE reconnector on `TransportException`/`CancelSignal`, `OperationInfo` as a request field.
2. New `packages/typed_openapi_dio` with `DioTransport` (spec decision 8 and the "Dio's error path is kept" call).
3. Generator: groups and root take a `ClientTransport`, generated imports, `takenTypeNames`, goldens, `corpus.lock`, CHANGELOG "Output changes" entry (the top section is `Unreleased`, so no version bump).
4. New `packages/typed_openapi_transport_tests` (`publish_to: none`): a loopback `dart:io` `HttpServer` (ephemeral port, started through `spawnHybridUri` in the browser) with the routes the spec lists, and `TransportConformance`, a suite that takes a `ClientTransport` factory and runs the same cases against any adapter; `typed_openapi_dio` runs it on the VM and in Chrome (dart2js, dart2wasm), with the web skips the spec allows, each with a stated reason. Port the existing `test/dio/*` tests of the old runtime: each either moves to core tests on a fake transport, or becomes a conformance case, or is deleted with a reason in the task.
5. CI (ci.yml, nightly.yml, `workflows_test.dart`), the publish dry-run for the two published packages, `dart pub workspace` entries, docs and READMEs (the Dio-specific parts go to the adapter's README), CLAUDE.md, roadmap, HANDOFF.

## Gates (every task and at the end)
- All suites green, `dart analyze packages` clean, `dart format` 0 changes.
- The M11 corpus check passes with the updated `corpus.lock` (only hashes of generated files change; diagnostics and round-trip counts stay equal); the generated golden diff shows only the changes the spec's Constraints allow.
- Every corpus client still analyzes clean and the round trip's `failures` stay 0.
- The M11 fuzz (200 seeds) stays green.
- A real Dio instance with an interceptor (an `onError` that retries a 401 with a new token) works through `DioTransport` against the loopback server: include it as a conformance-or-adapter test.
- Behaviour on the wire is unchanged: the ported M9/M10 tests assert the same URLs, headers and bytes.

## Constraints
- Allowlisted units never grow; new code goes into new files; no `// ignore:`; English only; code rules of CLAUDE.md (Dart 3.10 dot shorthands, OOP with no top-level functions except `main`, doc comments on public members).
- Do not dispatch subagents. Never push. Use the network only if the corpus spec cache is missing; it is at /home/genius/projects/typed_openapi/packages/typed_openapi_tool/.dart_tool/corpus (symlink or copy it into the scratch worktree so `corpus check` runs offline).
- Environment: `export PATH=$HOME/fvm/versions/3.47.6/bin:$HOME/fvm/versions/3.47.6/bin/cache/dart-sdk/bin:$PATH`; `CHROME_EXECUTABLE=/usr/bin/google-chrome`.
- Budget: about 5 hours. If time runs short, finish whole verified tasks in order and list the rest under a clear heading.

## Return
Return only (and write the same to `/home/genius/projects/typed_openapi/.superpowers/sdd/m11b-plan-report.md`): status, branch, commit and worktree; the task titles with test counts; the corpus numbers; defects found and fixed; open questions, each with the default you adopted.
