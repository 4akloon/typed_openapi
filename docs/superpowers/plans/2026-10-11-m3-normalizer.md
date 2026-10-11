# План M3: нормалізатор

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `typed_openapi check` читає YAML власним компоновщиком (теги поза JSON Schema ruleset, нерядкові ключі, глибина й аліаси — за один ітеративний прохід, без квадратичного сканера), каже, де `$ref` стоїть там, де OAS його не дозволяє, і проганяє специфікацію через рушій іменованих правил: однозначні дефекти виправляються правками сирого дерева з перечитуванням моделі, решта — діагностика з порадою, що виправити в джерелі.

**Architecture:** `load/yaml/` — сканер і парсер `package:yaml` 3.1.4 (MIT), скопійовані з двома правками сканера, що прибирають квадратичну вартість довгих flow-рядків. `load/yaml_composer.dart` — `YamlComposer` будує з подій парсера звичайне дерево і позиції за JSON pointer; його використовують `SpecLoader` і `ConfigLoader`, а `YamlEventGuard`, `loadYamlNode` і `_PlainConverter` зникають. Новий шар `normalize/`: `SpecEdit` + `TreeEditor` (правки копіюванням при записі), `NormalizerRule` + `RuleContext` + `Finding`, `Normalizer` (до 3 проходів read → rules → edits; діагностика парсера — лише з останнього проходу). Правила читають типізовану модель M2 і нічого не знають про текст. `SpecChecker` викликає `Normalizer` замість `SpecReader`.

**Tech Stack:** Dart `>=3.10.0 <4.0.0`, чистий Dart; залежності `args`, `io`, `path`, `source_span`, нові прямі `collection` і `string_scanner` (їх уже тягнув `package:yaml`, тепер їх використовує скопійований сканер); `yaml` переходить у `dev_dependencies` (лише для тестів-порівнянь); тести на `package:test`.

**Spec:** [docs/superpowers/specs/2026-10-11-m3-normalizer-design.md](../specs/2026-10-11-m3-normalizer-design.md) — рішення 1–7 і дві таблиці правил. Вимоги: R2.1, R2.5, R0.2 ([requirements.md](../../requirements.md)). Дефекти й рецепти: [research/06 §C, §D](../../research/06-spec-versions-and-defects.md). Корпус і перший прогін: [research/08](../../research/08-test-corpus.md). Місце етапу — [roadmap.md](../../roadmap.md), M3 і «Перенесено з M2». Правила коду — [CLAUDE.md](../../../CLAUDE.md).

## Global Constraints

- SDK `>=3.10.0 <4.0.0`; обидва пакети — чистий Dart. Primary constructors (Dart 3.13) не використовуються.
- Dart 3.10 активно: dot shorthands скрізь, де відомий тип контексту (`.nestingTooDeep`, `severity: .error`, `case .key`), null-aware елементи колекцій, switch-вирази і patterns, records, модифікатори класів (`final`, `sealed`, `base`). У тестах аргументи `expect(...)` — повні імена (`DiagnosticCode.boolRequired`).
- ООП: жодних функцій верхнього рівня, крім `main` у `bin/` і тестах. Компоненти, що звітують, отримують `DiagnosticBag` через конструктор (`YamlComposer(bag)`, `Normalizer(bag)`). Виняток — скопійований код `load/yaml/`: він лишається в стилі `package:yaml` і перевіряється лише `package:lints/recommended.yaml` (свій `analysis_options.yaml` у теці).
- Помилки вхідних даних не кидаються: вони йдуть у `DiagnosticBag`, решта документа читається. Ловиться лише `YamlException` — і, в одному місці (`_Composition._next`), `AssertionError` сканера `package:yaml` (див. «Ухвалені рішення», п. 3).
- Кожен новий код — у `DiagnosticCode` з doc-коментарем, slug у kebab-case, рівень за замовчуванням, файл, JSON pointer і, коли відомо, позиція; повідомлення каже, що виправити в джерелі (R2.2, R2.5).
- Детермінізм (R13.1): правила обходять вузли в порядку `SpecLocation` (`SpecModel.nodes`), правила йдуть у порядку `Normalizer.rules`, звіт сортує `DiagnosticBag.sorted`.
- Правила не змінюють модель і не читають текст: вони повертають `Finding` з `SpecEdit`-ами; застосовує й перечитує лише `Normalizer`. Знання структури OAS — лише в парсері.
- Override-и (M4) у M3 не застосовуються: діагностика лише називає поле і значення, яке варто перевизначити, без синтаксису файлу override-ів.
- Пресет не вмикає й не вимикає правил (рішення 7): він лише додає до `fix` рецепт фреймворку (`NormalizerRule.hint`).
- Фікстури — вигадані й маленькі. Приватна специфікація компанії не використовується ні як фікстура, ні як джерело фікстур. Публічний корпус (research/08) — лише для прогону `check`.
- Лінти з кореневого `analysis_options.yaml`; `dart analyze packages` з кореня — `No issues found!`; `dart format lib test bin` (з `packages/typed_openapi`) — другий запуск змінює 0 файлів.
- Тести не ходять у мережу; тимчасові файли — лише через `test/helpers/temp_dir.dart`. Ворожі входи перевіряються лише щедрим `timeout:`, без вимірювань часу в тестах.
- Команди `dart test`, `dart format` — з `packages/typed_openapi`; `dart pub get`, `dart analyze packages`, `git apply` і `git` — з кореня репозиторію.
- Кожен коміт — Conventional Commits і закінчується рядком `Co-Authored-By` моделі, що виконує задачу (у прикладах — `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`).

## Ухвалені рішення

Рішення специфікації M3 — обов'язкові; тут лише те, що специфікація лишає планові.

1. **Код нерядкового ключа — `TOA014 non-string-key`.** Специфікація пише «TOA00x», але `TOA001`–`TOA009` зайняті (TOA009 — теги), а `TOA010`–`TOA013` — версія документа; TOA014 — перший вільний у діапазоні 0xx.
2. **Скалярні ключі читаються як текст (YAML Failsafe), як вимагає OAS для ключів.** `200:` — це ключ `"200"`, `~:` — `"~"`, `0x1F:` — `"0x1F"`. Нерядковим (TOA014) вважається лише ключ-колекція або аліас колекції; такий запис пропускається, нічого в ньому не будується, тож «бомба в ключі» неможлива. Наявний тест M2 «`200:` читається як `"200"`» і TOA002 для `1`/`"1"` лишаються без змін. Відкрите питання — чи робити ключі-числа і ключі-`null` помилкою, як каже таблиця специфікації (див. кінець плану).
3. **Assert сканера.** Скопійований сканер має `assert(_simpleKeyAllowed || !required)` у `_saveSimpleKey`. Fuzz M2 (300 000 входів, seed 11) ловить його на 86 документах; усі 86 без асертів закінчуються `YamlException`, тобто це невалідний YAML. У зібраному CLI асерти вимкнені; у `dart test` і з `--enable-asserts` компоновщик ловить `AssertionError` рівно навколо `parser.parse()` і повертає його як синтаксичну помилку (TOA001). Інших асертів на шляху немає: `Loader` більше не використовується.
4. **Квадратичний сканер виправлено в копії.** Сканер `package:yaml` витрачає на кожен токен час, пропорційний глибині flow-вкладеності (`_staleSimpleKeys` і `.any` у `_fetchMoreTokens`). Дві правки (upstream: https://github.com/dart-lang/tools/issues/2657) роблять кожен токен O(1) у flow-контексті: файл ~1 MB з «захованими» дужками — з 57 с до часток секунди; обхід «підрахунок дужок перед парсером» з M2 не потрібен. Тести з гілки `fix/yaml-quadratic-scan` (коміт 719bd46, не зливається) перенацілено на компоновщик.
5. **Дублікати ключів — як у M2.** Два ключі, рівні для YAML (`a` і `"a"`), поза `.json` — TOA002 **error**, документ не читається (як `package:yaml`). У `.json` будь-який дублікат і в будь-якому файлі ключі, рівні лише як JSON-ключі (`1` і `"1"`), — TOA002 warning, перемагає останнє значення. Нове: `.json` з дублікатом тепер має позиції (без TOA005).
6. **Запасний `jsonDecode` для `.json` лишається**, хоча прикладу валідного JSON, який відкидає парсер, не знайдено (сурогатні пари, `\/`, таби, ключі > 1024 символів — усе читається).
7. **TOA107 замість TOA110/TOA111.** `$ref` як невідомий ключ об'єкта (операція `get: {$ref: ...}`) і об'єкт-`$ref` там, де очікується рядок або інше значення (`description: {$ref: ...}`, `tags: [{$ref: ...}]`), дають `TOA107 ref-not-allowed` з підказкою про `redocly bundle`. Підстановки «`$ref` будь-де» немає.
8. **TOA108 визначається з тексту біля порожнього значення.** `package:yaml` ставить порожнє блочне значення на `:` ключа, а порожнє flow-значення — на наступний токен (на наступному рядку, коли коментар закрив рядок). `ObjectReader` перевіряє обидва місця; позиції ключів компоновщик не зберігає.
9. **Проходи нормалізатора.** Прохід = read → усі правила. Якщо є правки і прохід не третій — знахідки-виправлення йдуть у звіт, правки застосовуються, документ перечитується. Інакше прохід останній: у звіт ідуть діагностика парсера цього проходу і всі знахідки; правки третього проходу не застосовуються і дають `TOA800 fix-not-applied`. Знахідки лише-діагностики з проміжних проходів не звітуються (вони повторяться в останньому).
10. **Конфлікт правок — `TOA800`.** Правка, що торкається того самого вузла, що й раніше прийнята (той самий pointer або один — нащадок іншого), пропускається з `TOA800`; виграє правило, що раніше в `Normalizer.rules`. Той самий код — для правки, чия ціль зникла, і для файлу, який не читається.
11. **Файли читаються один раз на всі проходи.** Діагностика завантаження (TOA001, TOA002, TOA009 …) інших файлів іде прямо в звіт; документи, завантажені в проході, передаються в наступний (`SpecDocuments(others:)`), відредаговані — з новим деревом (`SpecDocument.withRoot`). Позиції лишаються за pointer.
12. **Конфіг `rules`.** `rules: {<ім'я>: false}` у `defaults` і в клієнті; значення клієнта перекриває `defaults` поіменно. Невідоме ім'я — `TOA903` (warning, з переліком відомих правил), не-булеве значення — `TOA902`. Файл, спільний для кількох клієнтів, перевіряється один раз — з правилами першого клієнта за іменем (як і раніше: один прохід на файл).

## Нові коди діагностики (у задачах 1–6)

| Код | Slug | Рівень | Коли | Research / spec |
|---|---|---|---|---|
| TOA009 | `yaml-tag-unsupported` | error | Тег поза JSON Schema ruleset (`!!timestamp`, `!!binary`, `!!set`, `!custom`) або значення, неможливе для тегу (`!!int abc`) | spec п. 2; research/08 (Artemis) |
| TOA014 | `non-string-key` | error | Ключ — колекція або аліас колекції; запис пропускається | spec п. 6 |
| TOA107 | `ref-not-allowed` | warning | `$ref` там, де OAS не приймає Reference Object | spec; research/08 (DigitalOcean) |
| TOA108 | `ref-commented-out` | warning | `$ref: #/...` без лапок: `#` почав коментар | spec; research/08 (Grace) |
| TOA201 | `bool-required` | warning | `required: true/false` на властивості (виправляється) | C-1, C-49 |
| TOA211 | `invalid-default` | warning | `default` не того типу (ігнорується) | C-28 |
| TOA800 | `fix-not-applied` | warning | Правка правила не застосована: конфлікт, ціль зникла, три проходи | рішення 9–10 |

Змінюється опис `TOA008`: аліас у ключі більше не TOA008 (тепер це TOA014).

## Файли

Шляхи відносно `packages/typed_openapi/`.

| Файл | Відповідальність | Задача |
|---|---|---|
| `lib/src/load/yaml/` (`scanner.dart`, `parser.dart`, `token.dart`, `event.dart`, `style.dart`, `utils.dart`, `error_listener.dart`, `yaml_exception.dart`, `yaml_document.dart`, `LICENSE`, `analysis_options.yaml`) | Скопійовані сканер і парсер `package:yaml` 3.1.4 з виправленням квадратичності | 1 |
| `lib/src/load/yaml_composer.dart` | `YamlComposer`, `ComposedYaml` — дерево і позиції з подій парсера | 1 |
| `lib/src/load/spec_loader.dart` | `parse` на компоновщику | 1 |
| `lib/src/config/config_loader.dart` | YAML через компоновщик; `rules` | 2, 6 |
| `lib/src/load/yaml_event_guard.dart` | видаляється | 2 |
| `lib/src/parse/object_reader.dart` | TOA107, TOA108 | 3 |
| `lib/src/normalize/spec_edit.dart` | `EditOperation`, `SpecEdit`, `TreeEditor` | 4 |
| `lib/src/normalize/normalizer_rule.dart` | `Finding`, `RuleContext`, `NormalizerRule` | 4 |
| `lib/src/normalize/normalizer.dart` | `Normalizer`, `NormalizedSpec` | 4, 5 |
| `lib/src/load/spec_document.dart`, `lib/src/resolve/spec_documents.dart`, `lib/src/resolve/spec_reader.dart`, `lib/src/resolve/spec_model.dart`, `lib/src/model/spec_node.dart` | `withRoot`, `others`/`loaded`, `documents:`, `nodes`, `SpecLocation.child` | 4 |
| `lib/src/normalize/rules/bool_required_to_array.dart`, `lib/src/normalize/rules/drop_invalid_default.dart` | Правила-виправлення | 5 |
| `lib/src/config/project_config.dart`, `lib/src/check/spec_checker.dart` | `disabledRules`; `check` через `Normalizer` | 6 |
| `lib/src/diagnostics/diagnostic_code.dart` | нові коди | 1, 3, 4, 5 |
| `pubspec.yaml` | `collection`, `string_scanner`; `yaml` → dev | 1, 2 |

## Інтерфейси між задачами

```dart
// load (Tasks 1-2)
final class ComposedYaml { Object? root; Map<String, SourceSpan> spans;
  ({String message, SourceSpan span})? syntaxError; }
final class YamlComposer { const YamlComposer(DiagnosticBag);
  static const maxDepth = 1000, minBudget = 16000000, budgetPerChar = 20;
  ComposedYaml? compose(String text, {required String file, required Uri uri, bool json = false}); }
SpecDocument SpecDocument.withRoot(Map<String, Object?> root);                    // Task 4

// model / resolve (Task 4)
SpecLocation SpecLocation.child(Object token);
SpecDocuments(SpecLoader, SpecDocument root, {Iterable<SpecDocument> others = const []});
Iterable<SpecDocument> SpecDocuments.loaded;
SpecModel SpecReader.read(SpecDocument, OpenApiVersion, {SpecDocuments? documents});
List<SpecNode> SpecModel.nodes;                                                    // by location

// normalize (Tasks 4-6)
enum EditOperation { add, replace, remove }
final class SpecEdit { SpecEdit.add(SpecLocation, Object?); SpecEdit.replace(SpecLocation, Object?);
  SpecEdit.remove(SpecLocation); SpecLocation location; EditOperation operation; Object? value;
  bool overlaps(SpecEdit other); }
final class TreeEditor { TreeEditor(Map<String, Object?> root); Map<String, Object?> root;
  String? apply(SpecEdit edit); }                                // null, or why it failed
final class Finding { const Finding(Diagnostic, {List<SpecEdit> edits}); }
final class RuleContext { SpecModel model; SpecDocuments documents; OpenApiVersion version;
  Iterable<T> nodes<T extends SpecNode>(); (Object?,)? rawAt(SpecLocation);
  Finding finding(DiagnosticCode, String message, SpecLocation at, {String? fix, List<SpecEdit> edits}); }
abstract base class NormalizerRule { String name; List<DiagnosticCode> codes;
  Iterable<Finding> check(RuleContext); String? hint(DiagnosticCode, Preset) => null; }
final class Normalizer { Normalizer(DiagnosticBag, {List<NormalizerRule>? rules,
  Set<String> disabled, Preset? preset}); static const maxPasses = 3;
  static final List<NormalizerRule> rules; static Set<String> ruleNames;
  NormalizedSpec normalize(SpecDocument, OpenApiVersion); }
final class NormalizedSpec { SpecModel model; SpecDocuments documents; }
Set<String> ClientConfig.disabledRules;                                           // Task 6
```

Після задачі 6: 282 тести, `dart analyze packages` без зауважень.

---

### Task 1: Свій компоновщик YAML на подіях скопійованого парсера (TOA009, TOA014)

**Files:**
- Create: `packages/typed_openapi/lib/src/load/yaml/` (копія з `package:yaml` 3.1.4 + правки), `packages/typed_openapi/lib/src/load/yaml_composer.dart`, `packages/typed_openapi/test/load/yaml_composer_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_openapi/lib/src/load/spec_loader.dart`, `packages/typed_openapi/test/load/spec_loader_test.dart`, `packages/typed_openapi/pubspec.yaml`

**Interfaces:**
- Consumes: `DiagnosticBag`, `DiagnosticCode`, `JsonPointer`, `Severity`, `SpecDocument` (M1–M2).
- Produces: `YamlComposer`, `ComposedYaml` (див. «Інтерфейси»); `DiagnosticCode.yamlTagUnsupported` (TOA009), `DiagnosticCode.nonStringKey` (TOA014); `SpecLoader.parse` на компоновщику. `ConfigLoader` поки що лишається на `YamlEventGuard` + `loadYamlNode` (задача 2).

Поведінка, яку закріплюють тести:
- Скаляри-значення резолвляться рівно як у `package:yaml` (null/bool/int/float/рядок) — порівняльний тест із `loadYaml`; ключі — текст (Failsafe).
- Тег поза ruleset — TOA009 error, значення читається як текст, решта документа читається; `!!set`/`!!omap` — колекція без тегу; `!custom` розпізнається з тексту (парсер `package:yaml` звітує його як `!`).
- Ключ-колекція або аліас колекції — TOA014, запис пропускається без побудови; «бомба» з якорями всередині ключів нічого не коштує.
- Глибина: кожна колекція, яку відкриває парсер (ключі теж), і кожна, у яку розгортається аліас, — рівень; корінь — 0; > 1000 — TOA007. Бюджет аліасів — як у M2.
- Синтаксичні помилки (зокрема другий документ, невизначений аліас, самопосилання, assert сканера) повертаються в `syntaxError`, не звітуються; `SpecLoader` звітує їх як TOA001.
- Ворожі flow-рядки (дужки, сховані в лапках і коментарях, ~1 MB) — TOA007 майже лінійно; порівняльний fuzz (seed 7, 20 000 документів) — дерево збігається з `loadYamlNode`.

- [ ] **Step 1: Скопіювати сканер і парсер `package:yaml` 3.1.4**

```bash
dart pub get
Y="${PUB_CACHE:-$HOME/.pub-cache}/hosted/pub.dev/yaml-3.1.4"   # yaml 3.1.4 is in the cache: main depends on it
D=packages/typed_openapi/lib/src/load/yaml
mkdir -p "$D"
cp "$Y/LICENSE" "$Y"/lib/src/{scanner,parser,token,event,style,utils,error_listener,yaml_exception,yaml_document}.dart "$D/"
(cd packages/typed_openapi && dart format lib/src/load/yaml)
```

Заголовки файлів (copyright Dart project authors і Kirill Simonov, MIT) і `LICENSE` лишаються без змін.

- [ ] **Step 2: Правки копії**

Створи `packages/typed_openapi/lib/src/load/yaml/analysis_options.yaml`:

```yaml
# The scanner and parser of package:yaml 3.1.4 (MIT, see LICENSE), copied
# so that typed_openapi can fix their cost on long flow lines and read their
# events without an implementation import. Changes are marked
# "typed_openapi:". The code keeps package:yaml's style, so it is checked
# with the recommended lints only.
include: package:lints/recommended.yaml
```

У `yaml_document.dart` лиши лише `VersionDirective` і `TagDirective` (клас `YamlDocument` і імпорти `dart:collection`, `source_span`, `yaml_node.dart` видали). Файл після правки:

```dart
// Copyright (c) 2014, the Dart project authors.
// Copyright (c) 2006, Kirill Simonov.
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

/// A directive indicating which version of YAML a document was written to.
class VersionDirective {
  /// The major version number.
  final int major;

  /// The minor version number.
  final int minor;

  VersionDirective(this.major, this.minor);

  @override
  String toString() => '%YAML $major.$minor';
}

/// A directive describing a custom tag handle.
class TagDirective {
  /// The handle for use in the document.
  final String handle;

  /// The prefix that the handle maps to.
  final String prefix;

  TagDirective(this.handle, this.prefix);

  @override
  String toString() => '%TAG $handle $prefix';
}
```

У `style.dart` видали рядок `import 'yaml_node.dart';` (і порожній рядок після нього) і заміни в doc-коментарі `[YamlScalar.wrap]` на `` `YamlScalar.wrap` ``.

У `scanner.dart` — дві правки (diff відносно відформатованої копії):

```diff
--- a/packages/typed_openapi/lib/src/load/yaml/scanner.dart	2026-10-11 23:24:00
+++ b/packages/typed_openapi/lib/src/load/yaml/scanner.dart	2026-10-11 23:24:23
@@ -331,9 +331,12 @@
         // If the current token could be a simple key, we need to scan more
         // tokens until we determine whether it is or not. Otherwise we might
         // not emit the `KEY` token before we emit the value of the key.
-        if (!_simpleKeys.any(
-          (key) => key != null && key.tokenNumber == _tokensParsed,
-        )) {
+        // typed_openapi (https://github.com/dart-lang/tools/issues/2657):
+        // keys are saved in increasing token order by flow level, so only the
+        // first live key can be the current token; `any` over every level
+        // cost the flow depth for every token.
+        final firstKey = _simpleKeys.firstWhereOrNull((key) => key != null);
+        if (firstKey == null || firstKey.tokenNumber != _tokensParsed) {
           break;
         }
       }
@@ -474,6 +477,10 @@
   /// Checks the list of potential simple keys and remove the positions that
   /// cannot contain simple keys anymore.
   void _staleSimpleKeys() {
+    // typed_openapi (https://github.com/dart-lang/tools/issues/2657): the
+    // check below does not depend on the key, so it ends the loop before it
+    // starts; in flow context the loop cost the flow depth for every token.
+    if (!_inBlockContext) return;
     for (var i = 0; i < _simpleKeys.length; i++) {
       var key = _simpleKeys[i];
       if (key == null) continue;
```

- [ ] **Step 3: Залежності**

У `packages/typed_openapi/pubspec.yaml` заміни блок `dependencies` на:

```yaml
dependencies:
  args: ^2.7.0
  # collection and string_scanner are used by the YAML scanner copied from
  # package:yaml into lib/src/load/yaml.
  collection: ^1.15.0
  io: ^1.1.0
  path: ^1.9.1
  source_span: ^1.10.2
  string_scanner: ^1.2.0
  # Pinned to one minor version: YamlEventGuard reads package:yaml's own parser
  # events (package:yaml/src/parser.dart), which are not public API.
  yaml: ">=3.1.4 <3.2.0"
```

Run: `dart pub get && dart analyze packages` — `No issues found!`.

- [ ] **Step 4: Коди діагностики**

У `lib/src/diagnostics/diagnostic_code.dart` заміни doc-коментар `aliasExpansionTooLarge` і додай TOA009 після нього та TOA014 після `openApiVersionNotString`:

```dart
  /// YAML aliases expand to far more nodes than the text has, or the JSON
  /// pointers of the document's nodes add up to more than the budget.
  aliasExpansionTooLarge('TOA008', 'alias-expansion-too-large', .error),

  /// A YAML tag outside the JSON Schema ruleset OpenAPI requires, such as
  /// `!!timestamp` or `!custom`; the value is read as its text.
  yamlTagUnsupported('TOA009', 'yaml-tag-unsupported', .error),
```

```dart
  /// A mapping key is a collection, or an alias of one, instead of a
  /// string; the entry is ignored.
  nonStringKey('TOA014', 'non-string-key', .error),
```

- [ ] **Step 5: Написати тести компоновщика**

Створи `packages/typed_openapi/test/load/yaml_composer_test.dart`:

```dart
import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/load/yaml_composer.dart';
import 'package:yaml/yaml.dart';

void main() {
  const limit = Timeout(Duration(seconds: 60));

  /// Composes [text] as `api.yaml` (or `api.json` with [json]).
  (ComposedYaml?, DiagnosticBag) compose(String text, {bool json = false}) {
    final bag = DiagnosticBag();
    final result = YamlComposer(bag).compose(
      text,
      file: json ? 'api.json' : 'api.yaml',
      uri: Uri.file('/specs/api.yaml'),
      json: json,
    );
    return (result, bag);
  }

  /// The plain tree of [text]; it must compose without diagnostics.
  Object? plain(String text) {
    final (result, bag) = compose(text);
    expect(bag.all, isEmpty, reason: text);
    expect(result?.syntaxError, isNull, reason: text);
    return result!.root;
  }

  group('scalars', () {
    test('resolve exactly as package:yaml loads them', () {
      const scalars = [
        '',
        '~',
        'null',
        'Null',
        'NULL',
        'nULL',
        'true',
        'True',
        'TRUE',
        'tRUE',
        'false',
        'False',
        'FALSE',
        'yes',
        'no',
        'on',
        'off',
        'y',
        '0',
        '7',
        '-0',
        '+1',
        '-12',
        '012',
        '0o17',
        '0o',
        '0x1F',
        '0xg',
        '-0x10',
        '1_000',
        '1.5',
        '-1.5',
        '+1.5',
        '.5',
        '-.5',
        '+.5',
        '1e3',
        '1E-3',
        '1.',
        '.inf',
        '.Inf',
        '.INF',
        '-.inf',
        '+.inf',
        '.nan',
        '.NaN',
        '.NAN',
        '.',
        '+',
        '2025-07-27',
        '12:30',
        '1.2.3',
        '9223372036854775808',
        'x',
        '"quoted 1"',
        "'single'",
        '"true"',
        "'~'",
        '!!str 12',
        '!!int 12',
        '!!float .5',
        '!!bool true',
        '!!null ~',
        '! 12',
        '!!int 0x1F',
      ];
      for (final scalar in scalars) {
        final expected = (loadYaml('k: $scalar') as YamlMap)['k'];
        final actual = (plain('k: $scalar')! as Map)['k'];
        if (expected is double && expected.isNaN) {
          expect(actual, isA<double>().having((d) => d.isNaN, 'isNaN', true));
          continue;
        }
        expect(actual, expected, reason: scalar);
        expect(actual.runtimeType, expected.runtimeType, reason: scalar);
      }
    });

    test('keys are their text, as the Failsafe schema reads them', () {
      expect(plain('200: a\n~: b\n0x1F: c\n1.0: d\n"q": e\n'), {
        '200': 'a',
        '~': 'b',
        '0x1F': 'c',
        '1.0': 'd',
        'q': 'e',
      });
    });
  });

  group('tags', () {
    for (final (tag, value) in [
      ('!!timestamp', '2025-07-27T07:17:05.500Z'),
      ('!!binary', 'R0lGODlh'),
      ('!custom', 'x'),
      ('!custom', '42'),
    ]) {
      test('$tag is an error and the value is read as its text', () {
        final (result, bag) = compose(
          'a: 1\nexample: $tag \'$value\'\nb: 2\n',
        );
        expect(result!.root, {'a': 1, 'example': value, 'b': 2});
        final d = bag.all.single;
        expect(d.code, DiagnosticCode.yamlTagUnsupported);
        expect(d.severity, Severity.error);
        expect(d.pointer?.value, '#/example');
        expect(d.line, 2);
        expect(d.fix, contains('JSON Schema ruleset'));
      });
    }

    test('!!set and !!omap collections are read without the tag', () {
      final (result, bag) = compose(
        's: !!set {a: null, b: null}\no: !!omap [x: 1]\n',
      );
      expect(result!.root, {
        's': {'a': null, 'b': null},
        'o': [
          {'x': 1},
        ],
      });
      expect(bag.all.map((d) => d.code), [
        DiagnosticCode.yamlTagUnsupported,
        DiagnosticCode.yamlTagUnsupported,
      ]);
      expect(bag.all.first.message, contains('!!set'));
    });

    test('a ruleset tag with a value it cannot have is reported too', () {
      final (result, bag) = compose('a: !!int abc\n');
      expect(result!.root, {'a': 'abc'});
      expect(bag.all.single.message, contains('not a valid !!int'));
    });

    test('a tagged key is checked like a value', () {
      final (result, bag) = compose('!!timestamp 2026-01-01: x\n');
      expect(result!.root, {'2026-01-01': 'x'});
      expect(bag.all.single.pointer?.value, '#');
    });
  });

  group('duplicate keys', () {
    test('keys YAML considers equal are an error, as in YAML', () {
      final (result, bag) = compose('a: 1\n"a": 2\n');
      expect(result, isNull);
      expect(bag.all.single.severity, Severity.error);
      expect(bag.all.single.message, 'Duplicate mapping key.');
    });

    test('in a .json file they are a warning and the last value wins', () {
      final (result, bag) = compose('{"a": 1, "b": 0, "a": 2}', json: true);
      expect(result!.root, {'a': 2, 'b': 0});
      final d = bag.all.single;
      expect(d.severity, Severity.warning);
      expect(d.pointer?.value, '#/a');
      expect(d.column, 18);
    });

    test('keys equal only as JSON keys are a warning, last wins', () {
      final (result, bag) = compose('r:\n  1: a\n  "1": b\n');
      expect(result!.root, {
        'r': {'1': 'b'},
      });
      expect(bag.all.single.message, contains('same key "1" in JSON'));
    });
  });

  group('non-string keys', () {
    const prefix = 'x-a: &a [1, 2]\n';

    // Every key syntax the M2 alias-key guard covered: each makes a
    // collection a key.
    for (final (name, tail) in [
      ('an alias as a block key after ?', '? *a\n: v\n'),
      ('an alias as a block key', '*a : v\n'),
      ('an alias as a flow mapping key', 'x: {*a : v}\n'),
      ('an alias as an entry of a flow mapping', 'x: {a: 1, *a : v}\n'),
      ('an alias as a bare entry of a flow mapping', 'x: {*a, b: 1}\n'),
      ('an alias after ? in a flow mapping', 'x: {? *a : v}\n'),
      ('an alias after ? in a flow sequence', 'x: [? *a : v]\n'),
      ('an alias after a bare ? in a flow sequence', 'x: [? *a]\n'),
      ('a ? key sequence', '? [*a]\n: v\n'),
      ('a ? key block sequence', '? - *a\n: v\n'),
      ('a ? key block sequence at the same column', '?\n- *a\n: v\n'),
      ('a nested ? key', 'x:\n  ?\n  - *a\n  : v\n'),
      ('a flow sequence key', '[*a]: v\n'),
      ('a flow mapping key', '{a: *a}: v\n'),
      ('a flow key of a flow mapping', 'x: {[*a]: v}\n'),
      ('a flow key without a colon', 'x: {[*a]}\n'),
      ('a flow key before a comma', 'x: {[*a], a: 1}\n'),
      ('a flow mapping in a flow mapping', 'x: {{a: *a}}\n'),
      ('a flow key with the colon on the next line', 'x: [ [*a]\n  : v]\n'),
      ('a tagged flow key', '!!seq [*a]: v\n'),
      ('an anchored flow key', '&z [*a]: v\n'),
      ('a flow key in a flow sequence', 'x: [[*a]: v]\n'),
      ('a flow key in a block sequence', 'x:\n  - [*a]: v\n'),
      ('an alias key after a bare dash line', 'x:\n  - a\n  -\n    *a : v\n'),
      ('a key after a : with a # and no blank', 'x:\n  {a:# x, b: *a}: v\n'),
      ('a key after a : with a quote', "x:\n  {true:'x, c: *a}: v\n"),
      ('a key after a ? with a quote', 'x:\n  {?"a : *a}: v\n'),
      ('a key after a " in a flow mapping', 'x:\n  [{a:"b, c: *a}]: 1\n'),
    ]) {
      test('$name is an error and the entry is dropped', () {
        final (result, bag) = compose('$prefix$tail');
        expect(result?.syntaxError, isNull, reason: tail);
        expect(
          bag.all.map((d) => d.code),
          everyElement(DiagnosticCode.nonStringKey),
          reason: tail,
        );
        expect(bag.all, isNotEmpty, reason: tail);
        expect(bag.all.first.span, isNotNull);
      });
    }

    test('a key is never expanded, so a bomb in a key costs nothing', () {
      final text = StringBuffer('l0: &l0 [x, x, x, x, x, x, x, x, x]\n');
      for (var i = 1; i <= 9; i++) {
        text.write('? &l$i [');
        text.write(List.filled(9, '*l${i - 1}').join(', '));
        text.writeln(']\n: v');
      }
      text.writeln('after: 1');
      final (result, bag) = compose('$text');
      expect((result!.root! as Map)['after'], 1);
      expect(bag.all, hasLength(9));
    }, timeout: limit);

    test('an alias of a node inside a dropped key reads as null', () {
      final (result, bag) = compose('? &k [1]\n: v\nx: *k\n');
      expect(result!.root, {'x': null});
      expect(bag.all.map((d) => d.code), [
        DiagnosticCode.nonStringKey,
        DiagnosticCode.nonStringKey,
      ]);
    });

    for (final (name, doc) in [
      ('block values', 'k: *a\n'),
      ('block sequence items', '- *a\n- - *a\n- k: *a\n'),
      ('merge keys', 'k:\n  <<: *a\n  b: 1\n'),
      ('flow sequences', 'k: [*a, *a]\n'),
      ('flow mappings', 'k: {x: *a, y: [*a]}\n'),
      ('a value on its own line', 'k:\n  *a\n'),
      ('a value with a trailing comment', 'k: *a # why\n'),
      ('an explicit key without aliases', '? /pets\n: *a\n'),
      ('an alias of a scalar as a key', 's: &s name\n*s : 1\n'),
      ('quoted keys with a *', '"*a": 1\n\'*b\' : 2\n'),
      ('markdown in plain scalars', 'k: some *bold* text\n  * item\n'),
      ('markdown in block scalars', 'k: |\n  *a : v\n  [*a]\n'),
      ('CRLF', 'k: *a\r\nj: *a\r\n'),
    ]) {
      test('aliases are accepted in $name', () {
        final (result, bag) = compose(
          '${doc.startsWith('-') ? 'x-l: &a [1, 2]\nx-s:\n' : prefix}$doc',
        );
        expect(bag.all, isEmpty, reason: doc);
        expect(result?.syntaxError, isNull, reason: doc);
      });
    }
  });

  group('nesting', () {
    test('every collection the parser opens is a level, keys included', () {
      String nested(int levels) => '${'[' * levels}${']' * levels}';
      expect(compose('a: ${nested(1000)}\n').$2.all, isEmpty);
      expect(
        compose('a: ${nested(1001)}\n').$2.all.single.code,
        DiagnosticCode.nestingTooDeep,
      );
      final (key, bag) = compose('? ${nested(1001)}\n: v\n');
      expect(key, isNull);
      expect(
        bag.all.map((d) => d.code),
        contains(DiagnosticCode.nestingTooDeep),
      );
    }, timeout: limit);

    test('100 000 nested levels are reported, not a stack overflow', () {
      for (final text in [
        '${'[' * 100000}${']' * 100000}',
        '${'- ' * 100000}x',
        '${'{a: ' * 100000}x${'}' * 100000}',
        'x:\n  - a\n  -\n    ${'- ' * 100000}x',
        'x:\n  - a\n  -\n    ${'[' * 100000}',
      ]) {
        final (result, bag) = compose(text);
        expect(result, isNull);
        expect(bag.all.single.code, DiagnosticCode.nestingTooDeep);
      }
    }, timeout: limit);
  });

  group('flow collections that hide their closing brackets', () {
    // The scanner copied from package:yaml spent time proportional to the
    // flow depth on every token; each of these took a minute or more. No
    // assertion measures time: the timeout is the test.
    for (final (name, text) in [
      ('quoted closers after a key', 'x: ${'["]",' * 199000}'),
      ('quoted closers after a key, closed', 'x: ${'["]",' * 160000}]'),
      ('quoted closers at the root', '["]",' * 200000),
      ('quoted closers in braces', '{"}":' * 200000),
      ('single-quoted closers', "x: ${"[']'," * 200000}"),
      ('quoted closers on separate lines', 'x: [\n${'"]",[\n' * 150000}'),
      ('closers in comments', 'x: [\n${'[ #]\n' * 150000}'),
      ('a quoted opening bracket first', 'x: ["[", ${'["]",' * 200000}'),
    ]) {
      test('$name are nesting-too-deep, found in near-linear time', () {
        final (result, bag) = compose(text);
        expect(result, isNull);
        final d = bag.all.single;
        expect(d.code, DiagnosticCode.nestingTooDeep);
        expect(d.span, isNotNull);
      }, timeout: limit);
    }

    test(
      'quoted closers without a comma are a syntax error, found at once',
      () {
        // `["]"["]"...`: the parser rejects the second item before the
        // nesting gets deep.
        final (result, bag) = compose('["]"' * 250000);
        expect(bag.all, isEmpty);
        expect(result!.syntaxError, isNotNull);
      },
      timeout: limit,
    );

    test('the position is the first collection that is too deep', () {
      // `x: ` is 3 characters and each `["]",` starts with its `[`. The
      // root mapping is level 0, so the sequence at index 1000 is level 1001.
      final (_, bag) = compose('x: ${'["]",' * 5000}');
      expect(bag.all.single.span!.start.offset, 3 + 5 * 1000);
    });

    test('many short flow collections are read', () {
      final (result, bag) = compose('x: [${'[1, 2], ' * 60000}0]\n');
      expect(bag.all, isEmpty);
      expect(((result!.root! as Map)['x']! as List).length, 60001);
      expect(compose('{"a": [${'{"k": ["v"]},' * 40000}1]}').$2.all, isEmpty);
      expect(compose('x: ${'["]", ' * 900}${']' * 900}\n').$2.all, isEmpty);
    }, timeout: limit);
  });

  group('syntax errors are returned, not reported', () {
    for (final (name, text, message) in [
      ('an unclosed flow sequence', 'a: [1, 2\nb: {', null),
      ('an undefined alias', 'a: *missing\n', 'Undefined alias.'),
      (
        'a collection that contains its own alias',
        'a: &a [*a]\n',
        'Self-referential collections are not supported.',
      ),
      ('two documents', 'a: 1\n---\nb: 2\n', 'Only expected one document.'),
      (
        'a key alias in a second document',
        'x: &a [1]\n---\n? *a\n: v\n',
        'Only expected one document.',
      ),
      ('a bad indentation', 'a: 1\n a: 2\n  - x\n', null),
    ]) {
      test(name, () {
        final (result, bag) = compose(text);
        expect(bag.all, isEmpty);
        expect(result!.syntaxError, isNotNull);
        if (message != null) {
          expect(result.syntaxError!.message, message);
        }
      });
    }

    test('package:yaml\'s own assert on invalid YAML is a syntax error', () {
      // `Scanner._saveSimpleKey` asserts on this document (asserts are on in
      // tests); with asserts off the parser rejects it.
      final (result, bag) = compose(
        'x-a: &a [1, 2]\nx-z:\n   - ? "\n      , \'s\'] : \n  "!!seq \n'
        '  , *a :  "\n',
      );
      expect(bag.all, isEmpty);
      expect(result!.syntaxError, isNotNull);
    });
  });

  test('the composed tree matches package:yaml on random block and flow '
      'documents (fixed seed)', () {
    final random = Random(7);
    const tokens = [
      'k: ',
      'j: ',
      '- ',
      '[',
      ']',
      '{',
      '}',
      ', ',
      'v',
      '1',
      '"q"',
      "'s'",
      '~',
      'true',
      '2.5',
      '&b ',
      '*a',
      ': ',
      '? ',
      '|',
      '#c',
      ' ',
    ];
    var compared = 0;
    for (var i = 0; i < 20000; i++) {
      final lines = List.generate(1 + random.nextInt(4), (_) {
        final line = StringBuffer(' ' * (2 + random.nextInt(3)));
        for (var t = 1 + random.nextInt(5); t > 0; t--) {
          line.write(tokens[random.nextInt(tokens.length)]);
        }
        return '$line';
      });
      final text = 'x-a: &a [1, 2]\nx-z:\n${lines.join('\n')}\n';
      final YamlNode node;
      try {
        node = loadYamlNode(text);
        // The parser's own assertions fire on some invalid documents.
        // ignore: avoid_catching_errors
      } on AssertionError {
        continue;
      } on YamlException {
        continue;
      }
      final expected = _failsafeKeys(node);
      if (expected == _skip) continue;
      final (result, bag) = compose(text);
      expect(bag.all, isEmpty, reason: text);
      expect(result!.root, expected, reason: text);
      compared++;
    }
    expect(compared, greaterThan(1000));
  }, timeout: limit);
}

const _skip = Object();

/// An anchor or a tag in front of a scalar's text.
final _properties = RegExp(r'^(?:[&!]\S*(?:\s+|$))+');

/// The plain value of [node] with keys as their Failsafe text, or [_skip]
/// when a key is a collection or two keys are one JSON key.
Object? _failsafeKeys(YamlNode node) {
  switch (node) {
    case YamlMap():
      final map = <String, Object?>{};
      for (final MapEntry(:key, value: entry) in node.nodes.entries) {
        final keyNode = key as YamlNode;
        if (keyNode is! YamlScalar) return _skip;
        final value = keyNode.value;
        final name = value is String
            ? value
            : keyNode.span.text.replaceFirst(_properties, '').trim();
        if (map.containsKey(name)) return _skip;
        final converted = _failsafeKeys(entry);
        if (converted == _skip) return _skip;
        map[name] = converted;
      }
      return map;
    case YamlList():
      final list = <Object?>[];
      for (final item in node.nodes) {
        final converted = _failsafeKeys(item);
        if (converted == _skip) return _skip;
        list.add(converted);
      }
      return list;
    default:
      return node.value;
  }
}
```

- [ ] **Step 6: Переконатися, що тести не компілюються**

Run: `dart test test/load/yaml_composer_test.dart`
Expected: FAIL — `yaml_composer.dart` не існує.

- [ ] **Step 7: Компоновщик**

Створи `packages/typed_openapi/lib/src/load/yaml_composer.dart`:

```dart
import 'dart:math';

import 'package:source_span/source_span.dart';

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/json_pointer.dart';
import '../diagnostics/severity.dart';
// The composer reads the events of package:yaml's parser, copied into
// yaml/: the YAML syntax exactly as package:yaml tokenizes it, without the
// recursive loader, which overflows the stack on deep nesting, expands alias
// bombs and hashes collection keys.
import 'yaml/event.dart';
import 'yaml/parser.dart';
import 'yaml/yaml_exception.dart';

/// A JSON or YAML text read into plain values, with the source range of
/// every node by JSON pointer value.
final class ComposedYaml {
  /// Creates a composed document.
  const ComposedYaml({
    required this.root,
    required this.spans,
    this.syntaxError,
  });

  /// The root value: `Map<String, Object?>`, `List<Object?>`, `String`,
  /// `num`, `bool` or `null`. Null when [syntaxError] is set.
  final Object? root;

  /// The source range of every node, by pointer value.
  final Map<String, SourceSpan> spans;

  /// Why the text is not valid YAML, when it is not; nothing was reported
  /// for it, so the caller decides how to.
  final ({String message, SourceSpan span})? syntaxError;
}

/// Builds plain values from YAML (and JSON, which is YAML) text, one parser
/// event at a time.
///
/// The composer replaces package:yaml's loader. It walks the events with an
/// explicit stack, so no input overflows the Dart stack, and checks in the
/// same pass:
///
/// - nesting deeper than [maxDepth] collections (`nesting-too-deep`): every
///   collection the parser opens is a level, keys included, and so is every
///   collection an alias expands to; the root collection is level 0;
/// - aliases that expand to more than the budget (`alias-expansion-too-
///   large`): every node built, read or reached through an alias, costs the
///   length of its JSON pointer plus one, and the budget is
///   `max(`[minBudget]`, `[budgetPerChar]` * text length)`;
/// - keys that are the same JSON key (`duplicate-key`): a warning and the
///   last value wins, except two keys YAML itself considers equal outside a
///   `.json` file, which are an error, as in YAML;
/// - keys that are not strings (`non-string-key`): a collection, or an alias
///   of one, as a key; the entry is dropped and nothing in it is built, so a
///   key cannot hide an alias bomb;
/// - tags outside the YAML JSON Schema ruleset, such as `!!timestamp` or
///   `!custom` (`yaml-tag-unsupported`): the value is read as its text (a
///   collection as plain), so the rest of the file is still checked.
///
/// Scalar keys are read as their text, the YAML Failsafe schema OpenAPI
/// requires for keys: `200:` is the key `"200"`. Scalar values are resolved
/// with the JSON Schema ruleset exactly as package:yaml's loader does.
///
/// A limit or an undefined alias stops the composition: it is reported and
/// [compose] returns null. A syntax error is returned in
/// [ComposedYaml.syntaxError], unreported.
final class YamlComposer {
  /// Creates a composer that reports to [_diagnostics].
  const YamlComposer(this._diagnostics);

  /// The deepest nesting a document may have.
  static const maxDepth = 1000;

  /// The smallest budget, in characters: ordinary specs never come near it.
  static const minBudget = 16000000;

  /// The budget per character of text, once that exceeds [minBudget].
  static const budgetPerChar = 20;

  final DiagnosticBag _diagnostics;

  /// Composes [text]; [file] names it in diagnostics and [uri] in spans.
  ///
  /// With [json], every duplicate key is a warning (JSON keeps the last
  /// value); otherwise two keys YAML considers equal are an error.
  ComposedYaml? compose(
    String text, {
    required String file,
    required Uri uri,
    bool json = false,
  }) => _Composition(_diagnostics, text, file, uri, json: json).run();
}

/// One run of [YamlComposer].
final class _Composition {
  _Composition(
    this._diagnostics,
    this._text,
    this._file,
    this._uri, {
    required bool json,
  }) : _json = json,
       _budget = max(
         YamlComposer.minBudget,
         YamlComposer.budgetPerChar * _text.length,
       ),
       _mayHaveAliases = _text.contains('*');

  static const _yamlTags = 'tag:yaml.org,2002:';

  final DiagnosticBag _diagnostics;
  final String _text;
  final String _file;
  final Uri _uri;
  final bool _json;
  final bool _mayHaveAliases;
  int _budget;

  final Map<String, SourceSpan> _spans = {};
  final List<_Frame> _stack = [];
  final Map<String, _Anchor> _anchors = {};

  /// Span records of the nodes inside anchored collections being built, so
  /// that an alias can repeat them under its own pointer.
  final List<_Record> _records = [];
  int _openAnchors = 0;

  /// How many collections are open, skipped ones included: the level a
  /// collection that starts now has.
  int _open = 0;

  /// How deep inside a skipped collection the composer is; 0 when not.
  int _skipped = 0;

  Object? _root;
  bool _failed = false;
  ({String message, SourceSpan span})? _syntaxError;
  SourceSpan? _lastSpan;

  ComposedYaml? run() {
    final parser = Parser(_text, sourceUrl: _uri);
    var documents = 0;
    while (!_failed && _syntaxError == null) {
      final event = _next(parser);
      if (event == null) break;
      switch (event) {
        case DocumentStartEvent():
          if (++documents > 1) {
            _syntaxError = (
              message: 'Only expected one document.',
              span: event.span,
            );
          }
        case ScalarEvent():
          _scalar(event);
        case AliasEvent():
          _alias(event);
        case SequenceStartEvent():
          _start(
            event,
            _tagOf(event.tag, event.span),
            event.anchor,
            isMapping: false,
          );
        case MappingStartEvent():
          _start(
            event,
            _tagOf(event.tag, event.span),
            event.anchor,
            isMapping: true,
          );
        case Event(type: .sequenceEnd || .mappingEnd):
          _end(event);
        case Event(type: .streamEnd):
          return ComposedYaml(root: _root, spans: _spans);
        default:
      }
    }
    if (_failed) return null;
    return ComposedYaml(root: null, spans: _spans, syntaxError: _syntaxError);
  }

  /// The next parser event, or null after recording a syntax error.
  Event? _next(Parser parser) {
    try {
      final event = parser.parse();
      _lastSpan = event.span;
      return event;
    } on YamlException catch (e) {
      _syntaxError = (message: e.message, span: e.span ?? _here());
      return null;
      // package:yaml's scanner asserts an invariant that some invalid
      // documents break (`assert(_simpleKeyAllowed || !required)` in
      // `Scanner._saveSimpleKey`). Asserts are off in the shipped CLI, where
      // the same documents end in a YamlException; with asserts on (tests,
      // `dart --enable-asserts`) the assert is that syntax error.
      // ignore: avoid_catching_errors
    } on AssertionError {
      _syntaxError = (
        message: 'The document is not valid YAML.',
        span: _here(),
      );
      return null;
    }
  }

  SourceSpan _here() =>
      _lastSpan ?? SourceFile.fromString(_text, url: _uri).span(0, 0);

  // --- nodes ---------------------------------------------------------------

  void _scalar(ScalarEvent event) {
    if (_skipped > 0) {
      _skipAnchor(event.anchor);
      return;
    }
    final frame = _stack.isEmpty ? null : _stack.last;
    if (frame != null && frame.state == .skipValue) {
      _skipAnchor(event.anchor);
      frame.state = .key;
      return;
    }
    final isKey = frame != null && frame.state == .key;
    final pointer = isKey ? frame.pointer : _childPointer(frame);
    final value = _resolve(event, pointer);
    if (isKey) {
      _key(frame, event.value, value, event.span);
      if (event.anchor case final name?) {
        _anchors[name] = _Anchor.scalar(value, event.value, event.span);
      }
      return;
    }
    if (!_charge(pointer, event.span)) return;
    _spans[pointer.value] = event.span;
    if (_openAnchors > 0) _records.add(_Record(pointer.value, event.span, -1));
    if (event.anchor case final name?) {
      _anchors[name] = _Anchor.scalar(value, event.value, event.span);
    }
    _attach(frame, value);
  }

  void _alias(AliasEvent event) {
    if (_skipped > 0) return;
    final frame = _stack.isEmpty ? null : _stack.last;
    if (frame != null && frame.state == .skipValue) {
      frame.state = .key;
      return;
    }
    final anchor = _anchors[event.name];
    if (anchor == null) {
      _syntaxError = (message: 'Undefined alias.', span: event.span);
      return;
    }
    if (anchor.open) {
      _syntaxError = (
        message: 'Self-referential collections are not supported.',
        span: event.span,
      );
      return;
    }
    if (frame != null && frame.state == .key) {
      if (anchor.text case final text? when !anchor.skipped) {
        _key(frame, text, anchor.value, event.span);
      } else {
        _nonStringKey(frame, event.span);
        frame.state = .skipValue;
      }
      return;
    }
    final pointer = _childPointer(frame);
    if (anchor.skipped) {
      _diagnostics.report(
        .nonStringKey,
        'This alias refers to a node inside a mapping key that is not a '
        'string; it is read as null.',
        file: _file,
        pointer: pointer,
        span: event.span,
        fix: 'Anchor the node outside the key.',
      );
      _attach(frame, null);
      return;
    }
    if (!_expand(anchor, pointer, event.span)) return;
    _attach(frame, anchor.value);
  }

  void _start(
    Event event,
    String? tag,
    String? anchor, {
    required bool isMapping,
  }) {
    final level = _open++;
    if (level > YamlComposer.maxDepth) {
      _fail(
        .nestingTooDeep,
        'The document nests deeper than ${YamlComposer.maxDepth} levels.',
        null,
        event.span,
      );
      return;
    }
    if (_skipped > 0) {
      _skipped++;
      _skipAnchor(anchor);
      return;
    }
    final frame = _stack.isEmpty ? null : _stack.last;
    if (frame != null && frame.state != .value) {
      if (frame.state == .key) {
        _nonStringKey(frame, event.span);
        frame.state = .skippedKey;
      } else {
        frame.state = .skippedValue;
      }
      _skipped = 1;
      _skipAnchor(anchor);
      return;
    }
    final pointer = _childPointer(frame);
    if (!_charge(pointer, event.span)) return;
    _checkTag(
      tag,
      isMapping ? '${_yamlTags}map' : '${_yamlTags}seq',
      pointer,
      event.span,
      isMapping ? 'mapping' : 'list',
    );
    final record = _Record(pointer.value, event.span, level);
    _Anchor? anchored;
    if (anchor != null) {
      anchored = _anchors[anchor] = _Anchor.collection(
        _records.length,
        pointer.value,
        level,
      );
      _openAnchors++;
    }
    if (_openAnchors > 0) _records.add(record);
    _stack.add(
      _Frame(
        pointer,
        isMapping ? <String, Object?>{} : <Object?>[],
        event.span,
        record,
        anchored,
      ),
    );
  }

  void _end(Event event) {
    _open--;
    if (_skipped > 0) {
      if (--_skipped > 0) return;
      final frame = _stack.last;
      frame.state = frame.state == .skippedKey ? .skipValue : .key;
      return;
    }
    final frame = _stack.removeLast();
    final span = frame.start.expand(event.span);
    frame.record.span = span;
    _spans[frame.pointer.value] = span;
    if (frame.anchor case final anchor?) {
      anchor
        ..value = frame.value
        ..end = _records.length
        ..open = false;
      _openAnchors--;
    }
    _attach(_stack.isEmpty ? null : _stack.last, frame.value);
  }

  // --- maps ----------------------------------------------------------------

  void _key(_Frame frame, String text, Object? value, SourceSpan span) {
    final earlier = frame.keys[text];
    frame.keys[text] = (value: value, span: span);
    frame.key = text;
    frame.state = .value;
    if (earlier == null) return;
    final yamlEqual = earlier.value == value;
    if (yamlEqual && !_json) {
      _fail(
        .duplicateKey,
        'Duplicate mapping key.',
        frame.pointer.child(text),
        span,
        severity: .error,
      );
      return;
    }
    _diagnostics.report(
      .duplicateKey,
      yamlEqual
          ? 'Duplicate mapping key. The last value is used.'
          : 'Keys ${earlier.span.text} and ${span.text} are the same key '
                '"$text" in JSON; the last value is used.',
      file: _file,
      pointer: frame.pointer.child(text),
      span: span,
      fix: 'Remove one of the keys.',
    );
  }

  void _nonStringKey(_Frame frame, SourceSpan span) {
    _diagnostics.report(
      .nonStringKey,
      'A mapping key must be a string, not a collection; the entry is '
      'ignored.',
      file: _file,
      pointer: frame.pointer,
      span: span,
      fix: 'Write the key as a plain or quoted string.',
    );
  }

  // --- values --------------------------------------------------------------

  JsonPointer _childPointer(_Frame? frame) => switch (frame) {
    null => .root,
    _Frame(value: final List<Object?> list) => frame.pointer.child(list.length),
    _ => frame.pointer.child(frame.key!),
  };

  void _attach(_Frame? frame, Object? value) {
    if (frame == null) {
      _root = value;
      return;
    }
    switch (frame.value) {
      case final List<Object?> list:
        list.add(value);
      case final Map<String, Object?> map:
        map[frame.key!] = value;
        frame.state = .key;
    }
  }

  /// Repeats the records of [anchor] under [pointer], charging each one;
  /// false after reporting a limit.
  bool _expand(_Anchor anchor, JsonPointer pointer, SourceSpan span) {
    if (anchor.end < 0) {
      if (!_charge(pointer, span)) return false;
      _spans[pointer.value] = anchor.span!;
      if (_openAnchors > 0) {
        _records.add(_Record(pointer.value, anchor.span!, -1));
      }
      return true;
    }
    final level = _open;
    for (var i = anchor.first; i < anchor.end; i++) {
      final record = _records[i];
      final at = pointer.value + record.pointer.substring(anchor.base.length);
      final atLevel = record.level < 0
          ? -1
          : level + record.level - anchor.level;
      if (atLevel > YamlComposer.maxDepth) {
        _fail(
          .nestingTooDeep,
          'The document nests deeper than ${YamlComposer.maxDepth} levels, '
          'counting what its aliases expand to.',
          JsonPointer.parse(at),
          record.span!,
        );
        return false;
      }
      if (!_charge(JsonPointer.parse(at), record.span!)) return false;
      _spans[at] = record.span!;
      if (_openAnchors > 0) _records.add(_Record(at, record.span, atLevel));
    }
    return true;
  }

  bool _charge(JsonPointer pointer, SourceSpan span) {
    _budget -= pointer.value.length + 1;
    if (_budget >= 0) return true;
    _fail(
      .aliasExpansionTooLarge,
      _mayHaveAliases
          ? 'YAML aliases expand to far more nodes than the text has; the '
                'document is not read.'
          : 'The JSON pointers of the document\'s nodes add up to more than '
                'the supported size, because of very long keys or very deep '
                'nesting; the document is not read.',
      pointer,
      span,
      fix: _mayHaveAliases
          ? 'Remove the nested aliases.'
          : 'Shorten the longest keys.',
    );
    return false;
  }

  void _skipAnchor(String? name) {
    if (name != null) _anchors[name] = _Anchor.skipped();
  }

  void _fail(
    DiagnosticCode code,
    String message,
    JsonPointer? pointer,
    SourceSpan span, {
    String? fix,
    Severity? severity,
  }) {
    _failed = true;
    _diagnostics.report(
      code,
      message,
      severity: severity,
      file: _file,
      pointer: pointer,
      span: span,
      fix: fix,
    );
  }

  // --- scalars and tags ----------------------------------------------------

  /// The value of [event] as package:yaml's loader resolves it, with tags
  /// outside the JSON Schema ruleset reported and read as text.
  Object? _resolve(ScalarEvent event, JsonPointer pointer) {
    final tag = _tagOf(event.tag, event.span);
    if (tag == null) return _plain(event.value);
    if (tag == '!' || tag == '${_yamlTags}str') return event.value;
    final value = switch (tag) {
      '${_yamlTags}null' => _null(event.value),
      '${_yamlTags}bool' => _bool(event.value),
      '${_yamlTags}int' => _number(event.value, allowFloat: false),
      '${_yamlTags}float' => _number(event.value, allowInt: false),
      _ => null,
    };
    if (value != null) return value.$1;
    final known =
        tag.startsWith(_yamlTags) &&
        const {'null', 'bool', 'int', 'float'}.contains(
          tag.substring(_yamlTags.length),
        );
    _diagnostics.report(
      .yamlTagUnsupported,
      known
          ? '"${event.value}" is not a valid ${_tagName(tag)} value; it is '
                'read as a string.'
          : 'The YAML tag ${_tagName(tag)} is not in the JSON Schema ruleset '
                'OpenAPI requires; the value is read as the string '
                '"${event.value}".',
      file: _file,
      pointer: pointer,
      span: event.span,
      fix: _tagFix,
    );
    return event.value;
  }

  void _checkTag(
    String? tag,
    String allowed,
    JsonPointer pointer,
    SourceSpan span,
    String kind,
  ) {
    if (tag == null || tag == '!' || tag == allowed) return;
    _diagnostics.report(
      .yamlTagUnsupported,
      'The YAML tag ${_tagName(tag)} is not in the JSON Schema ruleset '
      'OpenAPI requires; the $kind is read without it.',
      file: _file,
      pointer: pointer,
      span: span,
      fix: _tagFix,
    );
  }

  static const _tagFix =
      'Remove the tag, or quote the value. OpenAPI YAML may only use the '
      'tags of the JSON Schema ruleset: !!str, !!int, !!float, !!bool, '
      '!!null, !!seq and !!map.';

  /// A tag property such as `!custom`, after an optional anchor.
  static final _localTag = RegExp(r'^(?:&\S+\s+)?(![^\s!]\S*)');

  /// The tag of a node whose parser event has [tag] and [span].
  ///
  /// package:yaml's parser reports a local tag such as `!custom` as the
  /// non-specific tag `!`, the tag of every quoted scalar; the source text
  /// tells them apart.
  static String? _tagOf(String? tag, SourceSpan span) {
    if (tag != '!') return tag;
    return _localTag.firstMatch(span.text)?.group(1) ?? tag;
  }

  static String _tagName(String tag) => tag.startsWith(_yamlTags)
      ? '!!${tag.substring(_yamlTags.length)}'
      : tag.startsWith('!')
      ? tag
      : '!<$tag>';

  /// A plain scalar resolved as package:yaml's loader does: null, bool,
  /// int, float, else the string.
  static Object? _plain(String text) {
    if (text.isEmpty) return null;
    final resolved = switch (text.codeUnitAt(0)) {
      0x2E || 0x2B || 0x2D => _number(text),
      0x6E || 0x4E => text.length == 4 ? _null(text) : null,
      0x74 || 0x54 => text.length == 4 ? _bool(text) : null,
      0x66 || 0x46 => text.length == 5 ? _bool(text) : null,
      0x7E => text.length == 1 ? (null,) : null,
      final c when c >= 0x30 && c <= 0x39 => _number(text),
      _ => null,
    };
    return resolved == null ? text : resolved.$1;
  }

  static (Object?,)? _null(String text) => switch (text) {
    '' || 'null' || 'Null' || 'NULL' || '~' => (null,),
    _ => null,
  };

  static (Object?,)? _bool(String text) => switch (text) {
    'true' || 'True' || 'TRUE' => (true,),
    'false' || 'False' || 'FALSE' => (false,),
    _ => null,
  };

  static (Object?,)? _number(
    String text, {
    bool allowInt = true,
    bool allowFloat = true,
  }) {
    final value = _numberValue(
      text,
      allowInt: allowInt,
      allowFloat: allowFloat,
    );
    return value == null ? null : (value,);
  }

  static num? _numberValue(
    String text, {
    required bool allowInt,
    required bool allowFloat,
  }) {
    if (text.isEmpty) return null;
    final first = text.codeUnitAt(0);
    if (allowInt && text.length == 1) {
      final digit = first - 0x30;
      return digit >= 0 && digit <= 9 ? digit : null;
    }
    if (text.length == 1) return null;
    final second = text.codeUnitAt(1);
    bool isDigit(int c) => c >= 0x30 && c <= 0x39;
    if (allowInt && first == 0x30) {
      if (second == 0x78) return int.tryParse(text);
      if (second == 0x6F) return int.tryParse(text.substring(2), radix: 8);
    }
    if (isDigit(first) ||
        ((first == 0x2B || first == 0x2D) && isDigit(second))) {
      num? result;
      if (allowInt) result = int.tryParse(text, radix: 10);
      if (allowFloat) result ??= double.tryParse(text);
      return result;
    }
    if (!allowFloat) return null;
    if ((first == 0x2E && isDigit(second)) ||
        ((first == 0x2D || first == 0x2B) && second == 0x2E)) {
      if (text.length == 5) {
        switch (text) {
          case '+.inf' || '+.Inf' || '+.INF':
            return double.infinity;
          case '-.inf' || '-.Inf' || '-.INF':
            return -double.infinity;
        }
      }
      return double.tryParse(text);
    }
    if (text.length == 4 && first == 0x2E) {
      switch (text) {
        case '.inf' || '.Inf' || '.INF':
          return double.infinity;
        case '.nan' || '.NaN' || '.NAN':
          return double.nan;
      }
    }
    return null;
  }
}

/// What a mapping frame expects next.
enum _State {
  /// A key.
  key,

  /// The value of [_Frame.key].
  value,

  /// A value to skip, because its key was not a string.
  skipValue,

  /// The rest of a key collection that is being skipped.
  skippedKey,

  /// The rest of a value collection that is being skipped.
  skippedValue,
}

/// A collection being built.
final class _Frame {
  _Frame(this.pointer, this.value, this.start, this.record, this.anchor)
    : state = value is List<Object?> ? .value : .key;

  final JsonPointer pointer;

  /// The `Map<String, Object?>` or `List<Object?>` being filled.
  final Object value;

  /// The span of the start event.
  final FileSpan start;

  /// The span record of the collection.
  final _Record record;

  /// The anchor defined on the collection, if any.
  final _Anchor? anchor;

  /// The keys read so far, with their YAML values and spans.
  final Map<String, ({Object? value, SourceSpan span})> keys = {};

  /// The key whose value comes next.
  String? key;

  /// What comes next; always [_State.value] in a list.
  _State state;
}

/// The span of one node, kept while an anchored collection is open.
final class _Record {
  _Record(this.pointer, this.span, this.level);

  final String pointer;

  /// Set when the node is complete.
  SourceSpan? span;

  /// The level of a collection; -1 for a scalar.
  final int level;
}

/// What an anchor names.
final class _Anchor {
  _Anchor.scalar(this.value, this.text, this.span)
    : skipped = false,
      first = -1,
      end = -1,
      base = '',
      level = -1,
      open = false;

  _Anchor.collection(this.first, this.base, this.level)
    : skipped = false,
      text = null,
      span = null,
      end = -1,
      open = true;

  _Anchor.skipped()
    : skipped = true,
      value = null,
      text = null,
      span = null,
      first = -1,
      end = -1,
      base = '',
      level = -1,
      open = false;

  /// Whether the anchored node is inside a skipped key or value.
  final bool skipped;

  Object? value;

  /// The text of a scalar.
  final String? text;

  /// The span of a scalar.
  final SourceSpan? span;

  /// The records of a collection: from [first] to [end] (exclusive).
  final int first;
  int end;

  /// The pointer value of the anchored collection.
  final String base;

  /// The level of the anchored collection.
  final int level;

  /// Whether the anchored collection is still being built.
  bool open;
}
```

- [ ] **Step 8: `SpecLoader.parse` на компоновщику і тести завантажувача**

Застосуй (з кореня, `git apply`):

```diff
diff --git a/packages/typed_openapi/lib/src/load/spec_loader.dart b/packages/typed_openapi/lib/src/load/spec_loader.dart
--- a/packages/typed_openapi/lib/src/load/spec_loader.dart
+++ b/packages/typed_openapi/lib/src/load/spec_loader.dart
@@ -1,16 +1,13 @@
 import 'dart:convert';
 import 'dart:io';
-import 'dart:math';
 
 import 'package:path/path.dart' as p;
 import 'package:source_span/source_span.dart';
-import 'package:yaml/yaml.dart';
 
 import '../diagnostics/diagnostic_bag.dart';
-import '../diagnostics/diagnostic_code.dart';
 import '../diagnostics/json_pointer.dart';
 import 'spec_document.dart';
-import 'yaml_event_guard.dart';
+import 'yaml_composer.dart';
 
 /// Reads spec files (JSON or YAML) into [SpecDocument]s.
 ///
@@ -66,71 +63,42 @@ final class SpecLoader {
   ///
   /// [uri] is the absolute location of the text, the base for relative
   /// `$ref`s; it defaults to [file] resolved against the current directory.
-  /// JSON and YAML go through the same YAML parser, so both get positions.
-  /// A JSON file the YAML parser rejects (for example, because of a
-  /// duplicate key) is read again with `jsonDecode`, without positions.
+  /// JSON and YAML go through the same [YamlComposer], so both get
+  /// positions. A `.json` file the YAML parser rejects is read again with
+  /// `jsonDecode`, without positions.
   SpecDocument? parse(String text, String file, {Uri? uri}) {
     final location = uri ?? p.toUri(p.normalize(p.absolute(file)));
-    final found = const YamlEventGuard().check(text);
-    if (found != null) {
-      final span = SourceFile.fromString(
-        text,
-        url: location,
-      ).span(found.offset, found.offset + 1);
-      switch (found.problem) {
-        case .tooDeep:
-          _diagnostics.report(
-            .nestingTooDeep,
-            'The document nests deeper than ${YamlEventGuard.maxDepth} '
-            'levels.',
-            file: file,
-            span: span,
-          );
-        case .aliasInKey:
-          _diagnostics.report(
-            .aliasExpansionTooLarge,
-            'A YAML alias is used in a mapping key. OpenAPI keys are '
-            'strings, and an alias there can expand without bound, so the '
-            'document is not read.',
-            file: file,
-            span: span,
-            fix: 'Write the key out instead of aliasing it.',
-          );
-      }
+    final json = p.extension(file).toLowerCase() == '.json';
+    final composed = YamlComposer(
+      _diagnostics,
+    ).compose(text, file: file, uri: location, json: json);
+    if (composed == null) return null;
+    if (composed.syntaxError case final error?) {
+      if (json) return _parseJsonFallback(text, file, location, error);
+      _diagnostics.report(
+        .parseError,
+        error.message,
+        file: file,
+        span: error.span,
+      );
       return null;
     }
-    final YamlNode node;
-    try {
-      node = loadYamlNode(text, sourceUrl: Uri.file(file));
-    } on YamlException catch (e) {
-      return _parseJsonFallback(text, file, location, e);
-    }
-    if (node is! YamlMap) {
+    final root = composed.root;
+    if (root is! Map<String, Object?>) {
       _diagnostics.report(
         .rootNotObject,
         'The document root must be an object.',
         file: file,
         pointer: .root,
-        span: node.span,
+        span: composed.spans[JsonPointer.root.value],
       );
       return null;
     }
-    final converter = _PlainConverter(
-      _diagnostics,
-      file,
-      max(
-        _PlainConverter.minBudget,
-        _PlainConverter.budgetPerChar * text.length,
-      ),
-      mayHaveAliases: text.contains('*'),
-    );
-    final root = converter.convert(node, .root, 0);
-    if (converter.failed) return null;
     return SpecDocument(
       file: file,
       uri: location,
-      root: root! as Map<String, Object?>,
-      spans: converter.spans,
+      root: root,
+      spans: composed.spans,
     );
   }
 
@@ -138,59 +106,20 @@ final class SpecLoader {
     String text,
     String file,
     Uri uri,
-    YamlException error,
+    ({String message, SourceSpan span}) error,
   ) {
-    final duplicate = error.message.startsWith('Duplicate mapping key');
-    if (p.extension(file).toLowerCase() != '.json') {
-      _diagnostics.report(
-        duplicate ? .duplicateKey : .parseError,
-        error.message,
-        severity: .error,
-        file: file,
-        span: error.span,
-      );
-      return null;
-    }
     final Object? root;
     try {
       root = jsonDecode(text);
-    } on FormatException catch (e) {
-      if (!duplicate) {
-        _diagnostics.report(
-          .parseError,
-          error.message,
-          file: file,
-          span: error.span,
-        );
-        return null;
-      }
+    } on FormatException {
       _diagnostics.report(
-        .duplicateKey,
+        .parseError,
         error.message,
         file: file,
         span: error.span,
-        fix: 'Remove the duplicate key from the spec.',
-      );
-      final offset = e.offset;
-      _diagnostics.report(
-        .parseError,
-        e.message,
-        file: file,
-        span: offset == null
-            ? null
-            : SourceFile.fromString(text, url: uri).span(offset, offset),
       );
       return null;
     }
-    if (duplicate) {
-      _diagnostics.report(
-        .duplicateKey,
-        '${error.message} The last value is used.',
-        file: file,
-        span: error.span,
-        fix: 'Remove the duplicate key from the spec.',
-      );
-    }
     if (root is! Map<String, Object?>) {
       _diagnostics.report(
         .rootNotObject,
@@ -209,137 +138,3 @@ final class SpecLoader {
     return SpecDocument(file: file, uri: uri, root: root, spans: const {});
   }
 }
-
-/// Turns a YAML node tree into plain values and records the span of every
-/// node.
-///
-/// YAML aliases make the tree a graph that shares nodes, so walking it as a
-/// tree can take far more steps, and go far deeper, than the text suggests.
-/// The `YamlEventGuard` runs before aliases are expanded and cannot see that, so the conversion
-/// enforces both limits itself: it stops at the first node deeper than
-/// [YamlEventGuard.maxDepth] (`nesting-too-deep`) and once the nodes it has
-/// converted have cost more than its budget (`alias-expansion-too-large`).
-/// Either is reported once, at that node, and sets [failed].
-///
-/// Every converted node, whether read for the first time or reached again
-/// through an alias, costs the length of its JSON pointer plus one. The
-/// pointer string is what a node keeps in [spans], so the sum of the costs
-/// is the memory the conversion holds and the time it spends. Ordinary
-/// specs cost a few times their text length, far below the budget; aliases
-/// of a deep node or of a node under a long key add up quickly.
-final class _PlainConverter {
-  _PlainConverter(
-    this._diagnostics,
-    this._file,
-    this._budget, {
-    required this.mayHaveAliases,
-  });
-
-  /// The smallest budget, in characters: ordinary specs never come near it.
-  static const minBudget = 16000000;
-
-  /// The budget per character of text, once that exceeds [minBudget].
-  static const budgetPerChar = 20;
-
-  final DiagnosticBag _diagnostics;
-  final String _file;
-  int _budget;
-
-  /// Whether the text may contain aliases, which decides how a depth error
-  /// is worded.
-  final bool mayHaveAliases;
-
-  /// The source range of every converted node, by pointer value.
-  final Map<String, SourceSpan> spans = {};
-
-  /// Whether a limit was hit; the converted value is then incomplete.
-  bool failed = false;
-
-  /// Converts [node], which is at [pointer], [depth] collections deep (the
-  /// root is 0, as for the `YamlEventGuard`).
-  Object? convert(YamlNode node, JsonPointer pointer, int depth) {
-    if (failed) return null;
-    _budget -= pointer.value.length + 1;
-    if (_budget < 0) {
-      _fail(
-        .aliasExpansionTooLarge,
-        mayHaveAliases
-            ? 'YAML aliases expand to far more nodes than the text has; the '
-                  'document is not read.'
-            : 'The JSON pointers of the document\'s nodes add up to more than '
-                  'the supported size, because of very long keys or very '
-                  'deep nesting; the document is not read.',
-        node,
-        pointer,
-        fix: mayHaveAliases
-            ? 'Remove the nested aliases.'
-            : 'Shorten the longest keys.',
-      );
-      return null;
-    }
-    final isCollection = node is YamlMap || node is YamlList;
-    if (isCollection && depth > YamlEventGuard.maxDepth) {
-      _fail(
-        .nestingTooDeep,
-        'The document nests deeper than ${YamlEventGuard.maxDepth} levels'
-        '${mayHaveAliases ? ', counting what its aliases expand to' : ''}.',
-        node,
-        pointer,
-      );
-      return null;
-    }
-    spans[pointer.value] = node.span;
-    switch (node) {
-      case YamlMap():
-        final map = <String, Object?>{};
-        final keys = <String, YamlNode>{};
-        for (final MapEntry(:key, :value) in node.nodes.entries) {
-          if (failed) return null;
-          final keyNode = key as YamlNode;
-          final name = '${keyNode.value}';
-          final earlier = keys[name];
-          if (earlier != null) {
-            _diagnostics.report(
-              .duplicateKey,
-              'Keys ${earlier.span.text} and ${keyNode.span.text} are the '
-              'same key "$name" in JSON; the last value is used.',
-              file: _file,
-              pointer: pointer.child(name),
-              span: keyNode.span,
-              fix: 'Remove one of the keys.',
-            );
-          }
-          keys[name] = keyNode;
-          map[name] = convert(value, pointer.child(name), depth + 1);
-        }
-        return map;
-      case YamlList():
-        final list = <Object?>[];
-        for (var i = 0; i < node.nodes.length; i++) {
-          if (failed) return null;
-          list.add(convert(node.nodes[i], pointer.child(i), depth + 1));
-        }
-        return list;
-      default:
-        return node.value;
-    }
-  }
-
-  void _fail(
-    DiagnosticCode code,
-    String message,
-    YamlNode node,
-    JsonPointer pointer, {
-    String? fix,
-  }) {
-    failed = true;
-    _diagnostics.report(
-      code,
-      message,
-      file: _file,
-      pointer: pointer,
-      span: node.span,
-      fix: fix,
-    );
-  }
-}
```

```diff
diff --git a/packages/typed_openapi/test/load/spec_loader_test.dart b/packages/typed_openapi/test/load/spec_loader_test.dart
--- a/packages/typed_openapi/test/load/spec_loader_test.dart
+++ b/packages/typed_openapi/test/load/spec_loader_test.dart
@@ -7,7 +7,7 @@ import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
 import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
 import 'package:typed_openapi/src/diagnostics/severity.dart';
 import 'package:typed_openapi/src/load/spec_loader.dart';
-import 'package:typed_openapi/src/load/yaml_event_guard.dart';
+import 'package:typed_openapi/src/load/yaml_composer.dart';
 
 import '../helpers/temp_dir.dart';
 
@@ -59,14 +59,24 @@ void main() {
         'api.json',
       )!;
       expect(doc.root['info'], {'title': 'b'});
-      expect(doc.hasPositions, isFalse);
-      expect(bag.all.map((d) => d.code), [
-        DiagnosticCode.duplicateKey,
-        DiagnosticCode.positionsUnavailable,
-      ]);
+      expect(doc.hasPositions, isTrue);
+      final d = bag.all.single;
+      expect(d.code, DiagnosticCode.duplicateKey);
+      expect(d.pointer?.value, '#/info');
       expect(bag.hasErrors, isFalse);
     });
 
+    test('a YAML tag outside the JSON Schema ruleset is an error, and the '
+        'rest of the document is read', () {
+      final bag = DiagnosticBag();
+      final doc = SpecLoader(bag).parse(
+        'openapi: 3.0.3\nx-when: !!timestamp 2025-07-27T07:17:05Z\n',
+        'api.yaml',
+      )!;
+      expect(doc.root['x-when'], '2025-07-27T07:17:05Z');
+      expect(bag.all.single.code, DiagnosticCode.yamlTagUnsupported);
+    });
+
     test('a duplicate key in YAML is an error', () {
       final bag = DiagnosticBag();
       final doc = SpecLoader(bag).parse(
@@ -78,6 +88,46 @@ void main() {
       expect(bag.all.single.severity, Severity.error);
     });
 
+    test('a second YAML document is a parse error, as in package:yaml', () {
+      final bag = DiagnosticBag();
+      expect(
+        SpecLoader(
+          bag,
+        ).parse('openapi: 3.1.0\n---\nopenapi: 3.0.0\n', 'a.yaml'),
+        isNull,
+      );
+      final d = bag.all.single;
+      expect(d.code, DiagnosticCode.parseError);
+      expect(d.span, isNotNull);
+    });
+
+    group('long flow lines', () {
+      const limit = Timeout(Duration(seconds: 30));
+
+      for (final (name, text) in [
+        ('quoted closers', 'openapi: 3.1.0\nx-a: ${'["]",' * 199000}'),
+        ('quoted closers in a JSON-style object', '{"a": ${'["]",' * 199000}'),
+      ]) {
+        test('$name are TOA007 at a position', () {
+          final bag = DiagnosticBag();
+          expect(SpecLoader(bag).parse(text, 'api.yaml'), isNull);
+          final d = bag.all.single;
+          expect(d.code, DiagnosticCode.nestingTooDeep);
+          expect(d.span, isNotNull);
+        }, timeout: limit);
+      }
+
+      test('a spec with many short flow collections is read', () {
+        final bag = DiagnosticBag();
+        final doc = SpecLoader(bag).parse(
+          'openapi: 3.1.0\nx-pairs: [${'[1, 2], ' * 40000}0]\n',
+          'api.yaml',
+        )!;
+        expect(bag.all, isEmpty);
+        expect((doc.root['x-pairs']! as List<Object?>).length, 40001);
+      }, timeout: limit);
+    });
+
     test('a root that is not an object is an error', () {
       final bag = DiagnosticBag();
       expect(SpecLoader(bag).parse('- a\n- b\n', 'a.yaml'), isNull);
@@ -90,7 +140,7 @@ void main() {
       expect(SpecLoader(bag).parse(text, 'api.json'), isNull);
       final d = bag.all.single;
       expect(d.code, DiagnosticCode.nestingTooDeep);
-      expect(d.column, 7 + YamlEventGuard.maxDepth);
+      expect(d.column, 7 + YamlComposer.maxDepth);
     });
 
     test('YAML nested deeper than the limit is an error too', () {
@@ -127,12 +177,11 @@ void main() {
           'not a stack overflow', () {
         final bag = DiagnosticBag();
         final text = deepAlias();
-        expect(const YamlEventGuard().check(text), isNull);
         expect(SpecLoader(bag).parse(text, 'api.yaml'), isNull);
         final d = bag.all.single;
         expect(d.code, DiagnosticCode.nestingTooDeep);
         expect(d.message, contains('alias'));
-        expect(d.pointer!.tokens, hasLength(YamlEventGuard.maxDepth + 1));
+        expect(d.pointer!.tokens, hasLength(YamlComposer.maxDepth + 1));
         expect(d.pointer!.tokens.take(2), ['x-use', '0']);
         expect(d.span, isNotNull);
       }, timeout: limit);
@@ -181,7 +230,7 @@ void main() {
         final bag = DiagnosticBag();
         final doc = SpecLoader(bag).parse(
           'openapi: 3.1.0\nx-deep: '
-              '${'[' * YamlEventGuard.maxDepth}${']' * YamlEventGuard.maxDepth}\n',
+              '${'[' * YamlComposer.maxDepth}${']' * YamlComposer.maxDepth}\n',
           'api.yaml',
         );
         expect(doc, isNotNull);
@@ -192,8 +241,8 @@ void main() {
         final bag = DiagnosticBag();
         final doc = SpecLoader(bag).parse(
           'openapi: 3.1.0\nx-deep: '
-              '${'[' * (YamlEventGuard.maxDepth + 1)}'
-              '${']' * (YamlEventGuard.maxDepth + 1)}\n',
+              '${'[' * (YamlComposer.maxDepth + 1)}'
+              '${']' * (YamlComposer.maxDepth + 1)}\n',
           'api.yaml',
         );
         expect(doc, isNull);
@@ -209,14 +258,14 @@ void main() {
               '{"openapi": "3.1.0", "x": ${'[' * levels}${']' * levels}}';
           final bag = DiagnosticBag();
           expect(
-            SpecLoader(bag).parse(doc(YamlEventGuard.maxDepth), 'a.$extension'),
+            SpecLoader(bag).parse(doc(YamlComposer.maxDepth), 'a.$extension'),
             isNotNull,
           );
           expect(bag.all, isEmpty);
           expect(
             SpecLoader(
               bag,
-            ).parse(doc(YamlEventGuard.maxDepth + 1), 'a.$extension'),
+            ).parse(doc(YamlComposer.maxDepth + 1), 'a.$extension'),
             isNull,
           );
           expect(bag.all.single.code, DiagnosticCode.nestingTooDeep);
@@ -301,65 +350,22 @@ x-two: *base
         return '$text';
       }
 
-      test('the bomb itself passes the guard and is bounded by the budget', () {
+      test('the bomb itself is bounded by the budget', () {
         final bag = DiagnosticBag();
-        expect(const YamlEventGuard().check(bomb('x-k: 1')), isNull);
         expect(SpecLoader(bag).parse(bomb('x-k: 1'), 'api.yaml'), isNull);
-        expect(bag.all.single.message, isNot(contains('mapping key')));
+        expect(bag.all.single.code, DiagnosticCode.aliasExpansionTooLarge);
       }, timeout: limit);
 
-      // Every key syntax of the re-reviews: package:yaml parses each as a key
-      // that contains an alias, and the guard must see it before loading.
-      for (final (name, tail) in [
-        ('after a ? marker', '? *l7\n: v'),
-        ('inside a ? key sequence', '? [*l7]\n: v'),
-        ('inside a ? key block sequence', '? - *l7\n: v'),
-        ('inside a ? key block sequence at the same column', '?\n- *l7\n: v'),
-        ('inside a nested ? key', 'x-k:\n  ?\n  - *l7\n  : v'),
-        ('before a colon', '*l7 : v'),
-        ('in a flow mapping', 'x-k: {*l7 : v}'),
-        ('as an entry of a flow mapping', 'x-k: {a: 1, *l7 : v}'),
-        ('as a bare entry of a flow mapping', 'x-k: {*l7, a: 1}'),
-        ('after a ? inside a flow mapping', 'x-k: {? *l7 : v}'),
-        ('after a ? inside a flow sequence', 'x-k: [? *l7 : v]'),
-        ('inside a flow sequence key', '[*l7]: v'),
-        ('inside a flow mapping key', '{a: *l7}: v'),
-        ('inside a flow key of a flow mapping', 'x-k: {[*l7]: v}'),
-        ('inside a tagged flow sequence key', '!!seq [*l7]: v'),
-        ('inside an anchored flow sequence key', '&z [*l7]: v'),
-        ('inside a flow key in a block sequence', 'x-k:\n  - [*l7]: v'),
-        ('inside a flow key without a colon', 'x-k: {[*l7]}'),
-        ('inside a flow key on its own line', 'x-k:\n  {\n   [*l7]\n  }'),
-        ('inside a flow key before a comma', 'x-k: {[*l7], a: 1}'),
-        ('inside a flow mapping in a flow mapping', 'x-k: {{a: *l7}}'),
-        ('inside a flow key, colon on the next line', 'x-k: [ [*l7]\n  : v]'),
-        ('after a bare dash line', 'x-k:\n  - a\n  -\n    *l7 : v'),
-        (
-          'in a flow mapping after a bare dash line',
-          'x-k:\n  - a\n  -\n    {*l7 : v}',
-        ),
-        ('after a : and a # without a blank', 'x-k:\n  {a:# x, b: *l7}: v'),
-        ('in a flow key after a : and a #', 'x-k:\n  [{a:# x, b: *l7}]: v'),
-        ('in a flow sequence after a : and a #', 'x-k:\n  [a:#, *l7]: v'),
-        (
-          'after a : and a quote without a blank',
-          "x-k:\n  {true:'x, c: *l7}: v",
-        ),
-        ('after a ? and a quote without a blank', 'x-k:\n  {?"a : *l7}: v'),
-        ('after a nested ? and a quote', 'x-k:\n  {x: {?"a : *l7}}: v'),
-        ('after a ? and a # without a blank', 'x-k:\n  {?#a : {v: *l7}}: 1'),
-        ('after a " in a flow mapping', 'x-k:\n  [{a:"b, c: *l7}]: 1'),
-        ('after an indented ---', 'x-k:\n --- "q:\n    j: 1\n    ? *l7'),
-      ]) {
-        test('an alias $name is reported before it is expanded', () {
-          final bag = DiagnosticBag();
-          expect(SpecLoader(bag).parse(bomb(tail), 'api.yaml'), isNull);
-          final d = bag.all.single;
-          expect(d.code, DiagnosticCode.aliasExpansionTooLarge);
-          expect(d.message, contains('mapping key'));
-          expect(d.span, isNotNull);
-        }, timeout: limit);
-      }
+      test('an alias of a collection as a key is an error, and the rest '
+          'of the document is read', () {
+        final bag = DiagnosticBag();
+        final doc = SpecLoader(bag).parse(
+          'openapi: 3.1.0\nx-a: &a [1, 2]\n? *a\n: v\nx-b: 1\n',
+          'api.yaml',
+        )!;
+        expect(doc.root.keys, ['openapi', 'x-a', 'x-b']);
+        expect(bag.all.single.code, DiagnosticCode.nonStringKey);
+      }, timeout: limit);
 
       test('aliases everywhere except in keys are accepted', () {
         final bag = DiagnosticBag();
```

Змінені очікування тестів: дублікат у `.json` тепер має позиції й не дає TOA005; група «alias keys» більше не чекає TOA008 «mapping key» для ключів (це TOA014, тести — у `yaml_composer_test.dart`), а лише перевіряє, що бомба обмежена бюджетом. `yaml_event_guard_test.dart` поки лишається (його видаляє задача 2 разом із `YamlEventGuard`).

- [ ] **Step 9: Перевірити**

Run (`dart analyze` — з кореня, решта — з `packages/typed_openapi`):

```bash
dart analyze packages                 # No issues found!
dart test                             # All tests passed!
dart format lib test bin && dart format lib test bin   # the second run: 0 changed
```

- [ ] **Step 10: Заміряти Stripe до і після**

```bash
C=<path to the research/08 corpus>/typed_openapi.yaml
git worktree add ../m3-before main
(cd ../m3-before && dart pub get >/dev/null && cd packages/typed_openapi && time dart run bin/typed_openapi.dart check -c "$C" stripe)
(cd packages/typed_openapi && time dart run bin/typed_openapi.dart check -c "$C" stripe)
git worktree remove ../m3-before
```

Expected: `check stripe` після задачі не повільніший, ніж на `main`. Під час написання плану `SpecLoader.parse` на `spec3.json` (Stripe) займав ~650 мс на `main` і ~355 мс з компоновщиком; OpenAI (`openapi.yaml`) — ~270 мс і ~155 мс.

- [ ] **Step 11: Коміт**

```bash
git add packages/typed_openapi
git commit -m "feat(typed_openapi): compose YAML from parser events in one iterative pass

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `ConfigLoader` на компоновщику, без `YamlEventGuard`

**Files:**
- Modify: `packages/typed_openapi/lib/src/config/config_loader.dart` (повна заміна), `packages/typed_openapi/test/config/config_loader_test.dart`, `packages/typed_openapi/test/resolve/spec_reader_test.dart`, `packages/typed_openapi/pubspec.yaml`
- Delete: `packages/typed_openapi/lib/src/load/yaml_event_guard.dart`, `packages/typed_openapi/test/load/yaml_event_guard_test.dart`, `packages/typed_openapi/test/load/yaml_event_guard_fuzz_test.dart`

**Interfaces:**
- Consumes: `YamlComposer`, `ComposedYaml` (задача 1).
- Produces: `ConfigLoader` читає звичайне дерево; кожна проблема самого YAML (TOA001/2/7/8/9/14) звітується як `TOA902` з рівнем компоновщика, тим самим pointer і позицією. Імпортів `package:yaml` у `lib/` не лишається.

Тести guard-а, що ще мають сенс, уже перенесено в `yaml_composer_test.dart` (задача 1): синтаксис ключів-аліасів, глибина, 100 000 рівнів, кілька документів, ворожі flow-рядки. Fuzz guard-а порівнював guard із деревом `loadYamlNode`; його замінює порівняльний fuzz компоновщика.

- [ ] **Step 1: Тести конфігу**

```diff
diff --git a/packages/typed_openapi/test/config/config_loader_test.dart b/packages/typed_openapi/test/config/config_loader_test.dart
--- a/packages/typed_openapi/test/config/config_loader_test.dart
+++ b/packages/typed_openapi/test/config/config_loader_test.dart
@@ -88,31 +88,31 @@ clients:
     expect(bag.all.single.message, contains('nests deeper'));
   });
 
-  for (final (name, key) in [
-    ('an explicit ? key', 'x-key:\n  ? *l7\n  : v'),
-    ('a flow sequence key', '[*l7]: v'),
-    ('a flow mapping key', '{a: *l7}: v'),
-    ('a flow mapping key without a colon', 'x-key: {[*l7]}'),
-    ('a ? key inside a flow mapping', 'x-key: {? *l7 : v}'),
-    ('a key after a bare dash line', 'x-key:\n  - a\n  -\n    *l7 : v'),
-  ]) {
-    test('rejects $name with an alias before expanding it', () {
-      final text = StringBuffer('x-l0: &l0 [x, x, x, x, x, x, x, x, x]\n');
-      for (var i = 1; i <= 7; i++) {
-        text.writeln('x-l$i: &l$i');
-        for (var n = 0; n < 9; n++) {
-          text.writeln('  - *l${i - 1}');
-        }
-      }
-      text.writeln(key);
-      text.writeln('clients:\n  api: {input: a.json, output: lib/api}');
-      final path = TempDir().write('typed_openapi.yaml', '$text');
-      final bag = DiagnosticBag();
-      expect(ConfigLoader(bag).load(path), isNull);
-      expect(bag.all.single.code, DiagnosticCode.configInvalid);
-      expect(bag.all.single.message, contains('mapping key'));
-    }, timeout: const Timeout(Duration(seconds: 30)));
-  }
+  test('rejects a collection as a key without expanding it', () {
+    final path = TempDir().write('typed_openapi.yaml', '''
+x-list: &l [a, b]
+? *l
+: v
+clients:
+  api: {input: a.json, output: lib/api}
+''');
+    final bag = DiagnosticBag();
+    expect(ConfigLoader(bag).load(path)!.clients, hasLength(1));
+    final codes = bag.all.map((d) => d.code).toList();
+    expect(codes, contains(DiagnosticCode.configInvalid));
+    expect(
+      bag.all.firstWhere((d) => d.code == DiagnosticCode.configInvalid).message,
+      contains('mapping key'),
+    );
+  });
+
+  test('reports a syntax error with its position', () {
+    final path = TempDir().write('c.yaml', 'clients: [a, b\n');
+    final bag = DiagnosticBag();
+    expect(ConfigLoader(bag).load(path), isNull);
+    expect(bag.all.single.code, DiagnosticCode.configInvalid);
+    expect(bag.all.single.span, isNotNull);
+  });
 
   test('accepts an alias in a value', () {
     final path = TempDir().write('typed_openapi.yaml', '''
```

```diff
diff --git a/packages/typed_openapi/test/resolve/spec_reader_test.dart b/packages/typed_openapi/test/resolve/spec_reader_test.dart
--- a/packages/typed_openapi/test/resolve/spec_reader_test.dart
+++ b/packages/typed_openapi/test/resolve/spec_reader_test.dart
@@ -3,7 +3,7 @@ import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
 import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
 import 'package:typed_openapi/src/load/openapi_version.dart';
 import 'package:typed_openapi/src/load/spec_loader.dart';
-import 'package:typed_openapi/src/load/yaml_event_guard.dart';
+import 'package:typed_openapi/src/load/yaml_composer.dart';
 import 'package:typed_openapi/src/model/schema.dart';
 import 'package:typed_openapi/src/resolve/spec_reader.dart';
 
@@ -51,7 +51,7 @@ components:
 
   test('a schema nested as deep as the loader allows is read', () {
     final bag = DiagnosticBag();
-    const depth = YamlEventGuard.maxDepth - 4;
+    const depth = YamlComposer.maxDepth - 4;
     final schema = '${'{"items": ' * depth}{"type": "string"}${'}' * depth}';
     final document = SpecLoader(bag).parse(
       '{"openapi": "3.1.0", "info": {"title": "t", "version": "1"}, '
```

Run: `dart test test/config` — Expected: FAIL (`rejects a collection as a key without expanding it`: старий guard відкидає весь конфіг).

- [ ] **Step 2: `ConfigLoader` на компоновщику**

Заміни `packages/typed_openapi/lib/src/config/config_loader.dart`:

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/json_pointer.dart';
import '../load/yaml_composer.dart';
import 'project_config.dart';

/// Reads `typed_openapi.yaml` into a [ProjectConfig].
///
/// Problems go to the [DiagnosticBag] given to the constructor instead of
/// being thrown.
final class ConfigLoader {
  /// Creates a loader that reports to [_diagnostics].
  const ConfigLoader(this._diagnostics);

  static const _topLevelKeys = {'defaults', 'clients'};
  static const _defaultsKeys = {'preset', 'line_width'};
  static const _clientKeys = {
    'input',
    'output',
    'preset',
    'overrides',
    'baseline',
    'line_width',
  };

  final DiagnosticBag _diagnostics;

  /// Reads the config file at [path].
  ///
  /// Relative paths inside it are resolved against its directory. Returns
  /// null when the file is missing or unusable; otherwise returns every
  /// client that is valid.
  ProjectConfig? load(String path) {
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
    } on FileSystemException catch (e) {
      _diagnostics.report(
        .configInvalid,
        'Cannot read $path: ${e.message}.',
        file: path,
      );
      return null;
    }
    final composed = _compose(text, path);
    if (composed == null) return null;
    final reader = _ConfigReader(path, _diagnostics, composed.spans);
    final root = composed.root;
    if (root is! Map<String, Object?>) {
      reader.invalid('The config must be a mapping.', .root);
      return null;
    }
    reader.checkKeys(root, _topLevelKeys, .root);

    final defaultsPointer = JsonPointer.root.child('defaults');
    final defaults = reader.mapAt(root, 'defaults', .root);
    Preset? defaultPreset;
    int? defaultWidth;
    if (defaults != null) {
      reader.checkKeys(defaults, _defaultsKeys, defaultsPointer);
      defaultPreset = reader.presetAt(defaults, defaultsPointer);
      defaultWidth = reader.intAt(defaults, 'line_width', defaultsPointer);
    }

    final clientsPointer = JsonPointer.root.child('clients');
    final clientNodes = reader.mapAt(root, 'clients', .root, required: true);
    if (clientNodes == null) return null;
    if (clientNodes.isEmpty) {
      reader.invalid('"clients" is empty.', clientsPointer);
      return null;
    }

    final baseDir = p.dirname(p.absolute(path));
    String resolve(String value) => p.normalize(p.join(baseDir, value));

    final clients = <ClientConfig>[];
    final declared = <String>{};
    final outputSpans = <String, SourceSpan?>{};
    for (final MapEntry(key: name, :value) in clientNodes.entries) {
      declared.add(name);
      final pointer = clientsPointer.child(name);
      if (value is! Map<String, Object?>) {
        reader.invalid('Client "$name" must be a mapping.', pointer);
        continue;
      }
      reader.checkKeys(value, _clientKeys, pointer);
      final input = reader.stringAt(value, 'input', pointer, required: true);
      final output = reader.stringAt(value, 'output', pointer, required: true);
      final preset = reader.presetAt(value, pointer) ?? defaultPreset;
      final lineWidth =
          reader.intAt(value, 'line_width', pointer) ??
          defaultWidth ??
          ClientConfig.defaultLineWidth;
      final overrides = reader.stringAt(value, 'overrides', pointer);
      final baseline = reader.stringAt(value, 'baseline', pointer);
      if (input == null || output == null) continue;
      outputSpans[name] = reader.spanAt(pointer.child('output'));
      clients.add(
        ClientConfig(
          name: name,
          input: resolve(input),
          output: resolve(output),
          lineWidth: lineWidth,
          preset: preset,
          overrides: overrides == null ? null : resolve(overrides),
          baseline: baseline == null ? null : resolve(baseline),
        ),
      );
    }
    clients.sort((a, b) => a.name.compareTo(b.name));
    _checkOutputOverlap(clients, outputSpans, path);
    return ProjectConfig(
      file: path,
      clients: clients,
      declaredClients: declared,
    );
  }

  /// Reads [text] into plain values; null after reporting why it cannot be
  /// used. Every problem of the YAML itself is a config error.
  ComposedYaml? _compose(String text, String path) {
    final yaml = DiagnosticBag();
    final composed = YamlComposer(
      yaml,
    ).compose(text, file: path, uri: p.toUri(p.absolute(path)));
    for (final d in yaml.all) {
      _diagnostics.report(
        .configInvalid,
        d.message,
        severity: d.severity,
        file: path,
        pointer: d.pointer,
        span: d.span,
        fix: d.fix,
      );
    }
    if (composed?.syntaxError case final error?) {
      _diagnostics.report(
        .configInvalid,
        error.message,
        file: path,
        span: error.span,
      );
      return null;
    }
    return composed;
  }

  void _checkOutputOverlap(
    List<ClientConfig> clients,
    Map<String, SourceSpan?> outputSpans,
    String file,
  ) {
    for (var i = 0; i < clients.length; i++) {
      for (var j = i + 1; j < clients.length; j++) {
        final a = clients[i];
        final b = clients[j];
        final overlap =
            p.equals(a.output, b.output) ||
            p.isWithin(a.output, b.output) ||
            p.isWithin(b.output, a.output);
        if (!overlap) continue;
        _diagnostics.report(
          .outputOverlap,
          'Clients "${a.name}" and "${b.name}" write to overlapping '
          'directories.',
          file: file,
          pointer: JsonPointer.root
              .child('clients')
              .child(b.name)
              .child('output'),
          span: outputSpans[b.name],
          fix: 'Give each client its own output directory.',
        );
      }
    }
  }
}

/// Typed access to the values of a config document that reports bad ones.
class _ConfigReader {
  _ConfigReader(this.file, this.diagnostics, this.spans);

  final String file;
  final DiagnosticBag diagnostics;
  final Map<String, SourceSpan> spans;

  SourceSpan? spanAt(JsonPointer at) => spans[at.value];

  void checkKeys(
    Map<String, Object?> map,
    Set<String> allowed,
    JsonPointer at,
  ) {
    for (final name in map.keys) {
      if (allowed.contains(name)) continue;
      diagnostics.report(
        .configUnknownKey,
        'Unknown key "$name".',
        file: file,
        pointer: at.child(name),
        span: spanAt(at.child(name)),
        fix: 'Allowed keys here: ${(allowed.toList()..sort()).join(', ')}.',
      );
    }
  }

  Map<String, Object?>? mapAt(
    Map<String, Object?> parent,
    String key,
    JsonPointer at, {
    bool required = false,
  }) {
    if (!parent.containsKey(key)) {
      if (required) invalid('Missing required key "$key".', at);
      return null;
    }
    final value = parent[key];
    if (value is Map<String, Object?>) return value;
    invalid('"$key" must be a mapping.', at.child(key));
    return null;
  }

  String? stringAt(
    Map<String, Object?> parent,
    String key,
    JsonPointer at, {
    bool required = false,
  }) {
    if (!parent.containsKey(key)) {
      if (required) invalid('Missing required key "$key".', at);
      return null;
    }
    final value = parent[key];
    if (value is String && value.isNotEmpty) return value;
    invalid('"$key" must be a non-empty string.', at.child(key));
    return null;
  }

  int? intAt(Map<String, Object?> parent, String key, JsonPointer at) {
    if (!parent.containsKey(key)) return null;
    final value = parent[key];
    if (value is int && value > 0) return value;
    invalid('"$key" must be a positive integer.', at.child(key));
    return null;
  }

  Preset? presetAt(Map<String, Object?> parent, JsonPointer at) {
    final name = stringAt(parent, 'preset', at);
    if (name == null) return null;
    final preset = Preset.values.asNameMap()[name];
    if (preset != null) return preset;
    final known = Preset.values.map((v) => v.name).toList()..sort();
    invalid(
      'Unknown preset "$name". Known presets: ${known.join(', ')}.',
      at.child('preset'),
    );
    return null;
  }

  void invalid(String message, JsonPointer at) {
    diagnostics.report(
      .configInvalid,
      message,
      file: file,
      pointer: at,
      span: spanAt(at),
    );
  }
}
```

- [ ] **Step 3: Прибрати guard і перенести `yaml` у dev**

```bash
git rm packages/typed_openapi/lib/src/load/yaml_event_guard.dart \
  packages/typed_openapi/test/load/yaml_event_guard_test.dart \
  packages/typed_openapi/test/load/yaml_event_guard_fuzz_test.dart
```

У `pubspec.yaml` видали з `dependencies` рядок `yaml` і коментар над ним, а `dev_dependencies` зроби такими:

```yaml
dev_dependencies:
  test: ^1.24.0
  # Tests compare the composer with package:yaml's loader.
  yaml: ^3.1.4
```

Run: `grep -rn "import 'package:yaml" packages/typed_openapi/lib` — Expected: нічого.

- [ ] **Step 4: Перевірити**

Run (`dart analyze` — з кореня, решта — з `packages/typed_openapi`):

```bash
dart analyze packages                 # No issues found!
dart test                             # All tests passed!
dart format lib test bin && dart format lib test bin   # the second run: 0 changed
```

- [ ] **Step 5: Коміт**

```bash
git add packages/typed_openapi
git commit -m "refactor(typed_openapi): read the config with the YAML composer

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `$ref` там, де OAS його не дозволяє (TOA107, TOA108)

**Files:**
- Create: `packages/typed_openapi/test/parse/ref_placement_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_openapi/lib/src/parse/object_reader.dart`

**Interfaces:**
- Consumes: `ObjectReader`, `ParseContext.document.spanOf` (M2), позиції компоновщика (задача 1).
- Produces: `DiagnosticCode.refNotAllowed` (TOA107), `DiagnosticCode.refCommentedOut` (TOA108).

- [ ] **Step 1: Коди**

Після `refBaseIgnored` у `diagnostic_code.dart`:

```dart
  /// A `$ref` where OpenAPI does not accept a Reference Object, as bundlers
  /// such as Redocly allow; it is ignored.
  refNotAllowed('TOA107', 'ref-not-allowed', .warning),

  /// `$ref: #/...` without quotes in YAML: `#` starts a comment, so the
  /// value is null.
  refCommentedOut('TOA108', 'ref-commented-out', .warning),
```

- [ ] **Step 2: Тест, що не проходить**

Створи `packages/typed_openapi/test/parse/ref_placement_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/resolve/spec_reader.dart';

void main() {
  /// The diagnostics of reading [yaml] as a 3.1 document.
  List<Diagnostic> read(String yaml) {
    final bag = DiagnosticBag();
    final document = SpecLoader(bag).parse(yaml, 'api.yaml')!;
    SpecReader(bag).read(document, .v31);
    return bag.sorted;
  }

  group(r'a $ref where OpenAPI does not accept one', () {
    test('as an operation is ref-not-allowed, not unknown-key', () {
      final found = read(r'''
openapi: 3.1.0
info: {title: Shop, version: "1"}
paths:
  /orders:
    get:
      $ref: resources/orders/list.yml
''');
      final d = found.single;
      expect(d.code, DiagnosticCode.refNotAllowed);
      expect(d.pointer?.value, r'#/paths/~1orders/get/$ref');
      expect(d.fix, contains('redocly bundle'));
    });

    test('instead of a string is ref-not-allowed, not invalid-value', () {
      final found = read(r'''
openapi: 3.1.0
info:
  title: Shop
  version: "1"
  description: {$ref: description.yml#/introduction}
paths:
  /orders:
    get:
      tags: [{$ref: tags.yml#/orders}]
''');
      expect(found.map((d) => (d.code, d.pointer?.value)), [
        (DiagnosticCode.refNotAllowed, '#/info/description'),
        (DiagnosticCode.refNotAllowed, '#/paths/~1orders/get/tags/0'),
      ]);
      expect(found.first.message, contains('expects a string here'));
    });

    test('a Reference Object where one is allowed is not reported', () {
      final found = read(r'''
openapi: 3.1.0
info: {title: Shop, version: "1"}
paths:
  /orders:
    get:
      responses:
        "200": {$ref: "#/components/responses/Ok"}
components:
  responses:
    Ok: {description: ok}
''');
      expect(found, isEmpty);
    });
  });

  group(r'an unquoted $ref: #/...', () {
    test('reads as a comment and gets a hint to quote it', () {
      final found = read(r'''
openapi: 3.1.0
info: {title: Shop, version: "1"}
components:
  schemas:
    Order:
      type: object
      properties:
        kind:
          $ref: #/components/schemas/Kind
    Kind: {type: string}
''');
      final d = found.single;
      expect(d.code, DiagnosticCode.refCommentedOut);
      expect(
        d.pointer?.value,
        r'#/components/schemas/Order/properties/kind/$ref',
      );
      expect(d.fix, contains("'#/components/schemas/Pet'"));
    });

    test('in a Reference Object as well', () {
      final found = read(r'''
openapi: 3.1.0
info: {title: Shop, version: "1"}
paths:
  /orders:
    get:
      responses:
        "200":
          $ref:   # /components/responses/Ok
''');
      expect(found.single.code, DiagnosticCode.refCommentedOut);
    });

    test('in a flow mapping, where the comment ends the line', () {
      final found = read(r'''
openapi: 3.1.0
info: {title: Shop, version: "1"}
components:
  schemas:
    Order: {$ref: #/components/schemas/Base
      }
''');
      expect(found.single.code, DiagnosticCode.refCommentedOut);
    });

    test(r'an empty $ref without a comment stays invalid-value', () {
      final found = read(r'''
openapi: 3.1.0
info: {title: Shop, version: "1"}
components:
  schemas:
    Order:
      $ref:
''');
      expect(found.single.code, DiagnosticCode.invalidValue);
    });
  });
}
```

Run: `dart test test/parse/ref_placement_test.dart` — Expected: FAIL (TOA110/TOA111 замість TOA107/TOA108).

- [ ] **Step 3: `ObjectReader`**

```diff
diff --git a/packages/typed_openapi/lib/src/parse/object_reader.dart b/packages/typed_openapi/lib/src/parse/object_reader.dart
--- a/packages/typed_openapi/lib/src/parse/object_reader.dart
+++ b/packages/typed_openapi/lib/src/parse/object_reader.dart
@@ -1,3 +1,5 @@
+import 'package:source_span/source_span.dart';
+
 import '../diagnostics/json_pointer.dart';
 import '../model/spec_node.dart';
 import 'parse_context.dart';
@@ -191,6 +193,16 @@ final class ObjectReader {
       if (_read.contains(key)) continue;
       if (!reportExtensions && key.startsWith('x-')) continue;
       unknown[key] = value;
+      if (key == r'$ref') {
+        _context.report(
+          .refNotAllowed,
+          'OpenAPI does not accept a Reference Object here, so this '
+          r'"$ref" is ignored.',
+          pointer.child(key),
+          fix: _bundleFix,
+        );
+        continue;
+      }
       _context.report(
         .unknownKey,
         'Unknown key "$key"; it is ignored.',
@@ -221,6 +233,10 @@ final class ObjectReader {
 
   T? _item<T>(Object? raw, JsonPointer at, String expected) {
     if (raw is T) return raw;
+    if (_isRefObject(raw)) {
+      _refNotAllowed(at, expected);
+      return null;
+    }
     _context.report(
       .invalidValue,
       'Each item must be $expected, not ${describe(raw)}.',
@@ -230,6 +246,21 @@ final class ObjectReader {
   }
 
   void _invalid(String key, String expected, Object? raw) {
+    final at = pointer.child(key);
+    if (_isRefObject(raw)) {
+      _refNotAllowed(at, expected);
+      return;
+    }
+    if (key == r'$ref' && raw == null && _commentFollows(at)) {
+      _context.report(
+        .refCommentedOut,
+        r'This "$ref" is empty: without quotes, "#" starts a YAML comment, '
+        'so the reference was read as a comment.',
+        at,
+        fix: r"Quote the reference: $ref: '#/components/schemas/Pet'.",
+      );
+      return;
+    }
     _context.report(
       .invalidValue,
       '"$key" must be $expected, not ${describe(raw)}; it is ignored.',
@@ -237,6 +268,50 @@ final class ObjectReader {
     );
   }
 
+  static const _bundleFix =
+      r'A spec that puts "$ref" anywhere is written for a bundler (Redocly, '
+      'swagger-cli) that resolves it as a JSON Reference. Bundle it first, '
+      'for example with `redocly bundle`, and check the bundled file.';
+
+  static bool _isRefObject(Object? raw) =>
+      raw is Map<String, Object?> && raw.containsKey(r'$ref');
+
+  void _refNotAllowed(JsonPointer at, String expected) {
+    _context.report(
+      .refNotAllowed,
+      'OpenAPI expects $expected here, not a Reference Object, so this '
+      r'"$ref" is ignored.',
+      at,
+      fix: _bundleFix,
+    );
+  }
+
+  /// Whether the empty value at [at] was written as `key: #...`, so that
+  /// the `#` started a comment.
+  ///
+  /// package:yaml puts an empty block value at the `:` of its key, and an
+  /// empty flow value at the token after it, which is on a later line when
+  /// a comment ended the line.
+  bool _commentFollows(JsonPointer at) {
+    final span = _context.document.spanOf(at);
+    if (span is! FileSpan) return false;
+    final file = span.file;
+    String lineAt(int line) => file.getText(
+      file.getOffset(line),
+      line + 1 < file.lines ? file.getOffset(line + 1) : file.length,
+    );
+    final line = span.start.line;
+    final before = file.getText(file.getOffset(line), span.start.offset);
+    final rest = lineAt(line).substring(before.length);
+    if (_blockComment.hasMatch(rest)) return true;
+    return before.trim().isEmpty &&
+        line > 0 &&
+        _flowComment.hasMatch(lineAt(line - 1));
+  }
+
+  static final _blockComment = RegExp(r'^:?[ \t]+#');
+  static final _flowComment = RegExp(r':[ \t]+#[^\n]*\n?$');
+
   void _missing(String key) {
     _context.report(
       .missingRequiredField,
```

- [ ] **Step 4: Перевірити**

Run (`dart analyze` — з кореня, решта — з `packages/typed_openapi`):

```bash
dart analyze packages                 # No issues found!
dart test                             # All tests passed!
dart format lib test bin && dart format lib test bin   # the second run: 0 changed
```

- [ ] **Step 5: Коміт**

```bash
git add packages/typed_openapi
git commit -m "feat(typed_openapi): report $ref where OpenAPI does not allow it

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Рушій правил: `SpecEdit`, `TreeEditor`, `NormalizerRule`, `Normalizer` (TOA800)

**Files:**
- Create: `packages/typed_openapi/lib/src/normalize/spec_edit.dart`, `packages/typed_openapi/lib/src/normalize/normalizer_rule.dart`, `packages/typed_openapi/lib/src/normalize/normalizer.dart`, `packages/typed_openapi/test/normalize/spec_edit_test.dart`, `packages/typed_openapi/test/normalize/normalizer_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_openapi/lib/src/load/spec_document.dart`, `packages/typed_openapi/lib/src/resolve/spec_documents.dart`, `packages/typed_openapi/lib/src/resolve/spec_reader.dart`, `packages/typed_openapi/lib/src/resolve/spec_model.dart`, `packages/typed_openapi/lib/src/model/spec_node.dart`

**Interfaces:**
- Consumes: `SpecReader`, `SpecDocuments`, `SpecModel`, `SpecLoader` (M2), `Preset` (M1).
- Produces: усе з блоку «normalize» і «model / resolve» в «Інтерфейсах»; `DiagnosticCode.fixNotApplied` (TOA800). `Normalizer.rules` поки порожній — правила додають задачі 5+.

Поведінка, яку закріплюють тести:
- `TreeEditor` змінює копію: оригінал і вузли, спільні через YAML-аліас, лишаються як були; помилка правки — рядок-причина, не виняток.
- Виправлення застосовується, модель перечитується, знахідка звітується один раз; TOA111 першого читання, яке виправлення прибрало, у звіт не потрапляє.
- Знахідки лише-діагностики — один раз, з останнього проходу.
- З двох правок одного вузла виграє раніше правило, друга — TOA800; три проходи максимум, правки третього — TOA800.
- Вимкнене правило не працює; пресет додає підказку до `fix`; правки в іншому файлі застосовуються до нього.

- [ ] **Step 1: Код**

Перед `configNotFound` у `diagnostic_code.dart`:

```dart
  /// A normalizer fix was not applied: it overlaps an earlier rule's fix,
  /// its target is gone, or the spec kept changing.
  fixNotApplied('TOA800', 'fix-not-applied', .warning),
```

- [ ] **Step 2: Тести**

Створи `packages/typed_openapi/test/normalize/spec_edit_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/model/spec_node.dart';
import 'package:typed_openapi/src/normalize/spec_edit.dart';

void main() {
  final file = Uri.file('/specs/api.yaml');
  SpecLocation at(String pointer) =>
      SpecLocation(file, JsonPointer.parse(pointer));

  test('add, replace and remove change a copy, never the original', () {
    final original = <String, Object?>{
      'a': {'b': 1, 'c': 2},
      'l': [1, 2],
    };
    final editor = TreeEditor(original);
    expect(editor.apply(SpecEdit.add(at('#/a/d'), 3)), isNull);
    expect(editor.apply(SpecEdit.replace(at('#/a/b'), 10)), isNull);
    expect(editor.apply(SpecEdit.remove(at('#/a/c'))), isNull);
    expect(editor.apply(SpecEdit.add(at('#/l/-'), 3)), isNull);
    expect(editor.apply(SpecEdit.add(at('#/l/0'), 0)), isNull);
    expect(editor.apply(SpecEdit.remove(at('#/l/1'))), isNull);
    expect(editor.root, {
      'a': {'b': 10, 'd': 3},
      'l': [0, 2, 3],
    });
    expect(original, {
      'a': {'b': 1, 'c': 2},
      'l': [1, 2],
    });
  });

  test('a node shared by two places (a YAML alias) changes in one', () {
    final shared = <String, Object?>{'type': 'string'};
    final editor = TreeEditor({'x': shared, 'y': shared});
    expect(editor.apply(SpecEdit.add(at('#/x/format'), 'uuid')), isNull);
    expect(editor.root['x'], {'type': 'string', 'format': 'uuid'});
    expect(editor.root['y'], {'type': 'string'});
  });

  test('an edit of a missing node says why and changes nothing', () {
    final editor = TreeEditor({
      'a': {'b': 1},
    });
    expect(editor.apply(SpecEdit.replace(at('#/a/x'), 1)), contains('#/a/x'));
    expect(editor.apply(SpecEdit.remove(at('#/a/b/c'))), isNotNull);
    expect(editor.apply(SpecEdit.add(at('#/l/0'), 1)), isNotNull);
    expect(editor.apply(SpecEdit.remove(at('#'))), contains('root'));
    expect(editor.root, {
      'a': {'b': 1},
    });
  });

  test('edits overlap when one is at or inside the other', () {
    final b = SpecEdit.remove(at('#/a/b'));
    expect(b.overlaps(SpecEdit.remove(at('#/a/b'))), isTrue);
    expect(b.overlaps(SpecEdit.add(at('#/a/b/c'), 1)), isTrue);
    expect(b.overlaps(SpecEdit.remove(at('#/a'))), isTrue);
    expect(b.overlaps(SpecEdit.remove(at('#/a/bc'))), isFalse);
    expect(
      b.overlaps(
        SpecEdit.remove(SpecLocation(Uri.file('/b.yaml'), b.location.pointer)),
      ),
      isFalse,
    );
  });
}
```

Створи `packages/typed_openapi/test/normalize/normalizer_test.dart`:

```dart
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/config/project_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/model/document.dart';
import 'package:typed_openapi/src/model/schema.dart';
import 'package:typed_openapi/src/normalize/normalizer.dart';
import 'package:typed_openapi/src/normalize/normalizer_rule.dart';
import 'package:typed_openapi/src/normalize/spec_edit.dart';

import '../helpers/temp_dir.dart';

/// Renames the title "old" to "new": a fix that holds after one pass.
final class _RenameTitle extends NormalizerRule {
  const _RenameTitle();

  @override
  String get name => 'rename-title';

  @override
  List<DiagnosticCode> get codes => const [.invalidValue];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final info in context.nodes<Info>()) {
      if (info.title != 'old') continue;
      final at = info.location.child('title');
      yield context.finding(
        .invalidValue,
        'The title is old.',
        at,
        fix: 'Rename it.',
        edits: [SpecEdit.replace(at, 'new')],
      );
    }
  }

  @override
  String? hint(DiagnosticCode code, Preset preset) =>
      preset == .nestjs ? 'Use @ApiTitle.' : null;
}

/// Removes `required: true` from every schema: the fix M3's
/// `bool-required-to-array` makes, without moving the name.
final class _DropBoolRequired extends NormalizerRule {
  const _DropBoolRequired();

  @override
  String get name => 'drop-bool-required';

  @override
  List<DiagnosticCode> get codes => const [.invalidValue];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      final raw = context.rawAt(schema.location)?.$1;
      if (raw is! Map<String, Object?> || raw['required'] is! bool) continue;
      final at = schema.location.child('required');
      yield context.finding(
        .invalidValue,
        'Boolean required.',
        at,
        edits: [SpecEdit.remove(at)],
      );
    }
  }
}

/// Reports every schema without a type: a diagnostic-only rule.
final class _Untyped extends NormalizerRule {
  const _Untyped();

  @override
  String get name => 'untyped';

  @override
  List<DiagnosticCode> get codes => const [.missingRequiredField];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      if (schema.types.isNotEmpty || schema.ref != null) continue;
      yield context.finding(
        .missingRequiredField,
        'No type.',
        schema.location,
      );
    }
  }
}

/// Sets `info.title` on every pass: it never settles.
final class _AlwaysEdits extends NormalizerRule {
  const _AlwaysEdits(this.name);

  @override
  final String name;

  @override
  List<DiagnosticCode> get codes => const [.invalidValue];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    final info = context.nodes<Info>().single;
    yield context.finding(
      .invalidValue,
      'Title by $name.',
      info.location,
      edits: [
        SpecEdit.replace(info.location.child('title'), '${info.title}+'),
      ],
    );
  }
}

void main() {
  const spec = '''
openapi: 3.0.3
info: {title: old, version: "1"}
components:
  schemas:
    Pet:
      type: object
      properties:
        name: {type: string, required: true}
''';

  (NormalizedSpec, DiagnosticBag) normalize(
    String text,
    List<NormalizerRule> rules, {
    Set<String> disabled = const {},
    Preset? preset,
  }) {
    final bag = DiagnosticBag();
    final document = SpecLoader(bag).parse(text, 'api.yaml')!;
    final result = Normalizer(
      bag,
      rules: rules,
      disabled: disabled,
      preset: preset,
    ).normalize(document, .v30);
    return (result, bag);
  }

  test('a fix is applied, the model is read again and reported once', () {
    final (result, bag) = normalize(spec, [const _RenameTitle()]);
    expect(result.model.document.info?.title, 'new');
    expect(result.documents.root.root['info'], {
      'title': 'new',
      'version': '1',
    });
    expect(bag.all.map((d) => (d.code, d.pointer?.value)), [
      (DiagnosticCode.invalidValue, '#/info/title'),
      (
        DiagnosticCode.invalidValue,
        '#/components/schemas/Pet/properties/name/required',
      ),
    ]);
    expect(bag.all.first.message, 'The title is old.');
    expect(bag.all.first.line, 2);
  });

  test('parser diagnostics come from the last pass only', () {
    // The first read reports `required: true` as invalid-value; the fix
    // removes it, so the report has the fix and not the parser's complaint.
    final (_, bag) = normalize(spec, [const _DropBoolRequired()]);
    expect(bag.all.single.message, 'Boolean required.');
  });

  test('diagnostic-only findings are reported once, from the last pass', () {
    final (_, bag) = normalize(
      'openapi: 3.0.3\ninfo: {title: old, version: "1"}\n'
      'components: {schemas: {Any: {description: anything}}}\n',
      [const _RenameTitle(), const _Untyped()],
    );
    expect(bag.all.map((d) => d.message), ['The title is old.', 'No type.']);
  });

  test('of two overlapping fixes the earlier rule wins, with a warning', () {
    final (result, bag) = normalize(spec, [
      const _AlwaysEdits('first'),
      const _AlwaysEdits('second'),
    ]);
    expect(result.model.document.info?.title, 'old++');
    final skipped = bag.all
        .where((d) => d.code == DiagnosticCode.fixNotApplied)
        .map((d) => d.message)
        .toSet();
    expect(skipped, contains(contains('overlaps a fix of rule "first"')));
  });

  test('the normalizer stops after three passes and says so', () {
    final (result, bag) = normalize(spec, [const _AlwaysEdits('loop')]);
    expect(result.model.document.info?.title, 'old++');
    expect(Normalizer.maxPasses, 3);
    expect(
      bag.all
          .where((d) => d.code == DiagnosticCode.fixNotApplied)
          .single
          .message,
      contains('still changed after 3 passes'),
    );
  });

  test('a disabled rule does not run', () {
    final (result, bag) = normalize(
      spec,
      [const _RenameTitle()],
      disabled: {'rename-title'},
    );
    expect(result.model.document.info?.title, 'old');
    expect(bag.all.single.code, DiagnosticCode.invalidValue);
    expect(bag.all.single.pointer?.value, contains('required'));
  });

  test('a preset adds the framework hint to the fix', () {
    final (_, bag) = normalize(spec, [const _RenameTitle()], preset: .nestjs);
    expect(bag.all.first.fix, 'Rename it. Use @ApiTitle.');
  });

  test('fixes in another file are applied to that file', () {
    final dir = TempDir();
    dir.write(
      'pet.yaml',
      'Pet:\n  type: object\n  properties:\n'
          '    name: {type: string, required: true}\n',
    );
    final path = dir.write('api.yaml', r'''
openapi: 3.0.3
info: {title: t, version: "1"}
components:
  schemas:
    Pet: {$ref: "pet.yaml#/Pet"}
''');
    final bag = DiagnosticBag();
    final document = SpecLoader(bag).load(path, displayPath: 'api.yaml')!;
    final result = Normalizer(
      bag,
      rules: [const _DropBoolRequired()],
    ).normalize(document, .v30);
    final pet = result.documents[p.toUri(p.join(dir.path, 'pet.yaml'))]!;
    expect(pet.root['Pet'], {
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
      },
    });
    expect(bag.all.single.file, 'pet.yaml');
    expect(bag.all.single.line, 4);
  });
}
```

Run: `dart test test/normalize` — Expected: FAIL (немає `normalize/`).

- [ ] **Step 3: Підтримка в моделі й резолвері**

```diff
diff --git a/packages/typed_openapi/lib/src/load/spec_document.dart b/packages/typed_openapi/lib/src/load/spec_document.dart
--- a/packages/typed_openapi/lib/src/load/spec_document.dart
+++ b/packages/typed_openapi/lib/src/load/spec_document.dart
@@ -27,6 +27,13 @@ final class SpecDocument {
 
   final Map<String, SourceSpan> _spans;
 
+  /// This document with [root] as its contents and the same positions.
+  ///
+  /// Positions stay keyed by pointer: a node an edit added has none, and a
+  /// list item an edit moved keeps the position of its old index.
+  SpecDocument withRoot(Map<String, Object?> root) =>
+      SpecDocument(file: file, uri: uri, root: root, spans: _spans);
+
   /// Whether source positions were recorded.
   bool get hasPositions => _spans.isNotEmpty;
 
diff --git a/packages/typed_openapi/lib/src/model/spec_node.dart b/packages/typed_openapi/lib/src/model/spec_node.dart
--- a/packages/typed_openapi/lib/src/model/spec_node.dart
+++ b/packages/typed_openapi/lib/src/model/spec_node.dart
@@ -15,6 +15,11 @@ final class SpecLocation implements Comparable<SpecLocation> {
   /// The pointer to the node inside [document].
   final JsonPointer pointer;
 
+  /// The location of [token] (a property name or a list index) under this
+  /// one, in the same document.
+  SpecLocation child(Object token) =>
+      SpecLocation(document, pointer.child(token));
+
   @override
   bool operator ==(Object other) =>
       other is SpecLocation &&
diff --git a/packages/typed_openapi/lib/src/resolve/spec_documents.dart b/packages/typed_openapi/lib/src/resolve/spec_documents.dart
--- a/packages/typed_openapi/lib/src/resolve/spec_documents.dart
+++ b/packages/typed_openapi/lib/src/resolve/spec_documents.dart
@@ -8,8 +8,16 @@ import '../load/spec_loader.dart';
 /// The documents of one spec: the root document and every file its `$ref`s
 /// reach, each loaded once and keyed by absolute URI.
 final class SpecDocuments {
-  /// Creates the set for [root]; other files are read with [_loader].
-  SpecDocuments(this._loader, this.root) {
+  /// Creates the set for [root]; other files are read with [_loader],
+  /// except [others], which are already loaded.
+  SpecDocuments(
+    this._loader,
+    this.root, {
+    Iterable<SpecDocument> others = const [],
+  }) {
+    for (final document in others) {
+      _documents[document.uri] = document;
+    }
     _documents[root.uri] = root;
   }
 
@@ -34,6 +42,13 @@ final class SpecDocuments {
     return _documents[uri] = document;
   }
 
+  /// Every document loaded so far, the root first.
+  Iterable<SpecDocument> get loaded => [
+    root,
+    for (final document in _documents.values)
+      if (document != null && document.uri != root.uri) document,
+  ];
+
   /// Whether a file (not a directory) is at [uri].
   ///
   /// False when [uri] does not name a file path, such as one with a
diff --git a/packages/typed_openapi/lib/src/resolve/spec_model.dart b/packages/typed_openapi/lib/src/resolve/spec_model.dart
--- a/packages/typed_openapi/lib/src/resolve/spec_model.dart
+++ b/packages/typed_openapi/lib/src/resolve/spec_model.dart
@@ -18,6 +18,11 @@ final class SpecModel {
   /// The root document.
   final OpenApiDocument document;
 
+  /// Every node read from any file, ordered by location.
+  late final List<SpecNode> nodes = List.unmodifiable(
+    _nodes.values.toList()..sort((a, b) => a.location.compareTo(b.location)),
+  );
+
   final Map<SpecLocation, SpecNode> _nodes;
   final Map<SpecLocation, SpecLocation> _targets;
 
diff --git a/packages/typed_openapi/lib/src/resolve/spec_reader.dart b/packages/typed_openapi/lib/src/resolve/spec_reader.dart
--- a/packages/typed_openapi/lib/src/resolve/spec_reader.dart
+++ b/packages/typed_openapi/lib/src/resolve/spec_reader.dart
@@ -20,13 +20,20 @@ final class SpecReader {
   final DiagnosticBag _diagnostics;
 
   /// Reads [document], which declares [version].
-  SpecModel read(SpecDocument document, OpenApiVersion version) {
+  ///
+  /// Other files come from [documents], whose root is [document]; by
+  /// default they are loaded on demand, reporting to this reader's bag.
+  SpecModel read(
+    SpecDocument document,
+    OpenApiVersion version, {
+    SpecDocuments? documents,
+  }) {
     final index = SpecIndex();
     final parsed = OpenApiParser(_diagnostics, document, index).parse(version);
     final model = RefResolver(_diagnostics).resolve(
       parsed,
       index,
-      SpecDocuments(SpecLoader(_diagnostics), document),
+      documents ?? SpecDocuments(SpecLoader(_diagnostics), document),
     );
     DialectChecker(_diagnostics).check(index.features, version);
     return model;
```

- [ ] **Step 4: Правки дерева**

Створи `packages/typed_openapi/lib/src/normalize/spec_edit.dart`:

```dart
import 'dart:collection';

import '../model/spec_node.dart';

/// What a [SpecEdit] does at its location.
enum EditOperation {
  /// Sets an object member, inserts a list item at an index or appends it
  /// at `-`, as JSON Patch `add` does.
  add,

  /// Replaces the value that is there.
  replace,

  /// Removes the value that is there.
  remove,
}

/// A change to the plain tree of one spec file: a rule's fix, and later an
/// override (M4).
final class SpecEdit {
  /// Sets the member, or inserts the item, at [location] to [value].
  const SpecEdit.add(this.location, this.value) : operation = .add;

  /// Replaces the value at [location] with [value].
  const SpecEdit.replace(this.location, this.value) : operation = .replace;

  /// Removes the value at [location].
  const SpecEdit.remove(this.location) : operation = .remove, value = null;

  /// The document and the pointer the edit applies to.
  final SpecLocation location;

  /// What the edit does.
  final EditOperation operation;

  /// The new plain value for [EditOperation.add] and
  /// [EditOperation.replace].
  final Object? value;

  /// Whether this edit and [other] touch the same node, or one of them a
  /// node inside the other's.
  bool overlaps(SpecEdit other) {
    if (location.document != other.location.document) return false;
    final a = location.pointer.tokens;
    final b = other.location.pointer.tokens;
    final shorter = a.length < b.length ? a : b;
    for (var i = 0; i < shorter.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Applies [SpecEdit]s to a plain tree without changing it: every object
/// and list on the way to an edit is copied once, and the copy is changed.
///
/// The tree may share nodes (a YAML alias is the same Dart object as its
/// anchor), so changing a node in place would change every place that
/// shares it.
final class TreeEditor {
  /// Creates an editor of [root].
  TreeEditor(Map<String, Object?> root) : _root = root;

  Map<String, Object?> _root;
  final Set<Object> _copies = HashSet.identity();

  /// The tree with every applied edit.
  Map<String, Object?> get root => _root;

  /// Applies [edit]; returns why it cannot be applied, or null.
  String? apply(SpecEdit edit) {
    final tokens = edit.location.pointer.tokens;
    if (tokens.isEmpty) return 'the document root cannot be edited';
    Object container = _root = _own(_root) as Map<String, Object?>;
    for (final token in tokens.take(tokens.length - 1)) {
      final child = _child(container, token);
      if (child is! Map<String, Object?> && child is! List<Object?>) {
        return 'there is no object or list at ${edit.location.pointer.value}';
      }
      final owned = _own(child!);
      _set(container, token, owned);
      container = owned;
    }
    return _change(container, tokens.last, edit);
  }

  String? _change(Object container, String token, SpecEdit edit) {
    switch ((container, edit.operation)) {
      case (final Map<String, Object?> map, .add):
        map[token] = edit.value;
      case (final Map<String, Object?> map, .replace)
          when map.containsKey(
            token,
          ):
        map[token] = edit.value;
      case (final Map<String, Object?> map, .remove)
          when map.containsKey(
            token,
          ):
        map.remove(token);
      case (final List<Object?> list, .add) when token == '-':
        list.add(edit.value);
      case (final List<Object?> list, .add):
        final index = _index(token);
        if (index == null || index > list.length) return _missing(edit);
        list.insert(index, edit.value);
      case (final List<Object?> list, .replace || .remove):
        final index = _index(token);
        if (index == null || index >= list.length) return _missing(edit);
        if (edit.operation == .replace) {
          list[index] = edit.value;
        } else {
          list.removeAt(index);
        }
      default:
        return _missing(edit);
    }
    return null;
  }

  static String _missing(SpecEdit edit) =>
      'nothing is at ${edit.location.pointer.value}';

  Object _own(Object container) {
    if (_copies.contains(container)) return container;
    final copy = container is Map<String, Object?>
        ? Map<String, Object?>.of(container)
        : List<Object?>.of(container as List<Object?>);
    _copies.add(copy);
    return copy;
  }

  static Object? _child(Object container, String token) => switch (container) {
    final Map<String, Object?> map => map[token],
    final List<Object?> list => switch (_index(token)) {
      final index? when index < list.length => list[index],
      _ => null,
    },
    _ => null,
  };

  static void _set(Object container, String token, Object value) {
    switch (container) {
      case final Map<String, Object?> map:
        map[token] = value;
      case final List<Object?> list:
        list[_index(token)!] = value;
    }
  }

  static int? _index(String token) =>
      _indexPattern.hasMatch(token) ? int.parse(token) : null;

  static final _indexPattern = RegExp(r'^(0|[1-9][0-9]{0,8})$');
}
```

- [ ] **Step 5: Правило і контекст**

Створи `packages/typed_openapi/lib/src/normalize/normalizer_rule.dart`:

```dart
import '../config/project_config.dart';
import '../diagnostics/diagnostic.dart';
import '../diagnostics/diagnostic_code.dart';
import '../load/openapi_version.dart';
import '../model/spec_node.dart';
import '../resolve/spec_documents.dart';
import '../resolve/spec_model.dart';
import 'spec_edit.dart';

/// What a rule found: a diagnostic, and for a fix the edits that make it.
final class Finding {
  /// Creates a finding.
  const Finding(this.diagnostic, {this.edits = const []});

  /// What is wrong and how to fix it at the source.
  final Diagnostic diagnostic;

  /// The edits that fix it; empty for a diagnostic-only finding.
  final List<SpecEdit> edits;
}

/// What a rule reads: the model of one pass and the files it came from.
final class RuleContext {
  /// Creates a context for [model], read from [documents] as [version].
  RuleContext(this.model, this.documents, this.version);

  /// The spec as the parser read it in this pass.
  final SpecModel model;

  /// The files of the spec, with their plain trees and positions.
  final SpecDocuments documents;

  /// The version the root document declares.
  final OpenApiVersion version;

  /// Every node of type [T], ordered by location.
  Iterable<T> nodes<T extends SpecNode>() => model.nodes.whereType<T>();

  /// The raw value at [location] as a one-element record, or null when
  /// nothing is there.
  (Object?,)? rawAt(SpecLocation location) =>
      documents[location.document]?.valueAt(location.pointer);

  /// A finding of [code] at [at], with [edits] when it is a fix.
  Finding finding(
    DiagnosticCode code,
    String message,
    SpecLocation at, {
    String? fix,
    List<SpecEdit> edits = const [],
  }) => Finding(
    Diagnostic(
      code: code,
      severity: code.defaultSeverity,
      message: message,
      file: documents.displayPath(at.document),
      pointer: at.pointer,
      span: documents[at.document]?.spanOf(at.pointer),
      fix: fix,
    ),
    edits: edits,
  );
}

/// A named check of the spec model: it finds a defect and either fixes it
/// with [SpecEdit]s, when the fix follows from the spec or the protocol, or
/// describes it.
///
/// Rules never change the model; the normalizer applies their edits to the
/// plain trees and reads the model again.
abstract base class NormalizerRule {
  /// Creates a rule.
  const NormalizerRule();

  /// The name used in the config, such as `bool-required-to-array`.
  String get name;

  /// The codes the rule reports.
  List<DiagnosticCode> get codes;

  /// The findings in [context], in a stable order.
  Iterable<Finding> check(RuleContext context);

  /// How to fix a [code] finding in the code of a [preset] framework, or
  /// null when there is no specific recipe.
  String? hint(DiagnosticCode code, Preset preset) => null;
}
```

- [ ] **Step 6: Нормалізатор**

Створи `packages/typed_openapi/lib/src/normalize/normalizer.dart`:

```dart
import '../config/project_config.dart';
import '../diagnostics/diagnostic.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../load/openapi_version.dart';
import '../load/spec_document.dart';
import '../load/spec_loader.dart';
import '../resolve/spec_documents.dart';
import '../resolve/spec_model.dart';
import '../resolve/spec_reader.dart';
import 'normalizer_rule.dart';
import 'spec_edit.dart';

/// The result of normalizing a spec.
final class NormalizedSpec {
  /// Creates a result.
  const NormalizedSpec(this.model, this.documents);

  /// The model of the last pass.
  final SpecModel model;

  /// The files of the last pass, with every fix applied.
  final SpecDocuments documents;
}

/// Reads a spec into the model, runs the rules over it, applies their fixes
/// to the plain trees and reads it again, until no rule has a fix or
/// [maxPasses] passes have run.
///
/// The report holds what the parser and resolver say about the last pass,
/// every fix of every pass, and the diagnostics of the last pass's rules.
/// Problems go to the [DiagnosticBag] given to the constructor; files are
/// loaded once, with their loading problems reported there too.
final class Normalizer {
  /// Creates a normalizer that reports to [_diagnostics] and runs [rules]
  /// (by default every rule) in order, except the [disabled] names; a
  /// [preset] adds framework hints to the findings.
  Normalizer(
    this._diagnostics, {
    List<NormalizerRule>? rules,
    Set<String> disabled = const {},
    this.preset,
  }) : _rules = [
         for (final rule in rules ?? Normalizer.rules)
           if (!disabled.contains(rule.name)) rule,
       ];

  /// How many times the model is read at most.
  static const maxPasses = 3;

  /// Every rule, in the order it runs; an earlier rule's fix wins a
  /// conflict.
  static final List<NormalizerRule> rules = List.unmodifiable(
    <NormalizerRule>[],
  );

  /// The names of [rules].
  static Set<String> get ruleNames => {for (final rule in rules) rule.name};

  final DiagnosticBag _diagnostics;
  final List<NormalizerRule> _rules;

  /// The framework whose hints the findings carry.
  final Preset? preset;

  /// Normalizes [document], which declares [version].
  NormalizedSpec normalize(SpecDocument document, OpenApiVersion version) {
    final loader = SpecLoader(_diagnostics);
    var root = document;
    var others = const <SpecDocument>[];
    for (var pass = 1; ; pass++) {
      final scratch = DiagnosticBag();
      final documents = SpecDocuments(loader, root, others: others);
      final model = SpecReader(scratch).read(
        root,
        version,
        documents: documents,
      );
      final context = RuleContext(model, documents, version);
      final found = [
        for (final rule in _rules)
          for (final finding in rule.check(context)) (rule, finding),
      ];
      final hasEdits = found.any((f) => f.$2.edits.isNotEmpty);
      if (!hasEdits || pass == maxPasses) {
        scratch.all.forEach(_diagnostics.add);
        for (final (rule, finding) in found) {
          _report(rule, finding);
          for (final edit in finding.edits) {
            _notApplied(
              documents,
              rule,
              edit,
              'the spec still changed after $maxPasses passes',
            );
          }
        }
        return NormalizedSpec(model, documents);
      }
      for (final (rule, finding) in found) {
        if (finding.edits.isNotEmpty) _report(rule, finding);
      }
      final edited = _apply(documents, found);
      root = edited[root.uri] ?? root;
      others = [
        for (final loaded in documents.loaded)
          if (loaded.uri != root.uri) edited[loaded.uri] ?? loaded,
      ];
    }
  }

  /// Applies the edits of [found] in order, skipping any that overlaps an
  /// earlier one; returns the edited documents by URI.
  Map<Uri, SpecDocument> _apply(
    SpecDocuments documents,
    List<(NormalizerRule, Finding)> found,
  ) {
    final accepted = <(NormalizerRule, SpecEdit)>[];
    final editors = <Uri, TreeEditor>{};
    for (final (rule, finding) in found) {
      for (final edit in finding.edits) {
        final earlier = accepted.where((a) => a.$2.overlaps(edit)).firstOrNull;
        if (earlier != null) {
          _notApplied(
            documents,
            rule,
            edit,
            'it overlaps a fix of rule "${earlier.$1.name}"',
          );
          continue;
        }
        final uri = edit.location.document;
        final document = documents[uri];
        if (document == null) {
          _notApplied(documents, rule, edit, 'its file cannot be read');
          continue;
        }
        final editor = editors[uri] ??= TreeEditor(document.root);
        final problem = editor.apply(edit);
        if (problem != null) {
          _notApplied(documents, rule, edit, problem);
          continue;
        }
        accepted.add((rule, edit));
      }
    }
    return {
      for (final MapEntry(key: uri, value: editor) in editors.entries)
        uri: documents[uri]!.withRoot(editor.root),
    };
  }

  void _report(NormalizerRule rule, Finding finding) {
    final d = finding.diagnostic;
    final hint = switch (preset) {
      final preset? => rule.hint(d.code, preset),
      null => null,
    };
    _diagnostics.add(
      hint == null
          ? d
          : Diagnostic(
              code: d.code,
              severity: d.severity,
              message: d.message,
              file: d.file,
              pointer: d.pointer,
              span: d.span,
              fix: d.fix == null ? hint : '${d.fix} $hint',
            ),
    );
  }

  void _notApplied(
    SpecDocuments documents,
    NormalizerRule rule,
    SpecEdit edit,
    String reason,
  ) {
    final uri = edit.location.document;
    final pointer = edit.location.pointer;
    _diagnostics.report(
      .fixNotApplied,
      'A fix of rule "${rule.name}" was not applied: $reason.',
      file: documents.displayPath(uri),
      pointer: pointer,
      span: documents[uri]?.spanOf(pointer),
    );
  }
}
```

- [ ] **Step 7: Перевірити**

Run (`dart analyze` — з кореня, решта — з `packages/typed_openapi`):

```bash
dart analyze packages                 # No issues found!
dart test                             # All tests passed!
dart format lib test bin && dart format lib test bin   # the second run: 0 changed
```

- [ ] **Step 8: Коміт**

```bash
git add packages/typed_openapi
git commit -m "feat(typed_openapi): add the normalizer rule engine

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Виправлення схем: `bool-required-to-array` (TOA201), `drop-invalid-default` (TOA211)

**Files:**
- Create: `packages/typed_openapi/lib/src/normalize/rules/bool_required_to_array.dart`, `packages/typed_openapi/lib/src/normalize/rules/drop_invalid_default.dart`, `packages/typed_openapi/test/normalize/schema_fix_rules_test.dart`
- Modify: `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_openapi/lib/src/normalize/normalizer.dart`

**Interfaces:**
- Consumes: `NormalizerRule`, `RuleContext`, `SpecEdit`, `Normalizer` (задача 4); `SchemaObject` (M2); `ObjectReader.describe` (M2).
- Produces: `BoolRequiredToArray`, `DropInvalidDefault` у `Normalizer.rules` (саме в цьому порядку); `DiagnosticCode.boolRequired` (TOA201), `DiagnosticCode.invalidDefault` (TOA211).

Поведінка:
- `required: true` на властивості → ім'я дописується в `required` батьківського об'єкта (після наявних, без повторів; список створюється, якщо його не було); `required` властивості прибирається. `required: false` прибирається. Властивість, що сама є об'єктом з `required: true`-дітьми, отримує замість булевого `required` список імен дітей (одна правка замість двох конфліктних). `required: true` поза властивістю (у `items`, у корені компонента) правило не чіпає: це C-49, діагностика TOA203 (задача 7).
- `default`, JSON-тип якого не збігається з жодним `type` схеми, прибирається (`null` при `nullable: true` — допустимий; `integer` приймає `3.0`). Пресет `nestjs` додає рецепт `excludeDynamicDefaults` (research/06 §D.1, п. 2).

- [ ] **Step 1: Коди**

Перед `fixNotApplied` у `diagnostic_code.dart`:

```dart
  /// A property schema says `required: true` or `false` (OpenAPI 2 style);
  /// the name is moved into the object's `required` list.
  boolRequired('TOA201', 'bool-required', .warning),

  /// A schema's `default` is not of the schema's type; it is ignored.
  invalidDefault('TOA211', 'invalid-default', .warning),
```

- [ ] **Step 2: Тест, що не проходить**

Створи `packages/typed_openapi/test/normalize/schema_fix_rules_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/config/project_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/model/schema.dart';
import 'package:typed_openapi/src/normalize/normalizer.dart';
import 'package:typed_openapi/src/normalize/rules/bool_required_to_array.dart';
import 'package:typed_openapi/src/normalize/rules/drop_invalid_default.dart';

void main() {
  /// Normalizes the 3.0 document whose `components.schemas` are [schemas]
  /// with every rule.
  (NormalizedSpec, DiagnosticBag) normalize(String schemas, {Preset? preset}) {
    final bag = DiagnosticBag();
    final document = SpecLoader(bag).parse(
      'openapi: 3.0.3\ninfo: {title: Shop, version: "1"}\n'
          'components:\n  schemas:\n$schemas',
      'api.yaml',
    )!;
    final result = Normalizer(bag, preset: preset).normalize(document, .v30);
    return (result, bag);
  }

  Map<String, Object?> schemaIn(NormalizedSpec result, String name) =>
      ((result.documents.root.root['components']! as Map)['schemas']!
              as Map)[name]!
          as Map<String, Object?>;

  test('every rule is registered once, in order', () {
    expect(Normalizer.rules.map((r) => r.name), [
      'bool-required-to-array',
      'drop-invalid-default',
    ]);
    expect(const BoolRequiredToArray().codes, [DiagnosticCode.boolRequired]);
    expect(const DropInvalidDefault().codes, [DiagnosticCode.invalidDefault]);
  });

  group('bool-required-to-array', () {
    test('required: true moves the name into the object\'s list', () {
      final (result, bag) = normalize('''
    Order:
      type: object
      required: [id]
      properties:
        id: {type: string}
        note: {type: string, required: true}
        total: {type: number, required: true}
        coupon: {type: string, required: false}
''');
      expect(schemaIn(result, 'Order'), {
        'type': 'object',
        'required': ['id', 'note', 'total'],
        'properties': {
          'id': {'type': 'string'},
          'note': {'type': 'string'},
          'total': {'type': 'number'},
          'coupon': {'type': 'string'},
        },
      });
      final order =
          result.model.document.components!.schemas['Order']! as SchemaObject;
      expect(order.required, ['id', 'note', 'total']);
      expect(bag.all.map((d) => (d.code, d.pointer?.value)), [
        (
          DiagnosticCode.boolRequired,
          '#/components/schemas/Order/properties/note/required',
        ),
        (
          DiagnosticCode.boolRequired,
          '#/components/schemas/Order/properties/total/required',
        ),
        (
          DiagnosticCode.boolRequired,
          '#/components/schemas/Order/properties/coupon/required',
        ),
      ]);
      expect(bag.all.first.severity, Severity.warning);
      expect(bag.all.first.line, 10);
    });

    test('an object without a list gets one', () {
      final (result, bag) = normalize('''
    Tag:
      type: object
      properties:
        name: {type: string, required: true}
''');
      expect(schemaIn(result, 'Tag')['required'], ['name']);
      expect(bag.all.single.message, contains('"name"'));
    });

    test('a required property that has required properties itself', () {
      final (result, bag) = normalize('''
    Order:
      type: object
      properties:
        address:
          type: object
          required: true
          properties:
            city: {type: string, required: true}
''');
      expect(schemaIn(result, 'Order')['required'], ['address']);
      final address =
          (schemaIn(result, 'Order')['properties']! as Map)['address']! as Map;
      expect(address['required'], ['city']);
      expect(bag.all.map((d) => d.code), [
        DiagnosticCode.boolRequired,
        DiagnosticCode.boolRequired,
      ]);
      expect(
        bag.all.where((d) => d.code == DiagnosticCode.invalidValue),
        isEmpty,
      );
    });

    test('a valid required list is left alone', () {
      final (_, bag) = normalize('''
    Tag:
      type: object
      required: [name]
      properties:
        name: {type: string}
''');
      expect(bag.all, isEmpty);
    });
  });

  group('drop-invalid-default', () {
    test('a default of another type is removed', () {
      final (result, bag) = normalize('''
    Filter:
      type: object
      properties:
        tags: {type: array, items: {type: string}, default: ""}
        limit: {type: integer, default: 2.5}
        page: {type: integer, default: 1}
        sort: {type: string, nullable: true, default: null}
''');
      final properties = schemaIn(result, 'Filter')['properties']! as Map;
      expect(properties['tags'], {
        'type': 'array',
        'items': {'type': 'string'},
      });
      expect((properties['limit']! as Map).containsKey('default'), isFalse);
      expect((properties['page']! as Map)['default'], 1);
      expect((properties['sort']! as Map)['default'], isNull);
      expect(bag.sorted.map((d) => d.pointer?.value), [
        '#/components/schemas/Filter/properties/tags/default',
        '#/components/schemas/Filter/properties/limit/default',
      ]);
      expect(
        bag.sorted.first.message,
        'The default, a string, is not of type array; it is ignored.',
      );
    });

    test('nestjs gets a hint about dynamic defaults', () {
      final (_, bag) = normalize(
        '    When: {type: string, format: date-time, default: 0}\n',
        preset: .nestjs,
      );
      expect(bag.all.single.fix, contains('excludeDynamicDefaults'));
    });
  });
}
```

Run: `dart test test/normalize/schema_fix_rules_test.dart` — Expected: FAIL (немає `rules/`).

- [ ] **Step 3: `bool-required-to-array`**

Створи `packages/typed_openapi/lib/src/normalize/rules/bool_required_to_array.dart`:

```dart
import '../../diagnostics/diagnostic_code.dart';
import '../../model/schema.dart';
import '../../model/spec_node.dart';
import '../normalizer_rule.dart';
import '../spec_edit.dart';

/// `required: true` on a property schema (OpenAPI 2 style, C-1, C-49)
/// moves the property's name into the `required` list of the object schema;
/// `required: false` is removed.
///
/// The fix is unambiguous: OpenAPI 3 has exactly one way to say a property
/// is required.
final class BoolRequiredToArray extends NormalizerRule {
  /// Creates the rule.
  const BoolRequiredToArray();

  @override
  String get name => 'bool-required-to-array';

  @override
  List<DiagnosticCode> get codes => const [.boolRequired];

  @override
  Iterable<Finding> check(RuleContext context) {
    final flags = <(SchemaObject, String, SchemaObject, bool)>[];
    final added = <SpecLocation, List<String>>{};
    for (final schema in context.nodes<SchemaObject>()) {
      for (final MapEntry(key: name, value: property)
          in schema.properties.entries) {
        if (property is! SchemaObject) continue;
        final flag = _flagOf(context, property);
        if (flag == null) continue;
        flags.add((schema, name, property, flag));
        if (flag) (added[schema.location] ??= []).add(name);
      }
    }
    final findings = <Finding>[];
    final listed = <SpecLocation>{};
    for (final (schema, name, property, flag) in flags) {
      final at = property.location.child('required');
      findings.add(
        context.finding(
          .boolRequired,
          flag
              ? 'Property "$name" says "required: true", the OpenAPI 2 way; '
                    'OpenAPI 3 lists required properties in the "required" '
                    'array of the object, so the name is moved there.'
              : 'Property "$name" says "required: false", the OpenAPI 2 way; '
                    'a property missing from "required" is optional, so the '
                    'flag is removed.',
          at,
          fix: flag
              ? 'Add "$name" to "required" of the object schema and remove '
                    '"required" from the property.'
              : 'Remove "required: false" from the property.',
          edits: [
            // A property that is also an object with required properties
            // gets its "required" replaced by that list below instead.
            if (!added.containsKey(property.location)) SpecEdit.remove(at),
            if (flag && listed.add(schema.location))
              _listEdit(context, schema, added[schema.location]!),
          ],
        ),
      );
    }
    return findings;
  }

  /// `required` of [property] when it is a boolean.
  static bool? _flagOf(RuleContext context, SchemaObject property) =>
      switch (context.rawAt(property.location)) {
        (final Map<String, Object?> raw,) => switch (raw['required']) {
          final bool flag => flag,
          _ => null,
        },
        _ => null,
      };

  /// The edit that makes `required` of [schema] list [names] after the
  /// names it already lists.
  static SpecEdit _listEdit(
    RuleContext context,
    SchemaObject schema,
    List<String> names,
  ) {
    final at = schema.location.child('required');
    final existing = switch (context.rawAt(at)) {
      (final List<Object?> list,) => list,
      _ => const <Object?>[],
    };
    final list = [
      ...existing,
      for (final name in names)
        if (!existing.contains(name)) name,
    ];
    return switch (context.rawAt(at)) {
      null => SpecEdit.add(at, list),
      _ => SpecEdit.replace(at, list),
    };
  }
}
```

- [ ] **Step 4: `drop-invalid-default`**

Створи `packages/typed_openapi/lib/src/normalize/rules/drop_invalid_default.dart`:

```dart
import '../../config/project_config.dart';
import '../../diagnostics/diagnostic_code.dart';
import '../../model/schema.dart';
import '../../parse/object_reader.dart';
import '../normalizer_rule.dart';
import '../spec_edit.dart';

/// A `default` whose JSON type is none of the schema's `type`s (C-28) is
/// ignored, as the parser ignores any value of the wrong type.
final class DropInvalidDefault extends NormalizerRule {
  /// Creates the rule.
  const DropInvalidDefault();

  @override
  String get name => 'drop-invalid-default';

  @override
  List<DiagnosticCode> get codes => const [.invalidDefault];

  @override
  Iterable<Finding> check(RuleContext context) sync* {
    for (final schema in context.nodes<SchemaObject>()) {
      final value = schema.defaultValue;
      if (value == null || schema.types.isEmpty) continue;
      final (raw,) = value;
      if (raw == null && schema.nullable == true) continue;
      if (schema.types.any((type) => _matches(type, raw))) continue;
      final types = schema.types.map((t) => t.wire).join(' or ');
      final at = schema.location.child('default');
      yield context.finding(
        .invalidDefault,
        'The default, ${ObjectReader.describe(raw)}, is not of type $types; '
        'it is ignored.',
        at,
        fix: 'Change the default to a value of type $types, or remove it.',
        edits: [SpecEdit.remove(at)],
      );
    }
  }

  @override
  String? hint(DiagnosticCode code, Preset preset) => switch (preset) {
    .nestjs =>
      'In NestJS, check `default` in @ApiProperty; '
          '`excludeDynamicDefaults: true` in SwaggerModule.createDocument '
          'leaves out defaults computed at runtime.',
    _ => null,
  };

  static bool _matches(SchemaType type, Object? value) => switch (type) {
    .string => value is String,
    .number => value is num,
    .integer => value is num && value.isFinite && value == value.truncate(),
    .boolean => value is bool,
    .array => value is List<Object?>,
    .object => value is Map<String, Object?>,
    .nullType => value == null,
  };
}
```

- [ ] **Step 5: Зареєструвати правила**

```diff
diff --git a/packages/typed_openapi/lib/src/normalize/normalizer.dart b/packages/typed_openapi/lib/src/normalize/normalizer.dart
--- a/packages/typed_openapi/lib/src/normalize/normalizer.dart
+++ b/packages/typed_openapi/lib/src/normalize/normalizer.dart
@@ -8,6 +8,8 @@ import '../resolve/spec_documents.dart';
 import '../resolve/spec_model.dart';
 import '../resolve/spec_reader.dart';
 import 'normalizer_rule.dart';
+import 'rules/bool_required_to_array.dart';
+import 'rules/drop_invalid_default.dart';
 import 'spec_edit.dart';
 
 /// The result of normalizing a spec.
@@ -50,7 +52,10 @@ final class Normalizer {
   /// Every rule, in the order it runs; an earlier rule's fix wins a
   /// conflict.
   static final List<NormalizerRule> rules = List.unmodifiable(
-    <NormalizerRule>[],
+    <NormalizerRule>[
+      const BoolRequiredToArray(),
+      const DropInvalidDefault(),
+    ],
   );
 
   /// The names of [rules].
```

- [ ] **Step 6: Перевірити**

Run (`dart analyze` — з кореня, решта — з `packages/typed_openapi`):

```bash
dart analyze packages                 # No issues found!
dart test                             # All tests passed!
dart format lib test bin && dart format lib test bin   # the second run: 0 changed
```

- [ ] **Step 7: Коміт**

```bash
git add packages/typed_openapi
git commit -m "feat(typed_openapi): fix boolean required and defaults of the wrong type

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Конфіг `rules` і `check` через нормалізатор

**Files:**
- Modify: `packages/typed_openapi/lib/src/config/config_loader.dart`, `packages/typed_openapi/lib/src/config/project_config.dart`, `packages/typed_openapi/lib/src/check/spec_checker.dart`, `packages/typed_openapi/test/config/config_loader_test.dart`, `packages/typed_openapi/test/check/spec_checker_test.dart`

**Interfaces:**
- Consumes: `Normalizer`, `Normalizer.ruleNames` (задачі 4–5).
- Produces: `ClientConfig.disabledRules`; ключ `rules` у `defaults` і клієнті; `SpecChecker.check` нормалізує кожну специфікацію з правилами й пресетом клієнта.

- [ ] **Step 1: Тести**

Тести — у diff-ах кроку 2 (`config_loader_test.dart`) і кроку 3 (`spec_checker_test.dart`); застосуй спершу лише тестові частини і переконайся, що вони падають (`dart test test/config test/check` — FAIL: `rules` — невідомий ключ, `check` не дає TOA201).

- [ ] **Step 2: `ConfigLoader` і його тести**

```diff
diff --git a/packages/typed_openapi/lib/src/config/config_loader.dart b/packages/typed_openapi/lib/src/config/config_loader.dart
--- a/packages/typed_openapi/lib/src/config/config_loader.dart
+++ b/packages/typed_openapi/lib/src/config/config_loader.dart
@@ -6,6 +6,7 @@ import 'package:source_span/source_span.dart';
 import '../diagnostics/diagnostic_bag.dart';
 import '../diagnostics/json_pointer.dart';
 import '../load/yaml_composer.dart';
+import '../normalize/normalizer.dart';
 import 'project_config.dart';
 
 /// Reads `typed_openapi.yaml` into a [ProjectConfig].
@@ -17,7 +18,7 @@ final class ConfigLoader {
   const ConfigLoader(this._diagnostics);
 
   static const _topLevelKeys = {'defaults', 'clients'};
-  static const _defaultsKeys = {'preset', 'line_width'};
+  static const _defaultsKeys = {'preset', 'line_width', 'rules'};
   static const _clientKeys = {
     'input',
     'output',
@@ -25,6 +26,7 @@ final class ConfigLoader {
     'overrides',
     'baseline',
     'line_width',
+    'rules',
   };
 
   final DiagnosticBag _diagnostics;
@@ -79,10 +81,12 @@ final class ConfigLoader {
     final defaults = reader.mapAt(root, 'defaults', .root);
     Preset? defaultPreset;
     int? defaultWidth;
+    var defaultRules = const <String, bool>{};
     if (defaults != null) {
       reader.checkKeys(defaults, _defaultsKeys, defaultsPointer);
       defaultPreset = reader.presetAt(defaults, defaultsPointer);
       defaultWidth = reader.intAt(defaults, 'line_width', defaultsPointer);
+      defaultRules = reader.rulesAt(defaults, defaultsPointer);
     }
 
     final clientsPointer = JsonPointer.root.child('clients');
@@ -116,6 +120,7 @@ final class ConfigLoader {
           ClientConfig.defaultLineWidth;
       final overrides = reader.stringAt(value, 'overrides', pointer);
       final baseline = reader.stringAt(value, 'baseline', pointer);
+      final rules = {...defaultRules, ...reader.rulesAt(value, pointer)};
       if (input == null || output == null) continue;
       outputSpans[name] = reader.spanAt(pointer.child('output'));
       clients.add(
@@ -127,6 +132,10 @@ final class ConfigLoader {
           preset: preset,
           overrides: overrides == null ? null : resolve(overrides),
           baseline: baseline == null ? null : resolve(baseline),
+          disabledRules: {
+            for (final MapEntry(:key, :value) in rules.entries)
+              if (!value) key,
+          },
         ),
       );
     }
@@ -268,6 +277,38 @@ class _ConfigReader {
     return null;
   }
 
+  /// `rules` of [parent]: normalizer rule names mapped to whether they run.
+  /// Unknown names are reported and skipped.
+  Map<String, bool> rulesAt(Map<String, Object?> parent, JsonPointer at) {
+    final rules = mapAt(parent, 'rules', at);
+    if (rules == null) return const {};
+    final pointer = at.child('rules');
+    final known = Normalizer.ruleNames;
+    final result = <String, bool>{};
+    for (final MapEntry(key: name, :value) in rules.entries) {
+      if (!known.contains(name)) {
+        diagnostics.report(
+          .configUnknownKey,
+          'Unknown normalizer rule "$name".',
+          file: file,
+          pointer: pointer.child(name),
+          span: spanAt(pointer.child(name)),
+          fix: 'Known rules: ${(known.toList()..sort()).join(', ')}.',
+        );
+        continue;
+      }
+      if (value is! bool) {
+        invalid(
+          'Rule "$name" must be true or false.',
+          pointer.child(name),
+        );
+        continue;
+      }
+      result[name] = value;
+    }
+    return result;
+  }
+
   Preset? presetAt(Map<String, Object?> parent, JsonPointer at) {
     final name = stringAt(parent, 'preset', at);
     if (name == null) return null;
diff --git a/packages/typed_openapi/test/config/config_loader_test.dart b/packages/typed_openapi/test/config/config_loader_test.dart
--- a/packages/typed_openapi/test/config/config_loader_test.dart
+++ b/packages/typed_openapi/test/config/config_loader_test.dart
@@ -114,6 +114,45 @@ clients:
     expect(bag.all.single.span, isNotNull);
   });
 
+  test('reads rules from defaults and clients; a client overrides', () {
+    final path = TempDir().write('c.yaml', '''
+defaults:
+  rules: {bool-required-to-array: false, drop-invalid-default: false}
+clients:
+  a: {input: a.json, output: lib/a}
+  b:
+    input: b.json
+    output: lib/b
+    rules: {drop-invalid-default: true}
+''');
+    final bag = DiagnosticBag();
+    final clients = ConfigLoader(bag).load(path)!.clients;
+    expect(bag.all, isEmpty);
+    expect(clients.first.disabledRules, {
+      'bool-required-to-array',
+      'drop-invalid-default',
+    });
+    expect(clients.last.disabledRules, {'bool-required-to-array'});
+  });
+
+  test('an unknown rule name is a warning; a value that is not a boolean '
+      'is an error', () {
+    final path = TempDir().write('c.yaml', '''
+clients:
+  a:
+    input: a.json
+    output: lib/a
+    rules: {bool-required: false, drop-invalid-default: off}
+''');
+    final bag = DiagnosticBag();
+    expect(ConfigLoader(bag).load(path)!.clients.single.disabledRules, isEmpty);
+    expect(bag.all.map((d) => (d.code, d.pointer?.value)), [
+      (DiagnosticCode.configUnknownKey, '#/clients/a/rules/bool-required'),
+      (DiagnosticCode.configInvalid, '#/clients/a/rules/drop-invalid-default'),
+    ]);
+    expect(bag.all.first.fix, contains('bool-required-to-array'));
+  });
+
   test('accepts an alias in a value', () {
     final path = TempDir().write('typed_openapi.yaml', '''
 clients:
```

- [ ] **Step 3: `ClientConfig`, `SpecChecker` і тест**

```diff
diff --git a/packages/typed_openapi/lib/src/check/spec_checker.dart b/packages/typed_openapi/lib/src/check/spec_checker.dart
--- a/packages/typed_openapi/lib/src/check/spec_checker.dart
+++ b/packages/typed_openapi/lib/src/check/spec_checker.dart
@@ -4,7 +4,7 @@ import '../config/project_config.dart';
 import '../diagnostics/diagnostic_bag.dart';
 import '../load/openapi_version.dart';
 import '../load/spec_loader.dart';
-import '../resolve/spec_reader.dart';
+import '../normalize/normalizer.dart';
 
 /// Loads every client's spec and reports what is wrong with it.
 ///
@@ -19,14 +19,14 @@ final class SpecChecker {
   /// Checks the spec of every client in [config].
   ///
   /// Each spec is loaded, its OpenAPI version detected, and then it is read
-  /// into the model with its `$ref`s resolved. [only] limits the run to
+  /// into the model with its `$ref`s resolved and normalized with the
+  /// client's rules and preset. [only] limits the run to
   /// clients with these names; empty means all. A file shared by several
   /// clients is checked once. Spec paths in diagnostics are relative to the
   /// config file's directory.
   void check(ProjectConfig config, {Set<String> only = const {}}) {
     final loader = SpecLoader(_diagnostics);
     final detector = OpenApiVersionDetector(_diagnostics);
-    final reader = SpecReader(_diagnostics);
     final configDir = p.dirname(p.absolute(config.file));
     final checked = <String>{};
     for (final client in config.clients) {
@@ -39,7 +39,11 @@ final class SpecChecker {
       if (document == null) continue;
       final version = detector.detect(document);
       if (version == null) continue;
-      reader.read(document, version);
+      Normalizer(
+        _diagnostics,
+        disabled: client.disabledRules,
+        preset: client.preset,
+      ).normalize(document, version);
     }
   }
 }
diff --git a/packages/typed_openapi/lib/src/config/project_config.dart b/packages/typed_openapi/lib/src/config/project_config.dart
--- a/packages/typed_openapi/lib/src/config/project_config.dart
+++ b/packages/typed_openapi/lib/src/config/project_config.dart
@@ -27,6 +27,7 @@ final class ClientConfig {
     this.preset,
     this.overrides,
     this.baseline,
+    this.disabledRules = const {},
   });
 
   /// Line width of generated code when the config does not set one.
@@ -52,6 +53,9 @@ final class ClientConfig {
 
   /// Absolute path of the baseline file.
   final String? baseline;
+
+  /// Normalizer rules the config turns off for this client, by name.
+  final Set<String> disabledRules;
 }
 
 /// The parsed `typed_openapi.yaml`.
diff --git a/packages/typed_openapi/test/check/spec_checker_test.dart b/packages/typed_openapi/test/check/spec_checker_test.dart
--- a/packages/typed_openapi/test/check/spec_checker_test.dart
+++ b/packages/typed_openapi/test/check/spec_checker_test.dart
@@ -32,6 +32,36 @@ clients:
     );
   });
 
+  test('normalizes each spec with the client\'s rules', () {
+    final dir = TempDir();
+    const spec = '''
+openapi: 3.0.3
+info: {title: t, version: "1"}
+components:
+  schemas:
+    Tag:
+      type: object
+      properties:
+        name: {type: string, required: true}
+''';
+    dir.write('a.yaml', spec);
+    dir.write('b.yaml', spec);
+    final path = dir.write('typed_openapi.yaml', '''
+clients:
+  a: {input: a.yaml, output: lib/a}
+  b:
+    input: b.yaml
+    output: lib/b
+    rules: {bool-required-to-array: false}
+''');
+    final bag = DiagnosticBag();
+    SpecChecker(bag).check(ConfigLoader(bag).load(path)!);
+    expect(bag.all.map((d) => (d.code, d.file)), [
+      (DiagnosticCode.boolRequired, 'a.yaml'),
+      (DiagnosticCode.invalidValue, 'b.yaml'),
+    ]);
+  });
+
   test('only checks the named clients', () {
     final dir = TempDir();
     final path = dir.write('typed_openapi.yaml', '''
```

- [ ] **Step 4: Перевірити**

Run (`dart analyze` — з кореня, решта — з `packages/typed_openapi`):

```bash
dart analyze packages                 # No issues found!
dart test                             # All tests passed!
dart format lib test bin && dart format lib test bin   # the second run: 0 changed
```

Expected: 282 тести.

- [ ] **Step 5: Прогін корпусу (smoke)**

```bash
cd packages/typed_openapi
dart run bin/typed_openapi.dart check -c <path to the research/08 corpus>/typed_openapi.yaml --format json > /tmp/m3-check.json; echo "exit $?"
```

Expected: exit 1 (TOA009 — error); підсумок за файлом і кодом (стан після задачі 6, під час написання плану):

| Специфікація | Діагностика |
|---|---|
| Artemis | TOA009 ×2 (`example: !!timestamp …`), TOA110 ×1 — тепер читається (у M2 — TOA001, файл не читався) |
| DigitalOcean | TOA107 ×793 (у M2 — TOA110 ×791, TOA111 ×2) |
| Grace (джерело і бандл — ті самі файли) | TOA108 ×13, TOA111 ×19, TOA110 ×4, TOA021 ×2 |
| OpenAI | TOA021 ×1, TOA110 ×1 |
| Stripe, Discord, Medusa, Airflow, Tambo, Jellyfin, Ditto, Google Maps, EFGS | — |

TOA201 і TOA211 у корпусі не трапляються (C-1 у цільових фреймворках за замовчуванням не відтворюється). Правила задач 7–11 додадуть свої коди до цієї таблиці.

- [ ] **Step 6: Коміт**

```bash
git add packages/typed_openapi
git commit -m "feat(typed_openapi): run the normalizer in check, with rules toggled in the config

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Ненаписані задачі (бюджет плану вичерпано)

Задачі нижче не мають перевіреного коду, тому тут лише їхній обсяг; кожну треба розписати й перевірити так само, як задачі 1–6, перш ніж виконувати. Порядок — як у брифі.

- **Task 7: Схеми масивів і об'єктів (лише діагностика).** TOA202 масив без `items` у документі 3.0 (C-5; пропозиція override `items`), TOA203 подвійний масив з булевим `required` в `items` (C-49; override `items` → `items.items`), TOA204 `format` на масиві без `items` (C-50; override `items: {type: string, format: <f>}`, TOA202 тоді не дублюється), TOA205 `type: object` + `format: binary` (C-51; override `type: string`), TOA206 `type: object` поряд з `oneOf`/`anyOf` без жодної об'єктної гілки (C-22), TOA207 JSON-тип `example` суперечить `type` (C-60; override `type: array` чи `object`). Підказка `nestjs` для TOA202/TOA203: `@ApiProperty({ type: [Item] })` без `isArray` (research/06 §D.1, п. 6).
- **Task 8: Enum.** Виправлення `dedupe-enum-values` TOA301 (C-9, C-52: JSON-рівні дублікати, лишається перше входження, регістр не зливається; правка `replace` цілого `enum`), діагностика TOA303 nullable enum через `oneOf` з `{enum: [null]}` + `$ref` (C-54). Підказки `nestjs`: `enumName`/`autoFillEnumName` (§D.1, п. 1), для TOA303 — `@nestjs/swagger` ≥ 12 (§D.1, п. 3).
- **Task 9: Path-параметри.** Виправлення `declare-missing-path-params` TOA501 (C-6: `{name, in: path, required: true, schema: {type: string}}`, правка `add` у `parameters/-` операції, з урахуванням параметрів path item і `$ref`-параметрів) і діагностика TOA502 (C-7: оголошено, але немає в шаблоні, або інший регістр).
- **Task 10: `operationId`.** TOA503 info — немає `operationId` (C-34), TOA504 error — однакові (C-36), детерміновано за `SpecLocation`. Підказки: `aspnet` — `.WithName(...)`/`[EndpointName]`/Swashbuckle `CustomOperationIds` (§D.4); `nestjs` — `operationIdFactory` (§D.1, п. 2); `fastapi` — `generate_unique_id_function` (§D.2, п. 1); `springdoc` — явний `@Operation(operationId = ...)` (§D.3, п. 2).
- **Task 11: Дискримінатор, media types, ключі components.** TOA401 info — властивість-дискримінатор не `required` у підсхемах (C-42), TOA402 error — `discriminator.mapping` веде в нікуди (M2 mapping не резолвить, перевірено: `Discriminator.mapping` лише читається), TOA601 — `*/*` (C-38; `springdoc.default-produces-media-type=application/json`, §D.3), TOA106 — ключ components не відповідає `^[a-zA-Z0-9\.\-_]+$` (C-32; `aspnet` — `CustomSchemaIds(... Replace('+', '.'))`, §D.4; `springdoc` — `@Schema(name)`/`use-fqn`, §D.3).
- **Task 12: Підказки пресетів і документація.** Звести підказки пресетів у правилах задач 5–11 (рецепти — лише з research/06 §D); `CLAUDE.md` (розділ Architecture: `load/yaml/`, `YamlComposer`, `normalize/`; прибрати `NestingScanner`/`YamlEventGuard`, оновити перелік експорту), `CHANGELOG.md`, абзац про `check` у `README.md`/`README.ua.md`; експорт `Normalizer`, `NormalizerRule`, `RuleContext`, `Finding`, `SpecEdit` з `lib/typed_openapi.dart`; повторити smoke-прогін корпусу і записати підсумкову таблицю в research/08.

## Самоперевірка

- **Покриття специфікації.** Рішення 2 (теги — задача 1; `$ref` поза OAS — задача 3), 3 (правила над моделлю, `SpecEdit`, ≤ 3 проходи — задача 4), 4 (діагностика парсера з останнього проходу — задача 4), 6 (свій компоновщик: глибина, бюджет, дублікати, теги, нерядкові ключі; `_toPlain` і перевірка за подіями зникають — задачі 1–2), 7 (пресети лише уточнюють підказки — `NormalizerRule.hint`, задача 4; вимикання правил у конфігу і TOA903 — задача 6). Таблиця «Виправлення»: `bool-required-to-array`, `drop-invalid-default` — задача 5; `dedupe-enum-values`, `declare-missing-path-params` — ненаписані задачі 8–9. Таблиця «Лише діагностика»: TOA107, TOA108, TOA009, TOA014 — задачі 1, 3; решта — ненаписані задачі 7–11. Рішення 1 і 5 — обмеження для всіх правил (Global Constraints).
- **Заглушки.** Задачі 1–6 містять увесь код (нові файли повністю, зміни — diff-ами, які застосовує `git apply`); ненаписані задачі винесено окремо й позначено.
- **Узгодженість типів.** `SpecLocation.child`, `RuleContext.finding`, `SpecEdit.add/replace/remove`, `Normalizer(bag, rules:, disabled:, preset:)`, `ClientConfig.disabledRules` — однакові в задачах 4–6 і тестах.

## Відкриті питання до користувача

1. **Ключі-числа і `null`.** Таблиця специфікації називає «число, null» нерядковими ключами (TOA00x, error). План читає скалярні ключі як текст (Failsafe, як вимагає OAS), бо `200:` у `responses` — поширений запис і наявний тест M2 закріплює його як валідний. Робити `200:`/`~:` помилкою (або warning з порадою взяти в лапки)?
2. **`AssertionError`.** Бриф каже «ловити лише `YamlException`». Гарантувати, що assert сканера не вилетить у checked-режимі, без вузького `catch (AssertionError)` неможливо (рішення 3). Залишити вузький catch, чи прибрати сам assert у скопійованому сканері (третя правка копії)?
3. **Номер коду нерядкового ключа:** TOA014 (рішення 1) — підходить?
4. **YAML-дублікати як error з відмовою читати документ** (поведінка M1–M2, рішення 5) — лишаємо, чи переводимо на warning «перемагає останнє», як для JSON, щоб показати решту проблем файлу (R2.5)?
5. **`warn()` у скопійованому сканері/парсері** друкує в stdout (невідома директива `%FOO`, `%YAML 1.3`), що псує `--format json`. Це поведінка `package:yaml` і в M2; виправити в копії (діагностика або тиша)?
6. **Merge key `<<`** (відкладено з M2 у M3): у брифі його немає, план не додає підказки. Додати окреме правило/діагностику?

