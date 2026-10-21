# Overrides

An overrides file changes what the generator sees without touching the spec. Use it when you cannot fix the spec at its source: rename a method, give a parameter its real type, mark a field nullable, exclude an operation. Each client names its own file with `overrides:` in [the config](configuration.md).

```yaml
operations:
  listProducts:
    name: browse
    parameters:
      limit: {schema: {type: integer}}
  'GET /products/{id}':
    reason: the backend really sends JSON here
    responses:
      '200': {contentType: application/json}
  ping:
    exclude: true
schemas:
  Product:
    properties:
      owner: {nullable: true}
      discount: {name: discountRate}
  Category:
    exhaustive: false
```

The file is JSON or YAML. An empty file, a file with only comments, and a null section are no overrides and report nothing. A missing file is TOA801; a directory or a bad value is TOA802. The top level has two sections, `operations` and `schemas`; keys are camelCase.

## Before and after

On a spec where `listProducts` takes `limit` as a string and `GET /products/{id}` answers `*/*`, the generator without the file writes:

```dart
Future<Result<Uint8List, Never>> getProduct({
Future<Result<List<Product>, Never>> listProducts({
    String? limit,
final num? discount;
sealed class Category {
```

(shortened; plus TOA601 and TOA650 diagnostics for the `*/*` media type). With the file above it writes:

```dart
Future<Result<Product, Never>> getProduct({
Future<Result<List<Product>, Never>> browse({
    int? limit,
final num? discountRate;
abstract interface class Category {
```

Both outputs were produced by `typed_openapi generate`; only the lines that differ are shown. The JSON key is still `discount`; `name` changes the Dart name only.

## Addresses

| Section | Key | Finds |
| --- | --- | --- |
| `operations` | an `operationId`, or `METHOD /path` (`GET /products/{id}`) | One operation. Methods: GET, PUT, POST, DELETE, OPTIONS, HEAD, PATCH, TRACE, QUERY. |
| `operations.*.parameters` | `name` or `in:name` (`query:page`) | A parameter of that operation. |
| `operations.*.responses` | a status key (`'200'`, `'4XX'`, `default`) | A response. |
| `schemas` | a `components.schemas` key | A schema. A `$ref` chain is followed. |
| `schemas.*.properties` | a property name | A property. A `$ref` is not followed. |

An operation addressed twice, by id and by `METHOD /path`, is a conflict (TOA806): neither applies.

## Fields

Fields are of two kinds. **Spec fields** rewrite the spec the generator reads. **Generation fields** steer the generator and never touch the spec. `reason` is a free-text note on any entry; nothing reads it.

| Entry | Spec fields | Generation fields |
| --- | --- | --- |
| Operation | `parameters`, `requestBody`, `responses` | `name`, `exclude`, `group`, `sse` |
| Parameter | `required`, `schema` | `name`, `dartType` |
| `requestBody`, response | `contentType` (must contain `/`), `schema` | none |
| Schema | `$ref`, `type`, `nullable`, `format`, `required` (a list), `items`, `additionalProperties`, `enum`, `discriminator` | `name`, `exclude`, `exhaustive`, `union`, `dartType`, `properties` |
| Property | the schema spec fields (`required` is a boolean) | `name`, `exclude`, `dartType`, `triState`, `union` |

`name` of a type must be an UpperCamelCase Dart identifier, of a method, parameter or field lowerCamelCase; an invalid one is TOA560 and the sanitised name is used (`"my rate"` becomes `myRate`). `group` is UpperCamelCase. `exhaustive: false` makes an enum or union `abstract interface` instead of `sealed`. `union` is `raw` or `structural`. `triState` makes a request property tell "absent" from `null`. `dartType` is `{type, import, converter?}` where `import` is a `package:` or `dart:` library. The required shape of `type` and `converter` is in [Configuration](configuration.md#the-shape-of-a-custom-type).

```yaml
operations:
  getItems:
    parameters:
      'query:page': {dartType: {type: PageToken, import: 'package:paging/paging.dart'}}
```

## Set semantics

A value in the file replaces the spec's value. `null` removes the field. A value the spec already has changes nothing and is reported as TOA807 (info) so you can delete it. Two entries that change one node differently are TOA806 and neither applies.

```yaml
schemas:
  Item:
    properties:
      label: {type: null}   # removes "type"
```

Two keys of one operation that reach the same shared node through `$ref` (two statuses using one component response) get TOA808; the same value is applied once, and different values for one field conflict (TOA806).

## Nullable

`nullable: true` is written in the form of the spec's dialect, so you write the same override for 3.0 and 3.1.

| Spec | Property is a `$ref` | Property is `type: string` |
| --- | --- | --- |
| 3.0 | `allOf: [{$ref}]` and `nullable: true` | `nullable: true` |
| 3.1 and later | `anyOf: [{$ref}, {type: 'null'}]` | `type: [string, 'null']` |

From 3.1 a schema whose `anyOf` or `oneOf` has a null branch and others is already nullable: `nullable: true` there is TOA807, and `nullable: false` removes the null branch, unwraps a single remaining branch and keeps the siblings except `default: null`. A `nullable` override without `$ref` keeps the other keys of a `$ref` node; with `$ref` it replaces the node. Removing `type` of a nullable 3.1 schema also drops its nullability (TOA809, info).

> **Gotcha:** In 3.0 a field other than `nullable` (and a property's `required`) beside a `$ref` is not written: TOA800 asks you to override the referenced schema by name. In 3.1 it is written. `$ref` together with `properties` in one entry is an error.

## Event streams

`sse` on an operation steers a `text/event-stream` response. See [Event streams](generated/event_streams.md) for the generated code.

| Key | Values | Effect |
| --- | --- | --- |
| `data` | a `components.schemas` key, an inline schema | The data type of every event. Exclusive with `events`. |
| `events` | a map of event name to a schema key, an inline schema, or `null` | A union with one variant per event; `null` is an event without data. |
| `unknown` | `keep`, `ignore` | `ignore` drops events the union does not name. |
| `reconnect` | boolean | Overrides `sse.reconnect` of the config. |
| `method` | `stream`, `only`, `none` | `only` returns only the events and drops the bodies (TOA651); `none` leaves the stream method out. |

```yaml
operations:
  tailLog:
    sse:
      events:
        line: {type: string}
        stats: Usage
        eof: null
      reconnect: true
```

`sse` on an operation with no `text/event-stream` success changes nothing and is TOA669; a response that is a shared `$ref` is not changed.

## Diagnostics

A file with every kind of mistake, checked with `typed_openapi check`:

```text
error TOA803 unknown-override-key: Unknown key "nmae"; it is ignored.
  --> bad.overrides.yaml:3:11
warning TOA804 override-target-not-found: Operation listProducts has no parameter "missing". The override is not applied.
error TOA806 override-conflict: This override and the one at #/operations/getProduct name the same node (#/paths/~1products~1{id}/get); neither is applied.
error TOA802 invalid-override: The method "FETCH" is not an OpenAPI operation method.
warning TOA560 override-name-invalid: The name "my rate" of this override is not a valid Dart field name; "myRate" is used.
```

(Fix lines left out.) The override codes:

| Code | Level | Cause |
| --- | --- | --- |
| TOA801 | error | The overrides file does not exist. |
| TOA802 | error | A value is invalid, or the path is a directory. The value is ignored. |
| TOA803 | error | An unknown key; the fix text suggests `Did you mean "name"?` within edit distance 2. |
| TOA804 | warning | The address finds nothing. |
| TOA805 | error | The address is ambiguous (an `operationId` two operations share: use `METHOD /path`; parameters of one operation with the same name: use `in:name`), or a response or body has several media types and the `schema` override gives no `contentType`, or the given one is not among them. |
| TOA806 | error | Two entries change one node. |
| TOA807 | info | The override changes nothing. |
| TOA808 | info | The node is shared with other operations. |
| TOA809 | info | Removing `type` dropped nullability. |
| TOA800 | warning | The change cannot be written (3.0 beside `$ref`). |
| TOA810 | warning | The entry addresses an operation that `include`/`exclude` leaves out. |

Every code is explained in [Diagnostics](diagnostics.md). Rules that only report give you an override snippet in their `fix:` text, for example TOA554 prints `operations: ping: group: Default`.

## Editor support

The overrides file has a JSON Schema too, [`typed_openapi.overrides.schema.json`](../schema/typed_openapi.overrides.schema.json), generated and tested like [the one of the config](configuration.md#editor-support) (`override_schema_test.dart` in `typed_openapi_core` checks it against `OverrideLoader`). Put this as the first line of the file:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/4akloon/typed_openapi/typed_openapi-v0.3.0/packages/typed_openapi/schema/typed_openapi.overrides.schema.json
operations:
  listPets:
    group: Pets
```

The editor then completes the keys of an operation or a schema and flags a key the loader would call TOA803 or a value it would call TOA802. The URL is pinned to the tag of release 0.1.0; use the tag of the version you have. The schema cannot know your spec, so an address that matches nothing (`listPet` for `listPets`) is still `TOA804` from `check`. It is not published to SchemaStore.

## See also

- [Configuration](configuration.md): the `overrides` key and `sse.reconnect`.
- [Diagnostics](diagnostics.md): TOA560, TOA800-TOA810.
- [Presets and rules](presets_and_rules.md): findings that suggest an override.
