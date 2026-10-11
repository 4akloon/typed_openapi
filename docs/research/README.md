# typed_openapi: ресерч конкурентів і рішень

Дата: **2026-10-11**. Зведено з 7 паралельних досліджень. Першоджерела (код на конкретних комітах, issues, специфікації) і деталі лежать у файлах `01…07` цієї папки. Вимоги: [../requirements.md](../requirements.md).

Позначки: ✅ є / виконано · ⚠️ частково · ❌ немає або порушено · ? не перевірено · — не застосовно.

---

## 0. Коротко

1. **Ніша вільна.** Серед ~25 Dart-генераторів жоден не має продуктового шару для неідеальних специфікацій: іменованих правил нормалізації з кодами діагностики, файлу override-ів з адресацією, baseline. Ті, хто генерує великі SDK з OpenAPI, латають вручну: Matrix тримає 16 `.patch`-файлів до специфікації, Mastodon — `hacks.dart` поверх згенерованого коду. Це пряме підтвердження R0.2.
2. **Ринок фрагментований.**
   - Лідери за завантаженнями: swagger_parser (~66k/міс, релізить одна людина) і swagger_dart_code_generator (~63k/міс, фактично покинутий).
   - Dart-генератори OpenAPI Generator живуть без власника.
   - 2026 рік приніс хвилю дрібних нових генераторів. Найближчий за функціями — **degenerate**, але він порушує R10.2 і не має ні діагностики, ні override-ів.
3. **Твої твердження з ТЗ підтвердились**, з уточненнями (§4).
4. **Ніхто не поєднує:** R8.1 разом з R8.2 (зберегти сире значення enum і заборонити його надсилати); R10.2 разом з типізованими помилками (вміє лише florval); SSE поверх клієнта користувача.
5. **json_serializable покриває моделі, R6.1, R6.4 і R7** (через твій `explicitJsonNullWhenNonNullField`). Не покриває: сире значення enum, union, шлях у JSON для помилок. **Вирішено:** генератор пише код сам, сумісний з контрактом json_serializable (§7.2).
6. **Парсер треба писати свій**, на `package:yaml`, з JSON Pointer і `SourceSpan` на кожному вузлі. `tonik_parse`/`tonik_core` для цього не годяться (§7.5).
7. **У вимогах знайшовся конфлікт: R14.2 проти `sealed` і вичерпного `switch`.** Новий варіант або значення ламає вичерпний `switch` у коді споживача. `openai_dart` через це випустив 11 мажорних версій за 7 місяців (§7.8).

### Ухвалені рішення (2026-10-11)

| Питання | Рішення |
|---|---|
| Ім'я | `typed_openapi` |
| Тип виходу (1) | Готовий код без обов'язкового build_runner |
| Серіалізація (2) | Власна емісія, **сумісна з контрактом** json_serializable (`fromJson`/`toJson`), без залежності від нього |
| HTTP-шар (3) | У v1 лише Dio через вузьку поверхню; абстракцію `ApiTransport` вирішити до 1.0 |
| Модель помилок (4) | **Без винятків:** кожен метод повертає `ApiResult<T, E>` (§7.4) |
| Парсер (5) | Власний; JSON і YAML читаються через `package:yaml` зі spans (§7.5) |
| Розширюваність (6) | Конфіг + override-и + типізовані хуки над IR, без шаблонів |
| Представлення (7) | Попередньо: `Patch<T>?` для трьох станів; enum як `sealed X` + `XKnown` / `XUnknown` |
| Кілька клієнтів (R1.3) | Один конфіг з розділом `clients` і спільними `defaults`; у кожного клієнта свої вихід, override-и, baseline і простір імен; один спільний runtime (деталі в [../requirements.md](../requirements.md)) |
| Групування (R5.3) | Клас на тег із суфіксом `Api` (шаблон налаштовується), кореневий клас клієнта з групами-полями. Звичайні класи без інтерфейсів і без модифікаторів `final`/`base`/`interface`, мокаються через `implements` (R10.7) |
| Помилки операції (R11.4) | Одна схема на всі помилки → тип помилки = ця схема; sealed за статусами лише коли схеми різні; тіла без опису — за `errors.default_schema` |
| Конверти (R6.4) | `{data: T}` за замовчуванням розгортається, метод повертає `T` |
| Імена (R5.1) | Як у схемі: `operationId` → lowerCamelCase, імена схем без змін (`Dto` лишається); трансформації лише явні (конфіг, пресет) |
| Числа (R6.2) | `integer` → `int`; `number` + `float`/`double` → `double`; `number` без формату → `num`; мапінг і override налаштовуються |
| Вичерпність (8) | `exhaustive` за замовчуванням для enum, union-ів, подій SSE і помилок операції; вимикається на рівні схеми в override-ах (`exhaustive: false`); звіт R14.1 позначає нові значення як source-breaking (§7.8) |

---

## 1. Ім'я і пакети

| Пакет | Роль |
|---|---|
| `typed_openapi` | CLI + програмний API генератора. Поширювати **як ізольований інструмент** (`dart install typed_openapi` / `dart run typed_openapi@x.y.z`), а не як `dev_dependency`, щоб його `analyzer`/`dart_style` не конфліктували з freezed, riverpod_generator тощо (analyzer випустив 5 мажорних версій за січень–червень 2026) |
| `typed_openapi_runtime` | Маленький runtime: помилки, `Result`, `Patch<T>`, JSON-хелпери зі шляхом, кодеки стилів параметрів, SSE-парсер. У v1 залежить лише від `dio` + `meta`; логіка, не пов'язана з транспортом, тримається окремо від Dio (див. §7.3) |
| `typed_openapi_dio` / `typed_openapi_http` | Окремі адаптери — **лише якщо** пізніше з'явиться HTTP-абстракція (рішення до 1.0, §7.3) |

Решта імен:
- **Файли:** `typed_openapi.yaml` (конфіг), `typed_openapi.overrides.yaml` (override-и), `typed_openapi.baseline.yaml` (baseline), `typed_openapi.lock` (див. §5, R13/R14).
- **Коди діагностики:** префікс (наприклад `TOA`) і діапазони за областями, як пропонує [06 §C.0](06-spec-versions-and-defects.md):

  | Діапазон | Область |
  |---|---|
  | 0xx | документ і діалект |
  | 1xx | `$ref` |
  | 2xx | схеми |
  | 3xx | enum |
  | 4xx | поліморфізм |
  | 5xx | операції та іменування |
  | 6xx | media types і стріми |
  | 7xx | стабільність виходу |
  | 8xx | override-и |

  До числового коду варто додати людську назву в стилі Stainless (`Schema/ArrayMissingItems`).
- **Власні `x-` розширення:** в одному просторі імен, наприклад `x-typed-*`.

---

## 2. Ландшафт

### 2.1 Хто є на ринку

| Інструмент | Версія (дата) | Популярність | Стан | Вихід / HTTP |
|---|---|---|---|---|
| OpenAPI Generator `dart-dio` / `dart` | 7.26.0 (2026-10-06) | — | Dart-генератори без власника, 134 відкриті issues з «dart» у назві, потрібна Java 11+ | mustache → built_value / json_serializable + build_runner; Dio / http |
| `openapi_generator` (обгортка на pub) | 7.0.0 (2026-05) | — | `analyzer <9`: із сучасним Flutter не ставиться (gibahjoe#201) | — |
| swagger_parser | 1.45.0 (2026-09-25) | 124♥, ~65.6k/міс | активний, але релізить одна людина; його форкають (openapi_retrofit_generator → openapi_sdk_gen) | retrofit + json_serializable / freezed / dart_mappable, build_runner |
| swagger_dart_code_generator | 4.1.1 (2025-12-11) | 331♥, ~62.6k/міс | фактично покинутий (#796 без відповіді, 13 PR висять) | chopper + json_serializable, build_runner |
| tonik | 0.10.0 (2026-09-07) | 8♥, ~2k/міс | дуже активний, 0.x, PR з SSE відкритий | готовий код; Dio або http; згенерований пакет потребує Dart ≥3.13 |
| swagger_to_dart | 6.0.0 (2026-10-06) | 26♥, ~2k/міс | активний сплесками, два мажорні релізи за тиждень | freezed + json_serializable + retrofit |
| space_gen | 1.4.0 (2026-07-19) | 56★, ~39k/міс (ймовірно, CI Shorebird) | стоїть з липня; найкраща архітектура | готовий код, лише `package:http` |
| **degenerate** | 0.5.0 (2026-09-10) | 5♥, ~0.5k/міс | активний, один автор | готовий код, власний `ApiClient` + адаптери dio/http |
| florval | 0.4.1 (2026-07-10) | 4♥ | активний | freezed + Dio користувача (через Riverpod) |
| Kiota (Dart) | abstractions 0.3.0 | — | preview | CLI на .NET, `package:http`, мутабельні моделі |

Ще близько 10 дрібних (dart_openapi_generator, flap, koi_swagger_parser, openapi_flutter_gen під AGPL та інші) розібрано в [04](04-dart-long-tail.md).

**Як генерують великі Dart SDK.**
- **Вручну:** davidmigloz (`openai_dart`, `anthropic_sdk_dart`, `googleai_dart`) перейшов з openapi_spec+freezed на ручний код із залежностями лише `http`, `logging`, `meta`. Supabase теж пише вручну.
- **Власним генератором:** Google, AWS, Appwrite, Matrix, Nextcloud.
- **Комерційні генератори** (Stainless, Speakeasy, Fern) Dart **не підтримують**.
- **Що це означає:** серйозні автори відмовляються не від генерації, а від build_runner, freezed і зайвих runtime-залежностей.

### 2.2 Матриця за ключовими вимогами

| | R2 діагн. | R3 override | R4.2 tree-shake | R7 три стани | R8.1 raw enum | R8.2 | R9.1 unknown | R10.2 onError | R11 типіз. помилки | R12 SSE | build_runner |
|---|---|---|---|---|---|---|---|---|---|---|---|
| OAG dart-dio (json_ser.) | ⚠️ мовчазний | ⚠️ глобальні мапінги | ❌ | ⚠️ лише PATCH через `$ref` | ❌ | ❌ | ❌ поліморфізму нема | ✅ | ❌ | ❌ | так |
| swagger_parser | ❌ | ⚠️ regex | ⚠️ | ❌ | ❌ | ❌ | ✅ (не для freezed) | ✅ | ❌ | ❌ | так |
| swagger_dart_code_gen. | ❌ | ⚠️ | ❌ | ❌ | ❌ | ⚠️ | ❌ `dynamic` | — chopper | ❌ | ❌ | так |
| tonik | ❌ | ⚠️ імена | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ PR | ні |
| swagger_to_dart | ❌ | ⚠️ імена | ❌ | ❌ | ❌ | ❌ | ✅ opt-in | ✅ | ❌ | ❌ | так |
| space_gen | ⚠️ pointer без кодів | ❌ | ❌ | ❌ | ❌ throw | — | ❌ | — http | ⚠️ | ❌ | ні |
| degenerate | ❌ рядки | ❌ | ✅ | ✅ | ✅ | ? | ✅ | ❌ | ✅ | ✅ неповний WHATWG | ні |
| florval | ❌ | ❌ | ? | ✅ | ❌ | ? | ? | ✅ | ✅ | ❌ | так |
| Kiota (Dart) | ⚠️ лише warnings | ❌ | ? | ? | ❌ throw | — | ⚠️ | — http | ✅ | ? | ні |
| **typed_openapi (ціль)** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ні/опційно |

---

## 3. Проблеми конкурентів: чого не повторювати

Кожен пункт містить проблему (де і доказ) і урок для typed_openapi.

**A. Мовчазні вгадування (R2.5)**
- **OAG** [01 P31, P13]:
  - виняток у нормалізаторі ковтається, генерація йде далі;
  - частини `allOf` викидаються з DEBUG-логом;
  - самопосилання стає `any`, map без типу значень стає `String`;
  - якщо 2xx немає, типом успіху стає `default`.
- **Cookie-параметри мовчки зникають** в OAG, swagger_parser і SDCG, хоча таблиця функцій OAG заявляє `Cookie ✓`.
- **Перебір варіантів через try/catch:** swagger_parser — для `oneOf` без дискримінатора, tonik — для невідомого дискримінатора.
- **Заглушки й деградація:** space_gen генерує `throw UnimplementedError` у `fromJson`, flap деградує типи в `dynamic`.
- **→ Урок:** кожне таке рішення має ставати діагностикою з кодом, pointer-ом і готовим фрагментом override-у.

**B. Розбір через касти, падіння на першому дефекті (R1.2, R2)**
- **Касти до перевірок:** swagger_parser на path-level `parameters` (#374, каст стоїть до перевірки ключа, досі не виправлено). tonik падає з `TypeError` на `required: true` і закінчує загальним «Unexpected error». `openapi_spec` і `openapi_spec_plus` падають на типових дефектах NestJS без позиції.
- **`$ref` як «останній сегмент шляху»** (SP, SDCG): зовнішніх файлів немає, цикл дає StackOverflow (SP #423).
- **→ Урок:** lossless-DTO з pointer, діагностика збирається, а не кидається; операція з дефектом пропускається з діагностикою, а не валить усю генерацію.

**C. Матриця required × nullable — головне джерело багів (R6.1)**
- **Масові баги:**
  - swagger_parser: #303, #358, #460, #443, #307;
  - OAG: #23866, #21565, #21510, #18647;
  - SDCG: #182, 28 коментарів.
- **Схлопування до «optional ⇒ nullable»** у SP і SDCG.
- **NestJS, SP #460:** один `allOf` без `required` робить усі поля required.
- **→ Урок:** окремий модуль з явною таблицею (у space_gen вона на 8 рядків, ogen документує матрицю декодера), golden-тест на кожну клітинку, окремо для запиту, відповіді і PATCH.

**D. Невідомі значення enum (R8)**
- **OAG:** sentinel — справжнє wire-значення (`'unknown_default_open_api'` / `11184809`), тож його можна відправити.
- **swagger_parser:** `$unknown(null)` губить сире значення, а json_serializable надсилає `"$unknown"` на сервер.
- **SDCG:** у nullable-полях невідоме значення стає `null`.
- **tonik:** опція `generateUnknownCase` глобальна, сире значення губиться, без неї декодування всієї відповіді падає.
- **space_gen і Kiota:** кидають виняток (у Kiota — свідомо).
- **→ Урок:** окремий тип для невідомого значення з raw, і в запитах його приймати не можна (§7.7).

**E. Втручання в транспорт користувача (R10.1, R10.2)**
- **OAG:** без явних `interceptors:` додає до переданого `Dio` 4 auth-інтерсептори, без Dio ставить жорсткі таймаути 5/3 с.
- **tonik:** `validateStatus: (_) => true`, тіло йде в інтерсептори як байти, `baseUrl` перезаписується навіть у Dio користувача.
- **degenerate:** той самий `validateStatus: (_) => true` в адаптері Dio.
- **Фальшиві HTTP-статуси:** space_gen перетворює транспортний збій на `ApiException(400)`, OAG `dart` — помилку декодування на `ApiException(500)`.
- **→ Урок:** не чіпати клієнта; HTTP-помилка проходить рідним шляхом (для Dio — `onError`) і типізується вже після нього, як у florval.

**F. Затирання даних null-ами (R7.3)**
- **swagger_to_dart:** надсилає `null` для всіх незаданих optional-полів, плюс default-значення.
- **tonik і space_gen:** надсилають `null` для optional + nullable (саме такі поля дає FastAPI `Optional[X] = None`).
- **→ Урок:** поле з одним станом без значення ключа не має; три стани лише за правилом R7.2.

**G. Ні типізованих помилок, ні кількох 2xx (R10.6, R11)**
- **OAG, SP, SDCG:** немає ні того, ні іншого.
- **retrofit:** це архітектурна стеля — один `T` на метод, issue про типізовані тіла помилок (#168) відкрите з 2020.
- **→ Урок:** не генерувати поверх retrofit; методи викликають транспорт напряму.

**H. Іменування (R5)**
- **Нестабільні inline-імена:** з HTTP-кодами (`GetPets200Response`) і суфіксами `_1`, `_2`. OAG змінював схему іменування без fallback (6.0) і логіку дедуплікації (7.23).
- **Перейменування regex-ом по сирому тексту** специфікації: swagger_parser так перетворив **шляхи API** на PascalCase.
- **Колізії:** з `dart:core`, з `Options` з Dio, з членами `Enum` (`name`, `index`, `values`).
- **Ключі `inlineSchemaNameMappings` в OAG — це згенеровані імена**, тож вони «пливуть».
- **→ Урок:** глобальний прохід іменування `Map<JsonPointer, String>` (як у space_gen) і префікси імпортів (як `DartEmitter.scoped()` у tonik). Ключ override-у — місце в специфікації, а не згенероване ім'я.

**I. Вихід змінюється в мінорних релізах (R15.4)**
- **OAG:**
  - 7.15 — за замовчуванням додано `copy_with_extension`, збірки впали;
  - 7.23 — змінено дедуплікацію;
  - 7.25 — багаторядкові описи дали невалідний код.
- **swagger_parser 1.42:** binary-відповідь стала `Stream<String>`, вимкнути не можна.
- **space_gen:** під час генерації запускає `dart pub get` і `dart fix`, тож результат залежить від мережі й версії SDK.
- **→ Урок:** golden-diff у CI на корпусі специфікацій; будь-яка зміна виходу — major (у dynamite це записана політика) або opt-in прапорець.

**J. Якість виходу (R13.2, R13.5)**
- **Лінти:** OAG не проходить `lints/recommended` (`/** */`, `unnecessary_this`, імпорт з `equatable/src`). SP і SDCG вимикають лінти цілком через `ignore_for_file: type=lint`. degenerate не форматує вихід.
- **Зайві файли:**
  - OAG: 131 з 217 файлів — заглушки документації і тестів, застарілі файли не видаляються;
  - swagger_to_dart: половина рядків моделей — дамп JSON-схеми в коментарях;
  - space_gen: генерує round-trip тести.
- **→ Урок:** тільки `lib`, маніфест вихідних файлів з видаленням застарілих, точкові ignore-и в самих файлах.

**K. build_runner і залежності (рішення 1)**
- **Конфлікти залежностей:** топ-issue SDCG (#812, 17 реакцій) — конфлікти версій `build` / `dart_style` / `chopper`. Обгортку OAG блокує `analyzer <9`.
- **Помилки видно лише після другої фази** (SP #380, #411, #462).
- **Мертві runtime-залежності:** `one_of` останній раз публікувався 2022 року.
- **→ Урок:** генератор не має жити в графі залежностей користувача; runtime мінімальний.

**L. Ін'єкція коду через рядки специфікації**
- **Проблема:** будь-який рядок зі специфікації, підставлений у згенерований код, — потенційна ін'єкція (degenerate #15, #18; tonik #88 — перенос рядка давав невалідний raw-літерал).
- **→ Урок:** один хелпер екранування для всіх місць підстановки, тип-обгортка `SpecString`, fuzz-тести (у tonik є корпус `adversarial_strings`).

**M. Документація розходиться з кодом (R15.5)**
- **Приклади:** OAG заявляє `Cookie ✓`; у README swagger_parser є `put_in_folder`, якого немає в коді; tonik заявляє «3.2» в описі репозиторію.
- **→ Урок:** матрицю підтримки генерувати з golden-фікстур.

**N. Bus factor**
- **Приклади:** SDCG покинутий; SP релізить одна людина; Dart-генератори OAG без власника.
- **→ Урок:** публічна roadmap, автоматичні релізи, кілька мейнтейнерів.

---

## 4. Перевірка тверджень із ТЗ

| Твердження | Вердикт | Доказ |
|---|---|---|
| tonik: `validateStatus: (_) => true` ламає `onError` (R10.2) | ✅ **правда** | `tonik_generate/.../dio_options_generator.dart#L25-L65`. Транспортні збої далі йдуть в `onError`, а 4xx/5xx — ні. Виправити через `BaseOptions` неможливо, бо опції запиту мають пріоритет. Окремо tonik перезаписує `baseUrl` у переданому Dio. Та сама проблема є в **degenerate** [03 §1.4a, 04 §2.1] |
| tonik і swagger_to_dart затирають дані null-ами (R7.3) | ⚠️ **tonik — частково**, ✅ **swagger_to_dart — правда** | tonik шле `null` лише для optional + nullable (`class_generator.dart#L864-L875`). swagger_to_dart — для всіх optional у JSON-тілах, бо генерує без `includeIfNull`. space_gen поводиться як tonik [03 §1.4b, §2.4] |
| swagger_parser губить сире значення невідомого enum (R8.1) | ✅ **правда** + порушено R8.2 | `dart_enum_dto_template.dart` L131-142: `$unknown(null)`. Значення надсилається як `"$unknown"`; з `enums_to_json` кидає `StateError` [02 §1.5] |
| tonik губить сире значення enum (R8.1) | ✅ **правда** | Без опції — помилка декодування всієї відповіді. З `generateUnknownCase` — фіксоване `unknown`. R8.2 при цьому ✅: `toJson` кидає [03 §1.4c] |
| dart-dio генерує заглушки (R13.5) | ✅ | 131 з 217 файлів прикладу Petstore — `doc/` і `test/`. Застарілі файли не видаляються [01 §2.2]. *Раніше в чаті я помилково назвав це «виправленням» до формулювання R13.5. Формулювання коректне* |

---

## 5. Що запозичити (за областями вимог)

| Область | Ідея | Звідки |
|---|---|---|
| **R2.1** нормалізатор | 25 іменованих правил, кожне вмикається окремо, набір «on за замовчуванням», `DISABLE_ALL`. У документації кожного правила — diff «до/після». **Додати** коди, pointer і звіт | OAG normalizer [01 §4.1] |
| **R2.1** каталог | 48 дефектів NestJS / FastAPI / springdoc / ASP.NET → назви правил, коди, auto-fix. Пресети `preset: nestjs | fastapi | springdoc | aspnet | generic` | [06 §C] |
| **R2.2** діагностика | Каталог `Категорія/Назва`, рівні з бізнес-семантикою, повідомлення-шаблон, що каже, як виправити. Незнижувані коди (ruleset `speakeasy-generation`) | Stainless, Speakeasy [05 R2] |
| **R2.2** вивід | `text`, `json` (з JSON Schema виводу), `sarif`, `github-actions`, `junit`. Pointer — основна адреса, line/col — додатково | Redocly, Spectral, oasdiff |
| **R2.2** непідтримане | Облік невикористаних ключів (`markUsed`) → автоматичне виявлення непідтриманих ключових слів і `x-*` | space_gen [03 §3.6] |
| **R2.3** baseline | Ключ — fingerprint `sha256(code|якір|args)[:12]` без тексту повідомлення (oasdiff). `count` як стеля для масових кодів. Запис, що більше не спрацьовує, валить CI з підказкою `baseline prune` (ESLint bulk suppressions) | oasdiff, ESLint, Redocly ignore-file |
| **R3** override-и | Обов'язковий `reason`; `matches_schema` (знайти структурно рівні схеми → `$ref`); діагностика `Transform/Useless` / «did not match any targets»; overlay `strict: true` за замовчуванням | Stainless, Speakeasy, oapi-codegen |
| **R3** типи | `scalars` (format → тип + функції серіалізації), `overriden_models`, `response_override_value_map` — це запити користувачів, які варто покрити адресованими override-ами | SDCG [02 §2.7] |
| **R4** фільтри | Селектори `'GET /path'` + regex, `exclude` має пріоритет, схеми-сироти прибираються автоматично; glob з суфіксом `#METHOD`; нормалізація тегів (регістр, `_`, `-`) | hey-api, Kiota, degenerate |
| **R5** імена | Глобальний прохід `Map<JsonPointer, String>`; scoped-імпорти; doc-коментар «Original name: `x`» при вимушеному перейменуванні; іменування `With<Subtype>` / `As<Subtype>` для кількох media type | space_gen, tonik, SP, OAG |
| **R6** модель | Матриця з 8 рядків; окремий тип `Date`; `JsonValue` як extension type; `fieldOrDefault`; моделі за напрямком (readOnly / writeOnly); `--unwrap-fields` для конвертів | space_gen, ogen, degenerate |
| **R7** три стани | Режими `nullable | all | off` (≈ R7.2); `Patch<T>?` + `explicitJsonNullWhenNonNullField` (перевірено на 6.14.1) | degenerate `Omittable`, [07 §A.2] |
| **R8** enum | `sealed X` + `enum XKnown implements X` + `XUnknown(raw)`; enum з одним значенням лишається закритим; читати `x-extensible-enum`, `x-ms-enum.modelAsString`, `x-enum-varnames`, `x-enumNames` | [07 §C.3], Speakeasy, Stainless Java |
| **R9** union | OAS 3.2 `discriminator.defaultMapping` як стандартний fallback. Для `oneOf` без дискримінатора — драбина ogen **під час генерації**: JSON-тип → унікальні required-поля → тип поля → непересічні const/enum. Діагностика при перетині умов. Диспетчер — як у freezed (switch за ключем, варіанти через `fromJson`), але з raw JSON у `Unknown` | ogen, Stainless, freezed 4.0.2 |
| **R10.5/10.8** метадані | `OperationInfo` (operationId, method, pathTemplate, tags, security) у кожному запиті, з мерджем у `extra` користувача. Security — структурні метадані (AND / OR) | SDCG `SwaggerMetaData`, space_gen `AuthRequest`, hey-api |
| **R10.2** Dio | Не чіпати `validateStatus`; ловити `DioException` з `response` і мапити в типізований варіант. Генерований код викликає `dio.request` (`fetch` з «голим» `RequestOptions` пропускає `BaseOptions`). Інтерсептор може `resolve`-нути не-2xx, тож статус завжди перевіряється через `switch` | florval, [07 §B] |
| **R10.3** стилі | Кодеки всіх стилів (simple, label, matrix, form, deepObject, pipe, space, `allowReserved`) як еталон для порівняльних тестів (MIT) | `tonik_util/lib/src/encoding` |
| **R11** помилки | Порядок вибору: точний код → `4XX`/`5XX` → `default` → базовий. Окремі варіанти: транспорт, задокументована помилка, помилка декодування, незадокументований статус | Kiota, progenitor, swift-openapi-generator |
| **R12** SSE | Таблиця обробників подій (`[DONE]`, подія помилки, fallthrough); `resumable` (Last-Event-ID, `retry:`, до 5 спроб зі скиданням) + `terminator`; без автоповтору POST-стрімів за замовчуванням. Еталони парсера: `sse_parser`, LaunchDarkly (17/17 кейсів WHATWG) | Stainless, Fern, openai-python, [04 §5] |
| **R13/R14** стабільність | Lock-файл (хеш специфікації + хеш конфігу + версія генератора); маніфест файлів + `--dry-run`; «володіємо лише своїми каталогами»; `edition`-и для свідомих змін виходу; `oasdiff --fail-on`; `dart_apitool diff` для Dart API | Kiota, Speakeasy, OAG, space_gen, Stainless |
| **R15.3** корпус | ~40 інтеграційних специфікацій tonik + мок-сервер Imposter + docker-приклади зі справжніми FastAPI / NestJS / Spring; snapshot-и degenerate (Stripe, GitHub, K8s, OpenAI, Cloudflare) з `dart analyze`; GitHub і Discord зі space_gen; golden на FastAPI `HTTPValidationError` | tonik, degenerate, space_gen, OAG #13302 |
| **Маркетинг** | Web-playground: ядро без `dart:io` дає генерацію в браузері | swagger_parser |

---

## 6. Пропоновані правки до вимог

| R-ID | Що змінити | Чому |
|---|---|---|
| R0.1 | Внутрішня модель — надмножина OAS 3.2; **діалект визначається за вмістом**, а не за полем `openapi` | NestJS ≤11 пише `nullable` у документи 3.1; FastAPI кладе `itemSchema` у документ `3.1.0`; .NET 3.0 прибирає `type` у чисел [06 §A.3] |
| R1.4 | Приймати `itemSchema` у документах будь-якої версії | FastAPI ≥0.135 так генерує SSE |
| R1.2 | Ідентичність схеми = абсолютний URI документа + pointer; враховувати `$id` і `$self` (3.2) | space_gen #358: однакові `#/components/schemas/Foo` з двох файлів злилися |
| R2.3 | Ключ baseline — код + fingerprint (семантичний якір), а не сирий pointer з індексами масивів; застарілий запис валить CI до `baseline prune` | індекси зсуваються; досвід ESLint / oasdiff |
| R2 (нове) | **R2.6:** будь-який рядок зі специфікації в коді проходить один екранувальник; fuzz-тести | ін'єкція коду (degenerate #15) |
| R3.2 | Overlay вважає дію без збігів **успішною**, а JSON Patch атомарний → потрібні власна діагностика «override не знайшов цілі» і «м'який» режим застосування патчів | Overlay spec, RFC 6902 [06 §B] |
| R3.3 | Актуальна версія Overlay — **1.2.0** (1.1 додала `copy`, 1.2 — reusable actions) | [06 §A.0] |
| R6.5 | Уточнити: «зрозуміла помилка» = схема + поле + JSON-pointer + очікуваний / фактичний тип, у **будь-якому** режимі збірки (OAG `dart` перевіряє required лише в `assert`) | OAG P10 |
| R8.2 | Механізм — на рівні типів (`XKnown` у параметрах і конструкторах запиту). Окремо вирішити політику GET→PUT round-trip невідомого значення: за замовчуванням заборонено, з opt-in на схему | space_gen PR #374 обирає протилежне |
| R10.1 | Генерований код викликає `dio.request`, не `fetch`: `fetch` з «голим» `RequestOptions` пропускає `BaseOptions` користувача. Якщо пізніше з'явиться абстракція (§7.3) — «адаптер використовує клієнт користувача як є» | [07 §B.1] |
| R10.2 | Додати: інтерсептор може `resolve`-нути помилку в не-2xx відповідь → генерований код завжди розбирає статус | [07 §B.2] |
| R10.7 | Документувати mocktail / fakes: mockito для null-safe моків потребує build_runner | [07 §C.4] |
| R11.7 | Dio 5.11 має 9 типів винятків (додано `transformTimeout`); `cancel` — окремий варіант, а не транспортний збій | [07 §B.3] |
| R12.4 | На Flutter Web стандартний Dio-адаптер (XHR) **не стрімить**: SSE прийде одним шматком. Задокументувати `ConversionLayerAdapter(FetchClient)`; `EventSource` браузера не підходить (лише GET, без заголовків) | dio#1859, #1740 відкриті з 2023 |
| R12.5 | Перепідключення за замовчуванням **вимкнене для не-ідемпотентних** (POST) стрімів | openai-python: повтор POST може задублювати результат |
| R13.1 | Пінити `dart_style`; `// dart format width=N` у кожному файлі; імпорти вже згруповані (тоді вихід 3.12 і 3.13 збігається); `lineEnding: '\n'`; жодної мережі і `dart fix` під час генерації | дрейф форматера [07 §D.2], space_gen |
| R13.5 | Без змін (формулювання коректне) | — |
| R14.1 | Окрема категорія **«source-breaking для exhaustive switch»** (нове значення enum чи варіант union) | §7.8 |
| R14.2 | Уточнити: варіанти `Unknown` захищають **вже скомпільований** код (старий клієнт, новий сервер), але **не** вихідний код після регенерації, якщо `switch` вичерпний | семантика Dart; `openai_dart` |
| R15.1 | Дистрибуція як ізольований інструмент, а не `dev_dependency` | analyzer lock-step |
| R15.3 | Конкретні джерела корпусу: tonik, degenerate, space_gen (§5) | — |

---

## 7. Відкриті рішення: рекомендації

### 7.1 Тип виходу (рішення 1)

**Готовий код без обов'язкового build_runner**; інтеграція з build_runner — опційний тонкий `Builder` над тим самим програмним API.
- **За:** вихід залежить лише від версії генератора (R13.1, R15.4); golden-тести = пряме порівняння; немає ~12 с холодної AOT-компіляції білдерів на CI; немає lock-step з `analyzer`. Macros скасовано (2025-01), augmentations станом на 2026-10 не вийшли й build_runner усе одно не приберуть.
- **Проти:** більше коду в генераторі.
- **Пом'якшення:** згенеровані типи дотримуються контракту json_serializable (`factory X.fromJson(Map<String, dynamic>)`, `toJson()`), тому вкладаються в `@JsonSerializable`-класи користувача і навпаки (перевірено).

### 7.2 Серіалізація (рішення 2): головне питання

Що json_serializable 6.14 закриває і що ні (перевірено на 6.14.1):

| Вимога | json_serializable | Деталі |
|---|---|---|
| Звичайні моделі, R6.1, зайві поля | ✅ | |
| R6.4 дженерики | ✅ | `genericArgumentFactories` |
| R7 три стани | ✅ | `explicitJsonNullWhenNonNullField` + `Patch<T>?` |
| R6.5 зрозумілі помилки | ⚠️ | `checked: true` дає клас + ключ, без шляху; ≈25× повільніше за unchecked; без checked — голий `TypeError` |
| R8.1 / R8.2 | ❌ | Dart `enum` не може тримати сире значення; `$unknown` надсилається |
| R9 union | ❌ нативно | Обхід: генератор сам пише sealed-базу з диспетчером (як freezed), варіанти — `@JsonSerializable` |

> У звітах 02 і 05 сказано, що три стани через json_serializable неможливі. Це **застаріло** з 6.14.0; звіт 07 перевірив, що працює.

**Варіант A — гібрид.** json_serializable для об'єктних моделей; генератор сам емітить sealed-enum, union-диспетчери, `Patch<T>`, типізовані помилки.
- **За:**
  - буквально відповідає ТЗ;
  - звична форма коду;
  - твоя експертиза в json_serializable — прогалини R6.5 можна закрити апстрімом (наприклад, JSON path у `CheckedFromJsonException`).
- **Проти:**
  - build_runner у проєкті користувача;
  - помилки видно лише після другої фази (SP #380);
  - мінімум `json_serializable: ^6.14.0` і Dart ≥3.8;
  - кінцевий `.g.dart` залежить від версії json_serializable у lockfile користувача. R13.1 формально виконується (вихід генератора детермінований), але фактичний код — ні.

**Варіант B — власна емісія з контрактом json_serializable.** Генератор пише `fromJson`/`toJson` сам; runtime-хелпери дають помилки з JSON-pointer.
- **За:**
  - R6.5 і R13.1 повністю;
  - без build_runner;
  - прототип: ≈2.2× повільніше за unchecked json_serializable і ≈10× швидше за checked;
  - сумісність з `@JsonSerializable`-класами користувача в обидва боки.
- **Проти:** ~300–500 рядків простого емітера; «не використовує» json_serializable.

**Рішення (2026-10-11): варіант B.** «Працює на json_serializable» означає **сумісність з контрактом**, а не залежність:
- генератор сам пише `fromJson`/`toJson`;
- публічні сигнатури такі самі, як у json_serializable: `factory X.fromJson(Map<String, dynamic> json)` і `Map<String, dynamic> toJson()`;
- runtime-хелпери дають помилки декодування з JSON-pointer;
- згенеровані типи вкладаються в `@JsonSerializable`-класи користувача і навпаки.

Тест на це вкладання має бути частиною golden-набору (R15.3).

### 7.3 HTTP-шар (рішення 3): у v1 лише Dio, абстракцію відкласти, але закласти шов

**Рекомендація: у v1 лише Dio** (`PetsApi(Dio dio)`), повноцінну незалежність від HTTP-клієнта відкласти. Умови:
1. **Згенерований код торкається Dio через вузьку поверхню:** `dio.request`, `Options`, `CancelToken`, `DioException`, `FormData`/`MultipartFile`, `ResponseBody`. Логіка (кодування параметрів, розбір статусів, SSE-парсер) лежить у runtime і від Dio не залежить. Тоді перехід на абстракцію пізніше стане механічною зміною.
2. **Рішення ухвалити до 1.0.** Зміна конструктора `PetsApi(Dio)` → `PetsApi(ApiTransport)` змінює вихід генератора, а це breaking change (R15.4). До 1.0 це прийнятно.
3. **Інші HTTP-клієнти вже доступні через Dio.** `dio_compatibility_layer` підставляє будь-який `package:http` клієнт (`cronet_http`, `cupertino_http`, `fetch_client`) як транспорт Dio. Без Dio-залежності лишаються лише ті, хто взагалі не хоче мати Dio в проєкті.

**Чому відкладати безпечно.** Сама абстракція коштує небагато: інтерфейс + адаптер, кілька сотень рядків. Дорожче інше:
- власні типи скасування і прогресу з містками до Dio;
- escape hatch для Dio-специфічних опцій;
- відсутність інтерсепторів у `package:http`, тож R10.2 для нього означає щось інше;
- подвійний набір тестів.

Нічого з цього не потрібно, поки немає реального користувача без Dio.

**Як виглядатиме абстракція, коли до неї дійде.** Тонкий інтерфейс транспорту в runtime і адаптери окремими пакетами:

```dart
// typed_openapi_runtime: без dio
abstract interface class ApiTransport {
  /// Надсилає запит РІДНИМ шляхом клієнта (інтерсептори, auth, ретраї).
  /// Будь-який HTTP-статус повертається як [RawResponse] — ПІСЛЯ того,
  /// як клієнт провів помилку своїм шляхом (для Dio — через onError).
  /// Транспортний збій → ApiTransportException, скасування → ApiCancelledException.
  Future<RawResponse> send(ApiRequest request);
}

final class ApiRequest {
  final OperationInfo operation;      // operationId, method, pathTemplate, tags, security
  final String method;
  final String path;                  // уже закодований за style
  final List<(String, String)> query; // уже закодований за style/explode
  final Map<String, String> headers;
  final ApiBody? body;                // json | formUrlEncoded | multipart | bytes
  final ResponseKind expect;          // json | text | bytes | stream
  final ApiCallOptions? options;      // cancel, progress, headers, extra, timeout
  // ...
}

// typed_openapi_dio
final class DioTransport implements ApiTransport {
  DioTransport(this._dio);            // Dio користувача; нічого не змінюємо (R10.1)
  final Dio _dio;

  @override
  Future<RawResponse> send(ApiRequest r) async {
    try {
      final res = await _dio.request<Object?>(          // request, не fetch: зливає BaseOptions
        r.path,
        queryParameters: ...,
        data: ...,
        options: Options(method: r.method, headers: r.headers,
            extra: {...?r.options?.extra, OperationInfo.key: r.operation}),   // R10.5
        cancelToken: bridgeCancel(r.options?.cancel),
      );
      return RawResponse.fromDio(res);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.badResponse && e.response != null) {
        return RawResponse.fromDio(e.response!, cause: e);  // onError уже відпрацював (R10.2)
      }
      throw mapTransportFailure(e);                         // R11.7
    }
  }
}

// використання
final pets = PetsApi(DioTransport(dio));
```

- **За:**
  - згенерований код не імпортує `dio`, тож адаптер `package:http` додається без зміни форми API;
  - тести можна мокати на рівні транспорту;
  - R10.2 виконується в кожному адаптері «рідним» способом.
- **Проти:**
  - власні типи скасування і прогресу з містками;
  - Dio-специфічне (власні `Options`) — через `extra` або escape hatch;
  - query кодується генератором (воно й так потрібне для label / matrix / deepObject / `allowReserved`, яких Dio не вміє), тому інтерсептори, що читають `options.queryParameters`, побачать готовий URI.
- **Урок degenerate:** у нього така сама схема, але Dio-адаптер виставив `validateStatus: (_) => true` і зламав `onError`. Контракт адаптера має прямо вимагати рідний шлях помилок.

### 7.4 Модель помилок (рішення 4)

**Рішення (2026-10-11): без винятків.** Кожен згенерований метод повертає `Future<ApiResult<T, E>>`, де `E` — sealed-тип задокументованих помилок операції. Очікувані збої (HTTP-помилка, транспорт, скасування, декодування) стають значеннями, а не винятками.

```dart
// typed_openapi_runtime
sealed class ApiResult<T, E> { const ApiResult(); }
final class ApiSuccess<T, E> extends ApiResult<T, E> {        // 2xx; статус і заголовки доступні
  const ApiSuccess(this.data, this.statusCode, this.headers);
  final T data; final int statusCode; final Map<String, List<String>> headers;
}
sealed class ApiFailure<T, E> extends ApiResult<T, E> { const ApiFailure(); }
final class ApiHttpError<T, E> extends ApiFailure<T, E> {     // задокументований 4xx/5xx/default (R11.1)
  const ApiHttpError(this.statusCode, this.body, this.headers);
  final int statusCode; final E body; final Map<String, List<String>> headers;
}
final class ApiUndocumentedStatus<T, E> extends ApiFailure<T, E> { /* statusCode, rawBody */ }  // R11.3
final class ApiTransportError<T, E> extends ApiFailure<T, E> { /* kind, cause */ }              // R11.7
final class ApiCancelled<T, E> extends ApiFailure<T, E> { /* cause */ }
final class ApiDecodeError<T, E> extends ApiFailure<T, E> { /* pointer, schema, message */ }    // R6.5

// використання
switch (await pets.getPetById(petId: 1)) {
  case ApiSuccess(:final data): show(data);
  case ApiHttpError(body: GetPetByIdError404()): showNotFound();
  case ApiHttpError(:final body): showError(body);
  case ApiUndocumentedStatus() || ApiTransportError() || ApiCancelled() || ApiDecodeError(): retryLater();
}
```

Правила:
- **R10.2 не порушується.** Dio кидає `DioException`, інтерсептори бачать його в `onError`, і лише потім згенерований метод ловить його і перетворює на `ApiFailure`.
- **Баги не ховаються.** `Error` (`StateError`, `TypeError` у коді користувача тощо) пролітає як і раніше: ловити його означало б маскувати помилки програміста.
- **Ергономіка в runtime:** `dataOrNull`, `fold`/`when`, `map`. Для місць, де фреймворк чекає виняток (`AsyncValue.guard` у Riverpod), можна дати явний `getOrThrow()` на боці виклику. Сам згенерований код винятків не кидає.
- **Мокання (R10.7):** один метод на операцію, мок повертає `ApiSuccess`/`ApiFailure`.
- **R11.2 («модель налаштовується»):** у v1 лише `Result`. Режим з винятками — пізніше, якщо з'явиться запит.
- **Відкрите питання для стрімів (R12):** збій після старту стріму (обрив, невалідна подія) має приходити елементом стріму, а не винятком. Форму треба спроєктувати окремо.

Спільна схема помилки генерується один раз (R11.4), помилки операції — sealed за статусами.

### 7.5 Парсер (рішення 5)

**Власний.** `tonik_parse`/`tonik_core` не підходять:
- позначені як internal, 0.x, breaking-зміни в кожному мінорному релізі;
- падають на першому дефекті;
- не мають pointer-ів і spans;
- відкидають обмеження, `x-*` і зовнішні `$ref`;
- `tonik_core` — мутабельна IR, зав'язана на runtime tonik.

Архітектура в дусі space_gen:

```
load (лише тут I/O) → lossless-DTO (JsonPointer + SourceSpan + extensions на кожному вузлі)
  → нормалізатор (R2.1) → override-и / overlay (R3) → resolve (абсолютний URI + pointer, цикли)
  → dispatch (oneOf/anyOf як окрема фаза з IR предикатів) → naming (Map<JsonPointer, String>)
  → незмінна IR без знань про Dart → Dart-мапінг → емітер
```

- **Основа — `package:yaml`, для JSON і YAML однаково.** JSON є підмножиною YAML 1.2, тож один парсер дає spans (рядок і колонку) для обох форматів. 4.7 МБ специфікації OpenAI розбирає за 225 мс проти 25 мс у `jsonDecode`, але `jsonDecode` позицій не дає, а без них немає діагностики R2.2.
- **Дублікати ключів.** `jsonDecode` мовчки бере останнє значення, а `package:yaml` кидає помилку. Шар завантаження має перехопити її і перетворити на діагностику з позицією, а не падати. Коерції YAML (наступний пункт) стосуються лише YAML-файлів.
- **Коерції YAML потребують окремих правил:** `200:` стає int-ключем, `1.0` — double, `0x1F` — числом, дублікати ключів кидають помилку.
- **Допоміжні пакети:** `rfc_6901`, `rfc_6902`, `json_path` (для Overlay; реалізації Overlay на pub немає), `source_span`, `yaml_edit` (baseline), `json_schema` + `checked_yaml` (валідація конфігу).

### 7.6 Розширюваність (рішення 6)

**Конфіг + override-и + типізовані хуки над IR** (мапінг типів, іменування, фільтри) через програмний API. **Шаблонів не робити.**
- Кожна зміна шаблону стає breaking (R15.4), ламає гарантії лінтів (R13.2), а користувачі форкають шаблони.
- Практика SP і SDCG показує, що реально використовуються саме конфіг-хуки (`field_parsers`, `scalars`, `custom_annotations`).

### 7.7 Представлення (рішення 7)

- **Три стани:** `Patch<T>?`, де `null` означає «ключа немає», плюс `Patch.value(x)` / `Patch.nullValue()`. Узгоджується з R7.3: скрізь у моделі `null` означає «не надсилати». Ергономіка з dot shorthands: `UpdatePet(name: .value('Rex'), tag: .nullValue())`.
- **Enum:** `sealed class X` + `enum XKnown implements X` + `final class XUnknown` з приватним конструктором і статичними аліасами `X.available`.
  - Поле моделі має тип `X`; **параметри операцій і конструктори запитів приймають лише `XKnown`**, тож R8.2 перевіряється компілятором.
  - Вичерпність `switch` зберігається.
  - Extension types **відхилено**: будь-який рядок кастується (`'hacked' as Color`), а вичерпність втрачається (перевірено).
- **Union:** sealed-база з диспетчером за дискримінатором (як у freezed) + `XUnknown(discriminator, Map json)`, у якого `toJson` повертає сирий JSON. Використовувати `defaultMapping` з 3.2, коли він заданий.

Ескізи коду: [07 §E.2–E.6](07-dart-building-blocks.md).

### 7.8 Нове рішення: вичерпність проти R14.2

Додавання значення в `enum` чи підкласу в `sealed` ламає **вихідний код** споживача з вичерпним `switch`, і варіант `Unknown` від цього не рятує. Аналога `@unknown default` зі Swift у Dart немає.

Приклад. Бекенд додав у `PetStatus` значення `pending`, клієнт перегенерували.

```dart
// exhaustive: PetStatusKnown — Dart enum, PetStatus — sealed
final label = switch (pet.status) {
  PetStatus.available => 'В наявності',
  PetStatus.sold => 'Продано',
  PetStatusUnknown(:final value) => value,
};
// після регенерації: помилка компіляції non_exhaustive_switch_expression,
// бо `pending` не оброблено. Розробник мусить вирішити, що показувати.

// open: PetStatus — звичайний клас зі static const, не enum і не sealed
final label = switch (pet.status) {
  PetStatus.available => 'В наявності',
  PetStatus.sold => 'Продано',
  _ => pet.status.value,      // гілка за замовчуванням обов'язкова завжди
};
// після регенерації: компілюється без змін, `pending` потрапляє в `_`.
```

В обох режимах **вже встановлений застосунок** (старий клієнт, новий сервер) не падає: невідоме значення декодується в `PetStatusUnknown`. Режим впливає лише на те, що станеться під час компіляції після регенерації клієнта.

Перемикання на рівні схеми — в override-ах:

```yaml
# typed_openapi.overrides.yaml
schemas:
  ChatEvent:          # union подій SSE, який часто росте
    exhaustive: false
```

| Режим | Поведінка | Для кого |
|---|---|---|
| `exhaustive` (sealed / enum) | Компілятор змушує обробити нове значення; звіт R14.1 позначає зміну як source-breaking | **Твоя аудиторія:** продуктові команди з власним бекендом, де «новий статус → треба обробити» — корисна помилка |
| `open` (клас зі статичними константами, `switch` вимагає `_`) | Нове значення нічого не ламає | Публічні SDK, стріми подій, що часто ростуть |

**Рішення (2026-10-11):**
- `exhaustive` за замовчуванням, з override-ом `exhaustive: false` на схему;
- окремого дефолту `open` для подій SSE немає: за потреби вимикається тим самим override-ом;
- звіт R14.1 показує нові значення enum і варіанти union як окрему категорію змін («source-breaking для вичерпного `switch`»).

---

## 8. Ризики

1. **Обсяг.** Вимог дуже багато. Найдорожчі частини: матриця R6.1 з golden-тестами, кодеки стилів R10.3, SSE на web.
2. **Темп змін тулчейну Dart.** analyzer міняє мажорну версію кожні 1–2 місяці, а `dart_style` змінює стиль навіть у patch-релізах. Захист: ізольована дистрибуція, пін `dart_style`, CI-матриця з найстарішим і найновішим SDK.
3. **Dio на web не стрімить.** SSE на Flutter Web працює лише з `ConversionLayerAdapter(FetchClient)`, і тоді скасування не перериває fetch.
4. **Конкуренти рухаються.** degenerate швидко додає функції; tonik має відкритий PR з SSE. Диференціація має бути саме в R2/R3, а не лише в моделях.
5. **Ліцензії.** Код openapi_flutter_gen (AGPL або комерційна) і генератора dynamite (AGPL) не копіювати. tonik, degenerate, Kiota, space_gen і sse_parser (MIT) та LaunchDarkly SSE (Apache-2.0) можна брати як еталон з атрибуцією.
6. **Bus factor** — головна причина смерті SDCG і ризик для SP.

---

## 9. Детальні звіти

| Файл | Зміст |
|---|---|
| [../requirements.md](../requirements.md) | Вимоги (вихідні) |
| [01-openapi-generator.md](01-openapi-generator.md) | OAG `dart-dio` / `dart`: покриття R-ID, повний список правил нормалізатора і мапінгів, 31 проблема з уроками |
| [02-swagger-parser-and-sdcg.md](02-swagger-parser-and-sdcg.md) | swagger_parser і swagger_dart_code_generator: конфіг як prior art, issues, перевірка R8.1 |
| [03-tonik-swagger-to-dart-space-gen.md](03-tonik-swagger-to-dart-space-gen.md) | tonik, swagger_to_dart, space_gen: вердикти по твердженнях, оцінка `tonik_parse` |
| [04-dart-long-tail.md](04-dart-long-tail.md) | 17 інших генераторів, великі SDK, пакети для парсера, тест SSE-пакетів на WHATWG |
| [05-cross-language-prior-art.md](05-cross-language-prior-art.md) | Speakeasy, Stainless, Fern, hey-api, Kiota, ogen, oapi-codegen, oasdiff, лінтери: патерни за R2–R14, таблиця `x-` розширень |
| [06-spec-versions-and-defects.md](06-spec-versions-and-defects.md) | OAS 3.0 → 3.1 → 3.2, Overlay / JSON Patch / Pointer, каталог 48 дефектів, рецепти для бекендів |
| [07-dart-building-blocks.md](07-dart-building-blocks.md) | json_serializable, build_runner, Dio, мовні можливості, dart_style; рекомендації 1–7 з ескізами коду |
