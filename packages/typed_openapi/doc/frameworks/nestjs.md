# NestJS

Specs from `@nestjs/swagger` are the best case for code-first generation and still need a few repairs: controller-prefixed `operationId`s, lists declared twice, duplicated enum values, `required: true` on properties and nullable enums that read as unions. Use `preset: nestjs` and a small overrides file. This guide lists what to expect, shows a config that generates a client from a NestJS-style spec, and says what to fix in the backend instead.

## Config

```yaml
# typed_openapi.yaml
defaults:
  preset: nestjs

clients:
  shop:
    input: openapi.json
    output: lib/shop
    overrides: overrides.yaml
```

What `preset: nestjs` does (see [Presets and rules](../presets_and_rules.md) for all presets):

- It removes `^[A-Za-z0-9]*Controller_` from every `operationId`, so `ProductsController_findOne` becomes the method `findOne` and `EventsController_stream` becomes `stream`. Set `naming.operation_prefix` to use another pattern (see [Configuration](../configuration.md)). Overrides still address the operation by its raw `operationId`.
- It adds NestJS advice (the decorator or option to change) to the `fix:` text of the rules below.

## What a NestJS spec looks like

These defects come from the decorators and the Swagger CLI plugin. The sample spec used in this guide has all of them except the last row (which the Immich spec below shows); each diagnostic shown is real output of `typed_openapi check` on it.

| Defect in the spec | Rule | Diagnostic |
| --- | --- | --- |
| `enum` with a repeated value (several TypeScript enums spread into one list) | `dedupe-enum-values` | `TOA301` (warning), repeats removed |
| `required: true` on a property (the OpenAPI 2 way) | `bool-required-to-array` | `TOA201` (warning), name moved to the parent's `required` |
| `default` of another type than the schema, or computed at run time | `drop-invalid-default` | `TOA211` (warning), default ignored |
| `type: array` with no `items` (3.0 only) | `array-without-items` | `TOA202` (warning), reports only |
| `type: [Item]` together with `isArray: true`: a list of lists | `double-array` | `TOA203` (warning), reports only |
| A nullable enum as `oneOf: [{enum: [null]}, {$ref}]` (NestJS 11) | `nullable-enum-one-of` | `TOA303` (warning), reports only |
| Several controllers with a method of the same name | none | `TOA551` (info), the second gets `2` |
| Operations with several tags | none | `TOA553` (info), generated once, in the first tag's group |

```text
$ typed_openapi check
warning TOA301 duplicate-enum-value: The enum repeats "active"; the repeats are removed and the first occurrence of each value is kept.
  at #/paths/~1products/get/parameters/0/schema/enum
  fix: Remove the repeated values at the source. In NestJS, give the enum its own schema with `enumName` (the CLI plugin option `autoFillEnumName` sets it) instead of spreading several TypeScript enums into one list.
info TOA551 name-collision: Another method of the group is named "findOne"; this one is named "findOne2".
  at #/paths/~1products~1{id}/get
  fix: Name the method explicitly to keep the name stable. Override:
    operations:
      ProductsController_findOne:
        name: findOne2
warning TOA202 array-without-items: This array has no "items", which OpenAPI 3.0 requires; its elements are read as any JSON value.
  at #/components/schemas/ProductDto/properties/tags
  fix: Add "items" with the element schema at the source, or override "items" of this schema. In NestJS, give the element type: @ApiProperty({ type: [Item] }).
warning TOA211 invalid-default: The default, a string, is not of type number; it is ignored.
  at #/components/schemas/ProductDto/properties/stock/default
  fix: Change the default to a value of type number, or remove it. In NestJS, check `default` in @ApiProperty; `excludeDynamicDefaults: true` in SwaggerModule.createDocument leaves out defaults computed at runtime.
warning TOA203 double-array: The items of this array are arrays too and say "required: true", the shape a decorator gives a list declared twice; clients read a list of lists.
  at #/components/schemas/ProductDto/properties/matrix/items
  fix: If the field is a flat list, declare it once at the source; until then, override "items" of this schema with the inner "items". Override: ...
errors: 0, warnings: 7, infos: 1
```

(The output is trimmed to five of the eight diagnostics, `-->` location lines omitted.) The `TOA201`, `TOA301` and `TOA211` findings are repaired in memory; the generated client reads the spec as if they were fixed. The others need an override, or a fix in the backend.

## Overrides

Apply the override each diagnostic suggests. `overrides.yaml` for the sample spec:

```yaml
operations:
  AdminProductsController_findOne:
    name: findOneAdmin
  EventsController_stream:
    sse:
      events:
        created: ProductDto
        removed: null
      unknown: ignore
schemas:
  ProductDto:
    properties:
      currency:
        $ref: "#/components/schemas/Currency"
        nullable: true
      tags:
        items: {type: string}
      matrix:
        items: {type: string}
```

- `name` removes the `findOne` clash between `ProductsController` and `AdminProductsController`.
- `currency` turns the `oneOf` into a nullable reference, so the field is `Currency?`.
- `tags` and `matrix` give the lists their element type: `List<String>?`.
- `@Sse()` endpoints are documented as `text/event-stream` with `type: string`. The `sse.events` override makes them a typed event union; see [Event streams](../generated/event_streams.md).
- A `default` cannot be overridden; `TOA211` already drops a wrong one. Remove it at the source.

With this, `typed_openapi generate` writes the client:

```text
warning TOA301 duplicate-enum-value: The enum repeats "active"; ...
warning TOA211 invalid-default: The default, a string, is not of type number; it is ignored.
warning TOA201 bool-required: Property "name" says "required: true", ...
errors: 0, warnings: 3, infos: 0
Generated shop in lib/shop: 9 files, 9 written, 0 deleted.
```

and the methods are `ProductsApi.findAll`, `create`, `findOne`, `findOneAdmin` and `EventsApi.stream`, which returns `Stream<SseItem<StreamEvent>>`. Accept the remaining warnings with a [baseline](../baseline.md) until the backend is fixed.

## Real specs

`typed_openapi` is tested on NestJS specs from open projects, pinned in the repository's corpus (`packages/typed_openapi_tool/corpus.yaml`). Both generate with `preset: nestjs`:

| Spec | Result of `check` |
| --- | --- |
| Immich (many controllers, `@nestjs/swagger`) | 23 diagnostics, none an error: `TOA553` for operations tagged `Jobs` and `Deprecated`, `TOA550` for parameters named like Dart keywords (`for` becomes `for_`), `TOA551` (the root client already has a member named `server`) and `TOA453` for two `anyOf`s without a discriminator, generated as `JsonValue`. |
| Tambo (SSE, multipart, `discriminator`) | 2 diagnostics, both `TOA207`: an `example` of the wrong shape (an object example on a string schema). |

`TOA453` offers an override that tries the variants (`union: structural`); see [Unions](../generated/unions.md).

## Fix it in the backend

The preset's hints, and the NestJS documentation they point at:

- **Enums:** give each enum its own schema with `enumName`; the Swagger CLI plugin option `autoFillEnumName` does it for all of them.
- **Arrays:** write `@ApiProperty({ type: [Item] })` and do not add `isArray: true`.
- **Defaults:** `excludeDynamicDefaults: true` in `SwaggerModule.createDocument` leaves out defaults computed at run time.
- **Operation ids:** `operationIdFactory` in `SwaggerModule.createDocument` replaces `controllerKey_methodKey`. If you return the method name, make it unique yourself (`TOA504` reports duplicates).
- **Nullable enums:** `@nestjs/swagger` 12 writes nullability according to the document version; on 11.x keep the document at OpenAPI 3.0.

## Caveats

- The preset changes names and advice only; it never edits your spec file.
- Two DTO classes with one name in different modules overwrite each other in `components.schemas`; no tool can see this in the output. Give them unique names in the backend and run `check` in its CI.
- No NestJS-specific envelope or pagination handling exists: generic wrappers are ordinary schemas.

## See also

- [Presets and rules](../presets_and_rules.md): every rule and preset.
- [Overrides](../overrides.md): the file format.
- [Diagnostics](../diagnostics.md): the full catalog.
- [Baseline](../baseline.md): accept what you cannot fix yet.
- [CI](../ci.md): run `check` on the backend's spec in its pipeline.
- Other frameworks: [FastAPI](fastapi.md), [Spring](spring.md), [ASP.NET](aspnet.md).
