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
dart run typed_openapi generate          # models of every client without errors
```

`generate` owns each output directory: it writes the whole new tree and a
manifest (`.typed_openapi.json`) next to it and swaps it in, so a failed run
leaves the previous output (or nothing) and never a half tree, and it deletes
every file there it did not write. It refuses a directory (TOA830) that holds
a `pubspec.yaml`, is a package's `lib`, holds an input of the run (the config,
the spec, its `$ref`'d files, the overrides or the baseline; also through
symbolic links or another letter case), holds a symbolic link, or holds files
but no manifest of its own. Clients whose output directories overlap are all
skipped (TOA904). TOA830, TOA831 and TOA904 cannot be lowered.

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
`group`, `exhaustive`, `dartType`, `triState`) name, leave out, group and
type what is generated. A `group` is written in UpperCamelCase like the
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
and read as bytes without its schema (info `TOA561`, which also names the
other media types of an operation that are dropped); an
`errors.default_schema` that is not a key of `components.schemas` is a
warning `TOA562` and is ignored; a parameter `style` that its `in` does not
allow (path `form`, query `matrix`, ...) is a warning `TOA564` and the default
style is used, and an `in: querystring` parameter (OpenAPI 3.2) is `TOA564`
too and is not generated. Header parameters named `Accept`, `Content-Type`
or `Authorization` are not generated, as OpenAPI says to ignore them.

Every finding has a stable code (`TOA011`), a JSON pointer into the spec and,
for files the parser could position, a line and column. Paths are relative
to the directory you run the command in. Change the level of a code, by its
id or name, in `defaults` or per client; `off` drops it. Codes that say a
spec, overrides or baseline file cannot be read cannot be lowered:

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
