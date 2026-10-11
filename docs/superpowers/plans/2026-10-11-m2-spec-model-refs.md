# План M2: модель специфікації і `$ref`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `typed_openapi check` читає кожну специфікацію в незмінну типізовану модель (надмножина OAS 3.0/3.1/3.2), розв'язує всі `$ref` усередині документа і між локальними файлами, визначає діалект за вмістом і повідомляє про невідомі ключі, значення неправильного типу, пропущені обов'язкові поля, биті, віддалені й зациклені посилання. Заразом закриває знахідки рев'ю M1 про завантаження (глибока вкладеність, ключі `1`/`"1"`, каталог замість файлу, порядок TOA005/TOA003, `.json` з дублікатом і синтаксичною помилкою).

**Architecture:** Три нові шари в `packages/typed_openapi/lib/src/` над наявним `load/`: `model/` — незмінні вузли (`SpecNode` з `SpecLocation` = абсолютний URI файлу + JSON pointer, `x-`-розширеннями і невідомими ключами; `RefOr<T>` = `Ref<T>` | `Inline<T>`; `Schema` = `BooleanSchema` | `SchemaObject`, де `$ref` — ключове слово); `parse/` — `OpenApiParser`, `OperationParser`, `SchemaParser` поверх `ObjectReader`, які нічого не кидають, а пишуть у `DiagnosticBag` і в спільний `SpecIndex` (усі вузли, усі `$ref`, усі версійно-специфічні конструкції); `resolve/` — `RefTarget` (розбір значення `$ref`), `SpecDocuments` (інші локальні файли, кожен один раз), `RefResolver` (ціль кожного `$ref`, вид цілі, цикли) і `SpecModel` (результат з `resolve`/`resolveSchema`). `SpecReader` з'єднує parse → resolve → `DialectChecker`; `SpecChecker` викликає його після детекції версії.

**Tech Stack:** Dart `>=3.10.0 <4.0.0`, чистий Dart; наявні залежності `yaml`, `source_span`, `path`, `args`, `io`; тести на `package:test`. Нових залежностей немає.

**Spec:** [docs/requirements.md](../../requirements.md) — R0.1, R1.2, R1.4, R2.1 (част.), R2.2, R2.5, R13.1. Версії й діалекти — [research/06 §A](../../research/06-spec-versions-and-defects.md) (A.1–A.3); каталог дефектів і діапазони кодів — [research/06 §C](../../research/06-spec-versions-and-defects.md) (C.0, C-2, C-3, C-16, C-17, C-47); архітектура парсера — [research/03 §4](../../research/03-tonik-swagger-to-dart-space-gen.md) і урок space_gen #358 (§3.5). Місце етапу — [roadmap.md](../../roadmap.md), розділ «Перенесено з M1». Правила коду — [CLAUDE.md](../../../CLAUDE.md) і [CONTRIBUTING.md](../../../CONTRIBUTING.md).

## Global Constraints

- SDK `>=3.10.0 <4.0.0`; обидва пакети — чистий Dart без Flutter. Primary constructors (Dart 3.13) не використовуються.
- Можливості Dart 3.10 використовуються активно: dot shorthands скрізь, де відомий тип контексту (`.invalidRef`, `.v31`, `kind == .mediaType`), null-aware елементи колекцій (`name: ?read(...)`), switch-вирази і patterns, records (`(Object?,)?` для «значення може бути `null`»), модифікатори класів (`final`, `sealed`). У тестах аргументи `expect(...)` пишуться повними іменами (`DiagnosticCode.invalidRef`).
- ООП: жодних функцій верхнього рівня, крім `main` у `bin/` і в тестах. Компоненти, що звітують про проблеми, отримують `DiagnosticBag` через конструктор (`SpecReader(bag)`, `RefResolver(bag)`, `DialectChecker(bag)`; парсери — через `ParseContext`).
- R2.5: помилки у вхідних даних ніколи не кидаються як винятки — вони потрапляють у `DiagnosticBag`, решта документа читається далі. `StackOverflowError` не ловиться (лінт `avoid_catching_errors`): надто глибокий вхід відсіюється до рекурсивного розбору.
- R2.2: кожна нова проблема — код `TOAnnn` у `DiagnosticCode` з doc-коментарем, slug у kebab-case, рівень за замовчуванням, файл, JSON pointer і, коли відомо, позиція. Діапазони — з research/06 §C.0: `0xx` документ і діалект, `1xx` посилання і структура.
- R13.1: результат детермінований — вузли і діагностики йдуть у порядку документа, цикли й набори сортуються (`SpecLocation.compareTo`), звіт сортує `DiagnosticBag.sorted`.
- Модель незмінна: поля `final`, колекції — `List.unmodifiable`/`Map.unmodifiable` або `const`.
- Ідентичність вузла — абсолютний URI файлу + JSON pointer (`SpecLocation`), а не лише pointer (space_gen #358).
- Лінти з кореневого `analysis_options.yaml` (`public_member_api_docs`, `sort_constructors_first`, `prefer_final_locals`, `require_trailing_commas`, `use_raw_strings`, `avoid_catching_errors` та інші). `dart analyze packages` з кореня — `No issues found!`; `dart format` з `trailing_commas: preserve` змінює 0 файлів.
- Немає залежності від `analyzer`. Тести не ходять у мережу; тимчасові файли — лише через `test/helpers/temp_dir.dart`. Справжні специфікації компанії в репозиторій не потрапляють; у тестах — вигадані фрагменти.
- Команди `dart test`, `dart format`, `dart pub publish --dry-run` — з `packages/typed_openapi`; `dart pub get`, `dart analyze packages` і всі `git`-команди — з кореня.
- Кожен коміт закінчується рядком `Co-Authored-By` моделі, що виконує задачу (у прикладах нижче — `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`).

## Ухвалені рішення

1. **Обсяг одного плану.** M2 не ділиться на M2a/M2b: 12 задач, кожна з власним тестовим циклом; після Task 7 модель уже читається, після Task 11 — резолвиться, Task 12 вмикає все в `check`. Розбиття дало б M2a без жодного видимого для користувача результату.
2. **Lossless.** Сире дерево `SpecDocument` лишається поруч із моделлю і отримує `uri` та `valueAt(pointer)`. Модель типізує все, що потрібно для кодогену (перелік — у класах `model/`). Ключі, які специфікація визначає, але модель поки не типізує (`externalDocs`, `xml`, `links`, `callbacks`, `contact`, `license`, `termsOfService`), приймаються мовчки і доступні в `SpecDocument` за pointer вузла. Ключові слова JSON Schema 2020-12 без типізованого поля (`$defs`, `if`/`then`/`else`, `patternProperties`, `unevaluated*` …) зберігаються сирими в `SchemaObject.otherKeywords`. `x-`-ключі — у `extensions` кожного вузла. Ключі Paths Object і Responses Object, що починаються з `x-`, не стають шляхами чи статусами (лишаються в сирому дереві).
3. **Невідомі ключі** (ні в 3.0, ні в 3.1, ні в 3.2, не `x-`) зберігаються в `unknownKeys` вузла і дають `TOA110 unknown-key` рівня **warning**: так ловляться опечатки (`nmae`) і залишки Swagger 2 (`type` у параметрі), а на реальній NestJS-специфікації (734 операції, 1434 схеми) таких ключів 0, тож шуму немає. Reference Object не можна розширювати, тому всі його ключі, крім `$ref`/`summary`/`description`, — невідомі.
4. **Неправильний тип значення** (`required: true` замість списку, `minLength: -1`, `in: body`) — `TOA111 invalid-value`, **warning**: поле читається як відсутнє, решта вузла читається. Це саме те місце, де M3 поставить правило `bool-required-to-array` (C-1, C-49) — воно виправить сире дерево до розбору, і TOA111 там зникне. Явний `null` у типізованому полі — теж TOA111; у полях «будь-якого значення» (`default`, `const`, `example`, `enum`) `null` — нормальне значення, тому вони зберігаються як record `(Object?,)?`.
5. **Обов'язкові поля** — `TOA112 missing-required-field`, **warning**, лише для полів, обов'язкових в усіх трьох версіях: `info`, `info.title`, `info.version`, `name` і `in` параметра, `type` схеми безпеки (і `name`/`scheme`/`flows`/`openIdConnectUrl` за її типом), `url` сервера, `default` серверної змінної, `name` тегу, `propertyName` дискримінатора, `content` тіла запиту. Залежні від версії вимоги (`paths` і `responses` у 3.0, `description` відповіді до 3.2) не перевіряються: це шум для документів 3.2 і робота нормалізатора (M3). У моделі такі поля nullable.
6. **Діалект за вмістом.** Парсер читає кожну конструкцію будь-якої версії і лише відмічає версійно-специфічні (`SpecFeature`: `since`/`until`). `DialectChecker` порівнює їх з оголошеною версією: 3.1-конструкції в 3.0 — `TOA020` (warning, SG001), `nullable` у 3.1+ — `TOA021` (warning, SG002), 3.2-конструкції в старших — `TOA022` (info, SG003). Щоб не шуміти, кожна конструкція повідомляється **один раз** — у місці першого використання, з кількістю місць у тексті. Нічого не конвертується: `nullable` і `type: [T, "null"]` лежать у моделі як записані; зведення — M3.
7. **`$ref` у схемі** — ключове слово (`SchemaObject.ref`), сусідні ключі зберігаються (3.1 застосовує їх разом із `$ref`). Для інших вузлів — `RefOr<T>`: `Ref<T>` (Reference Object з `summary`/`description`) або `Inline<T>`.
8. **Резолвер.** Усі `$ref` записуються під час розбору (`RefUse`: де, що, якого виду ціль очікується). `RefResolver` обходить їх списком (новий файл додає свої `$ref` у кінець списку), ціль ідентифікує `SpecLocation`. Ціль, яку основний розбір не читав (інший файл, `x-shared`, `$defs`), розбирається на вимогу як очікуваний вид вузла. Інші файли читаються `SpecLoader` один раз (`SpecDocuments`), у діагностиках названі відносно показаного шляху кореневого документа. Віддалені URI (http, https, urn) не читаються (R1.1) — `TOA102`. Порожні, обрізані (`#/components/schemas/`), «на цілу секцію» (`#/components/schemas`) і не-pointer фрагменти (`#Pet`, `$anchor`) — `TOA100` (SG101). Ціль, якої немає, або файл, якого немає, — `TOA101` (SG102). Ціль іншого виду (параметр → схема) — `TOA104`. `$id` у схемі і `$self` у документі змінювали б базовий URI — модель їх зберігає, резолвер їх не застосовує і каже про це (`TOA105`).
9. **Цикли.** Цикл — це лише ланцюжок посилань, що ніколи не доходить до вузла без `$ref` (`A → B → A`, `A → A`). Рекурсивна схема (`Node.children.items → Node`) — легальна. Кожен цикл повідомляється один раз (`TOA103`), у місці найменшого за `SpecLocation` учасника, з ланцюжком у повідомленні; `SpecModel.resolve` для таких посилань повертає `null`.
10. **Глибока вкладеність.** `package:yaml` рекурсивно розбирає вкладеність і падає з `StackOverflowError` десь на 3 500 рівнях (виміряно в `dart test`). `NestingScanner` до розбору оцінює глибину зверху (дужки поза рядками й коментарями; для блочного YAML — відступ і маркери `- `) і відкидає текст глибший за 1000 рівнів (`TOA007`). Ліміт достатній: реальні специфікації мають десятки рівнів, а парсер моделі перевірено на 996-рівневій схемі. Той самий захист стоїть у `ConfigLoader` (`TOA902`).
11. **Залишки рев'ю M1.** YAML-ключі, що стають однаковим JSON-ключем (`1` і `"1"`), — `TOA002` warning, перемагає останнє значення (як у JSON). Каталог замість файлу: специфікація — `TOA006` («is a directory»), конфіг — `TOA902`. `TOA005` («без позицій») повідомляється лише тоді, коли документ справді повертається, тобто після перевірки кореня (`TOA003`). `.json` з дублікатом і синтаксичною помилкою дає `TOA002` (warning) і `TOA001` (error) з позицією з `jsonDecode`.
12. **`check` і версія.** Модель читається лише для документів, версію яких визначено (Swagger 2 і документ без `openapi` дають лише M1-діагностики). Звідси й зміна в наявних тестах: мінімальні фікстури `openapi: 3.x` отримують `info`, бо без нього тепер є `TOA112`.

## Нові коди діагностики

| Код | Slug | Рівень | Коли | Research |
|---|---|---|---|---|
| TOA007 | `nesting-too-deep` | error | Текст глибший за 1000 рівнів | — |
| TOA020 | `openapi-3-1-in-3-0` | warning | 3.1 / JSON Schema 2020-12 у документі 3.0 | SG001, C-17 |
| TOA021 | `nullable-after-3-0` | warning | `nullable` у документі 3.1+ | SG002, C-16 |
| TOA022 | `openapi-3-2-in-older` | info | Конструкції 3.2 у документі 3.0/3.1 | SG003, C-47 |
| TOA100 | `invalid-ref` | error | Порожній, обрізаний, не-pointer `$ref` або `$ref` на цілу секцію | SG101, C-2 |
| TOA101 | `unresolved-ref` | error | Цілі або файлу немає | SG102, C-3 |
| TOA102 | `remote-ref` | error | `$ref` на http(s)/інший не-file URI | R1.1 |
| TOA103 | `ref-cycle` | error | Цикл посилань без визначення | R1.2 |
| TOA104 | `ref-kind-mismatch` | error | Ціль іншого виду | — |
| TOA105 | `ref-base-ignored` | warning | `$id` у схемі або `$self` у документі | A.1 #10, A.2 #12 |
| TOA110 | `unknown-key` | warning | Ключ, якого немає в жодній версії | A.3 п. 4 |
| TOA111 | `invalid-value` | warning | Неправильний JSON-тип або недопустиме значення | C-1, C-49 |
| TOA112 | `missing-required-field` | warning | Обов'язкове поле відсутнє | — |

Наявні коди отримують нові випадки: `TOA002` (злиті YAML-ключі), `TOA006` (каталог замість специфікації), `TOA902` (каталог замість конфігу, надто глибокий конфіг).

## Що свідомо не входить у M2

- Будь-яке виправлення дефектів (зведення `nullable`, `required: bool` → список, `examples` за версією, порожній `$ref` → JSON value) — правила нормалізатора M3. M2 лише читає і повідомляє.
- Перевірка імен: `security` → оголошені схеми безпеки, `tag.parent` → оголошений тег, значення `discriminator.mapping` (C-4), path-параметри проти шаблону шляху (C-6, C-7), ключі components за регексом (C-32) — M3.
- Зміна базового URI через `$id`, `$self`, `$anchor`, `$dynamicRef` — лише діагностика `TOA105`/`TOA100`; коли знадобиться реальним специфікаціям.
- Завантаження віддалених `$ref` — разом із локальним знімком і lock-файлом (M12).
- Злиття ключів, сусідніх з `$ref` (3.1), і `allOf` — семантична IR (M6). `SpecModel.resolveSchema` повертає кінцеву ціль без злиття.

## Структура файлів

Усі шляхи відносно `packages/typed_openapi/`, якщо не сказано інше.

| Файл | Відповідальність | Задача |
|---|---|---|
| `lib/src/load/spec_document.dart` | + `uri`, `valueAt(pointer)` | 1 |
| `lib/src/load/spec_loader.dart` | каталог, злиті ключі, порядок TOA005, JSON-fallback, `uri`, захист глибини | 1, 2 |
| `lib/src/config/config_loader.dart` | каталог, захист глибини | 1, 2 |
| `lib/src/load/nesting_scanner.dart` | `NestingScanner` — оцінка глибини без розбору | 2 |
| `lib/src/diagnostics/diagnostic_code.dart` | нові коди | 2, 4, 5, 8–11 |
| `lib/src/model/spec_node.dart` | `SpecLocation`, `SpecNode`, `RefKind`, `RefOr`, `Ref`, `Inline` | 3 |
| `lib/src/parse/spec_feature.dart` | `SpecFeature` — версійно-специфічні конструкції | 4 |
| `lib/src/parse/parse_context.dart` | `RefUse`, `FeatureUse`, `SpecIndex`, `ParseContext` | 4 |
| `lib/src/parse/object_reader.dart` | `ObjectReader` — типізоване читання полів, невідомі ключі | 4 |
| `lib/src/model/schema.dart` | `Schema`, `BooleanSchema`, `SchemaObject`, `SchemaType`, `Discriminator` | 5 |
| `lib/src/parse/schema_parser.dart` | `SchemaParser` | 5 |
| `lib/src/model/operation.dart` | `PathItem`, `Operation`, `Parameter`, `RequestBody`, `Response`, `Header`, `MediaType`, `Encoding`, `Example`, `Server`, `ServerVariable`, `SecurityRequirement` і enum-и | 6 |
| `lib/src/parse/operation_parser.dart` | `OperationParser` | 6 |
| `lib/src/model/security.dart` | `SecurityScheme`, `OAuthFlows`, `OAuthFlow` і enum-и | 7 |
| `lib/src/model/document.dart` | `OpenApiDocument`, `Info`, `Tag`, `Components` | 7 |
| `lib/src/parse/openapi_parser.dart` | `OpenApiParser` — документ і фрагменти для `$ref` | 7 |
| `lib/src/load/openapi_version.dart` | + `OpenApiVersion.label` | 8 |
| `lib/src/parse/dialect_checker.dart` | `DialectChecker` | 8 |
| `lib/src/resolve/ref_target.dart` | `RefTarget`, `ResolvableRef`, `BrokenRef` | 9 |
| `lib/src/resolve/spec_documents.dart` | `SpecDocuments` — файли специфікації за URI | 10 |
| `lib/src/resolve/spec_model.dart` | `SpecModel` | 10 |
| `lib/src/resolve/ref_resolver.dart` | `RefResolver` (+ цикли в Task 11) | 10, 11 |
| `lib/src/resolve/spec_reader.dart` | `SpecReader` — parse → resolve → dialect | 12 |
| `lib/src/check/spec_checker.dart` | викликає `SpecReader` | 12 |
| `lib/typed_openapi.dart` | експорт моделі, `SpecReader`, `SpecModel` | 12 |
| `CHANGELOG.md`, `README.md`, `README.ua.md`, `CLAUDE.md` (корінь) | документація | 12 |
| `test/helpers/spec_fixture.dart` | `SpecFixture` — документ + контекст розбору для тестів | 4 |
| `test/load/nesting_scanner_test.dart`, `test/load/spec_document_test.dart`, `test/model/spec_node_test.dart`, `test/parse/*_test.dart`, `test/resolve/*_test.dart` | нові тести | 1–12 |

## Інтерфейси між задачами

```dart
// load (Tasks 1-2)
final class SpecDocument { String file; Uri uri; Map<String, Object?> root;
  bool hasPositions; SourceSpan? spanOf(JsonPointer); (Object?,)? valueAt(JsonPointer); }
SpecDocument? SpecLoader.parse(String text, String file, {Uri? uri});   // uri defaults to file in cwd
final class NestingScanner { static const maxDepth = 1000; int? findTooDeep(String text, {int limit}); }

// model (Tasks 3, 5-7)
final class SpecLocation implements Comparable<SpecLocation> { Uri document; JsonPointer pointer; }
abstract class SpecNode { SpecLocation location; Map<String, Object?> extensions;
  Map<String, Object?> unknownKeys; JsonPointer get pointer; }
enum RefKind { schema, response, parameter, example, requestBody, header, securityScheme,
  pathItem, mediaType; String noun; String get withArticle; }
sealed class RefOr<T extends SpecNode>;  // Ref<T> (extends SpecNode: ref, kind, summary,
                                         // description) | Inline<T> (value)
sealed class Schema extends SpecNode;    // BooleanSchema(value) | SchemaObject(ref, types, ...)
final class OpenApiDocument extends SpecNode { OpenApiVersion? version; Info? info;
  Map<String, RefOr<PathItem>> paths; Components? components; ... }

// parse (Tasks 4-8)
final class SpecIndex { Map<SpecLocation, SpecNode> nodes; List<RefUse> refs; List<FeatureUse> features; }
final class ParseContext { ParseContext(DiagnosticBag, SpecDocument, SpecIndex);
  SpecLocation locate(JsonPointer); void report(DiagnosticCode, String, JsonPointer, {String? fix});
  void note(SpecFeature, JsonPointer); T register<T extends SpecNode>(T);
  ObjectReader? reader(Object? raw, JsonPointer, String what);
  RefOr<T>? refOr<T extends SpecNode>(Object? raw, JsonPointer, RefKind, T Function(ObjectReader)); }
final class ObjectReader { string, requiredString, boolean, number, count, choice, requiredChoice,
  strings, rawList, list, map, stringMap, object, requiredObject, value, accept, has, keys,
  extensions, unknownKeys({bool reportExtensions}) }
final class SchemaParser { Schema? parse(Object? raw, JsonPointer, {bool booleanIsClassic}); }
final class OperationParser { pathItem, parameter, requestBody, response, header, mediaType,
  example: RefOr<T>? Function(Object? raw, JsonPointer); server; securityRequirement; }
final class OpenApiParser { factory OpenApiParser(DiagnosticBag, SpecDocument, SpecIndex);
  OpenApiDocument parse(OpenApiVersion?); SpecNode? parseFragment(JsonPointer, RefKind); }
final class DialectChecker { void check(List<FeatureUse>, OpenApiVersion); }

// resolve (Tasks 9-12)
sealed class RefTarget { factory RefTarget.parse(String ref, Uri base); }  // ResolvableRef(location) | BrokenRef(code, reason, fix)
final class SpecDocuments { SpecDocuments(SpecLoader, SpecDocument root);
  SpecDocument? operator [](Uri); String displayPath(Uri); }
final class RefResolver { SpecModel resolve(OpenApiDocument, SpecIndex, SpecDocuments); }
final class SpecModel { OpenApiDocument document; SpecNode? nodeAt(SpecLocation);
  SpecLocation? targetOf(SpecLocation site); T? resolve<T extends SpecNode>(RefOr<T>);
  Schema? resolveSchema(Schema); }
final class SpecReader { SpecModel read(SpecDocument, OpenApiVersion); }
```

Тестів до початку — 51, після всіх задач — 132; `dart analyze packages` без зауважень, `dart pub publish --dry-run` без попереджень.

---

### Task 1: Завантаження: залишки рев'ю M1 і URI документа

**Files:**
- Create: `packages/typed_openapi/test/load/spec_document_test.dart`
- Modify: `packages/typed_openapi/lib/src/load/spec_document.dart`
- Modify: `packages/typed_openapi/lib/src/load/spec_loader.dart`
- Modify: `packages/typed_openapi/lib/src/config/config_loader.dart`
- Modify: `packages/typed_openapi/test/load/spec_loader_test.dart`
- Modify: `packages/typed_openapi/test/config/config_loader_test.dart`

**Interfaces:**
- Consumes: `SpecLoader`, `ConfigLoader`, `DiagnosticBag`, `DiagnosticCode`, `JsonPointer` (M1).
- Produces: `SpecDocument.uri` (`Uri`, абсолютний, нормалізований), `(Object?,)? SpecDocument.valueAt(JsonPointer)`, `SpecLoader.parse(String text, String file, {Uri? uri})`; `SpecLoader.load` передає `uri` файлу.

Поведінка, яку закріплюють тести:
- `SpecDocument` знає абсолютний `uri` свого файлу (база для відносних `$ref`) і віддає вузол за pointer: `valueAt` повертає record `(value,)`, щоб відрізнити явний `null` від відсутнього вузла; індекси списку — лише десяткові числа без провідних нулів.
- YAML-ключі `200` і `"200"` в одному об'єкті — warning `TOA002` з pointer і позицією другого ключа, перемагає останнє значення.
- `.json` з дублікатом і синтаксичною помилкою — `TOA002` warning і `TOA001` error з позицією від `jsonDecode`; без дубліката поведінка M1 не змінюється.
- `.json`, чий корінь не об'єкт, — `TOA003`, і вже без `TOA005`.
- Каталог замість файлу: специфікація — `TOA006` «is a directory», конфіг — `TOA902`.

- [ ] **Step 1: Написати тест, що не проходить**

Створи `packages/typed_openapi/test/load/spec_document_test.dart`:

```dart
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';

import '../helpers/temp_dir.dart';

void main() {
  final doc = SpecLoader(DiagnosticBag()).parse(
    'paths:\n  /a~b:\n    get: {tags: [x, y]}\n  /c: null\n',
    'api.yaml',
  )!;

  test('finds values by pointer, through objects and lists', () {
    final get = JsonPointer.root.child('paths').child('/a~b').child('get');
    expect(doc.valueAt(get.child('tags').child(1)), ('y',));
    expect(doc.valueAt(JsonPointer.root)?.$1, same(doc.root));
  });

  test('tells an explicit null from a missing node', () {
    final paths = JsonPointer.root.child('paths');
    expect(doc.valueAt(paths.child('/c')), (null,));
    expect(doc.valueAt(paths.child('/d')), isNull);
  });

  test('rejects list indexes that are not plain numbers', () {
    final tags = JsonPointer.parse('#/paths/~1a~0b/get/tags');
    expect(doc.valueAt(tags.child('01')), isNull);
    expect(doc.valueAt(tags.child('-')), isNull);
    expect(doc.valueAt(tags.child(2)), isNull);
  });

  test('parse defaults the URI to the file in the current directory', () {
    expect(doc.uri, p.toUri(p.absolute('api.yaml')));
  });

  test('load records the absolute, normalized file URI', () {
    final dir = TempDir();
    dir.write('specs/api.yaml', 'openapi: 3.1.0\n');
    final path = p.join(dir.path, 'specs', '..', 'specs', 'api.yaml');
    final loaded = SpecLoader(DiagnosticBag()).load(path)!;
    expect(loaded.uri, p.toUri(p.join(dir.path, 'specs', 'api.yaml')));
  });
}
```

- [ ] **Step 2: Додати тести в `spec_loader_test.dart`**

У `packages/typed_openapi/test/load/spec_loader_test.dart` після фрагмента:

```dart
    test('a root that is not an object is an error', () {
      final bag = DiagnosticBag();
      expect(SpecLoader(bag).parse('- a\n- b\n', 'a.yaml'), isNull);
      expect(bag.all.single.code, DiagnosticCode.rootNotObject);
    });
```

встав:

```dart
    test('YAML keys 1 and "1" are one JSON key: a warning, last wins', () {
      final bag = DiagnosticBag();
      final doc = SpecLoader(bag).parse(
        'openapi: 3.0.3\nresponses:\n  200: {description: a}\n'
            '  "200": {description: b}\n',
        'api.yaml',
      )!;
      expect(doc.root['responses'], {
        '200': {'description': 'b'},
      });
      final d = bag.all.single;
      expect(d.code, DiagnosticCode.duplicateKey);
      expect(d.severity, Severity.warning);
      expect(d.pointer?.value, '#/responses/200');
      expect(d.line, 4);
    });

    test('JSON with a duplicate key and a syntax error reports both', () {
      final bag = DiagnosticBag();
      final doc = SpecLoader(bag).parse(
        '{"openapi": "3.0.3", "a": 1, "a": 2,\n',
        'api.json',
      );
      expect(doc, isNull);
      expect(bag.all.map((d) => d.code), [
        DiagnosticCode.duplicateKey,
        DiagnosticCode.parseError,
      ]);
      expect(bag.all.last.severity, Severity.error);
      expect(bag.all.last.line, 2);
    });

    test('a JSON root that is not an object is reported before positions', () {
      final bag = DiagnosticBag();
      expect(SpecLoader(bag).parse('[{"a": 1, "a": 2}]', 'api.json'), isNull);
      expect(bag.all.map((d) => d.code), [
        DiagnosticCode.duplicateKey,
        DiagnosticCode.rootNotObject,
      ]);
    });
```

- [ ] **Step 3: Додати тести в `spec_loader_test.dart`**

У `packages/typed_openapi/test/load/spec_loader_test.dart` після фрагмента:

```dart
      File(path).writeAsBytesSync([0xFF, 0xFE, 0x41]);
      final bag = DiagnosticBag();
      expect(SpecLoader(bag).load(path), isNull);
      expect(bag.all.single.code, DiagnosticCode.inputUnreadable);
    });
```

встав:

```dart
    test('reports a directory given as the spec', () {
      final dir = TempDir();
      final bag = DiagnosticBag();
      expect(SpecLoader(bag).load(dir.path, displayPath: 'specs'), isNull);
      expect(bag.all.single.code, DiagnosticCode.inputUnreadable);
      expect(bag.all.single.message, contains('is a directory'));
    });
```

- [ ] **Step 4: Додати тести в `config_loader_test.dart`**

У `packages/typed_openapi/test/config/config_loader_test.dart` перед фрагментом:

```dart
  test('reports unknown keys as warnings and keeps going', () {
```

встав:

```dart
  test('reports a directory given as the config', () {
    final dir = TempDir();
    final bag = DiagnosticBag();
    expect(ConfigLoader(bag).load(dir.path), isNull);
    expect(bag.all.single.code, DiagnosticCode.configInvalid);
    expect(bag.all.single.message, contains('is a directory'));
  });
```

- [ ] **Step 5: Переконатися, що тести падають**

Run (з `packages/typed_openapi`): `dart test test/load test/config`
Expected: FAIL, перша помилка — `The method 'valueAt' isn't defined for the type 'SpecDocument'.`

- [ ] **Step 6: Переписати `spec_document.dart`**

Заміни весь вміст `packages/typed_openapi/lib/src/load/spec_document.dart` на:

```dart
import 'package:source_span/source_span.dart';

import '../diagnostics/json_pointer.dart';

/// A loaded spec: a plain JSON-like tree plus the source position of every
/// node, looked up by JSON pointer.
///
/// [root] contains only `Map<String, Object?>`, `List<Object?>`, `String`,
/// `num`, `bool` and `null`; keys are always strings.
final class SpecDocument {
  /// Creates a document; [spans] maps pointer values to source ranges.
  const SpecDocument({
    required this.file,
    required this.uri,
    required this.root,
    required Map<String, SourceSpan> spans,
  }) : _spans = spans;

  /// The file path as shown to the user.
  final String file;

  /// The absolute URI of the file; relative `$ref`s resolve against it.
  final Uri uri;

  /// The document contents.
  final Map<String, Object?> root;

  final Map<String, SourceSpan> _spans;

  /// Whether source positions were recorded.
  bool get hasPositions => _spans.isNotEmpty;

  /// The source range of the node at [pointer], if known.
  SourceSpan? spanOf(JsonPointer pointer) => _spans[pointer.value];

  /// The value at [pointer] as a one-element record, or null when nothing is
  /// there.
  ///
  /// The record tells an explicit `null` in the document, `(null,)`, from a
  /// missing node, `null`.
  (Object?,)? valueAt(JsonPointer pointer) {
    Object? current = root;
    for (final token in pointer.tokens) {
      switch (current) {
        case Map<String, Object?>() when current.containsKey(token):
          current = current[token];
        case List<Object?>():
          final index = _index.hasMatch(token) ? int.parse(token) : -1;
          if (index < 0 || index >= current.length) return null;
          current = current[index];
        default:
          return null;
      }
    }
    return (current,);
  }

  static final _index = RegExp(r'^(0|[1-9][0-9]{0,8})$');
}
```

- [ ] **Step 7: Переписати `spec_loader.dart`**

Заміни весь вміст `packages/typed_openapi/lib/src/load/spec_loader.dart` на:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/json_pointer.dart';
import 'spec_document.dart';

/// Reads spec files (JSON or YAML) into [SpecDocument]s.
///
/// Problems go to the [DiagnosticBag] given to the constructor instead of
/// being thrown.
final class SpecLoader {
  /// Creates a loader that reports to [_diagnostics].
  const SpecLoader(this._diagnostics);

  final DiagnosticBag _diagnostics;

  /// Reads the spec file at [path].
  ///
  /// [displayPath] is used in diagnostics instead of [path]. Returns null
  /// when the file cannot be used at all.
  SpecDocument? load(String path, {String? displayPath}) {
    final file = displayPath ?? path;
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) {
      _diagnostics.report(
        .inputNotFound,
        'Spec file $file does not exist.',
        file: file,
        fix: 'Check "input" in the config, or download a fresh snapshot.',
      );
      return null;
    }
    if (type == FileSystemEntityType.directory) {
      _diagnostics.report(
        .inputUnreadable,
        'Spec path $file is a directory, not a file.',
        file: file,
        fix: 'Point "input" at the spec file itself.',
      );
      return null;
    }
    final String text;
    try {
      text = File(path).readAsStringSync();
    } on FileSystemException catch (e) {
      _diagnostics.report(
        .inputUnreadable,
        'Cannot read $file: ${e.message}.',
        file: file,
        fix: 'Save the spec as UTF-8 and check the file permissions.',
      );
      return null;
    }
    return parse(text, file, uri: p.toUri(p.normalize(p.absolute(path))));
  }

  /// Parses spec [text]; [file] names it in diagnostics.
  ///
  /// [uri] is the absolute location of the text, the base for relative
  /// `$ref`s; it defaults to [file] resolved against the current directory.
  /// JSON and YAML go through the same YAML parser, so both get positions.
  /// A JSON file the YAML parser rejects (for example, because of a
  /// duplicate key) is read again with `jsonDecode`, without positions.
  SpecDocument? parse(String text, String file, {Uri? uri}) {
    final location = uri ?? p.toUri(p.normalize(p.absolute(file)));
    final YamlNode node;
    try {
      node = loadYamlNode(text, sourceUrl: Uri.file(file));
    } on YamlException catch (e) {
      return _parseJsonFallback(text, file, location, e);
    }
    if (node is! YamlMap) {
      _diagnostics.report(
        .rootNotObject,
        'The document root must be an object.',
        file: file,
        pointer: .root,
        span: node.span,
      );
      return null;
    }
    final spans = <String, SourceSpan>{};
    final root = _toPlain(node, .root, spans, file)! as Map<String, Object?>;
    return SpecDocument(file: file, uri: location, root: root, spans: spans);
  }

  SpecDocument? _parseJsonFallback(
    String text,
    String file,
    Uri uri,
    YamlException error,
  ) {
    final duplicate = error.message.startsWith('Duplicate mapping key');
    if (p.extension(file).toLowerCase() != '.json') {
      _diagnostics.report(
        duplicate ? .duplicateKey : .parseError,
        error.message,
        severity: .error,
        file: file,
        span: error.span,
      );
      return null;
    }
    final Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException catch (e) {
      if (!duplicate) {
        _diagnostics.report(
          .parseError,
          error.message,
          file: file,
          span: error.span,
        );
        return null;
      }
      _diagnostics.report(
        .duplicateKey,
        error.message,
        file: file,
        span: error.span,
        fix: 'Remove the duplicate key from the spec.',
      );
      final offset = e.offset;
      _diagnostics.report(
        .parseError,
        e.message,
        file: file,
        span: offset == null
            ? null
            : SourceFile.fromString(text, url: uri).span(offset, offset),
      );
      return null;
    }
    if (duplicate) {
      _diagnostics.report(
        .duplicateKey,
        '${error.message} The last value is used.',
        file: file,
        span: error.span,
        fix: 'Remove the duplicate key from the spec.',
      );
    }
    if (root is! Map<String, Object?>) {
      _diagnostics.report(
        .rootNotObject,
        'The document root must be an object.',
        file: file,
        pointer: .root,
      );
      return null;
    }
    _diagnostics.report(
      .positionsUnavailable,
      'Read $file without source positions; '
      'diagnostics for it show JSON pointers only.',
      file: file,
    );
    return SpecDocument(file: file, uri: uri, root: root, spans: const {});
  }

  Object? _toPlain(
    YamlNode node,
    JsonPointer pointer,
    Map<String, SourceSpan> spans,
    String file,
  ) {
    spans[pointer.value] = node.span;
    switch (node) {
      case YamlMap():
        final map = <String, Object?>{};
        final keys = <String, YamlNode>{};
        for (final MapEntry(:key, :value) in node.nodes.entries) {
          final keyNode = key as YamlNode;
          final name = '${keyNode.value}';
          final earlier = keys[name];
          if (earlier != null) {
            _diagnostics.report(
              .duplicateKey,
              'Keys ${earlier.span.text} and ${keyNode.span.text} are the '
              'same key "$name" in JSON; the last value is used.',
              file: file,
              pointer: pointer.child(name),
              span: keyNode.span,
              fix: 'Remove one of the keys.',
            );
          }
          keys[name] = keyNode;
          map[name] = _toPlain(value, pointer.child(name), spans, file);
        }
        return map;
      case YamlList():
        return <Object?>[
          for (var i = 0; i < node.nodes.length; i++)
            _toPlain(node.nodes[i], pointer.child(i), spans, file),
        ];
      default:
        return node.value;
    }
  }
}
```

- [ ] **Step 8: Змінити `config_loader.dart`**

У `packages/typed_openapi/lib/src/config/config_loader.dart` заміни:

```dart
    final source = File(path);
    if (!source.existsSync()) {
      _diagnostics.report(
        .configNotFound,
        'Config file $path does not exist.',
        file: path,
        fix: 'Create typed_openapi.yaml, or pass its path with --config.',
      );
      return null;
    }
    final String text;
    try {
      text = source.readAsStringSync();
```

на:

```dart
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) {
      _diagnostics.report(
        .configNotFound,
        'Config file $path does not exist.',
        file: path,
        fix: 'Create typed_openapi.yaml, or pass its path with --config.',
      );
      return null;
    }
    if (type == FileSystemEntityType.directory) {
      _diagnostics.report(
        .configInvalid,
        'Config path $path is a directory, not a file.',
        file: path,
        fix: 'Pass the path of typed_openapi.yaml itself with --config.',
      );
      return null;
    }
    final String text;
    try {
      text = File(path).readAsStringSync();
```

- [ ] **Step 9: Переконатися, що тести проходять**

Run (з `packages/typed_openapi`): `dart test test/load test/config`
Expected: `+34: All tests passed!`

- [ ] **Step 10: Формат, аналізатор, увесь набір тестів**

Run (з `packages/typed_openapi`): `dart format --output=none --set-exit-if-changed lib test bin && dart test`
Expected: `Formatted 28 files (0 changed)`, `+61: All tests passed!`

Run (з кореня): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 11: Commit**

```bash
git add packages/typed_openapi/lib/src/config/config_loader.dart packages/typed_openapi/lib/src/load/spec_document.dart packages/typed_openapi/lib/src/load/spec_loader.dart packages/typed_openapi/test/config/config_loader_test.dart packages/typed_openapi/test/load/spec_document_test.dart packages/typed_openapi/test/load/spec_loader_test.dart
git commit -m 'fix(typed_openapi): loader edge cases left from the M1 review' -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
```

---

### Task 2: Захист від надто глибокої вкладеності (TOA007)

**Files:**
- Create: `packages/typed_openapi/lib/src/load/nesting_scanner.dart`
- Create: `packages/typed_openapi/test/load/nesting_scanner_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`
- Modify: `packages/typed_openapi/lib/src/load/spec_loader.dart`
- Modify: `packages/typed_openapi/lib/src/config/config_loader.dart`
- Modify: `packages/typed_openapi/test/load/spec_loader_test.dart`
- Modify: `packages/typed_openapi/test/config/config_loader_test.dart`

**Interfaces:**
- Consumes: `SpecLoader.parse`, `ConfigLoader.load` (Task 1).
- Produces: `final class NestingScanner { const NestingScanner(); static const maxDepth = 1000; int? findTooDeep(String text, {int limit = maxDepth}); }`; `DiagnosticCode.nestingTooDeep` (`TOA007`).

Поведінка, яку закріплюють тести:
- `NestingScanner.findTooDeep` повертає зсув першого символу, на якому оцінка глибини перевищує ліміт, або `null`. Дужки в рядках (`"…"`, `'…'` з `''`) і коментарях не рахуються; апостроф усередині слова (`it's`) не відкриває рядок.
- Блочний YAML: відступ рядка плюс маркери `- ` на його початку; flow-колекція (`[`/`{`) починає рахунок від відступу свого рядка, тож pretty-printed JSON рахується точно.
- 20 000 рівнів сканер проходить без рекурсії; `SpecLoader.parse` і `ConfigLoader.load` повертають `null` з діагностикою, а не падають.

- [ ] **Step 1: Написати тест, що не проходить**

Створи `packages/typed_openapi/test/load/nesting_scanner_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/load/nesting_scanner.dart';

void main() {
  const scanner = NestingScanner();

  test('accepts JSON as deep as the limit', () {
    final text = '${'[' * 5}${']' * 5}';
    expect(scanner.findTooDeep(text, limit: 5), isNull);
  });

  test('finds the bracket that goes one level too deep', () {
    final text = '{"a": ${'[' * 6}${']' * 6}}';
    expect(scanner.findTooDeep(text, limit: 5), 10);
  });

  test('ignores brackets in strings and comments', () {
    const text = '''
a: "[[[[[["
b: '[[[[[[ it''s'
# [[[[[[
c: [1, 2]
''';
    expect(scanner.findTooDeep(text, limit: 2), isNull);
  });

  test('counts compact YAML sequences and indentation', () {
    expect(scanner.findTooDeep('- - - x\n', limit: 6), isNull);
    expect(scanner.findTooDeep('- - - - x\n', limit: 6), 6);
    expect(scanner.findTooDeep('a:\n        b: 1\n', limit: 6), 9);
  });

  test('a flow collection starts from the indentation of its line', () {
    expect(scanner.findTooDeep('a:\n    b: [[1]]\n', limit: 6), isNull);
    expect(scanner.findTooDeep('a:\n     b: [[1]]\n', limit: 6), 12);
  });

  test('scans 20 000 levels without recursion', () {
    final text = '${'[' * 20000}${']' * 20000}';
    expect(scanner.findTooDeep(text), NestingScanner.maxDepth);
  });
}
```

- [ ] **Step 2: Додати тести в `spec_loader_test.dart`**

У `packages/typed_openapi/test/load/spec_loader_test.dart` заміни:

```dart
import 'package:typed_openapi/src/load/spec_loader.dart';
```

на:

```dart
import 'package:typed_openapi/src/load/nesting_scanner.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
```

- [ ] **Step 3: Додати тести в `spec_loader_test.dart`**

У `packages/typed_openapi/test/load/spec_loader_test.dart` після фрагмента:

```dart
    test('a root that is not an object is an error', () {
      final bag = DiagnosticBag();
      expect(SpecLoader(bag).parse('- a\n- b\n', 'a.yaml'), isNull);
      expect(bag.all.single.code, DiagnosticCode.rootNotObject);
    });
```

встав:

```dart
    test('nesting deeper than the limit is an error, not a crash', () {
      final bag = DiagnosticBag();
      final text = '{"a": ${'[' * 20000}${']' * 20000}}';
      expect(SpecLoader(bag).parse(text, 'api.json'), isNull);
      final d = bag.all.single;
      expect(d.code, DiagnosticCode.nestingTooDeep);
      expect(d.column, 7 + NestingScanner.maxDepth - 1);
    });

    test('YAML nested deeper than the limit is an error too', () {
      final bag = DiagnosticBag();
      expect(SpecLoader(bag).parse('- ' * 20000, 'api.yaml'), isNull);
      expect(bag.all.single.code, DiagnosticCode.nestingTooDeep);
    });
```

- [ ] **Step 4: Додати тести в `config_loader_test.dart`**

У `packages/typed_openapi/test/config/config_loader_test.dart` перед фрагментом:

```dart
  test('reports unknown keys as warnings and keeps going', () {
```

встав:

```dart
  test('reports a config nested too deeply instead of crashing', () {
    final path = TempDir().write(
      'typed_openapi.yaml',
      'clients: ${'[' * 20000}${']' * 20000}\n',
    );
    final bag = DiagnosticBag();
    expect(ConfigLoader(bag).load(path), isNull);
    expect(bag.all.single.code, DiagnosticCode.configInvalid);
    expect(bag.all.single.message, contains('nests deeper'));
  });
```

- [ ] **Step 5: Переконатися, що тести падають**

Run (з `packages/typed_openapi`): `dart test test/load test/config`
Expected: FAIL, перша помилка — `cannot read 'lib/src/load/nesting_scanner.dart': No such file or directory`

- [ ] **Step 6: Додати коди в каталог**

У `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart` після фрагмента:

```dart
  inputUnreadable('TOA006', 'input-unreadable', .error),
```

встав:

```dart
  /// The document nests deeper than the parser can follow.
  nestingTooDeep('TOA007', 'nesting-too-deep', .error),
```

- [ ] **Step 7: Створити `nesting_scanner.dart`**

Створи `packages/typed_openapi/lib/src/load/nesting_scanner.dart`:

```dart
/// Finds text that nests too deeply to parse, without parsing it.
///
/// The YAML parser recurses once per nesting level and overflows the stack
/// at a few thousand levels. A `StackOverflowError` cannot be handled like
/// bad input, so loaders run this scan first and report such text as a
/// diagnostic instead.
///
/// The scan over-estimates and never under-estimates: inside `[...]` and
/// `{...}` it counts brackets outside quoted strings and comments; outside
/// them it counts the indentation of a line plus its leading `- ` markers.
final class NestingScanner {
  /// Creates a scanner.
  const NestingScanner();

  /// The deepest nesting a spec or config file may have.
  static const maxDepth = 1000;

  /// The offset in [text] where the nesting first exceeds [limit], or null
  /// when it never does.
  int? findTooDeep(String text, {int limit = maxDepth}) {
    var flow = 0;
    var block = 0;
    var flowBase = 0;
    var atLineStart = true;
    String? quote;
    var inComment = false;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == '\n') {
        inComment = false;
        if (quote == null && flow == 0) {
          atLineStart = true;
          block = 0;
        }
        continue;
      }
      if (inComment) continue;
      if (quote == '"') {
        if (char == r'\') {
          i++;
        } else if (char == '"') {
          quote = null;
        }
        continue;
      }
      if (quote == "'") {
        if (char == "'") {
          if (i + 1 < text.length && text[i + 1] == "'") {
            i++;
          } else {
            quote = null;
          }
        }
        continue;
      }
      if (atLineStart) {
        if (char == ' ' || char == '\t') {
          block++;
          if (block > limit) return i;
          continue;
        }
        if (char == '-' && _isBlank(text, i + 1)) {
          block += 2;
          if (block > limit) return i;
          i++;
          continue;
        }
        atLineStart = false;
      }
      switch (char) {
        case '#' when i == 0 || _isBlank(text, i - 1):
          inComment = true;
        case '"' || "'" when _startsToken(text, i):
          quote = char;
        case '[' || '{':
          if (flow == 0) flowBase = block;
          flow++;
          if (flowBase + flow > limit) return i;
        case ']' || '}':
          if (flow > 0) flow--;
      }
    }
    return null;
  }

  static bool _isBlank(String text, int i) =>
      i >= text.length || const {' ', '\t', '\n', '\r'}.contains(text[i]);

  static bool _startsToken(String text, int i) =>
      i == 0 ||
      const {' ', '\t', '\n', '\r', '[', '{', ',', ':', '-', '?'}.contains(
        text[i - 1],
      );
}
```

- [ ] **Step 8: Змінити `spec_loader.dart`**

У `packages/typed_openapi/lib/src/load/spec_loader.dart` заміни:

```dart
import 'spec_document.dart';
```

на:

```dart
import 'nesting_scanner.dart';
import 'spec_document.dart';
```

- [ ] **Step 9: Змінити `spec_loader.dart`**

У `packages/typed_openapi/lib/src/load/spec_loader.dart` перед фрагментом:

```dart
    final YamlNode node;
```

встав:

```dart
    final tooDeep = const NestingScanner().findTooDeep(text);
    if (tooDeep != null) {
      _diagnostics.report(
        .nestingTooDeep,
        'The document nests deeper than ${NestingScanner.maxDepth} levels.',
        file: file,
        span: SourceFile.fromString(
          text,
          url: location,
        ).span(tooDeep, tooDeep + 1),
      );
      return null;
    }
```

- [ ] **Step 10: Змінити `config_loader.dart`**

У `packages/typed_openapi/lib/src/config/config_loader.dart` заміни:

```dart
import '../diagnostics/json_pointer.dart';
```

на:

```dart
import '../diagnostics/json_pointer.dart';
import '../load/nesting_scanner.dart';
```

- [ ] **Step 11: Змінити `config_loader.dart`**

У `packages/typed_openapi/lib/src/config/config_loader.dart` перед фрагментом:

```dart
    final YamlNode root;
```

встав:

```dart
    final tooDeep = const NestingScanner().findTooDeep(text);
    if (tooDeep != null) {
      _diagnostics.report(
        .configInvalid,
        'The config nests deeper than ${NestingScanner.maxDepth} levels.',
        file: path,
        span: SourceFile.fromString(text).span(tooDeep, tooDeep + 1),
      );
      return null;
    }
```

- [ ] **Step 12: Переконатися, що тести проходять**

Run (з `packages/typed_openapi`): `dart test test/load test/config`
Expected: `+43: All tests passed!`

- [ ] **Step 13: Формат, аналізатор, увесь набір тестів**

Run (з `packages/typed_openapi`): `dart format --output=none --set-exit-if-changed lib test bin && dart test`
Expected: `Formatted 30 files (0 changed)`, `+70: All tests passed!`

Run (з кореня): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 14: Commit**

```bash
git add packages/typed_openapi/lib/src/config/config_loader.dart packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart packages/typed_openapi/lib/src/load/nesting_scanner.dart packages/typed_openapi/lib/src/load/spec_loader.dart packages/typed_openapi/test/config/config_loader_test.dart packages/typed_openapi/test/load/nesting_scanner_test.dart packages/typed_openapi/test/load/spec_loader_test.dart
git commit -m 'fix(typed_openapi): report deep nesting instead of overflowing the stack' -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
```

---

### Task 3: Ядро моделі: `SpecLocation`, `SpecNode`, `RefOr`

**Files:**
- Create: `packages/typed_openapi/lib/src/model/spec_node.dart`
- Create: `packages/typed_openapi/test/model/spec_node_test.dart`

**Interfaces:**
- Consumes: `JsonPointer` (M1).
- Produces: `SpecLocation(Uri document, JsonPointer pointer)` з `==`, `hashCode`, `compareTo`, `toString` (`file:///…#/…`); `abstract class SpecNode({required SpecLocation location, Map<String, Object?> extensions, Map<String, Object?> unknownKeys})` з `JsonPointer get pointer`; `enum RefKind` (`noun`, `withArticle`); `sealed class RefOr<T extends SpecNode>`, `final class Ref<T> extends SpecNode implements RefOr<T>` (`ref`, `kind`, `summary`, `description`), `final class Inline<T> implements RefOr<T>` (`value`).

Поведінка, яку закріплюють тести:
- `SpecLocation` рівні, коли збігаються і файл, і pointer; однаковий pointer у двох файлах — різні вузли (space_gen #358). Сортування — за файлом, потім за pointer.
- `RefKind.withArticle` дає `an example`, `a request body` — для повідомлень резолвера.

- [ ] **Step 1: Написати тест, що не проходить**

Створи `packages/typed_openapi/test/model/spec_node_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/model/spec_node.dart';

void main() {
  final a = Uri.parse('file:///specs/a.yaml');
  final b = Uri.parse('file:///specs/b.yaml');
  final user = JsonPointer.parse('#/components/schemas/User');

  test('a location is equal to another with the same file and pointer', () {
    expect(SpecLocation(a, user), SpecLocation(a, user));
    expect(SpecLocation(a, user).hashCode, SpecLocation(a, user).hashCode);
  });

  test('the same pointer in two files is two locations', () {
    expect(SpecLocation(a, user), isNot(SpecLocation(b, user)));
  });

  test('locations sort by file, then by pointer', () {
    final sorted = [
      SpecLocation(b, JsonPointer.root),
      SpecLocation(a, user),
      SpecLocation(a, JsonPointer.root),
    ]..sort();
    expect(sorted.map((l) => '$l'), [
      'file:///specs/a.yaml#',
      'file:///specs/a.yaml#/components/schemas/User',
      'file:///specs/b.yaml#',
    ]);
  });

  test('ref kinds name themselves with an article', () {
    expect(RefKind.example.withArticle, 'an example');
    expect(RefKind.requestBody.withArticle, 'a request body');
  });
}
```

- [ ] **Step 2: Переконатися, що тести падають**

Run (з `packages/typed_openapi`): `dart test test/model`
Expected: FAIL, перша помилка — `cannot read 'lib/src/model/spec_node.dart': No such file or directory`

- [ ] **Step 3: Створити `spec_node.dart`**

Створи `packages/typed_openapi/lib/src/model/spec_node.dart`:

```dart
import '../diagnostics/json_pointer.dart';

/// Where a node of a spec is: the absolute URI of its document and its JSON
/// pointer in that document.
///
/// This pair is the identity of a node. Two documents may both have
/// `#/components/schemas/User`; their locations still differ.
final class SpecLocation implements Comparable<SpecLocation> {
  /// Creates a location.
  const SpecLocation(this.document, this.pointer);

  /// The absolute URI of the document, without a fragment.
  final Uri document;

  /// The pointer to the node inside [document].
  final JsonPointer pointer;

  @override
  bool operator ==(Object other) =>
      other is SpecLocation &&
      other.document == document &&
      other.pointer == pointer;

  @override
  int get hashCode => Object.hash(document, pointer);

  @override
  int compareTo(SpecLocation other) {
    final byDocument = '$document'.compareTo('${other.document}');
    if (byDocument != 0) return byDocument;
    return pointer.value.compareTo(other.pointer.value);
  }

  @override
  String toString() => '$document${pointer.value}';
}

/// What every node of the spec model carries.
abstract class SpecNode {
  /// Creates a node.
  const SpecNode({
    required this.location,
    this.extensions = const {},
    this.unknownKeys = const {},
  });

  /// Where the node is.
  final SpecLocation location;

  /// The `x-` keys of the node and their raw values, in document order.
  final Map<String, Object?> extensions;

  /// Keys no OpenAPI version defines for this node, with their raw values.
  ///
  /// Each of them was reported as `unknown-key` when the node was read.
  final Map<String, Object?> unknownKeys;

  /// The pointer part of [location].
  JsonPointer get pointer => location.pointer;
}

/// The kinds of node a `$ref` may point to.
///
/// Schemas are not wrapped in [RefOr]: in a Schema Object `$ref` is a
/// keyword, see `SchemaObject.ref`.
enum RefKind {
  /// A Schema Object.
  schema('schema'),

  /// A Response Object.
  response('response'),

  /// A Parameter Object.
  parameter('parameter'),

  /// An Example Object.
  example('example'),

  /// A Request Body Object.
  requestBody('request body'),

  /// A Header Object.
  header('header'),

  /// A Security Scheme Object.
  securityScheme('security scheme'),

  /// A Path Item Object.
  pathItem('path item'),

  /// A Media Type Object (OpenAPI 3.2).
  mediaType('media type');

  const RefKind(this.noun);

  /// How messages name a node of this kind, such as `request body`.
  final String noun;

  /// [noun] with its article, such as `an example`.
  String get withArticle => '${noun.startsWith('e') ? 'an' : 'a'} $noun';
}

/// A node of type [T] written inline, or a Reference Object to one.
sealed class RefOr<T extends SpecNode> {}

/// A Reference Object: `{$ref: ...}`, with an optional summary and
/// description.
final class Ref<T extends SpecNode> extends SpecNode implements RefOr<T> {
  /// Creates a reference.
  const Ref({
    required super.location,
    required this.ref,
    required this.kind,
    this.summary,
    this.description,
    super.unknownKeys,
  });

  /// The `$ref` value as written.
  final String ref;

  /// The kind of node the reference must point to.
  final RefKind kind;

  /// The `summary` that overrides the target's one.
  final String? summary;

  /// The `description` that overrides the target's one.
  final String? description;
}

/// A node written in place.
final class Inline<T extends SpecNode> implements RefOr<T> {
  /// Wraps [value].
  const Inline(this.value);

  /// The node.
  final T value;
}
```

- [ ] **Step 4: Переконатися, що тести проходять**

Run (з `packages/typed_openapi`): `dart test test/model`
Expected: `+4: All tests passed!`

- [ ] **Step 5: Формат, аналізатор, увесь набір тестів**

Run (з `packages/typed_openapi`): `dart format --output=none --set-exit-if-changed lib test bin && dart test`
Expected: `Formatted 32 files (0 changed)`, `+74: All tests passed!`

Run (з кореня): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add packages/typed_openapi/lib/src/model/spec_node.dart packages/typed_openapi/test/model/spec_node_test.dart
git commit -m 'feat(typed_openapi): spec node locations and references' -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
```

---

### Task 4: `ObjectReader`, `ParseContext` і `SpecFeature` (TOA110–TOA112)

**Files:**
- Create: `packages/typed_openapi/lib/src/parse/spec_feature.dart`
- Create: `packages/typed_openapi/lib/src/parse/parse_context.dart`
- Create: `packages/typed_openapi/lib/src/parse/object_reader.dart`
- Create: `packages/typed_openapi/test/helpers/spec_fixture.dart`
- Create: `packages/typed_openapi/test/parse/object_reader_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`

**Interfaces:**
- Consumes: `SpecDocument` (Task 1), `SpecLocation`, `SpecNode`, `RefKind`, `Ref`, `Inline`, `RefOr` (Task 3), `OpenApiVersion` (M1).
- Produces: `enum SpecFeature` (`label`, `since`, `until`); `RefUse(site, ref, kind)`, `FeatureUse(feature, file, pointer, span)`, `SpecIndex` (`nodes`, `refs`, `features`); `ParseContext` (`locate`, `report`, `note`, `register`, `reader`, `refOr`); `ObjectReader` (геттери з блоку «Інтерфейси між задачами», `static String describe(Object?)`); коди `unknownKey` (TOA110), `invalidValue` (TOA111), `missingRequiredField` (TOA112); тестовий `SpecFixture(String text, {String file})` з `diagnostics`, `document`, `index`, `context`, `codes`, `pointers`.

Поведінка, яку закріплюють тести:
- Геттери `ObjectReader` повертають значення потрібного типу або `null`; неправильний тип — `TOA111` warning у pointer поля з повідомленням `"name" must be a string, not the number 5; it is ignored.`
- `count` приймає `3.0` як `3`, відкидає від'ємні й дробові; `choice` перелічує допустимі значення в повідомленні.
- Елементи списків і словників неправильного типу повідомляються окремо і пропускаються; `rawList` зберігає `null`.
- `map(..., skipExtensions: true)` не робить `x-`-ключі записами (Paths, Responses).
- `requiredString`/`requiredChoice`/`requiredObject` повідомляють `TOA112` у pointer об'єкта.
- `extensions` — усі `x-`-ключі; `unknownKeys()` повідомляє `TOA110` про кожен непрочитаний ключ і повертає їх. Тому `unknownKeys()` викликається останнім аргументом конструктора вузла: Dart обчислює аргументи зліва направо.

- [ ] **Step 1: Створити тестовий хелпер `spec_fixture.dart`**

Створи `packages/typed_openapi/test/helpers/spec_fixture.dart`:

```dart
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/load/spec_document.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/parse/parse_context.dart';

/// A spec parsed from text, with a parse context and the diagnostics so far.
final class SpecFixture {
  /// Parses [text] as the file [file]; the text must load without errors.
  SpecFixture(String text, {String file = 'api.yaml'})
    : this._(DiagnosticBag(), text, file);

  SpecFixture._(this.diagnostics, String text, String file)
    : document = SpecLoader(diagnostics).parse(text, file)!;

  /// Where every diagnostic goes.
  final DiagnosticBag diagnostics;

  /// The loaded document.
  final SpecDocument document;

  /// What the parsers record.
  final SpecIndex index = SpecIndex();

  /// A context for parsing [document].
  late final ParseContext context = ParseContext(
    diagnostics,
    document,
    index,
  );

  /// The codes reported so far, in report order.
  List<DiagnosticCode> get codes => [
    for (final d in diagnostics.all) d.code,
  ];

  /// The pointers reported so far, in report order.
  List<String?> get pointers => [
    for (final d in diagnostics.all) d.pointer?.value,
  ];
}
```

- [ ] **Step 2: Написати тест, що не проходить**

Створи `packages/typed_openapi/test/parse/object_reader_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/parse/object_reader.dart';

import '../helpers/spec_fixture.dart';

void main() {
  (ObjectReader, SpecFixture) read(String yaml) {
    final fixture = SpecFixture(yaml);
    final reader = ObjectReader(
      fixture.context,
      fixture.document.root,
      JsonPointer.root,
    );
    return (reader, fixture);
  }

  test('reads typed fields', () {
    final (r, fixture) = read(
      'name: id\nrequired: true\nmin: 1.5\nsize: 3.0\nstyle: form\n',
    );
    expect(r.string('name'), 'id');
    expect(r.boolean('required'), isTrue);
    expect(r.number('min'), 1.5);
    expect(r.count('size'), 3);
    expect(r.choice('style', {'form': 1, 'simple': 2}), 1);
    expect(r.string('absent'), isNull);
    expect(fixture.diagnostics.all, isEmpty);
  });

  test('a value of the wrong type is reported and read as missing', () {
    final (r, fixture) = read('name: 5\nrequired: "yes"\nsize: -1\n');
    expect(r.string('name'), isNull);
    expect(r.boolean('required'), isNull);
    expect(r.count('size'), isNull);
    expect(fixture.codes, [
      DiagnosticCode.invalidValue,
      DiagnosticCode.invalidValue,
      DiagnosticCode.invalidValue,
    ]);
    expect(fixture.pointers, ['#/name', '#/required', '#/size']);
    expect(
      fixture.diagnostics.all.first.message,
      '"name" must be a string, not the number 5; it is ignored.',
    );
    expect(fixture.diagnostics.all.first.severity, Severity.warning);
  });

  test('a value outside a choice is reported', () {
    final (r, fixture) = read('in: body\n');
    expect(r.choice('in', {'query': 1, 'path': 2}), isNull);
    expect(
      fixture.diagnostics.all.single.message,
      '"in" must be one of query, path, not "body".',
    );
  });

  test('reads lists and maps; bad items are reported and skipped', () {
    final (r, fixture) = read(
      'tags: [a, 1, b]\nscopes: {read: Read, write: 2}\nenum: [a, null]\n',
    );
    expect(r.strings('tags'), ['a', 'b']);
    expect(r.stringMap('scopes'), {'read': 'Read'});
    expect(r.rawList('enum'), ['a', null]);
    expect(fixture.pointers, ['#/tags/1', '#/scopes/write']);
  });

  test('map can skip x- keys that are not entries', () {
    final (r, _) = read('paths: {/a: 1, x-internal: 2}\n');
    expect(r.map('paths', (raw, _) => raw, skipExtensions: true), {'/a': 1});
  });

  test('a missing required field is reported at the object', () {
    final (r, fixture) = read('summary: s\n');
    expect(r.requiredString('name'), isNull);
    expect(fixture.codes, [DiagnosticCode.missingRequiredField]);
    expect(fixture.pointers, ['#']);
  });

  test('keeps x- keys and reports unknown keys after reading', () {
    final (r, fixture) = read(
      'name: a\nx-order: 1\nnmae: typo\nexternalDocs: {}\n',
    );
    r
      ..string('name')
      ..accept(['externalDocs']);
    expect(r.extensions, {'x-order': 1});
    expect(r.unknownKeys(), {'nmae': 'typo'});
    expect(fixture.codes, [DiagnosticCode.unknownKey]);
    expect(fixture.pointers, ['#/nmae']);
    expect(fixture.diagnostics.all.single.line, 3);
  });

  test('value tells an explicit null from a missing key', () {
    final (r, _) = read('default: null\n');
    expect(r.value('default'), (null,));
    expect(r.value('example'), isNull);
  });
}
```

- [ ] **Step 3: Переконатися, що тести падають**

Run (з `packages/typed_openapi`): `dart test test/parse`
Expected: FAIL, перша помилка — `cannot read 'lib/src/parse/object_reader.dart': No such file or directory`

- [ ] **Step 4: Додати коди в каталог**

У `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart` перед фрагментом:

```dart
  /// The configuration file does not exist.
```

встав:

```dart
  /// An object has a key that no OpenAPI version defines; it is ignored.
  unknownKey('TOA110', 'unknown-key', .warning),

  /// A field has the wrong JSON type or a value the spec does not allow; it
  /// is ignored.
  invalidValue('TOA111', 'invalid-value', .warning),

  /// A field the spec requires is missing.
  missingRequiredField('TOA112', 'missing-required-field', .warning),
```

- [ ] **Step 5: Створити `spec_feature.dart`**

Створи `packages/typed_openapi/lib/src/parse/spec_feature.dart`:

```dart
import '../load/openapi_version.dart';

/// A construct that only some OpenAPI versions define.
///
/// The parser reads every construct whatever version a document declares and
/// notes the version-specific ones; `DialectChecker` then reports those the
/// declared version does not have.
enum SpecFeature {
  /// `type` written as a list.
  typeList('"type" as a list', since: .v31),

  /// `type: "null"`.
  nullType('type "null"', since: .v31),

  /// `const`.
  constKeyword('"const"', since: .v31),

  /// `prefixItems`.
  prefixItems('"prefixItems"', since: .v31),

  /// `examples` (a list) in a schema.
  schemaExamples('"examples" in a schema', since: .v31),

  /// `exclusiveMinimum` or `exclusiveMaximum` written as a number.
  numericExclusiveBound(
    'a numeric "exclusiveMinimum" or "exclusiveMaximum"',
    since: .v31,
  ),

  /// `true` or `false` as a schema, other than in `additionalProperties`.
  booleanSchema('a boolean schema', since: .v31),

  /// `contentMediaType`, `contentEncoding` or `contentSchema`.
  contentKeywords(
    '"contentMediaType", "contentEncoding" or "contentSchema"',
    since: .v31,
  ),

  /// A JSON Schema 2020-12 keyword the model keeps raw, such as `$defs`.
  jsonSchemaKeyword(
    r'a JSON Schema keyword such as "$defs" or "if"',
    since: .v31,
  ),

  /// `webhooks`.
  webhooks('"webhooks"', since: .v31),

  /// `jsonSchemaDialect`.
  jsonSchemaDialect('"jsonSchemaDialect"', since: .v31),

  /// `summary` in the Info Object.
  infoSummary('"summary" in "info"', since: .v31),

  /// `pathItems` in the Components Object.
  componentPathItems('"components/pathItems"', since: .v31),

  /// The `mutualTLS` security scheme type.
  mutualTls('the "mutualTLS" security scheme', since: .v31),

  /// `itemSchema` in a media type.
  itemSchema('"itemSchema"', since: .v32),

  /// `prefixEncoding` or `itemEncoding` in a media type.
  sequentialEncoding('"prefixEncoding" or "itemEncoding"', since: .v32),

  /// The `query` operation of a path item.
  queryOperation('the "query" operation', since: .v32),

  /// `additionalOperations` in a path item.
  additionalOperations('"additionalOperations"', since: .v32),

  /// A parameter with `in: querystring`.
  querystringParameter('"in: querystring"', since: .v32),

  /// `style: cookie`.
  cookieStyle('"style: cookie"', since: .v32),

  /// `summary`, `parent` or `kind` in a tag.
  tagHierarchy('"summary", "parent" or "kind" in a tag', since: .v32),

  /// `defaultMapping` in a discriminator.
  defaultMapping('"defaultMapping"', since: .v32),

  /// `mediaTypes` in the Components Object.
  componentMediaTypes('"components/mediaTypes"', since: .v32),

  /// A `$ref` in place of a Media Type Object.
  mediaTypeRef(r'a "$ref" to a media type', since: .v32),

  /// `$self` at the document root.
  self(r'"$self"', since: .v32),

  /// `summary` in a response.
  responseSummary('"summary" in a response', since: .v32),

  /// `name` in a server.
  serverName('"name" in a server', since: .v32),

  /// `dataValue` or `serializedValue` in an example.
  exampleValues('"dataValue" or "serializedValue"', since: .v32),

  /// `deprecated` or `oauth2MetadataUrl` in a security scheme.
  securitySchemeExtras(
    '"deprecated" or "oauth2MetadataUrl" in a security scheme',
    since: .v32,
  ),

  /// The `deviceAuthorization` OAuth flow.
  deviceAuthorization('the "deviceAuthorization" OAuth flow', since: .v32),

  /// `nullable`, which JSON Schema 2020-12 replaced with `type: "null"`.
  nullable('"nullable"', until: .v31);

  const SpecFeature(this.label, {this.since, this.until});

  /// How diagnostics name the construct.
  final String label;

  /// The first version that has the construct, or null for all.
  final OpenApiVersion? since;

  /// The first version that no longer has the construct, or null for none.
  final OpenApiVersion? until;
}
```

- [ ] **Step 6: Створити `parse_context.dart`**

Створи `packages/typed_openapi/lib/src/parse/parse_context.dart`:

```dart
import 'package:source_span/source_span.dart';

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/json_pointer.dart';
import '../load/spec_document.dart';
import '../model/spec_node.dart';
import 'object_reader.dart';
import 'spec_feature.dart';

/// A `$ref` found while parsing.
final class RefUse {
  /// Creates a use of [ref] by the node at [site].
  const RefUse(this.site, this.ref, this.kind);

  /// The node that holds the `$ref`: a `Ref` or a `SchemaObject`.
  final SpecLocation site;

  /// The `$ref` value as written.
  final String ref;

  /// The kind of node the reference must point to.
  final RefKind kind;
}

/// A version-specific construct found while parsing.
final class FeatureUse {
  /// Creates a use of [feature].
  const FeatureUse(this.feature, this.file, this.pointer, this.span);

  /// The construct.
  final SpecFeature feature;

  /// The file it is in, as shown to the user.
  final String file;

  /// Where in [file] it is.
  final JsonPointer pointer;

  /// The source range, when positions are known.
  final SourceSpan? span;
}

/// What the parsers of one run collect: every node by location, every
/// `$ref` and every version-specific construct, in the order found.
final class SpecIndex {
  /// Every parsed node, references included, by location.
  final Map<SpecLocation, SpecNode> nodes = {};

  /// Every `$ref` found.
  final List<RefUse> refs = [];

  /// Every version-specific construct found.
  final List<FeatureUse> features = [];
}

/// The document being parsed, with the helpers every parser needs.
final class ParseContext {
  /// Creates a context for [document] that reports to [diagnostics] and
  /// records into [index].
  ParseContext(this.diagnostics, this.document, this.index);

  /// Where problems go.
  final DiagnosticBag diagnostics;

  /// The document being parsed.
  final SpecDocument document;

  /// Where nodes, refs and features are recorded.
  final SpecIndex index;

  /// The location of the node at [pointer] in [document].
  SpecLocation locate(JsonPointer pointer) =>
      SpecLocation(document.uri, pointer);

  /// Reports [code] at [pointer] of [document].
  void report(
    DiagnosticCode code,
    String message,
    JsonPointer pointer, {
    String? fix,
  }) {
    diagnostics.report(
      code,
      message,
      file: document.file,
      pointer: pointer,
      span: document.spanOf(pointer),
      fix: fix,
    );
  }

  /// Records that [feature] is used at [pointer].
  void note(SpecFeature feature, JsonPointer pointer) {
    index.features.add(
      FeatureUse(feature, document.file, pointer, document.spanOf(pointer)),
    );
  }

  /// Records [node] by its location and returns it.
  T register<T extends SpecNode>(T node) {
    index.nodes[node.location] = node;
    return node;
  }

  /// A reader for [raw] at [pointer], or null after reporting that [raw] is
  /// not an object; [what] names the node in the report.
  ObjectReader? reader(Object? raw, JsonPointer pointer, String what) {
    if (raw is Map<String, Object?>) return ObjectReader(this, raw, pointer);
    report(
      .invalidValue,
      '$what must be an object, not ${ObjectReader.describe(raw)}.',
      pointer,
    );
    return null;
  }

  /// Reads [raw] at [pointer] as a Reference Object to a [kind] node, or
  /// with [parse] as an inline node; null when [raw] is not an object.
  RefOr<T>? refOr<T extends SpecNode>(
    Object? raw,
    JsonPointer pointer,
    RefKind kind,
    T Function(ObjectReader reader) parse,
  ) {
    final reader = this.reader(raw, pointer, 'This ${kind.noun}');
    if (reader == null) return null;
    if (!reader.has(r'$ref')) return Inline(parse(reader));
    final ref = reader.string(r'$ref');
    final node = Ref<T>(
      location: reader.location,
      ref: ref ?? '',
      kind: kind,
      summary: reader.string('summary'),
      description: reader.string('description'),
      unknownKeys: reader.unknownKeys(reportExtensions: true),
    );
    if (ref != null) index.refs.add(RefUse(node.location, ref, kind));
    if (kind == .mediaType) note(.mediaTypeRef, pointer);
    register(node);
    return node;
  }
}
```

- [ ] **Step 7: Створити `object_reader.dart`**

Створи `packages/typed_openapi/lib/src/parse/object_reader.dart`:

```dart
import '../diagnostics/json_pointer.dart';
import '../model/spec_node.dart';
import 'parse_context.dart';

/// Reads the fields of one JSON object of a spec.
///
/// Every getter remembers the key it read. A value of the wrong JSON type is
/// reported as `invalid-value` and read as missing. [unknownKeys] reports
/// the keys nobody read, so call it after reading every field.
final class ObjectReader {
  /// Creates a reader for [_map], which is at [pointer].
  ObjectReader(this._context, this._map, this.pointer);

  final ParseContext _context;
  final Map<String, Object?> _map;
  final Set<String> _read = {};

  /// Where the object is.
  final JsonPointer pointer;

  /// The location of the object.
  SpecLocation get location => _context.locate(pointer);

  /// Whether the object has [key].
  bool has(String key) => _map.containsKey(key);

  /// The keys of the object, in document order.
  Iterable<String> get keys => _map.keys;

  /// The raw value of [key] as a one-element record, or null when the key
  /// is missing.
  (Object?,)? value(String key) {
    _read.add(key);
    return _map.containsKey(key) ? (_map[key],) : null;
  }

  /// Marks [keys] as read without reading them: keys the spec defines but
  /// the model does not type.
  void accept(Iterable<String> keys) => _read.addAll(keys);

  /// [key] as a string.
  String? string(String key) => _typed<String>(key, 'a string');

  /// [key] as a string; reports `missing-required-field` when it is missing.
  String? requiredString(String key) {
    if (!has(key)) _missing(key);
    return string(key);
  }

  /// [key] as a boolean.
  bool? boolean(String key) => _typed<bool>(key, 'true or false');

  /// [key] as a number.
  num? number(String key) => _typed<num>(key, 'a number');

  /// [key] as a non-negative integer; `3.0` reads as `3`.
  int? count(String key) {
    final raw = value(key);
    if (raw == null) return null;
    final (number,) = raw;
    if (number is num && number >= 0 && number == number.truncate()) {
      return number.toInt();
    }
    _invalid(key, 'a non-negative integer', number);
    return null;
  }

  /// [key] as one of the names in [byName].
  T? choice<T>(String key, Map<String, T> byName) {
    final name = string(key);
    if (name == null) return null;
    final result = byName[name];
    if (result != null) return result;
    _context.report(
      .invalidValue,
      '"$key" must be one of ${byName.keys.join(', ')}, not "$name".',
      pointer.child(key),
    );
    return null;
  }

  /// [key] as one of the names in [byName]; reports
  /// `missing-required-field` when it is missing.
  T? requiredChoice<T>(String key, Map<String, T> byName) {
    if (!has(key)) _missing(key);
    return choice(key, byName);
  }

  /// [key] as a list of strings; items that are not strings are reported
  /// and skipped.
  List<String>? strings(String key) =>
      list(key, (raw, at) => _item<String>(raw, at, 'a string'));

  /// [key] as a list of raw values, `null` items included.
  List<Object?>? rawList(String key) {
    final raw = value(key);
    if (raw == null) return null;
    final (items,) = raw;
    if (items is List<Object?>) return List.unmodifiable(items);
    _invalid(key, 'a list', items);
    return null;
  }

  /// [key] as a list whose items [read] converts; null items are skipped.
  List<T>? list<T>(String key, T? Function(Object? raw, JsonPointer at) read) {
    final raw = value(key);
    if (raw == null) return null;
    final (items,) = raw;
    if (items is! List<Object?>) {
      _invalid(key, 'a list', items);
      return null;
    }
    final at = pointer.child(key);
    return List.unmodifiable([
      for (var i = 0; i < items.length; i++) ?read(items[i], at.child(i)),
    ]);
  }

  /// [key] as an object whose values [read] converts, in document order;
  /// null values are skipped. With [skipExtensions], `x-` keys are not
  /// entries.
  Map<String, T>? map<T>(
    String key,
    T? Function(Object? raw, JsonPointer at) read, {
    bool skipExtensions = false,
  }) {
    final raw = value(key);
    if (raw == null) return null;
    final (entries,) = raw;
    if (entries is! Map<String, Object?>) {
      _invalid(key, 'an object', entries);
      return null;
    }
    final at = pointer.child(key);
    return Map.unmodifiable({
      for (final MapEntry(key: name, :value) in entries.entries)
        if (!skipExtensions || !name.startsWith('x-'))
          name: ?read(value, at.child(name)),
    });
  }

  /// [key] as an object of strings.
  Map<String, String>? stringMap(String key) =>
      map(key, (raw, at) => _item<String>(raw, at, 'a string'));

  /// [key] read by [read] when it is an object.
  T? object<T>(String key, T Function(ObjectReader reader) read) {
    final raw = value(key);
    if (raw == null) return null;
    final reader = _context.reader(raw.$1, pointer.child(key), '"$key"');
    return reader == null ? null : read(reader);
  }

  /// [key] read by [read]; reports `missing-required-field` when it is
  /// missing.
  T? requiredObject<T>(String key, T Function(ObjectReader reader) read) {
    if (!has(key)) _missing(key);
    return object(key, read);
  }

  /// The `x-` keys of the object and their raw values.
  Map<String, Object?> get extensions => Map.unmodifiable({
    for (final MapEntry(:key, :value) in _map.entries)
      if (key.startsWith('x-')) key: value,
  });

  /// Reports each key that was not read and is not an `x-` key as
  /// `unknown-key`, and returns them with their raw values.
  ///
  /// With [reportExtensions], `x-` keys are reported too: Reference Objects
  /// cannot be extended.
  Map<String, Object?> unknownKeys({bool reportExtensions = false}) {
    final unknown = <String, Object?>{};
    for (final MapEntry(:key, :value) in _map.entries) {
      if (_read.contains(key)) continue;
      if (!reportExtensions && key.startsWith('x-')) continue;
      unknown[key] = value;
      _context.report(
        .unknownKey,
        'Unknown key "$key"; it is ignored.',
        pointer.child(key),
      );
    }
    return Map.unmodifiable(unknown);
  }

  /// How a raw value is named in messages.
  static String describe(Object? raw) => switch (raw) {
    null => 'null',
    bool() => '$raw',
    num() => 'the number $raw',
    String() => 'a string',
    List<Object?>() => 'a list',
    _ => 'an object',
  };

  T? _typed<T>(String key, String expected) {
    final raw = value(key);
    if (raw == null) return null;
    final (result,) = raw;
    if (result is T) return result;
    _invalid(key, expected, result);
    return null;
  }

  T? _item<T>(Object? raw, JsonPointer at, String expected) {
    if (raw is T) return raw;
    _context.report(
      .invalidValue,
      'Each item must be $expected, not ${describe(raw)}.',
      at,
    );
    return null;
  }

  void _invalid(String key, String expected, Object? raw) {
    _context.report(
      .invalidValue,
      '"$key" must be $expected, not ${describe(raw)}; it is ignored.',
      pointer.child(key),
    );
  }

  void _missing(String key) {
    _context.report(
      .missingRequiredField,
      'The required field "$key" is missing.',
      pointer,
    );
  }
}
```

- [ ] **Step 8: Переконатися, що тести проходять**

Run (з `packages/typed_openapi`): `dart test test/parse`
Expected: `+8: All tests passed!`

- [ ] **Step 9: Формат, аналізатор, увесь набір тестів**

Run (з `packages/typed_openapi`): `dart format --output=none --set-exit-if-changed lib test bin && dart test`
Expected: `Formatted 37 files (0 changed)`, `+82: All tests passed!`

Run (з кореня): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 10: Commit**

```bash
git add packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart packages/typed_openapi/lib/src/parse/object_reader.dart packages/typed_openapi/lib/src/parse/parse_context.dart packages/typed_openapi/lib/src/parse/spec_feature.dart packages/typed_openapi/test/helpers/spec_fixture.dart packages/typed_openapi/test/parse/object_reader_test.dart
git commit -m 'feat(typed_openapi): object reader with key and type diagnostics' -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
```

---

### Task 5: Модель і парсер схем (TOA105)

**Files:**
- Create: `packages/typed_openapi/lib/src/model/schema.dart`
- Create: `packages/typed_openapi/lib/src/parse/schema_parser.dart`
- Create: `packages/typed_openapi/test/parse/schema_parser_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`

**Interfaces:**
- Consumes: `ParseContext`, `ObjectReader`, `RefUse`, `SpecFeature` (Task 4).
- Produces: `sealed class Schema extends SpecNode`, `BooleanSchema(value)`, `SchemaObject` (поля — у коді нижче), `enum SchemaType` (`wire`, `byWire`; `nullType` — це `"null"`), `Discriminator(propertyName, mapping, defaultMapping)`; `final class SchemaParser { const SchemaParser(ParseContext); Schema? parse(Object? raw, JsonPointer pointer, {bool booleanIsClassic = false}); }`; код `refBaseIgnored` (TOA105).

Поведінка, яку закріплюють тести:
- 3.0-схема читається повністю, кожна вкладена схема має свій pointer і реєструється в `SpecIndex.nodes`.
- Конструкції 2020-12 (`type`-список, `"null"`, `const`, `examples`, числовий `exclusiveMinimum`, `prefixItems`, булеві схеми, `content*`, `$defs`) читаються і відмічаються як `SpecFeature`; `nullable` — теж (як конструкція лише 3.0). `additionalProperties: false` не відмічається: це 3.0.
- `$ref` із сусідами зберігається разом із ними і записується в `SpecIndex.refs` з видом `schema`.
- `default: null` → `(null,)`, `enum: [a, null]` зберігає `null`.
- `required: true` і невідомий `type: file` — `TOA111`, решта схеми читається. `$id` — `TOA105`.

- [ ] **Step 1: Написати тест, що не проходить**

Створи `packages/typed_openapi/test/parse/schema_parser_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/model/schema.dart';
import 'package:typed_openapi/src/model/spec_node.dart';
import 'package:typed_openapi/src/parse/schema_parser.dart';
import 'package:typed_openapi/src/parse/spec_feature.dart';

import '../helpers/spec_fixture.dart';

void main() {
  (Schema?, SpecFixture) parse(String yaml) {
    final fixture = SpecFixture(yaml);
    final pointer = JsonPointer.root.child('schema');
    final schema = SchemaParser(
      fixture.context,
    ).parse(fixture.document.valueAt(pointer)!.$1, pointer);
    return (schema, fixture);
  }

  test('reads a 3.0 object schema', () {
    final (schema, fixture) = parse('''
schema:
  type: object
  required: [id]
  nullable: true
  description: A pet.
  properties:
    id: {type: integer, format: int64, minimum: 1}
    tags: {type: array, items: {type: string}, maxItems: 10}
  additionalProperties: false
  x-order: 3
''');
    final pet = schema! as SchemaObject;
    expect(pet.types, [SchemaType.object]);
    expect(pet.required, ['id']);
    expect(pet.nullable, isTrue);
    expect(pet.description, 'A pet.');
    expect(pet.properties.keys, ['id', 'tags']);
    final id = pet.properties['id']! as SchemaObject;
    expect(id.format, 'int64');
    expect(id.minimum, 1);
    final tags = pet.properties['tags']! as SchemaObject;
    expect((tags.items! as SchemaObject).types, [SchemaType.string]);
    expect(tags.maxItems, 10);
    expect((pet.additionalProperties! as BooleanSchema).value, isFalse);
    expect(pet.extensions, {'x-order': 3});
    expect(pet.pointer.value, '#/schema');
    expect(id.pointer.value, '#/schema/properties/id');
    expect(fixture.diagnostics.all, isEmpty);
    expect(fixture.index.features.map((f) => f.feature), [
      SpecFeature.nullable,
    ]);
  });

  test('reads 2020-12 keywords and notes them as 3.1 constructs', () {
    final (schema, fixture) = parse(r'''
schema:
  type: [string, "null"]
  const: a
  examples: [a]
  exclusiveMinimum: 0
  prefixItems: [true]
  contentMediaType: application/json
  contentSchema: {type: object}
  $defs: {Id: {type: string}}
''');
    final s = schema! as SchemaObject;
    expect(s.types, [SchemaType.string, SchemaType.nullType]);
    expect(s.constValue, ('a',));
    expect(s.examples, ['a']);
    expect(s.exclusiveMinimum, 0);
    expect(s.exclusiveMinimumFlag, isNull);
    expect(s.prefixItems.single, isA<BooleanSchema>());
    expect(s.contentSchema, isA<SchemaObject>());
    expect(s.otherKeywords.keys, [r'$defs']);
    expect(fixture.diagnostics.all, isEmpty);
    expect(
      fixture.index.features.map((f) => f.feature).toSet(),
      {
        SpecFeature.typeList,
        SpecFeature.nullType,
        SpecFeature.constKeyword,
        SpecFeature.schemaExamples,
        SpecFeature.numericExclusiveBound,
        SpecFeature.prefixItems,
        SpecFeature.booleanSchema,
        SpecFeature.contentKeywords,
        SpecFeature.jsonSchemaKeyword,
      },
    );
  });

  test('keeps a boolean exclusive bound as the 3.0 flag', () {
    final (schema, fixture) = parse(
      'schema: {maximum: 5, exclusiveMaximum: true}\n',
    );
    final s = schema! as SchemaObject;
    expect(s.exclusiveMaximumFlag, isTrue);
    expect(s.exclusiveMaximum, isNull);
    expect(fixture.index.features, isEmpty);
  });

  test(r'keeps $ref with its siblings and records the reference', () {
    final (schema, fixture) = parse(
      'schema: {\$ref: "#/components/schemas/Pet", description: Owner.}\n',
    );
    final s = schema! as SchemaObject;
    expect(s.ref, '#/components/schemas/Pet');
    expect(s.description, 'Owner.');
    final use = fixture.index.refs.single;
    expect(use.ref, '#/components/schemas/Pet');
    expect(use.kind, RefKind.schema);
    expect(use.site, s.location);
  });

  test('defaults, null enum members and examples are kept as written', () {
    final (schema, _) = parse(
      'schema: {default: null, enum: [a, null], example: {k: 1}}\n',
    );
    final s = schema! as SchemaObject;
    expect(s.defaultValue, (null,));
    expect(s.enumValues, ['a', null]);
    expect(s.example?.$1, {'k': 1});
  });

  test('a boolean "required" and an unknown type are reported, the rest is '
      'read', () {
    final (schema, fixture) = parse('''
schema:
  type: array
  items:
    type: file
    required: true
    format: binary
''');
    final items = (schema! as SchemaObject).items! as SchemaObject;
    expect(items.types, isEmpty);
    expect(items.required, isEmpty);
    expect(items.format, 'binary');
    expect(fixture.codes, [
      DiagnosticCode.invalidValue,
      DiagnosticCode.invalidValue,
    ]);
    expect(fixture.pointers, [
      '#/schema/items/type',
      '#/schema/items/required',
    ]);
  });

  test('reads a discriminator with a 3.2 defaultMapping', () {
    final (schema, fixture) = parse(r'''
schema:
  oneOf: [{$ref: "#/c/Cat"}, {$ref: "#/c/Dog"}]
  discriminator:
    propertyName: kind
    mapping: {cat: "#/c/Cat"}
    defaultMapping: "#/c/Dog"
''');
    final d = (schema! as SchemaObject).discriminator!;
    expect(d.propertyName, 'kind');
    expect(d.mapping, {'cat': '#/c/Cat'});
    expect(d.defaultMapping, '#/c/Dog');
    expect(fixture.index.refs, hasLength(2));
    expect(fixture.index.features.single.feature, SpecFeature.defaultMapping);
  });

  test('reports a schema that is neither an object nor a boolean', () {
    final (schema, fixture) = parse('schema: [a]\n');
    expect(schema, isNull);
    expect(fixture.codes, [DiagnosticCode.invalidValue]);
  });

  test(r'reports $id: refs inside are not resolved against it', () {
    final (_, fixture) = parse('schema: {\$id: "https://example.com/a"}\n');
    expect(fixture.codes, [DiagnosticCode.refBaseIgnored]);
  });

  test('registers every schema by location', () {
    final (schema, fixture) = parse(
      'schema: {properties: {a: {items: {type: string}}}}\n',
    );
    expect(fixture.index.nodes.values, hasLength(3));
    expect(fixture.index.nodes[schema!.location], same(schema));
  });
}
```

- [ ] **Step 2: Переконатися, що тести падають**

Run (з `packages/typed_openapi`): `dart test test/parse`
Expected: FAIL, перша помилка — `cannot read 'lib/src/model/schema.dart': No such file or directory`

- [ ] **Step 3: Додати коди в каталог**

У `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart` перед фрагментом:

```dart
  /// An object has a key that no OpenAPI version defines; it is ignored.
```

встав:

```dart
  /// `$id` or `$self` would change the base URI of `$ref`s; this tool
  /// resolves them against the file location instead.
  refBaseIgnored('TOA105', 'ref-base-ignored', .warning),
```

- [ ] **Step 4: Створити `schema.dart`**

Створи `packages/typed_openapi/lib/src/model/schema.dart`:

```dart
import 'spec_node.dart';

/// A JSON Schema: a [BooleanSchema] or a [SchemaObject].
///
/// The model is a superset of OpenAPI 3.0 schemas and JSON Schema 2020-12
/// (OpenAPI 3.1 and 3.2). Nothing is converted between the two: a 3.0
/// `nullable: true` and a 3.1 `type: [string, "null"]` are both kept as
/// written; the normalizer reconciles them later.
sealed class Schema extends SpecNode {
  /// Creates a schema.
  const Schema({
    required super.location,
    super.extensions,
    super.unknownKeys,
  });
}

/// `true` (any value) or `false` (no value) used as a schema.
final class BooleanSchema extends Schema {
  /// Creates a boolean schema.
  const BooleanSchema({required super.location, required this.value});

  /// Whether every value is valid.
  final bool value;
}

/// The JSON types a schema's `type` can name.
enum SchemaType {
  /// `string`.
  string('string'),

  /// `number`.
  number('number'),

  /// `integer`.
  integer('integer'),

  /// `boolean`.
  boolean('boolean'),

  /// `array`.
  array('array'),

  /// `object`.
  object('object'),

  /// `null` (JSON Schema 2020-12 only).
  nullType('null');

  const SchemaType(this.wire);

  /// The name used in specs.
  final String wire;

  /// The types by [wire] name.
  static final Map<String, SchemaType> byWire = {
    for (final type in values) type.wire: type,
  };
}

/// A Schema Object.
///
/// A raw value that may be `null` in the spec is kept as a one-element
/// record, so `default: null` reads as `(null,)` and a missing `default` as
/// `null`.
final class SchemaObject extends Schema {
  /// Creates a schema object.
  const SchemaObject({
    required super.location,
    this.ref,
    this.types = const [],
    this.nullable,
    this.format,
    this.title,
    this.description,
    this.deprecated = false,
    this.readOnly = false,
    this.writeOnly = false,
    this.defaultValue,
    this.constValue,
    this.enumValues,
    this.example,
    this.examples = const [],
    this.properties = const {},
    this.required = const [],
    this.additionalProperties,
    this.minProperties,
    this.maxProperties,
    this.items,
    this.prefixItems = const [],
    this.minItems,
    this.maxItems,
    this.uniqueItems = false,
    this.allOf = const [],
    this.oneOf = const [],
    this.anyOf = const [],
    this.not,
    this.discriminator,
    this.minimum,
    this.maximum,
    this.exclusiveMinimum,
    this.exclusiveMaximum,
    this.exclusiveMinimumFlag,
    this.exclusiveMaximumFlag,
    this.multipleOf,
    this.minLength,
    this.maxLength,
    this.pattern,
    this.contentMediaType,
    this.contentEncoding,
    this.contentSchema,
    this.otherKeywords = const {},
    super.extensions,
    super.unknownKeys,
  });

  /// The `$ref` keyword as written; the other keywords apply next to it.
  final String? ref;

  /// `type`, as a list even when the spec wrote a single string.
  final List<SchemaType> types;

  /// OpenAPI 3.0 `nullable`.
  final bool? nullable;

  /// `format`.
  final String? format;

  /// `title`.
  final String? title;

  /// `description`.
  final String? description;

  /// `deprecated`.
  final bool deprecated;

  /// `readOnly`.
  final bool readOnly;

  /// `writeOnly`.
  final bool writeOnly;

  /// `default`.
  final (Object?,)? defaultValue;

  /// `const`.
  final (Object?,)? constValue;

  /// `enum`.
  final List<Object?>? enumValues;

  /// `example` (deprecated in 3.1).
  final (Object?,)? example;

  /// `examples`, the JSON Schema list of examples.
  final List<Object?> examples;

  /// `properties`, in document order.
  final Map<String, Schema> properties;

  /// `required`.
  final List<String> required;

  /// `additionalProperties`; a [BooleanSchema] when the spec wrote a boolean.
  final Schema? additionalProperties;

  /// `minProperties`.
  final int? minProperties;

  /// `maxProperties`.
  final int? maxProperties;

  /// `items`.
  final Schema? items;

  /// `prefixItems`.
  final List<Schema> prefixItems;

  /// `minItems`.
  final int? minItems;

  /// `maxItems`.
  final int? maxItems;

  /// `uniqueItems`.
  final bool uniqueItems;

  /// `allOf`.
  final List<Schema> allOf;

  /// `oneOf`.
  final List<Schema> oneOf;

  /// `anyOf`.
  final List<Schema> anyOf;

  /// `not`.
  final Schema? not;

  /// `discriminator`.
  final Discriminator? discriminator;

  /// `minimum`.
  final num? minimum;

  /// `maximum`.
  final num? maximum;

  /// `exclusiveMinimum` written as a number (JSON Schema 2020-12).
  final num? exclusiveMinimum;

  /// `exclusiveMaximum` written as a number (JSON Schema 2020-12).
  final num? exclusiveMaximum;

  /// `exclusiveMinimum` written as a boolean (OpenAPI 3.0).
  final bool? exclusiveMinimumFlag;

  /// `exclusiveMaximum` written as a boolean (OpenAPI 3.0).
  final bool? exclusiveMaximumFlag;

  /// `multipleOf`.
  final num? multipleOf;

  /// `minLength`.
  final int? minLength;

  /// `maxLength`.
  final int? maxLength;

  /// `pattern`.
  final String? pattern;

  /// `contentMediaType`.
  final String? contentMediaType;

  /// `contentEncoding`.
  final String? contentEncoding;

  /// `contentSchema`.
  final Schema? contentSchema;

  /// JSON Schema 2020-12 keywords the model does not read yet, such as
  /// `$defs`, `if` or `patternProperties`, with their raw values.
  final Map<String, Object?> otherKeywords;
}

/// A Discriminator Object.
final class Discriminator extends SpecNode {
  /// Creates a discriminator.
  const Discriminator({
    required super.location,
    this.propertyName,
    this.mapping = const {},
    this.defaultMapping,
    super.extensions,
    super.unknownKeys,
  });

  /// `propertyName`; required by the spec.
  final String? propertyName;

  /// `mapping` from a property value to a schema name or `$ref`.
  final Map<String, String> mapping;

  /// `defaultMapping` (OpenAPI 3.2).
  final String? defaultMapping;
}
```

- [ ] **Step 5: Створити `schema_parser.dart`**

Створи `packages/typed_openapi/lib/src/parse/schema_parser.dart`:

```dart
import '../diagnostics/json_pointer.dart';
import '../model/schema.dart';
import 'object_reader.dart';
import 'parse_context.dart';
import 'spec_feature.dart';

/// Reads Schema Objects of OpenAPI 3.0, 3.1 and 3.2 into [Schema]s.
///
/// Every keyword of any of those versions is read, whatever version the
/// document declares; version-specific ones are noted in the context's
/// index for `DialectChecker`.
final class SchemaParser {
  /// Creates a parser that reads from [_context].
  const SchemaParser(this._context);

  /// Keywords the spec defines but the model does not type.
  static const _accepted = ['xml', 'externalDocs'];

  /// JSON Schema 2020-12 keywords kept raw in [SchemaObject.otherKeywords].
  static const _rawKeywords = [
    r'$id',
    r'$schema',
    r'$anchor',
    r'$dynamicRef',
    r'$dynamicAnchor',
    r'$defs',
    r'$comment',
    r'$vocabulary',
    'if',
    'then',
    'else',
    'dependentSchemas',
    'dependentRequired',
    'patternProperties',
    'propertyNames',
    'contains',
    'minContains',
    'maxContains',
    'unevaluatedItems',
    'unevaluatedProperties',
  ];

  final ParseContext _context;

  /// Reads the schema [raw] at [pointer]; null after reporting when [raw] is
  /// neither an object nor a boolean.
  ///
  /// A boolean is noted as a 3.1 construct unless [booleanIsClassic]: 3.0
  /// allows `additionalProperties: true`.
  Schema? parse(
    Object? raw,
    JsonPointer pointer, {
    bool booleanIsClassic = false,
  }) {
    if (raw is bool) {
      if (!booleanIsClassic) _context.note(.booleanSchema, pointer);
      return _context.register(
        BooleanSchema(location: _context.locate(pointer), value: raw),
      );
    }
    if (raw is! Map<String, Object?>) {
      _context.report(
        .invalidValue,
        'A schema must be an object or a boolean, not '
        '${ObjectReader.describe(raw)}; it is ignored.',
        pointer,
      );
      return null;
    }
    return _object(ObjectReader(_context, raw, pointer));
  }

  SchemaObject _object(ObjectReader r) {
    final ref = r.string(r'$ref');
    if (ref != null) {
      _context.index.refs.add(RefUse(r.location, ref, .schema));
    }
    if (r.has(r'$id')) {
      _context.report(
        .refBaseIgnored,
        r'"$id" changes the base URI of "$ref"s inside this schema; they '
        'are resolved against the file location instead.',
        r.pointer.child(r'$id'),
      );
    }
    final at = r.pointer;
    for (final (key, feature) in _notedKeys) {
      if (r.has(key)) _context.note(feature, at.child(key));
    }
    r.accept(_accepted);
    final schema = SchemaObject(
      location: r.location,
      ref: ref,
      types: _types(r),
      nullable: r.boolean('nullable'),
      format: r.string('format'),
      title: r.string('title'),
      description: r.string('description'),
      deprecated: r.boolean('deprecated') ?? false,
      readOnly: r.boolean('readOnly') ?? false,
      writeOnly: r.boolean('writeOnly') ?? false,
      defaultValue: r.value('default'),
      constValue: r.value('const'),
      enumValues: r.rawList('enum'),
      example: r.value('example'),
      examples: r.rawList('examples') ?? const [],
      properties: r.map('properties', parse) ?? const {},
      required: r.strings('required') ?? const [],
      additionalProperties: _schemaAt(
        r,
        'additionalProperties',
        booleanIsClassic: true,
      ),
      minProperties: r.count('minProperties'),
      maxProperties: r.count('maxProperties'),
      items: _schemaAt(r, 'items'),
      prefixItems: r.list('prefixItems', parse) ?? const [],
      minItems: r.count('minItems'),
      maxItems: r.count('maxItems'),
      uniqueItems: r.boolean('uniqueItems') ?? false,
      allOf: r.list('allOf', parse) ?? const [],
      oneOf: r.list('oneOf', parse) ?? const [],
      anyOf: r.list('anyOf', parse) ?? const [],
      not: _schemaAt(r, 'not'),
      discriminator: r.object('discriminator', _discriminator),
      minimum: r.number('minimum'),
      maximum: r.number('maximum'),
      exclusiveMinimum: _bound(r, 'exclusiveMinimum'),
      exclusiveMaximum: _bound(r, 'exclusiveMaximum'),
      exclusiveMinimumFlag: _flag(r, 'exclusiveMinimum'),
      exclusiveMaximumFlag: _flag(r, 'exclusiveMaximum'),
      multipleOf: r.number('multipleOf'),
      minLength: r.count('minLength'),
      maxLength: r.count('maxLength'),
      pattern: r.string('pattern'),
      contentMediaType: r.string('contentMediaType'),
      contentEncoding: r.string('contentEncoding'),
      contentSchema: _schemaAt(r, 'contentSchema'),
      otherKeywords: Map.unmodifiable({
        for (final key in _rawKeywords)
          if (r.value(key) case (final raw,)) key: raw,
      }),
      extensions: r.extensions,
      unknownKeys: r.unknownKeys(),
    );
    return _context.register(schema);
  }

  static const _notedKeys = [
    ('nullable', SpecFeature.nullable),
    ('const', SpecFeature.constKeyword),
    ('prefixItems', SpecFeature.prefixItems),
    ('examples', SpecFeature.schemaExamples),
    ('contentMediaType', SpecFeature.contentKeywords),
    ('contentEncoding', SpecFeature.contentKeywords),
    ('contentSchema', SpecFeature.contentKeywords),
    (r'$id', SpecFeature.jsonSchemaKeyword),
    (r'$schema', SpecFeature.jsonSchemaKeyword),
    (r'$anchor', SpecFeature.jsonSchemaKeyword),
    (r'$dynamicRef', SpecFeature.jsonSchemaKeyword),
    (r'$dynamicAnchor', SpecFeature.jsonSchemaKeyword),
    (r'$defs', SpecFeature.jsonSchemaKeyword),
    (r'$comment', SpecFeature.jsonSchemaKeyword),
    (r'$vocabulary', SpecFeature.jsonSchemaKeyword),
    ('if', SpecFeature.jsonSchemaKeyword),
    ('then', SpecFeature.jsonSchemaKeyword),
    ('else', SpecFeature.jsonSchemaKeyword),
    ('dependentSchemas', SpecFeature.jsonSchemaKeyword),
    ('dependentRequired', SpecFeature.jsonSchemaKeyword),
    ('patternProperties', SpecFeature.jsonSchemaKeyword),
    ('propertyNames', SpecFeature.jsonSchemaKeyword),
    ('contains', SpecFeature.jsonSchemaKeyword),
    ('minContains', SpecFeature.jsonSchemaKeyword),
    ('maxContains', SpecFeature.jsonSchemaKeyword),
    ('unevaluatedItems', SpecFeature.jsonSchemaKeyword),
    ('unevaluatedProperties', SpecFeature.jsonSchemaKeyword),
  ];

  List<SchemaType> _types(ObjectReader r) {
    final raw = r.value('type');
    if (raw == null) return const [];
    final at = r.pointer.child('type');
    final (type,) = raw;
    if (type is List<Object?>) _context.note(.typeList, at);
    final names = type is List<Object?> ? type : [type];
    final types = <SchemaType>[];
    for (var i = 0; i < names.length; i++) {
      final name = names[i];
      final itemAt = type is List<Object?> ? at.child(i) : at;
      final known = name is String ? SchemaType.byWire[name] : null;
      if (known == null) {
        _context.report(
          .invalidValue,
          name is String
              ? 'Unknown type "$name"; it is ignored.'
              : 'A type must be a string, not ${ObjectReader.describe(name)}; '
                    'it is ignored.',
          itemAt,
          fix: 'Use one of ${SchemaType.byWire.keys.join(', ')}.',
        );
        continue;
      }
      if (known == .nullType) _context.note(.nullType, itemAt);
      types.add(known);
    }
    return List.unmodifiable(types);
  }

  Schema? _schemaAt(
    ObjectReader r,
    String key, {
    bool booleanIsClassic = false,
  }) {
    final raw = r.value(key);
    if (raw == null) return null;
    return parse(
      raw.$1,
      r.pointer.child(key),
      booleanIsClassic: booleanIsClassic,
    );
  }

  num? _bound(ObjectReader r, String key) {
    final raw = r.value(key);
    if (raw case (final num bound,)) {
      _context.note(.numericExclusiveBound, r.pointer.child(key));
      return bound;
    }
    if (raw case (bool(),)) return null;
    if (raw != null) {
      _context.report(
        .invalidValue,
        '"$key" must be a number or a boolean, not '
        '${ObjectReader.describe(raw.$1)}; it is ignored.',
        r.pointer.child(key),
      );
    }
    return null;
  }

  static bool? _flag(ObjectReader r, String key) => switch (r.value(key)) {
    (final bool flag,) => flag,
    _ => null,
  };

  Discriminator _discriminator(ObjectReader r) {
    if (r.has('defaultMapping')) {
      _context.note(.defaultMapping, r.pointer.child('defaultMapping'));
    }
    return _context.register(
      Discriminator(
        location: r.location,
        propertyName: r.requiredString('propertyName'),
        mapping: r.stringMap('mapping') ?? const {},
        defaultMapping: r.string('defaultMapping'),
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }
}
```

- [ ] **Step 6: Переконатися, що тести проходять**

Run (з `packages/typed_openapi`): `dart test test/parse`
Expected: `+18: All tests passed!`

- [ ] **Step 7: Формат, аналізатор, увесь набір тестів**

Run (з `packages/typed_openapi`): `dart format --output=none --set-exit-if-changed lib test bin && dart test`
Expected: `Formatted 40 files (0 changed)`, `+92: All tests passed!`

Run (з кореня): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart packages/typed_openapi/lib/src/model/schema.dart packages/typed_openapi/lib/src/parse/schema_parser.dart packages/typed_openapi/test/parse/schema_parser_test.dart
git commit -m 'feat(typed_openapi): schema model and parser' -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
```

---

### Task 6: Path items, операції та їхні частини

**Files:**
- Create: `packages/typed_openapi/lib/src/model/operation.dart`
- Create: `packages/typed_openapi/lib/src/parse/operation_parser.dart`
- Create: `packages/typed_openapi/test/parse/operation_parser_test.dart`

**Interfaces:**
- Consumes: `ParseContext.refOr`, `ObjectReader` (Task 4), `SchemaParser`, `Schema` (Task 5).
- Produces: моделі `PathItem` (`static const methods`), `Operation`, `Parameter` (`placement` — це поле `in`), `ParameterLocation`, `ParameterStyle`, `RequestBody`, `Response`, `Header`, `MediaType`, `Encoding`, `Example`, `Server`, `ServerVariable`, `SecurityRequirement`; `final class OperationParser { const OperationParser(ParseContext, SchemaParser); … }` з публічними `pathItem`, `parameter`, `requestBody`, `response`, `header`, `mediaType`, `example` (усі `RefOr<T>? Function(Object? raw, JsonPointer)`), `server`, `securityRequirement`.

Поведінка, яку закріплюють тести:
- Path item, операція, параметри (inline і `$ref`), відповіді за статусом у порядку документа (без `x-`), заголовки, `content`, тіла, encoding, examples читаються з pointer на кожному вузлі; усі `$ref` записуються з очікуваним видом.
- `security` операції: `null` — не задано (успадковується), `[]` — явно без безпеки.
- 3.2: операція `query`, `additionalOperations`, `in: querystring`, `summary` відповіді, `itemSchema` — читаються і відмічаються.
- Параметр у стилі Swagger 2 (`type` замість `schema`) — `TOA110`; без `name` — `TOA112`; `in: body` — `TOA111`. Reference Object з чужими ключами — `TOA110`; вузол не-об'єкт — `TOA111` «This response must be an object, not a string.»

- [ ] **Step 1: Написати тест, що не проходить**

Створи `packages/typed_openapi/test/parse/operation_parser_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/model/operation.dart';
import 'package:typed_openapi/src/model/schema.dart';
import 'package:typed_openapi/src/model/spec_node.dart';
import 'package:typed_openapi/src/parse/operation_parser.dart';
import 'package:typed_openapi/src/parse/schema_parser.dart';
import 'package:typed_openapi/src/parse/spec_feature.dart';

import '../helpers/spec_fixture.dart';

void main() {
  (RefOr<PathItem>?, SpecFixture) parse(String yaml) {
    final fixture = SpecFixture(yaml);
    final pointer = JsonPointer.root.child('item');
    final item = OperationParser(
      fixture.context,
      SchemaParser(fixture.context),
    ).pathItem(fixture.document.valueAt(pointer)!.$1, pointer);
    return (item, fixture);
  }

  T inline<T extends SpecNode>(RefOr<T>? value) => (value! as Inline<T>).value;

  test('reads a path item with an operation', () {
    final (item, fixture) = parse(r'''
item:
  parameters:
    - {name: id, in: path, required: true, schema: {type: string}}
  get:
    operationId: getPet
    tags: [pets]
    parameters:
      - $ref: "#/components/parameters/Limit"
    responses:
      "200":
        description: OK
        headers:
          X-Rate: {schema: {type: integer}}
        content:
          application/json:
            schema: {$ref: "#/components/schemas/Pet"}
      default: {$ref: "#/components/responses/Error"}
      x-codegen: skip
    security: []
''');
    final pets = inline(item);
    expect(pets.parameters, hasLength(1));
    final id = inline(pets.parameters.single);
    expect(id.name, 'id');
    expect(id.placement, ParameterLocation.path);
    expect(id.required, isTrue);
    final get = pets.operations['get']!;
    expect(get.operationId, 'getPet');
    expect(get.tags, ['pets']);
    expect(get.parameters.single, isA<Ref<Parameter>>());
    expect(get.responses.keys, ['200', 'default']);
    final ok = inline(get.responses['200']);
    expect(ok.description, 'OK');
    expect(inline(ok.headers['X-Rate']).schema, isA<SchemaObject>());
    final json = inline(ok.content['application/json']);
    expect((json.schema! as SchemaObject).ref, '#/components/schemas/Pet');
    expect(get.security, isEmpty);
    expect(pets.operations['post'], isNull);
    expect(fixture.diagnostics.all, isEmpty);
    expect(fixture.index.refs.map((r) => (r.ref, r.kind)), [
      ('#/components/parameters/Limit', RefKind.parameter),
      ('#/components/schemas/Pet', RefKind.schema),
      ('#/components/responses/Error', RefKind.response),
    ]);
  });

  test('security stays null when an operation does not set it', () {
    final (item, _) = parse('item: {get: {responses: {}}}\n');
    expect(inline(item).operations['get']!.security, isNull);
  });

  test('reads request bodies, encodings and examples', () {
    final (item, fixture) = parse('''
item:
  post:
    requestBody:
      required: true
      content:
        multipart/form-data:
          schema: {type: object}
          encoding:
            file: {contentType: image/png}
          examples:
            one: {summary: One, value: {a: 1}}
''');
    final body = inline(inline(item).operations['post']!.requestBody);
    expect(body.required, isTrue);
    final form = inline(body.content['multipart/form-data']);
    expect(form.encoding['file']!.contentType, 'image/png');
    expect(inline(form.examples['one']).summary, 'One');
    expect(fixture.diagnostics.all, isEmpty);
  });

  test('reads 3.2 constructs and notes them', () {
    final (item, fixture) = parse('''
item:
  query:
    parameters:
      - {name: filter, in: querystring, content: {application/x-www-form-urlencoded: {}}}
    responses:
      "200":
        summary: Events
        content:
          text/event-stream:
            itemSchema: {type: object}
  additionalOperations:
    PURGE: {responses: {}}
''');
    final pets = inline(item);
    expect(pets.operations.keys, ['query']);
    expect(pets.additionalOperations.keys, ['PURGE']);
    final query = pets.operations['query']!;
    expect(
      inline(query.parameters.single).placement,
      ParameterLocation.querystring,
    );
    final events = inline(
      inline(query.responses['200']).content['text/event-stream'],
    );
    expect(events.itemSchema, isA<SchemaObject>());
    expect(fixture.diagnostics.all, isEmpty);
    expect(fixture.index.features.map((f) => f.feature).toSet(), {
      SpecFeature.queryOperation,
      SpecFeature.querystringParameter,
      SpecFeature.responseSummary,
      SpecFeature.itemSchema,
      SpecFeature.additionalOperations,
    });
  });

  test('a Swagger 2 style parameter is reported, the rest is read', () {
    final (item, fixture) = parse('''
item:
  get:
    parameters:
      - {name: limit, in: query, type: integer}
      - {in: header, schema: {type: string}}
      - {name: x, in: body}
''');
    final params = inline(item).operations['get']!.parameters;
    expect(params.map((p) => inline(p).name), ['limit', null, 'x']);
    expect(fixture.codes, [
      DiagnosticCode.unknownKey,
      DiagnosticCode.missingRequiredField,
      DiagnosticCode.invalidValue,
    ]);
    expect(fixture.pointers, [
      '#/item/get/parameters/0/type',
      '#/item/get/parameters/1',
      '#/item/get/parameters/2/in',
    ]);
  });

  test('a Reference Object keeps summary and description and reports the '
      'rest', () {
    final (item, fixture) = parse(r'''
item:
  $ref: "#/components/pathItems/Pets"
  description: Pets.
  get: {}
''');
    final ref = item! as Ref<PathItem>;
    expect(ref.ref, '#/components/pathItems/Pets');
    expect(ref.description, 'Pets.');
    expect(ref.kind, RefKind.pathItem);
    expect(ref.unknownKeys.keys, ['get']);
    expect(fixture.codes, [DiagnosticCode.unknownKey]);
  });

  test('a node of the wrong shape is reported and skipped', () {
    final (item, fixture) = parse('item: {get: {responses: {"200": oops}}}\n');
    expect(inline(item).operations['get']!.responses, isEmpty);
    expect(fixture.codes, [DiagnosticCode.invalidValue]);
    expect(
      fixture.diagnostics.all.single.message,
      'This response must be an object, not a string.',
    );
  });
}
```

- [ ] **Step 2: Переконатися, що тести падають**

Run (з `packages/typed_openapi`): `dart test test/parse`
Expected: FAIL, перша помилка — `cannot read 'lib/src/model/operation.dart': No such file or directory`

- [ ] **Step 3: Створити `operation.dart`**

Створи `packages/typed_openapi/lib/src/model/operation.dart`:

```dart
import 'schema.dart';
import 'spec_node.dart';

/// A Path Item Object.
final class PathItem extends SpecNode {
  /// Creates a path item.
  const PathItem({
    required super.location,
    this.summary,
    this.description,
    this.operations = const {},
    this.additionalOperations = const {},
    this.servers = const [],
    this.parameters = const [],
    super.extensions,
    super.unknownKeys,
  });

  /// The fixed operation fields of a path item, in the order the spec lists
  /// them; `query` is OpenAPI 3.2.
  static const methods = [
    'get',
    'put',
    'post',
    'delete',
    'options',
    'head',
    'patch',
    'trace',
    'query',
  ];

  /// `summary`.
  final String? summary;

  /// `description`.
  final String? description;

  /// Operations by lowercase method from [methods], in document order.
  final Map<String, Operation> operations;

  /// `additionalOperations` (OpenAPI 3.2): operations by method, with the
  /// method's case as written.
  final Map<String, Operation> additionalOperations;

  /// `servers`.
  final List<Server> servers;

  /// `parameters` shared by every operation of the path.
  final List<RefOr<Parameter>> parameters;
}

/// An Operation Object.
final class Operation extends SpecNode {
  /// Creates an operation.
  const Operation({
    required super.location,
    this.tags = const [],
    this.summary,
    this.description,
    this.operationId,
    this.parameters = const [],
    this.requestBody,
    this.responses = const {},
    this.deprecated = false,
    this.security,
    this.servers = const [],
    super.extensions,
    super.unknownKeys,
  });

  /// `tags`.
  final List<String> tags;

  /// `summary`.
  final String? summary;

  /// `description`.
  final String? description;

  /// `operationId`.
  final String? operationId;

  /// `parameters`.
  final List<RefOr<Parameter>> parameters;

  /// `requestBody`.
  final RefOr<RequestBody>? requestBody;

  /// `responses` by status code, range (`2XX`) or `default`, in document
  /// order; `x-` keys of the Responses Object are not included.
  final Map<String, RefOr<Response>> responses;

  /// `deprecated`.
  final bool deprecated;

  /// `security`; null when the operation does not set it and inherits the
  /// document's.
  final List<SecurityRequirement>? security;

  /// `servers`.
  final List<Server> servers;
}

/// Where a parameter is sent: the `in` field.
enum ParameterLocation {
  /// A query parameter.
  query,

  /// The whole query string as one value (OpenAPI 3.2).
  querystring,

  /// A header.
  header,

  /// A path segment.
  path,

  /// A cookie.
  cookie,
}

/// How a parameter value is serialized: the `style` field.
enum ParameterStyle {
  /// `matrix`.
  matrix,

  /// `label`.
  label,

  /// `simple`.
  simple,

  /// `form`.
  form,

  /// `spaceDelimited`.
  spaceDelimited,

  /// `pipeDelimited`.
  pipeDelimited,

  /// `deepObject`.
  deepObject,

  /// `cookie` (OpenAPI 3.2).
  cookie,
}

/// A Parameter Object.
final class Parameter extends SpecNode {
  /// Creates a parameter.
  const Parameter({
    required super.location,
    this.name,
    this.placement,
    this.description,
    this.required = false,
    this.deprecated = false,
    this.allowEmptyValue = false,
    this.style,
    this.explode,
    this.allowReserved = false,
    this.schema,
    this.example,
    this.examples = const {},
    this.content = const {},
    super.extensions,
    super.unknownKeys,
  });

  /// `name`; required by the spec.
  final String? name;

  /// `in`; required by the spec.
  final ParameterLocation? placement;

  /// `description`.
  final String? description;

  /// `required`.
  final bool required;

  /// `deprecated`.
  final bool deprecated;

  /// `allowEmptyValue`.
  final bool allowEmptyValue;

  /// `style`.
  final ParameterStyle? style;

  /// `explode`; null when the spec leaves it to the style's default.
  final bool? explode;

  /// `allowReserved`.
  final bool allowReserved;

  /// `schema`.
  final Schema? schema;

  /// `example`.
  final (Object?,)? example;

  /// `examples`.
  final Map<String, RefOr<Example>> examples;

  /// `content`, used instead of [schema] for complex serialization.
  final Map<String, RefOr<MediaType>> content;
}

/// A Request Body Object.
final class RequestBody extends SpecNode {
  /// Creates a request body.
  const RequestBody({
    required super.location,
    this.description,
    this.content = const {},
    this.required = false,
    super.extensions,
    super.unknownKeys,
  });

  /// `description`.
  final String? description;

  /// `content` by media type, in document order.
  final Map<String, RefOr<MediaType>> content;

  /// `required`.
  final bool required;
}

/// A Response Object.
final class Response extends SpecNode {
  /// Creates a response.
  const Response({
    required super.location,
    this.summary,
    this.description,
    this.headers = const {},
    this.content = const {},
    super.extensions,
    super.unknownKeys,
  });

  /// `summary` (OpenAPI 3.2).
  final String? summary;

  /// `description`.
  final String? description;

  /// `headers`.
  final Map<String, RefOr<Header>> headers;

  /// `content` by media type, in document order.
  final Map<String, RefOr<MediaType>> content;
}

/// A Header Object.
final class Header extends SpecNode {
  /// Creates a header.
  const Header({
    required super.location,
    this.description,
    this.required = false,
    this.deprecated = false,
    this.style,
    this.explode,
    this.schema,
    this.example,
    this.examples = const {},
    this.content = const {},
    super.extensions,
    super.unknownKeys,
  });

  /// `description`.
  final String? description;

  /// `required`.
  final bool required;

  /// `deprecated`.
  final bool deprecated;

  /// `style`.
  final ParameterStyle? style;

  /// `explode`.
  final bool? explode;

  /// `schema`.
  final Schema? schema;

  /// `example`.
  final (Object?,)? example;

  /// `examples`.
  final Map<String, RefOr<Example>> examples;

  /// `content`.
  final Map<String, RefOr<MediaType>> content;
}

/// A Media Type Object.
final class MediaType extends SpecNode {
  /// Creates a media type.
  const MediaType({
    required super.location,
    this.schema,
    this.itemSchema,
    this.example,
    this.examples = const {},
    this.encoding = const {},
    this.prefixEncoding = const [],
    this.itemEncoding,
    super.extensions,
    super.unknownKeys,
  });

  /// `schema`.
  final Schema? schema;

  /// `itemSchema` (OpenAPI 3.2): the schema of each item of a sequential
  /// media type such as `text/event-stream`.
  final Schema? itemSchema;

  /// `example`.
  final (Object?,)? example;

  /// `examples`.
  final Map<String, RefOr<Example>> examples;

  /// `encoding` by property name.
  final Map<String, Encoding> encoding;

  /// `prefixEncoding` (OpenAPI 3.2).
  final List<Encoding> prefixEncoding;

  /// `itemEncoding` (OpenAPI 3.2).
  final Encoding? itemEncoding;
}

/// An Encoding Object.
final class Encoding extends SpecNode {
  /// Creates an encoding.
  const Encoding({
    required super.location,
    this.contentType,
    this.headers = const {},
    this.style,
    this.explode,
    this.allowReserved = false,
    super.extensions,
    super.unknownKeys,
  });

  /// `contentType`.
  final String? contentType;

  /// `headers`.
  final Map<String, RefOr<Header>> headers;

  /// `style`.
  final ParameterStyle? style;

  /// `explode`.
  final bool? explode;

  /// `allowReserved`.
  final bool allowReserved;
}

/// An Example Object.
final class Example extends SpecNode {
  /// Creates an example.
  const Example({
    required super.location,
    this.summary,
    this.description,
    this.value,
    this.dataValue,
    this.serializedValue,
    this.externalValue,
    super.extensions,
    super.unknownKeys,
  });

  /// `summary`.
  final String? summary;

  /// `description`.
  final String? description;

  /// `value`.
  final (Object?,)? value;

  /// `dataValue` (OpenAPI 3.2).
  final (Object?,)? dataValue;

  /// `serializedValue` (OpenAPI 3.2).
  final String? serializedValue;

  /// `externalValue`.
  final String? externalValue;
}

/// A Server Object.
final class Server extends SpecNode {
  /// Creates a server.
  const Server({
    required super.location,
    this.url,
    this.name,
    this.description,
    this.variables = const {},
    super.extensions,
    super.unknownKeys,
  });

  /// `url`, possibly with `{variables}`; required by the spec.
  final String? url;

  /// `name` (OpenAPI 3.2).
  final String? name;

  /// `description`.
  final String? description;

  /// `variables` by name.
  final Map<String, ServerVariable> variables;
}

/// A Server Variable Object.
final class ServerVariable extends SpecNode {
  /// Creates a server variable.
  const ServerVariable({
    required super.location,
    this.enumValues,
    this.defaultValue,
    this.description,
    super.extensions,
    super.unknownKeys,
  });

  /// `enum`.
  final List<String>? enumValues;

  /// `default`; required by the spec.
  final String? defaultValue;

  /// `description`.
  final String? description;
}

/// A Security Requirement Object: scheme names and the scopes each needs.
///
/// An empty requirement (`{}`) makes security optional.
final class SecurityRequirement extends SpecNode {
  /// Creates a requirement.
  const SecurityRequirement({required super.location, this.schemes = const {}});

  /// Scopes by security scheme name, in document order.
  final Map<String, List<String>> schemes;
}
```

- [ ] **Step 4: Створити `operation_parser.dart`**

Створи `packages/typed_openapi/lib/src/parse/operation_parser.dart`:

```dart
import '../diagnostics/json_pointer.dart';
import '../model/operation.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';
import 'object_reader.dart';
import 'parse_context.dart';
import 'schema_parser.dart';

/// Reads path items, operations and everything they contain: parameters,
/// request bodies, responses, headers, media types, encodings, examples,
/// servers and security requirements.
final class OperationParser {
  /// Creates a parser that reads from [_context] and reads schemas with
  /// [_schemas].
  const OperationParser(this._context, this._schemas);

  final ParseContext _context;
  final SchemaParser _schemas;

  /// Reads the path item [raw] at [pointer].
  RefOr<PathItem>? pathItem(Object? raw, JsonPointer pointer) =>
      _context.refOr(raw, pointer, .pathItem, _pathItem);

  /// Reads the parameter [raw] at [pointer].
  RefOr<Parameter>? parameter(Object? raw, JsonPointer pointer) =>
      _context.refOr(raw, pointer, .parameter, _parameter);

  /// Reads the request body [raw] at [pointer].
  RefOr<RequestBody>? requestBody(Object? raw, JsonPointer pointer) =>
      _context.refOr(raw, pointer, .requestBody, _requestBody);

  /// Reads the response [raw] at [pointer].
  RefOr<Response>? response(Object? raw, JsonPointer pointer) =>
      _context.refOr(raw, pointer, .response, _response);

  /// Reads the header [raw] at [pointer].
  RefOr<Header>? header(Object? raw, JsonPointer pointer) =>
      _context.refOr(raw, pointer, .header, _header);

  /// Reads the media type [raw] at [pointer].
  RefOr<MediaType>? mediaType(Object? raw, JsonPointer pointer) =>
      _context.refOr(raw, pointer, .mediaType, _mediaType);

  /// Reads the example [raw] at [pointer].
  RefOr<Example>? example(Object? raw, JsonPointer pointer) =>
      _context.refOr(raw, pointer, .example, _example);

  /// Reads the server [raw] at [pointer].
  Server? server(Object? raw, JsonPointer pointer) {
    final r = _context.reader(raw, pointer, 'A server');
    if (r == null) return null;
    if (r.has('name')) _context.note(.serverName, pointer.child('name'));
    return _context.register(
      Server(
        location: r.location,
        url: r.requiredString('url'),
        name: r.string('name'),
        description: r.string('description'),
        variables: r.map('variables', _serverVariable) ?? const {},
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  /// Reads the security requirement [raw] at [pointer].
  SecurityRequirement? securityRequirement(Object? raw, JsonPointer pointer) {
    final r = _context.reader(raw, pointer, 'A security requirement');
    if (r == null) return null;
    return _context.register(
      SecurityRequirement(
        location: r.location,
        schemes: Map.unmodifiable({
          for (final name in r.keys.toList()) name: ?r.strings(name),
        }),
      ),
    );
  }

  PathItem _pathItem(ObjectReader r) {
    final operations = <String, Operation>{};
    for (final method in PathItem.methods) {
      final operation = r.object(method, _operation);
      if (operation == null) continue;
      operations[method] = operation;
      if (method == 'query') {
        _context.note(.queryOperation, r.pointer.child(method));
      }
    }
    if (r.has('additionalOperations')) {
      _context.note(
        .additionalOperations,
        r.pointer.child('additionalOperations'),
      );
    }
    return _context.register(
      PathItem(
        location: r.location,
        summary: r.string('summary'),
        description: r.string('description'),
        operations: Map.unmodifiable(operations),
        additionalOperations:
            r.map('additionalOperations', _operationAt) ?? const {},
        servers: r.list('servers', server) ?? const [],
        parameters: r.list('parameters', parameter) ?? const [],
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  Operation? _operationAt(Object? raw, JsonPointer pointer) {
    final r = _context.reader(raw, pointer, 'An operation');
    return r == null ? null : _operation(r);
  }

  Operation _operation(ObjectReader r) {
    r.accept(const ['externalDocs', 'callbacks']);
    return _context.register(
      Operation(
        location: r.location,
        tags: r.strings('tags') ?? const [],
        summary: r.string('summary'),
        description: r.string('description'),
        operationId: r.string('operationId'),
        parameters: r.list('parameters', parameter) ?? const [],
        requestBody: switch (r.value('requestBody')) {
          (final raw,) => requestBody(raw, r.pointer.child('requestBody')),
          null => null,
        },
        responses:
            r.map('responses', response, skipExtensions: true) ?? const {},
        deprecated: r.boolean('deprecated') ?? false,
        security: r.list('security', securityRequirement),
        servers: r.list('servers', server) ?? const [],
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  Parameter _parameter(ObjectReader r) {
    final placement = r.requiredChoice(
      'in',
      ParameterLocation.values.asNameMap(),
    );
    if (placement == .querystring) {
      _context.note(.querystringParameter, r.pointer.child('in'));
    }
    return _context.register(
      Parameter(
        location: r.location,
        name: r.requiredString('name'),
        placement: placement,
        description: r.string('description'),
        required: r.boolean('required') ?? false,
        deprecated: r.boolean('deprecated') ?? false,
        allowEmptyValue: r.boolean('allowEmptyValue') ?? false,
        style: _style(r),
        explode: r.boolean('explode'),
        allowReserved: r.boolean('allowReserved') ?? false,
        schema: _schema(r, 'schema'),
        example: r.value('example'),
        examples: r.map('examples', example) ?? const {},
        content: r.map('content', mediaType) ?? const {},
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  RequestBody _requestBody(ObjectReader r) {
    if (!r.has('content')) {
      _context.report(
        .missingRequiredField,
        'The required field "content" is missing.',
        r.pointer,
      );
    }
    return _context.register(
      RequestBody(
        location: r.location,
        description: r.string('description'),
        content: r.map('content', mediaType) ?? const {},
        required: r.boolean('required') ?? false,
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  Response _response(ObjectReader r) {
    if (r.has('summary')) {
      _context.note(.responseSummary, r.pointer.child('summary'));
    }
    r.accept(const ['links']);
    return _context.register(
      Response(
        location: r.location,
        summary: r.string('summary'),
        description: r.string('description'),
        headers: r.map('headers', header) ?? const {},
        content: r.map('content', mediaType) ?? const {},
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  Header _header(ObjectReader r) {
    r.accept(const ['allowEmptyValue', 'allowReserved']);
    return _context.register(
      Header(
        location: r.location,
        description: r.string('description'),
        required: r.boolean('required') ?? false,
        deprecated: r.boolean('deprecated') ?? false,
        style: _style(r),
        explode: r.boolean('explode'),
        schema: _schema(r, 'schema'),
        example: r.value('example'),
        examples: r.map('examples', example) ?? const {},
        content: r.map('content', mediaType) ?? const {},
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  MediaType _mediaType(ObjectReader r) {
    if (r.has('itemSchema')) {
      _context.note(.itemSchema, r.pointer.child('itemSchema'));
    }
    for (final key in const ['prefixEncoding', 'itemEncoding']) {
      if (r.has(key)) _context.note(.sequentialEncoding, r.pointer.child(key));
    }
    return _context.register(
      MediaType(
        location: r.location,
        schema: _schema(r, 'schema'),
        itemSchema: _schema(r, 'itemSchema'),
        example: r.value('example'),
        examples: r.map('examples', example) ?? const {},
        encoding: r.map('encoding', _encodingAt) ?? const {},
        prefixEncoding: r.list('prefixEncoding', _encodingAt) ?? const [],
        itemEncoding: r.object('itemEncoding', _encoding),
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  Encoding? _encodingAt(Object? raw, JsonPointer pointer) {
    final r = _context.reader(raw, pointer, 'An encoding');
    return r == null ? null : _encoding(r);
  }

  Encoding _encoding(ObjectReader r) {
    r.accept(const ['encoding', 'prefixEncoding', 'itemEncoding']);
    return _context.register(
      Encoding(
        location: r.location,
        contentType: r.string('contentType'),
        headers: r.map('headers', header) ?? const {},
        style: _style(r),
        explode: r.boolean('explode'),
        allowReserved: r.boolean('allowReserved') ?? false,
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  Example _example(ObjectReader r) {
    for (final key in const ['dataValue', 'serializedValue']) {
      if (r.has(key)) _context.note(.exampleValues, r.pointer.child(key));
    }
    return _context.register(
      Example(
        location: r.location,
        summary: r.string('summary'),
        description: r.string('description'),
        value: r.value('value'),
        dataValue: r.value('dataValue'),
        serializedValue: r.string('serializedValue'),
        externalValue: r.string('externalValue'),
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  ServerVariable? _serverVariable(Object? raw, JsonPointer pointer) {
    final r = _context.reader(raw, pointer, 'A server variable');
    if (r == null) return null;
    return _context.register(
      ServerVariable(
        location: r.location,
        enumValues: r.strings('enum'),
        defaultValue: r.requiredString('default'),
        description: r.string('description'),
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  ParameterStyle? _style(ObjectReader r) {
    final style = r.choice('style', ParameterStyle.values.asNameMap());
    if (style == .cookie) _context.note(.cookieStyle, r.pointer.child('style'));
    return style;
  }

  Schema? _schema(ObjectReader r, String key) => switch (r.value(key)) {
    (final raw,) => _schemas.parse(raw, r.pointer.child(key)),
    null => null,
  };
}
```

- [ ] **Step 5: Переконатися, що тести проходять**

Run (з `packages/typed_openapi`): `dart test test/parse`
Expected: `+25: All tests passed!`

- [ ] **Step 6: Формат, аналізатор, увесь набір тестів**

Run (з `packages/typed_openapi`): `dart format --output=none --set-exit-if-changed lib test bin && dart test`
Expected: `Formatted 43 files (0 changed)`, `+99: All tests passed!`

Run (з кореня): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add packages/typed_openapi/lib/src/model/operation.dart packages/typed_openapi/lib/src/parse/operation_parser.dart packages/typed_openapi/test/parse/operation_parser_test.dart
git commit -m 'feat(typed_openapi): path items, operations and their parts' -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
```

---

### Task 7: Документ, components і схеми безпеки: `OpenApiParser`

**Files:**
- Create: `packages/typed_openapi/lib/src/model/document.dart`
- Create: `packages/typed_openapi/lib/src/model/security.dart`
- Create: `packages/typed_openapi/lib/src/parse/openapi_parser.dart`
- Create: `packages/typed_openapi/test/parse/openapi_parser_test.dart`

**Interfaces:**
- Consumes: `OperationParser`, моделі Task 6, `SchemaParser` (Task 5), `ParseContext`, `SpecIndex` (Task 4).
- Produces: `SecurityScheme` (`placement` — це `in`), `SecuritySchemeType`, `ApiKeyLocation`, `OAuthFlows`, `OAuthFlow`; `OpenApiDocument`, `Info`, `Tag`, `Components`; `final class OpenApiParser { factory OpenApiParser(DiagnosticBag, SpecDocument, SpecIndex); OpenApiDocument parse(OpenApiVersion? version); SpecNode? parseFragment(JsonPointer pointer, RefKind kind); }`.

Поведінка, яку закріплюють тести:
- Увесь документ: `info` з розширеннями, сервери зі змінними, глобальна `security`, теги, `paths` (без `x-`-ключів), `components` (схеми, схеми безпеки всіх типів з потоками OAuth). Документ реєструється в `SpecIndex`.
- Пропущені обов'язкові поля (`info.version`, `tag.name`, `name` для `apiKey`) і невідомі ключі (`host`) повідомляються, читання триває.
- Конструкції 3.1/3.2 рівня документа відмічаються; `$self` — ще й `TOA105`.
- `parseFragment(pointer, kind)` читає будь-який вузол сирого дерева як потрібний вид — так резолвер читатиме цілі `$ref` поза `components` і в інших файлах.

- [ ] **Step 1: Написати тест, що не проходить**

Створи `packages/typed_openapi/test/parse/openapi_parser_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/load/openapi_version.dart';
import 'package:typed_openapi/src/model/document.dart';
import 'package:typed_openapi/src/model/operation.dart';
import 'package:typed_openapi/src/model/schema.dart';
import 'package:typed_openapi/src/model/security.dart';
import 'package:typed_openapi/src/model/spec_node.dart';
import 'package:typed_openapi/src/parse/openapi_parser.dart';
import 'package:typed_openapi/src/parse/spec_feature.dart';

import '../helpers/spec_fixture.dart';

void main() {
  (OpenApiDocument, SpecFixture) parse(String yaml) {
    final fixture = SpecFixture(yaml);
    final document = OpenApiParser(
      fixture.diagnostics,
      fixture.document,
      fixture.index,
    ).parse(OpenApiVersion.v30);
    return (document, fixture);
  }

  T inline<T extends SpecNode>(RefOr<T>? value) => (value! as Inline<T>).value;

  test('reads a whole document', () {
    final (doc, fixture) = parse('''
openapi: 3.0.3
info: {title: Pets, version: "1.0", x-audience: public}
servers:
  - url: "https://{env}.example.com"
    variables:
      env: {default: api, enum: [api, staging]}
security:
  - bearer: []
tags:
  - {name: pets, description: Pets.}
paths:
  /pets:
    get: {responses: {"204": {description: No content}}}
  x-internal: true
components:
  schemas:
    Pet: {type: object}
  securitySchemes:
    bearer: {type: http, scheme: bearer, bearerFormat: JWT}
    key: {type: apiKey, name: X-Key, in: header}
    oauth:
      type: oauth2
      flows:
        clientCredentials:
          tokenUrl: https://example.com/token
          scopes: {read: Read}
''');
    expect(fixture.diagnostics.all, isEmpty);
    expect(doc.version, OpenApiVersion.v30);
    expect(doc.info!.title, 'Pets');
    expect(doc.info!.extensions, {'x-audience': 'public'});
    expect(doc.servers.single.variables['env']!.enumValues, ['api', 'staging']);
    expect(doc.security!.single.schemes, {'bearer': <String>[]});
    expect(doc.tags.single.name, 'pets');
    expect(doc.paths.keys, ['/pets']);
    expect(doc.extensions, isEmpty);
    final components = doc.components!;
    expect(components.schemas['Pet'], isA<SchemaObject>());
    final schemes = components.securitySchemes;
    expect(inline(schemes['bearer']).type, SecuritySchemeType.http);
    expect(inline(schemes['key']).placement, ApiKeyLocation.header);
    final flow = inline(schemes['oauth']).flows!.clientCredentials!;
    expect(flow.scopes, {'read': 'Read'});
    expect(fixture.index.nodes[doc.location], same(doc));
  });

  test('missing required fields and unknown keys are reported; reading '
      'goes on', () {
    final (doc, fixture) = parse('''
openapi: 3.0.3
info: {title: Pets}
paths: {}
host: example.com
tags: [{description: No name.}]
components:
  securitySchemes:
    key: {type: apiKey}
''');
    expect(doc.info!.title, 'Pets');
    expect(doc.tags.single.description, 'No name.');
    expect(fixture.codes, [
      DiagnosticCode.missingRequiredField,
      DiagnosticCode.missingRequiredField,
      DiagnosticCode.missingRequiredField,
      DiagnosticCode.unknownKey,
    ]);
    expect(fixture.pointers, [
      '#/info',
      '#/components/securitySchemes/key',
      '#/tags/0',
      '#/host',
    ]);
  });

  test('notes 3.1 and 3.2 document-level constructs', () {
    final (_, fixture) = parse(r'''
openapi: 3.0.3
$self: https://example.com/api.yaml
info: {title: Pets, version: "1", summary: Pets API.}
jsonSchemaDialect: https://spec.openapis.org/oas/3.1/dialect/base
webhooks: {}
tags: [{name: cats, parent: pets, kind: nav}]
components:
  pathItems: {}
  mediaTypes:
    Json: {schema: {type: object}}
  securitySchemes:
    tls: {type: mutualTLS}
''');
    expect(fixture.codes, [DiagnosticCode.refBaseIgnored]);
    expect(fixture.index.features.map((f) => f.feature).toSet(), {
      SpecFeature.self,
      SpecFeature.jsonSchemaDialect,
      SpecFeature.webhooks,
      SpecFeature.infoSummary,
      SpecFeature.tagHierarchy,
      SpecFeature.componentPathItems,
      SpecFeature.componentMediaTypes,
      SpecFeature.mutualTls,
    });
  });

  test('parseFragment reads a node as the kind a reference expects', () {
    final fixture = SpecFixture('''
openapi: 3.0.3
x-shared:
  limit: {name: limit, in: query, schema: {type: integer}}
''');
    final parser = OpenApiParser(
      fixture.diagnostics,
      fixture.document,
      fixture.index,
    );
    final at = JsonPointer.parse('#/x-shared/limit');
    final limit = parser.parseFragment(at, RefKind.parameter)! as Parameter;
    expect(limit.name, 'limit');
    expect(
      parser.parseFragment(at.child('schema'), RefKind.schema),
      isA<SchemaObject>(),
    );
    expect(fixture.diagnostics.all, isEmpty);
  });
}
```

- [ ] **Step 2: Переконатися, що тести падають**

Run (з `packages/typed_openapi`): `dart test test/parse`
Expected: FAIL, перша помилка — `cannot read 'lib/src/model/document.dart': No such file or directory`

- [ ] **Step 3: Створити `security.dart`**

Створи `packages/typed_openapi/lib/src/model/security.dart`:

```dart
import 'spec_node.dart';

/// The `type` of a security scheme.
enum SecuritySchemeType {
  /// An API key in a header, query parameter or cookie.
  apiKey,

  /// HTTP authentication, such as `bearer` or `basic`.
  http,

  /// Mutual TLS (OpenAPI 3.1).
  mutualTLS,

  /// OAuth 2.
  oauth2,

  /// OpenID Connect discovery.
  openIdConnect,
}

/// Where an API key is sent: the `in` field of an `apiKey` scheme.
enum ApiKeyLocation {
  /// A query parameter.
  query,

  /// A header.
  header,

  /// A cookie.
  cookie,
}

/// A Security Scheme Object.
final class SecurityScheme extends SpecNode {
  /// Creates a security scheme.
  const SecurityScheme({
    required super.location,
    this.type,
    this.description,
    this.name,
    this.placement,
    this.scheme,
    this.bearerFormat,
    this.flows,
    this.openIdConnectUrl,
    this.oauth2MetadataUrl,
    this.deprecated = false,
    super.extensions,
    super.unknownKeys,
  });

  /// `type`; required by the spec.
  final SecuritySchemeType? type;

  /// `description`.
  final String? description;

  /// `name` of the header, query parameter or cookie of an `apiKey`.
  final String? name;

  /// `in` of an `apiKey`.
  final ApiKeyLocation? placement;

  /// `scheme` of `http`, such as `bearer`.
  final String? scheme;

  /// `bearerFormat`.
  final String? bearerFormat;

  /// `flows` of `oauth2`.
  final OAuthFlows? flows;

  /// `openIdConnectUrl`.
  final String? openIdConnectUrl;

  /// `oauth2MetadataUrl` (OpenAPI 3.2).
  final String? oauth2MetadataUrl;

  /// `deprecated` (OpenAPI 3.2).
  final bool deprecated;
}

/// An OAuth Flows Object.
final class OAuthFlows extends SpecNode {
  /// Creates the flows.
  const OAuthFlows({
    required super.location,
    this.implicit,
    this.password,
    this.clientCredentials,
    this.authorizationCode,
    this.deviceAuthorization,
    super.extensions,
    super.unknownKeys,
  });

  /// `implicit`.
  final OAuthFlow? implicit;

  /// `password`.
  final OAuthFlow? password;

  /// `clientCredentials`.
  final OAuthFlow? clientCredentials;

  /// `authorizationCode`.
  final OAuthFlow? authorizationCode;

  /// `deviceAuthorization` (OpenAPI 3.2).
  final OAuthFlow? deviceAuthorization;
}

/// An OAuth Flow Object.
final class OAuthFlow extends SpecNode {
  /// Creates a flow.
  const OAuthFlow({
    required super.location,
    this.authorizationUrl,
    this.deviceAuthorizationUrl,
    this.tokenUrl,
    this.refreshUrl,
    this.scopes = const {},
    super.extensions,
    super.unknownKeys,
  });

  /// `authorizationUrl`.
  final String? authorizationUrl;

  /// `deviceAuthorizationUrl` (OpenAPI 3.2).
  final String? deviceAuthorizationUrl;

  /// `tokenUrl`.
  final String? tokenUrl;

  /// `refreshUrl`.
  final String? refreshUrl;

  /// `scopes`: scope name to description.
  final Map<String, String> scopes;
}
```

- [ ] **Step 4: Створити `document.dart`**

Створи `packages/typed_openapi/lib/src/model/document.dart`:

```dart
import '../load/openapi_version.dart';
import 'operation.dart';
import 'schema.dart';
import 'security.dart';
import 'spec_node.dart';

/// An OpenAPI document read into the typed model.
///
/// The model is a superset of OpenAPI 3.0, 3.1 and 3.2: it holds what any of
/// them can say, whatever [version] the document declares. Keys the model
/// does not type, such as `externalDocs` or `links`, stay in the
/// `SpecDocument` under the node's pointer.
final class OpenApiDocument extends SpecNode {
  /// Creates a document.
  const OpenApiDocument({
    required super.location,
    this.version,
    this.self,
    this.info,
    this.jsonSchemaDialect,
    this.servers = const [],
    this.paths = const {},
    this.webhooks = const {},
    this.components,
    this.security,
    this.tags = const [],
    super.extensions,
    super.unknownKeys,
  });

  /// The OpenAPI line the document declares, or null when unknown.
  final OpenApiVersion? version;

  /// `$self` (OpenAPI 3.2).
  final String? self;

  /// `info`; required by the spec.
  final Info? info;

  /// `jsonSchemaDialect` (OpenAPI 3.1).
  final String? jsonSchemaDialect;

  /// `servers`.
  final List<Server> servers;

  /// `paths` by path template, in document order; `x-` keys of the Paths
  /// Object are not included.
  final Map<String, RefOr<PathItem>> paths;

  /// `webhooks` (OpenAPI 3.1).
  final Map<String, RefOr<PathItem>> webhooks;

  /// `components`.
  final Components? components;

  /// `security`; null when the document does not set it.
  final List<SecurityRequirement>? security;

  /// `tags`.
  final List<Tag> tags;
}

/// An Info Object.
final class Info extends SpecNode {
  /// Creates an info object.
  const Info({
    required super.location,
    this.title,
    this.summary,
    this.description,
    this.version,
    super.extensions,
    super.unknownKeys,
  });

  /// `title`; required by the spec.
  final String? title;

  /// `summary` (OpenAPI 3.1).
  final String? summary;

  /// `description`.
  final String? description;

  /// `version` of the API (not of OpenAPI); required by the spec.
  final String? version;
}

/// A Tag Object.
final class Tag extends SpecNode {
  /// Creates a tag.
  const Tag({
    required super.location,
    this.name,
    this.summary,
    this.description,
    this.parent,
    this.kind,
    super.extensions,
    super.unknownKeys,
  });

  /// `name`; required by the spec.
  final String? name;

  /// `summary` (OpenAPI 3.2).
  final String? summary;

  /// `description`.
  final String? description;

  /// `parent` tag name (OpenAPI 3.2).
  final String? parent;

  /// `kind`, such as `nav` (OpenAPI 3.2).
  final String? kind;
}

/// A Components Object.
final class Components extends SpecNode {
  /// Creates the components.
  const Components({
    required super.location,
    this.schemas = const {},
    this.responses = const {},
    this.parameters = const {},
    this.examples = const {},
    this.requestBodies = const {},
    this.headers = const {},
    this.securitySchemes = const {},
    this.pathItems = const {},
    this.mediaTypes = const {},
    super.extensions,
    super.unknownKeys,
  });

  /// `schemas`.
  final Map<String, Schema> schemas;

  /// `responses`.
  final Map<String, RefOr<Response>> responses;

  /// `parameters`.
  final Map<String, RefOr<Parameter>> parameters;

  /// `examples`.
  final Map<String, RefOr<Example>> examples;

  /// `requestBodies`.
  final Map<String, RefOr<RequestBody>> requestBodies;

  /// `headers`.
  final Map<String, RefOr<Header>> headers;

  /// `securitySchemes`.
  final Map<String, RefOr<SecurityScheme>> securitySchemes;

  /// `pathItems` (OpenAPI 3.1).
  final Map<String, RefOr<PathItem>> pathItems;

  /// `mediaTypes` (OpenAPI 3.2).
  final Map<String, RefOr<MediaType>> mediaTypes;
}
```

- [ ] **Step 5: Створити `openapi_parser.dart`**

Створи `packages/typed_openapi/lib/src/parse/openapi_parser.dart`:

```dart
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/json_pointer.dart';
import '../load/openapi_version.dart';
import '../load/spec_document.dart';
import '../model/document.dart';
import '../model/security.dart';
import '../model/spec_node.dart';
import 'object_reader.dart';
import 'operation_parser.dart';
import 'parse_context.dart';
import 'schema_parser.dart';
import 'spec_feature.dart';

/// Reads a [SpecDocument] into the typed model.
///
/// Wrong JSON types, missing required fields and unknown keys are reported
/// to the [DiagnosticBag] and the rest of the document is still read. Every
/// node, `$ref` and version-specific construct goes into the [SpecIndex]
/// given to the constructor, which several parsers of one run share.
final class OpenApiParser {
  /// Creates a parser for [document].
  factory OpenApiParser(
    DiagnosticBag diagnostics,
    SpecDocument document,
    SpecIndex index,
  ) {
    final context = ParseContext(diagnostics, document, index);
    final schemas = SchemaParser(context);
    return OpenApiParser._(
      context,
      schemas,
      OperationParser(context, schemas),
    );
  }

  OpenApiParser._(this._context, this._schemas, this._operations);

  final ParseContext _context;
  final SchemaParser _schemas;
  final OperationParser _operations;

  /// Reads the whole document, which declares [version].
  OpenApiDocument parse(OpenApiVersion? version) {
    final r = ObjectReader(_context, _context.document.root, .root);
    final at = r.pointer;
    r.accept(const ['openapi', 'externalDocs']);
    if (r.has(r'$self')) {
      _context.note(.self, at.child(r'$self'));
      _context.report(
        .refBaseIgnored,
        r'"$self" changes the base URI of "$ref"s; they are resolved '
        'against the file location instead.',
        at.child(r'$self'),
      );
    }
    for (final (key, feature) in const [
      ('jsonSchemaDialect', SpecFeature.jsonSchemaDialect),
      ('webhooks', SpecFeature.webhooks),
    ]) {
      if (r.has(key)) _context.note(feature, at.child(key));
    }
    return _context.register(
      OpenApiDocument(
        location: r.location,
        version: version,
        self: r.string(r'$self'),
        info: r.requiredObject('info', _info),
        jsonSchemaDialect: r.string('jsonSchemaDialect'),
        servers: r.list('servers', _operations.server) ?? const [],
        paths:
            r.map('paths', _operations.pathItem, skipExtensions: true) ??
            const {},
        webhooks: r.map('webhooks', _operations.pathItem) ?? const {},
        components: r.object('components', _components),
        security: r.list('security', _operations.securityRequirement),
        tags: r.list('tags', _tag) ?? const [],
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  /// Reads the node at [pointer] as a [kind] node, for a `$ref` that points
  /// there; null after reporting when the node has the wrong shape.
  SpecNode? parseFragment(JsonPointer pointer, RefKind kind) {
    final raw = _context.document.valueAt(pointer)?.$1;
    final RefOr<SpecNode>? node = switch (kind) {
      .schema => null,
      .response => _operations.response(raw, pointer),
      .parameter => _operations.parameter(raw, pointer),
      .example => _operations.example(raw, pointer),
      .requestBody => _operations.requestBody(raw, pointer),
      .header => _operations.header(raw, pointer),
      .securityScheme => _securityScheme(raw, pointer),
      .pathItem => _operations.pathItem(raw, pointer),
      .mediaType => _operations.mediaType(raw, pointer),
    };
    return switch (node) {
      Ref() => node,
      Inline(:final value) => value,
      null => kind == .schema ? _schemas.parse(raw, pointer) : null,
    };
  }

  Info _info(ObjectReader r) {
    if (r.has('summary')) {
      _context.note(.infoSummary, r.pointer.child('summary'));
    }
    r.accept(const ['termsOfService', 'contact', 'license']);
    return _context.register(
      Info(
        location: r.location,
        title: r.requiredString('title'),
        summary: r.string('summary'),
        description: r.string('description'),
        version: r.requiredString('version'),
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  Tag? _tag(Object? raw, JsonPointer pointer) {
    final r = _context.reader(raw, pointer, 'A tag');
    if (r == null) return null;
    for (final key in const ['summary', 'parent', 'kind']) {
      if (r.has(key)) _context.note(.tagHierarchy, pointer.child(key));
    }
    r.accept(const ['externalDocs']);
    return _context.register(
      Tag(
        location: r.location,
        name: r.requiredString('name'),
        summary: r.string('summary'),
        description: r.string('description'),
        parent: r.string('parent'),
        kind: r.string('kind'),
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  Components _components(ObjectReader r) {
    for (final (key, feature) in const [
      ('pathItems', SpecFeature.componentPathItems),
      ('mediaTypes', SpecFeature.componentMediaTypes),
    ]) {
      if (r.has(key)) _context.note(feature, r.pointer.child(key));
    }
    r.accept(const ['links', 'callbacks']);
    return _context.register(
      Components(
        location: r.location,
        schemas: r.map('schemas', _schemas.parse) ?? const {},
        responses: r.map('responses', _operations.response) ?? const {},
        parameters: r.map('parameters', _operations.parameter) ?? const {},
        examples: r.map('examples', _operations.example) ?? const {},
        requestBodies:
            r.map('requestBodies', _operations.requestBody) ?? const {},
        headers: r.map('headers', _operations.header) ?? const {},
        securitySchemes: r.map('securitySchemes', _securityScheme) ?? const {},
        pathItems: r.map('pathItems', _operations.pathItem) ?? const {},
        mediaTypes: r.map('mediaTypes', _operations.mediaType) ?? const {},
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  RefOr<SecurityScheme>? _securityScheme(Object? raw, JsonPointer pointer) =>
      _context.refOr(raw, pointer, .securityScheme, (r) {
        final type = r.requiredChoice(
          'type',
          SecuritySchemeType.values.asNameMap(),
        );
        if (type == .mutualTLS) {
          _context.note(.mutualTls, r.pointer.child('type'));
        }
        for (final key in const ['deprecated', 'oauth2MetadataUrl']) {
          if (r.has(key)) {
            _context.note(.securitySchemeExtras, r.pointer.child(key));
          }
        }
        String? field(String key, SecuritySchemeType requiredFor) =>
            type == requiredFor ? r.requiredString(key) : r.string(key);
        return _context.register(
          SecurityScheme(
            location: r.location,
            type: type,
            description: r.string('description'),
            name: field('name', .apiKey),
            placement: r.choice('in', ApiKeyLocation.values.asNameMap()),
            scheme: field('scheme', .http),
            bearerFormat: r.string('bearerFormat'),
            flows: type == .oauth2
                ? r.requiredObject('flows', _flows)
                : r.object('flows', _flows),
            openIdConnectUrl: field('openIdConnectUrl', .openIdConnect),
            oauth2MetadataUrl: r.string('oauth2MetadataUrl'),
            deprecated: r.boolean('deprecated') ?? false,
            extensions: r.extensions,
            unknownKeys: r.unknownKeys(),
          ),
        );
      });

  OAuthFlows _flows(ObjectReader r) {
    if (r.has('deviceAuthorization')) {
      _context.note(
        .deviceAuthorization,
        r.pointer.child('deviceAuthorization'),
      );
    }
    return _context.register(
      OAuthFlows(
        location: r.location,
        implicit: r.object('implicit', _flow),
        password: r.object('password', _flow),
        clientCredentials: r.object('clientCredentials', _flow),
        authorizationCode: r.object('authorizationCode', _flow),
        deviceAuthorization: r.object('deviceAuthorization', _flow),
        extensions: r.extensions,
        unknownKeys: r.unknownKeys(),
      ),
    );
  }

  OAuthFlow _flow(ObjectReader r) => _context.register(
    OAuthFlow(
      location: r.location,
      authorizationUrl: r.string('authorizationUrl'),
      deviceAuthorizationUrl: r.string('deviceAuthorizationUrl'),
      tokenUrl: r.string('tokenUrl'),
      refreshUrl: r.string('refreshUrl'),
      scopes: r.stringMap('scopes') ?? const {},
      extensions: r.extensions,
      unknownKeys: r.unknownKeys(),
    ),
  );
}
```

- [ ] **Step 6: Переконатися, що тести проходять**

Run (з `packages/typed_openapi`): `dart test test/parse`
Expected: `+29: All tests passed!`

- [ ] **Step 7: Формат, аналізатор, увесь набір тестів**

Run (з `packages/typed_openapi`): `dart format --output=none --set-exit-if-changed lib test bin && dart test`
Expected: `Formatted 47 files (0 changed)`, `+103: All tests passed!`

Run (з кореня): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add packages/typed_openapi/lib/src/model/document.dart packages/typed_openapi/lib/src/model/security.dart packages/typed_openapi/lib/src/parse/openapi_parser.dart packages/typed_openapi/test/parse/openapi_parser_test.dart
git commit -m 'feat(typed_openapi): document, components and security schemes' -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
```

---

### Task 8: Діалект за вмістом: `DialectChecker` (TOA020–TOA022)

**Files:**
- Create: `packages/typed_openapi/lib/src/parse/dialect_checker.dart`
- Create: `packages/typed_openapi/test/parse/dialect_checker_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`
- Modify: `packages/typed_openapi/lib/src/load/openapi_version.dart`

**Interfaces:**
- Consumes: `FeatureUse`, `SpecFeature` (Task 4), `OpenApiParser` (Task 7) — у тестах.
- Produces: `OpenApiVersion.label` (`'3.0'`, `'3.1'`, `'3.2'`); `final class DialectChecker { const DialectChecker(DiagnosticBag); void check(List<FeatureUse> uses, OpenApiVersion version); }`; коди `openApi31InOpenApi30` (TOA020), `nullableAfterOpenApi30` (TOA021), `openApi32InOlder` (TOA022).

Поведінка, яку закріплюють тести:
- 3.1-конструкції в документі 3.0 — `TOA020` warning, по одному на конструкцію, у місці першого використання; повідомлення каже, скільки місць.
- `nullable` у 3.1 і 3.2 — `TOA021` warning з позицією.
- 3.2-конструкції в 3.0/3.1 — `TOA022` info; у 3.2 — нічого.

- [ ] **Step 1: Написати тест, що не проходить**

Створи `packages/typed_openapi/test/parse/dialect_checker_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/load/openapi_version.dart';
import 'package:typed_openapi/src/parse/dialect_checker.dart';
import 'package:typed_openapi/src/parse/openapi_parser.dart';

import '../helpers/spec_fixture.dart';

void main() {
  DiagnosticBag check(String yaml, OpenApiVersion version) {
    final fixture = SpecFixture(yaml);
    OpenApiParser(
      fixture.diagnostics,
      fixture.document,
      fixture.index,
    ).parse(version);
    final bag = DiagnosticBag();
    DialectChecker(bag).check(fixture.index.features, version);
    return bag;
  }

  const schemas = '''
info: {title: t, version: "1"}
components:
  schemas:
    A: {type: [string, "null"]}
    B: {type: string, nullable: true}
    C: {const: c}
    D: {const: d}
''';

  test('3.1 constructs in a 3.0 document: one warning per construct', () {
    final bag = check(schemas, .v30);
    expect(bag.all.map((d) => (d.code, d.pointer?.value)), [
      (DiagnosticCode.openApi31InOpenApi30, '#/components/schemas/A/type'),
      (DiagnosticCode.openApi31InOpenApi30, '#/components/schemas/A/type/1'),
      (DiagnosticCode.openApi31InOpenApi30, '#/components/schemas/C/const'),
    ]);
    expect(bag.all.first.severity, Severity.warning);
    expect(
      bag.all.last.message,
      '"const" is OpenAPI 3.1 (JSON Schema 2020-12), but the document '
      'declares 3.0; it is read as 3.1. It is used in 2 places; this is the '
      'first.',
    );
  });

  test('nullable in a 3.1 document is a warning', () {
    final bag = check(schemas, .v31);
    final d = bag.all.single;
    expect(d.code, DiagnosticCode.nullableAfterOpenApi30);
    expect(d.pointer?.value, '#/components/schemas/B/nullable');
    expect(d.line, 5);
  });

  test('3.2 constructs in older documents are infos', () {
    const yaml = '''
info: {title: t, version: "1"}
paths:
  /events:
    get:
      responses:
        "200":
          description: Events.
          content:
            text/event-stream:
              itemSchema: {type: object}
''';
    final bag = check(yaml, .v31);
    expect(bag.all.single.code, DiagnosticCode.openApi32InOlder);
    expect(bag.all.single.severity, Severity.info);
    expect(check(yaml, .v32).all, isEmpty);
  });

  test('a 3.2 document may use everything but nullable', () {
    final bag = check(schemas, .v32);
    expect(bag.all.single.code, DiagnosticCode.nullableAfterOpenApi30);
  });
}
```

- [ ] **Step 2: Переконатися, що тести падають**

Run (з `packages/typed_openapi`): `dart test test/parse`
Expected: FAIL, перша помилка — `cannot read 'lib/src/parse/dialect_checker.dart': No such file or directory`

- [ ] **Step 3: Додати коди в каталог**

У `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart` після фрагмента:

```dart
    'openapi-version-not-string',
    .warning,
  ),
```

встав:

```dart
  /// A 3.0 document uses an OpenAPI 3.1 or JSON Schema 2020-12 construct;
  /// it is read as 3.1.
  openApi31InOpenApi30('TOA020', 'openapi-3-1-in-3-0', .warning),

  /// A 3.1 or later document uses `nullable`, which only 3.0 defines; it is
  /// read as in 3.0.
  nullableAfterOpenApi30('TOA021', 'nullable-after-3-0', .warning),

  /// A document older than 3.2 uses an OpenAPI 3.2 construct; it is read
  /// anyway.
  openApi32InOlder('TOA022', 'openapi-3-2-in-older', .info),
```

- [ ] **Step 4: Змінити `openapi_version.dart`**

У `packages/typed_openapi/lib/src/load/openapi_version.dart` заміни:

```dart
enum OpenApiVersion {
  /// OpenAPI 3.0.x.
  v30,

  /// OpenAPI 3.1.x.
  v31,

  /// OpenAPI 3.2.x.
  v32,
}
```

на:

```dart
enum OpenApiVersion {
  /// OpenAPI 3.0.x.
  v30('3.0'),

  /// OpenAPI 3.1.x.
  v31('3.1'),

  /// OpenAPI 3.2.x.
  v32('3.2');

  const OpenApiVersion(this.label);

  /// The version as people write it, such as `3.1`.
  final String label;
}
```

- [ ] **Step 5: Створити `dialect_checker.dart`**

Створи `packages/typed_openapi/lib/src/parse/dialect_checker.dart`:

```dart
import '../diagnostics/diagnostic_bag.dart';
import '../load/openapi_version.dart';
import 'parse_context.dart';
import 'spec_feature.dart';

/// Reports constructs that the version a document declares does not have.
///
/// The dialect of a document is decided by its content: the parser reads
/// every construct, and this check says where the content and the declared
/// `openapi` version disagree. Each construct is reported once, at its first
/// use, with the number of uses.
final class DialectChecker {
  /// Creates a checker that reports to [_diagnostics].
  const DialectChecker(this._diagnostics);

  final DiagnosticBag _diagnostics;

  /// Reports the [uses] that [version] does not define.
  void check(List<FeatureUse> uses, OpenApiVersion version) {
    final byFeature = <SpecFeature, List<FeatureUse>>{};
    for (final use in uses) {
      byFeature.putIfAbsent(use.feature, () => []).add(use);
    }
    for (final MapEntry(key: feature, value: found) in byFeature.entries) {
      final first = found.first;
      final count = found.length == 1
          ? ''
          : ' It is used in ${found.length} places; this is the first.';
      final declared = 'the document declares ${version.label}';
      final since = feature.since;
      final until = feature.until;
      if (since != null && version.index < since.index) {
        final is31 = since == .v31;
        _diagnostics.report(
          is31 ? .openApi31InOpenApi30 : .openApi32InOlder,
          is31
              ? '${feature.label} is OpenAPI 3.1 (JSON Schema 2020-12), but '
                    '$declared; it is read as 3.1.$count'
              : '${feature.label} is OpenAPI 3.2, but $declared; it is read '
                    'anyway.$count',
          file: first.file,
          pointer: first.pointer,
          span: first.span,
          fix:
              'Declare "openapi: ${since.label}.0" if the backend emits '
              '${since.label}; otherwise remove the construct.',
        );
      } else if (until != null && version.index >= until.index) {
        _diagnostics.report(
          .nullableAfterOpenApi30,
          '${feature.label} exists only in OpenAPI 3.0, but $declared; it '
          'is read as in 3.0.$count',
          file: first.file,
          pointer: first.pointer,
          span: first.span,
          fix: 'Write type: [<type>, "null"] instead of nullable: true.',
        );
      }
    }
  }
}
```

- [ ] **Step 6: Переконатися, що тести проходять**

Run (з `packages/typed_openapi`): `dart test test/parse`
Expected: `+33: All tests passed!`

- [ ] **Step 7: Формат, аналізатор, увесь набір тестів**

Run (з `packages/typed_openapi`): `dart format --output=none --set-exit-if-changed lib test bin && dart test`
Expected: `Formatted 49 files (0 changed)`, `+107: All tests passed!`

Run (з кореня): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart packages/typed_openapi/lib/src/load/openapi_version.dart packages/typed_openapi/lib/src/parse/dialect_checker.dart packages/typed_openapi/test/parse/dialect_checker_test.dart
git commit -m 'feat(typed_openapi): detect the schema dialect by content' -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
```

---

### Task 9: Розбір значення `$ref`: `RefTarget` (TOA100, TOA102)

**Files:**
- Create: `packages/typed_openapi/lib/src/resolve/ref_target.dart`
- Create: `packages/typed_openapi/test/resolve/ref_target_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`

**Interfaces:**
- Consumes: `SpecLocation` (Task 3), `JsonPointer`, `DiagnosticCode`.
- Produces: `sealed class RefTarget { factory RefTarget.parse(String ref, Uri base); }`, `ResolvableRef(SpecLocation location)`, `BrokenRef(DiagnosticCode code, String reason, {String? fix})`; коди `invalidRef` (TOA100), `remoteRef` (TOA102).

Поведінка, яку закріплюють тести:
- Локальний pointer лишається в тому самому документі; відносний файл розв'язується від URI документа; без фрагмента — корінь файлу.
- Фрагмент percent-декодується (`%7Bid%7D` → `{id}`), екранування `~0`/`~1` зберігаються в pointer.
- `https:`, `urn:` — `TOA102`. Порожній рядок, `#/components/schemas/`, `#/`, `#/components/schemas`, `#/components`, `#Pet`, поганий `%`, поганий `~`, невалідний URI — `TOA100` з поясненням.

- [ ] **Step 1: Написати тест, що не проходить**

Створи `packages/typed_openapi/test/resolve/ref_target_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/resolve/ref_target.dart';

void main() {
  final base = Uri.parse('file:///project/specs/api.yaml');

  String target(String ref) => switch (RefTarget.parse(ref, base)) {
    ResolvableRef(:final location) => '$location',
    BrokenRef(:final code) => code.id,
  };

  test('a local pointer stays in the same document', () {
    expect(
      target('#/components/schemas/Pet'),
      'file:///project/specs/api.yaml#/components/schemas/Pet',
    );
  });

  test('a relative file resolves against the document', () {
    expect(
      target('../common/errors.yaml#/Error'),
      'file:///project/common/errors.yaml#/Error',
    );
    expect(target('./pet.yaml'), 'file:///project/specs/pet.yaml#');
  });

  test('the fragment is percent-decoded and keeps ~ escapes', () {
    expect(
      target('#/paths/~1pets~1%7Bid%7D/get'),
      'file:///project/specs/api.yaml#/paths/~1pets~1{id}/get',
    );
  });

  test('remote documents are not read', () {
    expect(target('https://example.com/api.yaml#/A'), 'TOA102');
    expect(target('urn:example:pet'), 'TOA102');
  });

  test('empty, truncated and malformed references are invalid', () {
    for (final ref in [
      '',
      '#/components/schemas/',
      '#/',
      '#/components/schemas',
      '#/components',
      '#Pet',
      '#/a/%zz',
      '#/a~2b',
      'http://[bad#/a',
    ]) {
      expect(target(ref), 'TOA100', reason: ref);
    }
  });

  test('a broken reference says why', () {
    final broken = RefTarget.parse('#/components/schemas/', base) as BrokenRef;
    expect(broken.code, DiagnosticCode.invalidRef);
    expect(
      broken.reason,
      '"#/components/schemas/" ends with "/", so the name of the target is '
      'missing.',
    );
  });
}
```

- [ ] **Step 2: Переконатися, що тести падають**

Run (з `packages/typed_openapi`): `dart test test/resolve`
Expected: FAIL, перша помилка — `cannot read 'lib/src/resolve/ref_target.dart': No such file or directory`

- [ ] **Step 3: Додати коди в каталог**

У `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart` перед фрагментом:

```dart
  /// `$id` or `$self` would change the base URI of `$ref`s; this tool
```

встав:

```dart
  /// A `$ref` is empty, truncated or not a URI with a JSON pointer.
  invalidRef('TOA100', 'invalid-ref', .error),

  /// A `$ref` points to a remote URL; only local files are read.
  remoteRef('TOA102', 'remote-ref', .error),
```

- [ ] **Step 4: Створити `ref_target.dart`**

Створи `packages/typed_openapi/lib/src/resolve/ref_target.dart`:

```dart
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/json_pointer.dart';
import '../model/spec_node.dart';

/// What a `$ref` value points to, or why it cannot be followed.
sealed class RefTarget {
  const RefTarget();

  /// Reads [ref], written in the document at [base].
  ///
  /// The part before `#` is a URI relative to [base]; the fragment is a JSON
  /// pointer, percent-decoded. Remote URIs, plain-name fragments (`#foo`)
  /// and pointers that stop at a components section or end with `/` cannot
  /// be followed.
  factory RefTarget.parse(String ref, Uri base) {
    if (ref.isEmpty) {
      return const BrokenRef(.invalidRef, r'The "$ref" is empty.');
    }
    final hash = ref.indexOf('#');
    final address = hash < 0 ? ref : ref.substring(0, hash);
    final fragment = hash < 0 ? '' : ref.substring(hash + 1);
    final Uri document;
    if (address.isEmpty) {
      document = base;
    } else {
      final Uri parsed;
      try {
        parsed = Uri.parse(address);
      } on FormatException {
        return BrokenRef(.invalidRef, '"$ref" is not a valid URI.');
      }
      if (parsed.hasScheme && parsed.scheme != 'file') {
        return BrokenRef(
          .remoteRef,
          '"$ref" points to a remote document; only local files are read.',
          fix:
              'Save the document next to the spec and refer to it by a '
              'relative path.',
        );
      }
      document = base.resolveUri(parsed).removeFragment();
    }
    final pointer = _pointer(fragment);
    if (pointer == null) {
      return BrokenRef(
        .invalidRef,
        '"$ref" does not end with a JSON pointer such as '
        '"#/components/schemas/Name".',
        fix: r'Plain-name fragments ($anchor) are not supported.',
      );
    }
    final tokens = pointer.tokens;
    if (tokens.isNotEmpty && tokens.last.isEmpty) {
      return BrokenRef(
        .invalidRef,
        '"$ref" ends with "/", so the name of the target is missing.',
        fix:
            'Fix the code that writes the spec; in NestJS this usually '
            'means a circular import made a DTO type undefined.',
      );
    }
    if (tokens.length <= 2 && tokens.firstOrNull == 'components') {
      return BrokenRef(
        .invalidRef,
        '"$ref" points at a whole components section, not at one entry.',
      );
    }
    return ResolvableRef(SpecLocation(document, pointer));
  }

  static final _badPercent = RegExp('%(?![0-9A-Fa-f]{2})');
  static final _badTilde = RegExp('~(?![01])');

  static JsonPointer? _pointer(String fragment) {
    if (fragment.isEmpty) return JsonPointer.root;
    if (!fragment.startsWith('/') || _badPercent.hasMatch(fragment)) {
      return null;
    }
    final String decoded;
    try {
      decoded = fragment.contains('%')
          ? Uri.decodeComponent(fragment)
          : fragment;
    } on FormatException {
      return null;
    }
    if (_badTilde.hasMatch(decoded)) return null;
    return JsonPointer.parse('#$decoded');
  }
}

/// A `$ref` to a node in a local file.
final class ResolvableRef extends RefTarget {
  /// Creates a target at [location].
  const ResolvableRef(this.location);

  /// The file and pointer the `$ref` names.
  final SpecLocation location;
}

/// A `$ref` that cannot be followed.
final class BrokenRef extends RefTarget {
  /// Creates a broken target; [reason] becomes the diagnostic message.
  const BrokenRef(this.code, this.reason, {this.fix});

  /// The diagnostic code to report.
  final DiagnosticCode code;

  /// Why the `$ref` cannot be followed.
  final String reason;

  /// How to fix the `$ref`.
  final String? fix;
}
```

- [ ] **Step 5: Переконатися, що тести проходять**

Run (з `packages/typed_openapi`): `dart test test/resolve`
Expected: `+6: All tests passed!`

- [ ] **Step 6: Формат, аналізатор, увесь набір тестів**

Run (з `packages/typed_openapi`): `dart format --output=none --set-exit-if-changed lib test bin && dart test`
Expected: `Formatted 51 files (0 changed)`, `+113: All tests passed!`

Run (з кореня): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart packages/typed_openapi/lib/src/resolve/ref_target.dart packages/typed_openapi/test/resolve/ref_target_test.dart
git commit -m 'feat(typed_openapi): parse $ref values' -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
```

---

### Task 10: Резолвер `$ref`: локальні та файлові посилання (TOA101, TOA104)

**Files:**
- Create: `packages/typed_openapi/lib/src/resolve/spec_documents.dart`
- Create: `packages/typed_openapi/lib/src/resolve/spec_model.dart`
- Create: `packages/typed_openapi/lib/src/resolve/ref_resolver.dart`
- Create: `packages/typed_openapi/test/resolve/ref_resolver_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`

**Interfaces:**
- Consumes: `RefTarget` (Task 9), `OpenApiParser.parseFragment` (Task 7), `SpecIndex`, `RefUse` (Task 4), `SpecLoader`, `SpecDocument.valueAt` (Task 1), усі моделі.
- Produces: `final class SpecDocuments { SpecDocuments(SpecLoader, SpecDocument root); SpecDocument? operator [](Uri uri); String displayPath(Uri uri); }`; `final class SpecModel { SpecModel({required OpenApiDocument document, required Map<SpecLocation, SpecNode> nodes, required Map<SpecLocation, SpecLocation> targets}); nodeAt, targetOf, resolve<T>, resolveSchema }`; `final class RefResolver { const RefResolver(DiagnosticBag); SpecModel resolve(OpenApiDocument document, SpecIndex index, SpecDocuments documents); }`; коди `unresolvedRef` (TOA101), `refKindMismatch` (TOA104).

Поведінка, яку закріплюють тести:
- Локальні посилання розв'язуються, зокрема через ланцюжок аліасів у `components`; `SpecModel.resolve`/`resolveSchema` повертають кінцевий вузол, `targetOf` — безпосередню ціль.
- Рекурсивна схема — без діагностик, `resolveSchema` повертає саму схему.
- Висяче посилання — `TOA101` у pointer `…/$ref` з позицією; `resolveSchema` → `null`.
- `#/components/schemas/` — `TOA100` у місці запису.
- Посилання в інші файли: ціль ідентифікується файлом + pointer (однаковий pointer у двох файлах — різні вузли), `$ref` усередині іншого файлу розв'язуються від нього, діагностики там названі `specs/common/errors.yaml`.
- Відсутній файл — `TOA101` з назвою файлу; URL — `TOA102`; файл, на який посилаються двічі, читається (і повідомляється його синтаксична помилка) один раз.
- Параметр → схема — `TOA104`; ціль поза `components` (`#/x-shared/limit`) читається як очікуваний вид і реєструється.

- [ ] **Step 1: Написати тест, що не проходить**

Створи `packages/typed_openapi/test/resolve/ref_resolver_test.dart`:

```dart
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/model/schema.dart';
import 'package:typed_openapi/src/parse/openapi_parser.dart';
import 'package:typed_openapi/src/parse/parse_context.dart';
import 'package:typed_openapi/src/resolve/ref_resolver.dart';
import 'package:typed_openapi/src/resolve/spec_documents.dart';
import 'package:typed_openapi/src/resolve/spec_model.dart';

import '../helpers/temp_dir.dart';

void main() {
  late TempDir dir;

  setUp(() => dir = TempDir());

  (SpecModel, DiagnosticBag) resolve(String rootFile) {
    final bag = DiagnosticBag();
    final loader = SpecLoader(bag);
    final root = loader.load(
      p.join(dir.path, rootFile),
      displayPath: rootFile,
    )!;
    final index = SpecIndex();
    final document = OpenApiParser(bag, root, index).parse(.v31);
    final model = RefResolver(
      bag,
    ).resolve(document, index, SpecDocuments(loader, root));
    return (model, bag);
  }

  const info = 'openapi: 3.1.0\ninfo: {title: t, version: "1"}';

  test('resolves local references, through aliases', () {
    dir.write('api.yaml', '''
$info
paths:
  /pets:
    get:
      parameters: [{\$ref: "#/components/parameters/Limit"}]
      responses:
        "200":
          description: OK
          content:
            application/json:
              schema: {\$ref: "#/components/schemas/Pets"}
components:
  parameters:
    Limit: {\$ref: "#/components/parameters/PageSize"}
    PageSize: {name: size, in: query}
  schemas:
    Pets: {type: array, items: {\$ref: "#/components/schemas/Pet"}}
    Pet: {type: object}
''');
    final (model, bag) = resolve('api.yaml');
    expect(bag.all, isEmpty);
    final get = model.resolve(model.document.paths['/pets']!)!;
    final parameter = model.resolve(get.operations['get']!.parameters.single);
    expect(parameter!.name, 'size');
    final pets = model.document.components!.schemas['Pets']! as SchemaObject;
    final pet = model.resolveSchema(pets.items!)! as SchemaObject;
    expect(pet.pointer.value, '#/components/schemas/Pet');
    expect(model.targetOf(pets.items!.location), pet.location);
  });

  test('a recursive schema is not a problem', () {
    dir.write('api.yaml', '''
$info
components:
  schemas:
    Node:
      type: object
      properties:
        children: {type: array, items: {\$ref: "#/components/schemas/Node"}}
''');
    final (model, bag) = resolve('api.yaml');
    expect(bag.all, isEmpty);
    final node = model.document.components!.schemas['Node']! as SchemaObject;
    final children = node.properties['children']! as SchemaObject;
    expect(model.resolveSchema(children.items!), same(node));
  });

  test('a reference to nothing is unresolved', () {
    dir.write('api.yaml', '''
$info
components:
  schemas:
    Owner: {\$ref: "#/components/schemas/Person"}
''');
    final (model, bag) = resolve('api.yaml');
    final d = bag.all.single;
    expect(d.code, DiagnosticCode.unresolvedRef);
    expect(d.pointer?.value, r'#/components/schemas/Owner/$ref');
    expect(d.line, 5);
    final owner = model.document.components!.schemas['Owner']!;
    expect(model.resolveSchema(owner), isNull);
  });

  test('an empty name is invalid and reported where it is written', () {
    dir.write('api.yaml', '''
$info
components:
  schemas:
    Owner:
      properties:
        pet: {\$ref: "#/components/schemas/"}
''');
    final (_, bag) = resolve('api.yaml');
    final d = bag.all.single;
    expect(d.code, DiagnosticCode.invalidRef);
    expect(d.pointer?.value, r'#/components/schemas/Owner/properties/pet/$ref');
    expect(d.file, 'api.yaml');
  });

  test('follows references into other files, keyed by file and pointer', () {
    dir.write('specs/api.yaml', '''
$info
components:
  schemas:
    Error: {\$ref: "common/errors.yaml#/components/schemas/Error"}
''');
    dir.write('specs/common/errors.yaml', r'''
components:
  schemas:
    Error:
      type: object
      properties:
        code: {$ref: "codes.yaml#/Code"}
        extra: {$ref: "#/components/schemas/Missing"}
''');
    dir.write('specs/common/codes.yaml', 'Code: {type: string}\n');
    final (model, bag) = resolve('specs/api.yaml');
    final local = model.document.components!.schemas['Error']!;
    final remote = model.resolveSchema(local)! as SchemaObject;
    expect(remote.location, isNot(local.location));
    expect(remote.pointer, local.pointer);
    expect(
      remote.location.document,
      p.toUri(p.join(dir.path, 'specs', 'common', 'errors.yaml')),
    );
    final code = model.resolveSchema(remote.properties['code']!)!;
    expect((code as SchemaObject).types, [SchemaType.string]);
    final d = bag.all.single;
    expect(d.code, DiagnosticCode.unresolvedRef);
    expect(d.file, p.join('specs', 'common', 'errors.yaml'));
    expect(d.line, 7);
  });

  test('a missing file and a remote URL are reported', () {
    dir.write('api.yaml', '''
$info
components:
  schemas:
    A: {\$ref: "missing.yaml#/A"}
    B: {\$ref: "https://example.com/b.yaml"}
''');
    final (_, bag) = resolve('api.yaml');
    expect(bag.all.map((d) => d.code), [
      DiagnosticCode.unresolvedRef,
      DiagnosticCode.remoteRef,
    ]);
    expect(
      bag.all.first.message,
      '"missing.yaml#/A" points to missing.yaml, which does not exist or '
      'cannot be read.',
    );
  });

  test('a file referenced many times is read once', () {
    dir.write('api.yaml', '''
$info
components:
  schemas:
    A: {\$ref: "broken.yaml#/A"}
    B: {\$ref: "broken.yaml#/B"}
''');
    dir.write('broken.yaml', 'A: [\n');
    final (_, bag) = resolve('api.yaml');
    expect(bag.all.map((d) => (d.code, d.file)), [
      (DiagnosticCode.parseError, 'broken.yaml'),
      (DiagnosticCode.unresolvedRef, 'api.yaml'),
      (DiagnosticCode.unresolvedRef, 'api.yaml'),
    ]);
  });

  test('a reference to a node of another kind is reported', () {
    dir.write('api.yaml', '''
$info
paths:
  /a:
    get:
      parameters: [{\$ref: "#/components/schemas/Limit"}]
components:
  schemas:
    Limit: {type: integer}
''');
    final (model, bag) = resolve('api.yaml');
    final d = bag.all.single;
    expect(d.code, DiagnosticCode.refKindMismatch);
    expect(
      d.message,
      '"#/components/schemas/Limit" points to a schema, but a parameter is '
      'expected here.',
    );
    final get = model.resolve(model.document.paths['/a']!)!;
    expect(model.resolve(get.operations['get']!.parameters.single), isNull);
  });

  test('a target outside components is read as the expected kind', () {
    dir.write('api.yaml', '''
$info
x-shared:
  limit: {name: limit, in: query}
paths:
  /a:
    get:
      parameters: [{\$ref: "#/x-shared/limit"}]
''');
    final (model, bag) = resolve('api.yaml');
    expect(bag.all, isEmpty);
    final get = model.resolve(model.document.paths['/a']!)!;
    final limit = model.resolve(get.operations['get']!.parameters.single);
    expect(limit!.name, 'limit');
    expect(model.nodeAt(limit.location), same(limit));
  });
}
```

- [ ] **Step 2: Переконатися, що тести падають**

Run (з `packages/typed_openapi`): `dart test test/resolve`
Expected: FAIL, перша помилка — `cannot read 'lib/src/resolve/ref_resolver.dart': No such file or directory`

- [ ] **Step 3: Додати коди в каталог**

У `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart` перед фрагментом:

```dart
  /// A `$ref` points to a remote URL; only local files are read.
```

встав:

```dart
  /// A `$ref` points to a file or a node that does not exist.
  unresolvedRef('TOA101', 'unresolved-ref', .error),
```

- [ ] **Step 4: Додати коди в каталог**

У `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart` перед фрагментом:

```dart
  /// `$id` or `$self` would change the base URI of `$ref`s; this tool
```

встав:

```dart
  /// A `$ref` points to a node of another kind, such as a schema where a
  /// parameter is expected.
  refKindMismatch('TOA104', 'ref-kind-mismatch', .error),
```

- [ ] **Step 5: Створити `spec_documents.dart`**

Створи `packages/typed_openapi/lib/src/resolve/spec_documents.dart`:

```dart
import 'dart:io';

import 'package:path/path.dart' as p;

import '../load/spec_document.dart';
import '../load/spec_loader.dart';

/// The documents of one spec: the root document and every file its `$ref`s
/// reach, each loaded once and keyed by absolute URI.
final class SpecDocuments {
  /// Creates the set for [root]; other files are read with [_loader].
  SpecDocuments(this._loader, this.root) {
    _documents[root.uri] = root;
  }

  final SpecLoader _loader;
  final Map<Uri, SpecDocument?> _documents = {};

  /// The document the spec starts from.
  final SpecDocument root;

  /// The document at [uri], loaded on first use; null when the file does not
  /// exist or cannot be read.
  ///
  /// A file that does not exist is not reported here; one that exists but
  /// cannot be parsed is reported by the loader. Diagnostics name the file
  /// relative to the root document's displayed path.
  SpecDocument? operator [](Uri uri) {
    if (_documents.containsKey(uri)) return _documents[uri];
    final path = p.fromUri(uri);
    final document =
        FileSystemEntity.typeSync(path) == FileSystemEntityType.file
        ? _loader.load(path, displayPath: displayPath(uri))
        : null;
    return _documents[uri] = document;
  }

  /// How diagnostics name the file at [uri].
  String displayPath(Uri uri) {
    if (uri == root.uri) return root.file;
    final relative = p.relative(
      p.fromUri(uri),
      from: p.dirname(p.fromUri(root.uri)),
    );
    return p.normalize(p.join(p.dirname(root.file), relative));
  }
}
```

- [ ] **Step 6: Створити `spec_model.dart`**

Створи `packages/typed_openapi/lib/src/resolve/spec_model.dart`:

```dart
import '../model/document.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';

/// A parsed spec with its `$ref`s resolved.
///
/// Holds the root [document], every node read from any file by location,
/// and where each `$ref` that could be followed points.
final class SpecModel {
  /// Creates a model.
  SpecModel({
    required this.document,
    required Map<SpecLocation, SpecNode> nodes,
    required Map<SpecLocation, SpecLocation> targets,
  }) : _nodes = Map.unmodifiable(nodes),
       _targets = Map.unmodifiable(targets);

  /// The root document.
  final OpenApiDocument document;

  final Map<SpecLocation, SpecNode> _nodes;
  final Map<SpecLocation, SpecLocation> _targets;

  /// The node at [location], if one was read there.
  SpecNode? nodeAt(SpecLocation location) => _nodes[location];

  /// Where the `$ref` of the node at [site] points, or null when the node
  /// has no `$ref` or it could not be followed.
  SpecLocation? targetOf(SpecLocation site) => _targets[site];

  /// The node [value] stands for: the value itself, or the node at the end
  /// of its `$ref` chain; null when a `$ref` on the way is broken.
  T? resolve<T extends SpecNode>(RefOr<T> value) => switch (value) {
    Inline(:final value) => value,
    Ref() => switch (_follow(value.location)) {
      final T node => node,
      _ => null,
    },
  };

  /// The schema at the end of [schema]'s `$ref` chain, or [schema] itself
  /// when it has no `$ref`; null when a `$ref` on the way is broken.
  ///
  /// Keywords next to a `$ref` are not merged into the result.
  Schema? resolveSchema(Schema schema) {
    if (schema is! SchemaObject || schema.ref == null) return schema;
    return switch (_follow(schema.location)) {
      final Schema node => node,
      _ => null,
    };
  }

  SpecNode? _follow(SpecLocation site) {
    final seen = <SpecLocation>{};
    var current = site;
    while (seen.add(current)) {
      final target = _targets[current];
      if (target == null) return null;
      final node = _nodes[target];
      final isAlias = node is Ref || (node is SchemaObject && node.ref != null);
      if (!isAlias) return node;
      current = target;
    }
    return null;
  }
}
```

- [ ] **Step 7: Створити `ref_resolver.dart`**

Створи `packages/typed_openapi/lib/src/resolve/ref_resolver.dart`:

```dart
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../model/document.dart';
import '../model/operation.dart';
import '../model/schema.dart';
import '../model/security.dart';
import '../model/spec_node.dart';
import '../parse/openapi_parser.dart';
import '../parse/parse_context.dart';
import 'ref_target.dart';
import 'spec_documents.dart';
import 'spec_model.dart';

/// Follows every `$ref` of a parsed spec.
///
/// A target is identified by the absolute URI of its file plus its JSON
/// pointer. Targets in other local files are loaded once and parsed as the
/// kind of node the `$ref` expects; their own `$ref`s are followed in turn.
/// Problems go to the [DiagnosticBag] given to the constructor.
final class RefResolver {
  /// Creates a resolver that reports to [_diagnostics].
  const RefResolver(this._diagnostics);

  final DiagnosticBag _diagnostics;

  /// Resolves the `$ref`s in [index], which parsing [document] filled; the
  /// root document of the spec is [documents]' root.
  SpecModel resolve(
    OpenApiDocument document,
    SpecIndex index,
    SpecDocuments documents,
  ) {
    final parsers = <Uri, OpenApiParser>{};
    final targets = <SpecLocation, SpecLocation>{};
    for (var i = 0; i < index.refs.length; i++) {
      final use = index.refs[i];
      switch (RefTarget.parse(use.ref, use.site.document)) {
        case BrokenRef(:final code, :final reason, :final fix):
          _report(documents, use, code, reason, fix: fix);
        case ResolvableRef(:final location):
          final file = documents[location.document];
          if (file == null) {
            _report(
              documents,
              use,
              .unresolvedRef,
              '"${use.ref}" points to '
              '${documents.displayPath(location.document)}, which does not '
              'exist or cannot be read.',
            );
            continue;
          }
          var node = index.nodes[location];
          if (node == null) {
            if (file.valueAt(location.pointer) == null) {
              _report(
                documents,
                use,
                .unresolvedRef,
                'Nothing is at "${use.ref}".',
                fix:
                    'Define the target, or point the reference at an '
                    'existing one.',
              );
              continue;
            }
            final parser = parsers[location.document] ??= OpenApiParser(
              _diagnostics,
              file,
              index,
            );
            node = parser.parseFragment(location.pointer, use.kind);
            if (node == null) continue;
          }
          final kind = _kindOf(node);
          if (kind != use.kind) {
            _report(
              documents,
              use,
              .refKindMismatch,
              '"${use.ref}" points to '
              '${kind?.withArticle ?? 'a node that is not referable'}, but '
              '${use.kind.withArticle} is expected here.',
            );
            continue;
          }
          targets[use.site] = location;
      }
    }
    return SpecModel(document: document, nodes: index.nodes, targets: targets);
  }

  static RefKind? _kindOf(SpecNode node) => switch (node) {
    Ref(:final kind) => kind,
    Schema() => .schema,
    Response() => .response,
    Parameter() => .parameter,
    Example() => .example,
    RequestBody() => .requestBody,
    Header() => .header,
    SecurityScheme() => .securityScheme,
    PathItem() => .pathItem,
    MediaType() => .mediaType,
    _ => null,
  };

  void _report(
    SpecDocuments documents,
    RefUse use,
    DiagnosticCode code,
    String message, {
    String? fix,
  }) {
    final document = documents[use.site.document];
    final pointer = use.site.pointer.child(r'$ref');
    _diagnostics.report(
      code,
      message,
      file: documents.displayPath(use.site.document),
      pointer: pointer,
      span: document?.spanOf(pointer),
      fix: fix,
    );
  }
}
```

- [ ] **Step 8: Переконатися, що тести проходять**

Run (з `packages/typed_openapi`): `dart test test/resolve`
Expected: `+15: All tests passed!`

- [ ] **Step 9: Формат, аналізатор, увесь набір тестів**

Run (з `packages/typed_openapi`): `dart format --output=none --set-exit-if-changed lib test bin && dart test`
Expected: `Formatted 55 files (0 changed)`, `+122: All tests passed!`

Run (з кореня): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 10: Commit**

```bash
git add packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart packages/typed_openapi/lib/src/resolve/ref_resolver.dart packages/typed_openapi/lib/src/resolve/spec_documents.dart packages/typed_openapi/lib/src/resolve/spec_model.dart packages/typed_openapi/test/resolve/ref_resolver_test.dart
git commit -m 'feat(typed_openapi): resolve $ref inside a document and across files' -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
```

---

### Task 11: Цикли посилань (TOA103)

**Files:**
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`
- Modify: `packages/typed_openapi/lib/src/resolve/ref_resolver.dart`
- Modify: `packages/typed_openapi/test/resolve/ref_resolver_test.dart`

**Interfaces:**
- Consumes: `RefResolver`, `SpecDocuments` (Task 10), `SpecLocation.compareTo` (Task 3).
- Produces: приватні `RefResolver._reportCycles`/`_reportCycle`; код `refCycle` (TOA103). Публічний API не змінюється.

Поведінка, яку закріплюють тести:
- `A → B → A` (зокрема з `description` поруч із `$ref`) і `A → A` — один `TOA103` у pointer `$ref` найменшого учасника, повідомлення з ланцюжком; `resolveSchema` → `null`.
- `A → B → C → B` — один цикл `B → C → B`, а не по діагностиці на кожен вхід у нього; `resolve(A)` → `null`.
- Цикл через інший файл називає той файл (`other.yaml#/B`).

- [ ] **Step 1: Написати тест, що не проходить**

Допиши в кінець `main()` у `packages/typed_openapi/test/resolve/ref_resolver_test.dart` (перед останньою `}`):

```dart
  group('cycles', () {
    test('two schemas that only point at each other are a loop', () {
      dir.write('api.yaml', '''
$info
components:
  schemas:
    A: {\$ref: "#/components/schemas/B"}
    B: {\$ref: "#/components/schemas/A", description: Loops.}
''');
      final (model, bag) = resolve('api.yaml');
      final d = bag.all.single;
      expect(d.code, DiagnosticCode.refCycle);
      expect(d.pointer?.value, r'#/components/schemas/A/$ref');
      expect(
        d.message,
        'These references point at each other and never reach a definition: '
        '#/components/schemas/A -> #/components/schemas/B -> '
        '#/components/schemas/A.',
      );
      final a = model.document.components!.schemas['A']!;
      expect(model.resolveSchema(a), isNull);
    });

    test('a schema that points at itself is a loop', () {
      dir.write('api.yaml', '''
$info
components:
  schemas:
    A: {\$ref: "#/components/schemas/A"}
''');
      final (_, bag) = resolve('api.yaml');
      expect(bag.all.single.code, DiagnosticCode.refCycle);
    });

    test('a loop is reported once, not by every reference into it', () {
      dir.write('api.yaml', '''
$info
components:
  parameters:
    A: {\$ref: "#/components/parameters/B"}
    B: {\$ref: "#/components/parameters/C"}
    C: {\$ref: "#/components/parameters/B"}
''');
      final (model, bag) = resolve('api.yaml');
      expect(
        bag.all.single.message,
        contains('B -> #/components/parameters/C'),
      );
      final a = model.document.components!.parameters['A']!;
      expect(model.resolve(a), isNull);
    });

    test('a loop across files names the other file', () {
      dir.write('api.yaml', '''
$info
components:
  schemas:
    A: {\$ref: "other.yaml#/B"}
''');
      dir.write('other.yaml', 'B: {\$ref: "api.yaml#/components/schemas/A"}\n');
      final (_, bag) = resolve('api.yaml');
      expect(
        bag.all.single.message,
        endsWith(
          '#/components/schemas/A -> other.yaml#/B -> #/components/schemas/A.',
        ),
      );
    });
  });
```

- [ ] **Step 2: Переконатися, що тести падають**

Run (з `packages/typed_openapi`): `dart test test/resolve`
Expected: FAIL, перша помилка — `Member not found: 'refCycle'.`

- [ ] **Step 3: Додати коди в каталог**

У `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart` перед фрагментом:

```dart
  /// A `$ref` points to a node of another kind, such as a schema where a
```

встав:

```dart
  /// `$ref`s point at each other in a loop that never reaches a definition.
  refCycle('TOA103', 'ref-cycle', .error),
```

- [ ] **Step 4: Змінити `ref_resolver.dart`**

У `packages/typed_openapi/lib/src/resolve/ref_resolver.dart` перед фрагментом:

```dart
    return SpecModel(document: document, nodes: index.nodes, targets: targets);
```

встав:

```dart
    _reportCycles(targets, documents);
```

- [ ] **Step 5: Змінити `ref_resolver.dart`**

У `packages/typed_openapi/lib/src/resolve/ref_resolver.dart` перед фрагментом:

```dart

  static RefKind? _kindOf(SpecNode node) => switch (node) {
```

встав:

```dart
  /// Reports every loop of `$ref`s that never reaches a node without one.
  ///
  /// A key of [targets] is a node whose `$ref` resolved, so a chain that
  /// stays inside the keys only passes through references. A recursive
  /// schema is not a loop: its chain ends at the schema itself, which has
  /// no `$ref`.
  void _reportCycles(
    Map<SpecLocation, SpecLocation> targets,
    SpecDocuments documents,
  ) {
    final done = <SpecLocation>{};
    for (final start in targets.keys.toList()..sort()) {
      final path = <SpecLocation>[];
      final positions = <SpecLocation, int>{};
      SpecLocation? current = start;
      while (current != null &&
          targets.containsKey(current) &&
          !done.contains(current)) {
        final seen = positions[current];
        if (seen != null) {
          _reportCycle(path.sublist(seen), documents);
          break;
        }
        positions[current] = path.length;
        path.add(current);
        current = targets[current];
      }
      done.addAll(path);
    }
  }

  void _reportCycle(List<SpecLocation> cycle, SpecDocuments documents) {
    final first = cycle.reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
    final start = cycle.indexOf(first);
    final ordered = [...cycle.skip(start), ...cycle.take(start), first];
    String name(SpecLocation location) => location.document == first.document
        ? location.pointer.value
        : '${documents.displayPath(location.document)}'
              '${location.pointer.value}';
    final pointer = first.pointer.child(r'$ref');
    _diagnostics.report(
      .refCycle,
      'These references point at each other and never reach a definition: '
      '${ordered.map(name).join(' -> ')}.',
      file: documents.displayPath(first.document),
      pointer: pointer,
      span: documents[first.document]?.spanOf(pointer),
      fix: 'Point one of them at the actual definition.',
    );
  }
```

- [ ] **Step 6: Переконатися, що тести проходять**

Run (з `packages/typed_openapi`): `dart test test/resolve`
Expected: `+19: All tests passed!`

- [ ] **Step 7: Формат, аналізатор, увесь набір тестів**

Run (з `packages/typed_openapi`): `dart format --output=none --set-exit-if-changed lib test bin && dart test`
Expected: `Formatted 55 files (0 changed)`, `+126: All tests passed!`

Run (з кореня): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart packages/typed_openapi/lib/src/resolve/ref_resolver.dart packages/typed_openapi/test/resolve/ref_resolver_test.dart
git commit -m 'feat(typed_openapi): report $ref loops' -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
```

---

### Task 12: `SpecReader`, `check` на новій моделі, публічний API і документація

**Files:**
- Create: `packages/typed_openapi/lib/src/resolve/spec_reader.dart`
- Create: `packages/typed_openapi/test/resolve/spec_reader_test.dart`
- Modify: `packages/typed_openapi/lib/src/check/spec_checker.dart`
- Modify: `packages/typed_openapi/lib/typed_openapi.dart`
- Modify: `packages/typed_openapi/test/check/spec_checker_test.dart`
- Modify: `packages/typed_openapi/test/cli/cli_test.dart`
- Modify: `packages/typed_openapi/CHANGELOG.md`
- Modify: `packages/typed_openapi/README.md`
- Modify: `packages/typed_openapi/README.ua.md`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: усе попереднє.
- Produces: `final class SpecReader { const SpecReader(DiagnosticBag); SpecModel read(SpecDocument document, OpenApiVersion version); }`; `SpecChecker.check` читає модель після детекції версії; публічний API експортує моделі, `SpecModel`, `SpecReader`.

Поведінка, яку закріплюють тести:
- `SpecReader.read` одним викликом розбирає документ, розв'язує посилання і перевіряє діалект; схема глибиною до ліміту `NestingScanner` читається без переповнення стека.
- `SpecChecker` після детекції версії читає модель: битий `$ref` в іншому файлі і пропущене поле видно в `check`; діалект перевіряється проти оголошеної версії; документ без визначеної версії в модель не читається.
- CLI друкує `TOA100` з pointer. Мінімальні фікстури наявних тестів отримують `info`.

- [ ] **Step 1: Написати тест, що не проходить**

Створи `packages/typed_openapi/test/resolve/spec_reader_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/load/nesting_scanner.dart';
import 'package:typed_openapi/src/load/openapi_version.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/model/schema.dart';
import 'package:typed_openapi/src/resolve/spec_reader.dart';

void main() {
  test('parses, resolves and checks the dialect in one call', () {
    final bag = DiagnosticBag();
    final document = SpecLoader(bag).parse(r'''
openapi: 3.0.3
info: {title: Pets, version: "1"}
components:
  schemas:
    Pet: {type: object, properties: {tag: {$ref: "#/components/schemas/Tag"}}}
    Tag: {type: [string, "null"]}
''', 'api.yaml')!;
    final model = SpecReader(bag).read(document, .v30);
    final pet = model.document.components!.schemas['Pet']! as SchemaObject;
    final tag = model.resolveSchema(pet.properties['tag']!)! as SchemaObject;
    expect(tag.types, [SchemaType.string, SchemaType.nullType]);
    expect(model.document.version, OpenApiVersion.v30);
    expect(bag.all.map((d) => d.code), [
      DiagnosticCode.openApi31InOpenApi30,
      DiagnosticCode.openApi31InOpenApi30,
    ]);
  });

  test('a schema nested as deep as the loader allows is read', () {
    final bag = DiagnosticBag();
    const depth = NestingScanner.maxDepth - 4;
    final schema = '${'{"items": ' * depth}{"type": "string"}${'}' * depth}';
    final document = SpecLoader(bag).parse(
      '{"openapi": "3.1.0", "info": {"title": "t", "version": "1"}, '
          '"components": {"schemas": {"Deep": $schema}}}',
      'api.json',
    )!;
    final model = SpecReader(bag).read(document, .v31);
    var current = model.document.components!.schemas['Deep'];
    var levels = 0;
    while (current is SchemaObject && current.items != null) {
      current = current.items;
      levels++;
    }
    expect(levels, depth);
    expect(bag.all, isEmpty);
  });
}
```

- [ ] **Step 2: Додати тести в `spec_checker_test.dart`**

У `packages/typed_openapi/test/check/spec_checker_test.dart` заміни:

```dart
    dir.write('specs/ok.yaml', 'openapi: 3.0.3\n');
```

на:

```dart
    dir.write(
      'specs/ok.yaml',
      'openapi: 3.0.3\ninfo: {title: ok, version: "1"}\npaths: {}\n',
    );
```

- [ ] **Step 3: Додати тести в `spec_checker_test.dart`**

Допиши в кінець `main()` у `packages/typed_openapi/test/check/spec_checker_test.dart` (перед останньою `}`):

```dart
  test('reads each spec into the model and follows its references', () {
    final dir = TempDir();
    dir.write('specs/api.yaml', r'''
openapi: 3.0.3
info: {title: api}
paths:
  /pets:
    get:
      responses:
        "200": {$ref: "common.yaml#/components/responses/Missing"}
''');
    dir.write('specs/common.yaml', 'components: {responses: {}}\n');
    final path = dir.write('typed_openapi.yaml', '''
clients:
  api: {input: specs/api.yaml, output: lib/api}
''');
    final bag = DiagnosticBag();
    final config = ConfigLoader(bag).load(path)!;
    SpecChecker(bag).check(config);
    expect(
      bag.sorted.map((d) => (d.code, d.file, d.pointer?.value)),
      [
        (DiagnosticCode.missingRequiredField, 'specs/api.yaml', '#/info'),
        (
          DiagnosticCode.unresolvedRef,
          'specs/api.yaml',
          r'#/paths/~1pets/get/responses/200/$ref',
        ),
      ],
    );
  });

  test('reports the dialect of a spec against its declared version', () {
    final dir = TempDir();
    dir.write('api.json', '''
{
  "openapi": "3.1.0",
  "info": {"title": "api", "version": "1"},
  "components": {"schemas": {"A": {"type": "string", "nullable": true}}}
}
''');
    final path = dir.write(
      'typed_openapi.yaml',
      'clients:\n  api: {input: api.json, output: lib/api}\n',
    );
    final bag = DiagnosticBag();
    SpecChecker(bag).check(ConfigLoader(bag).load(path)!);
    expect(bag.all.single.code, DiagnosticCode.nullableAfterOpenApi30);
  });

  test('does not read a spec whose version it cannot detect', () {
    final dir = TempDir();
    dir.write('api.yaml', 'info: {title: 5}\nnmae: x\n');
    final path = dir.write(
      'typed_openapi.yaml',
      'clients:\n  api: {input: api.yaml, output: lib/api}\n',
    );
    final bag = DiagnosticBag();
    SpecChecker(bag).check(ConfigLoader(bag).load(path)!);
    expect(bag.all.single.code, DiagnosticCode.missingOpenApiVersion);
  });
```

- [ ] **Step 4: Додати тести в `cli_test.dart`**

У `packages/typed_openapi/test/cli/cli_test.dart` заміни:

```dart
    dir.write('specs/ok.yaml', 'openapi: 3.1.0\n');
```

на:

```dart
    dir.write(
      'specs/ok.yaml',
      'openapi: 3.1.0\ninfo: {title: ok, version: "1"}\n',
    );
```

- [ ] **Step 5: Додати тести в `cli_test.dart`**

Допиши в кінець `main()` у `packages/typed_openapi/test/cli/cli_test.dart` (перед останньою `}`):

```dart
  test('reports broken references in the spec', () async {
    final dir = TempDir();
    dir.write('api.yaml', r'''
openapi: 3.0.0
info: {title: api, version: "1"}
components:
  schemas:
    Owner: {properties: {pet: {$ref: "#/components/schemas/"}}}
''');
    final path = dir.write(
      'typed_openapi.yaml',
      'clients:\n  api: {input: api.yaml, output: lib/api}\n',
    );
    final (code, out, _) = await run(['check', '-c', path]);
    expect(code, 1);
    expect(out, contains('error TOA100 invalid-ref'));
    expect(
      out,
      contains(r'  at #/components/schemas/Owner/properties/pet/$ref'),
    );
  });
```

- [ ] **Step 6: Переконатися, що тести падають**

Run (з `packages/typed_openapi`): `dart test`
Expected: FAIL, перша помилка — `cannot read 'lib/src/resolve/spec_reader.dart': No such file or directory`

- [ ] **Step 7: Створити `spec_reader.dart`**

Створи `packages/typed_openapi/lib/src/resolve/spec_reader.dart`:

```dart
import '../diagnostics/diagnostic_bag.dart';
import '../load/openapi_version.dart';
import '../load/spec_document.dart';
import '../load/spec_loader.dart';
import '../parse/dialect_checker.dart';
import '../parse/openapi_parser.dart';
import '../parse/parse_context.dart';
import 'ref_resolver.dart';
import 'spec_documents.dart';
import 'spec_model.dart';

/// Reads a loaded spec into a [SpecModel]: parses it, follows its `$ref`s
/// and reports constructs its declared version does not have.
///
/// Problems go to the [DiagnosticBag] given to the constructor.
final class SpecReader {
  /// Creates a reader that reports to [_diagnostics].
  const SpecReader(this._diagnostics);

  final DiagnosticBag _diagnostics;

  /// Reads [document], which declares [version].
  SpecModel read(SpecDocument document, OpenApiVersion version) {
    final index = SpecIndex();
    final parsed = OpenApiParser(_diagnostics, document, index).parse(version);
    final model = RefResolver(_diagnostics).resolve(
      parsed,
      index,
      SpecDocuments(SpecLoader(_diagnostics), document),
    );
    DialectChecker(_diagnostics).check(index.features, version);
    return model;
  }
}
```

- [ ] **Step 8: Переписати `spec_checker.dart`**

Заміни весь вміст `packages/typed_openapi/lib/src/check/spec_checker.dart` на:

```dart
import 'package:path/path.dart' as p;

import '../config/project_config.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../load/openapi_version.dart';
import '../load/spec_loader.dart';
import '../resolve/spec_reader.dart';

/// Loads every client's spec and reports what is wrong with it.
///
/// Nothing is generated. Problems go to the [DiagnosticBag] given to the
/// constructor.
final class SpecChecker {
  /// Creates a checker that reports to [_diagnostics].
  const SpecChecker(this._diagnostics);

  final DiagnosticBag _diagnostics;

  /// Checks the spec of every client in [config].
  ///
  /// Each spec is loaded, its OpenAPI version detected, and then it is read
  /// into the model with its `$ref`s resolved. [only] limits the run to
  /// clients with these names; empty means all. A file shared by several
  /// clients is checked once. Spec paths in diagnostics are relative to the
  /// config file's directory.
  void check(ProjectConfig config, {Set<String> only = const {}}) {
    final loader = SpecLoader(_diagnostics);
    final detector = OpenApiVersionDetector(_diagnostics);
    final reader = SpecReader(_diagnostics);
    final configDir = p.dirname(p.absolute(config.file));
    final checked = <String>{};
    for (final client in config.clients) {
      if (only.isNotEmpty && !only.contains(client.name)) continue;
      if (!checked.add(p.absolute(client.input))) continue;
      final document = loader.load(
        client.input,
        displayPath: p.relative(client.input, from: configDir),
      );
      if (document == null) continue;
      final version = detector.detect(document);
      if (version == null) continue;
      reader.read(document, version);
    }
  }
}
```

- [ ] **Step 9: Переписати `typed_openapi.dart`**

Заміни весь вміст `packages/typed_openapi/lib/typed_openapi.dart` на:

```dart
/// OpenAPI 3.x to Dart client generator.
///
/// The programmatic API mirrors the CLI: load a config, check specs, report
/// diagnostics. [SpecReader] reads a loaded spec into the typed model
/// ([SpecModel]) with its `$ref`s resolved.
library;

export 'src/check/spec_checker.dart' show SpecChecker;
export 'src/cli/cli.dart' show TypedOpenApiCli;
export 'src/config/config_loader.dart' show ConfigLoader;
export 'src/config/project_config.dart'
    show ClientConfig, Preset, ProjectConfig;
export 'src/diagnostics/diagnostic.dart' show Diagnostic;
export 'src/diagnostics/diagnostic_bag.dart' show DiagnosticBag;
export 'src/diagnostics/diagnostic_code.dart' show DiagnosticCode;
export 'src/diagnostics/json_pointer.dart' show JsonPointer;
export 'src/diagnostics/reporters.dart'
    show DiagnosticReporter, JsonReporter, ReportFormat, TextReporter;
export 'src/diagnostics/severity.dart' show Severity;
export 'src/load/openapi_version.dart'
    show OpenApiVersion, OpenApiVersionDetector;
export 'src/load/spec_document.dart' show SpecDocument;
export 'src/load/spec_loader.dart' show SpecLoader;
export 'src/model/document.dart' show Components, Info, OpenApiDocument, Tag;
export 'src/model/operation.dart'
    show
        Encoding,
        Example,
        Header,
        MediaType,
        Operation,
        Parameter,
        ParameterLocation,
        ParameterStyle,
        PathItem,
        RequestBody,
        Response,
        SecurityRequirement,
        Server,
        ServerVariable;
export 'src/model/schema.dart'
    show BooleanSchema, Discriminator, Schema, SchemaObject, SchemaType;
export 'src/model/security.dart'
    show
        ApiKeyLocation,
        OAuthFlow,
        OAuthFlows,
        SecurityScheme,
        SecuritySchemeType;
export 'src/model/spec_node.dart'
    show Inline, Ref, RefKind, RefOr, SpecLocation, SpecNode;
export 'src/resolve/spec_model.dart' show SpecModel;
export 'src/resolve/spec_reader.dart' show SpecReader;
```

- [ ] **Step 10: Змінити `CHANGELOG.md`**

У `packages/typed_openapi/CHANGELOG.md` заміни:

```markdown
- Programmatic API: `ConfigLoader`, `SpecLoader`, `OpenApiVersionDetector`,
  `SpecChecker`, `TextReporter`, `JsonReporter`, `TypedOpenApiCli`.
```

на:

```markdown
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
- Loading: nesting deeper than 1000 levels is reported (TOA007) instead of
  crashing; YAML keys such as `1` and `"1"` that merge into one JSON key are
  reported (TOA002); a directory given as the spec or the config is reported
  as such.
```

- [ ] **Step 11: Змінити `README.md`**

У `packages/typed_openapi/README.md` перед фрагментом:

```markdown
Every finding has a stable code (`TOA011`), a JSON pointer into the spec and,
```

встав:

```markdown
`check` reads the whole spec, follows its `$ref`s (also into other local
files) and reports unknown keys, wrong value types, broken or looping
references and constructs that the declared OpenAPI version does not have.
```

- [ ] **Step 12: Змінити `README.ua.md`**

У `packages/typed_openapi/README.ua.md` перед фрагментом:

```markdown
У кожної знахідки є стабільний код (`TOA011`), JSON-pointer на місце в
```

встав:

```markdown
`check` читає всю специфікацію, проходить її `$ref` (зокрема в інші локальні
файли) і повідомляє про невідомі ключі, значення неправильного типу, биті або
зациклені посилання і конструкції, яких немає в оголошеній версії OpenAPI.
```

- [ ] **Step 13: Змінити `CLAUDE.md`**

У `CLAUDE.md` заміни:

```markdown
## Architecture of M1 (`dart run typed_openapi check`)

All under `packages/typed_openapi/lib/src/`, one folder per stage:

- `diagnostics/` - `Diagnostic`, `DiagnosticCode` (stable `TOAnnn` catalog),
  `Severity`, `JsonPointer`, `DiagnosticBag`, and the reporters
  (`DiagnosticReporter`, `TextReporter`, `JsonReporter`, `ReportFormat`).
- `load/` - `SpecLoader` reads JSON/YAML into a `SpecDocument` (plain tree plus
  source spans by JSON pointer); `OpenApiVersionDetector` reads its OpenAPI
  version.
- `config/` - `ConfigLoader`, `ProjectConfig`, `ClientConfig`, `Preset`.
- `check/` - `SpecChecker`.
- `cli/` - `TypedOpenApiCli` (`cli.dart`, owns the `CommandRunner` and maps
  usage errors to exit code 64) and `CheckCommand` (`check_command.dart`,
  options `--config/-c` and `--format`, client names as positional
  arguments); `bin/typed_openapi.dart` only calls `TypedOpenApiCli().run(args)`
  and sets `exitCode`.
- `lib/typed_openapi.dart` exports the public API: the classes above except
  `CheckCommand`, each with a `show` list.

Data flows loader -> checker, every stage writing problems into one
`DiagnosticBag`; reporters read the bag at the end.
```

на:

```markdown
## Architecture (`dart run typed_openapi check`)

All under `packages/typed_openapi/lib/src/`, one folder per stage:

- `diagnostics/` - `Diagnostic`, `DiagnosticCode` (stable `TOAnnn` catalog),
  `Severity`, `JsonPointer`, `DiagnosticBag`, and the reporters
  (`DiagnosticReporter`, `TextReporter`, `JsonReporter`, `ReportFormat`).
- `load/` - `SpecLoader` reads JSON/YAML into a `SpecDocument` (plain tree,
  absolute file URI, source spans by JSON pointer, `valueAt(pointer)`);
  `NestingScanner` rejects text nested deeper than 1000 levels before the
  recursive YAML parser sees it; `OpenApiVersionDetector` reads the version.
- `model/` - the immutable typed model, a superset of OAS 3.0/3.1/3.2:
  `SpecNode` (every node has a `SpecLocation` = file URI + pointer, `x-`
  `extensions` and reported `unknownKeys`), `RefOr<T>` = `Ref<T>` | `Inline<T>`,
  `Schema` = `BooleanSchema` | `SchemaObject` (`$ref` is a keyword there),
  `OpenApiDocument` and the other OAS objects.
- `parse/` - `OpenApiParser` (document, components, fragments for `$ref`
  targets), `OperationParser`, `SchemaParser`, all on `ObjectReader` (typed
  field access; wrong types -> TOA111, missing required -> TOA112, unknown
  keys -> TOA110). Parsers record nodes, `$ref`s and version-specific
  constructs (`SpecFeature`) in a shared `SpecIndex`; `DialectChecker` turns
  the constructs into TOA020-TOA022.
- `resolve/` - `RefTarget` reads a `$ref` value, `SpecDocuments` loads other
  local files once by URI, `RefResolver` follows every `$ref` and reports
  TOA100-TOA105, `SpecModel` answers `resolve`/`resolveSchema`; `SpecReader`
  runs parse -> resolve -> dialect check.
- `config/` - `ConfigLoader`, `ProjectConfig`, `ClientConfig`, `Preset`.
- `check/` - `SpecChecker`: config -> load -> version -> `SpecReader`.
- `cli/` - `TypedOpenApiCli` (`cli.dart`, owns the `CommandRunner` and maps
  usage errors to exit code 64) and `CheckCommand` (`check_command.dart`,
  options `--config/-c` and `--format`, client names as positional
  arguments); `bin/typed_openapi.dart` only calls `TypedOpenApiCli().run(args)`
  and sets `exitCode`.
- `lib/typed_openapi.dart` exports the public API: the classes above except
  `CheckCommand`, each with a `show` list.

Data flows loader -> parser -> resolver -> checker, every stage writing
problems into one `DiagnosticBag`; reporters read the bag at the end.
```

- [ ] **Step 14: Переконатися, що тести проходять**

Run (з `packages/typed_openapi`): `dart test`
Expected: `+132: All tests passed!`

- [ ] **Step 15: Формат, аналізатор, увесь набір тестів**

Run (з `packages/typed_openapi`): `dart format --output=none --set-exit-if-changed lib test bin && dart test`
Expected: `Formatted 57 files (0 changed)`, `+132: All tests passed!`

Run (з кореня): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 16: Commit**

```bash
git add CLAUDE.md packages/typed_openapi/CHANGELOG.md packages/typed_openapi/README.md packages/typed_openapi/README.ua.md packages/typed_openapi/lib/src/check/spec_checker.dart packages/typed_openapi/lib/src/resolve/spec_reader.dart packages/typed_openapi/lib/typed_openapi.dart packages/typed_openapi/test/check/spec_checker_test.dart packages/typed_openapi/test/cli/cli_test.dart packages/typed_openapi/test/resolve/spec_reader_test.dart
git commit -m 'feat(typed_openapi): check reads specs into the model' -m 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
```

---

## Фінальна перевірка

- [ ] **Step 1: Повна перевірка пакета**

Run (з `packages/typed_openapi`):

```bash
dart format --output=none --set-exit-if-changed lib test bin && dart test && dart pub publish --dry-run
```

Expected: `Formatted 57 files (0 changed)`, `+132: All tests passed!`, `Package has 0 warnings.`

Run (з кореня): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 2: Прогін на реальній специфікації (поза репозиторієм)**

Поклади `typed_openapi.yaml` у тимчасовий каталог поза репозиторієм з одним клієнтом, чий `input` — абсолютний шлях до NestJS-специфікації з research/06 §C.1a (саму специфікацію в репозиторій не копіювати), і запусти `dart run typed_openapi check -c <шлях>`.

Expected (перевірено на прототипі, OAS 3.0.0, 3 MB, 734 операції, 1434 схеми): `errors: 3, warnings: 9, infos: 0` — три `TOA100 invalid-ref` на `$ref: '#/components/schemas/'`, вісім `TOA111 invalid-value` на `required: true/false` усередині `items` (C-49), один `TOA020` («"examples" in a schema»); жодного `TOA110`. Час: ~0,25 с скомпільованим `dart compile exe` (~125 MB RSS), ~0,8 с через `dart run`.

## Покриття вимог

| Вимога | Де |
|---|---|
| R0.1 — OAS 3.0 і 3.1 | Модель-надмножина (Tasks 3, 5–7), діалект (Task 8) |
| R1.2 — `$ref` у документі й між файлами, цикли | Tasks 9–11 |
| R1.4 — 3.2 `itemSchema` | `MediaType.itemSchema` (Task 6), `TOA022` (Task 8) |
| R2.1 (част.) — порожній і висячий `$ref` як діагностики | `TOA100`, `TOA101` (Tasks 9–10); виправлення — M3 |
| R2.2 — коди, pointer, позиції | Усі нові коди з pointer і span; позиції — і в інших файлах |
| R2.5 — нічого не вгадувати мовчки | Невідомі ключі, неправильні типи, пропущені поля, проігноровані `$id`/`$self` — усе діагностики |
| R13.1 — детермінізм | Порядок документа, сортування циклів, `DiagnosticBag.sorted` |
| Перенесено з M1 | Tasks 1–2 |
