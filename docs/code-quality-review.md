# Code quality review and agent rules

Date: 2026-10-12. State: branch `main`, commit `6fc5285`. The rules that come
out of this review are in the "Code quality rules" section of `CLAUDE.md`.
No code was changed: this is a diagnosis and a plan.

## 1. Where the requirements come from

| Source | What was taken |
| --- | --- |
| [Google eng-practices: What to look for](https://google.github.io/eng-practices/review/reviewer/looking-for.html) | Complexity is checked at every level (lines, functions, classes); code that "can't be understood quickly" is simplified. Over-engineering: solve the problem you know you have now. Tests in the same change. A comment explains why; if it must explain what, simplify the code. A name is long enough to say what the thing is or does. Update the documentation with the change. |
| [Google C++ Style Guide](https://google.github.io/styleguide/cppguide.html) | "Write short functions": a function over about 40 lines is a reason to check whether it can be split. Composition over inheritance. No classes with only static members. |
| [Effective Dart: Design](https://dart.dev/effective-dart/design) | Class modifiers (`final`, `sealed`, `interface`) say how a class may be extended. No positional `bool`s. `==` together with `hashCode`. Never return `null` instead of an empty collection. |
| Community rules for agents ([agent-friendly-code](https://cdn.jsdelivr.net/npm/aiwg@2026.7.12/agentic/code/frameworks/sdlc-complete/rules/agent-friendly-code.md)) | File 300 lines (warning) / 500 (error), function 30 / 50, nesting 3 / 4, parameters 4 / 6, cyclomatic complexity 10 / 15. Before writing, estimate `current LOC + new lines`; over the threshold, extract first. |

What is not there: Google gives no official number for file size (only
"about 40 lines" for a function). The 300-line file limit is the repository
owner's requirement and a threshold from community rules, not a quote from
Google's standard. The numbers for nesting, parameters and complexity come
from the community rules, which cite no primary source; they are taken as
reasonable defaults.

What the search showed about instruction files themselves: they do not
guarantee compliance. A rule that must hold has to be checked by a linter or
a test (section 5); otherwise the agent will "forget" it and the file will
keep growing.

## 2. Repository metrics

The measurement excludes `lib/src/load/yaml/` (vendored code).

| Metric | Value |
| --- | --- |
| Files in `lib/` | 103 (23,516 lines) |
| Files in `lib/` over 300 lines | **20** |
| Of them, over 500 lines | 10 |
| Largest file | `schema_mapper.dart`, **2196** lines |
| Files in `test/` over 600 lines | 11 (largest 1017) |
| Methods over 50 lines | 35 of about 518 |
| Methods over 80 lines | 9 |
| Methods over 120 lines | 2 (`_model` 151, `ConfigLoader.load` 128) |
| Lines longer than 80 characters | 14 |
| `// ignore:` in `lib/` | 0 |
| `TODO`/`FIXME` | 0 |
| `dynamic` | 9 (probably in doc comments and JSON types, not checked) |
| `late` | 24 |
| `!` operator (rough count) | ~87 |

Methods were counted with a regex script, so the numbers are approximate (a
few methods either way), but the order of magnitude is right.

What is in good shape: zero `ignore`, zero `TODO`, clear pipeline stages (one
folder per stage), most files under 300 lines (83 of 103), no top-level
functions, doc comments everywhere, `sealed` hierarchies instead of flags.

## 3. Findings (by priority)

### P1. `SchemaMapper`: one 2000+ line class with hidden state

`ir/schema_mapper.dart`: 2196 lines, 46 members in one class (`final class
SchemaMapper`, lines 43-2095) and 5 more helper classes in the same file.

- The class does at least six different jobs: mapping a type (`_map`,
  `_component`, `_inline`, `_declare`), models (`_model`, `_merged`,
  `_notesOf`), enums (`_enum`, `_valueName`, `_numberName`), unions (`_union`,
  `_subtypes`, `_variantClass`), tri-state (`_isTriState`), and naming
  (`_claim`, `_memberName`, `_helperName`, `_additionalName`).
- `_union` is about 300 lines (1212-1518), `_model` 151, `_isTriState` 96.
- Hidden mutable state: `_direction`, `_patchTarget`, `_replacing`,
  `_aliases`, `_pending` and `_inlineEnums` are set before a call and read
  deep inside (`typeOf` sets `_direction` and `_patchTarget`, calls `_map`,
  then resets `_patchTarget = null`). A single method cannot be understood or
  tested without knowing who set the field.
- This breaks Google's "complexity" check at all three levels: line,
  function, class.

Proposed split (along the seams already visible in the method names, not by
line count):

| New file (in `ir/`) | What moves there |
| --- | --- |
| `declaration_names.dart` | `_claim`, `_helperName`, `_memberName`, `_additionalName`, `nameDeclarations`, `_referenceName`, `_tokensName`, `_componentKey` |
| `model_mapper.dart` | `_model`, `_merged`, `_notesOf`, `_constraintsOf`, `_isTriState`, `_reportBranchesBesideModel` |
| `enum_mapper.dart` | `_enum`, `_valueName`, `_numberName`, `_enumKind` |
| `union_mapper.dart` | `_union` (split into steps), `_subtypes`, `_findSubtypes`, `_variantClass(es)`, `_mappingTarget`, `_constantProperty`, `_isRawUnion`, `_unionMode` |
| `schema_mapper.dart` | stays as the facade: `typeOf`, `typeOfComponent`, `_map`, `_component`, `_inline`, `_declare` |
| `mapping_state.dart` | `_Pending`, `_Field`, `_FieldNotes`, `_Variant` |

The state `_direction` / `_patchTarget` / `_replacing` becomes a parameter or
a small immutable `MappingScope` passed down.

### P1. `OutputWriter` (896 lines) and `ConfigLoader` (780)

- `output_writer.dart`: the class mixes locking (`_lockHeld`, `_isAlive`),
  recovery (`_leftovers`, `_recover`), installation (`_install`, `_copyMode`,
  `_removeTree`, `_discard`) and the manifest. `OutputWriter.write` is about
  190 lines. Split: `OutputLock`, `OutputRecovery`, `OutputInstaller`,
  `OutputManifest`, with `OutputWriter` as the orchestrator.
- `config_loader.dart`: `load` is 128 lines; `severityAt` 63. Split: reading
  `defaults`, reading a client, and reading `severity`/`rules`/`types` into
  separate readers.

### P2. Other files over 300 lines

In order of size: `yaml_composer.dart` 810, `ir.dart` 733,
`override_applier.dart` 667, `override_loader.dart` 612,
`operation_builder.dart` 565, `ir_builder.dart` 534, `diagnostic_code.dart`
528, `model/operation.dart` 467, `override_resolver.dart` 450,
`schema_shapes.dart` 446, `json_reader.dart` 422, `union_emitter.dart` 416,
`normalizer.dart` 383, `model_emitter.dart` 379, `dio_request_sender.dart`
378, `object_reader.dart` 342, `schema_shape_rules.dart` 341,
`operation_parser.dart` 314.

Notes:

- `ir.dart` (24 types in one file) and `model/operation.dart` (14) look, by
  their names, like data catalogs with almost no logic (not fully checked).
  They split trivially, one `sealed` family per file (`declaration.dart`,
  `field_ir.dart`, `operation_ir.dart`, ...), and the public exports do not
  change because `lib/typed_openapi.dart` exports through `show`.
- `diagnostic_code.dart`, 528 lines: a flat catalog of `TOAnnn` codes with no
  logic. It is the only exception worth keeping.
- `yaml_composer.dart`, 810 lines: a complex algorithm (explicit stack,
  character budget). Split by responsibility: stack and node building,
  budget and depth, handling of keys and tags.

### P2. Long methods outside P1

`ConfigLoader.load` (128), `IrBuilder._group` (112), `OperationBuilder._parameter`
(99), `IrBuilder.build` (95), `EnumEmitter.write` (94), `RefResolver.resolve`
(91), `OverrideApplier._reference` (83), `UnionEmitter._variant` (78). In total
35 methods are over 50 lines. The usual cause is a loop with a `switch` inside
and an `if` that builds a diagnostic inside that. The cure is to move the body
of a branch into a method named for what it does.

### P2. Tests

11 files are over 600 lines, the largest `override_applier_test.dart` (1017),
then `ir_builder_test.dart` (970) and `model_library_test.dart` (891). Tests
are held to the same readability standard as code (Google). Split by
behaviour (`override_applier_nullable_test.dart`,
`override_applier_reference_test.dart`), with shared builders in
`test/helpers/`.

### P3. Smaller things

- `!`: about 87 places. Many can become a pattern (`if (x case final v?)`) or
  an early `return`; `_model` already has `override!` after the check
  `override?.triState != null`.
- `late`: 24 places. Each needs a comment saying where it is initialized
  before the first read (`_Pending.build` is a `late Declaration Function`).
- Three-level ternary chains (`_model`, lines 813-817) belong in a method or
  a `switch`.
- Named parameters of model constructors (`FieldIr` has 15): a candidate for
  grouping (`FieldFlags`, `FieldDocs`) if the fields keep growing.

## 4. What went into the agent rules

The "Code quality rules" section of `CLAUDE.md` has:

1. Limits: file 300, test 500, method 40, parameters 5, nesting 3, class
   about 15 members, one public type family per file.
2. Exemptions: `load/yaml/` and the flat catalog `diagnostic_code.dart`.
3. "Before you write": `wc -l` before extending a file; a file already over
   the limit **does not grow**, and a task that touches it first moves part
   of it to a new file.
4. How to split: by responsibility, by composition; no `part`, no
   `utils`/`helpers`; no hidden state in fields; a refactor is its own commit
   and the generator's output stays byte-identical.
5. Readability: names, comments that say why, `switch` instead of `is`
   chains, no `!`/`dynamic`/unjustified `late`, no speculative abstractions.
6. Tests: in the same commit, one check per test, repeated set-up in helpers.
7. A four-point self-review before saying "done".

## 5. Recommended next steps

The sequenced plan, with the M9 coordination and the safety net, is in
[code-quality-plan.md](code-quality-plan.md).

The rules in `CLAUDE.md` are context, not enforcement. To make them hold:

1. **A ratchet test** `test/quality/size_limits_test.dart` in
   `packages/typed_openapi`: walks `lib/` and `test/` and fails if a file is
   over the limit and not in the exemption list, or if a listed file *grew*.
   The list (20 files now) only shrinks. Without it the 300-line rule is
   broken by the first change to `schema_mapper.dart`. About 60 lines.
2. **The 40-line method limit** in the same test, approximated from
   indentation, with the same exemption list for the 35 current methods.
3. **Lints** for `analysis_options.yaml`, not yet checked for how many
   violations they would raise (enable each one alone first):
   `avoid_positional_boolean_parameters`, `avoid_returning_this`,
   `cascade_invocations`, `parameter_assignments`,
   `prefer_constructors_over_static_methods`, `unnecessary_lambdas`,
   `avoid_equals_and_hash_code_on_mutable_classes`,
   `use_to_and_as_if_applicable`.
4. **Refactoring order** (each a separate commit, generator output
   unchanged): `ir.dart` and `model/operation.dart` (mechanical, no risk) ->
   `OutputWriter` -> `SchemaMapper` (biggest gain, biggest risk) ->
   `ConfigLoader` -> the rest of the list. Do `SchemaMapper` with the
   existing fixtures as a safety net: first move the state into
   `MappingScope`, then split.
5. After each step check: `dart analyze packages`, the tests of both
   packages, `dart format` (0 changes) and a byte-for-byte comparison of the
   generated fixtures.

## 6. Exemption list (single source)

Files already over the limit that may not grow; the list only shrinks.

```
ir/schema_mapper.dart 2196       generate/output_writer.dart 896
load/yaml_composer.dart 810      config/config_loader.dart 780
ir/ir.dart 733                   overrides/override_applier.dart 667
overrides/override_loader.dart 612   ir/operation_builder.dart 565
ir/ir_builder.dart 534           model/operation.dart 467
overrides/override_resolver.dart 450 ir/schema_shapes.dart 446
runtime json/json_reader.dart 422    emit/union_emitter.dart 416
normalize/normalizer.dart 383    emit/model_emitter.dart 379
runtime dio/dio_request_sender.dart 378  parse/object_reader.dart 342
normalize/rules/schema_shape_rules.dart 341  parse/operation_parser.dart 314
```

Permanent exemption (not to be split): `diagnostics/diagnostic_code.dart`.
