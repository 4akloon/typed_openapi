## 0.3.1 - Unreleased

### Added
- `DiagnosticCode.findingsOutsideGeneratedApi` (`TOA811`, info): `SpecChecker`
  lowers to info the errors and warnings located in operations the client's
  filters or `exclude: true` overrides leave out and in nodes only those
  operations use (found by incoming references: a node a generated
  operation refers to, a subtype of a discriminated union at any depth or
  through aliases, a `discriminator.mapping` target, the
  `errors.default_schema` or a `$ref` into a left out operation from outside
  keeps its level; a client's `severity` entry is applied afterwards and
  wins), and reports how many.
- `DartNames.eventPascal`, which names the variants of an event union and
  their data types: every all-caps piece of an event name is lowercased after
  its first letter (`USER_CREATED` is `UserCreated`, not `USERCREATED`).
- `DiagnosticCode.overrideOperationNotGenerated` (`TOA810`, warning): an
  overrides entry addresses an operation that `include`/`exclude` leaves out.

### Changed
- An inline enum is a declaration of its own site: two inline enums with equal
  values are no longer merged into one declaration named after the first site.
- `IrJson` dumps every field the emitters read (descriptions, defaults,
  constraints, known and unknown names, dispatch) and can write the IR without
  locations (`IrJson.withoutLocations`), which the generator hashes for the
  manifest. The shape changed: enum `cases` was a map and is now a list of
  objects.

## 0.3.0

### Changed
- `DartNames.takenTypeNames` reserves `SseRetry`, the new type of
  `typed_openapi_client` 0.3.0: a schema with that name gets a suffix.
- The root client reserves `defaults` among its members, since its
  constructor takes a parameter of that name: a group named `defaults` gets a
  suffix (TOA551).

## 0.2.0

### Changed
- `DartNames.takenTypeNames` reserves `SseCooldown`, `SseTrace` and
  `SseTraceKind`, the new types of `typed_openapi_client` 0.2.0: a schema
  with one of these names gets a suffix, as the other runtime types do.

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
