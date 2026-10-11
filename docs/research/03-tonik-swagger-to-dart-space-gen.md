# 03. Нові Dart-нативні генератори: tonik, swagger_to_dart, space_gen

Стан на **2026-10-11**. Порівняння з вимогами з `../requirements.md` (R0.1…R15.6 і відкриті рішення 1–7).

**Метод.** Репозиторії клоновано (`git clone`) і прочитано без запуску їхнього коду. Ключові знахідки про tonik і swagger_to_dart перевірено ще й в опублікованих версіях у pub cache (`tonik_generate-0.10.0`, `tonik_parse-0.10.0`, `tonik_core-0.10.0`, `swagger_to_dart-6.0.0`). Генератори не запускались. Згенерований код показано за golden-файлами та очікуваннями з юніт-тестів самих репозиторіїв.

| Репозиторій | Коміт, на якому читали код |
|---|---|
| tonik (`t-unit/tonik`) | `f58c84a9` (2026-10-06), на 30 комітів новіший за тег v0.10.0 |
| swagger_to_dart (`masreplay/api_spec_to_dart`) | `fb1e11b6` (2026-10-06) = 6.0.0 |
| space_gen (`eseidel/space_gen`) | `983088e8` (2026-07-21), main після 1.4.0 |

Посилання у форматі `tonik:path#Lx-Ly` ведуть на файл у цьому коміті. Базові URL є в розділі «Джерела».

**Позначки:** ✅ є і відповідає вимозі · ⚠️ є частково або із застереженням · ❌ немає або суперечить вимозі.
**Впевненість:** **(код)** перевірено в коді · **(доки)** взято з README, CHANGELOG, issue чи PR · **(не перевірено)** це висновок, у коді не підтверджений.

---

## 0. Коротко

| | tonik 0.10.0 | swagger_to_dart 6.0.0 | space_gen 1.4.0 |
|---|---|---|---|
| Вихід | готовий пакет без build_runner | анотований код (freezed + json_serializable + retrofit) + build_runner | готовий пакет без build_runner |
| HTTP | Dio (за замовчуванням) або `package:http` | Dio через retrofit | лише `package:http` |
| Серіалізація | власна (code_builder) | json_serializable + freezed | власна (Mustache-шаблони) |
| Runtime | `tonik_util` (~6.4k LOC, 0.x, версія спільна з генератором) | немає власного; retrofit, freezed_annotation, json_annotation | немає окремого пакета: `api_client.dart` та інші копіюються в кожен згенерований пакет |
| Головна сила | типізовані відповіді для кожного статусу; усі стилі параметрів; корпус інтеграційних тестів | широкий вхід (Swagger 2, Postman, JSON Schema); дженерики FastAPI/.NET/ABP; `@Extras` з operationId | чиста архітектура фаз; JSON Pointer на кожному вузлі; round-trip тести на GitHub і Discord |
| Головна слабкість для R0.2 | падає на першому дефекті без вказівки місця; немає override-ів типу/required; немає tree-shaking | null у JSON-тілах; enum `unknown` можна надіслати; cookie йдуть як header | Dio відсутній; enum кидає виняток; немає конфігу (фільтри, override-и); transport-збій → `ApiException(400)` |

**Вердикти щодо тверджень автора:**
- **(a) `validateStatus: (_) => true` у tonik.** **Правда**, але лише для HTTP-статусів 4xx/5xx. Транспортні збої (таймаут, з'єднання, скасування) далі проходять через `onError`. Користувач не може виправити це через `BaseOptions`, бо опції запиту мають пріоритет.
- **(b) Явний `null` для незаданих optional-полів.**
  - **tonik: частково.** Optional + non-nullable поле опускається. Optional + nullable поле відправляється як `"x": null` завжди. Це саме патерн FastAPI `Optional[X] = None` і NestJS `@ApiPropertyOptional() x?: T | null`.
  - **swagger_to_dart: правда** для JSON-тіл при документованій конфігурації. Надсилаються null для **всіх** незаданих optional-полів, і nullable, і non-nullable. Поле з `default` надсилає значення за замовчуванням. Form і multipart null не шлють (з 6.0.0).
- **(c) tonik губить сире значення невідомого enum.** **Правда.** За замовчуванням (`generateUnknownCase: false`) невідоме значення взагалі ламає декодування всієї відповіді. З опцією воно перетворюється на фіксоване `unknown` (`'unknown'` або `-1`), а сире значення губиться. Надіслати `unknown` не можна: `toJson` кидає `EncodingException`, тобто R8.2 ✅.

**Рішення 5: перевикористати `tonik_parse` / `tonik_core`?** **Ні, як фундамент.** Пакети прямо позначені як internal, мають версію 0.x і ламаються майже в кожному minor-релізі. Парсер падає на першому дефекті, не має JSON Pointer і source spans, відкидає обмеження, `x-*` і external `$ref`. Модель — це мутабельний IR, заточений під tonik і навіть зав'язаний на його runtime. Брати варто ідеї й тестовий корпус (деталі в розділі 4).

---

## 1. tonik

### 1.1 Огляд

| Параметр | Значення | Джерело |
|---|---|---|
| Остання версія | 0.10.0, 2026-09-07. Усі 5 пакетів (`tonik`, `tonik_core`, `tonik_parse`, `tonik_generate`, `tonik_util`) мають одну версію і виходять разом (melos) | pub.dev API; CHANGELOG |
| Перший реліз | 0.0.1, 2025-04-17. Усього 21 версія; minor-релізи приблизно раз на місяць (0.6 у березні, 0.7 у квітні, 0.8 у червні, 0.9 у липні, 0.10 у вересні) | pub.dev API |
| Популярність | 12★ і 4 форки на GitHub; 8 likes, ~2.0k завантажень за 30 днів, 160/160 pub points. `tonik_parse` і `tonik_core` мають ~2.05k завантажень, тобто майже стільки ж, скільки `tonik`: окремо їх фактично ніхто не використовує. Пошук `dependency:tonik_parse` знаходить лише `tonik` | GitHub API, pub.dev |
| Супровід | Дуже активний: 1663 коміти, ~320 PR, push 2026-10-10. Відкриті PR #324 (типізовані стріми NDJSON/JSONL/SSE) і #325 (JSON-seq) створено 2026-10-10. Issues майже не використовуються (5 за весь час), робота йде через PR | GitHub |
| Ліцензія | MIT | LICENSE |
| SDK | **Dart ≥ 3.13** і для генератора, і для **згенерованого пакета** (primary constructors, `class const Foo(...)`) | `tonik:packages/tonik_generate/lib/src/pubspec_generator.dart#L50-L62` (код) |
| Зрілість | 0.x. Тести: ~6.2k юніт-тестів, 41 інтеграційний пакет на кожен бекенд (за описом PR #324). Інтеграційні специфікації: asana, cloudflare, figma, github, kubernetes, openai, shopify, stripe, twilio, petstore та ін. (`integration_test/`). Для тестів використовується мок-сервер Imposter. Є приклади з реальними серверами: FastAPI, NestJS, Fastify, Spring Boot, Rails (`examples/`) | (код/доки) |

### 1.2 Архітектура

- **Пакети і шари.**
  - `tonik` — CLI і завантаження файлу.
  - `tonik_parse` — сирі DTO OpenAPI і `Importer`, що перетворює їх на `ApiDocument` з `tonik_core`.
  - `tonik_core` — IR (`ClassModel`, `AllOfModel`, `OneOfModel`, `AnyOfModel`, `EnumModel`, `Property`…), конфіг і трансформери (фільтри, override-и імен, deprecation, allOf-нормалізація).
  - `tonik_generate` — генерація через `code_builder` і форматування через `dart_style`.
  - `tonik_util` — runtime (кодеки стилів параметрів, `TonikResult`, `Date`, `OffsetDateTime`, `ServerConfig`, multipart, charset).
- **Потік у CLI.** `loadOpenApiDocument` → `Importer.import` → `ContentTypeNormalizer` → `ConfigTransformer` → `Generator`. Кожен крок загорнуто в `on Object catch` з виходом `exit(1)` і загальним повідомленням «Unexpected error…» (`tonik:packages/tonik/bin/tonik.dart#L114-L195`) (код).
- **Вихід.** Повний пакет: `pubspec.yaml`, власний `analysis_options.yaml`, `lib/src/{model,operation,api_client,server,response,…}`. На кожну операцію генерується окремий клас, і ще один API-клас на тег. `build_runner` не потрібен (доки `features.md`, код).
- **Серіалізація.** Власна. Кожна модель уміє `toJson`/`fromJson`, а також `toSimple`, `toForm`, `toLabel`, `toMatrix`, `toDeepObject`. Тобто модель серіалізується в усі контексти параметрів, а не лише в JSON. Імена типів кваліфікуються через `DartEmitter.scoped()`, тому схеми `Error`, `List` чи `Response` не конфліктують з `dart:core` (доки, код).
- **HTTP.** Dio (за замовчуванням) або `package:http`, вибір на етапі генерації. Запит іде через `client.requestUri(absoluteUri, …)` з `responseType: bytes` і `validateStatus: (_) => true` (`tonik:packages/tonik_generate/lib/src/operation/dio_operation_base_generator.dart#L340-L355`) (код).
- **Залежності згенерованого пакета.** `big_decimal`, `collection`, `dio` або `http`, `meta`, `tonik_util: ^0.10.0`, опційно `fast_immutable_collections`. Сам `tonik_util` залежить від `big_decimal`, `charset`, `collection`, `http_parser`, `meta` (код).

### 1.3 Покриття вимог

| ID | Статус | Деталі та доказ |
|---|---|---|
| R0.1 OAS 3.0 | ✅ | `features.md`: «Fully Supported» (доки) |
| R0.1 OAS 3.1 | ⚠️ | Є: `$ref` із сусідніми ключами, `$defs`, boolean schemas, `type: [T, "null"]`, `contentEncoding`. Немає: `const`, `if/then/else`, `prefixItems`, `patternProperties`, `$id`/`$anchor`/`$dynamicRef`, `unevaluated*`. `not` ігнорується з warning (`roadmap.md`; `model_importer.dart#L932-L937`) (доки/код) |
| OAS 3.2 | ❌ | `features.md`: «Planned». Хоча опис репозиторію на GitHub заявляє «3.0/3.1/3.2». `Importer` для 3.2 лише пише warning «attempting to parse permissively» (`tonik:packages/tonik_parse/lib/src/importer.dart#L108-L119`). Є окремі шматки 3.2, наприклад `dataValue` у прикладах (доки/код) |
| R1.1 | ✅ | Лише локальний JSON/YAML (`tonik:packages/tonik/lib/src/openapi_loader.dart`) (код) |
| R1.2 зовнішній `$ref` | ❌ | Це прямо non-goal у roadmap. Код: `throw UnimplementedError('Only local schema references are supported…')` (`tonik_parse/lib/src/model_importer.dart#L539-L544`). Прямий self-ref дає `ArgumentError` (`#L549-L552`) (код) |
| R1.3 | ✅ | `--config`/`-c` на кожен запуск (`tonik/lib/src/config/cli_parser.dart`) (код) |
| R1.4 `itemSchema` | ❌ (⚠️ у роботі) | Лише у відкритому PR #324 (доки) |
| R2.1 нормалізатор | ❌ | Іменованих правил немає. Частина дефектів «проковтується» мовчки: масив без `items` стає `AnyModel` без warning (`model_importer.dart#L908-L913`). Інші дефекти валять генерацію: `required: true` у схемі дає `TypeError` на `map['required'] as List<dynamic>?` (`tonik_parse/lib/src/model/schema.dart#L102-L104`) (код) |
| R2.2 діагностика | ❌ | Є лише `package:logging` (`log.warning`), без кодів і JSON Pointer. CLI на будь-якій помилці парсингу пише одне загальне «Unexpected error while parsing…»; деталі видно лише на рівні `fine` (`bin/tonik.dart#L132-L147`) (код) |
| R2.3–R2.4 | ❌ | Немає ні baseline, ні режиму check (код, доки) |
| R2.5 | ❌ | Інструмент вгадує мовчки. Невідомий дискримінатор: перебір усіх варіантів, перемагає перший, що розпарсився (`composite_data_types.md`; `one_of_generator.dart#L434-L446`, `#L531-L566`). Колізії імен вирішуються числовим суфіксом з логом на рівні `fine` (код) |
| R3.1 override-и | ⚠️ | `nameOverrides` для schemas, properties, operations, parameters, enums, tags, а також `x-dart-name` і `x-dart-enum`. `typeOverrides` позначено «Reserved for future use». Override-ів required/nullable/формату/дискримінатора/content-type немає (`configuration.md`) (доки) |
| R3.2 | ❌ | `name_override_applier.dart` не логує override, ціль якого не знайдено (код) |
| R3.3 | ❌ | — |
| R4.1 | ⚠️ | Є `includeTags`, `excludeTags`, `excludeOperations`, `excludeSchemas`. Немає include за `operationId`, фільтра за шляхами і glob (`filter_applier.dart`) (код) |
| R4.2 tree-shaking | ❌ | Фільтри змінюють лише `document.operations`; моделі не обрізаються (`tonik_core/lib/src/transformer/config_transformer.dart#L43-L65`) (код) |
| R4.3 | ✅ | Окремий пакет; scoped-імпорти (код) |
| R5.1 | ⚠️ | Імена з `operationId` плюс override. Regex-трансформацій немає (доки) |
| R5.2 | ⚠️ | Scoped emission і числові суфікси працюють, але без діагностики (код) |
| R5.3 | ✅ | Клас на тег; override імені тегу (доки) |
| R5.4 | ✅/⚠️ | Inline-імена беруться з позиції в документі. Дедуплікацію однакових inline-enum не знайдено (не перевірено) |
| R6.1 матриця | ⚠️ | 3 з 4 клітинок коректні (див. 1.4b). Окремого режиму для PATCH немає. `readOnly` виключається з запиту, `writeOnly` — з відповіді (доки, код) |
| R6.2 типи | ⚠️ | `date-time` → `OffsetDateTime`, `date` → `Date`, `decimal` → `BigDecimal`, `uri` → `Uri`, `binary` → `List<int>`, `byte` → `String`, будь-яке значення → `Object?`. Власне відображення примітивів неможливе (`typeOverrides` зарезервовано) (`data_types.md`) |
| R6.3 allOf | ⚠️ | Один член згортається в alias (`AllOfNormalizer`). Кілька членів дають клас-**композицію** з полем на кожну частину, а не пласку модель (`composite_data_types.md`) (доки/код) |
| R6.4 дженерики | ❌ | — |
| R6.5 | ⚠️ | Зайві поля ігноруються, якщо немає `additionalProperties`. Помилка декодування має `context: 'User.name'` (схема і поле), але не шлях у JSON (`class_json_generator_test.dart#L793`) (код) |
| R6.6 | ✅ | `==`, `hashCode`, `copyWith`, `toString` (тести `class_equals/hash_code/copy_with_*`) (код) |
| R6.7 обмеження | ❌ | Взагалі **не парсяться**: коментар «We ignore … maxLength, minLength, pattern» (`tonik_parse/lib/src/model/schema.dart#L153-L155`). Твердження в `features.md` «parsed but not enforced» неточне (код) |
| R7.1–R7.2 три стани | ❌ | Немає ні `Optional`/`Undefined`-типу, ні окремого PATCH-режиму (код) |
| R7.3 | ⚠️ | Див. 1.4b |
| R8.1 | ❌ | Див. 1.4c |
| R8.2 | ✅ | `toJson` для `unknown` кидає `EncodingException` (`enum_generator.dart#L436-L452`) (код) |
| R8.3 | ⚠️ | Рядкові та int enum є. Булевих немає: генератор кидає `ArgumentError` для типу, що не `String`/`int` (`enum_generator.dart#L52-L57`) (код) |
| R8.4 | ❌ | Підтримується лише власний `x-dart-enum`, `x-enum-varnames` — ні (код) |
| R9.1 | ⚠️ | `oneOf` стає sealed-класом, дискримінатор диспетчеризує за O(1). Варіанта «невідомий тип із сирим JSON» **немає**; при невідомому дискримінаторі йде перебір усіх варіантів (код) |
| R9.2 | ❌ | Без дискримінатора варіанти перебираються мовчки в «stable semantic order», без діагностики (`one_of_generator.dart#L494-L566`) (код) |
| R9.3 | ✅ | Змішані примітиви диспетчеризуються за runtime-типом (`one_of_generator.dart#L455-L492`) (код) |
| `anyOf` | ⚠️ | Клас із nullable-полем на кожну альтернативу, а не sealed-ієрархія (доки) |
| R10.1 | ❌ | Свій `Dio` передати можна (`ServerConfig.client(dio)`), але генерований сервер **мутує його**: `resolvedDio.options.baseUrl = baseUrl;` виконується і для чужого клієнта (`tonik_generate/lib/src/transport/dio_backend_generator.dart#L247-L255`). До того ж кожен запит має свої `Options` (`responseType: bytes`, `validateStatus`, `Accept`) (код) |
| R10.2 | ❌ | Див. 1.4a |
| R10.3 стилі | ✅ | Path: `simple`, `label`, `matrix`. Query: `form`, `spaceDelimited`, `pipeDelimited`, `deepObject`. Header і cookie теж є. Плюс `allowReserved` (`tonik_parse/lib/src/model/serialization_style.dart`; `request_parameter_importer.dart#L334-L390`; кодеки в `tonik_util/lib/src/encoding/*`). Параметри через `content` не підтримуються (non-goal). Невідомий `style` дає `FormatException` і валить генерацію (код) |
| R10.4 | ✅/⚠️ | JSON, multipart (типізовані частини, `encoding`, файли), `x-www-form-urlencoded` (лише пласкі схеми), `octet-stream`, `text/plain`, мапінг кастомних content-type (доки) |
| R10.5 | ⚠️ | Скасування є (`TonikCancellation`). Прогресу, додаткових заголовків на виклик, `extra` чи тегу `operationId` для інтерсепторів **немає**: у `Options` немає `extra` (`dio_options_generator.dart#L25-L34`); єдиний параметр методу — `cancellation` (`api_client_generator_test.dart#L1926-L1931`) (код) |
| R10.6 | ✅ | Окремий варіант на кожну пару статус + content-type, плюс `2XX` і `default`. 204 дає `void`. Заголовки відповіді типізовані. Нативна відповідь доступна в `TonikSuccess.response`. Charset для тексту (доки) |
| R10.7 | ⚠️ | API-клас конкретний (`class UsersApi`); замокати можна лише через `implements` або mocktail (код) |
| R10.8 | ⚠️ | Security потрапляє лише в doc-коментарі (`authentication.md`) (доки) |
| R10.9 | ✅ | Типізовані класи серверів, змінні, enum для змінних, `CustomServer` (доки) |
| R11.1 | ✅ | Типізовано за кожним статусом (доки, код) |
| R11.2 | ⚠️ | Є лише `TonikResult`, режиму з винятком немає. HTTP-помилки приходять у каналі **успіху** (`TonikSuccess(value: Response404)`) (доки) |
| R11.3 | ⚠️ | Незадокументований статус дає `ResponseDecodingException`, а потім `TonikError(type: decoding, response: …)`. Тобто він змішаний зі справжніми помилками декодування (`parse_generator.dart#L94-L117`) (код) |
| R11.7 | ✅ | `TonikErrorType.network/cancelled/encoding/decoding/other` окремо від варіантів відповіді (`tonik_util/lib/src/tonik_result.dart`) (код) |
| R12 SSE | ❌ (⚠️ у роботі) | Ще не випущено; PR #324 генерує `Stream<TonikResult<T,R>>` для NDJSON/JSONL/SSE з `itemSchema` (доки) |
| R13.1 | ⚠️ | Є стабільне сортування (`stable_model_key.dart`) і паралельні isolates. Згенерований вихід не комітиться, тому байтової golden-перевірки всього виходу немає (не перевірено) |
| R13.2 | ⚠️ | Генерує власний `analysis_options.yaml`: `lints/recommended` плюс **13 вимкнених правил** (`unused_import`, `dead_code`, `lines_longer_than_80_chars`…) (`analysis_options_generator.dart`) (код) |
| R13.3 | ⚠️ | Runtime чималий (~6.4k LOC) і версіонується разом із генератором (`^0.10.0`); у 0.x кожен minor ламає сумісність. Issue #59 якраз про розсинхрон версії `tonik_util` у згенерованому pubspec (код/доки) |
| R13.4 | ✅ | Описи, приклади, `deprecated` (annotate/exclude/ignore) (доки) |
| R13.5 | ⚠️ | Тест-заглушок немає. Але без tree-shaking розмір не пропорційний вибраним операціям (код) |
| R14.1–R14.2 | ❌/⚠️ | Звіту про зміни немає. Новий статус у специфікації ламає exhaustive `switch` у споживача (так задумано). Старий клієнт отримує `TonikError(decoding)` (доки/код) |
| R15.1 | ⚠️ | CLI є. Програмний API — через internal-пакети (доки) |
| R15.2 | ❌ | JSON Schema для `tonik.yaml` немає (код) |
| R15.3 | ✅ | Найсильніша сторона (див. 1.6) |
| R15.4 | ⚠️ | 0.x, breaking-зміни в 0.9 і 0.10 (CHANGELOG) |

### 1.4 Перевірка тверджень автора

#### (a) `validateStatus: (_) => true` → HTTP-помилки обходять `onError` (R10.2) — **ПРАВДА (код)**

Генератор опцій для Dio (`tonik:packages/tonik_generate/lib/src/transport/dio/dio_options_generator.dart#L25-L34`, `#L60-L65`; ідентично в опублікованому `tonik_generate-0.10.0`):

```dart
final options = refer('Options', 'package:dio/dio.dart').call([], {
  'method': literalString(_methodName(operation.method)),
  'headers': refer(r'_$headers'),
  'contentType': ?generated.contentType,
  'responseType': refer('ResponseType', 'package:dio/dio.dart').property('bytes'),
  'validateStatus': _validateStatus(),          // ← (_) => true
});
...
Expression _validateStatus() => Method((b) => b
  ..lambda = true
  ..requiredParameters.add(Parameter((b) => b..name = '_'))
  ..body = literalBool(true).code).closure;
```

Очікуваний згенерований код з юніт-тесту (`tonik_generate/test/src/operation/options_generator_test.dart#L52-L62`):

```dart
Options _options() {
  final _$headers = <String, dynamic>{};
  _$headers['Accept'] = r'*/*';
  return Options(
    method: 'GET',
    headers: _$headers,
    responseType: ResponseType.bytes,
    validateStatus: (_) => true,
  );
}
```

Уточнення до твердження:
1. Dio вважає **будь-який** статус успіхом. Відповіді 401, 404 і 500 проходять через `onResponse`, а не через `onError`. Типовий `QueuedInterceptor.onError` для 401 → refresh токена **не спрацює**. Логери чи Sentry, підвішені на `onError`, HTTP-помилок не побачать.
2. Транспортні збої (connection, timeout, cancel) **далі** йдуть через `onError`. tonik ловить `DioException` і повертає `TonikError(type: network|cancelled)` (`dio_operation_base_generator.dart#L347-L420`). Тобто твердження правдиве для HTTP-статусів, а не для всіх помилок.
3. Глобально це не виправити. Dio під час злиття бере `validateStatus` з `Options` запиту раніше, ніж з `BaseOptions` клієнта.
4. Обхідний шлях — інтерсептор, що в `onResponse` робить `reject(...)` для 4xx/5xx. Але тоді tonik отримає `DioException` і віддасть `TonikError(network)`, а типізований варіант `Response404` загубиться. Модель tonik «HTTP-помилка — це успішна відповідь потрібного типу» принципово не сумісна з R10.2. Це наслідок дизайну, а не недогляд.
5. Додатково `responseType: ResponseType.bytes` означає, що інтерсептори бачать у `response.data` байти, а не JSON. Звичні логери й інтерсептори, які розбирають тіло помилки, стають марними.
6. **Ще одна знахідка: порушення R10.1 (код).** `resolvedDio.options.baseUrl = baseUrl;` виконується і для клієнта, який передав користувач (`dio_backend_generator.dart#L247-L255`). Якщо один `Dio` спільний для кількох API або частин застосунку, tonik мовчки змінює йому `baseUrl`.

#### (b) Явний `null` для незаданих optional-полів (R7.3) — **ЧАСТКОВО ПРАВДА (код)**

`tonik:packages/tonik_generate/lib/src/model/class_generator.dart#L864-L875`:

```dart
final keyLiteral = specLiteralStringCode(property.name);
if (!requiredInRequest && !property.isNullable) {
  mapEntries..add(Code('if ($name != null) $keyLiteral: '))   // опускається
  ...
} else {
  mapEntries..add(Code('$keyLiteral: '))                      // завжди присутнє
  ...
}
```

Очікуваний вихід у тестах (`tonik_generate/test/src/model/class_json_generator_test.dart#L130-L210`):

```dart
// bio: isRequired: false, isNullable: true
Object? toJson() => {r'name': name, r'bio': bio};                        // bio == null → "bio": null
// nickname: isRequired: false, isNullable: false
Object? toJson() => {r'name': name, if (nickname != null) r'nickname': nickname};
```

| required | nullable | Поведінка tonik | Оцінка |
|---|---|---|---|
| так | ні | значення | ✅ |
| так | так | `"x": null` дозволено | ✅ |
| ні | ні | ключ опускається, якщо null | ✅ (захист є) |
| ні | **так** | **`"x": null` завжди**, навіть якщо поле не задавали | ❌ затирання |

Отже, «tonik надсилає null» правда лише для optional + nullable полів. Проте для цільової аудиторії (R0.2) це найчастіший випадок: FastAPI `Optional[str] = None` генерує `anyOf: [{type: string}, {type: null}]` без `required`. Тристанового представлення немає.

#### (c) tonik губить сире значення невідомого enum (R8.1) — **ПРАВДА (код)**

- За замовчуванням `generateUnknownCase: false` (`tonik/lib/src/config/config_loader.dart#L338`). `fromJson` кидає `JsonDecodingException('No matching … for value')`, і відповідь цілком стає `TonikError(decoding)`. Сирого значення немає, бо немає жодного значення.
- З `generateUnknownCase: true` трансформер додає **один фіксований** варіант для **всіх** enum документа: `EnumEntry(value: 'unknown')` для рядкових і `value: -1` для int (`tonik_core/lib/src/transformer/config_transformer.dart#L169-L183`). Згенерований `fromJson` (очікування з `enum_generator_test.dart#L2198-L2210`):

```dart
factory Status.fromJson(dynamic value) {
  if (value is! String) { throw JsonDecodingException(...); }
  return values.firstWhere(
    (e) => e._$rawValue == value,
    orElse: () => Status.unknown,   // ← вхідне 'archived' загублено; _$rawValue == 'unknown'
  );
}
```

Dart `enum` — це синглтони, тож зберегти вхідне значення в такій формі неможливо. Плюс у тому, що `toJson` для `unknown` кидає `EncodingException`, тому R8.2 виконано. Крім того, налаштування глобальне: увімкнути його для одного enum не можна.

### 1.5 Проблеми з трекера та коду і уроки

| Проблема | Посилання | Урок для нового інструменту |
|---|---|---|
| Runtime відкидав `Content-Type: application/json; charset=utf-8` з помилкою «Unexpected content type». Виправлено в 0.8.0 | [#165](https://github.com/t-unit/tonik/issues/165) | Порівнювати media type без параметрів і `+json`-суфіксів; тест на `charset` та `version=` |
| `anyOf` з `{enum: [null]}` від fastify-type-provider-zod генерував порожній клас | [#31](https://github.com/t-unit/tonik/issues/31) | Нормалізатор (R2.1) має знати ідіоми `null` у різних генераторах: `{enum:[null]}`, `{type:'null'}`, `nullable` поруч з `$ref` |
| Перенос рядка в рядку зі специфікації давав невалідний raw-літерал | [#88](https://github.com/t-unit/tonik/issues/88) | Один хелпер екранування для всіх літералів плюс fuzz-тести (у tonik згодом з'явився інтеграційний пакет `adversarial_strings`) |
| Згенерований pubspec посилався на застарілу версію `tonik_util` | [#59](https://github.com/t-unit/tonik/issues/59) | Runtime версіонувати окремо і стабільно (R13.3); перевіряти сумісність генератора й runtime в CI |
| Падіння на першому дефекті, загальне «Unexpected error» | `bin/tonik.dart#L132-L147` (код) | Збирати діагностику, а не кидати виняток; кожне повідомлення з кодом і pointer (R2.2) |
| YAML перетворюється на `Map` без source spans; `Context` — це шлях для імен з заміною `/` на `-` | `openapi_loader.dart#L59-L69`; `tonik_core/lib/src/util/context.dart#L5-L15,#L40-L44` (код) | Зберігати `YamlNode.span` і RFC 6901 pointer окремо від логіки іменування |
| Мовчазні евристики: невідомий дискримінатор, перебір варіантів oneOf, суфікси імен | (код, див. таблицю) | R2.5: кожна евристика або вимкнена за замовчуванням, або дає діагностику з пропозицією override |
| `validateStatus` + `bytes` + мутація `baseUrl` | 1.4a (код) | Не чіпати транспорт користувача; HTTP-помилки пускати через `onError` і типізувати вже після цього (R10.1, R10.2, R11.2) |
| Генерований пакет вимагає Dart ≥ 3.13 | `pubspec_generator.dart` (код) | Мінімальний SDK для згенерованого коду має бути консервативним і налаштовуваним |
| Документація розходиться з кодом: «constraints parsed», «3.2» в описі репозиторію | (код) | Матриця підтримки (R15.5) має генеруватись або перевірятись тестами |

### 1.6 Що варто запозичити

1. **Відповідь як sealed-клас на кожну пару статус + content-type**, з exhaustive `switch`. Це добра основа для R11.1 і R10.6. Але **поверх** звичайного шляху помилок Dio, а не замість нього.
2. **Кодеки всіх стилів параметрів** (`tonik_util/lib/src/encoding/*`: `simple`, `label`, `matrix`, `form`, `deepObject`, `pipe` і `spaceDelimited`, `allowReserved`, кодування ключів об'єктів). Це хороший «оракул» для тестів R10.3. Ліцензія MIT дозволяє адаптацію з атрибуцією.
3. **Scoped emission** (`DartEmitter.scoped()`): автоматичний префікс імпортів знімає цілий клас колізій з `dart:core` і Dio (R5.2).
4. **Корпус інтеграційних тестів**: ~40 специфікацій (github, stripe, kubernetes, openai, cloudflare, twilio, shopify, asana, figma, `adversarial_strings`, `naming`, `nullable_bodies`, `fastify_type_provider_zod`…) з мок-сервером Imposter (`integration_test/`).
5. **Приклади з реальними серверами**: docker compose з FastAPI, NestJS, Fastify, Spring Boot і Rails. Специфікація береться наживо, генерується клієнт, запускаються assert-и (`examples/README.md`). Готовий шаблон для рецептів R15.5 і для R0.2.
6. **`ServerConfig.client` / `.clientFactory` з явним володінням клієнтом** (хто закриває `Dio`): гарна семантика життєвого циклу. Але без мутації клієнта.
7. Charset-декодування текстових відповідей; підтримка `type/*` і `*/*`; `TonikCancellation`, незалежне від бекенда.

---

## 2. swagger_to_dart (репозиторій `masreplay/api_spec_to_dart`)

### 2.1 Огляд

| Параметр | Значення | Джерело |
|---|---|---|
| Остання версія | **6.0.0, 2026-10-06** (5.0.0 вийшла 2026-09-30, тобто два мажорні релізи за тиждень). Усього 58 версій з 2024-11-21 | pub.dev API, CHANGELOG |
| Популярність | 11★ і 4 форки; 26 likes, ~2.05k завантажень за 30 днів. Pub points за API 70/160 з тегом `has:error`; ймовірно, аналіз 6.0.0 ще не завершився | GitHub, pub.dev |
| Супровід | Активний сплесками: велика серія виправлень у 5.0.0 закрила більшість старих issues (#49–#64). Відкритих issues немає | GitHub |
| Ліцензія | MIT | LICENSE |
| Вхід | OpenAPI 3.0, 3.1, 3.2; Swagger 2.0 (конвертується в 3.0.3); Postman v1, v2.x, v3; JSON Schema (лише моделі); JSON або YAML; файл або URL | README (доки) |
| SDK | Генератор: Dart ≥ 3.9. Споживач: ≥ 3.8 (через json_serializable ≥ 6.10) | README |

### 2.2 Архітектура

- **Вхід.** `readSpecSync` або `loadSpec` → `toOpenApiJson` (конвертери Swagger 2, Postman і JSON Schema в OAS3 JSON) → freezed-моделі OpenAPI (`lib/src/schema/openapi/v3/*`; сам парсер теж на freezed і json_serializable) → «стратегії» генерації (regular, enum, union, typedef, generic) → `code_builder` → `dart_style` (код).
- **Вихід.** Анотований код, який потім обробляє `build_runner`:
  - `models/*.dart` — `@freezed` і `@jsonSerializable`;
  - `api_client/*_client.dart` — `@RestApi()` від retrofit;
  - `custom_api_client.dart`, `exports.dart`, `gen.dart`.

  Споживачу потрібні dev-залежності `build_runner`, `freezed`, `json_serializable`, `retrofit_generator` і `build.yaml` з порядком builders (README).
- **HTTP.** Dio через retrofit: `abstract class XClient { factory XClient(Dio dio, {String? baseUrl, ParseErrorLogger? errorLogger}) = _XClient; }`. Метод повертає `Future<HttpResponse<T>>` (доступ до статусу й заголовків), має `CancelToken`, `onSendProgress`, `onReceiveProgress` і `@Extras()` (golden `example/lib/src/gen/api_client/basic_client.dart`) (код).
- **Runtime.** Власного пакета немає. Залежності `dio`, `retrofit`, `freezed_annotation`, `json_annotation`.
- **Розмір виходу.** Кожна модель і enum має повну JSON-схему у вигляді doc-коментаря. У `example/` 20 425 з 41 488 рядків моделей — це `///`. `@Extras` вбудовує в кожен метод метадані операції (parameters, responses зі схемами) як `const` map (код).

### 2.3 Покриття вимог

| ID | Статус | Деталі та доказ |
|---|---|---|
| R0.1 3.0 / 3.1 / 3.2 | ✅/⚠️ | Парсинг 3.x, type arrays, nullable enum. Для 3.2 є метод `query` і `additionalOperations` → `@Method`. `itemSchema` немає (CHANGELOG 5.0, 6.0) |
| R1.1 | ⚠️ | Підтримується `url`, після якого автоматично **перезаписується** локальний `input_directory`. Якщо мережа недоступна, береться стара копія з голосним warning. Збірка відтворювана лише тоді, коли `url` не задано (README) |
| R1.2 | ⚠️ | Локальні `$ref` і pointer-ref усередину схем працюють, цикли параметрів ловляться. **Зовнішній** `$ref` → `FormatException('Cannot resolve $ref')`, бо `target = ref.startsWith('#/') ? spec : null` (`swagger_to_dart:packages/swagger_to_dart/lib/src/schema/openapi/v3/open_api.dart#L111-L125`) (код) |
| R1.3 | ✅ | `--config` (README) |
| R2.1 | ⚠️ | Частина дефектів проковтується мовчки: «a stray `required: true` is ignored» (`open_api_schema.dart#L19-L21`), Swashbuckle `additionalProperties: {}`, content без схеми (код/доки) |
| R2.2–R2.4 | ❌ | Є лише `print('swagger_to_dart: warning: …')`, без кодів і pointer (`lib/src/utils/warning.dart`) (код) |
| R2.5 | ⚠️ | Частина колізій дає warning. Але union без дискримінатора структурно вгадується за замовчуванням, а `enum_fallback_type: first/last` мовчки підставляє справжнє значення (README) |
| R3.1 | ⚠️ | Є: перейменування членів enum (`model.enums`), `remove_model_prefixes`, `class_prefix`, `skipped_parameters`. Override-ів типів, required/nullable і дискримінатора немає (README) |
| R4.1–R4.2 | ❌ | Фільтрів за тегами чи операціями немає; tree-shaking немає (README, конфіг) |
| R4.3 | ✅ | `class_prefix`, власна директорія (README) |
| R5.1–R5.4 | ✅/⚠️ | Дублікати `operationId` дістають числові суфікси. Колізії з Dio, retrofit і `dart:core` дають `Response2`. Зарезервовані члени (`hashCode`, `toJson`, …) обробляються. Inline-моделі називаються з контексту (`GetUserResponseAddress`), кліент створюється на кожен тег, non-ASCII теги підтримуються. Regex-трансформацій немає (CHANGELOG 5.0/6.0) |
| R6.1 | ⚠️ | Optional без default стає `T?`. Optional з default стає non-nullable `@Default(v)`. Розрізнити «відсутнє» й `null` неможливо (`property_generator_strategy.dart#L39-L60`) (код) |
| R6.2 | ⚠️ | Є `DateTime`, а `binary` стає `MultipartFile` (тип Dio в моделі). Для FastAPI у Flutter є `Color` і `TimeOfDay`. Змішані примітиви (`string|integer`) стають **`dynamic`** (README) |
| R6.3 | ✅ | `allOf` зливає властивості й `required` (рекурсивно, з захистом від циклів); один `$ref` розгортається в тип (CHANGELOG 5.0) |
| R6.4 | ✅/⚠️ | Справжні дженерики `class Foo<T>`, розпізнані за конвенцією імен фреймворку: FastAPI `Page[User]`, .NET `PagedResult<User>`, ABP з backtick. Це opt-in через `support_generic_arguments` і `generation_source` (`lib/src/generator/model/strategy/*_generic_parser.dart`) (код) |
| R6.5 | ⚠️ | json_serializable ігнорує зайві поля. Помилки декодування — стандартні cast-помилки, без шляху (не перевірено) |
| R6.6 | ✅ | freezed (`==`, `copyWith`, `toString`) |
| R6.7 | ❌ | Обмеження не генеруються |
| R7.1–R7.3 | ❌ | Див. 2.4b |
| R8.1 | ❌ | `unknown`, `first`, `last` — сире значення губиться (golden `enum_fallback_unknown/golden/models/status.dart.golden`) (код) |
| R8.2 | ❌ | `Status.unknown.toJson()` дає `'unknown'`, а `Level.unknown.toJson()` дає `-1` (min − 1). Це **можна надіслати** в запиті. З `first`/`last` надсилається чуже валідне значення (код) |
| R8.3 | ⚠️ | String і int є. Імена для невалідних ідентифікаторів: `value1`, `value2`… за позицією (CHANGELOG 6.0) |
| R8.4 | ❌ | `x-enum-varnames` парситься, але генератор його не використовує (`open_api_components.dart#L42`; інших використань `xEnumVarnames` немає) (код) |
| R9.1 | ✅ | Sealed-класи з пласким JSON. Opt-in fallback-варіант (`union_class_fallback_name`) **зберігає сирий `Map`** (README «Unions») (доки) |
| R9.2 | ⚠️ | Без дискримінатора варіант обирається **структурно за замовчуванням** (перемагає той, що має найбільше ключів; «No try-and-catch guessing»), а не через opt-in (README) |
| R9.3 | ⚠️ | Змішання з масивом чи об'єктом дає sealed-клас. `string|integer` дає `dynamic`. Змішані union у параметрах і тілах теж `dynamic` (README) |
| R10.1 | ✅/⚠️ | Користувач передає `Dio` і `baseUrl`; retrofit нічого не мутує. **Але** `servers` на рівні операції чи шляху вшиваються як абсолютний URL, і `baseUrl` для них ігнорується (CHANGELOG 6.0, G7) |
| R10.2 | ✅ | retrofit не задає `validateStatus`, тому діє дефолт Dio і 4xx/5xx дають `DioException`, а з ним `onError`. `retrofit_generator-10.2.9/lib/src/generator.dart#L1941-L1962` лише передає далі `validateStatus`, який задав сам користувач (код retrofit) |
| R10.3 | ❌ | Path, query і header є. **Cookie-параметр генерується як `@Header('<cookie name>')`**, тобто йде на дріт як заголовок з іменем cookie, а не як `Cookie: k=v` (`swagger_to_dart:…/api_client/api_client_generator.dart#L658-L671`). `style` і `explode` ігноруються (масиви кодує Dio за своїм `ListFormat`); `deepObject` немає (код) |
| R10.4 | ✅ | JSON, multipart (`MultipartFile`), urlencoded (`@Body(nullToAbsent: true)`), бінарні дані (`Uint8List`), `text/*` (CHANGELOG 5.0) |
| R10.5 | ⚠️ | Є `CancelToken`, прогрес і `@Extras` з `operationId` (`include_openapi_extras: true`). **Але** `extras` — це параметр зі значенням за замовчуванням. Якщо користувач передасть свої `extras`, `operationId` зникне. Додаткових заголовків на виклик немає (код golden) |
| R10.6 | ⚠️ | `HttpResponse<T>` дає статус і заголовки. Типізується **лише найменший 2xx**, а `application/json` перемагає `text/plain` (CHANGELOG 5.0) |
| R10.7 | ✅ | `abstract class` від retrofit |
| R10.8 | ⚠️ | Security лише як частина `@Extras` або doc (не перевірено) |
| R10.9 | ⚠️ | Змінні серверів підставляються зі значень за замовчуванням (CHANGELOG 6.0) |
| R11.1–R11.6 | ❌ | Типізованих помилок немає, лише `DioException` |
| R11.7 | ⚠️ | Розрізняється за `DioExceptionType`, але не на рівні типів |
| R12 | ❌ | — |
| R13.1 | ✅ | Golden-снапшоти на кожен fixture; `Recase` зробили stateless (раніше спільний стан між запусками впливав на імена, #63) |
| R13.2 | ⚠️ | Користувач має сам додати в `analysis_options` виключення для `*.g.dart` і `*.freezed.dart` та `invalid_annotation_target: ignore` (README) |
| R13.3 | ⚠️ | Окремого runtime немає, але споживач тягне retrofit, freezed і json_serializable разом з build_runner |
| R13.4–R13.5 | ⚠️ | Описи є, але плюс дамп JSON-схем (~50% рядків моделей) і повні метадані операцій у `@Extras` |
| R14 | ❌ | — |
| R15.1 | ⚠️ | CLI є, бібліотечний API експортується (`loadSpec`, `toOpenApiJson`). Потрібен build_runner |
| R15.3 | ✅ | Fixture-цикл: golden плюс e2e-компіляція (`build_runner` + `analyze`) плюс `roundtrip_test.dart.tmpl`. Для Postman: кожен збережений приклад відповіді має декодуватись і закодуватись назад. Тести валідують вхід і вихід конвертерів офіційними JSON Schema OAS 2.0, 3.0, 3.1, 3.2 (`schemas/README.md`) (доки) |
| R15.4 | ⚠️ | Semver дотримано, але мажорні релізи часті (5.0 і 6.0 за тиждень) |

### 2.4 Перевірка тверджень автора

#### (b) Явний `null` для незаданих optional-полів — **ПРАВДА для JSON-тіл (код)**

1. Глобальна анотація, яку застосовують до всіх моделей (`swagger_to_dart:packages/swagger_to_dart/lib/src/generator/model/json_serialization_convertor_generator.dart#L47-L50`):
   ```dart
   const jsonSerializable = JsonSerializable(
     converters: jsonSerializableConverters,
     explicitToJson: true,
   );                       // includeIfNull не задано → дефолт json_serializable = true
   ```
2. Поле: `@JsonKey(name: …)` без `includeIfNull`; optional поле стає `T?` (`property_generator_strategy.dart#L39-L60`).
3. Тіло: для JSON використовується `@Body()`, а `nullToAbsent: true` лише для urlencoded (`api_client_generator.dart#L330-L336`). CHANGELOG 6.0.0 каже прямо: «urlencoded … and multipart bodies no longer send the model's null fields. **JSON bodies are unchanged** (null and absent can differ there)».
4. Доказ із тестів. E2E-проєкт зібрано з `build.yaml` рівно таким, як у README, без `include_if_null` (`packages/swagger_to_dart_e2e/build.yaml`). Round-trip у `test/fixtures/class_prefix/roundtrip_test.dart.tmpl#L13-L24,#L39` очікує, що `toJson()` поверне `'info': null, 'auth': null, 'run': null, …` для елемента, де `Item.required == ['name']`. Тобто optional-поля серіалізуються як `null`.

Приклад згенерованої моделі з FastAPI (`example/lib/src/gen/models/conditional_body.dart`): поля `int? itemId` і `String? itemName` (у схемі `anyOf: [T, null]`, не required). `ConditionalBody(itemName: 'x').toJson()` дасть `{"item_id": null, "item_name": "x"}`, і PATCH затре `item_id`.

Уточнення:
- На відміну від tonik, null шлеться і для optional **non-nullable** полів, бо вони теж стають `T?`.
- Поле з `default` генерується як `@Default(v) T`. Якщо його не задати, у тіло піде значення за замовчуванням, а це інший спосіб затерти дані.
- Якщо користувач увімкне `include_if_null: false` у `build.yaml` (так зроблено в `example/build.yaml` самого репозиторію), null зникнуть **всюди**. Тоді required + nullable поле не зможе надіслати явний `null`. Тристановості немає за жодного налаштування. Користувач у [#50](https://github.com/masreplay/api_spec_to_dart/issues/50) прямо просив зробити це налаштовуваним: «backend accepting null, and others preferring no field».

#### (a) і (c) у swagger_to_dart

- (a) не стосується: R10.2 ✅.
- Невідомий enum поводиться так само, як у tonik (raw губиться), але гірше щодо R8.2: `unknown` можна надіслати (golden `status.dart.golden`).

### 2.5 Проблеми з трекера

| Issue | Суть | Урок |
|---|---|---|
| [#50](https://github.com/masreplay/api_spec_to_dart/issues/50), [#52](https://github.com/masreplay/api_spec_to_dart/issues/52) | До 5.0 **усі** поля були `required` і non-null незалежно від `required` у схемі | Матриця required × nullable — головна вимога, а не деталь (R6.1). Потрібні тести на кожну клітинку |
| [#55](https://github.com/masreplay/api_spec_to_dart/issues/55), [#61](https://github.com/masreplay/api_spec_to_dart/issues/61) | `Null check operator` на inline-enum без `title` (специфікація з 342 ендпоінтів) | Inline-сутностям потрібне детерміноване ім'я з контексту (R5.4); `!` на даних специфікації заборонений |
| [#59](https://github.com/masreplay/api_spec_to_dart/issues/59), [#60](https://github.com/masreplay/api_spec_to_dart/issues/60), [#64](https://github.com/masreplay/api_spec_to_dart/issues/64) | `'` і `\n` в описах давали невалідний код у `@Extras` і літералах | Один хелпер екранування для всіх літералів плюс тести на «ворожі» рядки |
| [#49](https://github.com/masreplay/api_spec_to_dart/issues/49), [#58](https://github.com/masreplay/api_spec_to_dart/issues/58) | freezed-union очікував конверт `{"value": …}`; union працював лише на корені схеми | Не використовувати union-кодогенерацію сторонніх пакетів для wire-формату; union будувати самим і пласко |
| [#56](https://github.com/masreplay/api_spec_to_dart/issues/56), [#54](https://github.com/masreplay/api_spec_to_dart/issues/54) | `text/plain` і `image/*` валили генерацію | Невідомий content-type має давати діагностику і fallback на `bytes`/`String`, а не падіння |
| [#63](https://github.com/masreplay/api_spec_to_dart/issues/63) | Stateful `Recase`: ім'я `id` ставало `iD` після того, як генератор зустрів `userID` | Нормалізація імен має бути чистою функцією від входу (R13.1) |
| CHANGELOG 6.0 (G7) | Сервери на рівні операції ламають `baseUrl` користувача | Сервери операції віддавати як метадані чи параметр, а не вшивати абсолютний URL |
| Код (2.3 R10.3) | Cookie шлються як header з іменем cookie | Тести «на дроті» для кожної локації параметра |

### 2.6 Що варто запозичити

1. **Fixture-цикл**: мінімальна специфікація на одну фічу чи issue, golden-снапшот, e2e-компіляція з `analyze`, `roundtrip_test.dart.tmpl` проти скомпільованого виходу (`CONTRIBUTING.md`).
2. **Round-trip на прикладах із самої специфікації**: кожен `example` відповіді має декодуватись і закодуватись назад. Безкоштовні runtime-тести для R15.3.
3. **Валідація конвертерів офіційними JSON Schema OAS** (2.0, 3.0, 3.1, 3.2) у тестах.
4. **`@Extras` з `operationId` і тегами** як механізм R10.5. Але без вбудовування всієї операції, і так, щоб користувацькі `extras` **зливались** з метаданими, а не замінювали їх.
5. **Розпізнавання дженериків за конвенціями фреймворків** (FastAPI `Page[User]`, .NET `<T>`, ABP backtick). Прямо відповідає R6.4 для цільової аудиторії.
6. **Fallback-варіант union із сирим `Map`**: майже R9.1, треба лише зробити його ввімкненим за замовчуванням.
7. Детальні migration notes у CHANGELOG для кожної breaking-зміни виходу (R15.4).

---

## 3. space_gen (`eseidel/space_gen`)

### 3.1 Огляд

| Параметр | Значення | Джерело |
|---|---|---|
| Остання версія | **1.4.0, 2026-07-19**. 8 версій; 1.0.0 вийшла 2025-09-04. Проєкт — хобі з серпня 2023 року | pub.dev, README |
| Популярність | **56★**, 5 форків, 26 відкритих issues. 3 likes, але **~39k завантажень за 30 днів**, ймовірно з CI: пакет використовують Shorebird (`shorebird_code_push_protocol`) і `quickpatch_code_push_protocol` (не перевірено). 130/160 pub points | GitHub, pub.dev, README |
| Супровід | Main не змінювався з 2026-07-21. Відкриті PR від контриб'юторів (#374 про unknown enum від 2026-09-10, #376 від 2026-10-01) не змерджені. Висока якість інженерії: покриття ~96.7% (codecov), детальні ARCHITECTURE.md і CHANGELOG | GitHub |
| Ліцензія | MIT | LICENSE |
| SDK | Генератор ≥ 3.8; згенерований пакет ≥ 3.10 (null-aware елементи, dot shorthands) | `lib/templates/pubspec.mustache`, PR #321 |

### 3.2 Філософія автора (Eric Seidel) і архітектура

Цінності з README:
- найякісніший сучасний Dart, «як написаний вручну»;
- нуль помилок аналізатора, форматера й лінтера;
- зрозумілі помилки;
- прагнення покрити весь OpenAPI 3.x;
- тестований код.

Принципи, сформульовані явно:
- **«Great Dart first; OpenAPI-Generator-shaped when convenient».** Форма openapi-generator — лише запасний варіант для полегшення міграції. Для міграції є «quirks»: `--openapi` вмикає `SCREAMING_CAPS` enum, мутабельні моделі, «списки за замовчуванням `[]`» тощо.
- **«We own the directories we declare, and nothing else».** Чистяться лише `generatedDirs`; README, LICENSE і `.github` не пишуться; є `--no-clear`.
- **«Lint suppression lives in the generated `.dart` files»**: точкові `// ignore_for_file:`, а не глобальне вимкнення правил, бо споживач може не взяти згенерований `analysis_options`.
- **Фази конвеєра — чисті функції, I/O лише в Load.**

Фази (ARCHITECTURE.md):
1. **Load** — `file:` і `http(s)`, кеш.
2. **Parse** — типізоване дерево `Spec`. **Кожен вузол `HasPointer` несе `JsonPointer`**, `$ref` лишається як `RefOr<T>`. Парсер рахує використані ключі (`markUsed`), і невикористані потрапляють у лог «Unused: … in <pointer>» (`parser.dart#L220-L245`).
3. **Resolve** — `ResolvedSpec`, `RefRegistry` з ключем «абсолютний URI», цикли через `ResolvedRecursiveRef`.
4. **Dispatch** — окрема фаза для `oneOf`/`anyOf`. Результат — sealed `DispatchDecision` (`Discriminator`, `Shape`, `Hybrid`, `Predicate`, `NoDispatch`) з IR предикатів (`KeyExists`, `ArrayElementHasKey`, `Always`).
5. **Naming** (в роботі) — **глобальний** прохід, що будує `Map<JsonPointer, String>`; «the resolver stays Dart-blind».
6. **Render** — `RenderSpec` і Mustache-шаблони. Типи — структурований `DartType`; для виразів планується власний IR, а `code_builder` розглянули і відхилили (`doc/dart_expression.md`).

Вихід: готовий пакет без build_runner. Runtime-хелпери (`api_client.dart`, `api_exception.dart`, `auth.dart`, `model_helpers.dart`, `date.dart`) **копіюються** в пакет із переписуванням імпортів (`file_renderer.dart#L608`). Залежності пакета: `collection`, `http`, `meta`, `uri`; лінти `very_good_analysis`.

### 3.3 Покриття вимог

| ID | Статус | Деталі та доказ |
|---|---|---|
| R0.1 3.0 / 3.1 | ✅/⚠️ | Основне є: type arrays; ідіома `oneOf: [{type: null}, T]` згортається в `T?` (1.3.0); `const` (1.4.0). OAS 3.2 немає |
| R1.1 | ⚠️ | Шлях або URL, але локального знімка немає |
| R1.2 | ✅/⚠️ | **Зовнішні `$ref`**, включно зі split-spec, ref на цілий файл і довільний pointer (1.4.0, #315, #319). Відкрита проблема: однакові `#/components/schemas/Foo` у двох документах зливаються в один тип ([#358](https://github.com/eseidel/space_gen/issues/358); є лише warning) |
| R2.1 | ⚠️ | Частина дефектів обробляється з warning: `required` з неіснуючою властивістю відкидається (`parser.dart#L1622-L1640`); недійсний enum default (#353). Але парсер **строгий**: `_expectType` на першій невідповідності кидає `FormatException` («Path parameters must be required» теж помилка) |
| R2.2 | ⚠️ | **Кожне повідомлення має pointer**: `throw FormatException('$message in ${context.pointer}')` (`parser.dart#L212-L218`). Стабільних кодів і рівнів, що налаштовуються, немає. Зупиняється на першій помилці |
| R2.5 | ⚠️ | Непідтримані `style`, `explode` і `allowReserved` дають warning «not honored…» (`parser.dart#L324-L358`). Але oneOf без способу диспетчеризації генерує `throw UnimplementedError` у `fromJson`, тобто падіння в runtime (у Discord лишилось 6 таких заглушок) |
| R3, R4 | ❌ | CLI має лише `-i`, `-o`, `-v`, `--openapi`, `--clear` (`cli.dart#L42-L60`). Налаштування робиться через наслідування `FileRenderer`. Фільтрів, override-ів і tree-shaking немає |
| R5.2 | ⚠️ | Суфікс `_1` з warning. Глобальний naming-прохід у роботі (ARCHITECTURE «Phase 4.5») |
| R6.1 | ✅/⚠️ | **Повна матриця з 8 рядків** (required × nullable × default) у 1.4.0, PR [#321](https://github.com/eseidel/space_gen/pull/321). Optional non-nullable опускається через `'x': ?x`. **Optional + nullable лишається злитим**: `'omitWhenNull': dartIsNullable && !property.common.nullable` (`render_tree.dart#L4540`), тобто незадане поле піде як `null`, так само як у tonik. Тристановість винесено в [#213](https://github.com/eseidel/space_gen/issues/213) |
| R6.2 | ✅/⚠️ | **Окремий тип `Date` для `format: date`** (1.3.0); `byte` дає `Uint8List`. `int64` на web — відкрита проблема ([#185](https://github.com/eseidel/space_gen/issues/185)) |
| R6.3 | ✅ | `allOf` зливається в один клас, включно з вкладеними `allOf` і відкритими або map-членами (1.3.0, 1.4.0) |
| R6.6–R6.7 | ✅ | `==` і `hashCode` (Equatable-подібні); `validate()` для `min`/`max`/`pattern`/`minItems`/… (`templates/api_exception.dart`, розширення `ValidateNumber`, `ValidateString`, `ValidateArray`) |
| R7 | ❌/⚠️ | Див. R6.1; #213 відкрита |
| R8.1–R8.2 | ❌ | Невідоме значення: `orElse: () => throw FormatException('Unknown … value')` (`templates/schema_enum.mustache#L9-L16`); [#373](https://github.com/eseidel/space_gen/issues/373) відкрито. PR #374 пропонує sealed `StatusKnown`/`StatusUnknown(raw)`, де `toJson()` **повертає raw**. Це свідомо суперечить R8.2: «GET then PUT does not overwrite» |
| R8.4 | ⚠️ | `x-enum-descriptions` ✅; `x-enum-varnames` лише в TODO (`parser.dart#L226, #L1027`) |
| R9.1 | ⚠️ | Дискримінатор дає sealed-клас, але невідоме значення — `FormatException`, варіанта unknown немає (`schema_one_of.mustache#L5-L14`) |
| R9.2–R9.3 | ⚠️ | Без дискримінатора працює структурна диспетчеризація (shape/predicate) **за замовчуванням**, без діагностики; якщо диспетчеризація неможлива, генерується заглушка `UnimplementedError` |
| `anyOf` | ⚠️ | Рендериться як `oneOf`. Коментар у коді: «For multiple schemas, we just generate a oneOf, which is wrong» (`render_tree.dart#L866-L880`) |
| `readOnly`/`writeOnly` | ❌ | Ігноруються (`parser.dart#L1615-L1616`); [#186](https://github.com/eseidel/space_gen/issues/186) |
| R10 транспорт | ❌ для dio | Лише `package:http`. `ApiClient({Uri? baseUri, Client? client, defaultHeaders, readSecret})` нічого не мутує ✅. Немає скасування, прогресу, operationId і заголовків на виклик. Методів лише 5 (`delete`, `get`, `patch`, `post`, `put`) (`templates/api_client.dart`) |
| R10.3 | ❌/⚠️ | Підтримується лише `form` + `explode` true/false для query; решта стилів дає warning ([#100](https://github.com/eseidel/space_gen/issues/100)) |
| R10.4 | ✅ | JSON, multipart, octet-stream, text, form-urlencoded (1.4.0) |
| R10.6 | ⚠️ | Кілька статусів — через `multiStatus` і `switch`. Але повертається лише тіло; заголовків і статусу немає (`templates/api.mustache`) |
| R10.8 | ✅ | `security` перетворюється на **структурний** `AuthRequest` на операцію (`HttpAuth`, `ApiKeyAuth`, `OneOfAuth`, `AllOfAuth`); секрети отримуються через `readSecret` (`gen_tests/security/lib/api/default_api.dart`) |
| R11.1 | ⚠️ | `ApiException<T>` з тілом, типізованим лише за `default`/error-відповіддю |
| R11.7 | ❌ | **Транспортний збій перетворюється на `ApiException` з кодом 400**: `on SocketException … throw ApiException.withInner(HttpStatus.badRequest, …)` (`templates/api_client.dart#L150-L188`) |
| R12 | ❌ | — |
| R13.1 | ⚠️ | Згенерований вихід для GitHub (~1000 операцій) і Discord закомічено, CI падає на будь-якому diff ✅. Але генерація запускає `dart pub get` (мережа!), `dart format` і `dart fix --apply` (`render/formatting.dart#L475-L488`), тож результат залежить від версії SDK на машині |
| R13.2 | ✅ | `very_good_analysis`, точкові ignore-и; 1.4.0 на порядок зменшила кількість lint-ів `dart fix` на GitHub-регенерації |
| R13.5 | ⚠️ | **Генерує round-trip тести** на кожну схему в `test/gen/`. Корисно, але суперечить R13.5 «без заглушок тестів за замовчуванням» |
| R15.3 | ✅ | Реальні специфікації: GitHub, Discord (~511 схем), SpaceTraders, Train Travel, Backstage, Petstore. Кожна має проходити `dart analyze` і синтезовані round-trip тести (README «Tested specs») |

### 3.4 Перевірка тверджень автора

У завданні про space_gen тверджень немає. Але знахідка за R7.3 варта уваги: до 1.4.0 space_gen так само надсилав `{"x": null}` для **всіх** optional-полів, і автор описав це як «we produced the invalid payload automatically» (PR #321). Після виправлення поведінка збігається з tonik: optional + nullable поля все ще надсилають `null`.

### 3.5 Проблеми з трекера і уроки

| Issue | Суть | Урок |
|---|---|---|
| [#213](https://github.com/eseidel/space_gen/issues/213) | RFC 7396: як відрізнити «не змінювати» від «очистити» в PATCH. Автор: лише одна клітинка з восьми має три стани, і `T?` її не вміщує | Підтверджує R7.1–R7.2. Потрібен окремий тип (на кшталт `Optional<T?>`) або PATCH-режим, обмежений саме цією клітинкою |
| [#373](https://github.com/eseidel/space_gen/issues/373) і PR #374 | Користувачам потрібна стійкість до нових значень enum; PR пропонує sealed `Known`/`Unknown(raw)` | Підтверджує R8.1. Відкрите рішення 7: чи дозволяти надсилати `raw`. PR обирає «так» заради GET→PUT round-trip; R8.2 каже «ні». Варто зробити це політикою з дефолтом «заборонено» |
| [#100](https://github.com/eseidel/space_gen/issues/100) | `style` і `explode` відкидались: «silently producing wrong URLs… the API just 400s» | R10.3 потрібен від початку, а непідтримане має давати діагностику |
| [#358](https://github.com/eseidel/space_gen/issues/358) | Два документи з однаковим `#/components/schemas/Foo` зливаються | Ідентичність схеми — це **абсолютний URI документа + pointer**, а не pointer у документі |
| [#185](https://github.com/eseidel/space_gen/issues/185) | `int64` на web (dart2js) втрачає точність понад 2^53 | Потрібен налаштовуваний мапінг `int64` (`int`, `BigInt`, `String`); стосується R6.2 |
| [#186](https://github.com/eseidel/space_gen/issues/186) | Через ігнорування `readOnly` у запит доводиться передавати поля, які заповнює сервер (у GitHub таких 81) | Розділяти форми для запиту й відповіді або хоча б не вимагати `readOnly` у конструкторі запиту (R6.1) |
| [#372](https://github.com/eseidel/space_gen/issues/372) | oneOf із shape-диспетчеризацією недосяжний через батьківську властивість | Перевіряти не лише декодування union напряму, а й union як поле, елемент списку, тіло |
| [#271](https://github.com/eseidel/space_gen/issues/271), [#375](https://github.com/eseidel/space_gen/issues/375) | Невикористані імпорти і `public_member_api_docs` у споживача | R13.2: тестувати вихід під кількома наборами лінтів, а не лише під своїм |
| Код | Transport → `ApiException(400)`; `dart pub get` під час генерації; `UnimplementedError`-заглушки | R11.7; R13.1 (не залежати від мережі та `dart fix`); R2.5 (замість runtime-заглушки діагностика з override) |

### 3.6 Що варто запозичити

1. **Архітектура фаз** Load → Parse (з pointer) → Resolve → Dispatch → Naming → Render. Фази чисті, I/O лише на вході. Резолвер не знає про Dart. Це практично готова відповідь на рішення 5 щодо «ізоляції моделі специфікації від генерації».
2. **JsonPointer на кожному вузлі** і **облік невикористаних ключів** (`markUsed` / `_warnUnused`). Друге — дешевий спосіб знайти непідтримані ключові слова й `x-*` (R2.2, R15.5 «матриця підтримки»).
3. **Dispatch як окрема фаза з IR предикатів**. Добра основа для R9.2: «error / structural (opt-in) / raw» — це просто різні `DispatchDecision`.
4. **Глобальний прохід іменування** `Map<JsonPointer, String>` (R5.2, R5.4, R13.1).
5. **Явна матриця required × nullable × default з 8 рядків** і тест на кожну клітинку (PR #321). Варто взяти як специфікацію R6.1 і розширити дев'ятою «тристановою» клітинкою.
6. **Окремий тип `Date`** для `format: date`; **`AuthRequest` як структуровані метадані** на операцію (R10.8, для Dio — через `extra`).
7. **Політика «ми володіємо лише своїми директоріями»** і **ignore-и в самих файлах** замість глобальних (R4.3, R13.2).
8. **Регенерація реальних специфікацій у репозиторії з diff-gate у CI** (R13.1, R15.3). Але без `dart fix` і мережі під час генерації.

---

## 4. Чи можна перевикористати `tonik_parse` / `tonik_core` (рішення 5)

**Висновок: ні, як парсер і модель специфікації нового інструменту. Так, як джерело ідей, тест-оракул і корпус.**

| Критерій | Що є в tonik | Наслідок для нового інструменту |
|---|---|---|
| Статус API | README обох пакетів: «This is an internal package used by Tonik's code generation pipeline» (доки). Публічна поверхня `tonik_parse` — один клас `Importer({contentTypes, contentMediaTypes}).import(Map<String, dynamic>) → core.ApiDocument` (`tonik_parse/lib/tonik_parse.dart`, `importer.dart#L17-L106`) | Контракту стабільності немає. Сторонніх споживачів на pub.dev немає |
| Версіонування | 0.x; усі 5 пакетів випускаються разом; breaking-зміни в `tonik_parse`: 0.2.0, 0.9.0, **0.10.0 (3 шт.)**; у `tonik_core`: 0.2.0, **0.10.0 (2 шт.)** (CHANGELOG). Нові minor-релізи щомісяця | Доведеться пінити точну версію і переписувати адаптер майже на кожному релізі |
| SDK | `sdk: '>=3.13.0 <4.0.0'`, primary constructors скрізь (`class Importer({…})`) | Якщо новий інструмент ставиться як `dev_dependency` у Flutter-проєкт, вимога Dart ≥ 3.13 переходить на всіх користувачів |
| Толерантність до дефектів | Розбір через жорсткі `as`-касти: `json['openapi'] as String`, `(json['paths'] as Map<String, dynamic>)`, `(map['required'] as List<dynamic>?)` (`open_api_object.dart#L19-L39`, `schema.dart#L98-L141`). Близько 45 `throw` (`UnimplementedError`, `ArgumentError`, `FormatException`) і лише ~15 `log.warning` на весь пакет. **Перша ж помилка зупиняє весь імпорт** | R2.1–R2.5 неможливі без форку. Типові дефекти NestJS, FastAPI чи ASP.NET (`required: true`, невідомий `style`, зовнішній ref) валять генерацію |
| Місце в специфікації | YAML перетворюється на звичайний `Map` (spans губляться, `openapi_loader.dart#L59-L69`). `Context` — це шлях для **імен**: зрізає початкові `/`, замінює `/` на `-`, не екранує `~` (`context.dart#L40-L44`) | JSON Pointer і рядок/стовпчик для R2.2 і R3.1 (адресація override-ів) довелося б додавати в кожен DTO |
| Повнота моделі | Відкидаються: `minLength`, `pattern`, `minimum`… (`schema.dart#L153-L155`), `title`, `xml`, `externalDocs` схем, усі `x-*`, крім `x-dart-name` і `x-dart-enum`, кореневий `security` («We ignore security properties», `open_api_object.dart#L41`), `webhooks` | Заблоковано R6.7, R8.4, R6.4 (через `x-`), R12.2 (через `x-`) і правила нормалізатора, яким потрібні сирі дані |
| 3.1 і 3.2 | 3.1 частково (див. 1.3); 3.2 не підтримується, `itemSchema` лише в PR #324; external `$ref` прямо в non-goals | R1.2 ❌, R1.4 ❌ |
| Зв'язність з генератором tonik | `tonik_core` — це **знижений IR**, а не модель специфікації: `ClassModel`, `AllOfModel`, `AnyOfModel` з рішеннями tonik (allOf як композиція, anyOf як nullable-поля), `Property.isRequired/isNullable`. Поля **мутабельні** (`required var Set<Model> models`; трансформери змінюють їх на місці, `api_document.dart`, `allof_normalizer.dart`). Модель імпортує **runtime** `tonik_util` (`EncodingShape` в `model.dart#L7,#L11-L12`). Конфіг tonik (`FilterConfig`, `NameOverridesConfig`, `EnumConfig`) і трансформери теж живуть у `tonik_core` | Довелося б або жити з архітектурними рішеннями tonik, які розходяться з R6.3 і R9, або тягнути зайві залежності. Ізоляції «модель специфікації ↔ генерація» (суть рішення 5) тут немає |
| Ліцензія | MIT | Форк легальний; але форк + розходження = власний парсер з чужою історією |

**Що конкретно брати з tonik:**
1. **Корпус `integration_test/*`** і сценарії `adversarial_strings`, `naming`, `nullable_bodies`, `ref_siblings`, `type_arrays`, `boolean_schemas`, `fastify_type_provider_zod`. Перед копіюванням перевірити ліцензії самих специфікацій.
2. **Runtime-кодеки стилів параметрів** (`tonik_util/lib/src/encoding/*`) як еталон для порівняльних тестів.
3. Перелік граничних випадків з CHANGELOG 0.9 і 0.10: порожні масиви в query, `allowReserved`, кодування ключів об'єктів у form, charset. Це готовий чек-лист для тестів R10.3 і R10.4.

**Рекомендація для рішення 5.** Власний парсер у дусі space_gen:
- шар **lossless** DTO з `JsonPointer` + `SourceSpan` + `extensions: Map<String, Object?>` на кожному вузлі;
- **збір** діагностики замість винятків;
- окремий резолвер з ключем «абсолютний URI + pointer»;
- окремий **незмінний** семантичний IR, у якому немає нічого про Dart;
- фази dispatch і naming як окремі чисті проходи;
- нормалізатор (R2.1) і override-и (R3) працюють на рівні lossless-DTO або Overlay **до** резолву. Тоді pointer з діагностики прямо адресує override.

---

## 5. Зведена матриця за ключовими вимогами

| Вимога | tonik | swagger_to_dart | space_gen |
|---|---|---|---|
| R1.2 зовнішній `$ref` | ❌ | ❌ | ✅ (#358) |
| R2.2 діагностика з pointer | ❌ | ❌ | ⚠️ (є pointer, немає кодів, перша помилка) |
| R3 override-и | ⚠️ лише імена | ⚠️ лише імена/префікси | ❌ |
| R4.2 tree-shaking | ❌ | ❌ | ❌ |
| R6.1 матриця | ⚠️ 3/4 | ⚠️ | ✅ 7/8 (тристановості немає) |
| R6.3 allOf пласко | ⚠️ композиція | ✅ | ✅ |
| R6.4 дженерики | ❌ | ✅ (конвенції фреймворків) | ❌ |
| R7.3 не слати null | ⚠️ (opt+nullable шле) | ❌ (шле всі) | ⚠️ (opt+nullable шле) |
| R8.1 raw enum | ❌ | ❌ | ❌ (PR #374) |
| R8.2 не слати unknown | ✅ | ❌ | — (кидає при декодуванні) |
| R9.1 unknown-варіант з raw | ❌ | ✅ opt-in | ❌ |
| R10.1 не мутувати клієнт | ❌ (`baseUrl`) | ✅ | ✅ |
| R10.2 `onError` | ❌ | ✅ | — (http) |
| R10.3 стилі | ✅ усі | ❌ (+ баг cookie) | ⚠️ лише form/explode |
| R10.5 operationId у запиті | ❌ | ✅ (`@Extras`, з застереженням) | ❌ |
| R10.7 абстрактний API | ⚠️ | ✅ | ⚠️ |
| R11 типізовані помилки | ✅ (в каналі успіху) | ❌ | ⚠️ (лише `default`) |
| R11.7 transport ≠ HTTP | ✅ | ⚠️ | ❌ (400) |
| R12 SSE | ❌ (PR #324) | ❌ | ❌ |
| R13.1 детермінізм | ⚠️ | ✅ golden | ⚠️ (`dart fix` + мережа) |
| R15.3 реальні специфікації | ✅✅ | ✅ (fixtures) | ✅ (GitHub, Discord) |
| build_runner | ні | так | ні |
| Dio | ✅ | ✅ | ❌ |

---

## 6. Джерела

Базові permalink-и (усі посилання на код вище відносні до них):
- tonik: `https://github.com/t-unit/tonik/blob/f58c84a9ec9b6b93f8b146b07b933c100e811a81/`
- swagger_to_dart: `https://github.com/masreplay/api_spec_to_dart/blob/fb1e11b66629817003d808f7e7a8f186809c41ac/`
- space_gen: `https://github.com/eseidel/space_gen/blob/983088e85fa239820604d1b39f4b71d4292f7a3d/`

Ключові файли:
- tonik (a): [`packages/tonik_generate/lib/src/transport/dio/dio_options_generator.dart#L25-L65`](https://github.com/t-unit/tonik/blob/f58c84a9ec9b6b93f8b146b07b933c100e811a81/packages/tonik_generate/lib/src/transport/dio/dio_options_generator.dart#L25-L65); [`packages/tonik_generate/test/src/operation/options_generator_test.dart#L52-L62`](https://github.com/t-unit/tonik/blob/f58c84a9ec9b6b93f8b146b07b933c100e811a81/packages/tonik_generate/test/src/operation/options_generator_test.dart#L52-L62); [`packages/tonik_generate/lib/src/transport/dio_backend_generator.dart#L229-L256`](https://github.com/t-unit/tonik/blob/f58c84a9ec9b6b93f8b146b07b933c100e811a81/packages/tonik_generate/lib/src/transport/dio_backend_generator.dart#L229-L256); [`packages/tonik_generate/lib/src/operation/dio_operation_base_generator.dart#L320-L460`](https://github.com/t-unit/tonik/blob/f58c84a9ec9b6b93f8b146b07b933c100e811a81/packages/tonik_generate/lib/src/operation/dio_operation_base_generator.dart#L320-L460)
- tonik (b): [`packages/tonik_generate/lib/src/model/class_generator.dart#L810-L878`](https://github.com/t-unit/tonik/blob/f58c84a9ec9b6b93f8b146b07b933c100e811a81/packages/tonik_generate/lib/src/model/class_generator.dart#L810-L878); [`packages/tonik_generate/test/src/model/class_json_generator_test.dart#L130-L210`](https://github.com/t-unit/tonik/blob/f58c84a9ec9b6b93f8b146b07b933c100e811a81/packages/tonik_generate/test/src/model/class_json_generator_test.dart#L130-L210)
- tonik (c): [`packages/tonik_generate/lib/src/model/enum_generator.dart#L290-L452`](https://github.com/t-unit/tonik/blob/f58c84a9ec9b6b93f8b146b07b933c100e811a81/packages/tonik_generate/lib/src/model/enum_generator.dart#L290-L452); [`packages/tonik_core/lib/src/transformer/config_transformer.dart#L162-L183`](https://github.com/t-unit/tonik/blob/f58c84a9ec9b6b93f8b146b07b933c100e811a81/packages/tonik_core/lib/src/transformer/config_transformer.dart#L162-L183); [`packages/tonik/lib/src/config/config_loader.dart#L338`](https://github.com/t-unit/tonik/blob/f58c84a9ec9b6b93f8b146b07b933c100e811a81/packages/tonik/lib/src/config/config_loader.dart#L338); [`packages/tonik_generate/test/src/model/enum_generator_test.dart#L2167-L2215`](https://github.com/t-unit/tonik/blob/f58c84a9ec9b6b93f8b146b07b933c100e811a81/packages/tonik_generate/test/src/model/enum_generator_test.dart#L2167-L2215)
- tonik parse/core: `packages/tonik_parse/lib/src/importer.dart`, `…/model/schema.dart`, `…/model/open_api_object.dart`, `…/model_importer.dart#L539-L557`, `packages/tonik_core/lib/src/util/context.dart`, `…/model/api_document.dart`, `…/model/model.dart`, `packages/tonik/lib/src/openapi_loader.dart`, `packages/tonik/bin/tonik.dart#L114-L195`
- tonik docs: `README.md`, `docs/features.md`, `docs/configuration.md`, `docs/roadmap.md`, `docs/http_backends.md`, `docs/authentication.md`, `docs/composite_data_types.md`, `docs/additional_properties.md`, `CHANGELOG.md`, `examples/README.md`
- tonik issues і PR: [#31](https://github.com/t-unit/tonik/issues/31), [#59](https://github.com/t-unit/tonik/issues/59), [#88](https://github.com/t-unit/tonik/issues/88), [#165](https://github.com/t-unit/tonik/issues/165), [PR #324](https://github.com/t-unit/tonik/pull/324), [PR #325](https://github.com/t-unit/tonik/pull/325)
- swagger_to_dart (b): [`packages/swagger_to_dart/lib/src/generator/model/json_serialization_convertor_generator.dart#L47-L50`](https://github.com/masreplay/api_spec_to_dart/blob/fb1e11b66629817003d808f7e7a8f186809c41ac/packages/swagger_to_dart/lib/src/generator/model/json_serialization_convertor_generator.dart#L47-L50); [`…/model/strategy/property_generator_strategy.dart#L39-L60`](https://github.com/masreplay/api_spec_to_dart/blob/fb1e11b66629817003d808f7e7a8f186809c41ac/packages/swagger_to_dart/lib/src/generator/model/strategy/property_generator_strategy.dart#L39-L60); [`…/api_client/api_client_generator.dart#L320-L345`](https://github.com/masreplay/api_spec_to_dart/blob/fb1e11b66629817003d808f7e7a8f186809c41ac/packages/swagger_to_dart/lib/src/generator/api_client/api_client_generator.dart#L320-L345); [`packages/swagger_to_dart/test/fixtures/class_prefix/roundtrip_test.dart.tmpl`](https://github.com/masreplay/api_spec_to_dart/blob/fb1e11b66629817003d808f7e7a8f186809c41ac/packages/swagger_to_dart/test/fixtures/class_prefix/roundtrip_test.dart.tmpl); `packages/swagger_to_dart_e2e/build.yaml`; `packages/swagger_to_dart/example/build.yaml`
- swagger_to_dart інше: `…/api_client/api_client_generator.dart#L650-L680` (cookie → Header), `…/model/strategy/enum_model_generator_strategy.dart#L85-L170`, `test/fixtures/enum_fallback_unknown/*`, `…/schema/openapi/v3/open_api.dart#L111-L125`, `README.md`, `CHANGELOG.md` (5.0.0, 6.0.0), `CONTRIBUTING.md`, `schemas/README.md`
- swagger_to_dart issues: [#49](https://github.com/masreplay/api_spec_to_dart/issues/49), [#50](https://github.com/masreplay/api_spec_to_dart/issues/50), [#52](https://github.com/masreplay/api_spec_to_dart/issues/52), [#54](https://github.com/masreplay/api_spec_to_dart/issues/54), [#55](https://github.com/masreplay/api_spec_to_dart/issues/55), [#56](https://github.com/masreplay/api_spec_to_dart/issues/56), [#58](https://github.com/masreplay/api_spec_to_dart/issues/58), [#59](https://github.com/masreplay/api_spec_to_dart/issues/59), [#60](https://github.com/masreplay/api_spec_to_dart/issues/60), [#61](https://github.com/masreplay/api_spec_to_dart/issues/61), [#63](https://github.com/masreplay/api_spec_to_dart/issues/63), [#64](https://github.com/masreplay/api_spec_to_dart/issues/64)
- retrofit_generator 10.2.9 (pub cache): `lib/src/generator.dart#L1941-L1962`
- space_gen: `README.md`, `ARCHITECTURE.md`, `CHANGELOG.md` (1.3.0, 1.4.0), `CLAUDE.md`, `lib/src/parser.dart#L212-L245,#L300-L358,#L1615-L1640`, `lib/src/render/render_tree.dart#L866-L880,#L4540`, `lib/src/render/formatting.dart#L455-L488`, `lib/src/cli.dart#L42-L60`, `lib/templates/{api_client.dart,api.mustache,schema_enum.mustache,schema_one_of.mustache,schema_object.mustache,pubspec.mustache,analysis_options.mustache}`, `gen_tests/security/lib/api/default_api.dart`, `gen_tests/third_party/`
- space_gen issues і PR: [#100](https://github.com/eseidel/space_gen/issues/100), [#185](https://github.com/eseidel/space_gen/issues/185), [#186](https://github.com/eseidel/space_gen/issues/186), [#213](https://github.com/eseidel/space_gen/issues/213), [#271](https://github.com/eseidel/space_gen/issues/271), [#358](https://github.com/eseidel/space_gen/issues/358), [#372](https://github.com/eseidel/space_gen/issues/372), [#373](https://github.com/eseidel/space_gen/issues/373), [#375](https://github.com/eseidel/space_gen/issues/375), [PR #321](https://github.com/eseidel/space_gen/pull/321), [PR #374](https://github.com/eseidel/space_gen/pull/374)
- pub.dev API: `https://pub.dev/api/packages/{tonik,tonik_parse,tonik_core,tonik_generate,tonik_util,swagger_to_dart,space_gen}` і `/score`; `https://pub.dev/api/search?q=dependency:tonik_parse`
- GitHub API: `gh api repos/{t-unit/tonik, masreplay/api_spec_to_dart, eseidel/space_gen}`; `gh issue list` і `gh pr list` для кожного
