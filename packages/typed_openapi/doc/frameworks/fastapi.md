# FastAPI

FastAPI with Pydantic v2 produces a clean OpenAPI 3.1 document, and `typed_openapi` reads it with few repairs. What you meet are unions that Pydantic writes without a discriminator, operation ids built from function names and routes, a `422` response on every operation, and the same `operationId` twice when one function serves two routes. This guide shows what to expect and a config that generates a client from a FastAPI-style spec.

## Config

```yaml
# typed_openapi.yaml
clients:
  items:
    input: openapi.json
    output: lib/items
    preset: fastapi
    overrides: overrides.yaml
    severity:
      TOA504: warning
```

The `fastapi` preset changes no behaviour and no names. It adds FastAPI advice to the `fix:` text of `duplicate-operation-id` (`generate_unique_id_function`) and `discriminator-mapping-target` (give models unique names across the app); see [Presets and rules](../presets_and_rules.md). Use it anyway: the advice is what you hand the backend team.

Export the spec with `app.openapi()` (for example `json.dump(app.openapi(), f)` in a script) or fetch `/openapi.json`, and commit it, so generation is reproducible and offline.

## What a FastAPI spec looks like

The sample is a small FastAPI-style 3.1 document (`items` and `files` routes, `Item-Input` and `Item-Output` schemas, a `422` on the item routes, a discriminated `Cat | Dog`, a Pydantic `Decimal`). `typed_openapi check` on it, trimmed to the codes:

| Finding | Code | Meaning for the client |
| --- | --- | --- |
| The same `operationId` on two routes | `TOA504` (error), `TOA551` (info) | Methods would clash: the second is named `readItem2`. The check fails until the id is unique or the level is lowered (below). |
| `anyOf` of `date-time` string, string and `null` | `TOA453` (warning) | The variants share a JSON type, so no dispatch by type exists; generated as `JsonValue`, or as a union that tries each variant with `union: structural`. |
| `Cat \| Dog \| None` as `anyOf` on a response | `TOA453` (warning) | Pydantic drops `discriminator` when the field is optional. Same fix. |
| The discriminator property has a `default`, so it is not `required` in `Cat` and `Dog` | `TOA401` (info) | A payload without `pet_type` cannot be told apart. |

```text
error TOA504 duplicate-operation-id: operationId "read_item" is also the id of the operation at #/paths/~1items~1{item_id}/get; method names would clash.
  --> openapi.json:43:24
  at #/paths/~1v2~1items~1{item_id}/get/operationId
  fix: Give each operation its own operationId at the source. To generate anyway, lower TOA504 in the client's severity and pin the second method's name with an override. In FastAPI, pass `generate_unique_id_function` to FastAPI(...).
info TOA401 discriminator-not-required: Discriminator property "pet_type" is not required in Cat, Dog; a payload without it cannot be told apart.
  --> openapi.json:74:123
  at #/components/schemas/Item-Input/properties/pet/discriminator
  fix: Add "pet_type" to "required" of each variant at the source.
warning TOA453 union-undiscriminated: This anyOf has no discriminator and variants that share a JSON type, so a value cannot be told apart by its type; it is generated as JsonValue.
  --> openapi.json:86:18
  at #/components/schemas/Item-Output/properties/pet
  fix: Add a discriminator at the source, or generate a union that tries the variants with union: structural (an override of the schema, or the config key for every such union). Override:
    schemas:
      Item-Output:
        properties:
          pet:
            union: structural
errors: 1, warnings: 2, infos: 2
```

### Duplicate operation ids

`TOA504` is an error, and an override cannot rename an `operationId` (an operation's override has `name`, `group`, `exclude`, `parameters`, `requestBody`, `responses` and `sse`). Two ways out, in order of preference:

1. Fix the backend: `FastAPI(generate_unique_id_function=...)` gives every route a unique id. The default ids (`read_items_items__get`) are also why the methods below are called `readItemsItemsGet`; an id such as `f"{route.tags[0]}-{route.name}"` produces `items-read_items`.
2. Name the clashing method in the overrides file and lower the code's level for this client, as in the config above: `severity: {TOA504: warning}`. `TOA504` is not one of the fixed codes, so the level can change.

```yaml
# overrides.yaml
operations:
  GET /v2/items/{item_id}:
    name: readItemV2
schemas:
  Item-Input:
    properties:
      created:
        union: structural
  Item-Output:
    name: Item
    properties:
      pet:
        union: structural
```

`GET /v2/items/{item_id}` is the `METHOD /path` address of the second route (the `operationId` is ambiguous). `name: Item` on `Item-Output` gives the response model the clean name; Pydantic's split into `Item-Input` and `Item-Output` is otherwise kept as `ItemInput` and `ItemOutput`, one class for each direction. See [Models](../generated/models.md).

## The result

```text
$ typed_openapi generate
warning TOA504 duplicate-operation-id: operationId "read_item" is also the id of the operation at #/paths/~1v2~1items~1{item_id}/get/operationId ...
info TOA401 discriminator-not-required: Discriminator property "pet_type" is not required in Cat, Dog; ...
errors: 0, warnings: 1, infos: 1
Generated items in lib/items: 16 files, 16 written, 0 deleted.
```

The generated signatures (real output):

```dart
Future<Result<Item, HTTPValidationError>> createItemItemsPost({ ... })
Future<Result<Item, Never>> readItem({ ... })
Future<Result<Item, Never>> readItemV2({ ... })
Future<Result<List<Item>, HTTPValidationError>> readItemsItemsGet({ ... })
Future<Result<JsonValue, Never>> uploadFilesPost({ ... })  // FilesApi
```

- The documented `422` is the error type: a validation error from the server is an `HttpError` whose `body` is a typed `HTTPValidationError`. See [Responses and errors](../generated/responses_and_errors.md).
- `Cat | Dog` with a mapping is a sealed class `ItemInputPet` that decodes by `pet_type` (`ItemInputPetCat`, `ItemInputPetDog`, and an `Unknown` variant). The `anyOf` without a mapping, made `structural` by the override, tries `Cat` then `Dog` (`ItemPet`). See [Unions](../generated/unions.md).
- The Pydantic `Decimal` (`anyOf: [number, string with a pattern]`) is a union by JSON type, `ItemInputPrice`.
- A `multipart/form-data` body `Body_upload_files__post` becomes a parts class (`UploadFilesPostRequest`) with `toParts()`; see [Request bodies](../generated/request_bodies.md).

## Real specs

Apache Airflow's REST API v2 (134 operations, FastAPI, OpenAPI 3.1) is in the repository's corpus (`packages/typed_openapi_tool/corpus.yaml`) and generates (203 files) with `preset: fastapi`. `check` gives 27 diagnostics, none an error:

| Code | Count | What |
| --- | --- | --- |
| `TOA453` | 14 | `anyOf` and `oneOf` without a discriminator whose variants share a JSON type (`Bulk...` action lists, optional date-time or string fields). |
| `TOA651` | 5 | A response offers `application/json` and also `application/x-ndjson` or `text/plain`; the client uses JSON and drops the other. |
| `TOA553` | 3 | An operation tagged with two tags is generated once, in the first tag's group. |
| `TOA550`, `TOA552` | 2, 1 | An enum value `unknown` is named `unknown_`; `~` has no letter and is named `value_`. |
| `TOA658` | 2 | A `307` response (login, logout redirects) is not generated; at run time it is an `UndocumentedStatus`. |

## Fix it in the backend

- **Operation ids:** `generate_unique_id_function` (above).
- **One schema per model:** `separate_input_output_schemas=False` (FastAPI 0.102+) gives one schema instead of `Item-Input` and `Item-Output`.
- **Do not force `openapi_version="3.0.x"`:** FastAPI writes 3.1 constructs (`anyOf` with `null`, `const`) anyway, so the document becomes a mix of both. Leave the 3.1 default.
- **Unique model names across the application.** Same-named models from different modules get renamed keys; `TOA402` reports a `discriminator.mapping` value that points nowhere.
- **Discriminated unions:** `Annotated[Cat | Dog, Field(discriminator="pet_type")]` with `pet_type: Literal["cat"]` gives the mapping and a `const` per variant. Pydantic allows one discriminator per field; where the spec still has an `anyOf` without a mapping, the `structural` override covers it.
- **Typed errors:** `responses={404: {"model": ErrorOut}}`. The `422` is added automatically.

## Sources

Checked on 2026-10-20. Versions: FastAPI documentation as published on that date (`separate_input_output_schemas` needs FastAPI 0.102.0); Pydantic v2 documentation; Apache Airflow at the commit pinned in the corpus.

- FastAPI [Path operation advanced configuration](https://fastapi.tiangolo.com/advanced/path-operation-advanced-configuration/) (`operation_id`, `generate_unique_id_function`), [Separate OpenAPI schemas for input and output](https://fastapi.tiangolo.com/how-to/separate-openapi-schemas/) (`separate_input_output_schemas=False`, 0.102.0), [Additional responses](https://fastapi.tiangolo.com/advanced/additional-responses/) (`responses` with `model`; the example shows the `422` with `HTTPValidationError`).
- Pydantic [Unions](https://pydantic.dev/docs/validation/latest/concepts/unions/) (`Field(discriminator=...)` with `Literal` fields, one discriminator per field).

## Caveats

- The `Body_<function>_<path>` schemas FastAPI generates for forms are not given better names by the generator: a `multipart/form-data` body is a parts class named after the operation (`UploadFilesPostRequest`), and `name` on the `Body_...` schema has no effect on it. Name the method instead.
- Streaming endpoints: see [Event streams](../generated/event_streams.md) for what `itemSchema` and `text/event-stream` produce.
- `Item-Input` and `Item-Output` are two models. Convert between them yourself if you send back what you received.

## See also

- [Presets and rules](../presets_and_rules.md), [Overrides](../overrides.md), [Configuration](../configuration.md) (`severity`).
- [Diagnostics](../diagnostics.md) and [Baseline](../baseline.md).
- Other frameworks: [NestJS](nestjs.md), [Spring](spring.md), [ASP.NET](aspnet.md).
