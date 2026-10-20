## 0.0.1 - Unreleased

### Added
- The package, split from `typed_openapi` (M12b): the engine that loads,
  normalizes and checks an OpenAPI spec and builds the semantic IR, with
  the diagnostics, the config, the baseline, the API snapshot and the diff.
  No behaviour change: the generated output is byte-identical.

### Changed
- An invalid value in a client falls back to the value in `defaults`, and
  then to the built-in default, for every generation setting (`naming`,
  `types`, `errors`, `sse`, `group_by`, `tri_state`, `union`, `exhaustive`,
  `include` and `exclude`). Before, it fell back to the built-in default
  and ignored `defaults`. TOA902 names the value that is applied.
