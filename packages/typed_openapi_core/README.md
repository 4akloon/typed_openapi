# typed_openapi_core

![Dart 3.10+](https://img.shields.io/badge/dart-%3E%3D3.10-0175C2)
![Part of typed_openapi](https://img.shields.io/badge/part_of-typed__openapi-informational)

**The engine of [`typed_openapi`](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/README.md):**
it reads OpenAPI 3.0, 3.1 and 3.2 specs, repairs their defects with named
normalizer rules, checks them and reports problems as diagnostics with
stable `TOAnnn` codes, JSON pointers and file positions. It also builds the
semantic IR a client is written from, keeps baselines and the API lock, and
compares two versions of an API. Use it directly when you need to check
specs without generating Dart, for example in a CI tool or in the tests of a
backend platform. To generate a client, use the generator,
`typed_openapi`, which depends on this package.

> **Status:** version 0.1.0, the first release, on pub.dev.

## Install

```sh
dart pub add typed_openapi_core
```

## Check the specs of a config

```dart
import 'package:typed_openapi_core/typed_openapi_core.dart';

void main() {
  final diagnostics = DiagnosticBag();
  final config = ConfigLoader(diagnostics).load('typed_openapi.yaml');
  if (config == null) return;

  final checks = SpecChecker(diagnostics).check(config);
  print(const TextReporter().format(diagnostics));
  for (final check in checks) {
    print('${check.client.name}: ${check.errors} errors');
  }
}
```

Errors in the user's input are never thrown: they go to the
`DiagnosticBag`, and `ClientCheck.errors` counts those left after the
client's levels and baseline.

## What the library offers

`package:typed_openapi_core/typed_openapi_core.dart` exports, each with a
`show` list:

- **Load:** `SpecLoader`, `SpecDocument` and the typed model of the spec
  (`OpenApiDocument` and the other OpenAPI objects).
- **Normalize:** `Normalizer`, `NormalizerRule`, `Finding`, `SpecEdit`, and
  the overrides file (`OverrideLoader`, `OverrideSet`).
- **Check:** `ConfigLoader`, `ProjectConfig`, `ClientConfig`,
  `SpecChecker`, `ClientCheck`, the diagnostics and their reporters (text,
  JSON, SARIF, GitHub Actions).
- **IR:** `IrBuilder`, `ClientIr`, `DartType` and the other nodes, and
  `IrJson`.
- **Baseline:** `Baseline`, `BaselineLoader`, `Fingerprints`.
- **Snapshot and diff:** `ApiSnapshot`, `ApiLock`, `ApiDiff` and the change
  reports.

Each has a doc comment in the source. The
[programmatic API guide](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/programmatic_api.md)
of the generator covers the path from config to files; the other guides
(configuration, diagnostics, baselines, overrides) are in
[`packages/typed_openapi/doc`](https://github.com/4akloon/typed_openapi/tree/main/packages/typed_openapi/doc).
