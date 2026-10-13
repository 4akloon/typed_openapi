# Getting started

This guide takes one NestJS-style spec from file to a working call: install, config, `check`, `generate`, and using the client with Dio. Everything below was run on the sample spec; the program at the end prints the line shown.

## Install

`typed_openapi` is not published to pub.dev yet (version 0.0.1). Until it is, depend on it from the repository by git or path. The generator is a dev dependency; the generated client depends only on `typed_openapi_runtime` and Dio.

```yaml
dependencies:
  dio: ^5.11.1
  typed_openapi_runtime:
    path: ../typed_openapi/packages/typed_openapi_runtime
dev_dependencies:
  typed_openapi:
    path: ../typed_openapi/packages/typed_openapi
```

The minimum SDK is Dart 3.10, for the generator and for generated code. Run it with `dart run typed_openapi <command>`.

## The spec

`specs/shop.yaml` is an OpenAPI 3.0 document with the usual NestJS faults: controller-prefixed operation ids, a path variable without a parameter, a repeated enum value, and `required: true` on a property.

```yaml
openapi: 3.0.0
info: {title: Shop, version: "1.0"}
paths:
  /products/{id}:
    get:
      operationId: ProductsController_findOne
      tags: [products]
      responses:
        "200":
          description: One product.
          content:
            application/json: {schema: {$ref: '#/components/schemas/Product'}}
        "404": {description: Not found.}
components:
  schemas:
    Category:
      type: string
      enum: [tools, toys, toys]
    Product:
      type: object
      required: [id, name]
      properties:
        id: {type: integer}
        name: {type: string}
        category: {$ref: '#/components/schemas/Category'}
```

(This is the part of the spec that matters; the full file also has `GET` and `POST /products` and a `CreateProduct` schema.)

## The config

```yaml
# typed_openapi.yaml
defaults:
  preset: nestjs
clients:
  shop:
    input: specs/shop.yaml
    output: lib/src/api/shop
```

`input` and `output` are required. Paths are relative to the config file. See [Configuration](configuration.md) for every key.

## Check

`check` reads the spec and reports problems without writing anything.

```text
$ dart run typed_openapi check
warning TOA501 missing-path-parameter: The path /products/{id} has {id}, but this operation declares no path parameter "id"; it is added as a required string path parameter.
  --> specs/shop.yaml:30:7
  at #/paths/~1products~1{id}/get
  fix: Declare each at the source as {name: <name>, in: path, required: true, schema: {type: string}}.
warning TOA301 duplicate-enum-value: The enum repeats "toys"; the repeats are removed and the first occurrence of each value is kept.
  --> specs/shop.yaml:42:13
  at #/components/schemas/Category/enum
  fix: Remove the repeated values at the source. In NestJS, give the enum its own schema with `enumName` (the CLI plugin option `autoFillEnumName` sets it) instead of spreading several TypeScript enums into one list.
warning TOA201 bool-required: Property "name" says "required: true", the OpenAPI 2 way; OpenAPI 3 lists required properties in the "required" array of the object, so the name is moved there.
  --> specs/shop.yaml:46:40
  at #/components/schemas/CreateProduct/properties/name/required
  fix: Add "name" to "required" of the object schema and remove "required" from the property.
errors: 0, warnings: 3, infos: 0
```

Each warning says what the tool repaired in memory. Your spec file is not changed. The exit code is `0`; only errors make it `1`. The codes are explained in [Diagnostics](diagnostics.md) and the rules behind them in [Presets and rules](presets_and_rules.md). To accept warnings you cannot fix yet, see [CLI](cli.md#baseline).

## Generate

```text
$ dart run typed_openapi generate
Generated shop in lib/src/api/shop: 7 files, 7 written, 0 deleted.
```

The output is a self-contained tree. `generate` runs `check` first and skips a client that has errors.

```text
lib/src/api/shop/
  .typed_openapi.json   manifest: what was written, with hashes
  shop.dart             the root client, ShopClient
  api.dart, api/        one class per tag
  models.dart, models/  one file per model and enum
```

Run it again and it writes `0 files`. Do not edit the tree by hand: the next run replaces it, and refuses to replace files it did not write unless you pass `--force`.

## Use the client

```dart
import 'package:dio/dio.dart';
import 'package:shop_app/src/api/shop/shop.dart';
import 'package:typed_openapi_runtime/typed_openapi_runtime.dart';

Future<void> main() async {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
  final client = ShopClient(dio);

  final result = await client.products.findOne(id: '42');
  switch (result) {
    case Success(:final data):
      print('found ${data.name} in ${data.category}');
    case HttpError(:final body):
      print('documented error: $body');
    case TransportError(:final exception):
      print('network problem: ${exception.message}');
    case Failure():
      print('another failure: $result');
  }
}
```

The method name `findOne` comes from `ProductsController_findOne`: the `nestjs` preset strips the controller prefix. Against a local server that answered `{"id": 42, "name": "Hammer", "category": "garden"}` this printed:

```text
found Hammer in CategoryUnknown(garden)
```

`garden` is not in the enum the spec lists, so the open enum kept it as `CategoryUnknown` instead of failing. `dart analyze` reports no issues for the project.

Every call returns `Result<T, E>`: a `Success`, or a `Failure` such as `HttpError`, `UndocumentedStatus`, `DecodeError`, `TransportError` or `Cancelled`. The generated client never mutates your Dio and sets no base URL; configure `Dio` as you like. The runtime guides explain results, JSON decoding and parameters: see [typed_openapi_runtime](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/README.md).

> **Note:** The generated `shop.dart` does not re-export the result types, so import `package:typed_openapi_runtime/typed_openapi_runtime.dart` where you `switch` on a result.

## Next steps

- Fix what you cannot change in the spec with [Overrides](overrides.md).
- Silence or raise diagnostics with `severity` in [Configuration](configuration.md#severity).
- Commit the generated tree, or generate in CI: it is deterministic, so the same spec and config give the same bytes.

## See also

- [CLI](cli.md), [Configuration](configuration.md), [Diagnostics](diagnostics.md).
- [Presets and rules](presets_and_rules.md) and [Overrides](overrides.md).
