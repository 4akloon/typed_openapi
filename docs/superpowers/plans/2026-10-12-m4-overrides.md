# План M4: override-и

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `typed_openapi check` читає файл override-ів клієнта (`clients.<name>.overrides`, JSON або YAML), знаходить у специфікації операції, параметри, тіла, відповіді, схеми й властивості, які він адресує, застосовує його поля специфікації до сирого дерева до правил нормалізатора і звітує про застарілі, зайві, неоднозначні й конфліктні override-и в позиціях файлу override-ів; поля генерації перевіряються і зберігаються для M6; підказки п'яти правил M3, які лише діагностують, закінчуються готовим фрагментом override-у.

**Architecture:** Новий шар `lib/src/overrides/`: `OverrideLoader` читає файл через `SpecLoader` (компоновщик M3) у незмінну `OverrideSet` з типізованими записами; `OverrideResolver` перетворює логічні адреси на вузли `SpecModel` (`OverrideTarget`); `OverrideApplier` перетворює поля специфікації на `SpecEdit` рушія M3 з семантикою «set» і діалектним `nullable`; `Normalizer.normalize(..., overrides:)` застосовує ці правки один раз перед проходами правил і повертає `OverrideSet` у `NormalizedSpec`; `OverrideSnippet` обчислює з місця схеми адресу override-у і YAML-фрагмент, який правила додають до `fix` через `RuleContext.withOverride`. `SpecChecker` завантажує файл override-ів кожного клієнта.

**Tech Stack:** Dart `>=3.10.0 <4.0.0`, чистий Dart; нових залежностей немає (`collection`, `path`, `source_span` уже прямі); тести на `package:test`.

**Spec:** [docs/superpowers/specs/2026-10-12-m4-overrides-design.md](../specs/2026-10-12-m4-overrides-design.md) — рішення 1–10. Вимоги: R3.1, R3.2 ([requirements.md](../../requirements.md)); R6.8 (`{type, import, converter?}`), R7.2 (override тристановості), R5.3 (група) — лише як поля генерації. Уроки дослідження: [research/README](../../research/README.md) (R3: `reason`, «override не знайшов цілі», адреса — місце в специфікації, а не згенероване ім'я), [research/06 §B](../../research/06-spec-versions-and-defects.md) (чому не семантика Overlay). Рушій правок — [план M3](2026-10-11-m3-normalizer.md), задача 4. Правила коду — [CLAUDE.md](../../../CLAUDE.md).

## Global Constraints

- SDK `>=3.10.0 <4.0.0`; обидва пакети — чистий Dart. Primary constructors (Dart 3.13) не використовуються.
- Dart 3.10 активно: dot shorthands скрізь, де відомий тип контексту (`.overrideConflict`, `severity: .error`), null-aware елементи колекцій (`?_parameter(...)`), switch-вирази і patterns, records, модифікатори класів (`final`, `sealed`). У тестах аргументи `expect(...)` — повні імена (`DiagnosticCode.overrideConflict`).
- ООП: жодних функцій верхнього рівня, крім `main` у `bin/` і тестах. Компоненти, що звітують, отримують `DiagnosticBag` через конструктор (`OverrideLoader(bag)`, `OverrideResolver(bag, set)`, `OverrideApplier(bag, set, documents, version)`).
- Помилки вхідних даних (специфікація, конфіг, файл override-ів) не кидаються: вони йдуть у `DiagnosticBag`, решта читається. Нічого не вгадується: неоднозначність — діагностика (spec, рішення 8).
- Кожен новий код — у `DiagnosticCode` з doc-коментарем, slug у kebab-case, рівень за замовчуванням; діагностика про override — у файлі override-ів, з JSON pointer запису (поля) і позицією, і з `reason`, якщо він є (spec, рішення 6–7).
- Детермінізм (R13.1): записи — у порядку файлу, цілі — у порядку записів, правки — у порядку цілей; звіт сортує `DiagnosticBag.sorted`.
- Знання структури OAS — у парсері й моделі; override-и знаходять вузли через `SpecModel` і змінюють лише сире дерево через `SpecEdit` (spec, рішення 2–3).
- Error — лише для справжніх помилок (невалідне значення, невідомий ключ, неоднозначна адреса, конфлікт, відсутній файл); застарілий override — warning, зайвий і спільний вузол — info (R3.2).
- Негативні тести на валідних входах для кожного шляху: валідний файл override-ів — жодної діагностики; поля генерації — жодної правки; спільний параметр двох операцій — не конфлікт.
- Фікстури — вигадані й маленькі. Приватна специфікація компанії не використовується ні як фікстура, ні як джерело фікстур. Публічний корпус — лише для прогону `check`.
- Лінти з кореневого `analysis_options.yaml`; `dart analyze packages` з кореня — `No issues found!`; `dart format lib test bin` (з `packages/typed_openapi`) — другий запуск змінює 0 файлів.
- Тести не ходять у мережу; тимчасові файли — лише через `test/helpers/temp_dir.dart`.
- Команди `dart test`, `dart format` — з `packages/typed_openapi`; `dart analyze packages`, `git apply` і `git` — з кореня репозиторію. Diff-и в плані застосовуються `git apply` (з кореня).
- Кожен коміт — Conventional Commits і закінчується рядком `Co-Authored-By` моделі, що виконує задачу (у прикладах — `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`).

## Ухвалені рішення

Рішення специфікації M4 — обов'язкові. Тут — те, що специфікація лишає планові; формат файлу й семантику, які бачить користувач, підтвердили користувач (рішення 1, 2, 13, 14) і контролер (решта) після першої версії плану.

1. **Формат файлу.** Корінь — `operations` і `schemas`. Ключ операції — `operationId` або `METHOD /path` (метод без урахування регістру, один із методів `PathItem.methods`; невідомий метод — TOA802). У операції: `reason`, `name`, `exclude`, `group`, `parameters`, `requestBody`, `responses`. Параметр — за `name` або `in:name` (`path:id`); у ньому `required`, `schema` (поля специфікації), `name`, `dartType` (генерації). `requestBody` і `responses.<code>`: `contentType`, `schema`. Схема (ключ `components.schemas`): `$ref`, `type`, `nullable`, `format`, `required` (список імен), `items`, `additionalProperties`, `enum`, `discriminator` (специфікації), `name`, `exclude`, `exhaustive`, `dartType`, `properties`. Властивість — ті самі поля специфікації, але `required` — булеве; генерації: `name`, `exclude`, `dartType`, `triState`. `dartType: {type, import, converter?}` (R6.8). Кожен запис може мати `reason`. Ключі — camelCase, як в OpenAPI (конфіг лишається snake_case: `line_width`); `type` — один рядок, без списку типів 3.1; `exclude` — на операціях, схемах і властивостях, не на параметрах. **`sse` у M4 не приймається** (його форма — справа M10, а зміна форми потім зламала б файли користувачів): зараз це невідомий ключ, TOA803.
2. **`null` прибирає поле** специфікації (`format: null`, `type: null`): так закривається TOA204 (`format` на масиві) і TOA206 (`type: object` проти гілок). `type` — один рядок із семи типів JSON Schema, крім `null` (нульовість — через `nullable`).
3. **Семантика «set» (spec, рішення 4) на рівні поля запису:** кожне перелічене поле замінює значення специфікації цілком (`items`, `schema`, `discriminator` — об'єкт цілком), неперелічені лишаються.
4. **`$ref` у записі схеми чи властивості робить схему посиланням:** вузол замінюється цілком. Разом із `$ref` дозволені лише `nullable`, `reason`, поля генерації і `required` властивості; інші поля специфікації — TOA802 (рішення читача), `properties` у записі схеми з `$ref` — TOA802. Nullable-посилання: у 3.0 — `{allOf: [{$ref}], nullable: true}`, з 3.1 — `{anyOf: [{$ref}, {type: 'null'}]}`. Властивість, що вже є `$ref`, з override-ом `nullable` стає nullable-посиланням. M6 має читати обидві форми.
5. **Діалектний `nullable` (spec, рішення 5)** за версією, яку оголошує документ: у 3.0 `nullable: true` додається, `nullable: false` прибирає поле. З 3.1 `null` додається в `type` або прибирається з нього; `type` в override-і зберігає нульовість схеми (`[integer, 'null']` + `type: number` → `[number, 'null']`). `nullable: true` для схеми без `type` у 3.1+ — TOA802 «додай `type`».
6. **Цілі.** Схема — те, на чому закінчується ланцюжок `$ref` ключа `components.schemas` (зокрема в іншому файлі); властивість — вузол у власних `properties` цієї схеми, без переходу за `$ref` (змінюється лише ця властивість); параметр — вузол, що його визначає (параметр операції перекриває параметр шляху з тим самим `name` + `in`; `$ref` веде в `components.parameters`); тіло й відповідь — за `$ref`. Вебхуки, `additionalOperations` за `METHOD /path`, вкладені властивості й успадковані через `allOf` властивості не адресуються (див. «Відкладено»). **Спільний вузол:** коли override, адресований через операцію (її параметр, тіло, відповідь), має поля специфікації, а його вузол лежить поза операцією (параметр шляху, `$ref` на компонент, вузол в іншому файлі), — `TOA808 override-shared-target` (info) у позиції override-у: зміна стосується спільного вузла, повідомлення називає його місце (pointer, а для іншого файлу — `файл#pointer`). Override, адресований прямо ім'ям схеми, такої діагностики не дає.
7. **Конфлікти двох рівнів.** Адресний: два записи називають один вузол (`getPet` і `GET /pets/{id}`; `id` і `path:id` в одній операції; дві схеми-аліаси) — TOA806 на кожному, жоден не застосовується, вкладені записи операції чи схеми — теж. Правковий: дві *різні* правки, що перекриваються (`SpecEdit.overlaps`), від різних записів — TOA806 на кожному полі, обидві не робляться; однакові правки (`sameAs`) робляться один раз. Так спільний параметр шляху, який дві операції роблять `required: true`, — не конфлікт, а `required: [a]` схеми разом із `required: true` властивості — конфлікт.
8. **Тіло й відповідь.** `contentType` X: якщо X уже є — лишається тільки він; якщо media type один — він перейменовується на X; якщо немає жодного — додається `{X: {}}`; кілька і жоден не X — TOA805. `schema` без `contentType` — у єдиний media type; кілька — TOA805, жодного — TOA802 «додай `contentType`».
9. **«Нічого не змінив» (TOA807) — по полю**, у позиції поля, а не запису: запис може змінювати одне поле і повторювати інше. Порівняння — зі специфікацією, як її прочитано (до правил нормалізатора): override, який повторює виправлення правила, зайвим не позначається. Поля генерації не порівнюються.
10. **Застосування.** `Normalizer` читає модель один раз у тимчасовий журнал, розв'язує цілі, застосовує правки override-ів (`TreeEditor`, документи читаються один раз і передаються в проходи як `others`), а далі працює як у M3. Правка, яку не вдалося застосувати, — TOA800 у позиції override-у. Файл override-ів, який не можна використати (TOA801; TOA802 — синтаксис, корінь не об'єкт, каталог замість файлу з власним повідомленням «Overrides path … is a directory»), — помилка; `check` усе одно перевіряє специфікацію без нього, а `generate` (M9) мусить такого клієнта пропустити. Прогони `SpecChecker` розрізняються ще й файлом override-ів.
11. **Фрагменти в підказках (spec, рішення 9)** — лише там, де override повністю закриває дефект: `double-array` (TOA203: `items` ← внутрішні `items`), `format-on-array` (TOA204: `format: null` і `items: {type, format}` — лише коли тип елементів випливає з відомого формату: `int32`/`int64` → `integer`, `float`/`double` → `number`, рядкові формати OpenAPI і JSON Schema (`date`, `date-time`, `time`, `duration`, `uuid`, `byte`, `binary`, `password`, `email`, `uri`, `hostname`, `ipv4` тощо) → `string`; для невідомого формату фрагмента немає, діагностика лишається), `binary-object` (TOA205: `type: string`), `contradictory-object-type` (TOA206: `type: null`), `nullable-enum-one-of` (TOA303: `$ref` + `nullable: true`). Не отримують: `array-without-items` (тип елементів невідомий), `example-type-mismatch` (невідомо, що правильне — приклад чи схема), `path-param-not-in-template`, `duplicate-operation-id` (потрібне ім'я на проводі чи нове ім'я — вгадування), `wildcard-media-type` (невідомо, який media type), правила дискримінатора. Адреса — `schemas.<key>` або `schemas.<key>.properties.<name>`; ключ, що визначає схему, має перевагу над ключем-аліасом; без адреси фрагмента немає. Фрагмент — блоковий YAML, значення — flow-стиль, рядки, які YAML прочитав би інакше (`on`, `1.5`, `#/...`), — у лапках JSON. `TextReporter` зсуває рядки багаторядкового `fix` на 4 пробіли.
12. **Коди TOA801–TOA808** (TOA800 зайнятий).
13. **Невідомий ключ — помилка (TOA803)**, а не warning: одрук `nulable: true` інакше мовчки не застосовувався б. Якщо відомий ключ того самого рівня на відстані Левенштейна ≤ 2, `fix` починається з `Did you mean "<ключ>"?` (з кількох — найближчий, за рівної відстані — перший за абеткою); далі — перелік дозволених ключів.
14. **Позиція діагностики запису** — на значенні запису (`api.overrides.yaml:2:11`), а не на ключі: так компоновщик зберігає позиції за pointer; для запису блоком — перший ключ усередині.

**Відкладено.** Не адресуються в M4: вебхуки, `additionalOperations` 3.2 за `METHOD /path` (за `operationId` — так), вкладені властивості, властивості з `allOf`, схеми поза `components.schemas` (схему параметра чи тіла змінює лише `schema` цілком). Пункти «Перенесено з M3» у roadmap, призначені на M4 (URI з percent-кодуванням у ключах `SpecDocuments`, зсув позицій після правок списку, повторне читання файлу, що не завантажився), переходять у M6; roadmap оновлює контролер.

## Нові коди діагностики

| Код | Slug | Рівень | Коли | Задача | Spec |
|---|---|---|---|---|---|
| TOA801 | `overrides-not-found` | error | Файлу override-ів, який указує клієнт, немає | 1 | brief |
| TOA802 | `invalid-override` | error | Файл не читається (синтаксис, корінь не об'єкт, каталог, дублікати ключів — з рівнем джерела) або значення не того типу; значення ігнорується | 1, 3 | рішення 10 |
| TOA803 | `unknown-override-key` | error | Невідомий ключ (зокрема `sse`); ігнорується; «did you mean» для близького відомого | 1 | рішення 13 |
| TOA804 | `override-target-not-found` | warning | Ціль не знайдено | 2 | рішення 6 |
| TOA805 | `override-target-ambiguous` | error | Адреса називає кілька вузлів (`operationId` двічі, ім'я параметра в кількох `in`, кілька media types) | 2, 3 | рішення 8 |
| TOA806 | `override-conflict` | error | Два override-и одного вузла | 2, 3 | рішення 8 |
| TOA807 | `override-unchanged` | info | Специфікація вже має це значення; override можна прибрати | 3 | рішення 6 |
| TOA808 | `override-shared-target` | info | Override через операцію змінює спільний вузол (параметр шляху, `$ref`, інший файл) | 2 | рішення 6 |

## Файли

Шляхи відносно `packages/typed_openapi/`.

| Файл | Відповідальність | Задача |
|---|---|---|
| `lib/src/overrides/override_set.dart` | `OverrideSet`, `OverrideEntry` і підкласи, `DartTypeOverride` | 1 |
| `lib/src/overrides/override_loader.dart` | `OverrideLoader`: файл → `OverrideSet`, TOA801–TOA803 | 1 |
| `lib/src/overrides/override_resolver.dart` | `OverrideResolver`, `OverrideTarget` і підкласи; TOA804–TOA806, TOA808 | 2 |
| `lib/src/overrides/override_applier.dart` | `OverrideApplier`, `OverrideEdit`; поля → `SpecEdit`, TOA807, правкові конфлікти | 3 |
| `lib/src/normalize/normalizer.dart`, `lib/src/check/spec_checker.dart` | `overrides:` у `normalize`, `NormalizedSpec.overrides`; завантаження файлу клієнта | 3 |
| `lib/src/overrides/override_snippet.dart` | `OverrideSnippet`: місце → адреса, YAML | 4 |
| `lib/src/normalize/normalizer_rule.dart`, `rules/schema_shape_rules.dart`, `rules/enum_rules.dart`, `lib/src/diagnostics/reporters.dart` | `RuleContext.withOverride`, фрагменти в п'яти правилах, багаторядковий `fix` | 4 |
| `lib/src/diagnostics/diagnostic_code.dart` | нові коди | 1–3 |
| `lib/typed_openapi.dart`, `CLAUDE.md`, `CHANGELOG.md`, `README.md`, `README.ua.md` | Експорт і документація | 5 |

## Інтерфейси між задачами

```dart
// overrides/override_set.dart (Task 1)
final class DartTypeOverride { const DartTypeOverride({required String type,
  required String import, String? converter}); }
sealed class OverrideEntry { String key; JsonPointer pointer; String? reason;
  Map<String, Object?> spec; }                 // spec fields; null removes
final class OperationOverride extends OverrideEntry { String? operationId, method, path,
  name, group; bool? exclude; List<ParameterOverride> parameters;
  BodyOverride? requestBody; List<ResponseOverride> responses; }
final class ParameterOverride extends OverrideEntry { String parameterName;
  ParameterLocation? placement; String? name; DartTypeOverride? dartType; }
final class BodyOverride extends OverrideEntry {}
final class ResponseOverride extends OverrideEntry {}
final class SchemaOverride extends OverrideEntry { String? name; bool? exclude, exhaustive;
  DartTypeOverride? dartType; List<PropertyOverride> properties; }
final class PropertyOverride extends OverrideEntry { String? name; bool? exclude, triState;
  DartTypeOverride? dartType; }
final class OverrideSet { const OverrideSet(SpecDocument source,
  {List<OperationOverride> operations, List<SchemaOverride> schemas});
  String get file; bool get isEmpty; SourceSpan? spanOf(JsonPointer); }
final class OverrideLoader { const OverrideLoader(DiagnosticBag);
  OverrideSet? load(String path, {String? displayPath});
  OverrideSet? parse(String text, String file); OverrideSet read(SpecDocument); }

// overrides/override_resolver.dart (Task 2)
sealed class OverrideTarget { OverrideEntry get entry; SpecNode get node; }
OperationTarget(OperationOverride entry, Operation node);
ParameterTarget(ParameterOverride entry, Parameter node);
ContentTarget(OverrideEntry entry, SpecNode node);      // RequestBody or Response
SchemaTarget(SchemaOverride entry, SchemaObject node);
PropertyTarget(PropertyOverride entry, SchemaObject owner, Schema node);
final class OverrideResolver { const OverrideResolver(DiagnosticBag, OverrideSet);
  List<OverrideTarget> resolve(SpecModel model, SpecDocuments documents); }

// overrides/override_applier.dart, normalize (Task 3)
final class OverrideEdit { const OverrideEdit(SpecEdit edit,
  List<(OverrideEntry, String)> sources); }
final class OverrideApplier { const OverrideApplier(DiagnosticBag, OverrideSet,
  SpecDocuments, OpenApiVersion); List<OverrideEdit> edits(List<OverrideTarget>); }
NormalizedSpec Normalizer.normalize(SpecDocument, OpenApiVersion, {OverrideSet? overrides});
const NormalizedSpec(SpecModel, SpecDocuments, {OverrideSet? overrides});
OverrideSet? NormalizedSpec.overrides;

// overrides/override_snippet.dart, normalize (Task 4)
final class OverrideSnippet { const OverrideSnippet(SpecModel);
  List<String>? addressOf(SpecLocation); String? forSchema(SpecLocation, Map<String, Object?>); }
String RuleContext.withOverride(String fix, SpecLocation schema, Map<String, Object?> fields);
```

Кожну задачу перевірено так: код зібрано й перевірено на окремій гілці, потім задачі 1–5 відтворено з `main` (d33e8e8) лише з блоків коду цього плану (створення файлів, `git apply` diff-ів), і після кожної задачі `dart analyze packages` чистий, `dart format` удруге змінює 0 файлів, `dart test` зелений з кількістю тестів, указаною в задачі; кінцеве дерево збігається з перевіреним. Прогін `check` на публічному корпусі (14 специфікацій) після задачі 5 дає той самий JSON-звіт, що й `main` (1029 діагностик: 2 error, 853 warning, 174 info; у корпусі немає ні override-ів, ні знахідок TOA203–TOA206/TOA303).

---

### Task 1: Файл override-ів: `OverrideSet` і `OverrideLoader` (TOA801–TOA803)

**Files:**
- Create: `packages/typed_openapi/lib/src/overrides/override_set.dart`, `packages/typed_openapi/lib/src/overrides/override_loader.dart`, `packages/typed_openapi/test/overrides/override_loader_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`

**Interfaces:**
- Consumes: `SpecLoader` (`load`, `parse`), `SpecDocument` (`root`, `file`, `spanOf`), `DiagnosticBag`, `JsonPointer`, `ParameterLocation`, `PathItem.methods`, `SchemaType` (M1–M3).
- Produces: блок «override_set.dart (Task 1)» з «Інтерфейсів»; коди `overridesNotFound` (TOA801), `invalidOverride` (TOA802), `unknownOverrideKey` (TOA803).

Поведінка, яку закріплюють тести:
- Повний файл (усі розділи, ключ `operationId` і `METHOD /path`, `in:name`, `dartType` з `converter`, `format: null`, `$ref` + `nullable`) читається без діагностики; поля специфікації — у `spec` у порядку файлу, поля генерації — типізовані; JSON читається так само; `{}` — порожній набір без діагностики.
- Відсутній файл — TOA801 (`null`); синтаксична помилка й корінь не-об'єкт — TOA802 (`null`); дублікат ключа — TOA802 з рівнем, який дав компоновщик; файл з диска називається `displayPath`, позиція — рядок:колонка значення.
- Невідомі ключі на кожному рівні (корінь, операція, параметр, тіло, відповідь, схема, `dartType`, властивість) — TOA803 (error), решта запису читається; `nulable` — підказка `Did you mean "nullable"?`, далекий ключ (`exhaustiveness`) і `sse` — без підказки.
- Каталог замість файлу — TOA802 «Overrides path … is a directory, not a file.» з підказкою про `overrides` клієнта.
- Значення не того типу — TOA802 у pointer поля, ігнорується лише воно (запис-не-мапа ігнорується цілком).
- `$ref` із полем специфікації, крім `nullable` (і `required` властивості), — TOA802 на полі; `properties` у записі схеми з `$ref` — TOA802, властивості відкидаються.
- `FETCH /pets` — TOA802, запис відкидається; `body:id` — TOA802, параметр відкидається.

- [ ] **Step 1: Коди**

Diff `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart` (`git apply` з кореня):

```diff
diff --git a/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart b/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart
index 6933785..9cd1d37 100644
--- a/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart
+++ b/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart
@@ -202,6 +202,17 @@ enum DiagnosticCode {
   /// gone, or the spec kept changing after the last pass.
   fixNotApplied('TOA800', 'fix-not-applied', .warning),
 
+  /// The overrides file a client names does not exist.
+  overridesNotFound('TOA801', 'overrides-not-found', .error),
+
+  /// The overrides file cannot be read, or an override has a value of the
+  /// wrong type; the value is ignored.
+  invalidOverride('TOA802', 'invalid-override', .error),
+
+  /// An override has a key this tool does not know, such as a misspelled
+  /// field; it is ignored.
+  unknownOverrideKey('TOA803', 'unknown-override-key', .error),
+
   /// The configuration file does not exist.
   configNotFound('TOA901', 'config-not-found', .error),
 
```

- [ ] **Step 2: Тест, що не проходить**

Створи `packages/typed_openapi/test/overrides/override_loader_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/model/operation.dart';
import 'package:typed_openapi/src/overrides/override_loader.dart';
import 'package:typed_openapi/src/overrides/override_set.dart';

import '../helpers/temp_dir.dart';

void main() {
  OverrideSet? parse(
    DiagnosticBag bag,
    String text, {
    String file = 'o.yaml',
  }) => OverrideLoader(bag).parse(text, file);

  test('reads every section and field without diagnostics', () {
    final bag = DiagnosticBag();
    final set = parse(bag, r'''
operations:
  getPet:
    reason: the backend forgets 404
    name: fetchPet
    exclude: false
    group: pets
    parameters:
      id:
        required: true
        schema: {type: integer, format: int64}
        name: petId
        dartType: {type: PetId, import: 'package:app/pet_id.dart'}
      query:id: {required: false}
    requestBody:
      contentType: application/json
      schema: {$ref: '#/components/schemas/NewPet'}
    responses:
      '200':
        contentType: text/event-stream
  POST /pets:
    exclude: true
schemas:
  Pet:
    reason: nullable in practice
    type: object
    nullable: true
    required: [id]
    exhaustive: false
    name: PetModel
    dartType:
      type: Pet
      import: package:app/pet.dart
      converter: PetConverter
    properties:
      tag:
        format: null
        required: true
        triState: true
  Owner:
    $ref: '#/components/schemas/Person'
    nullable: true
''')!;
    expect(bag.all, isEmpty);
    expect(set.file, 'o.yaml');
    final [get, post] = set.operations;
    expect(get.operationId, 'getPet');
    expect(get.method, isNull);
    expect(get.reason, 'the backend forgets 404');
    expect((get.name, get.exclude, get.group), ('fetchPet', false, 'pets'));
    final [id, queryId] = get.parameters;
    expect(id.parameterName, 'id');
    expect(id.placement, isNull);
    expect(id.spec, {
      'required': true,
      'schema': {'type': 'integer', 'format': 'int64'},
    });
    expect(id.name, 'petId');
    expect(id.dartType?.import, 'package:app/pet_id.dart');
    expect(queryId.parameterName, 'id');
    expect(queryId.placement, ParameterLocation.query);
    expect(get.requestBody?.spec, {
      'contentType': 'application/json',
      'schema': {r'$ref': '#/components/schemas/NewPet'},
    });
    expect(get.responses.single.key, '200');
    expect(get.responses.single.spec, {'contentType': 'text/event-stream'});
    expect(post.operationId, isNull);
    expect((post.method, post.path, post.exclude), ('post', '/pets', true));
    final [pet, owner] = set.schemas;
    expect(pet.key, 'Pet');
    expect(pet.pointer.value, '#/schemas/Pet');
    expect(pet.spec, {
      'type': 'object',
      'nullable': true,
      'required': ['id'],
    });
    expect((pet.exhaustive, pet.name), (false, 'PetModel'));
    expect(pet.dartType?.converter, 'PetConverter');
    final tag = pet.properties.single;
    expect(tag.pointer.value, '#/schemas/Pet/properties/tag');
    expect(tag.spec, {'format': null, 'required': true});
    expect(tag.triState, isTrue);
    expect(owner.spec, {
      r'$ref': '#/components/schemas/Person',
      'nullable': true,
    });
  });

  test('reads a JSON file', () {
    final bag = DiagnosticBag();
    final set = parse(
      bag,
      '{"schemas": {"Pet": {"type": "string"}}}',
      file: 'o.json',
    )!;
    expect(bag.all, isEmpty);
    expect(set.schemas.single.spec, {'type': 'string'});
  });

  test('an empty file is an empty set', () {
    final bag = DiagnosticBag();
    expect(parse(bag, '{}')!.isEmpty, isTrue);
    expect(bag.all, isEmpty);
  });

  test('reports a missing file', () {
    final bag = DiagnosticBag();
    expect(OverrideLoader(bag).load('/nope/o.yaml'), isNull);
    expect(bag.all.single.code, DiagnosticCode.overridesNotFound);
    expect(bag.all.single.file, '/nope/o.yaml');
  });

  test('loads a file from disk and names it by its display path', () {
    final dir = TempDir();
    final path = dir.write('o.yaml', 'schemas: {Pet: {type: 1}}\n');
    final bag = DiagnosticBag();
    final set = OverrideLoader(bag).load(path, displayPath: 'o.yaml')!;
    expect(set.schemas.single.spec, isEmpty);
    expect(bag.all.single.code, DiagnosticCode.invalidOverride);
    expect(bag.all.single.location, 'o.yaml:1:23');
  });

  test('a directory as the overrides path is an invalid overrides file', () {
    final dir = TempDir();
    final bag = DiagnosticBag();
    expect(OverrideLoader(bag).load(dir.path, displayPath: 'o'), isNull);
    final d = bag.all.single;
    expect(d.code, DiagnosticCode.invalidOverride);
    expect(d.message, 'Overrides path o is a directory, not a file.');
    expect(d.fix, contains('"overrides"'));
  });

  test('a syntax error or a non-object root is an invalid file', () {
    final bag = DiagnosticBag();
    expect(parse(bag, 'schemas: [\n'), isNull);
    expect(parse(bag, '- a\n'), isNull);
    expect(bag.all.map((d) => d.code), [
      DiagnosticCode.invalidOverride,
      DiagnosticCode.invalidOverride,
    ]);
  });

  test('a duplicate key is reported as a problem of the overrides file', () {
    final bag = DiagnosticBag();
    parse(bag, 'schemas:\n  Pet: {type: string}\n  Pet: {type: integer}\n');
    expect(bag.all.single.code, DiagnosticCode.invalidOverride);
  });

  test('reports unknown keys at every level and reads the rest', () {
    final bag = DiagnosticBag();
    final set = parse(bag, '''
paths: {}
operations:
  getPet:
    summary: x
    parameters:
      id: {in: path}
    requestBody: {required: true}
    responses:
      '200': {headers: {}}
schemas:
  Pet:
    title: x
    dartType: {type: P, import: p.dart, from: x}
    properties:
      id: {nullabel: true, nullable: true}
''')!;
    expect(
      [for (final d in bag.sorted) (d.code, d.pointer?.value)],
      [
        (DiagnosticCode.unknownOverrideKey, '#/paths'),
        (DiagnosticCode.unknownOverrideKey, '#/operations/getPet/summary'),
        (
          DiagnosticCode.unknownOverrideKey,
          '#/operations/getPet/parameters/id/in',
        ),
        (
          DiagnosticCode.unknownOverrideKey,
          '#/operations/getPet/requestBody/required',
        ),
        (
          DiagnosticCode.unknownOverrideKey,
          '#/operations/getPet/responses/200/headers',
        ),
        (DiagnosticCode.unknownOverrideKey, '#/schemas/Pet/title'),
        (DiagnosticCode.unknownOverrideKey, '#/schemas/Pet/dartType/from'),
        (
          DiagnosticCode.unknownOverrideKey,
          '#/schemas/Pet/properties/id/nullabel',
        ),
      ],
    );
    expect(set.schemas.single.properties.single.spec, {'nullable': true});
    expect(set.schemas.single.dartType?.type, 'P');
  });

  test('an unknown key is an error that suggests a close known key', () {
    final bag = DiagnosticBag();
    final set = parse(bag, '''
schemas:
  Pet:
    properties:
      id: {nulable: true, type: string}
    exhaustiveness: false
operations:
  getPet:
    responses:
      '200': {sse: {type: object}}
''')!;
    final [typo, far, sse] = bag.sorted;
    expect(typo.code, DiagnosticCode.unknownOverrideKey);
    expect(typo.severity, Severity.error);
    expect(typo.pointer?.value, '#/schemas/Pet/properties/id/nulable');
    expect(
      typo.fix,
      startsWith('Did you mean "nullable"? Allowed keys here: '),
    );
    expect(far.pointer?.value, '#/schemas/Pet/exhaustiveness');
    expect(far.fix, startsWith('Allowed keys here: '));
    expect(sse.pointer?.value, '#/operations/getPet/responses/200/sse');
    expect(sse.fix, startsWith('Allowed keys here: '));
    expect(set.schemas.single.properties.single.spec, {'type': 'string'});
  });

  test('reports values of the wrong type and ignores only them', () {
    final bag = DiagnosticBag();
    final set = parse(bag, '''
operations:
  getPet:
    name: ''
    exclude: yes
    parameters:
      id: {required: 1, schema: string}
    requestBody: {contentType: json}
    responses: []
  listPets: 1
schemas:
  Pet:
    type: 'null'
    nullable: 'true'
    required: [1]
    enum: []
    items: [1]
    additionalProperties: 1
    exhaustive: 0
    dartType: {type: Pet}
    format: date
    properties:
      id: {required: [id], type: string}
''')!;
    expect(
      [for (final d in bag.sorted) d.pointer?.value],
      [
        '#/operations/getPet/name',
        '#/operations/getPet/exclude',
        '#/operations/getPet/parameters/id/required',
        '#/operations/getPet/parameters/id/schema',
        '#/operations/getPet/requestBody/contentType',
        '#/operations/getPet/responses',
        '#/operations/listPets',
        '#/schemas/Pet/type',
        '#/schemas/Pet/nullable',
        '#/schemas/Pet/required',
        '#/schemas/Pet/enum',
        '#/schemas/Pet/items',
        '#/schemas/Pet/additionalProperties',
        '#/schemas/Pet/exhaustive',
        '#/schemas/Pet/dartType',
        '#/schemas/Pet/properties/id/required',
      ],
    );
    expect(
      bag.all.every((d) => d.code == DiagnosticCode.invalidOverride),
      isTrue,
    );
    final get = set.operations.single;
    expect((get.name, get.exclude), (null, null));
    expect(get.parameters.single.spec, isEmpty);
    expect(get.requestBody?.spec, isEmpty);
    final pet = set.schemas.single;
    expect(pet.spec, {'format': 'date'});
    expect(pet.dartType, isNull);
    expect(pet.properties.single.spec, {'type': 'string'});
  });

  test(r'"$ref" replaces the schema: other schema fields are reported', () {
    final bag = DiagnosticBag();
    final set = parse(bag, r'''
schemas:
  Pet:
    $ref: '#/components/schemas/Animal'
    nullable: true
    type: object
    name: Animal
    properties:
      id: {type: string}
  Owner:
    properties:
      pet:
        $ref: '#/components/schemas/Pet'
        required: true
        format: uuid
''')!;
    expect(
      [for (final d in bag.sorted) (d.code, d.pointer?.value)],
      [
        (DiagnosticCode.invalidOverride, '#/schemas/Pet/type'),
        (DiagnosticCode.invalidOverride, '#/schemas/Pet/properties'),
        (
          DiagnosticCode.invalidOverride,
          '#/schemas/Owner/properties/pet/format',
        ),
      ],
    );
    final [pet, owner] = set.schemas;
    expect(pet.spec.keys, [r'$ref', 'nullable']);
    expect(pet.name, 'Animal');
    expect(pet.properties, isEmpty);
    expect(owner.properties.single.spec.keys, [r'$ref', 'required']);
  });

  test('reports an operation key with an unknown method and a parameter '
      'key with an unknown "in"', () {
    final bag = DiagnosticBag();
    final set = parse(bag, '''
operations:
  FETCH /pets: {name: fetch}
  GET /pets:
    parameters:
      body:id: {required: true}
      path:id: {required: true}
''')!;
    expect(
      [for (final d in bag.sorted) d.pointer?.value],
      [
        '#/operations/FETCH ~1pets',
        '#/operations/GET ~1pets/parameters/body:id',
      ],
    );
    final get = set.operations.single;
    expect((get.method, get.path), ('get', '/pets'));
    expect(get.parameters.single.placement, ParameterLocation.path);
  });
}
```

- [ ] **Step 3: Запустити тест**

Run (з `packages/typed_openapi`): `dart test test/overrides/override_loader_test.dart`
Expected: FAIL — `override_loader.dart` і `override_set.dart` не існують.

- [ ] **Step 4: Модель і читач**

Створи `packages/typed_openapi/lib/src/overrides/override_set.dart`:

```dart
import 'package:source_span/source_span.dart';

import '../diagnostics/json_pointer.dart';
import '../load/spec_document.dart';
import '../model/operation.dart';

/// A Dart type that a schema, a property or a parameter uses instead of the
/// generated one (R6.8).
final class DartTypeOverride {
  /// Creates a Dart type override.
  const DartTypeOverride({
    required this.type,
    required this.import,
    this.converter,
  });

  /// The Dart type, such as `Money`.
  final String type;

  /// The library that declares [type], such as `package:app/money.dart`.
  final String import;

  /// A class with `fromJson` and `toJson` that converts [type], when the
  /// type itself has no such members.
  final String? converter;
}

/// What every entry of the overrides file has.
sealed class OverrideEntry {
  /// Creates an entry.
  const OverrideEntry({
    required this.key,
    required this.pointer,
    this.reason,
    this.spec = const {},
  });

  /// The key of the entry as written, such as `getPet` or `id`.
  final String key;

  /// Where the entry is in the overrides file.
  final JsonPointer pointer;

  /// Why the override exists; printed in diagnostics about it.
  final String? reason;

  /// The fields that change the spec, by name, in file order; a `null` value
  /// removes the field from the spec.
  final Map<String, Object?> spec;
}

/// An override of an operation, addressed by `operationId` or by
/// `METHOD /path`.
final class OperationOverride extends OverrideEntry {
  /// Creates an operation override.
  const OperationOverride({
    required super.key,
    required super.pointer,
    super.reason,
    this.operationId,
    this.method,
    this.path,
    this.name,
    this.exclude,
    this.group,
    this.parameters = const [],
    this.requestBody,
    this.responses = const [],
  });

  /// The `operationId` the key names, when it is not `METHOD /path`.
  final String? operationId;

  /// The lowercase method of a `METHOD /path` key.
  final String? method;

  /// The path template of a `METHOD /path` key.
  final String? path;

  /// The name of the generated method.
  final String? name;

  /// Whether the operation is left out of the client.
  final bool? exclude;

  /// The group (API class) the operation belongs to.
  final String? group;

  /// Overrides of the operation's parameters.
  final List<ParameterOverride> parameters;

  /// The override of the request body.
  final BodyOverride? requestBody;

  /// Overrides of responses, by status code.
  final List<ResponseOverride> responses;
}

/// An override of a parameter, addressed by name, or by `in:name` when
/// several parameters share the name.
final class ParameterOverride extends OverrideEntry {
  /// Creates a parameter override.
  const ParameterOverride({
    required super.key,
    required super.pointer,
    required this.parameterName,
    super.reason,
    super.spec,
    this.placement,
    this.name,
    this.dartType,
  });

  /// The name of the parameter in the spec.
  final String parameterName;

  /// The `in` of an `in:name` key.
  final ParameterLocation? placement;

  /// The name of the generated argument.
  final String? name;

  /// The Dart type of the argument.
  final DartTypeOverride? dartType;
}

/// An override of an operation's request body.
final class BodyOverride extends OverrideEntry {
  /// Creates a request body override.
  const BodyOverride({
    required super.key,
    required super.pointer,
    super.reason,
    super.spec,
  });
}

/// An override of an operation's response, addressed by status code.
final class ResponseOverride extends OverrideEntry {
  /// Creates a response override.
  const ResponseOverride({
    required super.key,
    required super.pointer,
    super.reason,
    super.spec,
  });
}

/// An override of a schema, addressed by its key in `components.schemas`.
final class SchemaOverride extends OverrideEntry {
  /// Creates a schema override.
  const SchemaOverride({
    required super.key,
    required super.pointer,
    super.reason,
    super.spec,
    this.name,
    this.exclude,
    this.exhaustive,
    this.dartType,
    this.properties = const [],
  });

  /// The name of the generated type.
  final String? name;

  /// Whether the schema is left out of the client.
  final bool? exclude;

  /// Whether an enum or a union is generated as exhaustive.
  final bool? exhaustive;

  /// The Dart type every use of the schema gets instead of a generated one.
  final DartTypeOverride? dartType;

  /// Overrides of the schema's properties.
  final List<PropertyOverride> properties;
}

/// An override of a property of a schema, addressed by the property name.
final class PropertyOverride extends OverrideEntry {
  /// Creates a property override.
  const PropertyOverride({
    required super.key,
    required super.pointer,
    super.reason,
    super.spec,
    this.name,
    this.exclude,
    this.dartType,
    this.triState,
  });

  /// The name of the generated field.
  final String? name;

  /// Whether the property is left out of the generated model.
  final bool? exclude;

  /// The Dart type of the field.
  final DartTypeOverride? dartType;

  /// Whether the field tells "absent" from `null`.
  final bool? triState;
}

/// The overrides of one client, read from its overrides file.
final class OverrideSet {
  /// Creates a set read from [_source].
  const OverrideSet(
    this._source, {
    this.operations = const [],
    this.schemas = const [],
  });

  final SpecDocument _source;

  /// Operation overrides, in file order.
  final List<OperationOverride> operations;

  /// Schema overrides, in file order.
  final List<SchemaOverride> schemas;

  /// The overrides file as shown to the user.
  String get file => _source.file;

  /// Whether the file has no override.
  bool get isEmpty => operations.isEmpty && schemas.isEmpty;

  /// The source range of the node at [pointer] in [file], if known.
  SourceSpan? spanOf(JsonPointer pointer) => _source.spanOf(pointer);
}
```

Створи `packages/typed_openapi/lib/src/overrides/override_loader.dart`:

```dart
import 'dart:io';

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/json_pointer.dart';
import '../load/spec_document.dart';
import '../load/spec_loader.dart';
import '../model/operation.dart';
import '../model/schema.dart';
import 'override_set.dart';

/// Reads a client's overrides file (`typed_openapi.overrides.yaml`, JSON or
/// YAML) into an [OverrideSet].
///
/// Every problem goes to the [DiagnosticBag] given to the constructor, at
/// its position in the overrides file: a missing file is
/// `overrides-not-found`, text that cannot be read and values of the wrong
/// type are `invalid-override`, unknown keys `unknown-override-key`. A bad
/// value is ignored and the rest of the file is read.
final class OverrideLoader {
  /// Creates a loader that reports to [_diagnostics].
  const OverrideLoader(this._diagnostics);

  final DiagnosticBag _diagnostics;

  /// Reads the overrides file at [path]; [displayPath] names it in
  /// diagnostics. Returns null when the file cannot be used at all.
  OverrideSet? load(String path, {String? displayPath}) {
    final file = displayPath ?? path;
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) {
      _diagnostics.report(
        .overridesNotFound,
        'Overrides file $file does not exist.',
        file: file,
        fix: 'Create it, or fix "overrides" of this client in the config.',
      );
      return null;
    }
    if (type == FileSystemEntityType.directory) {
      _diagnostics.report(
        .invalidOverride,
        'Overrides path $file is a directory, not a file.',
        file: file,
        fix: 'Point "overrides" of this client at the overrides file itself.',
      );
      return null;
    }
    final scratch = DiagnosticBag();
    final document = SpecLoader(scratch).load(path, displayPath: file);
    _forward(scratch);
    return document == null ? null : read(document);
  }

  /// Reads overrides from [text]; [file] names it in diagnostics and tells
  /// JSON from YAML by its extension.
  OverrideSet? parse(String text, String file) {
    final scratch = DiagnosticBag();
    final document = SpecLoader(scratch).parse(text, file);
    _forward(scratch);
    return document == null ? null : read(document);
  }

  /// Reads the overrides in an already loaded [document].
  OverrideSet read(SpecDocument document) =>
      _OverrideReader(_diagnostics, document).read();

  /// Reports what the spec loader said about the file as problems of the
  /// overrides file.
  void _forward(DiagnosticBag scratch) {
    for (final d in scratch.all) {
      _diagnostics.report(
        d.code == .positionsUnavailable ? d.code : .invalidOverride,
        d.message,
        severity: d.severity,
        file: d.file,
        pointer: d.pointer,
        span: d.span,
        fix: d.fix,
      );
    }
  }
}

/// One read of an overrides document.
final class _OverrideReader {
  _OverrideReader(this._diagnostics, this._document);

  static const _sections = {'operations', 'schemas'};
  static const _operationKeys = {
    'reason',
    'name',
    'exclude',
    'group',
    'parameters',
    'requestBody',
    'responses',
  };
  static const _parameterKeys = {
    'reason',
    'required',
    'schema',
    'name',
    'dartType',
  };
  static const _bodyKeys = {'reason', 'contentType', 'schema'};
  static const _responseKeys = {'reason', 'contentType', 'schema'};

  /// Fields that change a schema, in the order they are applied.
  static const _schemaFields = [
    r'$ref',
    'type',
    'nullable',
    'format',
    'required',
    'items',
    'additionalProperties',
    'enum',
    'discriminator',
  ];
  static const _schemaKeys = {
    'reason',
    ..._schemaFields,
    'name',
    'exclude',
    'exhaustive',
    'dartType',
    'properties',
  };
  static const _propertyKeys = {
    'reason',
    ..._schemaFields,
    'name',
    'exclude',
    'dartType',
    'triState',
  };
  static const _dartTypeKeys = {'type', 'import', 'converter'};

  static final _methodAndPath = RegExp(r'^([A-Za-z]+) (/.*)$');

  final DiagnosticBag _diagnostics;
  final SpecDocument _document;

  OverrideSet read() {
    final root = _document.root;
    _checkKeys(root, _sections, .root);
    return OverrideSet(
      _document,
      operations: [
        for (final (key, entry, at) in _entries(root, 'operations', .root))
          ?_operation(key, entry, at),
      ],
      schemas: [
        for (final (key, entry, at) in _entries(root, 'schemas', .root))
          _schema(key, entry, at),
      ],
    );
  }

  OperationOverride? _operation(
    String key,
    Map<String, Object?> entry,
    JsonPointer at,
  ) {
    _checkKeys(entry, _operationKeys, at);
    String? method;
    String? path;
    if (_methodAndPath.firstMatch(key) case final match?) {
      method = match[1]!.toLowerCase();
      path = match[2];
      if (!PathItem.methods.contains(method)) {
        _invalid(
          'The method "${match[1]}" is not an OpenAPI operation method.',
          at,
          fix:
              'Write the key as an operationId, or as METHOD /path with one '
              'of ${PathItem.methods.map((m) => m.toUpperCase()).join(', ')}.',
        );
        return null;
      }
    }
    final body = _map(entry, 'requestBody', at);
    return OperationOverride(
      key: key,
      pointer: at,
      reason: _string(entry, 'reason', at),
      operationId: method == null ? key : null,
      method: method,
      path: path,
      name: _string(entry, 'name', at),
      exclude: _bool(entry, 'exclude', at),
      group: _string(entry, 'group', at),
      parameters: [
        for (final (name, value, p) in _entries(entry, 'parameters', at))
          ?_parameter(name, value, p),
      ],
      requestBody: body == null ? null : _body(body, at.child('requestBody')),
      responses: [
        for (final (status, value, p) in _entries(entry, 'responses', at))
          _response(status, value, p),
      ],
    );
  }

  ParameterOverride? _parameter(
    String key,
    Map<String, Object?> entry,
    JsonPointer at,
  ) {
    _checkKeys(entry, _parameterKeys, at);
    var name = key;
    ParameterLocation? placement;
    final colon = key.indexOf(':');
    if (colon > 0) {
      placement = ParameterLocation.values.asNameMap()[key.substring(0, colon)];
      if (placement == null) {
        _invalid(
          'The parameter key "$key" has no valid "in" before ":".',
          at,
          fix:
              'Write in:name with in one of '
              '${ParameterLocation.values.map((l) => l.name).join(', ')}.',
        );
        return null;
      }
      name = key.substring(colon + 1);
    }
    return ParameterOverride(
      key: key,
      pointer: at,
      parameterName: name,
      placement: placement,
      reason: _string(entry, 'reason', at),
      spec: {
        if (entry.containsKey('required'))
          'required': ?_bool(entry, 'required', at),
        if (entry.containsKey('schema')) 'schema': ?_map(entry, 'schema', at),
      },
      name: _string(entry, 'name', at),
      dartType: _dartType(entry, at),
    );
  }

  BodyOverride _body(Map<String, Object?> entry, JsonPointer at) {
    _checkKeys(entry, _bodyKeys, at);
    return BodyOverride(
      key: 'requestBody',
      pointer: at,
      reason: _string(entry, 'reason', at),
      spec: _contentSpec(entry, at),
    );
  }

  ResponseOverride _response(
    String status,
    Map<String, Object?> entry,
    JsonPointer at,
  ) {
    _checkKeys(entry, _responseKeys, at);
    return ResponseOverride(
      key: status,
      pointer: at,
      reason: _string(entry, 'reason', at),
      spec: _contentSpec(entry, at),
    );
  }

  Map<String, Object?> _contentSpec(
    Map<String, Object?> entry,
    JsonPointer at,
  ) {
    final contentType = _string(entry, 'contentType', at);
    if (contentType != null && !contentType.contains('/')) {
      _invalid(
        '"contentType" must be a media type such as application/json.',
        at.child('contentType'),
      );
    }
    return {
      if (contentType != null && contentType.contains('/'))
        'contentType': contentType,
      if (entry.containsKey('schema')) 'schema': ?_map(entry, 'schema', at),
    };
  }

  SchemaOverride _schema(
    String key,
    Map<String, Object?> entry,
    JsonPointer at,
  ) {
    _checkKeys(entry, _schemaKeys, at);
    final spec = _schemaSpec(entry, at, property: false);
    final properties = [
      for (final (name, value, p) in _entries(entry, 'properties', at))
        _property(name, value, p),
    ];
    if (spec.containsKey(r'$ref') && properties.isNotEmpty) {
      _invalid(
        r'"properties" cannot be combined with "$ref": the schema becomes the '
        'reference.',
        at.child('properties'),
      );
      properties.clear();
    }
    return SchemaOverride(
      key: key,
      pointer: at,
      reason: _string(entry, 'reason', at),
      spec: spec,
      name: _string(entry, 'name', at),
      exclude: _bool(entry, 'exclude', at),
      exhaustive: _bool(entry, 'exhaustive', at),
      dartType: _dartType(entry, at),
      properties: properties,
    );
  }

  PropertyOverride _property(
    String key,
    Map<String, Object?> entry,
    JsonPointer at,
  ) {
    _checkKeys(entry, _propertyKeys, at);
    return PropertyOverride(
      key: key,
      pointer: at,
      reason: _string(entry, 'reason', at),
      spec: _schemaSpec(entry, at, property: true),
      name: _string(entry, 'name', at),
      exclude: _bool(entry, 'exclude', at),
      dartType: _dartType(entry, at),
      triState: _bool(entry, 'triState', at),
    );
  }

  /// The schema fields of [entry]; for a [property], `required` is a
  /// boolean, else the list of required property names.
  Map<String, Object?> _schemaSpec(
    Map<String, Object?> entry,
    JsonPointer at, {
    required bool property,
  }) {
    final spec = <String, Object?>{};
    for (final field in _schemaFields) {
      if (!entry.containsKey(field)) continue;
      final value = entry[field];
      final valid = switch (field) {
        r'$ref' => value is String && value.isNotEmpty,
        'type' =>
          value == null ||
              SchemaType.values.any(
                (t) => t.wire == value && t != SchemaType.nullType,
              ),
        'nullable' => value is bool,
        'format' => value == null || value is String,
        'required' when property => value is bool,
        'required' =>
          value == null || value is List<Object?> && value.every(_isName),
        'items' || 'discriminator' => value == null || value is Map,
        'additionalProperties' =>
          value == null || value is bool || value is Map,
        'enum' => value == null || value is List<Object?> && value.isNotEmpty,
        _ => false,
      };
      if (!valid) {
        _invalid(
          '"$field" ${_expected(field, property: property)}.',
          at.child(field),
        );
        continue;
      }
      spec[field] = value;
    }
    if (spec.containsKey(r'$ref')) {
      for (final field in spec.keys.toList()) {
        if (field == r'$ref' || field == 'nullable') continue;
        if (field == 'required' && property) continue;
        _invalid(
          '"$field" cannot be combined with "\$ref": the schema becomes the '
          'reference.',
          at.child(field),
        );
        spec.remove(field);
      }
    }
    return spec;
  }

  static bool _isName(Object? value) => value is String && value.isNotEmpty;

  static String _expected(String field, {required bool property}) =>
      switch (field) {
        r'$ref' => 'must be a non-empty string',
        'type' =>
          'must be one of string, number, integer, boolean, array, object, or '
              'null to remove it (use "nullable" for null)',
        'nullable' => 'must be true or false',
        'format' => 'must be a string, or null to remove it',
        'required' when property => 'must be true or false',
        'required' => 'must be a list of property names, or null to remove it',
        'items' || 'discriminator' => 'must be an object, or null to remove it',
        'additionalProperties' =>
          'must be true, false or an object, or null to remove it',
        _ => 'must be a non-empty list, or null to remove it',
      };

  DartTypeOverride? _dartType(Map<String, Object?> entry, JsonPointer at) {
    final value = _map(entry, 'dartType', at);
    if (value == null) return null;
    final p = at.child('dartType');
    _checkKeys(value, _dartTypeKeys, p);
    final type = _string(value, 'type', p, required: true);
    final import = _string(value, 'import', p, required: true);
    final converter = _string(value, 'converter', p);
    if (type == null || import == null) return null;
    return DartTypeOverride(type: type, import: import, converter: converter);
  }

  /// The entries of the [key] mapping of [parent] whose values are
  /// mappings, with their pointers; other values are reported.
  List<(String, Map<String, Object?>, JsonPointer)> _entries(
    Map<String, Object?> parent,
    String key,
    JsonPointer at,
  ) {
    final section = _map(parent, key, at);
    if (section == null) return const [];
    final p = at.child(key);
    final entries = <(String, Map<String, Object?>, JsonPointer)>[];
    for (final MapEntry(key: name, :value) in section.entries) {
      if (value is Map<String, Object?>) {
        entries.add((name, value, p.child(name)));
      } else {
        _invalid('"$name" must be a mapping.', p.child(name));
      }
    }
    return entries;
  }

  Map<String, Object?>? _map(
    Map<String, Object?> parent,
    String key,
    JsonPointer at,
  ) {
    if (!parent.containsKey(key)) return null;
    final value = parent[key];
    if (value is Map<String, Object?>) return value;
    _invalid('"$key" must be a mapping.', at.child(key));
    return null;
  }

  String? _string(
    Map<String, Object?> parent,
    String key,
    JsonPointer at, {
    bool required = false,
  }) {
    if (!parent.containsKey(key)) {
      if (required) _invalid('"$key" is required.', at);
      return null;
    }
    final value = parent[key];
    if (value is String && value.isNotEmpty) return value;
    _invalid('"$key" must be a non-empty string.', at.child(key));
    return null;
  }

  bool? _bool(Map<String, Object?> parent, String key, JsonPointer at) {
    if (!parent.containsKey(key)) return null;
    final value = parent[key];
    if (value is bool) return value;
    _invalid('"$key" must be true or false.', at.child(key));
    return null;
  }

  void _checkKeys(
    Map<String, Object?> map,
    Set<String> allowed,
    JsonPointer at,
  ) {
    final known = allowed.toList()..sort();
    for (final key in map.keys) {
      if (allowed.contains(key)) continue;
      final closest = _closest(key, known);
      _diagnostics.report(
        .unknownOverrideKey,
        'Unknown key "$key"; it is ignored.',
        file: _document.file,
        pointer: at.child(key),
        span: _document.spanOf(at.child(key)),
        fix:
            '${closest == null ? '' : 'Did you mean "$closest"? '}'
            'Allowed keys here: ${known.join(', ')}.',
      );
    }
  }

  /// The first of the sorted [known] keys at the smallest edit distance
  /// from [key], when that distance is at most [_maxTypoDistance].
  static String? _closest(String key, List<String> known) {
    String? best;
    var bestDistance = _maxTypoDistance + 1;
    for (final candidate in known) {
      final distance = _distance(key, candidate);
      if (distance < bestDistance) {
        best = candidate;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// How many edits a key may be away from a known key to be suggested.
  static const _maxTypoDistance = 2;

  /// The Levenshtein distance between [a] and [b].
  static int _distance(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final substitution = a[i - 1] == b[j - 1] ? 0 : 1;
        current[j] = [
          previous[j] + 1,
          current[j - 1] + 1,
          previous[j - 1] + substitution,
        ].reduce((x, y) => x < y ? x : y);
      }
      previous = current;
    }
    return previous[b.length];
  }

  void _invalid(String message, JsonPointer at, {String? fix}) {
    _diagnostics.report(
      DiagnosticCode.invalidOverride,
      message,
      file: _document.file,
      pointer: at,
      span: _document.spanOf(at),
      fix: fix,
    );
  }
}
```

- [ ] **Step 5: Перевірити**

Run (з `packages/typed_openapi`): `dart test`
Expected: PASS, 350 тестів (`+350: All tests passed!`).

Run (з `packages/typed_openapi`): `dart format lib test bin` двічі
Expected: другий запуск — `0 changed`.

Run (з кореня): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 6: Коміт**

```bash
git add packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart packages/typed_openapi/lib/src/overrides/override_set.dart packages/typed_openapi/lib/src/overrides/override_loader.dart packages/typed_openapi/test/overrides/override_loader_test.dart
git commit -m "feat(typed_openapi): read the overrides file into an OverrideSet" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


### Task 2: Адресація: `OverrideResolver` (TOA804–TOA806, TOA808)

**Files:**
- Create: `packages/typed_openapi/lib/src/overrides/override_resolver.dart`, `packages/typed_openapi/test/overrides/override_resolver_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`

**Interfaces:**
- Consumes: `OverrideSet` і записи (задача 1); `SpecModel` (`document.paths`, `document.components.schemas`, `resolve`, `resolveSchema`), `Operation`, `PathItem`, `Parameter`, `SchemaObject` (M2); `SpecDocuments.displayPath` (M3).
- Produces: блок «override_resolver.dart (Task 2)»; коди `overrideTargetNotFound` (TOA804), `overrideTargetAmbiguous` (TOA805), `overrideConflict` (TOA806), `overrideSharedTarget` (TOA808).

Поведінка, яку закріплюють тести:
- Кожен вид цілі знаходиться без діагностики (записи без полів специфікації на спільних вузлах — без TOA808): операція за `operationId`, за `DELETE /pets/{id}` і за `get /pets`; параметр шляху `path:id`, параметр операції `query:id`, параметр через `$ref` у `components.parameters`; відповідь через `$ref`; тіло; схема; властивість (вузол властивості, не ціль її `$ref`; `owner` — схема). Ключ-аліас (`Animal: {$ref: Pet}`) веде до `Pet`.
- Відсутня ціль — TOA804 (warning) з `reason` у повідомленні, у позиції запису у файлі override-ів; інші записи застосовуються: невідомий `operationId`, шлях не в `paths`, метод відсутній, параметр (з `in` і без), тіло, відповідь, схема, булева схема, властивість.
- `operationId` двох операцій — TOA805 з підказкою `METHOD /path` для кожної (у порядку `paths`), вкладені записи не розв'язуються; ім'я параметра в `path` і `query` — TOA805 з підказкою `path:id, query:id`.
- Два записи одного вузла — TOA806 на кожному, жоден (і нічого всередині) не застосовується: `getPet` + `GET /pets/{id}`, `id` + `path:id`, `Pet` + аліас `Animal`.
- Поля специфікації через операцію на спільному вузлі — TOA808 (info) з місцем вузла: параметр шляху (`#/paths/~1pets~1{id}/parameters/0`), `$ref`-параметр, `$ref`-відповідь; на власному параметрі й тілі операції та на схемі за іменем — нічого; цілі все одно повертаються.
- Негатив: дві операції, кожна зі своїм override-ом спільного параметра шляху (лише поля генерації), — не конфлікт на рівні адрес і без TOA808.

- [ ] **Step 1: Коди**

Diff `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart` (`git apply` з кореня):

```diff
diff --git a/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart b/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart
index 9cd1d37..8ac01ee 100644
--- a/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart
+++ b/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart
@@ -213,6 +213,22 @@ enum DiagnosticCode {
   /// field; it is ignored.
   unknownOverrideKey('TOA803', 'unknown-override-key', .error),
 
+  /// An override names an operation, a schema, a property, a parameter or a
+  /// response the spec does not have; it is not applied.
+  overrideTargetNotFound('TOA804', 'override-target-not-found', .warning),
+
+  /// An override's address names more than one node, such as an
+  /// `operationId` two operations share; it is not applied.
+  overrideTargetAmbiguous('TOA805', 'override-target-ambiguous', .error),
+
+  /// Two overrides change the same node; neither is applied.
+  overrideConflict('TOA806', 'override-conflict', .error),
+
+  /// An override addressed through an operation changes a node other
+  /// operations may share: a path-level parameter, a `$ref`'d component or
+  /// a node in another file.
+  overrideSharedTarget('TOA808', 'override-shared-target', .info),
+
   /// The configuration file does not exist.
   configNotFound('TOA901', 'config-not-found', .error),
 
```

- [ ] **Step 2: Тест, що не проходить**

Створи `packages/typed_openapi/test/overrides/override_resolver_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/load/openapi_version.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/overrides/override_loader.dart';
import 'package:typed_openapi/src/overrides/override_resolver.dart';
import 'package:typed_openapi/src/resolve/spec_documents.dart';
import 'package:typed_openapi/src/resolve/spec_reader.dart';

const _spec = r'''
openapi: 3.1.0
info: {title: t, version: '1'}
paths:
  /pets/{id}:
    parameters:
      - {name: id, in: path, required: true, schema: {type: string}}
    get:
      operationId: getPet
      parameters:
        - {name: id, in: query, schema: {type: string}}
        - $ref: '#/components/parameters/Limit'
      responses:
        '200': {$ref: '#/components/responses/PetResponse'}
    delete:
      operationId: deletePet
      requestBody:
        content: {application/json: {schema: {type: object}}}
      responses:
        '204': {description: gone}
  /pets:
    get:
      operationId: listPets
      responses: {'200': {description: ok}}
    post:
      operationId: listPets
      responses: {'201': {description: ok}}
components:
  parameters:
    Limit: {name: limit, in: query, schema: {type: integer}}
  responses:
    PetResponse:
      description: ok
      content:
        application/json: {schema: {$ref: '#/components/schemas/Pet'}}
  schemas:
    Pet:
      type: object
      properties:
        id: {type: string}
        owner: {$ref: '#/components/schemas/Owner'}
    Owner: {type: object}
    Animal: {$ref: '#/components/schemas/Pet'}
    Flag: true
''';

/// The targets of [overrides] in [_spec], and what the resolver reported.
(List<OverrideTarget>, DiagnosticBag) _resolve(String overrides) {
  final setup = DiagnosticBag();
  final document = SpecLoader(setup).parse(_spec, 'api.yaml')!;
  final version = OpenApiVersionDetector(setup).detect(document)!;
  final documents = SpecDocuments(SpecLoader(setup), document);
  final model = SpecReader(
    setup,
  ).read(document, version, documents: documents);
  final set = OverrideLoader(setup).parse(overrides, 'o.yaml')!;
  expect(
    setup.all.where((d) => d.file == 'o.yaml'),
    isEmpty,
    reason: 'the overrides file itself is valid',
  );
  final bag = DiagnosticBag();
  return (OverrideResolver(bag, set).resolve(model, documents), bag);
}

/// Each target as (entry pointer, node pointer).
List<(String, String)> _pairs(List<OverrideTarget> targets) => [
  for (final t in targets) (t.entry.pointer.value, t.node.pointer.value),
];

void main() {
  test(r'finds every kind of node, through $refs, without diagnostics', () {
    final (targets, bag) = _resolve('''
operations:
  getPet:
    parameters:
      path:id: {name: petId}
      query:id: {required: false}
      limit: {name: max}
    responses:
      '200': {reason: x}
  DELETE /pets/{id}:
    requestBody: {contentType: application/json}
  get /pets: {name: list}
schemas:
  Pet:
    type: object
    properties:
      owner: {nullable: true}
  Owner: {exhaustive: false}
''');
    expect(bag.all, isEmpty);
    expect(_pairs(targets), [
      ('#/operations/getPet', '#/paths/~1pets~1{id}/get'),
      (
        '#/operations/getPet/parameters/path:id',
        '#/paths/~1pets~1{id}/parameters/0',
      ),
      (
        '#/operations/getPet/parameters/query:id',
        '#/paths/~1pets~1{id}/get/parameters/0',
      ),
      ('#/operations/getPet/parameters/limit', '#/components/parameters/Limit'),
      (
        '#/operations/getPet/responses/200',
        '#/components/responses/PetResponse',
      ),
      ('#/operations/DELETE ~1pets~1{id}', '#/paths/~1pets~1{id}/delete'),
      (
        '#/operations/DELETE ~1pets~1{id}/requestBody',
        '#/paths/~1pets~1{id}/delete/requestBody',
      ),
      ('#/operations/get ~1pets', '#/paths/~1pets/get'),
      ('#/schemas/Pet', '#/components/schemas/Pet'),
      (
        '#/schemas/Pet/properties/owner',
        '#/components/schemas/Pet/properties/owner',
      ),
      ('#/schemas/Owner', '#/components/schemas/Owner'),
    ]);
    expect(targets[9], isA<PropertyTarget>());
    expect(
      (targets[9] as PropertyTarget).owner.pointer.value,
      '#/components/schemas/Pet',
    );
  });

  test(r'a schema override follows the $ref of a components key', () {
    final (targets, bag) = _resolve('schemas: {Animal: {nullable: true}}');
    expect(bag.all, isEmpty);
    expect(_pairs(targets), [('#/schemas/Animal', '#/components/schemas/Pet')]);
  });

  test('a missing node is a warning with the reason, and the rest applies', () {
    final (targets, bag) = _resolve('''
operations:
  getPets: {reason: renamed upstream, name: x}
  GET /owners: {name: x}
  PUT /pets: {name: x}
  getPet:
    parameters:
      header:limit: {required: true}
      offset: {required: true}
    requestBody: {contentType: application/json}
    responses:
      '404': {contentType: application/json}
schemas:
  Cat: {type: object}
  Flag: {type: object}
  Pet:
    properties:
      name: {type: string}
      id: {type: integer}
''');
    expect(
      [for (final d in bag.sorted) (d.code, d.pointer?.value)],
      [
        for (final p in [
          '#/operations/getPets',
          '#/operations/GET ~1owners',
          '#/operations/PUT ~1pets',
          '#/operations/getPet/parameters/header:limit',
          '#/operations/getPet/parameters/offset',
          '#/operations/getPet/requestBody',
          '#/operations/getPet/responses/404',
          '#/schemas/Cat',
          '#/schemas/Flag',
          '#/schemas/Pet/properties/name',
        ])
          (DiagnosticCode.overrideTargetNotFound, p),
      ],
    );
    expect(
      bag.sorted.first.message,
      'No operation has operationId "getPets". The override is not applied. '
      'Reason given: "renamed upstream".',
    );
    expect(bag.sorted.first.file, 'o.yaml');
    expect(bag.sorted.first.line, 2);
    expect(bag.sorted[1].message, startsWith('The path /owners is not in'));
    expect(bag.sorted[2].message, startsWith('The path /pets has no PUT'));
    expect(_pairs(targets), [
      ('#/operations/getPet', '#/paths/~1pets~1{id}/get'),
      ('#/schemas/Pet', '#/components/schemas/Pet'),
      ('#/schemas/Pet/properties/id', '#/components/schemas/Pet/properties/id'),
    ]);
  });

  test('an operationId two operations share is ambiguous', () {
    final (targets, bag) = _resolve('''
operations:
  listPets:
    parameters:
      nope: {required: true}
''');
    expect(targets, isEmpty);
    final d = bag.all.single;
    expect(d.code, DiagnosticCode.overrideTargetAmbiguous);
    expect(d.pointer?.value, '#/operations/listPets');
    expect(
      d.fix,
      'Address the operation as METHOD /path: GET /pets, POST /pets.',
    );
  });

  test('a parameter name shared by two "in"s is ambiguous', () {
    final (targets, bag) = _resolve('''
operations:
  getPet:
    parameters:
      id: {required: true}
''');
    expect(_pairs(targets), [
      ('#/operations/getPet', '#/paths/~1pets~1{id}/get'),
    ]);
    final d = bag.all.single;
    expect(d.code, DiagnosticCode.overrideTargetAmbiguous);
    expect(d.pointer?.value, '#/operations/getPet/parameters/id');
    expect(d.fix, 'Write the key as in:name: path:id, query:id.');
  });

  test('two overrides of one node conflict and neither applies', () {
    final (targets, bag) = _resolve('''
operations:
  getPet:
    parameters:
      limit: {required: true}
  GET /pets/{id}: {name: x}
  deletePet:
    parameters:
      id: {required: true}
      path:id: {name: petId}
schemas:
  Pet: {type: object}
  Animal: {nullable: true}
''');
    expect(
      [for (final d in bag.sorted) (d.code, d.pointer?.value)],
      [
        for (final p in [
          '#/operations/getPet',
          '#/operations/GET ~1pets~1{id}',
          '#/operations/deletePet/parameters/id',
          '#/operations/deletePet/parameters/path:id',
          '#/schemas/Pet',
          '#/schemas/Animal',
        ])
          (DiagnosticCode.overrideConflict, p),
      ],
    );
    expect(
      bag.sorted.first.message,
      'This override and the one at #/operations/GET ~1pets~1{id} name the '
      'same node (#/paths/~1pets~1{id}/get); neither is applied.',
    );
    expect(_pairs(targets), [
      ('#/operations/deletePet', '#/paths/~1pets~1{id}/delete'),
    ]);
  });

  test('a spec change through an operation of a node it shares is an info '
      'that names the node', () {
    final (targets, bag) = _resolve('''
operations:
  getPet:
    parameters:
      path:id: {required: true}
      query:id: {required: true}
      limit: {required: true}
    responses:
      '200': {contentType: application/json}
  deletePet:
    requestBody: {contentType: application/json}
schemas:
  Pet: {nullable: true}
''');
    expect(
      [for (final d in bag.sorted) (d.code, d.pointer?.value)],
      [
        for (final p in [
          '#/operations/getPet/parameters/path:id',
          '#/operations/getPet/parameters/limit',
          '#/operations/getPet/responses/200',
        ])
          (DiagnosticCode.overrideSharedTarget, p),
      ],
    );
    expect(
      bag.sorted.first.message,
      'This override changes the shared node at '
      '#/paths/~1pets~1{id}/parameters/0; the change applies to every '
      'operation that uses it.',
    );
    expect(targets, hasLength(8));
  });

  test('two operations may each override a parameter they share', () {
    final (targets, bag) = _resolve('''
operations:
  getPet:
    parameters:
      path:id: {name: petId}
  deletePet:
    parameters:
      id: {name: petId}
''');
    expect(bag.all, isEmpty);
    expect(_pairs(targets).map((p) => p.$2), [
      '#/paths/~1pets~1{id}/get',
      '#/paths/~1pets~1{id}/parameters/0',
      '#/paths/~1pets~1{id}/delete',
      '#/paths/~1pets~1{id}/parameters/0',
    ]);
  });
}
```

- [ ] **Step 3: Запустити тест**

Run (з `packages/typed_openapi`): `dart test test/overrides/override_resolver_test.dart`
Expected: FAIL — `override_resolver.dart` не існує.

- [ ] **Step 4: Резолвер**

Створи `packages/typed_openapi/lib/src/overrides/override_resolver.dart`:

```dart
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../model/operation.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';
import '../resolve/spec_documents.dart';
import '../resolve/spec_model.dart';
import 'override_set.dart';

/// An override entry and the node of the spec model it names.
sealed class OverrideTarget {
  /// Creates a target.
  const OverrideTarget();

  /// The entry of the overrides file.
  OverrideEntry get entry;

  /// The node the entry changes.
  SpecNode get node;
}

/// An operation an [OperationOverride] names.
final class OperationTarget extends OverrideTarget {
  /// Creates a target.
  const OperationTarget(this.entry, this.node);

  @override
  final OperationOverride entry;

  @override
  final Operation node;
}

/// A parameter of an operation; a shared parameter (path-level or `$ref`)
/// is the node where it is defined.
final class ParameterTarget extends OverrideTarget {
  /// Creates a target.
  const ParameterTarget(this.entry, this.node);

  @override
  final ParameterOverride entry;

  @override
  final Parameter node;
}

/// A request body or a response, with the media types of its `content`.
final class ContentTarget extends OverrideTarget {
  /// Creates a target.
  const ContentTarget(this.entry, this.node);

  /// A [BodyOverride] or a [ResponseOverride].
  @override
  final OverrideEntry entry;

  /// A [RequestBody] or a [Response].
  @override
  final SpecNode node;
}

/// A schema in `components.schemas`: the schema its `$ref` chain ends at.
final class SchemaTarget extends OverrideTarget {
  /// Creates a target.
  const SchemaTarget(this.entry, this.node);

  @override
  final SchemaOverride entry;

  @override
  final SchemaObject node;
}

/// A property of a schema: the property schema as written, not where its
/// `$ref` points, so that only this property changes.
final class PropertyTarget extends OverrideTarget {
  /// Creates a target.
  const PropertyTarget(this.entry, this.owner, this.node);

  @override
  final PropertyOverride entry;

  /// The object schema that has the property.
  final SchemaObject owner;

  @override
  final Schema node;
}

/// Finds the node every override of an [OverrideSet] names.
///
/// An override whose node is missing is `override-target-not-found`; one
/// whose address names several nodes is `override-target-ambiguous`; two
/// overrides that name the same node (`getPet` and `GET /pets/{id}`, or `id`
/// and `path:id`) are `override-conflict`. None of them is a target; the
/// overrides inside such an operation or schema are not resolved.
///
/// A parameter, request body or response override with spec fields whose
/// node lies outside its operation (a path-level parameter, a `$ref`'d
/// component, a node in another file) is `override-shared-target`: the
/// change applies to every operation that uses the node.
final class OverrideResolver {
  /// Creates a resolver of [_overrides] that reports to [_diagnostics].
  const OverrideResolver(this._diagnostics, this._overrides);

  final DiagnosticBag _diagnostics;
  final OverrideSet _overrides;

  /// The targets in [model], read from [documents], in file order:
  /// operations with their parameters, request bodies and responses, then
  /// schemas with their properties.
  List<OverrideTarget> resolve(SpecModel model, SpecDocuments documents) {
    final operations = _OperationIndex(model);
    final targets = <OverrideTarget>[];
    final found = <(OperationTarget, List<OverrideTarget>)>[];
    for (final entry in _overrides.operations) {
      final operation = _operation(entry, operations);
      if (operation == null) continue;
      final target = OperationTarget(entry, operation.$1);
      found.add((target, _inside(entry, operation, model)));
    }
    for (final (target, inner) in _unique(found)) {
      final unique = _uniqueTargets(inner);
      targets
        ..add(target)
        ..addAll(unique);
      for (final t in unique) {
        _shared(t, target.node, model, documents);
      }
    }
    final schemas = <(SchemaTarget, List<OverrideTarget>)>[];
    for (final entry in _overrides.schemas) {
      final schema = _schema(entry, model);
      if (schema == null) continue;
      schemas.add((
        SchemaTarget(entry, schema),
        [
          for (final property in entry.properties)
            ?_property(property, entry, schema),
        ],
      ));
    }
    for (final (target, inner) in _unique(schemas)) {
      targets
        ..add(target)
        ..addAll(_uniqueTargets(inner));
    }
    return targets;
  }

  /// Reports [target] when it changes the spec at a node outside
  /// [operation].
  void _shared(
    OverrideTarget target,
    Operation operation,
    SpecModel model,
    SpecDocuments documents,
  ) {
    if (target.entry.spec.isEmpty) return;
    final at = target.node.location;
    final inside =
        at.document == operation.location.document &&
        at.pointer.value.startsWith('${operation.pointer.value}/');
    if (inside) return;
    final where = at.document == model.document.location.document
        ? at.pointer.value
        : '${documents.displayPath(at.document)}${at.pointer.value}';
    _report(
      .overrideSharedTarget,
      target.entry,
      'This override changes the shared node at $where; the change applies '
      'to every operation that uses it.',
    );
  }

  /// [found] without the targets whose node another one names too; those
  /// are reported, each naming the others.
  List<(T, List<OverrideTarget>)> _unique<T extends OverrideTarget>(
    List<(T, List<OverrideTarget>)> found,
  ) {
    final byNode = <SpecLocation, List<T>>{};
    for (final (target, _) in found) {
      (byNode[target.node.location] ??= []).add(target);
    }
    final unique = <(T, List<OverrideTarget>)>[];
    for (final (target, inner) in found) {
      final same = byNode[target.node.location]!;
      if (same.length == 1) {
        unique.add((target, inner));
      } else {
        _conflict(target, same);
      }
    }
    return unique;
  }

  /// [targets] without the ones whose node another one names too.
  List<OverrideTarget> _uniqueTargets(List<OverrideTarget> targets) => [
    for (final (target, _) in _unique([
      for (final target in targets) (target, const <OverrideTarget>[]),
    ]))
      target,
  ];

  /// Reports that [target] and the rest of [all] name the same node.
  void _conflict(OverrideTarget target, List<OverrideTarget> all) {
    final others = [
      for (final other in all)
        if (other != target) other.entry.pointer.value,
    ];
    _report(
      .overrideConflict,
      target.entry,
      'This override and the one at ${others.join(', ')} name the same '
      'node (${target.node.location.pointer.value}); neither is applied.',
      fix: 'Merge them into one override.',
    );
  }

  (Operation, PathItem?)? _operation(
    OperationOverride entry,
    _OperationIndex index,
  ) {
    if (entry.operationId case final id?) {
      final matches = index.byId[id] ?? const [];
      if (matches.length > 1) {
        final addresses = [
          for (final (_, method, path) in matches)
            '${method.toUpperCase()} $path',
        ];
        _report(
          .overrideTargetAmbiguous,
          entry,
          'operationId "$id" names ${matches.length} operations; this '
          'override is not applied.',
          fix:
              'Address the operation as METHOD /path: ${addresses.join(', ')}.',
        );
        return null;
      }
      if (matches.isEmpty) {
        _notFound(entry, 'No operation has operationId "$id".');
        return null;
      }
      final (operation, _, path) = matches.single;
      return (operation, index.items[path]);
    }
    final method = entry.method!;
    final path = entry.path!;
    final item = index.items[path];
    final operation = item?.operations[method];
    if (operation == null) {
      _notFound(
        entry,
        item == null
            ? 'The path $path is not in "paths".'
            : 'The path $path has no ${method.toUpperCase()} operation.',
      );
      return null;
    }
    return (operation, item);
  }

  /// The targets inside an operation override: parameters, request body,
  /// responses.
  List<OverrideTarget> _inside(
    OperationOverride entry,
    (Operation, PathItem?) found,
    SpecModel model,
  ) {
    final (operation, item) = found;
    return [
      for (final parameter in entry.parameters)
        ?_parameter(parameter, entry, operation, item, model),
      if (entry.requestBody case final body?)
        ?_content(
          body,
          operation.requestBody,
          model,
          'Operation ${entry.key} has no request body.',
        ),
      for (final response in entry.responses)
        ?_content(
          response,
          operation.responses[response.key],
          model,
          'Operation ${entry.key} has no response "${response.key}".',
        ),
    ];
  }

  /// The request body or response [value] for [entry], or null after
  /// reporting [missing].
  ContentTarget? _content(
    OverrideEntry entry,
    RefOr<SpecNode>? value,
    SpecModel model,
    String missing,
  ) {
    final node = value == null ? null : model.resolve(value);
    if (node != null) return ContentTarget(entry, node);
    _notFound(entry, missing);
    return null;
  }

  ParameterTarget? _parameter(
    ParameterOverride entry,
    OperationOverride parent,
    Operation operation,
    PathItem? item,
    SpecModel model,
  ) {
    final own = [
      for (final p in operation.parameters) ?model.resolve(p),
    ];
    final shared = [
      for (final p in item?.parameters ?? const <RefOr<Parameter>>[])
        if (model.resolve(p) case final resolved?)
          if (!own.any(
            (o) => o.name == resolved.name && o.placement == resolved.placement,
          ))
            resolved,
    ];
    final matches = [
      for (final p in [...own, ...shared])
        if (p.name == entry.parameterName &&
            (entry.placement == null || p.placement == entry.placement))
          p,
    ];
    if (matches.isEmpty) {
      final where = entry.placement == null
          ? ''
          : ' in ${entry.placement!.name}';
      _notFound(
        entry,
        'Operation ${parent.key} has no parameter '
        '"${entry.parameterName}"$where.',
      );
      return null;
    }
    if (matches.length > 1) {
      final keys = {
        for (final p in matches)
          '${p.placement?.name ?? '?'}:${entry.parameterName}',
      }.toList()..sort();
      _report(
        .overrideTargetAmbiguous,
        entry,
        'Operation ${parent.key} has ${matches.length} parameters named '
        '"${entry.parameterName}"; this override is not applied.',
        fix: 'Write the key as in:name: ${keys.join(', ')}.',
      );
      return null;
    }
    return ParameterTarget(entry, matches.single);
  }

  SchemaObject? _schema(SchemaOverride entry, SpecModel model) {
    final written = model.document.components?.schemas[entry.key];
    if (written == null) {
      _notFound(entry, 'No schema "${entry.key}" in components.schemas.');
      return null;
    }
    final schema = model.resolveSchema(written);
    if (schema is SchemaObject) return schema;
    _notFound(
      entry,
      schema == null
          ? 'The \$ref of schema "${entry.key}" cannot be followed.'
          : 'Schema "${entry.key}" is the boolean schema ${schema.location}; '
                'it has no fields to change.',
    );
    return null;
  }

  PropertyTarget? _property(
    PropertyOverride entry,
    SchemaOverride parent,
    SchemaObject owner,
  ) {
    final property = owner.properties[entry.key];
    if (property != null) return PropertyTarget(entry, owner, property);
    _notFound(
      entry,
      'Schema "${parent.key}" has no property "${entry.key}" in its own '
      '"properties".',
    );
    return null;
  }

  void _notFound(OverrideEntry entry, String message) => _report(
    .overrideTargetNotFound,
    entry,
    '$message The override is not applied.',
    fix: 'Remove the override, or fix its address.',
  );

  void _report(
    DiagnosticCode code,
    OverrideEntry entry,
    String message, {
    String? fix,
  }) {
    final reason = entry.reason;
    _diagnostics.report(
      code,
      reason == null ? message : '$message Reason given: "$reason".',
      file: _overrides.file,
      pointer: entry.pointer,
      span: _overrides.spanOf(entry.pointer),
      fix: fix,
    );
  }
}

/// The operations of `paths`, by `operationId` and by path template.
final class _OperationIndex {
  _OperationIndex(SpecModel model) {
    final seen = <SpecLocation>{};
    for (final MapEntry(key: path, :value) in model.document.paths.entries) {
      final item = model.resolve(value);
      if (item == null) continue;
      items[path] = item;
      for (final MapEntry(key: method, value: operation)
          in <MapEntry<String, Operation>>[
            ...item.operations.entries,
            ...item.additionalOperations.entries,
          ]) {
        final id = operation.operationId;
        if (id == null || !seen.add(operation.location)) continue;
        (byId[id] ??= []).add((operation, method, path));
      }
    }
  }

  /// Path items by template.
  final Map<String, PathItem> items = {};

  /// Operations with their method and path, by `operationId`.
  final Map<String, List<(Operation, String, String)>> byId = {};
}
```

- [ ] **Step 5: Перевірити**

Run (з `packages/typed_openapi`): `dart test`
Expected: PASS, 358 тестів (`+358: All tests passed!`).

Run (з `packages/typed_openapi`): `dart format lib test bin` двічі
Expected: другий запуск — `0 changed`.

Run (з кореня): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 6: Коміт**

```bash
git add packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart packages/typed_openapi/lib/src/overrides/override_resolver.dart packages/typed_openapi/test/overrides/override_resolver_test.dart
git commit -m "feat(typed_openapi): resolve override addresses to spec nodes" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


### Task 3: Застосування полів специфікації до нормалізатора (TOA807)

**Files:**
- Create: `packages/typed_openapi/lib/src/overrides/override_applier.dart`, `packages/typed_openapi/test/overrides/override_applier_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_openapi/lib/src/normalize/normalizer.dart`, `packages/typed_openapi/lib/src/check/spec_checker.dart`, `packages/typed_openapi/test/check/spec_checker_test.dart`

**Interfaces:**
- Consumes: `OverrideLoader`, `OverrideSet` (задача 1); `OverrideResolver`, `OverrideTarget` (задача 2); `SpecEdit` (`add`, `remove`, `replace`, `overlaps`, `sameAs`), `TreeEditor`, `SpecDocuments`, `SpecDocument.withRoot` (M3); `ClientConfig.overrides` (M1).
- Produces: блок «override_applier.dart, normalize (Task 3)»; код `overrideUnchanged` (TOA807).

Поведінка, яку закріплюють тести:
- 3.0: параметр (`schema`, `required`), тіло (`*/*` → `application/octet-stream` зі схемою), відповідь (`schema` у єдиний media type), схема (`discriminator`, `additionalProperties`), властивості (`format: null`, `nullable`, `items`, `enum`, `required: true` → ім'я в `required` власника) — дерево саме таке, як очікується; правила вже не дають TOA601, TOA205, TOA204 (рішення 3 специфікації); `NormalizedSpec.overrides` — прочитаний набір.
- 3.1: `nullable: true` → `[string, 'null']`; `type: number` для `[integer, 'null']` → `[number, 'null']`; `nullable: false` → `string`; `nullable: true` без `type` — TOA802, схема не змінюється.
- `$ref` і nullable-посилання: 3.0 — `allOf` + `nullable`, 3.1 — `anyOf` з `{type: 'null'}`; TOA303 після override-у зникає.
- Поле, яке специфікація вже має, — TOA807 (info) у pointer поля з `reason`: `required`/`schema` параметра, `contentType`/`schema` відповіді, `type`, `nullable`, `format: null` (поля немає), `required: true`/`false` властивості; змінене поле поряд — без TOA807 і застосовується.
- Різні правки одного вузла від різних записів — TOA806 на кожному полі, обидві не робляться (`schema` спільного параметра з двох операцій; `required` схеми + `required` властивості); однакові правки (`required: true` спільного параметра з двох операцій) — один раз, без конфлікту; кожен override спільного параметра — ще й TOA808.
- Кілька media types: `schema` без `contentType` і `contentType`, якого немає, — TOA805; `contentType`, що є, лишає тільки його.
- Вузли в іншому файлі змінюються в тому файлі: схема (ключ `$ref` у `pet.yaml`) — без діагностики; відповідь операції через `$ref` у `pet.yaml` — TOA808 «… shared node at pet.yaml#/Ok …».
- Лише поля генерації — жодної діагностики і жодної правки.
- `SpecChecker`: override клієнта прибирає TOA205; клієнт без override-ів на тому ж файлі дає TOA205; відсутній файл override-ів — TOA801 з відносним шляхом, а специфікацію все одно перевірено.

- [ ] **Step 1: Код**

Diff `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart` (`git apply` з кореня):

```diff
diff --git a/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart b/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart
index 8ac01ee..3acacd0 100644
--- a/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart
+++ b/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart
@@ -224,6 +224,9 @@ enum DiagnosticCode {
   /// Two overrides change the same node; neither is applied.
   overrideConflict('TOA806', 'override-conflict', .error),
 
+  /// An override sets a value the spec already has; it can be removed.
+  overrideUnchanged('TOA807', 'override-unchanged', .info),
+
   /// An override addressed through an operation changes a node other
   /// operations may share: a path-level parameter, a `$ref`'d component or
   /// a node in another file.
```

- [ ] **Step 2: Тести, що не проходять**

Створи `packages/typed_openapi/test/overrides/override_applier_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/load/openapi_version.dart';
import 'package:typed_openapi/src/load/spec_document.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/normalize/normalizer.dart';
import 'package:typed_openapi/src/overrides/override_loader.dart';

import '../helpers/temp_dir.dart';

/// A spec normalized with overrides.
final class _Run {
  /// Normalizes [spec] (or the file at [path]) with [overrides].
  _Run(String spec, String overrides, {String? path}) {
    final SpecDocument document = path == null
        ? SpecLoader(bag).parse(spec, 'api.yaml')!
        : SpecLoader(bag).load(path, displayPath: 'api.yaml')!;
    final version = OpenApiVersionDetector(bag).detect(document)!;
    final set = OverrideLoader(bag).parse(overrides, 'o.yaml')!;
    result = Normalizer(bag).normalize(document, version, overrides: set);
  }

  final DiagnosticBag bag = DiagnosticBag();
  late final NormalizedSpec result;

  /// The value at [pointer] of the root document after normalizing.
  Object? at(String pointer) =>
      result.documents.root.valueAt(JsonPointer.parse(pointer))?.$1;

  /// The diagnostics about the overrides file.
  List<(DiagnosticCode, String?)> get overrideDiagnostics => [
    for (final d in bag.sorted)
      if (d.file == 'o.yaml') (d.code, d.pointer?.value),
  ];

  /// The codes of every diagnostic.
  List<DiagnosticCode> get codes => [for (final d in bag.sorted) d.code];
}

const _header30 = '''
openapi: 3.0.3
info: {title: t, version: '1'}
''';

const _header31 = '''
openapi: 3.1.0
info: {title: t, version: '1'}
''';

void main() {
  test('sets schema, property, parameter and body fields (3.0)', () {
    final run = _Run(
      '''
$_header30
paths:
  /files/{id}:
    post:
      operationId: upload
      parameters:
        - {name: id, in: path, required: true, schema: {type: string}}
        - {name: tag, in: query, schema: {type: string}}
      requestBody:
        content:
          '*/*': {schema: {type: object, format: binary}}
      responses:
        '200':
          description: ok
          content:
            application/json: {schema: {type: object}}
components:
  schemas:
    Pet:
      type: object
      required: [id]
      properties:
        id: {type: string, format: uuid}
        tags: {type: array, format: uuid}
        name: {type: string}
''',
      r'''
operations:
  upload:
    parameters:
      id: {schema: {type: integer}}
      tag: {required: true}
    requestBody:
      contentType: application/octet-stream
      schema: {type: string, format: binary}
    responses:
      '200': {schema: {$ref: '#/components/schemas/Pet'}}
schemas:
  Pet:
    discriminator: {propertyName: kind}
    additionalProperties: false
    properties:
      id: {format: null, nullable: true}
      tags: {format: null, items: {type: string, format: uuid}}
      name: {required: true, enum: [a, b]}
''',
    );
    expect(run.overrideDiagnostics, isEmpty);
    expect(run.codes, isNot(contains(DiagnosticCode.wildcardMediaType)));
    expect(run.codes, isNot(contains(DiagnosticCode.binaryObject)));
    expect(run.codes, isNot(contains(DiagnosticCode.formatOnArray)));
    const op = '#/paths/~1files~1{id}/post';
    expect(run.at('$op/parameters/0/schema'), {'type': 'integer'});
    expect(run.at('$op/parameters/1/required'), isTrue);
    expect(run.at('$op/requestBody/content'), {
      'application/octet-stream': {
        'schema': {'type': 'string', 'format': 'binary'},
      },
    });
    expect(run.at('$op/responses/200/content/application~1json/schema'), {
      r'$ref': '#/components/schemas/Pet',
    });
    expect(run.at('#/components/schemas/Pet'), {
      'type': 'object',
      'required': ['id', 'name'],
      'properties': {
        'id': {'type': 'string', 'nullable': true},
        'tags': {
          'type': 'array',
          'items': {'type': 'string', 'format': 'uuid'},
        },
        'name': {
          'type': 'string',
          'enum': ['a', 'b'],
        },
      },
      'discriminator': {'propertyName': 'kind'},
      'additionalProperties': false,
    });
    expect(run.result.overrides?.schemas.single.key, 'Pet');
  });

  test('nullable is "null" in type from 3.1; type keeps nullability', () {
    final run = _Run(
      '''
$_header31
components:
  schemas:
    A: {type: string}
    B: {type: [integer, 'null']}
    C: {type: [string, 'null']}
    D: {properties: {x: {type: string}}}
''',
      '''
schemas:
  A: {nullable: true}
  B: {type: number}
  C: {nullable: false}
  D: {nullable: true}
''',
    );
    expect(run.at('#/components/schemas/A/type'), ['string', 'null']);
    expect(run.at('#/components/schemas/B/type'), ['number', 'null']);
    expect(run.at('#/components/schemas/C/type'), 'string');
    expect(run.at('#/components/schemas/D'), {
      'properties': {
        'x': {'type': 'string'},
      },
    });
    expect(run.overrideDiagnostics, [
      (DiagnosticCode.invalidOverride, '#/schemas/D/nullable'),
    ]);
  });

  test(r'"$ref" and nullable references follow the dialect', () {
    const spec = r'''
components:
  schemas:
    Status: {type: string, enum: [a, b]}
    Owner: {type: object}
    Pet:
      type: object
      properties:
        owner: {$ref: '#/components/schemas/Owner'}
        status:
          oneOf:
            - {enum: [null]}
            - {$ref: '#/components/schemas/Status'}
''';
    const overrides = r'''
schemas:
  Pet:
    properties:
      owner: {nullable: true}
      status: {$ref: '#/components/schemas/Status', nullable: true}
''';
    final v30 = _Run('$_header30$spec', overrides);
    expect(v30.overrideDiagnostics, isEmpty);
    expect(v30.codes, isNot(contains(DiagnosticCode.nullableEnumOneOf)));
    expect(v30.at('#/components/schemas/Pet/properties/owner'), {
      'allOf': [
        {r'$ref': '#/components/schemas/Owner'},
      ],
      'nullable': true,
    });
    final v31 = _Run('$_header31$spec', overrides);
    expect(v31.overrideDiagnostics, isEmpty);
    expect(v31.at('#/components/schemas/Pet/properties/status'), {
      'anyOf': [
        {r'$ref': '#/components/schemas/Status'},
        {'type': 'null'},
      ],
    });
  });

  test('a field the spec already has is reported as removable', () {
    final run = _Run(
      '''
$_header30
paths:
  /pets:
    get:
      operationId: listPets
      parameters:
        - {name: limit, in: query, required: true, schema: {type: integer}}
      responses:
        '200':
          description: ok
          content:
            application/json: {schema: {type: array}}
components:
  schemas:
    Pet:
      type: object
      nullable: true
      required: [id]
      properties:
        id: {type: string}
        name: {type: string}
''',
      '''
operations:
  listPets:
    parameters:
      limit: {required: true, schema: {type: integer}}
    responses:
      '200': {contentType: application/json, schema: {type: array}}
schemas:
  Pet:
    reason: the backend sends null
    type: object
    nullable: true
    format: null
    properties:
      id: {required: true}
      name: {required: false, type: integer}
''',
    );
    expect(run.overrideDiagnostics, [
      for (final p in [
        '#/operations/listPets/parameters/limit/required',
        '#/operations/listPets/parameters/limit/schema',
        '#/operations/listPets/responses/200/contentType',
        '#/operations/listPets/responses/200/schema',
        '#/schemas/Pet/type',
        '#/schemas/Pet/nullable',
        '#/schemas/Pet/format',
        '#/schemas/Pet/properties/id/required',
        '#/schemas/Pet/properties/name/required',
      ])
        (DiagnosticCode.overrideUnchanged, p),
    ]);
    final type = run.bag.sorted.firstWhere(
      (d) => d.pointer?.value == '#/schemas/Pet/type',
    );
    expect(
      type.message,
      'The spec already has this "type"; the override changes nothing and '
      'can be removed. Reason given: "the backend sends null".',
    );
    expect(type.line, 10);
    expect(run.at('#/components/schemas/Pet/properties/name/type'), 'integer');
  });

  test('two different changes of one node conflict; equal ones apply once', () {
    final run = _Run(
      '''
$_header30
paths:
  /pets/{id}:
    parameters:
      - {name: id, in: path, required: true, schema: {type: string}}
      - {name: v, in: query, schema: {type: string}}
    get:
      operationId: getPet
      responses: {'200': {description: ok}}
    delete:
      operationId: deletePet
      responses: {'204': {description: ok}}
components:
  schemas:
    Pet:
      type: object
      properties:
        a: {type: string}
        b: {type: string}
''',
      '''
operations:
  getPet:
    parameters:
      id: {schema: {type: integer}}
      v: {required: true}
  deletePet:
    parameters:
      id: {schema: {type: number}}
      v: {required: true}
schemas:
  Pet:
    required: [a]
    properties:
      b: {required: true}
''',
    );
    expect(run.overrideDiagnostics, [
      (
        DiagnosticCode.overrideSharedTarget,
        '#/operations/getPet/parameters/id',
      ),
      (
        DiagnosticCode.overrideConflict,
        '#/operations/getPet/parameters/id/schema',
      ),
      (DiagnosticCode.overrideSharedTarget, '#/operations/getPet/parameters/v'),
      (
        DiagnosticCode.overrideSharedTarget,
        '#/operations/deletePet/parameters/id',
      ),
      (
        DiagnosticCode.overrideConflict,
        '#/operations/deletePet/parameters/id/schema',
      ),
      (
        DiagnosticCode.overrideSharedTarget,
        '#/operations/deletePet/parameters/v',
      ),
      (DiagnosticCode.overrideConflict, '#/schemas/Pet/required'),
      (DiagnosticCode.overrideConflict, '#/schemas/Pet/properties/b/required'),
    ]);
    expect(run.at('#/paths/~1pets~1{id}/parameters/0/schema'), {
      'type': 'string',
    });
    expect(run.at('#/paths/~1pets~1{id}/parameters/1/required'), isTrue);
    expect(run.at('#/components/schemas/Pet/required'), isNull);
  });

  test('a body with several media types needs a contentType that names '
      'one', () {
    final run = _Run(
      '''
$_header30
paths:
  /a:
    post:
      operationId: a
      requestBody:
        content:
          application/json: {schema: {type: object}}
          application/xml: {schema: {type: object}}
      responses: {'200': {description: ok}}
  /b:
    post:
      operationId: b
      requestBody:
        content:
          application/json: {schema: {type: object}}
          application/xml: {schema: {type: object}}
      responses: {'200': {description: ok}}
  /c:
    post:
      operationId: c
      requestBody:
        content:
          application/json: {schema: {type: object}}
          application/xml: {schema: {type: object}}
      responses: {'200': {description: ok}}
''',
      '''
operations:
  a: {requestBody: {schema: {type: string}}}
  b: {requestBody: {contentType: text/plain}}
  c: {requestBody: {contentType: application/json}}
''',
    );
    expect(run.overrideDiagnostics, [
      (
        DiagnosticCode.overrideTargetAmbiguous,
        '#/operations/a/requestBody/schema',
      ),
      (
        DiagnosticCode.overrideTargetAmbiguous,
        '#/operations/b/requestBody/contentType',
      ),
    ]);
    expect(run.at('#/paths/~1c/post/requestBody/content'), {
      'application/json': {
        'schema': {'type': 'object'},
      },
    });
  });

  test('changes nodes defined in another file', () {
    final dir = TempDir();
    dir.write('pet.yaml', '''
Pet: {type: object}
Ok:
  description: ok
  content: {application/json: {schema: {type: object}}}
''');
    final path = dir.write('api.yaml', '''
$_header30
paths:
  /pets:
    get:
      operationId: listPets
      responses:
        '200': {\$ref: 'pet.yaml#/Ok'}
components:
  schemas:
    Pet: {\$ref: 'pet.yaml#/Pet'}
''');
    final run = _Run('', '''
operations:
  listPets:
    responses:
      '200': {schema: {type: array}}
schemas:
  Pet: {nullable: true}
''', path: path);
    // Addressed by schema name: no info; through an operation: an info that
    // names the shared node in its file.
    expect(run.overrideDiagnostics, [
      (
        DiagnosticCode.overrideSharedTarget,
        '#/operations/listPets/responses/200',
      ),
    ]);
    expect(
      run.bag.all.firstWhere((d) => d.file == 'o.yaml').message,
      'This override changes the shared node at pet.yaml#/Ok; the change '
      'applies to every operation that uses it.',
    );
    final pet = run.result.documents.loaded.last;
    expect(pet.valueAt(JsonPointer.parse('#/Pet'))?.$1, {
      'type': 'object',
      'nullable': true,
    });
  });

  test('generation fields change nothing in the spec', () {
    final run = _Run(
      '''
$_header30
paths:
  /pets:
    get:
      operationId: listPets
      responses: {'200': {description: ok}}
components:
  schemas:
    Pet: {type: object, properties: {id: {type: string}}}
''',
      '''
operations:
  listPets: {name: pets, group: zoo, exclude: false}
schemas:
  Pet:
    exhaustive: false
    name: Animal
    properties:
      id: {name: petId, triState: true}
''',
    );
    expect(run.bag.all, isEmpty);
    expect(run.at('#/components/schemas/Pet'), {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
      },
    });
    expect(run.result.overrides?.operations.single.group, 'zoo');
  });
}
```

Diff `packages/typed_openapi/test/check/spec_checker_test.dart` (`git apply` з кореня):

```diff
diff --git a/packages/typed_openapi/test/check/spec_checker_test.dart b/packages/typed_openapi/test/check/spec_checker_test.dart
index 237640c..8876421 100644
--- a/packages/typed_openapi/test/check/spec_checker_test.dart
+++ b/packages/typed_openapi/test/check/spec_checker_test.dart
@@ -62,6 +62,41 @@ clients:
     ]);
   });
 
+  test("applies each client's overrides before the rules", () {
+    final dir = TempDir();
+    const spec = '''
+openapi: 3.0.3
+info: {title: t, version: "1"}
+paths: {}
+components:
+  schemas:
+    File: {type: object, format: binary}
+''';
+    dir.write('specs/api.yaml', spec);
+    dir.write('specs/api.overrides.yaml', 'schemas: {File: {type: string}}\n');
+    final path = dir.write('typed_openapi.yaml', '''
+clients:
+  fixed:
+    input: specs/api.yaml
+    output: lib/fixed
+    overrides: specs/api.overrides.yaml
+  plain: {input: specs/api.yaml, output: lib/plain}
+  broken:
+    input: specs/api.yaml
+    output: lib/broken
+    overrides: specs/missing.yaml
+''');
+    final bag = DiagnosticBag();
+    SpecChecker(bag).check(ConfigLoader(bag).load(path)!);
+    expect(
+      bag.all.map((d) => (d.code, d.file)),
+      unorderedEquals([
+        (DiagnosticCode.overridesNotFound, 'specs/missing.yaml'),
+        (DiagnosticCode.binaryObject, 'specs/api.yaml'),
+      ]),
+    );
+  });
+
   test('only checks the named clients', () {
     final dir = TempDir();
     final path = dir.write('typed_openapi.yaml', '''
```

- [ ] **Step 3: Запустити тести**

Run (з `packages/typed_openapi`): `dart test test/overrides test/check`
Expected: FAIL — `override_applier.dart` не існує, `normalize` не має параметра `overrides`.

- [ ] **Step 4: Застосування**

Створи `packages/typed_openapi/lib/src/overrides/override_applier.dart`:

```dart
import 'package:collection/collection.dart';

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../load/openapi_version.dart';
import '../model/spec_node.dart';
import '../normalize/spec_edit.dart';
import '../resolve/spec_documents.dart';
import 'override_resolver.dart';
import 'override_set.dart';

/// An edit an override makes, with the override it comes from.
final class OverrideEdit {
  /// Creates an override edit.
  const OverrideEdit(this.edit, this.sources);

  /// The change of the spec's plain tree.
  final SpecEdit edit;

  /// The entries and fields that ask for the change.
  final List<(OverrideEntry, String)> sources;
}

/// Turns the spec fields of resolved overrides into [SpecEdit]s.
///
/// A field replaces the value of the spec (a list replaces the list, an
/// object the object) and `null` removes it. `nullable` follows the
/// document's dialect: `nullable: true` in 3.0, `null` in `type` from 3.1.
/// `$ref` makes the schema a reference; a nullable reference is
/// `allOf: [{$ref}]` with `nullable: true` in 3.0 and
/// `anyOf: [{$ref}, {type: 'null'}]` from 3.1.
///
/// A field whose value the spec already has is `override-unchanged`; two
/// different edits of one node by different overrides are
/// `override-conflict`, and neither is made.
final class OverrideApplier {
  /// Creates an applier of [_overrides] to [_documents], whose root declares
  /// [_version]; it reports to [_diagnostics].
  const OverrideApplier(
    this._diagnostics,
    this._overrides,
    this._documents,
    this._version,
  );

  static const _equality = DeepCollectionEquality();

  /// Schema fields replaced as they are, in the order they are applied.
  static const _plainFields = [
    'format',
    'required',
    'items',
    'additionalProperties',
    'enum',
    'discriminator',
  ];

  final DiagnosticBag _diagnostics;
  final OverrideSet _overrides;
  final SpecDocuments _documents;
  final OpenApiVersion _version;

  /// The edits of [targets], in their order.
  List<OverrideEdit> edits(List<OverrideTarget> targets) {
    final edits = <OverrideEdit>[];
    final required = <SpecLocation, List<PropertyTarget>>{};
    for (final target in targets) {
      switch (target) {
        case OperationTarget():
          break;
        case ParameterTarget():
          edits.addAll(_parameter(target));
        case ContentTarget():
          edits.addAll(_content(target));
        case SchemaTarget():
          edits.addAll(_schema(target.entry, target.node.location, false));
        case PropertyTarget():
          edits.addAll(_schema(target.entry, target.node.location, true));
          if (target.entry.spec.containsKey('required')) {
            (required[target.owner.location] ??= []).add(target);
          }
      }
    }
    for (final MapEntry(key: owner, value: properties) in required.entries) {
      edits.addAll(_required(owner, properties));
    }
    return _withoutConflicts(edits);
  }

  Iterable<OverrideEdit> _parameter(ParameterTarget target) sync* {
    final entry = target.entry;
    final at = target.node.location;
    final raw = _object(at) ?? const {};
    if (entry.spec case {'required': final bool required}) {
      if ((raw['required'] == true) == required) {
        _unchanged(entry, 'required');
      } else {
        yield OverrideEdit(
          required
              ? SpecEdit.add(at.child('required'), true)
              : SpecEdit.remove(at.child('required')),
          [(entry, 'required')],
        );
      }
    }
    if (entry.spec case {'schema': final Object schema}) {
      yield* _set(entry, 'schema', at, raw, schema);
    }
  }

  Iterable<OverrideEdit> _content(ContentTarget target) sync* {
    final entry = target.entry;
    final at = target.node.location;
    final raw = _object(at) ?? const {};
    final content = switch (raw['content']) {
      final Map<String, Object?> content => content,
      _ => const <String, Object?>{},
    };
    final type = entry.spec['contentType'] as String?;
    final hasSchema = entry.spec.containsKey('schema');
    final String key;
    if (type != null) {
      key = type;
    } else if (content.length == 1) {
      key = content.keys.single;
    } else {
      if (hasSchema) {
        _report(
          content.isEmpty ? .invalidOverride : .overrideTargetAmbiguous,
          entry,
          'schema',
          content.isEmpty
              ? 'This has no media type to put the schema in.'
              : 'This has the media types ${content.keys.join(', ')}; it is '
                    'not clear which schema to replace.',
          fix: 'Add "contentType" to the override.',
        );
      }
      return;
    }
    final Map<String, Object?> next;
    if (content.containsKey(key) || content.isEmpty || content.length == 1) {
      next = {key: content[key] ?? content.values.firstOrNull ?? {}};
    } else {
      _report(
        .overrideTargetAmbiguous,
        entry,
        'contentType',
        'This has the media types ${content.keys.join(', ')} and none is '
            '$key; it is not clear which one to replace.',
        fix: 'Set "contentType" to one of them.',
      );
      return;
    }
    if (type != null && _equality.equals(content.keys.toList(), [key])) {
      _unchanged(entry, 'contentType');
    }
    if (entry.spec case {'schema': final Object schema}) {
      final media = switch (next[key]) {
        final Map<String, Object?> media => media,
        _ => const <String, Object?>{},
      };
      if (_equality.equals(media['schema'], schema)) {
        _unchanged(entry, 'schema');
      } else {
        next[key] = {...media, 'schema': schema};
      }
    }
    if (_equality.equals(next, raw['content'])) return;
    yield OverrideEdit(SpecEdit.add(at.child('content'), next), [
      if (type != null) (entry, 'contentType'),
      if (hasSchema) (entry, 'schema'),
    ]);
  }

  Iterable<OverrideEdit> _schema(
    OverrideEntry entry,
    SpecLocation at,
    bool property,
  ) sync* {
    final spec = entry.spec;
    if (spec.keys.every((k) => property && k == 'required')) return;
    final raw = _object(at);
    if (raw == null) {
      _report(
        .invalidOverride,
        entry,
        null,
        'The schema at ${at.pointer.value} is not an object; its fields '
        'cannot be set.',
      );
      return;
    }
    final toRef =
        spec.containsKey(r'$ref') ||
        raw.containsKey(r'$ref') && spec.containsKey('nullable');
    if (toRef) {
      yield* _reference(entry, at, raw, property);
      return;
    }
    if (spec.containsKey('type') || spec.containsKey('nullable')) {
      yield* _version == .v30
          ? _typeAndNullable30(entry, at, raw)
          : _typeAndNullable31(entry, at, raw);
    }
    for (final field in _plainFields) {
      if (field == 'required' && property) continue;
      if (!spec.containsKey(field)) continue;
      yield* _set(entry, field, at, raw, spec[field]);
    }
  }

  /// Makes the schema at [at] a (nullable) reference.
  Iterable<OverrideEdit> _reference(
    OverrideEntry entry,
    SpecLocation at,
    Map<String, Object?> raw,
    bool property,
  ) sync* {
    final spec = entry.spec;
    final others = [
      for (final field in spec.keys)
        if (field != r'$ref' &&
            field != 'nullable' &&
            !(property && field == 'required'))
          field,
    ];
    if (others.isNotEmpty) {
      _report(
        .invalidOverride,
        entry,
        others.first,
        '"${others.first}" cannot be set on a schema that is a reference.',
        fix: r'Replace the reference with "$ref" and "nullable" only.',
      );
      return;
    }
    final ref = (spec[r'$ref'] ?? raw[r'$ref']) as String;
    final nullable = spec['nullable'] == true;
    final next = <String, Object?>{
      if (!nullable) r'$ref': ref,
      if (nullable && _version == .v30) ...{
        'allOf': [
          {r'$ref': ref},
        ],
        'nullable': true,
      },
      if (nullable && _version != .v30)
        'anyOf': [
          {r'$ref': ref},
          {'type': 'null'},
        ],
    };
    final fields = [
      for (final field in [r'$ref', 'nullable'])
        if (spec.containsKey(field)) field,
    ];
    if (_equality.equals(raw, next)) {
      for (final field in fields) {
        _unchanged(entry, field);
      }
      return;
    }
    yield OverrideEdit(SpecEdit.replace(at, next), [
      for (final field in fields) (entry, field),
    ]);
  }

  Iterable<OverrideEdit> _typeAndNullable30(
    OverrideEntry entry,
    SpecLocation at,
    Map<String, Object?> raw,
  ) sync* {
    final spec = entry.spec;
    if (spec.containsKey('type')) {
      yield* _set(entry, 'type', at, raw, spec['type']);
    }
    if (spec case {'nullable': final bool nullable}) {
      if ((raw['nullable'] == true) == nullable) {
        _unchanged(entry, 'nullable');
      } else {
        yield OverrideEdit(
          nullable
              ? SpecEdit.add(at.child('nullable'), true)
              : SpecEdit.remove(at.child('nullable')),
          [(entry, 'nullable')],
        );
      }
    }
  }

  Iterable<OverrideEdit> _typeAndNullable31(
    OverrideEntry entry,
    SpecLocation at,
    Map<String, Object?> raw,
  ) sync* {
    final spec = entry.spec;
    final current = switch (raw['type']) {
      final String type => [type],
      final List<Object?> types => types.whereType<String>().toList(),
      _ => const <String>[],
    };
    final wasNullable = current.contains('null');
    final base = [
      for (final type in current)
        if (type != 'null') type,
    ];
    final nextBase = switch (spec) {
      {'type': final String type} => [type],
      {'type': null} => const <String>[],
      _ => base,
    };
    var nullable = spec['nullable'] as bool? ?? wasNullable;
    if (nullable && nextBase.isEmpty) {
      _report(
        .invalidOverride,
        entry,
        'nullable',
        'From OpenAPI 3.1, a schema is nullable through "null" in its '
            '"type", and this schema has no type.',
        fix: 'Add "type" to the override.',
      );
      if (!spec.containsKey('type')) return;
      nullable = false;
    }
    final types = [...nextBase, if (nullable) 'null'];
    final fields = [
      if (spec.containsKey('type')) 'type',
      if (spec.containsKey('nullable') && nextBase.isNotEmpty) 'nullable',
    ];
    if (spec.containsKey('type') && _equality.equals(base, nextBase)) {
      _unchanged(entry, 'type');
      fields.remove('type');
    }
    if (fields.contains('nullable') && wasNullable == nullable) {
      _unchanged(entry, 'nullable');
      fields.remove('nullable');
    }
    if (fields.isEmpty) return;
    final sources = [for (final field in fields) (entry, field)];
    yield OverrideEdit(switch (types) {
      [] => SpecEdit.remove(at.child('type')),
      [final type] => SpecEdit.add(at.child('type'), type),
      _ => SpecEdit.add(at.child('type'), types),
    }, sources);
  }

  /// The edits of the `required` list of the schema at [owner] for the
  /// `required` of its [properties].
  Iterable<OverrideEdit> _required(
    SpecLocation owner,
    List<PropertyTarget> properties,
  ) sync* {
    final raw = _object(owner) ?? const {};
    final current = switch (raw['required']) {
      final List<Object?> names => names,
      _ => const <Object?>[],
    };
    final next = [...current];
    final sources = <(OverrideEntry, String)>[];
    for (final property in properties) {
      final name = property.entry.key;
      final required = property.entry.spec['required'] == true;
      if (next.contains(name) == required) {
        _unchanged(property.entry, 'required');
        continue;
      }
      if (required) {
        next.add(name);
      } else {
        next.remove(name);
      }
      sources.add((property.entry, 'required'));
    }
    if (sources.isEmpty) return;
    final at = owner.child('required');
    yield OverrideEdit(
      next.isEmpty ? SpecEdit.remove(at) : SpecEdit.add(at, next),
      sources,
    );
  }

  /// The edit that sets [field] of the object at [at] to [value]; `null`
  /// removes it.
  Iterable<OverrideEdit> _set(
    OverrideEntry entry,
    String field,
    SpecLocation at,
    Map<String, Object?> raw,
    Object? value,
  ) sync* {
    final has = raw.containsKey(field);
    if (value == null ? !has : has && _equality.equals(raw[field], value)) {
      _unchanged(entry, field);
      return;
    }
    yield OverrideEdit(
      value == null
          ? SpecEdit.remove(at.child(field))
          : SpecEdit.add(at.child(field), value),
      [(entry, field)],
    );
  }

  /// [edits] without the ones that touch a node another override's
  /// different edit touches; those are reported. One edit asked for by
  /// several overrides is made once.
  List<OverrideEdit> _withoutConflicts(List<OverrideEdit> edits) {
    final dropped = <OverrideEdit>{};
    final kept = <OverrideEdit>[];
    for (var i = 0; i < edits.length; i++) {
      final a = edits[i];
      if (kept.any((k) => k.edit.sameAs(a.edit))) continue;
      for (var j = 0; j < edits.length; j++) {
        final b = edits[j];
        if (i == j || b.edit.sameAs(a.edit) || !a.edit.overlaps(b.edit)) {
          continue;
        }
        dropped.add(a);
        for (final (entry, field) in a.sources) {
          final other = b.sources.first.$1.pointer.child(b.sources.first.$2);
          _report(
            .overrideConflict,
            entry,
            field,
            'This changes ${a.edit.location.pointer.value}, which the '
            'override at ${other.value} changes too; neither is applied.',
            fix: 'Keep one of them.',
          );
        }
        break;
      }
      if (!dropped.contains(a)) kept.add(a);
    }
    return kept;
  }

  Map<String, Object?>? _object(SpecLocation at) =>
      switch (_documents[at.document]?.valueAt(at.pointer)) {
        (final Map<String, Object?> raw,) => raw,
        _ => null,
      };

  void _unchanged(OverrideEntry entry, String field) => _report(
    .overrideUnchanged,
    entry,
    field,
    'The spec already has this "$field"; the override changes nothing and '
    'can be removed.',
    fix: 'Remove "$field" from the override.',
  );

  void _report(
    DiagnosticCode code,
    OverrideEntry entry,
    String? field,
    String message, {
    String? fix,
  }) {
    final at = field == null ? entry.pointer : entry.pointer.child(field);
    final reason = entry.reason;
    _diagnostics.report(
      code,
      reason == null ? message : '$message Reason given: "$reason".',
      file: _overrides.file,
      pointer: at,
      span: _overrides.spanOf(at),
      fix: fix,
    );
  }
}
```

- [ ] **Step 5: Нормалізатор і `SpecChecker`**

Diff `packages/typed_openapi/lib/src/normalize/normalizer.dart` (`git apply` з кореня):

```diff
diff --git a/packages/typed_openapi/lib/src/normalize/normalizer.dart b/packages/typed_openapi/lib/src/normalize/normalizer.dart
index c9da2d4..ea342e1 100644
--- a/packages/typed_openapi/lib/src/normalize/normalizer.dart
+++ b/packages/typed_openapi/lib/src/normalize/normalizer.dart
@@ -4,6 +4,9 @@ import '../diagnostics/diagnostic_bag.dart';
 import '../load/openapi_version.dart';
 import '../load/spec_document.dart';
 import '../load/spec_loader.dart';
+import '../overrides/override_applier.dart';
+import '../overrides/override_resolver.dart';
+import '../overrides/override_set.dart';
 import '../resolve/spec_documents.dart';
 import '../resolve/spec_model.dart';
 import '../resolve/spec_reader.dart';
@@ -20,18 +23,23 @@ import 'spec_edit.dart';
 /// The result of normalizing a spec.
 final class NormalizedSpec {
   /// Creates a result.
-  const NormalizedSpec(this.model, this.documents);
+  const NormalizedSpec(this.model, this.documents, {this.overrides});
 
   /// The model of the last pass.
   final SpecModel model;
 
   /// The files of the last pass, with every fix applied.
   final SpecDocuments documents;
+
+  /// The client's overrides, whose spec fields are applied; their
+  /// generation fields are for the generator.
+  final OverrideSet? overrides;
 }
 
-/// Reads a spec into the model, runs the rules over it, applies their fixes
-/// to the plain trees and reads it again, until no rule has a fix or
-/// [maxPasses] passes have run.
+/// Reads a spec into the model, applies the spec fields of the client's
+/// overrides, then runs the rules over it, applies their fixes to the plain
+/// trees and reads it again, until no rule has a fix or [maxPasses] passes
+/// have run.
 ///
 /// The report holds what the parser and resolver say about the last pass,
 /// every finding of a rule that fixed something in a pass, and the findings
@@ -89,11 +97,38 @@ final class Normalizer {
   /// The framework whose hints the findings carry.
   final Preset? preset;
 
-  /// Normalizes [document], which declares [version].
-  NormalizedSpec normalize(SpecDocument document, OpenApiVersion version) {
+  /// Normalizes [document], which declares [version], after applying the
+  /// spec fields of [overrides].
+  NormalizedSpec normalize(
+    SpecDocument document,
+    OpenApiVersion version, {
+    OverrideSet? overrides,
+  }) {
     final loader = SpecLoader(_diagnostics);
     var root = document;
     var others = const <SpecDocument>[];
+    if (overrides != null && !overrides.isEmpty) {
+      final documents = SpecDocuments(loader, root);
+      final model = SpecReader(
+        DiagnosticBag(),
+      ).read(root, version, documents: documents);
+      final targets = OverrideResolver(
+        _diagnostics,
+        overrides,
+      ).resolve(model, documents);
+      final edits = OverrideApplier(
+        _diagnostics,
+        overrides,
+        documents,
+        version,
+      ).edits(targets);
+      final edited = _applyOverrides(documents, overrides, edits);
+      root = edited[root.uri] ?? root;
+      others = [
+        for (final loaded in documents.loaded)
+          if (loaded.uri != root.uri) edited[loaded.uri] ?? loaded,
+      ];
+    }
     for (var pass = 1; ; pass++) {
       final scratch = DiagnosticBag();
       final documents = SpecDocuments(loader, root, others: others);
@@ -126,7 +161,7 @@ final class Normalizer {
             );
           }
         }
-        return NormalizedSpec(model, documents);
+        return NormalizedSpec(model, documents, overrides: overrides);
       }
       // Every finding of a rule that fixes something in this pass is part of
       // that fix (a rule may put one edit on the first of several
@@ -185,6 +220,37 @@ final class Normalizer {
     };
   }
 
+  /// Applies the override [edits] in order; returns the edited documents by
+  /// URI. An edit that cannot be applied is reported at its override.
+  Map<Uri, SpecDocument> _applyOverrides(
+    SpecDocuments documents,
+    OverrideSet overrides,
+    List<OverrideEdit> edits,
+  ) {
+    final editors = <Uri, TreeEditor>{};
+    for (final OverrideEdit(:edit, :sources) in edits) {
+      final uri = edit.location.document;
+      final document = documents[uri]!;
+      final editor = editors[uri] ??= TreeEditor(document.root);
+      final problem = editor.apply(edit);
+      if (problem == null) continue;
+      for (final (entry, field) in sources) {
+        final at = entry.pointer.child(field);
+        _diagnostics.report(
+          .fixNotApplied,
+          'This override was not applied: $problem.',
+          file: overrides.file,
+          pointer: at,
+          span: overrides.spanOf(at),
+        );
+      }
+    }
+    return {
+      for (final MapEntry(key: uri, value: editor) in editors.entries)
+        uri: documents[uri]!.withRoot(editor.root),
+    };
+  }
+
   void _report(NormalizerRule rule, Finding finding) {
     final d = finding.diagnostic;
     final hint = switch (preset) {
```

Diff `packages/typed_openapi/lib/src/check/spec_checker.dart` (`git apply` з кореня):

```diff
diff --git a/packages/typed_openapi/lib/src/check/spec_checker.dart b/packages/typed_openapi/lib/src/check/spec_checker.dart
index d13ef21..dd639bb 100644
--- a/packages/typed_openapi/lib/src/check/spec_checker.dart
+++ b/packages/typed_openapi/lib/src/check/spec_checker.dart
@@ -5,6 +5,7 @@ import '../diagnostics/diagnostic_bag.dart';
 import '../load/openapi_version.dart';
 import '../load/spec_loader.dart';
 import '../normalize/normalizer.dart';
+import '../overrides/override_loader.dart';
 
 /// Loads every client's spec and reports what is wrong with it.
 ///
@@ -19,24 +20,31 @@ final class SpecChecker {
   /// Checks the spec of every client in [config].
   ///
   /// Each spec is loaded, its OpenAPI version detected, and then it is read
-  /// into the model with its `$ref`s resolved and normalized with the
-  /// client's rules and preset. [only] limits the run to
-  /// clients with these names; empty means all. A file shared by several
-  /// clients is checked once per distinct preset and set of disabled rules;
-  /// the bag reports a diagnostic the runs share once. Spec paths in
+  /// into the model with its `$ref`s resolved, changed by the client's
+  /// overrides and normalized with the client's rules and preset. An
+  /// overrides file that cannot be used is reported and the spec is checked
+  /// without it. [only] limits the run to clients with these names; empty
+  /// means all. A file shared by several clients is checked once per
+  /// distinct preset, set of disabled rules and overrides file; the bag
+  /// reports a diagnostic the runs share once. Spec and overrides paths in
   /// diagnostics are relative to the config file's directory.
   void check(ProjectConfig config, {Set<String> only = const {}}) {
     final loader = SpecLoader(_diagnostics);
     final detector = OpenApiVersionDetector(_diagnostics);
     final configDir = p.dirname(p.absolute(config.file));
-    // A run is a file with a preset and a set of disabled rules.
-    final checked = <(String, Preset?, String)>{};
+    // A run is a file with a preset, a set of disabled rules and overrides.
+    final checked = <(String, Preset?, String, String?)>{};
     for (final client in config.clients) {
       if (only.isNotEmpty && !only.contains(client.name)) continue;
       final rules = (client.disabledRules.toList()..sort()).join(',');
-      if (!checked.add((p.absolute(client.input), client.preset, rules))) {
-        continue;
-      }
+      final overridesPath = client.overrides;
+      final run = (
+        p.absolute(client.input),
+        client.preset,
+        rules,
+        overridesPath,
+      );
+      if (!checked.add(run)) continue;
       final document = loader.load(
         client.input,
         displayPath: p.relative(client.input, from: configDir),
@@ -44,11 +52,17 @@ final class SpecChecker {
       if (document == null) continue;
       final version = detector.detect(document);
       if (version == null) continue;
+      final overrides = overridesPath == null
+          ? null
+          : OverrideLoader(_diagnostics).load(
+              overridesPath,
+              displayPath: p.relative(overridesPath, from: configDir),
+            );
       Normalizer(
         _diagnostics,
         disabled: client.disabledRules,
         preset: client.preset,
-      ).normalize(document, version);
+      ).normalize(document, version, overrides: overrides);
     }
   }
 }
```

- [ ] **Step 6: Перевірити**

Run (з `packages/typed_openapi`): `dart test`
Expected: PASS, 367 тестів (`+367: All tests passed!`).

Run (з `packages/typed_openapi`): `dart format lib test bin` двічі
Expected: другий запуск — `0 changed`.

Run (з кореня): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 7: Коміт**

```bash
git add packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart packages/typed_openapi/lib/src/overrides/override_applier.dart packages/typed_openapi/lib/src/normalize/normalizer.dart packages/typed_openapi/lib/src/check/spec_checker.dart packages/typed_openapi/test/overrides/override_applier_test.dart packages/typed_openapi/test/check/spec_checker_test.dart
git commit -m "feat(typed_openapi): apply override spec fields before the normalizer rules" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


### Task 4: Зворотна адреса і фрагменти override-у в підказках правил

**Files:**
- Create: `packages/typed_openapi/lib/src/overrides/override_snippet.dart`, `packages/typed_openapi/test/overrides/override_snippet_test.dart`
- Modify: `packages/typed_openapi/lib/src/normalize/normalizer_rule.dart`, `packages/typed_openapi/lib/src/diagnostics/reporters.dart`, `packages/typed_openapi/lib/src/normalize/rules/schema_shape_rules.dart`, `packages/typed_openapi/lib/src/normalize/rules/enum_rules.dart`

**Interfaces:**
- Consumes: `SpecModel` (`document.components.schemas`, `resolveSchema`), `SchemaObject.properties`, `SpecLocation` (M2); `RuleContext`, правила `DoubleArray`, `FormatOnArray`, `BinaryObject`, `ContradictoryObjectType`, `NullableEnumOneOf` (M3); `OverrideLoader` і `Normalizer.normalize(..., overrides:)` (задачі 1, 3) — у тестах.
- Produces: блок «override_snippet.dart, normalize (Task 4)».

Поведінка, яку закріплюють тести:
- `addressOf`: схема `components.schemas` — за ключем, що її визначає (не за аліасом, також для властивостей); властивість — `schemas.<key>.properties.<name>`; схема в іншому файлі — за ключем, чий `$ref` туди веде; inline-схема параметра, `items`, властивість вкладеного об'єкта, сам ключ-аліас — `null`.
- `forSchema`: блоковий YAML, значення у flow-стилі; `on`, `1.5`, `a b`, `#/...` — у лапках JSON; `null` — `null`.
- Для кожного з п'яти правил: `fix` закінчується ` Override:` і фрагментом; цей фрагмент, прочитаний як файл override-ів, прибирає знахідку і не дає жодної діагностики файлу override-ів (перевірка «повний і правильний фрагмент»).
- Негатив: та сама знахідка в схемі тіла запиту (без адреси) — `fix` без фрагмента; `format: money` на масиві — TOA204 без фрагмента (тип елементів невідомий), `format: date` поряд — з `items: {type: string, format: date}`.
- `TextReporter` зсуває рядки багаторядкового `fix` на 4 пробіли.

- [ ] **Step 1: Тест, що не проходить**

Створи `packages/typed_openapi/test/overrides/override_snippet_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/diagnostics/reporters.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/load/openapi_version.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/model/spec_node.dart';
import 'package:typed_openapi/src/normalize/normalizer.dart';
import 'package:typed_openapi/src/overrides/override_loader.dart';
import 'package:typed_openapi/src/overrides/override_snippet.dart';
import 'package:typed_openapi/src/resolve/spec_reader.dart';

import '../helpers/temp_dir.dart';

/// Normalizes [spec] with the overrides in [overrides], if any.
DiagnosticBag _normalize(String spec, {String? overrides}) {
  final bag = DiagnosticBag();
  final document = SpecLoader(bag).parse(spec, 'api.yaml')!;
  final version = OpenApiVersionDetector(bag).detect(document)!;
  final set = overrides == null
      ? null
      : OverrideLoader(bag).parse(overrides, 'o.yaml');
  Normalizer(bag).normalize(document, version, overrides: set);
  return bag;
}

void main() {
  group('addressOf', () {
    late Uri api;
    late Uri pet;
    late OverrideSnippet snippet;

    setUpAll(() {
      final dir = TempDir();
      dir.write('pet.yaml', 'Pet: {type: object, properties: {id: {}}}\n');
      final path = dir.write('api.yaml', r'''
openapi: 3.1.0
info: {title: t, version: '1'}
paths:
  /pets:
    get:
      parameters:
        - {name: q, in: query, schema: {type: string}}
      responses: {'200': {description: ok}}
components:
  schemas:
    Alias: {$ref: '#/components/schemas/Order'}
    Order:
      type: object
      properties:
        lines: {type: array, items: {type: object, properties: {n: {}}}}
    Pet: {$ref: 'pet.yaml#/Pet'}
''');
      final bag = DiagnosticBag();
      final document = SpecLoader(bag).load(path)!;
      final model = SpecReader(bag).read(document, OpenApiVersion.v31);
      snippet = OverrideSnippet(model);
      api = document.uri;
      pet = api.resolve('pet.yaml');
    });

    SpecLocation at(String pointer, [Uri? file]) =>
        SpecLocation(file ?? api, JsonPointer.parse(pointer));

    test('names a components schema by the key that defines it', () {
      expect(snippet.addressOf(at('#/components/schemas/Order')), [
        'schemas',
        'Order',
      ]);
    });

    test('names a property of a components schema', () {
      expect(
        snippet.addressOf(at('#/components/schemas/Order/properties/lines')),
        ['schemas', 'Order', 'properties', 'lines'],
      );
    });

    test(r'follows a key whose $ref leads into another file', () {
      expect(snippet.addressOf(at('#/Pet', pet)), ['schemas', 'Pet']);
      expect(snippet.addressOf(at('#/Pet/properties/id', pet)), [
        'schemas',
        'Pet',
        'properties',
        'id',
      ]);
    });

    test('has no address for schemas the overrides file cannot name', () {
      for (final pointer in [
        '#/paths/~1pets/get/parameters/0/schema',
        '#/components/schemas/Order/properties/lines/items',
        '#/components/schemas/Order/properties/lines/items/properties/n',
        '#/components/schemas/Alias',
      ]) {
        expect(snippet.addressOf(at(pointer)), isNull, reason: pointer);
      }
    });

    test('writes block YAML and quotes what YAML would misread', () {
      expect(
        snippet.forSchema(at('#/components/schemas/Order/properties/lines'), {
          'format': null,
          'items': {
            'type': 'string',
            'enum': ['on', '1.5', 'a b', 2],
          },
          r'$ref': '#/components/schemas/Order',
        }),
        'schemas:\n'
        '  Order:\n'
        '    properties:\n'
        '      lines:\n'
        '        format: null\n'
        '        items: {type: string, enum: ["on", "1.5", "a b", 2]}\n'
        r'        $ref: "#/components/schemas/Order"',
      );
    });
  });

  group('rule fixes carry an override that removes the finding', () {
    const header = '''
openapi: 3.0.3
info: {title: t, version: '1'}
paths: {}
''';
    final cases = {
      DiagnosticCode.doubleArray: '''
    Order:
      type: object
      properties:
        lines:
          type: array
          items: {required: true, type: array, items: {type: string}}
''',
      DiagnosticCode.formatOnArray: '''
    Ids: {type: array, format: int64}
''',
      DiagnosticCode.binaryObject: '''
    Upload:
      type: object
      properties:
        file: {type: object, format: binary}
''',
      DiagnosticCode.contradictoryObjectType: '''
    Value:
      type: object
      oneOf: [{type: string}, {type: integer}]
''',
      DiagnosticCode.nullableEnumOneOf: r'''
    Status: {type: string, enum: [a, b]}
    Pet:
      type: object
      properties:
        status:
          oneOf:
            - {enum: [null]}
            - {$ref: '#/components/schemas/Status'}
''',
    };
    for (final MapEntry(key: code, value: schemas) in cases.entries) {
      test(code.slug, () {
        final spec = '${header}components:\n  schemas:\n$schemas';
        final found = _normalize(spec).all.where((d) => d.code == code);
        final fix = found.single.fix!;
        expect(fix, contains(' Override:\nschemas:\n'));
        final overrides = fix.substring(fix.indexOf('\n') + 1);
        final again = _normalize(spec, overrides: overrides);
        expect(again.all.where((d) => d.code == code), isEmpty);
        expect(again.all.where((d) => d.file == 'o.yaml'), isEmpty);
      });
    }

    test('format-on-array has no override for an unknown format', () {
      const spec = '''
openapi: 3.0.3
info: {title: t, version: '1'}
paths: {}
components:
  schemas:
    Prices: {type: array, format: money}
    Days: {type: array, format: date}
''';
      final found = _normalize(
        spec,
      ).all.where((d) => d.code == DiagnosticCode.formatOnArray).toList();
      final [days, prices] = found;
      expect(days.pointer?.value, '#/components/schemas/Days/format');
      expect(days.fix, contains('items: {type: string, format: date}'));
      expect(prices.pointer?.value, '#/components/schemas/Prices/format');
      expect(prices.fix, isNot(contains('Override:')));
      expect(prices.fix, contains('the element schema'));
    });

    test('a schema without an address gets no override', () {
      const spec = '''
openapi: 3.0.3
info: {title: t, version: '1'}
paths:
  /files:
    post:
      requestBody:
        content:
          application/json: {schema: {type: object, format: binary}}
      responses: {'200': {description: ok}}
''';
      final d = _normalize(
        spec,
      ).all.singleWhere((d) => d.code == DiagnosticCode.binaryObject);
      expect(d.fix, isNot(contains('Override:')));
    });
  });

  test('the text report indents the lines of a multi-line fix', () {
    final bag = DiagnosticBag()
      ..add(
        const Diagnostic(
          code: DiagnosticCode.binaryObject,
          severity: Severity.warning,
          message: 'm',
          fix: 'Do it. Override:\nschemas:\n  A:\n    type: string',
        ),
      );
    expect(
      const TextReporter().format(bag),
      'warning TOA205 binary-object: m\n'
      '  fix: Do it. Override:\n'
      '    schemas:\n'
      '      A:\n'
      '        type: string\n'
      'errors: 0, warnings: 1, infos: 0',
    );
  });
}
```

- [ ] **Step 2: Запустити тест**

Run (з `packages/typed_openapi`): `dart test test/overrides/override_snippet_test.dart`
Expected: FAIL — `override_snippet.dart` не існує.

- [ ] **Step 3: Адреса і фрагмент**

Створи `packages/typed_openapi/lib/src/overrides/override_snippet.dart`:

```dart
import 'dart:convert';

import '../model/schema.dart';
import '../model/spec_node.dart';
import '../resolve/spec_model.dart';

/// Writes the override that changes a schema of a spec, as YAML to copy
/// into the overrides file.
///
/// Only schemas the overrides file can address have one: a schema in
/// `components.schemas` (or the schema its `$ref` chain ends at) and a
/// property in its own `properties`.
final class OverrideSnippet {
  /// Creates a writer for schemas of [_model].
  const OverrideSnippet(this._model);

  static final _plain = RegExp(r'^[A-Za-z_$][A-Za-z0-9_.$/-]*$');
  static final _reserved = RegExp(
    r'^(null|true|false|yes|no|on|off|y|n)$',
    caseSensitive: false,
  );

  final SpecModel _model;

  /// The keys that lead to the override of the schema at [location]:
  /// `schemas` and the components key, then `properties` and the property
  /// name for a property; null when the schema has no address.
  List<String>? addressOf(SpecLocation location) {
    final schemas = _model.document.components?.schemas ?? const {};
    // A key that defines its schema wins over a key that refers to one.
    final keys = [
      for (final MapEntry(:key, :value) in schemas.entries)
        if (_isDefinition(value)) key,
      for (final MapEntry(:key, :value) in schemas.entries)
        if (!_isDefinition(value)) key,
    ];
    for (final key in keys) {
      final schema = _model.resolveSchema(schemas[key]!);
      if (schema is! SchemaObject) continue;
      if (schema.location == location) return ['schemas', key];
      for (final MapEntry(key: name, value: property)
          in schema.properties.entries) {
        if (property.location == location) {
          return ['schemas', key, 'properties', name];
        }
      }
    }
    return null;
  }

  /// The override of the schema at [location] that sets [fields] (`null`
  /// removes a field), as block YAML; null when the schema has no address.
  String? forSchema(SpecLocation location, Map<String, Object?> fields) {
    final address = addressOf(location);
    if (address == null) return null;
    final lines = <String>[];
    for (final (depth, key) in address.indexed) {
      lines.add('${'  ' * depth}${_key(key)}:');
    }
    final indent = '  ' * address.length;
    for (final MapEntry(:key, :value) in fields.entries) {
      lines.add('$indent${_key(key)}: ${_flow(value)}');
    }
    return lines.join('\n');
  }

  static bool _isDefinition(Schema schema) =>
      schema is! SchemaObject || schema.ref == null;

  static String _key(String key) => _isPlain(key) ? key : jsonEncode(key);

  /// [value] as a YAML flow value; strings that YAML would read as
  /// something else are quoted.
  static String _flow(Object? value) => switch (value) {
    final Map<String, Object?> map =>
      '{${[for (final MapEntry(:key, :value) in map.entries) '${_key(key)}: ${_flow(value)}'].join(', ')}}',
    final List<Object?> list => '[${list.map(_flow).join(', ')}]',
    final String text => _isPlain(text) ? text : jsonEncode(text),
    _ => jsonEncode(value),
  };

  static bool _isPlain(String text) =>
      _plain.hasMatch(text) && !_reserved.hasMatch(text);
}
```

- [ ] **Step 4: Контекст правил, звіт і правила**

Diff `packages/typed_openapi/lib/src/normalize/normalizer_rule.dart` (`git apply` з кореня):

```diff
diff --git a/packages/typed_openapi/lib/src/normalize/normalizer_rule.dart b/packages/typed_openapi/lib/src/normalize/normalizer_rule.dart
index aa7b267..4867c45 100644
--- a/packages/typed_openapi/lib/src/normalize/normalizer_rule.dart
+++ b/packages/typed_openapi/lib/src/normalize/normalizer_rule.dart
@@ -3,6 +3,7 @@ import '../diagnostics/diagnostic.dart';
 import '../diagnostics/diagnostic_code.dart';
 import '../load/openapi_version.dart';
 import '../model/spec_node.dart';
+import '../overrides/override_snippet.dart';
 import '../resolve/spec_documents.dart';
 import '../resolve/spec_model.dart';
 import 'spec_edit.dart';
@@ -33,6 +34,8 @@ final class RuleContext {
   /// The version the root document declares.
   final OpenApiVersion version;
 
+  late final OverrideSnippet _snippets = OverrideSnippet(model);
+
   /// Every node of type [T], ordered by location.
   Iterable<T> nodes<T extends SpecNode>() => model.nodes.whereType<T>();
 
@@ -48,6 +51,18 @@ final class RuleContext {
         _ => null,
       };
 
+  /// [fix] followed by the override of the schema at [schema] that sets
+  /// [fields], to copy into the overrides file; [fix] alone when the schema
+  /// has no override address.
+  String withOverride(
+    String fix,
+    SpecLocation schema,
+    Map<String, Object?> fields,
+  ) => switch (_snippets.forSchema(schema, fields)) {
+    final snippet? => '$fix Override:\n$snippet',
+    null => fix,
+  };
+
   /// A finding of [code] at [at], with [edits] when it is a fix.
   Finding finding(
     DiagnosticCode code,
```

Diff `packages/typed_openapi/lib/src/diagnostics/reporters.dart` (`git apply` з кореня):

```diff
diff --git a/packages/typed_openapi/lib/src/diagnostics/reporters.dart b/packages/typed_openapi/lib/src/diagnostics/reporters.dart
index 540f31a..b9d58c9 100644
--- a/packages/typed_openapi/lib/src/diagnostics/reporters.dart
+++ b/packages/typed_openapi/lib/src/diagnostics/reporters.dart
@@ -26,7 +26,8 @@ final class TextReporter implements DiagnosticReporter {
       final pointer = d.pointer;
       if (pointer != null) out.writeln('  at ${pointer.value}');
       final fix = d.fix;
-      if (fix != null) out.writeln('  fix: $fix');
+      // A fix may end with an override snippet on several lines.
+      if (fix != null) out.writeln('  fix: ${fix.replaceAll('\n', '\n    ')}');
     }
     out.write(
       'errors: ${diagnostics.count(.error)}, '
```

Diff `packages/typed_openapi/lib/src/normalize/rules/schema_shape_rules.dart` (`git apply` з кореня):

```diff
diff --git a/packages/typed_openapi/lib/src/normalize/rules/schema_shape_rules.dart b/packages/typed_openapi/lib/src/normalize/rules/schema_shape_rules.dart
index 475ff2c..8b6950f 100644
--- a/packages/typed_openapi/lib/src/normalize/rules/schema_shape_rules.dart
+++ b/packages/typed_openapi/lib/src/normalize/rules/schema_shape_rules.dart
@@ -73,16 +73,24 @@ final class DoubleArray extends NormalizerRule {
       }
       final raw = context.rawObject(items.location);
       if (raw == null || raw['required'] is! bool) continue;
+      const fix =
+          'If the field is a flat list, declare it once at the source; '
+          'until then, override "items" of this schema with the inner '
+          '"items".';
       yield context.finding(
         .doubleArray,
         'The items of this array are arrays too and say "required: '
         '${raw['required']}", the shape a decorator gives a list declared '
         'twice; clients read a list of lists.',
         items.location,
-        fix:
-            'If the field is a flat list, declare it once at the source; '
-            'until then, override "items" of this schema with the inner '
-            '"items".',
+        fix: switch (raw['items']) {
+          final Map<String, Object?> inner => context.withOverride(
+            fix,
+            schema.location,
+            {'items': inner},
+          ),
+          _ => fix,
+        },
       );
     }
   }
@@ -108,6 +116,41 @@ final class FormatOnArray extends NormalizerRule {
   @override
   List<DiagnosticCode> get codes => const [.formatOnArray];
 
+  /// The element type each known format implies: the number formats of the
+  /// OpenAPI format registry and the string formats of OpenAPI and JSON
+  /// Schema. Another format gives no override, because its type is unknown.
+  static final _elementTypes = {
+    'int32': 'integer',
+    'int64': 'integer',
+    'float': 'number',
+    'double': 'number',
+    for (final format in [
+      'binary',
+      'byte',
+      'date',
+      'date-time',
+      'duration',
+      'email',
+      'hostname',
+      'idn-email',
+      'idn-hostname',
+      'ipv4',
+      'ipv6',
+      'iri',
+      'iri-reference',
+      'json-pointer',
+      'password',
+      'regex',
+      'relative-json-pointer',
+      'time',
+      'uri',
+      'uri-reference',
+      'uri-template',
+      'uuid',
+    ])
+      format: 'string',
+  };
+
   @override
   Iterable<Finding> check(RuleContext context) sync* {
     for (final schema in context.nodes<SchemaObject>()) {
@@ -118,14 +161,25 @@ final class FormatOnArray extends NormalizerRule {
           ArrayWithoutItems._hasItemsKey(context, schema)) {
         continue;
       }
+      final type = _elementTypes[format];
+      const move = 'Move it into the elements at the source; until then, ';
       yield context.finding(
         .formatOnArray,
         '"format: $format" is on the array, which has no "items", not on its '
         'elements.',
         schema.location.child('format'),
-        fix:
-            'Move it into the elements at the source; until then, override '
-            '"items" of this schema with {type: string, format: $format}.',
+        fix: type == null
+            ? '${move}override "items" of this schema with the element schema '
+                  'and remove its "format".'
+            : context.withOverride(
+                '${move}override "items" of this schema with {type: $type, '
+                'format: $format} and remove its "format".',
+                schema.location,
+                {
+                  'format': null,
+                  'items': {'type': type, 'format': format},
+                },
+              ),
       );
     }
   }
@@ -155,9 +209,12 @@ final class BinaryObject extends NormalizerRule {
         '"type: object" with "format: binary" does not describe a file; a '
         'file is "type: string, format: binary".',
         schema.location.child('type'),
-        fix:
-            'Write "type: string" at the source; until then, override "type" '
-            'of this schema with string.',
+        fix: context.withOverride(
+          'Write "type: string" at the source; until then, override "type" '
+          'of this schema with string.',
+          schema.location,
+          {'type': 'string'},
+        ),
       );
     }
   }
@@ -199,9 +256,12 @@ final class ContradictoryObjectType extends NormalizerRule {
         '"type: object" is next to "oneOf"/"anyOf" whose branches are all '
         '$names; no value matches both.',
         schema.location.child('type'),
-        fix:
-            'Remove "type: object" at the source; until then, override "type" '
-            'of this schema.',
+        fix: context.withOverride(
+          'Remove "type: object" at the source; until then, remove "type" of '
+          'this schema with an override.',
+          schema.location,
+          {'type': null},
+        ),
       );
     }
   }
```

Diff `packages/typed_openapi/lib/src/normalize/rules/enum_rules.dart` (`git apply` з кореня):

```diff
diff --git a/packages/typed_openapi/lib/src/normalize/rules/enum_rules.dart b/packages/typed_openapi/lib/src/normalize/rules/enum_rules.dart
index 946032d..ade94fa 100644
--- a/packages/typed_openapi/lib/src/normalize/rules/enum_rules.dart
+++ b/packages/typed_openapi/lib/src/normalize/rules/enum_rules.dart
@@ -91,9 +91,12 @@ final class NullableEnumOneOf extends NormalizerRule {
         'This is a nullable reference to "$ref" written as "oneOf" with an '
         'enum of only null; generators read it as a union of two types.',
         schema.location.child('oneOf'),
-        fix:
-            'Write a nullable reference to "$ref" at the source; until then, '
-            'override this schema as a nullable "$ref".',
+        fix: context.withOverride(
+          'Write a nullable reference to "$ref" at the source; until then, '
+          'override this schema as a nullable "$ref".',
+          schema.location,
+          {r'$ref': ref, 'nullable': true},
+        ),
       );
     }
   }
```

- [ ] **Step 5: Перевірити**

Run (з `packages/typed_openapi`): `dart test`
Expected: PASS, 380 тестів (`+380: All tests passed!`).

Run (з `packages/typed_openapi`): `dart format lib test bin` двічі
Expected: другий запуск — `0 changed`.

Run (з кореня): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 6: Коміт**

```bash
git add packages/typed_openapi/lib/src/overrides/override_snippet.dart packages/typed_openapi/lib/src/normalize/normalizer_rule.dart packages/typed_openapi/lib/src/diagnostics/reporters.dart packages/typed_openapi/lib/src/normalize/rules/schema_shape_rules.dart packages/typed_openapi/lib/src/normalize/rules/enum_rules.dart packages/typed_openapi/test/overrides/override_snippet_test.dart
git commit -m "feat(typed_openapi): add override snippets to the fixes of diagnostic-only rules" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```


### Task 5: Документація, публічний API, наскрізний тест CLI, прогін корпусу

**Files:**
- Modify: `CLAUDE.md`, `packages/typed_openapi/CHANGELOG.md`, `packages/typed_openapi/README.md`, `packages/typed_openapi/README.ua.md`, `packages/typed_openapi/lib/typed_openapi.dart`, `packages/typed_openapi/test/cli/cli_test.dart`

**Interfaces:**
- Consumes: усе з задач 1–4.
- Produces: експорт `OverrideLoader`, `OverrideSet`, `OverrideEntry`, `OperationOverride`, `ParameterOverride`, `BodyOverride`, `ResponseOverride`, `SchemaOverride`, `PropertyOverride`, `DartTypeOverride` з `package:typed_openapi/typed_openapi.dart`. Не експортуються: `OverrideResolver`, `OverrideTarget`, `OverrideApplier`, `OverrideEdit`, `OverrideSnippet`.

Наскрізний тест закріплює весь текстовий звіт `check` для конфлікту двох адрес однієї операції, застарілого override-у з `reason` і зайвого поля (зі зміненим полем поряд), код виходу `1`. Він проходить одразу: функціональність уже є після задач 1–4, тест фіксує зовнішню поведінку.

- [ ] **Step 1: Наскрізний тест CLI**

Diff `packages/typed_openapi/test/cli/cli_test.dart` (`git apply` з кореня):

```diff
diff --git a/packages/typed_openapi/test/cli/cli_test.dart b/packages/typed_openapi/test/cli/cli_test.dart
index b338db0..200f3db 100644
--- a/packages/typed_openapi/test/cli/cli_test.dart
+++ b/packages/typed_openapi/test/cli/cli_test.dart
@@ -85,6 +85,67 @@ clients:
     expect(err, isEmpty);
   });
 
+  test('reports stale, redundant and conflicting overrides', () async {
+    final dir = TempDir();
+    dir.write('api.yaml', '''
+openapi: 3.0.3
+info: {title: api, version: "1"}
+paths:
+  /pets/{id}:
+    get:
+      operationId: getPet
+      parameters:
+        - {name: id, in: path, required: true, schema: {type: string}}
+      responses: {'200': {description: ok}}
+components:
+  schemas:
+    Pet: {type: object, format: binary}
+''');
+    dir.write('api.overrides.yaml', '''
+operations:
+  getPet: {name: fetchPet}
+  GET /pets/{id}: {name: loadPet}
+  deletePet:
+    reason: removed in v2
+    exclude: true
+schemas:
+  Pet: {type: string, nullable: false}
+''');
+    final path = dir.write('typed_openapi.yaml', '''
+clients:
+  api: {input: api.yaml, output: lib/api, overrides: api.overrides.yaml}
+''');
+    final (code, out, _) = await run(['check', '-c', path]);
+    expect(code, 1);
+    expect(
+      out,
+      'error TOA806 override-conflict: This override and the one at '
+      '#/operations/GET ~1pets~1{id} name the same node '
+      '(#/paths/~1pets~1{id}/get); neither is applied.\n'
+      '  --> api.overrides.yaml:2:11\n'
+      '  at #/operations/getPet\n'
+      '  fix: Merge them into one override.\n'
+      'error TOA806 override-conflict: This override and the one at '
+      '#/operations/getPet name the same node (#/paths/~1pets~1{id}/get); '
+      'neither is applied.\n'
+      '  --> api.overrides.yaml:3:19\n'
+      '  at #/operations/GET ~1pets~1{id}\n'
+      '  fix: Merge them into one override.\n'
+      'warning TOA804 override-target-not-found: No operation has '
+      'operationId "deletePet". The override is not applied. Reason given: '
+      '"removed in v2".\n'
+      '  --> api.overrides.yaml:5:5\n'
+      '  at #/operations/deletePet\n'
+      '  fix: Remove the override, or fix its address.\n'
+      'info TOA807 override-unchanged: The spec already has this '
+      '"nullable"; the override changes nothing and can be removed.\n'
+      '  --> api.overrides.yaml:8:33\n'
+      '  at #/schemas/Pet/nullable\n'
+      '  fix: Remove "nullable" from the override.\n'
+      'errors: 2, warnings: 1, infos: 1\n',
+    );
+  });
+
   test('reports broken references in the spec', () async {
     final dir = TempDir();
     dir.write('api.yaml', r'''
```

Run (з `packages/typed_openapi`): `dart test test/cli`
Expected: PASS.

- [ ] **Step 2: Документація і експорт**

Diff `CLAUDE.md` (`git apply` з кореня):

```diff
diff --git a/CLAUDE.md b/CLAUDE.md
index 7f3ae54..4ed777c 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -104,8 +104,41 @@ All under `packages/typed_openapi/lib/src/`, one folder per stage:
   without `#` or `/` is a component name, also with a dot, when it is a key
   of `components.schemas`, and a remote value says remote refs are not read;
   `SchemaType.integer.accepts` takes whole-number doubles beyond int64.
+- `overrides/` - `OverrideLoader` reads a client's overrides file (JSON or
+  YAML, through `SpecLoader`) into an immutable `OverrideSet`: operations
+  (`operationId` or `METHOD /path`) with parameters (`name` or `in:name`),
+  `requestBody` and `responses`, schemas (`components.schemas` keys) with
+  their own `properties`. Keys are camelCase. Each entry splits into spec
+  fields (`spec`, a map where `null` removes the field) and typed
+  generation fields (`name`, `exclude`, `group`, `exhaustive`, `dartType`,
+  `triState`) that M4 only keeps for the generator (`sse` is not accepted
+  until M10 settles its shape). A missing file is TOA801, a directory or a
+  bad value TOA802 (the value is ignored), an unknown key the error TOA803
+  with "did you mean" for a known key within Levenshtein distance 2.
+  `OverrideResolver` maps entries to model nodes (`OverrideTarget`; a
+  schema follows its `$ref` chain, a property does not, a parameter is the
+  node that defines it): missing node TOA804 (warning), ambiguous address
+  TOA805, two entries for one node TOA806 (none of them applies); a
+  parameter, body or response override with spec fields whose node lies
+  outside its operation (path-level, `$ref`'d, another file) is TOA808
+  (info, names the shared node). `OverrideApplier` turns spec
+  fields into `SpecEdit`s with set semantics (a value replaces the spec's
+  value, `null` removes it), dialect-aware `nullable` (3.0 `nullable`, 3.1+
+  `null` in `type`; a nullable reference is `allOf` + `nullable` in 3.0 and
+  `anyOf` with `{type: 'null'}` from 3.1), a field the spec already has is
+  TOA807 (info), and two different edits of one node by different entries
+  are TOA806. `Normalizer.normalize(..., overrides:)` applies the edits once
+  before its passes, so rules see the overridden spec; `NormalizedSpec`
+  carries the `OverrideSet`. `OverrideSnippet` turns a schema location back
+  into an override address and block YAML; rules use it through
+  `RuleContext.withOverride` (TOA203-TOA206, TOA303; TOA204 only for a
+  format whose element type is known), and `TextReporter` indents the
+  lines of a multi-line fix.
 - `config/` - `ConfigLoader`, `ProjectConfig`, `ClientConfig`, `Preset`.
-- `check/` - `SpecChecker`: config -> load -> version -> `Normalizer`.
+- `check/` - `SpecChecker`: config -> load -> version -> overrides ->
+  `Normalizer`; an overrides file that cannot be used is reported (an
+  error) and the spec is checked without it; `generate` (M9) must skip
+  such a client.
 - `cli/` - `TypedOpenApiCli` (`cli.dart`, owns the `CommandRunner` and maps
   usage errors to exit code 64) and `CheckCommand` (`check_command.dart`,
   options `--config/-c` and `--format`, client names as positional
@@ -120,13 +153,17 @@ All under `packages/typed_openapi/lib/src/`, one folder per stage:
   `RefKind`, `OpenApiDocument` and the other OAS objects), the entry points
   `SpecReader`, `SpecModel` and `SpecDocuments`, and the normalizer
   (`Normalizer`, `NormalizedSpec`, `NormalizerRule`, `RuleContext`,
-  `Finding`, `SpecEdit`, `EditOperation`). Not exported: `CheckCommand`, the
+  `Finding`, `SpecEdit`, `EditOperation`) and the overrides file
+  (`OverrideLoader`, `OverrideSet`, `OverrideEntry` and its subclasses,
+  `DartTypeOverride`). Not exported: `CheckCommand`, the
   internals of `parse/` (`OpenApiParser`, `OperationParser`, `SchemaParser`,
   `ObjectReader`, `ParseContext`, `SpecIndex`, `DialectChecker`), `resolve/`
   (`RefTarget`, `RefResolver`), `normalize/` (`TreeEditor`, the rule
-  classes), `YamlComposer` and `load/yaml/`.
+  classes), `overrides/` (`OverrideResolver`, `OverrideApplier`,
+  `OverrideSnippet`), `YamlComposer` and `load/yaml/`.
 
-Data flows loader -> parser -> resolver -> normalizer -> checker, every stage
+Data flows loader -> parser -> resolver -> overrides -> normalizer ->
+checker, every stage
 writing problems into one `DiagnosticBag`; reporters read the bag at the end.
 
 Rules of the pipeline:
```

Diff `packages/typed_openapi/CHANGELOG.md` (`git apply` з кореня):

```diff
diff --git a/packages/typed_openapi/CHANGELOG.md b/packages/typed_openapi/CHANGELOG.md
index a5204ce..200e60a 100644
--- a/packages/typed_openapi/CHANGELOG.md
+++ b/packages/typed_openapi/CHANGELOG.md
@@ -64,3 +64,30 @@
   `RuleContext`, `Finding`, `SpecEdit`, `EditOperation`, `SpecDocuments`.
 - A region of a spec that several `$ref`s, enclosing nodes or clients reach is
   read once, and an identical diagnostic is reported once.
+- Overrides: `clients.<name>.overrides` names a JSON or YAML file that
+  addresses operations (`operationId` or `METHOD /path`), their parameters
+  (`name` or `in:name`), request body and responses, and schemas of
+  `components.schemas` with their properties. Spec fields (`type`,
+  `format`, `nullable`, `required`, `items`, `additionalProperties`, `enum`,
+  `discriminator`, `$ref`, parameter `required`/`schema`, body and response
+  `contentType`/`schema`) replace the spec's values before the normalizer
+  runs (`null` removes a field; `nullable` follows the document's dialect).
+  Generation fields (`name`, `exclude`, `group`, `exhaustive`, `dartType`,
+  `triState`) are checked and kept for the generator. Every entry may have
+  a `reason`, printed in diagnostics about it. A missing overrides file is
+  TOA801, a directory or an invalid value TOA802, an unknown key the error
+  TOA803 (with "did you mean" for a close known key), an override whose
+  target is gone TOA804 (warning), an ambiguous address TOA805, two
+  overrides of one node TOA806, an override the spec already matches TOA807
+  (info, "can be removed"), and a change through an operation of a node
+  other operations share TOA808 (info).
+- The fixes of `double-array`, `format-on-array`, `binary-object`,
+  `contradictory-object-type` and `nullable-enum-one-of` end with the
+  override to copy into the overrides file, when the schema is in
+  `components.schemas` or is one of its properties (`format-on-array` only
+  for a format whose element type is known).
+- Programmatic API: `OverrideLoader`, `OverrideSet`, `OverrideEntry`,
+  `OperationOverride`, `ParameterOverride`, `BodyOverride`,
+  `ResponseOverride`, `SchemaOverride`, `PropertyOverride`,
+  `DartTypeOverride`; `Normalizer.normalize` takes `overrides:` and
+  `NormalizedSpec.overrides` returns them.
```

Diff `packages/typed_openapi/README.md` (`git apply` з кореня):

````diff
diff --git a/packages/typed_openapi/README.md b/packages/typed_openapi/README.md
index 68b1aa0..b0986d8 100644
--- a/packages/typed_openapi/README.md
+++ b/packages/typed_openapi/README.md
@@ -45,6 +45,33 @@ defaults:
   rules: {dedupe-enum-values: false}
 ```
 
+Fix what the normalizer cannot know in an overrides file, without touching
+the backend. Name it in the client (`overrides: typed_openapi.overrides.yaml`)
+and address the spec by operations and schemas, not by pointers:
+
+```yaml
+operations:
+  getPet:                     # operationId, or METHOD /path: 'GET /pets/{id}'
+    parameters:
+      id: {schema: {type: integer, format: int64}}   # path:id if names clash
+    responses:
+      '200': {contentType: application/json}
+schemas:
+  Pet:
+    reason: the backend sends null for pets without an owner
+    properties:
+      owner: {nullable: true}
+      photo: {type: string, format: binary}
+```
+
+Overrides change the spec before the normalizer runs; `null` removes a field.
+An override whose target is gone is a warning, one the spec already matches
+is an info that it can be removed, and a misspelled key is an error that
+suggests the closest known one. Fields for the generator (`name`, `exclude`,
+`group`, `exhaustive`, `dartType`, `triState`) are checked now and used once
+code generation lands. Hints of rules that cannot fix a
+defect themselves end with the override to copy.
+
 Every finding has a stable code (`TOA011`), a JSON pointer into the spec and,
 for files the parser could position, a line and column. Exit code `1` means
 at least one error, `64` wrong arguments or an unknown client, `78` the
````

Diff `packages/typed_openapi/README.ua.md` (`git apply` з кореня):

````diff
diff --git a/packages/typed_openapi/README.ua.md b/packages/typed_openapi/README.ua.md
index 7922928..2467b25 100644
--- a/packages/typed_openapi/README.ua.md
+++ b/packages/typed_openapi/README.ua.md
@@ -46,6 +46,33 @@ defaults:
   rules: {dedupe-enum-values: false}
 ```
 
+Те, чого нормалізатор знати не може, виправляє файл override-ів — без змін на
+бекенді. Вкажи його в клієнті (`overrides: typed_openapi.overrides.yaml`) і
+адресуй специфікацію операціями та схемами, а не pointer-ами:
+
+```yaml
+operations:
+  getPet:                     # operationId або METHOD /path: 'GET /pets/{id}'
+    parameters:
+      id: {schema: {type: integer, format: int64}}   # path:id, якщо імена збігаються
+    responses:
+      '200': {contentType: application/json}
+schemas:
+  Pet:
+    reason: бекенд надсилає null для тварин без власника
+    properties:
+      owner: {nullable: true}
+      photo: {type: string, format: binary}
+```
+
+Override-и змінюють специфікацію до нормалізатора; `null` прибирає поле.
+Override, ціль якого зникла, дає warning, той, з яким специфікація вже
+збігається, — info, що його можна прибрати, а ключ з одруком — помилку з
+підказкою найближчого відомого ключа. Поля для генератора (`name`, `exclude`,
+`group`, `exhaustive`, `dartType`, `triState`) уже перевіряються і
+запрацюють разом із генерацією коду. Підказки правил, які не
+можуть виправити дефект самі, закінчуються override-ом, який можна скопіювати.
+
 У кожної знахідки є стабільний код (`TOA011`), JSON-pointer на місце в
 специфікації і, якщо парсер зміг визначити позицію, рядок і колонка. Код
 виходу `1` означає хоча б одну помилку, `64` — неправильні аргументи або
````

Diff `packages/typed_openapi/lib/typed_openapi.dart` (`git apply` з кореня):

```diff
diff --git a/packages/typed_openapi/lib/typed_openapi.dart b/packages/typed_openapi/lib/typed_openapi.dart
index e6f9892..f813174 100644
--- a/packages/typed_openapi/lib/typed_openapi.dart
+++ b/packages/typed_openapi/lib/typed_openapi.dart
@@ -2,8 +2,9 @@
 ///
 /// The programmatic API mirrors the CLI: load a config, check specs, report
 /// diagnostics. [SpecReader] reads a loaded spec into the typed model
-/// ([SpecModel]) with its `$ref`s resolved; [Normalizer] runs the named
-/// rules over it and applies their fixes.
+/// ([SpecModel]) with its `$ref`s resolved; [OverrideLoader] reads a
+/// client's overrides file; [Normalizer] applies its spec fields, runs the
+/// named rules over the spec and applies their fixes.
 library;
 
 export 'src/check/spec_checker.dart' show SpecChecker;
@@ -54,6 +55,18 @@ export 'src/normalize/normalizer.dart' show NormalizedSpec, Normalizer;
 export 'src/normalize/normalizer_rule.dart'
     show Finding, NormalizerRule, RuleContext;
 export 'src/normalize/spec_edit.dart' show EditOperation, SpecEdit;
+export 'src/overrides/override_loader.dart' show OverrideLoader;
+export 'src/overrides/override_set.dart'
+    show
+        BodyOverride,
+        DartTypeOverride,
+        OperationOverride,
+        OverrideEntry,
+        OverrideSet,
+        ParameterOverride,
+        PropertyOverride,
+        ResponseOverride,
+        SchemaOverride;
 export 'src/resolve/spec_documents.dart' show SpecDocuments;
 export 'src/resolve/spec_model.dart' show SpecModel;
 export 'src/resolve/spec_reader.dart' show SpecReader;
```

- [ ] **Step 3: Перевірити**

Run (з `packages/typed_openapi`): `dart test`
Expected: PASS, 381 тестів (`+381: All tests passed!`).

Run (з `packages/typed_openapi`): `dart format lib test bin` двічі
Expected: другий запуск — `0 changed`.

Run (з кореня): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 4: Прогін корпусу**

Запусти `check --format json` на конфігу публічного корпусу (research/08) на `main` і після задачі 5 і порівняй звіти.
Expected: звіти однакові (у корпусі немає override-ів і знахідок TOA203–TOA206/TOA303; на момент планування — 1029 діагностик: 2 error, 853 warning, 174 info).

- [ ] **Step 5: Коміт**

```bash
git add CLAUDE.md packages/typed_openapi/CHANGELOG.md packages/typed_openapi/README.md packages/typed_openapi/README.ua.md packages/typed_openapi/lib/typed_openapi.dart packages/typed_openapi/test/cli/cli_test.dart
git commit -m "docs(typed_openapi): document overrides and export their API" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Перевірити пакет**

Run (з `packages/typed_openapi`, після коміту): `dart pub publish --dry-run`
Expected: `Package has 0 warnings.`
