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
`group`, `exhaustive`, `dartType`, `triState`) are checked now and used once
code generation lands. Hints of rules that cannot fix a defect themselves
end with the override to copy.

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
level the config gives it. `baseline create` and `baseline prune` leave the
baseline of a client whose spec cannot be read untouched and exit with `1`.
Exit code `1`
means at least one error that is not accepted, `64` wrong arguments or an
unknown client, `78` the config could not be read.

Generated clients depend on
[`typed_openapi_runtime`](../typed_openapi_runtime/README.md).

[Українська версія](README.ua.md)
