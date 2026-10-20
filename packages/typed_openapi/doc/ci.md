# CI

`typed_openapi check` is made for CI: it reads files only, never touches the network, exits non-zero on new errors, and speaks the formats GitHub understands. This guide shows what each exit code, format and flag does, and ends with a workflow you can copy.

```sh
dart run typed_openapi check --strict-baseline --format github-actions
```

## Exit codes

The codes are listed in [Command line](cli.md#exit-codes). For CI what matters is:

- `0`: no errors. Warnings and infos never fail the build.
- `1`: at least one error that the baseline does not accept, or a client was skipped by `generate`.
- `64` (usage) and `78` (config could not be loaded) are mistakes in the command or the config; they also fail the job.

To make warnings fail, raise their level in the config (`severity: {TOA501: error}`, see [Configuration](configuration.md#severity)); there is no `--fatal-warnings` flag.

## GitHub Actions annotations

`--format github-actions` prints one workflow command per diagnostic. GitHub turns each into an annotation on the file and line in the pull request.

```text
$ typed_openapi check --format github-actions
::notice file=specs/shop.yaml,line=6,col=3,endLine=24,endColumn=1,title=TOA554 operation-untagged::No operation of the spec has a tag, so all operations are in DefaultApi.%0Aat #/paths%0Afix: Tag the operations at the source, or set group_by to path or single in the config.
errors: 0, warnings: 0, infos: 1, baselined: 2
```

| Part | Content |
| --- | --- |
| Command | `::error`, `::warning` or `::notice` (for an info). |
| Properties | `file`, `line`, `col`, `endLine`, `endColumn` (when the position is known) and `title`, which is the code and the slug. |
| Message | The text, then `at <JSON pointer>` and `fix: ...`, one per line (a line break is `%0A`). |
| Related locations | Each is a `::notice` of its own with the title `<code> <slug> (related)`. |
| Baselined | With `--show-baselined`, a `::notice` titled `... (baselined)`. Otherwise not printed. |
| Summary | The last line is the plain summary of the text format. |

**What is escaped.** Spec text is attacker-controlled in a pull request from a fork, so it can never start a workflow command or inject one:

- Control characters (an ESC byte, bidirectional marks) are neutralised before printing, as in the text format.
- In the message, `%`, CR and LF are written `%25`, `%0D` and `%0A`, as the runner expects, so a `::error::` line inside a description stays inside the message.
- In the properties (`file`, `title`), `:` and `,` are escaped too (`%3A`, `%2C`).

## SARIF

`--format sarif` prints SARIF 2.1.0 for [GitHub code scanning](https://docs.github.com/en/code-security/code-scanning). Alerts then appear in the Security tab and on pull requests, and a fixed problem closes its alert.

```sh
dart run typed_openapi check --format sarif > typed_openapi.sarif
```

The report is one run of the tool `typed_openapi`. It guarantees what code scanning needs:

- **Rules.** One per code that occurs, sorted by id, each with `name` (the slug), a short and a full description, `help` text and the default level. The help says how the level can be changed: `severity: {<slug>: off}` for most codes, "can be raised, not lowered" for fixed codes, "cannot be changed" for config codes.
- **Levels.** `error`, `warning`, and `note` for an info.
- **Locations.** Every result with a file has a physical location with a 1-based region. A file with no position (a missing baseline file) is located at its first line. A result without any file is located at the **config file**, so code scanning has somewhere to show it. The JSON pointer is the logical location. Files inside the working directory are relative URI references; outside it they are `file:` URIs.
- **Fingerprint.** `partialFingerprints["typedOpenapi/v1"]` is the first 16 hex digits of a SHA-256 of the code, file, pointer and message. It does not include the line, so moving a problem within a file keeps its alert. (It is not the baseline fingerprint; the baseline is separate.)
- **Related locations.** For example the override that introduced the problem, as `relatedLocations`.
- **Baseline.** Accepted diagnostics are left out. With `--show-baselined` they are results with an external suppression, `Accepted in the baseline.`

The command exits `1` when there are errors, which would skip a later upload step: write the file with `|| true` and upload with `if: always()`, as the workflow below does.

> **Note:** SARIF and JSON keep the spec's text as it is. Only the text and the `github-actions` formats neutralise it.

## Gating with a baseline

If the spec already has problems, [accept them in a baseline](baseline.md) and let CI fail only on new ones. `--strict-baseline` also fails the job when the baseline lists a problem that is gone (TOA822), so the baseline shrinks as you fix things.

```text
$ typed_openapi check --strict-baseline
error TOA822 baseline-entry-stale: No diagnostic matches this entry (TOA301 at @/schemas/Category#/enum); the problem is gone.
  --> specs/shop.baseline.yaml:10:5
  at #/entries/1
  fix: Run `typed_openapi baseline prune` to update the baseline.
errors: 1, warnings: 0, infos: 1, baselined: 2
```

A pull request that fixes a problem runs `baseline prune` and commits the smaller file; one that adds a problem either fixes it or runs `baseline create` in the open, where a reviewer sees the new entry.

## Checking that generated code is up to date

`generate` is deterministic and writes nothing when nothing changed (see [Generated output](generate_output.md#determinism)). So running it in CI and looking at git tells you whether the committed client matches the spec:

```sh
dart run typed_openapi generate
test -z "$(git status --porcelain -- lib/src/api)" || { echo "generated code is out of date"; exit 1; }
```

`git status --porcelain` is used instead of `git diff --exit-code` so that a **new file** (untracked) fails the check too. For a spec change that adds a value to an enum, it prints:

```text
 M lib/src/petstore/.typed_openapi.json
 M lib/src/petstore/models/pet_status.dart
```

`generate` also checks first, so a spec with new errors fails there, with the same exit code `1`.

> **Gotcha:** `generate` refuses an output that holds files it did not write (TOA830). On a fresh checkout every file is the committed one with the committed hash, so this works; do not edit generated files by hand.

## A ready-to-copy workflow

Save it as `.github/workflows/typed_openapi.yml`. It assumes `typed_openapi` is a dev dependency of the project at the repository root and the clients are in `lib/src/api`; change the path to your `output`. The YAML was parsed to check its syntax; `github/codeql-action/upload-sarif@v4` is the action's name at the time of writing, so check its current major version.

```yaml
name: typed_openapi

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  check:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write   # upload SARIF to code scanning
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
      - run: dart pub get

      # The gate: errors and stale baseline entries fail the job, and show up
      # as annotations on the changed files.
      - name: Check the specs
        run: dart run typed_openapi check --strict-baseline --format github-actions

      # The same findings in code scanning. Runs even when the gate failed.
      - name: Write the SARIF report
        if: always()
        run: dart run typed_openapi check --format sarif > typed_openapi.sarif || true
      - name: Upload the SARIF report
        if: always()
        uses: github/codeql-action/upload-sarif@v4
        with:
          sarif_file: typed_openapi.sarif
          category: typed_openapi

      # The committed clients must be what the specs generate.
      - name: Check that the generated code is up to date
        run: |
          dart run typed_openapi generate
          if [ -n "$(git status --porcelain -- lib/src/api)" ]; then
            echo "::error::The generated clients are out of date. Run 'dart run typed_openapi generate' and commit."
            git status --short -- lib/src/api
            exit 1
          fi
```

What each step does:

| Step | Effect |
| --- | --- |
| `check ... --format github-actions` | Annotates the files and fails on new errors and stale baseline entries. |
| `check --format sarif ... \|\| true` | Writes the report even when there are errors. |
| `upload-sarif` | Sends it to code scanning (needs `security-events: write`; on a private repository, code scanning must be enabled). |
| `generate` + `git status` | Fails when the committed client is not what the spec generates. |

## Lint in the backend pipeline

The team that writes the spec can run [`lint`](cli.md#lint) on the file its framework generates, with no `typed_openapi.yaml` and no generated code. This job belongs in the backend repository. It assumes an earlier step leaves the spec at `openapi.json`. It needs the Dart SDK, which the backend project does not otherwise need.

`typed_openapi` is not on pub.dev yet, so the job checks out its repository and activates the package from that checkout; once it is published, those two steps become `dart pub global activate typed_openapi`. The explicit `PATH` step is there so the job does not depend on whether `setup-dart` puts the pub cache on it. Pin `ref:` of the second checkout to a tag or a commit.

```yaml
name: openapi-lint

on:
  pull_request:

permissions:
  contents: read

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      # Build or export openapi.json here, with the backend's own tool.
      - uses: dart-lang/setup-dart@v1
      - uses: actions/checkout@v4
        with:
          repository: 4akloon/typed_openapi
          path: typed_openapi_src
      - run: dart pub global activate --source path typed_openapi_src/packages/typed_openapi
      - run: echo "${PUB_CACHE:-$HOME/.pub-cache}/bin" >> "$GITHUB_PATH"
      - run: typed_openapi lint --format github-actions --fail-on error openapi.json
```

Findings are annotations on the changed files, and an error fails the job; warnings are shown but do not. Use `--fail-on warning` once the spec has none, and `--preset` to name the framework when detection says `generic`. The `lint` command line and its annotations were run locally; the workflow file, including the second checkout and the `PATH` step, was not run on GitHub.

### Without Dart: the action and the binaries

A backend project that has no Dart SDK can run the same `lint` from a release binary. Each release `typed_openapi-v<version>` (the tag of the generator) attaches five archives and the file `SHA256SUMS`:

- `typed_openapi-<version>-linux-x64.tar.gz`
- `typed_openapi-<version>-linux-arm64.tar.gz`
- `typed_openapi-<version>-macos-x64.tar.gz`
- `typed_openapi-<version>-macos-arm64.tar.gz`
- `typed_openapi-<version>-windows-x64.tar.gz`

Each archive holds the executable (`typed_openapi.exe` on Windows) and the `LICENSE`. The action downloads the archive of the runner, checks its SHA-256 against `SHA256SUMS` and runs the command:

```yaml
      - uses: 4akloon/typed_openapi/action@typed_openapi-v0.1.0
        with:
          command: lint
          spec: openapi.json
          version: 0.1.0
          fail-on: error
```

| Input | Default | Meaning |
| --- | --- | --- |
| `command` | `lint` | `lint` (one spec) or `check` (the specs of a config). |
| `spec` | | The file to lint. Required for `lint`, refused for `check`. |
| `preset` | | The framework preset for `lint`. Refused for `check`. |
| `fail-on` | | The lowest level that fails `lint`. Refused for `check`. |
| `config` | `typed_openapi.yaml` | The config for `check`. |
| `format` | `github-actions` | `text`, `json`, `sarif` or `github-actions`. |
| `version` | | The release to download, such as `0.1.0`. |
| `executable` | | A binary to run instead of downloading one. |
| `working-directory` | `.` | Where the command runs. |

A relative `executable` is resolved against `working-directory`. `SHA256SUMS` is published in the same release as the archives, so the check detects a corrupt or mismatched download but does not protect against a compromised release. `version` or `executable` is required: there is no "latest", so a pipeline never changes under you. The first release is not out yet, so this step does not run until it is. The scripts and the action are tested on Linux with a fake executable and validated by actionlint; macOS and Windows are first exercised by the first release.

## See also

- [Command line](cli.md): options and exit codes.
- [Baseline](baseline.md): accepting existing problems.
- [Generated output](generate_output.md): ownership, locks and what to commit.
- [Diagnostics](diagnostics.md): every code and how to set its level.
- [Automation](automation.md): `diff`, `generate --locked`, a Makefile and a git hook.
