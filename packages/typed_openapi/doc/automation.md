# Automation

`typed_openapi` is a command you run, not a build step: `generate` reads the spec and the config and writes plain Dart files you commit. There is no `build_runner` builder; the [roadmap](https://github.com/4akloon/typed_openapi/blob/main/docs/roadmap.md) lists one as an item "After 1.0". Until then the recipes below cover the same need with a task, a git hook and a CI job. Every command and output on this page was produced by running it on a scratch project with one client named `grund` (the [sample of the 3.1 recipe](client_for_grund.md)), except where a recipe says it was not run.

## The loop

When the spec changes, run these steps in order:

| Step | Command | What it tells you |
| --- | --- | --- |
| 1 | `dart run typed_openapi diff` | What the new spec does to the API of the client, by category, before anything is written. |
| 2 | `dart run typed_openapi generate` | Writes the client and records the new API in `typed_openapi.lock`. |
| 3 | `git add` and `git commit` | Commits the spec, the lock and the generated files together. |

Here the enum `ItemStatus` gained the value `archived`. `diff --fail-on switch-breaking` exits `1`, because code that switches on the enum no longer compiles until it handles the new value:

```text
$ dart run typed_openapi diff --fail-on switch-breaking
grund: 0 breaking, 1 switch-breaking, 0 wire, 0 additive, 0 docs.
  switch-breaking: Enum value ItemStatus.archived was added.
$ echo $?
1
$ dart run typed_openapi generate
errors: 0, warnings: 0, infos: 0
Generated grund in lib/src/grund: 7 files, 1 written, 0 deleted.
API of grund since typed_openapi.lock: 0 breaking, 1 switch-breaking, 0 wire, 0 additive, 0 docs.
```

`generate` does not fail on a change of the API; `diff --fail-on` is how you decide that a category stops a pull request. The categories are in [Command line](cli.md#diff). `diff --format markdown` writes the same report for a pull request comment.

## A task for the team

A `Makefile` gives everyone the same two commands. `api` regenerates; `api-check` is what CI and a reviewer run: the spec is valid and the committed lock matches it.

```make
.PHONY: api api-check

# Regenerate the clients and the lock; commit what changes.
api:
	dart run typed_openapi generate

# What CI runs: the specs are fine and the lock matches them.
api-check:
	dart run typed_openapi check --strict-baseline
	dart run typed_openapi generate --locked
```

```text
$ make api-check
dart run typed_openapi check --strict-baseline
errors: 0, warnings: 0, infos: 0
dart run typed_openapi generate --locked
errors: 0, warnings: 0, infos: 0
Generated grund in lib/src/grund: 7 files, 0 written, 0 deleted.
API of grund since typed_openapi.lock: 0 breaking, 0 switch-breaking, 0 wire, 0 additive, 0 docs.
```

`--strict-baseline` makes a stale [baseline](baseline.md) entry an error; without a baseline it changes nothing.

## A git hook

A hook that runs only when a commit touches the config, a spec or the lock keeps the check out of unrelated commits. Save it as `.githooks/pre-commit`, make it executable, and enable the folder once per clone:

```sh
#!/bin/sh
# Check and verify the lock when a commit touches the config, a spec or the lock.
if git diff --cached --name-only | grep -Eq '^(typed_openapi\.yaml|typed_openapi\.lock|specs/)'; then
  dart run typed_openapi check --strict-baseline && dart run typed_openapi generate --locked
fi
```

```sh
chmod +x .githooks/pre-commit
git config core.hooksPath .githooks
```

Change `specs/` to the folder of your specs. With a spec change that was not generated, the commit stops:

```text
$ git commit -m change
errors: 0, warnings: 0, infos: 0
error TOA834 api-lock-differs: typed_openapi.lock differs from the API of client "grund": 0 breaking, 1 switch-breaking, 0 wire, 0 additive, 0 docs. Run generate without --locked and commit the lock; typed_openapi diff lists the changes.
  --> typed_openapi.lock
  at #/clients/grund
errors: 1, warnings: 0, infos: 0
Skipped grund: its API differs from typed_openapi.lock (TOA834).
```

Run `make api` (or `dart run typed_openapi generate`), `git add` the lock and the generated files, and commit again. The hook above was run; the same hook as a [pre-commit](https://pre-commit.com) local hook is below, and that file was checked as YAML only, because `pre-commit` was not installed where this page was written:

```yaml
repos:
  - repo: local
    hooks:
      - id: typed_openapi
        name: typed_openapi check and lock
        entry: sh -c 'dart run typed_openapi check --strict-baseline && dart run typed_openapi generate --locked'
        language: system
        files: ^(typed_openapi\.(yaml|lock)|specs/)
        pass_filenames: false
```

## CI with generate --locked

`generate --locked` writes nothing to the lock. It compares each client with its section of `typed_openapi.lock` and refuses a client whose API differs (`TOA834`, an error, exit `1`). In CI that catches a pull request that changed a spec and did not commit the regenerated lock and code. It compares the API only, not the files: whether the committed generated code is what the spec produces is a separate check, `generate` followed by `git status`, shown in [CI](ci.md#checking-that-generated-code-is-up-to-date).

```yaml
name: typed_openapi

on:
  pull_request:

permissions:
  contents: read

jobs:
  api:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
      - run: dart pub get
      - name: Check the specs
        run: dart run typed_openapi check --format github-actions --strict-baseline
      - name: Check the lock
        run: dart run typed_openapi generate --locked
```

The two commands were run with exactly these arguments; the workflow file itself was not run on GitHub. A complete workflow with SARIF upload is in [CI](ci.md#a-ready-to-copy-workflow).

## A spec that lives in another repository

`typed_openapi` reads files on disk and never calls the network, so fetch the spec in the task, commit it, and regenerate from the committed copy:

```make
api:
	curl --fail --silent --show-error --output specs/grund.yaml "$(SPEC_URL)"
	dart run typed_openapi generate
```

`SPEC_URL` is the address of the spec in the other repository; pin it to a tag or a commit. Commit the fetched file with the lock and the generated code, so a reviewer sees what the new spec changed and CI never depends on the other repository. This recipe was not run: it is the same `generate` with a download in front of it.

## See also

- [Command line](cli.md): `diff`, `generate --locked` and the exit codes.
- [CI](ci.md): annotations, SARIF and a complete workflow.
- [Generated output](generate_output.md): what to commit and what `generate` refuses to overwrite.
- [Client for a 3.1 service](client_for_grund.md): the project this page was run on.
