# 02. swagger_parser і swagger_dart_code_generator: prior art для нового генератора

> Дата дослідження: **2026-10-11**. Джерела первинні: код репозиторіїв (shallow clone), README/CHANGELOG, GitHub issues/PR (через `gh`), pub.dev API.
> Знімки коду:
> * **swagger_parser (SP)**: `Carapacik/swagger_parser@be6df7c` (main, 2026-10-01), пакет `swagger_parser 1.45.0`.
> * **swagger_dart_code_generator (SDCG)**: `epam-cross-platform-lab/swagger-dart-code-generator@753bdeb` (master, 2025-12-11), пакет `4.1.1`.
>
> Позначки впевненості: **(код)** = перевірено читанням коду (не запускалось), **(issue)** = зі слів репортера/мейнтейнера в issue, **(неперевірено)** = висновок без прямого доказу.
> Шляхи у форматі `SP:lib/...:L10-20` відносно `swagger_parser/` у репо SP; `SDCG:lib/...` відносно кореня репо SDCG. Повні базові URL у розділі «Джерела».

## TL;DR

1. **Твердження автора R8.1 підтверджене (код).** SP генерує `$unknown(null)` як окрему константу Dart `enum`; `fromJson` повертає `$unknown`, сире значення відкидається. Те саме в SDCG (`swaggerGeneratedUnknown(null)`). Нова знахідка: обидва порушують і **R8.2**. У SP невідоме значення можна надіслати назад: json_serializable закодує його як рядок `"$unknown"`, з `enums_to_json: true` воно кидає `StateError`, у dart_mappable стає рядком `"unknown"`. У SDCG невідоме значення в nullable-полі стає `null` при декодуванні, тож його не відрізнити від відсутнього.
2. Обидва інструменти **розбирають специфікацію як `Map<String, dynamic>` з кастами** і не мають моделі з JSON-pointer. Звідси падіння на «брудних» специфікаціях і відсутність діагностики. Приклад: у SP досі падає `paths./x.parameters` на рівні path-item, бо каст `requestPath as Map` стоїть **до** перевірки ключа (SP:open_api_parser.dart:L634 проти L641; [#374](https://github.com/Carapacik/swagger_parser/issues/374)). `$ref` в обох розв'язується як «останній сегмент шляху» (`p.basename` / `split('/').last`). Зовнішніх файлів і детекції циклів немає.
3. **Матриця required×nullable** в обох схлопнута до правила «optional ⇒ nullable». Ні tri-state для PATCH, ні розділення request/response немає. У SP це найбільший кластер багів (#303, #358, #460, #443, #440, #307). #460 б'є саме по NestJS-специфікаціях.
4. **Поліморфізм:** SP має sealed-класи для `oneOf`/`anyOf` з discriminator і `fallback_union` із сирим JSON (крім freezed). Без discriminator SP перебирає варіанти через послідовні try/catch, тобто мовчки вгадує. SDCG discriminator не підтримує зовсім ([#563](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/563), відкрите з 2023 року), а `oneOf`/`anyOf` перетворює на `dynamic`.
5. **Типізованих помилок, кількох 2xx, SSE-протоколу, cookie-параметрів, `style/explode/deepObject` немає в жодного.** Cookie-параметри обидва мовчки викидають (код).
6. **Активність:** SP живий, мейнтейнить в основному одна людина, релізи приблизно щомісяця (1.42→1.45 за 2026 рік). SDCG фактично стоїть: останній коміт 2025-12-11, 13 відкритих PR, [#796 «Future of this project»](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/796) без відповіді. Найпопулярніші його issues стосуються конфліктів залежностей build_runner.
7. **Що варто взяти:** з SP — `schemes:` з успадкуванням, `replacement_rules`, фільтри тегів і glob-шляхів із tree-shaking, `fallback_union` із сирим JSON, `add_openapi_metadata`, doc-коментар «Original name: …» при перейменуванні, e2e golden-тести. З SDCG — типізований `SwaggerMetaData` у кожному запиті (operationId/security/tags), `scalars` (format→тип+функції), `overriden_models`, `response_override_value_map`, `Wrapped<T>` для copyWith, `_dateToJson` для `format: date`, форматування через `dart_style` з `page_width`.

---

# 1. swagger_parser

## 1.1 Огляд

| Параметр | Значення | Джерело |
|---|---|---|
| Остання версія | **1.45.0**, опублікована 2026-09-25 | pub.dev API `/api/packages/swagger_parser` |
| Попередні релізи 2026 | 1.42.0 (02-02), 1.43.0 (03-03), 1.43.1 (04-21), 1.44.0 (06-22), 1.44.1 (08-02), 1.44.2 (09-01), 1.44.3 (09-05) | pub.dev API |
| Pub points / likes / завантаження за 30 днів | 160/160 · 124 likes · 65 650 | pub.dev `/score` |
| GitHub | 148★, 106 forks, ліцензія MIT, створений 2022-10-02 | `gh repo view` |
| Issues | 71 відкрите з 218 (PR відкритих: 0) | `gh issue list` |
| Хто мейнтейнить | Carapacik (198 комітів) плюс контриб'ютори (StarProxima, vasilich6107, peter-trost, Sadhorsephile…). У 2026 році десятки злитих PR від спільноти | `gh api …/commits`, `/contributors` |
| Мови виходу | Dart (retrofit + json_serializable / freezed / dart_mappable) і Kotlin (retrofit + moshi) | README |
| Розмір коду | ≈9.6 тис. рядків; ядро парсера `open_api_parser.dart` має 2299 рядків | `wc -l` |

Висновок щодо підтримки: проєкт активний. Більшість фіч і фіксів 2026 року прийшли PR-ами від спільноти. Bus factor близький до 1, бо релізить лише власник.

## 1.2 Архітектура

* **Запуск.** CLI `dart run swagger_parser` (SP:bin/swagger_parser.dart). Конфіг шукається в `swagger_parser.yaml` або в секції `swagger_parser:` у `pubspec.yaml`; аргумент `-f` вказує інший файл (SP:lib/src/utils/file/io_file.dart:L11-25). Є й програмний API: `GenProcessor`, `SWPConfig` експортуються з `lib/swagger_parser.dart`. Поверх нього зроблено веб-інтерфейс `swagger_parser_pages` (Flutter Web, <https://carapacik.github.io/swagger_parser>).
* **Конвеєр.** `OpenApiCorrector.correct()` (перейменування схем текстовими regex-заміщеннями в сирому JSON/YAML) → `OpenApiParser` (обхід `Map<String,dynamic>`) → «універсальна» модель (`UniversalDataClass`, `UniversalRestClient`, `UniversalType`) → рядкові шаблони (`lib/src/generator/templates/*.dart`) → запис файлів.
* **Вихід — анотований код, який потребує `build_runner`.** Клієнт генерується як `@RestApi() abstract class XClient { factory XClient(Dio dio, {String? baseUrl}) = _XClient; ... }` (SP:dart_retrofit_client_template.dart:L52-62). Моделі анотуються `@JsonSerializable` / `@Freezed` / `@MappableClass`. Потім користувач запускає `dart run build_runner build`, і `retrofit_generator` з `json_serializable` / `freezed` / `dart_mappable_builder` генерують `.g.dart`, `.freezed.dart`, `.mapper.dart`. Для freezed+retrofit README вимагає задати порядок builder-ів у `build.yaml`.
* **Розкладка файлів.** `<output>/clients/*_client.dart`, `<output>/models/*.dart` (одна модель на файл), опційний root client `rest_client.dart` (конкретний клас із lazy-геттерами клієнтів за тегами) і `export.dart`. `merge_outputs: true` зливає все в один файл. `put_clients_in_folder` кладе клієнти в окрему теку.
* **Заголовок файлів:** `// coverage:ignore-file`, `// GENERATED CODE - DO NOT MODIFY BY HAND`, `// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import` (SP:lib/src/utils/base_utils.dart:L79-84). Лінти **приглушуються**, а не задовольняються.
* **Форматування.** Генератор `dart format` не запускає, бо залежності від `dart_style` немає. Golden-тести форматують вивід уже після генерації (SP:test/e2e/e2e_util.dart) (код).
* **Завантаження за URL:** `schemaFromUrl` (SP:io_file.dart:L33-40). Це `HttpClient.getUrl` без заголовків авторизації і без перевірки статусу. Копія пишеться в корінь проєкту під basename URL (`writeSchemaToFile`, L43-45, config_processor.dart:L118-142), а генерація йде зі щойно завантаженого вмісту, а не з локального знімка (код).
* **Особливість YAML-входу (код).** `YamlMapX.toMap()` перетворює **всі скаляри на рядки** (`entry.value.toString()`, SP:open_api_corrector.dart:L309). Для YAML-специфікацій `true`, `1` і `null` стають `"true"`, `"1"`, `"null"`, а для JSON типи зберігаються. Через це в парсері всюди написано `x.toString().toBool()`, і поведінка JSON та YAML може розходитись.

## 1.3 Конфіг як prior art

Повний список ключів узято з `SP:lib/src/config/swp_config.dart` (`yamlMap['…']`). README розходиться з кодом: у ньому досі описано `put_in_folder`, хоча в 1.18.0 цю опцію прибрали (CHANGELOG:L469). `generate_validator` є в коді, але в README не задокументований.

| Опція (дефолт) | Що робить | Prior art для | Оцінка |
|---|---|---|---|
| `schema_path` / `schema_url` | локальний файл або завантаження за URL | R1.1 | URL без авторизації; знімок не використовується для генерації |
| `schemes: [...]` | кілька специфікацій; кожна успадковує кореневі параметри й може їх перевизначити (config_processor.dart:L44-87) | **R1.3** | добрий патерн; баг: `export.dart` перезаписується, якщо каталог спільний ([#405](https://github.com/Carapacik/swagger_parser/issues/405)) |
| `output_directory`, `name`, `put_clients_in_folder`, `merge_outputs`, `export_file`, `root_client`, `root_client_name`, `client_postfix` (`Client`) | розкладка вихідних файлів | R4.3 | `merge_outputs` придумано для сумісності з build_runner (один вхід → один вихід) |
| `language` (`dart`), `json_serializer` (`json_serializable` / `freezed` / `dart_mappable`) | вибір серіалізатора | відкрите рішення 2 | три гілки шаблонів означають потрійну поверхню багів (див. 1.6) |
| `replacement_rules: [{pattern, replacement}]` | regex-перейменування класів і enum, правила застосовуються по черзі | **R5.1** (regex-префікс) | застосовується через текстову заміну в сирій специфікації (corrector) — крихко |
| `replacement_rules_for_raw_schema` (1.38.0) | regex над **сирими** іменами до перетворення на ідентифікатор (`filters[name]` → `filters_name_`) | R2.1 (нормалізація), R5.2 | корисна ідея «pre-normalization» |
| `preserve_schema_casing` (`false`) | не перетворювати імена схем у PascalCase | R5.1 | — |
| `path_method_name` (`false`) | ім'я методу з path+method замість `operationId` | R5.1 | — |
| `include_tags` / `exclude_tags` | фільтр за тегом без урахування регістру; `include` має пріоритет над `exclude` (open_api_parser.dart:L2129-2152) | **R4.1** | немає фільтра за `operationId` і немає `exclude_paths` |
| `include_paths` (1.40.0) | glob `*` / `**` (lib/src/parser/utils/path_match.dart) | **R4.1** | лише include |
| (неявно) фільтр невикористаних схем (1.29.0, 1.44.2) | tree-shaking схем при фільтрі за тегами | **R4.2** | працює для tag-фільтрів; для `include_paths` не перевірено |
| `fallback_client` (`fallback`), `merge_clients` (`false`) | клієнт для операцій без тегів; один клієнт на всю специфікацію | **R5.3** | — |
| `skipped_parameters: [names]` | прибрати параметри за іменем (наприклад, `X-Some-Token`, який додає interceptor) | R3.1 (виключення), R10.1 | груба адресація: за іменем, глобально |
| `default_content_type` (`application/json`) | контент-тип за замовчуванням | R10.4 | — |
| `extras_parameter_by_default`, `dio_options_parameter_by_default` (`false`) | додати `@Extras() Map extras` і `@DioOptions() RequestOptions options` до **всіх** методів | **R10.5** | глобальний перемикач |
| `add_openapi_metadata` (1.36.0, `false`) | статичні константи `{tags, operationId, externalDocsUrl}` для кожного методу; якщо extras увімкнені, вони стають дефолтним `extras` | **R10.5, R10.8** | якщо користувач передасть свої `extras`, дефолт **замінюється**, а не зливається |
| `original_http_response` (`false`) | повертати `HttpResponse<T>` (тіло, статус, заголовки) | R10.6 | глобально |
| `generate_urls_constants` (1.40.0) | клас `XClientUrls` зі `static const` шляхами | (ергономіка) | — |
| `unknown_enum_value` (`true`) | додає `$unknown` / `unknown` в enum | **R8.1** | сире значення губиться (див. 1.5) |
| `enums_to_json` (`false`) | генерує `toJson()` в enum | R8 | `toJson()` на `$unknown` кидає `StateError` |
| `enums_parent_prefix` (`true`) | префікс імені inline-enum з батьківської схеми | **R5.4** | — |
| `use_x_nullable` (`false`) | враховувати `x-nullable` (Swagger 2) | R6.1 | — |
| `infer_required_from_nullable` (1.35.0, `false`) | якщо в схемі немає масиву `required`, все не-nullable вважається required | **R2.1** (евристика для ASP.NET) | ідея добра, але це прихований глобальний режим без звіту |
| `include_if_null` (`false`) | `@JsonKey(includeIfNull: …)` для nullable-полів | R7.3 | глобальний; tri-state не вирішує |
| `required_by_default` | **видалено** в 1.18.0 | R6.1 | — |
| `field_parsers: [{apply_to_type, parser_name, parser_absolute_path}]` (1.41.0) | підставити `JsonConverter` для конкретного **Dart-типу** (лише json_serializable) | **R6.2** (налаштовуваний мапінг) | адресація за Dart-типом, а не за `format`/місцем у спеці |
| `use_multipart_file` (`false`) | `MultipartFile` замість `dart:io File` (для web) | R10.4, R0.1 | — |
| `use_freezed3`, `freezed_json_serialization` (1.45.0), `fallback_union` (`""`), `dart_mappable_convenient_when`, `use_dart_mappable_naming` | тонкі налаштування серіалізаторів і union | R9.1 | `fallback_union` див. 1.5 |
| `use_flutter_compute` (1.37.0) | `@RestApi(parser: Parser.FlutterCompute)` і top-level (де)серіалізатори для isolate | (продуктивність) | генерований код залежить від Flutter, а не від чистого Dart (суперечить R0.1) |
| `generate_validator` (`false`, не в README) | для freezed: статичні `…Min/Max/…` і `bool validate()` | **R6.7** | лише freezed |
| `mark_files_as_generated` (`true`) | заголовок «GENERATED CODE» | R13 | — |

## 1.4 Таблиця покриття вимог

✅ є, ⚠️ частково або з дефектами, ❌ немає.

| Вимога | Статус | Доказ / коментар |
|---|---|---|
| R0.1 OAS 3.0 і 3.1, чистий Dart | ⚠️ | README заявляє v2/3.0/3.1. Масиви типів 3.1 обробляються лише у формі `[T, "null"]`, інакше стає `dynamic` (SP:parser/utils/type_utils.dart:L30-38). `const`-enum не підтримується ([#121](https://github.com/Carapacik/swagger_parser/issues/121), [#342](https://github.com/Carapacik/swagger_parser/issues/342) відкриті). `use_flutter_compute` додає залежність від Flutter (код) |
| R1.1 локальний файл / URL | ⚠️ | Локальний JSON/YAML працює. URL завантажується щоразу, без авторизації, генерація йде не зі знімка (io_file.dart:L33-45) (код) |
| R1.2 `$ref` усередині й між файлами, цикли | ❌ | `_formatRef` повертає `p.basename(ref)` (open_api_parser.dart:L1170-1176): JSON-pointer не розбирається, зовнішні файли не завантажуються ([#120](https://github.com/Carapacik/swagger_parser/issues/120), [#366](https://github.com/Carapacik/swagger_parser/issues/366)). Циклічні схеми дають StackOverflow ([#423](https://github.com/Carapacik/swagger_parser/issues/423)) (код+issue) |
| R1.3 кілька специфікацій | ✅/⚠️ | `schemes:` з успадкуванням працює; конфлікт `export.dart` ([#405](https://github.com/Carapacik/swagger_parser/issues/405)) |
| R1.4 OAS 3.2 `itemSchema` | ❌ | — |
| R2.1 нормалізатор з іменованими правилами | ❌/⚠️ | Є лише «corrector» для перейменування й кілька глобальних евристик (`infer_required_from_nullable`). Звіту немає |
| R2.2 діагностика з кодами й pointer-ами | ❌ | `print('Warning:…')` (L292-295), `stdout.writeln('Found duplicate object name')` (L1567). Будь-який виняток зриває генерацію всієї схеми (bin/swagger_parser.dart:L25-41) |
| R2.3 / R2.4 baseline, `check` | ❌ | — |
| R2.5 нічого не вгадувати мовчки | ❌ | Cookie-параметри відкидаються з `print` (L288-295). Береться перший 2xx (http_utils.dart:L2-20) і перший content-type. Union без discriminator розбирається через try/catch. Імена `Object0` / `Enum0` (type_utils.dart:L65-87) (код) |
| R3.1–R3.3 файл override-ів, overlay | ❌ | Є лише глобальні regex-правила і `skipped_parameters`; адресних override-ів немає |
| R4.1 фільтри tag / operationId / path | ⚠️ | tag include/exclude і path include (glob). Немає `operationId` і `exclude_paths` |
| R4.2 tree-shaking | ⚠️ | Для tag-фільтрів є з 1.29.0 (CHANGELOG), з фіксами [#369](https://github.com/Carapacik/swagger_parser/issues/369) і 1.44.2. Для `include_paths` не перевірено |
| R4.3 безпечне співіснування з кодом користувача | ⚠️ | Окремий каталог, глобальних побічних ефектів немає. Префікса для моделей немає: колізія з `Options` з dio ([#194](https://github.com/Carapacik/swagger_parser/issues/194), відкрите) |
| R5.1 імена операцій | ⚠️ | `operationId.toCamel` або path+method. Regex-правила стосуються лише класів |
| R5.2 детерміновані колізії | ⚠️ | Список keywords разом з типами `dart:core` (parser/utils/dart_keywords.dart) дає суфікс `value`/`enum` і doc-коментар з оригінальним іменем (type_utils.dart:L191-240). Дублікати отримують числовий суфікс за порядком обходу (L1563-1569) |
| R5.3 групування за тегом | ✅ | Перший тег визначає клієнт; є `fallback_client` і `merge_clients`; брудні теги проходять через `toPascal`/`toSnake`. Порожні теги ламаються ([#306](https://github.com/Carapacik/swagger_parser/issues/306), [#271](https://github.com/Carapacik/swagger_parser/issues/271)) |
| R5.4 inline-схеми та inline-enum | ⚠️ | `${Path}RequestBody`, `${Method}${Path}Response` (L649, L453), enum отримують ім'я `Parent+Prop`. Дедуплікація enum за іменем+значеннями є, об'єктів немає ([#448](https://github.com/Carapacik/swagger_parser/issues/448)). Override немає ([#379](https://github.com/Carapacik/swagger_parser/issues/379), [#389](https://github.com/Carapacik/swagger_parser/issues/389)) |
| R6.1 матриця required × nullable | ❌ | `nullable: false => !isRequired` (L1606-1610): optional завжди nullable. Request і response не розділені. Якщо в об'єкті без `required` хоч одна властивість має `allOf`, required стають **усі** (L775-777, L821-823; [#460](https://github.com/Carapacik/swagger_parser/issues/460)) (код) |
| R6.2 мапінг типів | ⚠️ | `date` і `date-time` → `DateTime` (date серіалізується як дата-час, [#463](https://github.com/Carapacik/swagger_parser/issues/463)); `int64` → `int`; `number` → `num`; `uuid` → `String`; `object` → `dynamic`; `additionalProperties` → `Map<String,T>` ✅. Кастомізація — лише `field_parsers` |
| R6.3 `allOf` | ⚠️ | Злиття є (1.23.0, 1.33.0), nullable з одним `$ref` полагоджено в 1.44.0. Відкриті [#239](https://github.com/Carapacik/swagger_parser/issues/239), [#358](https://github.com/Carapacik/swagger_parser/issues/358), [#204](https://github.com/Carapacik/swagger_parser/issues/204), [#381](https://github.com/Carapacik/swagger_parser/issues/381) |
| R6.4 дженерики-конверти | ❌ | [#218](https://github.com/Carapacik/swagger_parser/issues/218) |
| R6.5 зайві поля / помилка відсутнього поля | ⚠️ | Зайві поля ігноруються (дефолт json_serializable). `@JsonSerializable()` генерується без `checked: true`, тому відсутнє поле дає голий `TypeError` без шляху (неперевірено в рантаймі) |
| R6.6 `==`, `copyWith`, `toString` | ⚠️ | Є через freezed і dart_mappable; у json_serializable немає |
| R6.7 обмеження | ⚠️ | `generate_validator`, лише для freezed |
| R7.1–R7.3 tri-state PATCH | ❌ | Лише глобальний `include_if_null`; [#307](https://github.com/Carapacik/swagger_parser/issues/307) |
| **R8.1** сире значення enum | ❌ | **Губиться** (код, див. 1.5) |
| **R8.2** невідоме не можна надіслати | ❌ | Надсилається `"$unknown"` / `"unknown"` або кидається `StateError` (код, див. 1.5) |
| R8.3 рядкові, числові, булеві enum | ⚠️ | string, int і num є; bool-enum ламається ([#342](https://github.com/Carapacik/swagger_parser/issues/342)); невалідні імена замінюються на `value0`, `valueNull` |
| R8.4 `x-enum-varnames` / `x-enum-descriptions` | ⚠️ | Лише `x-enumNames` (L71, L918). `x-enum-varnames` немає ([#285](https://github.com/Carapacik/swagger_parser/issues/285)) |
| R9.1 discriminator → закрита ієрархія + unknown | ⚠️ | `sealed class` + `tryDeserialize` за значенням discriminator. Без `fallback_union` невідоме значення дає `FormatException` (json_serializable_dto_template.dart:L204-251). З `fallback_union` сирий JSON зберігається в json_serializable і dart_mappable (L385-407), а у freezed fallback порожній: `const factory X.unknown()` (freezed_dto_template.dart:L220-227) (код) |
| R9.2 `oneOf` без discriminator | ⚠️ | Послідовні `try { return V.fromJson(json); } catch (_) {}` (L254-290): мовчки вгадує першого, хто розпарсився. Режимів error / raw немає |
| R9.3 змішані примітиви | ❌ | `tryDeserialize(Map<String, dynamic>)` приймає лише об'єкти (L145, L280) (код) |
| R10.1 свій клієнт, `baseUrl` не перезаписується | ✅ | `factory X(Dio dio, {String? baseUrl})`, `@RestApi()` без baseUrl, `servers` ігнорується |
| R10.2 HTTP-помилки йдуть через `onError` | ✅ | Стандартна поведінка retrofit/Dio (DioException) |
| R10.3 path / query / header / cookie, стилі | ⚠️ | Cookie мовчки зникає (L288-295). `style`, `explode`, `deepObject` не читаються взагалі (grep порожній), тож працює дефолт Dio `ListFormat` (код) |
| R10.4 тіла | ⚠️ | JSON ✅, multipart ✅ (`@MultiPart`, `@Part`, File/MultipartFile), urlencoded ✅. Для OAS3 тіл, крім multipart/urlencoded, **обраний content-type не передається**: `resultContentType` лишається дефолтним (L346-362, L727), тож `application/octet-stream` чи `merge-patch+json` підуть із заголовком `application/json` (код). Вкладений об'єкт у multipart: [#444](https://github.com/Carapacik/swagger_parser/issues/444) |
| R10.5 скасування / прогрес / заголовки / метадані / operationId | ⚠️ | `@Extras` і `@DioOptions` вмикаються глобально; `add_openapi_metadata` кладе operationId в extras лише як дефолтне значення параметра (dart_retrofit_client_template.dart:L225-256) |
| R10.6 кілька 2xx, 204, статус і заголовки, не-JSON | ⚠️ | Лише перший 2xx ([#385](https://github.com/Carapacik/swagger_parser/issues/385)); `original_http_response` дає `HttpResponse<T>`; будь-який `format: binary` перетворюється на `Stream<Uint8List|String>` (L136-152) |
| R10.7 абстрактний API | ✅ | Абстрактний клас retrofit на кожен тег; мокається через `implements`. Root client конкретний |
| R10.8 security як метадані | ❌ | `securitySchemes` не читаються ([#388](https://github.com/Carapacik/swagger_parser/issues/388)) |
| R10.9 servers | ❌ | Ігноруються (L641) |
| R11.1–R11.7 типізовані помилки | ❌ | Схеми 4xx/5xx/default ігноруються ([#367](https://github.com/Carapacik/swagger_parser/issues/367)) |
| R12.x SSE | ⚠️/❌ | «SSE» тут означає `@DioResponseType(ResponseType.stream)` → `Stream<String>` або `Stream<Uint8List>`. Розбору WHATWG-протоколу і типізованих подій немає. Тригер — `format: binary`, а не `text/event-stream` (README; [#432](https://github.com/Carapacik/swagger_parser/issues/432)) |
| R13.1 детермінізм | ⚠️ | Таймстемпів немає, імпорти через `SplayTreeSet`. Суфікси `Name2` і `Object0` залежать від порядку обходу; вихід не форматується |
| R13.2 чистота під лінти | ❌ | `ignore_for_file: type=lint …` (base_utils.dart:L84) |
| R13.3 мінімальний runtime | ⚠️ | runtime: dio + retrofit + json_annotation (+ freezed_annotation або dart_mappable); dev: build_runner, retrofit_generator, json_serializable (+ freezed). Власного runtime-пакета немає |
| R13.4 doc-коментарі, `@Deprecated` | ✅/⚠️ | Описи й `@Deprecated` на методах і параметрах є; для полів — лише у freezed і dart_mappable |
| R13.5 розмір виходу | ✅ | Заглушок тестів і доків немає |
| R14.1 / R14.2 еволюція | ❌/⚠️ | Звіту про зміни немає. `$unknown` і fallback допомагають з R14.2 |
| R15.1 CLI і API | ✅ | CLI, Dart API, Web UI. Вихід потім іде через build_runner |
| R15.2 конфіг із JSON Schema | ❌ | YAML з ручними кастами й `ConfigException`; README відстає від коду |
| R15.3 тести | ⚠️ | e2e golden-тести (`test/e2e/tests/*/expected_files`, 27 кейсів). CI **не компілює і не аналізує** згенерований код (.github/workflows/tests.yml): `dart analyze` проганяється лише над `lib/` самого пакета |
| R15.4 semver | ⚠️ | Поведінка змінюється в minor-версіях: streaming у 1.42.0 ([#432](https://github.com/Carapacik/swagger_parser/issues/432)), регресія enum у 1.43.0 ([#446](https://github.com/Carapacik/swagger_parser/issues/446)) |

## 1.5 Перевірка тверджень автора

### «swagger_parser втрачає сире значення невідомого enum» (R8.1) — **ПІДТВЕРДЖЕНО (код)**

**Шлях генерації** (`unknown_enum_value: true` за замовчуванням, SP:swp_config.dart:L28):

1. json_serializable і freezed використовують спільний шаблон enum. [SP:lib/src/generator/templates/dart_enum_dto_template.dart](https://github.com/Carapacik/swagger_parser/blob/be6df7c11205d5e7dacf8cace6b07c7c5885c3fc/swagger_parser/lib/src/generator/templates/dart_enum_dto_template.dart):
   * L131-134 додає константу `$unknown(null);`. Значення `json` у неї `null`, тобто місця для сирого рядка немає.
   * L136-142: `factory X.fromJson(T json) => values.firstWhere((e) => e.json == json, orElse: () => $unknown);`. Вхідне `json` після цього відкидається.
   * L194-206 (`enums_to_json: true`): `toJson()` на `$unknown` кидає `StateError(...)`.
   * L208-209: `toString()` для `$unknown` повертає `super.toString()`, тобто `"X.$unknown"`. Сирого значення немає навіть у логах.
2. Анотація полів моделей (SP:dart_json_serializable_dto_template.dart:L438-461 `_jsonKey`) **не** генерує `@JsonKey(unknownEnumValue: …)`. Фолбек працює лише тому, що json_serializable 6.14.1 перевіряє `JsonHelper` (є конструктор `fromJson`) **раніше** за `EnumHelper` (`json_serializable/lib/src/settings.dart`: `_typeHelpers` перед `_coreHelpers`; `type_helpers/json_helper.dart` шукає `constructors.where((ce) => ce.name == 'fromJson')`). Тому декодування поля йде як `X.fromJson(json['f'] as String)`, і результат `$unknown` без сирого значення.
3. **Кодування (R8.2), код.** Коли `enums_to_json: false` (дефолт), `toJson` у enum немає, `JsonHelper` пропускає тип, і серіалізацію робить `EnumHelper` через `_$XEnumMap`. Для `$unknown`, у якого немає `@JsonValue`, json_serializable бере **ім'я поля** (`enum_utils.dart` `_generateEntry` → `encodedFieldName(fieldRename, field.name)`). Отже у мапі `X.$unknown: r'$unknown'`, і модель з невідомим значенням, відправлена назад на сервер, надішле рядок **`"$unknown"`**. З `enums_to_json: true` маємо `StateError`. Окремо виправлено [#454](https://github.com/Carapacik/swagger_parser/issues/454): такий `toJson()` не компілювався при `unknown_enum_value: false`.
4. **dart_mappable** (той самий файл, L60-113): додається значення `@MappableValue('unknown') unknown` і `@MappableEnum(defaultValue: X.unknown)`. Невідоме значення декодується в `unknown` без сирого рядка, а при кодуванні йде на сервер як `"unknown"`. Для integer-enum це взагалі рядковий літерал `'unknown'` (L151-163).
5. Як дійшли до такого дизайну: [#106](https://github.com/Carapacik/swagger_parser/issues/106). Колаборатор запропонував `@JsonValue(null) $unknown`, а `unknownEnumValue: null` у json_serializable тоді не працював.

**Наслідки для нового генератора.** У Dart-`enum` неможливо зберегти сире значення, бо константи статичні. Потрібен інший тип: sealed-клас або extension type з варіантом `Unknown(String raw)`, або клас-обгортка `{X? known; Object raw}` (відкрите рішення 7). R8.2 вимагає, щоб тип для запитів не мав варіанта unknown, або щоб серіалізація на ньому падала на етапі типів, а не в рантаймі.

### Додаткові твердження, перевірені принагідно

* «Union-fallback у SP зберігає сирий JSON» — **частково (код).** Так для json_serializable і dart_mappable (`json` getter, L385-407 і dart_mappable_dto_template.dart:L574, L788). Ні для freezed: порожній `const factory X.unknown()`.
* «SP повертає `ModelNameUnion` замість `…Sealed`» — виправлено в 1.39.1 ([#393](https://github.com/Carapacik/swagger_parser/issues/393)).

## 1.6 Відомі проблеми (issue tracker + код) і уроки

Найобговорюваніші (реакції ×2 + коментарі): #257, #5, #29, #25, #303, #225, #121, #251, #144, #340, #106, #78, #380, #279, #131, #444, #358. Нижче — згруповано за темами.

| # | Суть | Урок для нового інструмента |
|---|---|---|
| [#303](https://github.com/Carapacik/swagger_parser/issues/303) (8 реакцій, відкрите), [#251](https://github.com/Carapacik/swagger_parser/issues/251), [#358](https://github.com/Carapacik/swagger_parser/issues/358), [#460](https://github.com/Carapacik/swagger_parser/issues/460), [#443](https://github.com/Carapacik/swagger_parser/issues/443), [#440](https://github.com/Carapacik/swagger_parser/issues/440), [#363](https://github.com/Carapacik/swagger_parser/issues/363), [#307](https://github.com/Carapacik/swagger_parser/issues/307), [#257](https://github.com/Carapacik/swagger_parser/issues/257) (12 реакцій) | Nullable `$ref` поруч із `nullable: true`; `allOf:[$ref]+nullable` (патерн ASP.NET і NestJS); «один `allOf` робить усі поля required»; optional генерується як required або навпаки | Явна матриця R6.1 як окремий, протестований модуль. Нормалізатор (R2.1) з правилами `allof-single-ref-nullable` і `sibling-nullable-on-ref` зі звітом. Golden-тести на патерни NestJS, FastAPI, Swashbuckle і Microsoft.AspNetCore.OpenApi |
| [#374](https://github.com/Carapacik/swagger_parser/issues/374) (7 коментарів, на 1.42.0 досі є), [#442](https://github.com/Carapacik/swagger_parser/issues/442), [#375](https://github.com/Carapacik/swagger_parser/issues/375), [#321](https://github.com/Carapacik/swagger_parser/issues/321), [#296](https://github.com/Carapacik/swagger_parser/issues/296), [#110](https://github.com/Carapacik/swagger_parser/issues/110) | `type 'List<Object?>' is not a subtype of 'Map<String,dynamic>'` і подібні. **Підтверджено в коді**: path-level `parameters` (List), `summary` чи `description` (String) кастяться в `Map` раніше, ніж перевіряється ключ (open_api_parser.dart:L634 проти L641) | Типізована модель специфікації з tolerant-парсингом. Помилка в одній операції дає діагностику з JSON-pointer і пропуск операції, а не падіння всієї генерації (R2.2, R2.5) |
| [#120](https://github.com/Carapacik/swagger_parser/issues/120), [#366](https://github.com/Carapacik/swagger_parser/issues/366), [#423](https://github.com/Carapacik/swagger_parser/issues/423) | Немає зовнішніх `$ref`; цикли дають StackOverflow | Окремий resolver: URI + JSON Pointer (з `~0`/`~1`), кеш документів, детекція циклів, лінивий обхід (R1.2) |
| [#121](https://github.com/Carapacik/swagger_parser/issues/121) (5 реакцій), [#342](https://github.com/Carapacik/swagger_parser/issues/342) | Enum у стилі 3.1 (`oneOf` + `const` + `title`) і bool-`const` не підтримуються | У матрицю підтримки 3.1 (R15.5) включити `const`, масиви `type`, `oneOf[const]` як enum з іменами з `title` |
| Код + [#106](https://github.com/Carapacik/swagger_parser/issues/106), [#351](https://github.com/Carapacik/swagger_parser/issues/351), [#454](https://github.com/Carapacik/swagger_parser/issues/454), [#446](https://github.com/Carapacik/swagger_parser/issues/446), [#462](https://github.com/Carapacik/swagger_parser/issues/462), [#414](https://github.com/Carapacik/swagger_parser/issues/414), [#441](https://github.com/Carapacik/swagger_parser/issues/441) | Сире значення enum губиться; `$unknown` можна надіслати; regressions у `toString`/`toJson`/дефолтах query-параметрів | Окремий тип для невідомого з raw (R8.1). Тип запиту без unknown (R8.2). Одна реалізація enum замість трьох гілок серіалізаторів |
| [#385](https://github.com/Carapacik/swagger_parser/issues/385), [#367](https://github.com/Carapacik/swagger_parser/issues/367), [#273](https://github.com/Carapacik/swagger_parser/issues/273), [#312](https://github.com/Carapacik/swagger_parser/issues/312) | Немає кількох 2xx (на 204 падає `!`), схеми помилок ігноруються, тип не залежить від статусу | Повертати union відповідей (R10.6) і типізовані помилки (R11). Retrofit тут — архітектурна стеля: один тип на метод, CallAdapter лише як обхід |
| [#194](https://github.com/Carapacik/swagger_parser/issues/194), [#409](https://github.com/Carapacik/swagger_parser/issues/409), [#429](https://github.com/Carapacik/swagger_parser/issues/429), [#448](https://github.com/Carapacik/swagger_parser/issues/448), [#379](https://github.com/Carapacik/swagger_parser/issues/379), [#389](https://github.com/Carapacik/swagger_parser/issues/389), [#140](https://github.com/Carapacik/swagger_parser/issues/140), [#235](https://github.com/Carapacik/swagger_parser/issues/235) | Колізія з `Options` з dio; keyword-поля в sealed-класах втрачають `@JsonKey`; corrector перетворював **шляхи API** на PascalCase (текстова заміна); дублікати `AspectRatio2`; довгі імена без override | Перейменування на рівні таблиці символів, а не regex по тексту (SP:open_api_corrector.dart:L59-260). Зарезервовані імена мають включати символи runtime-імпортів, або використовувати `import … as`. Дедуплікація структурно однакових inline-схем. Override імені (R5.4) |
| [#380](https://github.com/Carapacik/swagger_parser/issues/380), [#411](https://github.com/Carapacik/swagger_parser/issues/411), [#462](https://github.com/Carapacik/swagger_parser/issues/462), [#454](https://github.com/Carapacik/swagger_parser/issues/454), [#408](https://github.com/Carapacik/swagger_parser/issues/408), [#326](https://github.com/Carapacik/swagger_parser/issues/326) | Згенерований код не компілюється, і це видно лише після `build_runner` | У CI компілювати й аналізувати golden-вихід плюс runtime-тести декодування (R15.3). Генерувати готовий код, щоб помилка ловилась одразу, а не на другій фазі |
| [#432](https://github.com/Carapacik/swagger_parser/issues/432) | У minor 1.42.0 binary-відповіді змінили тип на `Stream<String>`, і вимкнути це не можна | Зміна виходу — breaking change (R15.4); нові режими вводити опційно |
| [#340](https://github.com/Carapacik/swagger_parser/issues/340) (11 коментарів), [#444](https://github.com/Carapacik/swagger_parser/issues/444), [#249](https://github.com/Carapacik/swagger_parser/issues/249), [#272](https://github.com/Carapacik/swagger_parser/issues/272), [#154](https://github.com/Carapacik/swagger_parser/issues/154), [#144](https://github.com/Carapacik/swagger_parser/issues/144) | Multipart: `List<List<MultipartFile>>`, вкладені об'єкти, nullable-файли, `$ref` | Окрема модель multipart-частин з `encoding` (content-type частини), а об'єкти в частинах серіалізувати як JSON (R10.4) |
| Код (L346-362, L727) | Content-type OAS3-тіла, крім multipart і urlencoded, не потрапляє в запит | Тест на кожен media type з матриці R10.4 |
| Код (L288-295) | Cookie-параметри мовчки викидаються | R2.5: або підтримати, або error чи warning з кодом і override |
| [#213](https://github.com/Carapacik/swagger_parser/issues/213), [#463](https://github.com/Carapacik/swagger_parser/issues/463), [#16](https://github.com/Carapacik/swagger_parser/issues/16) | `date` серіалізується як дата-час; офсет часового поясу губиться; немає `x-dart-type` | Окремий тип `Date` для `format: date`, налаштовуваний мапінг `format`→тип (R6.2) і `x-dart-type` в реєстрі `x-` |
| [#218](https://github.com/Carapacik/swagger_parser/issues/218), [#415](https://github.com/Carapacik/swagger_parser/issues/415) | Немає дженериків і спільних інтерфейсів | R6.4 (конверти та пагінація) |
| [#405](https://github.com/Carapacik/swagger_parser/issues/405) | Кілька `schemes` перезаписують спільний `export.dart` | Перевіряти, що вихідні шляхи різних конфігів не перетинаються, і видавати діагностику (R1.3) |
| [#279](https://github.com/Carapacik/swagger_parser/issues/279), [#302](https://github.com/Carapacik/swagger_parser/issues/302), [#355](https://github.com/Carapacik/swagger_parser/issues/355), [#369](https://github.com/Carapacik/swagger_parser/issues/369) | Користувачі просять виключати моделі й фільтрувати вихід; tree-shaking з'явився пізно і з багами | Фільтри та tree-shaking закласти в ядро з першого дня (R4.1, R4.2) |
| [#232](https://github.com/Carapacik/swagger_parser/issues/232) | Тіло запиту — іменований параметр `body` | Тіло позиційним параметром, решта — іменованими (ергономіка API) |
| README і код | `put_in_folder` описаний у README, хоча в коді його немає; `generate_validator` не задокументований | Генерувати документацію конфігу з JSON Schema (R15.2, R15.5) |

Окремо про **build_runner**: issues саме про повільність у трекерах не знайшлося. Біль інша: розрив між двома фазами (#380, #411 — помилка видна лише після build_runner), обов'язковий порядок builder-ів у `build.yaml` для freezed, dart_mappable і retrofit (README) та обходи обмежень retrofit. Приклад обходу: параметр, що містить `value`, перейменовується на `value_` через [retrofit#661](https://github.com/trevorwang/retrofit.dart/issues/661) (SP:dart_retrofit_client_template.dart:L277-282, код).

## 1.7 Що варто запозичити

1. **`schemes:` з успадкуванням кореневих параметрів** (config_processor.dart:L44-87): простий і зрозумілий спосіб задати кілька специфікацій (R1.3).
2. **`replacement_rules` і `replacement_rules_for_raw_schema`**: упорядковані regex-правила, окремо для сирих імен і для Dart-імен (R5.1, R2.1). Застосовувати їх до символів, а не до тексту, і показувати у звіті, яке правило спрацювало.
3. **Фільтри**: `include_tags`/`exclude_tags` без урахування регістру, glob `*`/`**` для шляхів (path_match.dart), `fallback_client` для операцій без тегу, `merge_clients` (R4.1, R5.3).
4. **`fallback_union` із сирим JSON** (`json` getter) для невідомого discriminator (R9.1). Зробити це поведінкою за замовчуванням і для всіх представлень.
5. **`add_openapi_metadata`**: статична константа метаданих для кожної операції (tags, operationId, externalDocs). Покращити: завжди додавати до `RequestOptions.extra`, а не підставляти як дефолт параметра (R10.5).
6. **Doc-коментар при вимушеному перейменуванні**: «The name has been replaced because it contains a keyword. Original name: `x`.» (type_utils.dart:L191-240). Це дешева трасованість, і її варто доповнити кодом діагностики (R2.2).
7. **`$valuesDefined`**: список значень enum без unknown, зручний для UI-селекторів.
8. **`infer_required_from_nullable`** як іменоване правило нормалізатора для ASP.NET і NestJS, але з записом кожного спрацювання у звіт (R2.1).
9. **`field_parsers`**: інжекція `JsonConverter` для типу (R6.2). Адресувати краще за `format`, `x-` або override, ніж за Dart-типом.
10. **`generate_validator`**: обмеження як `static const` плюс `validate()` (R6.7, опційно).
11. **Інфраструктура тестів**: `test/e2e/tests/<case>/{openapi.yaml, expected_files/}` і прапорець `generateExpectedFiles` для регенерації golden-файлів (e2e_util.dart). Додати компіляцію й аналіз.
12. **Web-playground** (`swagger_parser_pages`): ядро без `dart:io` дозволяє спробувати генерацію в браузері, і це сильний маркетинговий хід.
13. Статистика після генерації (кількість файлів, рядків, час) і банер.

---

# 2. swagger_dart_code_generator (SDCG)

## 2.1 Огляд

| Параметр | Значення | Джерело |
|---|---|---|
| Остання версія | **4.1.1**, опублікована 2025-12-11. Попередні: 4.0.0 і 3.0.4 (2025-09-16), 4.0.1 і 4.0.2 (2025-09-29), 4.1.0 (2025-11-06) | pub.dev API |
| Pub points / likes / завантаження за 30 днів | **145/160** (−5: у CHANGELOG немає запису 4.1.1; −10: web) · 331 like · 62 634 | pub.dev `/score`, `/metrics` |
| GitHub | 303★, 161 fork, Apache-2.0, створений 2020-09-08 | `gh repo view` |
| Issues / PR | 55 відкритих issues з 398; **13 відкритих PR** (від 2026-01 до 2026-09, жоден не злитий) | `gh issue/pr list` |
| Активність | Останній коміт і реліз **2025-12-11**, 10 місяців тиші. Релізи пакетами від одного мейнтейнера (Vovanella95); [#796 «Future of this project»](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/796) (8 реакцій) без жодної відповіді | `gh api …/commits` |
| Розмір коду | ≈7.5 тис. рядків; `swagger_models_generator.dart` має 2033 рядки, `swagger_requests_generator.dart` — 1421 | `wc -l` |

Висновок: популярний за лайками й завантаженнями (legacy-база), але **фактично не підтримується** з грудня 2025 року. CHANGELOG малоінформативний: «Various fixes», «Fixed some border cases».

## 2.2 Архітектура

* **Запуск — лише як builder `build_runner`** (SDCG:build.yaml: `build_extensions "$lib$": [...]`, `build_to: source`, `runs_before: [chopper_generator, json_serializable]`). CLI немає. Конфіг задається в `build.yaml` → `targets.$default.builders.swagger_dart_code_generator.options` і десеріалізується через json_serializable (`GeneratorOptions`, SDCG:lib/src/models/generator_options.dart).
* **Вхід.** Усі `*.swagger`, `*.json`, `*.yaml` з `input_folder` (SDCG:lib/swagger_dart_code_generator.dart:L19, L36-40). `buildExtensions` обчислюється **листингом файлової системи** в конструкторі builder-а (L60-119), а файли читаються через `dart:io File(...)` в обхід `BuildStep.readAsString` (L166-167). Через це build_runner не бачить реальних залежностей: проблеми з кешем ([#789](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/789)), Pub Workspaces ([#852](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/852)), падіння на `.DS_Store` ([#563](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/563)) (код).
* **`input_urls`** завантажуються **під час кожного білду** (`http.get` без заголовків і без перевірки статусу) у `input_folder` (L149-157, L397-401) (код).
* **Вихід на кожну специфікацію:** `<name>.swagger.dart` (Chopper-сервіс, моделі, конвертер — все в одному файлі), `<name>.enums.swagger.dart`, `<name>.metadata.swagger.dart`, опційно `<name>.models.swagger.dart` (`separate_models`). Плюс спільні `client_index.dart` і `client_mapping.dart`. Далі `chopper_generator` і `json_serializable` генерують `.chopper.dart` і `.g.dart`.
* **HTTP-шар — Chopper.** `abstract class XService extends ChopperService` зі `static create({ChopperClient? client, http.Client? httpClient, Authenticator?, ErrorConverter?, Converter?, Uri? baseUrl, List<Interceptor>? interceptors})`. Публічні методи — конкретні обгортки над приватними анотованими `_method(...)` (SDCG:example/lib/swagger_generated_code/pet_service_json.swagger.dart:L29-79). Повертається `Future<chopper.Response<T>>`; з `custom_return_type` можна задати свій тип.
* **Серіалізація.** json_serializable з `explicitToJson: true`. Глобальний **рантайм-реєстр** фабрик `generatedMapping` (`Map<Type, JsonFactory>`): кожен метод виконує `generatedMapping.putIfAbsent(Pet, () => Pet.fromJsonFactory)` (SDCG:swagger_requests_generator.dart:L474). Top-level `$jsonDecoder` і `$CustomJsonDecoder` (SDCG:swagger_additions_generator.dart:L154-232). `_decodeList` мовчки відкидає `null`-елементи (L204).
* **Метадані.** Кожен приватний метод отримує `@chopper.Tag() SwaggerMetaData swaggerMetaData = const SwaggerMetaData(summary, description, operationId, consumes, produces, security, tags, deprecated)` (SDCG:swagger_meta_data_generator.dart; приклад вище). Через `Request.tag` метадані доступні interceptor-ам. З'явилось у вересні 2025 ([PR #811](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/pull/811)).
* **Форматування** через `dart_style` з опцією `page_width`; якщо форматування не вдалось, лише друкується warning (L135-144, L317-327). Заголовок `// ignore_for_file: type=lint`.
* **Моделі** містять `==` і `hashCode` (DeepCollectionEquality), `toString() => jsonEncode(this)`, а також extension `copyWith` і **`copyWithWrapped`** з `Wrapped<T>` для явного `null` (SDCG:swagger_additions_generator.dart:L149-151).

## 2.3 Конфіг як prior art

Повний список з `GeneratorOptions` (generator_options.dart:L9-41). README-таблиця неповна: у ній немає `model_postfix`, `custom_return_type`, `import_paths`, `page_width`, `generate_to_json_for`, `include_null_query_vars`, `urlencoded_file_type`, `custom_annotations`, `default_header_values_map`. `example/build.yaml` використовує неіснуючу опцію `use_default_null_for_lists`, яку парсер **мовчки ігнорує** ([#744](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/744)).

| Опція (дефолт) | Що робить | Prior art для | Оцінка |
|---|---|---|---|
| `input_folder`, `output_folder`, `input_urls: [{url, file_name}]` | вхід і вихід | R1.1, R1.3 | одна конфігурація на всі файли ([#785](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/785)) |
| **`overriden_models: [{file_name, import_url, overriden_models: [..]}]`** | замінити згенеровані моделі власними класами з імпорту, окремо для кожного файлу специфікації | **R3.1** (override типу) | найближчий до override-файлу механізм |
| **`response_override_value_map: [{url, method, overridden_value}]`** | задати Dart-тип відповіді для шляху+методу | **R3.1** (адресація операції) | тип — сирий рядок Dart, без перевірки |
| `nullable_models: [..]` | у вказаних моделей усі властивості nullable | R3.1 (`nullable`) | гранулярність — модель, не властивість |
| `classes_with_nullabe_lists: [regex]` (так, з помилкою в назві) | списки в цих класах мають дефолт `null`, а не `[]` | R6.1 | — |
| `default_values_map: [{type_name, default_value}]` | `defaultValue:` для всіх полів цього типу | (анти-патерн до R2.5 / R6.5) | мовчки підставляє `''` замість відсутнього значення (див. `Pet.name` у прикладі) |
| **`scalars: {format: {type, deserialize, serialize}}`** + `import_paths` | мапінг `format` → власний тип із функціями (де)серіалізації (наприклад `uuid` → `Uuid.parse`) | **R6.2** | добрий патерн; регресія в 4.1.0 для nullable ([#840](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/840)) |
| `custom_annotations: [{type_name, swagger_key}]` | якщо властивість має ключ `x-…`, генерується `@TypeName(value)` | R6.7, реєстр `x-` | — |
| `include_paths` / `exclude_paths` | **regex** за шляхом (swagger_requests_generator.dart:L141-147) | R4.1 | немає тегів і operationId; схеми не фільтруються (R4.2 ❌) |
| `use_path_for_request_names` (`true`) | ім'я методу з path+method; `false` бере `operationId` (L1044-1047) | R5.1 | дефолт дає імена на кшталт `petPetIdGet` |
| `cut_from_model_names` (regex), `model_postfix` | вирізати повторюваний префікс або додати суфікс до моделей | R5.1, **R4.3** | — |
| `enums_case_sensitive` (`true`) | регістронезалежне зіставлення enum | R8 | — |
| `with_base_url` (`true`), `add_base_path_to_requests` | вшити `servers[0]` / `basePath` у `create()` | R10.1, R10.9 | URL вшивається за замовчуванням |
| `with_converter` (`true`), `build_only_models` (`false`), `separate_models` (`false`) | склад виходу | R13.5 | — |
| `ignore_headers`, `additional_headers: [..]`, `default_header_values_map`, `use_required_attribute_for_headers` | керування заголовками | R10.3, R10.5 | — |
| `include_if_null` (`null`) | глобальний `includeIfNull` | R7.3 | глобально ([#806](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/806)) |
| `include_null_query_vars` (`false`) | `includeNullQueryVars` у Chopper | R10.3 | — |
| `generate_first_succeed_response` (`true`) | кілька 2xx: перший або `dynamic` (L1305) | R10.6 | явний вибір; добре, що він видимий |
| `multipart_file_type` (`List<int>`), `urlencoded_file_type` (`Map<String,String>`) | типи для multipart і urlencoded | R10.4 | — |
| `custom_return_type` | `MyType<T>` замість `Future<chopper.Response<T>>` | R11.2 (Result) | — |
| `generate_to_json_for: [..]` | `toJson` лише для вказаних моделей | R13.5 | — |
| `override_equals_and_hashcode` (`true`), `override_to_string` (`true`) | `==`, `hashCode`, `toString` | **R6.6** | — |
| `page_width` | ширина рядка для `dart_style` | **R13.2** | — |

## 2.4 Таблиця покриття вимог

| Вимога | Статус | Доказ / коментар |
|---|---|---|
| R0.1 OAS 3.0 і 3.1, чистий Dart | ⚠️ | Swagger 2.0 і OAS 3. Із 3.1 обробляється лише масив `type`, що містить `"null"` (SDCG:swagger_schema.dart:L115-119). `oneOf:[{type:null},{$ref}]` не підтримується ([#833](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/833)). Вихід — чистий Dart з `http` і Chopper |
| R1.1 вхід | ⚠️ | Локальні файли ✅. `input_urls` завантажуються під час кожного білду, без авторизації (код) |
| R1.2 `$ref` | ❌ | `split('/').last` (string_extension.dart:L32-34; `definedParameters[par.ref.split('/').last]`). Зовнішніх файлів немає |
| R1.3 кілька специфікацій | ⚠️ | Кілька файлів в одному `input_folder`, але конфіг спільний для всіх ([#785](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/785)) |
| R2.1–R2.5 нормалізація й діагностика | ❌ | Лише `print` при невдалому форматуванні. Тиха поведінка: cookie відкидаються, `default_values_map`, `oneOf` перетворюється на `dynamic` |
| R3.1 override-и | ⚠️ | `overriden_models`, `response_override_value_map`, `nullable_models`, `scalars`. Адресація не через JSON-pointer, попереджень про застарілі override-и немає (R3.2 ❌) |
| R4.1 фільтри | ⚠️ | Лише regex за шляхом (include і exclude) |
| R4.2 tree-shaking | ❌ | Генеруються всі компонентні схеми; фільтр шляхів стосується лише inline-відповідей (swagger_models_generator.dart:L209-220) |
| R4.3 безпечне співіснування | ❌ | Глобальний змінюваний `generatedMapping` і top-level `$jsonDecoder` (код). Колізії з іменами Chopper (`Query`: [#343](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/343)). `model_postfix` частково допомагає |
| R5.1 імена операцій | ⚠️ | За замовчуванням з path+method; `operationId` опційно; regex `cut_from_model_names` для моделей |
| R5.2 колізії | ⚠️ | `exceptionWords` і префікс `$` для дублікатів enum (enum_model.dart:L66-104). Дублікати методів: [#720](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/720) |
| R5.3 групування за тегом | ❌ | Один сервіс на файл специфікації ([#739](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/739)) |
| R5.4 inline-схеми | ⚠️ | Імена на кшталт `X$Item`, `Path$Method$Response` (зі знаком `$`). Override немає |
| R6.1 матриця required × nullable | ❌ | `isNullable = shouldBeNullable \|\| nullableModels \|\| !required` (swagger_models_generator.dart:L684-693): optional ⇒ nullable. required+nullable в конструкторі **не** required (L1663-1675). Усі параметри методів nullable ([#747](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/747)). Позитив: `readOnly`/`writeOnly` → nullable (swagger_schema.dart:L115-119) |
| R6.2 мапінг типів | ⚠️ | `int64` → **`num`** (constants.dart:L64-76; втрата точності на web, [#285](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/285)). `format: date` серіалізується як `yyyy-MM-dd` через `_dateToJson` ✅ (additions_generator.dart:L136-147). `additionalProperties` завжди дає `Map<String,dynamic>`, тип значення губиться (swagger_schema.dart:L151, models_generator.dart:L1314-1315). `scalars` ✅ |
| R6.3 `allOf` | ⚠️ | Властивості зливаються в плоску модель (L1929-1990); один `$ref` стає посиланням на тип (L931-946). Баги [#721](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/721), [#853](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/853) |
| R6.4 дженерики | ❌ | Є лише незлитий PR [#846](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/pull/846) |
| R6.5 зайві й відсутні поля | ⚠️/❌ | Зайві поля ігноруються. Відсутні обов'язкові часто **мовчки** отримують `defaultValue` (`''`, `[]`) |
| R6.6 `==`, `copyWith`, `toString` | ✅ | — |
| R6.7 обмеження | ❌ | Хіба що через `custom_annotations` |
| R7.1–R7.3 tri-state | ❌/⚠️ | `copyWithWrapped(Wrapped<T>?)` розрізняє «не передано» і «null» лише в `copyWith`. Серіалізація керується глобальним `includeIfNull` ([#768](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/768), [#806](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/806)) |
| **R8.1** сире значення enum | ❌ | `swaggerGeneratedUnknown(null)` (enum_model.dart:L57-64). `…FromJson` повертає `?? swaggerGeneratedUnknown` (L132). **У nullable-полях невідоме значення стає `null`** (`…NullableFromJson` → `?? defaultValue`, L111-112, L134-142) (код) |
| R8.2 невідоме не надсилається | ⚠️ | `…ToJson` дає `value`, тобто `null`. `…ListToJson` викликає `e.value!` і падає (L148, L161) |
| R8.3 типи enum | ⚠️ | Лише string та int: `isInteger` визначається за першим значенням (swagger_enums_generator.dart:L285-286). Імена приводяться до нижнього регістру ([#743](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/743)) |
| R8.4 `x-enum-*` | ⚠️ | `x-enumNames`, `x-enum-varnames`, `x-ms-enum` (constants.dart:L95-96, swagger_schema.dart:L87, L140). Описів немає |
| R9.1–R9.3 поліморфізм | ❌ | Discriminator не підтримується ([#563](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/563)). `anyOf` на верхньому рівні стає `typedef X = Map<String,dynamic>` або `Object` (L71-77). У властивості `anyOf`/`oneOf` з ≥2 не-null варіантами стає `dynamic` (L784-830) |
| R10.1 свій клієнт | ⚠️ | `create(client: myChopperClient)` бере клієнт користувача. Без нього генератор сам створює `ChopperClient` з вшитим URL зі специфікації (`with_base_url: true`) |
| R10.2 помилки йдуть шляхом клієнта | n/a / ⚠️ | Chopper не кидає виняток на не-2xx: `Response.error` разом із глобальним `ErrorConverter` |
| R10.3 параметри | ⚠️ | path/query/header ✅. Cookie **мовчки відфільтровуються** (requests_generator.dart:L740). `collectionFormat` парситься, але ніде не використовується; style і explode не підтримуються |
| R10.4 тіла | ⚠️ | JSON, multipart (`@Part`/`@PartFile`), urlencoded. Типізації binary-відповідей немає (незлитий PR [#854](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/pull/854)). Multipart для Swagger 2: [#726](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/726) (12 коментарів) |
| R10.5 метадані, скасування | ⚠️ | **Метадані operationId, tags, security є в кожному запиті** ✅. Скасування і прогресу немає ([#843](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/843) про `@AbortTrigger`) |
| R10.6 кілька 2xx, 204, статус | ⚠️ | `chopper.Response<T>` дає статус і заголовки; 204 з порожнім тілом повертає `null` (additions_generator.dart:L210-214). Кілька 2xx: перший або `dynamic` |
| R10.7 абстрактний API | ⚠️ | Абстрактний `ChopperService`, але публічні методи конкретні. Мокається через `implements` |
| R10.8 security як метадані | ✅/⚠️ | Імена security-схем потрапляють у `SwaggerMetaData.security` |
| R10.9 servers | ❌ | Береться лише перший URL |
| R11 типізовані помилки | ❌ | — |
| R12 SSE | ❌ | — |
| R13.1 детермінізм | ✅/⚠️ | `dart_style` + порядок зі специфікації. Скарги на «інший код з тієї самої специфікації» ([#770](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/770)) насправді про зміну між версіями |
| R13.2 лінти, формат | ⚠️ | Форматування є, але лінти приглушені `type=lint` |
| R13.3 runtime-залежності | ⚠️ | runtime: chopper, json_annotation, http, collection. Сам генератор тягне `build`, `dart_style`, `code_builder` у dev-граф користувача, звідси конфлікти ([#812](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/812), [#817](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/817), [#800](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/800)) |
| R13.4 документація в коді | ⚠️ | `///@param …`; `@deprecated` без повідомлення |
| R13.5 розмір виходу | ⚠️ | Заглушок немає, але одна величезна збірка на специфікацію без tree-shaking |
| R14 еволюція | ❌ | — |
| R15.1 CLI і API | ⚠️ | Лише builder для build_runner |
| R15.2 конфіг із JSON Schema | ❌ | Невідомі ключі мовчки ігноруються ([#744](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/744)); помилки конфігу виглядають як `type 'YamlMap' is not a subtype of 'bool?'` ([#208](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/208), 25 коментарів) і `'Null' is not a subtype of 'String'` ([#798](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/798)) |
| R15.3 тести | ⚠️ | 8 тестових файлів зі строковими порівняннями фрагментів; приклад регенерують вручну |
| R15.4 semver | ⚠️ | У CHANGELOG немає запису для 4.1.1; регресії в minor ([#840](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/840)); 4.1.1 відкотила PR #830 |

## 2.5 Перевірка тверджень автора

* R8.1 у формулюванні автора стосується swagger_parser і tonik, а не SDCG. Але SDCG **так само втрачає сире значення (код)**. Гірше: у nullable-полях невідоме значення стає `null` (enum_model.dart:L134-142), і його не відрізнити від відсутнього. Додаткова скарга [#809](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/809): зайва константа `swaggerGeneratedUnknown` у **кожному** enum ламає мапери на кшталт `auto_mappr`. Це аргумент тримати unknown **поза** множиною значень enum, тобто для відкритого рішення 7.
* «SDCG має `overriden_models`, `response_override_value_map`, `default_values_map`, `include_if_null`, `enums_case_sensitive`, `classes_with_nullabe_lists`, `separate_models`, `use_path_for_request_names`, `exclude_paths`/`include_paths`, `with_converter`» — **підтверджено (код)**: усі ці імена є в `GeneratorOptions`. Уточнення: `include_paths`/`exclude_paths` у SDCG — **regex**, а не glob. У swagger_parser `exclude_paths` **немає** (лише `include_paths` з glob). `required_by_default` у swagger_parser видалено в 1.18.0.

## 2.6 Відомі проблеми (issue tracker + код) і уроки

| # | Суть | Урок для нового інструмента |
|---|---|---|
| [#812](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/812) (**17 реакцій**, найпопулярніше), [#817](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/817), [#800](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/800), [#793](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/793), [#749](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/749) (16 коментарів), [#754](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/754), [#518](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/518) | Конфлікти версій `build`, `dart_style`, `chopper`; мажорні версії Chopper ламали вихід | Генератор не повинен жити в dependency graph користувача: CLI через `dart pub global activate` або `dart run`, зібраний окремо. Runtime-пакет мінімальний, із CI-матрицею версій залежностей (R13.3, відкрите рішення 1) |
| [#796](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/796), 13 відкритих PR | Проєкт закинутий, bus factor 1 | Відкрите управління: кілька мейнтейнерів, автоматичні релізи, публічна roadmap |
| [#182](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/182) (28 коментарів), [#324](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/324), [#506](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/506), [#650](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/650), [#747](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/747), [#806](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/806) | «Усе nullable»; required і nullable плутаються | R6.1: явна матриця, задокументована таблицею в README |
| [#410](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/410) (23 коментарі), [#436](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/436) (15), [#147](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/147), [#219](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/219), [#557](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/557), [#836](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/836) | «Could not find factory for type X» і помилки кастів у рантайм-конвертері `Map<Type, factory>` | Декодування має бути статичним у місці виклику (`Pet.fromJson`), без глобальних реєстрів і `Type`-ключів (R4.3) |
| [#563](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/563) (5 реакцій, 2023), [#761](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/761), [#833](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/833), [#803](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/803), [#758](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/758) | Немає discriminator, `anyOf`/`oneOf` стає `dynamic`; Microsoft.AspNetCore.OpenApi (.NET 10) генерує `oneOf:[null,$ref]` | R9 з першого релізу. Правило нормалізатора `oneOf-null-ref → nullable ref` для .NET 10 (R2.1) |
| [#768](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/768), [#806](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/806) | PATCH: не можна відрізнити «не надсилати» від «надіслати null» | R7: tri-state на рівні типів і власний `toJson` для таких моделей |
| [#285](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/285) (31 коментар) | `int64` → `num` втрачає точність на web, причому мовчки | Мапінг `int64` налаштовується (`int`, `BigInt`, `String`), з діагностикою для web-цілі (R6.2) |
| [#343](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/343) (14 коментарів), [#720](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/720), [#188](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/188), [#743](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/743), [#827](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/827), [#847](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/847) | Схема `Query` конфліктує з анотацією Chopper; дублікати імен функцій; enum у нижньому регістрі; `)` в іменах enum; властивість `type` | Зарезервовані імена включають runtime-символи; імпорти з префіксом; детермінований casing; fuzz-тести імен (R5.2) |
| [#739](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/739) | Один API-клас на всю специфікацію | Групування за тегом (R5.3) |
| [#852](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/852), [#789](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/789), [#277](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/277) (16), [#169](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/169), [#567](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/567), [#426](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/426), [#354](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/354) | Builder бере файли з ФС через `dart:io`, ламаються кеш, workspaces і вихідні шляхи | Якщо інтеграцію з build_runner таки робити, то лише як тонку обгортку, що читає через `BuildStep`, над тим самим ядром, що й CLI (R15.1) |
| [#770](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/770), [#840](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/840), [#354](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/354) | Вихід або поведінка змінюються в minor-версіях, рантайм-крахи | Golden-тести виходу + runtime-тести декодування + політика «зміна виходу = major» (R15.3, R15.4) |
| [#385](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/385) (20 коментарів), [#726](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/726) (12), [#760](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/760), [#799](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/799) | Multipart не генерується або генерується неправильно | Модель частин multipart + тести на `$ref`-схеми з файлами (R10.4) |
| [#208](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/208) (25), [#798](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/798), [#744](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/744), [#206](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/206), [#200](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/200) | Незрозумілі помилки конфігу; невідомі ключі мовчки ігноруються; опції неочевидно впливають одна на одну | Конфіг з JSON Schema, строгий режим для невідомих ключів, людські повідомлення (R15.2) |
| [#809](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/809), [#549](https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues/549) (16) | `swaggerGeneratedUnknown` заважає маперам; `""` в enum трактується як `null` | Unknown тримати поза множиною значень enum. Порожній рядок — нормальне значення з детермінованим іменем (R8.1, R8.3) |
| Код | Cookie відкидаються (L740); `collectionFormat` ігнорується; `additionalProperties` втрачає тип | R2.5: кожна відкинута конструкція має породжувати діагностику |

## 2.7 Що варто запозичити

1. **`SwaggerMetaData` у кожному запиті** через `@chopper.Tag()`: типізований const-об'єкт з `operationId`, `summary`, `tags`, `security`, `consumes`, `produces`, `deprecated`. Для Dio аналог — `RequestOptions.extra['openapi'] = const OperationMeta(...)` у кожному виклику, з мерджем у користувацький `extra` (R10.5, R10.8). Сильніше за `add_openapi_metadata` у SP, бо прив'язано завжди і не перезаписується.
2. **`scalars`**: `format` → `{type, deserialize, serialize}` + `import_paths` (R6.2). Це майже готовий дизайн налаштовуваного мапінгу примітивів (`Decimal`, `Uuid`, власний `Date`).
3. **`overriden_models`** (замінити модель власним класом через імпорт) і **`response_override_value_map`** (шлях+метод → тип). Вони показують, що користувачі реально потребують override-ів типу на рівні моделі й операції (R3.1). Новий інструмент має робити те саме через адресацію pointer-ом, з валідацією та попередженням про застарілий override.
4. **`Wrapped<T>` у `copyWithWrapped`**: перевірений спосіб представити «явний null проти не передано» в Dart без кодогенерації (відкрите рішення 7, R7). Розширити на серіалізацію тіла запиту.
5. **`_dateToJson`** для `format: date` у вигляді `yyyy-MM-dd` (R6.2): прямо закриває біль SP [#463](https://github.com/Carapacik/swagger_parser/issues/463).
6. **`readOnly`/`writeOnly` → nullable** як прагматичний дефолт (краще — окремі request/response-представлення, R6.1).
7. **`generate_first_succeed_response`**: явний перемикач замість прихованого правила. Новому інструменту краще union, але сама ідея «зробити компроміс видимим у конфігу» правильна.
8. **`dart_style` + `page_width`** у самому генераторі (R13.1, R13.2).
9. **`model_postfix`, `cut_from_model_names`, `generate_to_json_for`, `build_only_models`**: дрібні, але затребувані ручки розміру й неймінгу (R4.3, R13.5).
10. **`custom_annotations`** (`x-ключ` → анотація): дешевий механізм розширення через реєстр `x-` (відкрите рішення 6).
11. Обробка 204 і порожнього тіла в конвертері (additions_generator.dart:L210-214).

---

# 3. Наскрізні висновки для відкритих рішень (стисло)

| Відкрите рішення | Що показали SP і SDCG |
|---|---|
| 1. Анотований код + build_runner чи готовий код | Обидва вимагають build_runner. SP: CLI плюс друга фаза, і помилки видно лише після неї (#380, #411, #462). SDCG: builder у графі користувача, звідси dependency hell (#812 — топ-issue), кеш і workspaces (#789, #852). **Аргумент за готовий код без build_runner** або хоча б за компіляцію виходу в CI генератора |
| 2. Серіалізація | json_serializable підтримує unknown enum лише через спосіб вибору helper-ів (`JsonHelper` раніше за `EnumHelper`), а сирого значення не зберігає. `includeIfNull` задається статично на поле, тож tri-state через json_serializable без власного `toJson` неможливий. Три гілки серіалізаторів у SP множать баги (#409, #411, #462, #351). Висновок: один серіалізатор (json_serializable для звичайних моделей) і власний код для enum, union і PATCH-тіл |
| 3. HTTP-шар | Retrofit в SP задає стелю: один тип відповіді на метод (#385), немає типізованих помилок (#367), streaming лише `String`/`Uint8List`, хак `value_`. Chopper у SDCG не кидає винятків на HTTP-помилки й має глобальний реєстр. Висновок: генерувати прямі виклики `dio.fetch`, без retrofit |
| 4. Модель помилок | В обох нуль. SDCG: `custom_return_type` і `ErrorConverter`. SP: `HttpResponse<T>`. Простору для диференціації багато |
| 5. Парсер | Обидва ходять по `Map<String,dynamic>` з кастами, звідси крахи на брудних специфікаціях (SP #374, #375, #442). SP ще й переписує специфікацію regex-ами по тексту (corrector) і стрингифікує YAML-скаляри. `$ref` резолвиться як «останній сегмент». **Потрібна власна типізована модель з JSON-pointer у кожному вузлі**: це база для R2.2 і R3.1 |
| 6. Розширюваність | Шаблонів ніхто не відкриває. Реально використовуються конфіг-хуки: `field_parsers` у SP; `scalars`, `custom_annotations`, `overriden_models` у SDCG. «Конфіг + override-и + реєстр `x-`» покриває запит |
| 7. Сирий enum і tri-state | Обидва роблять «enum + константа unknown без raw», а SDCG у nullable-полях ще й робить null. Скарги на зайву константу (SDCG #809) і неможливість побачити raw (SP #106) кажуть, що варто брати sealed або extension type з `Unknown(raw)`, а для tri-state — `Wrapped`/`Optional`-подібний тип (prior art: SDCG `copyWithWrapped`) |

---

# Джерела

**Код (shallow clone, 2026-10-11):**
* SP @ `be6df7c11205d5e7dacf8cace6b07c7c5885c3fc`: базовий URL `https://github.com/Carapacik/swagger_parser/blob/be6df7c11205d5e7dacf8cace6b07c7c5885c3fc/swagger_parser/`
  * `lib/src/generator/templates/dart_enum_dto_template.dart` (enum, R8.1)
  * `lib/src/generator/templates/dart_json_serializable_dto_template.dart` (union, fallback, `_jsonKey`)
  * `lib/src/generator/templates/dart_freezed_dto_template.dart` (freezed fallback, validator)
  * `lib/src/generator/templates/dart_dart_mappable_dto_template.dart`
  * `lib/src/generator/templates/dart_retrofit_client_template.dart` (клієнт, stream, metadata, content-type)
  * `lib/src/generator/templates/dart_root_client_template.dart`
  * `lib/src/parser/parser/open_api_parser.dart` (required/nullable, `$ref`, cookie, content-type, path-item cast)
  * `lib/src/parser/corrector/open_api_corrector.dart` (текстові заміни, `YamlMapX.toMap`)
  * `lib/src/parser/utils/type_utils.dart`, `lib/src/parser/utils/http_utils.dart`, `lib/src/parser/utils/dart_keywords.dart`, `lib/src/parser/utils/path_match.dart`
  * `lib/src/config/swp_config.dart`, `lib/src/config/config_processor.dart`, `lib/src/utils/file/io_file.dart`, `lib/src/utils/base_utils.dart`
  * `test/e2e/e2e_util.dart`, `test/e2e/tests/**`, `.github/workflows/tests.yml`, `README.md`, `CHANGELOG.md`
* SDCG @ `753bdebea6774947c0b543c755af5448af85844d`: базовий URL `https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/blob/753bdebea6774947c0b543c755af5448af85844d/`
  * `lib/swagger_dart_code_generator.dart` (builder, dart:io, input_urls, formatter)
  * `lib/src/models/generator_options.dart` (усі опції)
  * `lib/src/code_generators/enum_model.dart` (enum, unknown)
  * `lib/src/code_generators/swagger_models_generator.dart`, `swagger_requests_generator.dart`, `swagger_additions_generator.dart`, `swagger_meta_data_generator.dart`, `constants.dart`
  * `lib/src/swagger_models/responses/swagger_schema.dart`, `lib/src/extensions/string_extension.dart`
  * `example/build.yaml`, `example/lib/swagger_generated_code/*.dart`, `README.md`, `CHANGELOG.md`, `build.yaml`
* json_serializable 6.14.1 (локальний pub-cache, той самий код, що на pub.dev): `lib/src/settings.dart` (порядок helper-ів), `lib/src/type_helpers/json_helper.dart` (конструктор `fromJson`), `lib/src/type_helpers/enum_helper.dart`, `lib/src/enum_utils.dart` (`_generateEntry` → ім'я поля без `@JsonValue`). json_annotation 4.12.0 `lib/src/enum_helpers.dart` (`$enumDecode`). Upstream: <https://github.com/google/json_serializable.dart>

**pub.dev API (2026-10-11):**
* <https://pub.dev/api/packages/swagger_parser>, `/score`
* <https://pub.dev/api/packages/swagger_dart_code_generator>, `/score`, `/metrics`

**GitHub (через `gh`, 2026-10-11):**
* Issues SP: <https://github.com/Carapacik/swagger_parser/issues> (218 загалом, 71 відкрите). Ключові: #106, #120, #121, #194, #213, #218, #232, #239, #251, #257, #271, #273, #279, #285, #302, #303, #304, #306, #307, #312, #321, #340, #342, #358, #363, #366, #367, #369, #374, #375, #379, #380, #381, #385, #388, #389, #393, #405, #408, #409, #411, #414, #415, #423, #429, #432, #440, #441, #442, #443, #444, #446, #448, #454, #460, #462, #463
* Issues/PR SDCG: <https://github.com/epam-cross-platform-lab/swagger-dart-code-generator/issues> (398 загалом, 55 відкритих; 13 відкритих PR #832–#858). Ключові: #182, #188, #200, #206, #208, #219, #277, #285, #324, #343, #354, #385, #410, #426, #436, #506, #518, #549, #557, #563, #567, #650, #721, #726, #739, #743, #744, #747, #749, #754, #758, #760, #761, #768, #770, #785, #789, #793, #796, #798, #799, #800, #803, #806, #809, #811 (PR), #812, #817, #827, #833, #836, #840, #843, #846 (PR), #847, #852, #853, #854 (PR)
* Історія комітів: `gh api repos/<repo>/commits?since=…`, `/contributors`
* retrofit: [trevorwang/retrofit.dart#661](https://github.com/trevorwang/retrofit.dart/issues/661) (цитується в коді SP)
