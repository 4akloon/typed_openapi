# typed_openapi

OpenAPI 3.x → Dart client generator for imperfect, code-first specs.

> **Status:** early design, not published yet.

- Input: local OpenAPI 3.0 / 3.1 / 3.2 file (JSON or YAML).
- Output: ready-to-use Dart code on Dio, no `build_runner` step.
- Models follow the `json_serializable` contract (`fromJson` / `toJson`).
- Spec defects are fixed by named normalizer rules and reported as diagnostics
  with stable codes; anything ambiguous is reported with a suggested override.

## Usage

Describe each client in `typed_openapi.yaml` next to your `pubspec.yaml`:

```yaml
defaults:
  preset: nestjs          # normalizer preset; also: generic, fastapi, springdoc, aspnet
clients:
  core_api:
    input: specs/core_api.json      # local JSON or YAML snapshot
    output: lib/src/api/core_api    # each client gets its own directory
```

Check the specs without generating anything:

```sh
dart run typed_openapi check            # all clients
dart run typed_openapi check core_api   # one client
dart run typed_openapi check --format json   # also: sarif, github-actions
```

Generate the models of the clients whose check has no errors (a client with
errors is skipped, and the exit code is the one `check` gives):

```sh
dart run typed_openapi generate          # every client
dart run typed_openapi generate core_api # one client
dart run typed_openapi generate --force  # also replace files it did not write
dart run typed_openapi generate --break-lock  # take over a lock of unknown owner
```

### What `generate` writes

Each client gets `models.dart` (it exports every model) and
`models/<name>.dart`, one file per class, with the header
`// GENERATED CODE - DO NOT MODIFY BY HAND.` and `// dart format off` on the
second line. The code is clean under `package:lints/recommended` and the
`flutter_lints` rules without `ignore_for_file`, and the same spec and
config give the same bytes. The classes are plain `class`es (not `final`, so
you can extend them); a union base is `sealed`.

- Models have `fromJson(Map<String, Object?>)` and `toJson()`, `==`,
  `hashCode` and `toString`. `fromJson` throws a `JsonDecodeException` with
  the pointer of the first property that does not match. A property the
  schema does not list goes to `additionalProperties` when the schema allows
  it. `date` is the runtime's `Date`, `date-time` a `DateTime` (RFC 3339 with
  an offset), `byte` and `binary` bytes. An optional nullable property of a
  PATCH body is `Patch<T>?` with the `tri_state` setting.
- Enums are open: a known value is `Status.active`, a value the spec does
  not list is `StatusUnknown` with the raw value, and it is written back as
  it came.
- Unions are `sealed` classes with a class per variant (`PetCat`) and an
  unknown variant (`PetUnknown`) with the raw JSON. With a `discriminator`
  the value picks the variant; a model that has no property for it gets it
  written by its wrapper, with the value it was decoded with (an alias such
  as `kitty` for `cat` is kept). A schema with a discriminator that other
  schemas extend with `allOf` (the whole hierarchy, also in other files the
  spec reads) is a union of those models. Without a discriminator the
  variants are told apart by their JSON type; variants that share one
  (TOA453) are one variant that keeps the raw JSON, unless you ask the
  generator to try each variant in order:

  ```yaml
  defaults:
    union: structural        # raw (the default) or structural; per client too
  ```

  The same key is an override for one schema or property
  (`union: structural` under it in the overrides file) and wins over the
  config. A discriminator at the source is better than either.
- An enum or `const` branch next to a plain branch of the same type
  (`anyOf: [string, {enum: ['']}]`) adds no value and is dropped (info
  `TOA455`); the field's doc comment lists the dropped values as "Known
  values". For `oneOf` this accepts a value both branches take (`''`), which
  the spec's `oneOf` would reject; this is on purpose, as the idiom means
  "any of these".
- A secret is never printed: `toString` writes `<redacted>` for a property
  that is `writeOnly` or has `format: password` (also through a `$ref`, a
  nullable `anyOf` such as Pydantic's `Optional[SecretStr]`, array items,
  map values or a union variant). A value that stays raw JSON (`JsonValue`,
  or the `...Unknown` class of a union) is printed as `<redacted>` too when
  its schema could carry a secret: any model or union variant it may hold,
  at any depth, has a secret property.

`generate` writes each output directory as a whole. It builds the new tree and
a manifest (`.typed_openapi.json`: the generator, the manifest format, a hash
of the inputs and the hash of every file) next to the output and swaps it in,
so a failed run leaves the previous output (or nothing) and never a half tree.
A run that would change nothing does not touch the directory.

**It replaces only what it wrote.** A file that the previous manifest lists
and whose hash still matches is replaced or deleted. Any other file in the
directory is foreign (a file of yours, of another client, of another tool) or
modified (a generated file someone edited): the client is not generated, and
error `TOA830` names the files and changes nothing. Move them away, or run
`generate --force` to replace them (the line of the client says how many were
replaced, and an info `TOA833` names each file it overwrote or deleted). A directory with files and no manifest of its own is refused the
same way, as all its files are foreign, and so is a directory whose manifest
has no hash for a file (written before manifest format 2): pass `--force`
once and the new manifest has the hashes. A file that already holds what the
run would write is never a problem.

`--force` never replaces a directory that holds a `pubspec.yaml`, is a
package's `lib`, holds a symbolic link or holds a file that any client of the
config reads (the config, a spec, its `$ref`'d files, the overrides or the
baseline; also through symbolic links, hard links or another letter case):
`TOA830` stays. Clients whose output directories overlap are all skipped
(`TOA904`).

One run works on an output at a time. It holds the lock file
`.<output>.typed_openapi.lock`, created next to the output, which names its
process. A second run on the same output gets `TOA831` and changes nothing.
The lock of a process that is gone (on the same host) is taken over (info
`TOA832`). When typed_openapi cannot tell whether the process runs (another
host, an unreadable lock, Windows), delete the lock file or run
`generate --break-lock`, which takes such a lock over and replaces no file;
`--force` does not touch locks. The lock of a process that runs stays held.
A directory that cannot be written is `TOA831` too.

A run that was killed while it swapped leaves `.<output>.typed_openapi-*`
directories (eight letters or digits after the dash, `-old` for the backup;
these names are the generator's, do not use them). The next run, under the
lock and after it has checked the output as above, puts the previous output
back if it is missing, removes them and says so (info `TOA832`); a directory
that holds a file any client reads is left alone. TOA830-TOA833 and TOA904
cannot be lowered.

`check` reads the whole spec, follows its `$ref`s (also into other local
files) and reports unknown keys, wrong value types, broken or looping
references and constructs that the declared OpenAPI version does not have.
Then it runs the normalizer: named rules fix the defects whose fix follows
from the spec or from HTTP (`required: true` on a property, repeated enum
values, undeclared path parameters, defaults of the wrong type) and report
the rest with what to change at the source. A `preset` adds the recipe for
your framework to those hints. Turn a rule off per client or in `defaults`:

```yaml
defaults:
  rules: {dedupe-enum-values: false}
```

Fix what the normalizer cannot know in an overrides file, without touching
the backend. Name it in the client (`overrides: typed_openapi.overrides.yaml`)
and address the spec by operations and schemas, not by pointers:

```yaml
operations:
  getPet:                     # operationId, or METHOD /path: 'GET /pets/{id}'
    parameters:
      id: {schema: {type: integer, format: int64}}   # path:id if names clash
    responses:
      '200': {contentType: application/json}
schemas:
  Pet:
    reason: the backend sends null for pets without an owner
    properties:
      owner: {nullable: true}
      photo: {type: string, format: binary}
```

Overrides change the spec before the normalizer runs; `null` removes a field.
An override whose target is gone is a warning, one the spec already matches
is an info that it can be removed, and a misspelled key is an error that
suggests the closest known one. Fields for the generator (`name`, `exclude`,
`group`, `exhaustive`, `dartType`, `triState`, `union`) name, leave out,
group and type what is generated. A `group` is written in UpperCamelCase like the
name of a class (`pet-store` is used as `PetStore`); a `name` of a method,
argument or schema must be a valid Dart name, otherwise `TOA560` says which
name is used instead. Hints of rules that cannot fix a defect themselves
end with the override to copy.

`check` also works out what will be generated: names, groups and Dart types.
Name clashes get a suffix (`List` -> `ListModel`, `class` -> `class_`,
`getPet2`) and an info with the override that pins the name. Choose what to
generate and how in `defaults` or per client:

```yaml
defaults:
  naming:
    client: PetstoreClient       # root client class; default: client name + Client
    group: '{Tag}Api'            # class per tag; group_by: tag|path|single
    patch_suffix: Patch          # PetPatch: PATCH body of a schema used elsewhere too
    operation_prefix: '^v1_'     # removed from operationIds (nestjs: XController_)
  include: {tags: [pets], paths: ['/store/**']}
  exclude: {operations: [deletePet]}
  types:
    number: double               # number without format; default num
    formats: {decimal: {type: Decimal, import: 'package:decimal/decimal.dart'}}
    schemas: {Money: {type: Money, import: 'package:app/money.dart', converter: MoneyConverter}}
  tri_state: patch               # optional nullable PATCH fields are Patch<T>?
  union: raw                     # unions without a discriminator, see above
  errors: {default_schema: ErrorDto}
```

How the filters work:

- `include` is a union: an operation is generated when any tag,
  `operationId` or path pattern of `include` matches it. An empty `include`
  is no filter.
- `exclude` wins over `include`. A pattern in both is info `TOA558`, one that
  matches no operation is a warning `TOA557`.
- In a path pattern `*` is one segment and `**` any number of segments, `?`
  one character. `/pets/*` matches `/pets/{id}` and does not match `/pets`;
  `/pets/**` does not match `/pets` either, so list both to take the
  collection and everything below it.
- `operations` match the `operationId` as the spec writes it, before
  `operation_prefix` is removed (with the `nestjs` preset
  `UsersController_findAll`, not `findAll`). The prefix is removed only where
  its match starts at the beginning of the id and is not empty.
- Tags are case-sensitive, and an operation matches by any of its tags.

Other things `check` tells you instead of guessing: a client that generates
no operation (everything filtered out, written as `$ref`, or with a path
variable without a parameter) is a warning `TOA563` that says why; a body
with a media type that is not JSON, a form, text or an event stream is sent
and read as bytes without its schema (info `TOA650`; the other media types
of an operation that are dropped are info `TOA651`); an
`errors.default_schema` that is not a key of `components.schemas` is a
warning `TOA652` and is ignored; a parameter `style` that its `in` does not
allow (path `form`, query `matrix`, ...) is a warning `TOA564` and the default
style is used, and an `in: querystring` parameter (OpenAPI 3.2) is a warning
`TOA565` and is not generated. Header parameters named `Accept`, `Content-Type`
or `Authorization` are not generated, as OpenAPI says to ignore them.

Every finding has a stable code (`TOA011`), a JSON pointer into the spec and,
for files the parser could position, a line and column. Paths are relative
to the directory you run the command in. Change the level of a code, by its
id or name, in `defaults` or per client; `off` drops it. Codes that say a
spec, overrides or baseline file cannot be read, and the codes of `generate`
(TOA830-TOA833), cannot be lowered:

```yaml
defaults:
  severity: {TOA208: off, duplicate-operation-id: warning}
```

To adopt the tool on a spec with many findings, accept the current ones in
a baseline and fail only on new ones:

```yaml
clients:
  core_api:
    input: specs/core_api.json
    output: lib/src/api/core_api
    baseline: specs/core_api.baseline.yaml
```

```sh
dart run typed_openapi baseline create   # accept today's errors and warnings
dart run typed_openapi check             # new findings only; "baselined: N"
dart run typed_openapi check --show-baselined
dart run typed_openapi baseline prune    # drop entries that no longer match
```

A finding is matched by a fingerprint of its code and its place (the
operation, parameter, schema or property when it has one), not by its
message or line, so rewording a message or editing the spec elsewhere keeps
it. An entry that no longer matches is a warning that suggests
`baseline prune`; `check --strict-baseline` makes it an error, whatever
level the config gives it. `check` reports `TOA820` (a missing baseline
file) until the first `baseline create` writes it. `baseline create` and
`baseline prune` leave the baseline of a client whose spec cannot be read
untouched and exit with `1`. Exit code `1` means at least one error that is
not accepted, `64` wrong arguments or an unknown client, `78` the config
could not be read.

`--format github-actions` prints one workflow annotation per finding; GitHub
shows only a limited number of annotations per run, so on a spec with many
findings adopt a baseline first.

Generated clients depend on
[`typed_openapi_runtime`](../typed_openapi_runtime/README.md).

[Українська версія](README.ua.md)
