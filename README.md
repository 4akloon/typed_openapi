# typed_openapi

![Dart SDK](https://img.shields.io/badge/Dart-%3E%3D3.10-0175C2?logo=dart&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-blue)
![Status](https://img.shields.io/badge/status-pre--release-orange)

**An OpenAPI 3.x to Dart client generator for imperfect, code-first specs** (NestJS, FastAPI, Spring, ASP.NET). It repairs what such specs get wrong, reports every repair with a stable code, and writes plain Dio clients with typed errors, open enums and unions that do not break on a value the spec forgot.

> **Status:** pre-release (version 0.1.0). Nothing is published to pub.dev yet; install from this repository. The stage map is in [docs/roadmap.md](docs/roadmap.md).

## Contents

- [Why typed_openapi](#why-typed_openapi)
- [Quick start](#quick-start)
- [Features](#features)
- [Documentation](#documentation)
- [Packages](#packages)
- [Status and roadmap](#status-and-roadmap)
- [Contributing and license](#contributing-and-license)

## Why typed_openapi

Specs exported by a framework are rarely clean: a path variable without a parameter, `required: true` on a property, a repeated enum value, a `$ref` to nothing. A generator either fails, or guesses without telling you, and then you patch the spec or the output by hand. `typed_openapi` makes the repair a first-class, visible step.

- **Nothing is guessed silently.** Every fix, fallback or skipped construct is a diagnostic with a `TOAnnn` code, a JSON pointer and a file position. Levels are configurable, and a [baseline](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/baseline.md) lets CI fail only on new problems.
- **You fix the spec without owning the backend.** An [overrides file](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/overrides.md) addresses operations, parameters and schemas by name and changes names, types, nullability, discriminators and SSE event schemas.
- **The generated code is plain Dart.** No `build_runner` step; models follow the `fromJson`/`toJson` contract, so they mix with your own `@JsonSerializable` classes. The client uses the `Dio` you pass in and never reconfigures it.
- **Types that do not lie.** Open enums keep the raw value, unions have an unknown variant, PATCH bodies are tri-state, every call returns a sealed `Result` with the documented error bodies.

**When to choose it:** your spec comes out of a code-first framework and you need to generate against it repeatedly without editing it, or you want typed errors and SSE on top of your own Dio. **When not to:** you only need a one-off client for a clean spec and are happy with an existing generator, or you need a target other than Dart and Dio (the HTTP layer is Dio only; Flutter is not required and not used).

The project's own [research](https://github.com/4akloon/typed_openapi/blob/main/docs/research/README.md) (October 2026, about 25 Dart generators surveyed) found none with named normalization rules, an override file with addressing and a baseline; projects that generate large SDKs from OpenAPI were seen patching the spec or the output by hand (Matrix keeps patches against the specification, Mastodon keeps hand-written code on top of the generated one). The same study found that the commercial SDK generators it looked at do not target Dart. Read it as a snapshot of that date, not as a ranking.

## Quick start

Five minutes, one spec. Add the packages (they are not on pub.dev yet; pin a `ref:` to get a reproducible build):

```yaml
dependencies:
  dio: ^5.11.1
  typed_openapi_client:
    git:
      url: https://github.com/4akloon/typed_openapi.git
      path: packages/typed_openapi_client
  typed_openapi_dio:
    git:
      url: https://github.com/4akloon/typed_openapi.git
      path: packages/typed_openapi_dio
dev_dependencies:
  typed_openapi_core:
    git:
      url: https://github.com/4akloon/typed_openapi.git
      path: packages/typed_openapi_core
  typed_openapi:
    git:
      url: https://github.com/4akloon/typed_openapi.git
      path: packages/typed_openapi
```

`specs/petstore.yaml`:

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

`typed_openapi.yaml` next to `pubspec.yaml`:

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

Use the client with your own Dio through `DioTransport`. The result is a sealed `Result`, so the 404 body arrives as a `Problem`, not as an exception:

```dart
import 'package:dio/dio.dart';
import 'package:typed_openapi_client/typed_openapi_client.dart';
import 'package:typed_openapi_dio/typed_openapi_dio.dart';

import 'src/petstore/petstore.dart';

Future<void> main() async {
  final dio = Dio(BaseOptions(baseUrl: PetstoreClient.server));
  final client = PetstoreClient(DioTransport(dio));

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

Against a server that answers `{"id": 7, "name": "Rex", "status": "available"}` this prints `Rex is available`. The walkthrough with a real NestJS-style spec, including the diagnostics it produces, is [Getting started](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/getting_started.md).

## Features

- **Reads real-world specs.** OpenAPI 3.0, 3.1 and 3.2, JSON or YAML, local `$ref`s between files; it never calls the network.
- **Normalizer rules and presets.** Named rules repair common defects; presets add recipes for NestJS, FastAPI, Spring and ASP.NET: [Presets and rules](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/presets_and_rules.md).
- **Several clients in one config**, each with its own input, output, overrides and baseline: [Configuration](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/configuration.md).
- **Models, open enums and unions** with unknown variants, tri-state PATCH fields and `<redacted>` secrets: [Models](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/models.md), [Enums](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/enums.md), [Unions](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/unions.md).
- **Typed errors per operation**, plus transport, decoding and cancellation failures: [Responses and errors](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/responses_and_errors.md).
- **Request bodies:** JSON, forms, multipart with typed parts, text, bytes, files: [Request bodies](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/request_bodies.md).
- **Server-Sent Events** as `Stream`s with reconnection and typed event unions: [Event streams](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/event_streams.md).
- **Security metadata** as data on each operation; it never signs a request: [Security](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/security.md).
- **Works in CI:** exit codes, text, JSON, SARIF and GitHub annotations: [CI](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/ci.md).
- **Deterministic output** written atomically; it replaces only files it wrote: [Generated output](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generate_output.md).
- **Runtime on the VM, dart2js and dart2wasm**, with strict JSON decoding that names the JSON pointer of a mismatch: [typed_openapi_client](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/README.md).

## Documentation

Every guide of the generator and the client. Package READMEs: [typed_openapi_core](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_core/README.md), [typed_openapi](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/README.md), [typed_openapi_client](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/README.md).

**The generator, `typed_openapi`**

| Guide | What it covers |
| --- | --- |
| [Getting started](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/getting_started.md) | From a spec to a working call. |
| [Command line](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/cli.md) | `check`, `generate`, `baseline`, formats, exit codes. |
| [Configuration](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/configuration.md) | Every key of `typed_openapi.yaml`. |
| [Overrides](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/overrides.md) | Fixing a spec by location. |
| [Presets and rules](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/presets_and_rules.md) | Normalizer rules and framework presets. |
| [Diagnostics](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/diagnostics.md) | Every `TOAnnn` code. |
| [Baseline](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/baseline.md) | Accepting existing problems. |
| [Generated output](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generate_output.md) | Ownership, manifest, locks, determinism. |
| [CI](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/ci.md) | Pipelines, annotations, SARIF. |
| [Programmatic API](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/programmatic_api.md) | Checker and writer as a library. |
| [Troubleshooting](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/troubleshooting.md) | Symptoms, causes, fixes, how to report a bug. |

**What gets generated**

| Guide | What it covers |
| --- | --- |
| [The generated client](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/overview.md) | Layout and shape of the output. |
| [Models](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/models.md) | Classes, required and nullable, tri-state. |
| [Enums](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/enums.md) | Open enums. |
| [Unions](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/unions.md) | Discriminated and untagged unions. |
| [Operations](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/operations.md) | Methods, groups, parameters. |
| [Request bodies](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/request_bodies.md) | JSON, forms, multipart, files. |
| [Responses and errors](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/responses_and_errors.md) | `Result` and typed errors. |
| [Event streams](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/event_streams.md) | SSE methods and event unions. |
| [Security](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/security.md) | Security requirements as data. |

**Frameworks**

| Guide | What it covers |
| --- | --- |
| [NestJS](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/frameworks/nestjs.md) | What a NestJS spec needs. |
| [FastAPI](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/frameworks/fastapi.md) | What a FastAPI spec needs. |
| [Spring](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/frameworks/spring.md) | springdoc-openapi. |
| [ASP.NET Core](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/frameworks/aspnet.md) | What an ASP.NET spec needs. |

**The runtime, `typed_openapi_client`**

| Guide | What it covers |
| --- | --- |
| [Getting started](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/getting_started.md) | The runtime in a generated client. |
| [Results and errors](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/results_and_errors.md) | `Result`, `Failure` and its cases. |
| [JSON decoding](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/json_decoding.md) | Strict reads, `JsonDecodeException`. |
| [Patch and nullability](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/patch_and_nullability.md) | Absent, `null`, value. |
| [Parameters](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/parameters.md) | Styles, encoding, cookies. |
| [Request bodies](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/request_bodies.md) | Forms, multipart, files. |
| [Server-Sent Events](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/sse.md) | Decoder, reconnection, cancel. |
| [Web and platforms](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/web_and_platforms.md) | dart2js, dart2wasm, differences. |
| [Security metadata](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/doc/security_metadata.md) | `OperationInfo` and schemes. |

## Packages

| Package | Role |
| --- | --- |
| [`typed_openapi`](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi) | The **generator**: CLI and programmatic API. A dev dependency, never a runtime dependency of your app. |
| [`typed_openapi_client`](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client) | The **client core** every generated client depends on (only `meta`): results, decoding, encoding, event streams, the `ClientTransport` interface. |
| [`typed_openapi_dio`](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_dio) | The **Dio transport**: `DioTransport` over your own `Dio`. |
| [`typed_openapi_transport_tests`](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_transport_tests) | The **transport conformance suite**, never published: every transport runs it. |
| [`typed_openapi_tool`](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_tool) | **Repository tools**, never published: the public-spec corpus and the escaping fuzz. |

The minimum SDK is Dart 3.10 for the generator and for generated code. Translations of the package READMEs: [typed_openapi (Українська)](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/README.ua.md), [typed_openapi_client (Українська)](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_client/README.ua.md).

## Status and roadmap

Version 0.1.0, pre-release: the surface may still change, and a change of generated output is a breaking change of the generator. The milestones (M1 to M13) are listed in [docs/roadmap.md](docs/roadmap.md); requirements and the research behind the decisions are in [docs/](docs/).

## Contributing and license

Setup, commands and conventions are in [CONTRIBUTING.md](CONTRIBUTING.md). Report a problem as described in [Troubleshooting](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/troubleshooting.md#reporting-a-bug). `typed_openapi` is released under the MIT license, see [LICENSE](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/LICENSE).
