## 0.0.1 - Unreleased

### Added
- `typed_openapi check`: reads every client from `typed_openapi.yaml`, loads
  its spec (JSON or YAML) with source positions, detects the OpenAPI version
  and reports diagnostics with stable codes and JSON pointers, as text or JSON.
- Programmatic API: `ConfigLoader`, `SpecLoader`, `OpenApiVersionDetector`,
  `SpecChecker`, `TextReporter`, `JsonReporter`, `TypedOpenApiCli`.
- `check` reads each spec into a typed model that is a superset of OpenAPI
  3.0, 3.1 and 3.2 (`SpecReader`, `SpecModel`) and reports unknown keys
  (TOA110), wrong value types (TOA111) and missing required fields (TOA112).
- `$ref` resolution inside a document and across local files, keyed by file
  URI and JSON pointer: invalid or truncated refs (TOA100), unresolved refs
  (TOA101), remote refs (TOA102), reference loops (TOA103), refs to the wrong
  kind of node (TOA104), ignored `$id`/`$self` (TOA105).
- The dialect is detected by content: 3.1 constructs in a 3.0 document
  (TOA020), `nullable` in 3.1+ (TOA021), 3.2 constructs in older documents
  (TOA022).
- Loading: YAML and JSON are read by `YamlComposer` from the events of a
  copy of package:yaml's parser, in one iterative pass. Nesting deeper than
  1000 levels, also once aliases are expanded, is TOA007; an alias bomb or
  very long keys (JSON pointers of all built nodes above
  `max(16000000, 20 * text length)` characters) are TOA008. A collection as a
  mapping key is TOA113 and is never built, so a key cannot hide an alias
  bomb; a null key is TOA114. Keys are their text (`200:` is `"200"`); keys
  that are one JSON key are TOA002, the last value wins. YAML tags outside
  the JSON Schema ruleset (`!!timestamp`, `!!binary`, `!custom`) are TOA009
  and the value is read as text; parser warnings are TOA015. The copied
  scanner is linear on long flow lines (dart-lang/tools#2657), so hostile
  one-line files are rejected in moments. A directory given as the spec or
  the config is reported as such; package:yaml is no longer a runtime
  dependency (it is used by tests only).
- `$ref` where OpenAPI does not accept a Reference Object (an operation,
  `description`) is TOA107 with a hint to bundle the spec (`redocly bundle`);
  `$ref: #/...` without quotes, which YAML reads as a comment, is TOA108; the
  YAML merge key `<<` is TOA109.
- Normalizer: `check` runs named rules over the model and applies the fixes
  that follow from the spec or the protocol, reading the spec again (at most
  3 passes; a fix that cannot be applied is TOA800). Fixes:
  `bool-required-to-array` (TOA201), `drop-invalid-default` (TOA211),
  `dedupe-enum-values` (TOA301), `declare-missing-path-params` (TOA501).
  Diagnostics: arrays without `items` in 3.0 (TOA202), double arrays (TOA203),
  `format` on an array (TOA204), binary objects (TOA205), `type: object`
  against non-object branches (TOA206), examples of the wrong type (TOA207),
  nullable enums through `oneOf` (TOA303), discriminator property not
  required (TOA401), unresolved discriminator mapping (TOA402), path
  parameters not in the template (TOA502), missing and duplicate
  `operationId` (TOA503, TOA504), `*/*` media types (TOA601), component keys
  with invalid characters (TOA106), and an example of another scalar type
  (TOA208, info). Presets add framework recipes to the hints;
  `rules: {<name>: false}` in `defaults` or a client turns a rule off. The
  rule names are `array-without-items`, `binary-object`,
  `bool-required-to-array`, `component-key-characters`,
  `contradictory-object-type`, `declare-missing-path-params`,
  `dedupe-enum-values`, `discriminator-mapping-target`,
  `discriminator-property-required`, `double-array`,
  `drop-invalid-default`, `duplicate-operation-id`,
  `example-type-mismatch`, `format-on-array`, `missing-operation-id`,
  `nullable-enum-one-of`, `path-param-not-in-template` and
  `wildcard-media-type`. An unknown name is TOA903 (the message lists the
  known ones); a `rules` value that is not a map, or a rule set to anything
  but `true` or `false`, is TOA902.
- Programmatic API: `Normalizer`, `NormalizedSpec`, `NormalizerRule`,
  `RuleContext`, `Finding`, `SpecEdit`, `EditOperation`, `SpecDocuments`.
- A region of a spec that several `$ref`s, enclosing nodes or clients reach is
  read once, and an identical diagnostic is reported once.
- Overrides: `clients.<name>.overrides` names a JSON or YAML file that
  addresses operations (`operationId` or `METHOD /path`), their parameters
  (`name` or `in:name`), request body and responses, and schemas of
  `components.schemas` with their properties. Spec fields (`type`,
  `format`, `nullable`, `required`, `items`, `additionalProperties`, `enum`,
  `discriminator`, `$ref`, parameter `required`/`schema`, body and response
  `contentType`/`schema`) replace the spec's values before the normalizer
  runs (`null` removes a field; `nullable` follows the document's dialect;
  in OpenAPI 3.0 a field other than `nullable` or `description` that would
  sit beside a `$ref` is not written, TOA800: override the referenced schema
  by name). Generation fields (`name`, `exclude`, `group`, `exhaustive`,
  `dartType`, `triState`) are checked and kept for the generator. Every
  entry may have a `reason`, printed in diagnostics about it. An empty file
  is no overrides. A missing overrides file is TOA801, a directory or an
  invalid value TOA802, an unknown key the error TOA803 (with "did you
  mean" for a close known key), an override whose target is gone TOA804
  (warning), an ambiguous address TOA805, two overrides of one node TOA806,
  an override the spec already matches TOA807 (info, "can be removed"), and
  a change through an operation of a node other operations share TOA808
  (info). An overrides file that cannot be used is an error and the spec is
  checked without it.
- The fixes of `double-array`, `format-on-array`, `binary-object`,
  `contradictory-object-type` and `nullable-enum-one-of` end with the
  override to copy into the overrides file, when the schema is in
  `components.schemas` or is one of its properties (`format-on-array` only
  for a format whose element type is known; none for a schema with `$ref` in
  OpenAPI 3.0 or a value YAML cannot carry).
- Programmatic API: `OverrideLoader`, `OverrideSet`, `OverrideEntry`,
  `OperationOverride`, `ParameterOverride`, `BodyOverride`,
  `ResponseOverride`, `SchemaOverride`, `PropertyOverride`,
  `DartTypeOverride`; `Normalizer.normalize` takes `overrides:` and
  `NormalizedSpec.overrides` returns them.
