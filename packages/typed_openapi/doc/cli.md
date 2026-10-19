# Command line

`typed_openapi` has three commands: `check` reads specs and reports problems, `generate` writes the Dart clients, and `baseline` records the problems you accept. All of them read `typed_openapi.yaml` from the working directory, and none of them calls the network.

```sh
dart run typed_openapi check
dart run typed_openapi generate
dart run typed_openapi baseline create
```

`typed_openapi` is not on pub.dev yet, so `dart pub global activate typed_openapi` does not work. From a checkout of the repository, `dart pub global activate --source path packages/typed_openapi` installs the `typed_openapi` executable; then replace `dart run typed_openapi` with `typed_openapi`.

```text
$ typed_openapi --help
OpenAPI 3.x to Dart client generator.

Usage: typed_openapi <command> [arguments]

Global options:
-h, --help    Print this usage information.

Available commands:
  baseline   Accept the current diagnostics, or remove entries that no longer match.
  check      Check specs and report diagnostics without generating code.
  generate   Check specs and generate the clients without errors.
```

> **Note:** A hidden `ir` command prints the intermediate representation of a client as JSON. It exists for the generator's own tests, is not listed in `--help`, and its output format is not a public contract.

## check

`typed_openapi check [options] [client...]` loads the config, reads every selected client's spec and overrides, runs the normalizer and the IR builder, and prints the diagnostics. It writes nothing.

| Option | Default | Meaning |
| --- | --- | --- |
| `-c`, `--config` | `typed_openapi.yaml` | Path to the config file. |
| `--format` | `text` | `text`, `json`, `sarif` or `github-actions`. |
| `--show-baselined` | off | Also list the diagnostics the baseline accepts, marked `[baselined]`. |
| `--strict-baseline` | off | Make stale baseline entries (TOA822) errors, whatever level the config gives them. |

```text
$ typed_openapi check
warning TOA501 missing-path-parameter: The path /products/{id} has {id}, but this operation declares no path parameter "id"; it is added as a required string path parameter.
  --> specs/shop.yaml:30:7
  at #/paths/~1products~1{id}/get
  fix: Declare each at the source as {name: <name>, in: path, required: true, schema: {type: string}}.
warning TOA301 duplicate-enum-value: The enum repeats "toys"; the repeats are removed and the first occurrence of each value is kept.
  --> specs/shop.yaml:42:13
  at #/components/schemas/Category/enum
  fix: Remove the repeated values at the source. In NestJS, give the enum its own schema with `enumName` (the CLI plugin option `autoFillEnumName` sets it) instead of spreading several TypeScript enums into one list.
warning TOA201 bool-required: Property "name" says "required: true", the OpenAPI 2 way; OpenAPI 3 lists required properties in the "required" array of the object, so the name is moved there.
  --> specs/shop.yaml:46:40
  at #/components/schemas/CreateProduct/properties/name/required
  fix: Add "name" to "required" of the object schema and remove "required" from the property.
errors: 0, warnings: 3, infos: 0
```

Each diagnostic has a header (`severity code slug: message`), a `-->` line with `file:line:column`, an `at` line with the JSON pointer, and a `fix:` line when the tool has advice. The last line is the summary; with a baseline it ends with `, baselined: N`.

## Client arguments

Positional arguments select clients by their name in the config. Without arguments every client runs.

```sh
dart run typed_openapi check shop billing
```

A name that is not in the config prints `Unknown client: nope.` followed by the usage and exits with `64`.

## Formats

| Format | Use it for | Output |
| --- | --- | --- |
| `text` | people | The layout above. Control characters and bidirectional marks in spec text are neutralised, so a spec cannot inject escape sequences into your terminal. |
| `json` | scripts | `{"diagnostics": [...], "summary": {"error", "warning", "info", "baselined"}}`. Each diagnostic has `code`, `name`, `severity`, `message`, `file`, `pointer`, `line`, `column`, `fix`, `related` and `baselined`. |
| `sarif` | code scanning | SARIF 2.1.0, see [CI](ci.md#sarif). |
| `github-actions` | workflow annotations | One `::error`, `::warning` or `::notice` line per diagnostic, see [CI](ci.md#github-actions-annotations). |

```sh
dart run typed_openapi check --format json | jq '.summary'
```

```json
{"error": 0, "warning": 3, "info": 0, "baselined": 0}
```

> **Note:** In `json` and `sarif` the text of the spec is kept as it is. Only `text` and `github-actions` neutralise it.

## generate

`typed_openapi generate [options] [client...]` runs the same checks as `check`, then writes every client that has no errors. A client with errors is skipped with `Skipped shop: its check reports errors; fix them and run generate again.`, so one broken spec does not stop the others, and the exit code is `1`. A config error does not skip a client. A bad config value (TOA902) is reported as an error and the default is used, so `generate` still writes the clients whose specs have no errors and exits `1`. This was run with `input_suffix` equal to `patch_suffix` and a non-string `group` under `defaults.naming`: the client was generated and the exit code was `1`. An invalid `severity` level on a client behaves the same, while a client in the same config whose spec file is missing is skipped. Check the exit code in CI, and run `check` first if you want nothing written on a bad config. When the check passes but the output cannot be written (TOA830, TOA831), the line is `Skipped shop: see the error above.`

| Option | Default | Meaning |
| --- | --- | --- |
| `-c`, `--config` | `typed_openapi.yaml` | Path to the config file. |
| `--force` | off | Replace files in an output directory that `typed_openapi` did not write or that changed since it wrote them. Each is reported as TOA833. |
| `--break-lock` | off | Take over a lock when it cannot be told whether the run that holds it still goes. Replaces no file. |
| `--locked` | off | Check each client against its API snapshot in `typed_openapi.lock` instead of updating the file. A client whose API differs is not written (TOA834). For CI. |

```text
$ typed_openapi generate
Generated shop in lib/src/api/shop: 7 files, 7 written, 0 deleted.
API of shop: first snapshot in typed_openapi.lock.
$ typed_openapi generate
Generated shop in lib/src/api/shop: 7 files, 0 written, 0 deleted.
API of shop since typed_openapi.lock: 0 breaking, 0 switch-breaking, 0 wire, 0 additive, 0 docs.
```

The second run writes nothing, because the output is the same. Ownership, locks and `--force` are explained in [Generated output](generate_output.md).

### The API lock

`generate` keeps the public API of every client it writes in `typed_openapi.lock`, next to `typed_openapi.yaml`: one section per client, with every type, field, enum value, variant, method and argument under a stable identity (the spec location of a schema, the `operationId` or `METHOD /path` of an operation). Commit the file, also when the generated code is git-ignored, as you would `pubspec.lock`. Each run prints, for each client written, how many changes since the lock fall in each category:

| Category | Meaning |
| --- | --- |
| `breaking` | Code that uses the client may no longer compile: a type, member or method was removed or renamed, a type changed, or something became required. |
| `switch-breaking` | A new enum value, union variant, status variant or event appeared; only an exhaustive `switch` over a sealed type breaks. With `exhaustive: false` this is `additive`. |
| `wire` | The Dart API is the same, but a JSON key, a path, a parameter style, a media type or the statuses changed. |
| `additive` | A new type, method, or optional field or argument. |
| `docs` | Only doc comments or `@Deprecated` changed. |

A run of some clients keeps the sections of the others, and drops the section of a client the config no longer declares. `generate --locked` changes no lock: a client whose API differs from its section, or has none, is skipped with TOA834, and so is a section of a client the config no longer declares. A lock that cannot be read, such as one with merge-conflict markers, is TOA835 and the run writes no client: resolve the conflict, or delete the file to start from the current API. This file is not the lock of an output directory (`.<output>.typed_openapi.lock`), which only keeps two runs apart.

## baseline

A baseline is a file of accepted diagnostics for one client. Both subcommands take `-c`/`--config` and client names, and need a `baseline:` path on the client.

| Subcommand | What it does |
| --- | --- |
| `baseline create` | Writes the client's baseline file from its current errors and warnings. |
| `baseline prune` | Removes the entries that no longer match a diagnostic. |

```text
$ typed_openapi baseline create
errors: 0, warnings: 0, infos: 0
Wrote specs/shop.baseline.yaml: 3 entries accept 3 diagnostics.
$ typed_openapi baseline prune
errors: 0, warnings: 0, infos: 0
Pruned specs/shop.baseline.yaml: removed 1 entries, 2 left.
```

Without a `baseline:` key on any selected client, `baseline create` prints `No client has a "baseline" in the config.` with the usage and exits `64`. See [Baseline](baseline.md) for the file format and an adoption workflow.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | No errors. Warnings and infos do not change it. |
| `1` | At least one error that a baseline does not accept (also: a client was skipped by `generate`, or a spec could not be read by `baseline`). |
| `64` | Usage error: unknown client, unknown option, missing subcommand, or no client with a baseline. |
| `78` | The config file could not be loaded (not found, or not readable as a config at all). |

A config that loads but has errors, such as an invalid `severity` level together with a missing spec, exits `1`, not `78`.

```text
$ typed_openapi check -c nothing.yaml
error TOA901 config-not-found: Config file nothing.yaml does not exist.
  --> nothing.yaml
  fix: Create typed_openapi.yaml, or pass its path with --config.
errors: 1, warnings: 0, infos: 0
$ echo $?
78
```

Diagnostics a baseline accepts do not count toward the exit code. The CLI never calls `exit()` from library code, so you can also run it from Dart code; see [Programmatic API](programmatic_api.md).

## See also

- [Configuration](configuration.md): what goes in `typed_openapi.yaml`.
- [Diagnostics](diagnostics.md): every code in the output.
- [Baseline](baseline.md) and [Generated output](generate_output.md): the two write commands in depth.
- [Programmatic API](programmatic_api.md): the same pipeline as a library.
- [CI](ci.md): using the formats and exit codes in a pipeline.
