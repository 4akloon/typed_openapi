# Spring (springdoc-openapi)

Spring Boot apps document themselves with springdoc-openapi, and the `springdoc` preset is the one for them. (There is no `spring` preset; the name is `springdoc`.) The defects you meet are `*/*` response media types, `_1` suffixes on `operationId`s, discriminators springdoc does not fully describe, and enum values named like Java constants (`NEW`, `UNKNOWN`). This guide shows them on a small Spring-style spec, the config that generates a client from it, and what the open-source Spring specs in the repository's corpus give.

## Config

```yaml
# typed_openapi.yaml
clients:
  shop:
    input: openapi.yaml
    output: lib/shop
    preset: springdoc
    overrides: overrides.yaml
    severity:
      TOA504: warning
```

The preset adds springdoc advice to the `fix:` text of `duplicate-operation-id`, `discriminator-mapping-target`, `wildcard-media-type` and `component-key-characters`; it changes no behaviour. See [Presets and rules](../presets_and_rules.md).

## What a springdoc spec looks like

The sample spec (OpenAPI 3.1) is what springdoc writes for a controller without `produces`, a `Pageable` parameter and a polymorphic response. `typed_openapi check` reports:

| Finding | Code | What happens |
| --- | --- | --- |
| Response content `*/*` | `TOA601` (warning) and `TOA650` (info) | The client cannot pick a decoder: the body is read as bytes and its schema is not used. This is the one to fix first. |
| `operationId: get_1` on two operations | `TOA504` (error) | Two methods would clash. |
| `discriminator.mapping` value that points nowhere | `TOA402` (error) | Spring does not complete the mapping from `@JsonSubTypes`. |
| Discriminator property not in `required` | `TOA401` (info) | A payload without it cannot be told apart. |
| Java enum constants `NEW`, `UNKNOWN` | `TOA550` (info) | Named `new_` and `unknown_` (Dart keywords and a reserved name). |

```text
warning TOA601 wildcard-media-type: The media type "*/*" does not say how the body is encoded, so the client cannot pick a decoder.
  at #/paths/~1api~1orders/get/responses/200/content/*~1*
  fix: Declare the actual media type (usually application/json) at the source, or override the content type here. In springdoc, set springdoc.default-produces-media-type=application/json.
info TOA650 media-type-as-bytes: The media type "*/*" of the response is not JSON, a form, text or an event stream, so it is sent as bytes and its schema is not used.
  at #/paths/~1api~1orders/get/responses/200/content/*~1*
  fix: Use a JSON media type at the source if the schema matters.
error TOA504 duplicate-operation-id: operationId "get_1" is also the id of the operation at #/paths/~1api~1invoices~1{id}/get; method names would clash.
  at #/paths/~1api~1payments~1{id}/get/operationId
  fix: Give each operation its own operationId at the source. To generate anyway, lower TOA504 in the client's severity and pin the second method's name with an override. In springdoc, set @Operation(operationId = "...") explicitly; the generated _1 suffixes are not stable.
error TOA402 discriminator-mapping-unresolved: discriminator.mapping "wire" points to "#/components/schemas/Missing", which does not exist.
  at #/paths/~1api~1payments~1{id}/get/responses/200/content/*~1*/schema/discriminator/mapping/wire
  fix: Point it at an existing schema at the source; until then, override the mapping of this discriminator. In springdoc, declare the mapping: @Schema(discriminatorProperty = "kind", discriminatorMapping = {@DiscriminatorMapping(value = "foo1", schema = Foo1.class)}).
info TOA550 name-reserved: Value "NEW" of enum OrderRequestStatus is named "new_".
  at #/components/schemas/OrderRequest/properties/status
  fix: Name the values with x-enum-varnames at the source.
```

(Shown with a dangling `wire` mapping value added to the sample to produce `TOA402`; the config below uses the sample without it. Each response with `*/*` gives one `TOA601` and one `TOA650`.)

## Overrides

The override file gives every `*/*` response the real media type and names the methods whose ids clash. An operation is addressed by `METHOD /path` because `get_1` is ambiguous:

```yaml
# overrides.yaml
operations:
  "GET /api/orders":
    name: listOrders
    responses: {'200': {contentType: application/json}}
  "POST /api/orders":
    name: createOrder
    responses: {'201': {contentType: application/json}}
  "GET /api/orders/{id}":
    name: getOrder
    responses: {'200': {contentType: application/json}}
  "GET /api/invoices/{id}":
    name: getInvoice
    responses: {'200': {contentType: application/json}}
  "GET /api/payments/{id}":
    name: getPayment
    responses: {'200': {contentType: application/json}}
```

An operation's override cannot change its `operationId`, so `TOA504` stays; it is an error that is not one of the fixed codes, so the config lowers it to a warning for this client until `@Operation(operationId = ...)` is set in the backend.

```text
$ typed_openapi generate
info TOA401 discriminator-not-required: Discriminator property "kind" is not required in Card, Transfer; a payload without it cannot be told apart.
  at #/paths/~1api~1payments~1{id}/get/responses/200/content/application~1json/schema/discriminator
  fix: Add "kind" to "required" of each variant at the source.
  related: Introduced by this override.
warning TOA504 duplicate-operation-id: operationId "get_1" is also the id of the operation at ...
info TOA550 name-reserved: Value "NEW" of enum OrderStatus is named "new_".
info TOA550 name-reserved: Value "UNKNOWN" of enum OrderStatus is named "unknown_".
errors: 0, warnings: 1, infos: 3
Generated shop in lib/shop: 16 files, 16 written, 0 deleted.
```

The methods (real output):

```dart
Future<Result<PageOrder, Never>> listOrders({required Pageable pageable, CallOptions? call})
Future<Result<Order, ProblemDetail>> createOrder({ ... })
Future<Result<Order, Never>> getOrder({ ... })
Future<Result<Invoice, Never>> getInvoice({ ... })
Future<Result<GetPaymentResponse, Never>> getPayment({ ... })   // sealed: Card | Transfer
```

Groups are named after springdoc's default tags (`order-controller` is `OrderControllerApi`); set `naming.group` or tag the controllers (`@Tag`) to change it, see [Configuration](../configuration.md). The `application/problem+json` error becomes the typed `ProblemDetail`, see [Responses and errors](../generated/responses_and_errors.md). The enum value `new_` is only a Dart name; the wire value stays `NEW`, see [Enums](../generated/enums.md).

## Real specs

Three open-source springdoc specs from the corpus (`packages/typed_openapi_tool/corpus.yaml`):

| Spec | Result |
| --- | --- |
| springdoc's own Spring Data REST test (HAL) | Generates (16 files). 6 diagnostics: `TOA601` for `*/*`, and `TOA651` where a response offers `application/vnd.hal+json` and `text/uri-list`: the client uses the first. |
| EFGS federation gateway (7 operations, 3.0.1) | Generates (5 files). `TOA553` on six operations that carry two tags (generated once, in the first tag's group), and `TOA651`: a request body offers JSON and protobuf, the JSON one is used. |
| Artemis (67 operations, flow-style YAML) | Not generated: `TOA009` (error), two `example: !!timestamp ...` values use a YAML tag OpenAPI does not allow. The rest is `TOA110` (an unknown key `if available`), `TOA457` (a discriminator value derived from the variant, not the mapping) and `TOA550` (`UNKNOWN` enum values). |

Only the first two have `expect: generate` in the corpus; Artemis is expected to fail with `TOA009`.

## Fix it in the backend

From the preset's hints and the springdoc documentation:

- `springdoc.default-produces-media-type=application/json` removes every `*/*`.
- Set `@Operation(operationId = "...")` explicitly; the `_1` suffixes depend on method order.
- Declare polymorphism twice: `@JsonTypeInfo`/`@JsonSubTypes` for Jackson and `@Schema(discriminatorProperty = "kind", discriminatorMapping = {...})` for the spec. Names from `@JsonSubTypes` do not reach the mapping by themselves.
- Name colliding schemas with `@Schema(name = "...")`; `component-key-characters` (`TOA106`) reports a `components` key that OpenAPI does not allow.
- Expand `Pageable` with `@ParameterObject` so `page`, `size` and `sort` are separate parameters instead of one object parameter.
- Pin the generated spec with a snapshot test in the backend's CI; springdoc output has changed between releases.

## Caveats

- The `springdoc` preset gives advice only. It does not turn `*/*` into JSON for you; that is the override above, per response.
- The `Pageable` parameter in the sample is one object query parameter; whether your server accepts that form depends on how the controller binds it.
- `Page<T>` wrappers are ordinary schemas: the client has a `PageOrder` model and no pagination helper.

## See also

- [Presets and rules](../presets_and_rules.md), [Overrides](../overrides.md), [Configuration](../configuration.md) (`severity`).
- [Diagnostics](../diagnostics.md), [Baseline](../baseline.md), [CI](../ci.md).
- Other frameworks: [NestJS](nestjs.md), [FastAPI](fastapi.md), [ASP.NET](aspnet.md).
