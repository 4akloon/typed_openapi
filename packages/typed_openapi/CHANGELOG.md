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
- Loading: nesting deeper than 1000 levels, in the text or once YAML aliases
  are expanded, is reported (TOA007) instead of crashing; an alias bomb, or
  very long keys (the JSON pointers of all nodes add up to more than
  `max(16000000, 20 * text length)` characters), is reported (TOA008)
  instead of hanging or exhausting memory. YAML aliases are supported only as
  block values (`key: *a`, `- *a`, `<<: *a`); an alias in a flow collection
  or in key position, and (in a document with aliases) an explicit `?` key,
  is reported (TOA008), because the YAML parser would expand it before any
  check runs. YAML keys such as `1` and `"1"` that merge into one JSON key
  are reported (TOA002); a directory given as the spec or the config is
  reported as such.
- A region of a spec that several `$ref`s, enclosing nodes or clients reach is
  read once, and an identical diagnostic is reported once.
