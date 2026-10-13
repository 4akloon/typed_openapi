# Baseline

A baseline is a file of diagnostics you have accepted for one client. With it, `typed_openapi check` and `generate` fail only on **new** errors, so you can adopt the tool on a spec that already has problems and keep it from getting worse.

```yaml
clients:
  shop:
    input: specs/shop.yaml
    output: lib/src/api/shop
    baseline: specs/shop.baseline.yaml   # one file per client
```

```text
$ typed_openapi baseline create
info TOA554 operation-untagged: No operation of the spec has a tag, so all operations are in DefaultApi.
  --> specs/shop.yaml:4:3
  at #/paths
  fix: Tag the operations at the source, or set group_by to path or single in the config.
errors: 0, warnings: 0, infos: 1
Wrote specs/shop.baseline.yaml: 3 entries accept 3 diagnostics.
$ typed_openapi check
info TOA554 operation-untagged: No operation of the spec has a tag, so all operations are in DefaultApi.
  --> specs/shop.yaml:4:3
  at #/paths
  fix: Tag the operations at the source, or set group_by to path or single in the config.
errors: 0, warnings: 0, infos: 1, baselined: 3
```

The three accepted warnings are hidden. The info is not: a baseline never hides an info.

## What a baseline can accept

A baseline accepts a diagnostic only when both hold:

- Its severity, **after** the client's [`severity` levels](configuration.md#severity), is `error` or `warning`. Infos are always shown.
- Its code is not a *fixed* code. Read errors, the override-file and baseline-file codes, the `generate` output codes (TOA830-TOA833) and the config codes (TOA901-TOA904) can never be accepted. [Diagnostics](diagnostics.md#severity-and-levels) lists them.

> **Gotcha:** The levels apply first. If you lower `TOA501` to `info` in the config, its baseline entry no longer matches (the diagnostic is an info now), becomes stale (TOA822) and `baseline prune` removes it. Choose one tool for a code: a level, or a baseline.

## File format

`baseline create` writes this file. You can read it, review it in a pull request and edit it by hand.

```yaml
# Diagnostics accepted for this client: typed_openapi check
# hides them. Written by `typed_openapi baseline create`;
# `typed_openapi baseline prune` removes stale entries.
version: 1
entries:
  - fingerprint: "61ee2300579e"
    code: "TOA201"
    anchor: "@/schemas/CreateProduct/properties/name#/required"
    message: "Property \"name\" says \"required: true\", the OpenAPI 2 way; ..."
  - fingerprint: "b87c2fe65078"
    code: "TOA501"
    anchor: "@/operations/GET ~1products~1{id}#"
    message: "The path /products/{id} has {id}, but ..."
```

| Key | Where | Meaning |
| --- | --- | --- |
| `version` | file | Must be the integer `1`. Anything else is TOA821 and the file is not used. |
| `entries` | file | A list of entries, sorted by code, anchor and fingerprint. |
| `fingerprint` | entry | Required: 12 lowercase hex digits. The only key used for matching, together with `count`. |
| `code`, `anchor`, `message` | entry | For the person reading the file. The message is the one the first accepted diagnostic had. |
| `count` | entry | How many diagnostics with this fingerprint the entry accepts. Written only when it is not `1`; at least `1`. |

An empty file, or one with only comments, is a baseline with no entries. A file that is not valid YAML, a `version` that is not `1`, or `entries` that is not a list is TOA821 and the whole baseline is ignored: every diagnostic of the client is shown. A bad entry (no valid fingerprint, a `count` below 1, not a mapping) is a TOA821 error and that entry is ignored. An unknown key and a repeated fingerprint (their counts add up) are TOA821 warnings.

```text
$ typed_openapi check
error TOA821 invalid-baseline: An entry needs a "fingerprint" of 12 lowercase hex digits; the entry is ignored.
  --> specs/shop.baseline.yaml:3:18
  at #/entries/0/fingerprint
warning TOA821 invalid-baseline: Unknown key "colour"; it is ignored.
  --> specs/shop.baseline.yaml:5:13
  at #/entries/1/colour
  fix: Allowed keys here: anchor, code, count, fingerprint, message.
```

A baseline path that does not exist is TOA820 (`Write it with typed_openapi baseline create, ...`). A directory in its place is TOA821. A baseline that cannot be written is TOA823.

## Fingerprints

A diagnostic matches an entry by its fingerprint: the first 12 hex digits of the SHA-256 of `[code, anchor, args]`.

- **code** is the `TOAnnn` id.
- **args** are the facts that make this finding this finding (for example the property name or the repeated value). They are fixed per code.
- **anchor** says where it is, written to survive edits elsewhere in the spec.

The message text, the line and the column are **not** part of the fingerprint. You can reword a message in a new release, reformat the spec or add paths above the problem, and the entry still matches. When a diagnostic is renamed in the source (a property `name` becomes `title`), it is a different finding: the old entry turns stale and the new diagnostic is shown.

### Anchors

When the place has a logical address, the anchor is `@<address>#<pointer>`. The address uses the same keys as the [overrides file](overrides.md), so it does not move with the file layout:

| Anchor | The place |
| --- | --- |
| `@/operations/GET ~1products~1{id}#` | an operation (`~1` is `/` in a JSON pointer) |
| `@/operations/GET ~1pets/parameters/query:limit#/schema` | a parameter the operation defines, then the pointer below it |
| `@/schemas/Category#/enum` | a `components.schemas` entry, then the pointer below it |
| `@/schemas/CreateProduct/properties/name#/required` | a property of a schema |

For a place with no address (a path-level parameter, a webhook, a node in the middle of nowhere) the anchor is the file relative to the baseline file's directory, then the pointer: `api.yaml#/info`. Moving the spec file or the baseline file then makes those entries stale.

## Matching and the report

`check` compares the client's diagnostics with the entries:

- An entry accepts up to its `count` diagnostics with its fingerprint. More than that: the extra ones are shown.
- Accepted diagnostics are hidden and counted in the summary (`baselined: 3`). `--show-baselined` prints them too, marked `[baselined]`, and they never affect the exit code.
- An entry that accepts more than the check finds is **stale**: TOA822.

```text
$ typed_openapi check --show-baselined
warning TOA501 missing-path-parameter [baselined]: The path /products/{id} has {id}, but ...
  --> specs/shop.yaml:6:7
  at #/paths/~1products~1{id}/get
  ...
errors: 0, warnings: 0, infos: 1, baselined: 3
```

### Stale entries

After you fix the duplicate enum value in the spec:

```text
$ typed_openapi check
warning TOA822 baseline-entry-stale: No diagnostic matches this entry (TOA301 at @/schemas/Category#/enum); the problem is gone.
  --> specs/shop.baseline.yaml:10:5
  at #/entries/1
  fix: Run `typed_openapi baseline prune` to update the baseline.
...
errors: 0, warnings: 1, infos: 1, baselined: 2
```

TOA822 is a warning, so the exit code stays `0`. To keep the baseline from holding on to fixed problems, run `check --strict-baseline`: it makes TOA822 an error whatever level the config gives it (even `off`), so CI fails until someone prunes.

```text
$ typed_openapi check --strict-baseline
error TOA822 baseline-entry-stale: No diagnostic matches this entry (TOA301 at @/schemas/Category#/enum); the problem is gone.
...
errors: 1, warnings: 0, infos: 1, baselined: 2
$ echo $?
1
```

An entry whose count is larger than what the check finds says `This entry accepts 3 diagnostics (...), but the check finds 2.`.

## baseline create

`typed_openapi baseline create [client...]` runs the check and writes the baseline of each client from its **current** errors and warnings. It replaces the file, so entries you removed by hand and entries that were stale are gone. Infos and fixed codes are not written; they are printed, as `check` would print them.

The file is written to a temporary file next to it and renamed, so an interrupted run never leaves a broken baseline. Missing directories are created.

## baseline prune

`typed_openapi baseline prune [client...]` reads the existing baseline and removes the entries that match nothing. An entry that matches fewer diagnostics than its `count` gets the smaller count. It adds nothing: new diagnostics stay unaccepted.

```text
$ typed_openapi baseline prune
errors: 0, warnings: 0, infos: 0
Pruned specs/shop.baseline.yaml: removed 1 entries, 2 left.
```

`prune` leaves the file alone, and prints the problems instead, when the baseline has a rejected entry (a TOA821 error: the rewrite would lose it) or when the spec could not be read.

## When the spec cannot be read

If a client's spec has a read error (invalid YAML or JSON, a `$ref` to a missing file, a missing `openapi` version), the check found too little for a baseline to mean anything. So:

- `check` reports the read error and **no** stale entries for that client.
- `baseline create` and `baseline prune` print the error, leave the file untouched and exit `1`.

```text
$ typed_openapi baseline prune
error TOA001 parse-error: Expected node content.
  --> specs/shop.yaml:2:1
errors: 1, warnings: 0, infos: 0
```

## Clients that share a baseline file

Two clients cannot name the same baseline file (compared after resolving the path, so `./x.yaml` and `x.yaml` are the same). Config loading reports TOA902, and `baseline create` and `baseline prune` write nothing for either client, because the last one would overwrite the other.

```text
error TOA902 config-invalid: Clients "shop" and "shop2" name the same baseline file.
  --> typed_openapi.yaml:9:15
  at #/clients/shop2/baseline
  fix: Give each client its own baseline file.
```

Clients that share a *spec* are fine: give each its own baseline.

## Adopting typed_openapi on an existing spec

1. **Run `check` and read the output.** Group by code: `dart run typed_openapi check --format json | jq -r '.diagnostics[].code' | sort | uniq -c | sort -rn`. Fix at the source what is cheap; see [Diagnostics](diagnostics.md) for each code's fix.
2. **Silence what you decide is fine.** A code you never want to hear about is a [level](configuration.md#severity) (`TOA553: info`), not a baseline entry.
3. **Accept the rest.** Add `baseline: <spec>.baseline.yaml` to the client and run `typed_openapi baseline create`.
4. **Commit the baseline** next to the spec. Its diff in a pull request shows exactly which problems the change accepts.
5. **Gate CI** with `check --strict-baseline` (see [CI](ci.md)). New problems fail the build; fixed ones fail it too until `baseline prune` removes their entries.
6. **Shrink it over time.** After each batch of fixes in the spec, run `baseline prune`. The goal is an empty `entries: []` and, then, no `baseline:` key.

> **Note:** `generate` uses the same baseline: a client whose only errors are accepted ones is generated.

## See also

- [Command line](cli.md): `check`, `baseline` and their exit codes.
- [Diagnostics](diagnostics.md): every code, and which ones are fixed.
- [Configuration](configuration.md): the `baseline` and `severity` keys.
- [CI](ci.md): gating with a baseline.
