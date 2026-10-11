# 01 — OpenAPI Generator: генератори `dart-dio` і `dart` та обгортка `openapi_generator` для pub.dev

> Стан на 2026-10-11. Джерела: код (`OpenAPITools/openapi-generator`, master на коміті `9f6536e` від 2026-10-09, версія `7.27.0-SNAPSHOT`; `gibahjoe/openapi-generator-dart` master), GitHub issues і PR, pub.dev API.
> Скорочення в посиланнях: **OAG** = `https://github.com/OpenAPITools/openapi-generator`. Шляхи до шаблонів вказано відносно `modules/openapi-generator/src/main/resources/`, шляхи до Java — відносно `modules/openapi-generator/src/main/java/org/openapitools/codegen/`.
> Позначки впевненості: **(перевірено в коді)** — бачив у шаблоні або Java-коді на зазначеному коміті; **(з issue)** — описано в issue або PR, у коді не відтворював; **(не перевірено)** — загальновідоме твердження без первинного джерела.
> Сам генератор не запускав: Java-збірку з клону свідомо не виконував, а JAR не завантажував. Висновки зроблено з шаблонів, Java-коду та закомічених у репозиторій прикладів вихідного коду (`samples/openapi3/client/petstore/dart-dio/*`).

---

## 1. Огляд

### 1.1 Що це

| Компонент | Що робить | Стан |
|---|---|---|
| `dart-dio` (OAG) | Клієнт на `dio ^5.7.0`. Серіалізація: `built_value` (за замовчуванням) або `json_serializable` (позначено **[BETA]**) | `STABLE` ([docs/generators/dart-dio.md](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/docs/generators/dart-dio.md)) |
| `dart` (OAG) | Клієнт на `package:http`, «native» серіалізація з рукописними `fromJson`/`toJson` у шаблонах, **без build_runner** | `STABLE` ([docs/generators/dart.md](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/docs/generators/dart.md)) |
| `openapi_generator`, `openapi_generator_annotations`, `openapi_generator_cli` (pub.dev, репозиторій gibahjoe/openapi-generator-dart) | Обгортка над Java-JAR: анотація `@Openapi(...)` і builder для `build_runner`. CLI завантажує JAR з Maven Central | v7.0.0 від 2026-05-31; видавець `devappliance.com`; 126 likes, ~11.5k завантажень ([pub.dev](https://pub.dev/packages/openapi_generator)) |

### 1.2 Версії і темп випусків
- Остання версія OAG — **v7.26.0 від 2026-10-06** (`gh release list`). За останні 12 місяців вийшло 10 мінорних релізів: 7.17 (2025-10-29), 7.18 (12-22), 7.19 (2026-01-19), 7.20 (02-16), 7.21 (03-24), 7.22 (04-28), 7.23 (06-08), 7.24 (07-20), 7.25 (08-24), 7.26 (10-06). Ритм — **приблизно раз на 4–7 тижнів**.
- Важливі зміни для Dart за останній рік (з release notes):
  - 7.21: `Optional<T>` для трьох станів поля (absent/null/value) у `dart` і `dart-dio`, опції `useOptional` і `patchOnly` ([PR #22257](https://github.com/OpenAPITools/openapi-generator/pull/22257));
  - 7.22: методи для зняття auth-токенів ([#23386](https://github.com/OpenAPITools/openapi-generator/pull/23386)), виправлення `importMappings` ([#23571](https://github.com/OpenAPITools/openapi-generator/pull/23571));
  - 7.23: `abortTrigger` (скасування запитів) у `dart` ([#23930](https://github.com/OpenAPITools/openapi-generator/pull/23930));
  - 7.25: tri-state для PATCH ([#23696](https://github.com/OpenAPITools/openapi-generator/pull/23696)), серіалізація `anyOf` у dart-dio ([#24605](https://github.com/OpenAPITools/openapi-generator/pull/24605)), зсув дати `format: date` у часових поясах на схід від UTC ([#24706](https://github.com/OpenAPITools/openapi-generator/pull/24706));
  - 7.26: explode для object query-параметрів у `dart` ([#24868](https://github.com/OpenAPITools/openapi-generator/pull/24868)), `unknownEnumValue` для колекцій enum у json_serializable ([#24673](https://github.com/OpenAPITools/openapi-generator/pull/24673)), багаторядкові `x-enum-descriptions` ([#24881](https://github.com/OpenAPITools/openapi-generator/pull/24881); ця помилка зламала генерацію у 7.25 — [#24858](https://github.com/OpenAPITools/openapi-generator/issues/24858)).

### 1.3 Хто супроводжує Dart-генератори
- Технічний комітет Dart у README: `@jaumard (2018/09) @amondnet (2019/12) @sbu-WBT (2020/12) @kuhnroyal (2020/12) @agilob (2020/12) @ahmednfwela (2021/08)` ([README.md, рядок 1264](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/README.md)). Активність комітету низька (пошук `commenter:` з 2025-10-01): ahmednfwela — 11 коментарів, kuhnroyal — 5, jaumard і amondnet — по 1, решта — 0. Жоден з них не відкрив жодного issue чи PR з 2024-10. У липні 2026 @josh-burton вийшов зі списку супровідників Dart ([#24352](https://github.com/OpenAPITools/openapi-generator/pull/24352)).
- **Усі 29 PR з «dart» у назві, злиті з 2025-10-01, злив @wing328** (засновник і core-maintainer OAG). Авторами переважно були разові контриб'ютори. Фактично Dart-генератори розвиваються зовнішніми PR, без власника.
- Issues (пошук `dart in:title`, 2026-10-11): **134 відкритих** (з них **70** з `dart-dio` у назві): **90 [BUG]**, **32 [REQ]**. За роком створення відкритих: 2019 — 7, 2020 — 13, 2021 — 10, 2022 — 23, 2023 — 35, 2024 — 19, 2025 — 24, 2026 — 3. Мітку `Client: Dart` ставлять рідко: лише 9 відкритих issue мають її. Епік «Dart full OAS3 support» ([#8179](https://github.com/OpenAPITools/openapi-generator/issues/8179)) відкритий з 2020 року.
- Загалом по репозиторію: 26.8k зірок і **5752 відкритих issue та PR**.

### 1.4 Залежність від Java
- Збірка під Java 11: `maven.compiler.source=11` ([pom.xml](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/pom.xml)). У [docs/installation.md](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/docs/installation.md) сказано «Java 11 runtime at a minimum». Способи постачання: JAR, npm-обгортка `@openapitools/openapi-generator-cli`, Docker, Homebrew, Maven і Gradle плагіни, `pip install openapi-generator-cli[jdk4py]`.
- README обгортки gibahjoe досі вимагає «Java (version 8 or higher)» (`openapi-generator/README.md`, рядок 18) **(перевірено в коді)**. На Java 8 користувачі отримують `UnsupportedClassVersionError` ([#19024](https://github.com/OpenAPITools/openapi-generator/issues/19024)).

### 1.5 Обгортка `openapi_generator` (gibahjoe)
- 173 зірки, 18 відкритих issue і PR, останній push 2026-05-31. Три пакети: annotations, builder (`openapi_generator`) і CLI.
- CLI створює `openapi_generator_cli` config. За замовчуванням він завантажує **OAG 7.17.0** (`openapi-generator-cli/lib/src/models.dart`, `openapiGeneratorVersion = '7.17.0'`), тобто відстає від поточного 7.26.0 на 9 мінорних версій. Додатково завантажує неофіційний генератор `openapi-dart-generator-7.2.jar` від bluetrainsoftware (`Generator.dioAlt`) **(перевірено в коді)**.
- Анотація передає лише частину прапорців OAG: `--additional-properties --api-package --enum-name-mappings --generator-name --import-mappings --inline-schema-name-mappings --inline-schema-options --name-mappings --reserved-words-mappings --skip-validate-spec --type-mappings`. **Немає `--openapi-normalizer`, `--model-name-mappings`, `--parameter-name-mappings`, `--schema-mappings`, `--operation-id-name-mappings`, `--global-property`.** Їх можна передати лише сирим рядком через `additionalCommands` у JSON-конфігу CLI **(перевірено в коді)**.
- Після генерації обгортка за замовчуванням запускає `flutter pub get` (`fetchDependencies = true`) і **вкладений** `build_runner` у каталозі виходу (`runSourceGenOnOutput = true`). Щоб примусити повторний запуск, `forceAlwaysRun` змінює анотований файл користувача.
- `openapi_generator` 7.0.0 оголошує залежність `analyzer: '>5.12.0 <9.0.0'`, а сучасний Flutter резолвить analyzer 10.x. Через це пакет не встановлюється в нових застосунках ([gibahjoe#201](https://github.com/gibahjoe/openapi-generator-dart/issues/201), відкрите з 2026-04). Генератор падає з незрозумілим повідомленням ([gibahjoe#202](https://github.com/gibahjoe/openapi-generator-dart/issues/202)) і конфліктує з `mockito:mockBuilder` у CI ([gibahjoe#136](https://github.com/gibahjoe/openapi-generator-dart/issues/136)).

---

## 2. Архітектура виходу

### 2.1 Конвеєр OAG
`swagger-parser` (розбір і валідація) → **OpenAPINormalizer** (правила, §4) → **InlineModelResolver** (виносить inline-схеми в іменовані моделі) → `DefaultCodegen` + `AbstractDartCodegen`/`DartDioClientCodegen` (будують модель для шаблонів) → **Mustache-шаблони** → (опційно) post-process кожного `.dart` файлу командою з env `DART_POST_PROCESS_FILE`, якщо передано `--enable-post-process-file` ([AbstractDartCodegen.java#L960-L976](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/java/org/openapitools/codegen/languages/AbstractDartCodegen.java#L960-L976)) → **користувач сам запускає `build_runner`** (для dart-dio в обох режимах).

Для OAS 3.1 генератор не має окремої логіки. `DefaultGenerator` вмикає правило `NORMALIZE_31SPEC` (воно не описане в документації), яке зводить конструкції 3.1 до семантики 3.0 ([DefaultGenerator.java#L263-L275](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/java/org/openapitools/codegen/DefaultGenerator.java#L263-L275)) **(перевірено в коді)**.

### 2.2 `dart-dio`: структура файлів (з `DartDioClientCodegen.processOpts`, рядки 210–296, і з прикладів)

```
pubspec.yaml, analysis_options.yaml, .gitignore, README.md
build.yaml                         # лише json_serializable
lib/<pubName>.dart                 # barrel-експорт
lib/src/api.dart                   # клас клієнта `Openapi` (clientName = camelize(pubName))
lib/src/api/<tag>_api.dart         # по класу на тег
lib/src/model/*.dart               # + *.g.dart після build_runner
lib/src/auth/{auth,api_key_auth,basic_auth,bearer_auth,oauth}.dart
lib/src/serializers.dart, api_util.dart        # built_value
lib/src/deserialize.dart                        # json_serializable
lib/src/model/date.dart, date_serializer.dart   # built_value + dateLibrary=core
lib/src/optional.dart                           # якщо useOptional=true
doc/*.md                           # документація на кожен API і кожну модель
test/*_test.dart                   # заглушки тестів `// TODO`
.openapi-generator/FILES, VERSION, .openapi-generator-ignore
```

Обсяг на прикладі `petstore_client_lib_fake` (built_value) **(перевірено в коді)**: **217 файлів, з них 67 `doc/*.md`, 64 `test/*_test.dart` (порожні `test('...', () async { // TODO })`) і лише 78 файлів у `lib/`**. Варіант з json_serializable дає 215 файлів, з них 67 і 64 відповідно.
→ **Уточнення до R13.5.** dart-dio за замовчуванням **генерує** заглушки документації і тестів. Вимкнути їх можна лише так: `--global-property apiDocs=false,modelDocs=false,apiTests=false,modelTests=false` ([docs/customization.md, «Selective generation»](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/docs/customization.md)). Формулювання R13.5 «(як у dart-dio)» варто читати як «**на відміну** від dart-dio».
Генератор `dart` створює ще й `git_push.sh` та `.travis.yml` ([DartClientCodegen.java#L97-L100](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/java/org/openapitools/codegen/languages/DartClientCodegen.java#L97-L100)) **(перевірено в коді)**.

**Вихід — окремий pub-пакет** (свій `pubspec.yaml`), який підключають як path-залежність. Вбудувати його в наявний пакет можна лише вручну, через `sourceFolder`, `pubName` і `pubLibrary`.

### 2.3 Форма API (`dart/libraries/dio/api.mustache`) **(перевірено в коді)**
- Конкретний клас `class PetApi { final Dio _dio; const PetApi(this._dio, this._serializers); }`. Абстрактного інтерфейсу немає. Мокати можна через неявний інтерфейс Dart (`implements PetApi` у mocktail).
- Метод `Future<Response<T>> getPetById({required int petId, CancelToken? cancelToken, Map<String,dynamic>? headers, Map<String,dynamic>? extra, ValidateStatus? validateStatus, ProgressCallback? onSendProgress, ProgressCallback? onReceiveProgress})`. Повертає **dio `Response<T>`**, тож заголовки і статус доступні.
- `Options.extra['secure']` — список `{type, scheme, name, keyName, where}` для кожного security requirement операції. Його читають згенеровані `AuthInterceptor` (`auth/auth.mustache`). **`operationId` в `extra` не потрапляє.**
- `contentType` береться лише як **перший** з `prioritizedContentTypes` (рядок 81).
- Помилки (де)серіалізації загортаються в `DioException(type: DioExceptionType.unknown, error: …)` (рядки 102 і 127).
- `lib/src/api.dart` (`api_client.mustache`): якщо `Dio` не передали, клієнт створює `Dio(BaseOptions(baseUrl: basePathOverride ?? basePath, connectTimeout: 5000ms, receiveTimeout: 3000ms))`. **Якщо `interceptors == null`, він додає 4 auth-інтерцептори навіть у `Dio`, переданий користувачем** ([api_client.mustache#L26-L41](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/resources/dart/libraries/dio/api_client.mustache#L26-L41)).

### 2.4 Серіалізація
- **built_value (за замовчуванням):** `abstract class X implements Built<X, XBuilder>`, колекції `BuiltList`/`BuiltMap`, `JsonObject` для any. Спільний `standardSerializers`. Для `oneOf`/`anyOf` використовуються пакети **`one_of` / `one_of_serializer` 1.5.0**, опубліковані **2022-05-10** з `sdk: '>=2.12.0 <3.0.0'` (pub.dev API). Enum — `EnumClass` з `BuiltSet values`, плюс до кожного enum генерується «Angular mixin» (`enum.mustache`). Залежності runtime: `dio`, `built_value`, `built_collection`, `one_of`, `one_of_serializer`.
- **json_serializable ([BETA]):** класи з `@JsonSerializable(checked: true, disallowUnrecognizedKeys: false, explicitToJson: true)`, з **`@CopyWith()` за замовчуванням** (з 7.15.0, [PR #21667](https://github.com/OpenAPITools/openapi-generator/pull/21667)). Рукописні `==` і `hashCode` (сума `hashCode` полів) або `equatable`. Відповідь декодується **рядковим диспетчером типів** `deserialize<ReturnType, BaseType>(value, 'TypeName')` з regex для `List<…>`/`Map<String,…>` і `throw Exception('Cannot deserialize')` наприкінці ([deserialize.mustache](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/resources/dart/libraries/dio/serialization/json_serializable/deserialize.mustache)). Тіло запиту кодується через `jsonEncode(body)`. Залежності: `dio`, `json_annotation ^4.9.0`, `copy_with_extension ^7.1.0` (+ dev: `json_serializable ^6.9.3`, `copy_with_extension_gen ^7.1.0`, `build_runner: any`).
- **`dart` (native):** одна бібліотека з `part`-файлами, без build_runner. Глобальна змінна `var defaultApiClient = ApiClient();` ([apilib.mustache#L32](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/resources/dart2/apilib.mustache)) і `import 'dart:io'` (рядок 6). Кожна операція має пару методів: `xxxWithHttpInfo()` повертає сирий `Response`, `xxx()` повертає декодоване значення. Для статусу ≥ 400 кидається `ApiException(code, String body)`.

---

## 3. Таблиця покриття вимог

Статус наведено для **`dart-dio` + json_serializable** (цільова конфігурація). Якщо built_value або `dart` поводяться інакше, це вказано в колонці «Доказ».
✅ — є; ⚠️ — частково, з багами або лише вручну; ❌ — немає.

| R-ID | Статус | Доказ |
|---|---|---|
| R0.1 OAS 3.0 / 3.1, чистий Dart | ⚠️ | 3.0 підтримано. 3.1 — **«beta support»** ([README.md L168](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/README.md)), працює через пониження до 3.0 (`NORMALIZE_31SPEC`). Баги ще відкриті: inline `type: ["object","null"]` дає non-null поле ([#23866](https://github.com/OpenAPITools/openapi-generator/issues/23866), 2026-05); виправлення 3.1 nullable були в 7.24–7.26. dart-dio — чистий Dart. **`dart` імпортує `dart:io`** (apilib.mustache L6), тому не працює на web (перевірено в коді; наслідок для web — мій висновок) |
| R0.2 толерантність до дефектів | ⚠️ | Є Normalizer (§4), але він працює мовчки, без звіту |
| R1.1 локальний файл / URL з auth | ⚠️ | `-i <file\|url>`, `-a/--auth name:header` ([docs/usage.md](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/docs/usage.md)). Поняття «знімка» немає. В обгортці є `RemoteSpec` + `headerDelegate` |
| R1.2 `$ref` між файлами, цикли | ⚠️ | Зовнішні `$ref` розв'язує swagger-parser. Самопосилання в масиві, `oneOf`, `anyOf` і `additionalProperties` «лагодяться» **заміною на any або видаленням варіанта** (`OpenAPINormalizer.fixSelfReferenceSchema`, ~L910–945, лише `LOGGER.error`) (перевірено в коді) |
| R1.3 кілька специфікацій | ✅ | Команда `batch` (YAML/JSON-конфіги), кілька `@Openapi` в обгортці |
| R1.4 OAS 3.2 `itemSchema` | ❌ | [#22728](https://github.com/OpenAPITools/openapi-generator/issues/22728) відкрите; залежить від swagger-parser#2248. Невідомі операції (наприклад, `query`) **мовчки зникають** з `--skip-validate-spec` ([#24212](https://github.com/OpenAPITools/openapi-generator/issues/24212)) |
| R2.1 іменовані правила нормалізатора, звіт | ⚠️ | 25 правил, кожне вмикається окремо, `DISABLE_ALL` (§4). Окремих правил для `required: bool`, порожнього `$ref`, масиву без `items`, неоголошених path-параметрів, `examples` у 3.0 і дублікатів enum **немає**. Звіту про спрацювання немає |
| R2.2 коди, рівні, JSON-pointer | ❌ | Лише slf4j-логи без кодів і без вказівника на місце (19 викликів `LOGGER` на 2809 рядків `OpenAPINormalizer.java`) |
| R2.3 baseline/ratchet | ❌ | — |
| R2.4 режим check | ⚠️ | `openapi-generator-cli validate -i … [--recommend]`. Це лише валідація swagger-parser (приклад виводу: `-attribute info is missing`), без перевірок, специфічних для генератора |
| R2.5 нічого не вгадувати мовчки | ❌ | Map без типу значень → `String` ([AbstractDartCodegen.java#L585-L588](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/java/org/openapitools/codegen/languages/AbstractDartCodegen.java#L585-L588)). Непідтримувані підсхеми `allOf` видаляються з логом рівня **DEBUG** (`OpenAPINormalizer.java` L1293). Виняток у нормалізаторі ловиться, генерація йде далі (`DefaultGenerator` L273–275). Без 2xx відповіддю успіху стає `default`. Cookie-параметри відкидаються (рядки нижче) |
| R3.1 файл override-ів з адресацією | ❌ | Є лише **глобальні** мапінги за іменем: `nameMappings`, `parameterNameMappings`, `modelNameMappings`, `enumNameMappings`, `operationIdNameMappings`, `inlineSchemaNameMappings`, `schemaMappings`, `typeMappings`, `importMappings` (§4) |
| R3.2 застарілий override → warning | ❌ | Мапінги лише перевіряються через `containsKey` (`toVarName`, `toParamName`, `toModelName`, `toEnumVarName`). Невикористаний ключ ніде не виявляється (перевірено в Dart-кодгені) |
| R3.3 JSON Patch / Overlay | ❌ | Запит на препроцесор або Overlay ([#22744](https://github.com/OpenAPITools/openapi-generator/issues/22744), 2026-01) відкритий |
| R4.1 фільтр за тегами, operationId, шляхами | ⚠️ | Правило `FILTER="operationId:a\|b ; tag:x ; path:/v1 ; method:get"` позначає решту операцій `x-internal: true`. Режим **лише include**. Шлях — за префіксом, не glob. Також `--global-property apis=Pet:Store` |
| R4.2 tree-shaking моделей | ❌ | Моделі генеруються для **всіх** `components.schemas` незалежно від вибраних операцій. Є лише `--global-property models=A:B` і (не задокументоване в docs/) `generateRecursiveDependentModels`, що підтягує залежності **від моделей**, не від операцій ([DefaultGenerator.java#L230, L533-L547](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/java/org/openapitools/codegen/DefaultGenerator.java)) |
| R4.3 співіснування з кодом користувача | ⚠️ | `--model-name-prefix/suffix`, окремий pub-пакет. Але dart-dio **змінює переданий `Dio`** (додає інтерцептори), а `dart` має глобальний `defaultApiClient` (перевірено в коді) |
| R5.1 імена операцій, трансформації | ⚠️ | `operationId` → camelCase, `--remove-operation-id-prefix`, `operationIdNameMappings`. Regex-трансформацій немає. Без `operationId` ім'я будується зі шляху і методу |
| R5.2 колізії | ⚠️ | Зарезервовані слова й типи з `typeMapping` отримують префікс `Model` (`ModelClient`, `ModelFile`, `ModelList`, `ModelReturn`) — лише з `LOGGER.warn`. `ensureUniqueParams` працює для параметрів. **Колізії властивостей не виявляються:** провідне `_` зрізається (`_type` → `type`) ([AbstractDartCodegen.java#L419-L457](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/java/org/openapitools/codegen/languages/AbstractDartCodegen.java#L419-L457)). Приклад колізії є в самих docs ([customization.md «Name Mapping»](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/docs/customization.md)). Див. також #9029, #20910, #12127 |
| R5.3 групування за тегом, нормалізація тегів | ✅/⚠️ | Клас на тег. Правила `KEEP_ONLY_FIRST_TAG_IN_OPERATION`, `SET_TAGS_FOR_ALL_OPERATIONS`, `SET_TAGS_TO_OPERATIONID`, `SET_TAGS_TO_VENDOR_EXTENSION`. Мапінгу «брудний тег → ім'я» немає |
| R5.4 іменування inline-схем | ⚠️ | `title`, інакше `{operationId}_request`, `{operationId}_{code}_response`, `{Parent}_{prop}`, `_inner` для елемента масиву, `inline_object`, **числові суфікси `_1`, `_2`** ([InlineModelResolver.java L630, L688, L842-L943](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/java/org/openapitools/codegen/InlineModelResolver.java)). Перейменування — `inlineSchemaNameMappings`, ключ — **згенероване** ім'я. `inlineSchemaOptions`: `ARRAY_ITEM_SUFFIX`, `MAP_ITEM_SUFFIX`, `RESOLVE_INLINE_ENUMS`, `SKIP_SCHEMA_REUSE` |
| R6.1 матриця required × nullable | ⚠️ | json_serializable: `required` → `required:true`, `includeIfNull` залежить від nullable. Optional поле завжди `T?`. Багато відкритих багів (§5, P9). Окремого режиму для запиту і відповіді немає |
| R6.2 типи і `format` | ⚠️ | `int64` → `int` (на web втрачається точність, [#14522](https://github.com/OpenAPITools/openapi-generator/issues/14522)). **`decimal` → `double`**, `uuid` → `String`, `byte` → `String`, `binary` → `MultipartFile` (у json_serializable навіть для відповіді, [#20682](https://github.com/OpenAPITools/openapi-generator/issues/20682)), any/object → `Object` (json_ser) або `JsonObject` (built_value) ([AbstractDartCodegen.java#L153-L178](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/java/org/openapitools/codegen/languages/AbstractDartCodegen.java#L153-L178)). Свої типи — через `typeMappings` + `importMappings`. `disallowAdditionalPropertiesIfNotPresent=true` за замовчуванням зберігає старе, некоректне трактування `additionalProperties` |
| R6.3 `allOf` | ⚠️ | built_value: успадкування через `implements` + `$Parent`. json_serializable: модель **сплющується, ієрархії немає** ([#21318](https://github.com/OpenAPITools/openapi-generator/issues/21318), [#22547](https://github.com/OpenAPITools/openapi-generator/issues/22547)). Одиночний `$ref` в `allOf` обробляється (у прикладах є `AllOfWithSingleRef`) |
| R6.4 конверти і дженерики | ❌ | Не підтримується. Кожен `{data: T}` стає окремою моделлю |
| R6.5 зайві поля / помилка про відсутнє поле | ⚠️ | Зайві поля ігноруються (`disallowUnrecognizedKeys: false`), хоча в `build.yaml` стоїть `disallow_unrecognized_keys: true`, що вводить в оману. При відсутньому полі `checked: true` кидає `CheckedFromJsonException` з ім'ям ключа, але без шляху в JSON, загорнутим у `DioException.unknown`. У `dart` перевірка required існує лише в **`assert`** (у release зрізається, перевірено в коді) |
| R6.6 `==`, `copyWith`, `toString` | ✅ | `==`/`hashCode` (або equatable), `copyWith` (`copy_with_extension`), `toString()` = `toJson().toString()` |
| R6.7 обмеження | ⚠️ | `minimum`/`maximum` лише коментарями `// minimum:` у json_serializable. Валідації немає |
| R7.1–R7.3 PATCH, три стани | ⚠️ | З 7.21 є `useOptional` (`Optional<T>` з `Absent`/`Present`, `readValue: readOptionalValue` з sentinel) і `patchOnly`. `patchOnly` спрацьовує **лише для тіл PATCH через `$ref`**, inline-схеми ігноруються ([AbstractDartCodegen.preprocessOpenAPI](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/java/org/openapitools/codegen/languages/AbstractDartCodegen.java)). Без `useOptional` optional поля не надсилаються, якщо дорівнюють null (`includeIfNull: false`), тож явний null надіслати неможливо. R7.3 ✅ |
| R8.1 невідоме значення enum, сире значення | ❌ | `enumUnknownDefaultCase=false` за замовчуванням. Якщо увімкнути — значення стає `unknownDefaultOpenApi`, **сире значення губиться**. У `dart` невідоме значення стає `null` (`decode(allowNull=true)`) |
| R8.2 невідоме не можна надіслати | ❌ | Sentinel — реальне wire-значення `'unknown_default_open_api'` або **`11184809`** для чисел ([DefaultCodegen.java#L7315-L7333](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/java/org/openapitools/codegen/DefaultCodegen.java#L7315-L7333)), тож його можна серіалізувати й відправити на сервер |
| R8.3 рядкові, числові, булеві enum | ⚠️ | У json_serializable `enum` для числових значень зберігає `final String value` (`'1'`) (перевірено в коді). Булеві enum правило `SIMPLIFY_BOOLEAN_ENUM` (увімкнене за замовчуванням) перетворює на звичайний `bool`. Невалідні ідентифікатори: `number1`, `number_negative1`, `empty` |
| R8.4 `x-enum-varnames`, `x-enum-descriptions` | ✅ | Через `DefaultCodegen.updateEnumVarsWithExtensions`. Плюс `x-enum-values` при `useEnumExtension`, але тоді ламається `enumUnknownDefaultCase` ([#21411](https://github.com/OpenAPITools/openapi-generator/issues/21411)) |
| R9.1 oneOf/anyOf + discriminator → закрита ієрархія + Unknown | ❌ / ⚠️ | json_serializable: **поліморфізму немає взагалі** (у `class.mustache` немає гілки для oneOf/anyOf/discriminator — перевірено в коді; [#21318](https://github.com/OpenAPITools/openapi-generator/issues/21318); пункт «Add polymorphism support to json_serializable» з [#13372](https://github.com/OpenAPITools/openapi-generator/issues/13372) відкритий з 2022). built_value: обгортка `OneOf get oneOf` з `Object value` (не sealed). Невідомий discriminator → `throw UnsupportedError("Couldn't deserialize oneOf for the discriminator value…")` (`class_serializer.mustache` L164) |
| R9.2 oneOf без discriminator | ❌ / ⚠️ | built_value: `OneOfSerializer` пробує типи по черзі, буває «more than one match found» ([#15373](https://github.com/OpenAPITools/openapi-generator/issues/15373)). Діагностики немає |
| R9.3 змішані примітиви | ⚠️ | built_value через `OneOf`/`AnyOf` з примітивами (є приклад `oneof_primitive`). Шаблон FastAPI `loc: array<anyOf[string,integer]>` давав невалідний `ValidationErrorLocInner` ([#13302](https://github.com/OpenAPITools/openapi-generator/issues/13302) відкрите, [#18913](https://github.com/OpenAPITools/openapi-generator/issues/18913)) |
| R10.1 свій Dio, генератор нічого не додає | ⚠️ | `Openapi(dio: myDio)` приймається, але без `interceptors:` **до нього додаються 4 auth-інтерцептори**. Якщо Dio не передано — жорсткі таймаути 5 с і 3 с |
| R10.2 HTTP-помилки через `onError` | ✅ | `_dio.request<Object>` з `validateStatus` користувача, тож помилки йдуть звичайним шляхом Dio |
| R10.3 path/query/header/cookie; стилі | ⚠️ | built_value: `ListParam` з `ListFormat.{csv,ssv,tsv,pipes,multi}`. json_serializable: query-значення передається **як є** (`query_param.mustache` = `{{paramName}}`) і `collectionFormat` ігнорується. **deepObject немає** ([#13584](https://github.com/OpenAPITools/openapi-generator/issues/13584); у `dart` Map іде в `parameterToString` → `toString()`). **Cookie-параметрів немає ні в сигнатурі, ні в запиті** (у шаблонах немає `isCookieParam` — перевірено в коді), хоча таблиця функцій заявляє `Cookie ✓`. Таблиця docs: `ParameterStyling ✗` |
| R10.4 JSON, multipart, urlencoded, binary | ⚠️ | multipart через `FormData.fromMap`. Content-type частин (`encoding`) не підтримується. У json_serializable моделі потрапляють у FormData без кодування ([#19420](https://github.com/OpenAPITools/openapi-generator/issues/19420), [#14472](https://github.com/OpenAPITools/openapi-generator/issues/14472)). Binary-відповідь: `ResponseType.bytes` → `Uint8List` (built_value), у json_ser — `MultipartFile` |
| R10.5 скасування, прогрес, заголовки, `extra`, operationId | ⚠️ | `cancelToken`, `onSend/ReceiveProgress`, `headers`, `extra` — ✅. **`operationId` у запиті немає.** Таймаут на окремий запит не передати ([#12645](https://github.com/OpenAPITools/openapi-generator/issues/12645)) |
| R10.6 кілька 2xx, 204, не-JSON | ⚠️ | Тип повернення береться з **найменшого 2xx коду, а якщо 2xx немає — з `default`** ([DefaultCodegen.java#L4850-L4860](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/java/org/openapitools/codegen/DefaultCodegen.java#L4850-L4860)). `text/plain` ламається ([#14904](https://github.com/OpenAPITools/openapi-generator/issues/14904)). Новий opt-in `--global-property splitOperationsByContentType=true` генерує окремі методи `With<Subtype>`/`As<Subtype>` ([docs/global-properties.md](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/docs/global-properties.md)) |
| R10.7 абстрактний API | ⚠️ | Класи конкретні, але мокаються через неявний інтерфейс без кодогенерації |
| R10.8 security як метадані | ✅/⚠️ | `extra['secure']` — хороший prior art. Але семантика AND/OR у вимогах `security` сплющується в плоский список ([#7057](https://github.com/OpenAPITools/openapi-generator/issues/7057)) |
| R10.9 кілька `servers`, змінні | ❌ | Береться лише перший сервер (`basePath`), `basePathOverride`. В docs: `MultiServer ✗`, `ParameterizedServer ✗`. Є CLI `--server-variables` (підстановка під час генерації) |
| R11.1–R11.7 типізовані помилки | ❌ | Тіло помилки — сирий `DioException.response.data`. Помилку декодування не відрізнити від транспортної (обидві `DioExceptionType.unknown`). У `dart` помилка декодування стає `ApiException(500, …)` — **фальшивий HTTP-статус** (перевірено в коді) |
| R12.x SSE | ❌ | Підтримки немає. Запит на stream response відкритий з 2020 ([#6750](https://github.com/OpenAPITools/openapi-generator/issues/6750)) |
| R13.1 детермінізм | ⚠️ | Шаблони детерміновані (заголовок без дати й версії). Але імена inline-моделей залежать від порядку обходу (`_1`, `_2`) і від дедуплікації, а поведінка дедуплікації змінилась у 7.23 ([#24177](https://github.com/OpenAPITools/openapi-generator/issues/24177)). Правило `SORT_MODEL_PROPERTIES` (opt-in) упорядковує властивості |
| R13.2 lints і format | ❌ | Див. §5, P20. `dart format` лише через env + прапорець |
| R13.3 малий runtime-пакет | ❌ | Окремого runtime немає. Хелпери копіюються в кожен згенерований пакет. Зовнішні залежності застарілі (`one_of` з 2022) |
| R13.4 doc-коментарі, `@Deprecated` | ✅ | `summary`/`notes` → `///`. `@Deprecated` на операціях, параметрах, моделях і полях |
| R13.5 без заглушок | ❌ | Див. §2.2: 67 doc + 64 test-заглушки на 78 файлів lib |
| R14.1 звіт про зміни | ❌ | Є лише `--dry-run` (зміни на рівні файлів) і `.openapi-generator/FILES`. Застарілі файли не видаляються: у самому прикладі `petstore_client_lib_fake` лежать `cat_all_of.dart`, `dog_all_of.dart`, `inline_response_default.dart`, яких немає у `FILES` (перевірено в коді) |
| R14.2 сумісність еволюції | ⚠️ | Новий варіант union при відомому discriminator у built_value — `UnsupportedError`. Новий enum — помилка або втрата значення |
| R15.1 CLI і програмний API | ⚠️ | Java CLI, Maven/Gradle плагіни, обгортка через build_runner. Нативного Dart API немає |
| R15.2 конфіг зі схемою | ⚠️ | `-c config.{json,yaml}` (additional properties), `batch`. Валідації конфігу за схемою немає (не перевірено для npm-обгортки) |
| R15.3 golden-тести | ⚠️ | `samples/` + `bin/configs/dart*.yaml` (10 конфігів) слугують golden-ами в CI. Тест-схеми розкидані ([#15449](https://github.com/OpenAPITools/openapi-generator/issues/15449)) |
| R15.4 semver | ❌ | Вихід змінюється в мінорних релізах (§5, P25) |
| R15.5 документація, матриця | ⚠️ | Сторінка генератора з таблицею функцій є, але таблиця **розходиться з кодом** (Cookie ✓ — насправді ні; [#17677](https://github.com/OpenAPITools/openapi-generator/issues/17677) стверджує, що `modelNameMappings` немає, а в коді воно є) |
| R15.6 lint для бекенду | ⚠️ | Лише `validate --recommend` |

---

## 4. Normalizer і mappings як prior art (R2, R3, R4, R5)

### 4.1 OpenAPI Normalizer — повний список правил (master `9f6536e`)
Джерело: [docs/customization.md, «OpenAPI Normalizer»](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/docs/customization.md) і [OpenAPINormalizer.java L65-L175, L250-L280](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/java/org/openapitools/codegen/OpenAPINormalizer.java). Синтаксис: `--openapi-normalizer RULE=true,RULE2=value` (CLI) або `openapiNormalizer` у плагінах.

| Правило | За замовч. | Що робить |
|---|---|---|
| `SIMPLIFY_ONEOF_ANYOF` | **on** | Прибирає `null`/`enum:[null]` з oneOf/anyOf і ставить `nullable: true`. Розгортає oneOf/anyOf з одним варіантом |
| `SIMPLIFY_BOOLEAN_ENUM` | **on** | Булевий enum → `boolean` |
| `SIMPLIFY_ONEOF_ANYOF_ENUM` | **on** | oneOf/anyOf лише з enum-підсхем → один enum |
| `REFACTOR_ALLOF_WITH_PROPERTIES_ONLY` | **on** | `allOf` + `properties` на одному рівні → `allOf` з новою підсхемою |
| `REF_AS_PARENT_IN_ALLOF` | off | `$ref` в `allOf` вважається батьківським класом (успадкування) |
| `REMOVE_ANYOF_ONEOF_AND_KEEP_PROPERTIES_ONLY` | off | Видаляє oneOf/anyOf, що лише перелічують required, і залишає properties |
| `SIMPLIFY_ANYOF_STRING_AND_ENUM_STRING` | off | `anyOf[string, enum<string>]` → `string` |
| `REPLACE_ONE_OF_BY_DISCRIMINATOR_MAPPING` | off | Замінює `oneOf` на `discriminator.mapping` (новинка 7.22; у docs є diff «до/після») |
| `KEEP_ONLY_FIRST_TAG_IN_OPERATION` | off | Залишає лише перший тег операції |
| `SET_TAGS_FOR_ALL_OPERATIONS=<tag>` | off | Усім операціям ставить один тег |
| `SET_TAGS_TO_OPERATIONID` | off | Тег = operationId |
| `SET_TAGS_TO_VENDOR_EXTENSION=<x-…>` | off | Тег береться з `x-` розширення |
| `FIX_DUPLICATED_OPERATIONID` | off | Додає суфікси `_0`, `_1` до дублікатів operationId |
| `ADD_UNSIGNED_TO_INTEGER_WITH_INVALID_MAX_VALUE` | off | Для `maximum: 2^32-1` / `2^64-1` додає `x-unsigned` |
| `REMOVE_PROPERTIES_FROM_TYPE_OTHER_THAN_OBJECT` | off | Прибирає `properties` у схем, що не є object |
| `REMOVE_X_INTERNAL` | off | Вимикає приховування елементів з `x-internal` |
| `FILTER="operationId:a\|b ; tag:x ; path:/v1 ; method:get"` | off | Операції, що не підпали під фільтр, отримують `x-internal: true` і не генеруються |
| `SECURITY_SCHEMES_FILTER="key:… ; type:…"` | off | Видаляє security schemes, що не підпали під фільтр, і посилання на них |
| `SET_CONTAINER_TO_NULLABLE=array\|set\|map` | off | Масові `nullable: true` для контейнерів |
| `SET_PRIMITIVE_TYPES_TO_NULLABLE=string\|integer\|number\|boolean` | off | Масові `nullable: true` для примітивів |
| `SET_BEARER_AUTH_FOR_NAME=<name>` | off | Перетворює securityDefinition зі Swagger 2 на `http bearer` |
| `SORT_MODEL_PROPERTIES` | off | Сортує властивості за алфавітом (для детермінізму) |
| `LOOSE_NULL_DEFINITIONS` | off | Більше форм у 3.0 трактуються як `null` (новинка 7.23) |
| `NORMALIZE_31SPEC` | авто для ≥3.1 | Пониження 3.1 → 3.0 (у docs не описане; вмикається в `DefaultGenerator` L268) |
| `NORMALIZER_CLASS=<FQCN>` | — | Власний Java-підклас нормалізатора (плагін) |
| `ENABLE_ALL` / `DISABLE_ALL` | — | Масове ввімкнення або вимкнення |

Не правило, але те саме за суттю: **`fixSelfReferenceSchema`** працює завжди і замінює самопосилання на any або видаляє варіант.

### 4.2 Мапінги та інші механізми
| Механізм | Ключ | Як працює |
|---|---|---|
| `nameMappings` | **сире ім'я властивості** (`_type=underscoreType`) | Глобально для **всіх** схем, без адресації `Schema.prop` |
| `parameterNameMappings` | сире ім'я параметра | Глобально для всіх операцій |
| `modelNameMappings` | ім'я схеми (`Tag=Label`) | Перейменування моделі |
| `enumNameMappings` | **значення** enum (`sold=UNAVAILABLE`) | Глобально для всіх enum з таким значенням |
| `operationIdNameMappings` | operationId | Ім'я методу |
| `inlineSchemaNameMappings` | **згенероване** ім'я (`meta_200_response=MetaObject`) | Спочатку треба запустити генерацію, щоб дізнатися ім'я. INFO-лог підказує: «Inline schema created as … To have complete control of the model name, set the `title` field or use the inlineSchemaNameMapping option» |
| `inlineSchemaOptions` | `ARRAY_ITEM_SUFFIX`, `MAP_ITEM_SUFFIX`, `SKIP_SCHEMA_REUSE`, `REFACTOR_ALLOF_INLINE_SCHEMAS`, `RESOLVE_INLINE_ENUMS` | Глобальні налаштування резолвера |
| `schemaMappings` | ім'я схеми → зовнішній тип | Модель не генерується, використовується тип користувача («bring your own model») |
| `typeMappings` + `importMappings` | тип OpenAPI (`DateTime`, `string+binary`) → тип Dart + import | Глобальна заміна типів. Для Dart потрібні **обидва** мапінги |
| `reservedWordsMappings` | слово → заміна | |
| `--skip-validate-spec` | — | Пропускає валідацію swagger-parser (може мовчки втрачати невідомі конструкції, [#24212](https://github.com/OpenAPITools/openapi-generator/issues/24212)) |
| `--global-property apis=Pet:Store,models=User:Pet,apiTests=false,…` | ім'я API або моделі | Вибіркова генерація. **Без tree-shaking** |
| `.openapi-generator-ignore` | glob-патерни шляхів **файлів** | Не перезаписувати або не генерувати файли. `--openapi-generator-ignore-list` наповнює його з CLI |
| `.openapi-generator/FILES` | — | Маніфест згенерованих файлів (для очищення застарілих, але очищує не сам генератор) |
| `--minimal-update`, `--dry-run` | — | Записує лише змінені файли / показує, що зміниться |
| `x-internal: true` у спеці | елемент | Виключає операцію або модель з генерації |

### 4.3 Слабкі місця, які новий інструмент має закрити
1. **Немає адресації.** Мапінги прив'язані до сирого імені, а не до місця в специфікації (JSON pointer, `operationId`, `Schema.property`). `nameMappings _type=…` діє на всі схеми одразу. `enumNameMappings` — на всі enum з таким значенням. Перейменувати поле лише в одній схемі неможливо (перевірено в коді: `toVarName` і `toParamName` роблять лише `nameMapping.containsKey(name)`).
2. **Ключі `inlineSchemaNameMappings` нестабільні.** Ключ — ім'я, яке генератор сам вигадав (`getPets_200_response`). Воно змінюється, коли змінюється `operationId`, порядок обходу (`_1`) або правила дедуплікації (зміна у 7.23, [#24177](https://github.com/OpenAPITools/openapi-generator/issues/24177)).
3. **Усе відбувається мовчки.** Спрацювання правил лише логуються (INFO/WARN/DEBUG) без коду, без JSON pointer і без машинозчитуваного звіту. Невідоме ім'я правила дає лише `WARN "Invalid openapi-normalizer rule name"`. **Виняток усередині нормалізатора ловиться, і генерація триває** з наполовину нормалізованою специфікацією (`DefaultGenerator` L273–275).
4. **Застарілі override-и не виявляються.** Мапінг на ім'я, якого вже немає, просто ігнорується (R3.2).
5. **Мапінги обходять валідацію.** Docs прямо попереджають, що мапінги не проходять жодної перевірки, тож результат може не скомпілюватися, якщо, наприклад, нове ім'я — зарезервоване слово.
6. **Правила — «великі молотки».** `SET_TAGS_FOR_ALL_OPERATIONS` і `SET_PRIMITIVE_TYPES_TO_NULLABLE` діють на всю специфікацію, а `REF_AS_PARENT_IN_ALLOF` змінює семантику всіх `allOf`. Точкового «тільки тут» немає.
7. **Поведінка правил змінюється між мінорними релізами:** 4 правила стали on за замовчуванням з 7.0.0; регресія `REF_AS_PARENT_IN_ALLOF` у 7.16 ([#22043](https://github.com/OpenAPITools/openapi-generator/issues/22043)); `fix(normalizer): restore behavior…` у 7.25 ([#24585](https://github.com/OpenAPITools/openapi-generator/pull/24585)).
8. **Немає правил для типових дефектів R2.1.** Правил для `required: bool`, порожнього `$ref`, масиву без `items`, неоголошених path-параметрів, `examples` у 3.0 і дублікатів enum немає. Частину «лагодить» swagger-parser неявно (не перевірено), частина ламає генерацію.
9. **`FILTER` — лише include, без glob, і не прибирає моделі** (немає tree-shaking).
10. **Розширення через `NORMALIZER_CLASS`** — Java-клас у classpath. Це потужно, але недоступно Dart-розробнику.
11. Немає Overlay чи JSON Patch: користувачі просять препроцесор ([#22744](https://github.com/OpenAPITools/openapi-generator/issues/22744)).

---

## 5. Проблеми (з посиланнями і «уроком»)

### A. Іменування
**P1. Inline-імена генеруються з operationId і HTTP-коду, і перейменування вже ламали API.** Імена бувають `GetPets200Response`, `CreateUserRequest`, `FooGetDefaultResponse`, `…Inner`, `InlineObject1`. У v6.0.0 схема іменування змінилася (`InlineResponse200` → `{OperationId}200Response`). PR [#12353](https://github.com/OpenAPITools/openapi-generator/pull/12353) мав мітку **«Breaking change (without fallback)»**. У прикладах OAG досі лежить застарілий `inline_response_default.dart`. **(з PR + перевірено в коді)**
→ **Урок:** імена з контексту (`<Parent><Property>`, `<Operation>Response`) без HTTP-коду в імені за замовчуванням. Стабільний ключ для override — **місце в специфікації** (pointer), а не згенероване ім'я. Будь-який числовий суфікс — це діагностика з пропозицією override (R5.4, R2.5).

**P2. Модель помилки валідації FastAPI ламає генератор.** `ValidationError.loc: array<anyOf[string, integer]>` перетворюється на порожній або невалідний `ValidationErrorLocInner` ([#13302](https://github.com/OpenAPITools/openapi-generator/issues/13302) відкрите з 2022, [#18913](https://github.com/OpenAPITools/openapi-generator/issues/18913)). **(з issue)**
→ **Урок:** примітивні union-и (R9.3) потрібні з першого дня. Варто мати вбудований «рецепт FastAPI» з golden-тестом на `HTTPValidationError`.

**P3. Дедуплікація inline-схем змінила вихід у мінорному релізі.** У 7.23.0 частина раніше згенерованих файлів зникла ([#24177](https://github.com/OpenAPITools/openapi-generator/issues/24177), відкрите). Там же з'явилася регресія: inline-enum з однаковими значеннями на різних властивостях мовчки зливалися в один тип ([#23978](https://github.com/OpenAPITools/openapi-generator/issues/23978), закрито 2026-08). Тепер структурне злиття обмежене схемами з `title`, що не є enum (коментарі в `InlineModelResolver.matchGenerated`). **(з issue + перевірено в коді)**
→ **Урок:** дедуплікація має бути явною. Кожне злиття — info-діагностика зі списком місць. Зміна алгоритму дедуплікації — breaking (R5.4, R15.4).

**P4. Колізії імен вирішуються мовчки або не вирішуються зовсім.** Провідне `_` зрізається, тож `_type` і `type` дають однакове поле (сама документація OAG наводить цей приклад). Зарезервовані слова й типи з мапінгу отримують префікс `Model` (`ModelClient`, `ModelFile`, `ModelList`, `ModelReturn` — у прикладах), лише з WARN-логом. Конфлікти з `dart:core` і з членами базових класів: `Type` ([#9029](https://github.com/OpenAPITools/openapi-generator/issues/9029)), статичний `name` в `EnumClass` ([#20910](https://github.com/OpenAPITools/openapi-generator/issues/20910), відкрите), поле `json`, затінене в `toJson` ([#12127](https://github.com/OpenAPITools/openapi-generator/issues/12127)), «The name 'xxx' is defined in the libraries» ([#13931](https://github.com/OpenAPITools/openapi-generator/issues/13931)). **(перевірено в коді + з issue)**
→ **Урок:** детерміноване розв'язання колізій з кодом діагностики для кожного випадку (R5.2). Перевіряти конфлікти з `dart:core`, з членами `Object` і `Enum` (`name`, `index`, `values`, `hashCode`, `toString`, `runtimeType`) та з власними методами моделі (`toJson`, `fromJson`, `copyWith`). Override-и теж проходять цю перевірку, на відміну від OAG.

**P5. Документація і таблиця функцій не збігаються з кодом.** Таблиця стверджує `Cookie ✓`, але cookie-параметри відкидаються. Issue [#17677](https://github.com/OpenAPITools/openapi-generator/issues/17677) каже, що `modelNameMappings` для dart-dio немає, хоча `AbstractDartCodegen.toModelName` його підтримує. **(перевірено в коді)**
→ **Урок:** матрицю підтримки (R15.5) генерувати з golden-тестів і фікстур, а не писати вручну.

### B. Поліморфізм
**P6. У json_serializable-режимі поліморфізму немає.** `oneOf`, `anyOf`, `discriminator` і успадкування не підтримуються: `class Dog {}` замість `Dog extends Pet` ([#21318](https://github.com/OpenAPITools/openapi-generator/issues/21318)), властивості предка губляться ([#22547](https://github.com/OpenAPITools/openapi-generator/issues/22547)). Пункт «Add polymorphism support to json_serializable» у [#13372](https://github.com/OpenAPITools/openapi-generator/issues/13372) відкритий з 2022. У `class.mustache` для json_serializable немає жодної гілки `oneOf`/`anyOf`/`discriminator` **(перевірено в коді)**. Запити на freezed ([#19284](https://github.com/OpenAPITools/openapi-generator/issues/19284) — 14 реакцій, [#21837](https://github.com/OpenAPITools/openapi-generator/issues/21837)) відкриті, а PR з freezed ([#13047](https://github.com/OpenAPITools/openapi-generator/pull/13047)) закрили без злиття.
→ **Урок:** саме цю прогалину закриває новий інструмент (dio + json_serializable). Sealed-ієрархія з варіантом `Unknown(raw JSON)` (R9.1) і власний `fromJson`-диспетчер за discriminator поверх json_serializable для варіантів.

**P7. built_value-поліморфізм незручний і крихкий.** `OneOf get oneOf` має `Object value` і `isType(T)`, а не sealed-класи. Невідомий discriminator дає `UnsupportedError` (`class_serializer.mustache` L164, **перевірено в коді**). Без discriminator трапляється «more than one match found» ([#15373](https://github.com/OpenAPITools/openapi-generator/issues/15373)). `oneOf` + `allOf` губить властивості ([#18380](https://github.com/OpenAPITools/openapi-generator/issues/18380)). Поліморфне тіло запиту не серіалізується ([#16708](https://github.com/OpenAPITools/openapi-generator/issues/16708)). Enum як discriminator не компілюється ([#21570](https://github.com/OpenAPITools/openapi-generator/issues/21570)). Java і Dart поводяться неоднаково ([#21297](https://github.com/OpenAPITools/openapi-generator/issues/21297)). Проблема «Polymorphism for dart-dio broken» ([#6160](https://github.com/OpenAPITools/openapi-generator/issues/6160)) відкрита з 2020. **(з issue)**
→ **Урок:** exhaustive `switch` по sealed-класах. Невідомий тип ніколи не кидає виняток при декодуванні. Discriminator будь-якого типу (string, enum). Серіалізація підкласу автоматично ставить discriminator.

**P8. Runtime-залежність від неживих пакетів.** `one_of` і `one_of_serializer` 1.5.0 опубліковані 2022-05-10 з `sdk <3.0.0`. Dart 3 резолвить їх лише завдяки правилу сумісності для SDK ≥2.12. **(перевірено через pub.dev API)**
→ **Урок:** R13.3 — власний маленький runtime без сторонніх «union»-пакетів. Союзні типи генерувати як sealed-класи в коді.

### C. Nullability / required
**P9. Матриця required × nullable — головне джерело багів.** Inline `type: ["object","null"]` у 3.1 дає non-null поле ([#23866](https://github.com/OpenAPITools/openapi-generator/issues/23866), 2026-05). `nullable: false` поряд з `$ref` (типовий вихід ASP.NET) ігнорується ([#21565](https://github.com/OpenAPITools/openapi-generator/issues/21565)). Є й інші відкриті: «incorrect nullable when required» ([#21510](https://github.com/OpenAPITools/openapi-generator/issues/21510)), `includeIfNull` хибне для required ([#21508](https://github.com/OpenAPITools/openapi-generator/issues/21508)), non-required non-nullable поле отримує null ([#18647](https://github.com/OpenAPITools/openapi-generator/issues/18647)), non-nullable поля стають nullable ([#14320](https://github.com/OpenAPITools/openapi-generator/issues/14320)), дискусія «non-nullable без default → required?» ([#10972](https://github.com/OpenAPITools/openapi-generator/issues/10972)), коментар «This property should have been non-nullable!» у кожному полі `dart` ([#17222](https://github.com/OpenAPITools/openapi-generator/issues/17222), шаблон `native_class.mustache` L27). **(з issue + перевірено в коді)**
→ **Урок:** R6.1 — явна задокументована таблиця (required, nullable, default, напрям request/response) → тип Dart з golden-тестами на кожну клітинку. Неоднозначні випадки — діагностика з override. Окремо обробляти `$ref` з сусідніми ключами в 3.0 і `allOf:[$ref] + nullable` (NestJS, ASP.NET).

**P10. Перевірки, які зникають у release.** У `dart` наявність required-ключів перевіряється лише в `assert(...)` («Note 2: this code is stripped in release mode!»). Невідомий enum мовчки стає `null` (`decode(allowNull = true)`). **(перевірено в коді)**
→ **Урок:** R6.5 — помилка декодування завжди, у будь-якому режимі збірки, з шляхом `Схема.поле` і JSON-path.

### D. Enum
**P11. Unknown-значення enum не вирішене.** `enumUnknownDefaultCase` за замовчуванням вимкнено. Sentinel — справжнє wire-значення (`'unknown_default_open_api'` / `11184809`), тож сире значення губиться і sentinel можна надіслати на сервер (**перевірено в коді**, `DefaultCodegen` L7315). Опція ламається з `useEnumExtension` ([#21411](https://github.com/OpenAPITools/openapi-generator/issues/21411)). Для колекцій enum виправлено лише у 7.26 ([#22160](https://github.com/OpenAPITools/openapi-generator/issues/22160) → [#24673](https://github.com/OpenAPITools/openapi-generator/pull/24673)). Enum з `default` не компілюється ([#20495](https://github.com/OpenAPITools/openapi-generator/issues/20495); регресія 7.16 — [#22120](https://github.com/OpenAPITools/openapi-generator/issues/22120); [#22561](https://github.com/OpenAPITools/openapi-generator/issues/22561)). Uppercase enum не серіалізуються ([#22399](https://github.com/OpenAPITools/openapi-generator/issues/22399)). Числові enum зберігаються як `String value` (перевірено в коді).
→ **Урок:** R8.1/R8.2 — окремий тип для невідомого значення з сирим значенням, який **неможливо передати в request** (наприклад, `sealed` з `Known`/`Unknown` для відповідей і закритий `enum` для запитів). Типізоване `value` (int/String/bool).

### E. Транспорт
**P12. Генератор змінює Dio користувача.** Без `interceptors:` до переданого `Dio` додаються `OAuthInterceptor`, `BasicAuthInterceptor`, `BearerAuthInterceptor`, `ApiKeyAuthInterceptor`. Якщо Dio не передано, таймаути жорстко задані: 5 с і 3 с ([api_client.mustache#L26-L41](https://github.com/OpenAPITools/openapi-generator/blob/9f6536e/modules/openapi-generator/src/main/resources/dart/libraries/dio/api_client.mustache#L26-L41)). **(перевірено в коді)**
→ **Урок:** R10.1 — приймати лише готовий `Dio`, нічого в ньому не змінювати. Auth віддати користувачу, але передавати **метадані** (`extra`).

**P13. Один тип відповіді, один content-type.** Береться найменший 2xx. **Якщо 2xx немає, типом успіху стає `default`**, яким у реальних специфікаціях зазвичай описують помилку (перевірено в коді). Для тіла береться лише перший content-type. `text/plain` ламає метод ([#14904](https://github.com/OpenAPITools/openapi-generator/issues/14904)). Binary-відповідь — це `MultipartFile` ([#12161](https://github.com/OpenAPITools/openapi-generator/issues/12161), [#20682](https://github.com/OpenAPITools/openapi-generator/issues/20682)). Stream не підтримується ([#6750](https://github.com/OpenAPITools/openapi-generator/issues/6750)).
→ **Урок:** R10.6 — union успішних відповідей за статусом. `default` вважати помилкою, якщо немає явного override. Декодер за media type. Діагностика, якщо content-type-ів кілька.

**P14. Помилки не типізовані.** Помилки HTTP, декодування і транспорту надходять як `DioException`. Для декодування — `DioExceptionType.unknown` (перевірено в коді). У `dart` помилка декодування — `ApiException(HttpStatus.internalServerError, …)`, фальшивий 500 (перевірено в коді).
→ **Урок:** R11.1/R11.7 — окремі типи для `HttpError<E>` (зі статусом і типізованим тілом), `DecodingError` (зі шляхом) і `TransportError`.

**P15. Параметри.** deepObject не підтримується ([#13584](https://github.com/OpenAPITools/openapi-generator/issues/13584), відкрите). Cookie-параметри відкидаються: шаблони не обробляють `isCookieParam`, а [#12489](https://github.com/OpenAPITools/openapi-generator/issues/12489) закрили без виправлення (перевірено в коді). У json_serializable `collectionFormat` ігнорується. Optional nullable query-параметр надсилався порожнім замість того, щоб бути пропущеним ([#24736](https://github.com/OpenAPITools/openapi-generator/issues/24736), закрито 2026-08).
→ **Урок:** R10.3 — серіалізатор параметрів у runtime-пакеті, покритий тестами на всі комбінації `style` × `explode` × тип з таблиці OAS.

**P16. Multipart.** У json_serializable моделі передаються в `FormData` без кодування ([#19420](https://github.com/OpenAPITools/openapi-generator/issues/19420), [#14472](https://github.com/OpenAPITools/openapi-generator/issues/14472)). Null-поля надсилаються ([#10295](https://github.com/OpenAPITools/openapi-generator/issues/10295)). Content-type частин (`encoding`) не підтримується (перевірено в коді).
→ **Урок:** R10.4 — типізовані частини з content-type, JSON-частини кодувати явно.

**P17. Запит не позначено `operationId`.** `extra` містить лише `secure` (перевірено в коді). Таймаут на окремий запит не задати ([#12645](https://github.com/OpenAPITools/openapi-generator/issues/12645), 11 реакцій).
→ **Урок:** R10.5 — `extra['openapi.operationId']`, `security`, тег. Окремий параметр `Options`, щоб змінити будь-що, зокрема таймаути.

**P18. Лише перший `servers`** (`basePath`). У docs: `MultiServer ✗`, `ParameterizedServer ✗`. Відкрите [#7310](https://github.com/OpenAPITools/openapi-generator/issues/7310).
→ **Урок:** R10.9 — генерувати константи або enum серверів зі змінними, але **не** нав'язувати `baseUrl`.

**P19. Втрата точності типів.** `decimal` → `double` (перевірено в коді). `int64` → `int` (на web 53 біти, [#14522](https://github.com/OpenAPITools/openapi-generator/issues/14522)). `string+int64` не мапиться в `BigInt` ([#21473](https://github.com/OpenAPITools/openapi-generator/issues/21473)). `uuid` → `String`. `format: date` → `DateTime` з багом зсуву часового поясу ([#24703](https://github.com/OpenAPITools/openapi-generator/issues/24703), виправлено у 7.25).
→ **Урок:** R6.2 — окремий тип `Date` (без часу). Для `decimal` за замовчуванням — `String` або діагностика з пропозицією мапінгу. Для int64 на web — діагностика або опція.

### F. Якість виходу та DX
**P20. Вихід не чистий під `package:lints/recommended`** (перевірено в шаблонах; належність правил перевірена в `lints-6.1.0/lib/recommended.yaml`):
- `/** … */` для описів enum → `slash_for_doc_comments`;
- `this.dio.interceptors` → `unnecessary_this`;
- `'Bearer ${token}'` → `unnecessary_brace_in_string_interps`;
- локальні `_path`, `_options`, `_response` → `no_leading_underscores_for_local_identifiers`;
- `import 'package:equatable/src/equatable_utils.dart'` → `implementation_imports`;
- `bool operator ==` без `@override` у гілці equatable → `annotate_overrides`;
- `@JsonKey(ignore: true)` — застаріле API json_annotation.

Згенерований `analysis_options.yaml` виключає `test/*.dart` і `*.g.dart` та ігнорує `deprecated_member_use_from_same_package`. У шаблонах `dart`/`dart-dio` близько 27 директив `// ignore` / `ignore_for_file`. `dart format` запускається лише за `DART_POST_PROCESS_FILE` + `--enable-post-process-file`.
→ **Урок:** R13.2 — golden-тест «`dart analyze` з recommended + flutter_lints = 0 зауважень» на корпусі специфікацій. Форматування вбудоване (через `dart_style` як бібліотеку). Жодних `ignore_for_file` на весь файл.

**P21. Зайві файли і накопичення застарілих.** Заглушки документації і тестів, README і pubspec генеруються за замовчуванням: 131 з 217 файлів у прикладі — `doc/` і `test/`. `dart` додає `git_push.sh` і `.travis.yml`. Застарілі файли не видаляються: у прикладі OAG лежать `cat_all_of.dart`, `dog_all_of.dart`, `inline_response_default.dart`, яких немає у `.openapi-generator/FILES` (перевірено в коді).
→ **Урок:** R13.5 — генерувати лише `lib`. Каталог виходу інструмент повністю контролює через маніфест і видаляє застарілі файли (або питає).

**P22. Потрібен build_runner, і з ним незручно працювати.** Обидва режими dart-dio вимагають запуску користувачем. Запит запускати його автоматично ([#15448](https://github.com/OpenAPITools/openapi-generator/issues/15448), 17 коментарів) відкритий. Синтаксична помилка в згенерованому коді блокує build_runner на великій специфікації (Twitter v2, [#12306](https://github.com/OpenAPITools/openapi-generator/issues/12306)). Обгортка запускає вкладений `build_runner`. Повільна генерація built_value на сотнях моделей — поширена скарга спільноти **(не перевірено, окремого issue в трекері OAG не знайшов)**.
→ **Урок:** відкрите рішення 1 — `dart`-генератор доводить, що вихід без build_runner (рукописні `fromJson`) реальний. Якщо лишається json_serializable, `.g.dart` краще генерувати самим (або повністю відмовитись від build_runner), щоб вихід був готовий одразу.

**P23. Два бекенди серіалізації переплетені в одному наборі шаблонів.** API-шаблони знають про серіалізатор ([#15477](https://github.com/OpenAPITools/openapi-generator/issues/15477)). json_serializable роками в статусі «[BETA]». PR-и на уніфікацію `dart`/`dart-dio` ([#14346](https://github.com/OpenAPITools/openapi-generator/pull/14346)) і на freezed ([#13047](https://github.com/OpenAPITools/openapi-generator/pull/13047)) закрито без злиття. Тест-схеми розкидані ([#15449](https://github.com/OpenAPITools/openapi-generator/issues/15449)).
→ **Урок:** один серіалізаційний бекенд або чітка IR → emitter межа (відкриті рішення 2, 5, 6).

**P24. Диспетчер типів за рядком під час виконання.** `deserialize<T, B>(value, 'List<Pet>')` з `RegExp(r'^List<(.*)>$')` і `throw Exception('Cannot deserialize')` (перевірено в коді).
→ **Урок:** генерувати прямі виклики `Pet.fromJson`. Помилки — з типом і шляхом.

**P25. Вихід змінюється в мінорних релізах.**
- 7.15.0: за замовчуванням додано `copy_with_extension` ([#21667](https://github.com/OpenAPITools/openapi-generator/pull/21667), мітка лише «Enhancement»). Збірки впали, бо пакет вимагав Dart ^3.8, а pubspec задавав 3.5.0 ([#21815](https://github.com/OpenAPITools/openapi-generator/issues/21815)).
- 7.16: регресія enum default ([#22120](https://github.com/OpenAPITools/openapi-generator/issues/22120)).
- 7.23: зміни в дедуплікації ([#24177](https://github.com/OpenAPITools/openapi-generator/issues/24177)).
- 7.25: багаторядкові `x-enum-descriptions` дали невалідний код ([#24858](https://github.com/OpenAPITools/openapi-generator/issues/24858)).

**(з issue + PR)**
→ **Урок:** R15.4 — golden-диф на корпусі специфікацій у CI. Будь-яка зміна виходу — major або opt-in прапорець.

**P26. Закріплені версії залежностей застарівають.** У шаблоні `copy_with_extension(_gen) ^7.1.0`, на pub.dev — 18.0.0 (2026-09-26). `equatable ^2.0.7` — на pub.dev 3.0.0, до того ж імпорт з `src/`. `time_machine` — 2022. `one_of` — 2022. `dart`: `test: '>=1.21.6 <1.22.0'`, `intl: any` (перевірено в коді і через pub.dev API).
→ **Урок:** R13.3 — мінімум залежностей, а версії в згенерованому pubspec (якщо він є) тестувати в CI проти актуальних пакетів.

**P27. Java.** OAG вимагає Java 11+, а обгортка пише про Java 8 → `UnsupportedClassVersionError` ([#19024](https://github.com/OpenAPITools/openapi-generator/issues/19024)). На великих специфікаціях — `OutOfMemoryError` ([#11195](https://github.com/OpenAPITools/openapi-generator/issues/11195)). Для Flutter-команд Java — зайва залежність у CI.
→ **Урок:** чистий Dart CLI (`dart run` / `dart pub global activate`).

**P28. Обгортка для pub.dev відстає і ламає резолвінг.** Вбудований за замовчуванням OAG 7.17.0. `analyzer <9` конфліктує з Flutter ([gibahjoe#201](https://github.com/gibahjoe/openapi-generator-dart/issues/201)). Повідомлення про помилки незрозумілі ([#202](https://github.com/gibahjoe/openapi-generator-dart/issues/202)). Прапорці нормалізатора недоступні.
→ **Урок:** R15.1 — не робити генератор залежним від `analyzer` у звичайному шляху (CLI-first). Якщо є інтеграція з build_runner, вона має бути тонкою і окремо версіонованою.

**P29. Глобальний стан і `dart:io` у `dart`.** `var defaultApiClient = ApiClient();`, `import 'dart:io'` (перевірено в коді).
→ **Урок:** R4.3 — жодних глобальних змінних. Платформо-незалежний код.

**P30. OAS 3.1 у «beta», 3.2 не підтримується, невідоме мовчки відкидається** ([#22728](https://github.com/OpenAPITools/openapi-generator/issues/22728), [#24212](https://github.com/OpenAPITools/openapi-generator/issues/24212)).
→ **Урок:** R0.1/R1.4/R2.5 — власна модель специфікації з повною семантикою 3.1 (а не пониження до 3.0). Невідомі ключі або методи — warning з pointer.

**P31. Нормалізатор вгадує мовчки.** Самопосилання замінюються на any. Непідтримувані підсхеми `allOf` видаляються з DEBUG-логом. Map без типу значень стає `String`. Винятки нормалізатора ковтаються (перевірено в коді).
→ **Урок:** R2.2/R2.5 — кожна така дія є діагностикою з кодом і pointer та має рівень, який можна перевизначити.

---

## 6. Що варто запозичити

| Ідея з OAG | Для якої вимоги | Як покращити |
|---|---|---|
| Іменовані правила нормалізатора, що вмикаються окремо, з набором «on за замовчуванням» і `DISABLE_ALL` | R2.1 | Додати код, pointer, звіт і рівень. Документацію кожного правила — з **diff «до/після»**, як у `REPLACE_ONE_OF_BY_DISCRIMINATOR_MAPPING` у docs |
| Конкретні правила: `SIMPLIFY_ONEOF_ANYOF` (null-варіант → nullable, одиночний варіант → сама схема), `SIMPLIFY_ONEOF_ANYOF_ENUM`, `REFACTOR_ALLOF_WITH_PROPERTIES_ONLY`, `FIX_DUPLICATED_OPERATIONID`, `REMOVE_PROPERTIES_FROM_TYPE_OTHER_THAN_OBJECT`, `LOOSE_NULL_DEFINITIONS`, `ADD_UNSIGNED_…` | R2.1, R5.2 | Взяти як стартовий каталог правил. Кожне спрацювання — info-діагностика |
| `FILTER` із синтаксисом `operationId:a\|b ; tag:x ; path:/v1 ; method:get` і маркер `x-internal` | R4.1 | Додати exclude, glob і **tree-shaking моделей** |
| `SET_TAGS_TO_VENDOR_EXTENSION`, `KEEP_ONLY_FIRST_TAG_IN_OPERATION` | R5.3 | Плюс мапінг «тег → ім'я класу» в override-ах |
| Сімейство мапінгів (`name`, `parameterName`, `modelName`, `enumName`, `operationIdName`, `inlineSchemaName`, `schemaMappings`, `typeMappings` + `importMappings`) | R3.1, R6.2 | Об'єднати в **один файл override-ів з адресацією за pointer / operationId / `Schema.prop`**. Невикористаний override → warning, override, що збігся зі специфікацією, → hint (R3.2). Перевіряти результат на зарезервовані слова |
| `schemaMappings` («bring your own model») | R6.2, R6.4 | Override «тип = зовнішній Dart-тип + import», зокрема для конвертів і дженериків |
| `inlineSchemaOptions` (`ARRAY_ITEM_SUFFIX`, `MAP_ITEM_SUFFIX`, `RESOLVE_INLINE_ENUMS`, `SKIP_SCHEMA_REUSE`) і пріоритет `title` | R5.4 | Ті самі налаштування, але дедуплікація за замовчуванням лише для enum з однаковим набором значень і з діагностикою |
| Підказка в лозі «set the `title` field or use inlineSchemaNameMapping» | R2.5 | Перетворити на діагностику з готовим YAML-фрагментом override |
| `extra['secure']` з описом security для інтерцепторів | R10.8 | Додати `operationId`, тег, семантику AND/OR вимог. Інтерцептори не нав'язувати |
| Сигнатура методу: `cancelToken`, `headers`, `extra`, `validateStatus`, `onSendProgress`, `onReceiveProgress` + повернення `Response<T>` | R10.5, R10.6 | Додати `Options? options` (таймаути) |
| Пара `xxx()` / `xxxWithHttpInfo()` у `dart` | R10.6, R11.2 | Аналог: `xxx()` повертає T, `xxxRaw()` / `Result` дає повний доступ |
| `Optional<T>` (`Absent`/`Present`) + трюк `@JsonKey(readValue: readOptionalValue)` із sentinel для розрізнення відсутнього ключа і null у json_serializable; `patchOnly` | R7.1–R7.3, відкрите рішення 7 | Зробити `sealed`. Підтримати й inline-тіла PATCH. Правило тристановості налаштовується (R7.2) |
| `enumUnknownDefaultCase` як концепція (у built_value — `fallback: true`) | R8.1 | Але зі збереженням сирого значення і забороною надсилати його |
| `splitOperationsByContentType` з детермінованим іменуванням `With<Subtype>` / `As<Subtype>` | R10.4, R10.6 | Взяти схему іменування для операцій з кількома media type |
| `.openapi-generator/FILES` + `--minimal-update` + `--dry-run` | R13.1, R14.1 | Маніфест для видалення застарілих файлів. Записувати лише змінені файли (дружньо до IDE і build_runner). `--dry-run` → повний diff і звіт про breaking changes |
| `--global-property debugOpenAPI / debugModels / debugOperations` (дамп нормалізованої специфікації і проміжної моделі в JSON) | R15.3, R2 | Команда `inspect` / `--emit-ir` для налагодження і golden-тестів IR |
| `validate --recommend` | R2.4, R15.6 | Режим `check` з тими самими діагностиками, що й генерація |
| `batch` з `!include` | R1.3 | Один конфіг з кількома специфікаціями |
| `bin/configs/*.yaml` + закомічені `samples/` як golden-и в CI | R15.3 | Плюс `dart analyze` і runtime-тести декодування на кожному golden |
| `x-enum-varnames` / `x-enum-descriptions` / `x-enum-values` | R8.4 | Підтримати, задокументувати в реєстрі `x-` |
| `--model-name-prefix/suffix`, `--remove-operation-id-prefix` | R4.3, R5.1 | Узагальнити до regex-трансформацій |
| `NORMALIZER_CLASS` (власний нормалізатор як плагін) | Відкрите рішення 6 | Якщо потрібна розширюваність — Dart-API для правил, але лише після декларативних override-ів |

### Чого точно **не** повторювати (коротко)
1. Мовчазні виправлення і логи без кодів (P31).
2. Мапінги за сирим іменем без адресації та без виявлення застарілих (§4.3).
3. Зміну `Dio` користувача та жорсткі таймаути (P12).
4. `default` як успішну відповідь (P13).
5. Sentinel unknown-enum як реальне wire-значення (P11).
6. Перевірки в `assert` (P10).
7. Два серіалізаційні бекенди в одних шаблонах (P23).
8. Заглушки docs/test за замовчуванням (P21).
9. Зміни виходу в мінорних релізах (P25).
10. Java (P27).

---

## 7. Джерела

**Код OAG (master `9f6536eca424fd3ca139f01b7d1727d5912f396f`, 2026-10-09):**
- `docs/generators/dart-dio.md`, `docs/generators/dart.md`, `docs/customization.md` (Selective generation, Ignore file, Name/Schema Mapping, Inline Schema Naming, OpenAPI Normalizer), `docs/usage.md` (`validate`, `generate`, `batch`), `docs/global-properties.md`, `docs/installation.md`, `README.md` (L168 — 3.1 beta; L1264 — Dart TC), `pom.xml` (L1250 — Java 11)
- `resources/dart/libraries/dio/{api,api_client,pubspec,analysis_options,optional,model,class,header,lib}.mustache`, `auth/*.mustache`
- `resources/dart/libraries/dio/serialization/json_serializable/{class,enum,enum_inline,dart_constructor,deserialize,build.yaml}.mustache`, `api/{serialize,deserialize,query_param,imports,constructor}.mustache`
- `resources/dart/libraries/dio/serialization/built_value/{class,class_serializer,class_members,enum,api_util}.mustache`, `api/*.mustache`
- `resources/dart2/{apilib,api,api_client,api_helper,api_exception,pubspec}.mustache`, `serialization/native/{native_class,native_enum}.mustache`
- `java/.../languages/{AbstractDartCodegen,DartDioClientCodegen,DartClientCodegen}.java`, `java/.../{OpenAPINormalizer,InlineModelResolver,DefaultGenerator,DefaultCodegen}.java`
- `samples/openapi3/client/petstore/dart-dio/{petstore_client_lib_fake,petstore_client_lib_fake-json_serializable,oneof,anyof,oneof_polymorphism_and_inheritance}`; `bin/configs/dart*.yaml`

**Релізи:** https://github.com/OpenAPITools/openapi-generator/releases (v7.17.0–v7.26.0); v6.0.0 (breaking changes Inline model resolver).

**Issues/PR OAG** (https://github.com/OpenAPITools/openapi-generator/issues/N): #6123, #6160, #6750, #7057, #7310, #8179, #9029, #10295, #10972, #11195, #12127, #12161, #12306, #12489, #12645, #13302, #13372, #13584, #13931, #14320, #14472, #14522, #14904, #15373, #15448, #15449, #15477, #16708, #17222, #17677, #18380, #18647, #18913, #19024, #19284, #19420, #20495, #20682, #20910, #21297, #21318, #21411, #21473, #21508, #21510, #21565, #21570, #21815, #21826, #21837, #22043, #22120, #22160, #22399, #22547, #22561, #22728, #22744, #23665, #23866, #23978, #24177, #24212, #24703, #24736, #24858.
PR: #12104, #12295, #12353, #13047, #14346, #21667, #22257, #23386, #23571, #23696, #23930, #24352, #24585, #24605, #24673, #24706, #24868, #24881.

**Обгортка:** https://github.com/gibahjoe/openapi-generator-dart (master; `openapi-generator-cli/lib/src/models.dart`, `openapi-generator-cli/bin/main.dart`, `openapi-generator-annotations/lib/src/openapi_generator_annotations_base.dart`, `openapi-generator/lib/src/openapi_generator_runner.dart`, CHANGELOG-и, `openapi-generator/README.md`); issues #136, #151, #201, #202; https://pub.dev/packages/openapi_generator.

**pub.dev API** (`https://pub.dev/api/packages/<name>`, 2026-10-11): `one_of` 1.5.0 (2022-05-10), `one_of_serializer` 1.5.0 (2022-05-10), `openapi_generator*` 7.0.0 (2026-05-31), `copy_with_extension(_gen)` 18.0.0 (2026-09-26), `equatable` 3.0.0, `dio` 5.11.1, `json_serializable` 6.14.1, `built_value` 8.13.0, `time_machine` 0.9.17 (2022-04-16).

**Lints:** `package:lints` 6.1.0 `lib/recommended.yaml` (локальний pub-cache) — належність правил `slash_for_doc_comments`, `unnecessary_this`, `unnecessary_brace_in_string_interps`, `no_leading_underscores_for_local_identifiers`, `implementation_imports`, `annotate_overrides`.
