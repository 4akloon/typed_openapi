# Implementer rules (template for every SDD task)

Copy this file into the plan's SDD workspace (`.superpowers/sdd/<plan>/implementer-rules.md`). Then replace `<WORKTREE>` and `<BRANCH>` with real values.

- **Where you work.** Work only in the worktree `<WORKTREE>`, on branch `<BRANCH>`. Stay on that branch and do not create new ones. Never `cd` into the main checkout.
- **Rules to follow.** Read CLAUDE.md first: its code quality rules, its Dart style rules and its strict lint set. The Global Constraints in the brief bind you too. Everything you write is in English.
- **How to use the brief.** A plan brief holds complete, pre-verified code, so transcribe it faithfully:
  - Create files from its blocks whole, and `git apply` its diffs from the worktree root.
  - Follow its TDD steps: run the failing test before the code, then make it green.
  - Use the exact names, values and tests it gives.
  - If a diff does not apply, or a test count differs from the brief, stop and report NEEDS_CONTEXT with the exact error. Do not improvise.

  A hardening brief has no pre-verified code: you write the fixes yourself, test-first.
- **Defects in earlier tasks.** Reviewers find defects in earlier tasks. Do not fix them unless your brief says so; they are scheduled separately.
- **Commands.**
  - Run `dart test` in every package the brief names, with the counts it gives. That includes the size ratchet in `test/quality/size_limits_test.dart`.
  - Run `dart format lib test bin`, or `lib test` in the runtime. A second run must change 0 files.
  - Run `dart analyze packages` from the root. It must print "No issues found!".
  - Never add `// ignore:`. Tests never use the network.
  - When the runtime changes, also run `dart test -p chrome` and `dart test -p chrome --compiler dart2wasm`.
- **Commits.** Commit as the brief says, with Conventional Commits. End the message with `Co-Authored-By: <your actual model name> <noreply@anthropic.com>`. Stage by explicit path. Do not push or merge.
- **Hard rules.** Never use the user's private company spec. Do not dispatch subagents. Self-review means reading your own diff.
- **Report.** Write the full report to the report file named in your dispatch: what you did, RED/GREEN evidence with commands and output, files changed, deviations and concerns. Then reply with only these:
  - status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT;
  - commits, as sha + subject;
  - a one-line test summary;
  - concerns;
  - the report path.
