# Support matrix

What `typed_openapi` does with each part of an OpenAPI document. The table is written by hand, not generated: each row names the tests, fixtures or corpus file that show the behaviour, and `support_matrix_test.dart` in `typed_openapi_tool` fails when a row has no proof or its proof file does not exist. A row is a claim about the code at the time of writing; when the proof test changes, read the row again.

| Status | Meaning |
| --- | --- |
| `Supported` | Read, and the generated client uses it. |
| `Partly` | Read, with a stated limit. |
| `Reported` | Read, not generated; a diagnostic with a stable code says so. |
| `Not supported` | Not read; a diagnostic says so. |

## Documents and references

| Feature | Status | What happens | Proof |
| --- | --- | --- | --- |
| OpenAPI 3.0.x, 3.1.x and 3.2.x as JSON or YAML (a construct of another version is `TOA020`-`TOA022`) | Supported | The version is read from `openapi`. A 3.1 construct in a 3.0 document is read as 3.1 (`TOA020`, warning); `nullable` in a 3.1 document is read as in 3.0 (`TOA021`, warning); a 3.2 construct in an older document is read anyway (`TOA022`, info). | `packages/typed_openapi_core/test/parse/dialect_checker_test.dart` |
| `$ref` to a component or a file on disk | Supported | Local references and relative files are followed; a reference that is malformed, does not resolve, loops or points at the wrong kind of object is an error (`TOA100`, `TOA101`, `TOA103`, `TOA104`). | `packages/typed_openapi_core/test/resolve/ref_resolver_test.dart` |
| `$ref` to a URL (`TOA102`) | Not supported | Only local files are read; the network is never called. The reference is an error (`TOA102`). | `packages/typed_openapi_core/test/resolve/ref_target_test.dart` |

## Schemas

| Feature | Status | What happens | Proof |
| --- | --- | --- | --- |
| Objects, arrays, scalars, `additionalProperties` | Supported | Objects become models, arrays lists, `additionalProperties` a map or an extra-keys field. | `packages/typed_openapi_core/test/ir/schema_mapper_test.dart` |
| `required` and nullability, 3.0 and 3.1 spellings | Supported | `nullable: true` (3.0) and a `null` in `type` or an `anyOf` branch (3.1) both give a nullable Dart type. | `packages/typed_openapi_core/test/ir/schema_mapper_test.dart` |
| `allOf` (`TOA252`, `TOA253`) | Supported | The parts are merged into one model. Two parts that define a property differently: the later one wins (`TOA252`, info). A part that is not an object is ignored (`TOA253`, warning). | `packages/typed_openapi_core/test/ir/schema_mapper_composition_test.dart`, `packages/typed_openapi_core/test/ir/schema_mapper_allof_test.dart` |
| `oneOf`/`anyOf` with a discriminator | Supported | A sealed union picked by the discriminator value, with an unknown variant that keeps the raw JSON. | `packages/typed_openapi_core/test/ir/union_dispatch_test.dart` |
| `oneOf`/`anyOf` without a discriminator (`TOA453`, `union: structural`) | Partly | Variants of different JSON types are told apart by type. Variants of the same type cannot be: they share one `JsonValue` variant (`TOA453`, warning), unless `union: structural` is set, which tries the variants in order. | `packages/typed_openapi_core/test/ir/union_dispatch_test.dart` |
| Enums (open, `x-enum-varnames`) | Supported | An enum keeps a value the spec does not list as an unknown value; `x-enum-varnames` names the values (see [Extensions](extensions.md)). | `packages/typed_openapi/test/emit/model_library_test.dart`, `packages/typed_openapi_core/test/ir/schema_mapper_enum_names_test.dart` |
| `readOnly` and `writeOnly` | Supported | A schema used both in requests and responses is split into a request model and a response model; `writeOnly` and `format: password` fields print as `<redacted>`. | `packages/typed_openapi_core/test/ir/ir_builder_test.dart`, `packages/typed_openapi_core/test/ir/patch_models_test.dart`, `packages/typed_openapi/test/emit/model_library_test.dart` |
| PATCH bodies (tri-state) | Supported | A PATCH body field is absent, `null` or a value (`Patch<T>`); `tri_state` in the [configuration](configuration.md) sets the rule. | `packages/typed_openapi_core/test/ir/patch_models_test.dart` |
| Constraints (`minLength`, `maximum`, `pattern` and the like) | Partly | Written into the doc comment of the field; the generated code does not validate them. | `packages/typed_openapi/test/emit/model_library_test.dart` |
| `default` values | Partly | Written into the doc comment of the field or parameter; the client does not send or apply them. | `packages/typed_openapi/test/emit/model_library_test.dart` |
| `const` | Supported | A property fixed by `const` is a constant of the model; an optional one is read with `JsonReader.constant`, so a decoded value is written back as it came. | `packages/typed_openapi/test/emit/optional_constant_test.dart`, `packages/typed_openapi_test_support/lib/fixtures/optional_constant.yaml` |

## Operations

| Feature | Status | What happens | Proof |
| --- | --- | --- | --- |
| Path, query and header parameters and their styles | Supported | The client expands them itself (OpenAPI styles, RFC 6570, RFC 3986 percent-encoding). A style its location does not allow falls back to the default (`TOA564`). | `packages/typed_openapi_client/test/params/parameters_test.dart` |
| Cookie parameters (not on the web) | Partly | Sent as a `Cookie` header; a browser drops that header, so on the web they do not reach the server. | `packages/typed_openapi_dio/test/cookie_browser_test.dart` |
| `in: querystring` (`TOA565`) | Reported | The parameter is not generated (`TOA565`, warning). | `packages/typed_openapi_core/test/ir/operation_builder_test.dart` |
| Request bodies: JSON, forms, multipart, text, bytes, files | Supported | JSON through `toJson`, forms and multipart with their `encoding`, text as `String`, other media types as bytes (the dropped ones are named, `TOA651`). | `packages/typed_openapi_client/test/request/body_encoder_test.dart` |
| Response codes, ranges and `default` | Supported | Each documented success and error status becomes a typed case of the `Result`; a status the spec does not list is an undocumented status. A key that is none of these is skipped (`TOA657`). | `packages/typed_openapi_core/test/ir/response_status_test.dart` |
| `1xx` and `3xx` responses (`TOA658`) | Reported | Not generated (`TOA658`, info); at run time such a status is an undocumented one, or handled by `default`. | `packages/typed_openapi_core/test/ir/response_status_test.dart` |
| Event streams (`text/event-stream`) | Supported | The method returns a `Stream` of events with reconnection; a stream whose successes disagree on the event type is not generated (`TOA654`). | `packages/typed_openapi_core/test/ir/event_stream_test.dart`, `packages/typed_openapi/test/emit/event_stream_emit_test.dart`, `packages/typed_openapi_client/test/sse/sse_reconnect_progress_test.dart` |
| Security schemes (metadata only) | Partly | Each operation carries its security requirements as data; the client never signs a request (see [Security](generated/security.md)). A scheme the spec does not define is `TOA568`. | `packages/typed_openapi_core/test/ir/operation_metadata_test.dart` |
| Servers of the document | Supported | Written as `static const` strings, or methods of the server variables, on the root client; the transport sets the base URL. | `packages/typed_openapi/test/emit/goldens/petstore/api_client.dart.golden`, `packages/typed_openapi_core/test/ir/root_names_test.dart` |
| Servers of a path item or an operation (`TOA566`) | Reported | Ignored; every request goes to the base URL of the transport (`TOA566`, warning). | `packages/typed_openapi_core/test/ir/operation_metadata_test.dart` |
| Callbacks and webhooks (`TOA567`) | Reported | Not generated (`TOA567`, info). | `packages/typed_openapi_core/test/ir/operation_metadata_test.dart` |

## Around the generator

| Feature | Status | What happens | Proof |
| --- | --- | --- | --- |
| Overrides | Supported | An [overrides file](overrides.md) changes names, types, nullability and more by location, without editing the spec; an address that matches nothing is `TOA804`. | `packages/typed_openapi_core/test/overrides/override_applier_test.dart` |
| Name stability and API diff | Supported | `typed_openapi.lock` keeps the names of models, enums, unions and methods between runs, and `diff` lists the changes by category (see [Command line](cli.md#diff)). | `packages/typed_openapi_core/test/ir/name_lock_hostile_test.dart`, `packages/typed_openapi_core/test/diff/api_diff_rules_test.dart`, `packages/typed_openapi_core/test/snapshot/snapshot_builder_test.dart` |
| Fixes for imperfect, code-first specs | Supported | [Normalizer rules](presets_and_rules.md) repair common defects and report each fix with a code. | `packages/typed_openapi_core/test/normalize/normalizer_end_to_end_test.dart` |
| Real specs | Supported | `corpus.yaml` pins public specs (GitHub, Stripe, OpenAI and others); the corpus run generates their clients, analyses the output and round-trips examples. | `packages/typed_openapi_tool/corpus.yaml` |

## See also

- [Presets and rules](presets_and_rules.md): what the normalizer fixes.
- [Diagnostics](diagnostics.md): every code in this table.
- [Extensions](extensions.md): the `x-` keys that are read.
- [The generated client](generated/overview.md): what `generate` writes.
