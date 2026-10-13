# Presets and rules

The normalizer reads your spec, finds the mistakes that code-first frameworks make, and repairs the ones it can in memory. It never edits your spec file. Each finding is a [diagnostic](diagnostics.md) with a code, a position and a fix text; a preset adds the advice for your framework to that text.

```yaml
defaults:
  preset: nestjs
  rules:
    array-without-items: false
```

## Presets

`preset` is one of five names, set per client or in `defaults`. A preset changes no behaviour of the rules. It adds a framework-specific hint to the `fix:` text of the rules it knows, and `nestjs` also changes one naming default.

| Preset | Hints for rules | Other effect |
| --- | --- | --- |
| `generic` | none | none (the default) |
| `nestjs` | `drop-invalid-default`, `array-without-items`, `double-array`, `dedupe-enum-values`, `nullable-enum-one-of` (`@nestjs/swagger` 12 versus 11.x), `duplicate-operation-id` (`operationIdFactory`) | Removes `^[A-Za-z0-9]*Controller_` from every `operationId` unless `naming.operation_prefix` is set |
| `fastapi` | `duplicate-operation-id` (`generate_unique_id_function`), `discriminator-mapping-target` | none |
| `springdoc` | `duplicate-operation-id`, `discriminator-mapping-target`, `wildcard-media-type` (`springdoc.default-produces-media-type`), `component-key-characters` (`@Schema(name=...)`) | none |
| `aspnet` | `missing-operation-id` (`.WithName`, `EndpointName`, Swashbuckle `CustomOperationIds`), `discriminator-property-required` (`[JsonPolymorphic]`), `component-key-characters` (`CustomSchemaIds`) | none |

```text
warning TOA301 duplicate-enum-value: The enum repeats "toys"; the repeats are removed and the first occurrence of each value is kept.
  --> specs/shop.yaml:42:13
  at #/components/schemas/Category/enum
  fix: Remove the repeated values at the source. In NestJS, give the enum its own schema with `enumName` (the CLI plugin option `autoFillEnumName` sets it) instead of spreading several TypeScript enums into one list.
```

That is the `nestjs` preset on a NestJS-style spec. With `generic` the same diagnostic ends after "at the source." When several clients with different presets share a finding, the hints are prefixed with the preset name.

## The rules

Eighteen rules run in this order. Turn one off with `rules: {<name>: false}` in `defaults` or in a client; an unknown name is TOA903. The code column links to the meaning in [Diagnostics](diagnostics.md).

| Rule | Code | Detects | Repairs |
| --- | --- | --- | --- |
| `bool-required-to-array` | TOA201 | `required: true` on a property (OpenAPI 2 style) | Moves the name into the parent's `required` list |
| `drop-invalid-default` | TOA211 | A `default` not of the schema's type | Removes the default |
| `array-without-items` | TOA202 | An array with no `items`, in 3.0 only | Reports only |
| `double-array` | TOA203 | `items` that is itself an array with a boolean `required` (a list declared twice) | Reports only |
| `format-on-array` | TOA204 | `format` on an array instead of on its elements | Reports only |
| `binary-object` | TOA205 | `type: object` with `format: binary` | Reports only |
| `contradictory-object-type` | TOA206 | `type: object` beside a `oneOf`/`anyOf` of other types | Reports only |
| `example-type-mismatch` | TOA207, TOA208 | An `example` of the wrong structure (TOA207) or scalar type (TOA208, info) | Reports only |
| `dedupe-enum-values` | TOA301 | An `enum` that repeats a value | Removes the repeats, keeps the first |
| `nullable-enum-one-of` | TOA303 | A nullable enum written as `oneOf` of a null-only enum and a `$ref` | Reports only |
| `declare-missing-path-params` | TOA501 | A path variable with no path parameter | Adds a required string path parameter |
| `path-param-not-in-template` | TOA502 | A path parameter that is not a variable of the template (or differs in case) | Reports only |
| `missing-operation-id` | TOA503 | An operation with no `operationId` | Reports only; the method is named from the HTTP method and path |
| `duplicate-operation-id` | TOA504 | Two operations with one `operationId` | Reports only |
| `discriminator-property-required` | TOA401 | A discriminator property that a variant does not require | Reports only |
| `discriminator-mapping-target` | TOA402 | A `discriminator.mapping` value pointing nowhere | Reports only |
| `wildcard-media-type` | TOA601 | `*/*` as a media type | Reports only |
| `component-key-characters` | TOA106 | A `components` key with characters OpenAPI does not allow | Reports only |

Four rules produce edits: `bool-required-to-array`, `drop-invalid-default`, `dedupe-enum-values` and `declare-missing-path-params`. The others only report, and give an override snippet where one helps (see [Overrides](overrides.md)). `array-without-items` is skipped on 3.1 documents. `bool-required-to-array` leaves a parent whose `required` is not a list alone and reports TOA201 without an edit. TOA401 is not reported when the discriminator holder itself requires the property.

## Passes

The normalizer runs at most three passes: read the spec, run the rules, apply their edits, read again. Edits go to a copy of the tree, so the files stay as they are. An edit equal to one already applied is skipped. An edit that touches the same node as an applied one waits for the next pass, where its rule proposes it again if it is still needed. An edit still proposed after three passes, or whose file cannot be read, or whose target has gone, is TOA800 (`fix-not-applied`).

Overrides are applied once, before the first pass, so the rules see the overridden spec.

## See also

- [Configuration](configuration.md): `preset` and `rules`.
- [Overrides](overrides.md): repair what a rule only reports.
- [Diagnostics](diagnostics.md): every code.
- [Getting started](getting_started.md): the rules on a real spec.
