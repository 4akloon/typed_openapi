# typed_openapi

![Dart SDK](https://img.shields.io/badge/Dart-%3E%3D3.10-0175C2?logo=dart&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-blue)
![Status](https://img.shields.io/badge/status-pre--release-orange)

**An OpenAPI 3.x to Dart client generator for imperfect, code-first specs** (NestJS, FastAPI, Spring, ASP.NET). It fixes what such specs get wrong, tells you every fix with a stable code, and generates Dio clients with typed errors, open enums and unions that do not break on a value the spec forgot.

> **Status:** pre-release (version 0.0.1). It is not published to pub.dev yet; install it from the repository, see [Install](#install).

## Install

`typed_openapi` is the generator: a dev dependency and a CLI, never a runtime dependency. The generated code depends only on [`typed_openapi_runtime`](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/README.md) and Dio. Neither package is on pub.dev yet, so use git (or a path to a checkout):

```yaml
dependencies:
  dio: ^5.11.1
  typed_openapi_runtime:
    git:
      url: https://github.com/4akloon/typed_openapi.git
      path: packages/typed_openapi_runtime
dev_dependencies:
  typed_openapi:
    git:
      url: https://github.com/4akloon/typed_openapi.git
      path: packages/typed_openapi
```

Pin a `ref:` (a tag or a commit) in both entries to get a reproducible build. The minimum SDK is Dart 3.10, for the generator and for the code it writes. Run the CLI with `dart run typed_openapi <command>`.

## Quick start

Five minutes, one spec (`specs/petstore.yaml`) with a single operation:

```yaml
openapi: 3.0.3
info: {title: Petstore, version: "1.0"}
servers:
  - url: https://petstore.example.com/v1
paths:
  /pets/{id}:
    get:
      operationId: getPet
      tags: [pets]
      parameters:
        - {name: id, in: path, required: true, schema: {type: integer}}
      responses:
        "200":
          description: The pet.
          content:
            application/json:
              schema: {$ref: "#/components/schemas/Pet"}
        "404":
          description: No such pet.
          content:
            application/json:
              schema: {$ref: "#/components/schemas/Problem"}
components:
  schemas:
    Pet:
      type: object
      required: [id, name, status]
      properties:
        id: {type: integer}
        name: {type: string}
        status: {type: string, enum: [available, sold]}
    Problem:
      type: object
      required: [message]
      properties:
        message: {type: string}
```

Describe the client in `typed_openapi.yaml` next to `pubspec.yaml`:

```yaml
clients:
  petstore:
    input: specs/petstore.yaml
    output: lib/src/petstore
```

Check the spec, then generate:

```text
$ dart run typed_openapi check
errors: 0, warnings: 0, infos: 0
$ dart run typed_openapi generate
errors: 0, warnings: 0, infos: 0
Generated petstore in lib/src/petstore: 7 files, 7 written, 0 deleted.
```

Use the client with your own Dio. The result is a sealed `Result` you match on, so the 404 body arrives as a `Problem`, not as an exception:

```dart
import 'package:dio/dio.dart';
import 'package:typed_openapi_runtime/typed_openapi_runtime.dart';

import 'src/petstore/petstore.dart';

Future<void> main() async {
  final dio = Dio(BaseOptions(baseUrl: PetstoreClient.server));
  final client = PetstoreClient(dio);

  switch (await client.pets.getPet(id: 7)) {
    case Success(:final data):
      print('${data.name} is ${data.status.value}');
    case HttpError(:final body):
      print('not found: ${body.message}');
    case Failure():
      print('request failed');
  }
}
```

Against a server that answers `{"id": 7, "name": "Rex", "status": "available"}` this prints `Rex is available`; for an id the server answers with a 404 and `{"message": "No such pet"}` it prints `not found: No such pet`. The generated files are plain Dart you commit; there is no `build_runner` step. The full walkthrough is in [Getting started](doc/getting_started.md).

## What it does

- **Reads real-world specs.** OpenAPI 3.0, 3.1 and 3.2, JSON or YAML, with local `$ref`s between files. It never calls the network.
- **Fixes and reports.** Named [normalizer rules](doc/presets_and_rules.md) repair common defects (`required: true` on a property, duplicate enum values, a missing path parameter, a discriminator whose property is not required) and framework [presets](doc/presets_and_rules.md) add recipes for NestJS, FastAPI, springdoc and ASP.NET. Every fix is a [diagnostic](doc/diagnostics.md) with a stable `TOAnnn` code, a JSON pointer, a file position and advice.
- **Overrides by location.** Correct names, types, nullability, `required`, discriminators and SSE event schemas in an [overrides file](doc/overrides.md), without touching the backend.
- **Types that do not lie.** [Open enums](doc/generated/enums.md) keep the raw value; [unions](doc/generated/unions.md) have an unknown variant with the raw JSON; PATCH bodies use tri-state fields (absent, `null`, value); secrets print as `<redacted>`.
- **Typed errors per operation.** A call returns a sealed `Result` with the success body, the documented error bodies and transport, decoding and cancellation failures. See [Responses and errors](doc/generated/responses_and_errors.md).
- **Request bodies.** JSON, forms, multipart with typed parts, text, bytes and files: [Request bodies](doc/generated/request_bodies.md).
- **Event streams.** `text/event-stream` operations become `Stream`s with reconnection and typed event unions: [Event streams](doc/generated/event_streams.md).
- **Security metadata.** Each operation carries its security requirements as data; it never signs requests for you: [Security](doc/generated/security.md).
- **Your Dio stays yours.** The client uses the `Dio` you pass as it is: interceptors, adapters and options are not touched.
- **Safe to run in CI.** [`check`](doc/cli.md) exits non-zero on new errors, a [baseline](doc/baseline.md) accepts the old ones, and output is available as text, JSON, SARIF and GitHub annotations: [CI](doc/ci.md).
- **Deterministic, and careful with your files.** The same spec and config give byte-identical code. `generate` replaces its output atomically and refuses to delete a file it did not write: [Generated output](doc/generate_output.md).

## Commands

```sh
dart run typed_openapi check              # report diagnostics, write nothing
dart run typed_openapi generate           # check, then write every client without errors
dart run typed_openapi baseline create    # accept the current errors and warnings
```

Exit code `0` means no errors, `1` errors, `64` a usage error and `78` a config that could not be loaded. All options are in [Command line](doc/cli.md).

## Documentation

| Guide | What it covers |
| --- | --- |
| [Getting started](doc/getting_started.md) | From a spec to a working call, step by step. |
| [Command line](doc/cli.md) | `check`, `generate`, `baseline`, formats and exit codes. |
| [Configuration](doc/configuration.md) | Every key of `typed_openapi.yaml`. |
| [Overrides](doc/overrides.md) | Fixing a spec by location without editing it. |
| [Presets and rules](doc/presets_and_rules.md) | The normalizer rules and the framework presets. |
| [Diagnostics](doc/diagnostics.md) | Every `TOAnnn` code and how to fix it. |
| [Baseline](doc/baseline.md) | Accepting existing problems; adopting on a large spec. |
| [Generated output](doc/generate_output.md) | Ownership, manifest, locks, determinism, what to commit. |
| [CI](doc/ci.md) | Exit codes, annotations, SARIF, a GitHub Actions workflow. |
| [The generated client](doc/generated/overview.md) | Layout and shape of what `generate` writes. |
| [Models](doc/generated/models.md), [Enums](doc/generated/enums.md), [Unions](doc/generated/unions.md) | Generated types. |
| [Operations](doc/generated/operations.md), [Request bodies](doc/generated/request_bodies.md), [Responses and errors](doc/generated/responses_and_errors.md) | Generated methods. |
| [Event streams](doc/generated/event_streams.md), [Security](doc/generated/security.md) | SSE and security metadata. |
| [NestJS](doc/frameworks/nestjs.md), [FastAPI](doc/frameworks/fastapi.md), [Spring](doc/frameworks/spring.md), [ASP.NET](doc/frameworks/aspnet.md) | What each framework's spec needs. |
| [Programmatic API](doc/programmatic_api.md) | Running the checker and the writer from Dart code. |
| [Troubleshooting](doc/troubleshooting.md) | Common problems and what to do. |

The runtime that generated code depends on has its own guides: [typed_openapi_runtime](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/README.md).

## Contributing and license

Development setup and conventions are in the [repository](https://github.com/4akloon/typed_openapi). `typed_openapi` is released under the MIT license, see [LICENSE](LICENSE).

[Українська версія](README.ua.md)
