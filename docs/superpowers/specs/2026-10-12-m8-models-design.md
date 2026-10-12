# M8: model emitter — design

Date: 2026-10-12. Requirements: R6.5–R6.8, R7, R8, R9, R13 ([requirements.md](../../requirements.md)). Research: [research/README](../../research/README.md) §7.1, 7.2, 7.7, 7.8 and [research/07](../../research/07-dart-building-blocks.md) §C and D. Previous stages:
- [M6 design](2026-10-12-m6-ir-design.md): the IR with Dart names and types, which M8 only prints;
- [M7 design](2026-10-12-m7-runtime-design.md): the runtime that the generated code relies on (`JsonReader`, `JsonValue`, `Patch`, `Date`).

The decisions were made in a session of questions with the user.

## Decisions

1. **Formatting — one's own layout, without `dart_style`.**
   - The emitter lays out the code itself, line by line, with indentation and line breaks. The first line after the header is `// dart format off`, so the user's `dart format` does not touch the file, and `--set-exit-if-changed` in CI passes. slang does the same.
   - The generator depends neither on `dart_style` nor on `analyzer`.
   - The lints (`package:lints/recommended`, `flutter_lints`) run for real, without `ignore_for_file: type=lint` (R13.2). Golden tests run `dart analyze` on the generated code.
   - A pinned `dart_style` as an option (`format: true`) — later, if asked.
2. **One file per declaration.** `<output>/models/<snake_case name>.dart` and a barrel `models.dart` with `export`. The files import each other by relative paths. Collisions of file names (macOS does not distinguish case) are resolved by a separate file-name namespace.
3. **Each model has `fromJson` and `toJson` regardless of direction.**
   - Signatures: `factory Pet.fromJson(Map<String, Object?> json)` and `Map<String, Object?> toJson()`. This is the json_serializable contract: a model fits into `@JsonSerializable` classes and vice versa, and it can be put in a cache.
   - `fromJson` throws `JsonDecodeException`, which the runtime converts (the M7 decision).
4. **Model form.**
   - A class without `final` (a user decision after the plan: models may be extended and implemented), a `const` constructor with named parameters (`required` — for required fields), `@immutable`, `final` fields.
   - `==` and `hashCode` — deep comparison of lists and maps through a small helper in the runtime (without `package:collection`).
   - `toString`.
   - `copyWith` is not generated (R6.6 SHOULD is deliberately narrowed).
5. **Union — wrappers.**
   - `sealed class Pet` with variants `PetCat(Cat value)`, `PetDog(Dog value)` and `PetUnknown`, which keeps the raw JSON.
   - The variant's model stays independent: it can be used in several unions and separately. Inline variants are wrapped the same way, so that a `switch` looks the same everywhere.
   - The dispatch — by the discriminator and the resolved `mapping` from the IR. The `toJson` of the wrapper adds the discriminator key if it is not in the variant's model.
   - `toJson` for `PetUnknown` returns the raw JSON.
6. **`oneOf`/`anyOf` without a discriminator (R9.2).**
   - By default the type is `JsonValue`, plus a warning with a ready override. The override offers two exits: add a `discriminator` or enable `union: structural`.
   - The override `union: structural | raw` is set on a schema; the same key exists globally in the config.
   - `structural`:
     - for `oneOf` the variant that decodes exactly one is chosen, and zero or several matches give `Unknown`;
     - for `anyOf` the first variant that decoded is chosen.
7. **Unions that differ by JSON type (R9.3).**
   - `string | integer`, `string | Cat`, `Cat | array` have the same sealed form: `IdOrNameString(String value)`, `IdOrNameInt(int value)`, `IdOrNameUnknown(JsonValue)`. The variant is chosen by the JSON type.
   - `integer` and `number` together are not a conflict: a whole number goes into `int`, a fractional one into `double`.
   - Two variants of one JSON type — rule 6.
8. **`const` and an enum with one value — a constant field.**
   - There is no parameter in the constructor.
   - `toJson` always writes the value.
   - `fromJson` checks that exactly that value arrived, otherwise a `DecodeError` with a pointer.
   - Access — a getter (`String get petType => 'cat'`).
9. **Other enums (decision 7 of the research).**
   - Form: `sealed X` + `enum XKnown implements X` + `class XUnknown` with a private constructor and static aliases `X.available`.
   - A response field has type `X`. The constructors of request models and operation parameters accept only `XKnown` (R8.2 is checked by the compiler).
   - String, numeric and boolean enums have the same form. `null` in an `enum` makes the field nullable and does not become a value.
   - `toJson` for `XUnknown` returns the raw value.
   - The name `unknown` in values is reserved (M6).
10. **`default` — documentation only.**
    - It does not affect the field type: an optional field stays `T?`.
    - Nothing is substituted when decoding.
    - An unset request field is not sent, and the server applies its own value.
    - Doc comment: `/// Defaults to 'available' on the server.`
11. **`properties` + `additionalProperties`.**
    - The field `additionalProperties` is generated only when `additionalProperties` is a schema. Its type is `Map<String, T>`, and its name passes through the model's namespace.
    - `fromJson` collects into this field the keys that are not in `properties`, and `toJson` appends them after the known fields.
    - `true` and `{}` give no field: extra keys are ignored (R6.5).
12. **Constraints (R6.7) — doc comment only** (`/// 1–64 characters, matches '^[a-z]+$'.`). There is no validation. A `validate()` method is possible later on request.
13. **Documentation (R13.4).**
    - `description` and `summary` become a doc comment, with escaping.
    - `deprecated: true` becomes `@Deprecated`.
14. **File header:** `// GENERATED CODE - DO NOT MODIFY BY HAND.` and `// dart format off`. There are no generator versions in the files.
15. **The manifest `.typed_openapi.json` in the output directory.** It contains the generator version, the manifest format, the hash of the spec and config, and the list of files with the hash of each. An update of the generator changes only the files whose code changed. By the manifest, CI checks that the output is fresh.
16. **The `generate` command appears in M8 and writes only models**; M9 will add operations.
    - The output path is set in the client's config.
    - A client with `check` errors (including an unusable overrides file, M4) is skipped.
    - The exit code is the same as for `check`.
17. **The generator replaces only what it wrote itself** (a user decision after the final review: the replacement "the output directory belongs entirely to the generator" caused data loss).
    - Only a file that is listed in the previous manifest and whose hash matches the manifest is removed or overwritten.
    - Any other file in the directory is foreign (it is not in the manifest: a user's file, a file of another client) or changed (the hash differs: the generated file was edited by hand). Then the client is not generated, and TOA830 names these files.
    - A directory without a manifest, whose manifest does not belong to `typed_openapi`, and a directory with files but no manifest are likewise rejected by TOA830: all its files are foreign.
    - `generate --force` allows replacing foreign and changed files (the client's line says how many, and the info TOA833 names each file that was overwritten or removed). `--force` never allows replacing a directory with `pubspec.yaml`, a package's `lib/`, a directory that is or holds a symbolic link, or a directory that contains an input of the run (config, spec, overrides, baseline): these safeguards remain as a second line of defence.
    - The manifest has format 2 (`format`): each file with a hash. A manifest without a file hash (of an older format) considers that file changed, so after an update one `--force` is needed; the message says so.
    - A file whose content already matches what the write would produce is never considered foreign.
    - The output directory has a lock: a file `.<output>.typed_openapi.lock` next to it, created exclusively (it holds the pid and the host). A second run on the same output gets TOA831 and changes nothing; a lock of a process that no longer exists (on the same host) is taken over (TOA832); a lock whose owner is unknown (another host, an unreadable file, Windows) is taken over only by `--break-lock`, which replaces no file; the lock of a running process stays held, and `--force` does not touch locks. Recovery after a killed run goes only under the lock, after the output checks, and never touches the directories that contain the run's input.
18. **Sealed types of operation statuses.**
    - When the statuses have different error schemas (`ErrorsByStatus` in the IR), the error type is `sealed class CreatePetError`. The variants are named after the HTTP status:
      - `CreatePetErrorNotFound`, `CreatePetErrorUnprocessableEntity`;
      - `4XX` → `ClientError`, `5XX` → `ServerError`;
      - `default` → `Other`;
      - a non-standard code → `Status499`.
    - The variant carries the body: `final CreatePetError404 body`. The names of the bodies stay from M6.
    - Several different successful bodies give the same: `CreatePetResponse` with variants `Ok`, `Created`, and the bodies `CreatePetResponse200`, `CreatePetResponse201`.
    - These names are allocated by the IR library's namespace, with a diagnostic of collisions. M6 did not do this, so it is moved here.
19. **`DateTime` in `toJson` — always `toUtc().toIso8601String()`**, that is, with `Z` and without an hour offset. `Date` is written as `YYYY-MM-DD`.
20. **The rest.**
    - The language of the generated code is Dart 3.10.
    - The runtime is imported without a prefix, with a `show` list.
    - `toJson` writes the fields in the spec's order; optional fields with the value `null` are not sent (R7.3).
    - `Patch<T>?`: `null` means "the key is absent", `.nullValue()` writes `null`.

## Out of scope

- Operations, groups, `Result` methods, form/multipart bodies with `encoding` — M9.
- SSE events — M10.
- ~~Polymorphism through `allOf` inheritance with a discriminator on the base~~ — done in M8 by a user decision (see "User decisions" in the plan): a base with a discriminator and subtypes (also in other files that the spec reads) becomes a union of its subtypes. TOA452 `discriminator-without-subtypes` (info) remains for a discriminator on a schema without subtypes: it is generated as an ordinary model.
- `copyWith`, `validate()`, `format: true` through `dart_style` — on request.
- Override address for the names of inline types (R5.4) — in the M8 plan, if the address can be built cheaply.
