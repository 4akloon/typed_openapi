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
| Effective Dart: [Style](https://dart.dev/effective-dart/style), [Usage](https://dart.dev/effective-dart/usage), [Documentation](https://dart.dev/effective-dart/documentation) | The rules behind the lints, and the ones no lint checks (acronyms, doc-comment shape, `///` summary, "Whether" for booleans, no tag-style `@param`). The latter went into `CLAUDE.md`. |
| [Dart linter rule catalog](https://dart.dev/tools/linter-rules/all) (data: `linter_rules.json` in dart-lang/site-www) | 264 rules with state, sets, categories, `incompatible` pairs and the SDK version of each. Used for section 7. |
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
3. **Lints** for `analysis_options.yaml`: done, see section 7 (40 rules
   enabled, the rest staged). The list that was proposed here before the
   trial, for the record:
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

Files and methods already over their limit that may not grow; the list only
shrinks. The single source is now the allowlists in the ratchet tests, one per
package:

- `packages/typed_openapi/test/quality/size_limits_test.dart`
- `packages/typed_openapi_runtime/test/quality/size_limits_test.dart`

Each holds a file allowlist (path -> lines), a method allowlist
(`path#Type.name` -> lines, methods over 40 lines of `lib/`) and the
permanent exemptions. The tests fail on a file or method over its limit that
is not listed and on a listed one that grew; a listed unit that shrank or is
within its limit again is a stale entry that is deleted (nothing fails, so
nothing reminds you). A new entry is never added: the unit is split instead.
The measuring code is `test/helpers/size_limits.dart` (the method check is an
indentation heuristic, expression bodies are not seen). The numbers that were
listed here in this document are not kept: they would go stale.

Permanent exemption (not to be split): `diagnostics/diagnostic_code.dart`.

## 7. Lint analysis

Method (2026-10-12, SDK 3.13.1, `lints` 6.1.0): the catalog has 264 rules
(233 stable, 11 experimental, 6 deprecated, 14 removed). Before this work the
project used `lints/recommended` plus 46 explicit rules. The 109 stable and
experimental rules that were not enabled were switched on together in a trial
run (27,773 findings) and counted per rule. Then each rule was judged by:
stable, available in the minimum SDK (3.10), no `incompatible` clash with an
enabled rule, fits Effective Dart or the rules of this repository, and no
findings (this cleanup touches no source while M9 is open).

Result:

- **Enabled now: 40 rules, zero findings** (`dart analyze packages` stays
  clean). Grouped in `analysis_options.yaml` by purpose:
  - types and signatures: `avoid_annotating_with_dynamic`,
    `avoid_types_on_closure_parameters`, `always_put_required_named_parameters_first`,
    `avoid_final_parameters`, `parameter_assignments`,
    `tighten_type_of_initializing_formals`;
  - class design: `avoid_returning_this`, `avoid_setters_without_getters`,
    `use_setters_to_change_properties`, `use_to_and_as_if_applicable`,
    `avoid_implementing_value_types`, `prefer_mixin`,
    `avoid_field_initializers_in_const_classes`,
    `prefer_const_constructors_in_immutables`,
    `prefer_const_literals_to_create_immutables`,
    `sort_unnamed_constructors_first`, `prefer_asserts_in_initializer_lists`;
  - expressions: `unnecessary_lambdas`, `join_return_with_assignment`,
    `switch_on_type`, `use_is_even_rather_than_modulo`,
    `use_truncating_division`, `prefer_int_literals`,
    `noop_primitive_operations`,
    `unnecessary_null_aware_operator_on_extension_on_nullable`;
  - errors and async: `avoid_catches_without_on_clauses`, `avoid_slow_async_io`,
    `avoid_print` (the generator reports through diagnostics, never prints);
  - web: `avoid_double_and_int_checks` (int and double are one type in JS),
    `avoid_js_rounded_ints`, `no_runtimetype_tostring`;
  - imports and docs: `prefer_relative_imports` (the repository convention),
    `conditional_uri_does_not_exist`, `unnecessary_library_directive`,
    `missing_code_block_language_in_doc_comment`;
  - deprecation, tests, pubspec: `deprecated_consistency`,
    `deprecated_member_use_from_same_package`, `unnecessary_ignore`,
    `use_test_throws_matchers`, `sort_pub_dependencies`.
- **Removed:** `unnecessary_await_in_return` (deprecated; the analyzer says to
  drop it).
- **Staged, valuable, a few findings in files M9 will change** (counts from the
  trial; enable after M9 merges, phase 3 of the plan):

  | Rule or flag | Findings |
  | --- | --- |
  | `strict-casts`, `strict-inference`, `strict-raw-types` | 6 (one in `dio_request_sender.dart`, one is a compile error in a test only strict-casts finds) |
  | `avoid_equals_and_hash_code_on_mutable_classes` | 24 (add `@immutable`) |
  | `comment_references` | 16 |
  | `missing_whitespace_between_adjacent_strings` | 11 (a real bug class in messages) |
  | `cast_nullable_to_non_nullable`, `avoid_escaping_inner_quotes` | 10 each |
  | `avoid_redundant_argument_values` | 6 |
  | `discarded_futures` | 5 |
  | `prefer_expression_function_bodies`, `prefer_foreach` | 3 each |
  | `avoid_positional_boolean_parameters`, `unnecessary_null_checks`, `unawaited_futures`, `async_return_with_no_await`, `prefer_constructors_over_static_methods` | 2 each |
  | `unnecessary_parenthesis`, `prefer_void_to_null`, `omit_obvious_local_variable_types`, `document_ignores`, `simplify_variable_pattern` | 1 each |
  | `omit_obvious_property_types`, `specify_nonobvious_property_types` | 42, 12 (Effective Dart's newer advice on obvious types) |
  | `lines_longer_than_80_chars` | 21 (long strings the formatter cannot wrap) |

- **Needs a newer SDK than 3.10** (enable when the minimum SDK is raised):
  `initialize_in_field_declaration` (3.13), `simple_directive_paths` (3.12),
  `no_dynamic_casts`, `no_raw_types` (3.13), and the primary-constructor
  rules (`use_declaring_parameters`, `unnecessary_primary_constructor_body`,
  `unnecessary_type_name_in_constructor`), which also contradict the rule
  that primary constructors are not used.
- **Rejected on purpose:**

  | Rule | Findings | Why |
  | --- | --- | --- |
  | `prefer_double_quotes` | 12,535 | clashes with `prefer_single_quotes` |
  | `always_use_package_imports` | 444 | clashes with `prefer_relative_imports` |
  | `unnecessary_final` | 3,737 | clashes with `prefer_final_locals` |
  | `always_specify_types`, `specify_nonobvious_local_variable_types`, `omit_local_variable_types` | 7,812, 2,460, 12 | the code uses inferred `final` locals |
  | `always_put_control_body_on_new_line` | 510 | formatting taste, not Effective Dart |
  | `cascade_invocations` | 60 | stylistic; revisit later |
  | `no_adjacent_strings_in_list` | 19 | long messages are written as adjacent strings |
  | `do_not_use_environment` | 2 | the web check uses `bool.fromEnvironment` on purpose |
- **Not applicable:** the Flutter widget rules, the experimental rules (their
  behaviour may still change), and rules with no use here.

No lint measures file or method size, so those limits stay with the ratchet
test (plan, phase 0).
