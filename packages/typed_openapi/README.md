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
dart run typed_openapi check --format json
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
for files the parser could position, a line and column. Exit code `1` means
at least one error, `64` wrong arguments or an unknown client, `78` the
config could not be read.

Generated clients depend on
[`typed_openapi_runtime`](../typed_openapi_runtime/README.md).

[Українська версія](README.ua.md)
