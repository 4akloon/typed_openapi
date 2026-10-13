# 07 — Dart-side building blocks: json_serializable, build_runner, Dio, language, toolchain

Research date: 2026-10-11. Goal: collect facts about the capabilities and limits of the Dart tools the generator will rest on (dio + json_serializable), and give recommendations on open decisions 1–7 from `../requirements.md`.

## 0. Versions used (pub.dev API, 2026-10-11)

| Package / SDK | Latest stable | Date | Note |
|---|---|---|---|
| Dart SDK | **3.13.5** (beta 3.14.0-211.1) | 2026-09-29 | 3.13 = primary constructors |
| json_serializable | **6.14.1** | 2026-07-30 | 6.14.0 (2026-05-15) added tri-state |
| json_annotation | **4.12.0** | 2026-05-15 | json_serializable hard-pins `>=4.12.0 <4.13.0` |
| build_runner | **2.16.2** | 2026-10-07 | requires Dart ^3.11, analyzer ≥14.3 |
| dio | **5.11.1** | 2026-09-04 | |
| dio_web_adapter | **2.2.2** | 2026-09-04 | |
| dart_style | **3.1.13** | 2026-08-26 | SDK 3.13.1 bundles **3.1.10** |
| code_builder | **4.12.0** | 2026-08-28 | switch expressions, patterns added |
| analyzer | **14.5.0** | 2026-10-06 | 5 major releases in H1 2026 |
| retrofit / retrofit_generator | 4.10.0 / 10.2.11 | 2026-08 / 2026-09 | |
| freezed | 4.0.2 | 2026-09-18 | requires Dart ≥3.13 |
| dart_mappable | 4.10.0 | 2026-09-07 | |
| http / fetch_client / dio_compatibility_layer | 1.6.0 / 1.2.1 / 0.1.1 | | |

All experiments are in `<scratchpad>/agent-dart/exp/` (hereinafter `exp/`), Dart 3.13.1, macOS arm64 (Apple M5). The list of files is at the end of the document.

---

## A. json_serializable and build_runner

### A.1. `checked: true` and `CheckedFromJsonException` (→ R6.5)

**How it works.** In checked mode each field is decoded through `$checkedConvert(map, key, castFunc)`, and the whole object is wrapped in `$checkedCreate(className, ...)`. Any exception is turned into `CheckedFromJsonException` with fields `className`, `key`, `map`, `innerError`, `message`, `badKey` (`~/.pub-cache/hosted/pub.dev/json_annotation-4.12.0/lib/src/checked_helpers.dart`).

**Limitations verified by experiment** (`exp/bin/main.dart`):

```
[nested list item wrong type]  Could not create `Item`. There is a problem with "price".
                               type 'String' is not a subtype of type 'num' in type cast
[nested missing required]      Could not create `Item`. There is a problem with "name".
                               type 'Null' is not a subtype of type 'String' in type cast
[unchecked missing]            _TypeError: type 'Null' is not a subtype of type 'String' in type cast
```

1. **There is no path in JSON.** Only the deepest class and key are available. `$checkedConvert` has a branch `on CheckedFromJsonException { rethrow; }`, so the outer context (`Page → items[1]`) is lost. So `/items/1/price` cannot be obtained.
2. **A missing required field looks like a type error** (`'Null' is not a subtype of 'String'`). To get `MissingRequiredKeysException` ("Required keys are missing: name."), `@JsonKey(required: true)` is needed (`allowed_keys_helpers.dart`).
3. **Without `checked` there is no context at all**: a bare `TypeError`, without the field or class name.
4. **Performance cost.** Microbenchmark in AOT (`exp/bin/bench.dart`, 2000 × page with 1000 items):

| Variant | Time |
|---|---|
| json_serializable, unchecked | ~35 ms |
| json_serializable, `checked: true` | **~910 ms (≈25× slower)** |
| Decoder prototype with paths (`exp/lib/rt.dart`) | ~80 ms (≈2.2×) |

The prototype gives exactly what R6.5 requires:
```
JsonDecodeException(Item at "/items/1/name"): missing required property "name"
JsonDecodeException(integer at "/items/1/price"): expected integer, got String
```
This is a microbenchmark on one machine, but the order of magnitude is indicative.

**`disallowUnrecognizedKeys`** throws `UnrecognizedKeysException`. For R6.5 ("extra fields are ignored") the default value `false` is required, and it already works (verified: `{"id":"x","zzz":1}` decodes).

### A.2. `includeIfNull`, `includeToJson/FromJson` and the new tri-state (→ R6.1, R7)

- `includeIfNull: false` (on a class or `@JsonKey`) generates `'k': ?instance.k`. This is a null-aware element, that is, the generated code requires language **≥3.8** (json_serializable ≥6.10, CHANGELOG). This closes R7.3: an optional field with a null value does not get into the JSON.
- `includeToJson: false` / `includeFromJson: false` exclude the field in one direction. Suitable for `readOnly` / `writeOnly`.
- **New in 6.14.0 (2026-05-15, PR google/json_serializable.dart#1574):** `@JsonKey(explicitJsonNullWhenNonNullField: true)`. The field must be nullable. A Dart `null` means the key is absent. If the value is non-null but serializes to JSON `null`, the output gets `"k": null`. `fromJson` distinguishes the states through `containsKey`. The official pattern from the tests (`json_serializable-6.14.1/test/src/patch_tri_state_test_input.dart`) is `sealed class PatchValue<T>` with `fromJson(Object?, fromJsonT)` / `toJson(toJsonT)`.

Verified (`exp/lib/models.dart`, class `UpdatePet`):
```
absent: {}
null:   {"name":null}
value:  {"name":"Rex","owner":{"id":"o1"}}
decode {"name":null,"tag":"t"} → name=PatchNull<String>, tag=PatchValue<String>, owner=null
```
**Conclusion: R7 on json_serializable ≥6.14 is implementable.** The R6.1 matrix is also expressible: `required: true` for "the key is mandatory", `disallowNullValue` for "null is forbidden", `includeIfNull` and `explicitJsonNullWhenNonNullField`.

### A.3. Enum: `unknownEnumValue`, `nullForUndefinedEnumValue`, `@JsonEnum(valueField:)` (→ R8)

`$enumDecode(map, source, unknownValue:)` returns `unknownValue`, and **drops** the source value (`enum_helpers.dart`). `JsonKey.nullForUndefinedEnumValue` returns `null` and also drops the value. Experiment:
```
WithEnum.fromJson({"status":"archived","maybe":"weird"})
→ status=Status.$unknown  maybe=null
→ toJson = {"status":"$unknown","maybe":null}
```
- **R8.1 violated**: the raw `"archived"` is lost.
- **R8.2 violated**: the placeholder value `$unknown` gets into `_$StatusEnumMap` and **is sent to the server as the string `"$unknown"`**. json_serializable cannot exclude it from the map.
- `@JsonEnum(valueField: 'value')` allows serializing an enhanced enum by a field, but does not solve the unknown problem.

**Workaround (verified, `exp/lib/open_enum.dart`, `exp/lib/mood_model.dart`).** json_serializable uses any type that has `factory X.fromJson(...)` and `toJson()`. `Mood.fromJson(v)` was generated for fields of `Mood`, `List<Mood>?` and `Mood?`. Therefore an open enum written as a hand-made sealed type (see E.3) works as a field of a `@JsonSerializable` class.

### A.4. `genericArgumentFactories` (→ R6.4)

Works as expected. `Envelope<T>.fromJson(json, T Function(Object?) fromJsonT)` and `toJson(Object? Function(T) toJsonT)`, verified on `Envelope<Owner>`. A known limitation: json_serializable does not see generics in `@JsonKey(fromJson:)` / `JsonConverter` (issue #1508, open).

### A.5. `JsonConverter`, `createFieldMap`, `createPerFieldToJson`, `createJsonKeys`

- `JsonConverter<T, S>` on a field, a class, or in `JsonSerializable(converters: [...])` suits R6.2 (`Decimal`, a custom `Date`, `int64` as `BigInt`/`Int64` on web, where `int` > 2^53 loses precision).
- `createFieldMap` / `createJsonKeys` give constants "Dart name → JSON key". `createPerFieldToJson` generates `_$XPerFieldToJson.<field>(value)`, which is convenient for serializing individual fields into query/form. They do not cover the requirements, they only help.
- `createJsonSchema` (6.12) generates a JSON Schema from a class. Not relevant for us.

### A.6. Sealed classes, union, `additionalProperties`

- **There is no native support for sealed / union.** Issue google/json_serializable.dart#1342 "Support dart3 sealed class" has been open since 2023-08. Maintainer: "I'll take a PR". PR #1483 (2025-03) **has not been merged** as of 2026-10.
- **Workaround verified** (`exp/lib/models.dart`: `Animal`, `Cat`, `Dog`, `UnknownAnimal`, `Zoo`). `sealed class Animal` with a hand-written `factory Animal.fromJson` (switch on the discriminator) and an abstract `toJson()`. Variants are `@JsonSerializable final class Cat extends Animal`. Fields `List<Animal>` and `Animal?` in another `@JsonSerializable` class are generated correctly, an unknown variant keeps the raw JSON, and the exhaustive switch works.
- **`additionalProperties` together with known fields** (capturing the "rest" of the keys) is not expressible natively. It is possible only with a hack: `readValue` + a hand-written `toJson`.

### A.7. What json_serializable **cannot express** from the requirements and how to work around it

| Requirement | json_serializable | Workaround |
|---|---|---|
| R6.5 path in JSON | only class + key, checked ≈25× slower | own decoders with paths (runtime helpers, ~150 LOC) |
| R8.1 raw enum value | lost | sealed open-enum with `fromJson`/`toJson`, written by the generator |
| R8.2 do not send unknown | `$unknown` is sent | constructor typing, see E.3 |
| R9 union with unknown | none (#1342) | sealed hierarchy with hand-written `fromJson` |
| R9.3 `string \| number` | none | sealed wrapper or extension type |
| `additionalProperties` + fields | `readValue` hack | hand-written code |
| R13.1 / R15.4 determinism | the output depends on the json_serializable version on the user's side (6.9 changed the `toJson` style, 6.10 started using null-aware elements, which require Dart 3.8) | generate the code ourselves or pin the version |

What json_serializable **covers**: simple object models, R6.1, R6.4, R7 (from 6.14), ignoring extra fields, converters.

### A.8. build_runner: state as of October 2026

**Performance has noticeably improved** (`build_runner-2.16.2/CHANGELOG.md`):
- 2.5: first round of optimization for large builds.
- 2.10: AOT compilation of builders (initially behind a flag).
- 2.13: speedup from 1.4× to 4× (dart-lang/build PR #4405).
- 2.14: another 2× for incremental builds, AOT by default, `stop` command, locking.
- 2.15: less memory, `--low-resources-mode` removed.
- 2.16: new behaviour "always fix changed generated files" and the **`--only-check`** mode for CI.

**Measurement** (`exp/lib/gen/`, 600 `@JsonSerializable(checked: true)` classes × 8 fields, 22.6 thousand lines of `.g.dart`):

| Scenario | Time |
|---|---|
| Cold start: AOT compilation of builders | **12 s** |
| Generation of 600 models | 1–2 s |
| Incremental build after changing one file | 0.8 s |

**What remains a problem:**
1. A separate step in the pipeline. On a clean CI each run pays ~12 s for compiling the builders.
2. **Lock-step dependencies on `analyzer`.** analyzer released 10.0 → 14.0 over January–June 2026. Current constraints: json_serializable 6.14.1 `>=10 <15`, retrofit_generator `>=13.3 <15`, freezed 4.0.2 `>=14 <15` (and Dart ≥3.13), build_runner 2.16.2 `>=14.3 <15` (and Dart ≥3.11). Any generator that lags behind blocks the user's upgrades.
3. The output depends on the generator version on the user's machine (see A.7).

**Macros and augmentations:**
- Macros were **cancelled** on 2025-01-29 ("we’ve made the difficult decision to stop our work on macros"). In the same post: "We also plan to ship augmentations", "We’ve already identified improvements for build_runner".
- Flutter & Dart 2026 roadmap (2026-02-24): "we plan to ship Primary Constructors … and Augmentations to simplify code generation", "We will continue to focus on improving build_runner".
- Fact as of 2026-10-11: primary constructors **shipped** in Dart 3.13 (2026-08-12). Augmentations **have not shipped**: the specification is in `dart-lang/language/working/augmentations/` (not in `accepted/`), "Experiment flag: augmentations", last edit 2026-10-06. The SDK CHANGELOG says nothing about them.
- Even when augmentations ship, they will only remove the `part` / `_$` boilerplate. build_runner will still have to be run. **There is no alternative official codegen mechanism, and none is expected in the near future.**

**Consequence for decision 1.** If the generator emits annotated code, the user **has to** run build_runner, because the `.g.dart` from json_serializable otherwise will not appear. The alternative is for the generator itself to emit equivalent code. Then the user keeps only the runtime dependencies (`dio`, `meta`, our runtime package).

---

## B. Dio 5.11.x

### B.1. Per-call parameters (→ R10.5)

- `Options.extra` / `RequestOptions.extra` (`Map<String, dynamic>`) are merged with `BaseOptions.extra` in `Options.compose` (`dio-5.11.1/lib/src/options.dart:339`). A typed object, e.g. `OperationInfo`, can be put there without serialization. Verified: an interceptor sees `extra['operationId']` (`exp/bin/dio_flow.dart`).
- `CancelToken`, `onSendProgress`, `onReceiveProgress` — parameters of `dio.request(...)`.
- **R10.1 trap.** `dio.fetch(RequestOptions(...))` with a "bare" `RequestOptions` is **not** merged with `BaseOptions` (baseUrl, headers, timeouts). Merging is done only by `dio.request()`, through `Options.compose(dio.options, …)` (`dio_mixin.dart`, around line 396). retrofit also explicitly calls `.compose(_dio.options, …)`. **The generated code must call `_dio.request<…>(path, options: Options(...))`.**
- **`fetch<T>` trap.** If `T != dynamic` and the response type is not `bytes`/`stream`, Dio forcibly sets `responseType = json` (or `plain` if `T == String`) (`dio_mixin.dart:418-427`). For text, `request<String>` is needed; for binary, `request<List<int>>` + `bytes`; for a stream, `request<ResponseBody>` + `stream`; for JSON, `request<Object?>`.
- **Tolerance to defects (R0.2).** `FusedTransformer` parses JSON only when the content-type equals `application/json`, `text/json` or `*+json`. Otherwise `data` is a `String` (`transformers/fused_transformer.dart`). Generated code must call `jsonDecode` when it expects JSON but receives a string.

### B.2. `validateStatus` and the error flow (→ R10.2)

`_defaultValidateStatus` passes statuses 200–299. Otherwise `DioException.badResponse` is thrown, and it **passes through the interceptors' `onError`**. The body is already parsed, because `receiveDataWhenStatusError` is true by default. Verified:
```
onError type=DioExceptionType.badResponse status=404 dataType=_Map<String, dynamic> data={code: NOT_FOUND, …}
```
The tonik approach `validateStatus: (_) => true` disables `onError` for HTTP errors, so R10.2 is violated. The recommended flow:
1. keep the user's `validateStatus`;
2. catch `DioException`;
3. if `type == badResponse`, decode `e.response!.data` according to the documented status.

Important: an interceptor may `resolve(...)` an error into a `Response` with a non-2xx status, for example return a cache on 503. Therefore the generated method must always parse `statusCode` through a switch and not assume 2xx.

### B.3. `DioExceptionType` (→ R11.7)

`dio_exception.dart:15` in 5.11.1 contains **9** values, not 8: `connectionTimeout`, `sendTimeout`, `receiveTimeout`, `badCertificate`, `badResponse`, `cancel`, `connectionError`, `unknown`, **`transformTimeout`** (added in 5.10.0). Mapping for R11.7:
- `badResponse` → HTTP error (documented or not);
- `cancel` → a separate "cancelled" variant (this is not a failure);
- the rest → transport failure.

Verified: a refused connection gives `connectionError`, cancellation gives `cancel`.

### B.4. `ListFormat` and OAS styles (→ R10.3)

Verified against the actual URL (`exp/bin/dio_flow.dart`):
```
multi=a&multi=b&csv=a,b+c&pipes=a%7Cb&ssv=a%20b&deep%5Bcolor%5D=red&deep%5Bsize%5D%5Bw%5D=1&reserved=a%2Fb%3Fc%26d
```

| OAS style / explode | Dio | Note |
|---|---|---|
| form, explode=true, array | `ListFormat.multi` (default) | ✓ |
| form, explode=false, array | `ListParam(v, ListFormat.csv)` | ✓ |
| spaceDelimited | `ssv` → `%20` | ✓ |
| pipeDelimited | `pipes` → `%7C` | ✓ (`\|` encoded) |
| deepObject | nested `Map` in `queryParameters` → `k%5Bp%5D=v` | ✓ semantically; brackets percent-encoded |
| form, explode=true, **object** | ✗ | the generator flattens into top-level keys |
| form, explode=false, object (`k,v,k2,v2`) | ✗ | the generator builds the string |
| `allowReserved: true` | ✗ | Dio always encodes |
| path: simple / label / matrix | ✗ | Dio has no path templates, the generator encodes itself (`Uri.encodeComponent`) |
| header simple, cookie | ✗ | generator; cookie via the `Cookie` header (account for a conflict with `dio_cookie_manager`) |

Oddity: `ListFormat.tsv` uses the separator `r'\t'`, that is, two characters `\` and `t` (`utils.dart:136`). OAS 3 has no tsv, so this does not matter.

### B.5. Multipart (→ R10.4)

- `MultipartFile.fromBytes / fromString / fromStream(…, filename:, contentType: DioMediaType(...), headers:)` sets the content-type of each part. `FormData.fields` (`MapEntry<String,String>`) have no content-type. The JSON part must be passed as `MultipartFile.fromString(jsonEncode(x), contentType: DioMediaType('application','json'))`.
- `MultipartFile.fromFile` works only with `dart:io`. For pure Dart and web the generated API must accept bytes or a stream.
- `MultipartFile` is single-use. For retries in interceptors `FormData.clone()` is needed (5.10 fixed the loss of `boundaryName`).

### B.6. Streaming and SSE (→ R12, web)

- **VM / mobile.** `ResponseType.stream` → `ResponseBody.stream`, chunks arrive as they come in (verified on a local server). In 5.11.1 backpressure was fixed; earlier, long streams could lead to OOM.
- **Web, the standard `BrowserHttpClientAdapter`, has no streaming.** XHR with `responseType = 'arraybuffer'`, and `ResponseBody.fromBytes` is created only in `xhr.onLoad` (`dio_web_adapter-2.2.2/lib/src/adapter_impl.dart:54,119`). SSE will arrive in one chunk after the connection closes. Issues cfug/dio#1859 "ServerSendEvent support for Flutter Web" and #1740 "Use modern Fetch API with Dio on Web" have been **open** since 2023.
- **How to work around it without giving up Dio.** `dio_compatibility_layer` (`ConversionLayerAdapter(http.Client)`) + `package:http` ≥1.3, where `BrowserClient` moved to the Fetch API and streams the response through `ReadableStream`. `fetch_client` also fits. Limitations of the adapter (code reviewed): the `cancelFuture` parameter is **ignored**, that is, fetch is not cancelled, Dio only discards the result. There is no upload progress. On the web the request body is buffered.
- The browser's `EventSource` is not suitable: GET only and without custom headers (R12.1 POST, R12.4 interceptors with auth).
- **SSE parser.** On pub there are only small packages with no user base (`sse_parser` 0.1.0). Better: ~150 LOC of our own WHATWG parser in the runtime package.

### B.7. How retrofit_generator solves these tasks and where it is limited

Overview of the annotations (`retrofit-4.10.0/lib/{http,dio,call_adapter,error_logger}.dart`) and of the generator (`retrofit_generator-10.2.11/lib/src/generator.dart`):

| Topic | retrofit | Limitations against our requirements |
|---|---|---|
| Per-call extras | `@Extra({...})` statically, `@Extras()` as a parameter, `@TypedExtras` | does not set operationId automatically |
| Options | `@DioOptions() Options` | |
| Cancel / progress | `@CancelRequest`, `@SendProgress`, `@ReceiveProgress` | ✓ |
| Multipart | `@Part(contentType:)` statically, `@PartMap` at runtime | ✓ |
| Query | `@Query`, `@Queries` (Map; Dio gives `a[b]=c`) | does not distinguish OAS styles |
| Errors | `DioException` passes through as is; `ParseErrorLogger` for decoding errors; `CallAdapter` for `Result` | **there are no typed error bodies**: issue #168 "Add error handler" has been open since 2020 |
| Several 2xx | one `T` + `HttpResponse<T>` | no variants by status |
| Streams | only `Stream<Uint8List>` / `Stream<String>` with `ResponseType.stream` | **no SSE**: #525 closed as not planned |
| Request | `Options(...).compose(_dio.options, …)` → `_dio.fetch` | |
| Codegen | build_runner + code_builder, internally mixed with raw `Code('…')` | |

---

## C. Dart language capabilities for the generated API

### C.1. Sealed + exhaustive switch (R9, R11)

Works as it should: a missing variant gives the compile error `non_exhaustive_switch_expression` (`exp/bin/exhaust.dart`). There is a contradiction with R14.2: **adding a new variant or value breaks the exhaustive switch in the consumer's source code** (Dart has no analogue of Swift's `@unknown default`). Compiled code (an old client against a new server) does not break, because `Unknown` arrives. The R14.1 report must mark such changes as "source-breaking for exhaustive switch".

### C.2. Extension types for open enum (`extension type const Status._(String value)`)

Verified (`exp/lib/models.dart` `Color`, `exp/bin/exhaust.dart`):
- **Exhaustiveness is lost**: a `switch` over `Color` with all constants gives `non_exhaustive_switch_expression … doesn't match 'String()'`, so `_` is required.
- **There are no runtime checks**: `("x" as Object) is Color` equals `true`, and `'hacked' as Color` passes and is sent as `{"color":"hacked"}`. **R8.2 cannot be blocked.**
- Without `implements Object` the type is considered potentially nullable: `Object o = p.color` does not compile.
- Pros: zero allocations, `jsonEncode` works directly (the representation is `String`), json_serializable picks up `fromJson`/`toJson`.
- dart.dev explicitly calls them "an _unsafe_ abstraction" (https://dart.dev/language/extension-types).

**Verdict:** not suitable for R8.1/R8.2. Suitable for R6.2 `JsonValue` and for cheap id wrappers.

### C.3. Recommended form of open enum: sealed + enum + unknown

Verified (`exp/lib/open_enum.dart`, `open_enum2.dart`, `shapes.dart`, `exhaust2.dart`):
- `enum XKnown implements X` inside `sealed class X` together with `final class XUnknown` gives **full exhaustiveness**: a missing known value is a compile error.
- Static aliases `static const shipped = XKnown.shipped;` on the sealed class **keep exhaustiveness**, allow writing `X.shipped` and the dot shorthand `.shipped` in the context of `X` (Dart 3.10).
- A parameter of type `XKnown` + a field of type `X` (`Pet({required PetStatusKnown this.status})`) gives **R8.2 at compile time**: `Pet(status: decoded.status)` does not compile, `argument_type_not_assignable`. The decoded object holds `XUnknown` (R8.1).

### C.4. Records, class modifiers, `meta`

- **Records** suit internal helpers. They are not suitable for the public API: adding a field changes the type (breaking). Several 2xx responses are better expressed with a sealed class.
- **`abstract interface class`** with `factory PetsApi(Dio) = _PetsApiImpl` is mocked by mocktail without code generation (`exp/test/mock_test.dart` passed). mockito for null-safe mocks requires build_runner, so for R10.7 document mocktail or fakes.
- **`final class`** for models: users cannot extend or implement a model, so adding fields and methods does not break their code (R14.2).
- **Interface evolution.** A new named parameter in an abstract method breaks hand-written fakes (`implements`). Therefore all per-call options should be gathered into one object `ApiCallOptions`: new fields in it break nothing.
- `@immutable` / `meta` are free: `meta` is already a transitive dependency of `dio`.
- **Dot shorthands (3.10)** sharply improve ergonomics for the consumer: `UpdatePet(name: .value('Rex'), tag: .nullValue())` compiles with the context `Patch<String>?` (verified in `exp/bin/shorthand.dart`). The generated code does not need them.
- **Primary constructors (3.13)** are better not used in generated code, so as not to require users to have Dart ≥3.13. The recommended baseline for generated code is **language 3.8** (null-aware elements, tall-style formatter, the same minimum as json_serializable ≥6.10). Make it configurable.

### C.5. Tri-state (R7)

| Pattern | Constructor | Reading | `toJson` skips absent | Compatibility with json_serializable |
|---|---|---|---|---|
| **`Patch<T>?`** (null = absent; `Patch.value(x)` / `Patch.nullValue()`) | `UpdatePet(name: .value('Rex'))` | `switch (p) { null => …, PatchNull() => …, PatchValue(:final value) => … }` — exhaustive (verified) | yes, null-aware entry | **yes, 6.14 `explicitJsonNullWhenNonNullField`** (verified) |
| drift `Value<T>` (`Value.absent()` by default, `Value(null)`) | `name: Value('Rex')` | `v.present ? v.value : …` | only hand-written `toJson` | no |
| freezed sentinel (`Object? x = freezed`) | — | — | — | only for `copyWith`, the inner type is lost |
| `Optional<T>` / Kotlin-like | similar to drift | | | no |

**Recommendation: `Patch<T>?`.** This is consistent with R7.3: everywhere in the model `null` means "do not send". There is no additional `absent` state in regular optional fields. The drawback is that `copyWith` does not distinguish "leave unchanged" from "make absent". For request bodies `copyWith` is rarely needed (R6.6 SHOULD), and if it is needed, a sentinel trick like the one in freezed will do.

### C.6. Arbitrary JSON (R6.2)

| Variant | Pros | Cons |
|---|---|---|
| `Object?` | zero cost | almost `dynamic`; the requirement says "a separate type" |
| **`extension type JsonValue(Object? raw)`** | a separate type, zero allocations, `jsonEncode` works, helpers `asMap`/`asList`/`asString` | no protection, but it is not needed here |
| sealed `JsonNull/Bool/Num/String/Array/Object` (precedent: `built_value` `JsonObject` — Bool/List/Map/Num/String, without Null) | exhaustive switch | deep conversion both ways, allocations |

**Recommendation:** extension type `JsonValue` in the runtime package; for parsing, pattern matching on `raw`. There is no ready-made popular package: a search on pub.dev found nothing relevant.

---

## D. Code generation toolchain

### D.1. `code_builder` vs templates vs custom emitters

| | code_builder 4.12 | mustache (`mustache_template` 2.0.6) | Custom emitter (string builder + import manager) |
|---|---|---|---|
| Syntactic correctness | high (AST specifications) | low | medium; backed by `DartFormatter`, since it throws an exception on a syntax error |
| Determinism (R13.1) | yes (`DartEmitter(orderDirectives: true)`, `Allocator`) | yes, but whitespace and escaping are under manual control | yes, if imports are sorted, `HashSet` is not iterated, and `lineEnding: '\n'` is passed |
| Modern syntax | 4.12 (2026-08) added `SwitchExpression`, `Pattern`, control flow; sealed and extension types are supported | any | any |
| Readability of the generator | verbose | the template is easy to read, the logic is not | reads like the code being generated |
| Who does this | retrofit_generator and tonik_generate, but both mix in raw `Code('…')` | openapi-generator (Java) | json_serializable (StringBuffer), freezed (`analyzer_buffer`) |
| Dependencies | `built_value`, `built_collection` (only in the generator) | minimal | none |

**Recommendation:** a custom typed emitter (DartWriter with an import allocator, identifier escaping and doc comments), or a hybrid where code_builder handles declarations and imports, and method bodies are assembled from strings. Do not take Mustache: the Dart-name and style escaping logic cannot be moved into a logic-less template, and templates as an extension point become an unstable public contract (see E, decision 6).

### D.2. `dart_style` and "formatter drift"

API: `DartFormatter(languageVersion: Version, pageWidth:, trailingCommas: TrailingCommas.automate|preserve, lineEnding:)`. `languageVersion` is required since 3.x.

**Facts:**
- The style depends on the file's language version: ≤3.6 is the old short style, ≥3.7 is the tall style. There are language-versioned changes in 3.8 and 3.13 (SDK CHANGELOG).
- **3.13 added "Separate imports into sections".** Verified (`exp/bin/fmt.dart`): unordered imports produce different output for 3.12 and 3.13. **If imports are emitted already grouped** (`dart:` / empty line / `package:` / empty line / relative), the output of 3.12 and 3.13 matches byte for byte (`exp/bin/fmt2.dart`).
- **Even patch releases change the style without being tied to a language version**: dart_style 3.1.13 started adding a trailing comma in an enum with a primary constructor, and this went into a patch SDK.
- `dart format` in SDK 3.13.1 is `dart_style 3.1.10 supporting … 2.12 through 3.13`, while pub already has 3.1.13. Therefore, the "same" format in the generator and for the user may differ.
- The user can enable `formatter: trailing_commas: preserve` or `page_width` in `analysis_options.yaml`. Verified: the output of `automate` is stable when reformatted with `preserve`.
- For generators there is a marker `// dart format width=N` at the start of the file ("mainly for code generators").
- `// dart format off` **without a paired `on`**: in 3.12 and 3.13 the rest of the file is left untouched (`exp/bin/fmt3.dart`). This is **undocumented** behaviour: the CHANGELOG describes only off/on pairs.
- Since 3.1.13, `DartFormatter.lineEnding` is inferred from the input code. For determinism, `'\n'` must be passed explicitly.

**Recommendations:**
1. Pin `dart_style` in the generator. Take `languageVersion` from `environment.sdk` of the target package, with an override in the config.
2. Write `// dart format width=<config>` in every file (R13.2).
3. Emit imports in a canonically grouped and sorted form.
4. Pass `lineEnding: '\n'`.
5. Golden tests: check formatting idempotence on the minimum and maximum supported language versions (e.g., 3.8 and 3.13), and in the CI matrix with the oldest and newest SDK run `dart format --set-exit-if-changed` on the generated code.
6. Optionally, as a safeguard: the header `// dart format off`. The risk is that the behaviour is undocumented.

### D.3. `analyzer` for tests (R15.3)

`analyzer` changes its major version on average every 1–2 months (10.0.0 2026-01-07 … 14.0.0 2026-06-18). `dart_style` itself depends on `analyzer >=13.1.0 <15.0.0`. What follows from this:
- **The generator core must not depend on the analyzer API.** For "compiles and passes the analyzer", run `dart analyze` as a subprocess on fixture packages (Petstore, Stripe, GitHub, OpenAI, K8s). The CLI interface is stable.
- Keep `analyzer` as a library (`AnalysisContextCollection` → `getErrors`) only in the `dev_dependencies` of the test package, if in-process speed is needed.
- **Distribution.** The generator should be distributed as an isolated tool: `dart install` (Dart 3.10+), `dart run <pkg>@<version>` (3.12+) or `dart pub global activate`, rather than as a `dev_dependency`. This way its `analyzer`/`dart_style` do not conflict with freezed, riverpod_generator, etc. in the user's project, and the version is pinned (R13.1, R15.4).

---

## E. Recommendations for open decisions

### Key question: can R6.5, R7, R8, R9 be done "using json_serializable"?

**In short: only partially. json_serializable covers simple object models well; unions, open enums and errors with a path will in any case have to be generated by hand.**

| Requirement | json_serializable 6.14 | Details |
|---|---|---|
| R7 tri-state | ✅ | `explicitJsonNullWhenNonNullField` + `Patch<T>?` (verified) |
| R6.1 matrix | ✅ | `required`, `disallowNullValue`, `includeIfNull` |
| R6.4 generics | ✅ | `genericArgumentFactories` |
| R6.5 clear errors | ⚠️ | class + key without a path; checked is ≈25× slower |
| R8.1 / R8.2 | ❌ | the raw value is lost, `$unknown` is sent |
| R9 union with unknown | ❌ | #1342 open since 2023; a hand-written sealed type with `fromJson`/`toJson` is picked up as a field (verified) |
| R13.1 / R15.4 determinism | ❌ | the output is generated on the user's machine by their version of json_serializable |

The generator still has to emit the most complex part by hand (unions, enums, errors, parameters, SSE). Emitting simple `fromJson`/`toJson` on top of this too costs little: it is the simplest emitter, ~300–500 LOC. In exchange, build_runner disappears along with all the problems from A.8.

### Decision 1. Output type

**Recommendation: ready-made code without build_runner** (and the only option in v1). Make the build_runner integration (R15.1) a thin optional `Builder` that calls the same programmatic API (spec → files, `build_to: source`).

- **For:** R13.1 and R15.4 (the output depends only on the generator's version); R15.3 (golden = direct comparison); no 12-second AOT compilation on CI; no lock-step on `analyzer`; the user is not tied to the SDK required by freezed 4 (≥3.13) or build_runner 2.16 (≥3.11). Macros have been cancelled, augmentations have not shipped, so there will be no "new path" in the near future.
- **Against:** more code in the generator; developers are used to seeing `@JsonSerializable` in models.
- **Mitigation:** the generated models follow the **json_serializable contract** (`factory X.fromJson(Map<String, dynamic>)`, `Map<String, dynamic> toJson()`), so they fit into the user's `@JsonSerializable` classes and vice versa (verified in A.3 and A.6). An optional mode "models as `@JsonSerializable`" can be added later for simple object schemas.

### Decision 2. Serialization

**Recommendation: our own emission of (de)serialization with minimal runtime helpers (`JsonObjectReader`, `$list`, `$map`, decoders for primitives and formats, `JsonDecodeException` with a path).** The public signatures are compatible with json_serializable.

- **json_serializable as the engine** is suitable only for simple models (see the table above).
- **freezed:** heavy, analyzer lock-step, 4.x requires Dart ≥3.13. Unions via `unionKey` / `fallbackUnion` exist, but there is no raw JSON in the fallback. Plus build_runner again.
- **dart_mappable:** a runtime dependency (`type_plus`) and a **global `MapperContainer.globals`**, which contradicts R4.3 ("no global side effects"). Plus build_runner.
- **Performance:** the prototype with paths is ≈2.2× slower than unchecked json_serializable and ≈10× faster than checked. If zero overhead on the success path is needed, it can be done in two phases: a fast decode, and on error a repeated traversal by the generated validator to obtain the path.

### Decision 3. HTTP layer

**Recommendation: Dio only. The transport is changed through Dio's own `HttpClientAdapter`; do not build our own abstraction.**
- Dio is already an abstraction over the transport: `IOHttpClientAdapter`, `BrowserHttpClientAdapter`, and via `dio_compatibility_layer` any `package:http` client (`cronet_http`, `cupertino_http`, `BrowserClient`/`FetchClient` with streaming).
- Our own abstraction would duplicate interceptors, `Options` and `CancelToken`, and would break R10.1, R10.2, R12.4 ("the user's same client").
- Narrow the Dio surface in the generated code to `Dio.request`, `Options`, `Response`, `DioException`, `CancelToken`, `FormData`, `MultipartFile`, `ListParam`, `ResponseBody`. Then the abstraction, if it is ever needed, will be a mechanical change.
- **Web + SSE:** in the documentation give the recipe `ConversionLayerAdapter(BrowserClient())` (conditional import) and honestly describe the limitations: cancellation only at the Dio level, without upload progress.

### Decision 4. Default error model

**Recommendation: an exception by default (sealed `ApiException<E>`), with `Result` as a generated extension over the same method.** In the "both" mode the interface has **one** method per operation, and only it needs to be mocked (R10.7).

| | Exception | `Result<T, E>` |
|---|---|---|
| Idiomaticity in Dart/Flutter | high (`Future` already carries the error; Riverpod `AsyncValue.guard` and Bloc are oriented toward exceptions) | requires unwrapping everywhere |
| Visibility in the signature | only a doc comment `/// Throws [ApiException<GetPetError>]` | in the type |
| Enforcement of handling | none | yes |
| R10.2 | natural: `DioException` has already passed through `onError` | the same, only a wrapper |
| Exhaustiveness | `on ApiException<GetPetError> catch (e) { switch (e) … }` | `switch (result)` |

### Decision 5. Parser

**Recommendation: our own parser and our own IR, isolated by layers:**

raw document with positions (`package:yaml` gives `SourceSpan`; plus JSON pointer) → normalizer (R2.1) → overrides (R3) → resolved IR → Dart mapping (names, types) → emitter.

The packages `tonik_core` and `tonik_parse` are at version 0.10.0 (pre-1.0, unstable API); moreover, `tonik_core` depends on the runtime package `tonik_util`, i.e. the model is coupled to the runtime. Moreover, R2 and R3 (diagnostics with pointers, overrides, baseline) require full control over the model. A more detailed analysis of parsers is outside this document.

### Decision 6. Extensibility

**Recommendation: config and overrides (R3) plus a programmatic API with typed hooks over the IR. Do not build templates.**

Examples of hooks: `TypeMapping` (Decimal, Date, BigInt — codecs for a format), naming, filters. Templates make every change of the output or of the template structure breaking (R15.4), break the lint guarantees (R13.2) and determinism, and users fork them. Hooks over the IR are deterministic, versioned together with the API, and tested.

### Decision 7. Representation of tri-state and raw enum

- **Tri-state:** `Patch<T>?` (see C.5 and sketch E.2).
- **Enum:** sealed `X` + `enum XKnown implements X` + `final class XUnknown` with a private constructor and static aliases (see C.3 and sketch E.3). Operation parameters and public model constructors accept `XKnown`; model fields have type `X`.
- **Extension type rejected** (C.2): R8.2 is not achieved, exhaustiveness is lost.
- **Trade-off with R14.2:** a new value breaks an exhaustive switch in the consumer at the source-code level. For those who do not accept this, provide a config option "do not make known values exhaustible" (an ordinary class with static constants).

### E.1. Minimal runtime package (R13.3)

Dependencies: **`dio` + `meta`** (`meta` is already transitive from dio, so there are no new transitive dependencies). Separate semver versioning; the generated code checks the compatible range.

```
errors.dart    sealed ApiException<E>: ApiHttpException<E> (status, headers, typed body),
               ApiUndocumentedStatusException<E> (status, raw body), ApiTransportException<E>
               (TransportFailure kind ← DioExceptionType), ApiCancelledException<E>,
               ApiDecodeException<E>
result.dart    sealed ApiResult<T,E>: ApiOk / ApiErr;  Future<ApiResult<T,E>> runAsResult<T,E>(…)
response.dart  ApiResponse<T> (data, statusCode, headers: Map<String,List<String>>, raw Response?)
               — constructor without Dio, so it can be mocked
call.dart      ApiCallOptions (cancelToken, headers, extra, onSend/ReceiveProgress, timeouts)
               OperationInfo (operationId, method, pathTemplate, tags, security) + OperationInfo.of(RequestOptions)
json.dart      JsonDecodeException (schema, pointer, message, value), JsonObjectReader (ext type),
               $list/$map/$int/$num/$string/$bool/$dateTime/$date/$uuid/$bytes/$int64, JsonValue (ext type)
patch.dart     sealed Patch<T>: PatchValue / PatchNull
params.dart    OAS style encoders: path (simple/label/matrix), query (form/explode, space/pipeDelimited,
               deepObject), header (simple), cookie, form-urlencoded; multipart-part helper
sse.dart       SseEvent, SseDecoder (StreamTransformer<List<int>, SseEvent>, WHATWG), reconnect + Last-Event-ID
```

### E.2. Sketch: tri-state field

```dart
// runtime
sealed class Patch<T> {
  const Patch();
  const factory Patch.value(T value) = PatchValue<T>;
  const factory Patch.nullValue() = PatchNull<T>;
  Object? toJson(Object? Function(T value) encode);
}
final class PatchValue<T> extends Patch<T> { const PatchValue(this.value); final T value;
  @override Object? toJson(Object? Function(T) encode) => encode(value); }
final class PatchNull<T> extends Patch<T> { const PatchNull();
  @override Object? toJson(Object? Function(T) encode) => null; }

// generated (PATCH body)
final class UpdatePetRequest {
  const UpdatePetRequest({this.name, this.tag, this.nickname});
  final Patch<String>? name;       // tri-state: null = absent
  final Patch<String>? tag;
  final String? nickname;          // one state: null = do not send (R7.3)
  Map<String, Object?> toJson() => {
    if (name case final v?) 'name': v.toJson((s) => s),
    if (tag case final v?) 'tag': v.toJson((s) => s),
    'nickname': ?nickname,
  };
}
// usage (Dart ≥3.10):
// api.updatePet(id: 1, body: UpdatePetRequest(name: .value('Rex'), tag: .nullValue()));
// → {"name":"Rex","tag":null}
```

### E.3. Sketch: open enum (R8.1 + R8.2)

```dart
sealed class PetStatus {
  static const available = PetStatusKnown.available;   // aliases: PetStatus.available, `.available`
  static const sold = PetStatusKnown.sold;
  factory PetStatus.fromJson(Object? json) {
    final s = $string(json);
    return PetStatusKnown._byValue[s] ?? PetStatusUnknown._(s);
  }
  String get value;
  String toJson();
}
enum PetStatusKnown implements PetStatus {
  available('available'), sold('sold');
  const PetStatusKnown(this.value);
  @override final String value;
  static final _byValue = {for (final v in values) v.value: v};
  @override String toJson() => value;
}
final class PetStatusUnknown implements PetStatus {
  const PetStatusUnknown._(this.value);               // only the decoder can create it
  @override final String value;                        // the raw value is stored (R8.1)
  @override String toJson() => value;
  @override bool operator ==(Object o) => o is PetStatusUnknown && o.value == value;
  @override int get hashCode => value.hashCode;
}

final class Pet {
  Pet({required this.name, required PetStatusKnown this.status});  // R8.2: known values only
  Pet._decoded({required this.name, required this.status});
  final String name;
  final PetStatus status;                                          // may be PetStatusUnknown
  // query/path parameters of operations also have type PetStatusKnown
}
// switch (pet.status) { PetStatus.available => …, PetStatus.sold => …, PetStatusUnknown(:final value) => … }
```

### E.4. Sketch: union with an unknown variant (R9.1)

```dart
sealed class Animal {
  const Animal();
  factory Animal.fromJson(Map<String, Object?> json) => switch (json['petType']) {
        'cat' => Cat.fromJson(json),
        'dog' => Dog.fromJson(json),
        final other => AnimalUnknown._(other is String ? other : null, json),
      };
  Map<String, Object?> toJson();
}
final class Cat extends Animal {
  const Cat({required this.lives});
  final int lives;
  factory Cat.fromJson(Map<String, Object?> json) {
    final r = JsonObjectReader(json);
    return Cat(lives: r.req('Cat', 'lives', $int));
  }
  @override Map<String, Object?> toJson() => {'petType': 'cat', 'lives': lives};
}
final class Dog extends Animal { /* … */ }
final class AnimalUnknown extends Animal {
  const AnimalUnknown._(this.discriminator, this.json);
  final String? discriminator;        // null if there is no discriminator in the JSON
  final Map<String, Object?> json;    // raw JSON (R9.1)
  @override Map<String, Object?> toJson() => json;
}
```

### E.5. Sketch: typed error and Result (R11)

```dart
// runtime
sealed class ApiException<E> implements Exception { const ApiException(); }
final class ApiHttpException<E> extends ApiException<E> {        // documented 4xx/5xx/default
  const ApiHttpException(this.statusCode, this.body, this.headers, this.cause);
  final int statusCode; final E body; final Map<String, List<String>> headers;
  final DioException cause;                                      // has already passed onError (R10.2)
}
final class ApiUndocumentedStatusException<E> extends ApiException<E> { // R11.3
  const ApiUndocumentedStatusException(this.statusCode, this.rawBody, this.cause);
  final int? statusCode; final Object? rawBody; final DioException? cause;
}
enum TransportFailure { connectionTimeout, sendTimeout, receiveTimeout, connectionError,
                        badCertificate, transformTimeout, unknown }   // R11.7
final class ApiTransportException<E> extends ApiException<E> {
  const ApiTransportException(this.kind, this.cause); final TransportFailure kind; final DioException cause;
}
final class ApiCancelledException<E> extends ApiException<E> { const ApiCancelledException(this.cause); final DioException cause; }
final class ApiDecodeException<E> extends ApiException<E> {
  const ApiDecodeException(this.error, this.statusCode); final JsonDecodeException error; final int? statusCode;
}

sealed class ApiResult<T, E> { const ApiResult(); }
final class ApiOk<T, E> extends ApiResult<T, E> { const ApiOk(this.response); final ApiResponse<T> response; }
final class ApiErr<T, E> extends ApiResult<T, E> { const ApiErr(this.error); final ApiException<E> error; }

// generated, per operation: the shared Error schema is generated once (R11.4)
sealed class GetPetByIdError { const GetPetByIdError(); }
final class GetPetByIdError404 extends GetPetByIdError { const GetPetByIdError404(this.body); final NotFound body; }
final class GetPetByIdErrorDefault extends GetPetByIdError {
  const GetPetByIdErrorDefault(this.statusCode, this.body); final int statusCode; final ApiError body;
}
```

### E.6. Sketch: abstract API class (R10.1, R10.5, R10.7)

```dart
abstract interface class PetsApi {
  factory PetsApi(Dio dio) = _PetsApi;          // the user's Dio; baseUrl is not touched (R10.1)

  /// GET /pet/{petId}
  /// Throws [ApiException<GetPetByIdError>].
  Future<ApiResponse<Pet>> getPetById({required int petId, ApiCallOptions? options});
}

final class _PetsApi implements PetsApi {
  _PetsApi(this._dio);
  final Dio _dio;

  static const _getPetById = OperationInfo(
      operationId: 'getPetById', method: 'GET', pathTemplate: '/pet/{petId}',
      tags: ['pet'], security: [{'api_key': []}]);              // R10.8

  @override
  Future<ApiResponse<Pet>> getPetById({required int petId, ApiCallOptions? options}) async {
    final Response<Object?> res;
    try {
      res = await _dio.request<Object?>(                         // request(), not fetch(): merges BaseOptions
        '/pet/${encodePathSimple(petId)}',
        options: Options(method: 'GET', responseType: ResponseType.json,
            headers: options?.headers,
            extra: {...?options?.extra, OperationInfo.key: _getPetById}),   // R10.5
        cancelToken: options?.cancelToken,
        onReceiveProgress: options?.onReceiveProgress,
      );
    } on DioException catch (e) {
      throw mapDioException<GetPetByIdError>(e, (status, body) => switch (status) {
        404 => GetPetByIdError404(NotFound.fromJson(asJsonObject(body))),
        final s? when s >= 400 => GetPetByIdErrorDefault(s, ApiError.fromJson(asJsonObject(body))),
        _ => null,                                               // → ApiUndocumentedStatusException
      });
    }
    return switch (res.statusCode) {                             // an interceptor could have resolved a non-2xx
      200 => decodeResponse(res, (body) => Pet.fromJson(asJsonObject(body))),
      _ => throw ApiUndocumentedStatusException<GetPetByIdError>(res.statusCode, res.data, null),
    };
  }
}

// "both" mode (R11.2): Result without changing the interface
extension PetsApiResults on PetsApi {
  Future<ApiResult<Pet, GetPetByIdError>> getPetByIdResult({required int petId, ApiCallOptions? options}) =>
      runAsResult(() => getPetById(petId: petId, options: options));
}

// test without code generation (R10.7, verified with mocktail)
// class MockPetsApi extends Mock implements PetsApi {}
```

---

## Sources

**pub.dev (versions and dates verified via `https://pub.dev/api/packages/<name>` 2026-10-11)**
- https://pub.dev/packages/json_serializable (6.14.1) · https://pub.dev/packages/json_annotation (4.12.0)
- https://pub.dev/packages/build_runner (2.16.2) · https://pub.dev/packages/dart_style (3.1.13) · https://pub.dev/packages/code_builder (4.12.0) · https://pub.dev/packages/analyzer (14.5.0)
- https://pub.dev/packages/dio (5.11.1) · https://pub.dev/packages/dio_web_adapter (2.2.2) · https://pub.dev/packages/dio_compatibility_layer (0.1.1) · https://pub.dev/packages/http (1.6.0) · https://pub.dev/packages/fetch_client (1.2.1)
- https://pub.dev/packages/retrofit (4.10.0) · https://pub.dev/packages/retrofit_generator (10.2.11) · https://pub.dev/packages/freezed (4.0.2) · https://pub.dev/packages/dart_mappable (4.10.0) · https://pub.dev/packages/tonik (0.10.0) · https://pub.dev/packages/mocktail · https://pub.dev/packages/sse_parser
- Dart SDK latest stable: https://storage.googleapis.com/dart-archive/channels/stable/release/latest/VERSION (3.13.5, 2026-09-29)

**Source code (local pub-cache, the same versions)**
- `~/.pub-cache/hosted/pub.dev/json_annotation-4.12.0/lib/src/{checked_helpers,enum_helpers,allowed_keys_helpers,json_key,json_serializable}.dart`, `CHANGELOG.md`
- `~/.pub-cache/hosted/pub.dev/json_serializable-6.14.1/{CHANGELOG.md,pubspec.yaml,lib/src/type_helpers/patch_tri_state_helper.dart,test/src/patch_tri_state_test_input.dart}`
- `~/.pub-cache/hosted/pub.dev/build_runner-2.16.2/CHANGELOG.md`
- `~/.pub-cache/hosted/pub.dev/dio-5.11.1/{CHANGELOG.md,lib/src/dio_exception.dart,lib/src/options.dart,lib/src/dio_mixin.dart,lib/src/utils.dart,lib/src/parameter.dart,lib/src/multipart_file.dart,lib/src/form_data.dart,lib/src/transformer.dart,lib/src/transformers/fused_transformer.dart}`
- `~/.pub-cache/hosted/pub.dev/dio_web_adapter-2.2.2/lib/src/adapter_impl.dart`
- `~/.pub-cache/hosted/pub.dev/http-1.6.0/{CHANGELOG.md,lib/src/browser_client.dart}`; `dio_compatibility_layer-0.1.1/lib/src/conversion_layer_adapter.dart` (pub archive downloaded)
- `~/.pub-cache/hosted/pub.dev/retrofit-4.10.0/lib/{http,dio,call_adapter,error_logger}.dart`, `retrofit_generator-10.2.11/lib/src/generator.dart`
- `~/.pub-cache/hosted/pub.dev/dart_style-3.1.13/{CHANGELOG.md,lib/src/dart_formatter.dart}`, `code_builder-4.12.0/CHANGELOG.md`, `freezed-4.0.2/CHANGELOG.md`, `drift-2.34.2/lib/src/runtime/data_class.dart`, `built_value-8.13.0/lib/json_object.dart`; `dart_mappable-4.10.0/lib/src/mapper_container.dart` (pub archive)

**GitHub**
- google/json_serializable.dart#1342 (sealed, open since 2023-08): https://github.com/google/json_serializable.dart/issues/1342
- google/json_serializable.dart PR #1483 (sealed, unmerged): https://github.com/google/json_serializable.dart/pull/1483
- google/json_serializable.dart PR #1574 (tri-state, merged 2026-05-15): https://github.com/google/json_serializable.dart/pull/1574
- google/json_serializable.dart#1508 (generics in converters): https://github.com/google/json_serializable.dart/issues/1508
- cfug/dio#1859 (SSE on Flutter Web, open): https://github.com/cfug/dio/issues/1859 · cfug/dio#1740 (Fetch API, open): https://github.com/cfug/dio/issues/1740
- trevorwang/retrofit.dart#168 (error handler, open since 2020): https://github.com/trevorwang/retrofit.dart/issues/168 · #525 (SSE, not planned): https://github.com/trevorwang/retrofit.dart/issues/525 · #235: https://github.com/trevorwang/retrofit.dart/issues/235
- dart-lang/build PR #4405 (perf build_runner 2.13): https://github.com/dart-lang/build/pull/4405
- Augmentations specification (working, experiment flag, revision 2026-10-06): https://github.com/dart-lang/language/blob/main/working/augmentations/feature-specification.md
- Dart SDK CHANGELOG (3.7 tall style and formatter markers; 3.8 null-aware elements; 3.10 dot shorthands and `dart install`; 3.12 `dart run pkg@ver`; 3.13 primary constructors and import sections): https://github.com/dart-lang/sdk/blob/main/CHANGELOG.md

**Blogs and documentation**
- "An update on Dart macros & data serialization", Vijay Menon, 2025-01-29: https://medium.com/dartlang/an-update-on-dart-macros-data-serialization-06d3037d4f12 (mirror: https://dart.cn/blog/an-update-on-dart-macros-data-serialization)
- Flutter & Dart 2026 roadmap, 2026-02-24: https://flutter.dev/blog/flutter-darts-2026-roadmap
- Extension types: https://dart.dev/language/extension-types · Class modifiers: https://dart.dev/language/class-modifiers · Exhaustiveness: https://dart.dev/language/branches#exhaustiveness-checking · dart format: https://dart.dev/tools/dart-format · dart install: https://dart.dev/tools/dart-install
- OpenAPI style values: https://spec.openapis.org/oas/v3.1.0#style-values

**Experiments** (`<scratchpad>/agent-dart/exp/`)
- `lib/models.dart` (+ `.g.dart`): checked errors, enum unknown, tri-state 6.14, sealed union as a field, generics, extension type as a field
- `lib/open_enum.dart`, `lib/open_enum2.dart`, `lib/mood_model.dart`, `lib/shapes.dart`; `bin/exhaust.dart`, `bin/exhaust2.dart`, `bin/shapes_neg.dart`, `bin/shorthand.dart`: exhaustiveness, narrowed type in a constructor, dot shorthands
- `lib/rt.dart`, `bin/rt_demo.dart`, `lib/bench_models.dart`, `bin/bench.dart`: prototype of a decoder with a path and a benchmark
- `lib/gen/` (600 models): build_runner measurements
- `bin/dio_flow.dart`: `onError`, 204, query encoding, SSE chunks, cancel / connectionError
- `bin/fmt.dart`, `bin/fmt2.dart`, `bin/fmt3.dart`: dart_style drift, grouping of imports, `width=` and `off` markers
- `lib/api.dart`, `test/mock_test.dart`: mocktail over `abstract interface class`
