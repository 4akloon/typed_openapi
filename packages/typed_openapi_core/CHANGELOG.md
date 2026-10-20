## 0.2.0 - Unreleased

No changes; the version moves with `typed_openapi_client` 0.2.0 (the four
published packages share one version).

## 0.1.0

### Added
- SARIF rules carry a `helpUri` that links the code's entry in the generated
  diagnostics catalog (`DiagnosticCode.helpUri`) (M13).
- `Diagnostic.backendFix`, the fix at the source of the spec, which `lint`
  prints in place of the config fix; `SpecLinter` runs the checks of a single
  spec without a config and `PresetDetector` guesses the framework preset
  from the spec (M13).
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
