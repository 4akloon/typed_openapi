# The generated client

`typed_openapi generate` writes one Dart package-ready directory per client: models, one API class per group of operations, two barrel files and a root class. The code depends on `package:dio` and [`typed_openapi_runtime`](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/README.md) only, needs no `build_runner` step and is clean under `dart analyze --fatal-infos`.

## Layout

For a client `petstore` with `output: lib/api/petstore`, a spec with the tags `pets` and `store` and one untagged operation gives this tree (real output of the `petstore.yaml` test fixture):

```text
lib/api/petstore/
  petstore.dart             the root class PetstoreClient; exports models.dart and api.dart
  api.dart                  exports the group files
  api/default_api.dart      one plain class per group (tag)
  api/pets_api.dart
  api/store_api.dart
  models.dart               exports every model
  models/pet.dart           one file per class, named after the declaration in snake_case
  models/status.dart
  models/problem.dart
  ...
  .typed_openapi.json       the manifest: generator, format, hash of the inputs, hash of every file
```

- Import `petstore.dart` and you have everything: the barrels are re-exported from it.
- A client named `api` or `models` gets `api_client.dart` or `models_client.dart` instead of `<client>.dart`, so the root file never collides with a barrel.
- Declarations whose snake_case file names collide get a numeric suffix (`2`, `3`...); class names are made unique first.
- Request and response models of a schema split by direction live next to each other (`user.dart`, `user_input.dart`, see [Models](models.md)).
- Types a method needs only for itself (the sealed status types, the parts class of a multipart body, an event union) are written in the group file after the class, not in `models/`.

Every Dart file starts with the same two lines:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND.
// dart format off
```

`dart format off` keeps `dart format` from rewriting the files, so a formatter run in your project never makes a generated file differ from what the generator writes. Do not edit the files: the next `generate` run refuses to replace a file whose hash no longer matches the manifest (`TOA830`, see [Generate output](../generate_output.md)).

## The root class

The root class has a field per group and the servers of the spec. It never sets a base URL for you.

```dart
class PetstoreClient {
  /// Creates the client: every group sends through [dio], which it uses as it
  /// is.
  PetstoreClient(Dio dio)
    : defaultApi = DefaultApi(dio),
      pets = PetsApi(dio),
      store = StoreApi(dio);

  final DefaultApi defaultApi;
  final PetsApi pets;
  final StoreApi store;

  /// `https://{region}.pets.example.com/v1`.
  static String server1({String region = 'eu'}) =>
      ['https://', region, '.pets.example.com/v1'].join();

  /// `http://localhost:8080`.
  static const server2 = 'http://localhost:8080';
}
```

Use a server as the base URL of your own `Dio`:

```dart
final dio = Dio(BaseOptions(baseUrl: PetstoreClient.server1(region: 'us')));
final client = PetstoreClient(dio);
```

| Servers in the spec | Generated |
| --- | --- |
| One, no variables | `static const server = '...'` |
| Several, or with variables | `server1`, `server2`, ... in the order of the spec; a server with variables is a `static String` method whose named arguments default to the spec's default (an `enum` of the variable is listed in the doc comment) |
| None | nothing |

A member that would collide with another member of the root class is renamed with a suffix and reported (`TOA551`, for example `server2` when a group field is called `server`). Servers on a single operation or path are not used (`TOA566`).

The client never changes your `Dio`: interceptors, adapters, timeouts and the base URL stay yours. See [Operations](operations.md) for what a method looks like.

## Naming rules

Names come from the spec and are made valid Dart. Nothing is renamed silently: a change is an info (`TOA550`, `TOA551`) or a warning (`TOA552`; `TOA559` is an info) with the override that pins the name.

| Source | Becomes | Example |
| --- | --- | --- |
| `components.schemas` key | UpperCamelCase class | `pet-item` gives `PetItem` |
| Inline schema | The parent's name plus the property, `Item`, `Value` or a status | `ListShapesResponse`, `ValidationErrorLocItem` |
| Property, parameter | lowerCamelCase | header `X-Trace` gives `xTrace` |
| Dart reserved word or a name Dart already has | Trailing underscore, `TOA550` | `class` gives `class_`; `for` gives `for_` |
| Same name twice in one scope | `2`, `3`... after the first, `TOA551` | `getPet2` |
| Name that loses letters (`$type`) | Sanitised, `TOA559` | |
| Name with no letter or digit | `value_`, an `Api...` fallback or a place-based name, `TOA552` | enum value `~` gives `value_` |
| Enum value `unknown` | `unknown_` (the word is reserved for unknown values) | |
| Group (tag) | `{Tag}Api` (`naming.group`) | tag `store` gives `StoreApi` |
| Untagged operations | `DefaultApi` (`naming.default_group`) | `TOA554` |
| Method | `operationId` without `operation_prefix`, else `METHOD /path` | `GET /pets/{id}` gives `getPetsById`, `GET /orders/{a}/{b}` gives `getOrdersByAAndB` (`TOA503`) |

The arguments of a method also avoid the names the generator uses itself: a parameter named `body` or `call` becomes `body_` or `call_` (`TOA550`), and `jsonEncode` and `base64Encode` get a trailing underscore too. The rest of the naming settings (`naming.client`, `naming.group`, `naming.default_group`, `naming.input_suffix`, `naming.patch_suffix`, `naming.stream_suffix`, `naming.operation_prefix`) are listed in [Configuration](../configuration.md); an override of one name is `name:` in the [overrides file](../overrides.md).

> **Gotcha:** an `operationId` in the spec is the method name. If your backend regenerates its ids (`..._1` suffixes, a framework prefix), your method names change. Pin them with `name:` overrides or fix the ids at the source. See [Frameworks](../frameworks/nestjs.md) for the usual cases.

## What is deterministic

The same spec, overrides and config give the same bytes: declarations, files, imports and members are sorted, nothing reads the clock, the network or the environment, and the line width comes from the config (`line_width`, default 80). The manifest records a hash of every input, so `generate` knows when nothing changed and then does not touch the directory (`0 written` in the summary line). A generator update that changes the output is a breaking change of the generator, noted in its changelog.

## The guides

| Guide | Covers |
| --- | --- |
| [Models](models.md) | classes, `fromJson`/`toJson`, optional, nullable and tri-state fields, `allOf`, secrets |
| [Enums](enums.md) | known and unknown values, `x-enum-varnames` |
| [Unions](unions.md) | `oneOf`/`anyOf`, discriminators, the unknown variant |
| [Operations](operations.md) | group classes, method signatures, parameters, `CallOptions` |
| [Responses and errors](responses_and_errors.md) | `Result`, status types, undocumented statuses |
| [Request bodies](request_bodies.md) | JSON, forms, multipart, files, text, bytes |
| [Event streams](event_streams.md) | server-sent events |
| [Security](security.md) | security metadata and an interceptor |

## See also

- [Getting started](../getting_started.md) for the first run.
- [Generate output](../generate_output.md) for how the directory is written, locked and recovered.
- [Troubleshooting](../troubleshooting.md) for symptoms and fixes.
