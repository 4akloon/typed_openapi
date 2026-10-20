## 0.0.1 - Unreleased

### Added
- The package, split from `typed_openapi` (M12b): the engine that loads,
  normalizes and checks an OpenAPI spec and builds the semantic IR, with
  the diagnostics, the config, the baseline, the API snapshot and the diff.
  No behaviour change: the generated output is byte-identical.
