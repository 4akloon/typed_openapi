# M3 plan: normalizer

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `typed_openapi check` reads YAML with its own composer (tags outside the JSON Schema ruleset, non-scalar and null keys, depth and aliases — in one iterative pass, without a quadratic scanner and without `print`), says where `$ref` or the merge key `<<` stand outside OpenAPI, and runs the spec through an engine of named rules: unambiguous defects are fixed by edits of the raw tree with re-reading of the model, the rest is a diagnostic with advice on what to fix in the source, and a framework recipe from a preset.

**Architecture:** `load/yaml/` — the scanner and parser of `package:yaml` 3.1.4 (MIT) with local edits (linear cost of flow lines, assert → syntax error, warnings to a handler). `load/yaml_composer.dart` — `YamlComposer` builds a plain tree from the parser's events and positions by JSON pointer; `SpecLoader` and `ConfigLoader` use it; `YamlEventGuard`, `loadYamlNode` and `_PlainConverter` go away. A new layer `normalize/`: `SpecEdit` + `TreeEditor` (edits by copying on write), `NormalizerRule` + `RuleContext` + `Finding`, `Normalizer` (up to 3 passes read → rules → edits; parser diagnostics only from the last pass) and 18 rules in `normalize/rules/`. `SpecChecker` calls `Normalizer` instead of `SpecReader`.

**Tech Stack:** Dart `>=3.10.0 <4.0.0`, pure Dart; dependencies `args`, `io`, `path`, `source_span`, new direct `collection` and `string_scanner` (already pulled in by `package:yaml`, now the copied scanner); `yaml` moves to `dev_dependencies` (only for comparison tests); tests on `package:test`.

**Spec:** [docs/superpowers/specs/2026-10-11-m3-normalizer-design.md](../specs/2026-10-11-m3-normalizer-design.md) — decisions 1–7 and two rule tables. Requirements: R2.1, R2.5, R0.2 ([requirements.md](../../requirements.md)). Defects and recipes: [research/06 §C, §D](../../research/06-spec-versions-and-defects.md). Corpus and first run: [research/08](../../research/08-test-corpus.md). The stage's place — [roadmap.md](../../roadmap.md), M3 and "Moved from M2". Code rules — [CLAUDE.md](../../../CLAUDE.md).

## Global Constraints

- SDK `>=3.10.0 <4.0.0`; both packages are pure Dart. Primary constructors (Dart 3.13) are not used.
- Dart 3.10 actively: dot shorthands wherever the context type is known (`.nestingTooDeep`, `severity: .error`, `case .key`), null-aware collection elements, switch expressions and patterns, records, class modifiers (`final`, `sealed`, `base`). In tests the arguments of `expect(...)` are full names (`DiagnosticCode.boolRequired`).
- OOP: no top-level functions except `main` in `bin/` and tests. Components that report get a `DiagnosticBag` through the constructor (`YamlComposer(bag)`, `Normalizer(bag)`). The exception is the copied code in `load/yaml/`: it stays in the `package:yaml` style and is checked only against `package:lints/recommended.yaml` (its own `analysis_options.yaml` in the folder).
- Input errors are not thrown: they go to `DiagnosticBag`, and the rest of the document is read. Only `YamlException` is caught; `AssertionError` in `lib/` is not caught (lint `avoid_catching_errors`): the scanner's assert that invalid documents break is replaced in the copy with a syntax error.
- Every new code goes into `DiagnosticCode` with a doc comment, a kebab-case slug, a default level, a file, a JSON pointer and, when known, a position; the message says what to fix in the source (R2.2, R2.5).
- Determinism (R13.1): rules walk nodes in `SpecLocation` order (`SpecModel.nodes`), rules run in `Normalizer.rules` order, the report is sorted by `DiagnosticBag.sorted`.
- Rules do not change the model and do not read text: they return a `Finding` with `SpecEdit`s; only `Normalizer` applies them and re-reads. Knowledge of the OAS structure lives only in the parser.
- Overrides (M4) are not applied in M3: the diagnostic only names the field and the value worth overriding, without the syntax of the overrides file.
- A preset does not turn rules on or off (decision 7): it only adds a framework recipe (`NormalizerRule.hint`) to `fix`, and only where it appears in research/06 §D.
- Fixtures are invented and small. A private company spec is used neither as a fixture nor as a source of fixtures. The public corpus (research/08) is used only for the `check` run.
- Lints come from the root `analysis_options.yaml`; `dart analyze packages` from the root — `No issues found!`; `dart format lib test bin` (from `packages/typed_openapi`) — a second run changes 0 files.
- Tests do not touch the network; temporary files only through `test/helpers/temp_dir.dart`. Hostile inputs are checked only with a generous `timeout:`, with no time measurements in tests.
- The commands `dart test`, `dart format` run from `packages/typed_openapi`; `dart pub get`, `dart analyze packages`, `git apply` and `git` run from the repository root. The diffs in the plan are applied with `git apply` (from the root).
- Every commit uses Conventional Commits and ends with a `Co-Authored-By` line of the model that performs the task (in the examples — `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`).

## Decisions made

The decisions of the M3 spec are mandatory; here are only the items the spec leaves to the plan, and the controller's decisions on open questions of earlier plan versions.

1. **Scalar keys are text (YAML Failsafe, as OAS requires for keys).** `200:`, `true:`, `0x1F:` are keys `"200"`, `"true"`, `"0x1F"` without a diagnostic (`200:` is everywhere). A null key (`~:`, `null:`, empty) — `TOA114 null-key` warning "quote it", read as text. A collection key or an alias of a collection — `TOA113 non-string-key` error (the range of structure next to TOA110–TOA112); the entry is skipped, nothing in it is built, so a "bomb in a key" is impossible.
2. **Scanner asserts.** The M2 fuzz (300 000 inputs, seed 11) catches `assert(_simpleKeyAllowed || !required)` in `Scanner._saveSimpleKey` on 86 documents; without the asserts all 86 end with `YamlException`. The scanner copy reports, instead of an assert, the syntax error `Expected a key at this indentation.` at that place; other asserts on the path (`Parser` — constructor arguments and `streamStart`) cannot be broken by input. The test runs the same 300 000 documents through the composer: no `AssertionError` escapes. The comparison fuzz with `loadYamlNode` (upstream) skips the documents on which the assert of `package:yaml` itself fails — this is the only `catch (AssertionError)`, and it is in the test.
3. **The quadratic scanner is fixed in the copy** (https://github.com/dart-lang/tools/issues/2657): `_staleSimpleKeys` exits at once outside block context, and `_fetchMoreTokens` checks only the first live simple key. A ~1 MB file with "hidden" brackets — from 57 s to fractions of a second; the "count brackets before the parser" workaround from M2 is not needed. Tests from branch `fix/yaml-quadratic-scan` (commit 719bd46, not merged) are retargeted to the composer.
4. **Parser warnings — `TOA015 yaml-warning`.** `warn()` of `package:yaml` printed to stdout (spoiling `--format json`); the copy passes warnings to `YamlWarningHandler`, and the composer reports them with a position.
5. **Duplicate keys.** Keys that are equal for YAML itself (`a` and `"a"`), outside `.json` — TOA002 with level **error** (`DiagnosticBag.report(severity:)`), but reading continues and the last value wins (as `JSON.parse` and `jsonDecode` do), and the message says so. The default level of TOA002 in the catalogue stays warning: it reports keys that are equal only as JSON keys (`1`/`"1"`) and any duplicates in `.json`.
6. **Merge key `<<` — `TOA109 yaml-merge-key` warning** (task 3): OpenAPI's YAML is the JSON Schema ruleset, which has no merge keys and no merging. In an object the key stays an ordinary (unknown) key; in a map of named entries (`components.*`, `paths`, `responses`, `properties` …) the `<<` entry after TOA109 is skipped, so that it does not become a schema or a path named `<<` and does not cascade into TOA110.
7. **The fallback `jsonDecode` for `.json` stays**, although no example of valid JSON that the parser rejects has been found (surrogate pairs, `\/`, tabs and keys longer than 1024 characters are read).
8. **TOA107 instead of TOA110/TOA111.** `$ref` as an unknown key of an object (operation `get: {$ref: ...}`) and an object-`$ref` where a string or another value is expected (`description: {$ref: ...}`, `tags: [{$ref: ...}]`) — `TOA107 ref-not-allowed` with a hint about `redocly bundle`. There is no "`$ref` anywhere" substitution. Rules that read operations (TOA501, TOA503) skip an operation written as `$ref`.
9. **TOA108 is determined from the text next to an empty value.** `package:yaml` places an empty block value at the key's `:`, and an empty flow value at the next token (on the next line, when a comment closed the line). `ObjectReader` checks both places.
10. **Normalizer passes.** A pass = read → all rules. If there are edits and the pass is not the third, all findings of the rules that have edits in this pass go into the report (a rule may put one edit on the first of several findings), the edits are applied, and the document is re-read. Otherwise the pass is the last one: the parser diagnostics of this pass and all findings go into the report; edits of the third pass are not applied and give `TOA800 fix-not-applied`.
11. **Edit conflict — `TOA800`.** An edit that touches the same node as an edit accepted earlier (the same pointer, or one is a descendant of the other) is skipped with `TOA800`; the rule that comes earlier in `Normalizer.rules` wins. The same code is used for an edit whose target has disappeared and for a file that cannot be read.
12. **Files are read once for all passes.** Diagnostics from loading other files go straight into the report; documents loaded in a pass are passed to the next one (`SpecDocuments(others:)`), and edited ones — with the new tree (`SpecDocument.withRoot`). Positions stay by pointer.
13. **Config `rules`.** `rules: {<name>: false}` in `defaults` and in a client; a client overrides `defaults` name by name. An unknown name — `TOA903` (warning, with the list of rules), a non-boolean value — `TOA902`. A file shared by several clients is checked once for each different pair (preset, disabled rules); clients with equal settings share one run, and an identical diagnostic is reported once (`DiagnosticBag`).
14. **The "diagnostic-only" checks are named rules too**, so that each can be turned off (R2.1): `array-without-items`, `double-array`, `format-on-array`, `binary-object`, `contradictory-object-type`, `example-type-mismatch`, `nullable-enum-one-of`, `path-param-not-in-template`, `missing-operation-id`, `duplicate-operation-id`, `discriminator-property-required`, `discriminator-mapping-target`, `wildcard-media-type`, `component-key-characters`. Diagnostics of the reading level (TOA009, TOA015, TOA107–TOA109, TOA113, TOA114) are not rules: they are about whether the document was read.
15. **TOA402 is needed:** M2 does not resolve the values of `discriminator.mapping` (`Discriminator.mapping` is only read). A value without `#`, `/` or `.` is a name in `components.schemas`; the rest is read as `$ref`.
16. **TOA207 / TOA208.** A mismatch of structures between `example` and the schema (object against array, structure against scalar) — `TOA207` warning: the client will fail on decoding. A scalar of another scalar type (`example: "1.5"` for `number`) — `TOA208 example-scalar-type` info: the decoder is not affected, only the documentation is wrong.
17. **TOA401 — one report per discriminator**, at the place of `discriminator`, with the list of variants where the property is not `required` (sorted, up to 10 names, then "and N more").
18. **TOA503 stays info**; level overrides — M5.

## New diagnostic codes

| Code | Slug | Level | When | Task | Research / spec |
|---|---|---|---|---|---|
| TOA009 | `yaml-tag-unsupported` | error | A tag outside the JSON Schema ruleset, or a value impossible for the tag | 1 | spec item 2; Artemis |
| TOA015 | `yaml-warning` | warning | A YAML parser warning (unknown directive, YAML > 1.2) | 1 | decision 4 |
| TOA113 | `non-string-key` | error | A key is a collection or an alias of a collection | 1 | spec item 6 |
| TOA114 | `null-key` | warning | A key `~`, `null` or empty | 1 | decision 1 |
| TOA106 | `invalid-component-key` | warning | A components key outside `^[a-zA-Z0-9\.\-_]+$` | 11 | C-32 |
| TOA107 | `ref-not-allowed` | warning | `$ref` where OAS does not accept a Reference Object | 3 | DigitalOcean |
| TOA108 | `ref-commented-out` | warning | `$ref: #/...` without quotes | 3 | Grace |
| TOA109 | `yaml-merge-key` | warning | YAML merge key `<<` | 3 | decision 6 |
| TOA201 | `bool-required` | warning | `required: true/false` on a property (auto-fixed) | 5 | C-1, C-49 |
| TOA202 | `array-without-items` | warning | An array without `items` in 3.0 | 7 | C-5 |
| TOA203 | `double-array` | warning | An `items` array with a boolean `required` | 7 | C-49 |
| TOA204 | `format-on-array` | warning | `format` on an array without `items` | 7 | C-50 |
| TOA205 | `binary-object` | warning | `type: object` + `format: binary` | 7 | C-51 |
| TOA206 | `contradictory-object-type` | warning | `type: object` against non-object branches | 7 | C-22 |
| TOA207 | `example-type-mismatch` | warning | `example` of another structure (object ↔ array, structure ↔ scalar) | 7 | C-60 |
| TOA208 | `example-scalar-type` | info | `example` is a scalar of another type | 7 | decision 16 |
| TOA211 | `invalid-default` | warning | `default` of the wrong type (ignored) | 5 | C-28 |
| TOA301 | `duplicate-enum-value` | warning | Repeated values in `enum` (auto-fixed) | 8 | C-9, C-52 |
| TOA303 | `nullable-enum-one-of` | warning | Nullable enum via `oneOf` | 8 | C-54 |
| TOA401 | `discriminator-not-required` | info | Discriminator not `required` in variants (one report per discriminator) | 11 | C-42 |
| TOA402 | `discriminator-mapping-unresolved` | error | `mapping` leads nowhere | 11 | C-4 |
| TOA501 | `missing-path-parameter` | warning | A template variable without a parameter (auto-fixed) | 9 | C-6 |
| TOA502 | `path-parameter-not-in-template` | error | A parameter outside the template / a different case | 9 | C-7 |
| TOA503 | `missing-operation-id` | info | No `operationId` | 10 | C-34 |
| TOA504 | `duplicate-operation-id` | error | Identical `operationId` values | 10 | C-36 |
| TOA601 | `wildcard-media-type` | warning | `*/*` | 11 | C-38 |
| TOA800 | `fix-not-applied` | warning | An edit not applied | 4 | decisions 10–11 |

Changed: the description of TOA008 (an alias in a key is now TOA113); TOA002 — level error for keys equal in YAML, the document is read.

## Files

Paths relative to `packages/typed_openapi/`.

| File | Responsibility | Task |
|---|---|---|
| `lib/src/load/yaml/` (`scanner`, `parser`, `token`, `event`, `style`, `utils`, `error_listener`, `yaml_exception`, `yaml_document`, `LICENSE`, `analysis_options.yaml`) | Copy of the scanner and parser of `package:yaml` 3.1.4 with local edits | 1 |
| `lib/src/load/yaml_composer.dart` | `YamlComposer`, `ComposedYaml` | 1 |
| `lib/src/load/spec_loader.dart` | `parse` on the composer | 1 |
| `lib/src/config/config_loader.dart` | YAML through the composer; `rules` | 2, 6 |
| `lib/src/load/yaml_event_guard.dart` | removed | 2 |
| `lib/src/parse/object_reader.dart` | TOA107, TOA108, TOA109 | 3 |
| `lib/src/normalize/spec_edit.dart`, `normalizer_rule.dart`, `normalizer.dart` | Rule engine | 4 (+ registration in 5, 7–11) |
| `lib/src/load/spec_document.dart`, `lib/src/resolve/spec_documents.dart`, `spec_reader.dart`, `spec_model.dart`, `lib/src/model/spec_node.dart` | `withRoot`, `others`/`loaded`, `documents:`, `nodes`, `SpecLocation.child` | 4 |
| `lib/src/model/schema.dart` | `SchemaType.accepts` | 5 |
| `lib/src/normalize/rules/bool_required_to_array.dart`, `drop_invalid_default.dart` | Schema fixes | 5 |
| `lib/src/config/project_config.dart`, `lib/src/check/spec_checker.dart` | `disabledRules`; `check` through `Normalizer` | 6 |
| `lib/src/normalize/rules/schema_shape_rules.dart` | TOA202–TOA208 | 7 |
| `lib/src/normalize/rules/enum_rules.dart` | TOA301, TOA303 | 8 |
| `lib/src/normalize/rules/path_param_rules.dart` | TOA501, TOA502 | 9 |
| `lib/src/normalize/rules/operation_id_rules.dart` | TOA503, TOA504 | 10 |
| `lib/src/normalize/rules/reference_shape_rules.dart` | TOA106, TOA401, TOA402, TOA601 | 11 |
| `lib/src/diagnostics/diagnostic_code.dart` | new codes | 1, 3–5, 7–11 |
| `lib/typed_openapi.dart`, `CLAUDE.md`, `CHANGELOG.md`, `README.md`, `README.ua.md` | Exports and documentation | 12 |
| `pubspec.yaml` | `collection`, `string_scanner`; `yaml` → dev | 1, 2 |
| `test/helpers/normalizer_fixture.dart` | `NormalizerFixture` for rule tests | 7 |

## Interfaces between tasks

```dart
// load (Tasks 1-2)
typedef YamlWarningHandler = void Function(String message, FileSpan span);   // load/yaml/utils.dart
Parser(String source, {Uri? sourceUrl, YamlWarningHandler? onWarning, ...});  // load/yaml/parser.dart
final class ComposedYaml { Object? root; Map<String, SourceSpan> spans;
  ({String message, SourceSpan span})? syntaxError; }
final class YamlComposer { const YamlComposer(DiagnosticBag);
  static const maxDepth = 1000, minBudget = 16000000, budgetPerChar = 20;
  ComposedYaml? compose(String text, {required String file, required Uri uri, bool json = false}); }

// model / resolve (Tasks 4-5)
SpecDocument SpecDocument.withRoot(Map<String, Object?> root);
SpecLocation SpecLocation.child(Object token);
SpecDocuments(SpecLoader, SpecDocument root, {Iterable<SpecDocument> others = const []});
Iterable<SpecDocument> SpecDocuments.loaded;
SpecModel SpecReader.read(SpecDocument, OpenApiVersion, {SpecDocuments? documents});
List<SpecNode> SpecModel.nodes;                                    // by location
bool SchemaType.accepts(Object? value);                            // Task 5

// normalize (Tasks 4-11)
enum EditOperation { add, replace, remove }
final class SpecEdit { SpecEdit.add(SpecLocation, Object?); SpecEdit.replace(SpecLocation, Object?);
  SpecEdit.remove(SpecLocation); SpecLocation location; EditOperation operation; Object? value;
  bool overlaps(SpecEdit other); }
final class TreeEditor { TreeEditor(Map<String, Object?> root); Map<String, Object?> root;
  String? apply(SpecEdit edit); }                                   // null, or why it failed
final class Finding { const Finding(Diagnostic, {List<SpecEdit> edits}); }
final class RuleContext { SpecModel model; SpecDocuments documents; OpenApiVersion version;
  Iterable<T> nodes<T extends SpecNode>(); (Object?,)? rawAt(SpecLocation);
  Map<String, Object?>? rawObject(SpecLocation);
  Finding finding(DiagnosticCode, String message, SpecLocation at, {String? fix, List<SpecEdit> edits}); }
abstract base class NormalizerRule { String name; List<DiagnosticCode> codes;
  Iterable<Finding> check(RuleContext); String? hint(DiagnosticCode, Preset) => null; }
final class Normalizer { Normalizer(DiagnosticBag, {List<NormalizerRule>? rules,
  Set<String> disabled, Preset? preset}); static const maxPasses = 3;
  static final List<NormalizerRule> rules; static Set<String> ruleNames;
  NormalizedSpec normalize(SpecDocument, OpenApiVersion); }
final class NormalizedSpec { SpecModel model; SpecDocuments documents; }
Set<String> ClientConfig.disabledRules;                            // Task 6

// tests (Task 7)
final class NormalizerFixture { NormalizerFixture(String yaml, {Preset? preset});
  DiagnosticBag diagnostics; NormalizedSpec result;
  List<Diagnostic> of(DiagnosticCode); List<String?> pointersOf(DiagnosticCode); }
```

Order of `Normalizer.rules` after task 11: `bool-required-to-array`, `drop-invalid-default`, `array-without-items`, `double-array`, `format-on-array`, `binary-object`, `contradictory-object-type`, `example-type-mismatch`, `dedupe-enum-values`, `nullable-enum-one-of`, `declare-missing-path-params`, `path-param-not-in-template`, `missing-operation-id`, `duplicate-operation-id`, `discriminator-property-required`, `discriminator-mapping-target`, `wildcard-media-type`, `component-key-characters`.

Each task was checked this way: the code was assembled and checked on a separate branch, then tasks 1–12 were reproduced from `main` using only the code blocks of this plan (copying files, `git apply` of diffs), and after each task `dart analyze packages` is clean, `dart format` changes 0 files on a second run, `dart test` is green with the number of tests stated in the task; the final tree matches the checked one.

---

### Task 1: Own YAML composer on the events of the copied parser (TOA009, TOA015, TOA113, TOA114)

**Files:**
- Create: `packages/typed_openapi/lib/src/load/yaml/` (copy of `package:yaml` 3.1.4 + local edits), `packages/typed_openapi/lib/src/load/yaml_composer.dart`, `packages/typed_openapi/test/load/yaml_composer_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_openapi/lib/src/load/spec_loader.dart`, `packages/typed_openapi/test/load/spec_loader_test.dart`, `packages/typed_openapi/pubspec.yaml`

**Interfaces:**
- Consumes: `DiagnosticBag`, `DiagnosticCode`, `JsonPointer`, `SpecDocument` (M1–M2).
- Produces: `YamlComposer`, `ComposedYaml`; `Parser(source, {sourceUrl, onWarning})` and `YamlWarningHandler` in `load/yaml/`; codes `yamlTagUnsupported` (TOA009), `yamlWarning` (TOA015), `nonStringKey` (TOA113), `nullKey` (TOA114); `SpecLoader.parse` on the composer. `ConfigLoader` for now stays on `YamlEventGuard` + `loadYamlNode` (task 2).

Behaviour pinned down by the tests:
- Scalar values resolve exactly as in `package:yaml` (comparison test with `loadYaml`); keys are text (Failsafe): `200:`, `true:`, `0x1F:` — without a diagnostic; a null key (`~:`, `null:`, empty) — TOA114 warning "quote it", read as text.
- A tag outside the ruleset — TOA009 error, the value is read as text, the rest of the document is read; `!custom` is recognised from the text.
- A collection key or an alias of a collection — TOA113, the entry is skipped without being built; a "bomb" in the keys costs nothing.
- YAML-equal keys (`a` and `"a"`) outside `.json` — TOA002 **error**, but reading continues and the last value wins; `1`/`"1"` and any duplicates in `.json` — TOA002 warning.
- Parser warnings (`%FOO`) — TOA015, nothing is printed.
- Depth (every collection, keys included; aliases — expanded depth) > 1000 — TOA007; the alias budget — as in M2 (TOA008).
- Syntax errors (a second document, an undefined alias, a self-reference, a document that broke the scanner's assert) are returned in `syntaxError`; `SpecLoader` reports TOA001. On the 300 000 documents of the M2 fuzz (seed 11) no `AssertionError` escapes.
- Hostile flow lines (~1 MB, brackets in quotes and comments) — TOA007 in almost linear time; the comparison fuzz (seed 7) — the tree matches `loadYamlNode`.

- [ ] **Step 1: Copy the scanner and parser of `package:yaml` 3.1.4**

```bash
dart pub get    # yaml 3.1.4 is in the pub cache: main depends on it
Y="${PUB_CACHE:-$HOME/.pub-cache}/hosted/pub.dev/yaml-3.1.4"
D=packages/typed_openapi/lib/src/load/yaml
mkdir -p "$D"
cp "$Y/LICENSE" "$Y"/lib/src/{scanner,parser,token,event,style,utils,error_listener,yaml_exception,yaml_document}.dart "$D/"
(cd packages/typed_openapi && dart format lib/src/load/yaml)
```

File headers (MIT; Copyright (c) 2014, the Dart project authors; Copyright (c) 2006, Kirill Simonov) and `LICENSE` are not changed.

- [ ] **Step 2: Local edits to the copy**

Create `packages/typed_openapi/lib/src/load/yaml/analysis_options.yaml` (it also serves as the description of the local changes):

```yaml
# The scanner and parser of package:yaml 3.1.4 (MIT, see LICENSE), copied
# so that typed_openapi can read their events without an implementation
# import. Local changes, each marked "typed_openapi:" in the code:
# - the scanner's cost on long flow lines is linear
#   (https://github.com/dart-lang/tools/issues/2657, two edits);
# - the assert in Scanner._saveSimpleKey, which invalid documents can break,
#   is a syntax error;
# - warnings go to a YamlWarningHandler instead of being printed;
# - yaml_document.dart keeps only the directives, style.dart does not import
#   yaml_node.dart.
# The code keeps package:yaml's style, so it is checked with the recommended
# lints only.
include: package:lints/recommended.yaml
```

`yaml_document.dart` — directives only (the `YamlDocument` class and its imports are removed):

```dart
// Copyright (c) 2014, the Dart project authors.
// Copyright (c) 2006, Kirill Simonov.
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

/// A directive indicating which version of YAML a document was written to.
class VersionDirective {
  /// The major version number.
  final int major;

  /// The minor version number.
  final int minor;

  VersionDirective(this.major, this.minor);

  @override
  String toString() => '%YAML $major.$minor';
}

/// A directive describing a custom tag handle.
class TagDirective {
  /// The handle for use in the document.
  final String handle;

  /// The prefix that the handle maps to.
  final String prefix;

  TagDirective(this.handle, this.prefix);

  @override
  String toString() => '%TAG $handle $prefix';
}
```

In `style.dart` remove the line `import 'yaml_node.dart';` (with the empty line after it) and replace in the doc comment `[YamlScalar.wrap]` with `` `YamlScalar.wrap` ``.

Edits to `scanner.dart` (linear cost — https://github.com/dart-lang/tools/issues/2657; assert → syntax error; warnings → handler), `parser.dart` (the warning handler) and `utils.dart` (instead of the global `print` callback — the handler type); diffs against the formatted copy, applied with `git apply` from the root:

```diff
--- a/packages/typed_openapi/lib/src/load/yaml/scanner.dart
+++ b/packages/typed_openapi/lib/src/load/yaml/scanner.dart
@@ -284,16 +284,21 @@
       _isBlankOrEndAt(3) &&
       (_scanner.matches('---') || _scanner.matches('...'));
 
-  /// Creates a scanner that scans [source].
+  /// Creates a scanner that scans [source]; warnings go to [onWarning].
   Scanner(
     String source, {
     Uri? sourceUrl,
     bool recover = false,
     ErrorListener? errorListener,
+    YamlWarningHandler? onWarning,
   }) : _recover = recover,
        _errorListener = errorListener,
+       _onWarning = onWarning,
        _scanner = SpanScanner.eager(source, sourceUrl: sourceUrl);
 
+  /// typed_openapi: where warnings go instead of being printed.
+  final YamlWarningHandler? _onWarning;
+
   /// Consumes and returns the next token.
   Token scan() {
     if (_streamEndProduced) throw StateError('Out of tokens.');
@@ -331,9 +336,12 @@
         // If the current token could be a simple key, we need to scan more
         // tokens until we determine whether it is or not. Otherwise we might
         // not emit the `KEY` token before we emit the value of the key.
-        if (!_simpleKeys.any(
-          (key) => key != null && key.tokenNumber == _tokensParsed,
-        )) {
+        // typed_openapi (https://github.com/dart-lang/tools/issues/2657):
+        // keys are saved in increasing token order by flow level, so only the
+        // first live key can be the current token; `any` over every level
+        // cost the flow depth for every token.
+        final firstKey = _simpleKeys.firstWhereOrNull((key) => key != null);
+        if (firstKey == null || firstKey.tokenNumber != _tokensParsed) {
           break;
         }
       }
@@ -474,6 +482,10 @@
   /// Checks the list of potential simple keys and remove the positions that
   /// cannot contain simple keys anymore.
   void _staleSimpleKeys() {
+    // typed_openapi (https://github.com/dart-lang/tools/issues/2657): the
+    // check below does not depend on the key, so it ends the loop before it
+    // starts; in flow context the loop cost the flow depth for every token.
+    if (!_inBlockContext) return;
     for (var i = 0; i < _simpleKeys.length; i++) {
       var key = _simpleKeys[i];
       if (key == null) continue;
@@ -521,7 +533,18 @@
 
     // A simple key is required only when it is the first token in the current
     // line. Therefore it is always allowed. But we add a check anyway.
-    assert(_simpleKeyAllowed || !required);
+    // typed_openapi: invalid documents break this (a token after a multi-line
+    // quoted scalar that ends left of the indentation), so it is a syntax
+    // error here instead of an assert; without asserts package:yaml rejects
+    // the same documents later.
+    if (!_simpleKeyAllowed && required) {
+      _reportError(
+        YamlException(
+          'Expected a key at this indentation.',
+          _scanner.emptySpan,
+        ),
+      );
+    }
 
     if (!_simpleKeyAllowed) return;
 
@@ -879,7 +902,7 @@
     } else if (name == 'TAG') {
       token = _scanTagDirectiveValue(start);
     } else {
-      warn('Warning: unknown directive.', _scanner.spanFrom(start));
+      _onWarning?.call('Unknown directive.', _scanner.spanFrom(start));
 
       // libyaml doesn't support unknown directives, but the spec says to ignore
       // them and warn: http://yaml.org/spec/1.2/spec.html#id2781147.
```

```diff
--- a/packages/typed_openapi/lib/src/load/yaml/parser.dart
+++ b/packages/typed_openapi/lib/src/load/yaml/parser.dart
@@ -28,6 +28,9 @@
   /// The underlying [Scanner] that generates [Token]s.
   final Scanner _scanner;
 
+  /// typed_openapi: where warnings go instead of being printed.
+  final YamlWarningHandler? _onWarning;
+
   /// The stack of parse states for nested contexts.
   final _states = <_State>[];
 
@@ -46,17 +49,23 @@
   /// return invalid or synthetic nodes. If [errorListener] is also supplied,
   /// its onError method will be called for each error recovered from. It is not
   /// valid to provide [errorListener] if [recover] is false.
+  ///
+  /// Warnings the YAML spec asks for (an unknown directive, a newer YAML
+  /// version) go to [onWarning].
   Parser(
     String source, {
     Uri? sourceUrl,
     bool recover = false,
     ErrorListener? errorListener,
+    YamlWarningHandler? onWarning,
   }) : assert(recover || errorListener == null),
+       _onWarning = onWarning,
        _scanner = Scanner(
          source,
          sourceUrl: sourceUrl,
          recover: recover,
          errorListener: errorListener,
+         onWarning: onWarning,
        );
 
   /// Consumes and returns the next event.
@@ -732,10 +741,8 @@
             token.span,
           );
         } else if (token.minor > 2) {
-          // TODO(nweiz): Print to stderr when issue 6943 is fixed and dart:io
-          // is available.
-          warn(
-            'Warning: this parser only supports YAML 1.1 and 1.2.',
+          _onWarning?.call(
+            'This parser only supports YAML 1.1 and 1.2.',
             token.span,
           );
         }
```

```diff
--- a/packages/typed_openapi/lib/src/load/yaml/utils.dart
+++ b/packages/typed_openapi/lib/src/load/yaml/utils.dart
@@ -7,32 +7,13 @@
 
 import 'package:source_span/source_span.dart';
 
-/// Print a warning.
+/// Receives a warning the YAML spec asks an implementation to give, such as
+/// for an unknown directive.
 ///
-/// If [span] is passed, associates the warning with that span.
-void warn(String message, [SourceSpan? span]) =>
-    yamlWarningCallback(message, span);
+/// typed_openapi: package:yaml prints these through a global callback; the
+/// copy hands them to the [Parser]'s owner instead.
+typedef YamlWarningHandler = void Function(String message, FileSpan span);
 
-/// A callback for emitting a warning.
-///
-/// [message] is the text of the warning. If [span] is passed, it's the portion
-/// of the document that the warning is associated with and should be included
-/// in the printed warning.
-typedef YamlWarningCallback = void Function(String message, [SourceSpan? span]);
-
-/// A callback for emitting a warning.
-///
-/// In a very few cases, the YAML spec indicates that an implementation should
-/// emit a warning. To do so, it calls this callback. The default implementation
-/// prints a message using [print].
-// ignore: prefer_function_declarations_over_variables
-YamlWarningCallback yamlWarningCallback = (message, [SourceSpan? span]) {
-  // TODO(nweiz): Print to stderr with color when issue 6943 is fixed and
-  // dart:io is available.
-  if (span != null) message = span.message(message);
-  print(message);
-};
-
 /// Whether [codeUnit] is a UTF-16 high surrogate.
 bool isHighSurrogate(int codeUnit) => codeUnit >>> 10 == 0x36;
 
```

- [ ] **Step 3: Dependencies**

In `packages/typed_openapi/pubspec.yaml` replace the `dependencies` block with:

```yaml
dependencies:
  args: ^2.7.0
  # collection and string_scanner are used by the YAML scanner copied from
  # package:yaml into lib/src/load/yaml.
  collection: ^1.15.0
  io: ^1.1.0
  path: ^1.9.1
  source_span: ^1.10.2
  string_scanner: ^1.2.0
  # Pinned to one minor version: YamlEventGuard reads package:yaml's own parser
  # events (package:yaml/src/parser.dart), which are not public API.
  yaml: ">=3.1.4 <3.2.0"
```

Run: `dart pub get && dart analyze packages` — `No issues found!`.

- [ ] **Step 4: Diagnostic codes**

In `lib/src/diagnostics/diagnostic_code.dart` replace the doc comment of TOA008:

```dart
  /// YAML aliases expand to far more nodes than the text has, or the JSON
  /// pointers of the document's nodes add up to more than the budget.
  aliasExpansionTooLarge('TOA008', 'alias-expansion-too-large', .error),
```

and add (each entry followed by an empty line):

Before the line `/// The document has no `openapi` field.`:

```dart
  /// A YAML tag outside the JSON Schema ruleset OpenAPI requires, such as
  /// `!!timestamp` or `!custom`; the value is read as its text.
  yamlTagUnsupported('TOA009', 'yaml-tag-unsupported', .error),
```

Before the line `/// A 3.0 document uses an OpenAPI 3.1 or JSON Schema 2020-12 construct;`:

```dart
  /// The YAML parser warns about the text, for example about an unknown
  /// directive; reading goes on.
  yamlWarning('TOA015', 'yaml-warning', .warning),
```

Before the line `/// The configuration file does not exist.`:

```dart
  /// A mapping key is a collection, or an alias of one, instead of a
  /// string; the entry is ignored.
  nonStringKey('TOA113', 'non-string-key', .error),

  /// A mapping key is a YAML null (`~`, `null` or empty); it is read as its
  /// text.
  nullKey('TOA114', 'null-key', .warning),
```

- [ ] **Step 5: Composer tests**

Create `packages/typed_openapi/test/load/yaml_composer_test.dart`:

```dart
import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/load/yaml_composer.dart';
import 'package:yaml/yaml.dart';

void main() {
  const limit = Timeout(Duration(seconds: 60));

  /// Composes [text] as `api.yaml` (or `api.json` with [json]).
  (ComposedYaml?, DiagnosticBag) compose(String text, {bool json = false}) {
    final bag = DiagnosticBag();
    final result = YamlComposer(bag).compose(
      text,
      file: json ? 'api.json' : 'api.yaml',
      uri: Uri.file('/specs/api.yaml'),
      json: json,
    );
    return (result, bag);
  }

  /// The plain tree of [text]; it must compose without diagnostics.
  Object? plain(String text) {
    final (result, bag) = compose(text);
    expect(bag.all, isEmpty, reason: text);
    expect(result?.syntaxError, isNull, reason: text);
    return result!.root;
  }

  group('scalars', () {
    test('resolve exactly as package:yaml loads them', () {
      const scalars = [
        '',
        '~',
        'null',
        'Null',
        'NULL',
        'nULL',
        'true',
        'True',
        'TRUE',
        'tRUE',
        'false',
        'False',
        'FALSE',
        'yes',
        'no',
        'on',
        'off',
        'y',
        '0',
        '7',
        '-0',
        '+1',
        '-12',
        '012',
        '0o17',
        '0o',
        '0x1F',
        '0xg',
        '-0x10',
        '1_000',
        '1.5',
        '-1.5',
        '+1.5',
        '.5',
        '-.5',
        '+.5',
        '1e3',
        '1E-3',
        '1.',
        '.inf',
        '.Inf',
        '.INF',
        '-.inf',
        '+.inf',
        '.nan',
        '.NaN',
        '.NAN',
        '.',
        '+',
        '2025-07-27',
        '12:30',
        '1.2.3',
        '9223372036854775808',
        'x',
        '"quoted 1"',
        "'single'",
        '"true"',
        "'~'",
        '!!str 12',
        '!!int 12',
        '!!float .5',
        '!!bool true',
        '!!null ~',
        '! 12',
        '!!int 0x1F',
      ];
      for (final scalar in scalars) {
        final expected = (loadYaml('k: $scalar') as YamlMap)['k'];
        final actual = (plain('k: $scalar')! as Map)['k'];
        if (expected is double && expected.isNaN) {
          expect(actual, isA<double>().having((d) => d.isNaN, 'isNaN', true));
          continue;
        }
        expect(actual, expected, reason: scalar);
        expect(actual.runtimeType, expected.runtimeType, reason: scalar);
      }
    });

    test('keys are their text, as the Failsafe schema reads them', () {
      expect(plain('200: a\ntrue: b\n0x1F: c\n1.0: d\n"q": e\n'), {
        '200': 'a',
        'true': 'b',
        '0x1F': 'c',
        '1.0': 'd',
        'q': 'e',
      });
    });

    test('a null key is a warning to quote it, and is read as its text', () {
      final (result, bag) = compose('~: a\nnull: b\n: c\n"~": d\n');
      expect(result!.root, {'~': 'd', 'null': 'b', '': 'c'});
      expect(
        bag.all.map((d) => (d.code, d.pointer?.value, d.severity)),
        [
          (DiagnosticCode.nullKey, '#/~0', Severity.warning),
          (DiagnosticCode.nullKey, '#/null', Severity.warning),
          (DiagnosticCode.nullKey, '#/', Severity.warning),
          (DiagnosticCode.duplicateKey, '#/~0', Severity.warning),
        ],
      );
      expect(bag.all.first.fix, 'Quote the key: "~".');
    });
  });

  group('tags', () {
    for (final (tag, value) in [
      ('!!timestamp', '2025-07-27T07:17:05.500Z'),
      ('!!binary', 'R0lGODlh'),
      ('!custom', 'x'),
      ('!custom', '42'),
    ]) {
      test('$tag is an error and the value is read as its text', () {
        final (result, bag) = compose(
          'a: 1\nexample: $tag \'$value\'\nb: 2\n',
        );
        expect(result!.root, {'a': 1, 'example': value, 'b': 2});
        final d = bag.all.single;
        expect(d.code, DiagnosticCode.yamlTagUnsupported);
        expect(d.severity, Severity.error);
        expect(d.pointer?.value, '#/example');
        expect(d.line, 2);
        expect(d.fix, contains('JSON Schema ruleset'));
      });
    }

    test('!!set and !!omap collections are read without the tag', () {
      final (result, bag) = compose(
        's: !!set {a: null, b: null}\no: !!omap [x: 1]\n',
      );
      expect(result!.root, {
        's': {'a': null, 'b': null},
        'o': [
          {'x': 1},
        ],
      });
      expect(bag.all.map((d) => d.code), [
        DiagnosticCode.yamlTagUnsupported,
        DiagnosticCode.yamlTagUnsupported,
      ]);
      expect(bag.all.first.message, contains('!!set'));
    });

    test('a ruleset tag with a value it cannot have is reported too', () {
      final (result, bag) = compose('a: !!int abc\n');
      expect(result!.root, {'a': 'abc'});
      expect(bag.all.single.message, contains('not a valid !!int'));
    });

    test('a tagged key is checked like a value', () {
      final (result, bag) = compose('!!timestamp 2026-01-01: x\n');
      expect(result!.root, {'2026-01-01': 'x'});
      expect(bag.all.single.pointer?.value, '#');
    });
  });

  group('duplicate keys', () {
    test('keys YAML considers equal are an error, as in YAML, and the last '
        'value wins', () {
      final (result, bag) = compose('a: 1\n"a": 2\nb: 3\n');
      expect(result!.root, {'a': 2, 'b': 3});
      final d = bag.all.single;
      expect(d.severity, Severity.error);
      expect(d.message, 'Duplicate mapping key "a"; the last value is used.');
      expect(d.pointer?.value, '#/a');
    });

    test('in a .json file they are a warning and the last value wins', () {
      final (result, bag) = compose('{"a": 1, "b": 0, "a": 2}', json: true);
      expect(result!.root, {'a': 2, 'b': 0});
      final d = bag.all.single;
      expect(d.severity, Severity.warning);
      expect(d.pointer?.value, '#/a');
      expect(d.column, 18);
    });

    test('keys equal only as JSON keys are a warning, last wins', () {
      final (result, bag) = compose('r:\n  1: a\n  "1": b\n');
      expect(result!.root, {
        'r': {'1': 'b'},
      });
      expect(bag.all.single.message, contains('same key "1" in JSON'));
    });
  });

  group('non-string keys', () {
    const prefix = 'x-a: &a [1, 2]\n';

    // Every key syntax the M2 alias-key guard covered: each makes a
    // collection a key.
    for (final (name, tail) in [
      ('an alias as a block key after ?', '? *a\n: v\n'),
      ('an alias as a block key', '*a : v\n'),
      ('an alias as a flow mapping key', 'x: {*a : v}\n'),
      ('an alias as an entry of a flow mapping', 'x: {a: 1, *a : v}\n'),
      ('an alias as a bare entry of a flow mapping', 'x: {*a, b: 1}\n'),
      ('an alias after ? in a flow mapping', 'x: {? *a : v}\n'),
      ('an alias after ? in a flow sequence', 'x: [? *a : v]\n'),
      ('an alias after a bare ? in a flow sequence', 'x: [? *a]\n'),
      ('a ? key sequence', '? [*a]\n: v\n'),
      ('a ? key block sequence', '? - *a\n: v\n'),
      ('a ? key block sequence at the same column', '?\n- *a\n: v\n'),
      ('a nested ? key', 'x:\n  ?\n  - *a\n  : v\n'),
      ('a flow sequence key', '[*a]: v\n'),
      ('a flow mapping key', '{a: *a}: v\n'),
      ('a flow key of a flow mapping', 'x: {[*a]: v}\n'),
      ('a flow key without a colon', 'x: {[*a]}\n'),
      ('a flow key before a comma', 'x: {[*a], a: 1}\n'),
      ('a flow mapping in a flow mapping', 'x: {{a: *a}}\n'),
      ('a flow key with the colon on the next line', 'x: [ [*a]\n  : v]\n'),
      ('a tagged flow key', '!!seq [*a]: v\n'),
      ('an anchored flow key', '&z [*a]: v\n'),
      ('a flow key in a flow sequence', 'x: [[*a]: v]\n'),
      ('a flow key in a block sequence', 'x:\n  - [*a]: v\n'),
      ('an alias key after a bare dash line', 'x:\n  - a\n  -\n    *a : v\n'),
      ('a key after a : with a # and no blank', 'x:\n  {a:# x, b: *a}: v\n'),
      ('a key after a : with a quote', "x:\n  {true:'x, c: *a}: v\n"),
      ('a key after a ? with a quote', 'x:\n  {?"a : *a}: v\n'),
      ('a key after a " in a flow mapping', 'x:\n  [{a:"b, c: *a}]: 1\n'),
    ]) {
      test('$name is an error and the entry is dropped', () {
        final (result, bag) = compose('$prefix$tail');
        expect(result?.syntaxError, isNull, reason: tail);
        expect(
          bag.all.map((d) => d.code),
          everyElement(DiagnosticCode.nonStringKey),
          reason: tail,
        );
        expect(bag.all, isNotEmpty, reason: tail);
        expect(bag.all.first.span, isNotNull);
      });
    }

    test('a key is never expanded, so a bomb in a key costs nothing', () {
      final text = StringBuffer('l0: &l0 [x, x, x, x, x, x, x, x, x]\n');
      for (var i = 1; i <= 9; i++) {
        text.write('? &l$i [');
        text.write(List.filled(9, '*l${i - 1}').join(', '));
        text.writeln(']\n: v');
      }
      text.writeln('after: 1');
      final (result, bag) = compose('$text');
      expect((result!.root! as Map)['after'], 1);
      expect(bag.all, hasLength(9));
    }, timeout: limit);

    test('an alias of a node inside a dropped key reads as null', () {
      final (result, bag) = compose('? &k [1]\n: v\nx: *k\n');
      expect(result!.root, {'x': null});
      expect(bag.all.map((d) => d.code), [
        DiagnosticCode.nonStringKey,
        DiagnosticCode.nonStringKey,
      ]);
    });

    for (final (name, doc) in [
      ('block values', 'k: *a\n'),
      ('block sequence items', '- *a\n- - *a\n- k: *a\n'),
      ('merge keys', 'k:\n  <<: *a\n  b: 1\n'),
      ('flow sequences', 'k: [*a, *a]\n'),
      ('flow mappings', 'k: {x: *a, y: [*a]}\n'),
      ('a value on its own line', 'k:\n  *a\n'),
      ('a value with a trailing comment', 'k: *a # why\n'),
      ('an explicit key without aliases', '? /pets\n: *a\n'),
      ('an alias of a scalar as a key', 's: &s name\n*s : 1\n'),
      ('quoted keys with a *', '"*a": 1\n\'*b\' : 2\n'),
      ('markdown in plain scalars', 'k: some *bold* text\n  * item\n'),
      ('markdown in block scalars', 'k: |\n  *a : v\n  [*a]\n'),
      ('CRLF', 'k: *a\r\nj: *a\r\n'),
    ]) {
      test('aliases are accepted in $name', () {
        final (result, bag) = compose(
          '${doc.startsWith('-') ? 'x-l: &a [1, 2]\nx-s:\n' : prefix}$doc',
        );
        expect(bag.all, isEmpty, reason: doc);
        expect(result?.syntaxError, isNull, reason: doc);
      });
    }
  });

  group('nesting', () {
    test('every collection the parser opens is a level, keys included', () {
      String nested(int levels) => '${'[' * levels}${']' * levels}';
      expect(compose('a: ${nested(1000)}\n').$2.all, isEmpty);
      expect(
        compose('a: ${nested(1001)}\n').$2.all.single.code,
        DiagnosticCode.nestingTooDeep,
      );
      final (key, bag) = compose('? ${nested(1001)}\n: v\n');
      expect(key, isNull);
      expect(
        bag.all.map((d) => d.code),
        contains(DiagnosticCode.nestingTooDeep),
      );
    }, timeout: limit);

    test('100 000 nested levels are reported, not a stack overflow', () {
      for (final text in [
        '${'[' * 100000}${']' * 100000}',
        '${'- ' * 100000}x',
        '${'{a: ' * 100000}x${'}' * 100000}',
        'x:\n  - a\n  -\n    ${'- ' * 100000}x',
        'x:\n  - a\n  -\n    ${'[' * 100000}',
      ]) {
        final (result, bag) = compose(text);
        expect(result, isNull);
        expect(bag.all.single.code, DiagnosticCode.nestingTooDeep);
      }
    }, timeout: limit);
  });

  group('flow collections that hide their closing brackets', () {
    // The scanner copied from package:yaml spent time proportional to the
    // flow depth on every token; each of these took a minute or more. No
    // assertion measures time: the timeout is the test.
    for (final (name, text) in [
      ('quoted closers after a key', 'x: ${'["]",' * 199000}'),
      ('quoted closers after a key, closed', 'x: ${'["]",' * 160000}]'),
      ('quoted closers at the root', '["]",' * 200000),
      ('quoted closers in braces', '{"}":' * 200000),
      ('single-quoted closers', "x: ${"[']'," * 200000}"),
      ('quoted closers on separate lines', 'x: [\n${'"]",[\n' * 150000}'),
      ('closers in comments', 'x: [\n${'[ #]\n' * 150000}'),
      ('a quoted opening bracket first', 'x: ["[", ${'["]",' * 200000}'),
    ]) {
      test('$name are nesting-too-deep, found in near-linear time', () {
        final (result, bag) = compose(text);
        expect(result, isNull);
        final d = bag.all.single;
        expect(d.code, DiagnosticCode.nestingTooDeep);
        expect(d.span, isNotNull);
      }, timeout: limit);
    }

    test(
      'quoted closers without a comma are a syntax error, found at once',
      () {
        // `["]"["]"...`: the parser rejects the second item before the
        // nesting gets deep.
        final (result, bag) = compose('["]"' * 250000);
        expect(bag.all, isEmpty);
        expect(result!.syntaxError, isNotNull);
      },
      timeout: limit,
    );

    test('the position is the first collection that is too deep', () {
      // `x: ` is 3 characters and each `["]",` starts with its `[`. The
      // root mapping is level 0, so the sequence at index 1000 is level 1001.
      final (_, bag) = compose('x: ${'["]",' * 5000}');
      expect(bag.all.single.span!.start.offset, 3 + 5 * 1000);
    });

    test('many short flow collections are read', () {
      final (result, bag) = compose('x: [${'[1, 2], ' * 60000}0]\n');
      expect(bag.all, isEmpty);
      expect(((result!.root! as Map)['x']! as List).length, 60001);
      expect(compose('{"a": [${'{"k": ["v"]},' * 40000}1]}').$2.all, isEmpty);
      expect(compose('x: ${'["]", ' * 900}${']' * 900}\n').$2.all, isEmpty);
    }, timeout: limit);
  });

  test('a YAML warning is a diagnostic, not a print', () {
    final (result, bag) = compose('%FOO bar\n---\na: 1\n');
    expect(result!.root, {'a': 1});
    final d = bag.all.single;
    expect(d.code, DiagnosticCode.yamlWarning);
    expect(d.message, 'Unknown directive.');
    expect(d.line, 1);
  });

  group('syntax errors are returned, not reported', () {
    for (final (name, text, message) in [
      ('an unclosed flow sequence', 'a: [1, 2\nb: {', null),
      ('an undefined alias', 'a: *missing\n', 'Undefined alias.'),
      (
        'a collection that contains its own alias',
        'a: &a [*a]\n',
        'Self-referential collections are not supported.',
      ),
      ('two documents', 'a: 1\n---\nb: 2\n', 'Only expected one document.'),
      (
        'a key alias in a second document',
        'x: &a [1]\n---\n? *a\n: v\n',
        'Only expected one document.',
      ),
      ('a bad indentation', 'a: 1\n a: 2\n  - x\n', null),
    ]) {
      test(name, () {
        final (result, bag) = compose(text);
        expect(bag.all, isEmpty);
        expect(result!.syntaxError, isNotNull);
        if (message != null) {
          expect(result.syntaxError!.message, message);
        }
      });
    }

    test('the document that broke package:yaml\'s scanner assert is a '
        'syntax error', () {
      // `Scanner._saveSimpleKey` asserted on this document; the copy reports
      // a syntax error there instead.
      final (result, bag) = compose(
        'x-a: &a [1, 2]\nx-z:\n   - ? "\n      , \'s\'] : \n  "!!seq \n'
        '  , *a :  "\n',
      );
      expect(bag.all, isEmpty);
      expect(
        result!.syntaxError!.message,
        'Expected a key at this indentation.',
      );
    });

    test('no assert escapes on the 300 000 documents of the M2 fuzz', () {
      // The generator and seed of M2's alias-key fuzz, which found the
      // scanner assert in 86 of these documents. Any AssertionError fails
      // the test.
      final random = Random(11);
      const tokens = [
        '- ',
        '? ',
        ': ',
        'k: ',
        'j: ',
        '&b ',
        '*a',
        '*a ',
        '*b',
        '[',
        ']',
        '{',
        '}',
        ', ',
        'v',
        'k',
        '|',
        '>',
        '"q"',
        "'s'",
        '"',
        "'",
        '#c',
        '!!str ',
        '!!seq ',
        ' ',
        '*a : ',
        '? *a',
        '[*a]',
        '{*a: 1}',
        '[*a]: ',
        '{a: *a}: ',
        ':',
        '?',
        '-',
        '&c ',
        'x y',
        '] : ',
        ':#',
        '?"',
        ":'",
        '?#',
        ' --- ',
        '---',
        '\t',
      ];
      const indents = ['', ' ', '  ', '   ', '    '];
      var syntaxErrors = 0;
      for (var i = 0; i < 300000; i++) {
        final lines = List.generate(2 + random.nextInt(5), (_) {
          final line = StringBuffer(indents[random.nextInt(indents.length)]);
          for (var t = 1 + random.nextInt(5); t > 0; t--) {
            line.write(tokens[random.nextInt(tokens.length)]);
          }
          return '  $line';
        });
        final text = 'x-a: &a [1, 2]\nx-z:\n${lines.join('\n')}\n';
        final (result, _) = compose(text);
        if (result?.syntaxError != null) syntaxErrors++;
      }
      expect(syntaxErrors, greaterThan(1000));
    }, timeout: limit);
  });

  test('the composed tree matches package:yaml on random block and flow '
      'documents (fixed seed)', () {
    final random = Random(7);
    const tokens = [
      'k: ',
      'j: ',
      '- ',
      '[',
      ']',
      '{',
      '}',
      ', ',
      'v',
      '1',
      '"q"',
      "'s'",
      '~',
      'true',
      '2.5',
      '&b ',
      '*a',
      ': ',
      '? ',
      '|',
      '#c',
      ' ',
    ];
    var compared = 0;
    for (var i = 0; i < 20000; i++) {
      final lines = List.generate(1 + random.nextInt(4), (_) {
        final line = StringBuffer(' ' * (2 + random.nextInt(3)));
        for (var t = 1 + random.nextInt(5); t > 0; t--) {
          line.write(tokens[random.nextInt(tokens.length)]);
        }
        return '$line';
      });
      final text = 'x-a: &a [1, 2]\nx-z:\n${lines.join('\n')}\n';
      final YamlNode node;
      try {
        node = loadYamlNode(text);
        // package:yaml's own scanner asserts on some invalid documents; the
        // comparison skips them (the copy reports a syntax error).
        // ignore: avoid_catching_errors
      } on AssertionError {
        continue;
      } on YamlException {
        continue;
      }
      final expected = _failsafeKeys(node);
      if (expected == _skip) continue;
      final (result, bag) = compose(text);
      expect(
        bag.all.where((d) => d.code != DiagnosticCode.nullKey),
        isEmpty,
        reason: text,
      );
      expect(result!.root, expected, reason: text);
      compared++;
    }
    expect(compared, greaterThan(1000));
  }, timeout: limit);
}

const _skip = Object();

/// An anchor or a tag in front of a scalar's text.
final _properties = RegExp(r'^(?:[&!]\S*(?:\s+|$))+');

/// The plain value of [node] with keys as their Failsafe text, or [_skip]
/// when a key is a collection or two keys are one JSON key.
Object? _failsafeKeys(YamlNode node) {
  switch (node) {
    case YamlMap():
      final map = <String, Object?>{};
      for (final MapEntry(:key, value: entry) in node.nodes.entries) {
        final keyNode = key as YamlNode;
        if (keyNode is! YamlScalar) return _skip;
        final value = keyNode.value;
        final name = value is String
            ? value
            : keyNode.span.text.replaceFirst(_properties, '').trim();
        if (map.containsKey(name)) return _skip;
        final converted = _failsafeKeys(entry);
        if (converted == _skip) return _skip;
        map[name] = converted;
      }
      return map;
    case YamlList():
      final list = <Object?>[];
      for (final item in node.nodes) {
        final converted = _failsafeKeys(item);
        if (converted == _skip) return _skip;
        list.add(converted);
      }
      return list;
    default:
      return node.value;
  }
}
```

Run: `dart test test/load/yaml_composer_test.dart` — Expected: FAIL (`yaml_composer.dart` does not exist).

- [ ] **Step 6: Composer**

Create `packages/typed_openapi/lib/src/load/yaml_composer.dart`:

```dart
import 'dart:math';

import 'package:source_span/source_span.dart';

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/json_pointer.dart';
// The composer reads the events of package:yaml's parser, copied into
// yaml/: the YAML syntax exactly as package:yaml tokenizes it, without the
// recursive loader, which overflows the stack on deep nesting, expands alias
// bombs and hashes collection keys.
import 'yaml/event.dart';
import 'yaml/parser.dart';
import 'yaml/yaml_exception.dart';

/// A JSON or YAML text read into plain values, with the source range of
/// every node by JSON pointer value.
final class ComposedYaml {
  /// Creates a composed document.
  const ComposedYaml({
    required this.root,
    required this.spans,
    this.syntaxError,
  });

  /// The root value: `Map<String, Object?>`, `List<Object?>`, `String`,
  /// `num`, `bool` or `null`. Null when [syntaxError] is set.
  final Object? root;

  /// The source range of every node, by pointer value.
  final Map<String, SourceSpan> spans;

  /// Why the text is not valid YAML, when it is not; nothing was reported
  /// for it, so the caller decides how to.
  final ({String message, SourceSpan span})? syntaxError;
}

/// Builds plain values from YAML (and JSON, which is YAML) text, one parser
/// event at a time.
///
/// The composer replaces package:yaml's loader. It walks the events with an
/// explicit stack, so no input overflows the Dart stack, and checks in the
/// same pass:
///
/// - nesting deeper than [maxDepth] collections (`nesting-too-deep`): every
///   collection the parser opens is a level, keys included, and so is every
///   collection an alias expands to; the root collection is level 0;
/// - aliases that expand to more than the budget (`alias-expansion-too-
///   large`): every node built, read or reached through an alias, costs the
///   length of its JSON pointer plus one, and the budget is
///   `max(`[minBudget]`, `[budgetPerChar]` * text length)`;
/// - keys that are the same JSON key (`duplicate-key`): a warning and the
///   last value wins, except two keys YAML itself considers equal outside a
///   `.json` file, which are an error (as in YAML) but are read the same
///   way;
/// - keys that are not strings (`non-string-key`): a collection, or an alias
///   of one, as a key; the entry is dropped and nothing in it is built, so a
///   key cannot hide an alias bomb;
/// - keys that YAML reads as null (`~`, `null`, an empty key)
///   (`null-key`): a warning; they are read as their text;
/// - warnings of the YAML parser, such as an unknown directive
///   (`yaml-warning`);
/// - tags outside the YAML JSON Schema ruleset, such as `!!timestamp` or
///   `!custom` (`yaml-tag-unsupported`): the value is read as its text (a
///   collection as plain), so the rest of the file is still checked.
///
/// Scalar keys are read as their text, the YAML Failsafe schema OpenAPI
/// requires for keys: `200:` is the key `"200"`, `true:` the key `"true"`. Scalar values are resolved
/// with the JSON Schema ruleset exactly as package:yaml's loader does.
///
/// A limit or an undefined alias stops the composition: it is reported and
/// [compose] returns null. A syntax error is returned in
/// [ComposedYaml.syntaxError], unreported.
final class YamlComposer {
  /// Creates a composer that reports to [_diagnostics].
  const YamlComposer(this._diagnostics);

  /// The deepest nesting a document may have.
  static const maxDepth = 1000;

  /// The smallest budget, in characters: ordinary specs never come near it.
  static const minBudget = 16000000;

  /// The budget per character of text, once that exceeds [minBudget].
  static const budgetPerChar = 20;

  final DiagnosticBag _diagnostics;

  /// Composes [text]; [file] names it in diagnostics and [uri] in spans.
  ///
  /// With [json], every duplicate key is a warning (JSON keeps the last
  /// value); otherwise two keys YAML considers equal are an error.
  ComposedYaml? compose(
    String text, {
    required String file,
    required Uri uri,
    bool json = false,
  }) => _Composition(_diagnostics, text, file, uri, json: json).run();
}

/// One run of [YamlComposer].
final class _Composition {
  _Composition(
    this._diagnostics,
    this._text,
    this._file,
    this._uri, {
    required bool json,
  }) : _json = json,
       _budget = max(
         YamlComposer.minBudget,
         YamlComposer.budgetPerChar * _text.length,
       ),
       _mayHaveAliases = _text.contains('*');

  static const _yamlTags = 'tag:yaml.org,2002:';

  final DiagnosticBag _diagnostics;
  final String _text;
  final String _file;
  final Uri _uri;
  final bool _json;
  final bool _mayHaveAliases;
  int _budget;

  final Map<String, SourceSpan> _spans = {};
  final List<_Frame> _stack = [];
  final Map<String, _Anchor> _anchors = {};

  /// Span records of the nodes inside anchored collections being built, so
  /// that an alias can repeat them under its own pointer.
  final List<_Record> _records = [];
  int _openAnchors = 0;

  /// How many collections are open, skipped ones included: the level a
  /// collection that starts now has.
  int _open = 0;

  /// How deep inside a skipped collection the composer is; 0 when not.
  int _skipped = 0;

  Object? _root;
  bool _failed = false;
  ({String message, SourceSpan span})? _syntaxError;
  SourceSpan? _lastSpan;

  ComposedYaml? run() {
    final parser = Parser(_text, sourceUrl: _uri, onWarning: _warning);
    var documents = 0;
    while (!_failed && _syntaxError == null) {
      final event = _next(parser);
      if (event == null) break;
      switch (event) {
        case DocumentStartEvent():
          if (++documents > 1) {
            _syntaxError = (
              message: 'Only expected one document.',
              span: event.span,
            );
          }
        case ScalarEvent():
          _scalar(event);
        case AliasEvent():
          _alias(event);
        case SequenceStartEvent():
          _start(
            event,
            _tagOf(event.tag, event.span),
            event.anchor,
            isMapping: false,
          );
        case MappingStartEvent():
          _start(
            event,
            _tagOf(event.tag, event.span),
            event.anchor,
            isMapping: true,
          );
        case Event(type: .sequenceEnd || .mappingEnd):
          _end(event);
        case Event(type: .streamEnd):
          return ComposedYaml(root: _root, spans: _spans);
        default:
      }
    }
    if (_failed) return null;
    return ComposedYaml(root: null, spans: _spans, syntaxError: _syntaxError);
  }

  /// The next parser event, or null after recording a syntax error.
  Event? _next(Parser parser) {
    try {
      final event = parser.parse();
      _lastSpan = event.span;
      return event;
    } on YamlException catch (e) {
      _syntaxError = (message: e.message, span: e.span ?? _here());
      return null;
    }
  }

  void _warning(String message, SourceSpan span) {
    _diagnostics.report(
      .yamlWarning,
      message,
      file: _file,
      span: span,
    );
  }

  SourceSpan _here() =>
      _lastSpan ?? SourceFile.fromString(_text, url: _uri).span(0, 0);

  // --- nodes ---------------------------------------------------------------

  void _scalar(ScalarEvent event) {
    if (_skipped > 0) {
      _skipAnchor(event.anchor);
      return;
    }
    final frame = _stack.isEmpty ? null : _stack.last;
    if (frame != null && frame.state == .skipValue) {
      _skipAnchor(event.anchor);
      frame.state = .key;
      return;
    }
    final isKey = frame != null && frame.state == .key;
    final pointer = isKey ? frame.pointer : _childPointer(frame);
    final value = _resolve(event, pointer);
    if (isKey) {
      if (value == null) _nullKey(frame, event.value, event.span);
      _key(frame, event.value, value, event.span);
      if (event.anchor case final name?) {
        _anchors[name] = _Anchor.scalar(value, event.value, event.span);
      }
      return;
    }
    if (!_charge(pointer, event.span)) return;
    _spans[pointer.value] = event.span;
    if (_openAnchors > 0) _records.add(_Record(pointer.value, event.span, -1));
    if (event.anchor case final name?) {
      _anchors[name] = _Anchor.scalar(value, event.value, event.span);
    }
    _attach(frame, value);
  }

  void _alias(AliasEvent event) {
    if (_skipped > 0) return;
    final frame = _stack.isEmpty ? null : _stack.last;
    if (frame != null && frame.state == .skipValue) {
      frame.state = .key;
      return;
    }
    final anchor = _anchors[event.name];
    if (anchor == null) {
      _syntaxError = (message: 'Undefined alias.', span: event.span);
      return;
    }
    if (anchor.open) {
      _syntaxError = (
        message: 'Self-referential collections are not supported.',
        span: event.span,
      );
      return;
    }
    if (frame != null && frame.state == .key) {
      if (anchor.text case final text? when !anchor.skipped) {
        _key(frame, text, anchor.value, event.span);
      } else {
        _nonStringKey(frame, event.span);
        frame.state = .skipValue;
      }
      return;
    }
    final pointer = _childPointer(frame);
    if (anchor.skipped) {
      _diagnostics.report(
        .nonStringKey,
        'This alias refers to a node inside a mapping key that is not a '
        'string; it is read as null.',
        file: _file,
        pointer: pointer,
        span: event.span,
        fix: 'Anchor the node outside the key.',
      );
      _attach(frame, null);
      return;
    }
    if (!_expand(anchor, pointer, event.span)) return;
    _attach(frame, anchor.value);
  }

  void _start(
    Event event,
    String? tag,
    String? anchor, {
    required bool isMapping,
  }) {
    final level = _open++;
    if (level > YamlComposer.maxDepth) {
      _fail(
        .nestingTooDeep,
        'The document nests deeper than ${YamlComposer.maxDepth} levels.',
        null,
        event.span,
      );
      return;
    }
    if (_skipped > 0) {
      _skipped++;
      _skipAnchor(anchor);
      return;
    }
    final frame = _stack.isEmpty ? null : _stack.last;
    if (frame != null && frame.state != .value) {
      if (frame.state == .key) {
        _nonStringKey(frame, event.span);
        frame.state = .skippedKey;
      } else {
        frame.state = .skippedValue;
      }
      _skipped = 1;
      _skipAnchor(anchor);
      return;
    }
    final pointer = _childPointer(frame);
    if (!_charge(pointer, event.span)) return;
    _checkTag(
      tag,
      isMapping ? '${_yamlTags}map' : '${_yamlTags}seq',
      pointer,
      event.span,
      isMapping ? 'mapping' : 'list',
    );
    final record = _Record(pointer.value, event.span, level);
    _Anchor? anchored;
    if (anchor != null) {
      anchored = _anchors[anchor] = _Anchor.collection(
        _records.length,
        pointer.value,
        level,
      );
      _openAnchors++;
    }
    if (_openAnchors > 0) _records.add(record);
    _stack.add(
      _Frame(
        pointer,
        isMapping ? <String, Object?>{} : <Object?>[],
        event.span,
        record,
        anchored,
      ),
    );
  }

  void _end(Event event) {
    _open--;
    if (_skipped > 0) {
      if (--_skipped > 0) return;
      final frame = _stack.last;
      frame.state = frame.state == .skippedKey ? .skipValue : .key;
      return;
    }
    final frame = _stack.removeLast();
    final span = frame.start.expand(event.span);
    frame.record.span = span;
    _spans[frame.pointer.value] = span;
    if (frame.anchor case final anchor?) {
      anchor
        ..value = frame.value
        ..end = _records.length
        ..open = false;
      _openAnchors--;
    }
    _attach(_stack.isEmpty ? null : _stack.last, frame.value);
  }

  // --- maps ----------------------------------------------------------------

  void _key(_Frame frame, String text, Object? value, SourceSpan span) {
    final earlier = frame.keys[text];
    frame.keys[text] = (value: value, span: span);
    frame.key = text;
    frame.state = .value;
    if (earlier == null) return;
    final yamlEqual = earlier.value == value;
    _diagnostics.report(
      .duplicateKey,
      yamlEqual
          ? 'Duplicate mapping key "$text"; the last value is used.'
          : 'Keys ${earlier.span.text} and ${span.text} are the same key '
                '"$text" in JSON; the last value is used.',
      // YAML forbids equal keys; JSON leaves them to the reader.
      severity: yamlEqual && !_json ? .error : null,
      file: _file,
      pointer: frame.pointer.child(text),
      span: span,
      fix: 'Remove one of the keys.',
    );
  }

  void _nullKey(_Frame frame, String text, SourceSpan span) {
    _diagnostics.report(
      .nullKey,
      text.isEmpty
          ? 'This mapping key is empty, which YAML reads as null; it is read '
                'as the empty string.'
          : 'The mapping key $text is null in YAML; it is read as the string '
                '"$text".',
      file: _file,
      pointer: frame.pointer.child(text),
      span: span,
      fix: 'Quote the key: "$text".',
    );
  }

  void _nonStringKey(_Frame frame, SourceSpan span) {
    _diagnostics.report(
      .nonStringKey,
      'A mapping key must be a string, not a collection; the entry is '
      'ignored.',
      file: _file,
      pointer: frame.pointer,
      span: span,
      fix: 'Write the key as a plain or quoted string.',
    );
  }

  // --- values --------------------------------------------------------------

  JsonPointer _childPointer(_Frame? frame) => switch (frame) {
    null => .root,
    _Frame(value: final List<Object?> list) => frame.pointer.child(list.length),
    _ => frame.pointer.child(frame.key!),
  };

  void _attach(_Frame? frame, Object? value) {
    if (frame == null) {
      _root = value;
      return;
    }
    switch (frame.value) {
      case final List<Object?> list:
        list.add(value);
      case final Map<String, Object?> map:
        map[frame.key!] = value;
        frame.state = .key;
    }
  }

  /// Repeats the records of [anchor] under [pointer], charging each one;
  /// false after reporting a limit.
  bool _expand(_Anchor anchor, JsonPointer pointer, SourceSpan span) {
    if (anchor.end < 0) {
      if (!_charge(pointer, span)) return false;
      _spans[pointer.value] = anchor.span!;
      if (_openAnchors > 0) {
        _records.add(_Record(pointer.value, anchor.span!, -1));
      }
      return true;
    }
    final level = _open;
    for (var i = anchor.first; i < anchor.end; i++) {
      final record = _records[i];
      final at = pointer.value + record.pointer.substring(anchor.base.length);
      final atLevel = record.level < 0
          ? -1
          : level + record.level - anchor.level;
      if (atLevel > YamlComposer.maxDepth) {
        _fail(
          .nestingTooDeep,
          'The document nests deeper than ${YamlComposer.maxDepth} levels, '
          'counting what its aliases expand to.',
          JsonPointer.parse(at),
          record.span!,
        );
        return false;
      }
      if (!_charge(JsonPointer.parse(at), record.span!)) return false;
      _spans[at] = record.span!;
      if (_openAnchors > 0) _records.add(_Record(at, record.span, atLevel));
    }
    return true;
  }

  bool _charge(JsonPointer pointer, SourceSpan span) {
    _budget -= pointer.value.length + 1;
    if (_budget >= 0) return true;
    _fail(
      .aliasExpansionTooLarge,
      _mayHaveAliases
          ? 'YAML aliases expand to far more nodes than the text has; the '
                'document is not read.'
          : 'The JSON pointers of the document\'s nodes add up to more than '
                'the supported size, because of very long keys or very deep '
                'nesting; the document is not read.',
      pointer,
      span,
      fix: _mayHaveAliases
          ? 'Remove the nested aliases.'
          : 'Shorten the longest keys.',
    );
    return false;
  }

  void _skipAnchor(String? name) {
    if (name != null) _anchors[name] = _Anchor.skipped();
  }

  void _fail(
    DiagnosticCode code,
    String message,
    JsonPointer? pointer,
    SourceSpan span, {
    String? fix,
  }) {
    _failed = true;
    _diagnostics.report(
      code,
      message,
      file: _file,
      pointer: pointer,
      span: span,
      fix: fix,
    );
  }

  // --- scalars and tags ----------------------------------------------------

  /// The value of [event] as package:yaml's loader resolves it, with tags
  /// outside the JSON Schema ruleset reported and read as text.
  Object? _resolve(ScalarEvent event, JsonPointer pointer) {
    final tag = _tagOf(event.tag, event.span);
    if (tag == null) return _plain(event.value);
    if (tag == '!' || tag == '${_yamlTags}str') return event.value;
    final value = switch (tag) {
      '${_yamlTags}null' => _null(event.value),
      '${_yamlTags}bool' => _bool(event.value),
      '${_yamlTags}int' => _number(event.value, allowFloat: false),
      '${_yamlTags}float' => _number(event.value, allowInt: false),
      _ => null,
    };
    if (value != null) return value.$1;
    final known =
        tag.startsWith(_yamlTags) &&
        const {'null', 'bool', 'int', 'float'}.contains(
          tag.substring(_yamlTags.length),
        );
    _diagnostics.report(
      .yamlTagUnsupported,
      known
          ? '"${event.value}" is not a valid ${_tagName(tag)} value; it is '
                'read as a string.'
          : 'The YAML tag ${_tagName(tag)} is not in the JSON Schema ruleset '
                'OpenAPI requires; the value is read as the string '
                '"${event.value}".',
      file: _file,
      pointer: pointer,
      span: event.span,
      fix: _tagFix,
    );
    return event.value;
  }

  void _checkTag(
    String? tag,
    String allowed,
    JsonPointer pointer,
    SourceSpan span,
    String kind,
  ) {
    if (tag == null || tag == '!' || tag == allowed) return;
    _diagnostics.report(
      .yamlTagUnsupported,
      'The YAML tag ${_tagName(tag)} is not in the JSON Schema ruleset '
      'OpenAPI requires; the $kind is read without it.',
      file: _file,
      pointer: pointer,
      span: span,
      fix: _tagFix,
    );
  }

  static const _tagFix =
      'Remove the tag, or quote the value. OpenAPI YAML may only use the '
      'tags of the JSON Schema ruleset: !!str, !!int, !!float, !!bool, '
      '!!null, !!seq and !!map.';

  /// A tag property such as `!custom`, after an optional anchor.
  static final _localTag = RegExp(r'^(?:&\S+\s+)?(![^\s!]\S*)');

  /// The tag of a node whose parser event has [tag] and [span].
  ///
  /// package:yaml's parser reports a local tag such as `!custom` as the
  /// non-specific tag `!`, the tag of every quoted scalar; the source text
  /// tells them apart.
  static String? _tagOf(String? tag, SourceSpan span) {
    if (tag != '!') return tag;
    return _localTag.firstMatch(span.text)?.group(1) ?? tag;
  }

  static String _tagName(String tag) => tag.startsWith(_yamlTags)
      ? '!!${tag.substring(_yamlTags.length)}'
      : tag.startsWith('!')
      ? tag
      : '!<$tag>';

  /// A plain scalar resolved as package:yaml's loader does: null, bool,
  /// int, float, else the string.
  static Object? _plain(String text) {
    if (text.isEmpty) return null;
    final resolved = switch (text.codeUnitAt(0)) {
      0x2E || 0x2B || 0x2D => _number(text),
      0x6E || 0x4E => text.length == 4 ? _null(text) : null,
      0x74 || 0x54 => text.length == 4 ? _bool(text) : null,
      0x66 || 0x46 => text.length == 5 ? _bool(text) : null,
      0x7E => text.length == 1 ? (null,) : null,
      final c when c >= 0x30 && c <= 0x39 => _number(text),
      _ => null,
    };
    return resolved == null ? text : resolved.$1;
  }

  static (Object?,)? _null(String text) => switch (text) {
    '' || 'null' || 'Null' || 'NULL' || '~' => (null,),
    _ => null,
  };

  static (Object?,)? _bool(String text) => switch (text) {
    'true' || 'True' || 'TRUE' => (true,),
    'false' || 'False' || 'FALSE' => (false,),
    _ => null,
  };

  static (Object?,)? _number(
    String text, {
    bool allowInt = true,
    bool allowFloat = true,
  }) {
    final value = _numberValue(
      text,
      allowInt: allowInt,
      allowFloat: allowFloat,
    );
    return value == null ? null : (value,);
  }

  static num? _numberValue(
    String text, {
    required bool allowInt,
    required bool allowFloat,
  }) {
    if (text.isEmpty) return null;
    final first = text.codeUnitAt(0);
    if (allowInt && text.length == 1) {
      final digit = first - 0x30;
      return digit >= 0 && digit <= 9 ? digit : null;
    }
    if (text.length == 1) return null;
    final second = text.codeUnitAt(1);
    bool isDigit(int c) => c >= 0x30 && c <= 0x39;
    if (allowInt && first == 0x30) {
      if (second == 0x78) return int.tryParse(text);
      if (second == 0x6F) return int.tryParse(text.substring(2), radix: 8);
    }
    if (isDigit(first) ||
        ((first == 0x2B || first == 0x2D) && isDigit(second))) {
      num? result;
      if (allowInt) result = int.tryParse(text, radix: 10);
      if (allowFloat) result ??= double.tryParse(text);
      return result;
    }
    if (!allowFloat) return null;
    if ((first == 0x2E && isDigit(second)) ||
        ((first == 0x2D || first == 0x2B) && second == 0x2E)) {
      if (text.length == 5) {
        switch (text) {
          case '+.inf' || '+.Inf' || '+.INF':
            return double.infinity;
          case '-.inf' || '-.Inf' || '-.INF':
            return -double.infinity;
        }
      }
      return double.tryParse(text);
    }
    if (text.length == 4 && first == 0x2E) {
      switch (text) {
        case '.inf' || '.Inf' || '.INF':
          return double.infinity;
        case '.nan' || '.NaN' || '.NAN':
          return double.nan;
      }
    }
    return null;
  }
}

/// What a mapping frame expects next.
enum _State {
  /// A key.
  key,

  /// The value of [_Frame.key].
  value,

  /// A value to skip, because its key was not a string.
  skipValue,

  /// The rest of a key collection that is being skipped.
  skippedKey,

  /// The rest of a value collection that is being skipped.
  skippedValue,
}

/// A collection being built.
final class _Frame {
  _Frame(this.pointer, this.value, this.start, this.record, this.anchor)
    : state = value is List<Object?> ? .value : .key;

  final JsonPointer pointer;

  /// The `Map<String, Object?>` or `List<Object?>` being filled.
  final Object value;

  /// The span of the start event.
  final FileSpan start;

  /// The span record of the collection.
  final _Record record;

  /// The anchor defined on the collection, if any.
  final _Anchor? anchor;

  /// The keys read so far, with their YAML values and spans.
  final Map<String, ({Object? value, SourceSpan span})> keys = {};

  /// The key whose value comes next.
  String? key;

  /// What comes next; always [_State.value] in a list.
  _State state;
}

/// The span of one node, kept while an anchored collection is open.
final class _Record {
  _Record(this.pointer, this.span, this.level);

  final String pointer;

  /// Set when the node is complete.
  SourceSpan? span;

  /// The level of a collection; -1 for a scalar.
  final int level;
}

/// What an anchor names.
final class _Anchor {
  _Anchor.scalar(this.value, this.text, this.span)
    : skipped = false,
      first = -1,
      end = -1,
      base = '',
      level = -1,
      open = false;

  _Anchor.collection(this.first, this.base, this.level)
    : skipped = false,
      text = null,
      span = null,
      end = -1,
      open = true;

  _Anchor.skipped()
    : skipped = true,
      value = null,
      text = null,
      span = null,
      first = -1,
      end = -1,
      base = '',
      level = -1,
      open = false;

  /// Whether the anchored node is inside a skipped key or value.
  final bool skipped;

  Object? value;

  /// The text of a scalar.
  final String? text;

  /// The span of a scalar.
  final SourceSpan? span;

  /// The records of a collection: from [first] to [end] (exclusive).
  final int first;
  int end;

  /// The pointer value of the anchored collection.
  final String base;

  /// The level of the anchored collection.
  final int level;

  /// Whether the anchored collection is still being built.
  bool open;
}
```

- [ ] **Step 7: `SpecLoader.parse` on the composer and loader tests**

```diff
diff --git a/packages/typed_openapi/lib/src/load/spec_loader.dart b/packages/typed_openapi/lib/src/load/spec_loader.dart
--- a/packages/typed_openapi/lib/src/load/spec_loader.dart
+++ b/packages/typed_openapi/lib/src/load/spec_loader.dart
@@ -1,16 +1,13 @@
 import 'dart:convert';
 import 'dart:io';
-import 'dart:math';
 
 import 'package:path/path.dart' as p;
 import 'package:source_span/source_span.dart';
-import 'package:yaml/yaml.dart';
 
 import '../diagnostics/diagnostic_bag.dart';
-import '../diagnostics/diagnostic_code.dart';
 import '../diagnostics/json_pointer.dart';
 import 'spec_document.dart';
-import 'yaml_event_guard.dart';
+import 'yaml_composer.dart';
 
 /// Reads spec files (JSON or YAML) into [SpecDocument]s.
 ///
@@ -66,71 +63,42 @@ final class SpecLoader {
   ///
   /// [uri] is the absolute location of the text, the base for relative
   /// `$ref`s; it defaults to [file] resolved against the current directory.
-  /// JSON and YAML go through the same YAML parser, so both get positions.
-  /// A JSON file the YAML parser rejects (for example, because of a
-  /// duplicate key) is read again with `jsonDecode`, without positions.
+  /// JSON and YAML go through the same [YamlComposer], so both get
+  /// positions. A `.json` file the YAML parser rejects is read again with
+  /// `jsonDecode`, without positions.
   SpecDocument? parse(String text, String file, {Uri? uri}) {
     final location = uri ?? p.toUri(p.normalize(p.absolute(file)));
-    final found = const YamlEventGuard().check(text);
-    if (found != null) {
-      final span = SourceFile.fromString(
-        text,
-        url: location,
-      ).span(found.offset, found.offset + 1);
-      switch (found.problem) {
-        case .tooDeep:
-          _diagnostics.report(
-            .nestingTooDeep,
-            'The document nests deeper than ${YamlEventGuard.maxDepth} '
-            'levels.',
-            file: file,
-            span: span,
-          );
-        case .aliasInKey:
-          _diagnostics.report(
-            .aliasExpansionTooLarge,
-            'A YAML alias is used in a mapping key. OpenAPI keys are '
-            'strings, and an alias there can expand without bound, so the '
-            'document is not read.',
-            file: file,
-            span: span,
-            fix: 'Write the key out instead of aliasing it.',
-          );
-      }
+    final json = p.extension(file).toLowerCase() == '.json';
+    final composed = YamlComposer(
+      _diagnostics,
+    ).compose(text, file: file, uri: location, json: json);
+    if (composed == null) return null;
+    if (composed.syntaxError case final error?) {
+      if (json) return _parseJsonFallback(text, file, location, error);
+      _diagnostics.report(
+        .parseError,
+        error.message,
+        file: file,
+        span: error.span,
+      );
       return null;
     }
-    final YamlNode node;
-    try {
-      node = loadYamlNode(text, sourceUrl: Uri.file(file));
-    } on YamlException catch (e) {
-      return _parseJsonFallback(text, file, location, e);
-    }
-    if (node is! YamlMap) {
+    final root = composed.root;
+    if (root is! Map<String, Object?>) {
       _diagnostics.report(
         .rootNotObject,
         'The document root must be an object.',
         file: file,
         pointer: .root,
-        span: node.span,
+        span: composed.spans[JsonPointer.root.value],
       );
       return null;
     }
-    final converter = _PlainConverter(
-      _diagnostics,
-      file,
-      max(
-        _PlainConverter.minBudget,
-        _PlainConverter.budgetPerChar * text.length,
-      ),
-      mayHaveAliases: text.contains('*'),
-    );
-    final root = converter.convert(node, .root, 0);
-    if (converter.failed) return null;
     return SpecDocument(
       file: file,
       uri: location,
-      root: root! as Map<String, Object?>,
-      spans: converter.spans,
+      root: root,
+      spans: composed.spans,
     );
   }
 
@@ -138,59 +106,20 @@ final class SpecLoader {
     String text,
     String file,
     Uri uri,
-    YamlException error,
+    ({String message, SourceSpan span}) error,
   ) {
-    final duplicate = error.message.startsWith('Duplicate mapping key');
-    if (p.extension(file).toLowerCase() != '.json') {
-      _diagnostics.report(
-        duplicate ? .duplicateKey : .parseError,
-        error.message,
-        severity: .error,
-        file: file,
-        span: error.span,
-      );
-      return null;
-    }
     final Object? root;
     try {
       root = jsonDecode(text);
-    } on FormatException catch (e) {
-      if (!duplicate) {
-        _diagnostics.report(
-          .parseError,
-          error.message,
-          file: file,
-          span: error.span,
-        );
-        return null;
-      }
+    } on FormatException {
       _diagnostics.report(
-        .duplicateKey,
+        .parseError,
         error.message,
         file: file,
         span: error.span,
-        fix: 'Remove the duplicate key from the spec.',
-      );
-      final offset = e.offset;
-      _diagnostics.report(
-        .parseError,
-        e.message,
-        file: file,
-        span: offset == null
-            ? null
-            : SourceFile.fromString(text, url: uri).span(offset, offset),
       );
       return null;
     }
-    if (duplicate) {
-      _diagnostics.report(
-        .duplicateKey,
-        '${error.message} The last value is used.',
-        file: file,
-        span: error.span,
-        fix: 'Remove the duplicate key from the spec.',
-      );
-    }
     if (root is! Map<String, Object?>) {
       _diagnostics.report(
         .rootNotObject,
@@ -209,137 +138,3 @@ final class SpecLoader {
     return SpecDocument(file: file, uri: uri, root: root, spans: const {});
   }
 }
-
-/// Turns a YAML node tree into plain values and records the span of every
-/// node.
-///
-/// YAML aliases make the tree a graph that shares nodes, so walking it as a
-/// tree can take far more steps, and go far deeper, than the text suggests.
-/// The `YamlEventGuard` runs before aliases are expanded and cannot see that, so the conversion
-/// enforces both limits itself: it stops at the first node deeper than
-/// [YamlEventGuard.maxDepth] (`nesting-too-deep`) and once the nodes it has
-/// converted have cost more than its budget (`alias-expansion-too-large`).
-/// Either is reported once, at that node, and sets [failed].
-///
-/// Every converted node, whether read for the first time or reached again
-/// through an alias, costs the length of its JSON pointer plus one. The
-/// pointer string is what a node keeps in [spans], so the sum of the costs
-/// is the memory the conversion holds and the time it spends. Ordinary
-/// specs cost a few times their text length, far below the budget; aliases
-/// of a deep node or of a node under a long key add up quickly.
-final class _PlainConverter {
-  _PlainConverter(
-    this._diagnostics,
-    this._file,
-    this._budget, {
-    required this.mayHaveAliases,
-  });
-
-  /// The smallest budget, in characters: ordinary specs never come near it.
-  static const minBudget = 16000000;
-
-  /// The budget per character of text, once that exceeds [minBudget].
-  static const budgetPerChar = 20;
-
-  final DiagnosticBag _diagnostics;
-  final String _file;
-  int _budget;
-
-  /// Whether the text may contain aliases, which decides how a depth error
-  /// is worded.
-  final bool mayHaveAliases;
-
-  /// The source range of every converted node, by pointer value.
-  final Map<String, SourceSpan> spans = {};
-
-  /// Whether a limit was hit; the converted value is then incomplete.
-  bool failed = false;
-
-  /// Converts [node], which is at [pointer], [depth] collections deep (the
-  /// root is 0, as for the `YamlEventGuard`).
-  Object? convert(YamlNode node, JsonPointer pointer, int depth) {
-    if (failed) return null;
-    _budget -= pointer.value.length + 1;
-    if (_budget < 0) {
-      _fail(
-        .aliasExpansionTooLarge,
-        mayHaveAliases
-            ? 'YAML aliases expand to far more nodes than the text has; the '
-                  'document is not read.'
-            : 'The JSON pointers of the document\'s nodes add up to more than '
-                  'the supported size, because of very long keys or very '
-                  'deep nesting; the document is not read.',
-        node,
-        pointer,
-        fix: mayHaveAliases
-            ? 'Remove the nested aliases.'
-            : 'Shorten the longest keys.',
-      );
-      return null;
-    }
-    final isCollection = node is YamlMap || node is YamlList;
-    if (isCollection && depth > YamlEventGuard.maxDepth) {
-      _fail(
-        .nestingTooDeep,
-        'The document nests deeper than ${YamlEventGuard.maxDepth} levels'
-        '${mayHaveAliases ? ', counting what its aliases expand to' : ''}.',
-        node,
-        pointer,
-      );
-      return null;
-    }
-    spans[pointer.value] = node.span;
-    switch (node) {
-      case YamlMap():
-        final map = <String, Object?>{};
-        final keys = <String, YamlNode>{};
-        for (final MapEntry(:key, :value) in node.nodes.entries) {
-          if (failed) return null;
-          final keyNode = key as YamlNode;
-          final name = '${keyNode.value}';
-          final earlier = keys[name];
-          if (earlier != null) {
-            _diagnostics.report(
-              .duplicateKey,
-              'Keys ${earlier.span.text} and ${keyNode.span.text} are the '
-              'same key "$name" in JSON; the last value is used.',
-              file: _file,
-              pointer: pointer.child(name),
-              span: keyNode.span,
-              fix: 'Remove one of the keys.',
-            );
-          }
-          keys[name] = keyNode;
-          map[name] = convert(value, pointer.child(name), depth + 1);
-        }
-        return map;
-      case YamlList():
-        final list = <Object?>[];
-        for (var i = 0; i < node.nodes.length; i++) {
-          if (failed) return null;
-          list.add(convert(node.nodes[i], pointer.child(i), depth + 1));
-        }
-        return list;
-      default:
-        return node.value;
-    }
-  }
-
-  void _fail(
-    DiagnosticCode code,
-    String message,
-    YamlNode node,
-    JsonPointer pointer, {
-    String? fix,
-  }) {
-    failed = true;
-    _diagnostics.report(
-      code,
-      message,
-      file: _file,
-      pointer: pointer,
-      span: node.span,
-      fix: fix,
-    );
-  }
-}
```

```diff
diff --git a/packages/typed_openapi/test/load/spec_loader_test.dart b/packages/typed_openapi/test/load/spec_loader_test.dart
--- a/packages/typed_openapi/test/load/spec_loader_test.dart
+++ b/packages/typed_openapi/test/load/spec_loader_test.dart
@@ -7,7 +7,7 @@ import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
 import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
 import 'package:typed_openapi/src/diagnostics/severity.dart';
 import 'package:typed_openapi/src/load/spec_loader.dart';
-import 'package:typed_openapi/src/load/yaml_event_guard.dart';
+import 'package:typed_openapi/src/load/yaml_composer.dart';
 
 import '../helpers/temp_dir.dart';
 
@@ -59,25 +59,75 @@ void main() {
         'api.json',
       )!;
       expect(doc.root['info'], {'title': 'b'});
-      expect(doc.hasPositions, isFalse);
-      expect(bag.all.map((d) => d.code), [
-        DiagnosticCode.duplicateKey,
-        DiagnosticCode.positionsUnavailable,
-      ]);
+      expect(doc.hasPositions, isTrue);
+      final d = bag.all.single;
+      expect(d.code, DiagnosticCode.duplicateKey);
+      expect(d.pointer?.value, '#/info');
       expect(bag.hasErrors, isFalse);
     });
 
-    test('a duplicate key in YAML is an error', () {
+    test('a YAML tag outside the JSON Schema ruleset is an error, and the '
+        'rest of the document is read', () {
       final bag = DiagnosticBag();
       final doc = SpecLoader(bag).parse(
-        'openapi: 3.0.3\npaths: {}\npaths: {}\n',
+        'openapi: 3.0.3\nx-when: !!timestamp 2025-07-27T07:17:05Z\n',
+        'api.yaml',
+      )!;
+      expect(doc.root['x-when'], '2025-07-27T07:17:05Z');
+      expect(bag.all.single.code, DiagnosticCode.yamlTagUnsupported);
+    });
+
+    test('a duplicate key in YAML is an error; the last value is used', () {
+      final bag = DiagnosticBag();
+      final doc = SpecLoader(bag).parse(
+        'openapi: 3.0.3\npaths: {/a: {}}\npaths: {}\n',
         'a.yaml',
-      );
-      expect(doc, isNull);
+      )!;
+      expect(doc.root['paths'], <String, Object?>{});
       expect(bag.all.single.code, DiagnosticCode.duplicateKey);
       expect(bag.all.single.severity, Severity.error);
     });
 
+    test('a second YAML document is a parse error, as in package:yaml', () {
+      final bag = DiagnosticBag();
+      expect(
+        SpecLoader(
+          bag,
+        ).parse('openapi: 3.1.0\n---\nopenapi: 3.0.0\n', 'a.yaml'),
+        isNull,
+      );
+      final d = bag.all.single;
+      expect(d.code, DiagnosticCode.parseError);
+      expect(d.span, isNotNull);
+    });
+
+    group('long flow lines', () {
+      const limit = Timeout(Duration(seconds: 30));
+
+      for (final (name, text) in [
+        ('quoted closers', 'openapi: 3.1.0\nx-a: ${'["]",' * 199000}'),
+        ('quoted closers in a JSON-style object', '{"a": ${'["]",' * 199000}'),
+      ]) {
+        test('$name are TOA007 at a position', () {
+          final bag = DiagnosticBag();
+          expect(SpecLoader(bag).parse(text, 'api.yaml'), isNull);
+          final d = bag.all.single;
+          expect(d.code, DiagnosticCode.nestingTooDeep);
+          expect(d.span, isNotNull);
+        }, timeout: limit);
+      }
+
+      test('a spec with many short flow collections is read', () {
+        final bag = DiagnosticBag();
+        final doc = SpecLoader(bag).parse(
+          'openapi: 3.1.0\nx-pairs: [${'[1, 2], ' * 40000}0]\n',
+          'api.yaml',
+        )!;
+        expect(bag.all, isEmpty);
+        expect((doc.root['x-pairs']! as List<Object?>).length, 40001);
+      }, timeout: limit);
+    });
+
     test('a root that is not an object is an error', () {
       final bag = DiagnosticBag();
       expect(SpecLoader(bag).parse('- a\n- b\n', 'a.yaml'), isNull);
@@ -90,7 +140,7 @@ void main() {
       expect(SpecLoader(bag).parse(text, 'api.json'), isNull);
       final d = bag.all.single;
       expect(d.code, DiagnosticCode.nestingTooDeep);
-      expect(d.column, 7 + YamlEventGuard.maxDepth);
+      expect(d.column, 7 + YamlComposer.maxDepth);
     });
 
     test('YAML nested deeper than the limit is an error too', () {
@@ -127,12 +177,11 @@ void main() {
           'not a stack overflow', () {
         final bag = DiagnosticBag();
         final text = deepAlias();
-        expect(const YamlEventGuard().check(text), isNull);
         expect(SpecLoader(bag).parse(text, 'api.yaml'), isNull);
         final d = bag.all.single;
         expect(d.code, DiagnosticCode.nestingTooDeep);
         expect(d.message, contains('alias'));
-        expect(d.pointer!.tokens, hasLength(YamlEventGuard.maxDepth + 1));
+        expect(d.pointer!.tokens, hasLength(YamlComposer.maxDepth + 1));
         expect(d.pointer!.tokens.take(2), ['x-use', '0']);
         expect(d.span, isNotNull);
       }, timeout: limit);
@@ -181,7 +230,7 @@ void main() {
         final bag = DiagnosticBag();
         final doc = SpecLoader(bag).parse(
           'openapi: 3.1.0\nx-deep: '
-              '${'[' * YamlEventGuard.maxDepth}${']' * YamlEventGuard.maxDepth}\n',
+              '${'[' * YamlComposer.maxDepth}${']' * YamlComposer.maxDepth}\n',
           'api.yaml',
         );
         expect(doc, isNotNull);
@@ -192,8 +241,8 @@ void main() {
         final bag = DiagnosticBag();
         final doc = SpecLoader(bag).parse(
           'openapi: 3.1.0\nx-deep: '
-              '${'[' * (YamlEventGuard.maxDepth + 1)}'
-              '${']' * (YamlEventGuard.maxDepth + 1)}\n',
+              '${'[' * (YamlComposer.maxDepth + 1)}'
+              '${']' * (YamlComposer.maxDepth + 1)}\n',
           'api.yaml',
         );
         expect(doc, isNull);
@@ -209,14 +258,14 @@ void main() {
               '{"openapi": "3.1.0", "x": ${'[' * levels}${']' * levels}}';
           final bag = DiagnosticBag();
           expect(
-            SpecLoader(bag).parse(doc(YamlEventGuard.maxDepth), 'a.$extension'),
+            SpecLoader(bag).parse(doc(YamlComposer.maxDepth), 'a.$extension'),
             isNotNull,
           );
           expect(bag.all, isEmpty);
           expect(
             SpecLoader(
               bag,
-            ).parse(doc(YamlEventGuard.maxDepth + 1), 'a.$extension'),
+            ).parse(doc(YamlComposer.maxDepth + 1), 'a.$extension'),
             isNull,
           );
           expect(bag.all.single.code, DiagnosticCode.nestingTooDeep);
@@ -301,65 +350,22 @@ x-two: *base
         return '$text';
       }
 
-      test('the bomb itself passes the guard and is bounded by the budget', () {
+      test('the bomb itself is bounded by the budget', () {
         final bag = DiagnosticBag();
-        expect(const YamlEventGuard().check(bomb('x-k: 1')), isNull);
         expect(SpecLoader(bag).parse(bomb('x-k: 1'), 'api.yaml'), isNull);
-        expect(bag.all.single.message, isNot(contains('mapping key')));
+        expect(bag.all.single.code, DiagnosticCode.aliasExpansionTooLarge);
       }, timeout: limit);
 
-      // Every key syntax of the re-reviews: package:yaml parses each as a key
-      // that contains an alias, and the guard must see it before loading.
-      for (final (name, tail) in [
-        ('after a ? marker', '? *l7\n: v'),
-        ('inside a ? key sequence', '? [*l7]\n: v'),
-        ('inside a ? key block sequence', '? - *l7\n: v'),
-        ('inside a ? key block sequence at the same column', '?\n- *l7\n: v'),
-        ('inside a nested ? key', 'x-k:\n  ?\n  - *l7\n  : v'),
-        ('before a colon', '*l7 : v'),
-        ('in a flow mapping', 'x-k: {*l7 : v}'),
-        ('as an entry of a flow mapping', 'x-k: {a: 1, *l7 : v}'),
-        ('as a bare entry of a flow mapping', 'x-k: {*l7, a: 1}'),
-        ('after a ? inside a flow mapping', 'x-k: {? *l7 : v}'),
-        ('after a ? inside a flow sequence', 'x-k: [? *l7 : v]'),
-        ('inside a flow sequence key', '[*l7]: v'),
-        ('inside a flow mapping key', '{a: *l7}: v'),
-        ('inside a flow key of a flow mapping', 'x-k: {[*l7]: v}'),
-        ('inside a tagged flow sequence key', '!!seq [*l7]: v'),
-        ('inside an anchored flow sequence key', '&z [*l7]: v'),
-        ('inside a flow key in a block sequence', 'x-k:\n  - [*l7]: v'),
-        ('inside a flow key without a colon', 'x-k: {[*l7]}'),
-        ('inside a flow key on its own line', 'x-k:\n  {\n   [*l7]\n  }'),
-        ('inside a flow key before a comma', 'x-k: {[*l7], a: 1}'),
-        ('inside a flow mapping in a flow mapping', 'x-k: {{a: *l7}}'),
-        ('inside a flow key, colon on the next line', 'x-k: [ [*l7]\n  : v]'),
-        ('after a bare dash line', 'x-k:\n  - a\n  -\n    *l7 : v'),
-        (
-          'in a flow mapping after a bare dash line',
-          'x-k:\n  - a\n  -\n    {*l7 : v}',
-        ),
-        ('after a : and a # without a blank', 'x-k:\n  {a:# x, b: *l7}: v'),
-        ('in a flow key after a : and a #', 'x-k:\n  [{a:# x, b: *l7}]: v'),
-        ('in a flow sequence after a : and a #', 'x-k:\n  [a:#, *l7]: v'),
-        (
-          'after a : and a quote without a blank',
-          "x-k:\n  {true:'x, c: *l7}: v",
-        ),
-        ('after a ? and a quote without a blank', 'x-k:\n  {?"a : *l7}: v'),
-        ('after a nested ? and a quote', 'x-k:\n  {x: {?"a : *l7}}: v'),
-        ('after a ? and a # without a blank', 'x-k:\n  {?#a : {v: *l7}}: 1'),
-        ('after a " in a flow mapping', 'x-k:\n  [{a:"b, c: *l7}]: 1'),
-        ('after an indented ---', 'x-k:\n --- "q:\n    j: 1\n    ? *l7'),
-      ]) {
-        test('an alias $name is reported before it is expanded', () {
-          final bag = DiagnosticBag();
-          expect(SpecLoader(bag).parse(bomb(tail), 'api.yaml'), isNull);
-          final d = bag.all.single;
-          expect(d.code, DiagnosticCode.aliasExpansionTooLarge);
-          expect(d.message, contains('mapping key'));
-          expect(d.span, isNotNull);
-        }, timeout: limit);
-      }
+      test('an alias of a collection as a key is an error, and the rest '
+          'of the document is read', () {
+        final bag = DiagnosticBag();
+        final doc = SpecLoader(bag).parse(
+          'openapi: 3.1.0\nx-a: &a [1, 2]\n? *a\n: v\nx-b: 1\n',
+          'api.yaml',
+        )!;
+        expect(doc.root.keys, ['openapi', 'x-a', 'x-b']);
+        expect(bag.all.single.code, DiagnosticCode.nonStringKey);
+      }, timeout: limit);
 
       test('aliases everywhere except in keys are accepted', () {
         final bag = DiagnosticBag();
```

Changed expectations: a YAML duplicate now gives a document (the last value) and TOA002 error; a duplicate in `.json` has positions (without TOA005); alias keys are checked by `yaml_composer_test.dart` (TOA113). `yaml_event_guard_test.dart` stays until task 2.

- [ ] **Step 8: Check**

```bash
dart analyze packages                                  # from the root: No issues found!
dart test                                              # from packages/typed_openapi
dart format lib test bin && dart format lib test bin   # second run: 0 changed
```

Expected: 316 tests.

- [ ] **Step 9: Measure Stripe before and after**

```bash
C=<path to the research/08 corpus>/typed_openapi.yaml
git worktree add ../m3-before main
(cd ../m3-before && dart pub get >/dev/null && cd packages/typed_openapi && time dart run bin/typed_openapi.dart check -c "$C" stripe)
(cd packages/typed_openapi && time dart run bin/typed_openapi.dart check -c "$C" stripe)
git worktree remove ../m3-before
```

Expected: no slower than on `main`. While the plan was being written, `SpecLoader.parse` on Stripe (`spec3.json`) took ~650 ms on `main` and ~355 ms with the composer; OpenAI (`openapi.yaml`) — ~270 and ~155 ms.

- [ ] **Step 10: Commit**

```bash
git add packages/typed_openapi
git commit -m "feat(typed_openapi): compose YAML from parser events in one iterative pass

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `ConfigLoader` on the composer, without `YamlEventGuard`

**Files:**
- Modify: `packages/typed_openapi/lib/src/config/config_loader.dart` (full replacement), `packages/typed_openapi/test/config/config_loader_test.dart`, `packages/typed_openapi/test/resolve/spec_reader_test.dart`, `packages/typed_openapi/pubspec.yaml`
- Delete: `packages/typed_openapi/lib/src/load/yaml_event_guard.dart`, `packages/typed_openapi/test/load/yaml_event_guard_test.dart`, `packages/typed_openapi/test/load/yaml_event_guard_fuzz_test.dart`

**Interfaces:**
- Consumes: `YamlComposer`, `ComposedYaml` (task 1).
- Produces: `ConfigLoader` reads a plain tree; every problem of the YAML itself is reported as `TOA902` with the level, pointer and position from the composer. No `package:yaml` imports remain in `lib/`; `yaml` is only a dev dependency.

The guard tests that make sense are already in `yaml_composer_test.dart` (task 1); the guard fuzz is replaced by the composer's comparison fuzz and the 300 000-document run on asserts.

- [ ] **Step 1: Tests**

```diff
diff --git a/packages/typed_openapi/test/config/config_loader_test.dart b/packages/typed_openapi/test/config/config_loader_test.dart
--- a/packages/typed_openapi/test/config/config_loader_test.dart
+++ b/packages/typed_openapi/test/config/config_loader_test.dart
@@ -88,31 +88,31 @@ clients:
     expect(bag.all.single.message, contains('nests deeper'));
   });
 
-  for (final (name, key) in [
-    ('an explicit ? key', 'x-key:\n  ? *l7\n  : v'),
-    ('a flow sequence key', '[*l7]: v'),
-    ('a flow mapping key', '{a: *l7}: v'),
-    ('a flow mapping key without a colon', 'x-key: {[*l7]}'),
-    ('a ? key inside a flow mapping', 'x-key: {? *l7 : v}'),
-    ('a key after a bare dash line', 'x-key:\n  - a\n  -\n    *l7 : v'),
-  ]) {
-    test('rejects $name with an alias before expanding it', () {
-      final text = StringBuffer('x-l0: &l0 [x, x, x, x, x, x, x, x, x]\n');
-      for (var i = 1; i <= 7; i++) {
-        text.writeln('x-l$i: &l$i');
-        for (var n = 0; n < 9; n++) {
-          text.writeln('  - *l${i - 1}');
-        }
-      }
-      text.writeln(key);
-      text.writeln('clients:\n  api: {input: a.json, output: lib/api}');
-      final path = TempDir().write('typed_openapi.yaml', '$text');
-      final bag = DiagnosticBag();
-      expect(ConfigLoader(bag).load(path), isNull);
-      expect(bag.all.single.code, DiagnosticCode.configInvalid);
-      expect(bag.all.single.message, contains('mapping key'));
-    }, timeout: const Timeout(Duration(seconds: 30)));
-  }
+  test('rejects a collection as a key without expanding it', () {
+    final path = TempDir().write('typed_openapi.yaml', '''
+x-list: &l [a, b]
+? *l
+: v
+clients:
+  api: {input: a.json, output: lib/api}
+''');
+    final bag = DiagnosticBag();
+    expect(ConfigLoader(bag).load(path)!.clients, hasLength(1));
+    final codes = bag.all.map((d) => d.code).toList();
+    expect(codes, contains(DiagnosticCode.configInvalid));
+    expect(
+      bag.all.firstWhere((d) => d.code == DiagnosticCode.configInvalid).message,
+      contains('mapping key'),
+    );
+  });
+
+  test('reports a syntax error with its position', () {
+    final path = TempDir().write('c.yaml', 'clients: [a, b\n');
+    final bag = DiagnosticBag();
+    expect(ConfigLoader(bag).load(path), isNull);
+    expect(bag.all.single.code, DiagnosticCode.configInvalid);
+    expect(bag.all.single.span, isNotNull);
+  });
 
   test('accepts an alias in a value', () {
     final path = TempDir().write('typed_openapi.yaml', '''
```

```diff
diff --git a/packages/typed_openapi/test/resolve/spec_reader_test.dart b/packages/typed_openapi/test/resolve/spec_reader_test.dart
--- a/packages/typed_openapi/test/resolve/spec_reader_test.dart
+++ b/packages/typed_openapi/test/resolve/spec_reader_test.dart
@@ -3,7 +3,7 @@ import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
 import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
 import 'package:typed_openapi/src/load/openapi_version.dart';
 import 'package:typed_openapi/src/load/spec_loader.dart';
-import 'package:typed_openapi/src/load/yaml_event_guard.dart';
+import 'package:typed_openapi/src/load/yaml_composer.dart';
 import 'package:typed_openapi/src/model/schema.dart';
 import 'package:typed_openapi/src/resolve/spec_reader.dart';
 
@@ -51,7 +51,7 @@ components:
 
   test('a schema nested as deep as the loader allows is read', () {
     final bag = DiagnosticBag();
-    const depth = YamlEventGuard.maxDepth - 4;
+    const depth = YamlComposer.maxDepth - 4;
     final schema = '${'{"items": ' * depth}{"type": "string"}${'}' * depth}';
     final document = SpecLoader(bag).parse(
       '{"openapi": "3.1.0", "info": {"title": "t", "version": "1"}, '
```

Run: `dart test test/config` — Expected: FAIL (the guard rejects the whole config with a collection key).

- [ ] **Step 2: `ConfigLoader`**

Replace `packages/typed_openapi/lib/src/config/config_loader.dart`:

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/json_pointer.dart';
import '../load/yaml_composer.dart';
import 'project_config.dart';

/// Reads `typed_openapi.yaml` into a [ProjectConfig].
///
/// Problems go to the [DiagnosticBag] given to the constructor instead of
/// being thrown.
final class ConfigLoader {
  /// Creates a loader that reports to [_diagnostics].
  const ConfigLoader(this._diagnostics);

  static const _topLevelKeys = {'defaults', 'clients'};
  static const _defaultsKeys = {'preset', 'line_width'};
  static const _clientKeys = {
    'input',
    'output',
    'preset',
    'overrides',
    'baseline',
    'line_width',
  };

  final DiagnosticBag _diagnostics;

  /// Reads the config file at [path].
  ///
  /// Relative paths inside it are resolved against its directory. Returns
  /// null when the file is missing or unusable; otherwise returns every
  /// client that is valid.
  ProjectConfig? load(String path) {
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) {
      _diagnostics.report(
        .configNotFound,
        'Config file $path does not exist.',
        file: path,
        fix: 'Create typed_openapi.yaml, or pass its path with --config.',
      );
      return null;
    }
    if (type == FileSystemEntityType.directory) {
      _diagnostics.report(
        .configInvalid,
        'Config path $path is a directory, not a file.',
        file: path,
        fix: 'Pass the path of typed_openapi.yaml itself with --config.',
      );
      return null;
    }
    final String text;
    try {
      text = File(path).readAsStringSync();
    } on FileSystemException catch (e) {
      _diagnostics.report(
        .configInvalid,
        'Cannot read $path: ${e.message}.',
        file: path,
      );
      return null;
    }
    final composed = _compose(text, path);
    if (composed == null) return null;
    final reader = _ConfigReader(path, _diagnostics, composed.spans);
    final root = composed.root;
    if (root is! Map<String, Object?>) {
      reader.invalid('The config must be a mapping.', .root);
      return null;
    }
    reader.checkKeys(root, _topLevelKeys, .root);

    final defaultsPointer = JsonPointer.root.child('defaults');
    final defaults = reader.mapAt(root, 'defaults', .root);
    Preset? defaultPreset;
    int? defaultWidth;
    if (defaults != null) {
      reader.checkKeys(defaults, _defaultsKeys, defaultsPointer);
      defaultPreset = reader.presetAt(defaults, defaultsPointer);
      defaultWidth = reader.intAt(defaults, 'line_width', defaultsPointer);
    }

    final clientsPointer = JsonPointer.root.child('clients');
    final clientNodes = reader.mapAt(root, 'clients', .root, required: true);
    if (clientNodes == null) return null;
    if (clientNodes.isEmpty) {
      reader.invalid('"clients" is empty.', clientsPointer);
      return null;
    }

    final baseDir = p.dirname(p.absolute(path));
    String resolve(String value) => p.normalize(p.join(baseDir, value));

    final clients = <ClientConfig>[];
    final declared = <String>{};
    final outputSpans = <String, SourceSpan?>{};
    for (final MapEntry(key: name, :value) in clientNodes.entries) {
      declared.add(name);
      final pointer = clientsPointer.child(name);
      if (value is! Map<String, Object?>) {
        reader.invalid('Client "$name" must be a mapping.', pointer);
        continue;
      }
      reader.checkKeys(value, _clientKeys, pointer);
      final input = reader.stringAt(value, 'input', pointer, required: true);
      final output = reader.stringAt(value, 'output', pointer, required: true);
      final preset = reader.presetAt(value, pointer) ?? defaultPreset;
      final lineWidth =
          reader.intAt(value, 'line_width', pointer) ??
          defaultWidth ??
          ClientConfig.defaultLineWidth;
      final overrides = reader.stringAt(value, 'overrides', pointer);
      final baseline = reader.stringAt(value, 'baseline', pointer);
      if (input == null || output == null) continue;
      outputSpans[name] = reader.spanAt(pointer.child('output'));
      clients.add(
        ClientConfig(
          name: name,
          input: resolve(input),
          output: resolve(output),
          lineWidth: lineWidth,
          preset: preset,
          overrides: overrides == null ? null : resolve(overrides),
          baseline: baseline == null ? null : resolve(baseline),
        ),
      );
    }
    clients.sort((a, b) => a.name.compareTo(b.name));
    _checkOutputOverlap(clients, outputSpans, path);
    return ProjectConfig(
      file: path,
      clients: clients,
      declaredClients: declared,
    );
  }

  /// Reads [text] into plain values; null after reporting why it cannot be
  /// used. Every problem of the YAML itself is a config error.
  ComposedYaml? _compose(String text, String path) {
    final yaml = DiagnosticBag();
    final composed = YamlComposer(
      yaml,
    ).compose(text, file: path, uri: p.toUri(p.absolute(path)));
    for (final d in yaml.all) {
      _diagnostics.report(
        .configInvalid,
        d.message,
        severity: d.severity,
        file: path,
        pointer: d.pointer,
        span: d.span,
        fix: d.fix,
      );
    }
    if (composed?.syntaxError case final error?) {
      _diagnostics.report(
        .configInvalid,
        error.message,
        file: path,
        span: error.span,
      );
      return null;
    }
    return composed;
  }

  void _checkOutputOverlap(
    List<ClientConfig> clients,
    Map<String, SourceSpan?> outputSpans,
    String file,
  ) {
    for (var i = 0; i < clients.length; i++) {
      for (var j = i + 1; j < clients.length; j++) {
        final a = clients[i];
        final b = clients[j];
        final overlap =
            p.equals(a.output, b.output) ||
            p.isWithin(a.output, b.output) ||
            p.isWithin(b.output, a.output);
        if (!overlap) continue;
        _diagnostics.report(
          .outputOverlap,
          'Clients "${a.name}" and "${b.name}" write to overlapping '
          'directories.',
          file: file,
          pointer: JsonPointer.root
              .child('clients')
              .child(b.name)
              .child('output'),
          span: outputSpans[b.name],
          fix: 'Give each client its own output directory.',
        );
      }
    }
  }
}

/// Typed access to the values of a config document that reports bad ones.
class _ConfigReader {
  _ConfigReader(this.file, this.diagnostics, this.spans);

  final String file;
  final DiagnosticBag diagnostics;
  final Map<String, SourceSpan> spans;

  SourceSpan? spanAt(JsonPointer at) => spans[at.value];

  void checkKeys(
    Map<String, Object?> map,
    Set<String> allowed,
    JsonPointer at,
  ) {
    for (final name in map.keys) {
      if (allowed.contains(name)) continue;
      diagnostics.report(
        .configUnknownKey,
        'Unknown key "$name".',
        file: file,
        pointer: at.child(name),
        span: spanAt(at.child(name)),
        fix: 'Allowed keys here: ${(allowed.toList()..sort()).join(', ')}.',
      );
    }
  }

  Map<String, Object?>? mapAt(
    Map<String, Object?> parent,
    String key,
    JsonPointer at, {
    bool required = false,
  }) {
    if (!parent.containsKey(key)) {
      if (required) invalid('Missing required key "$key".', at);
      return null;
    }
    final value = parent[key];
    if (value is Map<String, Object?>) return value;
    invalid('"$key" must be a mapping.', at.child(key));
    return null;
  }

  String? stringAt(
    Map<String, Object?> parent,
    String key,
    JsonPointer at, {
    bool required = false,
  }) {
    if (!parent.containsKey(key)) {
      if (required) invalid('Missing required key "$key".', at);
      return null;
    }
    final value = parent[key];
    if (value is String && value.isNotEmpty) return value;
    invalid('"$key" must be a non-empty string.', at.child(key));
    return null;
  }

  int? intAt(Map<String, Object?> parent, String key, JsonPointer at) {
    if (!parent.containsKey(key)) return null;
    final value = parent[key];
    if (value is int && value > 0) return value;
    invalid('"$key" must be a positive integer.', at.child(key));
    return null;
  }

  Preset? presetAt(Map<String, Object?> parent, JsonPointer at) {
    final name = stringAt(parent, 'preset', at);
    if (name == null) return null;
    final preset = Preset.values.asNameMap()[name];
    if (preset != null) return preset;
    final known = Preset.values.map((v) => v.name).toList()..sort();
    invalid(
      'Unknown preset "$name". Known presets: ${known.join(', ')}.',
      at.child('preset'),
    );
    return null;
  }

  void invalid(String message, JsonPointer at) {
    diagnostics.report(
      .configInvalid,
      message,
      file: file,
      pointer: at,
      span: spanAt(at),
    );
  }
}
```

- [ ] **Step 3: Remove the guard, move `yaml` to dev**

```bash
git rm packages/typed_openapi/lib/src/load/yaml_event_guard.dart \
  packages/typed_openapi/test/load/yaml_event_guard_test.dart \
  packages/typed_openapi/test/load/yaml_event_guard_fuzz_test.dart
```

In `pubspec.yaml` remove the `yaml` line with the comment above it from `dependencies`; `dev_dependencies`:

```yaml
dev_dependencies:
  test: ^1.24.0
  # Tests compare the composer with package:yaml's loader.
  yaml: ^3.1.4
```

Run: `grep -rn "import 'package:yaml" packages/typed_openapi/lib` — Expected: nothing.

- [ ] **Step 4: Check**

```bash
dart analyze packages                                  # from the root: No issues found!
dart test                                              # from packages/typed_openapi
dart format lib test bin && dart format lib test bin   # second run: 0 changed
```

Expected: 256 tests (the guard tests are removed).

- [ ] **Step 5: Commit**

```bash
git add packages/typed_openapi
git commit -m "refactor(typed_openapi): read the config with the YAML composer

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `$ref` where OAS does not allow it, and the YAML merge key (TOA107, TOA108, TOA109)

**Files:**
- Create: `packages/typed_openapi/test/parse/ref_placement_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_openapi/lib/src/parse/object_reader.dart`

**Interfaces:**
- Consumes: `ObjectReader`, `ParseContext.document.spanOf` (M2), the composer's positions (task 1).
- Produces: codes `refNotAllowed` (TOA107), `refCommentedOut` (TOA108), `yamlMergeKey` (TOA109).

Behaviour: `$ref` as an unknown key and an object-`$ref` in place of a string/value — TOA107 (hint `redocly bundle`), not TOA110/TOA111. An empty `$ref` followed by `#` in the text (block and flow entry) — TOA108 (hint to quote it). The key `<<` — TOA109: in an object it stays an ordinary (unknown) key, and in a map of named entries (`components.*`, `paths`, `responses`, `properties` …) the entry after TOA109 is skipped, so it does not become a schema or a path named `<<` and does not cascade into TOA110. There is no merging.

- [ ] **Step 1: Codes**

Before the line `/// An object has a key that no OpenAPI version defines; it is ignored.`:

```dart
  /// A `$ref` where OpenAPI does not accept a Reference Object, as bundlers
  /// such as Redocly allow; it is ignored.
  refNotAllowed('TOA107', 'ref-not-allowed', .warning),

  /// `$ref: #/...` without quotes in YAML: `#` starts a comment, so the
  /// value is null.
  refCommentedOut('TOA108', 'ref-commented-out', .warning),

  /// A YAML 1.1 merge key `<<`, which OpenAPI's YAML does not have; it is
  /// read as a plain key named `<<`.
  yamlMergeKey('TOA109', 'yaml-merge-key', .warning),
```

- [ ] **Step 2: A test that fails**

Create `packages/typed_openapi/test/parse/ref_placement_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/resolve/spec_reader.dart';

void main() {
  /// The diagnostics of reading [yaml] as a 3.1 document.
  List<Diagnostic> read(String yaml) {
    final bag = DiagnosticBag();
    final document = SpecLoader(bag).parse(yaml, 'api.yaml')!;
    SpecReader(bag).read(document, .v31);
    return bag.sorted;
  }

  group(r'a $ref where OpenAPI does not accept one', () {
    test('as an operation is ref-not-allowed, not unknown-key', () {
      final found = read(r'''
openapi: 3.1.0
info: {title: Shop, version: "1"}
paths:
  /orders:
    get:
      $ref: resources/orders/list.yml
''');
      final d = found.single;
      expect(d.code, DiagnosticCode.refNotAllowed);
      expect(d.pointer?.value, r'#/paths/~1orders/get/$ref');
      expect(d.fix, contains('redocly bundle'));
    });

    test('instead of a string is ref-not-allowed, not invalid-value', () {
      final found = read(r'''
openapi: 3.1.0
info:
  title: Shop
  version: "1"
  description: {$ref: description.yml#/introduction}
paths:
  /orders:
    get:
      tags: [{$ref: tags.yml#/orders}]
''');
      expect(found.map((d) => (d.code, d.pointer?.value)), [
        (DiagnosticCode.refNotAllowed, '#/info/description'),
        (DiagnosticCode.refNotAllowed, '#/paths/~1orders/get/tags/0'),
      ]);
      expect(found.first.message, contains('expects a string here'));
    });

    test('a Reference Object where one is allowed is not reported', () {
      final found = read(r'''
openapi: 3.1.0
info: {title: Shop, version: "1"}
paths:
  /orders:
    get:
      responses:
        "200": {$ref: "#/components/responses/Ok"}
components:
  responses:
    Ok: {description: ok}
''');
      expect(found, isEmpty);
    });
  });

  group(r'an unquoted $ref: #/...', () {
    test('reads as a comment and gets a hint to quote it', () {
      final found = read(r'''
openapi: 3.1.0
info: {title: Shop, version: "1"}
components:
  schemas:
    Order:
      type: object
      properties:
        kind:
          $ref: #/components/schemas/Kind
    Kind: {type: string}
''');
      final d = found.single;
      expect(d.code, DiagnosticCode.refCommentedOut);
      expect(
        d.pointer?.value,
        r'#/components/schemas/Order/properties/kind/$ref',
      );
      expect(d.fix, contains("'#/components/schemas/Pet'"));
    });

    test('in a Reference Object as well', () {
      final found = read(r'''
openapi: 3.1.0
info: {title: Shop, version: "1"}
paths:
  /orders:
    get:
      responses:
        "200":
          $ref:   # /components/responses/Ok
''');
      expect(found.single.code, DiagnosticCode.refCommentedOut);
    });

    test('in a flow mapping, where the comment ends the line', () {
      final found = read(r'''
openapi: 3.1.0
info: {title: Shop, version: "1"}
components:
  schemas:
    Order: {$ref: #/components/schemas/Base
      }
''');
      expect(found.single.code, DiagnosticCode.refCommentedOut);
    });

    test(r'an empty $ref without a comment stays invalid-value', () {
      final found = read(r'''
openapi: 3.1.0
info: {title: Shop, version: "1"}
components:
  schemas:
    Order:
      $ref:
''');
      expect(found.single.code, DiagnosticCode.invalidValue);
    });
  });

  group('a YAML merge key', () {
    test('in an object is yaml-merge-key, not unknown-key', () {
      final found = read('''
openapi: 3.1.0
info: {title: Shop, version: "1"}
x-defaults: &defaults {summary: List}
paths:
  /orders:
    get:
      <<: *defaults
      responses: {}
''');
      final d = found.single;
      expect(d.code, DiagnosticCode.yamlMergeKey);
      expect(d.pointer?.value, '#/paths/~1orders/get/<<');
      expect(d.fix, 'Write the keys out.');
    });

    test('in a map of named entries is reported and left out', () {
      final found = read('''
openapi: 3.1.0
info: {title: Shop, version: "1"}
components:
  schemas:
    <<: {Base: {type: object}}
    Order: {type: object}
''');
      final d = found.single;
      expect(d.code, DiagnosticCode.yamlMergeKey);
      expect(d.pointer?.value, '#/components/schemas/<<');
    });
  });
}
```

Run: `dart test test/parse/ref_placement_test.dart` — Expected: FAIL (TOA110/TOA111 instead of the new codes).

- [ ] **Step 3: `ObjectReader`**

```diff
diff --git a/packages/typed_openapi/lib/src/parse/object_reader.dart b/packages/typed_openapi/lib/src/parse/object_reader.dart
--- a/packages/typed_openapi/lib/src/parse/object_reader.dart
+++ b/packages/typed_openapi/lib/src/parse/object_reader.dart
@@ -1,3 +1,5 @@
+import 'package:source_span/source_span.dart';
+
 import '../diagnostics/json_pointer.dart';
 import '../model/spec_node.dart';
 import 'parse_context.dart';
@@ -143,9 +145,12 @@ final class ObjectReader {
       return null;
     }
     final at = pointer.child(key);
+    // In a map of named entries, a merge key is not an entry: it is reported
+    // and left out, so it does not become a schema or a path named "<<".
+    if (entries.containsKey(_mergeKey)) _merge(at.child(_mergeKey));
     return Map.unmodifiable({
       for (final MapEntry(key: name, :value) in entries.entries)
-        if (!skipExtensions || !name.startsWith('x-'))
+        if ((!skipExtensions || !name.startsWith('x-')) && name != _mergeKey)
           name: ?read(value, at.child(name)),
     });
   }
@@ -191,6 +196,20 @@ final class ObjectReader {
       if (_read.contains(key)) continue;
       if (!reportExtensions && key.startsWith('x-')) continue;
       unknown[key] = value;
+      if (key == _mergeKey) {
+        _merge(pointer.child(key));
+        continue;
+      }
+      if (key == r'$ref') {
+        _context.report(
+          .refNotAllowed,
+          'OpenAPI does not accept a Reference Object here, so this '
+          r'"$ref" is ignored.',
+          pointer.child(key),
+          fix: _bundleFix,
+        );
+        continue;
+      }
       _context.report(
         .unknownKey,
         'Unknown key "$key"; it is ignored.',
@@ -221,6 +240,10 @@ final class ObjectReader {
 
   T? _item<T>(Object? raw, JsonPointer at, String expected) {
     if (raw is T) return raw;
+    if (_isRefObject(raw)) {
+      _refNotAllowed(at, expected);
+      return null;
+    }
     _context.report(
       .invalidValue,
       'Each item must be $expected, not ${describe(raw)}.',
@@ -230,6 +253,21 @@ final class ObjectReader {
   }
 
   void _invalid(String key, String expected, Object? raw) {
+    final at = pointer.child(key);
+    if (_isRefObject(raw)) {
+      _refNotAllowed(at, expected);
+      return;
+    }
+    if (key == r'$ref' && raw == null && _commentFollows(at)) {
+      _context.report(
+        .refCommentedOut,
+        r'This "$ref" is empty: without quotes, "#" starts a YAML comment, '
+        'so the reference was read as a comment.',
+        at,
+        fix: r"Quote the reference: $ref: '#/components/schemas/Pet'.",
+      );
+      return;
+    }
     _context.report(
       .invalidValue,
       '"$key" must be $expected, not ${describe(raw)}; it is ignored.',
@@ -237,6 +275,62 @@ final class ObjectReader {
     );
   }
 
+  static const _bundleFix =
+      r'A spec that puts "$ref" anywhere is written for a bundler (Redocly, '
+      'swagger-cli) that resolves it as a JSON Reference. Bundle it first, '
+      'for example with `redocly bundle`, and check the bundled file.';
+
+  static const _mergeKey = '<<';
+
+  void _merge(JsonPointer at) {
+    _context.report(
+      .yamlMergeKey,
+      '"<<" is a YAML 1.1 merge key; OpenAPI tools read it as a plain key '
+      'named "<<", so its keys are not merged here.',
+      at,
+      fix: 'Write the keys out.',
+    );
+  }
+
+  static bool _isRefObject(Object? raw) =>
+      raw is Map<String, Object?> && raw.containsKey(r'$ref');
+
+  void _refNotAllowed(JsonPointer at, String expected) {
+    _context.report(
+      .refNotAllowed,
+      'OpenAPI expects $expected here, not a Reference Object, so this '
+      r'"$ref" is ignored.',
+      at,
+      fix: _bundleFix,
+    );
+  }
+
+  /// Whether the empty value at [at] was written as `key: #...`, so that
+  /// the `#` started a comment.
+  ///
+  /// package:yaml puts an empty block value at the `:` of its key, and an
+  /// empty flow value at the token after it, which is on a later line when
+  /// a comment ended the line.
+  bool _commentFollows(JsonPointer at) {
+    final span = _context.document.spanOf(at);
+    if (span is! FileSpan) return false;
+    final file = span.file;
+    String lineAt(int line) => file.getText(
+      file.getOffset(line),
+      line + 1 < file.lines ? file.getOffset(line + 1) : file.length,
+    );
+    final line = span.start.line;
+    final before = file.getText(file.getOffset(line), span.start.offset);
+    final rest = lineAt(line).substring(before.length);
+    if (_blockComment.hasMatch(rest)) return true;
+    return before.trim().isEmpty &&
+        line > 0 &&
+        _flowComment.hasMatch(lineAt(line - 1));
+  }
+
+  static final _blockComment = RegExp(r'^:?[ \t]+#');
+  static final _flowComment = RegExp(r':[ \t]+#[^\n]*\n?$');
+
   void _missing(String key) {
     _context.report(
       .missingRequiredField,
```

- [ ] **Step 4: Check**

```bash
dart analyze packages                                  # from the root: No issues found!
dart test                                              # from packages/typed_openapi
dart format lib test bin && dart format lib test bin   # second run: 0 changed
```

Expected: 265 tests.

- [ ] **Step 5: Commit**

```bash
git add packages/typed_openapi
git commit -m "feat(typed_openapi): report $ref where OpenAPI does not allow it and YAML merge keys

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Rule engine: `SpecEdit`, `TreeEditor`, `NormalizerRule`, `Normalizer` (TOA800)

**Files:**
- Create: `packages/typed_openapi/lib/src/normalize/spec_edit.dart`, `packages/typed_openapi/lib/src/normalize/normalizer_rule.dart`, `packages/typed_openapi/lib/src/normalize/normalizer.dart`, `packages/typed_openapi/test/normalize/spec_edit_test.dart`, `packages/typed_openapi/test/normalize/normalizer_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_openapi/lib/src/load/spec_document.dart`, `packages/typed_openapi/lib/src/resolve/spec_documents.dart`, `packages/typed_openapi/lib/src/resolve/spec_reader.dart`, `packages/typed_openapi/lib/src/resolve/spec_model.dart`, `packages/typed_openapi/lib/src/model/spec_node.dart`

**Interfaces:**
- Consumes: `SpecReader`, `SpecDocuments`, `SpecModel`, `SpecLoader` (M2), `Preset` (M1).
- Produces: the "model / resolve" and "normalize" blocks from "Interfaces"; `RuleContext.rawObject`; code `fixNotApplied` (TOA800). `Normalizer.rules` is empty — the rules are added by tasks 5, 7–11.

Behaviour: `TreeEditor` changes a copy (the original and nodes shared through an alias stay unchanged); the fix is applied and the model is re-read; a TOA111 from the first read that the fix removed does not reach the report; all findings of a rule that fixed something in the pass are reported (including those without an own edit); diagnostic-only findings — once, from the last pass; of two edits of one node the earlier rule wins (the second — TOA800); three passes at most; a disabled rule does not run; a preset adds a hint; edits in another file are applied to it.

- [ ] **Step 1: Code**

Before the line `/// The configuration file does not exist.`:

```dart
  /// A normalizer fix was not applied: it overlaps an earlier rule's fix,
  /// its target is gone, or the spec kept changing.
  fixNotApplied('TOA800', 'fix-not-applied', .warning),
```

- [ ] **Step 2: Tests**

Create `packages/typed_openapi/test/normalize/spec_edit_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/model/spec_node.dart';
import 'package:typed_openapi/src/normalize/spec_edit.dart';

void main() {
  final file = Uri.file('/specs/api.yaml');
  SpecLocation at(String pointer) =>
      SpecLocation(file, JsonPointer.parse(pointer));

  test('add, replace and remove change a copy, never the original', () {
    final original = <String, Object?>{
      'a': {'b': 1, 'c': 2},
      'l': [1, 2],
    };
    final editor = TreeEditor(original);
    expect(editor.apply(SpecEdit.add(at('#/a/d'), 3)), isNull);
    expect(editor.apply(SpecEdit.replace(at('#/a/b'), 10)), isNull);
    expect(editor.apply(SpecEdit.remove(at('#/a/c'))), isNull);
    expect(editor.apply(SpecEdit.add(at('#/l/-'), 3)), isNull);
    expect(editor.apply(SpecEdit.add(at('#/l/0'), 0)), isNull);
    expect(editor.apply(SpecEdit.remove(at('#/l/1'))), isNull);
    expect(editor.root, {
      'a': {'b': 10, 'd': 3},
      'l': [0, 2, 3],
    });
    expect(original, {
      'a': {'b': 1, 'c': 2},
      'l': [1, 2],
    });
  });

  test('a node shared by two places (a YAML alias) changes in one', () {
    final shared = <String, Object?>{'type': 'string'};
    final editor = TreeEditor({'x': shared, 'y': shared});
    expect(editor.apply(SpecEdit.add(at('#/x/format'), 'uuid')), isNull);
    expect(editor.root['x'], {'type': 'string', 'format': 'uuid'});
    expect(editor.root['y'], {'type': 'string'});
  });

  test('an edit of a missing node says why and changes nothing', () {
    final editor = TreeEditor({
      'a': {'b': 1},
    });
    expect(editor.apply(SpecEdit.replace(at('#/a/x'), 1)), contains('#/a/x'));
    expect(editor.apply(SpecEdit.remove(at('#/a/b/c'))), isNotNull);
    expect(editor.apply(SpecEdit.add(at('#/l/0'), 1)), isNotNull);
    expect(editor.apply(SpecEdit.remove(at('#'))), contains('root'));
    expect(editor.root, {
      'a': {'b': 1},
    });
  });

  test('edits overlap when one is at or inside the other', () {
    final b = SpecEdit.remove(at('#/a/b'));
    expect(b.overlaps(SpecEdit.remove(at('#/a/b'))), isTrue);
    expect(b.overlaps(SpecEdit.add(at('#/a/b/c'), 1)), isTrue);
    expect(b.overlaps(SpecEdit.remove(at('#/a'))), isTrue);
    expect(b.overlaps(SpecEdit.remove(at('#/a/bc'))), isFalse);
    expect(
      b.overlaps(
        SpecEdit.remove(SpecLocation(Uri.file('/b.yaml'), b.location.pointer)),
      ),
      isFalse,
    );
  });
}
```

Create `packages/typed_openapi/test/normalize/normalizer_test.dart`:

```dart
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/config/project_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/model/document.dart';
import 'package:typed_openapi/src/model/schema.dart';
import 'package:typed_openapi/src/normalize/normalizer.dart';
import 'package:typed_openapi/src/normalize/normalizer_rule.dart';
import 'package:typed_openapi/src/normalize/spec_edit.dart';

import '../helpers/temp_dir.dart';

/// Renames the title "old" to "new": a fix that holds after one pass.
final class _RenameTitle extends NormalizerRule {
  const _RenameTitle();

  @override
  String get name => 'rename-title';

  @override
  List<DiagnosticCode> get codes => const [.invalidValue];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final info in context.nodes<Info>()) {
      if (info.title != 'old') continue;
      final at = info.location.child('title');
      yield context.finding(
        .invalidValue,
        'The title is old.',
        at,
        fix: 'Rename it.',
        edits: [SpecEdit.replace(at, 'new')],
      );
    }
  }

  @override
  String? hint(DiagnosticCode code, Preset preset) =>
      preset == .nestjs ? 'Use @ApiTitle.' : null;
}

/// Removes `required: true` from every schema: the fix M3's
/// `bool-required-to-array` makes, without moving the name.
final class _DropBoolRequired extends NormalizerRule {
  const _DropBoolRequired();

  @override
  String get name => 'drop-bool-required';

  @override
  List<DiagnosticCode> get codes => const [.invalidValue];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      final raw = context.rawAt(schema.location)?.$1;
      if (raw is! Map<String, Object?> || raw['required'] is! bool) continue;
      final at = schema.location.child('required');
      yield context.finding(
        .invalidValue,
        'Boolean required.',
        at,
        edits: [SpecEdit.remove(at)],
      );
    }
  }
}

/// Removes `x-drop` from the root with one edit carried by the first of
/// two findings.
final class _OneEditTwoFindings extends NormalizerRule {
  const _OneEditTwoFindings();

  @override
  String get name => 'one-edit-two-findings';

  @override
  List<DiagnosticCode> get codes => const [.invalidValue];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final root = context.model.document.location;
    if (context.rawObject(root)?.containsKey('x-drop') != true) return;
    final at = root.child('x-drop');
    yield context.finding(
      .invalidValue,
      'First.',
      at,
      edits: [SpecEdit.remove(at)],
    );
    yield context.finding(.invalidValue, 'Second.', at);
  }
}

/// Reports every schema without a type: a diagnostic-only rule.
final class _Untyped extends NormalizerRule {
  const _Untyped();

  @override
  String get name => 'untyped';

  @override
  List<DiagnosticCode> get codes => const [.missingRequiredField];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      if (schema.types.isNotEmpty || schema.ref != null) continue;
      yield context.finding(
        .missingRequiredField,
        'No type.',
        schema.location,
      );
    }
  }
}

/// Sets `info.title` on every pass: it never settles.
final class _AlwaysEdits extends NormalizerRule {
  const _AlwaysEdits(this.name);

  @override
  final String name;

  @override
  List<DiagnosticCode> get codes => const [.invalidValue];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final info = context.nodes<Info>().single;
    yield context.finding(
      .invalidValue,
      'Title by $name.',
      info.location,
      edits: [
        SpecEdit.replace(info.location.child('title'), '${info.title}+'),
      ],
    );
  }
}

void main() {
  const spec = '''
openapi: 3.0.3
info: {title: old, version: "1"}
components:
  schemas:
    Pet:
      type: object
      properties:
        name: {type: string, required: true}
''';

  (NormalizedSpec, DiagnosticBag) normalize(
    String text,
    List<NormalizerRule> rules, {
    Set<String> disabled = const {},
    Preset? preset,
  }) {
    final bag = DiagnosticBag();
    final document = SpecLoader(bag).parse(text, 'api.yaml')!;
    final result = Normalizer(
      bag,
      rules: rules,
      disabled: disabled,
      preset: preset,
    ).normalize(document, .v30);
    return (result, bag);
  }

  test('a fix is applied, the model is read again and reported once', () {
    final (result, bag) = normalize(spec, [const _RenameTitle()]);
    expect(result.model.document.info?.title, 'new');
    expect(result.documents.root.root['info'], {
      'title': 'new',
      'version': '1',
    });
    expect(bag.all.map((d) => (d.code, d.pointer?.value)), [
      (DiagnosticCode.invalidValue, '#/info/title'),
      (
        DiagnosticCode.invalidValue,
        '#/components/schemas/Pet/properties/name/required',
      ),
    ]);
    expect(bag.all.first.message, 'The title is old.');
    expect(bag.all.first.line, 2);
  });

  test('parser diagnostics come from the last pass only', () {
    // The first read reports `required: true` as invalid-value; the fix
    // removes it, so the report has the fix and not the parser's complaint.
    final (_, bag) = normalize(spec, [const _DropBoolRequired()]);
    expect(bag.all.single.message, 'Boolean required.');
  });

  test('findings without edits of a rule that fixes are reported too', () {
    final (_, bag) = normalize(
      'openapi: 3.0.3\ninfo: {title: t, version: "1"}\nx-drop: 1\n',
      [const _OneEditTwoFindings()],
    );
    expect(bag.all.map((d) => d.message), ['First.', 'Second.']);
  });

  test('diagnostic-only findings are reported once, from the last pass', () {
    final (_, bag) = normalize(
      'openapi: 3.0.3\ninfo: {title: old, version: "1"}\n'
      'components: {schemas: {Any: {description: anything}}}\n',
      [const _RenameTitle(), const _Untyped()],
    );
    expect(bag.all.map((d) => d.message), ['The title is old.', 'No type.']);
  });

  test('of two overlapping fixes the earlier rule wins, with a warning', () {
    final (result, bag) = normalize(spec, [
      const _AlwaysEdits('first'),
      const _AlwaysEdits('second'),
    ]);
    expect(result.model.document.info?.title, 'old++');
    final skipped = bag.all
        .where((d) => d.code == DiagnosticCode.fixNotApplied)
        .map((d) => d.message)
        .toSet();
    expect(skipped, contains(contains('overlaps a fix of rule "first"')));
  });

  test('the normalizer stops after three passes and says so', () {
    final (result, bag) = normalize(spec, [const _AlwaysEdits('loop')]);
    expect(result.model.document.info?.title, 'old++');
    expect(Normalizer.maxPasses, 3);
    expect(
      bag.all
          .where((d) => d.code == DiagnosticCode.fixNotApplied)
          .single
          .message,
      contains('still changed after 3 passes'),
    );
  });

  test('a disabled rule does not run', () {
    final (result, bag) = normalize(
      spec,
      [const _RenameTitle()],
      disabled: {'rename-title'},
    );
    expect(result.model.document.info?.title, 'old');
    expect(bag.all.single.code, DiagnosticCode.invalidValue);
    expect(bag.all.single.pointer?.value, contains('required'));
  });

  test('a preset adds the framework hint to the fix', () {
    final (_, bag) = normalize(spec, [const _RenameTitle()], preset: .nestjs);
    expect(bag.all.first.fix, 'Rename it. Use @ApiTitle.');
  });

  test('fixes in another file are applied to that file', () {
    final dir = TempDir();
    dir.write(
      'pet.yaml',
      'Pet:\n  type: object\n  properties:\n'
          '    name: {type: string, required: true}\n',
    );
    final path = dir.write('api.yaml', r'''
openapi: 3.0.3
info: {title: t, version: "1"}
components:
  schemas:
    Pet: {$ref: "pet.yaml#/Pet"}
''');
    final bag = DiagnosticBag();
    final document = SpecLoader(bag).load(path, displayPath: 'api.yaml')!;
    final result = Normalizer(
      bag,
      rules: [const _DropBoolRequired()],
    ).normalize(document, .v30);
    final pet = result.documents[p.toUri(p.join(dir.path, 'pet.yaml'))]!;
    expect(pet.root['Pet'], {
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
      },
    });
    expect(bag.all.single.file, 'pet.yaml');
    expect(bag.all.single.line, 4);
  });
}
```

Run: `dart test test/normalize` — Expected: FAIL (there is no `normalize/`).

- [ ] **Step 3: Model and resolver**

```diff
diff --git a/packages/typed_openapi/lib/src/load/spec_document.dart b/packages/typed_openapi/lib/src/load/spec_document.dart
--- a/packages/typed_openapi/lib/src/load/spec_document.dart
+++ b/packages/typed_openapi/lib/src/load/spec_document.dart
@@ -27,6 +27,13 @@ final class SpecDocument {
 
   final Map<String, SourceSpan> _spans;
 
+  /// This document with [root] as its contents and the same positions.
+  ///
+  /// Positions stay keyed by pointer: a node an edit added has none, and a
+  /// list item an edit moved keeps the position of its old index.
+  SpecDocument withRoot(Map<String, Object?> root) =>
+      SpecDocument(file: file, uri: uri, root: root, spans: _spans);
+
   /// Whether source positions were recorded.
   bool get hasPositions => _spans.isNotEmpty;
 
diff --git a/packages/typed_openapi/lib/src/model/spec_node.dart b/packages/typed_openapi/lib/src/model/spec_node.dart
--- a/packages/typed_openapi/lib/src/model/spec_node.dart
+++ b/packages/typed_openapi/lib/src/model/spec_node.dart
@@ -15,6 +15,11 @@ final class SpecLocation implements Comparable<SpecLocation> {
   /// The pointer to the node inside [document].
   final JsonPointer pointer;
 
+  /// The location of [token] (a property name or a list index) under this
+  /// one, in the same document.
+  SpecLocation child(Object token) =>
+      SpecLocation(document, pointer.child(token));
+
   @override
   bool operator ==(Object other) =>
       other is SpecLocation &&
diff --git a/packages/typed_openapi/lib/src/resolve/spec_documents.dart b/packages/typed_openapi/lib/src/resolve/spec_documents.dart
--- a/packages/typed_openapi/lib/src/resolve/spec_documents.dart
+++ b/packages/typed_openapi/lib/src/resolve/spec_documents.dart
@@ -8,8 +8,16 @@ import '../load/spec_loader.dart';
 /// The documents of one spec: the root document and every file its `$ref`s
 /// reach, each loaded once and keyed by absolute URI.
 final class SpecDocuments {
-  /// Creates the set for [root]; other files are read with [_loader].
-  SpecDocuments(this._loader, this.root) {
+  /// Creates the set for [root]; other files are read with [_loader],
+  /// except [others], which are already loaded.
+  SpecDocuments(
+    this._loader,
+    this.root, {
+    Iterable<SpecDocument> others = const [],
+  }) {
+    for (final document in others) {
+      _documents[document.uri] = document;
+    }
     _documents[root.uri] = root;
   }
 
@@ -34,6 +42,13 @@ final class SpecDocuments {
     return _documents[uri] = document;
   }
 
+  /// Every document loaded so far, the root first.
+  Iterable<SpecDocument> get loaded => [
+    root,
+    for (final document in _documents.values)
+      if (document != null && document.uri != root.uri) document,
+  ];
+
   /// Whether a file (not a directory) is at [uri].
   ///
   /// False when [uri] does not name a file path, such as one with a
diff --git a/packages/typed_openapi/lib/src/resolve/spec_model.dart b/packages/typed_openapi/lib/src/resolve/spec_model.dart
--- a/packages/typed_openapi/lib/src/resolve/spec_model.dart
+++ b/packages/typed_openapi/lib/src/resolve/spec_model.dart
@@ -18,6 +18,11 @@ final class SpecModel {
   /// The root document.
   final OpenApiDocument document;
 
+  /// Every node read from any file, ordered by location.
+  late final List<SpecNode> nodes = List.unmodifiable(
+    _nodes.values.toList()..sort((a, b) => a.location.compareTo(b.location)),
+  );
+
   final Map<SpecLocation, SpecNode> _nodes;
   final Map<SpecLocation, SpecLocation> _targets;
 
diff --git a/packages/typed_openapi/lib/src/resolve/spec_reader.dart b/packages/typed_openapi/lib/src/resolve/spec_reader.dart
--- a/packages/typed_openapi/lib/src/resolve/spec_reader.dart
+++ b/packages/typed_openapi/lib/src/resolve/spec_reader.dart
@@ -20,13 +20,20 @@ final class SpecReader {
   final DiagnosticBag _diagnostics;
 
   /// Reads [document], which declares [version].
-  SpecModel read(SpecDocument document, OpenApiVersion version) {
+  ///
+  /// Other files come from [documents], whose root is [document]; by
+  /// default they are loaded on demand, reporting to this reader's bag.
+  SpecModel read(
+    SpecDocument document,
+    OpenApiVersion version, {
+    SpecDocuments? documents,
+  }) {
     final index = SpecIndex();
     final parsed = OpenApiParser(_diagnostics, document, index).parse(version);
     final model = RefResolver(_diagnostics).resolve(
       parsed,
       index,
-      SpecDocuments(SpecLoader(_diagnostics), document),
+      documents ?? SpecDocuments(SpecLoader(_diagnostics), document),
     );
     DialectChecker(_diagnostics).check(index.features, version);
     return model;
```

- [ ] **Step 4: Tree edits**

Create `packages/typed_openapi/lib/src/normalize/spec_edit.dart`:

```dart
import 'dart:collection';

import '../model/spec_node.dart';

/// What a [SpecEdit] does at its location.
enum EditOperation {
  /// Sets an object member, inserts a list item at an index or appends it
  /// at `-`, as JSON Patch `add` does.
  add,

  /// Replaces the value that is there.
  replace,

  /// Removes the value that is there.
  remove,
}

/// A change to the plain tree of one spec file: a rule's fix, and later an
/// override (M4).
final class SpecEdit {
  /// Sets the member, or inserts the item, at [location] to [value].
  const SpecEdit.add(this.location, this.value) : operation = .add;

  /// Replaces the value at [location] with [value].
  const SpecEdit.replace(this.location, this.value) : operation = .replace;

  /// Removes the value at [location].
  const SpecEdit.remove(this.location) : operation = .remove, value = null;

  /// The document and the pointer the edit applies to.
  final SpecLocation location;

  /// What the edit does.
  final EditOperation operation;

  /// The new plain value for [EditOperation.add] and
  /// [EditOperation.replace].
  final Object? value;

  /// Whether this edit and [other] touch the same node, or one of them a
  /// node inside the other's.
  bool overlaps(SpecEdit other) {
    if (location.document != other.location.document) return false;
    final a = location.pointer.tokens;
    final b = other.location.pointer.tokens;
    final shorter = a.length < b.length ? a : b;
    for (var i = 0; i < shorter.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Applies [SpecEdit]s to a plain tree without changing it: every object
/// and list on the way to an edit is copied once, and the copy is changed.
///
/// The tree may share nodes (a YAML alias is the same Dart object as its
/// anchor), so changing a node in place would change every place that
/// shares it.
final class TreeEditor {
  /// Creates an editor of [root].
  TreeEditor(Map<String, Object?> root) : _root = root;

  Map<String, Object?> _root;
  final Set<Object> _copies = HashSet.identity();

  /// The tree with every applied edit.
  Map<String, Object?> get root => _root;

  /// Applies [edit]; returns why it cannot be applied, or null.
  String? apply(SpecEdit edit) {
    final tokens = edit.location.pointer.tokens;
    if (tokens.isEmpty) return 'the document root cannot be edited';
    Object container = _root = _own(_root) as Map<String, Object?>;
    for (final token in tokens.take(tokens.length - 1)) {
      final child = _child(container, token);
      if (child is! Map<String, Object?> && child is! List<Object?>) {
        return 'there is no object or list at ${edit.location.pointer.value}';
      }
      final owned = _own(child!);
      _set(container, token, owned);
      container = owned;
    }
    return _change(container, tokens.last, edit);
  }

  String? _change(Object container, String token, SpecEdit edit) {
    switch ((container, edit.operation)) {
      case (final Map<String, Object?> map, .add):
        map[token] = edit.value;
      case (final Map<String, Object?> map, .replace)
          when map.containsKey(
            token,
          ):
        map[token] = edit.value;
      case (final Map<String, Object?> map, .remove)
          when map.containsKey(
            token,
          ):
        map.remove(token);
      case (final List<Object?> list, .add) when token == '-':
        list.add(edit.value);
      case (final List<Object?> list, .add):
        final index = _index(token);
        if (index == null || index > list.length) return _missing(edit);
        list.insert(index, edit.value);
      case (final List<Object?> list, .replace || .remove):
        final index = _index(token);
        if (index == null || index >= list.length) return _missing(edit);
        if (edit.operation == .replace) {
          list[index] = edit.value;
        } else {
          list.removeAt(index);
        }
      default:
        return _missing(edit);
    }
    return null;
  }

  static String _missing(SpecEdit edit) =>
      'nothing is at ${edit.location.pointer.value}';

  Object _own(Object container) {
    if (_copies.contains(container)) return container;
    final copy = container is Map<String, Object?>
        ? Map<String, Object?>.of(container)
        : List<Object?>.of(container as List<Object?>);
    _copies.add(copy);
    return copy;
  }

  static Object? _child(Object container, String token) => switch (container) {
    final Map<String, Object?> map => map[token],
    final List<Object?> list => switch (_index(token)) {
      final index? when index < list.length => list[index],
      _ => null,
    },
    _ => null,
  };

  static void _set(Object container, String token, Object value) {
    switch (container) {
      case final Map<String, Object?> map:
        map[token] = value;
      case final List<Object?> list:
        list[_index(token)!] = value;
    }
  }

  static int? _index(String token) =>
      _indexPattern.hasMatch(token) ? int.parse(token) : null;

  static final _indexPattern = RegExp(r'^(0|[1-9][0-9]{0,8})$');
}
```

- [ ] **Step 5: Rule and context**

Create `packages/typed_openapi/lib/src/normalize/normalizer_rule.dart`:

```dart
import '../config/project_config.dart';
import '../diagnostics/diagnostic.dart';
import '../diagnostics/diagnostic_code.dart';
import '../load/openapi_version.dart';
import '../model/spec_node.dart';
import '../resolve/spec_documents.dart';
import '../resolve/spec_model.dart';
import 'spec_edit.dart';

/// What a rule found: a diagnostic, and for a fix the edits that make it.
final class Finding {
  /// Creates a finding.
  const Finding(this.diagnostic, {this.edits = const []});

  /// What is wrong and how to fix it at the source.
  final Diagnostic diagnostic;

  /// The edits that fix it; empty for a diagnostic-only finding.
  final List<SpecEdit> edits;
}

/// What a rule reads: the model of one pass and the files it came from.
final class RuleContext {
  /// Creates a context for [model], read from [documents] as [version].
  RuleContext(this.model, this.documents, this.version);

  /// The spec as the parser read it in this pass.
  final SpecModel model;

  /// The files of the spec, with their plain trees and positions.
  final SpecDocuments documents;

  /// The version the root document declares.
  final OpenApiVersion version;

  /// Every node of type [T], ordered by location.
  Iterable<T> nodes<T extends SpecNode>() => model.nodes.whereType<T>();

  /// The raw value at [location] as a one-element record, or null when
  /// nothing is there.
  (Object?,)? rawAt(SpecLocation location) =>
      documents[location.document]?.valueAt(location.pointer);

  /// The raw value at [location] when it is an object, else null.
  Map<String, Object?>? rawObject(SpecLocation location) =>
      switch (rawAt(location)) {
        (final Map<String, Object?> raw,) => raw,
        _ => null,
      };

  /// A finding of [code] at [at], with [edits] when it is a fix.
  Finding finding(
    DiagnosticCode code,
    String message,
    SpecLocation at, {
    String? fix,
    List<SpecEdit> edits = const [],
  }) => Finding(
    Diagnostic(
      code: code,
      severity: code.defaultSeverity,
      message: message,
      file: documents.displayPath(at.document),
      pointer: at.pointer,
      span: documents[at.document]?.spanOf(at.pointer),
      fix: fix,
    ),
    edits: edits,
  );
}

/// A named check of the spec model: it finds a defect and either fixes it
/// with [SpecEdit]s, when the fix follows from the spec or the protocol, or
/// describes it.
///
/// Rules never change the model; the normalizer applies their edits to the
/// plain trees and reads the model again.
abstract base class NormalizerRule {
  /// Creates a rule.
  const NormalizerRule();

  /// The name used in the config, such as `bool-required-to-array`.
  String get name;

  /// The codes the rule reports.
  List<DiagnosticCode> get codes;

  /// The findings in [context], in a stable order.
  Iterable<Finding> check(RuleContext context);

  /// How to fix a [code] finding in the code of a [preset] framework, or
  /// null when there is no specific recipe.
  String? hint(DiagnosticCode code, Preset preset) => null;
}
```

- [ ] **Step 6: Normalizer**

Create `packages/typed_openapi/lib/src/normalize/normalizer.dart`:

```dart
import '../config/project_config.dart';
import '../diagnostics/diagnostic.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../load/openapi_version.dart';
import '../load/spec_document.dart';
import '../load/spec_loader.dart';
import '../resolve/spec_documents.dart';
import '../resolve/spec_model.dart';
import '../resolve/spec_reader.dart';
import 'normalizer_rule.dart';
import 'spec_edit.dart';

/// The result of normalizing a spec.
final class NormalizedSpec {
  /// Creates a result.
  const NormalizedSpec(this.model, this.documents);

  /// The model of the last pass.
  final SpecModel model;

  /// The files of the last pass, with every fix applied.
  final SpecDocuments documents;
}

/// Reads a spec into the model, runs the rules over it, applies their fixes
/// to the plain trees and reads it again, until no rule has a fix or
/// [maxPasses] passes have run.
///
/// The report holds what the parser and resolver say about the last pass,
/// every finding of a rule that fixed something in a pass, and the findings
/// of the last pass's rules.
/// Problems go to the [DiagnosticBag] given to the constructor; files are
/// loaded once, with their loading problems reported there too.
final class Normalizer {
  /// Creates a normalizer that reports to [_diagnostics] and runs [rules]
  /// (by default every rule) in order, except the [disabled] names; a
  /// [preset] adds framework hints to the findings.
  Normalizer(
    this._diagnostics, {
    List<NormalizerRule>? rules,
    Set<String> disabled = const {},
    this.preset,
  }) : _rules = [
         for (final rule in rules ?? Normalizer.rules)
           if (!disabled.contains(rule.name)) rule,
       ];

  /// How many times the model is read at most.
  static const maxPasses = 3;

  /// Every rule, in the order it runs; an earlier rule's fix wins a
  /// conflict.
  static final List<NormalizerRule> rules = List.unmodifiable(
    <NormalizerRule>[],
  );

  /// The names of [rules].
  static Set<String> get ruleNames => {for (final rule in rules) rule.name};

  final DiagnosticBag _diagnostics;
  final List<NormalizerRule> _rules;

  /// The framework whose hints the findings carry.
  final Preset? preset;

  /// Normalizes [document], which declares [version].
  NormalizedSpec normalize(SpecDocument document, OpenApiVersion version) {
    final loader = SpecLoader(_diagnostics);
    var root = document;
    var others = const <SpecDocument>[];
    for (var pass = 1; ; pass++) {
      final scratch = DiagnosticBag();
      final documents = SpecDocuments(loader, root, others: others);
      final model = SpecReader(scratch).read(
        root,
        version,
        documents: documents,
      );
      final context = RuleContext(model, documents, version);
      final found = [
        for (final rule in _rules)
          for (final finding in rule.check(context)) (rule, finding),
      ];
      final hasEdits = found.any((f) => f.$2.edits.isNotEmpty);
      if (!hasEdits || pass == maxPasses) {
        scratch.all.forEach(_diagnostics.add);
        for (final (rule, finding) in found) {
          _report(rule, finding);
          for (final edit in finding.edits) {
            _notApplied(
              documents,
              rule,
              edit,
              'the spec still changed after $maxPasses passes',
            );
          }
        }
        return NormalizedSpec(model, documents);
      }
      // Every finding of a rule that fixes something in this pass is part of
      // that fix (a rule may put one edit on the first of several
      // findings); the other rules' findings come again in the last pass.
      final fixing = {
        for (final (rule, finding) in found)
          if (finding.edits.isNotEmpty) rule,
      };
      for (final (rule, finding) in found) {
        if (fixing.contains(rule)) _report(rule, finding);
      }
      final edited = _apply(documents, found);
      root = edited[root.uri] ?? root;
      others = [
        for (final loaded in documents.loaded)
          if (loaded.uri != root.uri) edited[loaded.uri] ?? loaded,
      ];
    }
  }

  /// Applies the edits of [found] in order, skipping any that overlaps an
  /// earlier one; returns the edited documents by URI.
  Map<Uri, SpecDocument> _apply(
    SpecDocuments documents,
    List<(NormalizerRule, Finding)> found,
  ) {
    final accepted = <(NormalizerRule, SpecEdit)>[];
    final editors = <Uri, TreeEditor>{};
    for (final (rule, finding) in found) {
      for (final edit in finding.edits) {
        final earlier = accepted.where((a) => a.$2.overlaps(edit)).firstOrNull;
        if (earlier != null) {
          _notApplied(
            documents,
            rule,
            edit,
            'it overlaps a fix of rule "${earlier.$1.name}"',
          );
          continue;
        }
        final uri = edit.location.document;
        final document = documents[uri];
        if (document == null) {
          _notApplied(documents, rule, edit, 'its file cannot be read');
          continue;
        }
        final editor = editors[uri] ??= TreeEditor(document.root);
        final problem = editor.apply(edit);
        if (problem != null) {
          _notApplied(documents, rule, edit, problem);
          continue;
        }
        accepted.add((rule, edit));
      }
    }
    return {
      for (final MapEntry(key: uri, value: editor) in editors.entries)
        uri: documents[uri]!.withRoot(editor.root),
    };
  }

  void _report(NormalizerRule rule, Finding finding) {
    final d = finding.diagnostic;
    final hint = switch (preset) {
      final preset? => rule.hint(d.code, preset),
      null => null,
    };
    _diagnostics.add(
      hint == null
          ? d
          : Diagnostic(
              code: d.code,
              severity: d.severity,
              message: d.message,
              file: d.file,
              pointer: d.pointer,
              span: d.span,
              fix: d.fix == null ? hint : '${d.fix} $hint',
            ),
    );
  }

  void _notApplied(
    SpecDocuments documents,
    NormalizerRule rule,
    SpecEdit edit,
    String reason,
  ) {
    final uri = edit.location.document;
    final pointer = edit.location.pointer;
    _diagnostics.report(
      .fixNotApplied,
      'A fix of rule "${rule.name}" was not applied: $reason.',
      file: documents.displayPath(uri),
      pointer: pointer,
      span: documents[uri]?.spanOf(pointer),
    );
  }
}
```

- [ ] **Step 7: Check**

```bash
dart analyze packages                                  # from the root: No issues found!
dart test                                              # from packages/typed_openapi
dart format lib test bin && dart format lib test bin   # second run: 0 changed
```

Expected: 278 tests.

- [ ] **Step 8: Commit**

```bash
git add packages/typed_openapi
git commit -m "feat(typed_openapi): add the normalizer rule engine

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Schema fixes: `bool-required-to-array` (TOA201), `drop-invalid-default` (TOA211)

**Files:**
- Create: `packages/typed_openapi/lib/src/normalize/rules/bool_required_to_array.dart`, `packages/typed_openapi/lib/src/normalize/rules/drop_invalid_default.dart`, `packages/typed_openapi/test/normalize/schema_fix_rules_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_openapi/lib/src/model/schema.dart`, `packages/typed_openapi/lib/src/normalize/normalizer.dart`

**Interfaces:**
- Consumes: `NormalizerRule`, `RuleContext`, `SpecEdit`, `Normalizer` (task 4); `SchemaObject`, `ObjectReader.describe` (M2).
- Produces: `BoolRequiredToArray`, `DropInvalidDefault`; `SchemaType.accepts(Object? value)`; codes `boolRequired` (TOA201), `invalidDefault` (TOA211).

Behaviour: `required: true` on a property → the name is appended to the object's `required` (after the existing ones, without repeats; the list is created if absent), and the flag is removed; `required: false` is removed; an object property with `required: true` children gets the list of their names in one edit. `required: true` outside a property — TOA203 (task 7). A `default` of the wrong type is removed (`null` is allowed with `nullable: true`; `integer` accepts `3.0`); `nestjs` — recipe `excludeDynamicDefaults` (research/06 §D.1, item 2).

- [ ] **Step 1: Codes**

Before the line `/// A normalizer fix was not applied: it overlaps an earlier rule's fix,`:

```dart
  /// A property schema says `required: true` or `false` (OpenAPI 2 style);
  /// the name is moved into the object's `required` list.
  boolRequired('TOA201', 'bool-required', .warning),

  /// A schema's `default` is not of the schema's type; it is ignored.
  invalidDefault('TOA211', 'invalid-default', .warning),
```

- [ ] **Step 2: A test that fails**

Create `packages/typed_openapi/test/normalize/schema_fix_rules_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/config/project_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/model/schema.dart';
import 'package:typed_openapi/src/normalize/normalizer.dart';
import 'package:typed_openapi/src/normalize/rules/bool_required_to_array.dart';
import 'package:typed_openapi/src/normalize/rules/drop_invalid_default.dart';

void main() {
  /// Normalizes the 3.0 document whose `components.schemas` are [schemas]
  /// with every rule.
  (NormalizedSpec, DiagnosticBag) normalize(String schemas, {Preset? preset}) {
    final bag = DiagnosticBag();
    final document = SpecLoader(bag).parse(
      'openapi: 3.0.3\ninfo: {title: Shop, version: "1"}\n'
          'components:\n  schemas:\n$schemas',
      'api.yaml',
    )!;
    final result = Normalizer(bag, preset: preset).normalize(document, .v30);
    return (result, bag);
  }

  Map<String, Object?> schemaIn(NormalizedSpec result, String name) =>
      ((result.documents.root.root['components']! as Map)['schemas']!
              as Map)[name]!
          as Map<String, Object?>;

  test('the fix rules are registered once, in this order', () {
    expect(
      Normalizer.rules.map((r) => r.name),
      containsAllInOrder(['bool-required-to-array', 'drop-invalid-default']),
    );
    expect(Normalizer.ruleNames, hasLength(Normalizer.rules.length));
    expect(const BoolRequiredToArray().codes, [DiagnosticCode.boolRequired]);
    expect(const DropInvalidDefault().codes, [DiagnosticCode.invalidDefault]);
  });

  group('bool-required-to-array', () {
    test('required: true moves the name into the object\'s list', () {
      final (result, bag) = normalize('''
    Order:
      type: object
      required: [id]
      properties:
        id: {type: string}
        note: {type: string, required: true}
        total: {type: number, required: true}
        coupon: {type: string, required: false}
''');
      expect(schemaIn(result, 'Order'), {
        'type': 'object',
        'required': ['id', 'note', 'total'],
        'properties': {
          'id': {'type': 'string'},
          'note': {'type': 'string'},
          'total': {'type': 'number'},
          'coupon': {'type': 'string'},
        },
      });
      final order =
          result.model.document.components!.schemas['Order']! as SchemaObject;
      expect(order.required, ['id', 'note', 'total']);
      expect(bag.all.map((d) => (d.code, d.pointer?.value)), [
        (
          DiagnosticCode.boolRequired,
          '#/components/schemas/Order/properties/note/required',
        ),
        (
          DiagnosticCode.boolRequired,
          '#/components/schemas/Order/properties/total/required',
        ),
        (
          DiagnosticCode.boolRequired,
          '#/components/schemas/Order/properties/coupon/required',
        ),
      ]);
      expect(bag.all.first.severity, Severity.warning);
      expect(bag.all.first.line, 10);
    });

    test('an object without a list gets one', () {
      final (result, bag) = normalize('''
    Tag:
      type: object
      properties:
        name: {type: string, required: true}
''');
      expect(schemaIn(result, 'Tag')['required'], ['name']);
      expect(bag.all.single.message, contains('"name"'));
    });

    test('a required property that has required properties itself', () {
      final (result, bag) = normalize('''
    Order:
      type: object
      properties:
        address:
          type: object
          required: true
          properties:
            city: {type: string, required: true}
''');
      expect(schemaIn(result, 'Order')['required'], ['address']);
      final address =
          (schemaIn(result, 'Order')['properties']! as Map)['address']! as Map;
      expect(address['required'], ['city']);
      expect(bag.all.map((d) => d.code), [
        DiagnosticCode.boolRequired,
        DiagnosticCode.boolRequired,
      ]);
      expect(
        bag.all.where((d) => d.code == DiagnosticCode.invalidValue),
        isEmpty,
      );
    });

    test('a valid required list is left alone', () {
      final (_, bag) = normalize('''
    Tag:
      type: object
      required: [name]
      properties:
        name: {type: string}
''');
      expect(bag.all, isEmpty);
    });
  });

  group('drop-invalid-default', () {
    test('a default of another type is removed', () {
      final (result, bag) = normalize('''
    Filter:
      type: object
      properties:
        tags: {type: array, items: {type: string}, default: ""}
        limit: {type: integer, default: 2.5}
        page: {type: integer, default: 1}
        sort: {type: string, nullable: true, default: null}
''');
      final properties = schemaIn(result, 'Filter')['properties']! as Map;
      expect(properties['tags'], {
        'type': 'array',
        'items': {'type': 'string'},
      });
      expect((properties['limit']! as Map).containsKey('default'), isFalse);
      expect((properties['page']! as Map)['default'], 1);
      expect((properties['sort']! as Map)['default'], isNull);
      expect(bag.sorted.map((d) => d.pointer?.value), [
        '#/components/schemas/Filter/properties/tags/default',
        '#/components/schemas/Filter/properties/limit/default',
      ]);
      expect(
        bag.sorted.first.message,
        'The default, a string, is not of type array; it is ignored.',
      );
    });

    test('nestjs gets a hint about dynamic defaults', () {
      final (_, bag) = normalize(
        '    When: {type: string, format: date-time, default: 0}\n',
        preset: .nestjs,
      );
      expect(bag.all.single.fix, contains('excludeDynamicDefaults'));
    });
  });
}
```

Run: `dart test test/normalize/schema_fix_rules_test.dart` — Expected: FAIL.

- [ ] **Step 3: `SchemaType.accepts`**

```diff
diff --git a/packages/typed_openapi/lib/src/model/schema.dart b/packages/typed_openapi/lib/src/model/schema.dart
--- a/packages/typed_openapi/lib/src/model/schema.dart
+++ b/packages/typed_openapi/lib/src/model/schema.dart
@@ -56,6 +56,18 @@ enum SchemaType {
   static final Map<String, SchemaType> byWire = Map.unmodifiable({
     for (final type in values) type.wire: type,
   });
+
+  /// Whether the plain JSON [value] is of this type; `integer` accepts a
+  /// whole number written as `3.0`.
+  bool accepts(Object? value) => switch (this) {
+    .string => value is String,
+    .number => value is num,
+    .integer => value is num && value.isFinite && value == value.truncate(),
+    .boolean => value is bool,
+    .array => value is List<Object?>,
+    .object => value is Map<String, Object?>,
+    .nullType => value == null,
+  };
 }
 
 /// A Schema Object.
```

- [ ] **Step 4: Rules**

Create `packages/typed_openapi/lib/src/normalize/rules/bool_required_to_array.dart`:

```dart
import '../../diagnostics/diagnostic_code.dart';
import '../../model/schema.dart';
import '../../model/spec_node.dart';
import '../normalizer_rule.dart';
import '../spec_edit.dart';

/// `required: true` on a property schema (OpenAPI 2 style, C-1, C-49)
/// moves the property's name into the `required` list of the object schema;
/// `required: false` is removed.
///
/// The fix is unambiguous: OpenAPI 3 has exactly one way to say a property
/// is required.
final class BoolRequiredToArray extends NormalizerRule {
  /// Creates the rule.
  const BoolRequiredToArray();

  @override
  String get name => 'bool-required-to-array';

  @override
  List<DiagnosticCode> get codes => const [.boolRequired];

  @override
  Iterable<Finding> check(RuleContext context) {
    final flags = <(SchemaObject, String, SchemaObject, bool)>[];
    final added = <SpecLocation, List<String>>{};
    for (final schema in context.nodes<SchemaObject>()) {
      for (final MapEntry(key: name, value: property)
          in schema.properties.entries) {
        if (property is! SchemaObject) continue;
        final flag = _flagOf(context, property);
        if (flag == null) continue;
        flags.add((schema, name, property, flag));
        if (flag) (added[schema.location] ??= []).add(name);
      }
    }
    final findings = <Finding>[];
    final listed = <SpecLocation>{};
    for (final (schema, name, property, flag) in flags) {
      final at = property.location.child('required');
      findings.add(
        context.finding(
          .boolRequired,
          flag
              ? 'Property "$name" says "required: true", the OpenAPI 2 way; '
                    'OpenAPI 3 lists required properties in the "required" '
                    'array of the object, so the name is moved there.'
              : 'Property "$name" says "required: false", the OpenAPI 2 way; '
                    'a property missing from "required" is optional, so the '
                    'flag is removed.',
          at,
          fix: flag
              ? 'Add "$name" to "required" of the object schema and remove '
                    '"required" from the property.'
              : 'Remove "required: false" from the property.',
          edits: [
            // A property that is also an object with required properties
            // gets its "required" replaced by that list below instead.
            if (!added.containsKey(property.location)) SpecEdit.remove(at),
            if (flag && listed.add(schema.location))
              _listEdit(context, schema, added[schema.location]!),
          ],
        ),
      );
    }
    return findings;
  }

  /// `required` of [property] when it is a boolean.
  static bool? _flagOf(RuleContext context, SchemaObject property) =>
      switch (context.rawAt(property.location)) {
        (final Map<String, Object?> raw,) => switch (raw['required']) {
          final bool flag => flag,
          _ => null,
        },
        _ => null,
      };

  /// The edit that makes `required` of [schema] list [names] after the
  /// names it already lists.
  static SpecEdit _listEdit(
    RuleContext context,
    SchemaObject schema,
    List<String> names,
  ) {
    final at = schema.location.child('required');
    final existing = switch (context.rawAt(at)) {
      (final List<Object?> list,) => list,
      _ => const <Object?>[],
    };
    final list = [
      ...existing,
      for (final name in names)
        if (!existing.contains(name)) name,
    ];
    return switch (context.rawAt(at)) {
      null => SpecEdit.add(at, list),
      _ => SpecEdit.replace(at, list),
    };
  }
}
```

Create `packages/typed_openapi/lib/src/normalize/rules/drop_invalid_default.dart`:

```dart
import '../../config/project_config.dart';
import '../../diagnostics/diagnostic_code.dart';
import '../../model/schema.dart';
import '../../parse/object_reader.dart';
import '../normalizer_rule.dart';
import '../spec_edit.dart';

/// A `default` whose JSON type is none of the schema's `type`s (C-28) is
/// ignored, as the parser ignores any value of the wrong type.
final class DropInvalidDefault extends NormalizerRule {
  /// Creates the rule.
  const DropInvalidDefault();

  @override
  String get name => 'drop-invalid-default';

  @override
  List<DiagnosticCode> get codes => const [.invalidDefault];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      final value = schema.defaultValue;
      if (value == null || schema.types.isEmpty) continue;
      final (raw,) = value;
      if (raw == null && schema.nullable == true) continue;
      if (schema.types.any((type) => type.accepts(raw))) continue;
      final types = schema.types.map((t) => t.wire).join(' or ');
      final at = schema.location.child('default');
      yield context.finding(
        .invalidDefault,
        'The default, ${ObjectReader.describe(raw)}, is not of type $types; '
        'it is ignored.',
        at,
        fix: 'Change the default to a value of type $types, or remove it.',
        edits: [SpecEdit.remove(at)],
      );
    }
  }

  @override
  String? hint(DiagnosticCode code, Preset preset) => switch (preset) {
    .nestjs =>
      'In NestJS, check `default` in @ApiProperty; '
          '`excludeDynamicDefaults: true` in SwaggerModule.createDocument '
          'leaves out defaults computed at runtime.',
    _ => null,
  };
}
```

- [ ] **Step 5: Register**

In `lib/src/normalize/normalizer.dart` the rule imports between `import 'normalizer_rule.dart';` and `import 'spec_edit.dart';` must be as follows (sorted):

```dart
import 'rules/bool_required_to_array.dart';
import 'rules/drop_invalid_default.dart';
```

and the `rules` list as follows:

```dart
  static final List<NormalizerRule> rules = List.unmodifiable(
    <NormalizerRule>[
      const BoolRequiredToArray(),
      const DropInvalidDefault(),
    ],
  );
```

- [ ] **Step 6: Check**

```bash
dart analyze packages                                  # from the root: No issues found!
dart test                                              # from packages/typed_openapi
dart format lib test bin && dart format lib test bin   # second run: 0 changed
```

Expected: 285 tests.

- [ ] **Step 7: Commit**

```bash
git add packages/typed_openapi
git commit -m "feat(typed_openapi): fix boolean required and defaults of the wrong type

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Config `rules` and `check` through the normalizer

**Files:**
- Modify: `packages/typed_openapi/lib/src/config/config_loader.dart`, `packages/typed_openapi/lib/src/config/project_config.dart`, `packages/typed_openapi/lib/src/check/spec_checker.dart`, `packages/typed_openapi/test/config/config_loader_test.dart`, `packages/typed_openapi/test/check/spec_checker_test.dart`

**Interfaces:**
- Consumes: `Normalizer`, `Normalizer.ruleNames` (tasks 4–5).
- Produces: `ClientConfig.disabledRules`; the `rules` key in `defaults` and in a client (a client overrides `defaults` name by name; an unknown name — TOA903, a non-boolean value — TOA902); `SpecChecker.check` normalizes each spec with the client's rules and preset — one run for each different pair (preset, disabled rules) for a shared file; an identical diagnostic from the runs is reported once.

- [ ] **Step 1: Tests** — apply first the test parts of the diffs of steps 2–3; `dart test test/config test/check` — Expected: FAIL (`rules` is an unknown key, `check` does not give TOA201).

- [ ] **Step 2: `ConfigLoader` and tests**

```diff
diff --git a/packages/typed_openapi/lib/src/config/config_loader.dart b/packages/typed_openapi/lib/src/config/config_loader.dart
--- a/packages/typed_openapi/lib/src/config/config_loader.dart
+++ b/packages/typed_openapi/lib/src/config/config_loader.dart
@@ -6,6 +6,7 @@ import 'package:source_span/source_span.dart';
 import '../diagnostics/diagnostic_bag.dart';
 import '../diagnostics/json_pointer.dart';
 import '../load/yaml_composer.dart';
+import '../normalize/normalizer.dart';
 import 'project_config.dart';
 
 /// Reads `typed_openapi.yaml` into a [ProjectConfig].
@@ -17,7 +18,7 @@ final class ConfigLoader {
   const ConfigLoader(this._diagnostics);
 
   static const _topLevelKeys = {'defaults', 'clients'};
-  static const _defaultsKeys = {'preset', 'line_width'};
+  static const _defaultsKeys = {'preset', 'line_width', 'rules'};
   static const _clientKeys = {
     'input',
     'output',
@@ -25,6 +26,7 @@ final class ConfigLoader {
     'overrides',
     'baseline',
     'line_width',
+    'rules',
   };
 
   final DiagnosticBag _diagnostics;
@@ -79,10 +81,12 @@ final class ConfigLoader {
     final defaults = reader.mapAt(root, 'defaults', .root);
     Preset? defaultPreset;
     int? defaultWidth;
+    var defaultRules = const <String, bool>{};
     if (defaults != null) {
       reader.checkKeys(defaults, _defaultsKeys, defaultsPointer);
       defaultPreset = reader.presetAt(defaults, defaultsPointer);
       defaultWidth = reader.intAt(defaults, 'line_width', defaultsPointer);
+      defaultRules = reader.rulesAt(defaults, defaultsPointer);
     }
 
     final clientsPointer = JsonPointer.root.child('clients');
@@ -116,6 +120,7 @@ final class ConfigLoader {
           ClientConfig.defaultLineWidth;
       final overrides = reader.stringAt(value, 'overrides', pointer);
       final baseline = reader.stringAt(value, 'baseline', pointer);
+      final rules = {...defaultRules, ...reader.rulesAt(value, pointer)};
       if (input == null || output == null) continue;
       outputSpans[name] = reader.spanAt(pointer.child('output'));
       clients.add(
@@ -127,6 +132,10 @@ final class ConfigLoader {
           preset: preset,
           overrides: overrides == null ? null : resolve(overrides),
           baseline: baseline == null ? null : resolve(baseline),
+          disabledRules: {
+            for (final MapEntry(:key, :value) in rules.entries)
+              if (!value) key,
+          },
         ),
       );
     }
@@ -268,6 +277,38 @@ class _ConfigReader {
     return null;
   }
 
+  /// `rules` of [parent]: normalizer rule names mapped to whether they run.
+  /// Unknown names are reported and skipped.
+  Map<String, bool> rulesAt(Map<String, Object?> parent, JsonPointer at) {
+    final rules = mapAt(parent, 'rules', at);
+    if (rules == null) return const {};
+    final pointer = at.child('rules');
+    final known = Normalizer.ruleNames;
+    final result = <String, bool>{};
+    for (final MapEntry(key: name, :value) in rules.entries) {
+      if (!known.contains(name)) {
+        diagnostics.report(
+          .configUnknownKey,
+          'Unknown normalizer rule "$name".',
+          file: file,
+          pointer: pointer.child(name),
+          span: spanAt(pointer.child(name)),
+          fix: 'Known rules: ${(known.toList()..sort()).join(', ')}.',
+        );
+        continue;
+      }
+      if (value is! bool) {
+        invalid(
+          'Rule "$name" must be true or false.',
+          pointer.child(name),
+        );
+        continue;
+      }
+      result[name] = value;
+    }
+    return result;
+  }
+
   Preset? presetAt(Map<String, Object?> parent, JsonPointer at) {
     final name = stringAt(parent, 'preset', at);
     if (name == null) return null;
diff --git a/packages/typed_openapi/test/config/config_loader_test.dart b/packages/typed_openapi/test/config/config_loader_test.dart
--- a/packages/typed_openapi/test/config/config_loader_test.dart
+++ b/packages/typed_openapi/test/config/config_loader_test.dart
@@ -114,6 +114,45 @@ clients:
     expect(bag.all.single.span, isNotNull);
   });
 
+  test('reads rules from defaults and clients; a client overrides', () {
+    final path = TempDir().write('c.yaml', '''
+defaults:
+  rules: {bool-required-to-array: false, drop-invalid-default: false}
+clients:
+  a: {input: a.json, output: lib/a}
+  b:
+    input: b.json
+    output: lib/b
+    rules: {drop-invalid-default: true}
+''');
+    final bag = DiagnosticBag();
+    final clients = ConfigLoader(bag).load(path)!.clients;
+    expect(bag.all, isEmpty);
+    expect(clients.first.disabledRules, {
+      'bool-required-to-array',
+      'drop-invalid-default',
+    });
+    expect(clients.last.disabledRules, {'bool-required-to-array'});
+  });
+
+  test('an unknown rule name is a warning; a value that is not a boolean '
+      'is an error', () {
+    final path = TempDir().write('c.yaml', '''
+clients:
+  a:
+    input: a.json
+    output: lib/a
+    rules: {bool-required: false, drop-invalid-default: off}
+''');
+    final bag = DiagnosticBag();
+    expect(ConfigLoader(bag).load(path)!.clients.single.disabledRules, isEmpty);
+    expect(bag.all.map((d) => (d.code, d.pointer?.value)), [
+      (DiagnosticCode.configUnknownKey, '#/clients/a/rules/bool-required'),
+      (DiagnosticCode.configInvalid, '#/clients/a/rules/drop-invalid-default'),
+    ]);
+    expect(bag.all.first.fix, contains('bool-required-to-array'));
+  });
+
   test('accepts an alias in a value', () {
     final path = TempDir().write('typed_openapi.yaml', '''
 clients:
```

- [ ] **Step 3: `ClientConfig`, `SpecChecker` and test**

```diff
diff --git a/packages/typed_openapi/lib/src/check/spec_checker.dart b/packages/typed_openapi/lib/src/check/spec_checker.dart
--- a/packages/typed_openapi/lib/src/check/spec_checker.dart
+++ b/packages/typed_openapi/lib/src/check/spec_checker.dart
@@ -4,7 +4,7 @@ import '../config/project_config.dart';
 import '../diagnostics/diagnostic_bag.dart';
 import '../load/openapi_version.dart';
 import '../load/spec_loader.dart';
-import '../resolve/spec_reader.dart';
+import '../normalize/normalizer.dart';
 
 /// Loads every client's spec and reports what is wrong with it.
 ///
@@ -19,19 +19,24 @@ final class SpecChecker {
   /// Checks the spec of every client in [config].
   ///
   /// Each spec is loaded, its OpenAPI version detected, and then it is read
-  /// into the model with its `$ref`s resolved. [only] limits the run to
+  /// into the model with its `$ref`s resolved and normalized with the
+  /// client's rules and preset. [only] limits the run to
   /// clients with these names; empty means all. A file shared by several
-  /// clients is checked once. Spec paths in diagnostics are relative to the
-  /// config file's directory.
+  /// clients is checked once per distinct preset and set of disabled rules;
+  /// the bag reports a diagnostic the runs share once. Spec paths in
+  /// diagnostics are relative to the config file's directory.
   void check(ProjectConfig config, {Set<String> only = const {}}) {
     final loader = SpecLoader(_diagnostics);
     final detector = OpenApiVersionDetector(_diagnostics);
-    final reader = SpecReader(_diagnostics);
     final configDir = p.dirname(p.absolute(config.file));
-    final checked = <String>{};
+    // A run is a file with a preset and a set of disabled rules.
+    final checked = <(String, Preset?, String)>{};
     for (final client in config.clients) {
       if (only.isNotEmpty && !only.contains(client.name)) continue;
-      if (!checked.add(p.absolute(client.input))) continue;
+      final rules = (client.disabledRules.toList()..sort()).join(',');
+      if (!checked.add((p.absolute(client.input), client.preset, rules))) {
+        continue;
+      }
       final document = loader.load(
         client.input,
         displayPath: p.relative(client.input, from: configDir),
@@ -39,7 +44,11 @@ final class SpecChecker {
       if (document == null) continue;
       final version = detector.detect(document);
       if (version == null) continue;
-      reader.read(document, version);
+      Normalizer(
+        _diagnostics,
+        disabled: client.disabledRules,
+        preset: client.preset,
+      ).normalize(document, version);
     }
   }
 }
diff --git a/packages/typed_openapi/lib/src/config/project_config.dart b/packages/typed_openapi/lib/src/config/project_config.dart
--- a/packages/typed_openapi/lib/src/config/project_config.dart
+++ b/packages/typed_openapi/lib/src/config/project_config.dart
@@ -27,6 +27,7 @@ final class ClientConfig {
     this.preset,
     this.overrides,
     this.baseline,
+    this.disabledRules = const {},
   });
 
   /// Line width of generated code when the config does not set one.
@@ -52,6 +53,9 @@ final class ClientConfig {
 
   /// Absolute path of the baseline file.
   final String? baseline;
+
+  /// Normalizer rules the config turns off for this client, by name.
+  final Set<String> disabledRules;
 }
 
 /// The parsed `typed_openapi.yaml`.
diff --git a/packages/typed_openapi/test/check/spec_checker_test.dart b/packages/typed_openapi/test/check/spec_checker_test.dart
--- a/packages/typed_openapi/test/check/spec_checker_test.dart
+++ b/packages/typed_openapi/test/check/spec_checker_test.dart
@@ -32,6 +32,36 @@ clients:
     );
   });
 
+  test('normalizes each spec with the client\'s rules', () {
+    final dir = TempDir();
+    const spec = '''
+openapi: 3.0.3
+info: {title: t, version: "1"}
+components:
+  schemas:
+    Tag:
+      type: object
+      properties:
+        name: {type: string, required: true}
+''';
+    dir.write('a.yaml', spec);
+    dir.write('b.yaml', spec);
+    final path = dir.write('typed_openapi.yaml', '''
+clients:
+  a: {input: a.yaml, output: lib/a}
+  b:
+    input: b.yaml
+    output: lib/b
+    rules: {bool-required-to-array: false}
+''');
+    final bag = DiagnosticBag();
+    SpecChecker(bag).check(ConfigLoader(bag).load(path)!);
+    expect(bag.all.map((d) => (d.code, d.file)), [
+      (DiagnosticCode.boolRequired, 'a.yaml'),
+      (DiagnosticCode.invalidValue, 'b.yaml'),
+    ]);
+  });
+
   test('only checks the named clients', () {
     final dir = TempDir();
     final path = dir.write('typed_openapi.yaml', '''
@@ -59,6 +89,36 @@ clients:
     expect(bag.all.single.code, DiagnosticCode.unsupportedOpenApiVersion);
   });
 
+  test('a shared spec is checked once per preset and rule set', () {
+    final dir = TempDir();
+    dir.write('shared.yaml', '''
+openapi: 3.0.3
+info: {title: t, version: "1"}
+components:
+  schemas:
+    Tag:
+      type: object
+      properties:
+        name: {type: string, required: true}
+''');
+    final path = dir.write('typed_openapi.yaml', '''
+clients:
+  a: {input: shared.yaml, output: lib/a}
+  b:
+    input: shared.yaml
+    output: lib/b
+    rules: {bool-required-to-array: false}
+  c: {input: shared.yaml, output: lib/c}
+''');
+    final bag = DiagnosticBag();
+    SpecChecker(bag).check(ConfigLoader(bag).load(path)!);
+    // a and c share one run (TOA201); b runs without the fix (TOA111).
+    expect(bag.all.map((d) => d.code), [
+      DiagnosticCode.boolRequired,
+      DiagnosticCode.invalidValue,
+    ]);
+  });
+
   test('reads each spec into the model and follows its references', () {
     final dir = TempDir();
     dir.write('specs/api.yaml', r'''
@@ -67,6 +127,7 @@ info: {title: api}
 paths:
   /pets:
     get:
+      operationId: listPets
       responses:
         "200": {$ref: "common.yaml#/components/responses/Missing"}
 ''');
```

(`operationId: listPets` in the `SpecChecker` test fixture — so that the `missing-operation-id` rule of task 10 does not change the expected list.)

- [ ] **Step 4: Check**

```bash
dart analyze packages                                  # from the root: No issues found!
dart test                                              # from packages/typed_openapi
dart format lib test bin && dart format lib test bin   # second run: 0 changed
```

Expected: 289 tests.

- [ ] **Step 5: Commit**

```bash
git add packages/typed_openapi
git commit -m "feat(typed_openapi): run the normalizer in check, with rules toggled in the config

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Schema shape: arrays, files, combinators, examples (TOA202–TOA208, diagnostic only)

**Files:**
- Create: `packages/typed_openapi/lib/src/normalize/rules/schema_shape_rules.dart`, `packages/typed_openapi/test/helpers/normalizer_fixture.dart`, `packages/typed_openapi/test/normalize/schema_shape_rules_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_openapi/lib/src/normalize/normalizer.dart`

**Interfaces:**
- Consumes: `NormalizerRule`, `RuleContext.rawObject`, `SchemaType.accepts`, `SpecModel.resolveSchema`.
- Produces: `ArrayWithoutItems`, `DoubleArray`, `FormatOnArray`, `BinaryObject`, `ContradictoryObjectType`, `ExampleTypeMismatch`; the test helper `NormalizerFixture` (`of(code)`, `pointersOf(code)`), used by tasks 7–11.

Behaviour: an array without `items` in 3.0 — TOA202 (in 3.1 no; an array with `format` gets TOA204 only); an `items` array with a boolean `required` — TOA203 (C-49); `format` on an array without `items` — TOA204 with a suggestion of override `items: {type: string, format: …}`; `type: object` + `format: binary` — TOA205; `type: object` next to `oneOf`/`anyOf`, all branches of which are of a known non-object type — TOA206 (a branch without a type — "may be an object" — is not reported); `example` of the wrong JSON type: a mismatch of structures (object against array, structure against scalar) — TOA207 warning, a scalar of another scalar type (`example: "1.5"` for `number`) — TOA208 info (the type is taken from the schema, from `$ref` or from `allOf` with one member; an `allOf` cycle does not loop the rule). `nestjs` hints for TOA202/TOA203 — declaration of the element type `@ApiProperty({ type: [Item] })` (research/06 §D.1, item 6).

- [ ] **Step 1: Codes**

Before the line `/// A schema's `default` is not of the schema's type; it is ignored.`:

```dart
  /// An array has no `items` in an OpenAPI 3.0 document, which requires it.
  arrayWithoutItems('TOA202', 'array-without-items', .warning),

  /// An array's `items` is an array with a boolean `required`: a list
  /// declared twice by a decorator.
  doubleArray('TOA203', 'double-array', .warning),

  /// `format` is on an array without `items` instead of on its elements.
  formatOnArray('TOA204', 'format-on-array', .warning),

  /// `type: object` with `format: binary` instead of a binary string.
  binaryObject('TOA205', 'binary-object', .warning),

  /// `type: object` next to `oneOf`/`anyOf` whose branches are all of other
  /// types.
  contradictoryObjectType('TOA206', 'contradictory-object-type', .warning),

  /// An `example` whose structure the schema does not allow: an object for
  /// an array, or a structure for a scalar and back.
  exampleTypeMismatch('TOA207', 'example-type-mismatch', .warning),

  /// An `example` that is a scalar of another type than the scalar schema,
  /// such as a string for a number; only the documentation is off.
  exampleScalarType('TOA208', 'example-scalar-type', .info),
```

- [ ] **Step 1a: Test helper**

Create `packages/typed_openapi/test/helpers/normalizer_fixture.dart`:

```dart
import 'package:typed_openapi/src/config/project_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/load/openapi_version.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/normalize/normalizer.dart';

/// A spec read from text and normalized with every rule.
final class NormalizerFixture {
  /// Loads [text] as `api.yaml`, detects its version and normalizes it with
  /// [preset]; the text must load and declare a version.
  NormalizerFixture(String text, {Preset? preset}) {
    final document = SpecLoader(diagnostics).parse(text, 'api.yaml')!;
    final version = OpenApiVersionDetector(diagnostics).detect(document)!;
    result = Normalizer(diagnostics, preset: preset).normalize(
      document,
      version,
    );
  }

  /// Every diagnostic.
  final DiagnosticBag diagnostics = DiagnosticBag();

  /// What the normalizer produced.
  late final NormalizedSpec result;

  /// The diagnostics with [code], in report order.
  List<Diagnostic> of(DiagnosticCode code) => [
    for (final d in diagnostics.sorted)
      if (d.code == code) d,
  ];

  /// The pointers of the diagnostics with [code], in report order.
  List<String?> pointersOf(DiagnosticCode code) => [
    for (final d in of(code)) d.pointer?.value,
  ];
}
```

- [ ] **Step 2: A test that fails**

Create `packages/typed_openapi/test/normalize/schema_shape_rules_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';

import '../helpers/normalizer_fixture.dart';

void main() {
  /// A document of [version] whose `components.schemas` are [schemas].
  String spec(String schemas, {String version = '3.0.3'}) =>
      'openapi: $version\ninfo: {title: Shop, version: "1"}\n'
      'components:\n  schemas:\n$schemas';

  const base = '#/components/schemas';

  group('array-without-items', () {
    const schemas = '''
    Tags: {type: array}
    Ids: {type: array, items: {type: string}}
''';

    test('an array without items in 3.0 is reported', () {
      final run = NormalizerFixture(spec(schemas));
      expect(run.pointersOf(DiagnosticCode.arrayWithoutItems), ['$base/Tags']);
      expect(
        run.of(DiagnosticCode.arrayWithoutItems).single.severity,
        Severity.warning,
      );
    });

    test('3.1 does not require items', () {
      final run = NormalizerFixture(spec(schemas, version: '3.1.0'));
      expect(run.of(DiagnosticCode.arrayWithoutItems), isEmpty);
    });
  });

  test('double-array: items that are arrays with a boolean required', () {
    final run = NormalizerFixture(
      spec('''
    Order:
      type: object
      properties:
        lines:
          type: array
          items:
            required: true
            type: array
            items: {type: string}
'''),
    );
    expect(run.pointersOf(DiagnosticCode.doubleArray), [
      '$base/Order/properties/lines/items',
    ]);
    expect(
      run.of(DiagnosticCode.doubleArray).single.fix,
      contains('inner "items"'),
    );
  });

  test('format-on-array replaces array-without-items for that schema', () {
    final run = NormalizerFixture(
      spec('    Ids: {type: array, format: uuid}\n'),
    );
    expect(run.pointersOf(DiagnosticCode.formatOnArray), ['$base/Ids/format']);
    expect(run.of(DiagnosticCode.arrayWithoutItems), isEmpty);
    expect(
      run.of(DiagnosticCode.formatOnArray).single.fix,
      contains('{type: string, format: uuid}'),
    );
  });

  test('binary-object: a file written as an object', () {
    final run = NormalizerFixture(
      spec('''
    Upload:
      type: object
      properties:
        file: {type: object, format: binary}
        data: {type: string, format: binary}
'''),
    );
    expect(run.pointersOf(DiagnosticCode.binaryObject), [
      '$base/Upload/properties/file/type',
    ]);
  });

  group('contradictory-object-type', () {
    test('object next to branches that are all scalars', () {
      final run = NormalizerFixture(
        spec(r'''
    Amount:
      type: object
      oneOf: [{type: string}, {$ref: '#/components/schemas/Cents'}]
    Cents: {type: integer}
'''),
      );
      final d = run.of(DiagnosticCode.contradictoryObjectType).single;
      expect(d.pointer?.value, '$base/Amount/type');
      expect(d.message, contains('integer, string'));
    });

    test('a branch that may be an object is not reported', () {
      final run = NormalizerFixture(
        spec('''
    Pet:
      type: object
      anyOf: [{type: string}, {type: object}, {description: anything}]
'''),
      );
      expect(run.of(DiagnosticCode.contradictoryObjectType), isEmpty);
    });
  });

  group('example-type-mismatch', () {
    test('a list example for an object, through a one-member allOf', () {
      final run = NormalizerFixture(
        spec(r'''
    Token: {type: object, properties: {value: {type: string}}}
    Session:
      type: object
      properties:
        tokens:
          allOf: [{$ref: '#/components/schemas/Token'}]
          example: [{value: a}, {value: b}]
        count: {type: integer, example: 3}
        ratio: {type: number, example: "1.5"}
'''),
      );
      expect(run.pointersOf(DiagnosticCode.exampleTypeMismatch), [
        '$base/Session/properties/tokens/example',
      ]);
      final scalar = run.of(DiagnosticCode.exampleScalarType).single;
      expect(scalar.pointer?.value, '$base/Session/properties/ratio/example');
      expect(scalar.severity, Severity.info);
      expect(
        run.of(DiagnosticCode.exampleTypeMismatch).first.message,
        'The example is a list, but the schema is object; clients built from '
        'the schema fail on such values.',
      );
    });

    test('allOf members that point at each other end, not loop', () {
      final run = NormalizerFixture(
        spec(r'''
    A: {allOf: [{$ref: '#/components/schemas/B'}], example: 1}
    B: {allOf: [{$ref: '#/components/schemas/A'}]}
'''),
      );
      expect(run.of(DiagnosticCode.exampleTypeMismatch), isEmpty);
    });
  });

  test('nestjs gets the element type recipe for arrays', () {
    final run = NormalizerFixture(
      spec('    Tags: {type: array}\n'),
      preset: .nestjs,
    );
    expect(
      run.of(DiagnosticCode.arrayWithoutItems).single.fix,
      endsWith('@ApiProperty({ type: [Item] }).'),
    );
  });
}
```

Run: `dart test test/normalize/schema_shape_rules_test.dart` — Expected: FAIL (there are no rules yet).

- [ ] **Step 3: Rules**

Create `packages/typed_openapi/lib/src/normalize/rules/schema_shape_rules.dart`:

```dart
import '../../config/project_config.dart';
import '../../diagnostics/diagnostic_code.dart';
import '../../model/schema.dart';
import '../../parse/object_reader.dart';
import '../normalizer_rule.dart';

/// An array without `items` in an OpenAPI 3.0 document (C-5), which 3.0
/// requires; its elements are read as any JSON value.
final class ArrayWithoutItems extends NormalizerRule {
  /// Creates the rule.
  const ArrayWithoutItems();

  @override
  String get name => 'array-without-items';

  @override
  List<DiagnosticCode> get codes => const [.arrayWithoutItems];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    if (context.version != .v30) return;
    for (final schema in context.nodes<SchemaObject>()) {
      if (!schema.types.contains(SchemaType.array) || schema.items != null) {
        continue;
      }
      // A format on the array is FormatOnArray's finding.
      if (schema.format != null || _hasItemsKey(context, schema)) continue;
      yield context.finding(
        .arrayWithoutItems,
        'This array has no "items", which OpenAPI 3.0 requires; its elements '
        'are read as any JSON value.',
        schema.location,
        fix:
            'Add "items" with the element schema at the source, or override '
            '"items" of this schema.',
      );
    }
  }

  @override
  String? hint(DiagnosticCode code, Preset preset) => switch (preset) {
    .nestjs =>
      'In NestJS, give the element type: @ApiProperty({ type: [Item] }).',
    _ => null,
  };

  /// Whether [schema] writes an `items` key, even one the parser rejected.
  static bool _hasItemsKey(RuleContext context, SchemaObject schema) =>
      context.rawObject(schema.location)?.containsKey('items') ?? false;
}

/// An array whose `items` is an array again and carries a boolean
/// `required` (C-49): the NestJS `type: [X]` plus `isArray: true` pattern,
/// which reads as a list of lists.
final class DoubleArray extends NormalizerRule {
  /// Creates the rule.
  const DoubleArray();

  @override
  String get name => 'double-array';

  @override
  List<DiagnosticCode> get codes => const [.doubleArray];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      final items = schema.items;
      if (!schema.types.contains(SchemaType.array) ||
          items is! SchemaObject ||
          !items.types.contains(SchemaType.array)) {
        continue;
      }
      final raw = context.rawObject(items.location);
      if (raw == null || raw['required'] is! bool) continue;
      yield context.finding(
        .doubleArray,
        'The items of this array are arrays too and say "required: '
        '${raw['required']}", the shape a decorator gives a list declared '
        'twice; clients read a list of lists.',
        items.location,
        fix:
            'If the field is a flat list, declare it once at the source; '
            'until then, override "items" of this schema with the inner '
            '"items".',
      );
    }
  }

  @override
  String? hint(DiagnosticCode code, Preset preset) => switch (preset) {
    .nestjs =>
      'In NestJS, write @ApiProperty({ type: [Item] }) without '
          '`isArray: true`.',
    _ => null,
  };
}

/// `format` on an array without `items` (C-50): the format belongs to the
/// elements.
final class FormatOnArray extends NormalizerRule {
  /// Creates the rule.
  const FormatOnArray();

  @override
  String get name => 'format-on-array';

  @override
  List<DiagnosticCode> get codes => const [.formatOnArray];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      final format = schema.format;
      if (format == null ||
          !schema.types.contains(SchemaType.array) ||
          schema.items != null ||
          ArrayWithoutItems._hasItemsKey(context, schema)) {
        continue;
      }
      yield context.finding(
        .formatOnArray,
        '"format: $format" is on the array, which has no "items", not on its '
        'elements.',
        schema.location.child('format'),
        fix:
            'Move it into the elements at the source; until then, override '
            '"items" of this schema with {type: string, format: $format}.',
      );
    }
  }
}

/// `type: object` with `format: binary` (C-51): a file is
/// `type: string, format: binary`.
final class BinaryObject extends NormalizerRule {
  /// Creates the rule.
  const BinaryObject();

  @override
  String get name => 'binary-object';

  @override
  List<DiagnosticCode> get codes => const [.binaryObject];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      if (schema.format != 'binary' ||
          !schema.types.contains(SchemaType.object)) {
        continue;
      }
      yield context.finding(
        .binaryObject,
        '"type: object" with "format: binary" does not describe a file; a '
        'file is "type: string, format: binary".',
        schema.location.child('type'),
        fix:
            'Write "type: string" at the source; until then, override "type" '
            'of this schema with string.',
      );
    }
  }
}

/// `type: object` next to `oneOf`/`anyOf` whose branches are all of other
/// types (C-22): no value matches both.
final class ContradictoryObjectType extends NormalizerRule {
  /// Creates the rule.
  const ContradictoryObjectType();

  @override
  String get name => 'contradictory-object-type';

  @override
  List<DiagnosticCode> get codes => const [.contradictoryObjectType];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      final branches = [...schema.oneOf, ...schema.anyOf];
      if (branches.isEmpty || !schema.types.contains(SchemaType.object)) {
        continue;
      }
      final types = <SchemaType>{};
      var known = true;
      for (final branch in branches) {
        final resolved = context.model.resolveSchema(branch);
        if (resolved is! SchemaObject || resolved.types.isEmpty) {
          known = false;
          break;
        }
        types.addAll(resolved.types);
      }
      if (!known || types.contains(SchemaType.object)) continue;
      final names = (types.map((t) => t.wire).toList()..sort()).join(', ');
      yield context.finding(
        .contradictoryObjectType,
        '"type: object" is next to "oneOf"/"anyOf" whose branches are all '
        '$names; no value matches both.',
        schema.location.child('type'),
        fix:
            'Remove "type: object" at the source; until then, override "type" '
            'of this schema.',
      );
    }
  }
}

/// An `example` whose JSON type the schema does not allow (C-60). A list for
/// an object schema, or a structure against a scalar, is a warning: clients
/// built from the schema fail on such values. A scalar of another type
/// (`example: "1.5"` for a number) is info: the decoder is unaffected and
/// only the documentation is off.
final class ExampleTypeMismatch extends NormalizerRule {
  /// Creates the rule.
  const ExampleTypeMismatch();

  @override
  String get name => 'example-type-mismatch';

  @override
  List<DiagnosticCode> get codes => const [
    .exampleTypeMismatch,
    .exampleScalarType,
  ];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      final example = schema.example;
      if (example == null) continue;
      final (value,) = example;
      if (value == null) continue;
      final types = _effectiveTypes(context, schema, {});
      if (types.isEmpty || types.any((t) => t.accepts(value))) continue;
      final names = types.map((t) => t.wire).join(' or ');
      final structural =
          value is List<Object?> ||
          value is Map<String, Object?> ||
          types.any((t) => t == .array || t == .object);
      yield structural
          ? context.finding(
              .exampleTypeMismatch,
              'The example is ${ObjectReader.describe(value)}, but the schema '
              'is $names; clients built from the schema fail on such values.',
              schema.location.child('example'),
              fix:
                  'Fix the schema or the example at the source; if the '
                  'example is right, override "type" of this schema.',
            )
          : context.finding(
              .exampleScalarType,
              'The example is ${ObjectReader.describe(value)}, but the schema '
              'is $names; the documentation shows a value of another type.',
              schema.location.child('example'),
              fix: 'Write the example as a $names at the source.',
            );
    }
  }

  /// The types [schema] allows: its own, or those of the only schema it
  /// refers to (`$ref`, or `allOf` with one member); `object` for a schema
  /// with properties and no type.
  static List<SchemaType> _effectiveTypes(
    RuleContext context,
    SchemaObject schema,
    Set<SchemaObject> seen,
  ) {
    if (!seen.add(schema)) return const [];
    if (schema.types.isNotEmpty) return schema.types;
    if (schema.properties.isNotEmpty) return const [.object];
    final target = schema.ref != null
        ? context.model.resolveSchema(schema)
        : schema.allOf.length == 1
        ? context.model.resolveSchema(schema.allOf.single)
        : null;
    if (target is! SchemaObject) return const [];
    return _effectiveTypes(context, target, seen);
  }
}
```

- [ ] **Step 4: Register**

In `lib/src/normalize/normalizer.dart` the rule imports between `import 'normalizer_rule.dart';` and `import 'spec_edit.dart';` must be as follows (sorted):

```dart
import 'rules/bool_required_to_array.dart';
import 'rules/drop_invalid_default.dart';
import 'rules/schema_shape_rules.dart';
```

and the `rules` list as follows:

```dart
  static final List<NormalizerRule> rules = List.unmodifiable(
    <NormalizerRule>[
      const BoolRequiredToArray(),
      const DropInvalidDefault(),
      const ArrayWithoutItems(),
      const DoubleArray(),
      const FormatOnArray(),
      const BinaryObject(),
      const ContradictoryObjectType(),
      const ExampleTypeMismatch(),
    ],
  );
```

- [ ] **Step 5: Check**

```bash
dart analyze packages                                  # from the root: No issues found!
dart test                                              # from packages/typed_openapi
dart format lib test bin && dart format lib test bin   # second run: 0 changed
```

Expected: 299 tests.

- [ ] **Step 6: Commit**

```bash
git add packages/typed_openapi
git commit -m "feat(typed_openapi): report array, file, combinator and example shape defects

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Enum: `dedupe-enum-values` (TOA301, fix) and nullable enum via `oneOf` (TOA303)

**Files:**
- Create: `packages/typed_openapi/lib/src/normalize/rules/enum_rules.dart`, `packages/typed_openapi/test/normalize/enum_rules_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_openapi/lib/src/normalize/normalizer.dart`

**Interfaces:**
- Consumes: `NormalizerRule`, `SpecEdit.replace`, `NormalizerFixture` (task 7); `DeepCollectionEquality` from `package:collection`.
- Produces: `DedupeEnumValues`, `NullableEnumOneOf`; codes `duplicateEnumValue` (TOA301), `nullableEnumOneOf` (TOA303).

Behaviour: repeats in `enum` (JSON equality: `2` and `2.0` are one value, `Admin` and `admin` are different) are removed by one `replace` edit of the whole `enum`; the first occurrence stays; more than 3 repeats — a note "looks like several merged enums" (C-52). `oneOf` of two branches — an enum with only `null` and a `$ref` — TOA303 with a suggestion of an override of the nullable reference. `nestjs` hints: `enumName`/`autoFillEnumName` (§D.1, item 1) and `@nestjs/swagger` 12 (§D.1, item 3).

- [ ] **Step 1: Codes**

Before the line `/// A normalizer fix was not applied: it overlaps an earlier rule's fix,`:

```dart
  /// An `enum` repeats a value; the repeats are removed.
  duplicateEnumValue('TOA301', 'duplicate-enum-value', .warning),

  /// A nullable enum written as `oneOf` of an enum of only `null` and a
  /// `$ref`.
  nullableEnumOneOf('TOA303', 'nullable-enum-one-of', .warning),
```

- [ ] **Step 2: A test that fails**

Create `packages/typed_openapi/test/normalize/enum_rules_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/model/schema.dart';

import '../helpers/normalizer_fixture.dart';

void main() {
  String spec(String schemas) =>
      'openapi: 3.0.3\ninfo: {title: Shop, version: "1"}\n'
      'components:\n  schemas:\n$schemas';

  group('dedupe-enum-values', () {
    test('repeats are removed, the first occurrence stays, case is kept', () {
      final run = NormalizerFixture(
        spec('''
    Role: {type: string, enum: [user, admin, user, Admin, admin]}
    Level: {type: integer, enum: [1, 2.0, 2]}
'''),
      );
      final schemas = run.result.model.document.components!.schemas;
      expect((schemas['Role']! as SchemaObject).enumValues, [
        'user',
        'admin',
        'Admin',
      ]);
      expect((schemas['Level']! as SchemaObject).enumValues, [1, 2.0]);
      final d = run.of(DiagnosticCode.duplicateEnumValue);
      expect(d.map((d) => d.pointer?.value), [
        '#/components/schemas/Role/enum',
        '#/components/schemas/Level/enum',
      ]);
      expect(
        d.first.message,
        'The enum repeats "user", "admin"; the repeats are removed and the '
        'first occurrence of each value is kept.',
      );
    });

    test('many repeats suggest merged enums; nestjs gets enumName', () {
      final run = NormalizerFixture(
        spec('''
    Status:
      type: string
      enum: [BUILT, ERROR, QUEUED, READY, BUILT, ERROR, QUEUED, READY]
'''),
        preset: .nestjs,
      );
      final d = run.of(DiagnosticCode.duplicateEnumValue).single;
      expect(d.message, contains('several enums merged into one'));
      expect(d.fix, contains('enumName'));
    });
  });

  group('nullable-enum-one-of', () {
    test('oneOf of a null-only enum and a reference is reported', () {
      final run = NormalizerFixture(
        spec(r'''
    Currency: {type: string, enum: [EUR, USD]}
    Price:
      type: object
      properties:
        currency:
          nullable: true
          oneOf:
            - {type: string, nullable: true, enum: [null]}
            - {$ref: '#/components/schemas/Currency'}
'''),
      );
      final d = run.of(DiagnosticCode.nullableEnumOneOf).single;
      expect(
        d.pointer?.value,
        '#/components/schemas/Price/properties/currency/oneOf',
      );
      expect(d.message, contains('"#/components/schemas/Currency"'));
    });

    test('an ordinary oneOf is not reported', () {
      final run = NormalizerFixture(
        spec(r'''
    Pet:
      oneOf:
        - {$ref: '#/components/schemas/Cat'}
        - {type: string, enum: [none]}
    Cat: {type: object}
'''),
      );
      expect(run.of(DiagnosticCode.nullableEnumOneOf), isEmpty);
    });
  });
}
```

Run: `dart test test/normalize/enum_rules_test.dart` — Expected: FAIL (there are no rules yet).

- [ ] **Step 3: Rules**

Create `packages/typed_openapi/lib/src/normalize/rules/enum_rules.dart`:

```dart
import 'dart:convert';

import 'package:collection/collection.dart';

import '../../config/project_config.dart';
import '../../diagnostics/diagnostic_code.dart';
import '../../model/schema.dart';
import '../normalizer_rule.dart';
import '../spec_edit.dart';

/// Values repeated in an `enum` (C-9, C-52) are removed; the first
/// occurrence of each stays, in order. Values are compared as JSON, so
/// `Admin` and `admin` are two values.
final class DedupeEnumValues extends NormalizerRule {
  /// Creates the rule.
  const DedupeEnumValues();

  /// More repeats than this suggest several enums merged into one (C-52).
  static const _mergedEnums = 3;

  static const _equality = DeepCollectionEquality();

  @override
  String get name => 'dedupe-enum-values';

  @override
  List<DiagnosticCode> get codes => const [.duplicateEnumValue];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      final values = schema.enumValues;
      if (values == null) continue;
      final kept = <Object?>[];
      final repeated = <Object?>[];
      for (final value in values) {
        final seen = kept.any((k) => _equality.equals(k, value));
        (seen ? repeated : kept).add(value);
      }
      if (repeated.isEmpty) continue;
      final at = schema.location.child('enum');
      final shown = repeated.map(jsonEncode).toSet().join(', ');
      yield context.finding(
        .duplicateEnumValue,
        'The enum repeats $shown; the repeats are removed and the first '
        'occurrence of each value is kept'
        '${repeated.length > _mergedEnums ? '. So many repeats look like '
                  'several enums merged into one' : ''}.',
        at,
        fix: 'Remove the repeated values at the source.',
        edits: [SpecEdit.replace(at, kept)],
      );
    }
  }

  @override
  String? hint(DiagnosticCode code, Preset preset) => switch (preset) {
    .nestjs =>
      'In NestJS, give the enum its own schema with `enumName` (the CLI '
          'plugin option `autoFillEnumName` sets it) instead of spreading '
          'several TypeScript enums into one list.',
    _ => null,
  };
}

/// A nullable enum written as `oneOf` of an enum of only `null` and a
/// `$ref` (C-54, NestJS 11): the intent is a nullable reference, but
/// generators read a union.
final class NullableEnumOneOf extends NormalizerRule {
  /// Creates the rule.
  const NullableEnumOneOf();

  @override
  String get name => 'nullable-enum-one-of';

  @override
  List<DiagnosticCode> get codes => const [.nullableEnumOneOf];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      if (schema.oneOf.length != 2) continue;
      final nulls = schema.oneOf.whereType<SchemaObject>().where(_onlyNull);
      final refs = schema.oneOf.whereType<SchemaObject>().where(
        (s) => s.ref != null,
      );
      if (nulls.length != 1 || refs.length != 1) continue;
      final ref = refs.single.ref!;
      yield context.finding(
        .nullableEnumOneOf,
        'This is a nullable reference to "$ref" written as "oneOf" with an '
        'enum of only null; generators read it as a union of two types.',
        schema.location.child('oneOf'),
        fix:
            'Write a nullable reference to "$ref" at the source; until then, '
            'override this schema as a nullable "$ref".',
      );
    }
  }

  static bool _onlyNull(SchemaObject schema) {
    final values = schema.enumValues;
    return values != null &&
        values.isNotEmpty &&
        values.every((v) => v == null) &&
        schema.ref == null;
  }

  @override
  String? hint(DiagnosticCode code, Preset preset) => switch (preset) {
    .nestjs =>
      'In NestJS, @nestjs/swagger 12 writes nullability according to the '
          'document version; on 11.x keep the document at OpenAPI 3.0.',
    _ => null,
  };
}
```

- [ ] **Step 4: Register**

In `lib/src/normalize/normalizer.dart` the rule imports between `import 'normalizer_rule.dart';` and `import 'spec_edit.dart';` must be as follows (sorted):

```dart
import 'rules/bool_required_to_array.dart';
import 'rules/drop_invalid_default.dart';
import 'rules/enum_rules.dart';
import 'rules/schema_shape_rules.dart';
```

and the `rules` list as follows:

```dart
  static final List<NormalizerRule> rules = List.unmodifiable(
    <NormalizerRule>[
      const BoolRequiredToArray(),
      const DropInvalidDefault(),
      const ArrayWithoutItems(),
      const DoubleArray(),
      const FormatOnArray(),
      const BinaryObject(),
      const ContradictoryObjectType(),
      const ExampleTypeMismatch(),
      const DedupeEnumValues(),
      const NullableEnumOneOf(),
    ],
  );
```

- [ ] **Step 5: Check**

```bash
dart analyze packages                                  # from the root: No issues found!
dart test                                              # from packages/typed_openapi
dart format lib test bin && dart format lib test bin   # second run: 0 changed
```

Expected: 303 tests.

- [ ] **Step 6: Commit**

```bash
git add packages/typed_openapi
git commit -m "feat(typed_openapi): dedupe enum values and report nullable enums through oneOf

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Path parameters: `declare-missing-path-params` (TOA501, fix) and a parameter outside the template (TOA502)

**Files:**
- Create: `packages/typed_openapi/lib/src/normalize/rules/path_param_rules.dart`, `packages/typed_openapi/test/normalize/path_param_rules_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_openapi/lib/src/normalize/normalizer.dart`

**Interfaces:**
- Consumes: `NormalizerRule`, `SpecEdit.add/replace`, `SpecModel.resolve`, `NormalizerFixture`.
- Produces: `DeclareMissingPathParams`, `PathParamNotInTemplate`; codes `missingPathParameter` (TOA501), `pathParameterNotInTemplate` (TOA502).

Behaviour: a template variable without a path parameter (neither in the path item nor in the operation, taking `$ref` parameters into account) — one finding per operation and one edit of its `parameters` (adds `{name, in: path, required: true, schema: {type: string}}` for each variable; if there was no list, it creates one). A parameter that differs only by case is not added: that is TOA502, "the template writes it as {id}". A declared path parameter outside the template — TOA502 error at the place where the parameter is written. An operation written as `$ref` (TOA107) is skipped.

- [ ] **Step 1: Codes**

Before the line `/// A normalizer fix was not applied: it overlaps an earlier rule's fix,`:

```dart
  /// A variable of the path template has no path parameter; one is added.
  missingPathParameter('TOA501', 'missing-path-parameter', .warning),

  /// A path parameter is not a variable of the path template, or is one in
  /// another case.
  pathParameterNotInTemplate(
    'TOA502',
    'path-parameter-not-in-template',
    .error,
  ),
```

- [ ] **Step 2: A test that fails**

Create `packages/typed_openapi/test/normalize/path_param_rules_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/model/operation.dart';

import '../helpers/normalizer_fixture.dart';

void main() {
  String spec(String paths) =>
      'openapi: 3.0.3\ninfo: {title: Shop, version: "1"}\npaths:\n$paths';

  group('declare-missing-path-params', () {
    test('every missing variable is added to the operation', () {
      final run = NormalizerFixture(
        spec('''
  /shops/{shop}/orders/{order}:
    get:
      parameters:
        - {name: limit, in: query, schema: {type: integer}}
      responses: {}
    delete:
      responses: {}
'''),
      );
      final item = run.result.model.resolve(
        run.result.model.document.paths['/shops/{shop}/orders/{order}']!,
      )!;
      final get = item.operations['get']!;
      final names = [
        for (final p in get.parameters) run.result.model.resolve(p)!.name,
      ];
      expect(names, ['limit', 'shop', 'order']);
      final added = run.result.model.resolve(get.parameters[1])!;
      expect(added.placement, ParameterLocation.path);
      expect(added.required, isTrue);
      expect(item.operations['delete']!.parameters, hasLength(2));
      final found = run.of(DiagnosticCode.missingPathParameter);
      expect(found, hasLength(2));
      expect(
        found.first.message,
        'The path /shops/{shop}/orders/{order} has {shop}, {order}, but this '
        'operation declares no path parameter "shop", "order"; they are '
        'added as required string path parameters.',
      );
      expect(found.first.severity, Severity.warning);
      expect(
        found.first.pointer?.value,
        '#/paths/~1shops~1{shop}~1orders~1{order}/get',
      );
    });

    test('parameters of the path item and references count as declared', () {
      final run = NormalizerFixture(
        spec(r'''
  /users/{id}/posts/{post}:
    parameters:
      - {$ref: '#/components/parameters/Id'}
    get:
      parameters:
        - {name: post, in: path, required: true, schema: {type: string}}
      responses: {}
components:
  parameters:
    Id: {name: id, in: path, required: true, schema: {type: string}}
'''),
      );
      expect(run.of(DiagnosticCode.missingPathParameter), isEmpty);
      expect(run.of(DiagnosticCode.pathParameterNotInTemplate), isEmpty);
    });
  });

  group('path-param-not-in-template', () {
    test('a renamed or differently cased parameter is an error', () {
      final run = NormalizerFixture(
        spec('''
  /users/{id}:
    get:
      parameters:
        - {name: userId, in: path, required: true, schema: {type: string}}
        - {name: ID, in: path, required: true, schema: {type: string}}
      responses: {}
'''),
      );
      final found = run.of(DiagnosticCode.pathParameterNotInTemplate);
      expect(found.map((d) => d.pointer?.value), [
        '#/paths/~1users~1{id}/get/parameters/0',
        '#/paths/~1users~1{id}/get/parameters/1',
      ]);
      expect(found.first.severity, Severity.error);
      expect(found.last.message, endsWith('which writes it as {id}.'));
      // {id} is not added: the case mismatch is the finding.
      expect(run.of(DiagnosticCode.missingPathParameter), isEmpty);
    });
  });
}
```

Run: `dart test test/normalize/path_param_rules_test.dart` — Expected: FAIL (there are no rules yet).

- [ ] **Step 3: Rules**

Create `packages/typed_openapi/lib/src/normalize/rules/path_param_rules.dart`:

```dart
import '../../diagnostics/diagnostic_code.dart';
import '../../model/operation.dart';
import '../../model/spec_node.dart';
import '../normalizer_rule.dart';
import '../spec_edit.dart';

/// The path templates of a spec with their path items, as both path rules
/// read them.
final class _PathTemplates {
  _PathTemplates(this.context);

  final RuleContext context;

  static final _variable = RegExp(r'\{([^{}]+)\}');

  /// Every templated path with its resolved path item, in document order.
  Iterable<(String, PathItem)> get paths sync* {
    for (final MapEntry(key: template, value: item)
        in context.model.document.paths.entries) {
      final resolved = context.model.resolve(item);
      if (resolved != null) yield (template, resolved);
    }
  }

  /// The variables of [template], in order, each once.
  static List<String> variablesOf(String template) => [
    ...{for (final m in _variable.allMatches(template)) m.group(1)!},
  ];

  /// The path parameters among [parameters], with where each is written.
  List<(Parameter, SpecLocation)> pathParameters(
    List<RefOr<Parameter>> parameters,
  ) => [
    for (final parameter in parameters)
      if (context.model.resolve(parameter) case final resolved?
          when resolved.placement == .path && resolved.name != null)
        (resolved, _siteOf(parameter, resolved)),
  ];

  static SpecLocation _siteOf(RefOr<Parameter> written, Parameter resolved) =>
      switch (written) {
        Ref() => written.location,
        Inline() => resolved.location,
      };
}

/// A variable of the path template without a declared path parameter (C-6)
/// gets `{name, in: path, required: true, schema: {type: string}}` in each
/// operation that lacks it: a path segment is a string on the wire.
final class DeclareMissingPathParams extends NormalizerRule {
  /// Creates the rule.
  const DeclareMissingPathParams();

  @override
  String get name => 'declare-missing-path-params';

  @override
  List<DiagnosticCode> get codes => const [.missingPathParameter];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final templates = _PathTemplates(context);
    for (final (template, item) in templates.paths) {
      final variables = _PathTemplates.variablesOf(template);
      if (variables.isEmpty) continue;
      final shared = {
        for (final (p, _) in templates.pathParameters(item.parameters)) p.name,
      };
      for (final operation in item.operations.values) {
        // An operation written as a `$ref` is TOA107 already; it is empty.
        if (operation.unknownKeys.containsKey(r'$ref')) continue;
        final declared = {
          ...shared,
          for (final (p, _) in templates.pathParameters(operation.parameters))
            p.name,
        };
        final lowered = {for (final n in declared) n!.toLowerCase()};
        // A name that differs only in case is PathParamNotInTemplate's
        // finding; adding a parameter would hide it.
        final missing = [
          for (final v in variables)
            if (!declared.contains(v) && !lowered.contains(v.toLowerCase())) v,
        ];
        if (missing.isEmpty) continue;
        // One finding per operation: a fix is one edit of its parameters.
        final names = missing.map((m) => '"$m"').join(', ');
        yield context.finding(
          .missingPathParameter,
          'The path $template has ${missing.map((m) => '{$m}').join(', ')}, '
          'but this operation declares no path parameter $names; '
          '${missing.length == 1 ? 'it is' : 'they are'} added as required '
          'string path parameters.',
          operation.location,
          fix:
              'Declare each at the source as {name: <name>, in: path, '
              'required: true, schema: {type: string}}.',
          edits: [_edit(context, operation, missing)],
        );
      }
    }
  }

  /// One edit that adds every parameter of [names] to [operation].
  static SpecEdit _edit(
    RuleContext context,
    Operation operation,
    List<String> names,
  ) {
    final at = operation.location.child('parameters');
    final added = [
      for (final name in names)
        {
          'name': name,
          'in': 'path',
          'required': true,
          'schema': {'type': 'string'},
        },
    ];
    return switch (context.rawAt(at)) {
      (final List<Object?> existing,) => SpecEdit.replace(at, [
        ...existing,
        ...added,
      ]),
      _ => SpecEdit.add(at, added),
    };
  }
}

/// A declared path parameter that is not a variable of the path template,
/// or is one in another case (C-7). Which name is right cannot be told, so
/// this is a diagnostic only.
final class PathParamNotInTemplate extends NormalizerRule {
  /// Creates the rule.
  const PathParamNotInTemplate();

  @override
  String get name => 'path-param-not-in-template';

  @override
  List<DiagnosticCode> get codes => const [.pathParameterNotInTemplate];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final templates = _PathTemplates(context);
    for (final (template, item) in templates.paths) {
      final variables = _PathTemplates.variablesOf(template);
      final parameters = [
        ...templates.pathParameters(item.parameters),
        for (final operation in item.operations.values)
          ...templates.pathParameters(operation.parameters),
      ];
      for (final (parameter, site) in parameters) {
        final name = parameter.name!;
        if (variables.contains(name)) continue;
        final other = variables
            .where((v) => v.toLowerCase() == name.toLowerCase())
            .firstOrNull;
        yield context.finding(
          .pathParameterNotInTemplate,
          'Path parameter "$name" is not in the path template $template'
          '${other == null ? '' : ', which writes it as {$other}'}.',
          site,
          fix:
              'Make the parameter name and the template variable the same at '
              'the source; until then, override the name of this parameter.',
        );
      }
    }
  }
}
```

- [ ] **Step 4: Register**

In `lib/src/normalize/normalizer.dart` the rule imports between `import 'normalizer_rule.dart';` and `import 'spec_edit.dart';` must be as follows (sorted):

```dart
import 'rules/bool_required_to_array.dart';
import 'rules/drop_invalid_default.dart';
import 'rules/enum_rules.dart';
import 'rules/path_param_rules.dart';
import 'rules/schema_shape_rules.dart';
```

and the `rules` list as follows:

```dart
  static final List<NormalizerRule> rules = List.unmodifiable(
    <NormalizerRule>[
      const BoolRequiredToArray(),
      const DropInvalidDefault(),
      const ArrayWithoutItems(),
      const DoubleArray(),
      const FormatOnArray(),
      const BinaryObject(),
      const ContradictoryObjectType(),
      const ExampleTypeMismatch(),
      const DedupeEnumValues(),
      const NullableEnumOneOf(),
      const DeclareMissingPathParams(),
      const PathParamNotInTemplate(),
    ],
  );
```

- [ ] **Step 5: Check**

```bash
dart analyze packages                                  # from the root: No issues found!
dart test                                              # from packages/typed_openapi
dart format lib test bin && dart format lib test bin   # second run: 0 changed
```

Expected: 306 tests.

- [ ] **Step 6: Commit**

```bash
git add packages/typed_openapi
git commit -m "feat(typed_openapi): declare missing path parameters and report stray ones

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: `operationId`: missing (TOA503) and repeated (TOA504)

**Files:**
- Create: `packages/typed_openapi/lib/src/normalize/rules/operation_id_rules.dart`, `packages/typed_openapi/test/normalize/operation_id_rules_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_openapi/lib/src/normalize/normalizer.dart`

**Interfaces:**
- Consumes: `NormalizerRule`, `RuleContext.nodes<Operation>()`, `SpecDocuments.displayPath`, `NormalizerFixture`.
- Produces: `MissingOperationId`, `DuplicateOperationId`; codes `missingOperationId` (TOA503, info), `duplicateOperationId` (TOA504, error).

Behaviour: an operation without `operationId` — TOA503 info (an operation that is a `$ref` is skipped); a repeat — TOA504 on each one after the first in `SpecLocation` order, citing the place of the first. Hints: `aspnet` — `.WithName`/`[EndpointName]`/Swashbuckle `CustomOperationIds` (§D.4); `nestjs` — `operationIdFactory` (§D.1, item 2); `fastapi` — `generate_unique_id_function` (§D.2, item 1); `springdoc` — `@Operation(operationId = …)` (§D.3, item 2).

- [ ] **Step 1: Codes**

Before the line `/// A normalizer fix was not applied: it overlaps an earlier rule's fix,`:

```dart
  /// An operation has no `operationId`.
  missingOperationId('TOA503', 'missing-operation-id', .info),

  /// Two operations share an `operationId`.
  duplicateOperationId('TOA504', 'duplicate-operation-id', .error),
```

- [ ] **Step 2: A test that fails**

Create `packages/typed_openapi/test/normalize/operation_id_rules_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/config/project_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';

import '../helpers/normalizer_fixture.dart';

void main() {
  const spec = '''
openapi: 3.0.3
info: {title: Shop, version: "1"}
paths:
  /orders:
    get: {operationId: list, responses: {}}
    post: {responses: {}}
  /orders/archive:
    get: {operationId: list, responses: {}}
''';

  test('missing-operation-id is info at the operation', () {
    final d = NormalizerFixture(spec).of(DiagnosticCode.missingOperationId);
    expect(d.single.pointer?.value, '#/paths/~1orders/post');
    expect(d.single.severity, Severity.info);
  });

  test(r'an operation written as a $ref is left to ref-not-allowed', () {
    final run = NormalizerFixture(r'''
openapi: 3.0.3
info: {title: Shop, version: "1"}
paths:
  /orders/{id}:
    get: {$ref: resources/orders/get.yml}
''');
    expect(run.of(DiagnosticCode.missingOperationId), isEmpty);
    expect(run.of(DiagnosticCode.missingPathParameter), isEmpty);
    expect(run.of(DiagnosticCode.refNotAllowed), hasLength(1));
  });

  test('duplicate-operation-id names the first owner of the id', () {
    final d = NormalizerFixture(spec).of(DiagnosticCode.duplicateOperationId);
    expect(
      d.single.pointer?.value,
      '#/paths/~1orders~1archive/get/operationId',
    );
    expect(d.single.severity, Severity.error);
    expect(
      d.single.message,
      'operationId "list" is also the id of the operation at '
      '#/paths/~1orders/get; method names would clash.',
    );
  });

  test('presets add their recipes', () {
    expect(
      NormalizerFixture(
        spec,
        preset: .aspnet,
      ).of(DiagnosticCode.missingOperationId).single.fix,
      contains('[EndpointName("getUser")]'),
    );
    for (final (preset, recipe) in [
      (Preset.nestjs, 'operationIdFactory'),
      (Preset.fastapi, 'generate_unique_id_function'),
      (Preset.springdoc, '@Operation(operationId'),
    ]) {
      expect(
        NormalizerFixture(
          spec,
          preset: preset,
        ).of(DiagnosticCode.duplicateOperationId).single.fix,
        contains(recipe),
      );
    }
  });
}
```

Run: `dart test test/normalize/operation_id_rules_test.dart` — Expected: FAIL (there are no rules yet).

- [ ] **Step 3: Rules**

Create `packages/typed_openapi/lib/src/normalize/rules/operation_id_rules.dart`:

```dart
import '../../config/project_config.dart';
import '../../diagnostics/diagnostic_code.dart';
import '../../model/operation.dart';
import '../normalizer_rule.dart';

/// An operation without `operationId` (C-34): the generator has to name its
/// method after the HTTP method and path.
final class MissingOperationId extends NormalizerRule {
  /// Creates the rule.
  const MissingOperationId();

  @override
  String get name => 'missing-operation-id';

  @override
  List<DiagnosticCode> get codes => const [.missingOperationId];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final operation in context.nodes<Operation>()) {
      // An operation written as a `$ref` is TOA107 already; it is empty.
      if (operation.operationId != null ||
          operation.unknownKeys.containsKey(r'$ref')) {
        continue;
      }
      yield context.finding(
        .missingOperationId,
        'This operation has no "operationId", so its method is named after '
        'the HTTP method and the path.',
        operation.location,
        fix:
            'Add an operationId at the source, or override the method name of '
            'this operation.',
      );
    }
  }

  @override
  String? hint(DiagnosticCode code, Preset preset) => switch (preset) {
    .aspnet =>
      'In ASP.NET, name the endpoint: .WithName("getUser") or '
          '[EndpointName("getUser")]; with Swashbuckle, '
          'CustomOperationIds(api => api.TryGetMethodInfo(out var mi) ? '
          'mi.Name : null).',
    _ => null,
  };
}

/// Operations that share an `operationId` (C-36); which one keeps the name
/// cannot be told, so this is a diagnostic only.
final class DuplicateOperationId extends NormalizerRule {
  /// Creates the rule.
  const DuplicateOperationId();

  @override
  String get name => 'duplicate-operation-id';

  @override
  List<DiagnosticCode> get codes => const [.duplicateOperationId];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final first = <String, Operation>{};
    for (final operation in context.nodes<Operation>()) {
      final id = operation.operationId;
      if (id == null) continue;
      final earlier = first[id];
      if (earlier == null) {
        first[id] = operation;
        continue;
      }
      final where = earlier.location.document == operation.location.document
          ? earlier.pointer.value
          : '${context.documents.displayPath(earlier.location.document)}'
                '${earlier.pointer.value}';
      yield context.finding(
        .duplicateOperationId,
        'operationId "$id" is also the id of the operation at $where; method '
        'names would clash.',
        operation.location.child('operationId'),
        fix:
            'Give each operation its own operationId at the source, or '
            'override the method name of this operation.',
      );
    }
  }

  @override
  String? hint(DiagnosticCode code, Preset preset) => switch (preset) {
    .nestjs =>
      'In NestJS, set `operationIdFactory` in SwaggerModule.createDocument '
          '(the default is controllerKey_methodKey).',
    .fastapi =>
      'In FastAPI, pass `generate_unique_id_function` to FastAPI(...).',
    .springdoc =>
      'In springdoc, set @Operation(operationId = "...") explicitly; the '
          'generated _1 suffixes are not stable.',
    _ => null,
  };
}
```

- [ ] **Step 4: Register**

In `lib/src/normalize/normalizer.dart` the rule imports between `import 'normalizer_rule.dart';` and `import 'spec_edit.dart';` must be as follows (sorted):

```dart
import 'rules/bool_required_to_array.dart';
import 'rules/drop_invalid_default.dart';
import 'rules/enum_rules.dart';
import 'rules/operation_id_rules.dart';
import 'rules/path_param_rules.dart';
import 'rules/schema_shape_rules.dart';
```

and the `rules` list as follows:

```dart
  static final List<NormalizerRule> rules = List.unmodifiable(
    <NormalizerRule>[
      const BoolRequiredToArray(),
      const DropInvalidDefault(),
      const ArrayWithoutItems(),
      const DoubleArray(),
      const FormatOnArray(),
      const BinaryObject(),
      const ContradictoryObjectType(),
      const ExampleTypeMismatch(),
      const DedupeEnumValues(),
      const NullableEnumOneOf(),
      const DeclareMissingPathParams(),
      const PathParamNotInTemplate(),
      const MissingOperationId(),
      const DuplicateOperationId(),
    ],
  );
```

- [ ] **Step 5: Check**

```bash
dart analyze packages                                  # from the root: No issues found!
dart test                                              # from packages/typed_openapi
dart format lib test bin && dart format lib test bin   # second run: 0 changed
```

Expected: 310 tests.

- [ ] **Step 6: Commit**

```bash
git add packages/typed_openapi
git commit -m "feat(typed_openapi): report missing and duplicate operationIds

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Discriminator, media type, components keys (TOA401, TOA402, TOA601, TOA106)

**Files:**
- Create: `packages/typed_openapi/lib/src/normalize/rules/reference_shape_rules.dart`, `packages/typed_openapi/test/normalize/reference_shape_rules_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_openapi/lib/src/normalize/normalizer.dart`

**Interfaces:**
- Consumes: `NormalizerRule`, `RefTarget.parse` (M2), `SpecModel.resolveSchema`, `Components` (M2), `NormalizerFixture`.
- Produces: `DiscriminatorPropertyRequired`, `DiscriminatorMappingTarget`, `WildcardMediaType`, `ComponentKeyCharacters`; codes `invalidComponentKey` (TOA106), `discriminatorNotRequired` (TOA401, info), `discriminatorMappingUnresolved` (TOA402, error), `wildcardMediaType` (TOA601).

Behaviour: the discriminator property is not `required` in `oneOf`/`anyOf` variants (taking `allOf` into account) — one TOA401 per discriminator, at its place, with the list of variants (sorted, up to 10 names, then "and N more"); a value of `discriminator.mapping` that leads nowhere (a name without `#`, `/`, `.` is looked up in `components.schemas`, the rest — as `$ref`) — TOA402 (M2 does not resolve mapping); `*/*` — TOA601; a `components.*` key outside `^[a-zA-Z0-9\.\-_]+$` — TOA106. Hints: `aspnet` — `[JsonPolymorphic]`/`[JsonDerivedType]` (§D.4, item 4) and `CustomSchemaIds` (§D.4); `fastapi` — unique model names (§D.2, item 5); `springdoc` — `discriminatorMapping` (§D.3, item 6), `default-produces-media-type` (§D.3, item 1), `@Schema(name)` (§D.3, item 1).

- [ ] **Step 1: Codes**

Before the line `/// A `$ref` where OpenAPI does not accept a Reference Object, as bundlers`:

```dart
  /// A key in `components` has characters OpenAPI does not allow there.
  invalidComponentKey('TOA106', 'invalid-component-key', .warning),
```

Before the line `/// A variable of the path template has no path parameter; one is added.`:

```dart
  /// The discriminator property is not required in a variant.
  discriminatorNotRequired('TOA401', 'discriminator-not-required', .info),

  /// A `discriminator.mapping` value points to a schema that does not
  /// exist.
  discriminatorMappingUnresolved(
    'TOA402',
    'discriminator-mapping-unresolved',
    .error,
  ),
```

Before the line `/// A normalizer fix was not applied: it overlaps an earlier rule's fix,`:

```dart
  /// `*/*` is used as a media type.
  wildcardMediaType('TOA601', 'wildcard-media-type', .warning),
```

- [ ] **Step 2: A test that fails**

Create `packages/typed_openapi/test/normalize/reference_shape_rules_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/config/project_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';

import '../helpers/normalizer_fixture.dart';

void main() {
  const pets = r'''
openapi: 3.1.0
info: {title: Pets, version: "1"}
components:
  schemas:
    Pet:
      oneOf:
        - {$ref: '#/components/schemas/Cat'}
        - {$ref: '#/components/schemas/Dog'}
      discriminator:
        propertyName: kind
        mapping:
          cat: '#/components/schemas/Cat'
          dog: Dog
          bird: '#/components/schemas/Bird'
          fish: Fish
    Base:
      type: object
      required: [kind]
      properties: {kind: {type: string}}
    Cat:
      allOf: [{$ref: '#/components/schemas/Base'}]
    Dog:
      type: object
      properties: {kind: {type: string}}
''';

  test('discriminator-property-required: once per discriminator, through '
      'allOf', () {
    final d = NormalizerFixture(pets).of(
      DiagnosticCode.discriminatorNotRequired,
    );
    expect(d.single.pointer?.value, '#/components/schemas/Pet/discriminator');
    expect(d.single.severity, Severity.info);
    expect(
      d.single.message,
      'Discriminator property "kind" is not required in Dog; a payload '
      'without it cannot be told apart.',
    );
  });

  test('discriminator-property-required lists at most ten variants', () {
    final schemas = StringBuffer();
    final refs = StringBuffer();
    for (var i = 0; i < 12; i++) {
      final name = 'V${i.toString().padLeft(2, '0')}';
      schemas.writeln('    $name: {type: object}');
      refs.writeln("        - {\$ref: '#/components/schemas/$name'}");
    }
    final d = NormalizerFixture('''
openapi: 3.1.0
info: {title: Pets, version: "1"}
components:
  schemas:
    Pet:
      discriminator: {propertyName: kind}
      oneOf:
$refs$schemas''').of(DiagnosticCode.discriminatorNotRequired);
    expect(
      d.single.message,
      'Discriminator property "kind" is not required in V00, V01, V02, V03, '
      'V04, V05, V06, V07, V08, V09 and 2 more; a payload without it cannot '
      'be told apart.',
    );
  });

  test('discriminator-mapping-target: names and references', () {
    final d = NormalizerFixture(pets).of(
      DiagnosticCode.discriminatorMappingUnresolved,
    );
    expect(d.map((d) => d.pointer?.value), [
      '#/components/schemas/Pet/discriminator/mapping/bird',
      '#/components/schemas/Pet/discriminator/mapping/fish',
    ]);
    expect(d.first.severity, Severity.error);
    expect(
      d.first.message,
      'discriminator.mapping "bird" points to '
      '"#/components/schemas/Bird", which does not exist.',
    );
  });

  test('wildcard-media-type in a response; springdoc gets the property', () {
    final run = NormalizerFixture('''
openapi: 3.1.0
info: {title: Pets, version: "1"}
paths:
  /pets:
    get:
      operationId: list
      responses:
        "200":
          description: ok
          content:
            "*/*": {schema: {type: string}}
            application/json: {schema: {type: string}}
''', preset: .springdoc);
    final d = run.of(DiagnosticCode.wildcardMediaType).single;
    expect(d.pointer?.value, '#/paths/~1pets/get/responses/200/content/*~1*');
    expect(d.fix, contains('springdoc.default-produces-media-type'));
  });

  test('component-key-characters; aspnet gets CustomSchemaIds', () {
    final run = NormalizerFixture('''
openapi: 3.1.0
info: {title: Pets, version: "1"}
components:
  schemas:
    "Page[User]": {type: object}
    Ns.Outer+Inner: {type: object}
    Pet_v2.1-beta: {type: object}
  responses:
    "Not Found": {description: missing}
''', preset: Preset.aspnet);
    final d = run.of(DiagnosticCode.invalidComponentKey);
    expect(d.map((d) => d.pointer?.value), [
      '#/components/schemas/Page[User]',
      '#/components/schemas/Ns.Outer+Inner',
      '#/components/responses/Not Found',
    ]);
    expect(d.first.fix, contains('CustomSchemaIds'));
  });
}
```

Run: `dart test test/normalize/reference_shape_rules_test.dart` — Expected: FAIL (there are no rules yet).

- [ ] **Step 3: Rules**

Create `packages/typed_openapi/lib/src/normalize/rules/reference_shape_rules.dart`:

```dart
import '../../config/project_config.dart';
import '../../diagnostics/diagnostic_code.dart';
import '../../model/operation.dart';
import '../../model/schema.dart';
import '../../resolve/ref_target.dart';
import '../normalizer_rule.dart';

/// The discriminator property is not `required` in some variants (C-42): a
/// payload without it cannot be told apart. Reported once per
/// discriminator, with the variants.
final class DiscriminatorPropertyRequired extends NormalizerRule {
  /// Creates the rule.
  const DiscriminatorPropertyRequired();

  @override
  String get name => 'discriminator-property-required';

  @override
  List<DiagnosticCode> get codes => const [.discriminatorNotRequired];

  /// How many variant names a message lists.
  static const _shown = 10;

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      final discriminator = schema.discriminator;
      final property = discriminator?.propertyName;
      if (discriminator == null || property == null) continue;
      final names = <String>{
        for (final branch in [...schema.oneOf, ...schema.anyOf])
          if (context.model.resolveSchema(branch) case final SchemaObject v
              when !_required(context, v, {}).contains(property))
            _nameOf(v),
      }.toList()..sort();
      if (names.isEmpty) continue;
      final listed = names.take(_shown).join(', ');
      final more = names.length > _shown
          ? ' and ${names.length - _shown} more'
          : '';
      yield context.finding(
        .discriminatorNotRequired,
        'Discriminator property "$property" is not required in $listed'
        '$more; a payload without it cannot be told apart.',
        discriminator.location,
        fix: 'Add "$property" to "required" of each variant at the source.',
      );
    }
  }

  /// A variant's component name, or its pointer when it is inline.
  static String _nameOf(SchemaObject variant) {
    final tokens = variant.pointer.tokens;
    return tokens.length == 3 && tokens[1] == 'schemas'
        ? tokens.last
        : variant.pointer.value;
  }

  /// The names [schema] requires, its `allOf` members included.
  static Set<String> _required(
    RuleContext context,
    SchemaObject schema,
    Set<SchemaObject> seen,
  ) {
    if (!seen.add(schema)) return const {};
    return {
      ...schema.required,
      for (final member in schema.allOf)
        if (context.model.resolveSchema(member) case final SchemaObject m)
          ..._required(context, m, seen),
    };
  }

  @override
  String? hint(DiagnosticCode code, Preset preset) => switch (preset) {
    .aspnet =>
      'In ASP.NET, put [JsonPolymorphic] on an abstract base type and '
          '[JsonDerivedType(typeof(Bar), "bar")] on it for each variant.',
    _ => null,
  };
}

/// A `discriminator.mapping` value that points nowhere (C-4). M2 does not
/// resolve mapping values, so this rule does.
final class DiscriminatorMappingTarget extends NormalizerRule {
  /// Creates the rule.
  const DiscriminatorMappingTarget();

  @override
  String get name => 'discriminator-mapping-target';

  @override
  List<DiagnosticCode> get codes => const [.discriminatorMappingUnresolved];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final schemas = context.model.document.components?.schemas ?? const {};
    for (final discriminator in context.nodes<Discriminator>()) {
      for (final MapEntry(key: value, value: target)
          in discriminator.mapping.entries) {
        final exists = _isName(target)
            ? schemas.containsKey(target)
            : switch (RefTarget.parse(
                target,
                discriminator.location.document,
              )) {
                ResolvableRef(:final location) =>
                  context.rawAt(location) != null,
                BrokenRef() => false,
              };
        if (exists) continue;
        yield context.finding(
          .discriminatorMappingUnresolved,
          'discriminator.mapping "$value" points to "$target", which does '
          'not exist.',
          discriminator.location.child('mapping').child(value),
          fix:
              'Point it at an existing schema at the source; until then, '
              'override the mapping of this discriminator.',
        );
      }
    }
  }

  /// Whether [target] is a schema name rather than a reference: OpenAPI
  /// reads a value without `#`, `/` or `.` as a name in
  /// `components.schemas`.
  static bool _isName(String target) => !target.contains(RegExp('[#/.]'));

  @override
  String? hint(DiagnosticCode code, Preset preset) => switch (preset) {
    .fastapi =>
      'In FastAPI, give models unique names across the app; same-named '
          'models from different modules get renamed keys.',
    .springdoc =>
      'In springdoc, declare the mapping: @Schema(discriminatorProperty = '
          '"kind", discriminatorMapping = {@DiscriminatorMapping(value = '
          '"foo1", schema = Foo1.class)}).',
    _ => null,
  };
}

/// `*/*` as a media type (C-38): the client cannot pick a decoder.
final class WildcardMediaType extends NormalizerRule {
  /// Creates the rule.
  const WildcardMediaType();

  @override
  String get name => 'wildcard-media-type';

  @override
  List<DiagnosticCode> get codes => const [.wildcardMediaType];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final media in context.nodes<MediaType>()) {
      if (media.pointer.tokens.lastOrNull != '*/*') continue;
      yield context.finding(
        .wildcardMediaType,
        'The media type "*/*" does not say how the body is encoded, so the '
        'client cannot pick a decoder.',
        media.location,
        fix:
            'Declare the actual media type (usually application/json) at the '
            'source, or override the content type here.',
      );
    }
  }

  @override
  String? hint(DiagnosticCode code, Preset preset) => switch (preset) {
    .springdoc =>
      'In springdoc, set springdoc.default-produces-media-type='
          'application/json.',
    _ => null,
  };
}

/// A key in `components` with characters OpenAPI does not allow there
/// (C-32): only letters, digits, `.`, `-` and `_`.
final class ComponentKeyCharacters extends NormalizerRule {
  /// Creates the rule.
  const ComponentKeyCharacters();

  static final _key = RegExp(r'^[a-zA-Z0-9\.\-_]+$');

  @override
  String get name => 'component-key-characters';

  @override
  List<DiagnosticCode> get codes => const [.invalidComponentKey];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final components = context.model.document.components;
    if (components == null) return;
    for (final (section, keys) in [
      ('schemas', components.schemas.keys),
      ('responses', components.responses.keys),
      ('parameters', components.parameters.keys),
      ('examples', components.examples.keys),
      ('requestBodies', components.requestBodies.keys),
      ('headers', components.headers.keys),
      ('securitySchemes', components.securitySchemes.keys),
      ('pathItems', components.pathItems.keys),
      ('mediaTypes', components.mediaTypes.keys),
    ]) {
      for (final key in keys) {
        if (_key.hasMatch(key)) continue;
        yield context.finding(
          .invalidComponentKey,
          'The component name "$key" has characters OpenAPI does not allow '
          'in component keys (only letters, digits, ".", "-" and "_").',
          components.location.child(section).child(key),
          fix: 'Rename it at the source; type names are derived from it.',
        );
      }
    }
  }

  @override
  String? hint(DiagnosticCode code, Preset preset) => switch (preset) {
    .aspnet =>
      "With Swashbuckle, set CustomSchemaIds(t => t.FullName!.Replace('+', "
          "'.')).",
    .springdoc => 'In springdoc, name the schema with @Schema(name = "...").',
    _ => null,
  };
}
```

- [ ] **Step 4: Register**

In `lib/src/normalize/normalizer.dart` the rule imports between `import 'normalizer_rule.dart';` and `import 'spec_edit.dart';` must be as follows (sorted):

```dart
import 'rules/bool_required_to_array.dart';
import 'rules/drop_invalid_default.dart';
import 'rules/enum_rules.dart';
import 'rules/operation_id_rules.dart';
import 'rules/path_param_rules.dart';
import 'rules/reference_shape_rules.dart';
import 'rules/schema_shape_rules.dart';
```

and the `rules` list as follows:

```dart
  static final List<NormalizerRule> rules = List.unmodifiable(
    <NormalizerRule>[
      const BoolRequiredToArray(),
      const DropInvalidDefault(),
      const ArrayWithoutItems(),
      const DoubleArray(),
      const FormatOnArray(),
      const BinaryObject(),
      const ContradictoryObjectType(),
      const ExampleTypeMismatch(),
      const DedupeEnumValues(),
      const NullableEnumOneOf(),
      const DeclareMissingPathParams(),
      const PathParamNotInTemplate(),
      const MissingOperationId(),
      const DuplicateOperationId(),
      const DiscriminatorPropertyRequired(),
      const DiscriminatorMappingTarget(),
      const WildcardMediaType(),
      const ComponentKeyCharacters(),
    ],
  );
```

- [ ] **Step 5: Check**

```bash
dart analyze packages                                  # from the root: No issues found!
dart test                                              # from packages/typed_openapi
dart format lib test bin && dart format lib test bin   # second run: 0 changed
```

Expected: 315 tests.

- [ ] **Step 6: Commit**

```bash
git add packages/typed_openapi
git commit -m "feat(typed_openapi): report discriminator, media type and component key defects

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Rule catalogue, documentation, public API, corpus run

**Files:**
- Create: `packages/typed_openapi/test/normalize/rule_catalog_test.dart`
- Modify: `CLAUDE.md`, `packages/typed_openapi/CHANGELOG.md`, `packages/typed_openapi/README.md`, `packages/typed_openapi/README.ua.md`, `packages/typed_openapi/lib/typed_openapi.dart`

**Interfaces:**
- Consumes: everything from tasks 1–11.
- Produces: export of `Normalizer`, `NormalizedSpec`, `NormalizerRule`, `RuleContext`, `Finding`, `SpecEdit`, `EditOperation`, `SpecDocuments`; a catalogue test (unique kebab-case names, each code belongs to one rule, the full set of M3 codes, each framework preset has recipes, `generic` does not, rules do not report parser codes).

- [ ] **Step 1: Catalogue test**

Create `packages/typed_openapi/test/normalize/rule_catalog_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/config/project_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/normalize/normalizer.dart';

void main() {
  test('rule names are unique kebab-case, and each code has one rule', () {
    final names = Normalizer.rules.map((r) => r.name).toList();
    expect(names.toSet(), hasLength(names.length));
    for (final name in names) {
      expect(name, matches(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$')));
    }
    final codes = [for (final rule in Normalizer.rules) ...rule.codes];
    expect(codes.toSet(), hasLength(codes.length));
  });

  test('every M3 rule code is in the catalog, in its range', () {
    final ids = {
      for (final rule in Normalizer.rules)
        for (final code in rule.codes) code.id,
    };
    expect(ids, {
      'TOA106',
      'TOA201',
      'TOA202',
      'TOA203',
      'TOA204',
      'TOA205',
      'TOA206',
      'TOA207',
      'TOA208',
      'TOA211',
      'TOA301',
      'TOA303',
      'TOA401',
      'TOA402',
      'TOA501',
      'TOA502',
      'TOA503',
      'TOA504',
      'TOA601',
    });
  });

  test('each framework preset has recipes, generic has none', () {
    String? hintFor(Preset preset) => [
      for (final rule in Normalizer.rules)
        for (final code in rule.codes) ?rule.hint(code, preset),
    ].firstOrNull;
    for (final preset in [
      Preset.nestjs,
      Preset.fastapi,
      Preset.springdoc,
      Preset.aspnet,
    ]) {
      expect(hintFor(preset), isNotNull, reason: preset.name);
    }
    expect(hintFor(Preset.generic), isNull);
  });

  test('a code a rule reports is never one the parser reports', () {
    const parser = {
      DiagnosticCode.unknownKey,
      DiagnosticCode.invalidValue,
      DiagnosticCode.missingRequiredField,
    };
    for (final rule in Normalizer.rules) {
      expect(rule.codes.toSet().intersection(parser), isEmpty);
    }
  });
}
```

Run: `dart test test/normalize/rule_catalog_test.dart` — Expected: PASS (the test pins the state after tasks 5–11; FAIL if some task is missing).

- [ ] **Step 2: Documentation and export**

```diff
diff --git a/CLAUDE.md b/CLAUDE.md
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -36,29 +36,26 @@ All under `packages/typed_openapi/lib/src/`, one folder per stage:
   `Severity`, `JsonPointer`, `DiagnosticBag`, and the reporters
   (`DiagnosticReporter`, `TextReporter`, `JsonReporter`, `ReportFormat`).
 - `load/` - `SpecLoader` reads JSON/YAML into a `SpecDocument` (plain tree,
-  absolute file URI, source spans by JSON pointer, `valueAt(pointer)`);
-  `YamlEventGuard` runs package:yaml's own `Parser` over the text before
-  `loadYamlNode` (an iterative state machine: it builds no tree, hashes
-  nothing and cannot overflow the stack) and reads its events. It reports
-  collections nested deeper than 1000 levels (TOA007; the root collection is
-  level 0, keys and the one-pair mappings of `[k: v]` count) and an alias
-  inside a mapping key, directly or inside a collection used as the key
-  (TOA008): `loadYamlNode` hashes keys as trees, which is exponential for an
-  alias bomb. Aliases anywhere else (values, flow collections, `<<: *a`) and
-  `?` keys without aliases are fine. A syntax error stops the guard silently
-  and `loadYamlNode` reports it (TOA001). The scanner of package:yaml is
-  quadratic in the flow depth of a long line, so the guard first parses the
-  text up to where a crude bracket count passes the limit (quotes are not
-  considered: it only picks where to look first, the parser decides); text
-  that hides closing brackets in quotes is read in full at that cost.
-  Aliases in values still expand in
-  the conversion to a plain tree, so `SpecLoader` also limits that:
-  deeper than 1000 levels once aliases are expanded is TOA007; a budget of
-  `max(16000000, 20 * text length)` characters, where each converted node
-  (first visit or repeat) costs the length of its JSON pointer + 1 (the
-  pointer is what it keeps in `spans`), is TOA008 when spent (an alias bomb,
-  or very long keys); both return no document. `OpenApiVersionDetector`
-  reads the version.
+  absolute file URI, source spans by JSON pointer, `valueAt(pointer)`,
+  `withRoot`) through `YamlComposer`, which `ConfigLoader` uses too.
+  `load/yaml/` is a copy of package:yaml 3.1.4's scanner and parser (MIT,
+  see its `LICENSE` and `analysis_options.yaml` for the local changes: linear
+  cost on long flow lines, dart-lang/tools#2657; the scanner assert is a
+  syntax error; warnings go to a handler, never `print`). `YamlComposer`
+  builds the plain tree from the parser's events with an explicit stack, in
+  one pass: nesting deeper than 1000 levels (every collection the parser
+  opens, keys included, and every collection an alias expands to; the root
+  is level 0) is TOA007; a budget of `max(16000000, 20 * text length)`
+  characters, each built node (first visit or through an alias) costing its
+  JSON pointer length + 1, is TOA008 when spent; both return no document.
+  Scalar keys are their text (YAML Failsafe: `200:` is `"200"`); a null key
+  is TOA114 (warning), a collection key or an alias of one TOA113 (the entry
+  is dropped and never built). Duplicate keys are TOA002, last value wins
+  (error when YAML itself sees equal keys outside `.json`). Tags outside the
+  JSON Schema ruleset are TOA009 (the value is read as its text); parser
+  warnings are TOA015. A syntax error is returned to the caller, which
+  reports TOA001 (`.json` falls back to `jsonDecode` without positions).
+  `OpenApiVersionDetector` reads the version.
 - `model/` - the immutable typed model, a superset of OAS 3.0/3.1/3.2:
   `SpecNode` (every node has a `SpecLocation` = file URI + pointer, `x-`
   `extensions` and reported `unknownKeys`), `RefOr<T>` = `Ref<T>` | `Inline<T>`,
@@ -67,7 +64,9 @@ All under `packages/typed_openapi/lib/src/`, one folder per stage:
 - `parse/` - `OpenApiParser` (document, components, fragments for `$ref`
   targets), `OperationParser`, `SchemaParser`, all on `ObjectReader` (typed
   field access; wrong types and non-finite numbers -> TOA111, missing required
-  -> TOA112, unknown keys -> TOA110). Parsers record nodes, `$ref`s and
+  -> TOA112, unknown keys -> TOA110; a `$ref` where OAS accepts no Reference
+  Object -> TOA107, `$ref: #/...` emptied by a YAML comment -> TOA108, the
+  YAML merge key `<<` -> TOA109). Parsers record nodes, `$ref`s and
   version-specific constructs (`SpecFeature`) in a shared `SpecIndex`, which
   also remembers every location a parser has read (`visited`): a location is
   read once, so a later read (a `$ref` into a region and then one to its
@@ -77,10 +76,23 @@ All under `packages/typed_openapi/lib/src/`, one folder per stage:
   file name that is not UTF-8 after percent-decoding -> TOA100, a host ->
   TOA102), `SpecDocuments` loads other local files once by
   URI, `RefResolver` follows every `$ref` (parsing each on-demand target once)
-  and reports TOA100-TOA105, `SpecModel` answers `resolve`/`resolveSchema`;
-  `SpecReader` runs parse -> resolve -> dialect check.
+  and reports TOA100-TOA105, `SpecModel` answers `resolve`/`resolveSchema`
+  and lists `nodes` by location; `SpecReader` runs parse -> resolve ->
+  dialect check.
+- `normalize/` - `Normalizer` runs up to 3 passes of read (`SpecReader`) ->
+  rules -> edits: a `NormalizerRule` reads the model through a
+  `RuleContext` and returns `Finding`s (a diagnostic and, for a fix,
+  `SpecEdit`s: document URI + pointer + add/replace/remove); `TreeEditor`
+  applies edits copy-on-write to the plain trees and the model is read
+  again. Parser diagnostics of intermediate passes go to a scratch bag; the
+  report has the last pass's, every finding of a rule that fixed something,
+  and the last pass's findings. An edit overlapping an earlier rule's edit,
+  or left after 3 passes, is TOA800. Rules (`normalize/rules/`, in
+  `Normalizer.rules` order) never change the model and never read text;
+  presets only add framework recipes (`NormalizerRule.hint`). Config
+  `rules: {<name>: false}` in `defaults` or a client turns a rule off.
 - `config/` - `ConfigLoader`, `ProjectConfig`, `ClientConfig`, `Preset`.
-- `check/` - `SpecChecker`: config -> load -> version -> `SpecReader`.
+- `check/` - `SpecChecker`: config -> load -> version -> `Normalizer`.
 - `cli/` - `TypedOpenApiCli` (`cli.dart`, owns the `CommandRunner` and maps
   usage errors to exit code 64) and `CheckCommand` (`check_command.dart`,
   options `--config/-c` and `--format`, client names as positional
@@ -92,13 +104,17 @@ All under `packages/typed_openapi/lib/src/`, one folder per stage:
   `DiagnosticCode`, `JsonPointer`, `Severity` and the reporters), the loader
   (`SpecLoader`, `SpecDocument`, `OpenApiVersion`, `OpenApiVersionDetector`),
   the whole `model/` (`SpecNode`, `SpecLocation`, `RefOr`, `Ref`, `Inline`,
-  `RefKind`, `OpenApiDocument` and the other OAS objects) and the entry points
-  `SpecReader` and `SpecModel`. Not exported: `CheckCommand`, the internals of
-  `parse/` (`OpenApiParser`, `OperationParser`, `SchemaParser`, `ObjectReader`,
-  `ParseContext`, `SpecIndex`, `DialectChecker`) and `resolve/` (`RefTarget`,
-  `RefResolver`, `SpecDocuments`), and `YamlEventGuard`.
-
-Data flows loader -> parser -> resolver -> checker, every stage writing
+  `RefKind`, `OpenApiDocument` and the other OAS objects), the entry points
+  `SpecReader`, `SpecModel` and `SpecDocuments`, and the normalizer
+  (`Normalizer`, `NormalizedSpec`, `NormalizerRule`, `RuleContext`,
+  `Finding`, `SpecEdit`, `EditOperation`). Not exported: `CheckCommand`, the
+  internals of `parse/` (`OpenApiParser`, `OperationParser`, `SchemaParser`,
+  `ObjectReader`, `ParseContext`, `SpecIndex`, `DialectChecker`), `resolve/`
+  (`RefTarget`, `RefResolver`), `normalize/` (`TreeEditor`, the rule
+  classes), `YamlComposer` and `load/yaml/`.
+
+Data flows loader -> parser -> resolver -> normalizer -> checker, every stage
+writing
 problems into one `DiagnosticBag`; reporters read the bag at the end.
 
 Rules of the pipeline:
diff --git a/packages/typed_openapi/CHANGELOG.md b/packages/typed_openapi/CHANGELOG.md
--- a/packages/typed_openapi/CHANGELOG.md
+++ b/packages/typed_openapi/CHANGELOG.md
@@ -16,17 +16,39 @@
 - The dialect is detected by content: 3.1 constructs in a 3.0 document
   (TOA020), `nullable` in 3.1+ (TOA021), 3.2 constructs in older documents
   (TOA022).
-- Loading: a guard reads package:yaml's own parser events before the document
-  is loaded. Nesting deeper than 1000 levels (exact, keys and `[k: v]` pairs
-  included) is reported (TOA007) instead of crashing, and so is an alias
-  inside a mapping key (TOA008), which the YAML parser would expand
-  exponentially before any check runs. Aliases in values and flow
-  collections are fine. Once aliases are expanded, an alias bomb or very
-  long keys (the JSON pointers of all nodes add up to more than
-  `max(16000000, 20 * text length)` characters) are reported (TOA008) instead
-  of hanging or exhausting memory, and expansion deeper than 1000 levels is
-  TOA007. YAML keys such as `1` and `"1"` that merge into one JSON key are
-  reported (TOA002); a directory given as the spec or the config is reported
-  as such. The yaml dependency is pinned to `>=3.1.4 <3.2.0` for the guard.
+- Loading: YAML and JSON are read by `YamlComposer` from the events of a
+  copy of package:yaml's parser, in one iterative pass. Nesting deeper than
+  1000 levels, also once aliases are expanded, is TOA007; an alias bomb or
+  very long keys (JSON pointers of all built nodes above
+  `max(16000000, 20 * text length)` characters) are TOA008. A collection as a
+  mapping key is TOA113 and is never built, so a key cannot hide an alias
+  bomb; a null key is TOA114. Keys are their text (`200:` is `"200"`); keys
+  that are one JSON key are TOA002, the last value wins. YAML tags outside
+  the JSON Schema ruleset (`!!timestamp`, `!!binary`, `!custom`) are TOA009
+  and the value is read as text; parser warnings are TOA015. The copied
+  scanner is linear on long flow lines (dart-lang/tools#2657), so hostile
+  one-line files are rejected in moments. A directory given as the spec or
+  the config is reported as such; package:yaml is no longer a dependency.
+- `$ref` where OpenAPI does not accept a Reference Object (an operation,
+  `description`) is TOA107 with a hint to bundle the spec (`redocly bundle`);
+  `$ref: #/...` without quotes, which YAML reads as a comment, is TOA108; the
+  YAML merge key `<<` is TOA109.
+- Normalizer: `check` runs named rules over the model and applies the fixes
+  that follow from the spec or the protocol, reading the spec again (at most
+  3 passes; a fix that cannot be applied is TOA800). Fixes:
+  `bool-required-to-array` (TOA201), `drop-invalid-default` (TOA211),
+  `dedupe-enum-values` (TOA301), `declare-missing-path-params` (TOA501).
+  Diagnostics: arrays without `items` in 3.0 (TOA202), double arrays (TOA203),
+  `format` on an array (TOA204), binary objects (TOA205), `type: object`
+  against non-object branches (TOA206), examples of the wrong type (TOA207),
+  nullable enums through `oneOf` (TOA303), discriminator property not
+  required (TOA401), unresolved discriminator mapping (TOA402), path
+  parameters not in the template (TOA502), missing and duplicate
+  `operationId` (TOA503, TOA504), `*/*` media types (TOA601), component keys
+  with invalid characters (TOA106). Presets add framework recipes to the
+  hints; `rules: {<name>: false}` in `defaults` or a client turns a rule off
+  (unknown names are TOA903).
+- Programmatic API: `Normalizer`, `NormalizedSpec`, `NormalizerRule`,
+  `RuleContext`, `Finding`, `SpecEdit`, `EditOperation`, `SpecDocuments`.
 - A region of a spec that several `$ref`s, enclosing nodes or clients reach is
   read once, and an identical diagnostic is reported once.
diff --git a/packages/typed_openapi/README.md b/packages/typed_openapi/README.md
--- a/packages/typed_openapi/README.md
+++ b/packages/typed_openapi/README.md
@@ -34,6 +34,16 @@ dart run typed_openapi check --format json
 `check` reads the whole spec, follows its `$ref`s (also into other local
 files) and reports unknown keys, wrong value types, broken or looping
 references and constructs that the declared OpenAPI version does not have.
+Then it runs the normalizer: named rules fix the defects whose fix follows
+from the spec or from HTTP (`required: true` on a property, repeated enum
+values, undeclared path parameters, defaults of the wrong type) and report
+the rest with what to change at the source. A `preset` adds the recipe for
+your framework to those hints. Turn a rule off per client or in `defaults`:
+
+```yaml
+defaults:
+  rules: {dedupe-enum-values: false}
+```
 
 Every finding has a stable code (`TOA011`), a JSON pointer into the spec and,
 for files the parser could position, a line and column. Exit code `1` means
diff --git a/packages/typed_openapi/README.ua.md b/packages/typed_openapi/README.ua.md
--- a/packages/typed_openapi/README.ua.md
+++ b/packages/typed_openapi/README.ua.md
@@ -35,6 +35,16 @@ dart run typed_openapi check --format json
 `check` reads the whole spec, follows its `$ref`s (including into other local
 files) and reports unknown keys, values of the wrong type, broken or
 circular references, and constructs that are absent from the declared OpenAPI version.
+Then the normalizer runs: named rules fix defects, fixes
+that follow from the spec or from HTTP (`required: true` on a property,
+repeated enum values, undeclared path parameters, a `default` of the wrong type),
+and the rest is reported with what to change in the source. `preset` adds to these hints
+a recipe for your framework. A rule is turned off in a client or in `defaults`:
+
+```yaml
+defaults:
+  rules: {dedupe-enum-values: false}
+```
 
 Each finding has a stable code (`TOA011`) and a JSON pointer to the place in
 the spec and, if the parser could determine the position, the line and column. The code
diff --git a/packages/typed_openapi/lib/typed_openapi.dart b/packages/typed_openapi/lib/typed_openapi.dart
--- a/packages/typed_openapi/lib/typed_openapi.dart
+++ b/packages/typed_openapi/lib/typed_openapi.dart
@@ -2,7 +2,8 @@
 ///
 /// The programmatic API mirrors the CLI: load a config, check specs, report
 /// diagnostics. [SpecReader] reads a loaded spec into the typed model
-/// ([SpecModel]) with its `$ref`s resolved.
+/// ([SpecModel]) with its `$ref`s resolved; [Normalizer] runs the named
+/// rules over it and applies their fixes.
 library;
 
 export 'src/check/spec_checker.dart' show SpecChecker;
@@ -49,5 +50,10 @@ export 'src/model/security.dart'
         SecuritySchemeType;
 export 'src/model/spec_node.dart'
     show Inline, Ref, RefKind, RefOr, SpecLocation, SpecNode;
+export 'src/normalize/normalizer.dart' show NormalizedSpec, Normalizer;
+export 'src/normalize/normalizer_rule.dart'
+    show Finding, NormalizerRule, RuleContext;
+export 'src/normalize/spec_edit.dart' show EditOperation, SpecEdit;
+export 'src/resolve/spec_documents.dart' show SpecDocuments;
 export 'src/resolve/spec_model.dart' show SpecModel;
 export 'src/resolve/spec_reader.dart' show SpecReader;
```

- [ ] **Step 3: Check**

```bash
dart analyze packages                                  # from the root: No issues found!
dart test                                              # from packages/typed_openapi
dart format lib test bin && dart format lib test bin   # second run: 0 changed
```

```bash
cd packages/typed_openapi && dart pub publish --dry-run   # Package has 0 warnings (after the commit)
```

Expected: 319 tests.

- [ ] **Step 4: Corpus run (smoke)**

```bash
cd packages/typed_openapi
dart run bin/typed_openapi.dart check -c <path to the research/08 corpus>/typed_openapi.yaml --format json > ../../m3-check.json; echo "exit $?"
```

Expected: exit 1. Summary per spec and code (state while the plan was written):

| Spec | Diagnostics |
|---|---|
| Artemis | TOA009 ×2, TOA110 ×1, TOA401 ×1 — now read (in M2 — TOA001) |
| DigitalOcean | TOA107 ×793 (in M2 — TOA110 ×791, TOA111 ×2) |
| Ditto | TOA202 ×2, TOA207 ×7, TOA503 ×131 |
| Google Maps | TOA208 ×1 |
| Grace (source and bundle) | TOA108 ×13, TOA111 ×19, TOA110 ×4, TOA021 ×2 |
| Jellyfin | TOA401 ×3 |
| Medusa | TOA208 ×2 |
| OpenAI | TOA021 ×1, TOA110 ×1, TOA207 ×7, TOA401 ×7, TOA503 ×30, TOA601 ×1 |
| Tambo | TOA207 ×2 |
| Stripe, Discord, Airflow, EFGS | — |

Delete `m3-check.json` after review. Move the table to research/08 in a separate `docs:` commit once the user confirms it.

- [ ] **Step 5: Commit**

```bash
git add packages/typed_openapi
git commit -m "docs(typed_openapi): document the normalizer and export its API

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Self-check

- **Spec coverage.** Decision 2 (tags — task 1; `$ref` outside OAS — task 3), 3 (rules over the model, `SpecEdit`, ≤ 3 passes — task 4), 4 (parser diagnostics from the last pass — task 4), 5 (interpretation for Dart — outside M3; rules only fix defects and diagnose), 6 (own composer: depth, budget, duplicates, tags, non-scalar keys; the event-based check and the converter go away — tasks 1–2), 7 (presets only refine hints — `NormalizerRule.hint`; turning rules off and TOA903 — task 6). The "Fixes" table: `bool-required-to-array`, `drop-invalid-default` — task 5; `dedupe-enum-values` — 8; `declare-missing-path-params` — 9. The "Diagnostic only" table: TOA502 — 9; TOA503, TOA504 — 10; TOA202–TOA207 (and TOA208) — 7; TOA303 — 8; TOA401, TOA402, TOA601, TOA106 — 11; TOA107, TOA108 — 3; TOA009 and the non-scalar key (TOA113) — 1. "Moved from M2": tags, `$ref` outside OAS, `$ref` without quotes, merge key `<<`, asserts and the single depth limit of the composer — tasks 1–3.
- **Placeholders.** Each task contains all the code (new files in full, changes as diffs for `git apply` or as blocks with the exact place of insertion); the path to the research/08 corpus is the only thing the implementer fills in themselves (the corpus is not in the repository).
- **Type consistency.** `SpecLocation.child`, `RuleContext.finding/rawObject`, `SpecEdit.add/replace/remove`, `Normalizer(bag, rules:, disabled:, preset:)`, `ClientConfig.disabledRules`, `NormalizerFixture.of/pointersOf` — the same in tasks and tests; reproduction from `main` confirms it.

