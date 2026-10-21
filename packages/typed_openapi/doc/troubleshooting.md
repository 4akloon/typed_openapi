# Troubleshooting

This guide is organised by what you see: a message, a missing file, a surprising type. Each entry gives the cause and the fix. The outputs below were produced by running `typed_openapi` 0.1.0 on small specs; a code that is only named here is explained in [Diagnostics](diagnostics.md).

## The spec cannot be read

### `TOA001 parse-error`

```text
$ typed_openapi check
error TOA001 parse-error: While parsing a flow mapping, expected ',' or '}'.
  --> specs/bad.yaml:3:6
errors: 1, warnings: 0, infos: 0
```

**Cause:** the file is not valid JSON or YAML. The position is `file:line:column`; the real mistake is often on the line before (an unclosed `{` or `[`, a tab used as indentation). **Fix:** open the file at that line. For a `.json` file the same code is reported with the position of the JSON decoder. `generate` then prints `Skipped bad: its check reports errors; fix them and run generate again.` and exits `1`; other clients still run.

### `TOA004 input-not-found`

**Cause:** `input` (or a file a `$ref` names) does not exist. Paths in the config are relative to the config file, not to the directory you run the command from. **Fix:** correct the path, or pass `-c path/to/typed_openapi.yaml` so that the directory is the one you meant. See [Configuration](configuration.md#layout).

### `TOA007` and `TOA008`: YAML limits

```text
error TOA007 nesting-too-deep: The document nests deeper than 1000 levels.
  --> specs/deep.yaml:4:1009

error TOA008 alias-expansion-too-large: YAML aliases expand to far more nodes than the text has; the document is not read.
  --> specs/bomb.yaml:5:26
  at #/x-bomb/a5/5/0/4/8/7/7
  fix: Remove the nested aliases.
```

**Cause:** the reader refuses documents that nest more than 1000 levels, or whose aliases expand to a size far above the text (a "billion laughs" document). A real spec never does this; the usual source is a generator that dumps a cyclic object graph with YAML anchors. **Fix:** export the spec as JSON from the framework, or remove the nested aliases the `at` line points to. Both codes are errors you cannot lower.

### A `$ref` does not resolve

```text
error TOA101 unresolved-ref: Nothing is at "#/components/schemas/Missing".
  --> specs/refs.yaml:13:30
  at #/paths/~1a/get/responses/200/content/application~1json/schema/$ref
  fix: Define the target, or point the reference at an existing one.
error TOA102 remote-ref: "https://example.com/schemas.yaml#/Err" points to a remote document; only local files are read.
  --> specs/refs.yaml:18:30
  fix: Save the document next to the spec and refer to it by a relative path.
error TOA004 input-not-found: "common.yaml#/Err" points to specs/common.yaml, which does not exist or cannot be read.
```

| Message | Cause | Fix |
| --- | --- | --- |
| `TOA101` | The target schema is not in the document. In NestJS a circular import makes the DTO type `undefined`, so the exporter writes a `$ref` to nothing. | Fix the code that writes the spec. If you cannot, add the schema in your own file and refer to it. |
| `TOA102` | The tool never touches the network. | Download the document once, commit it next to the spec, refer to it by relative path. |
| `TOA004` for a `$ref` | A local file in the `$ref` is missing. | Put the file where the `$ref` says. |

Fragments (`#/...`) and relative files are read; URLs are not. See [Diagnostics](diagnostics.md#parse-and-resolve-toa1xx).

## Names

### `TOA504`: duplicate `operationId`

```text
error TOA504 duplicate-operation-id: operationId "list" is also the id of the operation at #/paths/~1a/get; method names would clash.
  --> specs/shop.yaml:10:20
  at #/paths/~1b/get/operationId
  fix: Give each operation its own operationId at the source. To generate anyway, lower TOA504 in the client's severity and pin the second method's name with an override.
```

**Cause:** two operations share an id; the second would clash with the first. **Fix:** make the ids unique at the source. A method-name override does not clear this error (an override of `GET /b` with `name: listB` was tried, and TOA504 was still reported), so the fix text no longer suggests one. The other way out is to lower the code in the client's `severity` (see [Configuration](configuration.md#severity)):

```yaml
clients:
  shop:
    input: specs/shop.yaml
    output: lib/shop
    severity:
      TOA504: warning
```

Then `check` reports a warning, `generate` runs (`Generated shop in lib/shop: 4 files, 4 written, 0 deleted.`), and the second method is named `list2` with an info (`TOA551 name-collision`) whose fix is an override that pins the name. Pin it, so that adding an operation later does not rename a method.

### A name lost letters (`TOA559`)

The spec also has a non-ASCII component key, so `check` prints `TOA106` (a warning: `The component name "Größe" has characters OpenAPI does not allow in component keys`) next to the info below.

```text
info TOA559 name-lossy: Schema "Größe" lost characters when it became the Dart name "GrE": letters outside ASCII are dropped.
  --> specs/names.yaml:17:7
  at #/components/schemas/Größe
  fix: Name it explicitly to keep the meaning. Override:
    schemas:
      "Größe":
        name: GrE
```

**Cause:** generated names are ASCII; letters outside it are dropped, not transliterated. **Fix:** copy the override from the `fix:` line and change the name. This gave `class Size` and a field `length` that still reads the JSON key `Länge`:

```yaml
schemas:
  "Größe":
    name: Size
    properties:
      "Länge":
        name: length
```

The same applies to a client name: set `naming.client` in the config. See [Overrides](overrides.md).

### My override does nothing

```text
warning TOA804 override-target-not-found: No operation has operationId "getPets". The override is not applied.
  --> ov.yaml:3:5
  fix: Remove the override, or fix its address.
```

**Cause:** the address matches nothing: a typo in an `operationId` or a schema name (see [Addresses](overrides.md#addresses)). An unknown key is TOA803, an error with a "did you mean". **Fix:** use the text of the diagnostic; `METHOD /path` always works.

## Generating

### `TOA830`: the output is not owned

```text
error TOA830 output-not-owned: Client "names" is not generated: its output directory lib/own holds files but no .typed_openapi.json, so they were not written by it: hand.dart (not written by typed_openapi).
  --> lib/own
  fix: Move them out of the directory, or run generate --force to replace them.
Skipped names: see the error above.
```

**Cause:** `generate` replaces its output directory as a whole, so it refuses a directory that holds files it did not write or that changed after it wrote them (a hand edit, a missing manifest). **Fix:** move your files out, or keep generated code in a directory of its own. `generate --force` replaces them and reports each file as TOA833; it never replaces a package (`pubspec.yaml`), a `lib` directory, a symbolic link or an input. See [Generated output](generate_output.md#ownership-and-the-manifest).

> **Gotcha:** an edit in a generated file is a reason for this error on the next run. Change the spec, the config or the overrides instead.

### `TOA831`: the output is locked

```text
error TOA831 output-not-written: Client "names" is not generated: another typed_openapi run holds the lock lib/.own.typed_openapi.lock of its output lib/own (process 1 on other-host; it cannot be told whether that process still runs). Nothing was changed.
  fix: Delete lib/.own.typed_openapi.lock if no run is going, or run generate --break-lock, which takes the lock over and replaces no file.
```

**Cause:** another run is writing, or one was killed and left its lock. A lock of a process on this machine that is gone is taken over by itself (TOA832, info). **Fix:** wait, or if no run is going use `generate --break-lock`:

```text
$ typed_openapi generate --break-lock
info TOA832 output-recovered: Took over the lock lib/.own.typed_openapi.lock of client "names", which process 1 on other-host held: --break-lock takes it over.
Generated names in lib/own: 5 files, 5 written, 0 deleted.
```

`--force` never touches locks. See [Generated output](generate_output.md#locks).

### The generated code does not compile

Run `dart analyze` first: it names the file and line. If the error is in `lib/.../models/*.dart` or `api/*.dart`, it is a generator bug (the project analyses its own fixtures with `--fatal-infos`). Common non-bugs:

- **`typed_openapi_client` or the transport (`typed_openapi_dio` and `dio`) missing in `pubspec.yaml`.** The generated code imports the client; your code creates the transport. See [Getting started](getting_started.md#install).
- **An old runtime.** Generator and runtime come from the same checkout; pin both to the same `ref`.
- **A lower SDK.** The minimum SDK is Dart 3.10, for the generated code too.

If it is a bug, report it as described in [Reporting a bug](#reporting-a-bug).

### `generate` prints dozens of diagnostics

A spec from a code-first framework may have hundreds. Do not lower the levels; accept the current state and gate on new problems:

```text
$ typed_openapi check          # baseline file does not exist yet
error TOA820 baseline-not-found: Baseline file specs/big.baseline.yaml does not exist.
...
errors: 1, warnings: 40, infos: 0
$ typed_openapi baseline create
errors: 0, warnings: 0, infos: 0
Wrote specs/big.baseline.yaml: 40 entries accept 40 diagnostics.
$ typed_openapi check
errors: 0, warnings: 0, infos: 0, baselined: 40
```

Set `baseline:` on the client first; until the file exists `check` reports TOA820. Errors from reading and from `generate` (TOA001, TOA830...) cannot be baselined. Commit the file, and run `baseline prune` when you fix the spec. See [Baseline](baseline.md#adopting-typed_openapi-on-an-existing-spec).

### The output changed after an upgrade

The manifest `.typed_openapi.json` records the generator version (`"generator": "typed_openapi 0.3.0"`). A new generator can write different code from the same spec and config; that is a change of the generator, not of your API. **Fix:** commit the generated tree, upgrade in a branch, and read the diff. Pin the version of `typed_openapi` and `typed_openapi_client` together with the same `ref`. If the diff is a change you did not expect, see [Reporting a bug](#reporting-a-bug). The same spec and config on the same version always give the same bytes. See [Determinism](generate_output.md#determinism).

## Using the client

### A call returns `DecodeError`

```text
status 200
JsonDecodeException: expected a string, got a number at /tags/1/name in Tag
pointer /tags/1/name, expected a string, actual a number, schema Tag, field name
```

**Cause:** the server's body does not match the spec; the first mismatch is reported, never the value. `pointer` is an RFC 6901 path into the body (`/tags/1/name` is the `name` of the second tag), `expected` is what the spec wants, `actual` is the JSON type that came, `schema` is the model that was reading. **Fix:** compare with the real body (`DecodeError.rawBody`). If the server is right, correct the schema at the source or with an [override](overrides.md) (`nullable: true`, a different `type`). If it is wrong, fix the server. See [JSON decoding](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/json_decoding.md#jsondecodeexception).

### `The type 'PetStatus' isn't exhaustively matched`

```text
error - e.dart:3:26 - The type 'PetStatus' isn't exhaustively matched by the switch cases since it doesn't match the pattern 'PetStatusUnknown()'.
```

**Cause:** an enum is open: the base class is `sealed` with a `...Known` and a `...Unknown` side, so a value the spec forgot does not make decoding fail. **Fix:** add an arm for `PetStatusUnknown`. To make the base `abstract interface` and switch with a default, set `exhaustive: false` in an override. See [Enums](generated/enums.md#exhaustive-or-open-for-switching).

### A field is nullable (or not) when I expected the opposite

A field is `T x` only when it is in `required` and not nullable. Optional fields are `T?`, and a `null` value for an optional non-nullable field is read as absent. The rule `bool-required-to-array` repairs `required: true` on a property (TOA201). To change a field, use `nullable` in an [override](overrides.md); do not edit the generated file. The full table is in [Models](generated/models.md#required-optional-nullable); for PATCH bodies see [Patch and nullability](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/patch_and_nullability.md).

### An event stream returns one error on the web

**Cause:** Dio's default browser adapter delivers a response body only when the connection closes, so `openEvents` returns a `TransportError` before sending a request. **Fix:** set a fetch-based adapter on your `Dio`, then the stream opens. For a cross-origin stream the server must also list `Last-Event-ID` in `Access-Control-Allow-Headers`. The message and the adapters are in [Web and platforms](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/web_and_platforms.md#event-streams).

## Reporting a bug

Open an issue at [github.com/4akloon/typed_openapi/issues](https://github.com/4akloon/typed_openapi/issues) with:

- **The version:** the `generator` line of `.typed_openapi.json`, and `dart --version`.
- **A minimal spec** that shows it (a few lines; remove private data), and your `typed_openapi.yaml` and overrides file.
- **The command and its exact output** (`typed_openapi check --format json` is easiest to paste), and the exit code.
- **For code that does not compile:** the `dart analyze` lines and the generated file they point to.
- **What you expected.**

`typed_openapi check --format json` prints locations and messages, which is usually enough. The hidden `ir` command prints the internal model as JSON; it is for the project's tests and its format may change, so attach it only when asked.

## See also

- [Diagnostics](diagnostics.md): every code in the output.
- [CLI](cli.md) and [Generated output](generate_output.md): commands, ownership, locks.
- [Baseline](baseline.md), [Overrides](overrides.md) and [Configuration](configuration.md): the ways to fix or accept a problem.
- [The generated client](generated/overview.md): what the code looks like.
