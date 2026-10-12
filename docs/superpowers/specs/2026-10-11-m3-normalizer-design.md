# M3: normalizer — design

Date: 2026-10-11. Requirements: R2.1, R2.5, R0.2 ([requirements.md](../../requirements.md)). Defect catalog: [research/06 §C](../../research/06-spec-versions-and-defects.md). Corpus: [research/08](../../research/08-test-corpus.md).

## Decisions

1. **Unambiguous fixes; the rest is diagnostics.** A rule fixes the spec only when the answer follows from the spec itself or from the protocol (HTTP, JSON). If the backend's intent has to be guessed, the rule gives a diagnostic that explains what to fix in the source, and a ready override (the override format — M4).
2. **Only what is in OpenAPI.** Constructs outside the spec are not supported and get a clear diagnostic:
   - `$ref` where OAS does not allow it (the style of the Redocly / swagger-cli bundlers) — a hint "bundle the spec with a bundler";
   - YAML tags outside the JSON Schema ruleset (`!!timestamp`, `!!binary`, `!!set`, custom `!tag`) — an error; the value is read as its text, to show the file's other problems.
3. **Rules work over the model.** A rule reads the typed M2 model (`SpecModel`) and produces findings: a diagnostic and, for fixes, edits of the raw tree (`SpecEdit`: document, JSON pointer, operation). The normalizer applies the edits and rereads the model while there are edits, but no more than 3 passes. Knowledge of OAS structure stays only in the parser. M4 will apply overrides by the same edit mechanism.
4. **Parser diagnostics — from the last pass.** Intermediate passes write to a scratch log. The report gets the diagnostics of the last read and the findings of the rules. So `required: true`, fixed by a rule, does not also give TOA111 from the first read.
5. **Interpretation for Dart — in M6, not in M3.** `allOf` with one `$ref`, inline enum, envelopes, `anyOf` with `null`, `const` → enum, names of methods and groups, `strip-controller-prefix` — these are mapping decisions, not defects of the spec.
6. **Our own YAML composer.** The tree and positions are built from the events of the `package:yaml` parser (`Parser` — an internal module, version pinned in M2), without `loadYamlNode`. One iterative pass gives depth (TOA007), the alias expansion budget (TOA008), duplicate keys (TOA002), tags (see item 2) and non-scalar keys. Collection keys are not hashed, so a "key bomb" is impossible by construction. The check by the M2 events and the `_toPlain` converter go away.
7. **Presets do not enable rules, they refine hints.** All M3 rules concern the spec and are enabled in every preset. A preset (`nestjs`, `fastapi`, `springdoc`, `aspnet`) adds to the message how to fix the defect in the framework's code (recipes — [research/06 §D](../../research/06-spec-versions-and-defects.md)). Each rule is turned off in the config: `rules: {<name>: false}` in `defaults` or in the client; an unknown name — TOA903.

## M3 rules

### Fixes

| Rule | Defect (§C) | What it does | Code / level |
|---|---|---|---|
| `bool-required-to-array` | C-1, C-49 | `required: true` in a property schema → the name goes into `required[]` of the parent schema; `required: false` is removed | TOA201 / warning |
| `dedupe-enum-values` | C-9, C-52 | Equal (JSON-level) `enum` values are removed, the first occurrence is kept. Values that differ only by case are not merged | TOA301 / warning |
| `declare-missing-path-params` | C-6 | A path template variable without a declared parameter → `{name, in: path, required: true, schema: {type: string}}`. Unambiguous: a path segment on the wire is a string | TOA501 / warning |
| `drop-invalid-default` | C-28 | A `default` that does not match the schema's `type` is ignored (like a value with TOA111) | TOA211 / warning |

### Diagnostics only

| Check | Defect (§C) | Code / level |
|---|---|---|
| A path parameter is declared, but is absent from the template (or differs in case) | C-7 | TOA502 / error |
| No `operationId` | C-34 | TOA503 / info |
| Duplicate `operationId` | C-36 | TOA504 / error |
| An array without `items` in a 3.0 document | C-5 | TOA202 / warning |
| Double array: `items` with `type: array` and a boolean `required` | C-49 | TOA203 / warning |
| `format` on an array without `items` | C-50 | TOA204 / warning |
| `type: object` with `format: binary` | C-51 | TOA205 / warning |
| `type: object` next to `oneOf`/`anyOf`, where no branch is an object | C-22 | TOA206 / warning |
| The JSON type of `example` contradicts `type` (an object against an array, etc.) | C-60 | TOA207 / warning |
| Nullable enum through `oneOf` with `{enum: [null]}` and `$ref` | C-54 | TOA303 / warning |
| The discriminator property is not `required` in the subschemas | C-42 | TOA401 / info |
| `discriminator.mapping` leads nowhere (if M2 does not yet resolve the mapping) | C-4 | TOA402 / error |
| `*/*` as a media type | C-38 | TOA601 / warning |
| A key in `components` does not match `^[a-zA-Z0-9\.\-_]+$` | C-32 | TOA106 / warning |
| `$ref` in a place where OAS does not allow it (instead of TOA110) | — | TOA107 / warning |
| `$ref: #/...` without quotes in YAML: the value became `null`, because `#` started a comment | — | TOA108 / warning |
| A YAML tag outside the JSON Schema ruleset | — | TOA009 / error |
| A map key that is not a string (a collection, a number, null) | — | TOA00x / error (the number is in the plan) |

## Out of scope

- Overrides and their application — M4. M3 only prints an override suggestion in the diagnostic text.
- Overriding levels, baseline — M5.
- Interpretation rules and naming — M6.
- `$ref` anywhere, YAML 1.1 — not supported (item 2).
