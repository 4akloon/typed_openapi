# M4: overrides — design

Date: 2026-10-12. Requirements: R3.1, R3.2 ([requirements.md](../../requirements.md)); R3.3 (Overlay, JSON Patch) — outside M4. Research: [research/06 §B](../../research/06-spec-versions-and-defects.md), [research/README](../../research/README.md) (R3: a mandatory `reason` in Stainless, the diagnostic "override did not find its target", overrides are logical, not by generated names). Previous stage: [M3 design](2026-10-11-m3-normalizer-design.md).

## Decisions

1. **Our own logical format.** The file `typed_openapi.overrides.yaml` (the path is `clients.<name>.overrides` in the config, JSON or YAML, read by the M3 composer). A target is addressed by a spec entity, not by a JSON pointer and not by a generated name: an operation — by `operationId` or `METHOD /path`, a schema — by its key in `components.schemas`, a property, a parameter, a response — nested in them. Overlay 1.2 and JSON Patch (R3.3) — a separate stage later.
2. **M4 reads and checks the whole file, but applies only spec fields.**
   - Spec fields (`type`, `format`, `nullable`, `required`, `items`, `additionalProperties`, `enum`, `discriminator`, a schema as `$ref`, a response schema, the body's content type, the parameter's `required`/`schema`) become edits of the raw tree (`SpecEdit`) and are applied by the M3 edit engine.
   - Generation fields (`name`, `exclude`, `exhaustive`, `group`, the Dart type of R6.8 `{type, import, converter}`, the schemas of SSE events, the tri-state mode) are checked and stored in the typed override model, which M6+ will receive. In M4 they change nothing.
3. **Overrides — before the normalizer rules.** Order: read → overrides (edits, reread) → normalizer passes. The rules already see the fixed spec, so a defect closed by an override is not reported.
4. **An override value replaces the spec value** (the "set" semantics): a list replaces a list, a scalar — a scalar; an override map is applied field by field (each listed field is replaced, unlisted ones remain). There is no merging of lists, as in Overlay.
5. **`nullable` in an override is abstract.** Application accounts for the document's dialect: in 3.0 — `nullable: true`, in 3.1+ — `null` in `type`.
6. **R3.2.** Target not found — a warning, the other overrides are applied. An override changed nothing (the spec already has this value) — info "the override can be removed". Both reports point to the override's position in the overrides file, with `reason` if there is one.
7. **`reason` is optional**, but is printed in the diagnostic about an override (stale, redundant, conflicting).
8. **Ambiguous or conflicting addressing is an override error, not a guess.** An `operationId` that occurs twice; two entries for the same target (`getPet` and `GET /pets/{id}`); a parameter whose name is ambiguous between `in` values — a diagnostic with a hint on how to specify the address.
9. **Hints of the M3 rules get a ready override fragment.** A rule that only diagnoses (double array, `format` on an array, object + binary, nullable enum through `oneOf`, an array without `items`, a contradictory `type`, a parameter outside the template, etc.) adds a YAML fragment to `fix` that can be copied into the overrides file. The fragment's address is computed from the diagnostic's location; if the location has no logical address, there is no fragment.
10. **Codes — the 8xx range** (TOA800 is already taken by "edit not applied"): an invalid overrides file, a target not found, an override that changed nothing, an ambiguous target, a conflict of two overrides. The concrete numbers are in the plan.

## Out of scope

- Overlay 1.2, JSON Patch (R3.3).
- Consumption of generation fields — M6 and later.
- Baseline and overriding levels — M5.
