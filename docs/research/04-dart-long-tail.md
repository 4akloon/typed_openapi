# 04. «Довгий хвіст» Dart-екосистеми: інші генератори, великі SDK, будівельні блоки, SSE

Стан на **2026-10-11**. Сюди не входять OpenAPI Generator (dart / dart-dio), swagger_parser, swagger_dart_code_generator, tonik, swagger_to_dart і space_gen: їх розбирають інші документи.

**Як збирали.** Пошук на pub.dev за запитами `openapi`, `swagger`, `topic:openapi`, `openapi generator`, `kiota`, `chopper openapi`, `openapi freezed`, `openapi parser`, `server-sent events`, `topic:sse` тощо. Далі метадані pub.dev API і GitHub API, неглибокі клони репозиторіїв (лише читання коду) і чотири власні експерименти в окремому scratch-проєкті: парсинг через `package:yaml`, реакція типізованих моделей на дефекти, коерції YAML і відповідність SSE-парсерів WHATWG. Скрипти лежать у `scratchpad/longtail-exp/bin/` (`exp.dart`, `defects.dart`, `yaml_gotchas.dart`, `sse_conf.dart`).

Позначення: «дл/30д» — завантаження за 30 днів за даними pub.dev search API; «♥» — likes на pub.dev.

---

## 1. Зведена таблиця генераторів

| Генератор | Остання версія (дата) | ♥ / дл/30д | Стан | Тип виходу | Моделі / серіалізація | HTTP | OAS | Чим цікавий для нас |
|---|---|---|---|---|---|---|---|---|
| **degenerate** (blopker) | 0.5.0 (2026-09-10), перша — 2026-03 | 5 / 517 | активний, 1 автор | готовий код, CLI, без build_runner | власні `final class`, ручний `fromJson`, extension types | власний `ApiClient` + адаптери `degenerate_dio` / `degenerate_http` | 3.0, 3.1, частково 3.2 | `Omittable` (3 стани), сирі значення невідомих enum, `$Unknown` в union, юніони за статусами, SSE/JSONL з `itemSchema`, tree-shaking за тегом і шляхом, golden-тести на Stripe, GitHub, K8s, OpenAI, Cloudflare |
| **Kiota (Dart)** (Microsoft) | `microsoft_kiota_abstractions` 0.3.0 (2026-09-18) | 2 / ~21k | Dart у статусі **preview** | готовий код, CLI на .NET | власні `Parsable`, мутабельні моделі | `package:http` (`microsoft_kiota_http`) | 3.x (OpenAPI.NET) | Каталог іменованих правил валідації з вимкненням окремих правил, glob-фільтри `--include-path`/`--exclude-path` з `#METHOD`, lock-файл з хешем, порядок мапінгу помилок |
| **dynamite** (Nextcloud → provokateurin) | 0.6.0 (2026-03-27) | 2 / 165 | репозиторій перенесено 2026-04, з того часу тихо | `build_runner` | `built_value` | `package:http` + `dynamite_runtime` | «поширена підмножина» 3.0/3.1 | Мажорна версія генератора росте при breaking change у генерованому коді. Генератор під AGPL, runtime під BSD |
| **openapi_spec** (tazatechnology) | 0.15.0 (2025-08-03) | 7 / 3 832 | застоює ~14 міс. | Dart-скрипт / CLI | freezed + json_serializable | `package:http` | 3.0 (3.1 частково) | Раніше на ньому стояли клієнти davidmigloz (через форк). Модель + парсер + генератор в одному пакеті |
| **openapi_code_builder + openapi_base** (hpoul) | 1.8.1+1 (2026-02-10); у git 1.8.2-dev.7 (2026-10-08) | 16 / 327 | повільно живий | `build_runner` (`*.openapi.yaml`) | json_serializable | власний `RequestSender` (http) | 3.0, лише YAML | Генерує і клієнт, і серверні заглушки (shelf). Відповідь — тип на кожен статус |
| **florval** (encer-jp) | 0.4.1 (2026-07-10), перша — 2026-03 | 4 / 196 | активний | CLI → freezed (далі build_runner) | freezed 3 + json_serializable | **Dio користувача** (через Riverpod-провайдер) | 3.1, 3.0→3.1, 2.0 частково | sealed-юніон за статусами **без** `validateStatus: true` (ловить `DioException`), `JsonOptional<T>` для PATCH, Riverpod |
| **dart_openapi_generator** (AngeloAvv) | 0.4.0 (2026-09-28), перша — 2026-05 | 0 / 784 | активний | `build_runner` (single-pass trick) | ручні `final class` | Dio | 3.0–3.2, `$ref` лише в межах файлу, `anyOf` дає помилку | `SourceMap`: JSON-pointer → `SourceSpan` з `package:yaml` для діагностики |
| **openapi_flutter_gen** (PurpleSoft) | 0.2.12 (2026-08-31) | 0 / 178 | активний | CLI, без build_runner | ручні immutable-класи | Dio | 2.0, 3.x | Десеріалізація в Isolate. **Ліцензія AGPL-3.0 або комерційна** |
| **flap** (miracle101000) | 0.0.7 (2026-09-12) | 2 / 276 | ранній | CLI-бінарник на **Rust** | freezed + json_serializable | Dio або http | 2.0, 3.0, 3.1 | Шаблони Jinja2 можна перевизначати. Непідтримувані конструкції деградують у `dynamic` з warning |
| **koi_swagger_parser** (mrkoi-is) | 0.2.0 (2026-07-31) | 0 / 39 | ранній | CLI → Retrofit + freezed | freezed + json_serializable | Dio / Retrofit | 3.0, 3.1 | Мапінги моделей, полів і параметрів з діагностикою колізій. `x-enum-varnames` і fallback для невідомого enum |
| **openapi_retrofit_generator** / **openapi_sdk_gen** | 2.0.4 (2026-01-08) / 2.6.3 (2026-09-24) | 5 / 1 911; 0 / 997 | форки swagger_parser | CLI → Retrofit | json_serializable / freezed / dart_mappable | Retrofit + Dio | 2.0, 3.0, 3.1 | Показують, що swagger_parser форкають, бо upstream не встигає з фіксами |
| **open_api_client_generator** (BreX900) | 1.5.0 (2026-09-26) | 1 / 553 | повільно живий | CLI або Dart-скрипт | json_serializable та інші «codec»-и | Dio / http | 3.x | Підключувані `ClientCodec` і `SerializationCodec` |
| **dart_openapi_codegen** (famedly, Matrix) | не на pub, git | — | живий (2026-09) | CLI | власна | власна | 3.x, лише JSON | **Файл правил** (exclude, voidResponse, imports) і набір `.patch` до специфікації |
| **@sdk-it/dart** (npm) | 0.46.8 (2026-10-08) | 541 дл/міс на npm | активний | Node CLI | власна | — | 3.x | Генератор на TypeScript, для Dart це скоріше екзотика |
| **openapi_to_retrofit** (Seuketchi) | 0.1.0 (2026-08-14) | 0 / 53 | щойно з'явився, 0 pub points | CLI → Retrofit | json_serializable | Retrofit | 3.x | Обмеження зі специфікації переносить у декодери (R6.7) |
| openapi_freezed_dio_builder (jonasbark) | 0.9.7 (2024-06-05) | 29 / 28 | **мертвий** (форк hpoul) | build_runner | freezed | Dio | 3.0 | — |
| openapi_dart_common (dart-ogurets) | 5.1.2 (2026-06-25) | 4 / 2 101 | живий | runtime для Java/Maven-генератора | — | — | — | Окрема Java-гілка генерації, для нас нерелевантна |

Окрім цього на pub.dev є «шум»: генератори clean-architecture-каркасів зі Swagger. Це `flutter_feature_generator`, `swagger_dart_generator`, `api_generator`, `clean_api_codegen`, `nebula_api_studio` і `dart_swagger_to_models` (лише моделі). У кожного менше 130 дл/30д. Утиліта `openapi_enum_patch` (1.3.1, 2026-09-19) — це пре/пост-процесор для swagger_parser, який дає імена integer-enum. Сам факт її появи показує попит на override-и (R3) і `x-enum-varnames` (R8.4).

**Головне спостереження.** У 2026 році з'явилася хвиля нових генераторів: degenerate, florval, dart_openapi_generator, openapi_flutter_gen, flap, koi_swagger_parser, openapi_to_retrofit, форки swagger_parser. Майже всі мають одного автора, менше 1k завантажень за 30 днів, і частина явно написана з допомогою AI-агентів. **Жоден не будує продукт навколо неідеальних специфікацій**: немає іменованих правил нормалізації з кодами діагностики, файлу override-ів з адресацією елементів і baseline/ratchet. Найближчі за ідеєю — правила валідації Kiota і файл правил плюс патчі у famedly.

---

## 2. Короткі профілі

### 2.1 degenerate — найближчий за функціями (докладно)

Джерела: [pub](https://pub.dev/packages/degenerate), [GitHub](https://github.com/blopker/degenerate), README, TODO.md і код у клоні.

- **Архітектура.** Пайплайн `parse → normalize → lower to IR → emit` поверх `code_builder`. Парсер власний: `yaml` + власний `ref_inliner` з підтримкою зовнішніх файлів і циклів, віддалені `$ref` не підтримуються. Нормалізатор розплющує `allOf`, будує окремі моделі для запиту і відповіді за `readOnly`/`writeOnly` і визначає дискримінатори ([структура lib/src](https://github.com/blopker/degenerate/tree/main/packages/degenerate/lib/src)). Генератор містить ~11k рядків.
- **Модель даних.** Генерує `final class` з `const`-конструктором, `fromJson`/`toJson`, `copyWith`, `==`/`hashCode` і overflow-мапою для `additionalProperties`. Іменовані примітиви стають **extension types** (`extension type const UserId(String value)`). Enum — це `final class` зі статичними константами, де `fromJson` для невідомого значення **зберігає сирий рядок** (`isUnknown`). Для дискримінованих юніонів генерується `sealed` з `X$Unknown(json)`. Для недискримінованих `oneOf` (2–9 варіантів) — `typedef X = OneOf2<A,B>` з runtime-контейнера. `anyOf` — клас з кількома «view» і збереженим сирим JSON ([README: Data Classes / Enums / Unions](https://github.com/blopker/degenerate#data-classes)).
- **Три стани (R7).** Поле optional + nullable стає `Omittable<T?>`: відсутнє, `Omittable(null)` або значення. Є прапорець `--omittable=nullable|all|off` як «escape hatch» для серверів, що не відповідають специфікації ([README: Omittable](https://github.com/blopker/degenerate#omittable-fields-json-merge-patch)). Це майже дослівно R7.2. Значення `default` зі схеми **не** робить поле присутнім: для нього є окремий getter `fieldOrDefault`.
- **Відповіді.** `ApiResult<T,E>` з варіантами `ApiSuccess`, `ApiError`, `ApiParseException` і `ApiException`. Якщо відповідей кілька, генерується sealed-юніон за статусом і media type (`PostAuthSuccess200`, `…Success2xx`, `…SuccessUnknown(response)`) ([README](https://github.com/blopker/degenerate#request-and-response-models)). Це покриває R10.6, R11.1 і R11.3.
- **SSE / JSONL.** Для `text/event-stream` і `application/jsonl` з `itemSchema` метод повертає `Stream<T>` ([README: Streaming](https://github.com/blopker/degenerate#streaming)). Це єдиний генератор у моєму «хвості» з підтримкою SSE.
- **Фільтри.** `--tag` і `--path` з tree-shaking невикористаних типів. Теги порівнюються без урахування регістру, пробілів, `_` і `-` (R4.1, R4.2, R5.3). Є також `--unwrap-fields=result`, щоб розгортати конверти (R6.4, частково).
- **Тестування.** Snapshot-тести (golden) публічних специфікацій: Cloudflare, GitHub 3.1, Kubernetes, OpenAI, Shopify, Stripe, Twilio, «unhinged» 3.2. Для них виконується `dart analyze`, окремо є wire-тести рантайму ([Makefile](https://github.com/blopker/degenerate/blob/main/Makefile), [snapshots/public](https://github.com/blopker/degenerate/tree/main/snapshots/public)). Це практично готовий рецепт для R15.3.
- **Безпека генерації.** Issues [#15](https://github.com/blopker/degenerate/issues/15) («Escape spec-controlled strings at every code interpolation site») і [#18](https://github.com/blopker/degenerate/issues/18) («SpecString»: текст зі специфікації як окремий тип). Будь-який рядок зі специфікації в шаблоні — потенційна ін'єкція коду.
- **Проблеми відносно наших вимог.**
  - Dio-адаптер викликає `requestUri(..., validateStatus: (_) => true)` ([dio_api_client.dart](https://github.com/blopker/degenerate/blob/main/packages/degenerate_dio/lib/src/dio_api_client.dart)). Це та сама проблема, що в tonik: `onError` інтерсепторів Dio не спрацьовує для 4xx/5xx (**R10.2 ✗**). Інтерсептори в degenerate власні, у стилі OkHttp, а не Dio.
  - Діагностика — лише рядки `List<String> warnings` і `--verbose`. Немає кодів, JSON-pointer і рівнів (**R2.2 ✗**). Override-ів немає (**R3 ✗**).
  - Серіалізація власна, не json_serializable. Вихід за README «not formatted»: треба запускати `dart format` (R13.2).
  - SSE-парсер не обробляє `retry`, не перепідключається, приймає `id` з NUL і віддає неповну подію наприкінці потоку. Див. §5.
- **Що скопіювати:** семантику `Omittable` з режимами, `fieldOrDefault`, іменування статусних варіантів, моделі за напрямком (readOnly/writeOnly), набір snapshot-специфікацій із scorecard «0 issues», `SpecString`-дисципліну і `--unwrap-fields`.

### 2.2 Kiota (Microsoft) — продукт «для неідеальних специфікацій» в іншому стилі (докладно)

Джерела: [kiota README](https://github.com/microsoft/kiota), [kiota-dart](https://github.com/microsoft/kiota-dart), документація [using](https://learn.microsoft.com/en-us/openapi/kiota/using), [errors](https://learn.microsoft.com/en-us/openapi/kiota/errors) і [Dart quickstart](https://learn.microsoft.com/en-us/openapi/kiota/quickstarts/dart).

- **Статус Dart.** У таблиці підтримуваних мов README позначено 🛠️ «in preview» для генерації, abstractions, serialization і HTTP. Runtime-пакети мають версії 0.0.x–0.3.0; у serialization/http близько 20k дл/30д. Є відкриті Dart-баги: [#7807](https://github.com/microsoft/kiota/issues/7807) (код для Notion API не компілюється) і [#7997](https://github.com/microsoft/kiota/issues/7997) (недетермінована генерація на binary-юніонах — дзеркало нашого R13.1).
- **Форма API.** Request builders повторюють структуру URL: `client.posts.byPostId(5).getAsync()`. Моделі мутабельні (`Post()..title = …`), відповіді nullable, транспорт — лише `package:http` ([quickstart](https://learn.microsoft.com/en-us/openapi/kiota/quickstarts/dart)). Для Flutter-команд на Dio це не підходить. Проте один публічний клієнт Stripe для Dart, [stripe_api_client](https://pub.dev/packages/stripe_api_client), побудований на Kiota.
- **Що скопіювати.**
  1. **Іменовані правила валідації.** Кожне правило можна вимкнути окремо: `--disable-validation-rules <Name>|all`. Правила: `DivergentResponseSchema`, `GetWithBody`, `InconsistentTypeFormat`, `KnownAndNotSupportedFormats`, `MissingDiscriminator`, `MultipleServerEntries`, `NoContentWithBody`, `NoServerEntry`, `UrlFormEncodedComplex` ([using](https://learn.microsoft.com/en-us/openapi/kiota/using#--disable-validation-rules---dvr)). Це прямий прототип R2.1 і R2.2, хоча в Kiota правило лише попереджає і нічого не виправляє.
  2. **Фільтри шляхів.** `--include-path`/`--exclude-path` — glob-шаблони з суфіксом `#GET`. Семантика: «(немає include АБО збіг з include) І (немає exclude АБО немає збігу з exclude)» (R4.1).
  3. **`kiota-lock.json`.** Зберігає всі параметри генерації і хеш специфікації; без змін генерацію пропускають. Команда `kiota update` перегенеровує все за lock-файлами (R13.1, R1.3).
  4. **Порядок мапінгу помилок.** Точний код, потім діапазон `4XX`/`5XX`, потім `default`, потім базовий `ApiException` зі статусом і заголовками. Для незадокументованого статусу є стабільне повідомлення ([errors](https://learn.microsoft.com/en-us/openapi/kiota/errors)) (R11.1, R11.3). Розширення `x-ms-primary-error-message` позначає поле з текстом помилки (ідея для реєстру `x-`, R15.5).
  5. `--structured-mime-types` з q-вагами за RFC 9110 вирішує, для якого content-type будувати моделі (R10.4, R3.1 «content-type тіла»).

### 2.3 florval — правильний патерн для Dio

- Не створює власний HTTP-клієнт: генерує Riverpod-провайдер `apiDioProvider`, який користувач перевизначає своїм Dio ([README: Wire up your Dio](https://github.com/encer-jp/florval#5-wire-up-your-dio)) (R10.1).
- Генерований метод не вимикає `validateStatus`. Він обгортає виклик у `try { … } on DioException catch (e) { if (e.response != null) → типізований варіант; else rethrow; }` ([client_generator.dart](https://github.com/encer-jp/florval/blob/main/lib/src/generator/client_generator.dart)). Інтерсептори Dio бачать помилку в `onError`, а користувач отримує sealed-юніон за статусом з `…Unknown(statusCode, body)`. **Це саме та поведінка, яку вимагають R10.2 і R11.3.**
- Інші можливості: `JsonOptional<T>` для PUT/PATCH (R7), курсорна пагінація, `@Deprecated`, doc-коментарі. Як парсер використовує `openapi_spec_plus`.
- Мінуси: обов'язкова прив'язка до Riverpod для провайдера Dio, freezed плюс build_runner, SSE немає. У генераторі я не знайшов fallback для невідомих enum (`unknownEnumValue`), тож декодування, ймовірно, падає (R8.1 ✗).

### 2.4 dart_openapi_generator (AngeloAvv)

- `SourceMap`: обходить дерево `YamlNode` до конвертації в `Map` і індексує `SourceSpan` за JSON-pointer (RFC 6901 з екрануванням `~0`/`~1`) ([source_map.dart](https://github.com/AngeloAvv/dart_openapi_generator/blob/main/lib/src/parser/source_map.dart)). Помилки парсера несуть `sourceSpan`. Автор вважає, що для JSON спанів немає, але `loadYamlNode` дає їх і для JSON (перевірено, див. §4).
- `build_runner` у «single-pass» режимі: фабрика білдера заздалегідь парсить специфікацію і повертає реальний `buildExtensions`, щоб build_runner знав усі вихідні файли ([README: How it works](https://github.com/AngeloAvv/dart_openapi_generator#how-it-works)). Це наочна ілюстрація тертя між build_runner і генератором «один вхід → багато файлів» (відкрите рішення 1).
- Невідомий enum або дискримінатор → `ArgumentError` (R8.1 ✗, R9.1 ✗). `anyOf` дає помилку збірки. Cookie-параметри не підтримуються, видається warning.

### 2.5 dynamite (Nextcloud)

- `build_runner` + `built_value`. Власні моделі OpenAPI/JSON Schema на built_value, `rfc_6901` для pointer, `pattern_check.dart` для перевірки `pattern` (R6.7) ([pubspec](https://github.com/provokateurin/dynamite/blob/main/packages/dynamite/pubspec.yaml)).
- Версіонування: «if there is a breaking change in the generated code the major version of this package will be updated» ([README](https://pub.dev/packages/dynamite)). Це наш R15.4.
- Генератор під AGPL-3.0, runtime під BSD-3, і генерований код ліцензією не покривається. У квітні 2026 dynamite і клієнт `nextcloud` винесли з `nextcloud/neon` в особисті репозиторії автора ([neon PR #3205](https://github.com/nextcloud/neon/pull/3205)). Останній push — 2026-04-26, тож ризик застою високий.

### 2.6 openapi_spec (tazatechnology) і пов'язана історія davidmigloz

- Пакет поєднує моделі специфікації (freezed), парсер і генератори схем, клієнта (`package:http`) і сервера. Останній реліз 2025-08-03. Відкриті issues: «LateInitializationError» ([#84](https://github.com/tazatechnology/openapi_spec/issues/84)), compile error для `object` з `default: {}` ([#85](https://github.com/tazatechnology/openapi_spec/issues/85)) і запит «Replace freezed with dart_mappable» ([#74](https://github.com/tazatechnology/openapi_spec/issues/74)).
- davidmigloz генерував `openai_dart`, `googleai_dart` та інші клієнти у `langchain_dart` через **власний форк** `davidmigloz/openapi_spec` (git-залежність у [кореневому pubspec](https://github.com/davidmigloz/langchain_dart/blob/main/pubspec.yaml)). Зараз від нього **відмовився**, див. §3.

### 2.7 Решта коротко

- **openapi_code_builder** (hpoul) ([GitHub](https://github.com/hpoul/openapi_dart)): найстаріший нативний Dart-генератор (з 2020 року), build_runner, лише YAML, клієнт і сервер (shelf). Відкриті баги 2022–2025 про `additionalProperties: true`, специфікацію без `components` і `string:binary`. Повільно живий: два фікси у вересні–жовтні 2026.
- **openapi_flutter_gen**: Isolate-десеріалізація і sealed-відповіді. **AGPL або комерційна ліцензія** ([README](https://github.com/PurpleSoftSrl/openapi_flutter_gen#license)), тож копіювати код не можна. Невідомий enum → `ArgumentError`.
- **flap**: генератор на Rust (`flap-spec` → `flap-ir` → `flap-emit-dart`), бінарники під п'ять платформ, перевизначення шаблонів через minijinja, lock-файл на SHA-256 специфікації, «lenient loading» з деградацією в `dynamic` ([README](https://github.com/miracle101000/flap-dart#crate-responsibilities)). Мовчазна деградація в `dynamic` суперечить R2.5. Ідея lock-файлу та сама, що в Kiota.
- **koi_swagger_parser**: заявляє розділення на load, `$ref`, validation, IR, rendering і «safe incremental writes», мапінги моделей, полів і параметрів «with collision diagnostics», `x-enumNames`/`x-enum-varnames`, unknown enum fallback ([README](https://github.com/mrkoi-is/koi_swagger_parser)). Пакет новий, 39 дл/30д, тож заяви варто сприймати обережно.
- **openapi_retrofit_generator → openapi_sdk_gen**: «complete rework of swagger_parser», а потім форк цього форку. Відкриті баги «Nullable not respected» і «nullable: true ignored for single-ref allOf/oneOf» ([issues](https://github.com/westito/openapi_retrofit_generator/issues)). Саме цю болячку ми закриваємо в R6.1 і R6.3.
- **open_api_client_generator** (BreX900): підключувані `ClientCodec` (Dio/http) і `SerializationCodec` (json_serializable та інші) через Dart-API ([README](https://github.com/BreX900/mek-packages/tree/main/shelf_packages/open_api_client_generator)). Близько до нашого відкритого рішення 6 щодо розширюваності, але розвинено слабо.
- **dart_openapi_codegen** (famedly): генерує `matrix_api_lite`. Генерація керується [`rules/matrix.yaml`](https://github.com/famedly/dart_openapi_codegen/blob/main/rules/matrix.yaml) (секції `exclude`, `voidResponse`, `imports`) і **16 файлами `.patch`** до специфікації Matrix у [`scripts/`](https://github.com/famedly/dart_openapi_codegen/tree/main/scripts) (`no-one-of.patch`, `additional-properties.patch` тощо). Це живий приклад того, що «override-и + патчі специфікації» потрібні навіть для якісної специфікації.

---

## 3. Як генеруються великі Dart SDK

| SDK | Як зроблено | Деталі | Джерело |
|---|---|---|---|
| `openai_dart` 11.0.0, `anthropic_sdk_dart` 9.0.0, `googleai_dart` 13.0.0, `mistralai_dart` 8.1.0, `ollama_dart` 4.0.0 (davidmigloz) | **Вручну, з AI-агентами**, за специфікацією. Раніше — openapi_spec (форк) + freezed | Новий монорепозиторій `ai_clients_dart` створено 2025-12-19. Версії 1.0.0 — «complete reimplementation… Hand-crafted models (no code generation)», залежності лише `http`, `logging`, `meta`. Python-тулкіт `api_toolkit` з командами `fetch`, `review` («diff canonical vs candidate specs and report implementation gaps»), `scaffold` і `verify` | [ai_clients_dart](https://github.com/davidmigloz/ai_clients_dart), [spec-core.md](https://github.com/davidmigloz/ai_clients_dart/blob/main/docs/spec-core.md), [api-toolkit README](https://github.com/davidmigloz/ai_clients_dart/blob/main/.agents/shared/api-toolkit/README.md), [MIGRATION.md](https://github.com/davidmigloz/ai_clients_dart/blob/main/packages/openai_dart/MIGRATION.md), [старе місце](https://github.com/davidmigloz/langchain_dart/tree/main/packages/openai_dart) |
| `googleapis` | Власний генератор `discoveryapis_generator` з Google **Discovery** docs, не з OpenAPI | Згенерований код комітиться в репозиторій | [google/googleapis.dart](https://github.com/google/googleapis.dart) |
| `aws_client` (agilord, спільнота) | Власний генератор з JSON-моделей AWS SDK for JavaScript | Згенерований код комітиться | [agilord/aws_client](https://github.com/agilord/aws_client) |
| Appwrite (`appwrite` 27.0.0, Flutter SDK) | Власний `sdk-generator` на PHP з шаблонами Twig. Парсер `utopia-php/openapi` зводить OAS 2.0/3.0/3.1 до однієї канонічної моделі | Шаблони під кожну мову | [appwrite/sdk-generator](https://github.com/appwrite/sdk-generator) |
| Supabase (`supabase` 2.16.4 та ін.) | **Вручну** (postgrest, auth, storage, realtime, functions). Новий `supabase_typegen` генерує типи зі **схеми БД**, а не з OpenAPI | Рядки — zero-cost **extension types** поверх декодованого JSON-map. Окремі типи `Insert`/`Update` | [supabase-flutter](https://github.com/supabase/supabase-flutter), [supabase_typegen](https://github.com/supabase/supabase-flutter/tree/main/packages/supabase_typegen) |
| `matrix` 14.0.0 (famedly) | Власний `dart_openapi_codegen` + правила + `.patch` до специфікації | Див. §2.7 | [famedly/dart_openapi_codegen](https://github.com/famedly/dart_openapi_codegen) |
| `nextcloud` 9.0.0 | Власний `dynamite` (build_runner, built_value) | Див. §2.5 | [provokateurin/dynamite](https://github.com/provokateurin/dynamite) |
| `mastodon` 1.1.0 (abraham) | `openapi_generator` (обгортка над OpenAPI Generator) + **`lib/hacks.dart`**: патчі поверх згенерованого коду | «patches applied to the generated code to fix issues with the OpenAPI spec or the generator» | [mastodon_generator](https://github.com/abraham/mastodon_dart/tree/main/packages/mastodon_generator) |
| Stripe (немає офіційного Dart SDK) | `client_stripe` (Celest) згенеровано з `spec3.sdk.json` внутрішнім генератором. `stripe_api_client` (univelop) згенеровано Kiota | Обидва з низькою популярністю (до 210 дл/30д) | [celest-dev/dart-api-clients](https://github.com/celest-dev/dart-api-clients/tree/main/clients/stripe), [stripe_api_client](https://pub.dev/packages/stripe_api_client) |
| `pinecone` (tazatechnology) | openapi_spec | Останній реліз 2023-11 | [openapi_spec README](https://github.com/tazatechnology/openapi_spec) |
| Комерційні вендори | **Dart не підтримує ніхто** | Fern: TS, Python, Go, Java, C#, PHP, Ruby, Swift, Rust. Stainless: TS, Python, Go, Java, Kotlin, Ruby, PHP, C#, SQL. У Speakeasy Dart у документації немає | [Fern](https://buildwithfern.com/learn/sdks/introduction/overview), [Stainless](https://www.stainless.com/docs/), [Speakeasy](https://www.speakeasy.com/docs/sdks/create-client-sdks) |

**Що це показує.**

1. Серйозні автори **не використовують** універсальні Dart-генератори. Вони або пишуть код вручну (davidmigloz, Supabase), або пишуть власний генератор під свій формат (Google, AWS, Appwrite, Matrix, Nextcloud).
2. Ті, хто все-таки генерує з OpenAPI, **обов'язково латають** або специфікацію (Matrix: правила плюс 16 патчів), або згенерований код (Mastodon: `hacks.dart`). Це пряме підтвердження, що R2 і R3 — головна цінність продукту.
3. **Аргументи davidmigloz** за ручний код записані в [spec-core.md](https://github.com/davidmigloz/ai_clients_dart/blob/main/docs/spec-core.md):
   - мінімум залежностей («Runtime dependencies limited to `http` and `logging` ONLY»);
   - «Manual Serialization (No Codegen)… explicit control over wire formats»;
   - resource-based групування методів;
   - `copyWith` з sentinel `unsetCopyWithValue`;
   - enum з обов'язковим fallback.

   Тобто серйозні автори відмовляються не від генерації як такої, а від build_runner, freezed і зайвих runtime-залежностей. Генератор, що видає готовий чистий код з мінімальним runtime (R13.3), закриває саме ці причини.
4. **Урок про `sealed` і semver.** `openai_dart` випустив **11 мажорних версій** між 2026-03-03 і 2026-10-11, `googleai_dart` — 11 мажорних (3→13), `anthropic_sdk_dart` — 9 (дані з [pub.dev versions](https://pub.dev/packages/openai_dart/versions)). Причина видна в MIGRATION.md: «Adding variants to an existing sealed class can break an otherwise unchanged exhaustive switch». Кожна нова подія чи варіант у специфікації ламає код споживача, і це прямо стосується R14.2.
5. Схема «spec diff → звіт про gaps» з тулкіта davidmigloz — ручний аналог нашого R14.1.

---

## 4. Будівельні блоки для парсера (відкрите рішення 5)

### 4.1 Пакети

| Пакет | Версія (дата) | Роль | Позиції (line/col) | Коментар |
|---|---|---|---|---|
| [`yaml`](https://pub.dev/packages/yaml) | 3.1.4 (2026-08-28), dart-lang | Парсинг YAML **і JSON** у `YamlNode` | **Так**: `YamlNode.span` (`SourceSpan`) для кожного вузла, включно з ключами | Див. експерименти нижче |
| [`source_span`](https://pub.dev/packages/source_span) | 1.10.2 (2026-02-05) | `SourceSpan.message()` друкує фрагмент з підкресленням (у стилі rustc) | — | Готовий формат для людського виводу R2.2 |
| [`yaml_edit`](https://pub.dev/packages/yaml_edit) | 2.2.4 (2026-02-13) | Редагування YAML зі збереженням коментарів і відступів | так | Автоматичне оновлення baseline чи override-файлів (R2.3, R3.2: «можна прибрати») |
| [`checked_yaml`](https://pub.dev/packages/checked_yaml) | 2.0.4 (2025-06-05) | Помилки декодування конфігу з json_serializable зі спанами | так | R15.2: зрозумілі помилки конфігу |
| [`json_schema`](https://pub.dev/packages/json_schema) (Workiva) | 5.2.2 (2025-10-08), ♥45 | Валідатор JSON Schema draft 4/6/7/2019-09/2020-12 (у `constants.dart` є визначення до `draft2020_12`), `ValidationError` з `instancePath`/`schemaPath` | ні (лише pointer) | Валідація конфігу за JSON Schema (R15.2). Можлива опційна перевірка специфікації за мета-схемою OAS |
| [`json_schema_builder`](https://pub.dev/packages/json_schema_builder) (flutter/genui) | 0.1.7 (2026-09-01), ~125k дл/30д | Побудова і валідація 2020-12, помилки з `path` | ні | Альтернатива від labs.flutter.dev, ще 0.x |
| [`rfc_6901`](https://pub.dev/packages/rfc_6901) (f3ath) | 0.2.1 (2025-10-17) | JSON Pointer: читання і запис | — | Використовує dynamite. [`json_pointer`](https://pub.dev/packages/json_pointer) (2019) мертвий |
| [`rfc_6902`](https://pub.dev/packages/rfc_6902) (f3ath) | 0.3.1 (2025-11-04) | JSON Patch: add, remove, replace, move, copy, test | — | R3.3. [`json_patch`](https://pub.dev/packages/json_patch) (2021) застарів |
| [`json_path`](https://pub.dev/packages/json_path) (f3ath) | 0.9.0 (2025-12-11) | JSONPath за **RFC 9535**, проганяється через Compliance Test Suite | — | **Потрібен для Overlay 1.0**: `target` за специфікацією — «RFC9535 JSONPath» (`specs/overlay-1.0.0.md`). Готової реалізації Overlay для Dart на pub.dev не знайшлося |
| [`code_builder`](https://pub.dev/packages/code_builder) / [`dart_style`](https://pub.dev/packages/dart_style) | 4.12.0 / 3.1.13 | Емісія коду і форматування | — | Ними користуються degenerate, dynamite, dart_openapi_generator |
| Моделі OpenAPI: [`openapi_spec`](https://pub.dev/packages/openapi_spec) 0.15.0, [`openapi_spec_plus`](https://pub.dev/packages/openapi_spec_plus) 0.6.0, [`conduit_open_api`](https://pub.dev/packages/conduit_open_api) 7.0.0, [`open_api_forked`](https://pub.dev/packages/open_api_forked) (2022), [`open_api_specification`](https://pub.dev/packages/open_api_specification) 4.1.0, [`openapi_dart`](https://pub.dev/packages/openapi_dart) 0.2.0 | — | Типізовані моделі специфікації | **ні в жодного** | `openapi_spec_plus`: окремі freezed-моделі для v20, v30 і v31 (3.2 немає), `x-*` зберігає в `extensions`, `$ref` залишає сирим рядком без резолвера. `tonik_parse`/`tonik_core` 0.10.0 описано в документі про tonik |

### 4.2 Експерименти

**(а) `package:yaml` на JSON** (`bin/exp.dart`). Вхід — специфікація OpenAI з `ai_clients_dart`, 4.77 МБ JSON, Dart 3.13.1 JIT на macOS arm64:

- `jsonDecode` — **25 мс**, `loadYamlNode` — **225 мс**. Спани для JSON є: ключ `"/agents"` знайдено на `line 89375, column 5`, і `span.message(...)` друкує фрагмент з підкресленням.
- **Дублікати ключів**: `loadYamlNode('{"a":1,"a":2}')` кидає `YamlException: Duplicate mapping key` з позицією, а `jsonDecode` мовчки бере останнє значення. Для толерантного інструмента це окреме правило нормалізатора: diagnostic плюс «перемагає останній».

**(б) Коерції YAML 1.2** (`bin/yaml_gotchas.dart`):

| Що в YAML | Що повертає `package:yaml` |
|---|---|
| `responses: 200:` | **`int` 200** як ключ (`default` лишається `String`) |
| `info.version: 1.0` | **`double` 1.0** |
| enum `0x1F` | **`int` 31** |
| enum `1e3` | **`double` 1000.0** |
| `yes`, `no`, `on`, `off` | `String` (семантика YAML 1.2; інструменти на YAML 1.1 побачать bool) |
| `2024-01-01` | `String` |

Кожен рядок таблиці — кандидат на іменоване правило нормалізатора з warning. Початкову лексему можна відновити з `YamlScalar.span.text`.

**(в) Типізовані моделі на дефектах** (`bin/defects.dart`):

| Дефект | `openapi_spec_plus` 0.6.0 | `openapi_spec` 0.15.0 |
|---|---|---|
| `required: true` на властивості (стиль NestJS) | **кидає** `_TypeError: bool is not a subtype of List<dynamic>?` | OK (мовчки) |
| масив без `items` | OK | **кидає** `Failed to parse Schema: {type: array}` |
| `type: [string, null]` + `nullable: true` | OK | **кидає** |
| `info.version: 1.0` (число) | **кидає** `_TypeError` | **кидає** |
| порожній `$ref`, дублікати в enum | OK (мовчки) | OK (мовчки) |

Жодна помилка не містить ні JSON-pointer, ні рядка в файлі.

**Висновок для рішення 5.** Готового Dart-пакета з моделлю OpenAPI, позиціями в джерелі й толерантністю до дефектів **немає**. Пропонована архітектура:

1. Сирий шар: `loadYamlNode` для YAML і JSON + індекс JSON-pointer → `SourceSpan` за зразком `SourceMap` з dart_openapi_generator.
2. Нормалізатор (R2.1) працює **на сирому дереві**: виправлення типів, дублікати, `required: bool`, коерції YAML. Кожне спрацювання дає діагностику з pointer і span.
3. Лише після нормалізації дерево мапиться у власну типізовану модель або IR, ізольовану від генерації.
4. `$ref` (R1.2) — власний резолвер на `rfc_6901`. JSON Patch — `rfc_6902`, Overlay — `json_path`. Конфіг перевіряється через `json_schema` + `checked_yaml`, baseline редагується через `yaml_edit`.

---

## 5. SSE-пакети для Dart (R12)

### 5.1 Огляд

| Пакет | Версія (дата) | ♥ / дл/30д | Транспорт | Dio користувача? | Web | Reconnect / `Last-Event-ID` / `retry` | Оцінка (17 тестів WHATWG) | Примітки |
|---|---|---|---|---|---|---|---|---|
| [`sse_parser`](https://pub.dev/packages/sse_parser) | 0.1.0 (2026-05-31) | 0 / 562 | **лише парсер**, 0 залежностей | так: годуєш байтами з `ResponseBody.stream` | так (pure Dart) | — / зберігає lastId / колбек `onRetry` | **17/17** | Push-API (`feed`) і Stream-API. `close(dispatchPending: true)` вмикає поблажливий режим. MIT. Низька популярність, 1 реліз |
| [`launchdarkly_event_source_client`](https://pub.dev/packages/launchdarkly_event_source_client) | 3.0.0 (2026-06-25) | 3 / ~102k | `package:http` | ні | через браузерний `EventSource`: **method, body і заголовки відкидаються** («dropping unsupported configuration options») | backoff з jitter / **так** (`Last-Event-ID`) / поле `retry` ігнорує | **17/17** | Парсер у `src/` (не публічний API), прогнаний через contract-тести LaunchDarkly. Призначений для власних SDK LaunchDarkly |
| [`simple_sse`](https://pub.dev/packages/simple_sse) + [`simple_sse_dio`](https://pub.dev/packages/simple_sse_dio) | 2.0.0 / 1.0.1 (2025-11-11) | 1 / 178 (dio) | Dio або http | **так** (`DioSseClient([Dio? dio])`) | як у Dio (див. нижче) | ні / зберігає id / зберігає в події | 16/17 | Обрізає **всі** кінцеві `\n` у data. **Баг:** Dio-клієнт робить `.map(utf8.decode)` на кожен chunk, тож багатобайтний символ на межі chunk дасть `FormatException` ([dio_sse_client.dart](https://github.com/andyhorn/sse_client/blob/main/packages/simple_sse_dio/lib/src/dio_sse_client.dart)) |
| [`eventflux`](https://pub.dev/packages/eventflux) | 3.0.2 (2026-09-25) | **97 / ~20k** | `package:http`, на web `fetch_client` | ні (адаптер на `http.BaseRequest`) | так (fetch) | так / так / так | не запускав: залежить від **Flutter** | Відправляє подію на кожен порожній рядок, навіть без `data`. Видаляє U+2028/2029 з рядків. Чистий Dart не підтримує |
| [`flutter_client_sse`](https://pub.dev/packages/flutter_client_sse) | 2.0.3 (2024-08-28) | **110 / ~44k** | `package:http`, **статичний глобальний клієнт** | ні | — | фіксовані 5 с / ні / ні | не запускав (Flutter) | `substring(5)` лишає пробіл на початку data, кінцевий `\n` не обрізає. Невідоме поле → `print` і **перепідключення**. Найпопулярніший і найгірший за якістю |
| [`sse_channel`](https://pub.dev/packages/sse_channel) | 0.2.2 (2025-10-07) | 16 / ~99k | `http.Client` (можна передати свій) | ні | так | так / так / так | — | Обгортка `StreamChannel`, заточена під протокол `package:sse` |
| [`sse`](https://pub.dev/packages/sse) (dart-lang) | 4.2.0 (2026-04-08) | 93 / 8.5M | власний двонаправлений протокол SSE+POST | — | — | — | — | Документація прямо каже: «not intended to be a general purpose SSE package». Використовується DWDS |
| [`eventsource`](https://pub.dev/packages/eventsource) | 0.4.0 (2022-03-23) | 30 / 843 | http | ні | — | так | — | Мертвий |
| `degenerate_runtime.parseSseStream` | 0.5.0 | — | парсер | так | так | ні / так / ігнорує | 15/17 | Приймає `id` з NUL. Відправляє неповну подію в кінці потоку |
| `openai_dart` `SseParser.parseRaw` (ручний) | 11.0.0 | — | парсер | — | — | — | **9/17** | `trim()` значень, `id` не зберігається між подіями, `data` без значення ігнорується. Типовий приклад «самописного» парсера |

### 5.2 Тест WHATWG

Скрипт `bin/sse_conf.dart` порівнює парсери на 17 кейсах за [алгоритмом WHATWG](https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation):

- багаторядковий `data`;
- обрізання лише одного пробілу після двокрапки; збереження кінцевих пробілів;
- коментарі `:`;
- рядки, що закінчуються лише CR; CRLF, розрізаний між chunk-ами;
- UTF-8 символ, розрізаний між chunk-ами;
- BOM;
- `data` без значення → `""`;
- `event` без `data` не відправляється;
- `id` зберігається між подіями; `id` з NUL ігнорується;
- невідоме поле ігнорується;
- `event`-тип;
- неповна подія в кінці потоку відкидається;
- `[DONE]` проходить як звичайні дані;
- `data:\ndata:` → `"\n"`.

Підсумок: `sse_parser` 17, `launchdarkly` 17, `simple_sse` 16, `degenerate_runtime` 15, ручний парсер `openai_dart` 9.

Попутне спостереження: BOM коректно оброблено в усіх, навіть у парсерах без явного коду для BOM. Схоже, BOM на початку прибирає сам `utf8.decoder` у пайплайні тесту.

### 5.3 Dio і web — важливий розрив

- `dio_web_adapter` 2.2.2 (2026-09-04) досі побудований на `XMLHttpRequest` з `responseType = 'arraybuffer'` ([adapter_impl.dart](https://github.com/cfug/dio/blob/main/plugins/web_adapter/lib/src/adapter_impl.dart)). Тому `ResponseType.stream` на web віддає відповідь **цілком після завершення** ([dio#2268](https://github.com/cfug/dio/issues/2268), [#1795](https://github.com/cfug/dio/issues/1795)). Issues «ServerSendEvent support for Flutter Web» ([#1859](https://github.com/cfug/dio/issues/1859)) і «Use modern Fetch API» ([#1740](https://github.com/cfug/dio/issues/1740)) відкриті.
- Обхідний шлях, який радять самі maintainer-и: `Dio()..httpClientAdapter = ConversionLayerAdapter(FetchClient(...))` з [`dio_compatibility_layer`](https://pub.dev/packages/dio_compatibility_layer) 0.1.1 і [`fetch_client`](https://pub.dev/packages/fetch_client) 1.2.1. `fetch_client` підтримує потокову відповідь.
- Наслідок для R12.4 «транспорт через Dio користувача»: на мобільних і десктопі достатньо `ResponseType.stream`, а на Flutter Web потрібна документована вимога до адаптера Dio. Інакше стрім «працює», але без інкрементальності.

### 5.4 Прогалини

**Немає жодного пакета, що поєднує все одразу:**

1. повну відповідність WHATWG;
2. роботу поверх **Dio користувача**, щоб інтерсептори, auth і `onError` спрацьовували;
3. політику перепідключення з `Last-Event-ID` і `retry`, яку можна вимкнути;
4. чистий Dart без Flutter;
5. стрімінг на web.

**Рекомендація.** У runtime-пакеті потрібен власний маленький парсер (~150–250 рядків). Можна взяти за еталон `sse_parser` (MIT) або парсер LaunchDarkly (Apache-2.0) і прогнати наші 17 кейсів разом з SSE contract-тестами LaunchDarkly. Перепідключення — власна петля над `dio.request(..., responseType: stream)`.

---

## 6. Висновки

1. **Ніша вільна.** Ринок Dart-генераторів у 2026 році фрагментований: багато нових, але дрібних проєктів (degenerate, florval, dart_openapi_generator, openapi_flutter_gen, flap, koi_swagger_parser, форки swagger_parser). **Ніхто** не пропонує продуктовий шар для поганих специфікацій: іменовані правила нормалізації з кодами, override-файл з адресацією елементів, baseline/ratchet і режим `check`. Найближчі прецеденти — правила валідації Kiota (R2.1, R2.2), а також правила і патчі famedly (R3). Позиціювання за R0.2 конкурентно виправдане.
2. **Що взяти з degenerate:**
   - `Omittable` з режимами `nullable|all|off` → R7.2;
   - enum як `final class` із сирим значенням → R8.1;
   - `$Unknown` в union → R9.1;
   - sealed-юніони відповідей за статусом і media type → R10.6, R11.3;
   - SSE з `itemSchema` → R12.2;
   - tree-shaking за тегом і шляхом → R4.2;
   - snapshot-корпус публічних специфікацій → R15.3;
   - дисципліна екранування рядків зі специфікації (`SpecString`).

   **Чого не брати:** `validateStatus: (_) => true` і власні інтерсептори замість Dio-нативних.
3. **Що взяти з florval для R10.2:** не чіпати `validateStatus`, а ловити `DioException` з `response` і мапити його в типізований варіант або виняток. Тоді інтерсептори Dio отримують `onError`, а користувач — типізований результат. Dio вбудовує користувач, генератор нічого не налаштовує (R10.1).
4. **Що взяти з Kiota:**
   - каталог правил з іменами і `--disable-validation-rules`;
   - glob-фільтри з `#METHOD` і зрозумілою семантикою include/exclude;
   - lock-файл з хешем специфікації і параметрів (R13.1, R14.1);
   - порядок мапінгу помилок «код → діапазон → default → базовий» (R11.1);
   - `x-ms-primary-error-message` як ідея для реєстру `x-` (R15.5).

   Kiota Dart сам по собі не конкурент: він у preview, підтримує лише `http`, а моделі мутабельні.
5. **Великі SDK** або написані вручну (davidmigloz, Supabase), або побудовані власним генератором (Google, AWS, Appwrite, Matrix, Nextcloud). Ті, хто генерує з OpenAPI, латають специфікацію чи вихід. Головна претензія серйозних авторів — залежності і build_runner, а не генерація як така. Звідси аргумент для відкритих рішень 1 і 2: **готовий код без обов'язкового build_runner у споживача** і мінімальний runtime (R13.3). json_serializable при цьому виправданий лише тому, що його вимагає ТЗ; варто передбачити, що частина аудиторії захоче вихід без build_runner.
6. **Sealed і semver (R14.2, відкрите рішення 7).** Досвід `openai_dart` (11 мажорних версій за 7 місяців) показує: якщо відкриті множини (юніони подій і відповідей) генерувати як `sealed`, кожне доповнення специфікації стає breaking change для споживача. Варіанти рішення:
   - генерувати відкриті ієрархії не як `sealed`, а як `abstract`/`base`, щоб компілятор вимагав гілку за замовчуванням;
   - або дати прапорець `exhaustive: true|false` на рівні конфігу чи override-у;
   - і в будь-якому разі відображати це у звіті breaking changes (R14.1).
7. **Парсер (відкрите рішення 5).** Будувати власний сирий шар над `package:yaml`: спани і для YAML, і для JSON, ~0.2 с на 4.7 МБ. Нормалізувати на сирому дереві, а потім будувати типізовану модель. Готові моделі на кшталт `openapi_spec` чи `openapi_spec_plus` кидають винятки без позиції навіть на типових дефектах NestJS. Інструменти поруч: `rfc_6901`, `rfc_6902`, `json_path` (Overlay), `json_schema` + `checked_yaml` (конфіг), `source_span` (вивід), `yaml_edit` (baseline). Коерції YAML (int-ключі статусів, `version: 1.0`, `0x…` в enum) і дублікати ключів варто оформити як окремі іменовані правила нормалізатора.
8. **SSE (R12).** Писати власний парсер у runtime, тестувати на кейсах WHATWG і contract-тестах LaunchDarkly. Транспорт — `ResponseType.stream` на Dio користувача, перепідключення з `Last-Event-ID` і `retry` вимикається. Для Flutter Web документувати вимогу `ConversionLayerAdapter(FetchClient)`, бо `dio_web_adapter` на XHR не стрімить.
9. **Ліцензії.** Код openapi_flutter_gen (AGPL або комерційна) і генератора dynamite (AGPL) не копіювати. degenerate (MIT), Kiota (MIT), sse_parser (MIT) і LaunchDarkly SSE (Apache-2.0) можна брати як еталон з атрибуцією.

---

## 7. Джерела

**Генератори**
- degenerate: https://pub.dev/packages/degenerate · https://github.com/blopker/degenerate · https://github.com/blopker/degenerate/blob/main/TODO.md · https://github.com/blopker/degenerate/blob/main/packages/degenerate_dio/lib/src/dio_api_client.dart · https://github.com/blopker/degenerate/blob/main/packages/degenerate_runtime/lib/src/sse.dart · https://github.com/blopker/degenerate/issues/15 · https://github.com/blopker/degenerate/issues/18 · https://github.com/blopker/degenerate/blob/main/Makefile
- Kiota: https://github.com/microsoft/kiota · https://github.com/microsoft/kiota-dart · https://pub.dev/packages/microsoft_kiota_abstractions · https://learn.microsoft.com/en-us/openapi/kiota/using · https://learn.microsoft.com/en-us/openapi/kiota/errors · https://learn.microsoft.com/en-us/openapi/kiota/quickstarts/dart · https://github.com/microsoft/kiota/issues/7807 · https://github.com/microsoft/kiota/issues/7997 · https://pub.dev/packages/stripe_api_client
- dynamite: https://pub.dev/packages/dynamite · https://github.com/provokateurin/dynamite · https://github.com/nextcloud/neon/pull/3205
- openapi_spec: https://pub.dev/packages/openapi_spec · https://github.com/tazatechnology/openapi_spec · https://github.com/tazatechnology/openapi_spec/issues/84 · https://github.com/tazatechnology/openapi_spec/issues/85 · https://github.com/tazatechnology/openapi_spec/issues/74 · https://github.com/davidmigloz/openapi_spec
- hpoul: https://pub.dev/packages/openapi_code_builder · https://pub.dev/packages/openapi_base · https://github.com/hpoul/openapi_dart
- florval: https://pub.dev/packages/florval · https://github.com/encer-jp/florval · https://github.com/encer-jp/florval/blob/main/lib/src/generator/client_generator.dart
- dart_openapi_generator: https://pub.dev/packages/dart_openapi_generator · https://github.com/AngeloAvv/dart_openapi_generator · https://github.com/AngeloAvv/dart_openapi_generator/blob/main/lib/src/parser/source_map.dart
- openapi_flutter_gen: https://pub.dev/packages/openapi_flutter_gen · https://github.com/PurpleSoftSrl/openapi_flutter_gen
- flap: https://pub.dev/packages/flap · https://github.com/miracle101000/flap-dart
- koi_swagger_parser: https://pub.dev/packages/koi_swagger_parser · https://github.com/mrkoi-is/koi_swagger_parser
- openapi_retrofit_generator / openapi_sdk_gen: https://pub.dev/packages/openapi_retrofit_generator · https://github.com/westito/openapi_retrofit_generator · https://pub.dev/packages/openapi_sdk_gen · https://github.com/fluxerapp/openapi_sdk_gen_dart
- open_api_client_generator: https://pub.dev/packages/open_api_client_generator · https://github.com/BreX900/mek-packages
- openapi_freezed_dio_builder: https://pub.dev/packages/openapi_freezed_dio_builder
- openapi_to_retrofit: https://pub.dev/packages/openapi_to_retrofit
- openapi_dart_common / dart-openapi-maven: https://pub.dev/packages/openapi_dart_common · https://github.com/dart-ogurets/dart-openapi-maven
- openapi_enum_patch: https://pub.dev/packages/openapi_enum_patch
- famedly: https://github.com/famedly/dart_openapi_codegen · https://github.com/famedly/dart_openapi_codegen/blob/main/rules/matrix.yaml
- @sdk-it/dart: https://www.npmjs.com/package/@sdk-it/dart · https://github.com/JanuaryLabs/sdk-it

**Великі SDK**
- https://github.com/davidmigloz/ai_clients_dart · https://github.com/davidmigloz/ai_clients_dart/blob/main/docs/spec-core.md · https://github.com/davidmigloz/ai_clients_dart/blob/main/docs/new_dart_api_client.md · https://github.com/davidmigloz/ai_clients_dart/blob/main/.agents/shared/api-toolkit/README.md · https://github.com/davidmigloz/ai_clients_dart/blob/main/packages/openai_dart/MIGRATION.md · https://github.com/davidmigloz/ai_clients_dart/blob/main/packages/openai_dart/CHANGELOG.md · https://github.com/davidmigloz/langchain_dart/tree/main/packages/openai_dart · https://github.com/davidmigloz/langchain_dart/blob/main/pubspec.yaml · https://pub.dev/packages/openai_dart/versions · https://pub.dev/packages/anthropic_sdk_dart · https://pub.dev/packages/googleai_dart
- https://github.com/google/googleapis.dart · https://github.com/agilord/aws_client · https://github.com/appwrite/sdk-generator · https://github.com/supabase/supabase-flutter · https://github.com/supabase/supabase-flutter/tree/main/packages/supabase_typegen · https://github.com/abraham/mastodon_dart/tree/main/packages/mastodon_generator · https://github.com/celest-dev/dart-api-clients/tree/main/clients/stripe · https://pub.dev/packages/pinecone
- Вендори: https://buildwithfern.com/learn/sdks/introduction/overview · https://www.stainless.com/docs/ · https://www.speakeasy.com/docs/sdks/create-client-sdks

**Будівельні блоки**
- https://pub.dev/packages/yaml · https://pub.dev/packages/source_span · https://pub.dev/packages/yaml_edit · https://pub.dev/packages/checked_yaml · https://pub.dev/packages/json_schema · https://github.com/workiva/json_schema · https://pub.dev/packages/json_schema_builder · https://pub.dev/packages/rfc_6901 · https://pub.dev/packages/json_pointer · https://pub.dev/packages/rfc_6902 · https://pub.dev/packages/json_patch · https://pub.dev/packages/json_path · https://github.com/f3ath/jessie · https://pub.dev/packages/code_builder · https://pub.dev/packages/dart_style
- https://pub.dev/packages/openapi_spec_plus · https://pub.dev/packages/conduit_open_api · https://pub.dev/packages/open_api_forked · https://pub.dev/packages/open_api_specification · https://pub.dev/packages/openapi_dart · https://pub.dev/packages/tonik_parse · https://pub.dev/packages/tonik_core
- OpenAPI Overlay 1.0.0: https://spec.openapis.org/overlay/v1.0.0.html (локальна копія `scratchpad/specs/overlay-1.0.0.md`)

**SSE**
- WHATWG: https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation
- https://pub.dev/packages/sse_parser · https://github.com/guillaumegay13/sse_parser
- https://pub.dev/packages/launchdarkly_event_source_client · https://github.com/launchdarkly/flutter-client-sdk/tree/main/packages/event_source_client
- https://pub.dev/packages/simple_sse · https://pub.dev/packages/simple_sse_dio · https://github.com/andyhorn/sse_client
- https://pub.dev/packages/eventflux · https://github.com/Imgkl/EventFlux
- https://pub.dev/packages/flutter_client_sse · https://github.com/pratikbaid3/flutter_client_sse
- https://pub.dev/packages/sse_channel · https://pub.dev/packages/sse · https://pub.dev/packages/eventsource
- https://github.com/davidmigloz/ai_clients_dart/blob/main/packages/openai_dart/lib/src/utils/streaming_parser.dart
- Dio web: https://github.com/cfug/dio/issues/2268 · https://github.com/cfug/dio/issues/1795 · https://github.com/cfug/dio/issues/1859 · https://github.com/cfug/dio/issues/1740 · https://github.com/cfug/dio/pull/2376 · https://github.com/cfug/dio/blob/main/plugins/web_adapter/lib/src/adapter_impl.dart · https://pub.dev/packages/dio_compatibility_layer · https://pub.dev/packages/fetch_client

**Власні експерименти** (повторювані): `scratchpad/longtail-exp/bin/exp.dart` (yaml на JSON, спани, дублікати), `yaml_gotchas.dart` (коерції), `defects.dart` (типізовані моделі на дефектах), `sse_conf.dart` (17 кейсів WHATWG). Dart 3.13.1; версії пакетів зафіксовано в `scratchpad/longtail-exp/pubspec.lock`.
