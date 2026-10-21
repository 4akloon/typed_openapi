# Configuration

A project has one `typed_openapi.yaml`. It lists the clients to generate and the settings that shape them. The file is read before anything else, so its mistakes are reported with the config codes TOA901-TOA904 and never throw.

This is a config that sets every key. It is the one the samples in this guide were checked with: `check` prints `errors: 0, warnings: 0, infos: 0` for it.

```yaml
defaults:
  preset: generic
  line_width: 100
  rules:
    array-without-items: false
  severity:
    TOA553: info
    duplicate-operation-id: error
  naming:
    group: "{Tag}Api"
    default_group: DefaultApi
    input_suffix: Input
    patch_suffix: Patch
    stream_suffix: Stream
  group_by: tag
  types:
    number: double
    formats:
      uuid:
        type: UuidValue
        import: package:uuid/uuid_value.dart
        converter: UuidConverter
  tri_state: patch
  union: raw
  exhaustive: true
  errors:
    default_schema: Problem
  sse:
    reconnect: true

clients:
  petstore:
    input: specs/petstore.yaml
    output: lib/src/api/petstore
    preset: fastapi
    naming:
      client: PetstoreClient
    include:
      tags: [pets]
      paths: ["/pets/**"]
    exclude:
      operations: [deletePet]
```

## Layout

The file is a mapping with two keys, `defaults` and `clients`. `clients` is required and cannot be empty. A client is a mapping named after the client; the name is what you pass to [`check` and `generate`](cli.md#client-arguments).

| Key | Where | Required | Meaning |
| --- | --- | --- | --- |
| `input` | client | yes | The spec: a JSON or YAML file. |
| `output` | client | yes | The directory `generate` writes. |
| `overrides` | client | no | The [overrides file](overrides.md). |
| `baseline` | client | no | The [baseline file](baseline.md). One file per client. |
| `preset` | both | no | One of `generic`, `nestjs`, `fastapi`, `springdoc`, `aspnet`. See [Presets and rules](presets_and_rules.md). |
| `line_width` | both | no | A positive integer, default `80`, the width of the generated code. |
| `rules` | both | no | Normalizer rules to turn off, see [Rules](#rules). |
| `severity` | both | no | Levels of diagnostic codes, see [Severity](#severity). |
| `naming` | both | no | Names of classes and methods, see [Naming](#naming). |
| `group_by` | both | no | `tag` (default), `path` or `single`. |
| `include`, `exclude` | both | no | Operation filters, see [Filters](#filters). |
| `types` | both | no | Dart types for numbers, formats and schemas, see [Types](#types). |
| `tri_state` | both | no | `patch` (default), `optional` or `extension`. |
| `union` | both | no | `raw` (default) or `structural`. |
| `exhaustive` | both | no | `true` (default) or `false`, see [Exhaustive](#exhaustive). |
| `errors` | both | no | `default_schema`, see [Errors](#errors). |
| `sse` | both | no | `reconnect`, see [Event streams](#event-streams). |

Relative paths in `input`, `output`, `overrides` and `baseline` are resolved against the directory of the config file, not the working directory. An unknown key is TOA903, a warning that names the allowed keys; the key is ignored.

```text
warning TOA903 config-unknown-key: Unknown key "colour".
  --> bad.yaml:3:62
  at #/clients/b/colour
  fix: Allowed keys here: baseline, errors, exclude, exhaustive, group_by, include, input, line_width, naming, output, overrides, preset, rules, severity, sse, tri_state, types, union.
```

## Precedence

A client's key wins over `defaults`. Most keys are replaced as a whole; these are merged:

| Key | Merge |
| --- | --- |
| `rules`, `severity` | Key by key. A client `true` turns a rule back on that `defaults` turned off. |
| `naming` | Key by key (`client`, `group`, and so on). |
| `types.formats`, `types.schemas` | Entry by entry. |

`types.number`, `errors.default_schema`, `sse.reconnect`, `group_by`, `tri_state`, `union` and `exhaustive` take the value of the last source that has them (the client, else `defaults`). `include` and `exclude` take the whole key from the last source that has it: a client `include:` replaces the `defaults` one, it does not extend it. `preset` and `line_width` come from the client, else `defaults`.

> **Gotcha:** A client that sets `include: {tags: [pets]}` forgets a `defaults.include` completely. Repeat what you still want.

## Rules

`rules` maps a [normalizer rule](presets_and_rules.md#the-rules) name to `true` or `false`. Only `false` has an effect. A rule that is off finds nothing and fixes nothing. An unknown name is TOA903 and the entry is skipped.

```yaml
defaults:
  rules:
    array-without-items: false
```

## Severity

`severity` maps a diagnostic code, by id (`TOA201`) or slug (`bool-required`), to `error`, `warning`, `info` or `off`. The rules for which codes may change are in [Diagnostics](diagnostics.md#severity-and-levels).

| Mistake | Result |
| --- | --- |
| An unknown code | TOA903 warning, `Unknown diagnostic code "TOA999".`, skipped. |
| A level that is not one of the four | TOA902: `The level of "TOA201" must be error, warning, info or off.` |
| Two names for one code | TOA902, only the first is used. |
| A config code (TOA901-TOA904) | TOA902: `The level of TOA902 config-invalid cannot be changed: the config is read before levels apply.` |
| Lowering or switching off a fixed code | TOA902: `... cannot be lowered or turned off`. Raising it is allowed. |

## Naming

| Key | Default | Rule |
| --- | --- | --- |
| `client` | the client name plus `Client` | The root class. An identifier that starts with an uppercase letter and is not a Dart reserved word. |
| `group` | `{Tag}Api` | The class of a group. Must contain `{Tag}` and give a Dart identifier. |
| `default_group` | `DefaultApi` | The class of operations with no tag. Not a reserved word. |
| `input_suffix` | `Input` | Suffix of the request model of a schema that is split by direction. |
| `patch_suffix` | `Patch` | Suffix of the PATCH body model of a schema also used elsewhere. |
| `operation_prefix` | none | A regular expression. When its match starts at index 0 and is not empty, it is removed from `operationId` before the method name is made. |
| `stream_suffix` | `Stream` | Suffix of the second method of an operation that returns a body or an event stream. Letters and digits, starting with an uppercase letter or a digit. |

If `input_suffix` and `patch_suffix` are equal, both return to their defaults and TOA902 is reported. A bad value of any other key is TOA902, and the setting is read as if the client had not set it: the value from `defaults` applies, and when that is missing or bad too, the built-in default. The message names the value that is applied, for example `"union" must be one of raw, structural. The value from "defaults" (structural) is used.` or, without a usable `defaults`, `... The default (raw) is used.`

> **Note:** With `preset: nestjs` and no `operation_prefix`, the pattern `^[A-Za-z0-9]*Controller_` is removed from every `operationId`, so `ProductsController_findOne` becomes the method `findOne`. Set `operation_prefix` to replace that.

## Filters

`include` and `exclude` take lists of patterns under three keys.

| Key | Matches |
| --- | --- |
| `tags` | A tag, as written in the spec. Case-sensitive. |
| `operations` | The raw `operationId`. |
| `paths` | A path template. `*` is one segment and `**` any number of segments. |

`include` is the union of its three lists; empty means no filter. `exclude` is applied after and wins. A pattern that matches nothing is TOA557, and a pattern in both filters is TOA558. When filters leave no operation, TOA563 says so. An override can also take one operation out with `exclude: true`, see [Overrides](overrides.md).

## Types

```yaml
types:
  number: double
  formats:
    uuid: {type: UuidValue, import: package:uuid/uuid_value.dart, converter: UuidConverter}
  schemas:
    Money: {type: Decimal, import: package:decimal/decimal.dart}
```

`number` decides the Dart type of `type: number` without `format: float` or `double`: `num` (default), `double` or `int`. `formats` maps a string `format` to a Dart type; `schemas` maps a `components.schemas` key to one. An entry needs `type` and `import`, may have `converter`, and an unknown key in it is TOA903. `import` must be a `package:` or `dart:` library; `type` and `converter` must be Dart names. A schema a custom type replaces generates no declaration.

### The shape of a custom type

The generated code calls the type or its converter on the JSON value of the schema it replaces (a `String` for a string `format`, a `num`, `double` or `int` for a number, and so on). Nothing checks that your class has these members; a wrong shape is a compile error in the generated file.

| Entry | Decoding | Encoding |
| --- | --- | --- |
| `type: Money` (no `converter`) | `Money.fromJson(JsonReader.asString(value))`: a static or factory `fromJson` that takes the JSON value | `value.toJson()`: an instance method that returns the JSON value |
| `type: UuidValue`, `converter: UuidConverter` | `const UuidConverter().fromJson(JsonReader.asString(value))` | `const UuidConverter().toJson(id)` |

So a converter is a class with a `const` constructor and no required arguments, a `fromJson` that takes the JSON value and returns the type, and a `toJson` that takes the type and returns the JSON value. The generated file imports `type` and `converter` from `import` with a `show` list. The two rows are what the generator wrote for `format: uuid` with a converter and `format: money` without one.

## Tri-state

`tri_state` decides which request-body properties tell "absent" from `null`, using `Patch<T>` from the runtime.

| Value | Properties |
| --- | --- |
| `patch` | Optional nullable properties of PATCH bodies. |
| `optional` | Every optional property of PATCH bodies. |
| `extension` | Properties with `x-typed-tri-state: true`. |

## Union

`union` decides how a `oneOf` or `anyOf` with no discriminator whose variants share a JSON type is generated: `raw` keeps the value as `JsonValue` (TOA453), `structural` tries each variant in order. An override can set it for one schema.

## Exhaustive

`exhaustive` decides whether the bases of enums, unions, the status types of an operation and event unions are `sealed` (`true`, the default) or `abstract interface` (`false`). A `switch` over a sealed type must name every variant, so a value the API adds later breaks it at compile time; over an interface it needs a default case, and a new value is no breaking change for the code that uses the client (see `typed_openapi diff`). An override `exhaustive` on a schema wins. A value that is not `true` or `false` is TOA902 and falls back like any other setting (to `defaults`, then `true`).

## Errors

`errors.default_schema` is the key of a `components.schemas` schema used as the body of error statuses that declare none. A key that is not in `components.schemas` is TOA652 and ignored.

## Event streams

`sse.reconnect` is a boolean that applies to GET event streams. Without it (or `false`) a GET stream reconnects only when the call passes `SseOptions(reconnect: true)`; with `true` it reconnects unless the call says no. Other methods never reconnect because of this key: TOA665 (info) says so, and an operation that can be repeated safely turns it on with `sse.reconnect: true` in the [overrides file](overrides.md#event-streams), which wins over the config for that operation. See [Event streams](generated/event_streams.md).

## Config errors

| Code | Meaning |
| --- | --- |
| TOA901 | The config file does not exist. Exit `78`. |
| TOA902 | The config is malformed or a value is invalid. Exit `78` when no config could be loaded (not a mapping, no clients), else `1`. |
| TOA903 | An unknown key, rule or diagnostic code. A warning. |
| TOA904 | Two clients write to overlapping directories. The later one is skipped by `generate`. |

None of these codes can be given another level. See [Diagnostics](diagnostics.md) for their texts.

## Editor support

A JSON Schema of the config, [`typed_openapi.schema.json`](../schema/typed_openapi.schema.json), gives an editor completion and checking while you edit `typed_openapi.yaml`. It is generated from the key catalog that `ConfigLoader` reads, and a test (`config_schema_test.dart` in `typed_openapi_core`) checks that the loader accepts what the schema accepts, and rejects what it rejects, for a list of documents. Point the editor at it with this as the first line of the file (read by the YAML language server, for example the YAML extension of VS Code):

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/4akloon/typed_openapi/typed_openapi-v0.3.1/packages/typed_openapi/schema/typed_openapi.schema.json
```

That URL is pinned to the tag of release 0.3.1; use the tag of the version you have. In a checkout a relative path to the file works as well. The schema checks the shape only: that a key is known, has the right type and takes one of its values. A missing `input` file and overlapping outputs stay with [`check`](cli.md#check) (TOA904), and a few things the loader rejects the schema cannot say (one code written under both its id and its name, equal `input_suffix` and `patch_suffix`, an `operation_prefix` that is not a regular expression). The schema is not published to SchemaStore.

## See also

- [CLI](cli.md): `--config` and client names.
- [Overrides](overrides.md): per-operation and per-schema changes.
- [Presets and rules](presets_and_rules.md): `preset` and `rules`.
- [Diagnostics](diagnostics.md): `severity` and the config codes.
