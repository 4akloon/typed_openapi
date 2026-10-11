## typed_openapi

![Dart](https://img.shields.io/badge/Dart-%3E%3D3.8-0175C2?logo=dart&logoColor=white)
![Style](https://img.shields.io/badge/style-lints-brightgreen)

Monorepo for `typed_openapi`: an OpenAPI 3.x → Dart client generator built for
imperfect, code-first specs (NestJS, FastAPI, Spring, ASP.NET).

> **Status:** early design. Nothing is published yet.

What sets it apart:

- **Tolerant by design.** Named normalizer rules fix common spec defects; every fix
  is reported. Diagnostics have stable codes and JSON pointers, levels can be
  overridden, and a baseline lets CI fail only on new problems.
- **Overrides addressed by location.** Fix names, types, `required`/`nullable`,
  discriminators and SSE event schemas without touching the backend.
- **Types that don't lie.** Open enums keep the raw value and can't be sent back
  unknown; unions get an unknown variant with the raw JSON; tri-state fields for
  PATCH; typed errors per operation.
- **Your client stays yours.** The generated code uses your Dio instance as is:
  interceptors see HTTP errors, nothing is reconfigured.
- **Ready-to-use output.** No `build_runner` step; models follow the
  `json_serializable` contract (`fromJson`/`toJson`), so they mix with your own
  `@JsonSerializable` classes.

## Packages

- `packages/typed_openapi` – the generator: CLI and programmatic API.
- `packages/typed_openapi_runtime` – small runtime used by generated clients.

Per-package docs:

- Generator: [English](packages/typed_openapi/README.md), [Українська](packages/typed_openapi/README.ua.md)
- Runtime: [English](packages/typed_openapi_runtime/README.md), [Українська](packages/typed_openapi_runtime/README.ua.md)

## Design docs

- [docs/](docs/) – requirements and competitor research.
