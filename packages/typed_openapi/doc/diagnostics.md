# Diagnostics reference

Every problem `typed_openapi` finds in a spec, an overrides file, a baseline or a config has a stable code such as `TOA501`. This guide is the single reference for all 128 codes: what each one means and how to fix it. Other guides link here instead of repeating the table.

```text
warning TOA501 missing-path-parameter: The path /products/{id} has {id}, but this operation declares no path parameter "id"; it is added as a required string path parameter.
  --> specs/shop.yaml:30:7
  at #/paths/~1products~1{id}/get
  fix: Declare each at the source as {name: <name>, in: path, required: true, schema: {type: string}}.
```

A code never changes meaning once released. The slug (`missing-path-parameter`) is its readable name; both work wherever a code is accepted.

## Severity and levels

Every code has a default severity: `error`, `warning` or `info`. Errors make `check` and `generate` exit with `1`; warnings and infos do not (see [CLI](cli.md#exit-codes)). A client changes the level of a code in `severity:` of the config, by id or by slug, and `off` removes the code from the report (see [Configuration](configuration.md#severity)).

```yaml
clients:
  shop:
    input: specs/shop.yaml
    output: lib/src/api/shop
    severity:
      TOA201: info
      duplicate-operation-id: error
      TOA553: off
```

Three groups of codes are limited:

| Group | Codes | Rule |
| --- | --- | --- |
| Config codes | TOA901, TOA902, TOA903, TOA904 | The level cannot be changed at all, because the config is read before levels apply. Setting one is TOA902. |
| Fixed codes | Marked `fixed` below | The level can be raised but not lowered, and they cannot be turned off. |
| Everything else | All other codes | Any of `error`, `warning`, `info`, `off`. |

> **Note:** A baseline accepts only errors and warnings of codes that are not fixed. Infos are never accepted. See [Baseline](baseline.md).

The column "Default" below shows the severity before `severity:` applies. The column "Fix" is the text the tool prints after `fix:`; when it depends on the situation the table says to read the message.

> **Gotcha:** Two diagnostics that are equal (same code, severity, message, file, pointer and start position) are reported once, so a region of the spec that is read twice does not repeat its problems.

## Load (TOA0xx)

Reading the spec files: JSON/YAML syntax, versions and limits.

| Code | Slug | Default | Meaning | Fix |
| --- | --- | --- | --- | --- |
| TOA001 | `parse-error` | error (fixed) | The document is not valid JSON or YAML. | See the message of the diagnostic. |
| TOA002 | `duplicate-key` | warning | A mapping repeats a key. | Remove one of the keys. |
| TOA003 | `root-not-object` | error (fixed) | The document root is not an object. | See the message of the diagnostic. |
| TOA004 | `input-not-found` | error (fixed) | The input file, or a file a `$ref` points to, does not exist. | Check "input" in the config, or download a fresh snapshot. |
| TOA005 | `positions-unavailable` | info | Source positions could not be recorded for a document. | See the message of the diagnostic. |
| TOA006 | `input-unreadable` | error (fixed) | The input file exists but cannot be read as UTF-8 text. | Point "input" at the spec file itself. |
| TOA007 | `nesting-too-deep` | error (fixed) | The document nests deeper than the parser can follow, in its text or once YAML aliases are expanded. | See the message of the diagnostic. |
| TOA008 | `alias-expansion-too-large` | error (fixed) | YAML aliases expand to far more nodes than the text has, or the JSON pointers of the document's nodes add up to more than the budget. | See the message of the diagnostic. |
| TOA009 | `yaml-tag-unsupported` | error | A YAML tag outside the JSON Schema ruleset OpenAPI requires, such as `!!timestamp` or `!custom`; the value is read as its text. | See the message of the diagnostic. |
| TOA010 | `missing-openapi-version` | error (fixed) | The document has no `openapi` field. | Add the version the backend emits, for example "openapi: 3.0.3". |
| TOA011 | `unsupported-openapi-version` | error (fixed) | The document declares a version this tool does not read. | Have the backend emit OpenAPI 3, or convert the document. |
| TOA012 | `unknown-openapi-minor-version` | warning | The document declares a 3.x minor version newer than 3.2. | See the message of the diagnostic. |
| TOA013 | `openapi-version-not-string` | warning | The `openapi` field is not a string, so YAML may have changed it (3.10 reads as 3.1). | Quote the version, for example openapi: "3.1.0". |
| TOA015 | `yaml-warning` | warning | The YAML parser warns about the text, for example about an unknown directive; reading goes on. | See the message of the diagnostic. |
| TOA020 | `openapi-3-1-in-3-0` | warning | A 3.0 document uses an OpenAPI 3.1 or JSON Schema 2020-12 construct; it is read as 3.1. | See the message of the diagnostic. |
| TOA021 | `nullable-after-3-0` | warning | A 3.1 or later document uses `nullable`, which only 3.0 defines; it is read as in 3.0. | Write type: [<type>, "null"] instead of nullable: true. |
| TOA022 | `openapi-3-2-in-older` | info | A document older than 3.2 uses an OpenAPI 3.2 construct; it is read anyway. | Declare "openapi: 3.2.0" if the backend emits 3.2; otherwise remove the construct. |

## Parse and resolve (TOA1xx)

Reading the OpenAPI objects and following `$ref`s.

| Code | Slug | Default | Meaning | Fix |
| --- | --- | --- | --- | --- |
| TOA100 | `invalid-ref` | error | A `$ref` is empty, truncated or not a URI with a JSON pointer. | Fix the code that writes the spec; in NestJS this usually means a circular import made a DTO type undefined. |
| TOA101 | `unresolved-ref` | error | A `$ref` points to a file or a node that does not exist. | Define the target, or point the reference at an existing one. |
| TOA102 | `remote-ref` | error | A `$ref` points to a remote URL; only local files are read. | Save the document next to the spec and refer to it by a relative path. |
| TOA103 | `ref-cycle` | error | `$ref`s point at each other in a loop that never reaches a definition. | Point one of them at the actual definition. |
| TOA104 | `ref-kind-mismatch` | error | A `$ref` points to a node of another kind, such as a schema where a parameter is expected. | See the message of the diagnostic. |
| TOA105 | `ref-base-ignored` | warning | `$id` or `$self` would change the base URI of `$ref`s; this tool resolves them against the file location instead. | See the message of the diagnostic. |
| TOA106 | `invalid-component-key` | warning | A key in `components` has characters OpenAPI does not allow there. | Rename it at the source; type names are derived from it. |
| TOA107 | `ref-not-allowed` | warning | A `$ref` where OpenAPI does not accept a Reference Object, as bundlers such as Redocly allow; it is ignored. | See the message of the diagnostic. |
| TOA108 | `ref-commented-out` | warning | `$ref: #/...` without quotes in YAML: `#` starts a comment, so the value is null. | See the message of the diagnostic. |
| TOA109 | `yaml-merge-key` | warning | A YAML 1.1 merge key `<<`, which OpenAPI's YAML does not have; it is read as a plain key named `<<`. | Write the keys out. |
| TOA110 | `unknown-key` | warning | An object has a key that no OpenAPI version defines; it is ignored. | See the message of the diagnostic. |
| TOA111 | `invalid-value` | warning | A field has the wrong JSON type or a value the spec does not allow; it is ignored. | For an unknown `type`: Use one of string, number, integer, boolean, array, object, null. |
| TOA112 | `missing-required-field` | warning | A field the spec requires is missing. | See the message of the diagnostic. |
| TOA113 | `non-string-key` | error | A mapping key is a collection, or an alias of one, instead of a string; the entry is ignored. | Write the key as a plain or quoted string. |
| TOA114 | `null-key` | warning | A mapping key is a YAML null (`~`, `null` or empty); it is read as its text. | Quote the key: "$text". |

## Normalizer and schema mapping (TOA2xx)

Schema problems that the normalizer repairs or the mapper has to work around.

| Code | Slug | Default | Meaning | Fix |
| --- | --- | --- | --- | --- |
| TOA201 | `bool-required` | warning | A property schema says `required: true` or `false` (OpenAPI 2 style); the name is moved into the object's `required` list. | See the message of the diagnostic. |
| TOA202 | `array-without-items` | warning | An array has no `items` in an OpenAPI 3.0 document, which requires it. | Add "items" with the element schema at the source, or override "items" of this schema. |
| TOA203 | `double-array` | warning | An array's `items` is an array with a boolean `required`: a list declared twice by a decorator. | See the message of the diagnostic. |
| TOA204 | `format-on-array` | warning | `format` is on an array without `items` instead of on its elements. | See the message of the diagnostic. |
| TOA205 | `binary-object` | warning | `type: object` with `format: binary` instead of a binary string. | See the message of the diagnostic. |
| TOA206 | `contradictory-object-type` | warning | `type: object` next to `oneOf`/`anyOf` whose branches are all of other types. | See the message of the diagnostic. |
| TOA207 | `example-type-mismatch` | warning | An `example` whose structure the schema does not allow: an object for an array, or a structure for a scalar and back. | Fix the schema or the example at the source; if the example is right, override "type" of this schema. |
| TOA208 | `example-scalar-type` | info | An `example` that is a scalar of another type than the scalar schema, such as a string for a number; only the documentation is off. | Write the example as a $names at the source. |
| TOA211 | `invalid-default` | warning | A schema's `default` is not of the schema's type; it is ignored. | Change the default to a value of type $types, or remove it. |
| TOA250 | `mixed-type-schema` | warning | A schema allows several JSON types besides `null` (`type: [string, integer]`); it is generated as `JsonValue`. | Give the schema one type at the source, or a Dart type with an override. |
| TOA251 | `recursive-alias` | warning | A schema that is not an object, an enum or a union refers to itself (`A: {type: array, items: {$ref: A}}`); the reference is generated as `JsonValue`. | Make the recursive part an object schema at the source. |
| TOA252 | `allof-property-conflict` | info | Two `allOf` parts define the same property with different schemas; the later part's is used. | Define each property in one allOf part at the source. |
| TOA253 | `allof-part-ignored` | warning | An `allOf` part is not an object (a scalar, an enum or a union), so it cannot be merged into a model; it is ignored. | Make every allOf part an object schema at the source. |
| TOA254 | `excluded-schema-referenced` | info | A schema an override excludes is used by a generated type; the use is generated as `JsonValue`. An excluded `allOf` part is the exception: it is merged into the flat model all the same, and this says so. | Remove the exclude, or the custom type. |
| TOA255 | `oneof-constraints-ignored` | info | An object with `properties` has a `oneOf` or `anyOf` whose branches only add constraints (`required`, `minProperties`, ...); it is generated as a model and the branches are ignored. | Nothing to do; the constraints are not checked by the client. |
| TOA256 | `composition-parts-ignored` | warning | Parts, properties or branches of a schema are ignored because another keyword decides its shape: `allOf` parts or `properties` beside a `oneOf` or `anyOf` union, or the union's branches when the schema is a model made of `allOf` parts or `properties`. | Move the properties into the branches, or make the schema a plain union at the source. |

## Enums (TOA3xx)

Enum values and their names.

| Code | Slug | Default | Meaning | Fix |
| --- | --- | --- | --- | --- |
| TOA301 | `duplicate-enum-value` | warning | An `enum` repeats a value; the repeats are removed. | Remove the repeated values at the source. |
| TOA303 | `nullable-enum-one-of` | warning | A nullable enum written as `oneOf` of an enum of only `null` and a `$ref`. | See the message of the diagnostic. |
| TOA350 | `enum-mixed-values` | warning | An enum mixes values of several JSON types, or has objects or lists among its values; it is generated as `JsonValue`. | Give the enum values of one JSON type at the source. |
| TOA351 | `enum-varnames-invalid` | warning | `x-enum-varnames` or `x-enum-descriptions` is not a list of strings as long as the enum; it is ignored. | See the message of the diagnostic. |

## Discriminators and unions (TOA4xx)

How `oneOf`/`anyOf` and discriminators become Dart types.

| Code | Slug | Default | Meaning | Fix |
| --- | --- | --- | --- | --- |
| TOA401 | `discriminator-not-required` | info | The discriminator property is not required in a variant. | Add "$property" to "required" of each variant at the source. |
| TOA402 | `discriminator-mapping-unresolved` | error | A `discriminator.mapping` value points to a schema that does not exist. | Point it at an existing schema at the source; until then, override the mapping of this discriminator. |
| TOA450 | `discriminator-value-missing` | warning | A variant of a union with a discriminator is written inline, so no discriminator value selects it. | See the message of the diagnostic. |
| TOA451 | `discriminator-mapping-not-variant` | info | A `discriminator.mapping` value names a schema that is not a variant of the union; it is ignored. | Map the value to a schema that extends the base. |
| TOA452 | `discriminator-without-subtypes` | info | A `discriminator` sits on a schema that is neither a `oneOf`/`anyOf` union nor a base other schemas extend with `allOf`: nothing can be picked by it, so the schema is generated as a model. | Extend the schema with allOf in its subtypes, or list them in a oneOf. |
| TOA453 | `union-undiscriminated` | warning | A `oneOf` or `anyOf` without a discriminator has variants of the same JSON type, or a variant that can hold several (a nested union without a discriminator), so a value cannot be told apart (R9.2): the union keeps it as `JsonValue` in one variant (`PetJson`), or, when no variant has a JSON type of its own, is `JsonValue` itself. An override `union: structural` (or the config key `union`) generates a union that tries the variants; a discriminator at the source is better. | Add a discriminator at the source, or generate a union that tries the variants with union: structural (an override of the schema, or the config key for every such union). |
| TOA454 | `union-variant-duplicate` | info | Two variants of a union have the same Dart type; the later one is dropped, since a value could not be told apart between them. | Remove the duplicate variant at the source. |
| TOA455 | `union-branch-subsumed` | info | A branch of a `oneOf` or `anyOf` without a discriminator is an enum or a `const` of a primitive type (`string`, `integer`, `number`, `boolean`) while another branch is that type with no constraint: the values of the first are values of the second, so the branch is dropped and, when one branch remains, the union is that type (Stripe's `anyOf: [string, {enum: ['']}]`). An integer enum next to a plain `number` is dropped too; a number enum next to an `integer` is not.  The other branch counts as plain when it has no `enum`, `const`, `format`, `pattern` or keyword the rule does not model (`if`, `not`, `dependentSchemas`, ...), and every enum value meets its length and range constraints (`multipleOf` on the exact decimal numbers). From OpenAPI 3.1 the keywords next to the `$ref` of a branch are the branch's own and are held to the same rule; 3.0 ignores them. The values of a dropped branch stay in the documentation of the field ("Known values") when the union is a union class or collapses; a union that stays `JsonValue` lists none.  For a `oneOf` the collapse is looser than the spec: a value both branches take (`''` for `oneOf: [string, {const: ''}]`) is rejected by the `oneOf` and accepted by the type. This is accepted on purpose: the idiom is common (Stripe), its authors mean "any of these", and the client does not validate. | Remove the enum branch at the source, or leave it for the documentation. |
| TOA456 | `discriminator-value-duplicate` | warning | Two variants of a union with a discriminator are selected by the same value (a `const` of the property, a mapping entry or the implicit name): the earlier variant decodes it, and the later one is never picked by that value. | Give each variant its own discriminator value, in the mapping or in the const of the property. |
| TOA457 | `discriminator-value-derived` | info | A `$ref` variant that the discriminator's `mapping` does not name fixes the discriminator property to one value (a `const` or a one-value `enum`, also through a `$ref` or an `allOf` part) that is not its component name: that value selects it, not the name OpenAPI implies (OpenAI's tool unions). An explicit `mapping` entry always wins. | Add $quotedValue to the mapping to say so, or map the name $quotedKey if the payloads carry it. |

## Paths, naming and operations (TOA5xx)

Operation ids, parameters, groups and Dart names.

| Code | Slug | Default | Meaning | Fix |
| --- | --- | --- | --- | --- |
| TOA501 | `missing-path-parameter` | warning | A variable of the path template has no path parameter; one is added. | Declare each at the source as {name: <name>, in: path, required: true, schema: {type: string}}. |
| TOA502 | `path-parameter-not-in-template` | error | A path parameter is not a variable of the path template, or is one in another case. | Make the parameter name and the template variable the same at the source; until then, override the name of this parameter. |
| TOA503 | `missing-operation-id` | info | An operation has no `operationId`. | Add an operationId at the source, or override the method name of this operation. |
| TOA504 | `duplicate-operation-id` | error | Two operations share an `operationId`. | Give each operation its own operationId at the source. To generate anyway, lower TOA504 in the client's severity and pin the second method's name with an override. |
| TOA550 | `name-reserved` | info | A name from the spec is a Dart reserved word or a name Dart already has (`class`, `List`); the generated name gets a suffix. | See the message of the diagnostic. |
| TOA551 | `name-collision` | info | Two generated declarations, members or arguments would have the same name; the later one (by spec location) gets a suffix. | Rename the other type, or rename this one. |
| TOA552 | `name-unrepresentable` | warning (info for an enum value) | A name from the spec has no ASCII letter or digit, so no Dart name can be made from it; a generic name is used. | Rename the schema at the source, or name its type. |
| TOA553 | `operation-multiple-tags` | info | An operation has several tags; it is generated once, in the group of its first tag. | Keep one tag at the source, or name the group. |
| TOA554 | `operation-untagged` | info | An operation has no tag; it is generated in the default group. | Tag the operations at the source, or set group_by to path or single in the config. |
| TOA555 | `tags-merged` | info | Two tags differ only in case or separators, so they give one group. | Write the tag the same way everywhere at the source. |
| TOA556 | `path-variable-unbound` | error | A variable of the path template has no path parameter with its exact name (`{ID}` with a parameter `id`); the operation is not generated. | Declare a path parameter named "$variable" at the source. |
| TOA557 | `filter-matches-nothing` | warning | A tag, `operationId` or path pattern of the config's `include` or `exclude` matches no operation of the spec. | Fix the pattern, or remove it from the config. |
| TOA558 | `filter-conflict` | info | The config lists the same tag, `operationId` or path pattern in both `include` and `exclude`; `exclude` wins. | Remove it from one of the filters. |
| TOA559 | `name-lossy` | info | A name from the spec lost characters when it became a Dart name (`Größe` became `GrE` and `Länge` became `lNge`: letters outside ASCII are dropped). Changes of case and separators (`my_thing`, `X-Request-ID`) are not reported. | Name it explicitly to keep the meaning: the text of the diagnostic ends with an `Override:` snippet. For a client name, set naming.client in the config. |
| TOA560 | `override-name-invalid` | warning | An override `name` (of a schema, property, operation, parameter) or `group` is not a valid Dart name for what it names (`my thing`, `1x`, `_private`), or loses characters when it is made one; the name made from it is used, or the override is ignored when nothing is left. A `group` that differs from UpperCamelCase only by case or separators (`pet-store`) is not reported: it is used as `PetStore`. | See the message of the diagnostic. |
| TOA563 | `client-empty` | warning | No operation of a client is generated: all are filtered out, all are written as a `$ref` (TOA107), or all have an unbound path variable (TOA556). The message says why. | See the message of the diagnostic. |
| TOA564 | `parameter-style-invalid` | warning | A parameter's `style` is not allowed for its `in` (path takes `simple`, `label` or `matrix`; query `form`, `spaceDelimited`, `pipeDelimited` or `deepObject`; header `simple`; cookie `form` or `cookie`), or the `style` of the `encoding` of a form property is not one a query takes, so the default style is used. | Use one of these styles at the source. |
| TOA565 | `querystring-not-generated` | warning | A parameter is `in: querystring` (OpenAPI 3.2), which the client cannot send yet: the parameter is not generated (TOA564 until M9). | Describe the query string as query parameters at the source. |
| TOA566 | `operation-servers-ignored` | warning | A path item or an operation has its own `servers`; the client sends every request to the base URL of the user's Dio. | Set the base URL for these requests in an interceptor, or move the servers to the document. |
| TOA567 | `callbacks-not-generated` | info | An operation has `callbacks`, or the document has `webhooks`: requests the server makes, which the client does not generate. | See the message of the diagnostic. |
| TOA568 | `security-scheme-unknown` | warning | A security requirement names a scheme that `components.securitySchemes` does not have (or defines without a valid type), or is not an object (a string, `null`; also TOA111): the alternative is left out of the operation's metadata when another one can be described, else it stays with a scheme of the kind unknown. | Write the requirement as an object at the source. |

## Media types, errors and event streams (TOA6xx)

Bodies, responses, defaults and Server-Sent Events.

| Code | Slug | Default | Meaning | Fix |
| --- | --- | --- | --- | --- |
| TOA601 | `wildcard-media-type` | warning | `*/*` is used as a media type. | Declare the actual media type (usually application/json) at the source, or override the content type here. |
| TOA650 | `media-type-as-bytes` | info | A request or response body has a media type that is not JSON, a form, `multipart/form-data`, `text/*` or `text/event-stream` (or is a form or multipart response): it is sent or read as bytes and its schema is not used (TOA561 until M9). | Use a JSON media type at the source if the schema matters. |
| TOA651 | `media-types-dropped` | info | A request body, a response or a parameter offers several media types; the client uses one and the message names the ones it drops (TOA561 until M9). | Remove sse.method: only to keep the body in a method too. |
| TOA652 | `default-error-schema-missing` | warning | `errors.default_schema` names a key that is not in `components.schemas`; the setting is ignored (TOA562 until M9). | Name a key of components.schemas, or remove the setting. |
| TOA653 | `success-undocumented` | warning | An operation documents no 2xx response: any 2xx is a success whose value is the body as `JsonValue`. | Document the success response at the source. |
| TOA654 | `event-stream-not-generated` | warning | An event-stream operation has a shape the client cannot express: its event-stream successes have different event types, or another success has a body that is not an event stream. The operation is not generated when some of its successes are only a stream; when each stream offers a body too, only the event-stream method is left out and the method that returns the body is generated. | Offer text/event-stream on every success with   event_streams.dart : .eventStreamNotGenerated,  |
| TOA655 | `multipart-not-object` | warning | The schema of a multipart body is not an object with properties (a union, an `allOf`, a map): there is no class of parts, the body is the schema's type, each property of its JSON is a part, and a binary string is sent as base64 text, not as a file. | Describe the body as an object with a property for each part at the source. |
| TOA656 | `encoding-headers-ignored` | info | An `encoding` entry of a multipart part or of a form property has `headers`, which the client does not send. | Send the headers another way, or remove them at the source. |
| TOA657 | `response-status-invalid` | warning | A key of an operation's `responses` is not an HTTP status: OpenAPI allows a code from 100 to 599, a range (`1XX` to `5XX`, in either case) and `default`. The response is not generated, so a key written by a tool or by hand can never reach a name or an expression of the client. A key that repeats another one in a different case (`2xx` and `2XX`) is reported the same way. | Rename or remove the key at the source. |
| TOA658 | `response-status-not-generated` | info | A response documents a 1xx or 3xx status. The client has no result for them (Dio follows redirects and the interim statuses are not responses), so the response is not generated; at run time the status is an undocumented one, or handled by the `default` response when the operation has one. | See the message of the diagnostic. |
| TOA659 | `encoding-key-unknown` | warning | An `encoding` key of a form or multipart body names no property of the body's schema (a misspelled name, a property the schema does not have): the entry is ignored. | Use the name of a property of the schema, or remove the entry. |
| TOA660 | `default-value-invalid` | warning | The `default` of a parameter does not match the parameter's `enum` or `format` (`default: other` for `enum: [a, b]`, a `format: date` default that is not a date): it is not documented as the default. | Use a default that fits the schema at the source. |
| TOA661 | `part-media-type-chosen` | info | The `contentType` of an `encoding` entry of a multipart part is a list (`image/png, image/jpeg`), a wildcard (`image/*`) or no media type: the part is sent with one concrete type, the file's own when it has one, else the first concrete type of the list, else `application/octet-stream` for a file and no media type for text. | Name one concrete media type in the encoding at the source. |
| TOA662 | `part-media-type-not-json` | warning | An object part of a multipart body has a `contentType` that is not JSON (`application/xml`). The client writes JSON only, so the part is a `String` the caller supplies, sent with that media type. | Write the value in that format yourself and pass the text, or describe the part as a string at the source. |
| TOA663 | `event-stream-method-added` | info | A success of an operation offers JSON (or another body) and `text/event-stream`: the operation gets a second method, named with `naming.stream_suffix`, that returns the events. | Set naming.stream_suffix in the config to name it otherwise. |
| TOA664 | `event-data-array-items` | info | The `schema` of an event stream is an array: each event's data is taken to be one item, as code-first frameworks write it. | Describe one event at the source (itemSchema in OpenAPI 3.2). |
| TOA665 | `event-stream-reconnect-off` | info | `sse.reconnect` in the config asks event streams to reconnect, but it applies to GET only: an event-stream operation that is not GET does not reconnect, since repeating the request may not be safe, unless its own `sse.reconnect` override enables it. Reported once per such operation, and only when the config asks. | Enable it for this operation if the request can be repeated. |
| TOA666 | `event-item-schema-unread` | warning | The `itemSchema` of an event stream does not say what the data of an event is (no `data` property, or one that is neither text nor JSON with a `contentSchema`): the data is read as text. | Give "data" contentMediaType: application/json and a contentSchema at the source. |
| TOA667 | `event-name-duplicate` | warning | Two branches of an `itemSchema` union fix the same event name: the later one is left out. | Give each event its own name at the source. |
| TOA668 | `event-name-unrepresentable` | info | An event name has no ASCII letter or digit (`""`, `*/`), so its variant is named by its place (`ChatEventEvent2`). | Name the event with letters at the source. |
| TOA669 | `sse-override-not-applied` | warning | A part of the `sse` override of an operation does not apply: `data` or `events` find no `text/event-stream` 2xx response written in the operation (a `$ref`'d one is shared), the operation has no event stream for `reconnect`, `method` or `unknown`, `unknown` has no events by name to apply to, or an event's data cannot be read. The message names the part; the rest of `sse` applies. | Rename the event, or remove it from "events". |
| TOA670 | `event-name-unreachable` | warning | An event name that no `event:` line can carry: an empty one (the wire reads it as `message`) or one with a line break. Its variant could never be selected, so it is left out. | See the message of the diagnostic. |
| TOA671 | `event-stream-error-as-text` | info | A `text/event-stream` response with an error status (or `default`) of an operation whose method does not return events: its body is read as text, like any other error body that is not JSON. | Use a JSON media type for errors at the source if the schema matters. |

## Fixes, overrides, baseline and generate (TOA8xx)

Applying fixes and overrides, baselines, and writing the output.

| Code | Slug | Default | Meaning | Fix |
| --- | --- | --- | --- | --- |
| TOA800 | `fix-not-applied` | warning | A normalizer fix or an override was not applied: its file cannot be read, its target is gone, the spec kept changing after the last pass, or the change would have no effect in the spec's dialect. | See the message of the diagnostic. |
| TOA801 | `overrides-not-found` | error (fixed) | The overrides file a client names does not exist. | Create it, or fix "overrides" of this client in the config. |
| TOA802 | `invalid-override` | error (fixed) | The overrides file cannot be read, or an override has a value of the wrong type; the value is ignored. | Point "overrides" of this client at the overrides file itself. |
| TOA803 | `unknown-override-key` | error (fixed) | An override has a key this tool does not know, such as a misspelled field; it is ignored. | Names the closest known key (`Did you mean "name"?`) when one is within edit distance 2, then lists the allowed keys. |
| TOA804 | `override-target-not-found` | warning | An override names an operation, a schema, a property, a parameter or a response the spec does not have; it is not applied. | Remove the override, or fix its address. |
| TOA805 | `override-target-ambiguous` | error | An override's address names more than one node: an `operationId` two operations share, or parameters of one operation with the same name in different places; it is not applied. A `schema` override of a response or body with several media types and no (or an unmatched) `contentType` is also TOA805. | For an `operationId` two operations share, address the operation as `METHOD /path`; for parameters with one name, write the key as `in:name`; for a response with several media types, add "contentType" to the override. |
| TOA806 | `override-conflict` | error | Two overrides change the same node; neither is applied. | Keep one of them. |
| TOA807 | `override-unchanged` | info | An override sets a value the spec already has; it can be removed. | Remove it. |
| TOA808 | `override-shared-target` | info | An override addressed through an operation changes a node other operations may share: a path-level parameter, a `$ref`'d component or a node in another file. | See the message of the diagnostic. |
| TOA809 | `override-nullability-dropped` | info | An override removes the `type` of a nullable 3.1 schema, so the schema is no longer nullable: nullability is the `null` in that `type`. | See the message of the diagnostic. |
| TOA820 | `baseline-not-found` | error (fixed) | The baseline file a client names does not exist. | Write it with `typed_openapi baseline create`, or fix "baseline" of this client in the config. |
| TOA821 | `invalid-baseline` | error (fixed) | The baseline file cannot be read, or an entry is malformed and is ignored. | Point "baseline" of this client at the baseline file itself. |
| TOA822 | `baseline-entry-stale` | warning | A baseline entry accepts more diagnostics than the check finds: the problem was fixed, and `baseline prune` can remove the entry. | See the message of the diagnostic. |
| TOA823 | `baseline-not-written` | error (fixed) | The baseline file cannot be written. | See the message of the diagnostic. |
| TOA830 | `output-not-owned` | error (fixed) | `generate` refuses a client's output directory, which it would replace: it holds a `pubspec.yaml`, is the `lib` directory of a package, holds a symbolic link or an input of the run, or holds a file it did not write or that changed since it wrote it (a file the manifest does not list or whose hash differs, or any file when there is no manifest); the message names the files, and `--force` replaces them, but never a package, a link or an input. Nothing is written for the client. | See the message of the diagnostic. |
| TOA831 | `output-not-written` | error (fixed) | `generate` cannot write a client's output directory, or another run holds its lock (`.<output>.typed_openapi.lock` next to the output; a lock of a process that is gone is taken over, and `--break-lock` takes over one whose owner cannot be told). | Check whether another generate runs on this output. |
| TOA832 | `output-recovered` | info (fixed) | An earlier `generate` was killed while it replaced the output directory and left the previous tree or a half-built one in sibling directories named `.<output>.typed_openapi-*`. The run put the previous output back, when the output was missing, and removed the leftovers. Also reported when a run takes over the lock of a process that is gone, or breaks a lock whose owner cannot be told with `--break-lock`. | See the message of the diagnostic. |
| TOA833 | `output-file-replaced` | info (fixed) | `generate --force` overwrote or deleted a file that it did not write or that changed since it wrote it; one report for each file. | See the message of the diagnostic. |

## Config (TOA9xx)

Reading `typed_openapi.yaml`.

| Code | Slug | Default | Meaning | Fix |
| --- | --- | --- | --- | --- |
| TOA901 | `config-not-found` | error (config) | The configuration file does not exist. | Create typed_openapi.yaml, or pass its path with --config. |
| TOA902 | `config-invalid` | error (config) | The configuration file is malformed or has an invalid value. | Pass the path of typed_openapi.yaml itself with --config. |
| TOA903 | `config-unknown-key` | warning (config) | The configuration file has a key this tool does not know. | Lists the allowed keys at that place (`Allowed keys here: ...`). |
| TOA904 | `output-overlap` | error (config) | Two clients write to the same or nested output directories. | Give each client its own output directory. |
## Where codes are reported

| Stage | Codes | Reported by |
| --- | --- | --- |
| Reading files | TOA001-TOA022 | `check`, `generate`, `baseline` |
| Normalizer rules | TOA106, TOA201-TOA208, TOA211, TOA301, TOA303, TOA401, TOA402, TOA501-TOA504, TOA601 | one of the 18 rules, see [Presets and rules](presets_and_rules.md) |
| Mapping to Dart | the other TOA2xx-TOA6xx | the IR builder while it names and types the client |
| Overrides | TOA560, TOA800-TOA809 | the overrides file, see [Overrides](overrides.md) |
| Baseline | TOA820-TOA823 | see [Baseline](baseline.md) |
| Generate | TOA830-TOA833 | see [Generated output](generate_output.md) |
| Config | TOA901-TOA904 | see [Configuration](configuration.md) |

## See also

- [CLI](cli.md): formats and exit codes.
- [Configuration](configuration.md): the `severity` key.
- [Baseline](baseline.md): accept diagnostics you cannot fix yet.
- [Presets and rules](presets_and_rules.md): the normalizer rules behind TOA2xx to TOA5xx.
