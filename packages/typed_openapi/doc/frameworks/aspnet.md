# ASP.NET Core

ASP.NET Core specs come from Swashbuckle.AspNetCore or from Microsoft.AspNetCore.OpenApi. The two have the same defects: no `operationId` unless the endpoint is named, the same response offered as `text/plain`, `application/json` and `text/json`, integer enums with no names, component keys with a `+` for nested types, and discriminators that need `[JsonPolymorphic]`. Use `preset: aspnet`. This guide shows them on a small Swashbuckle-style spec and what the repository's corpus (Jellyfin and Swashbuckle's own test site) gives.

## Config

```yaml
# typed_openapi.yaml
clients:
  zoo:
    input: swagger.json
    output: lib/zoo
    preset: aspnet
    overrides: overrides.yaml
```

The preset adds ASP.NET advice to the `fix:` text of `missing-operation-id` (`.WithName`, `[EndpointName]`, Swashbuckle's `CustomOperationIds`), `discriminator-property-required` (`[JsonPolymorphic]`) and `component-key-characters` (`CustomSchemaIds`). It changes no behaviour; see [Presets and rules](../presets_and_rules.md).

Export the document at build time (`swagger tofile`, or the `Microsoft.Extensions.ApiDescription.Server` package) or save the `/swagger/v1/swagger.json` response, and commit it.

## What the spec looks like

The sample spec (OpenAPI 3.0.4) has an `Animals` controller with one endpoint that has an `operationId` and two that have none, a response offered in three media types, an integer enum, a polymorphic `Animal` and the key `Result+Page`. `typed_openapi check` reports:

| Finding | Code | What happens |
| --- | --- | --- |
| Endpoint without `operationId` | `TOA503` (info) | The method is named from the HTTP method and the path. Name it in an override. |
| Response in `text/plain`, `application/json` and `text/json` | `TOA651` (info) | `application/json` is used and `text/plain` is dropped. `text/json` is JSON, so it is not reported. |
| Component key `Result+Page` | `TOA106` (warning) | OpenAPI allows only letters, digits, `.`, `-` and `_` in keys. The type is named `ResultPage`. |
| An enum value `Default` | `TOA550` (info) | Named `default_`; the wire value stays `Default`. |
| Integer enum `[0, 1, 2]` | none | Values are named `value0`, `value1`, `value2`. |

```text
info TOA651 media-types-dropped: The response offers 3 media types; "application/json" is used and "text/plain" is dropped.
  at #/paths/~1Animals/get/responses/200/content
  fix: Offer one media type at the source if the client should use another.
info TOA503 missing-operation-id: This operation has no "operationId", so its method is named after the HTTP method and the path.
  at #/paths/~1Animals/post
  fix: Add an operationId at the source, or override the method name of this operation. In ASP.NET, name the endpoint: .WithName("getUser") or [EndpointName("getUser")]; with Swashbuckle, CustomOperationIds(api => api.TryGetMethodInfo(out var mi) ? mi.Name : null).
info TOA550 name-reserved: Value "Default" of enum Diet is named "default_".
  at #/components/schemas/Diet
  fix: Name the values with x-enum-varnames at the source.
warning TOA106 invalid-component-key: The component name "Result+Page" has characters OpenAPI does not allow in component keys (only letters, digits, ".", "-" and "_").
  at #/components/schemas/Result+Page
  fix: Rename it at the source; type names are derived from it. With Swashbuckle, set CustomSchemaIds(t => t.FullName!.Replace('+', '.')).
errors: 0, warnings: 1, infos: 4
```

## Overrides

Name the endpoints that have no id. Without an `operationId` an operation is addressed by `METHOD /path`:

```yaml
# overrides.yaml
operations:
  "POST /Animals":
    name: createAnimal
  "GET /Animals/{id}":
    name: getAnimal
```

`typed_openapi generate` then writes (real output):

```dart
Future<Result<List<Animal>, Never>> getAnimals({ ... })           // operationId GetAnimals
Future<Result<Animal, ProblemDetails>> createAnimal({Animal? body, CallOptions? call})
Future<Result<Animal, ProblemDetails>> getAnimal({ ... })
Future<Result<ResultPage, Never>> getReport({ ... })              // ReportsApi
```

- `Animal` (a discriminator `kind` with a mapping and `Lion` extending it through `allOf`) is a sealed class with `AnimalLion` and an `AnimalUnknown` for a value no variant has. See [Unions](../generated/unions.md).
- The `application/problem+json` error is the typed `ProblemDetails`; see [Responses and errors](../generated/responses_and_errors.md).
- The request body of the sample has no `required: true`, so `body` is optional and the call sends no `Content-Type` without one. See [Request bodies](../generated/request_bodies.md).
- The unnamed integer enum `AnimalKind` is `AnimalKind.value0`, `value1` and `value2`. Give the names in the spec with `x-enum-varnames`, or make the server write strings (see below). See [Enums](../generated/enums.md).

## Real specs

Both are in the repository's corpus (`packages/typed_openapi_tool/corpus.yaml`) and generate with `preset: aspnet`:

| Spec | Result of `check` |
| --- | --- |
| Jellyfin (Swashbuckle, 364 operations, 3.0.4) | Generates 346 files. 32 diagnostics, none an error: `TOA550` (22, enum values such as `Default`), `TOA651` (5, for example `text/css` dropped beside `application/json`), `TOA401` (3, a discriminator property `Type` that the variants do not require) and `TOA658` (2, a `302` response that is not generated). |
| Swashbuckle's test site (.NET 10) | Generates 8 files. `TOA503` (4, endpoints without an id) and `TOA453` (3, a `oneOf` without a discriminator, generated as `JsonValue`). |

## Fix it in the backend

From the preset's hints and the framework documentation:

- **Operation ids.** `.WithName("getUser")` or `[EndpointName("getUser")]`; with Swashbuckle, `o.CustomOperationIds(api => api.TryGetMethodInfo(out var mi) ? mi.Name : null)`.
- **One media type.** `[Produces("application/json")]` and `[Consumes("application/json")]` remove `text/plain`, `text/json` and `application/*+json`.
- **Errors:** `[ProducesResponseType<ProblemDetails>(400, "application/problem+json")]`.
- **Enums as strings.** Register `JsonStringEnumConverter` so the document lists names, not numbers. With Microsoft.AspNetCore.OpenApi the JSON options are the global `Microsoft.AspNetCore.Http.Json.JsonOptions`; MVC's `AddJsonOptions` does not reach the document.
- **Polymorphism.** `[JsonPolymorphic]` on an abstract base type and `[JsonDerivedType(typeof(Bar), "bar")]` for each variant; a concrete base type does not put the discriminator in the document. With Swashbuckle also `UseAllOfForInheritance()` and `UseOneOfForPolymorphism()`.
- **Schema ids.** `o.CustomSchemaIds(t => t.FullName!.Replace('+', '.'))` for nested types and generic clashes.
- **Required and nullable.** `[Required]` or the `required` modifier; with Swashbuckle `SupportNonNullableReferenceTypes()` and `NonNullableReferenceTypesAsRequired()`.
- **OpenAPI 3.1.** The document version is chosen by `OpenApiVersion` in Microsoft.AspNetCore.OpenApi and by `UseSwagger(o => o.OpenApiVersion = ...)` in Swashbuckle 10; both are read by this tool.

## Caveats

- Without `operationId` the generated names depend on the path. Name the methods in the overrides, or the next route change renames them.

## See also

- [Presets and rules](../presets_and_rules.md), [Overrides](../overrides.md), [Configuration](../configuration.md).
- [Diagnostics](../diagnostics.md), [Baseline](../baseline.md), [CI](../ci.md).
- [Security](../generated/security.md): Bearer and API key schemes.
- Other frameworks: [NestJS](nestjs.md), [FastAPI](fastapi.md), [Spring](spring.md).
