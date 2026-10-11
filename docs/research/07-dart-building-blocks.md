# 07 — Будівельні блоки на боці Dart: json_serializable, build_runner, Dio, мова, тулчейн

Дата дослідження: 2026-10-11. Мета: зібрати факти про можливості й обмеження Dart-інструментів, на яких стоятиме генератор (dio + json_serializable), і дати рекомендації щодо відкритих рішень 1–7 з `../requirements.md`.

## 0. Версії, з якими працювали (pub.dev API, 2026-10-11)

| Пакет / SDK | Остання стабільна | Дата | Примітка |
|---|---|---|---|
| Dart SDK | **3.13.5** (beta 3.14.0-211.1) | 2026-09-29 | 3.13 = primary constructors |
| json_serializable | **6.14.1** | 2026-07-30 | 6.14.0 (2026-05-15) додав tri-state |
| json_annotation | **4.12.0** | 2026-05-15 | json_serializable жорстко пінить `>=4.12.0 <4.13.0` |
| build_runner | **2.16.2** | 2026-10-07 | потребує Dart ^3.11, analyzer ≥14.3 |
| dio | **5.11.1** | 2026-09-04 | |
| dio_web_adapter | **2.2.2** | 2026-09-04 | |
| dart_style | **3.1.13** | 2026-08-26 | SDK 3.13.1 бандлить **3.1.10** |
| code_builder | **4.12.0** | 2026-08-28 | додано switch expressions, patterns |
| analyzer | **14.5.0** | 2026-10-06 | 5 мажорних релізів за H1 2026 |
| retrofit / retrofit_generator | 4.10.0 / 10.2.11 | 2026-08 / 2026-09 | |
| freezed | 4.0.2 | 2026-09-18 | потребує Dart ≥3.13 |
| dart_mappable | 4.10.0 | 2026-09-07 | |
| http / fetch_client / dio_compatibility_layer | 1.6.0 / 1.2.1 / 0.1.1 | | |

Усі експерименти — у `/private/tmp/claude-501/…/scratchpad/agent-dart/exp/` (далі `exp/`), Dart 3.13.1, macOS arm64 (Apple M5). Перелік файлів — у кінці документа.

---

## A. json_serializable і build_runner

### A.1. `checked: true` і `CheckedFromJsonException` (→ R6.5)

**Як працює.** У checked-режимі кожне поле декодується через `$checkedConvert(map, key, castFunc)`, а весь об'єкт загортається в `$checkedCreate(className, ...)`. Будь-яке виключення перетворюється на `CheckedFromJsonException` з полями `className`, `key`, `map`, `innerError`, `message`, `badKey` (`~/.pub-cache/hosted/pub.dev/json_annotation-4.12.0/lib/src/checked_helpers.dart`).

**Обмеження, перевірені експериментом** (`exp/bin/main.dart`):

```
[nested list item wrong type]  Could not create `Item`. There is a problem with "price".
                               type 'String' is not a subtype of type 'num' in type cast
[nested missing required]      Could not create `Item`. There is a problem with "name".
                               type 'Null' is not a subtype of type 'String' in type cast
[unchecked missing]            _TypeError: type 'Null' is not a subtype of type 'String' in type cast
```

1. **Шляху в JSON немає.** Є тільки найглибший клас і ключ. `$checkedConvert` має гілку `on CheckedFromJsonException { rethrow; }`, тому зовнішній контекст (`Page → items[1]`) губиться. Отже, `/items/1/price` отримати не вийде.
2. **Відсутнє обов'язкове поле виглядає як помилка типу** (`'Null' is not a subtype of 'String'`). Щоб отримати `MissingRequiredKeysException` («Required keys are missing: name.»), потрібен `@JsonKey(required: true)` (`allowed_keys_helpers.dart`).
3. **Без `checked` контексту немає взагалі**: голий `TypeError`, без імені поля і класу.
4. **Ціна продуктивності.** Мікробенчмарк в AOT (`exp/bin/bench.dart`, 2000 × сторінка з 1000 елементів):

| Варіант | Час |
|---|---|
| json_serializable, unchecked | ~35 мс |
| json_serializable, `checked: true` | **~910 мс (≈25× повільніше)** |
| Прототип декодера зі шляхами (`exp/lib/rt.dart`) | ~80 мс (≈2,2×) |

Прототип видає саме те, чого вимагає R6.5:
```
JsonDecodeException(Item at "/items/1/name"): missing required property "name"
JsonDecodeException(integer at "/items/1/price"): expected integer, got String
```
Це мікробенчмарк на одній машині, але порядок величин показовий.

**`disallowUnrecognizedKeys`** кидає `UnrecognizedKeysException`. Для R6.5 («зайві поля ігноруються») потрібне значення за замовчуванням `false`, і воно вже працює (перевірено: `{"id":"x","zzz":1}` декодується).

### A.2. `includeIfNull`, `includeToJson/FromJson` і новий tri-state (→ R6.1, R7)

- `includeIfNull: false` (на класі або `@JsonKey`) генерує `'k': ?instance.k`. Це null-aware element, тобто згенерований код потребує мови **≥3.8** (json_serializable ≥6.10, CHANGELOG). Так закривається R7.3: optional-поле зі значенням null у JSON не потрапляє.
- `includeToJson: false` / `includeFromJson: false` виключають поле в одному напрямку. Підходить для `readOnly` / `writeOnly`.
- **Нове в 6.14.0 (2026-05-15, PR google/json_serializable.dart#1574):** `@JsonKey(explicitJsonNullWhenNonNullField: true)`. Поле має бути nullable. Dart `null` означає, що ключ відсутній. Якщо значення ненульове, але серіалізується в JSON `null`, у вихід потрапляє `"k": null`. `fromJson` розрізняє стани через `containsKey`. Офіційний патерн із тестів (`json_serializable-6.14.1/test/src/patch_tri_state_test_input.dart`) — `sealed class PatchValue<T>` з `fromJson(Object?, fromJsonT)` / `toJson(toJsonT)`.

Перевірено (`exp/lib/models.dart`, клас `UpdatePet`):
```
absent: {}
null:   {"name":null}
value:  {"name":"Rex","owner":{"id":"o1"}}
decode {"name":null,"tag":"t"} → name=PatchNull<String>, tag=PatchValue<String>, owner=null
```
**Висновок: R7 на json_serializable ≥6.14 реалізовується.** Матриця R6.1 теж виражається: `required: true` для «ключ обов'язковий», `disallowNullValue` для «null заборонений», `includeIfNull` і `explicitJsonNullWhenNonNullField`.

### A.3. Enum: `unknownEnumValue`, `nullForUndefinedEnumValue`, `@JsonEnum(valueField:)` (→ R8)

`$enumDecode(map, source, unknownValue:)` повертає `unknownValue`, а саме значення `source` **викидає** (`enum_helpers.dart`). `JsonKey.nullForUndefinedEnumValue` повертає `null` і теж губить значення. Експеримент:
```
WithEnum.fromJson({"status":"archived","maybe":"weird"})
→ status=Status.$unknown  maybe=null
→ toJson = {"status":"$unknown","maybe":null}
```
- **R8.1 порушено**: сире `"archived"` втрачено.
- **R8.2 порушено**: значення-заглушка `$unknown` потрапляє в `_$StatusEnumMap` і **надсилається на сервер як рядок `"$unknown"`**. Виключити його з мапи засобами json_serializable не можна.
- `@JsonEnum(valueField: 'value')` дозволяє серіалізувати enhanced enum за полем, але проблему unknown не розв'язує.

**Обхідний шлях (перевірено, `exp/lib/open_enum.dart`, `exp/lib/mood_model.dart`).** json_serializable використовує будь-який тип, що має `factory X.fromJson(...)` і `toJson()`. Згенерувався `Mood.fromJson(v)` для полів `Mood`, `List<Mood>?` і `Mood?`. Тому відкритий enum у вигляді sealed-типу, написаного вручну (див. E.3), працює як поле `@JsonSerializable`-класу.

### A.4. `genericArgumentFactories` (→ R6.4)

Працює як очікується. `Envelope<T>.fromJson(json, T Function(Object?) fromJsonT)` і `toJson(Object? Function(T) toJsonT)`, перевірено на `Envelope<Owner>`. Відоме обмеження: json_serializable не бачить дженериків у `@JsonKey(fromJson:)` / `JsonConverter` (issue #1508, відкрите).

### A.5. `JsonConverter`, `createFieldMap`, `createPerFieldToJson`, `createJsonKeys`

- `JsonConverter<T, S>` на полі, класі або в `JsonSerializable(converters: [...])` підходить для R6.2 (`Decimal`, власний `Date`, `int64` як `BigInt`/`Int64` на web, де `int` > 2^53 втрачає точність).
- `createFieldMap` / `createJsonKeys` дають константи «Dart-ім'я → JSON-ключ». `createPerFieldToJson` генерує `_$XPerFieldToJson.<field>(value)`, що зручно для серіалізації окремих полів у query/form. Вимог вони не закривають, лише допомагають.
- `createJsonSchema` (6.12) генерує JSON Schema з класу. Для нас нерелевантно.

### A.6. Sealed-класи, union, `additionalProperties`

- **Нативної підтримки sealed / union немає.** Issue google/json_serializable.dart#1342 «Support dart3 sealed class» відкрите з 2023-08. Мейнтейнер: «I'll take a PR». PR #1483 (2025-03) **не змерджено** станом на 2026-10.
- **Обхідний шлях перевірено** (`exp/lib/models.dart`: `Animal`, `Cat`, `Dog`, `UnknownAnimal`, `Zoo`). `sealed class Animal` з ручним `factory Animal.fromJson` (switch за дискримінатором) і абстрактним `toJson()`. Варіанти — `@JsonSerializable final class Cat extends Animal`. Поля `List<Animal>` і `Animal?` в іншому `@JsonSerializable`-класі генеруються коректно, невідомий варіант зберігає сирий JSON, exhaustive switch працює.
- **`additionalProperties` разом з відомими полями** (захопити «решту» ключів) нативно не виражається. Можна лише хаком `readValue` + ручним `toJson`.

### A.7. Що json_serializable **не може** виразити з вимог і як це обійти

| Вимога | json_serializable | Обхід |
|---|---|---|
| R6.5 шлях у JSON | лише клас + ключ, checked ≈25× повільніше | власні декодери зі шляхом (рантайм-хелпери, ~150 LOC) |
| R8.1 сире значення enum | губиться | sealed open-enum з `fromJson`/`toJson`, написаний генератором |
| R8.2 не надсилати unknown | `$unknown` надсилається | типізація конструктора, див. E.3 |
| R9 union з unknown | немає (#1342) | sealed-ієрархія з ручним `fromJson` |
| R9.3 `string \| number` | немає | sealed wrapper або extension type |
| `additionalProperties` + поля | хак `readValue` | ручний код |
| R13.1 / R15.4 детермінізм | вихід залежить від версії json_serializable у користувача (6.9 змінив стиль `toJson`, 6.10 почав використовувати null-aware elements, які потребують Dart 3.8) | генерувати код самому або пінити версію |

Що json_serializable **закриває**: прості об'єктні моделі, R6.1, R6.4, R7 (з 6.14), ігнорування зайвих полів, конвертери.

### A.8. build_runner: стан на жовтень 2026

**Продуктивність помітно покращилася** (`build_runner-2.16.2/CHANGELOG.md`):
- 2.5: перший раунд оптимізації великих збірок.
- 2.10: AOT-компіляція білдерів (спершу за прапорцем).
- 2.13: прискорення від 1,4× до 4× (dart-lang/build PR #4405).
- 2.14: ще 2× для інкрементальних збірок, AOT за замовчуванням, команда `stop`, блокування.
- 2.15: менше пам'яті, `--low-resources-mode` прибрано.
- 2.16: нова поведінка «завжди виправляти змінені згенеровані файли» і режим **`--only-check`** для CI.

**Замір** (`exp/lib/gen/`, 600 `@JsonSerializable(checked: true)` класів × 8 полів, 22,6 тис. рядків `.g.dart`):

| Сценарій | Час |
|---|---|
| Холодний старт: AOT-компіляція білдерів | **12 с** |
| Генерація 600 моделей | 1–2 с |
| Інкрементальна збірка після зміни одного файлу | 0,8 с |

**Що лишається проблемою:**
1. Окремий крок у пайплайні. На чистому CI кожен прогін платить ~12 с за компіляцію білдерів.
2. **Lock-step залежностей від `analyzer`.** analyzer випустив 10.0 → 14.0 за січень–червень 2026. Поточні обмеження: json_serializable 6.14.1 `>=10 <15`, retrofit_generator `>=13.3 <15`, freezed 4.0.2 `>=14 <15` (і Dart ≥3.13), build_runner 2.16.2 `>=14.3 <15` (і Dart ≥3.11). Будь-який генератор, що відстає, блокує оновлення в користувача.
3. Вихід залежить від версії генератора на машині користувача (див. A.7).

**Macros і augmentations:**
- Macros **скасовано** 2025-01-29 («we’ve made the difficult decision to stop our work on macros»). У тому ж пості: «We also plan to ship augmentations», «We’ve already identified improvements for build_runner».
- Roadmap Flutter & Dart 2026 (2026-02-24): «we plan to ship Primary Constructors … and Augmentations to simplify code generation», «We will continue to focus on improving build_runner».
- Факт на 2026-10-11: primary constructors **вийшли** в Dart 3.13 (2026-08-12). Augmentations **не вийшли**: специфікація лежить у `dart-lang/language/working/augmentations/` (не в `accepted/`), «Experiment flag: augmentations», остання правка 2026-10-06. У CHANGELOG SDK про них нічого немає.
- Навіть коли augmentations вийдуть, вони лише приберуть `part` / `_$`-бойлерплейт. Запускати build_runner усе одно доведеться. **Альтернативного офіційного codegen-механізму немає і найближчим часом не очікується.**

**Наслідок для рішення 1.** Якщо генератор віддає анотований код, користувач **мусить** запускати build_runner, бо `.g.dart` від json_serializable інакше не з'явиться. Альтернатива — генератор сам емітить еквівалентний код. Тоді в користувача лишаються тільки runtime-залежності (`dio`, `meta`, наш runtime-пакет).

---

## B. Dio 5.11.x

### B.1. Per-call параметри (→ R10.5)

- `Options.extra` / `RequestOptions.extra` (`Map<String, dynamic>`) зливаються з `BaseOptions.extra` в `Options.compose` (`dio-5.11.1/lib/src/options.dart:339`). Типізований об'єкт, напр. `OperationInfo`, можна класти без серіалізації. Перевірено: інтерсептор бачить `extra['operationId']` (`exp/bin/dio_flow.dart`).
- `CancelToken`, `onSendProgress`, `onReceiveProgress` — параметри `dio.request(...)`.
- **Пастка R10.1.** `dio.fetch(RequestOptions(...))` з «голим» `RequestOptions` **не** зливається з `BaseOptions` (baseUrl, headers, timeouts). Злиття робить тільки `dio.request()`, через `Options.compose(dio.options, …)` (`dio_mixin.dart`, ~рядок 396). retrofit теж явно викликає `.compose(_dio.options, …)`. **Генерований код має викликати `_dio.request<…>(path, options: Options(...))`.**
- **Пастка `fetch<T>`.** Якщо `T != dynamic` і тип відповіді не `bytes`/`stream`, Dio примусово ставить `responseType = json` (або `plain`, якщо `T == String`) (`dio_mixin.dart:418-427`). Для тексту треба `request<String>`, для бінарного — `request<List<int>>` + `bytes`, для стріму — `request<ResponseBody>` + `stream`, для JSON — `request<Object?>`.
- **Толерантність до дефектів (R0.2).** `FusedTransformer` парсить JSON лише коли content-type дорівнює `application/json`, `text/json` або `*+json`. Інакше `data` буде `String` (`transformers/fused_transformer.dart`). Генерований код має робити `jsonDecode`, якщо очікує JSON, а отримав рядок.

### B.2. `validateStatus` і потік помилок (→ R10.2)

`_defaultValidateStatus` пропускає статуси 200–299. Інакше кидається `DioException.badResponse`, і він **проходить через `onError` інтерсепторів**. Тіло вже розпарсене, бо `receiveDataWhenStatusError` за замовчуванням true. Перевірено:
```
onError type=DioExceptionType.badResponse status=404 dataType=_Map<String, dynamic> data={code: NOT_FOUND, …}
```
Підхід tonik `validateStatus: (_) => true` вимикає `onError` для HTTP-помилок, тому R10.2 і порушено. Рекомендований потік:
1. залишити `validateStatus` користувача;
2. зловити `DioException`;
3. якщо `type == badResponse`, декодувати `e.response!.data` за задокументованим статусом.

Важливо: інтерсептор може зробити `resolve(...)` помилки у `Response` з не-2xx статусом, наприклад повернути кеш на 503. Тому генерований метод має завжди розбирати `statusCode` через switch, а не припускати 2xx.

### B.3. `DioExceptionType` (→ R11.7)

`dio_exception.dart:15` у 5.11.1 містить **9** значень, а не 8: `connectionTimeout`, `sendTimeout`, `receiveTimeout`, `badCertificate`, `badResponse`, `cancel`, `connectionError`, `unknown`, **`transformTimeout`** (додано в 5.10.0). Мапінг для R11.7:
- `badResponse` → HTTP-помилка (задокументована або ні);
- `cancel` → окремий варіант «скасовано» (це не збій);
- решта → транспортний збій.

Перевірено: відмова з'єднання дає `connectionError`, скасування — `cancel`.

### B.4. `ListFormat` і стилі OAS (→ R10.3)

Перевірено фактичним URL (`exp/bin/dio_flow.dart`):
```
multi=a&multi=b&csv=a,b+c&pipes=a%7Cb&ssv=a%20b&deep%5Bcolor%5D=red&deep%5Bsize%5D%5Bw%5D=1&reserved=a%2Fb%3Fc%26d
```

| OAS style / explode | Dio | Примітка |
|---|---|---|
| form, explode=true, масив | `ListFormat.multi` (default) | ✓ |
| form, explode=false, масив | `ListParam(v, ListFormat.csv)` | ✓ |
| spaceDelimited | `ssv` → `%20` | ✓ |
| pipeDelimited | `pipes` → `%7C` | ✓ (`\|` закодовано) |
| deepObject | вкладений `Map` у `queryParameters` → `k%5Bp%5D=v` | ✓ семантично; дужки percent-encoded |
| form, explode=true, **об'єкт** | ✗ | генератор розплющує в ключі верхнього рівня |
| form, explode=false, об'єкт (`k,v,k2,v2`) | ✗ | генератор складає рядок |
| `allowReserved: true` | ✗ | Dio завжди кодує |
| path: simple / label / matrix | ✗ | Dio не має шаблонів шляху, генератор кодує сам (`Uri.encodeComponent`) |
| header simple, cookie | ✗ | генератор; cookie через заголовок `Cookie` (врахувати конфлікт з `dio_cookie_manager`) |

Курйоз: `ListFormat.tsv` використовує розділювач `r'\t'`, тобто два символи `\` і `t` (`utils.dart:136`). В OAS 3 tsv немає, тож це неважливо.

### B.5. Multipart (→ R10.4)

- `MultipartFile.fromBytes / fromString / fromStream(…, filename:, contentType: DioMediaType(...), headers:)` задає content-type кожної частини. `FormData.fields` (`MapEntry<String,String>`) content-type не мають. JSON-частину треба передавати як `MultipartFile.fromString(jsonEncode(x), contentType: DioMediaType('application','json'))`.
- `MultipartFile.fromFile` працює лише з `dart:io`. Для чистого Dart і web генерований API має приймати байти або стрім.
- `MultipartFile` одноразовий. Для повторів в інтерсепторах потрібен `FormData.clone()` (5.10 виправив втрату `boundaryName`).

### B.6. Стрімінг і SSE (→ R12, web)

- **VM / mobile.** `ResponseType.stream` → `ResponseBody.stream`, чанки приходять у міру надходження (перевірено на локальному сервері). У 5.11.1 виправлено backpressure, раніше довгі стріми могли призвести до OOM.
- **Web, стандартний `BrowserHttpClientAdapter`, стрімінгу немає.** XHR з `responseType = 'arraybuffer'`, а `ResponseBody.fromBytes` створюється лише в `xhr.onLoad` (`dio_web_adapter-2.2.2/lib/src/adapter_impl.dart:54,119`). SSE прийде одним шматком після закриття з'єднання. Issues cfug/dio#1859 «ServerSendEvent support for Flutter Web» і #1740 «Use modern Fetch API with Dio on Web» **відкриті** з 2023.
- **Як обійти, не відмовляючись від Dio.** `dio_compatibility_layer` (`ConversionLayerAdapter(http.Client)`) + `package:http` ≥1.3, де `BrowserClient` перейшов на Fetch API і стрімить відповідь через `ReadableStream`. Підходить і `fetch_client`. Обмеження адаптера (переглянуто код): параметр `cancelFuture` **ігнорується**, тобто fetch не скасовується, Dio лише відкидає результат. Прогресу upload немає. На web тіло запиту буферизується.
- `EventSource` браузера не годиться: лише GET і без власних заголовків (R12.1 POST, R12.4 інтерсептори з auth).
- **Парсер SSE.** На pub є лише маленькі пакети без аудиторії (`sse_parser` 0.1.0). Краще ~150 LOC власного WHATWG-парсера в runtime-пакеті.

### B.7. Як retrofit_generator розв'язує ці задачі і де він обмежений

Огляд анотацій (`retrofit-4.10.0/lib/{http,dio,call_adapter,error_logger}.dart`) і генератора (`retrofit_generator-10.2.11/lib/src/generator.dart`):

| Тема | retrofit | Обмеження щодо наших вимог |
|---|---|---|
| Per-call extras | `@Extra({...})` статично, `@Extras()` параметром, `@TypedExtras` | operationId автоматично не ставить |
| Options | `@DioOptions() Options` | |
| Cancel / progress | `@CancelRequest`, `@SendProgress`, `@ReceiveProgress` | ✓ |
| Multipart | `@Part(contentType:)` статично, `@PartMap` у рантаймі | ✓ |
| Query | `@Query`, `@Queries` (Map; Dio дає `a[b]=c`) | стилі OAS не розрізняє |
| Помилки | `DioException` пролітає як є; `ParseErrorLogger` для помилок декодування; `CallAdapter` для `Result` | **типізованих тіл помилок немає**: issue #168 «Add error handler» відкрите з 2020 |
| Кілька 2xx | один `T` + `HttpResponse<T>` | немає варіантів за статусом |
| Стріми | лише `Stream<Uint8List>` / `Stream<String>` з `ResponseType.stream` | **SSE немає**: #525 закрито як not planned |
| Запит | `Options(...).compose(_dio.options, …)` → `_dio.fetch` | |
| Codegen | build_runner + code_builder, усередині змішаний із сирими `Code('…')` | |

---

## C. Можливості мови Dart для генерованого API

### C.1. Sealed + exhaustive switch (R9, R11)

Працює як треба: пропущений варіант дає помилку компіляції `non_exhaustive_switch_expression` (`exp/bin/exhaust.dart`). Є протиріччя з R14.2: **додавання нового варіанта або значення ламає exhaustive switch у вихідному коді споживача** (аналога `@unknown default` зі Swift у Dart немає). Скомпільований код (старий клієнт проти нового сервера) не ламається, бо приходить `Unknown`. Звіт R14.1 має позначати такі зміни як «source-breaking для exhaustive switch».

### C.2. Extension types для open enum (`extension type const Status._(String value)`)

Перевірено (`exp/lib/models.dart` `Color`, `exp/bin/exhaust.dart`):
- **Exhaustiveness втрачається**: `switch` по `Color` з усіма константами дає `non_exhaustive_switch_expression … doesn't match 'String()'`, тож потрібен `_`.
- **Runtime-перевірок немає**: `("x" as Object) is Color` дорівнює `true`, а `'hacked' as Color` проходить і надсилається як `{"color":"hacked"}`. **R8.2 заблокувати неможливо.**
- Без `implements Object` тип вважається потенційно nullable: `Object o = p.color` не компілюється.
- Плюси: нуль алокацій, `jsonEncode` працює напряму (representation є `String`), json_serializable підхоплює `fromJson`/`toJson`.
- dart.dev прямо називає їх «an _unsafe_ abstraction» (https://dart.dev/language/extension-types).

**Вердикт:** для R8.1/R8.2 не годиться. Підходить для R6.2 `JsonValue` і для дешевих id-обгорток.

### C.3. Рекомендована форма open enum: sealed + enum + unknown

Перевірено (`exp/lib/open_enum.dart`, `open_enum2.dart`, `shapes.dart`, `exhaust2.dart`):
- `enum XKnown implements X` всередині `sealed class X` разом з `final class XUnknown` дає **повну exhaustiveness**: пропущене відоме значення — помилка компіляції.
- Статичні аліаси `static const shipped = XKnown.shipped;` на sealed-класі **зберігають exhaustiveness**, дозволяють писати `X.shipped` і dot shorthand `.shipped` у контексті `X` (Dart 3.10).
- Параметр типу `XKnown` + поле типу `X` (`Pet({required PetStatusKnown this.status})`) дає **R8.2 на етапі компіляції**: `Pet(status: decoded.status)` не компілюється, `argument_type_not_assignable`. Декодований об'єкт тримає `XUnknown` (R8.1).

### C.4. Records, модифікатори класів, `meta`

- **Records** підходять для внутрішніх хелперів. Для публічного API не годяться: додавання поля змінює тип (breaking). Кілька 2xx краще виражати sealed-класом.
- **`abstract interface class`** з `factory PetsApi(Dio) = _PetsApiImpl` мокається mocktail-ом без кодогенерації (`exp/test/mock_test.dart` пройшов). mockito для null-safe моків потребує build_runner, тож для R10.7 документувати mocktail або fakes.
- **`final class`** для моделей: користувачі не можуть розширювати або імплементувати модель, тому додавання полів і методів не ламає їхній код (R14.2).
- **Еволюція інтерфейсу.** Новий named-параметр в абстрактному методі ламає ручні fakes (`implements`). Тому всі per-call опції варто зібрати в один об'єкт `ApiCallOptions`: нові поля в ньому нічого не ламають.
- `@immutable` / `meta` безкоштовні: `meta` уже транзитивна залежність `dio`.
- **Dot shorthands (3.10)** різко покращують ергономіку споживача: `UpdatePet(name: .value('Rex'), tag: .nullValue())` компілюється з контекстом `Patch<String>?` (перевірено в `exp/bin/shorthand.dart`). Генерованому коду вони не потрібні.
- **Primary constructors (3.13)** у генерованому коді краще не використовувати, щоб не вимагати від користувачів Dart ≥3.13. Рекомендований baseline згенерованого коду — **мова 3.8** (null-aware elements, tall-style formatter, той самий мінімум, що в json_serializable ≥6.10). Зробити налаштовуваним.

### C.5. Tri-state (R7)

| Патерн | Конструктор | Читання | `toJson` пропускає absent | Сумісність з json_serializable |
|---|---|---|---|---|
| **`Patch<T>?`** (null = absent; `Patch.value(x)` / `Patch.nullValue()`) | `UpdatePet(name: .value('Rex'))` | `switch (p) { null => …, PatchNull() => …, PatchValue(:final value) => … }` — exhaustive (перевірено) | так, null-aware entry | **так, 6.14 `explicitJsonNullWhenNonNullField`** (перевірено) |
| drift `Value<T>` (`Value.absent()` за замовчуванням, `Value(null)`) | `name: Value('Rex')` | `v.present ? v.value : …` | лише ручний `toJson` | ні |
| freezed sentinel (`Object? x = freezed`) | — | — | — | лише для `copyWith`, тип усередині втрачається |
| `Optional<T>` / Kotlin-подібні | аналогічно drift | | | ні |

**Рекомендація: `Patch<T>?`.** Це узгоджується з R7.3: скрізь у моделі `null` означає «не надсилати». Додаткового стану `absent` у звичайних optional-полях немає. Мінус — `copyWith` не розрізняє «не змінювати» і «зробити absent». Для тіл запитів `copyWith` рідко потрібен (R6.6 SHOULD), а за потреби підійде sentinel-трюк, як у freezed.

### C.6. Довільний JSON (R6.2)

| Варіант | Плюси | Мінуси |
|---|---|---|
| `Object?` | нуль витрат | майже `dynamic`; вимога каже «окремий тип» |
| **`extension type JsonValue(Object? raw)`** | окремий тип, нуль алокацій, `jsonEncode` працює, хелпери `asMap`/`asList`/`asString` | захисту немає, але тут він і не потрібен |
| sealed `JsonNull/Bool/Num/String/Array/Object` (прецедент: `built_value` `JsonObject` — Bool/List/Map/Num/String, без Null) | exhaustive switch | глибока конвертація в обидва боки, алокації |

**Рекомендація:** extension type `JsonValue` у runtime-пакеті; для розбору — pattern matching по `raw`. Готового популярного пакета немає: пошук на pub.dev нічого релевантного не знайшов.

---

## D. Тулчейн кодогенерації

### D.1. `code_builder` vs шаблони vs власні емітери

| | code_builder 4.12 | mustache (`mustache_template` 2.0.6) | Власний емітер (string builder + import manager) |
|---|---|---|---|
| Синтаксична коректність | висока (AST-специфікації) | низька | середня; страхує `DartFormatter`, бо він кидає виняток на синтаксичній помилці |
| Детермінізм (R13.1) | так (`DartEmitter(orderDirectives: true)`, `Allocator`) | так, але пробіли й екранування на ручному контролі | так, якщо сортувати імпорти, не ітерувати `HashSet` і передавати `lineEnding: '\n'` |
| Сучасний синтаксис | 4.12 (2026-08) додав `SwitchExpression`, `Pattern`, control flow; sealed і extension types підтримуються | будь-який | будь-який |
| Читабельність генератора | багатослівно | шаблон читається легко, логіка — ні | читається як код, що генерується |
| Хто так робить | retrofit_generator і tonik_generate, але обидва змішують із сирими `Code('…')` | openapi-generator (Java) | json_serializable (StringBuffer), freezed (`analyzer_buffer`) |
| Залежності | `built_value`, `built_collection` (лише в генераторі) | мінімальні | жодних |

**Рекомендація:** власний типізований емітер (DartWriter з алокатором імпортів, екрануванням ідентифікаторів і doc-коментарями) або гібрид, де code_builder відповідає за декларації та імпорти, а тіла методів збираються рядками. Mustache не брати: логіку екранування Dart-імен і стилів не винести в logic-less шаблон, а шаблони як точка розширення стають нестабільним публічним контрактом (див. E, рішення 6).

### D.2. `dart_style` і «дрейф форматера»

API: `DartFormatter(languageVersion: Version, pageWidth:, trailingCommas: TrailingCommas.automate|preserve, lineEnding:)`. `languageVersion` обов'язковий з 3.x.

**Факти:**
- Стиль залежить від мовної версії файлу: ≤3.6 — старий short style, ≥3.7 — tall style. Є language-versioned зміни в 3.8 і 3.13 (CHANGELOG SDK).
- **3.13 додав «Separate imports into sections».** Перевірено (`exp/bin/fmt.dart`): неупорядковані імпорти дають різний вихід для 3.12 і 3.13. **Якщо емітувати імпорти вже згрупованими** (`dart:` / порожній рядок / `package:` / порожній рядок / відносні), вихід 3.12 і 3.13 збігається байт-у-байт (`exp/bin/fmt2.dart`).
- **Навіть patch-релізи змінюють стиль без прив'язки до мовної версії**: dart_style 3.1.13 почав додавати trailing comma в enum з primary constructor, і це пішло в patch SDK.
- `dart format` у SDK 3.13.1 — це `dart_style 3.1.10 supporting … 2.12 through 3.13`, а на pub уже 3.1.13. Отже, «той самий» формат у генератора і в користувача може відрізнятися.
- Користувач може ввімкнути `formatter: trailing_commas: preserve` або `page_width` в `analysis_options.yaml`. Перевірено: вихід `automate` стабільний при повторному форматуванні з `preserve`.
- Для генераторів є маркер `// dart format width=N` на початку файлу («mainly for code generators»).
- `// dart format off` **без парного `on`**: у 3.12 і 3.13 решта файлу лишається недоторканою (`exp/bin/fmt3.dart`). Це **недокументована** поведінка: CHANGELOG описує лише пари off/on.
- `DartFormatter.lineEnding` з 3.1.13 виводиться з вхідного коду. Для детермінізму треба явно передавати `'\n'`.

**Рекомендації:**
1. Пінити `dart_style` у генераторі. `languageVersion` брати з `environment.sdk` цільового пакета, з override у конфігу.
2. Писати `// dart format width=<config>` у кожному файлі (R13.2).
3. Імпорти емітувати канонічно згрупованими й відсортованими.
4. Передавати `lineEnding: '\n'`.
5. Golden-тести: перевіряти ідемпотентність форматування на мінімальній і максимальній підтримуваних мовних версіях (напр., 3.8 і 3.13), а в CI-матриці з найстарішим і найновішим SDK запускати `dart format --set-exit-if-changed` на згенерованому.
6. Опційно, як запобіжник: заголовок `// dart format off`. Ризик у тому, що поведінка недокументована.

### D.3. `analyzer` для тестів (R15.3)

`analyzer` змінює мажорну версію в середньому кожні 1–2 місяці (10.0.0 2026-01-07 … 14.0.0 2026-06-18). `dart_style` сам залежить від `analyzer >=13.1.0 <15.0.0`. Що з цього випливає:
- **Ядро генератора не повинно залежати від analyzer API.** Для «компілюється і проходить аналізатор» запускати `dart analyze` як підпроцес на fixture-пакетах (Petstore, Stripe, GitHub, OpenAI, K8s). Інтерфейс CLI стабільний.
- `analyzer` як бібліотеку (`AnalysisContextCollection` → `getErrors`) тримати лише в `dev_dependencies` тестового пакета, якщо потрібна in-process швидкість.
- **Дистрибуція.** Генератор варто поширювати як ізольований інструмент: `dart install` (Dart 3.10+), `dart run <pkg>@<version>` (3.12+) або `dart pub global activate`, а не як `dev_dependency`. Так його `analyzer`/`dart_style` не конфліктують із freezed, riverpod_generator тощо в проєкті користувача, а версія запінена (R13.1, R15.4).

---

## E. Рекомендації за відкритими рішеннями

### Ключове питання: чи можна виконати R6.5, R7, R8, R9, «використовуючи json_serializable»?

**Коротко: лише частково. json_serializable добре покриває прості об'єктні моделі; union, open enum і помилки зі шляхом у будь-якому разі доведеться генерувати руками.**

| Вимога | json_serializable 6.14 | Деталі |
|---|---|---|
| R7 tri-state | ✅ | `explicitJsonNullWhenNonNullField` + `Patch<T>?` (перевірено) |
| R6.1 матриця | ✅ | `required`, `disallowNullValue`, `includeIfNull` |
| R6.4 дженерики | ✅ | `genericArgumentFactories` |
| R6.5 зрозумілі помилки | ⚠️ | клас + ключ без шляху; checked ≈25× повільніше |
| R8.1 / R8.2 | ❌ | сире значення губиться, `$unknown` надсилається |
| R9 union з unknown | ❌ | #1342 відкрите з 2023; ручний sealed-тип з `fromJson`/`toJson` підхоплюється як поле (перевірено) |
| R13.1 / R15.4 детермінізм | ❌ | вихід генерується на машині користувача його версією json_serializable |

Генератору все одно треба вручну емітувати найскладнішу частину (union, enum, помилки, параметри, SSE). Емітувати поверх цього ще й прості `fromJson`/`toJson` коштує мало: це найпростіший емітер, ~300–500 LOC. Натомість зникає build_runner разом з усіма проблемами з A.8.

### Рішення 1. Тип виходу

**Рекомендація: готовий код без build_runner** (і єдиний варіант у v1). Build_runner-інтеграцію (R15.1) зробити тонким опційним `Builder`, який викликає той самий програмний API (spec → файли, `build_to: source`).

- **За:** R13.1 і R15.4 (вихід залежить лише від версії генератора); R15.3 (golden = пряме порівняння); немає 12-секундної AOT-компіляції на CI; немає lock-step по `analyzer`; користувач не прив'язаний до SDK, якого вимагають freezed 4 (≥3.13) або build_runner 2.16 (≥3.11). Macros скасовано, augmentations не вийшли, тож «нового шляху» найближчим часом не буде.
- **Проти:** більше коду в генераторі; розробники звикли бачити `@JsonSerializable` у моделях.
- **Пом'якшення:** згенеровані моделі дотримуються **контракту json_serializable** (`factory X.fromJson(Map<String, dynamic>)`, `Map<String, dynamic> toJson()`), тому вкладаються в `@JsonSerializable`-класи користувача і навпаки (перевірено в A.3 і A.6). Опційний режим «моделі як `@JsonSerializable`» можна додати пізніше для простих об'єктних схем.

### Рішення 2. Серіалізація

**Рекомендація: власна емісія (de)serialization з мінімальними runtime-хелперами (`JsonObjectReader`, `$list`, `$map`, декодери примітивів і форматів, `JsonDecodeException` зі шляхом).** Публічні сигнатури сумісні з json_serializable.

- **json_serializable як рушій** підходить лише для простих моделей (див. таблицю вище).
- **freezed:** важкий, analyzer lock-step, 4.x потребує Dart ≥3.13. Union через `unionKey` / `fallbackUnion` є, але сирого JSON у fallback немає. Плюс знову build_runner.
- **dart_mappable:** runtime-залежність (`type_plus`) і **глобальний `MapperContainer.globals`**, що суперечить R4.3 («жодних глобальних побічних ефектів»). Плюс build_runner.
- **Продуктивність:** прототип зі шляхами ≈2,2× повільніший за unchecked json_serializable і ≈10× швидший за checked. Якщо потрібен нуль накладних витрат на успішному шляху, можна робити двофазно: швидкий декод, а при помилці — повторний обхід генерованим валідатором, щоб отримати шлях.

### Рішення 3. HTTP-шар

**Рекомендація: лише Dio. Транспорт змінюється через `HttpClientAdapter` самого Dio, власної абстракції не робити.**
- Dio уже є абстракцією над транспортом: `IOHttpClientAdapter`, `BrowserHttpClientAdapter`, а через `dio_compatibility_layer` — будь-який `package:http` клієнт (`cronet_http`, `cupertino_http`, `BrowserClient`/`FetchClient` зі стрімінгом).
- Власна абстракція продублювала б інтерсептори, `Options` і `CancelToken` і зламала б R10.1, R10.2, R12.4 («той самий клієнт користувача»).
- Звузити поверхню Dio в генерованому коді до `Dio.request`, `Options`, `Response`, `DioException`, `CancelToken`, `FormData`, `MultipartFile`, `ListParam`, `ResponseBody`. Тоді абстракція, якщо колись знадобиться, буде механічною зміною.
- **Web + SSE:** у документації дати рецепт `ConversionLayerAdapter(BrowserClient())` (умовний імпорт) і чесно описати обмеження: скасування лише на рівні Dio, без upload-прогресу.

### Рішення 4. Модель помилок за замовчуванням

**Рекомендація: виняток за замовчуванням (sealed `ApiException<E>`), `Result` — як згенероване розширення поверх того самого методу.** У режимі «обидва» інтерфейс має **один** метод на операцію, а мокати треба лише його (R10.7).

| | Виняток | `Result<T, E>` |
|---|---|---|
| Ідіоматичність Dart/Flutter | висока (`Future` уже несе помилку; Riverpod `AsyncValue.guard` і Bloc орієнтовані на винятки) | потребує unwrap всюди |
| Видимість у сигнатурі | лише doc-коментар `/// Throws [ApiException<GetPetError>]` | у типі |
| Примус до обробки | немає | є |
| R10.2 | природно: `DioException` уже пройшов `onError` | так само, лише обгортка |
| Exhaustiveness | `on ApiException<GetPetError> catch (e) { switch (e) … }` | `switch (result)` |

### Рішення 5. Парсер

**Рекомендація: власний парсер і власна IR, ізольовані шарами:**

сирий документ з позиціями (`package:yaml` дає `SourceSpan`; плюс JSON pointer) → нормалізатор (R2.1) → override-и (R3) → розв'язана IR → Dart-мапінг (імена, типи) → емітер.

Пакети `tonik_core` і `tonik_parse` мають версію 0.10.0 (pre-1.0, API нестабільний), до того ж `tonik_core` залежить від runtime-пакета `tonik_util`, тобто модель зв'язана з рантаймом. До того ж R2 і R3 (діагностика з pointer-ами, override-и, baseline) вимагають повного контролю над моделлю. Детальніший аналіз парсерів — поза цим документом.

### Рішення 6. Розширюваність

**Рекомендація: конфіг і override-и (R3) плюс програмний API з типізованими хуками над IR. Шаблонів не робити.**

Приклади хуків: `TypeMapping` (Decimal, Date, BigInt — кодеки для формату), іменування, фільтри. Шаблони роблять кожну зміну виходу або структури шаблону breaking (R15.4), ламають гарантії лінтів (R13.2) і детермінізм, а користувачі форкають їх. Хуки над IR детерміновані, версіонуються разом з API і тестуються.

### Рішення 7. Представлення tri-state і сирого enum

- **Tri-state:** `Patch<T>?` (див. C.5 і ескіз E.2).
- **Enum:** sealed `X` + `enum XKnown implements X` + `final class XUnknown` з приватним конструктором і статичними аліасами (див. C.3 і ескіз E.3). Параметри операцій і публічні конструктори моделей приймають `XKnown`, поля моделей мають тип `X`.
- **Extension type відхилено** (C.2): R8.2 не досягається, exhaustiveness втрачається.
- **Компроміс з R14.2:** нове значення ламає exhaustive switch у споживача на рівні вихідного коду. Для тих, хто це не приймає, дати опцію конфігу «не робити known-значення exhaustible» (звичайний клас зі статичними константами).

### E.1. Мінімальний runtime-пакет (R13.3)

Залежності: **`dio` + `meta`** (`meta` уже транзитивна від dio, тож нових транзитивних залежностей немає). Окреме semver-версіонування; згенерований код перевіряє сумісний діапазон.

```
errors.dart    sealed ApiException<E>: ApiHttpException<E> (status, headers, typed body),
               ApiUndocumentedStatusException<E> (status, raw body), ApiTransportException<E>
               (TransportFailure kind ← DioExceptionType), ApiCancelledException<E>,
               ApiDecodeException<E>
result.dart    sealed ApiResult<T,E>: ApiOk / ApiErr;  Future<ApiResult<T,E>> runAsResult<T,E>(…)
response.dart  ApiResponse<T> (data, statusCode, headers: Map<String,List<String>>, raw Response?)
               — конструктор без Dio, щоб мокати
call.dart      ApiCallOptions (cancelToken, headers, extra, onSend/ReceiveProgress, timeouts)
               OperationInfo (operationId, method, pathTemplate, tags, security) + OperationInfo.of(RequestOptions)
json.dart      JsonDecodeException (schema, pointer, message, value), JsonObjectReader (ext type),
               $list/$map/$int/$num/$string/$bool/$dateTime/$date/$uuid/$bytes/$int64, JsonValue (ext type)
patch.dart     sealed Patch<T>: PatchValue / PatchNull
params.dart    кодери стилів OAS: path (simple/label/matrix), query (form/explode, space/pipeDelimited,
               deepObject), header (simple), cookie, form-urlencoded; хелпер multipart-частин
sse.dart       SseEvent, SseDecoder (StreamTransformer<List<int>, SseEvent>, WHATWG), reconnect + Last-Event-ID
```

### E.2. Ескіз: поле tri-state

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
  final Patch<String>? name;       // tri-state: null = відсутнє
  final Patch<String>? tag;
  final String? nickname;          // один стан: null = не надсилати (R7.3)
  Map<String, Object?> toJson() => {
    if (name case final v?) 'name': v.toJson((s) => s),
    if (tag case final v?) 'tag': v.toJson((s) => s),
    'nickname': ?nickname,
  };
}
// використання (Dart ≥3.10):
// api.updatePet(id: 1, body: UpdatePetRequest(name: .value('Rex'), tag: .nullValue()));
// → {"name":"Rex","tag":null}
```

### E.3. Ескіз: open enum (R8.1 + R8.2)

```dart
sealed class PetStatus {
  static const available = PetStatusKnown.available;   // аліаси: PetStatus.available, `.available`
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
  const PetStatusUnknown._(this.value);               // створити може лише декодер
  @override final String value;                        // сире значення збережене (R8.1)
  @override String toJson() => value;
  @override bool operator ==(Object o) => o is PetStatusUnknown && o.value == value;
  @override int get hashCode => value.hashCode;
}

final class Pet {
  Pet({required this.name, required PetStatusKnown this.status});  // R8.2: лише відомі значення
  Pet._decoded({required this.name, required this.status});
  final String name;
  final PetStatus status;                                          // може бути PetStatusUnknown
  // query/path-параметри операцій теж мають тип PetStatusKnown
}
// switch (pet.status) { PetStatus.available => …, PetStatus.sold => …, PetStatusUnknown(:final value) => … }
```

### E.4. Ескіз: union з невідомим варіантом (R9.1)

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
  final String? discriminator;        // null, якщо дискримінатора немає в JSON
  final Map<String, Object?> json;    // сирий JSON (R9.1)
  @override Map<String, Object?> toJson() => json;
}
```

### E.5. Ескіз: типізована помилка і Result (R11)

```dart
// runtime
sealed class ApiException<E> implements Exception { const ApiException(); }
final class ApiHttpException<E> extends ApiException<E> {        // задокументований 4xx/5xx/default
  const ApiHttpException(this.statusCode, this.body, this.headers, this.cause);
  final int statusCode; final E body; final Map<String, List<String>> headers;
  final DioException cause;                                      // уже пройшов onError (R10.2)
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

// generated, per operation: спільна схема Error генерується один раз (R11.4)
sealed class GetPetByIdError { const GetPetByIdError(); }
final class GetPetByIdError404 extends GetPetByIdError { const GetPetByIdError404(this.body); final NotFound body; }
final class GetPetByIdErrorDefault extends GetPetByIdError {
  const GetPetByIdErrorDefault(this.statusCode, this.body); final int statusCode; final ApiError body;
}
```

### E.6. Ескіз: абстрактний API-клас (R10.1, R10.5, R10.7)

```dart
abstract interface class PetsApi {
  factory PetsApi(Dio dio) = _PetsApi;          // Dio користувача; baseUrl не чіпаємо (R10.1)

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
      res = await _dio.request<Object?>(                         // request(), а не fetch(): зливає BaseOptions
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
    return switch (res.statusCode) {                             // інтерсептор міг resolve-нути не-2xx
      200 => decodeResponse(res, (body) => Pet.fromJson(asJsonObject(body))),
      _ => throw ApiUndocumentedStatusException<GetPetByIdError>(res.statusCode, res.data, null),
    };
  }
}

// режим «обидва» (R11.2): Result без зміни інтерфейсу
extension PetsApiResults on PetsApi {
  Future<ApiResult<Pet, GetPetByIdError>> getPetByIdResult({required int petId, ApiCallOptions? options}) =>
      runAsResult(() => getPetById(petId: petId, options: options));
}

// тест без кодогенерації (R10.7, перевірено mocktail)
// class MockPetsApi extends Mock implements PetsApi {}
```

---

## Джерела

**pub.dev (версії та дати перевірено через `https://pub.dev/api/packages/<name>` 2026-10-11)**
- https://pub.dev/packages/json_serializable (6.14.1) · https://pub.dev/packages/json_annotation (4.12.0)
- https://pub.dev/packages/build_runner (2.16.2) · https://pub.dev/packages/dart_style (3.1.13) · https://pub.dev/packages/code_builder (4.12.0) · https://pub.dev/packages/analyzer (14.5.0)
- https://pub.dev/packages/dio (5.11.1) · https://pub.dev/packages/dio_web_adapter (2.2.2) · https://pub.dev/packages/dio_compatibility_layer (0.1.1) · https://pub.dev/packages/http (1.6.0) · https://pub.dev/packages/fetch_client (1.2.1)
- https://pub.dev/packages/retrofit (4.10.0) · https://pub.dev/packages/retrofit_generator (10.2.11) · https://pub.dev/packages/freezed (4.0.2) · https://pub.dev/packages/dart_mappable (4.10.0) · https://pub.dev/packages/tonik (0.10.0) · https://pub.dev/packages/mocktail · https://pub.dev/packages/sse_parser
- Dart SDK latest stable: https://storage.googleapis.com/dart-archive/channels/stable/release/latest/VERSION (3.13.5, 2026-09-29)

**Вихідний код (локальний pub-cache, ті самі версії)**
- `~/.pub-cache/hosted/pub.dev/json_annotation-4.12.0/lib/src/{checked_helpers,enum_helpers,allowed_keys_helpers,json_key,json_serializable}.dart`, `CHANGELOG.md`
- `~/.pub-cache/hosted/pub.dev/json_serializable-6.14.1/{CHANGELOG.md,pubspec.yaml,lib/src/type_helpers/patch_tri_state_helper.dart,test/src/patch_tri_state_test_input.dart}`
- `~/.pub-cache/hosted/pub.dev/build_runner-2.16.2/CHANGELOG.md`
- `~/.pub-cache/hosted/pub.dev/dio-5.11.1/{CHANGELOG.md,lib/src/dio_exception.dart,lib/src/options.dart,lib/src/dio_mixin.dart,lib/src/utils.dart,lib/src/parameter.dart,lib/src/multipart_file.dart,lib/src/form_data.dart,lib/src/transformer.dart,lib/src/transformers/fused_transformer.dart}`
- `~/.pub-cache/hosted/pub.dev/dio_web_adapter-2.2.2/lib/src/adapter_impl.dart`
- `~/.pub-cache/hosted/pub.dev/http-1.6.0/{CHANGELOG.md,lib/src/browser_client.dart}`; `dio_compatibility_layer-0.1.1/lib/src/conversion_layer_adapter.dart` (завантажено архів pub)
- `~/.pub-cache/hosted/pub.dev/retrofit-4.10.0/lib/{http,dio,call_adapter,error_logger}.dart`, `retrofit_generator-10.2.11/lib/src/generator.dart`
- `~/.pub-cache/hosted/pub.dev/dart_style-3.1.13/{CHANGELOG.md,lib/src/dart_formatter.dart}`, `code_builder-4.12.0/CHANGELOG.md`, `freezed-4.0.2/CHANGELOG.md`, `drift-2.34.2/lib/src/runtime/data_class.dart`, `built_value-8.13.0/lib/json_object.dart`; `dart_mappable-4.10.0/lib/src/mapper_container.dart` (архів pub)

**GitHub**
- google/json_serializable.dart#1342 (sealed, open з 2023-08): https://github.com/google/json_serializable.dart/issues/1342
- google/json_serializable.dart PR #1483 (sealed, unmerged): https://github.com/google/json_serializable.dart/pull/1483
- google/json_serializable.dart PR #1574 (tri-state, merged 2026-05-15): https://github.com/google/json_serializable.dart/pull/1574
- google/json_serializable.dart#1508 (generics у converters): https://github.com/google/json_serializable.dart/issues/1508
- cfug/dio#1859 (SSE on Flutter Web, open): https://github.com/cfug/dio/issues/1859 · cfug/dio#1740 (Fetch API, open): https://github.com/cfug/dio/issues/1740
- trevorwang/retrofit.dart#168 (error handler, open з 2020): https://github.com/trevorwang/retrofit.dart/issues/168 · #525 (SSE, not planned): https://github.com/trevorwang/retrofit.dart/issues/525 · #235: https://github.com/trevorwang/retrofit.dart/issues/235
- dart-lang/build PR #4405 (perf build_runner 2.13): https://github.com/dart-lang/build/pull/4405
- Специфікація augmentations (working, experiment flag, правка 2026-10-06): https://github.com/dart-lang/language/blob/main/working/augmentations/feature-specification.md
- Dart SDK CHANGELOG (3.7 tall style і маркери форматера; 3.8 null-aware elements; 3.10 dot shorthands і `dart install`; 3.12 `dart run pkg@ver`; 3.13 primary constructors і секції імпортів): https://github.com/dart-lang/sdk/blob/main/CHANGELOG.md

**Блоги та документація**
- «An update on Dart macros & data serialization», Vijay Menon, 2025-01-29: https://medium.com/dartlang/an-update-on-dart-macros-data-serialization-06d3037d4f12 (дзеркало: https://dart.cn/blog/an-update-on-dart-macros-data-serialization)
- Flutter & Dart 2026 roadmap, 2026-02-24: https://flutter.dev/blog/flutter-darts-2026-roadmap
- Extension types: https://dart.dev/language/extension-types · Class modifiers: https://dart.dev/language/class-modifiers · Exhaustiveness: https://dart.dev/language/branches#exhaustiveness-checking · dart format: https://dart.dev/tools/dart-format · dart install: https://dart.dev/tools/dart-install
- OpenAPI style values: https://spec.openapis.org/oas/v3.1.0#style-values

**Експерименти** (`/private/tmp/claude-501/-Users-genius-Library-Application-Support-Claude-scratch-workspaces-caefcd6d-e2d0-4474-a3da-92a11b5759cf-a7084c89-0a78-4871-9d7a-89b7ea2dfa9f-scratch-2026-10-11-3d1424/43951355-e983-4f99-aeac-345c65820b5a/scratchpad/agent-dart/exp/`)
- `lib/models.dart` (+ `.g.dart`): checked-помилки, enum unknown, tri-state 6.14, sealed union як поле, генерики, extension type як поле
- `lib/open_enum.dart`, `lib/open_enum2.dart`, `lib/mood_model.dart`, `lib/shapes.dart`; `bin/exhaust.dart`, `bin/exhaust2.dart`, `bin/shapes_neg.dart`, `bin/shorthand.dart`: exhaustiveness, звужений тип у конструкторі, dot shorthands
- `lib/rt.dart`, `bin/rt_demo.dart`, `lib/bench_models.dart`, `bin/bench.dart`: прототип декодера зі шляхом і бенчмарк
- `lib/gen/` (600 моделей): заміри build_runner
- `bin/dio_flow.dart`: `onError`, 204, кодування query, SSE-чанки, cancel / connectionError
- `bin/fmt.dart`, `bin/fmt2.dart`, `bin/fmt3.dart`: дрейф dart_style, групування імпортів, маркери `width=` і `off`
- `lib/api.dart`, `test/mock_test.dart`: mocktail поверх `abstract interface class`
