## 0.0.1 - Unreleased

### Output changes
- Generated files import `package:typed_openapi_client/typed_openapi_client.dart`
  in place of `package:typed_openapi_runtime/typed_openapi_runtime.dart`: the
  runtime package is renamed (M11b).
- Groups and the root client take a `ClientTransport` in place of a `Dio`
  and send through `ClientSender` in place of `DioRequestSender`; generated
  files no longer import `package:dio`. A Dio user writes
  `ApiClient(DioTransport(dio))` with `package:typed_openapi_dio`. Schemas
  named `Dio` keep their name; `ClientSender`, `ClientTransport`,
  `CancelSignal` and the other transport types of the client are taken
  (TOA550). TOA566 names the transport's base URL (M11b).
- Paths in reports, baseline entries and CI annotations use `/` as the
  separator on every OS, with a drive letter kept on an absolute Windows
  path, so a report and its fingerprints do not depend on the OS. Nothing
  changes on POSIX (M11).
- Every generated file has a third header line,
  `// ignore_for_file: deprecated_member_use_from_same_package`: a model
  whose spec deprecates a field, enum value or type uses it in its own code,
  and the analyzer of Dart 3.10 reports that under `--fatal-infos` (stable
  does not). Every file of every client changes, so the output hashes of
  unreleased 0.0.1 change; the code is otherwise as before (M11).
- A model with an optional constant (a `const` or one-value `enum` the
  schema does not require) remembers which of them the decoded JSON did
  not have, in a private `_absent` list, and `toJson` leaves those out, so
  a decoded value is written back as it came (Medusa's `union: structural`
  `oneOf` of search facets no longer decodes its own JSON as unknown). A
  model made in code still writes every constant. These models gain a
  private constructor `_`, and `==`/`hashCode` compare `_absent`, so a
  decoded model is not equal to a model made in code with the same getters
  when an optional constant was absent from the JSON. The generated
  `fromJson` calls `JsonReader.constant`, which now returns whether the
  constant was present, so generated code needs the matching
  `typed_openapi_runtime`: release the two packages together. No golden
  file changes; in the corpus the models with optional constants of
  `stripe`, `openai`, `github`, `discord` and `medusa` change (M11).
- In a union with a discriminator, a variant that is not an object and has
  the JSON type of an earlier variant (a string enum after a string) is
  reported as TOA458 (info): a value of that type is decoded as the earlier
  variant, since it has no property to read. The variants that pick a number
  are now matched `int` before `num` whatever their order, so an integer is
  no longer taken by an earlier `num` variant (M11).
- A union with a discriminator picks a variant whose JSON is not an object
  (an array, a string, a number, a boolean) by its JSON type before it
  reads the discriminator, so GitHub's `repos/get-content` decodes a
  directory listing; in the corpus the `github` client's
  `repos_get_content_response.dart` changes (M11).
- A discriminator variant that the `mapping` does not name and that fixes
  the discriminator property to one value is selected by that value, not
  by its component name (TOA457, info). OpenAI's unions now decode real
  payloads (`{"type": "function"}` is a `FunctionTool`); in the corpus the
  `openai` client's union files change (M11).

### Fixed
- The fix text of TOA504 no longer suggests a method-name override, which
  does not clear the error; it names the cure (a unique `operationId` at the
  source) and the way to generate anyway (lower TOA504 in `severity`).
- A framework hint after a multi-line fix (an override snippet) is on a line
  of its own instead of glued to the last line of the snippet.
- A `name` override of a schema that only a multipart body uses is reported
  (TOA807, info): the parts class is named after the operation.
- A union variant whose type is a nullable list (GitHub's
  `pull-request-stacks` 422 error, every branch nullable) binds its value
  in `toJson` before it encodes it, so the code compiles (M11).
- SARIF reports have what GitHub code scanning requires (M11): every rule a
  short and a full description and help, every result a partial
  fingerprint (`typedOpenapi/v1`) and a region (line 1 for a file without a
  position); `check --format sarif` locates a result without a file (a
  missing config) at the config file. `SarifReporter` takes `defaultFile`.

### Added
- Config `exhaustive` (M12, R14.2), in `defaults` or a client: with
  `false` the bases of enums, unions, status types and event unions are
  `abstract interface` in place of `sealed`, so a new value is not a
  breaking change for a `switch` with a default case. The default `true`
  changes nothing; an override `exhaustive` on a schema wins.
- `generate` keeps the API snapshot of every client it writes in
  `typed_openapi.lock` next to the config and prints, for each client, the
  count of its changes since the lock per category (breaking,
  switch-breaking, wire, additive, docs). `generate --locked` checks the
  lock instead of updating it and skips a client whose API differs
  (TOA834); a lock that cannot be read is TOA835 (M12).
- `typed_openapi diff [client...]` reports how the API of each client
  changed since `typed_openapi.lock`, or between two lock files (`--from`,
  `--to`), as `text`, `json` or `markdown`; `--fail-on breaking |
  switch-breaking | wire | any` sets the exit code. A schema renamed in the
  spec is removed plus added, with the `name:` override that keeps the old
  Dart name (M12).
- `typed_openapi.lock` keeps the names of models, enums, unions and
  methods (M12): `check`, `generate`, `diff`, `baseline` and `ir` name each
  as the lock has it, so a schema or an operation added to the spec never
  renames one that existed; the new one gets the suffix. TOA570 (info)
  names a kept name a run without the lock would not give, TOA569
  (warning) one an override or a custom type took, TOA571 (info) a type the
  spec no longer declares. `generate --fresh-names` names everything from
  the spec alone. `IrBuilder` takes the lock as `names:`; `SpecChecker`
  reads it next to the config, and `SpecChecker.freshNames` does not.
- `ApiLibrary` is exported: the files of a whole client from its IR, as
  `generate` writes them (M11). The programmatic guide now writes a whole
  client with it, and a test checks the files equal those of `generate`.
- Event streams (M10): an operation whose success is `text/event-stream` is
  generated. A stream method returns `Future<Result<Stream<SseItem<T>>, E>>`
  and uses `DioRequestSender.openEvents`; its `streamStatuses` are the 2xx
  statuses of the operation, a range written once. When a success offers a
  body and a stream, the operation gets two methods: the one that returns the
  body (JSON, text or bytes) sends the `Accept` of the media types its 2xx
  successes offer, and a second one named with `naming.stream_suffix`
  (`chatStream`, default `Stream`; a reserved word keeps its stem,
  `classStream`) returns the events. `OpenAPI 3.2` `itemSchema` and the
  code-first `schema` give the data type; an `itemSchema` whose `oneOf` or
  `anyOf` branches fix `event` to a constant is a sealed union
  `<Method>Event` with a class per event (`<Union><Event>`) and an unknown
  variant `<Union>Unknown`, and an event is dispatched by its exact name.
  A GET reconnects when the call asks (`CallOptions.sse`), or unless it
  says no when `sse.reconnect: true` is in the config; any other method
  reconnects only when the operation's `sse.reconnect` override enables it.
  The `sse` field of an operation override (`data`, `events`, `unknown`,
  `reconnect`, `method`) types the events, drops unknown ones, enables
  reconnection and chooses the methods; `SseOverride` and `SseMethod` are
  part of the public overrides API. Several event-stream successes that
  describe their events alike, whatever the annotations, the spelling of
  `nullable` or the `allOf` wrapper, are one stream.
- Operations (M9): an API class per group in `api/` (`PetsApi(Dio dio)`, a
  plain class that `implements` can mock), the barrel `api.dart` and the
  root client in `<client>.dart` (`PetstoreClient(Dio dio)` with a field per
  group, the servers as constants or methods of their variables), which
  exports the models and the API. Methods take named arguments, `body` and
  `CallOptions? call`, and return `Future<Result<T, E>>`: JSON, text and
  binary successes, sealed types for several successes or errors with
  different bodies, envelopes, typed errors, `UndocumentedStatus`; bodies
  are JSON, forms with their `encoding`, multipart parts with `FileUpload`
  files, binary `FileUpload`s and text. A multipart text part sent after a
  file or a typed part now has `Content-Type: text/plain; charset=utf-8`
  (before, such a part could be sent before the files, out of the schema's
  order). Every request carries its
  `OperationInfo` with tags and security metadata.
- Models (M8): `generate` writes the models of every client without check
  errors into its `output` directory: a file per model, enum and union in
  `models/` and the barrel `models.dart`. Every file starts with
  `// GENERATED CODE - DO NOT MODIFY BY HAND.` and has `// dart format off`
  on the second line, and the code is clean under `package:lints/recommended`
  and `flutter_lints` (the header's one `ignore_for_file` aside). Classes are `class` (not
  `final`, so they can be extended) and `@immutable`, with `fromJson`,
  `toJson`, deep `==`/`hashCode` and `toString`; a `const` property is a
  constant getter, `additionalProperties` a map field, constraints, defaults
  and descriptions doc comments, `deprecated` `@Deprecated`. Enums are open
  (`Status`, `StatusKnown`, `StatusUnknown`); request models take only known
  values. Unions are `sealed` and wrap their variants (`PetCat(Cat value)`),
  and pick one by the discriminator, by the JSON type, or, with
  `union: structural` (config key or schema or property override), by trying
  them. A union that cannot be told apart by JSON type (variants of one JSON
  type) keeps the raw JSON of those variants in one `JsonValue` variant
  (`PetJson`) or, when no variant has a type of its own, is `JsonValue`
  (TOA453). A variant that takes any JSON makes the union structural, still
  with TOA453.
- `generate` writes the output directory as a whole: it builds the tree and
  the manifest `.typed_openapi.json` (the generator, the manifest `format`
  2, a hash of the inputs and the hash of every file) in a temporary
  directory next to it and swaps it in, so a failed run keeps the previous
  output and a failed first run leaves nothing. A run that changes nothing
  does not touch the directory.
- `generate` replaces only what it wrote: a file that the previous manifest
  lists with a matching hash. A file of the user or of another client, or a
  generated file that was edited, is foreign or modified: the client is not
  generated and `TOA830` names the files. The new flag `generate --force`
  replaces them, says how many and names each file it overwrote or deleted
  (info `TOA833`); it never replaces a directory with a
  package, a symbolic link or a file any client reads (the config, a spec,
  its `$ref`'d files, overrides, baseline; also through links or another
  letter case). A manifest without the hash of a file (written before format
  2) counts the file as modified: pass `--force` once. Outputs that overlap
  are skipped (`TOA904`).
- `generate` holds a lock file `.<output>.typed_openapi.lock` next to the
  output while it works (created exclusively, with its pid and host): a
  second run on the same output gets `TOA831` and changes nothing, the lock
  of a process that is gone is taken over (`TOA832`), and the new flag
  `--break-lock` takes over a lock whose owner cannot be told (another host,
  unreadable, Windows) without replacing any file; `--force` never breaks a
  lock. A run killed while it swapped leaves `.<output>.typed_openapi-*`
  directories; the next run recovers under the lock (`TOA832`), after it has
  checked the output, and never touches a directory that holds an input of
  the run. A read-only output (mode 555) works, and a missing `chmod` is
  `TOA831`.
- A schema with a discriminator that other schemas extend with `allOf`
  (also from other files the spec reads) is a union of their models where it
  is used as a type. A wrapper writes back the discriminator value it was
  decoded with, so aliases survive a round trip, also across a nested
  hierarchy (`Pet` -> `Dog` -> `Lab` writes every level); wrappers are
  equal when that value, or the first mapping value for one made in code,
  is. `toString` prints `<redacted>` for a secret: a `writeOnly` or
  `format: password` property, also through a `$ref`, an annotation part,
  the one branch of a nullable `anyOf`/`oneOf` (Pydantic's
  `Optional[SecretStr]`), array items, map values and union variants. A
  value that stays raw JSON (a `JsonValue` field, list or map, a `...Json`
  variant, the `...Unknown` class of a union) is redacted too when a model
  or variant it may hold has a secret property, at any depth.
- A `oneOf` or `anyOf` without a discriminator drops an inline enum or
  `const` of a primitive type (string, integer, number, boolean) when
  another branch (inline or a `$ref`) is that type with no `format`,
  `pattern`, `enum`, `const` or keyword the rule does not model (`if`,
  `not`, `dependentSchemas`, ...), and length or range constraints that
  every enum value meets (`multipleOf` on exact decimal numbers), as in
  Stripe's `anyOf: [{type: string, maxLength: 5000}, {enum: ['']}]`
  (TOA455, info); a union left with one branch is that branch's type
  (`String`) and no longer `JsonValue` (TOA453). From OpenAPI 3.1 the
  keywords next to the `$ref` of a branch count as its own; 3.0 ignores
  them. An integer enum is also covered by a plain `number`. For `oneOf`
  the type accepts a value both branches take (`''` for
  `oneOf: [string, {const: ''}]`), which the spec's `oneOf` would reject:
  this is accepted on purpose, since the idiom means "any of these". The
  dropped values are listed in the doc comment of the field
  (`Known values: ...`), also through a wrapper of a `$ref`, and not for a
  union that stays `JsonValue`.
- M8 codes, with their default level: TOA452 discriminator-without-subtypes
  (info, renamed from inheritance-polymorphism-deferred: a discriminator on
  a schema nothing extends; it stays a model), TOA453 union-undiscriminated
  (warning), TOA454 union-variant-duplicate (info), TOA455
  union-branch-subsumed (info), TOA456 discriminator-value-duplicate
  (warning), TOA830 output-not-owned (error), TOA831 output-not-written
  (error), TOA832 output-recovered (info), TOA833 output-file-replaced (info).
  TOA830-TOA833 cannot be lowered.
- Semantic IR (M6): `check` builds each client's IR (`IrBuilder`,
  `ClientIr`) from the normalized spec and reports naming and mapping
  problems. Types follow R6.2 (`integer` -> `int`, `number` -> `num` or
  `double` with `float`/`double`, `date-time` -> `DateTime`, `date` ->
  `Date`, `byte` -> `Uint8List`, a schema without constraints -> `JsonValue`,
  `additionalProperties` -> `Map<String, T>`); custom types come from
  `types.formats`, `types.schemas` and the overrides' `dartType`. Fields
  follow the required x nullable matrix; optional nullable properties of
  PATCH bodies are `Patch<T>?` (`tri_state: patch|optional|extension`,
  `x-typed-tri-state`, override `triState`). A schema with `readOnly` or
  `writeOnly` properties used in requests and responses becomes `Pet` and
  `PetInput` (`naming.input_suffix`); a PATCH body schema that is also used
  elsewhere gets its own model `PetPatch` (`naming.patch_suffix`) with the
  tri-state fields. `allOf` parts merge into one model,
  one `$ref` stays a reference (also nullable, and also with parts that only
  annotate: `allOf: [{$ref: Pet}, {nullable: true, description: ...}]`; the
  annotations go to the field), `oneOf`/`anyOf` with one
  branch besides `null` is that branch, nullable; other `oneOf`/`anyOf` are
  unions with their discriminator mapping resolved. `{data: T}` envelopes of
  success responses are unwrapped. Documented errors give `Never`, one
  schema, or a schema per status (`errors.default_schema` for bodies the
  spec does not document).
- Names (R5): schemas keep their key in UpperCamelCase, inline schemas are
  named `<Parent><Property>` (inline enums with the same values share one),
  bodies `<Method>Request`, `<Method>Response` and `<Method>Error` (with the
  status only when several responses of that kind have a body),
  properties and methods are lowerCamelCase (`naming.operation_prefix`; the
  `nestjs` preset removes `XController_`; without `operationId`,
  `GET /users/{userId}/posts/{postId}` is `getUsersPostsByUserIdAndPostId`),
  operations are grouped by first
  tag into `{Tag}Api` (`naming.group`, `naming.default_group`, `group_by:
  tag|path|single`, override `group`; a spec without any tag gets one
  TOA554, otherwise each untagged operation does). Reserved and `dart:core` names get
  `Model` (types) or `_` (members), collisions `2`, `3`... with TOA550 /
  TOA551 and the override to pin the name; unrepresentable names are TOA552
  (an info for enum values: name them with `x-enum-varnames` in the spec).
  The value name `unknown` is reserved in enums (`unknown_`), as the emitters
  add an `unknown` member. The names of custom types (`types.formats`,
  `types.schemas`, `dartType`) are taken in the library's type scope, so a
  generated type of the same name gets a suffix (TOA551).
- In OpenAPI 3.1 and later the `description`, `default` and `deprecated`
  written beside a `$ref` win over the target's for that field; in 3.0 a
  `$ref` has no siblings and the target's are used.
- Header parameters named `Accept`, `Content-Type` and `Authorization` (any
  case) are not generated: OpenAPI says to ignore them.
- Filters (R4): `include` / `exclude` by `tags`, `operations` and path
  globs, override `exclude` on operations, schemas and properties; only
  schemas the selected operations reach are generated.
- New codes: TOA250 mixed-type-schema, TOA251 recursive-alias, TOA252
  allof-property-conflict, TOA253 allof-part-ignored, TOA254
  excluded-schema-referenced, TOA350 enum-mixed-values, TOA450
  discriminator-value-missing, TOA451 discriminator-mapping-not-variant,
  TOA550 name-reserved, TOA551 name-collision, TOA552 name-unrepresentable,
  TOA553 operation-multiple-tags, TOA554 operation-untagged, TOA555
  tags-merged, TOA556 path-variable-unbound, TOA557 filter-matches-nothing,
  TOA558 filter-conflict.
- More M6 codes, with their default level:
  - TOA255 oneof-constraints-ignored (info): `oneOf`/`anyOf` branches that
    only add constraints to an object with `properties` are ignored.
  - TOA256 composition-parts-ignored (warning): `allOf` parts or properties
    beside a union, or the union's branches beside a model, are ignored.
  - TOA351 enum-varnames-invalid (warning): `x-enum-varnames` or
    `x-enum-descriptions` is not a list of strings as long as the enum; it is
    ignored.
  - TOA452 discriminator-without-subtypes (info): a `discriminator` on a
    schema that is neither a union nor extended by other schemas is not
    used; the schema is a model.
  - TOA559 name-lossy (info): a schema, property, enum value, tag,
    `operationId` or parameter name lost letters outside ASCII.
  - TOA560 override-name-invalid (warning): an override `name` or `group` is
    not a valid Dart name; the name made from it is used, or the override is
    ignored when nothing is left.
  - TOA563 client-empty (warning): no operation of the client is generated
    (filtered out, written as `$ref`, or an unbound path variable).
  - TOA564 parameter-style-invalid (warning): a parameter `style` that its
    `in` does not allow (path: `simple`, `label`, `matrix`; query: `form`,
    `spaceDelimited`, `pipeDelimited`, `deepObject`; header: `simple`;
    cookie: `form`, `cookie`) falls back to the default style of the
    placement; also a form property's `encoding` style.
  - TOA565 querystring-not-generated (warning): an `in: querystring`
    parameter (OpenAPI 3.2) is not generated (TOA564 before M9).
  - TOA566 operation-servers-ignored (warning): a path item or operation has
    its own `servers`; requests go to the Dio base URL.
  - TOA567 callbacks-not-generated (info): `callbacks` of an operation and
    the document's `webhooks` are not generated.
  - TOA568 security-scheme-unknown (warning): a security requirement names
    a scheme `components.securitySchemes` does not have or defines without a
    usable type; its alternative is
    left out of the metadata when another one can be described, else the
    scheme has the kind `unknown`, so no operation reads as open. A
    requirement that is not an object (`security: ["bearer"]`, `[null]`) is
    the same, next to its TOA111.
  - TOA650 media-type-as-bytes (info): a body whose media type is not JSON, a
    form, `multipart/form-data`, `text/*` or `text/event-stream`, or a form
    or multipart response, is bytes and its schema is not used (TOA561
    before M9).
  - TOA651 media-types-dropped (info): the media types of a body, response
    or parameter that are dropped for the chosen one (variants of the chosen
    media type and other JSON types are not reported; TOA561 before M9).
  - TOA652 default-error-schema-missing (warning): `errors.default_schema` is
    not a key of `components.schemas`; the setting is ignored (TOA562 before
    M9).
  - TOA653 success-undocumented (warning): no 2xx response; any 2xx is a
    success with the body as `JsonValue`.
  - TOA654 event-stream-not-generated (warning): event streams that the
    client cannot express are not generated: some successes are only a
    stream and others offer a body (neither a method that returns the body
    nor one that returns the events covers them: the operation is left
    out), or the event-stream successes have different event types, or each
    stream also offers a body while another 2xx has a body without a stream
    (only the event-stream method is left out; the method that returns the
    body is generated, as before M10, and the message names the statuses).
    When `sse.data` or
    `sse.events` left a shared response alone, the message says so.
  - TOA655 multipart-not-object (warning): a multipart body that is not an
    object with properties has no class of parts.
  - TOA656 encoding-headers-ignored (info): the `headers` of the `encoding`
    of a multipart part or a form property are not sent.
  - TOA657 response-status-invalid (warning): a key of `responses` that is
    not an HTTP status (a code 100-599, a range `1XX`-`5XX` or `default`), or
    repeats another key in a different case; the response is not generated.
  - TOA658 response-status-not-generated (info): a documented 1xx or 3xx
    response is not generated; at run time the status is undocumented, or
    handled by the `default` response when the operation has one.
  - TOA659 encoding-key-unknown (warning): an `encoding` key of a form or
    multipart body names no property of its schema; the entry is ignored. A
    schema that lists no properties is free-form and is not checked.
  - TOA660 default-value-invalid (warning): a parameter's `default` does not
    fit its `enum` or `format` (`date`, `date-time`, `uuid`, `int32`); it is
    not documented as the default (a lower-case `t` or `z` of a `date-time`
    is valid, as RFC 3339 says).
  - TOA661 part-media-type-chosen (info): the `contentType` of the `encoding`
    of a multipart part is a list (`image/png, image/jpeg`), a wildcard
    (`image/*`) or no media type; the part is sent with one concrete type
    (the file's own when it has one, else the first concrete type, else
    `application/octet-stream` for a file and none for text).
  - TOA662 part-media-type-not-json (warning): an object part whose
    `contentType` is not JSON (`application/xml`) is a `String` the caller
    supplies, sent with that media type; it used to make every call throw.
  - TOA663 event-stream-method-added (info): an operation that offers a
    body and a stream gets a second method for the events.
  - TOA664 event-data-array-items (info): the `schema` of an event stream is
    an array; the data of each event is taken to be one item.
  - TOA665 event-stream-reconnect-off (info): `sse.reconnect` in the config
    applies to GET only, so another method does not reconnect unless its
    own override enables it.
  - TOA666 event-item-schema-unread (warning): an `itemSchema` does not say
    what the data is (a string, or JSON with a `contentSchema`), or a branch
    of a union fixes no event name; the data is read as text.
  - TOA667 event-name-duplicate (warning): two branches fix the same event
    name; the later one is left out.
  - TOA668 event-name-unrepresentable (info): an event name without an ASCII
    letter or digit; its class is named by its place.
  - TOA669 sse-override-not-applied (warning): a part of the `sse` override
    changes nothing (no stream written in the operation, a shared response,
    `unknown` without events by name, an event whose data cannot be read);
    the message names the part, and the rest of `sse` applies.
  - TOA670 event-name-unreachable (warning): an event name that no `event:`
    line can carry (empty, or with a line break); its variant is left out.
  - TOA671 event-stream-error-as-text (info): a `text/event-stream` response
    on an error status is read as text.
  - Renamed parts, group fields, server members, server variables and root
    client names (also one that gets the `Api` prefix because it starts with
    a digit) are reported (TOA550, TOA551, TOA552, TOA559); a method named `jsonEncode`,
    `base64Encode`, `int`, `bool`, `double` or `num` gets a suffix (TOA550).
- The IR names what the API emitter declares, after the models (which never
  move): the root client (`naming.client`, else the client name with
  `Client`), the sealed types of successes and errors with variants named by
  the HTTP reason phrase (`CreatePetErrorNotFound`, `…ClientError` for
  `4XX`, `…Other` for `default`, `…Status499`; the plural `GetPetErrors`
  when the operation's own inline body is `GetPetError`, any other name
  taken gets a suffix, TOA551), the classes of multipart parts
  (`UploadRequest`), the group fields and the servers of the root client;
  and it keeps security requirements with their schemes.
- Config: `naming.stream_suffix` (default `Stream`; letters and digits that
  start with an uppercase letter or a digit, else TOA902) and
  `sse.reconnect` (default false), in `defaults` or a client. Report
  messages and pointers print spec text with controls and bidirectional
  marks escaped, and generated code escapes U+200E, U+200F and U+061C.
- An `apiKey` security scheme without `in` is TOA112, as one without `name`.
- Schemas named `Dio` or like the runtime's new names (`FileUpload`,
  `FormBody`, `MultipartBody`, `SecurityScheme`, ...) get the `Model` suffix
  (TOA550); `Response`, `Options` and `Headers` keep their names, because the
  API files import only `Dio` from `package:dio`.
- An `allOf` parent that an override excludes is still merged into the flat
  child: the exclude only removes the parent's own declaration, and TOA254
  (info) says so.
- `naming.default_group` may not be a reserved word and `naming.input_suffix`
  and `naming.patch_suffix` must differ (TOA902).
  `naming.operation_prefix` is removed only from the start of an
  `operationId`, and not when its match is empty.
- Hidden `typed_openapi ir [client...]` prints the IR as JSON for debugging;
  its errors and warnings go to stderr as text, the infos are only counted,
  and its exit code is the one `check` gives. Its format may change in any
  release.
- `typed_openapi check`: reads every client from `typed_openapi.yaml`, loads
  its spec (JSON or YAML) with source positions, detects the OpenAPI version
  and reports diagnostics with stable codes and JSON pointers, as text or JSON.
- Programmatic API: `ConfigLoader`, `SpecLoader`, `OpenApiVersionDetector`,
  `SpecChecker`, `TextReporter`, `JsonReporter`, `TypedOpenApiCli`.
- `check` reads each spec into a typed model that is a superset of OpenAPI
  3.0, 3.1 and 3.2 (`SpecReader`, `SpecModel`) and reports unknown keys
  (TOA110), wrong value types (TOA111) and missing required fields (TOA112).
- `$ref` resolution inside a document and across local files, keyed by file
  URI and JSON pointer: invalid or truncated refs (TOA100), unresolved refs
  (TOA101), remote refs (TOA102), reference loops (TOA103), refs to the wrong
  kind of node (TOA104), ignored `$id`/`$self` (TOA105).
- The dialect is detected by content: 3.1 constructs in a 3.0 document
  (TOA020), `nullable` in 3.1+ (TOA021), 3.2 constructs in older documents
  (TOA022).
- Loading: YAML and JSON are read by `YamlComposer` from the events of a
  copy of package:yaml's parser, in one iterative pass. Nesting deeper than
  1000 levels, also once aliases are expanded, is TOA007; an alias bomb or
  very long keys (JSON pointers of all built nodes above
  `max(16000000, 20 * text length)` characters) are TOA008. A collection as a
  mapping key is TOA113 and is never built, so a key cannot hide an alias
  bomb; a null key is TOA114. Keys are their text (`200:` is `"200"`); keys
  that are one JSON key are TOA002, the last value wins. YAML tags outside
  the JSON Schema ruleset (`!!timestamp`, `!!binary`, `!custom`) are TOA009
  and the value is read as text; parser warnings are TOA015. The copied
  scanner is linear on long flow lines (dart-lang/tools#2657), so hostile
  one-line files are rejected in moments. A directory given as the spec or
  the config is reported as such; package:yaml is no longer a runtime
  dependency (it is used by tests only).
- `$ref` where OpenAPI does not accept a Reference Object (an operation,
  `description`) is TOA107 with a hint to bundle the spec (`redocly bundle`);
  `$ref: #/...` without quotes, which YAML reads as a comment, is TOA108; the
  YAML merge key `<<` is TOA109.
- Normalizer: `check` runs named rules over the model and applies the fixes
  that follow from the spec or the protocol, reading the spec again (at most
  3 passes; a fix that cannot be applied is TOA800). Fixes:
  `bool-required-to-array` (TOA201), `drop-invalid-default` (TOA211),
  `dedupe-enum-values` (TOA301), `declare-missing-path-params` (TOA501).
  Diagnostics: arrays without `items` in 3.0 (TOA202), double arrays (TOA203),
  `format` on an array (TOA204), binary objects (TOA205), `type: object`
  against non-object branches (TOA206), examples of the wrong type (TOA207),
  nullable enums through `oneOf` (TOA303), discriminator property not
  required (TOA401), unresolved discriminator mapping (TOA402), path
  parameters not in the template (TOA502), missing and duplicate
  `operationId` (TOA503, TOA504), `*/*` media types (TOA601), component keys
  with invalid characters (TOA106), and an example of another scalar type
  (TOA208, info). Presets add framework recipes to the hints;
  `rules: {<name>: false}` in `defaults` or a client turns a rule off. The
  rule names are `array-without-items`, `binary-object`,
  `bool-required-to-array`, `component-key-characters`,
  `contradictory-object-type`, `declare-missing-path-params`,
  `dedupe-enum-values`, `discriminator-mapping-target`,
  `discriminator-property-required`, `double-array`,
  `drop-invalid-default`, `duplicate-operation-id`,
  `example-type-mismatch`, `format-on-array`, `missing-operation-id`,
  `nullable-enum-one-of`, `path-param-not-in-template` and
  `wildcard-media-type`. An unknown name is TOA903 (the message lists the
  known ones); a `rules` value that is not a map, or a rule set to anything
  but `true` or `false`, is TOA902.
- Programmatic API: `Normalizer`, `NormalizedSpec`, `NormalizerRule`,
  `RuleContext`, `Finding`, `SpecEdit`, `EditOperation`, `SpecDocuments`.
- A region of a spec that several `$ref`s, enclosing nodes or clients reach is
  read once, and an identical diagnostic is reported once.
- Overrides: `clients.<name>.overrides` names a JSON or YAML file that
  addresses operations (`operationId` or `METHOD /path`), their parameters
  (`name` or `in:name`), request body and responses, and schemas of
  `components.schemas` with their properties. Spec fields (`type`,
  `format`, `nullable`, `required`, `items`, `additionalProperties`, `enum`,
  `discriminator`, `$ref`, parameter `required`/`schema`, body and response
  `contentType`/`schema`) replace the spec's values before the normalizer
  runs (`null` removes a field; `nullable` follows the document's dialect:
  from 3.1 a schema whose `anyOf` or `oneOf` has a null branch and one or
  more other branches, with or without siblings, is nullable, and
  `nullable: false` removes the null branch (one branch left is unwrapped)
  and keeps the siblings; a `nullable` override
  without `$ref` keeps the other keys of a `$ref` node; `type: null` on a
  nullable 3.1 schema drops its nullability, TOA809 info; in OpenAPI 3.0 a
  field other than `nullable` (and a property's `required`) that would sit
  beside a `$ref` is not written, TOA800: override the referenced schema by
  name). Generation fields (`name`, `exclude`, `group`, `exhaustive`,
  `dartType`, `triState`) are checked and kept for the generator. Every
  entry may have a `reason`, printed in diagnostics about it. An empty file
  is no overrides. A missing overrides file is TOA801, a directory or an
  invalid value TOA802, an unknown key the error TOA803 (with "did you
  mean" for a close known key), an override whose target is gone TOA804
  (warning), an ambiguous address TOA805, two overrides of one node TOA806,
  an override the spec already matches TOA807 (info, "can be removed"), and
  a change through an operation of a node other operations share TOA808
  (info). An overrides file that cannot be used is an error and the spec is
  checked without it.
- The fixes of `double-array`, `format-on-array`, `binary-object`,
  `contradictory-object-type` and `nullable-enum-one-of` end with the
  override to copy into the overrides file, when the schema is in
  `components.schemas` or is one of its properties (`format-on-array` only
  for a format whose element type is known; none for a schema with `$ref` in
  OpenAPI 3.0 or a value YAML cannot carry).
- Programmatic API: `OverrideLoader`, `OverrideSet`, `OverrideEntry`,
  `OperationOverride`, `ParameterOverride`, `BodyOverride`,
  `ResponseOverride`, `SchemaOverride`, `PropertyOverride`,
  `DartTypeOverride`; `Normalizer.normalize` takes `overrides:` and
  `NormalizedSpec.overrides` is the set, or null without an overrides file.
- Paths in reports are relative to the working directory, in every format
  and for every file (the config, specs, files reached through `$ref`,
  overrides and baseline files); a file outside it is named by its absolute
  path (`DisplayPaths`). `TypedOpenApiCli(workingDirectory:)` sets the
  directory for tests and tools.
- Levels in the config: `severity: {<code or name>: error|warning|info|off}`
  in `defaults` and per client (a client overrides `defaults` code by code)
  changes the report and the exit code. An unknown code is TOA903; a bad
  level and a code named twice are TOA902. The config codes (TOA901-TOA904)
  cannot be changed at all. The codes of `DiagnosticCode.fixedCodes` (a spec,
  overrides or baseline file cannot be read: TOA001, TOA003, TOA004,
  TOA006-TOA008, TOA010, TOA011, TOA801-TOA803, TOA820, TOA821, TOA823) can
  be raised but not lowered or turned off, which is TOA902. Any other code
  may be raised, lowered or turned off.
- Baseline (R2.3): `clients.<name>.baseline` names a YAML file written by
  `typed_openapi baseline create [client...]` from the client's errors and
  warnings (infos are always shown); `check` then hides the diagnostics it
  accepts and counts them (`baselined: N`), lists them marked
  with `--show-baselined`, and reports an entry that matches nothing (or
  fewer diagnostics than its `count`) as TOA822 (warning, an error with
  `--strict-baseline`) with a hint to run `typed_openapi baseline prune`;
  `--strict-baseline` applies after the configured levels, so TOA822 is an
  error even if the config lowered it.
  Entries are keyed by a fingerprint: the first 12 hex digits of SHA-256 of
  `[code, anchor, args]`, where the anchor is the logical address of the
  place (operation `METHOD /path`, `in:name` parameter, components schema,
  property) or the file (relative to the baseline file) and JSON pointer;
  message text and positions are not part of it. A missing baseline file
  is TOA820, an unreadable one or a bad entry TOA821, a file that cannot be
  written TOA823; two clients naming one baseline file is TOA902. The
  file starts with `version: 1` (it must be the integer 1) and its entries
  are sorted. `baseline create` and `baseline prune` write it atomically
  (a temporary file, then a rename), and skip a client whose spec, or a
  file it is read with (a `$ref` to a file that does not exist is TOA004),
  cannot be read: its baseline is left as it is, the error is printed and
  the exit code is `1`. `baseline prune` also keeps a baseline that has an
  entry it rejected (TOA821), and neither command writes a baseline file
  that two clients share. `check` reports no stale entries for a client
  whose spec cannot be read either.
- Report formats `sarif` (SARIF 2.1.0: rules, levels, relative URIs,
  logical locations, `relatedLocations`, baselined results as suppressed)
  and `github-actions` (workflow-command annotations).
- A problem an override introduces has a related location: the override
  field (text `related:`, JSON `related`, SARIF `relatedLocations`).
- Preset hints are kept apart (`Diagnostic.hints`): a finding two clients
  share keeps the hints of both presets instead of the first one's; with
  more than one, each starts with its preset's name (`nestjs: ...`).
- `Diagnostic.args` (part of the fingerprint): the field name of TOA112.
