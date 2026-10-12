# Plan M2: spec model and `$ref`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `typed_openapi check` reads every spec into an immutable typed model (a superset of OAS 3.0/3.1/3.2), resolves all `$ref` within the document and between local files, detects the dialect from the content, and reports unknown keys, values of the wrong type, missing required fields, and broken, remote and circular references. At the same time it closes the M1 review findings about loading (deep nesting, keys `1`/`"1"`, a directory instead of a file, the order of TOA005/TOA003, `.json` with a duplicate and a syntax error).

**Architecture:** Three new layers in `packages/typed_openapi/lib/src/` above the existing `load/`: `model/` — immutable nodes (`SpecNode` with `SpecLocation` = absolute file URI + JSON pointer, `x-` extensions and unknown keys; `RefOr<T>` = `Ref<T>` | `Inline<T>`; `Schema` = `BooleanSchema` | `SchemaObject`, where `$ref` is a keyword); `parse/` — `OpenApiParser`, `OperationParser`, `SchemaParser` on top of `ObjectReader`, which throw nothing but write to `DiagnosticBag` and to the shared `SpecIndex` (all nodes, all `$ref`s, all version-specific constructs); `resolve/` — `RefTarget` (parsing of a `$ref` value), `SpecDocuments` (other local files, each once), `RefResolver` (the target of every `$ref`, the kind of target, cycles) and `SpecModel` (the result of `resolve`/`resolveSchema`). `SpecReader` connects parse → resolve → `DialectChecker`; `SpecChecker` calls it after version detection.

**Tech Stack:** Dart `>=3.10.0 <4.0.0`, pure Dart; the existing dependencies `yaml`, `source_span`, `path`, `args`, `io`; tests on `package:test`. No new dependencies.

**Spec:** [docs/requirements.md](../../requirements.md) — R0.1, R1.2, R1.4, R2.1 (part), R2.2, R2.5, R13.1. Versions and dialects — [research/06 §A](../../research/06-spec-versions-and-defects.md) (A.1–A.3); the catalog of defects and code ranges — [research/06 §C](../../research/06-spec-versions-and-defects.md) (C.0, C-2, C-3, C-16, C-17, C-47); parser architecture — [research/03 §4](../../research/03-tonik-swagger-to-dart-space-gen.md) and the lesson of space_gen #358 (§3.5). Where the stage fits — [roadmap.md](../../roadmap.md), section "Moved from M1". Code rules — [CLAUDE.md](../../../CLAUDE.md) and [CONTRIBUTING.md](../../../CONTRIBUTING.md).

## Global Constraints

- SDK `>=3.10.0 <4.0.0`; both packages are pure Dart without Flutter. Primary constructors (Dart 3.13) are not used.
- Dart 3.10 features are used actively: dot shorthands wherever the context type is known (`.invalidRef`, `.v31`, `kind == .mediaType`), null-aware collection elements (`name: ?read(...)`), switch expressions and patterns, records (`(Object?,)?` for "a value that may be `null`"), class modifiers (`final`, `sealed`). In tests, the arguments of `expect(...)` are written with full names (`DiagnosticCode.invalidRef`).
- OOP: no top-level functions, except `main` in `bin/` and in tests. Components that report problems receive a `DiagnosticBag` through the constructor (`SpecReader(bag)`, `RefResolver(bag)`, `DialectChecker(bag)`; parsers receive it through `ParseContext`).
- R2.5: errors in input data are never thrown as exceptions; they go into the `DiagnosticBag`, and the rest of the document is read on. `StackOverflowError` is not caught (lint `avoid_catching_errors`): input that is too deep is filtered out before the recursive parse.
- R2.2: every new problem has a `TOAnnn` code in `DiagnosticCode` with a doc comment, a kebab-case slug, a default severity, a file, a JSON pointer and, when known, a position. The ranges come from research/06 §C.0: `0xx` document and dialect, `1xx` references and structure.
- R13.1: the result is deterministic: nodes and diagnostics follow the document order, cycles and sets are sorted (`SpecLocation.compareTo`), and the report is sorted by `DiagnosticBag.sorted`.
- The model is immutable: fields are `final`, collections are `List.unmodifiable`/`Map.unmodifiable` or `const`.
- A node's identity is the file's absolute URI + JSON pointer (`SpecLocation`), not the pointer alone (space_gen #358).
- Lints come from the root `analysis_options.yaml` (`public_member_api_docs`, `sort_constructors_first`, `prefer_final_locals`, `require_trailing_commas`, `use_raw_strings`, `avoid_catching_errors` and others). `dart analyze packages` from the root prints `No issues found!`; `dart format` with `trailing_commas: preserve` changes 0 files.
- No dependency on `analyzer`. Tests do not touch the network; temporary files go only through `test/helpers/temp_dir.dart`. Real company specifications never go into the repository; tests use invented fragments.
- The commands `dart test`, `dart format`, `dart pub publish --dry-run` run from `packages/typed_openapi`; `dart pub get`, `dart analyze packages` and all `git` commands run from the root.
- Every commit ends with a `Co-Authored-By` line for the model that performs the task (in the examples below — `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`).

## Decisions made

1. **Scope of one plan.** M2 is not split into M2a/M2b: 12 tasks, each with its own test cycle; after Task 7 the model is already read, after Task 11 it is resolved, and Task 12 enables everything in `check`. A split would give M2a with no result visible to the user.
2. **Lossless.** The raw `SpecDocument` tree stays next to the model and gets `uri` and `valueAt(pointer)`. The model types everything that code generation needs (the list is in the classes of `model/`). Keys that the spec defines but the model does not yet type (`externalDocs`, `xml`, `links`, `callbacks`, `contact`, `license`, `termsOfService`) are accepted silently and are available in `SpecDocument` by the node's pointer. JSON Schema 2020-12 keywords without a typed field (`$defs`, `if`/`then`/`else`, `patternProperties`, `unevaluated*` …) are kept raw in `SchemaObject.otherKeywords`. `x-` keys go into the `extensions` of each node. Keys of the Paths Object and Responses Object that start with `x-` do not become paths or statuses (they stay in the raw tree).
3. **Unknown keys** (in none of 3.0, 3.1 or 3.2, and not `x-`) are kept in the node's `unknownKeys` and give `TOA110 unknown-key` at **warning** level: this catches typos (`nmae`) and leftovers of Swagger 2 (`type` in a parameter), and on a real NestJS spec (734 operations, 1434 schemas) there are 0 such keys, so there is no noise. A Reference Object cannot be extended, so all of its keys except `$ref`/`summary`/`description` are unknown.
4. **Wrong value type** (`required: true` instead of a list, `minLength: -1`, `in: body`) — `TOA111 invalid-value`, **warning**: the field is read as missing, and the rest of the node is read. This is exactly where M3 will put the `bool-required-to-array` rule (C-1, C-49): it will fix the raw tree before parsing, and TOA111 will disappear there. An explicit `null` in a typed field is also TOA111; in the fields of "any value" (`default`, `const`, `example`, `enum`) `null` is a normal value, so they are stored as a record `(Object?,)?`.
5. **Required fields** — `TOA112 missing-required-field`, **warning**, only for fields required in all three versions: `info`, `info.title`, `info.version`, the `name` and `in` of a parameter, the `type` of a security scheme (and `name`/`scheme`/`flows`/`openIdConnectUrl` depending on its type), the `url` of a server, the `default` of a server variable, the `name` of a tag, the `propertyName` of a discriminator, the `content` of a request body. Version-dependent requirements (`paths` and `responses` in 3.0, the `description` of a response before 3.2) are not checked: for 3.2 documents this is noise, and it is the normalizer's job (M3). In the model such fields are nullable.
6. **Dialect by content.** The parser reads every construct of any version and only marks the version-specific ones (`SpecFeature`: `since`/`until`). `DialectChecker` compares them with the declared version: 3.1 constructs in 3.0 — `TOA020` (warning, SG001), `nullable` in 3.1+ — `TOA021` (warning, SG002), 3.2 constructs in older versions — `TOA022` (info, SG003). To avoid noise, each construct is reported **once** — at the place of its first use, with the count of places in the text. Nothing is converted: `nullable` and `type: [T, "null"]` stay in the model as written; normalization is M3.
7. **`$ref` in a schema** is a keyword (`SchemaObject.ref`); sibling keys are kept (3.1 applies them together with `$ref`). For other nodes — `RefOr<T>`: `Ref<T>` (a Reference Object with `summary`/`description`) or `Inline<T>`.
8. **Resolver.** All `$ref`s are recorded during parsing (`RefUse`: where, what, and which kind of target is expected). `RefResolver` goes through them as a list (a new file adds its own `$ref`s to the end of the list); the target is identified by a `SpecLocation`. A target that the main parse did not read (another file, `x-shared`, `$defs`) is parsed on demand as the expected kind of node. Other files are read once by `SpecLoader` (`SpecDocuments`); in diagnostics they are named relative to the displayed path of the root document. Remote URIs (http, https, urn) are not read (R1.1) — `TOA102`. Empty, truncated (`#/components/schemas/`), "to a whole section" (`#/components/schemas`) and non-pointer fragments (`#Pet`, `$anchor`) — `TOA100` (SG101). A target that does not exist, or a file that does not exist — `TOA101` (SG102). A target of another kind (parameter → schema) — `TOA104`. `$id` in a schema and `$self` in a document would change the base URI — the model stores them, the resolver does not apply them and reports this (`TOA105`).
9. **Cycles.** A cycle is only a chain of references that never reaches a node without `$ref` (`A → B → A`, `A → A`). A recursive schema (`Node.children.items → Node`) is legal. Each cycle is reported once (`TOA103`), at the place of the participant that is smallest by `SpecLocation`, with the chain in the message; `SpecModel.resolve` returns `null` for such references.
10. **Deep nesting.** `package:yaml` parses nesting recursively and fails with `StackOverflowError` somewhere around 3 500 levels (measured in `dart test`). Before parsing, `NestingScanner` estimates the depth from the top (brackets outside strings and comments; for block YAML — the indentation and `- ` markers) and rejects text deeper than 1000 levels (`TOA007`). The limit is sufficient: real specifications have dozens of levels, and the model parser has been checked on a 996-level schema. The same guard is in `ConfigLoader` (`TOA902`).
11. **Leftovers from the M1 review.** YAML keys that become the same JSON key (`1` and `"1"`) — `TOA002` warning; the last value wins (as in JSON). A directory instead of a file: for a specification — `TOA006` ("is a directory"), for a config — `TOA902`. `TOA005` ("without positions") is reported only when the document is actually returned, that is, after the root check (`TOA003`). A `.json` file with a duplicate and a syntax error gives `TOA002` (warning) and `TOA001` (error) with the position from `jsonDecode`.
12. **`check` and the version.** The model is read only for documents whose version is determined (Swagger 2 and a document without `openapi` give only M1 diagnostics). Hence the change in the existing tests as well: minimal fixtures with `openapi: 3.x` get `info`, because without it there is now a `TOA112`.

## New diagnostic codes

| Code | Slug | Level | When | Research |
|---|---|---|---|---|
| TOA007 | `nesting-too-deep` | error | Text deeper than 1000 levels | — |
| TOA020 | `openapi-3-1-in-3-0` | warning | 3.1 / JSON Schema 2020-12 in a 3.0 document | SG001, C-17 |
| TOA021 | `nullable-after-3-0` | warning | `nullable` in a 3.1+ document | SG002, C-16 |
| TOA022 | `openapi-3-2-in-older` | info | 3.2 constructs in a 3.0/3.1 document | SG003, C-47 |
| TOA100 | `invalid-ref` | error | Empty, truncated, non-pointer `$ref`, or a `$ref` to a whole section | SG101, C-2 |
| TOA101 | `unresolved-ref` | error | The target or the file does not exist | SG102, C-3 |
| TOA102 | `remote-ref` | error | `$ref` to http(s) or another non-file URI | R1.1 |
| TOA103 | `ref-cycle` | error | Reference cycle without a definition | R1.2 |
| TOA104 | `ref-kind-mismatch` | error | Target of another kind | — |
| TOA105 | `ref-base-ignored` | warning | `$id` in a schema or `$self` in a document | A.1 #10, A.2 #12 |
| TOA110 | `unknown-key` | warning | Key that exists in no version | A.3 item 4 |
| TOA111 | `invalid-value` | warning | Wrong JSON type or invalid value | C-1, C-49 |
| TOA112 | `missing-required-field` | warning | Required field is missing | — |

Existing codes get new cases: `TOA002` (merged YAML keys), `TOA006` (a directory instead of a specification), `TOA902` (a directory instead of a config, a config that is too deep).

## What is deliberately not part of M2

- Any fixing of defects (normalizing `nullable`, `required: bool` → list, `examples` by version, an empty `$ref` → JSON value) — the normalizer rules of M3. M2 only reads and reports.
- Name checks: `security` → declared security schemes, `tag.parent` → a declared tag, values of `discriminator.mapping` (C-4), path parameters against the path template (C-6, C-7), keys of components by regex (C-32) — M3.
- Changing the base URI through `$id`, `$self`, `$anchor`, `$dynamicRef` — only the diagnostic `TOA105`/`TOA100`; it will be needed when real specifications require it.
- Loading remote `$ref`s — together with a local snapshot and a lock file (M12).
- Merging keys next to `$ref` (3.1) and `allOf` — the semantic IR (M6). `SpecModel.resolveSchema` returns the final target without merging.

## File structure

All paths are relative to `packages/typed_openapi/`, unless stated otherwise.

| File | Responsibility | Task |
|---|---|---|
| `lib/src/load/spec_document.dart` | + `uri`, `valueAt(pointer)` | 1 |
| `lib/src/load/spec_loader.dart` | directory, merged keys, TOA005 order, JSON fallback, `uri`, depth guard | 1, 2 |
| `lib/src/config/config_loader.dart` | directory, depth guard | 1, 2 |
| `lib/src/load/nesting_scanner.dart` | `NestingScanner` — depth estimate without parsing | 2 |
| `lib/src/diagnostics/diagnostic_code.dart` | new codes | 2, 4, 5, 8–11 |
| `lib/src/model/spec_node.dart` | `SpecLocation`, `SpecNode`, `RefKind`, `RefOr`, `Ref`, `Inline` | 3 |
| `lib/src/parse/spec_feature.dart` | `SpecFeature` — version-specific constructs | 4 |
| `lib/src/parse/parse_context.dart` | `RefUse`, `FeatureUse`, `SpecIndex`, `ParseContext` | 4 |
| `lib/src/parse/object_reader.dart` | `ObjectReader` — typed field reading, unknown keys | 4 |
| `lib/src/model/schema.dart` | `Schema`, `BooleanSchema`, `SchemaObject`, `SchemaType`, `Discriminator` | 5 |
| `lib/src/parse/schema_parser.dart` | `SchemaParser` | 5 |
| `lib/src/model/operation.dart` | `PathItem`, `Operation`, `Parameter`, `RequestBody`, `Response`, `Header`, `MediaType`, `Encoding`, `Example`, `Server`, `ServerVariable`, `SecurityRequirement` and the enums | 6 |
| `lib/src/parse/operation_parser.dart` | `OperationParser` | 6 |
| `lib/src/model/security.dart` | `SecurityScheme`, `OAuthFlows`, `OAuthFlow` and the enums | 7 |
| `lib/src/model/document.dart` | `OpenApiDocument`, `Info`, `Tag`, `Components` | 7 |
| `lib/src/parse/openapi_parser.dart` | `OpenApiParser` — document and fragments for `$ref` targets | 7 |
| `lib/src/load/openapi_version.dart` | + `OpenApiVersion.label` | 8 |
| `lib/src/parse/dialect_checker.dart` | `DialectChecker` | 8 |
| `lib/src/resolve/ref_target.dart` | `RefTarget`, `ResolvableRef`, `BrokenRef` | 9 |
| `lib/src/resolve/spec_documents.dart` | `SpecDocuments` — specification files by URI | 10 |
| `lib/src/resolve/spec_model.dart` | `SpecModel` | 10 |
| `lib/src/resolve/ref_resolver.dart` | `RefResolver` (+ cycles in Task 11) | 10, 11 |
| `lib/src/resolve/spec_reader.dart` | `SpecReader` — parse → resolve → dialect | 12 |
| `lib/src/check/spec_checker.dart` | calls `SpecReader` | 12 |
| `lib/typed_openapi.dart` | export of the model, `SpecReader`, `SpecModel` | 12 |
| `CHANGELOG.md`, `README.md`, `README.ua.md`, `CLAUDE.md` (root) | documentation | 12 |
| `test/helpers/spec_fixture.dart` | `SpecFixture` — document + parse context for tests | 4 |
| `test/load/nesting_scanner_test.dart`, `test/load/spec_document_test.dart`, `test/model/spec_node_test.dart`, `test/parse/*_test.dart`, `test/resolve/*_test.dart` | new tests | 1–12 |

## Interfaces between tasks

```dart
// load (Tasks 1-2)
final class SpecDocument { String file; Uri uri; Map<String, Object?> root;
  bool hasPositions; SourceSpan? spanOf(JsonPointer); (Object?,)? valueAt(JsonPointer); }
SpecDocument? SpecLoader.parse(String text, String file, {Uri? uri});   // uri defaults to file in cwd
final class NestingScanner { static const maxDepth = 1000; int? findTooDeep(String text, {int limit}); }

// model (Tasks 3, 5-7)
final class SpecLocation implements Comparable<SpecLocation> { Uri document; JsonPointer pointer; }
abstract class SpecNode { SpecLocation location; Map<String, Object?> extensions;
  Map<String, Object?> unknownKeys; JsonPointer get pointer; }
enum RefKind { schema, response, parameter, example, requestBody, header, securityScheme,
  pathItem, mediaType; String noun; String get withArticle; }
sealed class RefOr<T extends SpecNode>;  // Ref<T> (extends SpecNode: ref, kind, summary,
                                         // description) | Inline<T> (value)
sealed class Schema extends SpecNode;    // BooleanSchema(value) | SchemaObject(ref, types, ...)
final class OpenApiDocument extends SpecNode { OpenApiVersion? version; Info? info;
  Map<String, RefOr<PathItem>> paths; Components? components; ... }

// parse (Tasks 4-8)
final class SpecIndex { Map<SpecLocation, SpecNode> nodes; List<RefUse> refs; List<FeatureUse> features; }
final class ParseContext { ParseContext(DiagnosticBag, SpecDocument, SpecIndex);
  SpecLocation locate(JsonPointer); void report(DiagnosticCode, String, JsonPointer, {String? fix});
  void note(SpecFeature, JsonPointer); T register<T extends SpecNode>(T);
  ObjectReader? reader(Object? raw, JsonPointer, String what);
  RefOr<T>? refOr<T extends SpecNode>(Object? raw, JsonPointer, RefKind, T Function(ObjectReader)); }
final class ObjectReader { string, requiredString, boolean, number, count, choice, requiredChoice,
  strings, rawList, list, map, stringMap, object, requiredObject, value, accept, has, keys,
  extensions, unknownKeys({bool reportExtensions}) }
final class SchemaParser { Schema? parse(Object? raw, JsonPointer, {bool booleanIsClassic}); }
final class OperationParser { pathItem, parameter, requestBody, response, header, mediaType,
  example: RefOr<T>? Function(Object? raw, JsonPointer); server; securityRequirement; }
final class OpenApiParser { factory OpenApiParser(DiagnosticBag, SpecDocument, SpecIndex);
  OpenApiDocument parse(OpenApiVersion?); SpecNode? parseFragment(JsonPointer, RefKind); }
final class DialectChecker { void check(List<FeatureUse>, OpenApiVersion); }

// resolve (Tasks 9-12)
sealed class RefTarget { factory RefTarget.parse(String ref, Uri base); }  // ResolvableRef(location) | BrokenRef(code, reason, fix)
final class SpecDocuments { SpecDocuments(SpecLoader, SpecDocument root);
  SpecDocument? operator [](Uri); String displayPath(Uri); }
final class RefResolver { SpecModel resolve(OpenApiDocument, SpecIndex, SpecDocuments); }
final class SpecModel { OpenApiDocument document; SpecNode? nodeAt(SpecLocation);
  SpecLocation? targetOf(SpecLocation site); T? resolve<T extends SpecNode>(RefOr<T>);
  Schema? resolveSchema(Schema); }
final class SpecReader { SpecModel read(SpecDocument, OpenApiVersion); }
```

Tests before starting: 51; after all tasks: 132. `dart analyze packages` reports no issues, and `dart pub publish --dry-run` reports no warnings.

---

### Task 1: Loading: leftovers of the M1 review and the document URI

**Files:**
- Create: `packages/typed_openapi/test/load/spec_document_test.dart`
- Modify: `packages/typed_openapi/lib/src/load/spec_document.dart`
- Modify: `packages/typed_openapi/lib/src/load/spec_loader.dart`
- Modify: `packages/typed_openapi/lib/src/config/config_loader.dart`
- Modify: `packages/typed_openapi/test/load/spec_loader_test.dart`
- Modify: `packages/typed_openapi/test/config/config_loader_test.dart`

**Interfaces:**
- Consumes: `SpecLoader`, `ConfigLoader`, `DiagnosticBag`, `DiagnosticCode`, `JsonPointer` (M1).
- Produces: `SpecDocument.uri` (`Uri`, absolute, normalized), `(Object?,)? SpecDocument.valueAt(JsonPointer)`, `SpecLoader.parse(String text, String file, {Uri? uri})`; `SpecLoader.load` passes the `uri` of the file.

Behaviour the tests pin down:
- `SpecDocument` knows the absolute `uri` of its file (the base for relative `$ref`s) and returns a node by pointer: `valueAt` returns a record `(value,)` to tell an explicit `null` from a missing node; list indexes are only decimal numbers without leading zeros.
- YAML keys `200` and `"200"` in one object — warning `TOA002` with the pointer and the position of the second key; the last value wins.
- A `.json` file with a duplicate and a syntax error — `TOA002` warning and `TOA001` error with the position from `jsonDecode`; without a duplicate the M1 behaviour does not change.
- A `.json` whose root is not an object — `TOA003`, and no longer `TOA005`.
- A directory instead of a file: for a specification — `TOA006` "is a directory", for a config — `TOA902`.

- [ ] **Step 1: Write a test that fails**

Create `packages/typed_openapi/test/load/spec_document_test.dart`:

```dart
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';

import '../helpers/temp_dir.dart';

void main() {
  final doc = SpecLoader(DiagnosticBag()).parse(
    'paths:\n  /a~b:\n    get: {tags: [x, y]}\n  /c: null\n',
    'api.yaml',
  )!;

  test('finds values by pointer, through objects and lists', () {
    final get = JsonPointer.root.child('paths').child('/a~b').child('get');
    expect(doc.valueAt(get.child('tags').child(1)), ('y',));
    expect(doc.valueAt(JsonPointer.root)?.$1, same(doc.root));
  });

  test('tells an explicit null from a missing node', () {
    final paths = JsonPointer.root.child('paths');
    expect(doc.valueAt(paths.child('/c')), (null,));
    expect(doc.valueAt(paths.child('/d')), isNull);
  });

  test('rejects list indexes that are not plain numbers', () {
    final tags = JsonPointer.parse('#/paths/~1a~0b/get/tags');
    expect(doc.valueAt(tags.child('01')), isNull);
    expect(doc.valueAt(tags.child('-')), isNull);
    expect(doc.valueAt(tags.child(2)), isNull);
  });

  test('parse defaults the URI to the file in the current directory', () {
    expect(doc.uri, p.toUri(p.absolute('api.yaml')));
  });

  test('load records the absolute, normalized file URI', () {
    final dir = TempDir();
    dir.write('specs/api.yaml', 'openapi: 3.1.0\n');
    final path = p.join(dir.path, 'specs', '..', 'specs', 'api.yaml');
    final loaded = SpecLoader(DiagnosticBag()).load(path)!;
    expect(loaded.uri, p.toUri(p.join(dir.path, 'specs', 'api.yaml')));
  });
}
```

- [ ] **Step 2: Add tests to `spec_loader_test.dart`**

In `packages/typed_openapi/test/load/spec_loader_test.dart`, after the fragment:

```dart
    test('a root that is not an object is an error', () {
      final bag = DiagnosticBag();
      expect(SpecLoader(bag).parse('- a\n- b\n', 'a.yaml'), isNull);
      expect(bag.all.single.code, DiagnosticCode.rootNotObject);
    });
```

insert:

```dart
    test('YAML keys 1 and "1" are one JSON key: a warning, last wins', () {
      final bag = DiagnosticBag();
      final doc = SpecLoader(bag).parse(
        'openapi: 3.0.3\nresponses:\n  200: {description: a}\n'
            '  "200": {description: b}\n',
        'api.yaml',
      )!;
      expect(doc.root['responses'], {
        '200': {'description': 'b'},
      });
      final d = bag.all.single;
      expect(d.code, DiagnosticCode.duplicateKey);
      expect(d.severity, Severity.warning);
      expect(d.pointer?.value, '#/responses/200');
      expect(d.line, 4);
    });

    test('JSON with a duplicate key and a syntax error reports both', () {
      final bag = DiagnosticBag();
      final doc = SpecLoader(bag).parse(
        '{"openapi": "3.0.3", "a": 1, "a": 2,\n',
        'api.json',
      );
      expect(doc, isNull);
      expect(bag.all.map((d) => d.code), [
        DiagnosticCode.duplicateKey,
        DiagnosticCode.parseError,
      ]);
      expect(bag.all.last.severity, Severity.error);
      expect(bag.all.last.line, 2);
    });

    test('a JSON root that is not an object is reported before positions', () {
      final bag = DiagnosticBag();
      expect(SpecLoader(bag).parse('[{"a": 1, "a": 2}]', 'api.json'), isNull);
      expect(bag.all.map((d) => d.code), [
        DiagnosticCode.duplicateKey,
        DiagnosticCode.rootNotObject,
      ]);
    });
```

- [ ] **Step 3: Add tests to `spec_loader_test.dart`**

In `packages/typed_openapi/test/load/spec_loader_test.dart`, after the fragment:

```dart
      File(path).writeAsBytesSync([0xFF, 0xFE, 0x41]);
      final bag = DiagnosticBag();
      expect(SpecLoader(bag).load(path), isNull);
      expect(bag.all.single.code, DiagnosticCode.inputUnreadable);
    });
```

insert:

```dart
    test('reports a directory given as the spec', () {
      final dir = TempDir();
      final bag = DiagnosticBag();
      expect(SpecLoader(bag).load(dir.path, displayPath: 'specs'), isNull);
      expect(bag.all.single.code, DiagnosticCode.inputUnreadable);
      expect(bag.all.single.message, contains('is a directory'));
    });
```

- [ ] **Step 4: Add tests to `config_loader_test.dart`**

In `packages/typed_openapi/test/config/config_loader_test.dart`, before the fragment:

```dart
  test('reports unknown keys as warnings and keeps going', () {
```

insert:

```dart
  test('reports a directory given as the config', () {
    final dir = TempDir();
    final bag = DiagnosticBag();
    expect(ConfigLoader(bag).load(dir.path), isNull);
    expect(bag.all.single.code, DiagnosticCode.configInvalid);
    expect(bag.all.single.message, contains('is a directory'));
  });
```

- [ ] **Step 5: Make sure the tests fail**

Run (from `packages/typed_openapi`): `dart test test/load test/config`
Expected: FAIL, the first error — `The method 'valueAt' isn't defined for the type 'SpecDocument'.`

- [ ] **Step 6: Rewrite `spec_document.dart`**

Replace the entire contents of `packages/typed_openapi/lib/src/load/spec_document.dart` with:

```dart
import 'package:source_span/source_span.dart';

import '../diagnostics/json_pointer.dart';

/// A loaded spec: a plain JSON-like tree plus the source position of every
/// node, looked up by JSON pointer.
///
/// [root] contains only `Map<String, Object?>`, `List<Object?>`, `String`,
/// `num`, `bool` and `null`; keys are always strings.
final class SpecDocument {
  /// Creates a document; [spans] maps pointer values to source ranges.
  const SpecDocument({
    required this.file,
    required this.uri,
    required this.root,
    required Map<String, SourceSpan> spans,
  }) : _spans = spans;

  /// The file path as shown to the user.
  final String file;

  /// The absolute URI of the file; relative `$ref`s resolve against it.
  final Uri uri;

  /// The document contents.
  final Map<String, Object?> root;

  final Map<String, SourceSpan> _spans;

  /// Whether source positions were recorded.
  bool get hasPositions => _spans.isNotEmpty;

  /// The source range of the node at [pointer], if known.
  SourceSpan? spanOf(JsonPointer pointer) => _spans[pointer.value];

  /// The value at [pointer] as a one-element record, or null when nothing is
  /// there.
  ///
  /// The record tells an explicit `null` in the document, `(null,)`, from a
  /// missing node, `null`.
  (Object?,)? valueAt(JsonPointer pointer) {
    Object? current = root;
    for (final token in pointer.tokens) {
      switch (current) {
        case Map<String, Object?>() when current.containsKey(token):
          current = current[token];
        case List<Object?>():
          final index = _index.hasMatch(token) ? int.parse(token) : -1;
          if (index < 0 || index >= current.length) return null;
          current = current[index];
        default:
          return null;
      }
    }
    return (current,);
  }

  static final _index = RegExp(r'^(0|[1-9][0-9]{0,8})$');
}
```

- [ ] **Step 7: Rewrite `spec_loader.dart`**

Replace the entire contents of `packages/typed_openapi/lib/src/load/spec_loader.dart` with:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/json_pointer.dart';
import 'spec_document.dart';

/// Reads spec files (JSON or YAML) into [SpecDocument]s.
///
/// Problems go to the [DiagnosticBag] given to the constructor instead of
/// being thrown.
final class SpecLoader {
  /// Creates a loader that reports to [_diagnostics].
  const SpecLoader(this._diagnostics);

  final DiagnosticBag _diagnostics;

  /// Reads the spec file at [path].
  ///
  /// [displayPath] is used in diagnostics instead of [path]. Returns null
  /// when the file cannot be used at all.
  SpecDocument? load(String path, {String? displayPath}) {
    final file = displayPath ?? path;
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) {
      _diagnostics.report(
        .inputNotFound,
        'Spec file $file does not exist.',
        file: file,
        fix: 'Check "input" in the config, or download a fresh snapshot.',
      );
      return null;
    }
    if (type == FileSystemEntityType.directory) {
      _diagnostics.report(
        .inputUnreadable,
        'Spec path $file is a directory, not a file.',
        file: file,
        fix: 'Point "input" at the spec file itself.',
      );
      return null;
    }
    final String text;
    try {
      text = File(path).readAsStringSync();
    } on FileSystemException catch (e) {
      _diagnostics.report(
        .inputUnreadable,
        'Cannot read $file: ${e.message}.',
        file: file,
        fix: 'Save the spec as UTF-8 and check the file permissions.',
      );
      return null;
    }
    return parse(text, file, uri: p.toUri(p.normalize(p.absolute(path))));
  }

  /// Parses spec [text]; [file] names it in diagnostics.
  ///
  /// [uri] is the absolute location of the text, the base for relative
  /// `$ref`s; it defaults to [file] resolved against the current directory.
  /// JSON and YAML go through the same YAML parser, so both get positions.
  /// A JSON file the YAML parser rejects (for example, because of a
  /// duplicate key) is read again with `jsonDecode`, without positions.
  SpecDocument? parse(String text, String file, {Uri? uri}) {
    final location = uri ?? p.toUri(p.normalize(p.absolute(file)));
    final YamlNode node;
    try {
      node = loadYamlNode(text, sourceUrl: Uri.file(file));
    } on YamlException catch (e) {
      return _parseJsonFallback(text, file, location, e);
    }
    if (node is! YamlMap) {
      _diagnostics.report(
        .rootNotObject,
        'The document root must be an object.',
        file: file,
        pointer: .root,
        span: node.span,
      );
      return null;
    }
    final spans = <String, SourceSpan>{};
    final root = _toPlain(node, .root, spans, file)! as Map<String, Object?>;
    return SpecDocument(file: file, uri: location, root: root, spans: spans);
  }

  SpecDocument? _parseJsonFallback(
    String text,
    String file,
    Uri uri,
    YamlException error,
  ) {
    final duplicate = error.message.startsWith('Duplicate mapping key');
    if (p.extension(file).toLowerCase() != '.json') {
      _diagnostics.report(
        duplicate ? .duplicateKey : .parseError,
        error.message,
        severity: .error,
        file: file,
        span: error.span,
      );
      return null;
    }
    final Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException catch (e) {
      if (!duplicate) {
        _diagnostics.report(
          .parseError,
          error.message,
          file: file,
          span: error.span,
        );
        return null;
      }
      _diagnostics.report(
        .duplicateKey,
        error.message,
        file: file,
        span: error.span,
        fix: 'Remove the duplicate key from the spec.',
      );
      final offset = e.offset;
      _diagnostics.report(
        .parseError,
        e.message,
        file: file,
        span: offset == null
            ? null
            : SourceFile.fromString(text, url: uri).span(offset, offset),
      );
      return null;
    }
    if (duplicate) {
      _diagnostics.report(
        .duplicateKey,
        '${error.message} The last value is used.',
        file: file,
        span: error.span,
        fix: 'Remove the duplicate key from the spec.',
      );
    }
    if (root is! Map<String, Object?>) {
      _diagnostics.report(
        .rootNotObject,
        'The document root must be an object.',
        file: file,
        pointer: .root,
      );
      return null;
    }
    _diagnostics.report(
      .positionsUnavailable,
      'Read $file without source positions; '
      'diagnostics for it show JSON pointers only.',
      file: file,
    );
    return SpecDocument(file: file, uri: uri, root: root, spans: const {});
  }

  Object? _toPlain(
    YamlNode node,
    JsonPointer pointer,
    Map<String, SourceSpan> spans,
    String file,
  ) {
    spans[pointer.value] = node.span;
    switch (node) {
      case YamlMap():
        final map = <String, Object?>{};
        final keys = <String, YamlNode>{};
        for (final MapEntry(:key, :value) in node.nodes.entries) {
          final keyNode = key as YamlNode;
          final name = '${keyNode.value}';
          final earlier = keys[name];
          if (earlier != null) {
            _diagnostics.report(
              .duplicateKey,
              'Keys ${earlier.span.text} and ${keyNode.span.text} are the '
              'same key "$name" in JSON; the last value is used.',
              file: file,
              pointer: pointer.child(name),
              span: keyNode.span,
              fix: 'Remove one of the keys.',
            );
          }
          keys[name] = keyNode;
          map[name] = _toPlain(value, pointer.child(name), spans, file);
        }
        return map;
      case YamlList():
        return <Object?>[
          for (var i = 0; i < node.nodes.length; i++)
            _toPlain(node.nodes[i], pointer.child(i), spans, file),
        ];
      default:
        return node.value;
    }
  }
}
```

- [ ] **Step 8: Change `config_loader.dart`**

In `packages/typed_openapi/lib/src/config/config_loader.dart`, replace:

```dart
    final source = File(path);
    if (!source.existsSync()) {
      _diagnostics.report(
        .configNotFound,
        'Config file $path does not exist.',
        file: path,
        fix: 'Create typed_openapi.yaml, or pass its path with --config.',
      );
      return null;
    }
    final String text;
    try {
      text = source.readAsStringSync();
```

with:

```dart
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
```

- [ ] **Step 9: Make sure the tests pass**

Run (from `packages/typed_openapi`): `dart test test/load test/config`
Expected: `+34: All tests passed!`

- [ ] **Step 10: Format, analyzer, the whole test suite**

Run (from `packages/typed_openapi`): `dart format --output=none --set-exit-if-changed lib test bin && dart test`
Expected: `Formatted 28 files (0 changed)`, `+61: All tests passed!`

Run (from the root): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 11: Commit**

```bash
git add packages/typed_openapi/lib/src/config/config_loader.dart packages/typed_openapi/lib/src/load/spec_document.dart packages/typed_openapi/lib/src/load/spec_loader.dart packages/typed_openapi/test/config/config_loader_test.dart packages/typed_openapi/test/load/spec_document_test.dart packages/typed_openapi/test/load/spec_loader_test.dart
git commit -m 'fix(typed_openapi): loader edge cases left from the M1 review' -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
```

---

### Task 2: Protection against excessive nesting depth (TOA007)

**Files:**
- Create: `packages/typed_openapi/lib/src/load/nesting_scanner.dart`
- Create: `packages/typed_openapi/test/load/nesting_scanner_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`
- Modify: `packages/typed_openapi/lib/src/load/spec_loader.dart`
- Modify: `packages/typed_openapi/lib/src/config/config_loader.dart`
- Modify: `packages/typed_openapi/test/load/spec_loader_test.dart`
- Modify: `packages/typed_openapi/test/config/config_loader_test.dart`

**Interfaces:**
- Consumes: `SpecLoader.parse`, `ConfigLoader.load` (Task 1).
- Produces: `final class NestingScanner { const NestingScanner(); static const maxDepth = 1000; int? findTooDeep(String text, {int limit = maxDepth}); }`; `DiagnosticCode.nestingTooDeep` (`TOA007`).

Behaviour the tests pin down:
- `NestingScanner.findTooDeep` returns the offset of the first character at which the depth estimate exceeds the limit, or `null`. Brackets inside strings (`"…"`, `'…'` with `''`) and comments are not counted; an apostrophe inside a word (`it's`) does not open a string.
- Block YAML: the indentation of the line plus the `- ` markers at its start; a flow collection (`[`/`{`) starts counting from the indentation of its own line, so pretty-printed JSON is counted exactly.
- The scanner handles 20 000 levels without recursion; `SpecLoader.parse` and `ConfigLoader.load` return `null` with a diagnostic instead of crashing.

- [ ] **Step 1: Write a test that fails**

Create `packages/typed_openapi/test/load/nesting_scanner_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/load/nesting_scanner.dart';

void main() {
  const scanner = NestingScanner();

  test('accepts JSON as deep as the limit', () {
    final text = '${'[' * 5}${']' * 5}';
    expect(scanner.findTooDeep(text, limit: 5), isNull);
  });

  test('finds the bracket that goes one level too deep', () {
    final text = '{"a": ${'[' * 6}${']' * 6}}';
    expect(scanner.findTooDeep(text, limit: 5), 10);
  });

  test('ignores brackets in strings and comments', () {
    const text = '''
a: "[[[[[["
b: '[[[[[[ it''s'
# [[[[[[
c: [1, 2]
''';
    expect(scanner.findTooDeep(text, limit: 2), isNull);
  });

  test('counts compact YAML sequences and indentation', () {
    expect(scanner.findTooDeep('- - - x\n', limit: 6), isNull);
    expect(scanner.findTooDeep('- - - - x\n', limit: 6), 6);
    expect(scanner.findTooDeep('a:\n        b: 1\n', limit: 6), 9);
  });

  test('a flow collection starts from the indentation of its line', () {
    expect(scanner.findTooDeep('a:\n    b: [[1]]\n', limit: 6), isNull);
    expect(scanner.findTooDeep('a:\n     b: [[1]]\n', limit: 6), 12);
  });

  test('scans 20 000 levels without recursion', () {
    final text = '${'[' * 20000}${']' * 20000}';
    expect(scanner.findTooDeep(text), NestingScanner.maxDepth);
  });
}
```

- [ ] **Step 2: Add tests to `spec_loader_test.dart`**

In `packages/typed_openapi/test/load/spec_loader_test.dart`, replace:

```dart
import 'package:typed_openapi/src/load/spec_loader.dart';
```

with:

```dart
import 'package:typed_openapi/src/load/nesting_scanner.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
```

- [ ] **Step 3: Add tests to `spec_loader_test.dart`**

In `packages/typed_openapi/test/load/spec_loader_test.dart`, after the fragment:

```dart
    test('a root that is not an object is an error', () {
      final bag = DiagnosticBag();
      expect(SpecLoader(bag).parse('- a\n- b\n', 'a.yaml'), isNull);
      expect(bag.all.single.code, DiagnosticCode.rootNotObject);
    });
```

insert:

```dart
    test('nesting deeper than the limit is an error, not a crash', () {
      final bag = DiagnosticBag();
      final text = '{"a": ${'[' * 20000}${']' * 20000}}';
      expect(SpecLoader(bag).parse(text, 'api.json'), isNull);
      final d = bag.all.single;
      expect(d.code, DiagnosticCode.nestingTooDeep);
      expect(d.column, 7 + NestingScanner.maxDepth - 1);
    });

    test('YAML nested deeper than the limit is an error too', () {
      final bag = DiagnosticBag();
      expect(SpecLoader(bag).parse('- ' * 20000, 'api.yaml'), isNull);
      expect(bag.all.single.code, DiagnosticCode.nestingTooDeep);
    });
```

- [ ] **Step 4: Add tests to `config_loader_test.dart`**

In `packages/typed_openapi/test/config/config_loader_test.dart`, before the fragment:

```dart
  test('reports unknown keys as warnings and keeps going', () {
```

insert:

```dart
  test('reports a config nested too deeply instead of crashing', () {
    final path = TempDir().write(
      'typed_openapi.yaml',
      'clients: ${'[' * 20000}${']' * 20000}\n',
    );
    final bag = DiagnosticBag();
    expect(ConfigLoader(bag).load(path), isNull);
    expect(bag.all.single.code, DiagnosticCode.configInvalid);
    expect(bag.all.single.message, contains('nests deeper'));
  });
```

- [ ] **Step 5: Make sure the tests fail**

Run (from `packages/typed_openapi`): `dart test test/load test/config`
Expected: FAIL, the first error — `cannot read 'lib/src/load/nesting_scanner.dart': No such file or directory`

- [ ] **Step 6: Add the codes to the catalogue**

In `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`, after the fragment:

```dart
  inputUnreadable('TOA006', 'input-unreadable', .error),
```

insert:

```dart
  /// The document nests deeper than the parser can follow.
  nestingTooDeep('TOA007', 'nesting-too-deep', .error),
```

- [ ] **Step 7: Create `nesting_scanner.dart`**

Create `packages/typed_openapi/lib/src/load/nesting_scanner.dart`:

```dart
/// Finds text that nests too deeply to parse, without parsing it.
///
/// The YAML parser recurses once per nesting level and overflows the stack
/// at a few thousand levels. A `StackOverflowError` cannot be handled like
/// bad input, so loaders run this scan first and report such text as a
/// diagnostic instead.
///
/// The scan over-estimates and never under-estimates: inside `[...]` and
/// `{...}` it counts brackets outside quoted strings and comments; outside
/// them it counts the indentation of a line plus its leading `- ` markers.
final class NestingScanner {
  /// Creates a scanner.
  const NestingScanner();

  /// The deepest nesting a spec or config file may have.
  static const maxDepth = 1000;

  /// The offset in [text] where the nesting first exceeds [limit], or null
  /// when it never does.
  int? findTooDeep(String text, {int limit = maxDepth}) {
    var flow = 0;
    var block = 0;
    var flowBase = 0;
    var atLineStart = true;
    String? quote;
    var inComment = false;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == '\n') {
        inComment = false;
        if (quote == null && flow == 0) {
          atLineStart = true;
          block = 0;
        }
        continue;
      }
      if (inComment) continue;
      if (quote == '"') {
        if (char == r'\') {
          i++;
        } else if (char == '"') {
          quote = null;
        }
        continue;
      }
      if (quote == "'") {
        if (char == "'") {
          if (i + 1 < text.length && text[i + 1] == "'") {
            i++;
          } else {
            quote = null;
          }
        }
        continue;
      }
      if (atLineStart) {
        if (char == ' ' || char == '\t') {
          block++;
          if (block > limit) return i;
          continue;
        }
        if (char == '-' && _isBlank(text, i + 1)) {
          block += 2;
          if (block > limit) return i;
          i++;
          continue;
        }
        atLineStart = false;
      }
      switch (char) {
        case '#' when i == 0 || _isBlank(text, i - 1):
          inComment = true;
        case '"' || "'" when _startsToken(text, i):
          quote = char;
        case '[' || '{':
          if (flow == 0) flowBase = block;
          flow++;
          if (flowBase + flow > limit) return i;
        case ']' || '}':
          if (flow > 0) flow--;
      }
    }
    return null;
  }

  static bool _isBlank(String text, int i) =>
      i >= text.length || const {' ', '\t', '\n', '\r'}.contains(text[i]);

  static bool _startsToken(String text, int i) =>
      i == 0 ||
      const {' ', '\t', '\n', '\r', '[', '{', ',', ':', '-', '?'}.contains(
        text[i - 1],
      );
}
```

- [ ] **Step 8: Change `spec_loader.dart`**

In `packages/typed_openapi/lib/src/load/spec_loader.dart`, replace:

```dart
import 'spec_document.dart';
```

with:

```dart
import 'nesting_scanner.dart';
import 'spec_document.dart';
```

- [ ] **Step 9: Change `spec_loader.dart`**

In `packages/typed_openapi/lib/src/load/spec_loader.dart`, before the fragment:

```dart
    final YamlNode node;
```

insert:

```dart
    final tooDeep = const NestingScanner().findTooDeep(text);
    if (tooDeep != null) {
      _diagnostics.report(
        .nestingTooDeep,
        'The document nests deeper than ${NestingScanner.maxDepth} levels.',
        file: file,
        span: SourceFile.fromString(
          text,
          url: location,
        ).span(tooDeep, tooDeep + 1),
      );
      return null;
    }
```

- [ ] **Step 10: Change `config_loader.dart`**

In `packages/typed_openapi/lib/src/config/config_loader.dart`, replace:

```dart
import '../diagnostics/json_pointer.dart';
```

with:

```dart
import '../diagnostics/json_pointer.dart';
import '../load/nesting_scanner.dart';
```

- [ ] **Step 11: Change `config_loader.dart`**

In `packages/typed_openapi/lib/src/config/config_loader.dart`, before the fragment:

```dart
    final YamlNode root;
```

insert:

```dart
    final tooDeep = const NestingScanner().findTooDeep(text);
    if (tooDeep != null) {
      _diagnostics.report(
        .configInvalid,
        'The config nests deeper than ${NestingScanner.maxDepth} levels.',
        file: path,
        span: SourceFile.fromString(text).span(tooDeep, tooDeep + 1),
      );
      return null;
    }
```

- [ ] **Step 12: Make sure the tests pass**

Run (from `packages/typed_openapi`): `dart test test/load test/config`
Expected: `+43: All tests passed!`

- [ ] **Step 13: Format, analyzer, the whole test suite**

Run (from `packages/typed_openapi`): `dart format --output=none --set-exit-if-changed lib test bin && dart test`
Expected: `Formatted 30 files (0 changed)`, `+70: All tests passed!`

Run (from the root): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 14: Commit**

```bash
git add packages/typed_openapi/lib/src/config/config_loader.dart packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart packages/typed_openapi/lib/src/load/nesting_scanner.dart packages/typed_openapi/lib/src/load/spec_loader.dart packages/typed_openapi/test/config/config_loader_test.dart packages/typed_openapi/test/load/nesting_scanner_test.dart packages/typed_openapi/test/load/spec_loader_test.dart
git commit -m 'fix(typed_openapi): report deep nesting instead of overflowing the stack' -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
```

---

### Task 3: Model core: `SpecLocation`, `SpecNode`, `RefOr`

**Files:**
- Create: `packages/typed_openapi/lib/src/model/spec_node.dart`
- Create: `packages/typed_openapi/test/model/spec_node_test.dart`

**Interfaces:**
- Consumes: `JsonPointer` (M1).
- Produces: `SpecLocation(Uri document, JsonPointer pointer)` with `==`, `hashCode`, `compareTo`, `toString` (`file:///…#/…`); `abstract class SpecNode({required SpecLocation location, Map<String, Object?> extensions, Map<String, Object?> unknownKeys})` with `JsonPointer get pointer`; `enum RefKind` (`noun`, `withArticle`); `sealed class RefOr<T extends SpecNode>`, `final class Ref<T> extends SpecNode implements RefOr<T>` (`ref`, `kind`, `summary`, `description`), `final class Inline<T> implements RefOr<T>` (`value`).

Behaviour the tests pin down:
- `SpecLocation` values are equal when both the file and the pointer match; the same pointer in two files gives different nodes (space_gen #358). Sorting is by file, then by pointer.
- `RefKind.withArticle` gives `an example`, `a request body` — for the resolver's messages.

- [ ] **Step 1: Write a test that fails**

Create `packages/typed_openapi/test/model/spec_node_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/model/spec_node.dart';

void main() {
  final a = Uri.parse('file:///specs/a.yaml');
  final b = Uri.parse('file:///specs/b.yaml');
  final user = JsonPointer.parse('#/components/schemas/User');

  test('a location is equal to another with the same file and pointer', () {
    expect(SpecLocation(a, user), SpecLocation(a, user));
    expect(SpecLocation(a, user).hashCode, SpecLocation(a, user).hashCode);
  });

  test('the same pointer in two files is two locations', () {
    expect(SpecLocation(a, user), isNot(SpecLocation(b, user)));
  });

  test('locations sort by file, then by pointer', () {
    final sorted = [
      SpecLocation(b, JsonPointer.root),
      SpecLocation(a, user),
      SpecLocation(a, JsonPointer.root),
    ]..sort();
    expect(sorted.map((l) => '$l'), [
      'file:///specs/a.yaml#',
      'file:///specs/a.yaml#/components/schemas/User',
      'file:///specs/b.yaml#',
    ]);
  });

  test('ref kinds name themselves with an article', () {
    expect(RefKind.example.withArticle, 'an example');
    expect(RefKind.requestBody.withArticle, 'a request body');
  });
}
```

- [ ] **Step 2: Make sure the tests fail**

Run (from `packages/typed_openapi`): `dart test test/model`
Expected: FAIL, the first error — `cannot read 'lib/src/model/spec_node.dart': No such file or directory`

- [ ] **Step 3: Create `spec_node.dart`**

Create `packages/typed_openapi/lib/src/model/spec_node.dart`:

```dart
import '../diagnostics/json_pointer.dart';

/// Where a node of a spec is: the absolute URI of its document and its JSON
/// pointer in that document.
///
/// This pair is the identity of a node. Two documents may both have
/// `#/components/schemas/User`; their locations still differ.
final class SpecLocation implements Comparable<SpecLocation> {
  /// Creates a location.
  const SpecLocation(this.document, this.pointer);

  /// The absolute URI of the document, without a fragment.
  final Uri document;

  /// The pointer to the node inside [document].
  final JsonPointer pointer;

  @override
  bool operator ==(Object other) =>
      other is SpecLocation &&
      other.document == document &&
      other.pointer == pointer;

  @override
  int get hashCode => Object.hash(document, pointer);

  @override
  int compareTo(SpecLocation other) {
    final byDocument = '$document'.compareTo('${other.document}');
    if (byDocument != 0) return byDocument;
    return pointer.value.compareTo(other.pointer.value);
  }

  @override
  String toString() => '$document${pointer.value}';
}

/// What every node of the spec model carries.
abstract class SpecNode {
  /// Creates a node.
  const SpecNode({
    required this.location,
    this.extensions = const {},
    this.unknownKeys = const {},
  });

  /// Where the node is.
  final SpecLocation location;

  /// The `x-` keys of the node and their raw values, in document order.
  final Map<String, Object?> extensions;

  /// Keys no OpenAPI version defines for this node, with their raw values.
  ///
  /// Each of them was reported as `unknown-key` when the node was read.
  final Map<String, Object?> unknownKeys;

  /// The pointer part of [location].
  JsonPointer get pointer => location.pointer;
}

/// The kinds of node a `$ref` may point to.
///
/// Schemas are not wrapped in [RefOr]: in a Schema Object `$ref` is a
/// keyword, see `SchemaObject.ref`.
enum RefKind {
  /// A Schema Object.
  schema('schema'),

  /// A Response Object.
  response('response'),

  /// A Parameter Object.
  parameter('parameter'),

  /// An Example Object.
  example('example'),

  /// A Request Body Object.
  requestBody('request body'),

  /// A Header Object.
  header('header'),

  /// A Security Scheme Object.
  securityScheme('security scheme'),

  /// A Path Item Object.
  pathItem('path item'),

  /// A Media Type Object (OpenAPI 3.2).
  mediaType('media type');

  const RefKind(this.noun);

  /// How messages name a node of this kind, such as `request body`.
  final String noun;

  /// [noun] with its article, such as `an example`.
  String get withArticle => '${noun.startsWith('e') ? 'an' : 'a'} $noun';
}

/// A node of type [T] written inline, or a Reference Object to one.
sealed class RefOr<T extends SpecNode> {}

/// A Reference Object: `{$ref: ...}`, with an optional summary and
/// description.
final class Ref<T extends SpecNode> extends SpecNode implements RefOr<T> {
  /// Creates a reference.
  const Ref({
    required super.location,
    required this.ref,
    required this.kind,
    this.summary,
    this.description,
    super.unknownKeys,
  });

  /// The `$ref` value as written.
  final String ref;

  /// The kind of node the reference must point to.
  final RefKind kind;

  /// The `summary` that overrides the target's one.
  final String? summary;

  /// The `description` that overrides the target's one.
  final String? description;
}

/// A node written in place.
final class Inline<T extends SpecNode> implements RefOr<T> {
  /// Wraps [value].
  const Inline(this.value);

  /// The node.
  final T value;
}
```

- [ ] **Step 4: Make sure the tests pass**

Run (from `packages/typed_openapi`): `dart test test/model`
Expected: `+4: All tests passed!`

- [ ] **Step 5: Format, analyzer, the whole test suite**

Run (from `packages/typed_openapi`): `dart format --output=none --set-exit-if-changed lib test bin && dart test`
Expected: `Formatted 32 files (0 changed)`, `+74: All tests passed!`

Run (from the root): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add packages/typed_openapi/lib/src/model/spec_node.dart packages/typed_openapi/test/model/spec_node_test.dart
git commit -m 'feat(typed_openapi): spec node locations and references' -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
```

---

### Task 4: `ObjectReader`, `ParseContext` and `SpecFeature` (TOA110–TOA112)

**Files:**
- Create: `packages/typed_openapi/lib/src/parse/spec_feature.dart`
- Create: `packages/typed_openapi/lib/src/parse/parse_context.dart`
- Create: `packages/typed_openapi/lib/src/parse/object_reader.dart`
- Create: `packages/typed_openapi/test/helpers/spec_fixture.dart`
- Create: `packages/typed_openapi/test/parse/object_reader_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`

**Interfaces:**
- Consumes: `SpecDocument` (Task 1), `SpecLocation`, `SpecNode`, `RefKind`, `Ref`, `Inline`, `RefOr` (Task 3), `OpenApiVersion` (M1).
- Produces: `enum SpecFeature` (`label`, `since`, `until`); `RefUse(site, ref, kind)`, `FeatureUse(feature, file, pointer, span)`, `SpecIndex` (`nodes`, `refs`, `features`); `ParseContext` (`locate`, `report`, `note`, `register`, `reader`, `refOr`); `ObjectReader` (the getters from the block "Interfaces between tasks", `static String describe(Object?)`); codes `unknownKey` (TOA110), `invalidValue` (TOA111), `missingRequiredField` (TOA112); test `SpecFixture(String text, {String file})` with `diagnostics`, `document`, `index`, `context`, `codes`, `pointers`.

Behaviour the tests pin down:
- The `ObjectReader` getters return a value of the required type or `null`; a wrong type is a `TOA111` warning at the field's pointer, with the message `"name" must be a string, not the number 5; it is ignored.`
- `count` accepts `3.0` as `3` and rejects negative and fractional values; `choice` lists the allowed values in the message.
- Elements of lists and maps of the wrong type are reported separately and skipped; `rawList` keeps `null`.
- `map(..., skipExtensions: true)` does not make `x-` keys entries (Paths, Responses).
- `requiredString`/`requiredChoice`/`requiredObject` report `TOA112` at the object's pointer.
- `extensions` — all `x-` keys; `unknownKeys()` reports `TOA110` for each unread key and returns them. That is why `unknownKeys()` is called as the last argument of the node's constructor: Dart evaluates arguments left to right.

- [ ] **Step 1: Create the test helper `spec_fixture.dart`**

Create `packages/typed_openapi/test/helpers/spec_fixture.dart`:

```dart
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/load/spec_document.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/parse/parse_context.dart';

/// A spec parsed from text, with a parse context and the diagnostics so far.
final class SpecFixture {
  /// Parses [text] as the file [file]; the text must load without errors.
  SpecFixture(String text, {String file = 'api.yaml'})
    : this._(DiagnosticBag(), text, file);

  SpecFixture._(this.diagnostics, String text, String file)
    : document = SpecLoader(diagnostics).parse(text, file)!;

  /// Where every diagnostic goes.
  final DiagnosticBag diagnostics;

  /// The loaded document.
  final SpecDocument document;

  /// What the parsers record.
  final SpecIndex index = SpecIndex();

  /// A context for parsing [document].
  late final ParseContext context = ParseContext(
    diagnostics,
    document,
    index,
  );

  /// The codes reported so far, in report order.
  List<DiagnosticCode> get codes => [
    for (final d in diagnostics.all) d.code,
  ];

  /// The pointers reported so far, in report order.
  List<String?> get pointers => [
    for (final d in diagnostics.all) d.pointer?.value,
  ];
}
```

- [ ] **Step 2: Write a test that fails**

Create `packages/typed_openapi/test/parse/object_reader_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/parse/object_reader.dart';

import '../helpers/spec_fixture.dart';

void main() {
  (ObjectReader, SpecFixture) read(String yaml) {
    final fixture = SpecFixture(yaml);
    final reader = ObjectReader(
      fixture.context,
      fixture.document.root,
      JsonPointer.root,
    );
    return (reader, fixture);
  }

  test('reads typed fields', () {
    final (r, fixture) = read(
      'name: id\nrequired: true\nmin: 1.5\nsize: 3.0\nstyle: form\n',
    );
    expect(r.string('name'), 'id');
    expect(r.boolean('required'), isTrue);
    expect(r.number('min'), 1.5);
    expect(r.count('size'), 3);
    expect(r.choice('style', {'form': 1, 'simple': 2}), 1);
    expect(r.string('absent'), isNull);
    expect(fixture.diagnostics.all, isEmpty);
  });

  test('a value of the wrong type is reported and read as missing', () {
    final (r, fixture) = read('name: 5\nrequired: "yes"\nsize: -1\n');
    expect(r.string('name'), isNull);
    expect(r.boolean('required'), isNull);
    expect(r.count('size'), isNull);
    expect(fixture.codes, [
      DiagnosticCode.invalidValue,
      DiagnosticCode.invalidValue,
      DiagnosticCode.invalidValue,
    ]);
    expect(fixture.pointers, ['#/name', '#/required', '#/size']);
    expect(
      fixture.diagnostics.all.first.message,
      '"name" must be a string, not the number 5; it is ignored.',
    );
    expect(fixture.diagnostics.all.first.severity, Severity.warning);
  });

  test('a value outside a choice is reported', () {
    final (r, fixture) = read('in: body\n');
    expect(r.choice('in', {'query': 1, 'path': 2}), isNull);
    expect(
      fixture.diagnostics.all.single.message,
      '"in" must be one of query, path, not "body".',
    );
  });

  test('reads lists and maps; bad items are reported and skipped', () {
    final (r, fixture) = read(
      'tags: [a, 1, b]\nscopes: {read: Read, write: 2}\nenum: [a, null]\n',
    );
    expect(r.strings('tags'), ['a', 'b']);
    expect(r.stringMap('scopes'), {'read': 'Read'});
    expect(r.rawList('enum'), ['a', null]);
    expect(fixture.pointers, ['#/tags/1', '#/scopes/write']);
  });

  test('map can skip x- keys that are not entries', () {
    final (r, _) = read('paths: {/a: 1, x-internal: 2}\n');
    expect(r.map('paths', (raw, _) => raw, skipExtensions: true), {'/a': 1});
  });

  test('a missing required field is reported at the object', () {
    final (r, fixture) = read('summary: s\n');
    expect(r.requiredString('name'), isNull);
    expect(fixture.codes, [DiagnosticCode.missingRequiredField]);
    expect(fixture.pointers, ['#']);
  });

  test('keeps x- keys and reports unknown keys after reading', () {
    final (r, fixture) = read(
      'name: a\nx-order: 1\nnmae: typo\nexternalDocs: {}\n',
    );
    r
      ..string('name')
      ..accept(['externalDocs']);
    expect(r.extensions, {'x-order': 1});
    expect(r.unknownKeys(), {'nmae': 'typo'});
    expect(fixture.codes, [DiagnosticCode.unknownKey]);
    expect(fixture.pointers, ['#/nmae']);
    expect(fixture.diagnostics.all.single.line, 3);
  });

  test('value tells an explicit null from a missing key', () {
    final (r, _) = read('default: null\n');
    expect(r.value('default'), (null,));
    expect(r.value('example'), isNull);
  });
}
```

- [ ] **Step 3: Make sure the tests fail**

Run (from `packages/typed_openapi`): `dart test test/parse`
Expected: FAIL, the first error — `cannot read 'lib/src/parse/object_reader.dart': No such file or directory`

- [ ] **Step 4: Add the codes to the catalogue**

In `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`, before the fragment:

```dart
  /// The configuration file does not exist.
```

insert:

```dart
  /// An object has a key that no OpenAPI version defines; it is ignored.
  unknownKey('TOA110', 'unknown-key', .warning),

  /// A field has the wrong JSON type or a value the spec does not allow; it
  /// is ignored.
  invalidValue('TOA111', 'invalid-value', .warning),

  /// A field the spec requires is missing.
  missingRequiredField('TOA112', 'missing-required-field', .warning),
```

- [ ] **Step 5: Create `spec_feature.dart`**

Create `packages/typed_openapi/lib/src/parse/spec_feature.dart`:

```dart
import '../load/openapi_version.dart';

/// A construct that only some OpenAPI versions define.
///
/// The parser reads every construct whatever version a document declares and
/// notes the version-specific ones; `DialectChecker` then reports those the
/// declared version does not have.
enum SpecFeature {
  /// `type` written as a list.
  typeList('"type" as a list', since: .v31),

  /// `type: "null"`.
  nullType('type "null"', since: .v31),

  /// `const`.
  constKeyword('"const"', since: .v31),

  /// `prefixItems`.
  prefixItems('"prefixItems"', since: .v31),

  /// `examples` (a list) in a schema.
  schemaExamples('"examples" in a schema', since: .v31),

  /// `exclusiveMinimum` or `exclusiveMaximum` written as a number.
  numericExclusiveBound(
    'a numeric "exclusiveMinimum" or "exclusiveMaximum"',
    since: .v31,
  ),

  /// `true` or `false` as a schema, other than in `additionalProperties`.
  booleanSchema('a boolean schema', since: .v31),

  /// `contentMediaType`, `contentEncoding` or `contentSchema`.
  contentKeywords(
    '"contentMediaType", "contentEncoding" or "contentSchema"',
    since: .v31,
  ),

  /// A JSON Schema 2020-12 keyword the model keeps raw, such as `$defs`.
  jsonSchemaKeyword(
    r'a JSON Schema keyword such as "$defs" or "if"',
    since: .v31,
  ),

  /// `webhooks`.
  webhooks('"webhooks"', since: .v31),

  /// `jsonSchemaDialect`.
  jsonSchemaDialect('"jsonSchemaDialect"', since: .v31),

  /// `summary` in the Info Object.
  infoSummary('"summary" in "info"', since: .v31),

  /// `pathItems` in the Components Object.
  componentPathItems('"components/pathItems"', since: .v31),

  /// The `mutualTLS` security scheme type.
  mutualTls('the "mutualTLS" security scheme', since: .v31),

  /// `itemSchema` in a media type.
  itemSchema('"itemSchema"', since: .v32),

  /// `prefixEncoding` or `itemEncoding` in a media type.
  sequentialEncoding('"prefixEncoding" or "itemEncoding"', since: .v32),

  /// The `query` operation of a path item.
  queryOperation('the "query" operation', since: .v32),

  /// `additionalOperations` in a path item.
  additionalOperations('"additionalOperations"', since: .v32),

  /// A parameter with `in: querystring`.
  querystringParameter('"in: querystring"', since: .v32),

  /// `style: cookie`.
  cookieStyle('"style: cookie"', since: .v32),

  /// `summary`, `parent` or `kind` in a tag.
  tagHierarchy('"summary", "parent" or "kind" in a tag', since: .v32),

  /// `defaultMapping` in a discriminator.
  defaultMapping('"defaultMapping"', since: .v32),

  /// `mediaTypes` in the Components Object.
  componentMediaTypes('"components/mediaTypes"', since: .v32),

  /// A `$ref` in place of a Media Type Object.
  mediaTypeRef(r'a "$ref" to a media type', since: .v32),

  /// `$self` at the document root.
  self(r'"$self"', since: .v32),

  /// `summary` in a response.
  responseSummary('"summary" in a response', since: .v32),

  /// `name` in a server.
  serverName('"name" in a server', since: .v32),

  /// `dataValue` or `serializedValue` in an example.
  exampleValues('"dataValue" or "serializedValue"', since: .v32),

  /// `deprecated` or `oauth2MetadataUrl` in a security scheme.
  securitySchemeExtras(
    '"deprecated" or "oauth2MetadataUrl" in a security scheme',
    since: .v32,
  ),

  /// The `deviceAuthorization` OAuth flow.
  deviceAuthorization('the "deviceAuthorization" OAuth flow', since: .v32),

  /// `nullable`, which JSON Schema 2020-12 replaced with `type: "null"`.
  nullable('"nullable"', until: .v31);

  const SpecFeature(this.label, {this.since, this.until});

  /// How diagnostics name the construct.
  final String label;

  /// The first version that has the construct, or null for all.
  final OpenApiVersion? since;

  /// The first version that no longer has the construct, or null for none.
  final OpenApiVersion? until;
}
```

- [ ] **Step 6: Create `parse_context.dart`**

Create `packages/typed_openapi/lib/src/parse/parse_context.dart`:

```dart
import 'package:source_span/source_span.dart';

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/json_pointer.dart';
import '../load/spec_document.dart';
import '../model/spec_node.dart';
import 'object_reader.dart';
import 'spec_feature.dart';

/// A `$ref` found while parsing.
final class RefUse {
  /// Creates a use of [ref] by the node at [site].
  const RefUse(this.site, this.ref, this.kind);

  /// The node that holds the `$ref`: a `Ref` or a `SchemaObject`.
  final SpecLocation site;

  /// The `$ref` value as written.
  final String ref;

  /// The kind of node the reference must point to.
  final RefKind kind;
}

/// A version-specific construct found while parsing.
final class FeatureUse {
  /// Creates a use of [feature].
  const FeatureUse(this.feature, this.file, this.pointer, this.span);

  /// The construct.
  final SpecFeature feature;

  /// The file it is in, as shown to the user.
  final String file;

  /// Where in [file] it is.
  final JsonPointer pointer;

  /// The source range, when positions are known.
  final SourceSpan? span;
}

/// What the parsers of one run collect: every node by location, every
/// `$ref` and every version-specific construct, in the order found.
final class SpecIndex {
  /// Every parsed node, references included, by location.
  final Map<SpecLocation, SpecNode> nodes = {};

  /// Every `$ref` found.
  final List<RefUse> refs = [];

  /// Every version-specific construct found.
  final List<FeatureUse> features = [];
}

/// The document being parsed, with the helpers every parser needs.
final class ParseContext {
  /// Creates a context for [document] that reports to [diagnostics] and
  /// records into [index].
  ParseContext(this.diagnostics, this.document, this.index);

  /// Where problems go.
  final DiagnosticBag diagnostics;

  /// The document being parsed.
  final SpecDocument document;

  /// Where nodes, refs and features are recorded.
  final SpecIndex index;

  /// The location of the node at [pointer] in [document].
  SpecLocation locate(JsonPointer pointer) =>
      SpecLocation(document.uri, pointer);

  /// Reports [code] at [pointer] of [document].
  void report(
    DiagnosticCode code,
    String message,
    JsonPointer pointer, {
    String? fix,
  }) {
    diagnostics.report(
      code,
      message,
      file: document.file,
      pointer: pointer,
      span: document.spanOf(pointer),
      fix: fix,
    );
  }

  /// Records that [feature] is used at [pointer].
  void note(SpecFeature feature, JsonPointer pointer) {
    index.features.add(
      FeatureUse(feature, document.file, pointer, document.spanOf(pointer)),
    );
  }

  /// Records [node] by its location and returns it.
  T register<T extends SpecNode>(T node) {
    index.nodes[node.location] = node;
    return node;
  }

  /// A reader for [raw] at [pointer], or null after reporting that [raw] is
  /// not an object; [what] names the node in the report.
  ObjectReader? reader(Object? raw, JsonPointer pointer, String what) {
    if (raw is Map<String, Object?>) return ObjectReader(this, raw, pointer);
    report(
      .invalidValue,
      '$what must be an object, not ${ObjectReader.describe(raw)}.',
      pointer,
    );
    return null;
  }

  /// Reads [raw] at [pointer] as a Reference Object to a [kind] node, or
  /// with [parse] as an inline node; null when [raw] is not an object.
  RefOr<T>? refOr<T extends SpecNode>(
    Object? raw,
    JsonPointer pointer,
    RefKind kind,
    T Function(ObjectReader reader) parse,
  ) {
    final reader = this.reader(raw, pointer, 'This ${kind.noun}');
    if (reader == null) return null;
    if (!reader.has(r'$ref')) return Inline(parse(reader));
    final ref = reader.string(r'$ref');
    final node = Ref<T>(
      location: reader.location,
      ref: ref ?? '',
      kind: kind,
      summary: reader.string('summary'),
      description: reader.string('description'),
      unknownKeys: reader.unknownKeys(reportExtensions: true),
    );
    if (ref != null) index.refs.add(RefUse(node.location, ref, kind));
    if (kind == .mediaType) note(.mediaTypeRef, pointer);
    register(node);
    return node;
  }
}
```

- [ ] **Step 7: Create `object_reader.dart`**

Create `packages/typed_openapi/lib/src/parse/object_reader.dart`:

```dart
import '../diagnostics/json_pointer.dart';
import '../model/spec_node.dart';
import 'parse_context.dart';

/// Reads the fields of one JSON object of a spec.
///
/// Every getter remembers the key it read. A value of the wrong JSON type is
/// reported as `invalid-value` and read as missing. [unknownKeys] reports
/// the keys nobody read, so call it after reading every field.
final class ObjectReader {
  /// Creates a reader for [_map], which is at [pointer].
  ObjectReader(this._context, this._map, this.pointer);

  final ParseContext _context;
  final Map<String, Object?> _map;
  final Set<String> _read = {};

  /// Where the object is.
  final JsonPointer pointer;

  /// The location of the object.
  SpecLocation get location => _context.locate(pointer);

  /// Whether the object has [key].
  bool has(String key) => _map.containsKey(key);

  /// The keys of the object, in document order.
  Iterable<String> get keys => _map.keys;

  /// The raw value of [key] as a one-element record, or null when the key
  /// is missing.
  (Object?,)? value(String key) {
    _read.add(key);
    return _map.containsKey(key) ? (_map[key],) : null;
  }

  /// Marks [keys] as read without reading them: keys the spec defines but
  /// the model does not type.
  void accept(Iterable<String> keys) => _read.addAll(keys);

  /// [key] as a string.
  String? string(String key) => _typed<String>(key, 'a string');

  /// [key] as a string; reports `missing-required-field` when it is missing.
  String? requiredString(String key) {
    if (!has(key)) _missing(key);
    return string(key);
  }

  /// [key] as a boolean.
  bool? boolean(String key) => _typed<bool>(key, 'true or false');

  /// [key] as a number.
  num? number(String key) => _typed<num>(key, 'a number');

  /// [key] as a non-negative integer; `3.0` reads as `3`.
  int? count(String key) {
    final raw = value(key);
    if (raw == null) return null;
    final (number,) = raw;
    if (number is num && number >= 0 && number == number.truncate()) {
      return number.toInt();
    }
    _invalid(key, 'a non-negative integer', number);
    return null;
  }

  /// [key] as one of the names in [byName].
  T? choice<T>(String key, Map<String, T> byName) {
    final name = string(key);
    if (name == null) return null;
    final result = byName[name];
    if (result != null) return result;
    _context.report(
      .invalidValue,
      '"$key" must be one of ${byName.keys.join(', ')}, not "$name".',
      pointer.child(key),
    );
    return null;
  }

  /// [key] as one of the names in [byName]; reports
  /// `missing-required-field` when it is missing.
  T? requiredChoice<T>(String key, Map<String, T> byName) {
    if (!has(key)) _missing(key);
    return choice(key, byName);
  }

  /// [key] as a list of strings; items that are not strings are reported
  /// and skipped.
  List<String>? strings(String key) =>
      list(key, (raw, at) => _item<String>(raw, at, 'a string'));

  /// [key] as a list of raw values, `null` items included.
  List<Object?>? rawList(String key) {
    final raw = value(key);
    if (raw == null) return null;
    final (items,) = raw;
    if (items is List<Object?>) return List.unmodifiable(items);
    _invalid(key, 'a list', items);
    return null;
  }

  /// [key] as a list whose items [read] converts; null items are skipped.
  List<T>? list<T>(String key, T? Function(Object? raw, JsonPointer at) read) {
    final raw = value(key);
    if (raw == null) return null;
    final (items,) = raw;
    if (items is! List<Object?>) {
      _invalid(key, 'a list', items);
      return null;
    }
    final at = pointer.child(key);
    return List.unmodifiable([
      for (var i = 0; i < items.length; i++) ?read(items[i], at.child(i)),
    ]);
  }

  /// [key] as an object whose values [read] converts, in document order;
  /// null values are skipped. With [skipExtensions], `x-` keys are not
  /// entries.
  Map<String, T>? map<T>(
    String key,
    T? Function(Object? raw, JsonPointer at) read, {
    bool skipExtensions = false,
  }) {
    final raw = value(key);
    if (raw == null) return null;
    final (entries,) = raw;
    if (entries is! Map<String, Object?>) {
      _invalid(key, 'an object', entries);
      return null;
    }
    final at = pointer.child(key);
    return Map.unmodifiable({
      for (final MapEntry(key: name, :value) in entries.entries)
        if (!skipExtensions || !name.startsWith('x-'))
          name: ?read(value, at.child(name)),
    });
  }

  /// [key] as an object of strings.
  Map<String, String>? stringMap(String key) =>
      map(key, (raw, at) => _item<String>(raw, at, 'a string'));

  /// [key] read by [read] when it is an object.
  T? object<T>(String key, T Function(ObjectReader reader) read) {
    final raw = value(key);
    if (raw == null) return null;
    final reader = _context.reader(raw.$1, pointer.child(key), '"$key"');
    return reader == null ? null : read(reader);
  }

  /// [key] read by [read]; reports `missing-required-field` when it is
  /// missing.
  T? requiredObject<T>(String key, T Function(ObjectReader reader) read) {
    if (!has(key)) _missing(key);
    return object(key, read);
  }

  /// The `x-` keys of the object and their raw values.
  Map<String, Object?> get extensions => Map.unmodifiable({
    for (final MapEntry(:key, :value) in _map.entries)
      if (key.startsWith('x-')) key: value,
  });

  /// Reports each key that was not read and is not an `x-` key as
  /// `unknown-key`, and returns them with their raw values.
  ///
  /// With [reportExtensions], `x-` keys are reported too: Reference Objects
  /// cannot be extended.
  Map<String, Object?> unknownKeys({bool reportExtensions = false}) {
    final unknown = <String, Object?>{};
    for (final MapEntry(:key, :value) in _map.entries) {
      if (_read.contains(key)) continue;
      if (!reportExtensions && key.startsWith('x-')) continue;
      unknown[key] = value;
      _context.report(
        .unknownKey,
        'Unknown key "$key"; it is ignored.',
        pointer.child(key),
      );
    }
    return Map.unmodifiable(unknown);
  }

  /// How a raw value is named in messages.
  static String describe(Object? raw) => switch (raw) {
    null => 'null',
    bool() => '$raw',
    num() => 'the number $raw',
    String() => 'a string',
    List<Object?>() => 'a list',
    _ => 'an object',
  };

  T? _typed<T>(String key, String expected) {
    final raw = value(key);
    if (raw == null) return null;
    final (result,) = raw;
    if (result is T) return result;
    _invalid(key, expected, result);
    return null;
  }

  T? _item<T>(Object? raw, JsonPointer at, String expected) {
    if (raw is T) return raw;
    _context.report(
      .invalidValue,
      'Each item must be $expected, not ${describe(raw)}.',
      at,
    );
    return null;
  }

  void _invalid(String key, String expected, Object? raw) {
    _context.report(
      .invalidValue,
      '"$key" must be $expected, not ${describe(raw)}; it is ignored.',
      pointer.child(key),
    );
  }

  void _missing(String key) {
    _context.report(
      .missingRequiredField,
      'The required field "$key" is missing.',
      pointer,
    );
  }
}
```

- [ ] **Step 8: Make sure the tests pass**

Run (from `packages/typed_openapi`): `dart test test/parse`
Expected: `+8: All tests passed!`

- [ ] **Step 9: Format, analyzer, the whole test suite**

Run (from `packages/typed_openapi`): `dart format --output=none --set-exit-if-changed lib test bin && dart test`
Expected: `Formatted 37 files (0 changed)`, `+82: All tests passed!`

Run (from the root): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 10: Commit**

```bash
git add packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart packages/typed_openapi/lib/src/parse/object_reader.dart packages/typed_openapi/lib/src/parse/parse_context.dart packages/typed_openapi/lib/src/parse/spec_feature.dart packages/typed_openapi/test/helpers/spec_fixture.dart packages/typed_openapi/test/parse/object_reader_test.dart
git commit -m 'feat(typed_openapi): object reader with key and type diagnostics' -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
```

---

### Task 5: Schema model and parser (TOA105)

**Files:**
- Create: `packages/typed_openapi/lib/src/model/schema.dart`
- Create: `packages/typed_openapi/lib/src/parse/schema_parser.dart`
- Create: `packages/typed_openapi/test/parse/schema_parser_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`

**Interfaces:**
- Consumes: `ParseContext`, `ObjectReader`, `RefUse`, `SpecFeature` (Task 4).
- Produces: `sealed class Schema extends SpecNode`, `BooleanSchema(value)`, `SchemaObject` (fields are in the code below), `enum SchemaType` (`wire`, `byWire`; `nullType` is `"null"`), `Discriminator(propertyName, mapping, defaultMapping)`; `final class SchemaParser { const SchemaParser(ParseContext); Schema? parse(Object? raw, JsonPointer pointer, {bool booleanIsClassic = false}); }`; code `refBaseIgnored` (TOA105).

Behaviour the tests pin down:
- A 3.0 schema is read in full; each nested schema has its own pointer and is registered in `SpecIndex.nodes`.
- 2020-12 constructs (a `type` list, `"null"`, `const`, `examples`, a numeric `exclusiveMinimum`, `prefixItems`, boolean schemas, `content*`, `$defs`) are read and marked as `SpecFeature`; `nullable` too (as a 3.0-only construct). `additionalProperties: false` is not marked: it belongs to 3.0.
- A `$ref` with siblings is stored together with them and recorded in `SpecIndex.refs` with the kind `schema`.
- `default: null` → `(null,)`; `enum: [a, null]` keeps `null`.
- `required: true` and an unknown `type: file` — `TOA111`; the rest of the schema is read. `$id` — `TOA105`.

- [ ] **Step 1: Write a test that fails**

Create `packages/typed_openapi/test/parse/schema_parser_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/model/schema.dart';
import 'package:typed_openapi/src/model/spec_node.dart';
import 'package:typed_openapi/src/parse/schema_parser.dart';
import 'package:typed_openapi/src/parse/spec_feature.dart';

import '../helpers/spec_fixture.dart';

void main() {
  (Schema?, SpecFixture) parse(String yaml) {
    final fixture = SpecFixture(yaml);
    final pointer = JsonPointer.root.child('schema');
    final schema = SchemaParser(
      fixture.context,
    ).parse(fixture.document.valueAt(pointer)!.$1, pointer);
    return (schema, fixture);
  }

  test('reads a 3.0 object schema', () {
    final (schema, fixture) = parse('''
schema:
  type: object
  required: [id]
  nullable: true
  description: A pet.
  properties:
    id: {type: integer, format: int64, minimum: 1}
    tags: {type: array, items: {type: string}, maxItems: 10}
  additionalProperties: false
  x-order: 3
''');
    final pet = schema! as SchemaObject;
    expect(pet.types, [SchemaType.object]);
    expect(pet.required, ['id']);
    expect(pet.nullable, isTrue);
    expect(pet.description, 'A pet.');
    expect(pet.properties.keys, ['id', 'tags']);
    final id = pet.properties['id']! as SchemaObject;
    expect(id.format, 'int64');
    expect(id.minimum, 1);
    final tags = pet.properties['tags']! as SchemaObject;
    expect((tags.items! as SchemaObject).types, [SchemaType.string]);
    expect(tags.maxItems, 10);
    expect((pet.additionalProperties! as BooleanSchema).value, isFalse);
    expect(pet.extensions, {'x-order': 3});
    expect(pet.pointer.value, '#/schema');
    expect(id.pointer.value, '#/schema/properties/id');
    expect(fixture.diagnostics.all, isEmpty);
    expect(fixture.index.features.map((f) => f.feature), [
      SpecFeature.nullable,
    ]);
  });

  test('reads 2020-12 keywords and notes them as 3.1 constructs', () {
    final (schema, fixture) = parse(r'''
schema:
  type: [string, "null"]
  const: a
  examples: [a]
  exclusiveMinimum: 0
  prefixItems: [true]
  contentMediaType: application/json
  contentSchema: {type: object}
  $defs: {Id: {type: string}}
''');
    final s = schema! as SchemaObject;
    expect(s.types, [SchemaType.string, SchemaType.nullType]);
    expect(s.constValue, ('a',));
    expect(s.examples, ['a']);
    expect(s.exclusiveMinimum, 0);
    expect(s.exclusiveMinimumFlag, isNull);
    expect(s.prefixItems.single, isA<BooleanSchema>());
    expect(s.contentSchema, isA<SchemaObject>());
    expect(s.otherKeywords.keys, [r'$defs']);
    expect(fixture.diagnostics.all, isEmpty);
    expect(
      fixture.index.features.map((f) => f.feature).toSet(),
      {
        SpecFeature.typeList,
        SpecFeature.nullType,
        SpecFeature.constKeyword,
        SpecFeature.schemaExamples,
        SpecFeature.numericExclusiveBound,
        SpecFeature.prefixItems,
        SpecFeature.booleanSchema,
        SpecFeature.contentKeywords,
        SpecFeature.jsonSchemaKeyword,
      },
    );
  });

  test('keeps a boolean exclusive bound as the 3.0 flag', () {
    final (schema, fixture) = parse(
      'schema: {maximum: 5, exclusiveMaximum: true}\n',
    );
    final s = schema! as SchemaObject;
    expect(s.exclusiveMaximumFlag, isTrue);
    expect(s.exclusiveMaximum, isNull);
    expect(fixture.index.features, isEmpty);
  });

  test(r'keeps $ref with its siblings and records the reference', () {
    final (schema, fixture) = parse(
      'schema: {\$ref: "#/components/schemas/Pet", description: Owner.}\n',
    );
    final s = schema! as SchemaObject;
    expect(s.ref, '#/components/schemas/Pet');
    expect(s.description, 'Owner.');
    final use = fixture.index.refs.single;
    expect(use.ref, '#/components/schemas/Pet');
    expect(use.kind, RefKind.schema);
    expect(use.site, s.location);
  });

  test('defaults, null enum members and examples are kept as written', () {
    final (schema, _) = parse(
      'schema: {default: null, enum: [a, null], example: {k: 1}}\n',
    );
    final s = schema! as SchemaObject;
    expect(s.defaultValue, (null,));
    expect(s.enumValues, ['a', null]);
    expect(s.example?.$1, {'k': 1});
  });

  test('a boolean "required" and an unknown type are reported, the rest is '
      'read', () {
    final (schema, fixture) = parse('''
schema:
  type: array
  items:
    type: file
    required: true
    format: binary
''');
    final items = (schema! as SchemaObject).items! as SchemaObject;
    expect(items.types, isEmpty);
    expect(items.required, isEmpty);
    expect(items.format, 'binary');
    expect(fixture.codes, [
      DiagnosticCode.invalidValue,
      DiagnosticCode.invalidValue,
    ]);
    expect(fixture.pointers, [
      '#/schema/items/type',
      '#/schema/items/required',
    ]);
  });

  test('reads a discriminator with a 3.2 defaultMapping', () {
    final (schema, fixture) = parse(r'''
schema:
  oneOf: [{$ref: "#/c/Cat"}, {$ref: "#/c/Dog"}]
  discriminator:
    propertyName: kind
    mapping: {cat: "#/c/Cat"}
    defaultMapping: "#/c/Dog"
''');
    final d = (schema! as SchemaObject).discriminator!;
    expect(d.propertyName, 'kind');
    expect(d.mapping, {'cat': '#/c/Cat'});
    expect(d.defaultMapping, '#/c/Dog');
    expect(fixture.index.refs, hasLength(2));
    expect(fixture.index.features.single.feature, SpecFeature.defaultMapping);
  });

  test('reports a schema that is neither an object nor a boolean', () {
    final (schema, fixture) = parse('schema: [a]\n');
    expect(schema, isNull);
    expect(fixture.codes, [DiagnosticCode.invalidValue]);
  });

  test(r'reports $id: refs inside are not resolved against it', () {
    final (_, fixture) = parse('schema: {\$id: "https://example.com/a"}\n');
    expect(fixture.codes, [DiagnosticCode.refBaseIgnored]);
  });

  test('registers every schema by location', () {
    final (schema, fixture) = parse(
      'schema: {properties: {a: {items: {type: string}}}}\n',
    );
    expect(fixture.index.nodes.values, hasLength(3));
    expect(fixture.index.nodes[schema!.location], same(schema));
  });
}
```

- [ ] **Step 2: Make sure the tests fail**

Run (from `packages/typed_openapi`): `dart test test/parse`
Expected: FAIL, the first error — `cannot read 'lib/src/model/schema.dart': No such file or directory`

- [ ] **Step 3: Add the codes to the catalog**

In `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart` before the snippet:

```dart
  /// An object has a key that no OpenAPI version defines; it is ignored.
```

insert:

```dart
  /// `$id` or `$self` would change the base URI of `$ref`s; this tool
  /// resolves them against the file location instead.
  refBaseIgnored('TOA105', 'ref-base-ignored', .warning),
```

- [ ] **Step 4: Create `schema.dart`**

Create `packages/typed_openapi/lib/src/model/schema.dart`:

```dart
import 'spec_node.dart';

/// A JSON Schema: a [BooleanSchema] or a [SchemaObject].
///
/// The model is a superset of OpenAPI 3.0 schemas and JSON Schema 2020-12
/// (OpenAPI 3.1 and 3.2). Nothing is converted between the two: a 3.0
/// `nullable: true` and a 3.1 `type: [string, "null"]` are both kept as
/// written; the normalizer reconciles them later.
sealed class Schema extends SpecNode {
  /// Creates a schema.
  const Schema({
    required super.location,
    super.extensions,
    super.unknownKeys,
  });
}

/// `true` (any value) or `false` (no value) used as a schema.
final class BooleanSchema extends Schema {
  /// Creates a boolean schema.
  const BooleanSchema({required super.location, required this.value});

  /// Whether every value is valid.
  final bool value;
}

/// The JSON types a schema's `type` can name.
enum SchemaType {
  /// `string`.
  string('string'),

  /// `number`.
  number('number'),

  /// `integer`.
  integer('integer'),

  /// `boolean`.
  boolean('boolean'),

  /// `array`.
  array('array'),

  /// `object`.
  object('object'),

  /// `null` (JSON Schema 2020-12 only).
  nullType('null');

  const SchemaType(this.wire);

  /// The name used in specs.
  final String wire;

  /// The types by [wire] name.
  static final Map<String, SchemaType> byWire = {
    for (final type in values) type.wire: type,
  };
}

/// A Schema Object.
///
/// A raw value that may be `null` in the spec is kept as a one-element
/// record, so `default: null` reads as `(null,)` and a missing `default` as
/// `null`.
final class SchemaObject extends Schema {
  /// Creates a schema object.
  const SchemaObject({
    required super.location,
    this.ref,
    this.types = const [],
    this.nullable,
    this.format,
    this.title,
    this.description,
    this.deprecated = false,
    this.readOnly = false,
    this.writeOnly = false,
    this.defaultValue,
    this.constValue,
    this.enumValues,
    this.example,
    this.examples = const [],
    this.properties = const {},
    this.required = const [],
    this.additionalProperties,
    this.minProperties,
    this.maxProperties,
    this.items,
    this.prefixItems = const [],
    this.minItems,
    this.maxItems,
    this.uniqueItems = false,
    this.allOf = const [],
    this.oneOf = const [],
    this.anyOf = const [],
    this.not,
    this.discriminator,
    this.minimum,
    this.maximum,
    this.exclusiveMinimum,
    this.exclusiveMaximum,
    this.exclusiveMinimumFlag,
    this.exclusiveMaximumFlag,
    this.multipleOf,
    this.minLength,
    this.maxLength,
    this.pattern,
    this.contentMediaType,
    this.contentEncoding,
    this.contentSchema,
    this.otherKeywords = const {},
    super.extensions,
    super.unknownKeys,
  });

  /// The `$ref` keyword as written; the other keywords apply next to it.
  final String? ref;

  /// `type`, as a list even when the spec wrote a single string.
  final List<SchemaType> types;

  /// OpenAPI 3.0 `nullable`.
  final bool? nullable;

  /// `format`.
  final String? format;

  /// `title`.
  final String? title;

  /// `description`.
  final String? description;

  /// `deprecated`.
  final bool deprecated;

  /// `readOnly`.
  final bool readOnly;

  /// `writeOnly`.
  final bool writeOnly;

  /// `default`.
  final (Object?,)? defaultValue;

  /// `const`.
  final (Object?,)? constValue;

  /// `enum`.
  final List<Object?>? enumValues;

  /// `example` (deprecated in 3.1).
  final (Object?,)? example;

  /// `examples`, the JSON Schema list of examples.
  final List<Object?> examples;

  /// `properties`, in document order.
  final Map<String, Schema> properties;

  /// `required`.
  final List<String> required;

  /// `additionalProperties`; a [BooleanSchema] when the spec wrote a boolean.
  final Schema? additionalProperties;

  /// `minProperties`.
  final int? minProperties;

  /// `maxProperties`.
  final int? maxProperties;

  /// `items`.
  final Schema? items;

  /// `prefixItems`.
  final List<Schema> prefixItems;

  /// `minItems`.
  final int? minItems;

  /// `maxItems`.
  final int? maxItems;

  /// `uniqueItems`.
  final bool uniqueItems;

  /// `allOf`.
  final List<Schema> allOf;

  /// `oneOf`.
  final List<Schema> oneOf;

  /// `anyOf`.
  final List<Schema> anyOf;

  /// `not`.
  final Schema? not;

  /// `discriminator`.
  final Discriminator? discriminator;

  /// `minimum`.
  final num? minimum;

  /// `maximum`.
  final num? maximum;

  /// `exclusiveMinimum` written as a number (JSON Schema 2020-12).
  final num? exclusiveMinimum;

  /// `exclusiveMaximum` written as a number (JSON Schema 2020-12).
  final num? exclusiveMaximum;

  /// `exclusiveMinimum` written as a boolean (OpenAPI 3.0).
  final bool? exclusiveMinimumFlag;

  /// `exclusiveMaximum` written as a boolean (OpenAPI 3.0).
  final bool? exclusiveMaximumFlag;

  /// `multipleOf`.
  final num? multipleOf;

  /// `minLength`.
  final int? minLength;

  /// `maxLength`.
  final int? maxLength;

  /// `pattern`.
  final String? pattern;

  /// `contentMediaType`.
  final String? contentMediaType;

  /// `contentEncoding`.
  final String? contentEncoding;

  /// `contentSchema`.
  final Schema? contentSchema;

  /// JSON Schema 2020-12 keywords the model does not read yet, such as
  /// `$defs`, `if` or `patternProperties`, with their raw values.
  final Map<String, Object?> otherKeywords;
}

/// A Discriminator Object.
final class Discriminator extends SpecNode {
  /// Creates a discriminator.
  const Discriminator({
    required super.location,
    this.propertyName,
    this.mapping = const {},
    this.defaultMapping,
    super.extensions,
    super.unknownKeys,
  });

  /// `propertyName`; required by the spec.
  final String? propertyName;

  /// `mapping` from a property value to a schema name or `$ref`.
  final Map<String, String> mapping;

  /// `defaultMapping` (OpenAPI 3.2).
  final String? defaultMapping;
}
```

- [ ] **Step 5: Create `schema_parser.dart`**

Create `packages/typed_openapi/lib/src/parse/schema_parser.dart`:

```dart
import '../diagnostics/json_pointer.dart';
import '../model/schema.dart';
import 'object_reader.dart';
import 'parse_context.dart';
import 'spec_feature.dart';

/// Reads Schema Objects of OpenAPI 3.0, 3.1 and 3.2 into [Schema]s.
///
/// Every keyword of any of those versions is read, whatever version the
/// document declares; version-specific ones are noted in the context's
/// index for `DialectChecker`.
final class SchemaParser {
  /// Creates a parser that reads from [_context].
  const SchemaParser(this._context);

  /// Keywords the spec defines but the model does not type.
  static const _accepted = ['xml', 'externalDocs'];

  /// JSON Schema 2020-12 keywords kept raw in [SchemaObject.otherKeywords].
  static const _rawKeywords = [
    r'$id',
    r'$schema',
    r'$anchor',
    r'$dynamicRef',
    r'$dynamicAnchor',
    r'$defs',
    r'$comment',
    r'$vocabulary',
    'if',
    'then',
    'else',
    'dependentSchemas',
    'dependentRequired',
    'patternProperties',
    'propertyNames',
    'contains',
    'minContains',
    'maxContains',
    'unevaluatedItems',
    'unevaluatedProperties',
  ];

  final ParseContext _context;

  /// Reads the schema [raw] at [pointer]; null after reporting when [raw] is
  /// neither an object nor a boolean.
  ///
  /// A boolean is noted as a 3.1 construct unless [booleanIsClassic]: 3.0
  /// allows `additionalProperties: true`.
  Schema? parse(
    Object? raw,
    JsonPointer pointer, {
    bool booleanIsClassic = false,
  }) {
    if (raw is bool) {
      if (!booleanIsClassic) _context.note(.booleanSchema, pointer);
      return _context.register(
        BooleanSchema(location: _context.locate(pointer), value: raw),
      );
    }
    if (raw is! Map<String, Object?>) {
      _context.report(
        .invalidValue,
        'A schema must be an object or a boolean, not '
        '${ObjectReader.describe(raw)}; it is ignored.',
        pointer,
      );
      return null;
    }
    return _object(ObjectReader(_context, raw, pointer));
  }

  SchemaObject _object(ObjectReader r) {
    final ref = r.string(r'$ref');
    if (ref != null) {
      _context.index.refs.add(RefUse(r.location, ref, .schema));
    }
    if (r.has(r'$id')) {
      _context.report(
        .refBaseIgnored,
        r'"$id" changes the base URI of "$ref"s inside this schema; they '
        'are resolved against the file location instead.',
        r.pointer.child(r'$id'),
      );
    }
    final at = r.pointer;
    for (final (key, feature) in _notedKeys) {
      if (r.has(key)) _context.note(feature, at.child(key));
    }
    r.accept(_accepted);
    final schema = SchemaObject(
      location: r.location,
      ref: ref,
      types: _types(r),
      nullable: r.boolean('nullable'),
      format: r.string('format'),
      title: r.string('title'),
      description: r.string('description'),
      deprecated: r.boolean('deprecated') ?? false,
      readOnly: r.boolean('readOnly') ?? false,
      writeOnly: r.boolean('writeOnly') ?? false,
      defaultValue: r.value('default'),
      constValue: r.value('const'),
      enumValues: r.rawList('enum'),
      example: r.value('example'),
      examples: r.rawList('examples') ?? const [],
      properties: r.map('properties', parse) ?? const {},
      required: r.strings('required') ?? const [],
      additionalProperties: _schemaAt(
        r,
        'additionalProperties',
        booleanIsClassic: true,
      ),
      minProperties: r.count('minProperties'),
      maxProperties: r.count('maxProperties'),
      items: _schemaAt(r, 'items'),
      prefixItems: r.list('prefixItems', parse) ?? const [],
      minItems: r.count('minItems'),
      maxItems: r.count('maxItems'),
      uniqueItems: r.boolean('uniqueItems') ?? false,
      allOf: r.list('allOf', parse) ?? const [],
      oneOf: r.list('oneOf', parse) ?? const [],
      anyOf: r.list('anyOf', parse) ?? const [],
      not: _schemaAt(r, 'not'),
      discriminator: r.object('discriminator', _discriminator),
      minimum: r.number('minimum'),
      maximum: r.number('maximum'),
      exclusiveMinimum: _bound(r, 'exclusiveMinimum'),
      exclusiveMaximum: _bound(r, 'exclusiveMaximum'),
      exclusiveMinimumFlag: _flag(r, 'exclusiveMinimum'),
      exclusiveMaximumFlag: _flag(r, 'exclusiveMaximum'),
      multipleOf: r.number('multipleOf'),
      minLength: r.count('minLength'),
      maxLength: r.count('maxLength'),
      pattern: r.string('pattern'),
      contentMediaType: r.string('contentMediaType'),
      contentEncoding: r.string('contentEncoding'),
      contentSchema: _schemaAt(r, 'contentSchema'),
      otherKeywords: Map.unmodifiable({
        for (final key in _rawKeywords)
          if (r.value(key) case (final raw,)) key: raw,
      }),
      extensions: r.extensions,
      unknownKeys: r.unknownKeys(),
    );
    return _context.register(schema);
  }

  static const _notedKeys = [
    ('nullable', SpecFeature.nullable),
    ('const', SpecFeature.constKeyword),
    ('prefixItems', SpecFeature.prefixItems),
    ('examples', SpecFeature.schemaExamples),
    ('contentMediaType', SpecFeature.contentKeywords),
    ('contentEncoding', SpecFeature.contentKeywords),
    ('contentSchema', SpecFeature.contentKeywords),
    (r'$id', SpecFeature.jsonSchemaKeyword),
    (r'$schema', SpecFeature.jsonSchemaKeyword),
    (r'$anchor', SpecFeature.jsonSchemaKeyword),
    (r'$dynamicRef', SpecFeature.jsonSchemaKeyword),
    (r'$dynamicAnchor', SpecFeature.jsonSchemaKeyword),
    (r'$defs', SpecFeature.jsonSchemaKeyword),
    (r'$comment', SpecFeature.jsonSchemaKeyword),
    (r'$vocabulary', SpecFeature.jsonSchemaKeyword),
    ('if', SpecFeature.jsonSchemaKeyword),
    ('then', SpecFeature.jsonSchemaKeyword),
    ('else', SpecFeature.jsonSchemaKeyword),
    ('dependentSchemas', SpecFeature.jsonSchemaKeyword),
    ('dependentRequired', SpecFeature.jsonSchemaKeyword),
    ('patternProperties', SpecFeature.jsonSchemaKeyword),
    ('propertyNames', SpecFeature.jsonSchemaKeyword),
    ('contains', SpecFeature.jsonSchemaKeyword),
    ('minContains', SpecFeature.jsonSchemaKeyword),
    ('maxContains', SpecFeature.jsonSchemaKeyword),
    ('unevaluatedItems', SpecFeature.jsonSchemaKeyword),
    ('unevaluatedProperties', SpecFeature.jsonSchemaKeyword),
  ];

  List<SchemaType> _types(ObjectReader r) {
    final raw = r.value('type');
    if (raw == null) return const [];
    final at = r.pointer.child('type');
    final (type,) = raw;
    if (type is List<Object?>) _context.note(.typeList, at);
    final names = type is List<Object?> ? type : [type];
    final types = <SchemaType>[];
    for (var i = 0; i < names.length; i++) {
      final name = names[i];
      final itemAt = type is List<Object?> ? at.child(i) : at;
      final known = name is String ? SchemaType.byWire[name] : null;
      if (known == null) {
        _context.report(
          .invalidValue,
          name is String
              ? 'Unknown type "$name"; it is ignored.'
              : 'A type must be a string, not ${ObjectReader.describe(name)}; '
                    'it is ignored.',
          itemAt,
          fix: 'Use one of ${SchemaType.byWire.keys.join(', ')}.',
        );
        continue;
      }
      if (known == .nullType) _context.note(.nullType, itemAt);
      types.add(known);
    }
    return List.unmodifiable(types);
  }

  Schema? _schemaAt(
    ObjectReader r,
    String key, {
    bool booleanIsClassic = false,
  }) {
    final raw = r.value(key);
    if (raw == null) return null;
    return parse(
      raw.$1,
      r.pointer.child(key),
      booleanIsClassic: booleanIsClassic,
    );
  }

  num? _bound(ObjectReader r, String key) {
    final raw = r.value(key);
    if (raw case (final num bound,)) {
      _context.note(.numericExclusiveBound, r.pointer.child(key));
      return bound;
    }
    if (raw case (bool(),)) return null;
    if (raw != null) {
      _context.report(
        .invalidValue,
        '"$key" must be a number or a boolean, not '
        '${ObjectReader.describe(raw.$1)}; it is ignored.',
        r.pointer.child(key),
      );
    }
    return null;
  }

  static bool? _flag(ObjectReader r, String key) => switch (r.value(key)) {
    (final bool flag,) => flag,
    _ => null,
  };

  Discriminator _discriminator(ObjectReader r) {
    if (r.has('defaultMapping')) {
      _context.note(.defaultMapping, r.pointer.child('defaultMapping'));
    }
    return _context.register(
      Discriminator(
        location: r.location,
        propertyName: r.requiredString('propertyName'),
        mapping: r.stringMap('mapping') ?? const {},
        defaultMapping: r.string('defaultMapping'),
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }
}
```

- [ ] **Step 6: Make sure the tests pass**

Run (from `packages/typed_openapi`): `dart test test/parse`
Expected: `+18: All tests passed!`

- [ ] **Step 7: Format, analyzer, the whole test suite**

Run (from `packages/typed_openapi`): `dart format --output=none --set-exit-if-changed lib test bin && dart test`
Expected: `Formatted 40 files (0 changed)`, `+92: All tests passed!`

Run (from the root): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart packages/typed_openapi/lib/src/model/schema.dart packages/typed_openapi/lib/src/parse/schema_parser.dart packages/typed_openapi/test/parse/schema_parser_test.dart
git commit -m 'feat(typed_openapi): schema model and parser' -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
```

---

### Task 6: Path items, operations and their parts

**Files:**
- Create: `packages/typed_openapi/lib/src/model/operation.dart`
- Create: `packages/typed_openapi/lib/src/parse/operation_parser.dart`
- Create: `packages/typed_openapi/test/parse/operation_parser_test.dart`

**Interfaces:**
- Consumes: `ParseContext.refOr`, `ObjectReader` (Task 4), `SchemaParser`, `Schema` (Task 5).
- Produces: models `PathItem` (`static const methods`), `Operation`, `Parameter` (`placement` is the field `in`), `ParameterLocation`, `ParameterStyle`, `RequestBody`, `Response`, `Header`, `MediaType`, `Encoding`, `Example`, `Server`, `ServerVariable`, `SecurityRequirement`; `final class OperationParser { const OperationParser(ParseContext, SchemaParser); … }` with the public `pathItem`, `parameter`, `requestBody`, `response`, `header`, `mediaType`, `example` (all `RefOr<T>? Function(Object? raw, JsonPointer)`), `server`, `securityRequirement`.

The behaviour the tests pin down:
- Path item, operation, parameters (inline and `$ref`), responses by status in document order (without `x-`), headers, `content`, bodies, encoding, examples are read from the pointer on every node; all `$ref`s are recorded with the expected kind.
- Operation `security`: `null` — not set (inherited), `[]` — explicitly no security.
- 3.2: the `query` operation, `additionalOperations`, `in: querystring`, the response `summary`, `itemSchema` — are read and flagged.
- A Swagger 2 style parameter (`type` instead of `schema`) — `TOA110`; without `name` — `TOA112`; `in: body` — `TOA111`. A Reference Object with foreign keys — `TOA110`; a node that is not an object — `TOA111` "This response must be an object, not a string."

- [ ] **Step 1: Write a failing test**

Create `packages/typed_openapi/test/parse/operation_parser_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/model/operation.dart';
import 'package:typed_openapi/src/model/schema.dart';
import 'package:typed_openapi/src/model/spec_node.dart';
import 'package:typed_openapi/src/parse/operation_parser.dart';
import 'package:typed_openapi/src/parse/schema_parser.dart';
import 'package:typed_openapi/src/parse/spec_feature.dart';

import '../helpers/spec_fixture.dart';

void main() {
  (RefOr<PathItem>?, SpecFixture) parse(String yaml) {
    final fixture = SpecFixture(yaml);
    final pointer = JsonPointer.root.child('item');
    final item = OperationParser(
      fixture.context,
      SchemaParser(fixture.context),
    ).pathItem(fixture.document.valueAt(pointer)!.$1, pointer);
    return (item, fixture);
  }

  T inline<T extends SpecNode>(RefOr<T>? value) => (value! as Inline<T>).value;

  test('reads a path item with an operation', () {
    final (item, fixture) = parse(r'''
item:
  parameters:
    - {name: id, in: path, required: true, schema: {type: string}}
  get:
    operationId: getPet
    tags: [pets]
    parameters:
      - $ref: "#/components/parameters/Limit"
    responses:
      "200":
        description: OK
        headers:
          X-Rate: {schema: {type: integer}}
        content:
          application/json:
            schema: {$ref: "#/components/schemas/Pet"}
      default: {$ref: "#/components/responses/Error"}
      x-codegen: skip
    security: []
''');
    final pets = inline(item);
    expect(pets.parameters, hasLength(1));
    final id = inline(pets.parameters.single);
    expect(id.name, 'id');
    expect(id.placement, ParameterLocation.path);
    expect(id.required, isTrue);
    final get = pets.operations['get']!;
    expect(get.operationId, 'getPet');
    expect(get.tags, ['pets']);
    expect(get.parameters.single, isA<Ref<Parameter>>());
    expect(get.responses.keys, ['200', 'default']);
    final ok = inline(get.responses['200']);
    expect(ok.description, 'OK');
    expect(inline(ok.headers['X-Rate']).schema, isA<SchemaObject>());
    final json = inline(ok.content['application/json']);
    expect((json.schema! as SchemaObject).ref, '#/components/schemas/Pet');
    expect(get.security, isEmpty);
    expect(pets.operations['post'], isNull);
    expect(fixture.diagnostics.all, isEmpty);
    expect(fixture.index.refs.map((r) => (r.ref, r.kind)), [
      ('#/components/parameters/Limit', RefKind.parameter),
      ('#/components/schemas/Pet', RefKind.schema),
      ('#/components/responses/Error', RefKind.response),
    ]);
  });

  test('security stays null when an operation does not set it', () {
    final (item, _) = parse('item: {get: {responses: {}}}\n');
    expect(inline(item).operations['get']!.security, isNull);
  });

  test('reads request bodies, encodings and examples', () {
    final (item, fixture) = parse('''
item:
  post:
    requestBody:
      required: true
      content:
        multipart/form-data:
          schema: {type: object}
          encoding:
            file: {contentType: image/png}
          examples:
            one: {summary: One, value: {a: 1}}
''');
    final body = inline(inline(item).operations['post']!.requestBody);
    expect(body.required, isTrue);
    final form = inline(body.content['multipart/form-data']);
    expect(form.encoding['file']!.contentType, 'image/png');
    expect(inline(form.examples['one']).summary, 'One');
    expect(fixture.diagnostics.all, isEmpty);
  });

  test('reads 3.2 constructs and notes them', () {
    final (item, fixture) = parse('''
item:
  query:
    parameters:
      - {name: filter, in: querystring, content: {application/x-www-form-urlencoded: {}}}
    responses:
      "200":
        summary: Events
        content:
          text/event-stream:
            itemSchema: {type: object}
  additionalOperations:
    PURGE: {responses: {}}
''');
    final pets = inline(item);
    expect(pets.operations.keys, ['query']);
    expect(pets.additionalOperations.keys, ['PURGE']);
    final query = pets.operations['query']!;
    expect(
      inline(query.parameters.single).placement,
      ParameterLocation.querystring,
    );
    final events = inline(
      inline(query.responses['200']).content['text/event-stream'],
    );
    expect(events.itemSchema, isA<SchemaObject>());
    expect(fixture.diagnostics.all, isEmpty);
    expect(fixture.index.features.map((f) => f.feature).toSet(), {
      SpecFeature.queryOperation,
      SpecFeature.querystringParameter,
      SpecFeature.responseSummary,
      SpecFeature.itemSchema,
      SpecFeature.additionalOperations,
    });
  });

  test('a Swagger 2 style parameter is reported, the rest is read', () {
    final (item, fixture) = parse('''
item:
  get:
    parameters:
      - {name: limit, in: query, type: integer}
      - {in: header, schema: {type: string}}
      - {name: x, in: body}
''');
    final params = inline(item).operations['get']!.parameters;
    expect(params.map((p) => inline(p).name), ['limit', null, 'x']);
    expect(fixture.codes, [
      DiagnosticCode.unknownKey,
      DiagnosticCode.missingRequiredField,
      DiagnosticCode.invalidValue,
    ]);
    expect(fixture.pointers, [
      '#/item/get/parameters/0/type',
      '#/item/get/parameters/1',
      '#/item/get/parameters/2/in',
    ]);
  });

  test('a Reference Object keeps summary and description and reports the '
      'rest', () {
    final (item, fixture) = parse(r'''
item:
  $ref: "#/components/pathItems/Pets"
  description: Pets.
  get: {}
''');
    final ref = item! as Ref<PathItem>;
    expect(ref.ref, '#/components/pathItems/Pets');
    expect(ref.description, 'Pets.');
    expect(ref.kind, RefKind.pathItem);
    expect(ref.unknownKeys.keys, ['get']);
    expect(fixture.codes, [DiagnosticCode.unknownKey]);
  });

  test('a node of the wrong shape is reported and skipped', () {
    final (item, fixture) = parse('item: {get: {responses: {"200": oops}}}\n');
    expect(inline(item).operations['get']!.responses, isEmpty);
    expect(fixture.codes, [DiagnosticCode.invalidValue]);
    expect(
      fixture.diagnostics.all.single.message,
      'This response must be an object, not a string.',
    );
  });
}
```

- [ ] **Step 2: Make sure the tests fail**

Run (from `packages/typed_openapi`): `dart test test/parse`
Expected: FAIL, the first error — `cannot read 'lib/src/model/operation.dart': No such file or directory`

- [ ] **Step 3: Create `operation.dart`**

Create `packages/typed_openapi/lib/src/model/operation.dart`:

```dart
import 'schema.dart';
import 'spec_node.dart';

/// A Path Item Object.
final class PathItem extends SpecNode {
  /// Creates a path item.
  const PathItem({
    required super.location,
    this.summary,
    this.description,
    this.operations = const {},
    this.additionalOperations = const {},
    this.servers = const [],
    this.parameters = const [],
    super.extensions,
    super.unknownKeys,
  });

  /// The fixed operation fields of a path item, in the order the spec lists
  /// them; `query` is OpenAPI 3.2.
  static const methods = [
    'get',
    'put',
    'post',
    'delete',
    'options',
    'head',
    'patch',
    'trace',
    'query',
  ];

  /// `summary`.
  final String? summary;

  /// `description`.
  final String? description;

  /// Operations by lowercase method from [methods], in document order.
  final Map<String, Operation> operations;

  /// `additionalOperations` (OpenAPI 3.2): operations by method, with the
  /// method's case as written.
  final Map<String, Operation> additionalOperations;

  /// `servers`.
  final List<Server> servers;

  /// `parameters` shared by every operation of the path.
  final List<RefOr<Parameter>> parameters;
}

/// An Operation Object.
final class Operation extends SpecNode {
  /// Creates an operation.
  const Operation({
    required super.location,
    this.tags = const [],
    this.summary,
    this.description,
    this.operationId,
    this.parameters = const [],
    this.requestBody,
    this.responses = const {},
    this.deprecated = false,
    this.security,
    this.servers = const [],
    super.extensions,
    super.unknownKeys,
  });

  /// `tags`.
  final List<String> tags;

  /// `summary`.
  final String? summary;

  /// `description`.
  final String? description;

  /// `operationId`.
  final String? operationId;

  /// `parameters`.
  final List<RefOr<Parameter>> parameters;

  /// `requestBody`.
  final RefOr<RequestBody>? requestBody;

  /// `responses` by status code, range (`2XX`) or `default`, in document
  /// order; `x-` keys of the Responses Object are not included.
  final Map<String, RefOr<Response>> responses;

  /// `deprecated`.
  final bool deprecated;

  /// `security`; null when the operation does not set it and inherits the
  /// document's.
  final List<SecurityRequirement>? security;

  /// `servers`.
  final List<Server> servers;
}

/// Where a parameter is sent: the `in` field.
enum ParameterLocation {
  /// A query parameter.
  query,

  /// The whole query string as one value (OpenAPI 3.2).
  querystring,

  /// A header.
  header,

  /// A path segment.
  path,

  /// A cookie.
  cookie,
}

/// How a parameter value is serialized: the `style` field.
enum ParameterStyle {
  /// `matrix`.
  matrix,

  /// `label`.
  label,

  /// `simple`.
  simple,

  /// `form`.
  form,

  /// `spaceDelimited`.
  spaceDelimited,

  /// `pipeDelimited`.
  pipeDelimited,

  /// `deepObject`.
  deepObject,

  /// `cookie` (OpenAPI 3.2).
  cookie,
}

/// A Parameter Object.
final class Parameter extends SpecNode {
  /// Creates a parameter.
  const Parameter({
    required super.location,
    this.name,
    this.placement,
    this.description,
    this.required = false,
    this.deprecated = false,
    this.allowEmptyValue = false,
    this.style,
    this.explode,
    this.allowReserved = false,
    this.schema,
    this.example,
    this.examples = const {},
    this.content = const {},
    super.extensions,
    super.unknownKeys,
  });

  /// `name`; required by the spec.
  final String? name;

  /// `in`; required by the spec.
  final ParameterLocation? placement;

  /// `description`.
  final String? description;

  /// `required`.
  final bool required;

  /// `deprecated`.
  final bool deprecated;

  /// `allowEmptyValue`.
  final bool allowEmptyValue;

  /// `style`.
  final ParameterStyle? style;

  /// `explode`; null when the spec leaves it to the style's default.
  final bool? explode;

  /// `allowReserved`.
  final bool allowReserved;

  /// `schema`.
  final Schema? schema;

  /// `example`.
  final (Object?,)? example;

  /// `examples`.
  final Map<String, RefOr<Example>> examples;

  /// `content`, used instead of [schema] for complex serialization.
  final Map<String, RefOr<MediaType>> content;
}

/// A Request Body Object.
final class RequestBody extends SpecNode {
  /// Creates a request body.
  const RequestBody({
    required super.location,
    this.description,
    this.content = const {},
    this.required = false,
    super.extensions,
    super.unknownKeys,
  });

  /// `description`.
  final String? description;

  /// `content` by media type, in document order.
  final Map<String, RefOr<MediaType>> content;

  /// `required`.
  final bool required;
}

/// A Response Object.
final class Response extends SpecNode {
  /// Creates a response.
  const Response({
    required super.location,
    this.summary,
    this.description,
    this.headers = const {},
    this.content = const {},
    super.extensions,
    super.unknownKeys,
  });

  /// `summary` (OpenAPI 3.2).
  final String? summary;

  /// `description`.
  final String? description;

  /// `headers`.
  final Map<String, RefOr<Header>> headers;

  /// `content` by media type, in document order.
  final Map<String, RefOr<MediaType>> content;
}

/// A Header Object.
final class Header extends SpecNode {
  /// Creates a header.
  const Header({
    required super.location,
    this.description,
    this.required = false,
    this.deprecated = false,
    this.style,
    this.explode,
    this.schema,
    this.example,
    this.examples = const {},
    this.content = const {},
    super.extensions,
    super.unknownKeys,
  });

  /// `description`.
  final String? description;

  /// `required`.
  final bool required;

  /// `deprecated`.
  final bool deprecated;

  /// `style`.
  final ParameterStyle? style;

  /// `explode`.
  final bool? explode;

  /// `schema`.
  final Schema? schema;

  /// `example`.
  final (Object?,)? example;

  /// `examples`.
  final Map<String, RefOr<Example>> examples;

  /// `content`.
  final Map<String, RefOr<MediaType>> content;
}

/// A Media Type Object.
final class MediaType extends SpecNode {
  /// Creates a media type.
  const MediaType({
    required super.location,
    this.schema,
    this.itemSchema,
    this.example,
    this.examples = const {},
    this.encoding = const {},
    this.prefixEncoding = const [],
    this.itemEncoding,
    super.extensions,
    super.unknownKeys,
  });

  /// `schema`.
  final Schema? schema;

  /// `itemSchema` (OpenAPI 3.2): the schema of each item of a sequential
  /// media type such as `text/event-stream`.
  final Schema? itemSchema;

  /// `example`.
  final (Object?,)? example;

  /// `examples`.
  final Map<String, RefOr<Example>> examples;

  /// `encoding` by property name.
  final Map<String, Encoding> encoding;

  /// `prefixEncoding` (OpenAPI 3.2).
  final List<Encoding> prefixEncoding;

  /// `itemEncoding` (OpenAPI 3.2).
  final Encoding? itemEncoding;
}

/// An Encoding Object.
final class Encoding extends SpecNode {
  /// Creates an encoding.
  const Encoding({
    required super.location,
    this.contentType,
    this.headers = const {},
    this.style,
    this.explode,
    this.allowReserved = false,
    super.extensions,
    super.unknownKeys,
  });

  /// `contentType`.
  final String? contentType;

  /// `headers`.
  final Map<String, RefOr<Header>> headers;

  /// `style`.
  final ParameterStyle? style;

  /// `explode`.
  final bool? explode;

  /// `allowReserved`.
  final bool allowReserved;
}

/// An Example Object.
final class Example extends SpecNode {
  /// Creates an example.
  const Example({
    required super.location,
    this.summary,
    this.description,
    this.value,
    this.dataValue,
    this.serializedValue,
    this.externalValue,
    super.extensions,
    super.unknownKeys,
  });

  /// `summary`.
  final String? summary;

  /// `description`.
  final String? description;

  /// `value`.
  final (Object?,)? value;

  /// `dataValue` (OpenAPI 3.2).
  final (Object?,)? dataValue;

  /// `serializedValue` (OpenAPI 3.2).
  final String? serializedValue;

  /// `externalValue`.
  final String? externalValue;
}

/// A Server Object.
final class Server extends SpecNode {
  /// Creates a server.
  const Server({
    required super.location,
    this.url,
    this.name,
    this.description,
    this.variables = const {},
    super.extensions,
    super.unknownKeys,
  });

  /// `url`, possibly with `{variables}`; required by the spec.
  final String? url;

  /// `name` (OpenAPI 3.2).
  final String? name;

  /// `description`.
  final String? description;

  /// `variables` by name.
  final Map<String, ServerVariable> variables;
}

/// A Server Variable Object.
final class ServerVariable extends SpecNode {
  /// Creates a server variable.
  const ServerVariable({
    required super.location,
    this.enumValues,
    this.defaultValue,
    this.description,
    super.extensions,
    super.unknownKeys,
  });

  /// `enum`.
  final List<String>? enumValues;

  /// `default`; required by the spec.
  final String? defaultValue;

  /// `description`.
  final String? description;
}

/// A Security Requirement Object: scheme names and the scopes each needs.
///
/// An empty requirement (`{}`) makes security optional.
final class SecurityRequirement extends SpecNode {
  /// Creates a requirement.
  const SecurityRequirement({required super.location, this.schemes = const {}});

  /// Scopes by security scheme name, in document order.
  final Map<String, List<String>> schemes;
}
```

- [ ] **Step 4: Create `operation_parser.dart`**

Create `packages/typed_openapi/lib/src/parse/operation_parser.dart`:

```dart
import '../diagnostics/json_pointer.dart';
import '../model/operation.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';
import 'object_reader.dart';
import 'parse_context.dart';
import 'schema_parser.dart';

/// Reads path items, operations and everything they contain: parameters,
/// request bodies, responses, headers, media types, encodings, examples,
/// servers and security requirements.
final class OperationParser {
  /// Creates a parser that reads from [_context] and reads schemas with
  /// [_schemas].
  const OperationParser(this._context, this._schemas);

  final ParseContext _context;
  final SchemaParser _schemas;

  /// Reads the path item [raw] at [pointer].
  RefOr<PathItem>? pathItem(Object? raw, JsonPointer pointer) =>
      _context.refOr(raw, pointer, .pathItem, _pathItem);

  /// Reads the parameter [raw] at [pointer].
  RefOr<Parameter>? parameter(Object? raw, JsonPointer pointer) =>
      _context.refOr(raw, pointer, .parameter, _parameter);

  /// Reads the request body [raw] at [pointer].
  RefOr<RequestBody>? requestBody(Object? raw, JsonPointer pointer) =>
      _context.refOr(raw, pointer, .requestBody, _requestBody);

  /// Reads the response [raw] at [pointer].
  RefOr<Response>? response(Object? raw, JsonPointer pointer) =>
      _context.refOr(raw, pointer, .response, _response);

  /// Reads the header [raw] at [pointer].
  RefOr<Header>? header(Object? raw, JsonPointer pointer) =>
      _context.refOr(raw, pointer, .header, _header);

  /// Reads the media type [raw] at [pointer].
  RefOr<MediaType>? mediaType(Object? raw, JsonPointer pointer) =>
      _context.refOr(raw, pointer, .mediaType, _mediaType);

  /// Reads the example [raw] at [pointer].
  RefOr<Example>? example(Object? raw, JsonPointer pointer) =>
      _context.refOr(raw, pointer, .example, _example);

  /// Reads the server [raw] at [pointer].
  Server? server(Object? raw, JsonPointer pointer) {
    final r = _context.reader(raw, pointer, 'A server');
    if (r == null) return null;
    if (r.has('name')) _context.note(.serverName, pointer.child('name'));
    return _context.register(
      Server(
        location: r.location,
        url: r.requiredString('url'),
        name: r.string('name'),
        description: r.string('description'),
        variables: r.map('variables', _serverVariable) ?? const {},
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  /// Reads the security requirement [raw] at [pointer].
  SecurityRequirement? securityRequirement(Object? raw, JsonPointer pointer) {
    final r = _context.reader(raw, pointer, 'A security requirement');
    if (r == null) return null;
    return _context.register(
      SecurityRequirement(
        location: r.location,
        schemes: Map.unmodifiable({
          for (final name in r.keys.toList()) name: ?r.strings(name),
        }),
      ),
    );
  }

  PathItem _pathItem(ObjectReader r) {
    final operations = <String, Operation>{};
    for (final method in PathItem.methods) {
      final operation = r.object(method, _operation);
      if (operation == null) continue;
      operations[method] = operation;
      if (method == 'query') {
        _context.note(.queryOperation, r.pointer.child(method));
      }
    }
    if (r.has('additionalOperations')) {
      _context.note(
        .additionalOperations,
        r.pointer.child('additionalOperations'),
      );
    }
    return _context.register(
      PathItem(
        location: r.location,
        summary: r.string('summary'),
        description: r.string('description'),
        operations: Map.unmodifiable(operations),
        additionalOperations:
            r.map('additionalOperations', _operationAt) ?? const {},
        servers: r.list('servers', server) ?? const [],
        parameters: r.list('parameters', parameter) ?? const [],
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  Operation? _operationAt(Object? raw, JsonPointer pointer) {
    final r = _context.reader(raw, pointer, 'An operation');
    return r == null ? null : _operation(r);
  }

  Operation _operation(ObjectReader r) {
    r.accept(const ['externalDocs', 'callbacks']);
    return _context.register(
      Operation(
        location: r.location,
        tags: r.strings('tags') ?? const [],
        summary: r.string('summary'),
        description: r.string('description'),
        operationId: r.string('operationId'),
        parameters: r.list('parameters', parameter) ?? const [],
        requestBody: switch (r.value('requestBody')) {
          (final raw,) => requestBody(raw, r.pointer.child('requestBody')),
          null => null,
        },
        responses:
            r.map('responses', response, skipExtensions: true) ?? const {},
        deprecated: r.boolean('deprecated') ?? false,
        security: r.list('security', securityRequirement),
        servers: r.list('servers', server) ?? const [],
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  Parameter _parameter(ObjectReader r) {
    final placement = r.requiredChoice(
      'in',
      ParameterLocation.values.asNameMap(),
    );
    if (placement == .querystring) {
      _context.note(.querystringParameter, r.pointer.child('in'));
    }
    return _context.register(
      Parameter(
        location: r.location,
        name: r.requiredString('name'),
        placement: placement,
        description: r.string('description'),
        required: r.boolean('required') ?? false,
        deprecated: r.boolean('deprecated') ?? false,
        allowEmptyValue: r.boolean('allowEmptyValue') ?? false,
        style: _style(r),
        explode: r.boolean('explode'),
        allowReserved: r.boolean('allowReserved') ?? false,
        schema: _schema(r, 'schema'),
        example: r.value('example'),
        examples: r.map('examples', example) ?? const {},
        content: r.map('content', mediaType) ?? const {},
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  RequestBody _requestBody(ObjectReader r) {
    if (!r.has('content')) {
      _context.report(
        .missingRequiredField,
        'The required field "content" is missing.',
        r.pointer,
      );
    }
    return _context.register(
      RequestBody(
        location: r.location,
        description: r.string('description'),
        content: r.map('content', mediaType) ?? const {},
        required: r.boolean('required') ?? false,
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  Response _response(ObjectReader r) {
    if (r.has('summary')) {
      _context.note(.responseSummary, r.pointer.child('summary'));
    }
    r.accept(const ['links']);
    return _context.register(
      Response(
        location: r.location,
        summary: r.string('summary'),
        description: r.string('description'),
        headers: r.map('headers', header) ?? const {},
        content: r.map('content', mediaType) ?? const {},
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  Header _header(ObjectReader r) {
    r.accept(const ['allowEmptyValue', 'allowReserved']);
    return _context.register(
      Header(
        location: r.location,
        description: r.string('description'),
        required: r.boolean('required') ?? false,
        deprecated: r.boolean('deprecated') ?? false,
        style: _style(r),
        explode: r.boolean('explode'),
        schema: _schema(r, 'schema'),
        example: r.value('example'),
        examples: r.map('examples', example) ?? const {},
        content: r.map('content', mediaType) ?? const {},
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  MediaType _mediaType(ObjectReader r) {
    if (r.has('itemSchema')) {
      _context.note(.itemSchema, r.pointer.child('itemSchema'));
    }
    for (final key in const ['prefixEncoding', 'itemEncoding']) {
      if (r.has(key)) _context.note(.sequentialEncoding, r.pointer.child(key));
    }
    return _context.register(
      MediaType(
        location: r.location,
        schema: _schema(r, 'schema'),
        itemSchema: _schema(r, 'itemSchema'),
        example: r.value('example'),
        examples: r.map('examples', example) ?? const {},
        encoding: r.map('encoding', _encodingAt) ?? const {},
        prefixEncoding: r.list('prefixEncoding', _encodingAt) ?? const [],
        itemEncoding: r.object('itemEncoding', _encoding),
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  Encoding? _encodingAt(Object? raw, JsonPointer pointer) {
    final r = _context.reader(raw, pointer, 'An encoding');
    return r == null ? null : _encoding(r);
  }

  Encoding _encoding(ObjectReader r) {
    r.accept(const ['encoding', 'prefixEncoding', 'itemEncoding']);
    return _context.register(
      Encoding(
        location: r.location,
        contentType: r.string('contentType'),
        headers: r.map('headers', header) ?? const {},
        style: _style(r),
        explode: r.boolean('explode'),
        allowReserved: r.boolean('allowReserved') ?? false,
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  Example _example(ObjectReader r) {
    for (final key in const ['dataValue', 'serializedValue']) {
      if (r.has(key)) _context.note(.exampleValues, r.pointer.child(key));
    }
    return _context.register(
      Example(
        location: r.location,
        summary: r.string('summary'),
        description: r.string('description'),
        value: r.value('value'),
        dataValue: r.value('dataValue'),
        serializedValue: r.string('serializedValue'),
        externalValue: r.string('externalValue'),
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  ServerVariable? _serverVariable(Object? raw, JsonPointer pointer) {
    final r = _context.reader(raw, pointer, 'A server variable');
    if (r == null) return null;
    return _context.register(
      ServerVariable(
        location: r.location,
        enumValues: r.strings('enum'),
        defaultValue: r.requiredString('default'),
        description: r.string('description'),
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  ParameterStyle? _style(ObjectReader r) {
    final style = r.choice('style', ParameterStyle.values.asNameMap());
    if (style == .cookie) _context.note(.cookieStyle, r.pointer.child('style'));
    return style;
  }

  Schema? _schema(ObjectReader r, String key) => switch (r.value(key)) {
    (final raw,) => _schemas.parse(raw, r.pointer.child(key)),
    null => null,
  };
}
```

- [ ] **Step 5: Make sure the tests pass**

Run (from `packages/typed_openapi`): `dart test test/parse`
Expected: `+25: All tests passed!`

- [ ] **Step 6: Format, analyzer, the whole test suite**

Run (from `packages/typed_openapi`): `dart format --output=none --set-exit-if-changed lib test bin && dart test`
Expected: `Formatted 43 files (0 changed)`, `+99: All tests passed!`

Run (from the root): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add packages/typed_openapi/lib/src/model/operation.dart packages/typed_openapi/lib/src/parse/operation_parser.dart packages/typed_openapi/test/parse/operation_parser_test.dart
git commit -m 'feat(typed_openapi): path items, operations and their parts' -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
```

---

### Task 7: Document, components and security schemes: `OpenApiParser`

**Files:**
- Create: `packages/typed_openapi/lib/src/model/document.dart`
- Create: `packages/typed_openapi/lib/src/model/security.dart`
- Create: `packages/typed_openapi/lib/src/parse/openapi_parser.dart`
- Create: `packages/typed_openapi/test/parse/openapi_parser_test.dart`

**Interfaces:**
- Consumes: `OperationParser`, the models of Task 6, `SchemaParser` (Task 5), `ParseContext`, `SpecIndex` (Task 4).
- Produces: `SecurityScheme` (`placement` is `in`), `SecuritySchemeType`, `ApiKeyLocation`, `OAuthFlows`, `OAuthFlow`; `OpenApiDocument`, `Info`, `Tag`, `Components`; `final class OpenApiParser { factory OpenApiParser(DiagnosticBag, SpecDocument, SpecIndex); OpenApiDocument parse(OpenApiVersion? version); SpecNode? parseFragment(JsonPointer pointer, RefKind kind); }`.

The behaviour the tests pin down:
- The whole document: `info` with extensions, servers with variables, global `security`, tags, `paths` (without `x-` keys), `components` (schemas, security schemes of all types with OAuth flows). The document is registered in `SpecIndex`.
- Missing required fields (`info.version`, `tag.name`, `name` for `apiKey`) and unknown keys (`host`) are reported, and reading continues.
- Document-level 3.1/3.2 constructs are flagged; `$self` is also `TOA105`.
- `parseFragment(pointer, kind)` reads any node of the raw tree as the required kind — so the resolver will read `$ref` targets outside `components` and in other files.

- [ ] **Step 1: Write a failing test**

Create `packages/typed_openapi/test/parse/openapi_parser_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/load/openapi_version.dart';
import 'package:typed_openapi/src/model/document.dart';
import 'package:typed_openapi/src/model/operation.dart';
import 'package:typed_openapi/src/model/schema.dart';
import 'package:typed_openapi/src/model/security.dart';
import 'package:typed_openapi/src/model/spec_node.dart';
import 'package:typed_openapi/src/parse/openapi_parser.dart';
import 'package:typed_openapi/src/parse/spec_feature.dart';

import '../helpers/spec_fixture.dart';

void main() {
  (OpenApiDocument, SpecFixture) parse(String yaml) {
    final fixture = SpecFixture(yaml);
    final document = OpenApiParser(
      fixture.diagnostics,
      fixture.document,
      fixture.index,
    ).parse(OpenApiVersion.v30);
    return (document, fixture);
  }

  T inline<T extends SpecNode>(RefOr<T>? value) => (value! as Inline<T>).value;

  test('reads a whole document', () {
    final (doc, fixture) = parse('''
openapi: 3.0.3
info: {title: Pets, version: "1.0", x-audience: public}
servers:
  - url: "https://{env}.example.com"
    variables:
      env: {default: api, enum: [api, staging]}
security:
  - bearer: []
tags:
  - {name: pets, description: Pets.}
paths:
  /pets:
    get: {responses: {"204": {description: No content}}}
  x-internal: true
components:
  schemas:
    Pet: {type: object}
  securitySchemes:
    bearer: {type: http, scheme: bearer, bearerFormat: JWT}
    key: {type: apiKey, name: X-Key, in: header}
    oauth:
      type: oauth2
      flows:
        clientCredentials:
          tokenUrl: https://example.com/token
          scopes: {read: Read}
''');
    expect(fixture.diagnostics.all, isEmpty);
    expect(doc.version, OpenApiVersion.v30);
    expect(doc.info!.title, 'Pets');
    expect(doc.info!.extensions, {'x-audience': 'public'});
    expect(doc.servers.single.variables['env']!.enumValues, ['api', 'staging']);
    expect(doc.security!.single.schemes, {'bearer': <String>[]});
    expect(doc.tags.single.name, 'pets');
    expect(doc.paths.keys, ['/pets']);
    expect(doc.extensions, isEmpty);
    final components = doc.components!;
    expect(components.schemas['Pet'], isA<SchemaObject>());
    final schemes = components.securitySchemes;
    expect(inline(schemes['bearer']).type, SecuritySchemeType.http);
    expect(inline(schemes['key']).placement, ApiKeyLocation.header);
    final flow = inline(schemes['oauth']).flows!.clientCredentials!;
    expect(flow.scopes, {'read': 'Read'});
    expect(fixture.index.nodes[doc.location], same(doc));
  });

  test('missing required fields and unknown keys are reported; reading '
      'goes on', () {
    final (doc, fixture) = parse('''
openapi: 3.0.3
info: {title: Pets}
paths: {}
host: example.com
tags: [{description: No name.}]
components:
  securitySchemes:
    key: {type: apiKey}
''');
    expect(doc.info!.title, 'Pets');
    expect(doc.tags.single.description, 'No name.');
    expect(fixture.codes, [
      DiagnosticCode.missingRequiredField,
      DiagnosticCode.missingRequiredField,
      DiagnosticCode.missingRequiredField,
      DiagnosticCode.unknownKey,
    ]);
    expect(fixture.pointers, [
      '#/info',
      '#/components/securitySchemes/key',
      '#/tags/0',
      '#/host',
    ]);
  });

  test('notes 3.1 and 3.2 document-level constructs', () {
    final (_, fixture) = parse(r'''
openapi: 3.0.3
$self: https://example.com/api.yaml
info: {title: Pets, version: "1", summary: Pets API.}
jsonSchemaDialect: https://spec.openapis.org/oas/3.1/dialect/base
webhooks: {}
tags: [{name: cats, parent: pets, kind: nav}]
components:
  pathItems: {}
  mediaTypes:
    Json: {schema: {type: object}}
  securitySchemes:
    tls: {type: mutualTLS}
''');
    expect(fixture.codes, [DiagnosticCode.refBaseIgnored]);
    expect(fixture.index.features.map((f) => f.feature).toSet(), {
      SpecFeature.self,
      SpecFeature.jsonSchemaDialect,
      SpecFeature.webhooks,
      SpecFeature.infoSummary,
      SpecFeature.tagHierarchy,
      SpecFeature.componentPathItems,
      SpecFeature.componentMediaTypes,
      SpecFeature.mutualTls,
    });
  });

  test('parseFragment reads a node as the kind a reference expects', () {
    final fixture = SpecFixture('''
openapi: 3.0.3
x-shared:
  limit: {name: limit, in: query, schema: {type: integer}}
''');
    final parser = OpenApiParser(
      fixture.diagnostics,
      fixture.document,
      fixture.index,
    );
    final at = JsonPointer.parse('#/x-shared/limit');
    final limit = parser.parseFragment(at, RefKind.parameter)! as Parameter;
    expect(limit.name, 'limit');
    expect(
      parser.parseFragment(at.child('schema'), RefKind.schema),
      isA<SchemaObject>(),
    );
    expect(fixture.diagnostics.all, isEmpty);
  });
}
```

- [ ] **Step 2: Make sure the tests fail**

Run (from `packages/typed_openapi`): `dart test test/parse`
Expected: FAIL, the first error — `cannot read 'lib/src/model/document.dart': No such file or directory`

- [ ] **Step 3: Create `security.dart`**

Create `packages/typed_openapi/lib/src/model/security.dart`:

```dart
import 'spec_node.dart';

/// The `type` of a security scheme.
enum SecuritySchemeType {
  /// An API key in a header, query parameter or cookie.
  apiKey,

  /// HTTP authentication, such as `bearer` or `basic`.
  http,

  /// Mutual TLS (OpenAPI 3.1).
  mutualTLS,

  /// OAuth 2.
  oauth2,

  /// OpenID Connect discovery.
  openIdConnect,
}

/// Where an API key is sent: the `in` field of an `apiKey` scheme.
enum ApiKeyLocation {
  /// A query parameter.
  query,

  /// A header.
  header,

  /// A cookie.
  cookie,
}

/// A Security Scheme Object.
final class SecurityScheme extends SpecNode {
  /// Creates a security scheme.
  const SecurityScheme({
    required super.location,
    this.type,
    this.description,
    this.name,
    this.placement,
    this.scheme,
    this.bearerFormat,
    this.flows,
    this.openIdConnectUrl,
    this.oauth2MetadataUrl,
    this.deprecated = false,
    super.extensions,
    super.unknownKeys,
  });

  /// `type`; required by the spec.
  final SecuritySchemeType? type;

  /// `description`.
  final String? description;

  /// `name` of the header, query parameter or cookie of an `apiKey`.
  final String? name;

  /// `in` of an `apiKey`.
  final ApiKeyLocation? placement;

  /// `scheme` of `http`, such as `bearer`.
  final String? scheme;

  /// `bearerFormat`.
  final String? bearerFormat;

  /// `flows` of `oauth2`.
  final OAuthFlows? flows;

  /// `openIdConnectUrl`.
  final String? openIdConnectUrl;

  /// `oauth2MetadataUrl` (OpenAPI 3.2).
  final String? oauth2MetadataUrl;

  /// `deprecated` (OpenAPI 3.2).
  final bool deprecated;
}

/// An OAuth Flows Object.
final class OAuthFlows extends SpecNode {
  /// Creates the flows.
  const OAuthFlows({
    required super.location,
    this.implicit,
    this.password,
    this.clientCredentials,
    this.authorizationCode,
    this.deviceAuthorization,
    super.extensions,
    super.unknownKeys,
  });

  /// `implicit`.
  final OAuthFlow? implicit;

  /// `password`.
  final OAuthFlow? password;

  /// `clientCredentials`.
  final OAuthFlow? clientCredentials;

  /// `authorizationCode`.
  final OAuthFlow? authorizationCode;

  /// `deviceAuthorization` (OpenAPI 3.2).
  final OAuthFlow? deviceAuthorization;
}

/// An OAuth Flow Object.
final class OAuthFlow extends SpecNode {
  /// Creates a flow.
  const OAuthFlow({
    required super.location,
    this.authorizationUrl,
    this.deviceAuthorizationUrl,
    this.tokenUrl,
    this.refreshUrl,
    this.scopes = const {},
    super.extensions,
    super.unknownKeys,
  });

  /// `authorizationUrl`.
  final String? authorizationUrl;

  /// `deviceAuthorizationUrl` (OpenAPI 3.2).
  final String? deviceAuthorizationUrl;

  /// `tokenUrl`.
  final String? tokenUrl;

  /// `refreshUrl`.
  final String? refreshUrl;

  /// `scopes`: scope name to description.
  final Map<String, String> scopes;
}
```

- [ ] **Step 4: Create `document.dart`**

Create `packages/typed_openapi/lib/src/model/document.dart`:

```dart
import '../load/openapi_version.dart';
import 'operation.dart';
import 'schema.dart';
import 'security.dart';
import 'spec_node.dart';

/// An OpenAPI document read into the typed model.
///
/// The model is a superset of OpenAPI 3.0, 3.1 and 3.2: it holds what any of
/// them can say, whatever [version] the document declares. Keys the model
/// does not type, such as `externalDocs` or `links`, stay in the
/// `SpecDocument` under the node's pointer.
final class OpenApiDocument extends SpecNode {
  /// Creates a document.
  const OpenApiDocument({
    required super.location,
    this.version,
    this.self,
    this.info,
    this.jsonSchemaDialect,
    this.servers = const [],
    this.paths = const {},
    this.webhooks = const {},
    this.components,
    this.security,
    this.tags = const [],
    super.extensions,
    super.unknownKeys,
  });

  /// The OpenAPI line the document declares, or null when unknown.
  final OpenApiVersion? version;

  /// `$self` (OpenAPI 3.2).
  final String? self;

  /// `info`; required by the spec.
  final Info? info;

  /// `jsonSchemaDialect` (OpenAPI 3.1).
  final String? jsonSchemaDialect;

  /// `servers`.
  final List<Server> servers;

  /// `paths` by path template, in document order; `x-` keys of the Paths
  /// Object are not included.
  final Map<String, RefOr<PathItem>> paths;

  /// `webhooks` (OpenAPI 3.1).
  final Map<String, RefOr<PathItem>> webhooks;

  /// `components`.
  final Components? components;

  /// `security`; null when the document does not set it.
  final List<SecurityRequirement>? security;

  /// `tags`.
  final List<Tag> tags;
}

/// An Info Object.
final class Info extends SpecNode {
  /// Creates an info object.
  const Info({
    required super.location,
    this.title,
    this.summary,
    this.description,
    this.version,
    super.extensions,
    super.unknownKeys,
  });

  /// `title`; required by the spec.
  final String? title;

  /// `summary` (OpenAPI 3.1).
  final String? summary;

  /// `description`.
  final String? description;

  /// `version` of the API (not of OpenAPI); required by the spec.
  final String? version;
}

/// A Tag Object.
final class Tag extends SpecNode {
  /// Creates a tag.
  const Tag({
    required super.location,
    this.name,
    this.summary,
    this.description,
    this.parent,
    this.kind,
    super.extensions,
    super.unknownKeys,
  });

  /// `name`; required by the spec.
  final String? name;

  /// `summary` (OpenAPI 3.2).
  final String? summary;

  /// `description`.
  final String? description;

  /// `parent` tag name (OpenAPI 3.2).
  final String? parent;

  /// `kind`, such as `nav` (OpenAPI 3.2).
  final String? kind;
}

/// A Components Object.
final class Components extends SpecNode {
  /// Creates the components.
  const Components({
    required super.location,
    this.schemas = const {},
    this.responses = const {},
    this.parameters = const {},
    this.examples = const {},
    this.requestBodies = const {},
    this.headers = const {},
    this.securitySchemes = const {},
    this.pathItems = const {},
    this.mediaTypes = const {},
    super.extensions,
    super.unknownKeys,
  });

  /// `schemas`.
  final Map<String, Schema> schemas;

  /// `responses`.
  final Map<String, RefOr<Response>> responses;

  /// `parameters`.
  final Map<String, RefOr<Parameter>> parameters;

  /// `examples`.
  final Map<String, RefOr<Example>> examples;

  /// `requestBodies`.
  final Map<String, RefOr<RequestBody>> requestBodies;

  /// `headers`.
  final Map<String, RefOr<Header>> headers;

  /// `securitySchemes`.
  final Map<String, RefOr<SecurityScheme>> securitySchemes;

  /// `pathItems` (OpenAPI 3.1).
  final Map<String, RefOr<PathItem>> pathItems;

  /// `mediaTypes` (OpenAPI 3.2).
  final Map<String, RefOr<MediaType>> mediaTypes;
}
```

- [ ] **Step 5: Create `openapi_parser.dart`**

Create `packages/typed_openapi/lib/src/parse/openapi_parser.dart`:

```dart
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/json_pointer.dart';
import '../load/openapi_version.dart';
import '../load/spec_document.dart';
import '../model/document.dart';
import '../model/security.dart';
import '../model/spec_node.dart';
import 'object_reader.dart';
import 'operation_parser.dart';
import 'parse_context.dart';
import 'schema_parser.dart';
import 'spec_feature.dart';

/// Reads a [SpecDocument] into the typed model.
///
/// Wrong JSON types, missing required fields and unknown keys are reported
/// to the [DiagnosticBag] and the rest of the document is still read. Every
/// node, `$ref` and version-specific construct goes into the [SpecIndex]
/// given to the constructor, which several parsers of one run share.
final class OpenApiParser {
  /// Creates a parser for [document].
  factory OpenApiParser(
    DiagnosticBag diagnostics,
    SpecDocument document,
    SpecIndex index,
  ) {
    final context = ParseContext(diagnostics, document, index);
    final schemas = SchemaParser(context);
    return OpenApiParser._(
      context,
      schemas,
      OperationParser(context, schemas),
    );
  }

  OpenApiParser._(this._context, this._schemas, this._operations);

  final ParseContext _context;
  final SchemaParser _schemas;
  final OperationParser _operations;

  /// Reads the whole document, which declares [version].
  OpenApiDocument parse(OpenApiVersion? version) {
    final r = ObjectReader(_context, _context.document.root, .root);
    final at = r.pointer;
    r.accept(const ['openapi', 'externalDocs']);
    if (r.has(r'$self')) {
      _context.note(.self, at.child(r'$self'));
      _context.report(
        .refBaseIgnored,
        r'"$self" changes the base URI of "$ref"s; they are resolved '
        'against the file location instead.',
        at.child(r'$self'),
      );
    }
    for (final (key, feature) in const [
      ('jsonSchemaDialect', SpecFeature.jsonSchemaDialect),
      ('webhooks', SpecFeature.webhooks),
    ]) {
      if (r.has(key)) _context.note(feature, at.child(key));
    }
    return _context.register(
      OpenApiDocument(
        location: r.location,
        version: version,
        self: r.string(r'$self'),
        info: r.requiredObject('info', _info),
        jsonSchemaDialect: r.string('jsonSchemaDialect'),
        servers: r.list('servers', _operations.server) ?? const [],
        paths:
            r.map('paths', _operations.pathItem, skipExtensions: true) ??
            const {},
        webhooks: r.map('webhooks', _operations.pathItem) ?? const {},
        components: r.object('components', _components),
        security: r.list('security', _operations.securityRequirement),
        tags: r.list('tags', _tag) ?? const [],
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  /// Reads the node at [pointer] as a [kind] node, for a `$ref` that points
  /// there; null after reporting when the node has the wrong shape.
  SpecNode? parseFragment(JsonPointer pointer, RefKind kind) {
    final raw = _context.document.valueAt(pointer)?.$1;
    final RefOr<SpecNode>? node = switch (kind) {
      .schema => null,
      .response => _operations.response(raw, pointer),
      .parameter => _operations.parameter(raw, pointer),
      .example => _operations.example(raw, pointer),
      .requestBody => _operations.requestBody(raw, pointer),
      .header => _operations.header(raw, pointer),
      .securityScheme => _securityScheme(raw, pointer),
      .pathItem => _operations.pathItem(raw, pointer),
      .mediaType => _operations.mediaType(raw, pointer),
    };
    return switch (node) {
      Ref() => node,
      Inline(:final value) => value,
      null => kind == .schema ? _schemas.parse(raw, pointer) : null,
    };
  }

  Info _info(ObjectReader r) {
    if (r.has('summary')) {
      _context.note(.infoSummary, r.pointer.child('summary'));
    }
    r.accept(const ['termsOfService', 'contact', 'license']);
    return _context.register(
      Info(
        location: r.location,
        title: r.requiredString('title'),
        summary: r.string('summary'),
        description: r.string('description'),
        version: r.requiredString('version'),
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  Tag? _tag(Object? raw, JsonPointer pointer) {
    final r = _context.reader(raw, pointer, 'A tag');
    if (r == null) return null;
    for (final key in const ['summary', 'parent', 'kind']) {
      if (r.has(key)) _context.note(.tagHierarchy, pointer.child(key));
    }
    r.accept(const ['externalDocs']);
    return _context.register(
      Tag(
        location: r.location,
        name: r.requiredString('name'),
        summary: r.string('summary'),
        description: r.string('description'),
        parent: r.string('parent'),
        kind: r.string('kind'),
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  Components _components(ObjectReader r) {
    for (final (key, feature) in const [
      ('pathItems', SpecFeature.componentPathItems),
      ('mediaTypes', SpecFeature.componentMediaTypes),
    ]) {
      if (r.has(key)) _context.note(feature, r.pointer.child(key));
    }
    r.accept(const ['links', 'callbacks']);
    return _context.register(
      Components(
        location: r.location,
        schemas: r.map('schemas', _schemas.parse) ?? const {},
        responses: r.map('responses', _operations.response) ?? const {},
        parameters: r.map('parameters', _operations.parameter) ?? const {},
        examples: r.map('examples', _operations.example) ?? const {},
        requestBodies:
            r.map('requestBodies', _operations.requestBody) ?? const {},
        headers: r.map('headers', _operations.header) ?? const {},
        securitySchemes: r.map('securitySchemes', _securityScheme) ?? const {},
        pathItems: r.map('pathItems', _operations.pathItem) ?? const {},
        mediaTypes: r.map('mediaTypes', _operations.mediaType) ?? const {},
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  RefOr<SecurityScheme>? _securityScheme(Object? raw, JsonPointer pointer) =>
      _context.refOr(raw, pointer, .securityScheme, (r) {
        final type = r.requiredChoice(
          'type',
          SecuritySchemeType.values.asNameMap(),
        );
        if (type == .mutualTLS) {
          _context.note(.mutualTls, r.pointer.child('type'));
        }
        for (final key in const ['deprecated', 'oauth2MetadataUrl']) {
          if (r.has(key)) {
            _context.note(.securitySchemeExtras, r.pointer.child(key));
          }
        }
        String? field(String key, SecuritySchemeType requiredFor) =>
            type == requiredFor ? r.requiredString(key) : r.string(key);
        return _context.register(
          SecurityScheme(
            location: r.location,
            type: type,
            description: r.string('description'),
            name: field('name', .apiKey),
            placement: r.choice('in', ApiKeyLocation.values.asNameMap()),
            scheme: field('scheme', .http),
            bearerFormat: r.string('bearerFormat'),
            flows: type == .oauth2
                ? r.requiredObject('flows', _flows)
                : r.object('flows', _flows),
            openIdConnectUrl: field('openIdConnectUrl', .openIdConnect),
            oauth2MetadataUrl: r.string('oauth2MetadataUrl'),
            deprecated: r.boolean('deprecated') ?? false,
            extensions: r.extensions,
            unknownKeys: r.unknownKeys(),
          ),
        );
      });

  OAuthFlows _flows(ObjectReader r) {
    if (r.has('deviceAuthorization')) {
      _context.note(
        .deviceAuthorization,
        r.pointer.child('deviceAuthorization'),
      );
    }
    return _context.register(
      OAuthFlows(
        location: r.location,
        implicit: r.object('implicit', _flow),
        password: r.object('password', _flow),
        clientCredentials: r.object('clientCredentials', _flow),
        authorizationCode: r.object('authorizationCode', _flow),
        deviceAuthorization: r.object('deviceAuthorization', _flow),
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  OAuthFlow _flow(ObjectReader r) => _context.register(
    OAuthFlow(
      location: r.location,
      authorizationUrl: r.string('authorizationUrl'),
      deviceAuthorizationUrl: r.string('deviceAuthorizationUrl'),
      tokenUrl: r.string('tokenUrl'),
      refreshUrl: r.string('refreshUrl'),
      scopes: r.stringMap('scopes') ?? const {},
      extensions: r.extensions,
      unknownKeys: r.unknownKeys(),
    ),
  );
}
```

- [ ] **Step 6: Make sure the tests pass**

Run (from `packages/typed_openapi`): `dart test test/parse`
Expected: `+29: All tests passed!`

- [ ] **Step 7: Format, analyzer, the whole test suite**

Run (from `packages/typed_openapi`): `dart format --output=none --set-exit-if-changed lib test bin && dart test`
Expected: `Formatted 47 files (0 changed)`, `+103: All tests passed!`

Run (from the root): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add packages/typed_openapi/lib/src/model/document.dart packages/typed_openapi/lib/src/model/security.dart packages/typed_openapi/lib/src/parse/openapi_parser.dart packages/typed_openapi/test/parse/openapi_parser_test.dart
git commit -m 'feat(typed_openapi): document, components and security schemes' -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
```

---

### Task 8: Dialect by content: `DialectChecker` (TOA020–TOA022)

**Files:**
- Create: `packages/typed_openapi/lib/src/parse/dialect_checker.dart`
- Create: `packages/typed_openapi/test/parse/dialect_checker_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`
- Modify: `packages/typed_openapi/lib/src/load/openapi_version.dart`

**Interfaces:**
- Consumes: `FeatureUse`, `SpecFeature` (Task 4), `OpenApiParser` (Task 7) — in tests.
- Produces: `OpenApiVersion.label` (`'3.0'`, `'3.1'`, `'3.2'`); `final class DialectChecker { const DialectChecker(DiagnosticBag); void check(List<FeatureUse> uses, OpenApiVersion version); }`; codes `openApi31InOpenApi30` (TOA020), `nullableAfterOpenApi30` (TOA021), `openApi32InOlder` (TOA022).

The behaviour the tests pin down:
- 3.1 constructs in a 3.0 document — `TOA020` warning, one per construct, at the place of its first use; the message says how many places there are.
- `nullable` in 3.1 and 3.2 — `TOA021` warning with a position.
- 3.2 constructs in 3.0/3.1 — `TOA022` info; in 3.2 — nothing.

- [ ] **Step 1: Write a failing test**

Create `packages/typed_openapi/test/parse/dialect_checker_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/load/openapi_version.dart';
import 'package:typed_openapi/src/parse/dialect_checker.dart';
import 'package:typed_openapi/src/parse/openapi_parser.dart';

import '../helpers/spec_fixture.dart';

void main() {
  DiagnosticBag check(String yaml, OpenApiVersion version) {
    final fixture = SpecFixture(yaml);
    OpenApiParser(
      fixture.diagnostics,
      fixture.document,
      fixture.index,
    ).parse(version);
    final bag = DiagnosticBag();
    DialectChecker(bag).check(fixture.index.features, version);
    return bag;
  }

  const schemas = '''
info: {title: t, version: "1"}
components:
  schemas:
    A: {type: [string, "null"]}
    B: {type: string, nullable: true}
    C: {const: c}
    D: {const: d}
''';

  test('3.1 constructs in a 3.0 document: one warning per construct', () {
    final bag = check(schemas, .v30);
    expect(bag.all.map((d) => (d.code, d.pointer?.value)), [
      (DiagnosticCode.openApi31InOpenApi30, '#/components/schemas/A/type'),
      (DiagnosticCode.openApi31InOpenApi30, '#/components/schemas/A/type/1'),
      (DiagnosticCode.openApi31InOpenApi30, '#/components/schemas/C/const'),
    ]);
    expect(bag.all.first.severity, Severity.warning);
    expect(
      bag.all.last.message,
      '"const" is OpenAPI 3.1 (JSON Schema 2020-12), but the document '
      'declares 3.0; it is read as 3.1. It is used in 2 places; this is the '
      'first.',
    );
  });

  test('nullable in a 3.1 document is a warning', () {
    final bag = check(schemas, .v31);
    final d = bag.all.single;
    expect(d.code, DiagnosticCode.nullableAfterOpenApi30);
    expect(d.pointer?.value, '#/components/schemas/B/nullable');
    expect(d.line, 5);
  });

  test('3.2 constructs in older documents are infos', () {
    const yaml = '''
info: {title: t, version: "1"}
paths:
  /events:
    get:
      responses:
        "200":
          description: Events.
          content:
            text/event-stream:
              itemSchema: {type: object}
''';
    final bag = check(yaml, .v31);
    expect(bag.all.single.code, DiagnosticCode.openApi32InOlder);
    expect(bag.all.single.severity, Severity.info);
    expect(check(yaml, .v32).all, isEmpty);
  });

  test('a 3.2 document may use everything but nullable', () {
    final bag = check(schemas, .v32);
    expect(bag.all.single.code, DiagnosticCode.nullableAfterOpenApi30);
  });
}
```

- [ ] **Step 2: Make sure the tests fail**

Run (from `packages/typed_openapi`): `dart test test/parse`
Expected: FAIL, the first error — `cannot read 'lib/src/parse/dialect_checker.dart': No such file or directory`

- [ ] **Step 3: Add the codes to the catalog**

In `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart` after the snippet:

```dart
    'openapi-version-not-string',
    .warning,
  ),
```

insert:

```dart
  /// A 3.0 document uses an OpenAPI 3.1 or JSON Schema 2020-12 construct;
  /// it is read as 3.1.
  openApi31InOpenApi30('TOA020', 'openapi-3-1-in-3-0', .warning),

  /// A 3.1 or later document uses `nullable`, which only 3.0 defines; it is
  /// read as in 3.0.
  nullableAfterOpenApi30('TOA021', 'nullable-after-3-0', .warning),

  /// A document older than 3.2 uses an OpenAPI 3.2 construct; it is read
  /// anyway.
  openApi32InOlder('TOA022', 'openapi-3-2-in-older', .info),
```

- [ ] **Step 4: Change `openapi_version.dart`**

In `packages/typed_openapi/lib/src/load/openapi_version.dart` replace:

```dart
enum OpenApiVersion {
  /// OpenAPI 3.0.x.
  v30,

  /// OpenAPI 3.1.x.
  v31,

  /// OpenAPI 3.2.x.
  v32,
}
```

with:

```dart
enum OpenApiVersion {
  /// OpenAPI 3.0.x.
  v30('3.0'),

  /// OpenAPI 3.1.x.
  v31('3.1'),

  /// OpenAPI 3.2.x.
  v32('3.2');

  const OpenApiVersion(this.label);

  /// The version as people write it, such as `3.1`.
  final String label;
}
```

- [ ] **Step 5: Create `dialect_checker.dart`**

Create `packages/typed_openapi/lib/src/parse/dialect_checker.dart`:

```dart
import '../diagnostics/diagnostic_bag.dart';
import '../load/openapi_version.dart';
import 'parse_context.dart';
import 'spec_feature.dart';

/// Reports constructs that the version a document declares does not have.
///
/// The dialect of a document is decided by its content: the parser reads
/// every construct, and this check says where the content and the declared
/// `openapi` version disagree. Each construct is reported once, at its first
/// use, with the number of uses.
final class DialectChecker {
  /// Creates a checker that reports to [_diagnostics].
  const DialectChecker(this._diagnostics);

  final DiagnosticBag _diagnostics;

  /// Reports the [uses] that [version] does not define.
  void check(List<FeatureUse> uses, OpenApiVersion version) {
    final byFeature = <SpecFeature, List<FeatureUse>>{};
    for (final use in uses) {
      byFeature.putIfAbsent(use.feature, () => []).add(use);
    }
    for (final MapEntry(key: feature, value: found) in byFeature.entries) {
      final first = found.first;
      final count = found.length == 1
          ? ''
          : ' It is used in ${found.length} places; this is the first.';
      final declared = 'the document declares ${version.label}';
      final since = feature.since;
      final until = feature.until;
      if (since != null && version.index < since.index) {
        final is31 = since == .v31;
        _diagnostics.report(
          is31 ? .openApi31InOpenApi30 : .openApi32InOlder,
          is31
              ? '${feature.label} is OpenAPI 3.1 (JSON Schema 2020-12), but '
                    '$declared; it is read as 3.1.$count'
              : '${feature.label} is OpenAPI 3.2, but $declared; it is read '
                    'anyway.$count',
          file: first.file,
          pointer: first.pointer,
          span: first.span,
          fix:
              'Declare "openapi: ${since.label}.0" if the backend emits '
              '${since.label}; otherwise remove the construct.',
        );
      } else if (until != null && version.index >= until.index) {
        _diagnostics.report(
          .nullableAfterOpenApi30,
          '${feature.label} exists only in OpenAPI 3.0, but $declared; it '
          'is read as in 3.0.$count',
          file: first.file,
          pointer: first.pointer,
          span: first.span,
          fix: 'Write type: [<type>, "null"] instead of nullable: true.',
        );
      }
    }
  }
}
```

- [ ] **Step 6: Make sure the tests pass**

Run (from `packages/typed_openapi`): `dart test test/parse`
Expected: `+33: All tests passed!`

- [ ] **Step 7: Format, analyzer, the whole test suite**

Run (from `packages/typed_openapi`): `dart format --output=none --set-exit-if-changed lib test bin && dart test`
Expected: `Formatted 49 files (0 changed)`, `+107: All tests passed!`

Run (from the root): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart packages/typed_openapi/lib/src/load/openapi_version.dart packages/typed_openapi/lib/src/parse/dialect_checker.dart packages/typed_openapi/test/parse/dialect_checker_test.dart
git commit -m 'feat(typed_openapi): detect the schema dialect by content' -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
```

---

### Task 9: Parsing a `$ref` value: `RefTarget` (TOA100, TOA102)

**Files:**
- Create: `packages/typed_openapi/lib/src/resolve/ref_target.dart`
- Create: `packages/typed_openapi/test/resolve/ref_target_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`

**Interfaces:**
- Consumes: `SpecLocation` (Task 3), `JsonPointer`, `DiagnosticCode`.
- Produces: `sealed class RefTarget { factory RefTarget.parse(String ref, Uri base); }`, `ResolvableRef(SpecLocation location)`, `BrokenRef(DiagnosticCode code, String reason, {String? fix})`; codes `invalidRef` (TOA100), `remoteRef` (TOA102).

The behaviour the tests pin down:
- A local pointer stays in the same document; a relative file is resolved against the document's URI; without a fragment — the root of the file.
- The fragment is percent-decoded (`%7Bid%7D` → `{id}`), the escapes `~0`/`~1` are kept in the pointer.
- `https:`, `urn:` — `TOA102`. An empty string, `#/components/schemas/`, `#/`, `#/components/schemas`, `#/components`, `#Pet`, a malformed `%`, a malformed `~`, an invalid URI — `TOA100` with an explanation.

- [ ] **Step 1: Write a failing test**

Create `packages/typed_openapi/test/resolve/ref_target_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/resolve/ref_target.dart';

void main() {
  final base = Uri.parse('file:///project/specs/api.yaml');

  String target(String ref) => switch (RefTarget.parse(ref, base)) {
    ResolvableRef(:final location) => '$location',
    BrokenRef(:final code) => code.id,
  };

  test('a local pointer stays in the same document', () {
    expect(
      target('#/components/schemas/Pet'),
      'file:///project/specs/api.yaml#/components/schemas/Pet',
    );
  });

  test('a relative file resolves against the document', () {
    expect(
      target('../common/errors.yaml#/Error'),
      'file:///project/common/errors.yaml#/Error',
    );
    expect(target('./pet.yaml'), 'file:///project/specs/pet.yaml#');
  });

  test('the fragment is percent-decoded and keeps ~ escapes', () {
    expect(
      target('#/paths/~1pets~1%7Bid%7D/get'),
      'file:///project/specs/api.yaml#/paths/~1pets~1{id}/get',
    );
  });

  test('remote documents are not read', () {
    expect(target('https://example.com/api.yaml#/A'), 'TOA102');
    expect(target('urn:example:pet'), 'TOA102');
  });

  test('empty, truncated and malformed references are invalid', () {
    for (final ref in [
      '',
      '#/components/schemas/',
      '#/',
      '#/components/schemas',
      '#/components',
      '#Pet',
      '#/a/%zz',
      '#/a~2b',
      'http://[bad#/a',
    ]) {
      expect(target(ref), 'TOA100', reason: ref);
    }
  });

  test('a broken reference says why', () {
    final broken = RefTarget.parse('#/components/schemas/', base) as BrokenRef;
    expect(broken.code, DiagnosticCode.invalidRef);
    expect(
      broken.reason,
      '"#/components/schemas/" ends with "/", so the name of the target is '
      'missing.',
    );
  });
}
```

- [ ] **Step 2: Make sure the tests fail**

Run (from `packages/typed_openapi`): `dart test test/resolve`
Expected: FAIL, the first error — `cannot read 'lib/src/resolve/ref_target.dart': No such file or directory`

- [ ] **Step 3: Add the codes to the catalog**

In `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart` before the snippet:

```dart
  /// `$id` or `$self` would change the base URI of `$ref`s; this tool
```

insert:

```dart
  /// A `$ref` is empty, truncated or not a URI with a JSON pointer.
  invalidRef('TOA100', 'invalid-ref', .error),

  /// A `$ref` points to a remote URL; only local files are read.
  remoteRef('TOA102', 'remote-ref', .error),
```

- [ ] **Step 4: Create `ref_target.dart`**

Create `packages/typed_openapi/lib/src/resolve/ref_target.dart`:

```dart
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/json_pointer.dart';
import '../model/spec_node.dart';

/// What a `$ref` value points to, or why it cannot be followed.
sealed class RefTarget {
  const RefTarget();

  /// Reads [ref], written in the document at [base].
  ///
  /// The part before `#` is a URI relative to [base]; the fragment is a JSON
  /// pointer, percent-decoded. Remote URIs, plain-name fragments (`#foo`)
  /// and pointers that stop at a components section or end with `/` cannot
  /// be followed.
  factory RefTarget.parse(String ref, Uri base) {
    if (ref.isEmpty) {
      return const BrokenRef(.invalidRef, r'The "$ref" is empty.');
    }
    final hash = ref.indexOf('#');
    final address = hash < 0 ? ref : ref.substring(0, hash);
    final fragment = hash < 0 ? '' : ref.substring(hash + 1);
    final Uri document;
    if (address.isEmpty) {
      document = base;
    } else {
      final Uri parsed;
      try {
        parsed = Uri.parse(address);
      } on FormatException {
        return BrokenRef(.invalidRef, '"$ref" is not a valid URI.');
      }
      if (parsed.hasScheme && parsed.scheme != 'file') {
        return BrokenRef(
          .remoteRef,
          '"$ref" points to a remote document; only local files are read.',
          fix:
              'Save the document next to the spec and refer to it by a '
              'relative path.',
        );
      }
      document = base.resolveUri(parsed).removeFragment();
    }
    final pointer = _pointer(fragment);
    if (pointer == null) {
      return BrokenRef(
        .invalidRef,
        '"$ref" does not end with a JSON pointer such as '
        '"#/components/schemas/Name".',
        fix: r'Plain-name fragments ($anchor) are not supported.',
      );
    }
    final tokens = pointer.tokens;
    if (tokens.isNotEmpty && tokens.last.isEmpty) {
      return BrokenRef(
        .invalidRef,
        '"$ref" ends with "/", so the name of the target is missing.',
        fix:
            'Fix the code that writes the spec; in NestJS this usually '
            'means a circular import made a DTO type undefined.',
      );
    }
    if (tokens.length <= 2 && tokens.firstOrNull == 'components') {
      return BrokenRef(
        .invalidRef,
        '"$ref" points at a whole components section, not at one entry.',
      );
    }
    return ResolvableRef(SpecLocation(document, pointer));
  }

  static final _badPercent = RegExp('%(?![0-9A-Fa-f]{2})');
  static final _badTilde = RegExp('~(?![01])');

  static JsonPointer? _pointer(String fragment) {
    if (fragment.isEmpty) return JsonPointer.root;
    if (!fragment.startsWith('/') || _badPercent.hasMatch(fragment)) {
      return null;
    }
    final String decoded;
    try {
      decoded = fragment.contains('%')
          ? Uri.decodeComponent(fragment)
          : fragment;
    } on FormatException {
      return null;
    }
    if (_badTilde.hasMatch(decoded)) return null;
    return JsonPointer.parse('#$decoded');
  }
}

/// A `$ref` to a node in a local file.
final class ResolvableRef extends RefTarget {
  /// Creates a target at [location].
  const ResolvableRef(this.location);

  /// The file and pointer the `$ref` names.
  final SpecLocation location;
}

/// A `$ref` that cannot be followed.
final class BrokenRef extends RefTarget {
  /// Creates a broken target; [reason] becomes the diagnostic message.
  const BrokenRef(this.code, this.reason, {this.fix});

  /// The diagnostic code to report.
  final DiagnosticCode code;

  /// Why the `$ref` cannot be followed.
  final String reason;

  /// How to fix the `$ref`.
  final String? fix;
}
```

- [ ] **Step 5: Make sure the tests pass**

Run (from `packages/typed_openapi`): `dart test test/resolve`
Expected: `+6: All tests passed!`

- [ ] **Step 6: Format, analyzer, the whole test suite**

Run (from `packages/typed_openapi`): `dart format --output=none --set-exit-if-changed lib test bin && dart test`
Expected: `Formatted 51 files (0 changed)`, `+113: All tests passed!`

Run (from the root): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart packages/typed_openapi/lib/src/resolve/ref_target.dart packages/typed_openapi/test/resolve/ref_target_test.dart
git commit -m 'feat(typed_openapi): parse $ref values' -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
```

---

### Task 10: The `$ref` resolver: local and file references (TOA101, TOA104)

**Files:**
- Create: `packages/typed_openapi/lib/src/resolve/spec_documents.dart`
- Create: `packages/typed_openapi/lib/src/resolve/spec_model.dart`
- Create: `packages/typed_openapi/lib/src/resolve/ref_resolver.dart`
- Create: `packages/typed_openapi/test/resolve/ref_resolver_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`

**Interfaces:**
- Consumes: `RefTarget` (Task 9), `OpenApiParser.parseFragment` (Task 7), `SpecIndex`, `RefUse` (Task 4), `SpecLoader`, `SpecDocument.valueAt` (Task 1), all the models.
- Produces: `final class SpecDocuments { SpecDocuments(SpecLoader, SpecDocument root); SpecDocument? operator [](Uri uri); String displayPath(Uri uri); }`; `final class SpecModel { SpecModel({required OpenApiDocument document, required Map<SpecLocation, SpecNode> nodes, required Map<SpecLocation, SpecLocation> targets}); nodeAt, targetOf, resolve<T>, resolveSchema }`; `final class RefResolver { const RefResolver(DiagnosticBag); SpecModel resolve(OpenApiDocument document, SpecIndex index, SpecDocuments documents); }`; codes `unresolvedRef` (TOA101), `refKindMismatch` (TOA104).

The behaviour the tests pin down:
- Local references are resolved, including through a chain of aliases in `components`; `SpecModel.resolve`/`resolveSchema` return the final node, `targetOf` — the direct target.
- A recursive schema — no diagnostics, `resolveSchema` returns the schema itself.
- A dangling reference — `TOA101` at the pointer `…/$ref` with a position; `resolveSchema` → `null`.
- `#/components/schemas/` — `TOA100` at the place where it is written.
- References to other files: a target is identified by file + pointer (the same pointer in two files — different nodes), a `$ref` inside another file is resolved from that file, and the diagnostics there name `specs/common/errors.yaml`.
- A missing file — `TOA101` with the file name; a URL — `TOA102`; a file referenced twice is read (and its syntax error reported) once.
- A parameter → schema — `TOA104`; a target outside `components` (`#/x-shared/limit`) is read as the expected kind and registered.

- [ ] **Step 1: Write a failing test**

Create `packages/typed_openapi/test/resolve/ref_resolver_test.dart`:

```dart
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/model/schema.dart';
import 'package:typed_openapi/src/parse/openapi_parser.dart';
import 'package:typed_openapi/src/parse/parse_context.dart';
import 'package:typed_openapi/src/resolve/ref_resolver.dart';
import 'package:typed_openapi/src/resolve/spec_documents.dart';
import 'package:typed_openapi/src/resolve/spec_model.dart';

import '../helpers/temp_dir.dart';

void main() {
  late TempDir dir;

  setUp(() => dir = TempDir());

  (SpecModel, DiagnosticBag) resolve(String rootFile) {
    final bag = DiagnosticBag();
    final loader = SpecLoader(bag);
    final root = loader.load(
      p.join(dir.path, rootFile),
      displayPath: rootFile,
    )!;
    final index = SpecIndex();
    final document = OpenApiParser(bag, root, index).parse(.v31);
    final model = RefResolver(
      bag,
    ).resolve(document, index, SpecDocuments(loader, root));
    return (model, bag);
  }

  const info = 'openapi: 3.1.0\ninfo: {title: t, version: "1"}';

  test('resolves local references, through aliases', () {
    dir.write('api.yaml', '''
$info
paths:
  /pets:
    get:
      parameters: [{\$ref: "#/components/parameters/Limit"}]
      responses:
        "200":
          description: OK
          content:
            application/json:
              schema: {\$ref: "#/components/schemas/Pets"}
components:
  parameters:
    Limit: {\$ref: "#/components/parameters/PageSize"}
    PageSize: {name: size, in: query}
  schemas:
    Pets: {type: array, items: {\$ref: "#/components/schemas/Pet"}}
    Pet: {type: object}
''');
    final (model, bag) = resolve('api.yaml');
    expect(bag.all, isEmpty);
    final get = model.resolve(model.document.paths['/pets']!)!;
    final parameter = model.resolve(get.operations['get']!.parameters.single);
    expect(parameter!.name, 'size');
    final pets = model.document.components!.schemas['Pets']! as SchemaObject;
    final pet = model.resolveSchema(pets.items!)! as SchemaObject;
    expect(pet.pointer.value, '#/components/schemas/Pet');
    expect(model.targetOf(pets.items!.location), pet.location);
  });

  test('a recursive schema is not a problem', () {
    dir.write('api.yaml', '''
$info
components:
  schemas:
    Node:
      type: object
      properties:
        children: {type: array, items: {\$ref: "#/components/schemas/Node"}}
''');
    final (model, bag) = resolve('api.yaml');
    expect(bag.all, isEmpty);
    final node = model.document.components!.schemas['Node']! as SchemaObject;
    final children = node.properties['children']! as SchemaObject;
    expect(model.resolveSchema(children.items!), same(node));
  });

  test('a reference to nothing is unresolved', () {
    dir.write('api.yaml', '''
$info
components:
  schemas:
    Owner: {\$ref: "#/components/schemas/Person"}
''');
    final (model, bag) = resolve('api.yaml');
    final d = bag.all.single;
    expect(d.code, DiagnosticCode.unresolvedRef);
    expect(d.pointer?.value, r'#/components/schemas/Owner/$ref');
    expect(d.line, 5);
    final owner = model.document.components!.schemas['Owner']!;
    expect(model.resolveSchema(owner), isNull);
  });

  test('an empty name is invalid and reported where it is written', () {
    dir.write('api.yaml', '''
$info
components:
  schemas:
    Owner:
      properties:
        pet: {\$ref: "#/components/schemas/"}
''');
    final (_, bag) = resolve('api.yaml');
    final d = bag.all.single;
    expect(d.code, DiagnosticCode.invalidRef);
    expect(d.pointer?.value, r'#/components/schemas/Owner/properties/pet/$ref');
    expect(d.file, 'api.yaml');
  });

  test('follows references into other files, keyed by file and pointer', () {
    dir.write('specs/api.yaml', '''
$info
components:
  schemas:
    Error: {\$ref: "common/errors.yaml#/components/schemas/Error"}
''');
    dir.write('specs/common/errors.yaml', r'''
components:
  schemas:
    Error:
      type: object
      properties:
        code: {$ref: "codes.yaml#/Code"}
        extra: {$ref: "#/components/schemas/Missing"}
''');
    dir.write('specs/common/codes.yaml', 'Code: {type: string}\n');
    final (model, bag) = resolve('specs/api.yaml');
    final local = model.document.components!.schemas['Error']!;
    final remote = model.resolveSchema(local)! as SchemaObject;
    expect(remote.location, isNot(local.location));
    expect(remote.pointer, local.pointer);
    expect(
      remote.location.document,
      p.toUri(p.join(dir.path, 'specs', 'common', 'errors.yaml')),
    );
    final code = model.resolveSchema(remote.properties['code']!)!;
    expect((code as SchemaObject).types, [SchemaType.string]);
    final d = bag.all.single;
    expect(d.code, DiagnosticCode.unresolvedRef);
    expect(d.file, p.join('specs', 'common', 'errors.yaml'));
    expect(d.line, 7);
  });

  test('a missing file and a remote URL are reported', () {
    dir.write('api.yaml', '''
$info
components:
  schemas:
    A: {\$ref: "missing.yaml#/A"}
    B: {\$ref: "https://example.com/b.yaml"}
''');
    final (_, bag) = resolve('api.yaml');
    expect(bag.all.map((d) => d.code), [
      DiagnosticCode.unresolvedRef,
      DiagnosticCode.remoteRef,
    ]);
    expect(
      bag.all.first.message,
      '"missing.yaml#/A" points to missing.yaml, which does not exist or '
      'cannot be read.',
    );
  });

  test('a file referenced many times is read once', () {
    dir.write('api.yaml', '''
$info
components:
  schemas:
    A: {\$ref: "broken.yaml#/A"}
    B: {\$ref: "broken.yaml#/B"}
''');
    dir.write('broken.yaml', 'A: [\n');
    final (_, bag) = resolve('api.yaml');
    expect(bag.all.map((d) => (d.code, d.file)), [
      (DiagnosticCode.parseError, 'broken.yaml'),
      (DiagnosticCode.unresolvedRef, 'api.yaml'),
      (DiagnosticCode.unresolvedRef, 'api.yaml'),
    ]);
  });

  test('a reference to a node of another kind is reported', () {
    dir.write('api.yaml', '''
$info
paths:
  /a:
    get:
      parameters: [{\$ref: "#/components/schemas/Limit"}]
components:
  schemas:
    Limit: {type: integer}
''');
    final (model, bag) = resolve('api.yaml');
    final d = bag.all.single;
    expect(d.code, DiagnosticCode.refKindMismatch);
    expect(
      d.message,
      '"#/components/schemas/Limit" points to a schema, but a parameter is '
      'expected here.',
    );
    final get = model.resolve(model.document.paths['/a']!)!;
    expect(model.resolve(get.operations['get']!.parameters.single), isNull);
  });

  test('a target outside components is read as the expected kind', () {
    dir.write('api.yaml', '''
$info
x-shared:
  limit: {name: limit, in: query}
paths:
  /a:
    get:
      parameters: [{\$ref: "#/x-shared/limit"}]
''');
    final (model, bag) = resolve('api.yaml');
    expect(bag.all, isEmpty);
    final get = model.resolve(model.document.paths['/a']!)!;
    final limit = model.resolve(get.operations['get']!.parameters.single);
    expect(limit!.name, 'limit');
    expect(model.nodeAt(limit.location), same(limit));
  });
}
```

- [ ] **Step 2: Make sure the tests fail**

Run (from `packages/typed_openapi`): `dart test test/resolve`
Expected: FAIL, the first error — `cannot read 'lib/src/resolve/ref_resolver.dart': No such file or directory`

- [ ] **Step 3: Add the codes to the catalog**

In `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart` before the snippet:

```dart
  /// A `$ref` points to a remote URL; only local files are read.
```

insert:

```dart
  /// A `$ref` points to a file or a node that does not exist.
  unresolvedRef('TOA101', 'unresolved-ref', .error),
```

- [ ] **Step 4: Add the codes to the catalog**

In `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart` before the snippet:

```dart
  /// `$id` or `$self` would change the base URI of `$ref`s; this tool
```

insert:

```dart
  /// A `$ref` points to a node of another kind, such as a schema where a
  /// parameter is expected.
  refKindMismatch('TOA104', 'ref-kind-mismatch', .error),
```

- [ ] **Step 5: Create `spec_documents.dart`**

Create `packages/typed_openapi/lib/src/resolve/spec_documents.dart`:

```dart
import 'dart:io';

import 'package:path/path.dart' as p;

import '../load/spec_document.dart';
import '../load/spec_loader.dart';

/// The documents of one spec: the root document and every file its `$ref`s
/// reach, each loaded once and keyed by absolute URI.
final class SpecDocuments {
  /// Creates the set for [root]; other files are read with [_loader].
  SpecDocuments(this._loader, this.root) {
    _documents[root.uri] = root;
  }

  final SpecLoader _loader;
  final Map<Uri, SpecDocument?> _documents = {};

  /// The document the spec starts from.
  final SpecDocument root;

  /// The document at [uri], loaded on first use; null when the file does not
  /// exist or cannot be read.
  ///
  /// A file that does not exist is not reported here; one that exists but
  /// cannot be parsed is reported by the loader. Diagnostics name the file
  /// relative to the root document's displayed path.
  SpecDocument? operator [](Uri uri) {
    if (_documents.containsKey(uri)) return _documents[uri];
    final path = p.fromUri(uri);
    final document =
        FileSystemEntity.typeSync(path) == FileSystemEntityType.file
        ? _loader.load(path, displayPath: displayPath(uri))
        : null;
    return _documents[uri] = document;
  }

  /// How diagnostics name the file at [uri].
  String displayPath(Uri uri) {
    if (uri == root.uri) return root.file;
    final relative = p.relative(
      p.fromUri(uri),
      from: p.dirname(p.fromUri(root.uri)),
    );
    return p.normalize(p.join(p.dirname(root.file), relative));
  }
}
```

- [ ] **Step 6: Create `spec_model.dart`**

Create `packages/typed_openapi/lib/src/resolve/spec_model.dart`:

```dart
import '../model/document.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';

/// A parsed spec with its `$ref`s resolved.
///
/// Holds the root [document], every node read from any file by location,
/// and where each `$ref` that could be followed points.
final class SpecModel {
  /// Creates a model.
  SpecModel({
    required this.document,
    required Map<SpecLocation, SpecNode> nodes,
    required Map<SpecLocation, SpecLocation> targets,
  }) : _nodes = Map.unmodifiable(nodes),
       _targets = Map.unmodifiable(targets);

  /// The root document.
  final OpenApiDocument document;

  final Map<SpecLocation, SpecNode> _nodes;
  final Map<SpecLocation, SpecLocation> _targets;

  /// The node at [location], if one was read there.
  SpecNode? nodeAt(SpecLocation location) => _nodes[location];

  /// Where the `$ref` of the node at [site] points, or null when the node
  /// has no `$ref` or it could not be followed.
  SpecLocation? targetOf(SpecLocation site) => _targets[site];

  /// The node [value] stands for: the value itself, or the node at the end
  /// of its `$ref` chain; null when a `$ref` on the way is broken.
  T? resolve<T extends SpecNode>(RefOr<T> value) => switch (value) {
    Inline(:final value) => value,
    Ref() => switch (_follow(value.location)) {
      final T node => node,
      _ => null,
    },
  };

  /// The schema at the end of [schema]'s `$ref` chain, or [schema] itself
  /// when it has no `$ref`; null when a `$ref` on the way is broken.
  ///
  /// Keywords next to a `$ref` are not merged into the result.
  Schema? resolveSchema(Schema schema) {
    if (schema is! SchemaObject || schema.ref == null) return schema;
    return switch (_follow(schema.location)) {
      final Schema node => node,
      _ => null,
    };
  }

  SpecNode? _follow(SpecLocation site) {
    final seen = <SpecLocation>{};
    var current = site;
    while (seen.add(current)) {
      final target = _targets[current];
      if (target == null) return null;
      final node = _nodes[target];
      final isAlias = node is Ref || (node is SchemaObject && node.ref != null);
      if (!isAlias) return node;
      current = target;
    }
    return null;
  }
}
```

- [ ] **Step 7: Create `ref_resolver.dart`**

Create `packages/typed_openapi/lib/src/resolve/ref_resolver.dart`:

```dart
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../model/document.dart';
import '../model/operation.dart';
import '../model/schema.dart';
import '../model/security.dart';
import '../model/spec_node.dart';
import '../parse/openapi_parser.dart';
import '../parse/parse_context.dart';
import 'ref_target.dart';
import 'spec_documents.dart';
import 'spec_model.dart';

/// Follows every `$ref` of a parsed spec.
///
/// A target is identified by the absolute URI of its file plus its JSON
/// pointer. Targets in other local files are loaded once and parsed as the
/// kind of node the `$ref` expects; their own `$ref`s are followed in turn.
/// Problems go to the [DiagnosticBag] given to the constructor.
final class RefResolver {
  /// Creates a resolver that reports to [_diagnostics].
  const RefResolver(this._diagnostics);

  final DiagnosticBag _diagnostics;

  /// Resolves the `$ref`s in [index], which parsing [document] filled; the
  /// root document of the spec is [documents]' root.
  SpecModel resolve(
    OpenApiDocument document,
    SpecIndex index,
    SpecDocuments documents,
  ) {
    final parsers = <Uri, OpenApiParser>{};
    final targets = <SpecLocation, SpecLocation>{};
    for (var i = 0; i < index.refs.length; i++) {
      final use = index.refs[i];
      switch (RefTarget.parse(use.ref, use.site.document)) {
        case BrokenRef(:final code, :final reason, :final fix):
          _report(documents, use, code, reason, fix: fix);
        case ResolvableRef(:final location):
          final file = documents[location.document];
          if (file == null) {
            _report(
              documents,
              use,
              .unresolvedRef,
              '"${use.ref}" points to '
              '${documents.displayPath(location.document)}, which does not '
              'exist or cannot be read.',
            );
            continue;
          }
          var node = index.nodes[location];
          if (node == null) {
            if (file.valueAt(location.pointer) == null) {
              _report(
                documents,
                use,
                .unresolvedRef,
                'Nothing is at "${use.ref}".',
                fix:
                    'Define the target, or point the reference at an '
                    'existing one.',
              );
              continue;
            }
            final parser = parsers[location.document] ??= OpenApiParser(
              _diagnostics,
              file,
              index,
            );
            node = parser.parseFragment(location.pointer, use.kind);
            if (node == null) continue;
          }
          final kind = _kindOf(node);
          if (kind != use.kind) {
            _report(
              documents,
              use,
              .refKindMismatch,
              '"${use.ref}" points to '
              '${kind?.withArticle ?? 'a node that is not referable'}, but '
              '${use.kind.withArticle} is expected here.',
            );
            continue;
          }
          targets[use.site] = location;
      }
    }
    return SpecModel(document: document, nodes: index.nodes, targets: targets);
  }

  static RefKind? _kindOf(SpecNode node) => switch (node) {
    Ref(:final kind) => kind,
    Schema() => .schema,
    Response() => .response,
    Parameter() => .parameter,
    Example() => .example,
    RequestBody() => .requestBody,
    Header() => .header,
    SecurityScheme() => .securityScheme,
    PathItem() => .pathItem,
    MediaType() => .mediaType,
    _ => null,
  };

  void _report(
    SpecDocuments documents,
    RefUse use,
    DiagnosticCode code,
    String message, {
    String? fix,
  }) {
    final document = documents[use.site.document];
    final pointer = use.site.pointer.child(r'$ref');
    _diagnostics.report(
      code,
      message,
      file: documents.displayPath(use.site.document),
      pointer: pointer,
      span: document?.spanOf(pointer),
      fix: fix,
    );
  }
}
```

- [ ] **Step 8: Make sure the tests pass**

Run (from `packages/typed_openapi`): `dart test test/resolve`
Expected: `+15: All tests passed!`

- [ ] **Step 9: Format, analyzer, the whole test suite**

Run (from `packages/typed_openapi`): `dart format --output=none --set-exit-if-changed lib test bin && dart test`
Expected: `Formatted 55 files (0 changed)`, `+122: All tests passed!`

Run (from the root): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 10: Commit**

```bash
git add packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart packages/typed_openapi/lib/src/resolve/ref_resolver.dart packages/typed_openapi/lib/src/resolve/spec_documents.dart packages/typed_openapi/lib/src/resolve/spec_model.dart packages/typed_openapi/test/resolve/ref_resolver_test.dart
git commit -m 'feat(typed_openapi): resolve $ref inside a document and across files' -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
```

---

### Task 11: Reference cycles (TOA103)

**Files:**
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`
- Modify: `packages/typed_openapi/lib/src/resolve/ref_resolver.dart`
- Modify: `packages/typed_openapi/test/resolve/ref_resolver_test.dart`

**Interfaces:**
- Consumes: `RefResolver`, `SpecDocuments` (Task 10), `SpecLocation.compareTo` (Task 3).
- Produces: private `RefResolver._reportCycles`/`_reportCycle`; code `refCycle` (TOA103). The public API does not change.

The behaviour the tests pin down:
- `A → B → A` (in particular with a `description` next to the `$ref`) and `A → A` — one `TOA103` at the `$ref` pointer of the smallest participant, the message with the chain; `resolveSchema` → `null`.
- `A → B → C → B` — one cycle `B → C → B`, not a diagnostic for each entry into it; `resolve(A)` → `null`.
- A cycle through another file names that file (`other.yaml#/B`).

- [ ] **Step 1: Write a failing test**

Append to the end of `main()` in `packages/typed_openapi/test/resolve/ref_resolver_test.dart` (before the last `}`):

```dart
  group('cycles', () {
    test('two schemas that only point at each other are a loop', () {
      dir.write('api.yaml', '''
$info
components:
  schemas:
    A: {\$ref: "#/components/schemas/B"}
    B: {\$ref: "#/components/schemas/A", description: Loops.}
''');
      final (model, bag) = resolve('api.yaml');
      final d = bag.all.single;
      expect(d.code, DiagnosticCode.refCycle);
      expect(d.pointer?.value, r'#/components/schemas/A/$ref');
      expect(
        d.message,
        'These references point at each other and never reach a definition: '
        '#/components/schemas/A -> #/components/schemas/B -> '
        '#/components/schemas/A.',
      );
      final a = model.document.components!.schemas['A']!;
      expect(model.resolveSchema(a), isNull);
    });

    test('a schema that points at itself is a loop', () {
      dir.write('api.yaml', '''
$info
components:
  schemas:
    A: {\$ref: "#/components/schemas/A"}
''');
      final (_, bag) = resolve('api.yaml');
      expect(bag.all.single.code, DiagnosticCode.refCycle);
    });

    test('a loop is reported once, not by every reference into it', () {
      dir.write('api.yaml', '''
$info
components:
  parameters:
    A: {\$ref: "#/components/parameters/B"}
    B: {\$ref: "#/components/parameters/C"}
    C: {\$ref: "#/components/parameters/B"}
''');
      final (model, bag) = resolve('api.yaml');
      expect(
        bag.all.single.message,
        contains('B -> #/components/parameters/C'),
      );
      final a = model.document.components!.parameters['A']!;
      expect(model.resolve(a), isNull);
    });

    test('a loop across files names the other file', () {
      dir.write('api.yaml', '''
$info
components:
  schemas:
    A: {\$ref: "other.yaml#/B"}
''');
      dir.write('other.yaml', 'B: {\$ref: "api.yaml#/components/schemas/A"}\n');
      final (_, bag) = resolve('api.yaml');
      expect(
        bag.all.single.message,
        endsWith(
          '#/components/schemas/A -> other.yaml#/B -> #/components/schemas/A.',
        ),
      );
    });
  });
```

- [ ] **Step 2: Make sure the tests fail**

Run (from `packages/typed_openapi`): `dart test test/resolve`
Expected: FAIL, the first error — `Member not found: 'refCycle'.`

- [ ] **Step 3: Add the codes to the catalog**

In `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart` before the snippet:

```dart
  /// A `$ref` points to a node of another kind, such as a schema where a
```

insert:

```dart
  /// `$ref`s point at each other in a loop that never reaches a definition.
  refCycle('TOA103', 'ref-cycle', .error),
```

- [ ] **Step 4: Change `ref_resolver.dart`**

In `packages/typed_openapi/lib/src/resolve/ref_resolver.dart` before the snippet:

```dart
    return SpecModel(document: document, nodes: index.nodes, targets: targets);
```

insert:

```dart
    _reportCycles(targets, documents);
```

- [ ] **Step 5: Change `ref_resolver.dart`**

In `packages/typed_openapi/lib/src/resolve/ref_resolver.dart` before the snippet:

```dart

  static RefKind? _kindOf(SpecNode node) => switch (node) {
```

insert:

```dart
  /// Reports every loop of `$ref`s that never reaches a node without one.
  ///
  /// A key of [targets] is a node whose `$ref` resolved, so a chain that
  /// stays inside the keys only passes through references. A recursive
  /// schema is not a loop: its chain ends at the schema itself, which has
  /// no `$ref`.
  void _reportCycles(
    Map<SpecLocation, SpecLocation> targets,
    SpecDocuments documents,
  ) {
    final done = <SpecLocation>{};
    for (final start in targets.keys.toList()..sort()) {
      final path = <SpecLocation>[];
      final positions = <SpecLocation, int>{};
      SpecLocation? current = start;
      while (current != null &&
          targets.containsKey(current) &&
          !done.contains(current)) {
        final seen = positions[current];
        if (seen != null) {
          _reportCycle(path.sublist(seen), documents);
          break;
        }
        positions[current] = path.length;
        path.add(current);
        current = targets[current];
      }
      done.addAll(path);
    }
  }

  void _reportCycle(List<SpecLocation> cycle, SpecDocuments documents) {
    final first = cycle.reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
    final start = cycle.indexOf(first);
    final ordered = [...cycle.skip(start), ...cycle.take(start), first];
    String name(SpecLocation location) => location.document == first.document
        ? location.pointer.value
        : '${documents.displayPath(location.document)}'
              '${location.pointer.value}';
    final pointer = first.pointer.child(r'$ref');
    _diagnostics.report(
      .refCycle,
      'These references point at each other and never reach a definition: '
      '${ordered.map(name).join(' -> ')}.',
      file: documents.displayPath(first.document),
      pointer: pointer,
      span: documents[first.document]?.spanOf(pointer),
      fix: 'Point one of them at the actual definition.',
    );
  }
```

- [ ] **Step 6: Make sure the tests pass**

Run (from `packages/typed_openapi`): `dart test test/resolve`
Expected: `+19: All tests passed!`

- [ ] **Step 7: Format, analyzer, the whole test suite**

Run (from `packages/typed_openapi`): `dart format --output=none --set-exit-if-changed lib test bin && dart test`
Expected: `Formatted 55 files (0 changed)`, `+126: All tests passed!`

Run (from the root): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart packages/typed_openapi/lib/src/resolve/ref_resolver.dart packages/typed_openapi/test/resolve/ref_resolver_test.dart
git commit -m 'feat(typed_openapi): report $ref loops' -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
```

---

### Task 12: `SpecReader`, `check` on the new model, the public API and the documentation

**Files:**
- Create: `packages/typed_openapi/lib/src/resolve/spec_reader.dart`
- Create: `packages/typed_openapi/test/resolve/spec_reader_test.dart`
- Modify: `packages/typed_openapi/lib/src/check/spec_checker.dart`
- Modify: `packages/typed_openapi/lib/typed_openapi.dart`
- Modify: `packages/typed_openapi/test/check/spec_checker_test.dart`
- Modify: `packages/typed_openapi/test/cli/cli_test.dart`
- Modify: `packages/typed_openapi/CHANGELOG.md`
- Modify: `packages/typed_openapi/README.md`
- Modify: `packages/typed_openapi/README.ua.md`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: everything above.
- Produces: `final class SpecReader { const SpecReader(DiagnosticBag); SpecModel read(SpecDocument document, OpenApiVersion version); }`; `SpecChecker.check` reads the model after version detection; the public API exports the models, `SpecModel`, `SpecReader`.

The behaviour the tests pin down:
- `SpecReader.read` in one call parses the document, resolves references and checks the dialect; a schema nested up to the `NestingScanner` limit is read without a stack overflow.
- After version detection, `SpecChecker` reads the model: a broken `$ref` in another file and a missing field are visible in `check`; the dialect is checked against the declared version; a document without a determined version is not read into the model.
- The CLI prints `TOA100` with the pointer. The minimal fixtures of the existing tests get `info`.

- [ ] **Step 1: Write a failing test**

Create `packages/typed_openapi/test/resolve/spec_reader_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/load/nesting_scanner.dart';
import 'package:typed_openapi/src/load/openapi_version.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/model/schema.dart';
import 'package:typed_openapi/src/resolve/spec_reader.dart';

void main() {
  test('parses, resolves and checks the dialect in one call', () {
    final bag = DiagnosticBag();
    final document = SpecLoader(bag).parse(r'''
openapi: 3.0.3
info: {title: Pets, version: "1"}
components:
  schemas:
    Pet: {type: object, properties: {tag: {$ref: "#/components/schemas/Tag"}}}
    Tag: {type: [string, "null"]}
''', 'api.yaml')!;
    final model = SpecReader(bag).read(document, .v30);
    final pet = model.document.components!.schemas['Pet']! as SchemaObject;
    final tag = model.resolveSchema(pet.properties['tag']!)! as SchemaObject;
    expect(tag.types, [SchemaType.string, SchemaType.nullType]);
    expect(model.document.version, OpenApiVersion.v30);
    expect(bag.all.map((d) => d.code), [
      DiagnosticCode.openApi31InOpenApi30,
      DiagnosticCode.openApi31InOpenApi30,
    ]);
  });

  test('a schema nested as deep as the loader allows is read', () {
    final bag = DiagnosticBag();
    const depth = NestingScanner.maxDepth - 4;
    final schema = '${'{"items": ' * depth}{"type": "string"}${'}' * depth}';
    final document = SpecLoader(bag).parse(
      '{"openapi": "3.1.0", "info": {"title": "t", "version": "1"}, '
          '"components": {"schemas": {"Deep": $schema}}}',
      'api.json',
    )!;
    final model = SpecReader(bag).read(document, .v31);
    var current = model.document.components!.schemas['Deep'];
    var levels = 0;
    while (current is SchemaObject && current.items != null) {
      current = current.items;
      levels++;
    }
    expect(levels, depth);
    expect(bag.all, isEmpty);
  });
}
```

- [ ] **Step 2: Add tests to `spec_checker_test.dart`**

In `packages/typed_openapi/test/check/spec_checker_test.dart` replace:

```dart
    dir.write('specs/ok.yaml', 'openapi: 3.0.3\n');
```

with:

```dart
    dir.write(
      'specs/ok.yaml',
      'openapi: 3.0.3\ninfo: {title: ok, version: "1"}\npaths: {}\n',
    );
```

- [ ] **Step 3: Add tests to `spec_checker_test.dart`**

Append to the end of `main()` in `packages/typed_openapi/test/check/spec_checker_test.dart` (before the last `}`):

```dart
  test('reads each spec into the model and follows its references', () {
    final dir = TempDir();
    dir.write('specs/api.yaml', r'''
openapi: 3.0.3
info: {title: api}
paths:
  /pets:
    get:
      responses:
        "200": {$ref: "common.yaml#/components/responses/Missing"}
''');
    dir.write('specs/common.yaml', 'components: {responses: {}}\n');
    final path = dir.write('typed_openapi.yaml', '''
clients:
  api: {input: specs/api.yaml, output: lib/api}
''');
    final bag = DiagnosticBag();
    final config = ConfigLoader(bag).load(path)!;
    SpecChecker(bag).check(config);
    expect(
      bag.sorted.map((d) => (d.code, d.file, d.pointer?.value)),
      [
        (DiagnosticCode.missingRequiredField, 'specs/api.yaml', '#/info'),
        (
          DiagnosticCode.unresolvedRef,
          'specs/api.yaml',
          r'#/paths/~1pets/get/responses/200/$ref',
        ),
      ],
    );
  });

  test('reports the dialect of a spec against its declared version', () {
    final dir = TempDir();
    dir.write('api.json', '''
{
  "openapi": "3.1.0",
  "info": {"title": "api", "version": "1"},
  "components": {"schemas": {"A": {"type": "string", "nullable": true}}}
}
''');
    final path = dir.write(
      'typed_openapi.yaml',
      'clients:\n  api: {input: api.json, output: lib/api}\n',
    );
    final bag = DiagnosticBag();
    SpecChecker(bag).check(ConfigLoader(bag).load(path)!);
    expect(bag.all.single.code, DiagnosticCode.nullableAfterOpenApi30);
  });

  test('does not read a spec whose version it cannot detect', () {
    final dir = TempDir();
    dir.write('api.yaml', 'info: {title: 5}\nnmae: x\n');
    final path = dir.write(
      'typed_openapi.yaml',
      'clients:\n  api: {input: api.yaml, output: lib/api}\n',
    );
    final bag = DiagnosticBag();
    SpecChecker(bag).check(ConfigLoader(bag).load(path)!);
    expect(bag.all.single.code, DiagnosticCode.missingOpenApiVersion);
  });
```

- [ ] **Step 4: Add tests to `cli_test.dart`**

In `packages/typed_openapi/test/cli/cli_test.dart` replace:

```dart
    dir.write('specs/ok.yaml', 'openapi: 3.1.0\n');
```

with:

```dart
    dir.write(
      'specs/ok.yaml',
      'openapi: 3.1.0\ninfo: {title: ok, version: "1"}\n',
    );
```

- [ ] **Step 5: Add tests to `cli_test.dart`**

Append to the end of `main()` in `packages/typed_openapi/test/cli/cli_test.dart` (before the last `}`):

```dart
  test('reports broken references in the spec', () async {
    final dir = TempDir();
    dir.write('api.yaml', r'''
openapi: 3.0.0
info: {title: api, version: "1"}
components:
  schemas:
    Owner: {properties: {pet: {$ref: "#/components/schemas/"}}}
''');
    final path = dir.write(
      'typed_openapi.yaml',
      'clients:\n  api: {input: api.yaml, output: lib/api}\n',
    );
    final (code, out, _) = await run(['check', '-c', path]);
    expect(code, 1);
    expect(out, contains('error TOA100 invalid-ref'));
    expect(
      out,
      contains(r'  at #/components/schemas/Owner/properties/pet/$ref'),
    );
  });
```

- [ ] **Step 6: Make sure the tests fail**

Run (from `packages/typed_openapi`): `dart test`
Expected: FAIL, the first error — `cannot read 'lib/src/resolve/spec_reader.dart': No such file or directory`

- [ ] **Step 7: Create `spec_reader.dart`**

Create `packages/typed_openapi/lib/src/resolve/spec_reader.dart`:

```dart
import '../diagnostics/diagnostic_bag.dart';
import '../load/openapi_version.dart';
import '../load/spec_document.dart';
import '../load/spec_loader.dart';
import '../parse/dialect_checker.dart';
import '../parse/openapi_parser.dart';
import '../parse/parse_context.dart';
import 'ref_resolver.dart';
import 'spec_documents.dart';
import 'spec_model.dart';

/// Reads a loaded spec into a [SpecModel]: parses it, follows its `$ref`s
/// and reports constructs its declared version does not have.
///
/// Problems go to the [DiagnosticBag] given to the constructor.
final class SpecReader {
  /// Creates a reader that reports to [_diagnostics].
  const SpecReader(this._diagnostics);

  final DiagnosticBag _diagnostics;

  /// Reads [document], which declares [version].
  SpecModel read(SpecDocument document, OpenApiVersion version) {
    final index = SpecIndex();
    final parsed = OpenApiParser(_diagnostics, document, index).parse(version);
    final model = RefResolver(_diagnostics).resolve(
      parsed,
      index,
      SpecDocuments(SpecLoader(_diagnostics), document),
    );
    DialectChecker(_diagnostics).check(index.features, version);
    return model;
  }
}
```

- [ ] **Step 8: Rewrite `spec_checker.dart`**

Replace the whole content of `packages/typed_openapi/lib/src/check/spec_checker.dart` with:

```dart
import 'package:path/path.dart' as p;

import '../config/project_config.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../load/openapi_version.dart';
import '../load/spec_loader.dart';
import '../resolve/spec_reader.dart';

/// Loads every client's spec and reports what is wrong with it.
///
/// Nothing is generated. Problems go to the [DiagnosticBag] given to the
/// constructor.
final class SpecChecker {
  /// Creates a checker that reports to [_diagnostics].
  const SpecChecker(this._diagnostics);

  final DiagnosticBag _diagnostics;

  /// Checks the spec of every client in [config].
  ///
  /// Each spec is loaded, its OpenAPI version detected, and then it is read
  /// into the model with its `$ref`s resolved. [only] limits the run to
  /// clients with these names; empty means all. A file shared by several
  /// clients is checked once. Spec paths in diagnostics are relative to the
  /// config file's directory.
  void check(ProjectConfig config, {Set<String> only = const {}}) {
    final loader = SpecLoader(_diagnostics);
    final detector = OpenApiVersionDetector(_diagnostics);
    final reader = SpecReader(_diagnostics);
    final configDir = p.dirname(p.absolute(config.file));
    final checked = <String>{};
    for (final client in config.clients) {
      if (only.isNotEmpty && !only.contains(client.name)) continue;
      if (!checked.add(p.absolute(client.input))) continue;
      final document = loader.load(
        client.input,
        displayPath: p.relative(client.input, from: configDir),
      );
      if (document == null) continue;
      final version = detector.detect(document);
      if (version == null) continue;
      reader.read(document, version);
    }
  }
}
```

- [ ] **Step 9: Rewrite `typed_openapi.dart`**

Replace the whole content of `packages/typed_openapi/lib/typed_openapi.dart` with:

```dart
/// OpenAPI 3.x to Dart client generator.
///
/// The programmatic API mirrors the CLI: load a config, check specs, report
/// diagnostics. [SpecReader] reads a loaded spec into the typed model
/// ([SpecModel]) with its `$ref`s resolved.
library;

export 'src/check/spec_checker.dart' show SpecChecker;
export 'src/cli/cli.dart' show TypedOpenApiCli;
export 'src/config/config_loader.dart' show ConfigLoader;
export 'src/config/project_config.dart'
    show ClientConfig, Preset, ProjectConfig;
export 'src/diagnostics/diagnostic.dart' show Diagnostic;
export 'src/diagnostics/diagnostic_bag.dart' show DiagnosticBag;
export 'src/diagnostics/diagnostic_code.dart' show DiagnosticCode;
export 'src/diagnostics/json_pointer.dart' show JsonPointer;
export 'src/diagnostics/reporters.dart'
    show DiagnosticReporter, JsonReporter, ReportFormat, TextReporter;
export 'src/diagnostics/severity.dart' show Severity;
export 'src/load/openapi_version.dart'
    show OpenApiVersion, OpenApiVersionDetector;
export 'src/load/spec_document.dart' show SpecDocument;
export 'src/load/spec_loader.dart' show SpecLoader;
export 'src/model/document.dart' show Components, Info, OpenApiDocument, Tag;
export 'src/model/operation.dart'
    show
        Encoding,
        Example,
        Header,
        MediaType,
        Operation,
        Parameter,
        ParameterLocation,
        ParameterStyle,
        PathItem,
        RequestBody,
        Response,
        SecurityRequirement,
        Server,
        ServerVariable;
export 'src/model/schema.dart'
    show BooleanSchema, Discriminator, Schema, SchemaObject, SchemaType;
export 'src/model/security.dart'
    show
        ApiKeyLocation,
        OAuthFlow,
        OAuthFlows,
        SecurityScheme,
        SecuritySchemeType;
export 'src/model/spec_node.dart'
    show Inline, Ref, RefKind, RefOr, SpecLocation, SpecNode;
export 'src/resolve/spec_model.dart' show SpecModel;
export 'src/resolve/spec_reader.dart' show SpecReader;
```

- [ ] **Step 10: Change `CHANGELOG.md`**

In `packages/typed_openapi/CHANGELOG.md` replace:

```markdown
- Programmatic API: `ConfigLoader`, `SpecLoader`, `OpenApiVersionDetector`,
  `SpecChecker`, `TextReporter`, `JsonReporter`, `TypedOpenApiCli`.
```

with:

```markdown
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
- Loading: nesting deeper than 1000 levels is reported (TOA007) instead of
  crashing; YAML keys such as `1` and `"1"` that merge into one JSON key are
  reported (TOA002); a directory given as the spec or the config is reported
  as such.
```

- [ ] **Step 11: Change `README.md`**

In `packages/typed_openapi/README.md` before the snippet:

```markdown
Every finding has a stable code (`TOA011`), a JSON pointer into the spec and,
```

insert:

```markdown
`check` reads the whole spec, follows its `$ref`s (also into other local
files) and reports unknown keys, wrong value types, broken or looping
references and constructs that the declared OpenAPI version does not have.
```

- [ ] **Step 12: Edit `README.ua.md`**

In `packages/typed_openapi/README.ua.md`, before the fragment:

```markdown
Each finding has a stable code (`TOA011`) and a JSON pointer to the place in
```

insert:

```markdown
`check` reads the whole spec, follows its `$ref`s (including into other local
files) and reports unknown keys, values of the wrong type, broken or
circular references, and constructs that are absent from the declared OpenAPI version.
```

- [ ] **Step 13: Edit `CLAUDE.md`**

In `CLAUDE.md` replace:

```markdown
## Architecture of M1 (`dart run typed_openapi check`)

All under `packages/typed_openapi/lib/src/`, one folder per stage:

- `diagnostics/` - `Diagnostic`, `DiagnosticCode` (stable `TOAnnn` catalog),
  `Severity`, `JsonPointer`, `DiagnosticBag`, and the reporters
  (`DiagnosticReporter`, `TextReporter`, `JsonReporter`, `ReportFormat`).
- `load/` - `SpecLoader` reads JSON/YAML into a `SpecDocument` (plain tree plus
  source spans by JSON pointer); `OpenApiVersionDetector` reads its OpenAPI
  version.
- `config/` - `ConfigLoader`, `ProjectConfig`, `ClientConfig`, `Preset`.
- `check/` - `SpecChecker`.
- `cli/` - `TypedOpenApiCli` (`cli.dart`, owns the `CommandRunner` and maps
  usage errors to exit code 64) and `CheckCommand` (`check_command.dart`,
  options `--config/-c` and `--format`, client names as positional
  arguments); `bin/typed_openapi.dart` only calls `TypedOpenApiCli().run(args)`
  and sets `exitCode`.
- `lib/typed_openapi.dart` exports the public API: the classes above except
  `CheckCommand`, each with a `show` list.

Data flows loader -> checker, every stage writing problems into one
`DiagnosticBag`; reporters read the bag at the end.
```

with:

```markdown
## Architecture (`dart run typed_openapi check`)

All under `packages/typed_openapi/lib/src/`, one folder per stage:

- `diagnostics/` - `Diagnostic`, `DiagnosticCode` (stable `TOAnnn` catalog),
  `Severity`, `JsonPointer`, `DiagnosticBag`, and the reporters
  (`DiagnosticReporter`, `TextReporter`, `JsonReporter`, `ReportFormat`).
- `load/` - `SpecLoader` reads JSON/YAML into a `SpecDocument` (plain tree,
  absolute file URI, source spans by JSON pointer, `valueAt(pointer)`);
  `NestingScanner` rejects text nested deeper than 1000 levels before the
  recursive YAML parser sees it; `OpenApiVersionDetector` reads the version.
- `model/` - the immutable typed model, a superset of OAS 3.0/3.1/3.2:
  `SpecNode` (every node has a `SpecLocation` = file URI + pointer, `x-`
  `extensions` and reported `unknownKeys`), `RefOr<T>` = `Ref<T>` | `Inline<T>`,
  `Schema` = `BooleanSchema` | `SchemaObject` (`$ref` is a keyword there),
  `OpenApiDocument` and the other OAS objects.
- `parse/` - `OpenApiParser` (document, components, fragments for `$ref`
  targets), `OperationParser`, `SchemaParser`, all on `ObjectReader` (typed
  field access; wrong types -> TOA111, missing required -> TOA112, unknown
  keys -> TOA110). Parsers record nodes, `$ref`s and version-specific
  constructs (`SpecFeature`) in a shared `SpecIndex`; `DialectChecker` turns
  the constructs into TOA020-TOA022.
- `resolve/` - `RefTarget` reads a `$ref` value, `SpecDocuments` loads other
  local files once by URI, `RefResolver` follows every `$ref` and reports
  TOA100-TOA105, `SpecModel` answers `resolve`/`resolveSchema`; `SpecReader`
  runs parse -> resolve -> dialect check.
- `config/` - `ConfigLoader`, `ProjectConfig`, `ClientConfig`, `Preset`.
- `check/` - `SpecChecker`: config -> load -> version -> `SpecReader`.
- `cli/` - `TypedOpenApiCli` (`cli.dart`, owns the `CommandRunner` and maps
  usage errors to exit code 64) and `CheckCommand` (`check_command.dart`,
  options `--config/-c` and `--format`, client names as positional
  arguments); `bin/typed_openapi.dart` only calls `TypedOpenApiCli().run(args)`
  and sets `exitCode`.
- `lib/typed_openapi.dart` exports the public API: the classes above except
  `CheckCommand`, each with a `show` list.

Data flows loader -> parser -> resolver -> checker, every stage writing
problems into one `DiagnosticBag`; reporters read the bag at the end.
```

- [ ] **Step 14: Make sure the tests pass**

Run (from `packages/typed_openapi`): `dart test`
Expected: `+132: All tests passed!`

- [ ] **Step 15: Format, analyzer, the whole test suite**

Run (from `packages/typed_openapi`): `dart format --output=none --set-exit-if-changed lib test bin && dart test`
Expected: `Formatted 57 files (0 changed)`, `+132: All tests passed!`

Run (from the root): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 16: Commit**

```bash
git add CLAUDE.md packages/typed_openapi/CHANGELOG.md packages/typed_openapi/README.md packages/typed_openapi/README.ua.md packages/typed_openapi/lib/src/check/spec_checker.dart packages/typed_openapi/lib/src/resolve/spec_reader.dart packages/typed_openapi/lib/typed_openapi.dart packages/typed_openapi/test/check/spec_checker_test.dart packages/typed_openapi/test/cli/cli_test.dart packages/typed_openapi/test/resolve/spec_reader_test.dart
git commit -m 'feat(typed_openapi): check reads specs into the model' -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
```

---

## Final check

- [ ] **Step 1: Full check of the package**

Run (from `packages/typed_openapi`):

```bash
dart format --output=none --set-exit-if-changed lib test bin && dart test && dart pub publish --dry-run
```

Expected: `Formatted 57 files (0 changed)`, `+132: All tests passed!`, `Package has 0 warnings.`

Run (from the root): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 2: Run on a real spec (outside the repository)**

Put `typed_openapi.yaml` in a temporary directory outside the repository with one client whose `input` is the absolute path to the NestJS spec from research/06 §C.1a (do not copy the spec itself into the repository), and run `dart run typed_openapi check -c <path>`.

Expected (checked on the prototype, OAS 3.0.0, 3 MB, 734 operations, 1434 schemas): `errors: 3, warnings: 9, infos: 0` — three `TOA100 invalid-ref` on `$ref: '#/components/schemas/'`, eight `TOA111 invalid-value` on `required: true/false` inside `items` (C-49), one `TOA020` ("examples" in a schema); no `TOA110`. Time: ~0.25 s compiled with `dart compile exe` (~125 MB RSS), ~0.8 s via `dart run`.

## Requirements coverage

| Requirement | Where |
|---|---|
| R0.1 — OAS 3.0 and 3.1 | Superset model (Tasks 3, 5–7), dialect (Task 8) |
| R1.2 — `$ref` in a document and between files, cycles | Tasks 9–11 |
| R1.4 — 3.2 `itemSchema` | `MediaType.itemSchema` (Task 6), `TOA022` (Task 8) |
| R2.1 (partly) — empty and dangling `$ref` as diagnostics | `TOA100`, `TOA101` (Tasks 9–10); fix — M3 |
| R2.2 — codes, pointer, positions | All new codes with pointer and span; positions also in other files |
| R2.5 — guess nothing silently | Unknown keys, wrong types, missing fields, ignored `$id`/`$self` — all diagnostics |
| R13.1 — determinism | Document order, sorting of cycles, `DiagnosticBag.sorted` |
| Moved from M1 | Tasks 1–2 |
