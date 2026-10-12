# План M5: baseline, рівні і формати звіту

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `typed_openapi check` називає файли відносно робочого каталогу, бере рівні кодів із конфігу (`severity`, зокрема `off`), ховає знахідки, зафіксовані в baseline клієнта (`baseline create` / `baseline prune`, fingerprint без тексту й без індексів, де місце адресовне), звітує про застарілі записи, друкує звіт ще й у форматах `sarif` і `github-actions`, показує override, який вніс проблему, другою позицією і не губить підказку пресету другого клієнта.

**Architecture:** `DisplayPaths` (diagnostics/) — одна політика імен файлів для конфігу, специфікацій, файлів за `$ref`, override-ів і baseline. `SeverityLevels` застосовує рівні клієнта після прогону: `SpecChecker.checkClients` перевіряє кожен прогін (файл, пресет, правила, override-и) один раз і повертає `ClientCheck` на клієнта з його рівнями й `AnchorIndex` моделі. Новий шар `lib/src/baseline/`: `AnchorIndex` (логічні адреси вузлів за зворотною адресацією M4), `Fingerprints` (якір і `sha256([code, anchor, args])[:12]`), `Baseline` / `BaselineMatch` (зіставлення, prune, YAML) і `BaselineLoader`; `SpecChecker.check` зіставляє, а `DiagnosticBag` тримає прийняті діагностики окремо. `SarifReporter` і `GitHubActionsReporter` поряд із `TextReporter` / `JsonReporter`; `Diagnostic.related` — друга позиція (override), `Diagnostic.hints` — підказки пресетів, які дедуп зливає.

**Tech Stack:** Dart `>=3.10.0 <4.0.0`, чистий Dart; нова пряма залежність `crypto: ^3.0.6` (SHA-256, dart-lang); тести на `package:test`.

**Spec:** [docs/superpowers/specs/2026-10-12-m5-baseline-severity-design.md](../specs/2026-10-12-m5-baseline-severity-design.md) — рішення 1–8. Вимоги: R2.2 (рівні в конфігу, формати), R2.3 (baseline / ratchet) ([requirements.md](../../requirements.md)). Дослідження: [research/README](../../research/README.md), рядки R2.2 і R2.3 (fingerprint як в oasdiff, `count` як стеля і `baseline prune` як в ESLint bulk suppressions, формати Redocly / Spectral). Перенесене: [roadmap](../../roadmap.md), рядки «Перенесено з M1/M2/M3/M4» з позначкою M5. Правила коду — [CLAUDE.md](../../../CLAUDE.md).

## Global Constraints

- SDK `>=3.10.0 <4.0.0`; обидва пакети — чистий Dart. Primary constructors (Dart 3.13) не використовуються.
- Dart 3.10 активно: dot shorthands скрізь, де відомий тип контексту (`.baselineEntryStale`, `severity: .error`), null-aware елементи колекцій (`?client.severity.apply(d)`), switch-вирази і patterns, records, модифікатори класів (`final`, `sealed`). У тестах аргументи `expect(...)` — повні імена (`DiagnosticCode.invalidBaseline`).
- ООП: жодних функцій верхнього рівня, крім `main` у `bin/` і тестах. Компоненти, що звітують, отримують `DiagnosticBag` через конструктор (`BaselineLoader(bag)`, `SpecChecker(bag, paths)`, `ConfigLoader(bag, paths)`).
- Помилки вхідних даних (специфікація, конфіг, файл override-ів, файл baseline) не кидаються: вони йдуть у `DiagnosticBag`, решта читається. Запис файлу, що не вдався, — діагностика (TOA823), а не виняток.
- Кожен новий код — у `DiagnosticCode` з doc-коментарем, slug у kebab-case, рівень за замовчуванням.
- Детермінізм (R13.1): звіт сортує `DiagnosticBag.sorted`; записи baseline — за кодом, якорем, fingerprint; прогони — у порядку клієнтів; rules у SARIF — за id.
- Error — лише для справжніх помилок (відсутній чи непридатний файл baseline, невалідний запис, рівень, якого код не може мати); застарілий запис — warning (error лише з `--strict-baseline`), невідомий ключ у baseline і повтор fingerprint — warning.
- Негативні тести на валідних входах: валідний `severity` — жодної діагностики; baseline, що збігається з усім, — порожній звіт; записаний `baseline create` файл читається без діагностик; проблема, яка була в специфікації до override-у, і проблема деінде — без другої позиції.
- Фікстури — вигадані й маленькі. Приватна специфікація компанії не використовується ні як фікстура, ні як джерело фікстур. Публічний корпус — лише для прогону `check`.
- Лінти з кореневого `analysis_options.yaml`; `dart analyze packages` з кореня — `No issues found!`; `dart format lib test bin` (з `packages/typed_openapi`) — другий запуск змінює 0 файлів.
- Тести не ходять у мережу; тимчасові файли — лише через `test/helpers/temp_dir.dart`. Робочий каталог процесу тести не змінюють: його задає `DisplayPaths(dir.path)` / `TypedOpenApiCli(workingDirectory:)`.
- Команди `dart test`, `dart format` — з `packages/typed_openapi`; `dart pub get`, `dart analyze packages`, `git apply` і `git` — з кореня репозиторію. Diff-и в плані застосовуються `git apply` (з кореня), нові файли створюються з блоків цілком.
- Кожен коміт — Conventional Commits і закінчується рядком `Co-Authored-By` моделі, що виконує задачу (у прикладах — `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`).

## Ухвалені рішення

Рішення специфікації M5 — обов'язкові. Тут — те, що специфікація лишає планові (технічні рішення); питання формату, які бачить користувач, винесено в «Відкриті питання» наприкінці і реалізовано в запропонованому вигляді.

1. **Робочий каталог** (spec, рішення 7). `DisplayPaths(workingDirectory)`: файл усередині — відносний шлях, поза ним — абсолютний. Його отримують `ConfigLoader` (шлях конфігу з `--config` читається відносно нього), `SpecChecker` (специфікація, override-и, baseline) і CLI (`TypedOpenApiCli(workingDirectory:)`, за замовчуванням — каталог процесу). Файли за `$ref` іменує `SpecDocuments.displayPath` тим самим правилом без нового параметра: ім'я кореневого документа вже відносне до робочого каталогу, тож шлях, що виходить за нього (`..` на початку), стає абсолютним, а абсолютне ім'я кореня дає абсолютні імена. Повідомлення TOA804 про булеву схему більше не друкує `file:///`.
2. **Рівні застосовуються після прогону, на клієнта** (spec, рішення 5). Ключ прогону лишається (файл, пресет, вимкнені правила, override-и): рівень не змінює того, що прогін знаходить, лише як це звітується, тож спільна специфікація не перечитується через різні рівні. `checkClients` дає кожному клієнтові діагностики його прогону з його `SeverityLevels`; `off` — діагностики немає. Два клієнти з різними рівнями одного коду дають дві діагностики (різний `severity` — різний ключ дедупу).
3. **Незмінні коди** (`DiagnosticCode.fixedCodes`): без них документ не прочитати — TOA001, TOA003, TOA004, TOA006, TOA007, TOA008, TOA010, TOA011; файл override-ів — TOA801–TOA809; baseline — TOA820–TOA823; конфіг — TOA901–TOA904 (`configCodes`). Їх можна підняти (`TOA804: error`), але не знизити й не вимкнути — TOA902, значення ігнорується. Коди конфігу не змінюються зовсім (TOA902): конфіг читається до того, як рівні відомі. Невідомий код чи slug — TOA903 (як невідоме правило); рівень не з `error|warning|info|off` — TOA902; код, названий двічі (`TOA201` і `bool-required`), — TOA902 на другому, діє перший. Клієнт перекриває `defaults` поіменно — за кодом, а не за написанням ключа.
4. **Fingerprint** (spec, рішення 2): перші 12 hex SHA-256 від JSON-масиву `[code, anchor, args]` — JSON замість `|`, щоб `|` в якорі чи аргументі не дав колізії. `args` — `Diagnostic.args`: значення зі специфікації, що розрізняють дві знахідки одного коду в одному місці; у M5 — ім'я відсутнього поля TOA112. Решта кодів має аргументи в pointer-і; однакові fingerprint-и рахує `count` (стеля, як в ESLint).
5. **Якір.** `AnchorIndex` будується з моделі останнього проходу нормалізатора: операція — `operations` + `METHOD /path` (метод великими літерами; завжди однозначна, на відміну від `operationId`), параметр, який операція визначає сама, — `parameters` + `in:name`, схема — `schemas` + ключ `components.schemas` (ключ-визначення має перевагу над ключем-аліасом, як в `OverrideSnippet`), властивість — `properties` + ім'я. Діагностика бере найближчий адресовний вузол на шляху свого pointer-а, решта pointer-а — хвіст: `@/schemas/Tag/properties/name#/required`. Без адреси — `файл#pointer`, файл відносно каталогу файлу baseline у формі з `/`: `api.yaml#/info`. Параметри рівня шляху, вебхуки, `additionalOperations` адреси не мають. Pointer-и правил указують на дерево до правок; зсув індексів від правок нормалізатора не враховується (правки додають у кінець списків).
6. **Зіставлення.** Діагностики клієнта (з його рівнями) сортуються; запис приймає до `count` діагностик зі своїм fingerprint, решта показується. Коди `fixedCodes` baseline не приймає ніколи (і `baseline create` їх не записує). Запис, що прийняв менше за `count` (зокрема 0), — TOA822 у позиції запису з підказкою `baseline prune`; рівні клієнта діють і на діагностики baseline. `prune` прибирає записи без знахідок, зменшує `count` до знайденого і нічого не додає; `create` переписує файл з нуля.
7. **Відсутній файл baseline — помилка TOA820**, як TOA801 для override-ів (M4, рішення 10): шлях з одруком інакше мовчки показав би все як нове, а R2.5 забороняє мовчазні здогадки. `check` тоді показує всі знахідки клієнта. Файл створює `baseline create`, якому відсутній файл не заважає. Порожній файл (лише коментарі) — baseline без записів, без діагностики. Два клієнти з одним файлом baseline — TOA902 (кожен baseline пишеться з діагностик одного клієнта).
8. **Прийняті діагностики** зберігає `DiagnosticBag.addBaselined` окремо від `all`: `count`, `hasErrors` і код виходу їх не бачать. Звіти отримують `showBaselined`: text — `[baselined]` після slug і `, baselined: N` у рядку підсумку, коли N > 0; JSON — `"baselined": bool` у кожній діагностиці і `summary.baselined` завжди; SARIF — `suppressions: [{kind: external}]`; github-actions — `::notice` з `(baselined)` у title.
9. **Друга позиція override-у** (`Diagnostic.related`, `RelatedLocation`). Проблема «внесена override-ом», якщо її (код, файл, pointer) не було у специфікації, як її прочитано до override-ів (діагностики читання і знахідки правил на моделі до правок), і застосований override змінив член її вузла, вузла всередині чи вузла навколо (порівнюється батьківський pointer правки: TOA205 указує на `/type`, override змінює `/format` того самого об'єкта). Повідомлення — `Introduced by this override.`, позиція — поле override-у.
10. **Підказки пресетів** (`Diagnostic.hints`) зберігаються окремо від `fix`; `fix` — геттер `fix + hints`. `DiagnosticBag` при дублікаті додає нові підказки до наявної діагностики, а не губить їх і не дублює знахідку: одна проблема — один рядок звіту, з підказками всіх пресетів, у порядку клієнтів. Альтернатива «`fix` у ключі дедупу» дала б два однакові рядки без пояснення, якому клієнту який належить.
11. **SARIF 2.1.0**: один `run` з `tool.driver` (`name`, `informationUri`, `rules` — лише коди, що трапились, за id, з `name` = slug і `defaultConfiguration.level`), `ruleIndex`, рівні `error`/`warning`/`note`, `message.text` = повідомлення + `\nFix: …`, `physicalLocation` (відносний URI-reference з `/` і percent-кодуванням або `file:` URI для файлу поза робочим каталогом; `region` 1-based з кінцем), `logicalLocations` з pointer-ом, `relatedLocations` з `id` від 1. Діагностика без файлу й pointer-а — `locations: []`. Перевірка схеми — тестом без мережі (обов'язкові поля, enum-и, індекси, URI).
12. **github-actions**: рядок `::error|warning|notice file=…,line=…,col=…,endLine=…,endColumn=…,title=TOAnnn slug::повідомлення%0Aat pointer%0Afix: …` з екрануванням раннера (`%`, CR, LF; у властивостях ще `:` і `,`), related — окремий `::notice` з `(related)`, наприкінці — рядок підсумку тексту.
13. **Коди TOA820–TOA823** (діапазон після override-ів; TOA9xx — конфіг).

**Відкладено.** `junit` і baseline для `generate` (spec, «Що не входить»). Аргументи fingerprint для інших кодів, де кілька знахідок ділять pointer, — коли знадобиться (зараз їх обмежує `count`). Адреси для параметрів рівня шляху, вебхуків і `additionalOperations` — разом з адресацією M6.

## Нові коди діагностики

| Код | Slug | Рівень | Коли | Задача | Spec |
|---|---|---|---|---|---|
| TOA820 | `baseline-not-found` | error | Файлу baseline, який указує клієнт, немає (`check`, `prune`) | 4 | рішення 1 |
| TOA821 | `invalid-baseline` | error (warning — невідомий ключ, повтор fingerprint) | Файл не читається, `version` не 1, `entries` не список, запис без fingerprint чи з поганим `count`; запис ігнорується | 4 | рішення 1 |
| TOA822 | `baseline-entry-stale` | warning (error з `--strict-baseline`) | Запис приймає більше діагностик, ніж знайдено; підказка `baseline prune` | 4 | рішення 4 |
| TOA823 | `baseline-not-written` | error | `baseline create` / `prune` не змогли записати файл | 4 | — |

## Файли

Шляхи відносно `packages/typed_openapi/`.

| Файл | Відповідальність | Задача |
|---|---|---|
| `lib/src/diagnostics/display_paths.dart` | `DisplayPaths`: імена файлів відносно робочого каталогу | 1 |
| `lib/src/config/config_loader.dart`, `lib/src/check/spec_checker.dart`, `lib/src/cli/*.dart`, `lib/src/resolve/spec_documents.dart` | робочий каталог; `severity`; спільний baseline; `checkClients`, зіставлення; прапорці й команди | 1, 2, 4 |
| `lib/src/diagnostics/severity_levels.dart`, `diagnostic_code.dart` | `SeverityLevels`; `fixedCodes`, `configCodes`; TOA820–TOA823 | 2, 4 |
| `lib/src/baseline/anchor_index.dart`, `fingerprints.dart` | логічні адреси, якорі, fingerprint | 3 |
| `lib/src/diagnostics/diagnostic.dart`, `diagnostic_bag.dart`, `lib/src/parse/*.dart` | `args`, `related`, `hints`, `addBaselined`, злиття підказок | 3–6 |
| `lib/src/baseline/baseline.dart`, `baseline_loader.dart`, `lib/src/cli/baseline_command.dart` | модель і файл baseline, `baseline create` / `prune` | 4 |
| `lib/src/diagnostics/reporters.dart`, `sarif_reporter.dart`, `github_actions_reporter.dart` | `showBaselined`, `related`, нові формати, `ReportFormat.option` | 4, 5 |
| `lib/src/normalize/normalizer.dart` | друга позиція override-у, підказки як `hints` | 6 |
| `lib/typed_openapi.dart`, `CLAUDE.md`, `CHANGELOG.md`, `README.md`, `README.ua.md` | експорт і документація | 7 |

## Інтерфейси між задачами

```dart
// diagnostics/display_paths.dart (Task 1)
final class DisplayPaths { const DisplayPaths([String? workingDirectory]);
  String get workingDirectory; String absolute(String path); String of(String path); }
const ConfigLoader(DiagnosticBag, [DisplayPaths paths = const DisplayPaths()]);
const SpecChecker(DiagnosticBag, [DisplayPaths paths = const DisplayPaths()]);
TypedOpenApiCli({StringSink? out, StringSink? err, String? workingDirectory});

// diagnostics/severity_levels.dart, diagnostic_code.dart, config (Task 2)
final class SeverityLevels { const SeverityLevels([Map<DiagnosticCode, Severity?> levels]);
  Map<DiagnosticCode, Severity?> levels; Diagnostic? apply(Diagnostic); } // null = off
static const Set<DiagnosticCode> DiagnosticCode.fixedCodes, DiagnosticCode.configCodes;
Diagnostic Diagnostic.withSeverity(Severity);
SeverityLevels ClientConfig.severity;

// baseline/ (Task 3)
List<String> Diagnostic.args;                              // DiagnosticBag.report(args:), ParseContext.report(args:)
final class AnchorIndex { AnchorIndex(SpecModel, SpecDocuments); AnchorIndex.none();
  (List<String>, JsonPointer)? addressOf(String file, JsonPointer pointer); }
final class Fingerprints { Fingerprints(AnchorIndex, String baselineFile, [DisplayPaths]);
  static const length = 12; String of(Diagnostic); String anchorOf(Diagnostic);
  static String hash(DiagnosticCode, String anchor, List<String> args); }

// baseline/, check, cli (Task 4)
final class BaselineEntry { fingerprint; String? code, anchor, message; int count; JsonPointer pointer; }
final class BaselineMatch { List<Diagnostic> shown, baselined; List<(BaselineEntry, int)> stale; }
final class Baseline { const Baseline(String file, List<BaselineEntry>, {SpecDocument? source});
  factory Baseline.of(String file, Iterable<Diagnostic>, Fingerprints); static const version = 1;
  BaselineMatch match(Iterable<Diagnostic>, Fingerprints); Baseline pruned(BaselineMatch);
  String toYaml(); SourceSpan? spanOf(JsonPointer); }
final class BaselineLoader { const BaselineLoader(DiagnosticBag);
  Baseline? load(String path, {String? displayPath}); Baseline? parse(String text, String file, {Uri? uri}); }
final class ClientCheck { ClientConfig client; List<Diagnostic> diagnostics; AnchorIndex anchors;
  Fingerprints fingerprints(String baselineFile, DisplayPaths); }
List<ClientCheck> SpecChecker.checkClients(ProjectConfig, {Set<String> only});
void SpecChecker.check(ProjectConfig, {Set<String> only, bool strictBaseline = false});
void DiagnosticBag.addBaselined(Diagnostic); List<Diagnostic> DiagnosticBag.baselined;
String DiagnosticReporter.format(DiagnosticBag, {bool showBaselined = false});

// diagnostics (Task 5)
final class RelatedLocation { const RelatedLocation({required String message, String? file,
  JsonPointer? pointer, SourceSpan? span}); String? get location; }
List<RelatedLocation> Diagnostic.related; static String TextReporter.summary(DiagnosticBag);
final class SarifReporter; final class GitHubActionsReporter;
enum ReportFormat { text, json, sarif, githubActions; String option; static ReportFormat byOption(String); }

// diagnostics, normalize (Task 6)
List<String> Diagnostic.hints; String? get Diagnostic.fix;   // fix + hints
Diagnostic Diagnostic.withHints(List<String>); Diagnostic Diagnostic.withRelated(List<RelatedLocation>);
```

Кожну задачу перевірено так: код зібрано й перевірено на окремій гілці, потім задачі 1–7 відтворено з `main` (ea04ebe) лише з блоків коду цього плану (створення файлів, `git apply` diff-ів), і після кожної задачі `dart analyze packages` чистий, `dart format` удруге змінює 0 файлів, `dart test` зелений з кількістю тестів, указаною в задачі; кінцеве дерево збігається з перевіреним. До M5 — 416 тестів.

---

### Task 1: Шляхи відносно робочого каталогу

**Files:**
- Create: `packages/typed_openapi/lib/src/diagnostics/display_paths.dart`, `packages/typed_openapi/test/diagnostics/display_paths_test.dart`
- Modify: `lib/src/config/config_loader.dart`, `lib/src/check/spec_checker.dart`, `lib/src/cli/cli.dart`, `lib/src/cli/check_command.dart`, `lib/src/resolve/spec_documents.dart`, `lib/src/overrides/override_resolver.dart`
- Test: `test/check/spec_checker_test.dart`, `test/cli/cli_test.dart`

**Interfaces:**
- Consumes: `SpecLoader.load(path, displayPath:)`, `SpecDocuments.displayPath`, `OverrideLoader.load(path, displayPath:)` (M2–M4).
- Produces: `DisplayPaths`, `ConfigLoader(bag, paths)`, `SpecChecker(bag, paths)`, `CheckCommand(out, paths)`, `TypedOpenApiCli(workingDirectory:)`.

Поведінка, яку закріплюють тести: файл усередині робочого каталогу — відносний шлях, поза ним — абсолютний; конфіг у підкаталозі з `input: ../specs/api.yaml` дає `specs/...`, а не `../specs/...`; файл за `$ref` поза робочим каталогом — абсолютний; відносний `--config` читається з робочого каталогу CLI, і відсутній конфіг названо відносно нього. Наявні тести `SpecChecker` отримують `DisplayPaths(dir.path)`, бо тимчасовий каталог лежить поза каталогом процесу.

- [ ] **Step 1: Тести, що не проходять**

Файл `packages/typed_openapi/test/diagnostics/display_paths_test.dart` (новий):

```dart
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/display_paths.dart';

void main() {
  final root = p.rootPrefix(p.current);
  final base = p.join(root, 'work', 'project');
  final paths = DisplayPaths(base);

  test('names a file inside the working directory relative to it', () {
    expect(
      paths.of(p.join(base, 'specs', 'api.yaml')),
      p.join('specs', 'api.yaml'),
    );
    expect(paths.of(p.join('specs', 'api.yaml')), p.join('specs', 'api.yaml'));
    expect(paths.of(p.join(base, 'specs', '..', 'api.yaml')), 'api.yaml');
  });

  test('names a file outside the working directory by its absolute path', () {
    final outside = p.join(root, 'work', 'shared', 'a.yaml');
    expect(paths.of(outside), outside);
    expect(paths.of(p.join('..', 'shared', 'a.yaml')), outside);
  });

  test('resolves relative paths against the working directory', () {
    expect(
      paths.absolute('typed_openapi.yaml'),
      p.join(base, 'typed_openapi.yaml'),
    );
    expect(paths.workingDirectory, base);
  });

  test('defaults to the current directory', () {
    expect(const DisplayPaths().workingDirectory, p.normalize(p.current));
    expect(const DisplayPaths().of('a.yaml'), 'a.yaml');
  });
}
```

Diff `packages/typed_openapi/test/check/spec_checker_test.dart`, `packages/typed_openapi/test/cli/cli_test.dart` (`git apply` з кореня):

```diff
diff --git a/packages/typed_openapi/test/check/spec_checker_test.dart b/packages/typed_openapi/test/check/spec_checker_test.dart
index 8876421..6e5ffb9 100644
--- a/packages/typed_openapi/test/check/spec_checker_test.dart
+++ b/packages/typed_openapi/test/check/spec_checker_test.dart
@@ -1,13 +1,16 @@
+import 'package:path/path.dart' as p;
 import 'package:test/test.dart';
 import 'package:typed_openapi/src/check/spec_checker.dart';
 import 'package:typed_openapi/src/config/config_loader.dart';
 import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
 import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
+import 'package:typed_openapi/src/diagnostics/display_paths.dart';
 
 import '../helpers/temp_dir.dart';
 
 void main() {
-  test('checks every client and names files relative to the config', () {
+  test('checks every client and names files relative to the working '
+      'directory', () {
     final dir = TempDir();
     dir.write(
       'specs/ok.yaml',
@@ -22,7 +25,7 @@ clients:
 ''');
     final bag = DiagnosticBag();
     final config = ConfigLoader(bag).load(path)!;
-    SpecChecker(bag).check(config);
+    SpecChecker(bag, DisplayPaths(dir.path)).check(config);
     expect(
       bag.all.map((d) => (d.code, d.file)),
       unorderedEquals([
@@ -55,7 +58,10 @@ clients:
     rules: {bool-required-to-array: false}
 ''');
     final bag = DiagnosticBag();
-    SpecChecker(bag).check(ConfigLoader(bag).load(path)!);
+    SpecChecker(
+      bag,
+      DisplayPaths(dir.path),
+    ).check(ConfigLoader(bag).load(path)!);
     expect(bag.all.map((d) => (d.code, d.file)), [
       (DiagnosticCode.boolRequired, 'a.yaml'),
       (DiagnosticCode.invalidValue, 'b.yaml'),
@@ -87,7 +93,10 @@ clients:
     overrides: specs/missing.yaml
 ''');
     final bag = DiagnosticBag();
-    SpecChecker(bag).check(ConfigLoader(bag).load(path)!);
+    SpecChecker(
+      bag,
+      DisplayPaths(dir.path),
+    ).check(ConfigLoader(bag).load(path)!);
     expect(
       bag.all.map((d) => (d.code, d.file)),
       unorderedEquals([
@@ -106,7 +115,7 @@ clients:
 ''');
     final bag = DiagnosticBag();
     final config = ConfigLoader(bag).load(path)!;
-    SpecChecker(bag).check(config, only: {'a'});
+    SpecChecker(bag, DisplayPaths(dir.path)).check(config, only: {'a'});
     expect(bag.all.single.file, 'a.yaml');
   });
 
@@ -120,7 +129,7 @@ clients:
 ''');
     final bag = DiagnosticBag();
     final config = ConfigLoader(bag).load(path)!;
-    SpecChecker(bag).check(config);
+    SpecChecker(bag, DisplayPaths(dir.path)).check(config);
     expect(bag.all.single.code, DiagnosticCode.unsupportedOpenApiVersion);
   });
 
@@ -146,7 +155,10 @@ clients:
   c: {input: shared.yaml, output: lib/c}
 ''');
     final bag = DiagnosticBag();
-    SpecChecker(bag).check(ConfigLoader(bag).load(path)!);
+    SpecChecker(
+      bag,
+      DisplayPaths(dir.path),
+    ).check(ConfigLoader(bag).load(path)!);
     // a and c share one run (TOA201); b runs without the fix (TOA111).
     expect(bag.all.map((d) => d.code), [
       DiagnosticCode.boolRequired,
@@ -173,7 +185,7 @@ clients:
 ''');
     final bag = DiagnosticBag();
     final config = ConfigLoader(bag).load(path)!;
-    SpecChecker(bag).check(config);
+    SpecChecker(bag, DisplayPaths(dir.path)).check(config);
     expect(
       bag.sorted.map((d) => (d.code, d.file, d.pointer?.value)),
       [
@@ -203,7 +215,10 @@ clients:
   b: {input: b.yaml, output: lib/b}
 ''');
     final bag = DiagnosticBag();
-    SpecChecker(bag).check(ConfigLoader(bag).load(path)!);
+    SpecChecker(
+      bag,
+      DisplayPaths(dir.path),
+    ).check(ConfigLoader(bag).load(path)!);
     expect(bag.all.map((d) => (d.code, d.file, d.pointer?.value)), [
       (DiagnosticCode.unknownKey, 'common.yaml', '#/Err/bogus'),
     ]);
@@ -223,7 +238,10 @@ clients:
       'clients:\n  api: {input: api.json, output: lib/api}\n',
     );
     final bag = DiagnosticBag();
-    SpecChecker(bag).check(ConfigLoader(bag).load(path)!);
+    SpecChecker(
+      bag,
+      DisplayPaths(dir.path),
+    ).check(ConfigLoader(bag).load(path)!);
     expect(bag.all.single.code, DiagnosticCode.nullableAfterOpenApi30);
   });
 
@@ -235,7 +253,57 @@ clients:
       'clients:\n  api: {input: api.yaml, output: lib/api}\n',
     );
     final bag = DiagnosticBag();
-    SpecChecker(bag).check(ConfigLoader(bag).load(path)!);
+    SpecChecker(
+      bag,
+      DisplayPaths(dir.path),
+    ).check(ConfigLoader(bag).load(path)!);
     expect(bag.all.single.code, DiagnosticCode.missingOpenApiVersion);
   });
+
+  test('names files by the working directory, not the config', () {
+    final dir = TempDir();
+    dir.write('specs/api.yaml', r'''
+openapi: 3.1.0
+info: {title: t, version: "1"}
+components: {schemas: {E: {$ref: "common.yaml#/Err"}}}
+''');
+    dir.write('specs/common.yaml', 'Err: {type: object, bogus: 1}\n');
+    final path = dir.write('config/typed_openapi.yaml', '''
+clients:
+  api: {input: ../specs/api.yaml, output: ../lib/api}
+''');
+    final bag = DiagnosticBag();
+    SpecChecker(
+      bag,
+      DisplayPaths(dir.path),
+    ).check(ConfigLoader(bag).load(path)!);
+    expect(bag.all.map((d) => (d.code, d.file)), [
+      (DiagnosticCode.unknownKey, p.join('specs', 'common.yaml')),
+    ]);
+  });
+
+  test('names a file outside the working directory by its absolute path', () {
+    final dir = TempDir();
+    dir.write('project/api.yaml', r'''
+openapi: 3.1.0
+info: {title: t, version: "1"}
+components: {schemas: {E: {$ref: "../shared/common.yaml#/Err"}}}
+''');
+    dir.write('shared/common.yaml', 'Err: {type: object, bogus: 1}\n');
+    final path = dir.write('project/typed_openapi.yaml', '''
+clients:
+  api: {input: api.yaml, output: lib/api}
+''');
+    final bag = DiagnosticBag();
+    SpecChecker(
+      bag,
+      DisplayPaths(p.join(dir.path, 'project')),
+    ).check(ConfigLoader(bag).load(path)!);
+    expect(bag.all.map((d) => (d.code, d.file)), [
+      (
+        DiagnosticCode.unknownKey,
+        p.normalize(p.join(dir.path, 'shared', 'common.yaml')),
+      ),
+    ]);
+  });
 }
diff --git a/packages/typed_openapi/test/cli/cli_test.dart b/packages/typed_openapi/test/cli/cli_test.dart
index 200f3db..ad35235 100644
--- a/packages/typed_openapi/test/cli/cli_test.dart
+++ b/packages/typed_openapi/test/cli/cli_test.dart
@@ -8,9 +8,11 @@ import '../helpers/temp_dir.dart';
 
 void main() {
   late String configPath;
+  late String workingDirectory;
 
   setUp(() {
     final dir = TempDir();
+    workingDirectory = dir.path;
     dir.write(
       'specs/ok.yaml',
       'openapi: 3.1.0\ninfo: {title: ok, version: "1"}\n',
@@ -23,10 +25,17 @@ clients:
 ''');
   });
 
-  Future<(int, String, String)> run(List<String> args) async {
+  Future<(int, String, String)> run(
+    List<String> args, {
+    String? workingDirectory,
+  }) async {
     final out = StringBuffer();
     final err = StringBuffer();
-    final code = await TypedOpenApiCli(out: out, err: err).run(args);
+    final code = await TypedOpenApiCli(
+      out: out,
+      err: err,
+      workingDirectory: workingDirectory,
+    ).run(args);
     return (code, out.toString(), err.toString());
   }
 
@@ -37,7 +46,11 @@ clients:
   });
 
   test('exits 1 and prints the location when a spec has errors', () async {
-    final (code, out, _) = await run(['check', '--config', configPath]);
+    final (code, out, _) = await run([
+      'check',
+      '--config',
+      configPath,
+    ], workingDirectory: workingDirectory);
     expect(code, 1);
     expect(out, contains('error TOA011 unsupported-openapi-version'));
     expect(out, contains('  --> ${p.join('specs', 'old.json')}:2:14'));
@@ -65,6 +78,28 @@ clients:
     expect(out, contains('TOA901 config-not-found'));
   });
 
+  test('reads a relative config path from the working directory', () async {
+    final (code, out, _) = await run([
+      'check',
+      '-c',
+      'typed_openapi.yaml',
+      'ok',
+    ], workingDirectory: workingDirectory);
+    expect(code, 0);
+    expect(out.trim(), 'errors: 0, warnings: 0, infos: 0');
+  });
+
+  test('names the missing config relative to the working directory', () async {
+    final (code, out, _) = await run([
+      'check',
+      '-c',
+      'nope.yaml',
+    ], workingDirectory: workingDirectory);
+    expect(code, 78);
+    expect(out, contains('Config file nope.yaml does not exist.'));
+    expect(out, contains('  --> nope.yaml\n'));
+  });
+
   test('exits 64 on an unknown client', () async {
     final (code, _, err) = await run(['check', '-c', configPath, 'nope']);
     expect(code, 64);
@@ -115,7 +150,11 @@ schemas:
 clients:
   api: {input: api.yaml, output: lib/api, overrides: api.overrides.yaml}
 ''');
-    final (code, out, _) = await run(['check', '-c', path]);
+    final (code, out, _) = await run([
+      'check',
+      '-c',
+      path,
+    ], workingDirectory: dir.path);
     expect(code, 1);
     expect(
       out,
```

- [ ] **Step 2: Запустити тести**

Run (з `packages/typed_openapi`): `dart test test/diagnostics/display_paths_test.dart test/check test/cli`
Expected: FAIL — компіляція: `display_paths.dart` не існує, `TypedOpenApiCli` не має `workingDirectory`.

- [ ] **Step 3: Реалізація**

Файл `packages/typed_openapi/lib/src/diagnostics/display_paths.dart` (новий):

```dart
import 'package:path/path.dart' as p;

/// How reports name files: relative to the working directory when the file
/// is inside it, absolute otherwise.
///
/// Every report format uses the same names, so a path printed by `check`
/// opens from the directory the command ran in.
final class DisplayPaths {
  /// Names files relative to [_workingDirectory], by default the current
  /// directory of the process.
  const DisplayPaths([this._workingDirectory]);

  final String? _workingDirectory;

  /// The absolute, normalized working directory.
  String get workingDirectory =>
      p.normalize(p.absolute(_workingDirectory ?? p.current));

  /// [path] as an absolute, normalized path; a relative [path] is relative
  /// to [workingDirectory].
  String absolute(String path) => p.normalize(p.join(workingDirectory, path));

  /// How reports name the file at [path]: relative to [workingDirectory]
  /// when it is inside it, absolute otherwise.
  String of(String path) {
    final full = absolute(path);
    final base = workingDirectory;
    if (p.equals(full, base) || p.isWithin(base, full)) {
      return p.relative(full, from: base);
    }
    return full;
  }
}
```

Diff `packages/typed_openapi/lib/src/check/spec_checker.dart`, `packages/typed_openapi/lib/src/cli/check_command.dart`, `packages/typed_openapi/lib/src/cli/cli.dart`, `packages/typed_openapi/lib/src/config/config_loader.dart`, `packages/typed_openapi/lib/src/overrides/override_resolver.dart`, `packages/typed_openapi/lib/src/resolve/spec_documents.dart` (`git apply` з кореня):

```diff
diff --git a/packages/typed_openapi/lib/src/check/spec_checker.dart b/packages/typed_openapi/lib/src/check/spec_checker.dart
index dd639bb..7fabd64 100644
--- a/packages/typed_openapi/lib/src/check/spec_checker.dart
+++ b/packages/typed_openapi/lib/src/check/spec_checker.dart
@@ -2,6 +2,7 @@ import 'package:path/path.dart' as p;
 
 import '../config/project_config.dart';
 import '../diagnostics/diagnostic_bag.dart';
+import '../diagnostics/display_paths.dart';
 import '../load/openapi_version.dart';
 import '../load/spec_loader.dart';
 import '../normalize/normalizer.dart';
@@ -12,10 +13,12 @@ import '../overrides/override_loader.dart';
 /// Nothing is generated. Problems go to the [DiagnosticBag] given to the
 /// constructor.
 final class SpecChecker {
-  /// Creates a checker that reports to [_diagnostics].
-  const SpecChecker(this._diagnostics);
+  /// Creates a checker that reports to [_diagnostics]; [_paths] names files
+  /// in diagnostics.
+  const SpecChecker(this._diagnostics, [this._paths = const DisplayPaths()]);
 
   final DiagnosticBag _diagnostics;
+  final DisplayPaths _paths;
 
   /// Checks the spec of every client in [config].
   ///
@@ -26,12 +29,11 @@ final class SpecChecker {
   /// without it. [only] limits the run to clients with these names; empty
   /// means all. A file shared by several clients is checked once per
   /// distinct preset, set of disabled rules and overrides file; the bag
-  /// reports a diagnostic the runs share once. Spec and overrides paths in
-  /// diagnostics are relative to the config file's directory.
+  /// reports a diagnostic the runs share once. Diagnostics name files
+  /// relative to the working directory (see [DisplayPaths]).
   void check(ProjectConfig config, {Set<String> only = const {}}) {
     final loader = SpecLoader(_diagnostics);
     final detector = OpenApiVersionDetector(_diagnostics);
-    final configDir = p.dirname(p.absolute(config.file));
     // A run is a file with a preset, a set of disabled rules and overrides.
     final checked = <(String, Preset?, String, String?)>{};
     for (final client in config.clients) {
@@ -47,7 +49,7 @@ final class SpecChecker {
       if (!checked.add(run)) continue;
       final document = loader.load(
         client.input,
-        displayPath: p.relative(client.input, from: configDir),
+        displayPath: _paths.of(client.input),
       );
       if (document == null) continue;
       final version = detector.detect(document);
@@ -56,7 +58,7 @@ final class SpecChecker {
           ? null
           : OverrideLoader(_diagnostics).load(
               overridesPath,
-              displayPath: p.relative(overridesPath, from: configDir),
+              displayPath: _paths.of(overridesPath),
             );
       Normalizer(
         _diagnostics,
diff --git a/packages/typed_openapi/lib/src/cli/check_command.dart b/packages/typed_openapi/lib/src/cli/check_command.dart
index 824fd88..09f674c 100644
--- a/packages/typed_openapi/lib/src/cli/check_command.dart
+++ b/packages/typed_openapi/lib/src/cli/check_command.dart
@@ -4,12 +4,14 @@ import 'package:io/io.dart' show ExitCode;
 import '../check/spec_checker.dart';
 import '../config/config_loader.dart';
 import '../diagnostics/diagnostic_bag.dart';
+import '../diagnostics/display_paths.dart';
 import '../diagnostics/reporters.dart';
 
 /// `typed_openapi check`: analyzes specs without generating code.
 final class CheckCommand extends Command<int> {
-  /// Creates the command; reports are written to [_out].
-  CheckCommand(this._out) {
+  /// Creates the command; reports are written to [_out] and name files as
+  /// [_paths] does.
+  CheckCommand(this._out, [this._paths = const DisplayPaths()]) {
     argParser
       ..addOption(
         'config',
@@ -29,6 +31,7 @@ final class CheckCommand extends Command<int> {
   static const exitHasErrors = 1;
 
   final StringSink _out;
+  final DisplayPaths _paths;
 
   @override
   String get name => 'check';
@@ -45,7 +48,10 @@ final class CheckCommand extends Command<int> {
   Future<int> run() async {
     final results = argResults!;
     final diagnostics = DiagnosticBag();
-    final config = ConfigLoader(diagnostics).load(results.option('config')!);
+    final config = ConfigLoader(
+      diagnostics,
+      _paths,
+    ).load(results.option('config')!);
     if (config != null) {
       final only = results.rest.toSet();
       final unknown = only.difference(config.declaredClients);
@@ -54,7 +60,7 @@ final class CheckCommand extends Command<int> {
           'Unknown client: ${(unknown.toList()..sort()).join(', ')}.',
         );
       }
-      SpecChecker(diagnostics).check(config, only: only);
+      SpecChecker(diagnostics, _paths).check(config, only: only);
     }
     final format = ReportFormat.values.byName(results.option('format')!);
     _out.writeln(format.reporter.format(diagnostics));
diff --git a/packages/typed_openapi/lib/src/cli/cli.dart b/packages/typed_openapi/lib/src/cli/cli.dart
index c7af23d..bc5848f 100644
--- a/packages/typed_openapi/lib/src/cli/cli.dart
+++ b/packages/typed_openapi/lib/src/cli/cli.dart
@@ -3,6 +3,7 @@ import 'dart:io';
 import 'package:args/command_runner.dart';
 import 'package:io/io.dart' show ExitCode;
 
+import '../diagnostics/display_paths.dart';
 import 'check_command.dart';
 
 /// The `typed_openapi` command line.
@@ -10,13 +11,18 @@ final class TypedOpenApiCli {
   /// Creates the command line.
   ///
   /// Reports go to [out] and usage errors to [err]; both default to the
-  /// process streams.
-  TypedOpenApiCli({StringSink? out, StringSink? err})
+  /// process streams. Paths on the command line are relative to
+  /// [workingDirectory], and reports name files relative to it; it defaults
+  /// to the current directory.
+  TypedOpenApiCli({StringSink? out, StringSink? err, String? workingDirectory})
     : _err = err ?? stderr,
-      _runner = CommandRunner<int>(
-        'typed_openapi',
-        'OpenAPI 3.x to Dart client generator.',
-      )..addCommand(CheckCommand(out ?? stdout));
+      _runner =
+          CommandRunner<int>(
+            'typed_openapi',
+            'OpenAPI 3.x to Dart client generator.',
+          )..addCommand(
+            CheckCommand(out ?? stdout, DisplayPaths(workingDirectory)),
+          );
 
   final CommandRunner<int> _runner;
   final StringSink _err;
diff --git a/packages/typed_openapi/lib/src/config/config_loader.dart b/packages/typed_openapi/lib/src/config/config_loader.dart
index 8c63d21..2df85a9 100644
--- a/packages/typed_openapi/lib/src/config/config_loader.dart
+++ b/packages/typed_openapi/lib/src/config/config_loader.dart
@@ -4,6 +4,7 @@ import 'package:path/path.dart' as p;
 import 'package:source_span/source_span.dart';
 
 import '../diagnostics/diagnostic_bag.dart';
+import '../diagnostics/display_paths.dart';
 import '../diagnostics/json_pointer.dart';
 import '../load/yaml_composer.dart';
 import '../normalize/normalizer.dart';
@@ -14,8 +15,9 @@ import 'project_config.dart';
 /// Problems go to the [DiagnosticBag] given to the constructor instead of
 /// being thrown.
 final class ConfigLoader {
-  /// Creates a loader that reports to [_diagnostics].
-  const ConfigLoader(this._diagnostics);
+  /// Creates a loader that reports to [_diagnostics]; [_paths] names the
+  /// config file in diagnostics.
+  const ConfigLoader(this._diagnostics, [this._paths = const DisplayPaths()]);
 
   static const _topLevelKeys = {'defaults', 'clients'};
   static const _defaultsKeys = {'preset', 'line_width', 'rules'};
@@ -30,19 +32,23 @@ final class ConfigLoader {
   };
 
   final DiagnosticBag _diagnostics;
+  final DisplayPaths _paths;
 
-  /// Reads the config file at [path].
+  /// Reads the config file at [path], relative to the working directory of
+  /// the [DisplayPaths] given to the constructor.
   ///
   /// Relative paths inside it are resolved against its directory. Returns
   /// null when the file is missing or unusable; otherwise returns every
   /// client that is valid.
   ProjectConfig? load(String path) {
-    final type = FileSystemEntity.typeSync(path);
+    final full = _paths.absolute(path);
+    final file = _paths.of(path);
+    final type = FileSystemEntity.typeSync(full);
     if (type == FileSystemEntityType.notFound) {
       _diagnostics.report(
         .configNotFound,
-        'Config file $path does not exist.',
-        file: path,
+        'Config file $file does not exist.',
+        file: file,
         fix: 'Create typed_openapi.yaml, or pass its path with --config.',
       );
       return null;
@@ -50,26 +56,26 @@ final class ConfigLoader {
     if (type == FileSystemEntityType.directory) {
       _diagnostics.report(
         .configInvalid,
-        'Config path $path is a directory, not a file.',
-        file: path,
+        'Config path $file is a directory, not a file.',
+        file: file,
         fix: 'Pass the path of typed_openapi.yaml itself with --config.',
       );
       return null;
     }
     final String text;
     try {
-      text = File(path).readAsStringSync();
+      text = File(full).readAsStringSync();
     } on FileSystemException catch (e) {
       _diagnostics.report(
         .configInvalid,
-        'Cannot read $path: ${e.message}.',
-        file: path,
+        'Cannot read $file: ${e.message}.',
+        file: file,
       );
       return null;
     }
-    final composed = _compose(text, path);
+    final composed = _compose(text, file, full);
     if (composed == null) return null;
-    final reader = _ConfigReader(path, _diagnostics, composed.spans);
+    final reader = _ConfigReader(file, _diagnostics, composed.spans);
     final root = composed.root;
     if (root is! Map<String, Object?>) {
       reader.invalid('The config must be a mapping.', .root);
@@ -97,7 +103,7 @@ final class ConfigLoader {
       return null;
     }
 
-    final baseDir = p.dirname(p.absolute(path));
+    final baseDir = p.dirname(full);
     String resolve(String value) => p.normalize(p.join(baseDir, value));
 
     final clients = <ClientConfig>[];
@@ -140,7 +146,7 @@ final class ConfigLoader {
       );
     }
     clients.sort((a, b) => a.name.compareTo(b.name));
-    _checkOutputOverlap(clients, outputSpans, path);
+    _checkOutputOverlap(clients, outputSpans, file);
     return ProjectConfig(
       file: path,
       clients: clients,
@@ -150,17 +156,17 @@ final class ConfigLoader {
 
   /// Reads [text] into plain values; null after reporting why it cannot be
   /// used. Every problem of the YAML itself is a config error.
-  ComposedYaml? _compose(String text, String path) {
+  ComposedYaml? _compose(String text, String file, String path) {
     final yaml = DiagnosticBag();
     final composed = YamlComposer(
       yaml,
-    ).compose(text, file: path, uri: p.toUri(p.absolute(path)));
+    ).compose(text, file: file, uri: p.toUri(path));
     for (final d in yaml.all) {
       _diagnostics.report(
         .configInvalid,
         d.message,
         severity: d.severity,
-        file: path,
+        file: file,
         pointer: d.pointer,
         span: d.span,
         fix: d.fix,
@@ -170,7 +176,7 @@ final class ConfigLoader {
       _diagnostics.report(
         .configInvalid,
         error.message,
-        file: path,
+        file: file,
         span: error.span,
       );
       return null;
diff --git a/packages/typed_openapi/lib/src/overrides/override_resolver.dart b/packages/typed_openapi/lib/src/overrides/override_resolver.dart
index f6e4b28..46f3f12 100644
--- a/packages/typed_openapi/lib/src/overrides/override_resolver.dart
+++ b/packages/typed_openapi/lib/src/overrides/override_resolver.dart
@@ -129,7 +129,7 @@ final class OverrideResolver {
     }
     final schemas = <(SchemaTarget, List<OverrideTarget>)>[];
     for (final entry in _overrides.schemas) {
-      final schema = _schema(entry, model);
+      final schema = _schema(entry, model, documents);
       if (schema == null) continue;
       schemas.add((
         SchemaTarget(entry, schema),
@@ -358,7 +358,11 @@ final class OverrideResolver {
     return ParameterTarget(entry, matches.single);
   }
 
-  SchemaObject? _schema(SchemaOverride entry, SpecModel model) {
+  SchemaObject? _schema(
+    SchemaOverride entry,
+    SpecModel model,
+    SpecDocuments documents,
+  ) {
     final written = model.document.components?.schemas[entry.key];
     if (written == null) {
       _notFound(entry, 'No schema "${entry.key}" in components.schemas.');
@@ -370,7 +374,9 @@ final class OverrideResolver {
       entry,
       schema == null
           ? 'The \$ref of schema "${entry.key}" cannot be followed.'
-          : 'Schema "${entry.key}" is the boolean schema ${schema.location}; '
+          : 'Schema "${entry.key}" is the boolean schema '
+                '${documents.displayPath(schema.location.document)}'
+                '${schema.pointer.value}; '
                 'it has no fields to change.',
     );
     return null;
diff --git a/packages/typed_openapi/lib/src/resolve/spec_documents.dart b/packages/typed_openapi/lib/src/resolve/spec_documents.dart
index be2d988..b894574 100644
--- a/packages/typed_openapi/lib/src/resolve/spec_documents.dart
+++ b/packages/typed_openapi/lib/src/resolve/spec_documents.dart
@@ -59,14 +59,21 @@ final class SpecDocuments {
         FileSystemEntity.typeSync(path) == FileSystemEntityType.file;
   }
 
-  /// How diagnostics name the file at [uri].
+  /// How diagnostics name the file at [uri]: like the root document, whose
+  /// name is relative to the working directory or absolute.
+  ///
+  /// A file outside the directory the root's relative name starts from is
+  /// named by its absolute path, as is every file when the root's name is
+  /// absolute.
   String displayPath(Uri uri) {
     if (uri == root.uri) return root.file;
     final path = _pathOf(uri);
     final rootPath = _pathOf(root.uri);
     if (path == null || rootPath == null) return '$uri';
+    if (p.isAbsolute(root.file)) return p.normalize(path);
     final relative = p.relative(path, from: p.dirname(rootPath));
-    return p.normalize(p.join(p.dirname(root.file), relative));
+    final name = p.normalize(p.join(p.dirname(root.file), relative));
+    return p.split(name).first == '..' ? p.normalize(path) : name;
   }
 
   static String? _pathOf(Uri uri) {
```

- [ ] **Step 4: Перевірити**

Run (з `packages/typed_openapi`): `dart test`
Expected: PASS, 424 тести (`+424: All tests passed!`).

Run (з `packages/typed_openapi`): `dart format lib test bin` двічі
Expected: другий запуск — `0 changed`.

Run (з кореня): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 5: Коміт**

```bash
git add packages/typed_openapi
git commit -m "feat(typed_openapi): name files relative to the working directory" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: Рівні в конфігу (`severity`)

**Files:**
- Create: `lib/src/diagnostics/severity_levels.dart`, `test/diagnostics/severity_levels_test.dart`
- Modify: `lib/src/diagnostics/diagnostic.dart`, `lib/src/diagnostics/diagnostic_code.dart`, `lib/src/config/project_config.dart`, `lib/src/config/config_loader.dart`, `lib/src/check/spec_checker.dart`
- Test: `test/config/config_loader_test.dart`, `test/check/spec_checker_test.dart`, `test/cli/cli_test.dart`

**Interfaces:**
- Consumes: `DisplayPaths`, `SpecChecker(bag, paths)` (задача 1); `_ConfigReader` (`mapAt`, `invalid`, `spanAt`) і `DiagnosticCode` (M1).
- Produces: `SeverityLevels`, `ClientConfig.severity`, `DiagnosticCode.fixedCodes`, `DiagnosticCode.configCodes`, `Diagnostic.withSeverity`; `SpecChecker` перевіряє прогін один раз і застосовує рівні кожного клієнта.

Поведінка, яку закріплюють тести: `severity` у `defaults` і в клієнті за кодом або slug, клієнт перекриває `defaults` за кодом; невідомий код — TOA903, поганий рівень і повтор коду — TOA902; незмінний код можна підняти (`TOA807: warning`), а не знизити (`parse-error: warning`, `TOA804: off`), код конфігу не змінюється; `severity` не мапа — TOA902; валідний конфіг — без діагностик. Спільна специфікація з трьома клієнтами (`error`, `off`, за замовчуванням) — дві діагностики різних рівнів; `off` у `defaults` — порожній звіт; знижений до warning TOA504 дає код виходу `0`.

- [ ] **Step 1: Тести, що не проходять**

Файл `packages/typed_openapi/test/diagnostics/severity_levels_test.dart` (новий):

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/diagnostics/severity_levels.dart';

void main() {
  const warning = Diagnostic(
    code: DiagnosticCode.boolRequired,
    severity: Severity.warning,
    message: 'm',
    file: 'api.yaml',
    fix: 'f',
  );

  test('gives a code its configured level and keeps the rest', () {
    const levels = SeverityLevels({
      DiagnosticCode.boolRequired: Severity.error,
    });
    final raised = levels.apply(warning)!;
    expect(raised.severity, Severity.error);
    expect(
      (raised.code, raised.message, raised.file, raised.fix),
      (
        DiagnosticCode.boolRequired,
        'm',
        'api.yaml',
        'f',
      ),
    );
  });

  test('drops a code that is off', () {
    const levels = SeverityLevels({DiagnosticCode.boolRequired: null});
    expect(levels.apply(warning), isNull);
  });

  test('leaves codes the config does not name unchanged', () {
    const levels = SeverityLevels({DiagnosticCode.invalidValue: null});
    expect(levels.apply(warning), same(warning));
    expect(const SeverityLevels().apply(warning), same(warning));
  });

  test('every config code is fixed', () {
    expect(
      DiagnosticCode.fixedCodes.containsAll(DiagnosticCode.configCodes),
      isTrue,
    );
  });
}
```

Diff `packages/typed_openapi/test/check/spec_checker_test.dart`, `packages/typed_openapi/test/cli/cli_test.dart`, `packages/typed_openapi/test/config/config_loader_test.dart` (`git apply` з кореня):

```diff
diff --git a/packages/typed_openapi/test/check/spec_checker_test.dart b/packages/typed_openapi/test/check/spec_checker_test.dart
index 6e5ffb9..604e71c 100644
--- a/packages/typed_openapi/test/check/spec_checker_test.dart
+++ b/packages/typed_openapi/test/check/spec_checker_test.dart
@@ -5,6 +5,7 @@ import 'package:typed_openapi/src/config/config_loader.dart';
 import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
 import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
 import 'package:typed_openapi/src/diagnostics/display_paths.dart';
+import 'package:typed_openapi/src/diagnostics/severity.dart';
 
 import '../helpers/temp_dir.dart';
 
@@ -306,4 +307,60 @@ clients:
       ),
     ]);
   });
+
+  test("gives each client's diagnostics its levels", () {
+    final dir = TempDir();
+    dir.write('shared.yaml', '''
+openapi: 3.0.3
+info: {title: t, version: "1"}
+components:
+  schemas:
+    Tag:
+      type: object
+      properties:
+        name: {type: string, required: true}
+''');
+    final path = dir.write('typed_openapi.yaml', '''
+clients:
+  a: {input: shared.yaml, output: lib/a, severity: {bool-required: error}}
+  b: {input: shared.yaml, output: lib/b, severity: {bool-required: off}}
+  c: {input: shared.yaml, output: lib/c}
+''');
+    final bag = DiagnosticBag();
+    SpecChecker(
+      bag,
+      DisplayPaths(dir.path),
+    ).check(ConfigLoader(bag).load(path)!);
+    // One run: a raises the finding, b turns it off, c keeps the default.
+    expect(bag.all.map((d) => (d.code, d.severity)), [
+      (DiagnosticCode.boolRequired, Severity.error),
+      (DiagnosticCode.boolRequired, Severity.warning),
+    ]);
+    expect(bag.hasErrors, isTrue);
+  });
+
+  test('a code turned off leaves nothing in the report', () {
+    final dir = TempDir();
+    dir.write('api.yaml', '''
+openapi: 3.0.3
+info: {title: t, version: "1"}
+components:
+  schemas:
+    Tag:
+      type: object
+      properties:
+        name: {type: string, required: true}
+''');
+    final path = dir.write('typed_openapi.yaml', '''
+defaults: {severity: {TOA201: off}}
+clients:
+  api: {input: api.yaml, output: lib/api}
+''');
+    final bag = DiagnosticBag();
+    SpecChecker(
+      bag,
+      DisplayPaths(dir.path),
+    ).check(ConfigLoader(bag).load(path)!);
+    expect(bag.all, isEmpty);
+  });
 }
diff --git a/packages/typed_openapi/test/cli/cli_test.dart b/packages/typed_openapi/test/cli/cli_test.dart
index ad35235..5e9bf52 100644
--- a/packages/typed_openapi/test/cli/cli_test.dart
+++ b/packages/typed_openapi/test/cli/cli_test.dart
@@ -206,4 +206,30 @@ components:
       contains(r'  at #/components/schemas/Owner/properties/pet/$ref'),
     );
   });
+
+  test('a level from the config changes the exit code', () async {
+    final dir = TempDir();
+    dir.write('api.yaml', '''
+openapi: 3.0.3
+info: {title: api, version: "1"}
+paths:
+  /a: {get: {operationId: same, responses: {'200': {description: ok}}}}
+  /b: {get: {operationId: same, responses: {'200': {description: ok}}}}
+''');
+    final path = dir.write('typed_openapi.yaml', '''
+clients:
+  api:
+    input: api.yaml
+    output: lib/api
+    severity: {duplicate-operation-id: warning}
+''');
+    final (code, out, _) = await run([
+      'check',
+      '-c',
+      path,
+    ], workingDirectory: dir.path);
+    expect(code, 0);
+    expect(out, contains('warning TOA504 duplicate-operation-id'));
+    expect(out, endsWith('errors: 0, warnings: 1, infos: 0\n'));
+  });
 }
diff --git a/packages/typed_openapi/test/config/config_loader_test.dart b/packages/typed_openapi/test/config/config_loader_test.dart
index f5a1daf..6b0125a 100644
--- a/packages/typed_openapi/test/config/config_loader_test.dart
+++ b/packages/typed_openapi/test/config/config_loader_test.dart
@@ -6,6 +6,7 @@ import 'package:typed_openapi/src/config/config_loader.dart';
 import 'package:typed_openapi/src/config/project_config.dart';
 import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
 import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
+import 'package:typed_openapi/src/diagnostics/severity.dart';
 
 import '../helpers/temp_dir.dart';
 
@@ -235,4 +236,117 @@ clients:
     );
     expect(bag.all.single.code, DiagnosticCode.configInvalid);
   });
+
+  test('reads levels by code or name; a client overrides defaults per '
+      'code', () {
+    final path = TempDir().write('c.yaml', '''
+defaults:
+  severity: {TOA201: off, example-scalar-type: warning}
+clients:
+  a: {input: a.json, output: lib/a}
+  b:
+    input: b.json
+    output: lib/b
+    severity: {bool-required: error, TOA804: error}
+''');
+    final bag = DiagnosticBag();
+    final clients = ConfigLoader(bag).load(path)!.clients;
+    expect(bag.all, isEmpty);
+    expect(clients.first.severity.levels, {
+      DiagnosticCode.boolRequired: null,
+      DiagnosticCode.exampleScalarType: Severity.warning,
+    });
+    expect(clients.last.severity.levels, {
+      DiagnosticCode.boolRequired: Severity.error,
+      DiagnosticCode.exampleScalarType: Severity.warning,
+      DiagnosticCode.overrideTargetNotFound: Severity.error,
+    });
+  });
+
+  test('reports unknown codes, bad levels and codes named twice', () {
+    final path = TempDir().write('c.yaml', '''
+clients:
+  a:
+    input: a.json
+    output: lib/a
+    severity:
+      TOA999: off
+      bool-required: fatal
+      TOA111: info
+      invalid-value: off
+''');
+    final bag = DiagnosticBag();
+    final client = ConfigLoader(bag).load(path)!.clients.single;
+    expect(client.severity.levels, {
+      DiagnosticCode.invalidValue: Severity.info,
+    });
+    expect(bag.all.map((d) => (d.code, d.pointer?.value, d.message)), [
+      (
+        DiagnosticCode.configUnknownKey,
+        '#/clients/a/severity/TOA999',
+        'Unknown diagnostic code "TOA999".',
+      ),
+      (
+        DiagnosticCode.configInvalid,
+        '#/clients/a/severity/bool-required',
+        'The level of "bool-required" must be error, warning, info or off.',
+      ),
+      (
+        DiagnosticCode.configInvalid,
+        '#/clients/a/severity/invalid-value',
+        '"invalid-value" names the same code as "TOA111" (TOA111); only the '
+            'first is used.',
+      ),
+    ]);
+  });
+
+  test('a fixed code may be raised but not lowered or turned off', () {
+    final path = TempDir().write('c.yaml', '''
+defaults:
+  severity:
+    parse-error: warning
+    TOA804: off
+    TOA807: warning
+    config-unknown-key: error
+clients:
+  a: {input: a.json, output: lib/a}
+''');
+    final bag = DiagnosticBag();
+    final client = ConfigLoader(bag).load(path)!.clients.single;
+    expect(client.severity.levels, {
+      DiagnosticCode.overrideUnchanged: Severity.warning,
+    });
+    expect(bag.all.map((d) => (d.code, d.pointer?.value, d.message)), [
+      (
+        DiagnosticCode.configInvalid,
+        '#/defaults/severity/parse-error',
+        'TOA001 parse-error cannot be lowered or turned off: without it a '
+            'broken spec or overrides file would pass.',
+      ),
+      (
+        DiagnosticCode.configInvalid,
+        '#/defaults/severity/TOA804',
+        'TOA804 override-target-not-found cannot be lowered or turned off: '
+            'without it a broken spec or overrides file would pass.',
+      ),
+      (
+        DiagnosticCode.configInvalid,
+        '#/defaults/severity/config-unknown-key',
+        'The level of TOA903 config-unknown-key cannot be changed: the '
+            'config is read before levels apply.',
+      ),
+    ]);
+  });
+
+  test('severity must be a mapping', () {
+    final path = TempDir().write('c.yaml', '''
+clients:
+  a: {input: a.json, output: lib/a, severity: [TOA201]}
+''');
+    final bag = DiagnosticBag();
+    expect(ConfigLoader(bag).load(path)!.clients.single.severity.levels, {});
+    expect(bag.all.map((d) => (d.code, d.pointer?.value)), [
+      (DiagnosticCode.configInvalid, '#/clients/a/severity'),
+    ]);
+  });
 }
```

- [ ] **Step 2: Запустити тести**

Run (з `packages/typed_openapi`): `dart test test/diagnostics/severity_levels_test.dart test/config test/check test/cli`
Expected: FAIL — компіляція: `severity_levels.dart` не існує, `ClientConfig` не має `severity`.

- [ ] **Step 3: Реалізація**

Файл `packages/typed_openapi/lib/src/diagnostics/severity_levels.dart` (новий):

```dart
import 'diagnostic.dart';
import 'diagnostic_code.dart';
import 'severity.dart';

/// The levels a client's config gives diagnostic codes, in place of their
/// [DiagnosticCode.defaultSeverity].
///
/// A level of `null` turns the code off: its diagnostics are not reported
/// and do not change the exit code.
final class SeverityLevels {
  /// Creates the levels; codes missing from [levels] keep their default.
  const SeverityLevels([this.levels = const {}]);

  /// The level of each code the config names; `null` is `off`.
  final Map<DiagnosticCode, Severity?> levels;

  /// [diagnostic] with the level of its code, or null when the code is off.
  Diagnostic? apply(Diagnostic diagnostic) {
    if (!levels.containsKey(diagnostic.code)) return diagnostic;
    final level = levels[diagnostic.code];
    if (level == null) return null;
    return level == diagnostic.severity
        ? diagnostic
        : diagnostic.withSeverity(level);
  }
}
```

Diff `packages/typed_openapi/lib/src/check/spec_checker.dart`, `packages/typed_openapi/lib/src/config/config_loader.dart`, `packages/typed_openapi/lib/src/config/project_config.dart`, `packages/typed_openapi/lib/src/diagnostics/diagnostic.dart`, `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart` (`git apply` з кореня):

```diff
diff --git a/packages/typed_openapi/lib/src/check/spec_checker.dart b/packages/typed_openapi/lib/src/check/spec_checker.dart
index 7fabd64..f1f3232 100644
--- a/packages/typed_openapi/lib/src/check/spec_checker.dart
+++ b/packages/typed_openapi/lib/src/check/spec_checker.dart
@@ -1,6 +1,7 @@
 import 'package:path/path.dart' as p;
 
 import '../config/project_config.dart';
+import '../diagnostics/diagnostic.dart';
 import '../diagnostics/diagnostic_bag.dart';
 import '../diagnostics/display_paths.dart';
 import '../load/openapi_version.dart';
@@ -28,43 +29,53 @@ final class SpecChecker {
   /// overrides file that cannot be used is reported and the spec is checked
   /// without it. [only] limits the run to clients with these names; empty
   /// means all. A file shared by several clients is checked once per
-  /// distinct preset, set of disabled rules and overrides file; the bag
-  /// reports a diagnostic the runs share once. Diagnostics name files
+  /// distinct preset, set of disabled rules and overrides file; each client
+  /// then gives the diagnostics of that run its own levels
+  /// ([ClientConfig.severity]), because levels change how a finding is
+  /// reported, not what a run finds. The bag reports a diagnostic the
+  /// clients share once. Diagnostics name files
   /// relative to the working directory (see [DisplayPaths]).
   void check(ProjectConfig config, {Set<String> only = const {}}) {
-    final loader = SpecLoader(_diagnostics);
-    final detector = OpenApiVersionDetector(_diagnostics);
     // A run is a file with a preset, a set of disabled rules and overrides.
-    final checked = <(String, Preset?, String, String?)>{};
+    final runs = <(String, Preset?, String, String?), List<Diagnostic>>{};
     for (final client in config.clients) {
       if (only.isNotEmpty && !only.contains(client.name)) continue;
       final rules = (client.disabledRules.toList()..sort()).join(',');
-      final overridesPath = client.overrides;
       final run = (
         p.absolute(client.input),
         client.preset,
         rules,
-        overridesPath,
+        client.overrides,
       );
-      if (!checked.add(run)) continue;
-      final document = loader.load(
-        client.input,
-        displayPath: _paths.of(client.input),
-      );
-      if (document == null) continue;
-      final version = detector.detect(document);
-      if (version == null) continue;
-      final overrides = overridesPath == null
-          ? null
-          : OverrideLoader(_diagnostics).load(
-              overridesPath,
-              displayPath: _paths.of(overridesPath),
-            );
-      Normalizer(
-        _diagnostics,
-        disabled: client.disabledRules,
-        preset: client.preset,
-      ).normalize(document, version, overrides: overrides);
+      final found = runs[run] ??= _run(client);
+      for (final diagnostic in found) {
+        final reported = client.severity.apply(diagnostic);
+        if (reported != null) _diagnostics.add(reported);
+      }
     }
   }
+
+  /// Checks the spec of [client]; returns what the run found, with default
+  /// levels.
+  List<Diagnostic> _run(ClientConfig client) {
+    final found = DiagnosticBag();
+    final document = SpecLoader(
+      found,
+    ).load(client.input, displayPath: _paths.of(client.input));
+    if (document == null) return found.all;
+    final version = OpenApiVersionDetector(found).detect(document);
+    if (version == null) return found.all;
+    final overridesPath = client.overrides;
+    final overrides = overridesPath == null
+        ? null
+        : OverrideLoader(
+            found,
+          ).load(overridesPath, displayPath: _paths.of(overridesPath));
+    Normalizer(
+      found,
+      disabled: client.disabledRules,
+      preset: client.preset,
+    ).normalize(document, version, overrides: overrides);
+    return found.all;
+  }
 }
diff --git a/packages/typed_openapi/lib/src/config/config_loader.dart b/packages/typed_openapi/lib/src/config/config_loader.dart
index 2df85a9..e1bcf80 100644
--- a/packages/typed_openapi/lib/src/config/config_loader.dart
+++ b/packages/typed_openapi/lib/src/config/config_loader.dart
@@ -4,8 +4,11 @@ import 'package:path/path.dart' as p;
 import 'package:source_span/source_span.dart';
 
 import '../diagnostics/diagnostic_bag.dart';
+import '../diagnostics/diagnostic_code.dart';
 import '../diagnostics/display_paths.dart';
 import '../diagnostics/json_pointer.dart';
+import '../diagnostics/severity.dart';
+import '../diagnostics/severity_levels.dart';
 import '../load/yaml_composer.dart';
 import '../normalize/normalizer.dart';
 import 'project_config.dart';
@@ -20,7 +23,7 @@ final class ConfigLoader {
   const ConfigLoader(this._diagnostics, [this._paths = const DisplayPaths()]);
 
   static const _topLevelKeys = {'defaults', 'clients'};
-  static const _defaultsKeys = {'preset', 'line_width', 'rules'};
+  static const _defaultsKeys = {'preset', 'line_width', 'rules', 'severity'};
   static const _clientKeys = {
     'input',
     'output',
@@ -29,6 +32,7 @@ final class ConfigLoader {
     'baseline',
     'line_width',
     'rules',
+    'severity',
   };
 
   final DiagnosticBag _diagnostics;
@@ -88,11 +92,13 @@ final class ConfigLoader {
     Preset? defaultPreset;
     int? defaultWidth;
     var defaultRules = const <String, bool>{};
+    var defaultLevels = const <DiagnosticCode, Severity?>{};
     if (defaults != null) {
       reader.checkKeys(defaults, _defaultsKeys, defaultsPointer);
       defaultPreset = reader.presetAt(defaults, defaultsPointer);
       defaultWidth = reader.intAt(defaults, 'line_width', defaultsPointer);
       defaultRules = reader.rulesAt(defaults, defaultsPointer);
+      defaultLevels = reader.severityAt(defaults, defaultsPointer);
     }
 
     final clientsPointer = JsonPointer.root.child('clients');
@@ -127,6 +133,10 @@ final class ConfigLoader {
       final overrides = reader.stringAt(value, 'overrides', pointer);
       final baseline = reader.stringAt(value, 'baseline', pointer);
       final rules = {...defaultRules, ...reader.rulesAt(value, pointer)};
+      final levels = {
+        ...defaultLevels,
+        ...reader.severityAt(value, pointer),
+      };
       if (input == null || output == null) continue;
       outputSpans[name] = reader.spanAt(pointer.child('output'));
       clients.add(
@@ -142,6 +152,7 @@ final class ConfigLoader {
             for (final MapEntry(:key, :value) in rules.entries)
               if (!value) key,
           },
+          severity: SeverityLevels(levels),
         ),
       );
     }
@@ -315,6 +326,87 @@ class _ConfigReader {
     return result;
   }
 
+  /// `severity` of [parent]: diagnostic codes, by id or slug, mapped to
+  /// their level; `null` is `off`. Unknown codes are a warning, bad levels
+  /// and levels a code cannot have are errors; all of them are skipped.
+  Map<DiagnosticCode, Severity?> severityAt(
+    Map<String, Object?> parent,
+    JsonPointer at,
+  ) {
+    final entries = mapAt(parent, 'severity', at);
+    if (entries == null) return const {};
+    final pointer = at.child('severity');
+    final result = <DiagnosticCode, Severity?>{};
+    final names = <DiagnosticCode, String>{};
+    for (final MapEntry(key: name, :value) in entries.entries) {
+      final at = pointer.child(name);
+      final code = _codes[name];
+      if (code == null) {
+        diagnostics.report(
+          .configUnknownKey,
+          'Unknown diagnostic code "$name".',
+          file: file,
+          pointer: at,
+          span: spanAt(at),
+          fix:
+              'Use a code such as TOA201 or its name such as bool-required; '
+              'the README lists them.',
+        );
+        continue;
+      }
+      if (names[code] case final first?) {
+        invalid(
+          '"$name" names the same code as "$first" (${code.id}); '
+          'only the first is used.',
+          at,
+        );
+        continue;
+      }
+      names[code] = name;
+      if (value is! String || !_levels.containsKey(value)) {
+        invalid(
+          'The level of "$name" must be error, warning, info or off.',
+          at,
+        );
+        continue;
+      }
+      final level = _levels[value];
+      if (DiagnosticCode.configCodes.contains(code)) {
+        invalid(
+          'The level of ${code.id} ${code.slug} cannot be changed: the '
+          'config is read before levels apply.',
+          at,
+        );
+        continue;
+      }
+      if (DiagnosticCode.fixedCodes.contains(code) &&
+          (level == null || level.index > code.defaultSeverity.index)) {
+        invalid(
+          '${code.id} ${code.slug} cannot be lowered or turned off: '
+          'without it a broken spec or overrides file would pass.',
+          at,
+        );
+        continue;
+      }
+      result[code] = level;
+    }
+    return result;
+  }
+
+  static final _codes = {
+    for (final code in DiagnosticCode.values) ...{
+      code.id: code,
+      code.slug: code,
+    },
+  };
+
+  static const _levels = <String, Severity?>{
+    'error': .error,
+    'warning': .warning,
+    'info': .info,
+    'off': null,
+  };
+
   Preset? presetAt(Map<String, Object?> parent, JsonPointer at) {
     final name = stringAt(parent, 'preset', at);
     if (name == null) return null;
diff --git a/packages/typed_openapi/lib/src/config/project_config.dart b/packages/typed_openapi/lib/src/config/project_config.dart
index fe57114..47bc8ce 100644
--- a/packages/typed_openapi/lib/src/config/project_config.dart
+++ b/packages/typed_openapi/lib/src/config/project_config.dart
@@ -1,3 +1,5 @@
+import '../diagnostics/severity_levels.dart';
+
 /// Normalizer presets a client may name in the config.
 enum Preset {
   /// No framework-specific fixes.
@@ -28,6 +30,7 @@ final class ClientConfig {
     this.overrides,
     this.baseline,
     this.disabledRules = const {},
+    this.severity = const SeverityLevels(),
   });
 
   /// Line width of generated code when the config does not set one.
@@ -56,6 +59,10 @@ final class ClientConfig {
 
   /// Normalizer rules the config turns off for this client, by name.
   final Set<String> disabledRules;
+
+  /// The levels the config gives diagnostic codes for this client:
+  /// `defaults.severity` with the client's `severity` on top.
+  final SeverityLevels severity;
 }
 
 /// The parsed `typed_openapi.yaml`.
diff --git a/packages/typed_openapi/lib/src/diagnostics/diagnostic.dart b/packages/typed_openapi/lib/src/diagnostics/diagnostic.dart
index 7b16df5..f09c110 100644
--- a/packages/typed_openapi/lib/src/diagnostics/diagnostic.dart
+++ b/packages/typed_openapi/lib/src/diagnostics/diagnostic.dart
@@ -53,6 +53,17 @@ final class Diagnostic implements Comparable<Diagnostic> {
     return start == null ? null : start.column + 1;
   }
 
+  /// This diagnostic with [severity] instead of its own.
+  Diagnostic withSeverity(Severity severity) => Diagnostic(
+    code: code,
+    severity: severity,
+    message: message,
+    file: file,
+    pointer: pointer,
+    span: span,
+    fix: fix,
+  );
+
   /// `file:line:column`, `file` when only the file is known, or null.
   String? get location {
     final file = this.file;
diff --git a/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart b/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart
index 3286c6f..0c559b8 100644
--- a/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart
+++ b/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart
@@ -255,6 +255,39 @@ enum DiagnosticCode {
 
   const DiagnosticCode(this.id, this.slug, this.defaultSeverity);
 
+  /// Codes of the config file: it is read before any level applies, so the
+  /// config cannot change them.
+  static const configCodes = {
+    configNotFound,
+    configInvalid,
+    configUnknownKey,
+    outputOverlap,
+  };
+
+  /// Codes the config may raise but not lower or turn off: without them the
+  /// spec is not read at all, or they are about a file the user writes for
+  /// this tool (the config and the overrides file).
+  static const fixedCodes = {
+    parseError,
+    rootNotObject,
+    inputNotFound,
+    inputUnreadable,
+    nestingTooDeep,
+    aliasExpansionTooLarge,
+    missingOpenApiVersion,
+    unsupportedOpenApiVersion,
+    overridesNotFound,
+    invalidOverride,
+    unknownOverrideKey,
+    overrideTargetNotFound,
+    overrideTargetAmbiguous,
+    overrideConflict,
+    overrideUnchanged,
+    overrideSharedTarget,
+    overrideNullabilityDropped,
+    ...configCodes,
+  };
+
   /// The stable id, such as `TOA001`.
   final String id;
 
```

- [ ] **Step 4: Перевірити**

Run (з `packages/typed_openapi`): `dart test`
Expected: PASS, 435 тестів (`+435: All tests passed!`).

Run (з `packages/typed_openapi`): `dart format lib test bin` двічі
Expected: другий запуск — `0 changed`.

Run (з кореня): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 5: Коміт**

```bash
git add packages/typed_openapi
git commit -m "feat(typed_openapi): set diagnostic levels per client in the config" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: Якір і fingerprint

**Files:**
- Create: `lib/src/baseline/anchor_index.dart`, `lib/src/baseline/fingerprints.dart`, `test/baseline/fingerprints_test.dart`
- Modify: `pubspec.yaml` (`crypto`), `lib/src/diagnostics/diagnostic.dart`, `lib/src/diagnostics/diagnostic_bag.dart`, `lib/src/parse/parse_context.dart`, `lib/src/parse/object_reader.dart`, `lib/src/parse/operation_parser.dart`

**Interfaces:**
- Consumes: `SpecModel` (`document.paths`, `components.schemas`, `resolve`, `resolveSchema`), `SpecDocuments.loaded` / `displayPath`, `Parameter.name` / `placement`, `Inline` (M2); `Normalizer.normalize` → `NormalizedSpec(model, documents)` (M3); `DisplayPaths` (задача 1).
- Produces: `AnchorIndex`, `Fingerprints`, `Diagnostic.args`, `DiagnosticBag.report(args:)`, `ParseContext.report(args:)`.

Поведінка, яку закріплюють тести: параметр, перед який вставлено інший, зберігає якір `@/operations/GET ~1pets/parameters/query:limit#/bogus` і fingerprint; новий шлях вище в специфікації не змінює fingerprint властивості; схема в іншому файлі має якір за ключем `components.schemas`; місце без адреси — `../api.yaml#/info` відносно файлу baseline у підкаталозі; два TOA112 на одному об'єкті розрізняє `args`; текст повідомлення не впливає, код впливає; значення fingerprint зафіксоване (`ed41f0665b98` для `["TOA110","api.yaml#/info/x",[]]`).

- [ ] **Step 1: Тест, що не проходить**

Файл `packages/typed_openapi/test/baseline/fingerprints_test.dart` (новий):

```dart
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/baseline/anchor_index.dart';
import 'package:typed_openapi/src/baseline/fingerprints.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/display_paths.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/load/openapi_version.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/normalize/normalizer.dart';

import '../helpers/temp_dir.dart';

void main() {
  /// Checks [spec] written to `api.yaml` (and [files] next to it) and
  /// returns its diagnostics with their anchors for a baseline at
  /// [baseline], both relative to the temp directory.
  List<(DiagnosticCode, String, String)> check(
    String spec, {
    Map<String, String> files = const {},
    String baseline = 'api.baseline.yaml',
  }) {
    final dir = TempDir();
    final paths = DisplayPaths(dir.path);
    final path = dir.write('api.yaml', spec);
    files.forEach(dir.write);
    final bag = DiagnosticBag();
    final document = SpecLoader(bag).load(path, displayPath: paths.of(path))!;
    final normalized = Normalizer(
      bag,
    ).normalize(document, OpenApiVersionDetector(bag).detect(document)!);
    final fingerprints = Fingerprints(
      AnchorIndex(normalized.model, normalized.documents),
      baseline,
      paths,
    );
    return [
      for (final d in bag.sorted)
        (d.code, fingerprints.anchorOf(d), fingerprints.of(d)),
    ];
  }

  const petsWithLimit = '''
openapi: 3.0.3
info: {title: t, version: "1"}
paths:
  /pets:
    get:
      parameters:
        - {name: page, in: query, schema: {type: integer}}
        - {name: limit, in: query, bogus: 1, schema: {type: integer}}
      responses: {'200': {description: ok}}
''';

  test('anchors a parameter by its address, not its index', () {
    final before = check(petsWithLimit);
    final after = check(
      petsWithLimit.replaceFirst(
        '        - {name: page',
        '        - {name: sort, in: query, schema: {type: string}}\n'
            '        - {name: page',
      ),
    );
    final unknown = before.where((d) => d.$1 == DiagnosticCode.unknownKey);
    expect(
      unknown.single.$2,
      '@/operations/GET ~1pets/parameters/query:limit#/bogus',
    );
    expect(
      after.where((d) => d.$1 == DiagnosticCode.unknownKey).single,
      unknown.single,
    );
  });

  test('an edit elsewhere in the spec keeps the fingerprint', () {
    const spec = '''
openapi: 3.0.3
info: {title: t, version: "1"}
components:
  schemas:
    Tag:
      type: object
      properties:
        name: {type: string, required: true}
''';
    final before = check(spec);
    final after = check(
      spec.replaceFirst(
        'components:',
        'paths:\n  /a: {get: {responses: {"200": {description: ok}}}}\n'
            'components:',
      ),
    );
    final tag = before.where((d) => d.$1 == DiagnosticCode.boolRequired);
    expect(tag.single.$2, '@/schemas/Tag/properties/name#/required');
    expect(
      after.where((d) => d.$1 == DiagnosticCode.boolRequired).single,
      tag.single,
    );
  });

  test('anchors a schema in another file by its components key', () {
    final found = check(
      r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components: {schemas: {Err: {$ref: "common.yaml#/Error"}}}
''',
      files: {'common.yaml': 'Error: {type: object, bogus: 1}\n'},
    );
    expect(found.single.$2, '@/schemas/Err#/bogus');
  });

  test('anchors a place without an address by the file and pointer, '
      'relative to the baseline file', () {
    final found = check(
      'openapi: 3.0.3\ninfo: {version: "1"}\npaths: {}\n',
      baseline: 'baselines/api.baseline.yaml',
    );
    expect(found.single.$2, '../api.yaml#/info');
  });

  test('a finding with args differs from one at the same place without '
      'them', () {
    final found = check('openapi: 3.0.3\ninfo: {}\npaths: {}\n');
    expect(found.map((d) => (d.$1, d.$2)), [
      (DiagnosticCode.missingRequiredField, 'api.yaml#/info'),
      (DiagnosticCode.missingRequiredField, 'api.yaml#/info'),
    ]);
    expect(found.first.$3, isNot(found.last.$3));
  });

  group('Fingerprints.of', () {
    final fingerprints = Fingerprints(
      AnchorIndex.none(),
      p.join('work', 'api.baseline.yaml'),
      DisplayPaths(p.join(p.rootPrefix(p.current), 'repo')),
    );
    Diagnostic diagnostic(
      String message, {
      DiagnosticCode code = DiagnosticCode.unknownKey,
      String? file = 'work/api.yaml',
    }) => Diagnostic(
      code: code,
      severity: Severity.warning,
      message: message,
      file: file,
      pointer: JsonPointer.parse('#/info/x'),
    );

    test('ignores the message', () {
      expect(
        fingerprints.of(diagnostic('Unknown key "x".')),
        fingerprints.of(diagnostic('The key "x" is not defined.')),
      );
    });

    test('depends on the code', () {
      expect(
        fingerprints.of(diagnostic('m')),
        isNot(
          fingerprints.of(
            diagnostic('m', code: DiagnosticCode.invalidValue),
          ),
        ),
      );
    });

    test('is 12 hex digits of SHA-256 over [code, anchor, args]', () {
      expect(fingerprints.anchorOf(diagnostic('m')), 'api.yaml#/info/x');
      expect(fingerprints.of(diagnostic('m')), 'ed41f0665b98');
      expect(
        Fingerprints.hash(DiagnosticCode.unknownKey, 'api.yaml#/info/x', []),
        'ed41f0665b98',
      );
    });

    test('a diagnostic without a file is anchored by its pointer', () {
      expect(fingerprints.anchorOf(diagnostic('m', file: null)), '#/info/x');
    });
  });
}
```

- [ ] **Step 2: Запустити тест**

Run (з `packages/typed_openapi`): `dart test test/baseline/fingerprints_test.dart`
Expected: FAIL — компіляція: `anchor_index.dart` і `fingerprints.dart` не існують.

- [ ] **Step 3: Реалізація**

Файл `packages/typed_openapi/lib/src/baseline/anchor_index.dart` (новий):

```dart
import '../diagnostics/json_pointer.dart';
import '../model/operation.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';
import '../resolve/spec_documents.dart';
import '../resolve/spec_model.dart';

/// The logical addresses of a spec's nodes: the part of a baseline anchor
/// that survives edits elsewhere in the spec.
///
/// An address is the path of keys the overrides file uses for the node:
/// `operations`, `METHOD /path`, then `parameters` and `in:name` for a
/// parameter the operation defines itself; `schemas` and the
/// `components.schemas` key (a key that defines its schema wins over one
/// that refers to it), then `properties` and the name for a property. A
/// path-level parameter, a webhook and a node no address reaches have
/// none; their anchor is the file and the JSON pointer.
final class AnchorIndex {
  /// Indexes the operations, parameters, schemas and properties of [model],
  /// whose files are [documents].
  AnchorIndex(SpecModel model, SpecDocuments documents) {
    for (final document in documents.loaded) {
      _documents[documents.displayPath(document.uri)] = document.uri;
    }
    for (final MapEntry(key: path, value: written)
        in model.document.paths.entries) {
      final item = model.resolve(written);
      if (item == null) continue;
      for (final MapEntry(key: method, value: operation)
          in item.operations.entries) {
        final address = ['operations', '${method.toUpperCase()} $path'];
        _put(operation.location, address);
        for (final parameter in operation.parameters) {
          if (parameter case Inline(
            value: Parameter(:final name?, :final placement?, :final location),
          )) {
            _put(location, [
              ...address,
              'parameters',
              '${placement.name}:$name',
            ]);
          }
        }
      }
    }
    final schemas = model.document.components?.schemas ?? const {};
    final keys = [
      for (final MapEntry(:key, :value) in schemas.entries)
        if (_isDefinition(value)) key,
      for (final MapEntry(:key, :value) in schemas.entries)
        if (!_isDefinition(value)) key,
    ];
    for (final key in keys) {
      final schema = model.resolveSchema(schemas[key]!);
      if (schema == null) continue;
      _put(schema.location, ['schemas', key]);
      if (schema is! SchemaObject) continue;
      for (final MapEntry(key: name, value: property)
          in schema.properties.entries) {
        _put(property.location, ['schemas', key, 'properties', name]);
      }
    }
  }

  /// An index without logical addresses, for a spec that was not read.
  AnchorIndex.none();

  final Map<String, Uri> _documents = {};
  final Map<SpecLocation, List<String>> _addresses = {};

  /// The address of the closest node at or above [pointer] in the file
  /// diagnostics name [file], and the pointer from that node down to
  /// [pointer]; null when no node on the way has an address.
  (List<String>, JsonPointer)? addressOf(String file, JsonPointer pointer) {
    final uri = _documents[file];
    if (uri == null) return null;
    final tokens = pointer.tokens;
    for (var length = tokens.length; length >= 0; length--) {
      final at = tokens.take(length).fold(JsonPointer.root, _child);
      final address = _addresses[SpecLocation(uri, at)];
      if (address == null) continue;
      return (address, tokens.skip(length).fold(JsonPointer.root, _child));
    }
    return null;
  }

  void _put(SpecLocation location, List<String> address) =>
      _addresses.putIfAbsent(location, () => address);

  static JsonPointer _child(JsonPointer pointer, String token) =>
      pointer.child(token);

  static bool _isDefinition(Schema schema) =>
      schema is! SchemaObject || schema.ref == null;
}
```

Файл `packages/typed_openapi/lib/src/baseline/fingerprints.dart` (новий):

```dart
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../diagnostics/diagnostic.dart';
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/display_paths.dart';
import '../diagnostics/json_pointer.dart';
import 'anchor_index.dart';

/// The anchors and fingerprints of a client's diagnostics, by which its
/// baseline file matches them.
///
/// A fingerprint is the first 12 hex digits of the SHA-256 of the JSON
/// array `[code, anchor, args]` ([Diagnostic.args]). The message text and
/// the line and column are not part of it, so rewording a message or
/// editing the spec elsewhere keeps it.
///
/// An anchor is `@<address>#<pointer>` when [AnchorIndex] has a logical
/// address for the place (`@/operations/GET ~1pets/parameters/query:limit#/schema`),
/// and `<file>#<pointer>` otherwise, with the file relative to the baseline
/// file's directory in `/` form (`api.yaml#/info`).
final class Fingerprints {
  /// Creates the fingerprints of diagnostics about the spec [_index]
  /// indexes, for the baseline file at [baselineFile]; [_paths] reads the
  /// file names diagnostics carry.
  Fingerprints(
    this._index,
    String baselineFile, [
    this._paths = const DisplayPaths(),
  ]) : _baselineDirectory = p.dirname(_paths.absolute(baselineFile));

  /// How many hex digits of the hash a fingerprint keeps.
  static const length = 12;

  final AnchorIndex _index;
  final DisplayPaths _paths;
  final String _baselineDirectory;

  /// The fingerprint of [diagnostic].
  String of(Diagnostic diagnostic) =>
      hash(diagnostic.code, anchorOf(diagnostic), diagnostic.args);

  /// Where [diagnostic] is, written to survive edits elsewhere in the spec.
  String anchorOf(Diagnostic diagnostic) {
    final file = diagnostic.file;
    final pointer = diagnostic.pointer;
    if (file == null) return pointer?.value ?? '';
    if (pointer != null) {
      if (_index.addressOf(file, pointer) case (final address, final rest)) {
        final at = address.fold(JsonPointer.root, (a, key) => a.child(key));
        return '@${at.value.substring(1)}${rest.value}';
      }
    }
    return '${_fileName(file)}${pointer?.value ?? ''}';
  }

  /// The fingerprint of a [code] finding at [anchor] with [args].
  static String hash(DiagnosticCode code, String anchor, List<String> args) {
    final input = jsonEncode([code.id, anchor, args]);
    return '${sha256.convert(utf8.encode(input))}'.substring(0, length);
  }

  String _fileName(String file) {
    final full = _paths.absolute(file);
    try {
      return p.posix.joinAll(
        p.split(p.relative(full, from: _baselineDirectory)),
      );
    } on p.PathException {
      // On another drive than the baseline file.
      return p.posix.joinAll(p.split(full));
    }
  }
}
```

Diff `packages/typed_openapi/lib/src/diagnostics/diagnostic.dart`, `packages/typed_openapi/lib/src/diagnostics/diagnostic_bag.dart`, `packages/typed_openapi/lib/src/parse/object_reader.dart`, `packages/typed_openapi/lib/src/parse/operation_parser.dart`, `packages/typed_openapi/lib/src/parse/parse_context.dart`, `packages/typed_openapi/pubspec.yaml` (`git apply` з кореня):

```diff
diff --git a/packages/typed_openapi/lib/src/diagnostics/diagnostic.dart b/packages/typed_openapi/lib/src/diagnostics/diagnostic.dart
index f09c110..af04807 100644
--- a/packages/typed_openapi/lib/src/diagnostics/diagnostic.dart
+++ b/packages/typed_openapi/lib/src/diagnostics/diagnostic.dart
@@ -18,6 +18,7 @@ final class Diagnostic implements Comparable<Diagnostic> {
     this.pointer,
     this.span,
     this.fix,
+    this.args = const [],
   });
 
   /// The stable code from the catalog.
@@ -41,6 +42,11 @@ final class Diagnostic implements Comparable<Diagnostic> {
   /// What to change in the source to fix the finding.
   final String? fix;
 
+  /// Values from the spec that tell this finding from another of the same
+  /// code at the same place, such as the name of a missing field; part of
+  /// the baseline fingerprint, unlike [message].
+  final List<String> args;
+
   /// The 1-based line of the finding, or null when the position is unknown.
   int? get line {
     final start = span?.start;
@@ -62,6 +68,7 @@ final class Diagnostic implements Comparable<Diagnostic> {
     pointer: pointer,
     span: span,
     fix: fix,
+    args: args,
   );
 
   /// `file:line:column`, `file` when only the file is known, or null.
diff --git a/packages/typed_openapi/lib/src/diagnostics/diagnostic_bag.dart b/packages/typed_openapi/lib/src/diagnostics/diagnostic_bag.dart
index 6daa1dd..f4307f7 100644
--- a/packages/typed_openapi/lib/src/diagnostics/diagnostic_bag.dart
+++ b/packages/typed_openapi/lib/src/diagnostics/diagnostic_bag.dart
@@ -57,6 +57,7 @@ final class DiagnosticBag {
     JsonPointer? pointer,
     SourceSpan? span,
     String? fix,
+    List<String> args = const [],
   }) {
     add(
       Diagnostic(
@@ -67,6 +68,7 @@ final class DiagnosticBag {
         pointer: pointer,
         span: span,
         fix: fix,
+        args: args,
       ),
     );
   }
diff --git a/packages/typed_openapi/lib/src/parse/object_reader.dart b/packages/typed_openapi/lib/src/parse/object_reader.dart
index 60d6b1c..6fb6252 100644
--- a/packages/typed_openapi/lib/src/parse/object_reader.dart
+++ b/packages/typed_openapi/lib/src/parse/object_reader.dart
@@ -336,6 +336,7 @@ final class ObjectReader {
       .missingRequiredField,
       'The required field "$key" is missing.',
       pointer,
+      args: [key],
     );
   }
 }
diff --git a/packages/typed_openapi/lib/src/parse/operation_parser.dart b/packages/typed_openapi/lib/src/parse/operation_parser.dart
index 4fac926..bc7367b 100644
--- a/packages/typed_openapi/lib/src/parse/operation_parser.dart
+++ b/packages/typed_openapi/lib/src/parse/operation_parser.dart
@@ -173,6 +173,7 @@ final class OperationParser {
         .missingRequiredField,
         'The required field "content" is missing.',
         r.pointer,
+        args: const ['content'],
       );
     }
     return _context.register(
diff --git a/packages/typed_openapi/lib/src/parse/parse_context.dart b/packages/typed_openapi/lib/src/parse/parse_context.dart
index 7c344bc..1baf19b 100644
--- a/packages/typed_openapi/lib/src/parse/parse_context.dart
+++ b/packages/typed_openapi/lib/src/parse/parse_context.dart
@@ -86,6 +86,7 @@ final class ParseContext {
     String message,
     JsonPointer pointer, {
     String? fix,
+    List<String> args = const [],
   }) {
     diagnostics.report(
       code,
@@ -94,6 +95,7 @@ final class ParseContext {
       pointer: pointer,
       span: document.spanOf(pointer),
       fix: fix,
+      args: args,
     );
   }
 
diff --git a/packages/typed_openapi/pubspec.yaml b/packages/typed_openapi/pubspec.yaml
index bc75c3f..2fe8bd9 100644
--- a/packages/typed_openapi/pubspec.yaml
+++ b/packages/typed_openapi/pubspec.yaml
@@ -18,6 +18,7 @@ dependencies:
   # collection and string_scanner are used by the YAML scanner copied from
   # package:yaml into lib/src/load/yaml.
   collection: ^1.15.0
+  crypto: ^3.0.6
   io: ^1.1.0
   path: ^1.9.1
   source_span: ^1.10.2
```

Run (з кореня): `dart pub get`
Expected: `Got dependencies!` (додано `crypto`).

- [ ] **Step 4: Перевірити**

Run (з `packages/typed_openapi`): `dart test`
Expected: PASS, 444 тести (`+444: All tests passed!`).

Run (з `packages/typed_openapi`): `dart format lib test bin` двічі
Expected: другий запуск — `0 changed`.

Run (з кореня): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 5: Коміт**

```bash
git add packages/typed_openapi
git commit -m "feat(typed_openapi): fingerprint diagnostics by code, anchor and args" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4: Файл baseline, `baseline create` / `prune`, зіставлення в `check` (TOA820–TOA823)

**Files:**
- Create: `lib/src/baseline/baseline.dart`, `lib/src/baseline/baseline_loader.dart`, `lib/src/cli/baseline_command.dart`, `test/baseline/baseline_test.dart`
- Modify: `lib/src/diagnostics/diagnostic_code.dart`, `lib/src/diagnostics/diagnostic_bag.dart`, `lib/src/diagnostics/reporters.dart`, `lib/src/config/config_loader.dart`, `lib/src/check/spec_checker.dart`, `lib/src/cli/check_command.dart`, `lib/src/cli/cli.dart`
- Test: `test/check/spec_checker_test.dart`, `test/cli/cli_test.dart`, `test/config/config_loader_test.dart`, `test/diagnostics/reporters_test.dart`

**Interfaces:**
- Consumes: `AnchorIndex`, `Fingerprints` (задача 3); `SeverityLevels`, `fixedCodes` (задача 2); `DisplayPaths` (задача 1); `SpecLoader.parse` (компоновщик M3).
- Produces: `Baseline`, `BaselineEntry`, `BaselineMatch`, `BaselineLoader`, `ClientCheck`, `SpecChecker.checkClients`, `SpecChecker.check(strictBaseline:)`, `DiagnosticBag.addBaselined` / `baselined`, `DiagnosticReporter.format(showBaselined:)`, команди `baseline create` / `baseline prune`, прапорці `--show-baselined` / `--strict-baseline`.

Поведінка, яку закріплюють тести: `Baseline.of` групує однакові fingerprint-и з `count`, сортує, пропускає незмінні коди; файл, записаний `toYaml`, читається назад без діагностик і записується так само; зіставлення приймає до `count` у порядку звіту; запис без знахідок і запис з меншою кількістю — застарілі; `pruned` прибирає перші й зменшує другі; читач: порожній файл — без записів; без `version` чи з `version: 2` — помилка; поганий fingerprint, `count: 0`, не мапа — помилка й запис пропущено; невідомий ключ і повтор fingerprint — warning; синтаксична помилка, відсутній файл, каталог. `check`: прийняті сховано й пораховано, застарілий запис — warning у позиції запису (рядок 3), з `--strict-baseline` — error; baseline, що збігається з усім, — порожній звіт; зламаний файл — помилка й нічого не сховано. CLI: `create` → `check` з кодом `0` і `baselined: 2`, `--show-baselined`, нова проблема валить `check`, виправлена лишає застарілий запис, `prune` його прибирає; відсутній файл — TOA820 у `check` і `prune`; без `baseline` у конфігу — код `64`. Конфіг: два клієнти з одним файлом — TOA902. JSON: `baselined` у кожній діагностиці і в `summary`.

- [ ] **Step 1: Тести, що не проходять**

Файл `packages/typed_openapi/test/baseline/baseline_test.dart` (новий):

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/baseline/anchor_index.dart';
import 'package:typed_openapi/src/baseline/baseline.dart';
import 'package:typed_openapi/src/baseline/baseline_loader.dart';
import 'package:typed_openapi/src/baseline/fingerprints.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/display_paths.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';

import '../helpers/temp_dir.dart';

void main() {
  final fingerprints = Fingerprints(
    AnchorIndex.none(),
    '/work/api.baseline.yaml',
    const DisplayPaths('/work'),
  );

  Diagnostic finding(
    String key, {
    DiagnosticCode code = DiagnosticCode.unknownKey,
    String message = 'Unknown key.',
  }) => Diagnostic(
    code: code,
    severity: code.defaultSeverity,
    message: message,
    file: 'api.yaml',
    pointer: JsonPointer.root.child(key),
  );

  final b = finding('b');
  final a1 = finding('a', message: 'First.');
  final a2 = finding('a', message: 'Second.');
  final missing = finding('a', code: DiagnosticCode.inputNotFound);

  test('of groups equal fingerprints, sorts and skips fixed codes', () {
    final baseline = Baseline.of('api.baseline.yaml', [
      b,
      a2,
      missing,
      a1,
    ], fingerprints);
    final hashA = Fingerprints.hash(
      DiagnosticCode.unknownKey,
      'api.yaml#/a',
      const [],
    );
    final hashB = Fingerprints.hash(
      DiagnosticCode.unknownKey,
      'api.yaml#/b',
      const [],
    );
    expect(
      baseline.toYaml(),
      '# Diagnostics accepted for this client: typed_openapi check\n'
      '# hides them. Written by `typed_openapi baseline create`;\n'
      '# `typed_openapi baseline prune` removes stale entries.\n'
      'version: 1\n'
      'entries:\n'
      '  - fingerprint: "$hashA"\n'
      '    code: "TOA110"\n'
      '    anchor: "api.yaml#/a"\n'
      '    message: "First."\n'
      '    count: 2\n'
      '  - fingerprint: "$hashB"\n'
      '    code: "TOA110"\n'
      '    anchor: "api.yaml#/b"\n'
      '    message: "Unknown key."\n',
    );
  });

  test('an empty baseline is written as an empty list', () {
    expect(
      const Baseline('x.yaml', []).toYaml(),
      endsWith('version: 1\nentries: []\n'),
    );
  });

  test('the written file reads back without diagnostics', () {
    final written = Baseline.of('api.baseline.yaml', [
      a1,
      a2,
      b,
    ], fingerprints).toYaml();
    final bag = DiagnosticBag();
    final read = BaselineLoader(bag).parse(written, 'b.yaml')!;
    expect(bag.all, isEmpty);
    expect(read.entries.map((e) => (e.anchor, e.count, e.pointer.value)), [
      ('api.yaml#/a', 2, '#/entries/0'),
      ('api.yaml#/b', 1, '#/entries/1'),
    ]);
    expect(read.toYaml(), written);
  });

  group('match', () {
    final baseline = Baseline.of('x.yaml', [a1, b], fingerprints);

    test('accepts up to the count and shows the rest', () {
      final match = baseline.match([a2, a1, b, missing], fingerprints);
      expect(match.baselined, [a1, b]);
      expect(match.shown, [missing, a2]);
      expect(match.stale, isEmpty);
    });

    test('an entry with fewer findings than its count is stale', () {
      final match = baseline.match([b], fingerprints);
      expect(match.baselined, [b]);
      expect(match.stale.map((s) => (s.$1.anchor, s.$2)), [
        ('api.yaml#/a', 0),
      ]);
    });

    test('pruned drops entries without findings and lowers counts', () {
      final twice = Baseline.of('x.yaml', [a1, a2, b], fingerprints);
      final pruned = twice.pruned(twice.match([a1], fingerprints));
      expect(pruned.entries.map((e) => (e.anchor, e.count)), [
        ('api.yaml#/a', 1),
      ]);
    });
  });

  group('BaselineLoader', () {
    List<(DiagnosticCode, Severity, String?)> problems(String text) {
      final bag = DiagnosticBag();
      BaselineLoader(bag).parse(text, 'b.yaml');
      return [for (final d in bag.all) (d.code, d.severity, d.pointer?.value)];
    }

    test('a blank file has no entries and no problems', () {
      final bag = DiagnosticBag();
      expect(
        BaselineLoader(bag).parse('# nothing yet\n', 'b.yaml')!.entries,
        isEmpty,
      );
      expect(bag.all, isEmpty);
    });

    test('rejects a missing or unknown version', () {
      expect(problems('entries: []\n'), [
        (DiagnosticCode.invalidBaseline, Severity.error, '#'),
      ]);
      expect(problems('version: 2\nentries: []\n'), [
        (DiagnosticCode.invalidBaseline, Severity.error, '#/version'),
      ]);
    });

    test('skips bad entries and warns about unknown keys and repeats', () {
      expect(
        problems('''
version: 1
entries:
  - {fingerprint: "ABC"}
  - {fingerprint: "0123456789ab", count: 0}
  - {fingerprint: "0123456789ab", note: x}
  - {fingerprint: "0123456789ab"}
  - just text
'''),
        [
          (
            DiagnosticCode.invalidBaseline,
            Severity.error,
            '#/entries/0/fingerprint',
          ),
          (DiagnosticCode.invalidBaseline, Severity.error, '#/entries/1/count'),
          (
            DiagnosticCode.invalidBaseline,
            Severity.warning,
            '#/entries/2/note',
          ),
          (DiagnosticCode.invalidBaseline, Severity.warning, '#/entries/3'),
          (DiagnosticCode.invalidBaseline, Severity.error, '#/entries/4'),
        ],
      );
    });

    test('reports a syntax error as invalid-baseline', () {
      expect(
        problems('version: [1\n').single.$1,
        DiagnosticCode.invalidBaseline,
      );
    });

    test('reports a missing file and a directory', () {
      final dir = TempDir();
      final bag = DiagnosticBag();
      final loader = BaselineLoader(bag);
      expect(
        loader.load('${dir.path}/none.yaml', displayPath: 'none.yaml'),
        isNull,
      );
      expect(loader.load(dir.path, displayPath: 'dir'), isNull);
      expect(bag.all.map((d) => (d.code, d.file)), [
        (DiagnosticCode.baselineNotFound, 'none.yaml'),
        (DiagnosticCode.invalidBaseline, 'dir'),
      ]);
    });
  });
}
```

Diff `packages/typed_openapi/test/check/spec_checker_test.dart`, `packages/typed_openapi/test/cli/cli_test.dart`, `packages/typed_openapi/test/config/config_loader_test.dart`, `packages/typed_openapi/test/diagnostics/reporters_test.dart` (`git apply` з кореня):

```diff
diff --git a/packages/typed_openapi/test/check/spec_checker_test.dart b/packages/typed_openapi/test/check/spec_checker_test.dart
index 604e71c..c43cf85 100644
--- a/packages/typed_openapi/test/check/spec_checker_test.dart
+++ b/packages/typed_openapi/test/check/spec_checker_test.dart
@@ -1,5 +1,6 @@
 import 'package:path/path.dart' as p;
 import 'package:test/test.dart';
+import 'package:typed_openapi/src/baseline/fingerprints.dart';
 import 'package:typed_openapi/src/check/spec_checker.dart';
 import 'package:typed_openapi/src/config/config_loader.dart';
 import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
@@ -363,4 +364,125 @@ clients:
     ).check(ConfigLoader(bag).load(path)!);
     expect(bag.all, isEmpty);
   });
+
+  group('baseline', () {
+    const spec = '''
+openapi: 3.0.3
+info: {title: t, version: "1"}
+components:
+  schemas:
+    Tag:
+      type: object
+      properties:
+        name: {type: string, required: true}
+        id: {type: string, required: true}
+''';
+
+    DiagnosticBag check(String baseline, {bool strict = false}) {
+      final dir = TempDir();
+      dir.write('api.yaml', spec);
+      dir.write('api.baseline.yaml', baseline);
+      final path = dir.write('typed_openapi.yaml', '''
+clients:
+  api: {input: api.yaml, output: lib/api, baseline: api.baseline.yaml}
+''');
+      final bag = DiagnosticBag();
+      SpecChecker(
+        bag,
+        DisplayPaths(dir.path),
+      ).check(ConfigLoader(bag).load(path)!, strictBaseline: strict);
+      return bag;
+    }
+
+    const name = '@/schemas/Tag/properties/name#/required';
+    final nameFingerprint = Fingerprints.hash(
+      DiagnosticCode.boolRequired,
+      name,
+      const [],
+    );
+
+    test('hides accepted diagnostics and shows the rest', () {
+      final bag = check('''
+version: 1
+entries:
+  - {fingerprint: "$nameFingerprint", code: TOA201, anchor: "$name"}
+''');
+      expect(bag.all.map((d) => (d.code, d.pointer?.value)), [
+        (
+          DiagnosticCode.boolRequired,
+          '#/components/schemas/Tag/properties/id/required',
+        ),
+      ]);
+      expect(bag.baselined.map((d) => d.pointer?.value), [
+        '#/components/schemas/Tag/properties/name/required',
+      ]);
+    });
+
+    test('an entry with nothing to match is stale; strict makes it an '
+        'error', () {
+      const stale = '''
+version: 1
+entries:
+  - {fingerprint: "000000000000", code: TOA201, anchor: "@/schemas/Gone#"}
+''';
+      final bag = check(stale);
+      final entry = bag.all.where(
+        (d) => d.code == DiagnosticCode.baselineEntryStale,
+      );
+      expect(entry.single.severity, Severity.warning);
+      expect(entry.single.file, 'api.baseline.yaml');
+      expect(entry.single.pointer?.value, '#/entries/0');
+      expect(entry.single.line, 3);
+      expect(
+        check(stale, strict: true).all
+            .where((d) => d.code == DiagnosticCode.baselineEntryStale)
+            .single
+            .severity,
+        Severity.error,
+      );
+    });
+
+    test('an entry that accepts more than the check finds is stale', () {
+      final bag = check('''
+version: 1
+entries:
+  - {fingerprint: "$nameFingerprint", count: 3}
+''');
+      expect(bag.baselined.length, 1);
+      expect(
+        bag.all
+            .where((d) => d.code == DiagnosticCode.baselineEntryStale)
+            .single
+            .message,
+        'This entry accepts 3 diagnostics (A diagnostic at $nameFingerprint), '
+        'but the check finds 1.',
+      );
+    });
+
+    test('a valid baseline that matches everything reports nothing', () {
+      final id = Fingerprints.hash(
+        DiagnosticCode.boolRequired,
+        '@/schemas/Tag/properties/id#/required',
+        const [],
+      );
+      final bag = check('''
+version: 1
+entries:
+  - {fingerprint: "$nameFingerprint"}
+  - {fingerprint: "$id"}
+''');
+      expect(bag.all, isEmpty);
+      expect(bag.baselined.length, 2);
+    });
+
+    test('a broken baseline file hides nothing', () {
+      final bag = check('version: 2\nentries: []\n');
+      expect(bag.all.map((d) => d.code), [
+        DiagnosticCode.boolRequired,
+        DiagnosticCode.boolRequired,
+        DiagnosticCode.invalidBaseline,
+      ]);
+      expect(bag.baselined, isEmpty);
+    });
+  });
 }
diff --git a/packages/typed_openapi/test/cli/cli_test.dart b/packages/typed_openapi/test/cli/cli_test.dart
index 5e9bf52..f6a1297 100644
--- a/packages/typed_openapi/test/cli/cli_test.dart
+++ b/packages/typed_openapi/test/cli/cli_test.dart
@@ -1,4 +1,5 @@
 import 'dart:convert';
+import 'dart:io';
 
 import 'package:path/path.dart' as p;
 import 'package:test/test.dart';
@@ -65,7 +66,12 @@ clients:
       'json',
     ]);
     final json = jsonDecode(out) as Map<String, Object?>;
-    expect(json['summary'], {'error': 1, 'warning': 0, 'info': 0});
+    expect(json['summary'], {
+      'error': 1,
+      'warning': 0,
+      'info': 0,
+      'baselined': 0,
+    });
   });
 
   test('exits 78 when the config file is missing', () async {
@@ -232,4 +238,129 @@ clients:
     expect(out, contains('warning TOA504 duplicate-operation-id'));
     expect(out, endsWith('errors: 0, warnings: 1, infos: 0\n'));
   });
+
+  group('baseline', () {
+    const spec = '''
+openapi: 3.0.3
+info: {title: api, version: "1"}
+paths:
+  /a: {get: {operationId: same, responses: {'200': {description: ok}}}}
+  /b: {get: {operationId: same, responses: {'200': {description: ok}}}}
+components:
+  schemas:
+    Tag:
+      type: object
+      properties:
+        name: {type: string, required: true}
+''';
+    late TempDir dir;
+    late String config;
+
+    setUp(() {
+      dir = TempDir();
+      dir.write('api.yaml', spec);
+      config = dir.write('typed_openapi.yaml', '''
+clients:
+  api: {input: api.yaml, output: lib/api, baseline: api.baseline.yaml}
+''');
+    });
+
+    Future<(int, String, String)> inDir(List<String> args) =>
+        run([...args, '-c', config], workingDirectory: dir.path);
+
+    test('create accepts the current diagnostics; check hides them', () async {
+      final (created, createOut, _) = await inDir(['baseline', 'create']);
+      expect(created, 0);
+      expect(
+        createOut,
+        'errors: 0, warnings: 0, infos: 0\n'
+        'Wrote api.baseline.yaml: 2 entries accept 2 diagnostics.\n',
+      );
+      expect(
+        File(p.join(dir.path, 'api.baseline.yaml')).readAsStringSync(),
+        contains('code: "TOA504"'),
+      );
+      final (code, out, _) = await inDir(['check']);
+      expect(code, 0);
+      expect(out, 'errors: 0, warnings: 0, infos: 0, baselined: 2\n');
+      final (_, shown, _) = await inDir(['check', '--show-baselined']);
+      expect(
+        shown,
+        contains('error TOA504 duplicate-operation-id [baselined]: '),
+      );
+    });
+
+    test('check fails on a new problem only', () async {
+      await inDir(['baseline', 'create']);
+      dir.write(
+        'api.yaml',
+        spec.replaceFirst(
+          '/b: {get: {operationId: same',
+          '/b: {get: {operationId: same, parameters: [{name: x, in: path}]',
+        ),
+      );
+      final (code, out, _) = await inDir(['check']);
+      expect(code, 1);
+      expect(out, contains('error TOA502 path-parameter-not-in-template'));
+      expect(out, isNot(contains('TOA504')));
+      expect(out, endsWith('baselined: 2\n'));
+    });
+
+    test('a fixed problem leaves a stale entry; prune removes it', () async {
+      await inDir(['baseline', 'create']);
+      dir.write('api.yaml', spec.replaceFirst('required: true', 'x: 1'));
+      final (code, out, _) = await inDir(['check']);
+      expect(code, 0);
+      expect(
+        out,
+        contains(
+          'warning TOA822 baseline-entry-stale: No diagnostic matches this '
+          'entry (TOA201 at @/schemas/Tag/properties/name#/required); the '
+          'problem is gone.\n'
+          '  --> api.baseline.yaml:',
+        ),
+      );
+      expect(out, contains('  fix: Run `typed_openapi baseline prune`'));
+      final (strict, _, _) = await inDir(['check', '--strict-baseline']);
+      expect(strict, 1);
+      final (pruned, pruneOut, _) = await inDir(['baseline', 'prune']);
+      expect(pruned, 0);
+      expect(
+        pruneOut,
+        contains('Pruned api.baseline.yaml: removed 1 entries, 1 left.'),
+      );
+      final (after, afterOut, _) = await inDir(['check']);
+      expect(after, 0);
+      expect(afterOut, contains('baselined: 1\n'));
+      expect(afterOut, isNot(contains('TOA822')));
+    });
+
+    test('a missing baseline file is an error and hides nothing', () async {
+      final (code, out, _) = await inDir(['check']);
+      expect(code, 1);
+      expect(out, contains('error TOA820 baseline-not-found'));
+      expect(out, contains('error TOA504 duplicate-operation-id'));
+    });
+
+    test('prune reports a missing baseline file', () async {
+      final (code, out, _) = await inDir(['baseline', 'prune']);
+      expect(code, 1);
+      expect(out, contains('error TOA820 baseline-not-found'));
+    });
+
+    test('a client without a baseline is a usage error', () async {
+      final path = dir.write(
+        'other.yaml',
+        'clients:\n  api: {input: api.yaml, output: lib/api}\n',
+      );
+      final (code, _, err) = await run([
+        'baseline',
+        'create',
+        '-c',
+        path,
+      ], workingDirectory: dir.path);
+      expect(code, 64);
+      expect(err, contains('No client has a "baseline" in the config.'));
+    });
+  });
 }
diff --git a/packages/typed_openapi/test/config/config_loader_test.dart b/packages/typed_openapi/test/config/config_loader_test.dart
index 6b0125a..953eb1e 100644
--- a/packages/typed_openapi/test/config/config_loader_test.dart
+++ b/packages/typed_openapi/test/config/config_loader_test.dart
@@ -349,4 +349,22 @@ clients:
       (DiagnosticCode.configInvalid, '#/clients/a/severity'),
     ]);
   });
+
+  test('reports a baseline file two clients share', () {
+    final path = TempDir().write('c.yaml', '''
+clients:
+  a: {input: a.json, output: lib/a, baseline: shared.yaml}
+  b: {input: b.json, output: lib/b, baseline: ./shared.yaml}
+  c: {input: c.json, output: lib/c, baseline: c.yaml}
+''');
+    final bag = DiagnosticBag();
+    ConfigLoader(bag).load(path);
+    expect(bag.all.map((d) => (d.code, d.pointer?.value, d.message)), [
+      (
+        DiagnosticCode.configInvalid,
+        '#/clients/b/baseline',
+        'Clients "a" and "b" name the same baseline file.',
+      ),
+    ]);
+  });
 }
diff --git a/packages/typed_openapi/test/diagnostics/reporters_test.dart b/packages/typed_openapi/test/diagnostics/reporters_test.dart
index 9c84387..f631636 100644
--- a/packages/typed_openapi/test/diagnostics/reporters_test.dart
+++ b/packages/typed_openapi/test/diagnostics/reporters_test.dart
@@ -2,9 +2,12 @@ import 'dart:convert';
 
 import 'package:source_span/source_span.dart';
 import 'package:test/test.dart';
+import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
 import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
+import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
 import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
 import 'package:typed_openapi/src/diagnostics/reporters.dart';
+import 'package:typed_openapi/src/diagnostics/severity.dart';
 
 void main() {
   final source = SourceFile.fromString(
@@ -59,8 +62,68 @@ void main() {
       'line': 2,
       'column': 14,
       'fix': 'Emit OpenAPI 3.',
+      'baselined': false,
+    });
+    expect(json['summary'], {
+      'error': 1,
+      'warning': 0,
+      'info': 1,
+      'baselined': 0,
+    });
+  });
+
+  group('baselined diagnostics', () {
+    DiagnosticBag withBaselined() => sample()
+      ..addBaselined(
+        Diagnostic(
+          code: DiagnosticCode.boolRequired,
+          severity: Severity.warning,
+          message: 'Accepted.',
+          file: 'api.json',
+          pointer: JsonPointer.root.child('a'),
+        ),
+      );
+
+    test('are counted in the summary, not listed', () {
+      final text = const TextReporter().format(withBaselined());
+      expect(text, isNot(contains('Accepted.')));
+      expect(text, endsWith('errors: 1, warnings: 0, infos: 1, baselined: 1'));
+      final json =
+          jsonDecode(const JsonReporter().format(withBaselined()))
+              as Map<String, Object?>;
+      expect((json['diagnostics']! as List<Object?>).length, 2);
+      expect((json['summary']! as Map<String, Object?>)['baselined'], 1);
+    });
+
+    test('are listed and marked with showBaselined', () {
+      final text = const TextReporter().format(
+        withBaselined(),
+        showBaselined: true,
+      );
+      expect(
+        text,
+        contains(
+          'warning TOA201 bool-required [baselined]: Accepted.\n'
+          '  --> api.json\n'
+          '  at #/a\n',
+        ),
+      );
+      final json =
+          jsonDecode(
+                const JsonReporter().format(
+                  withBaselined(),
+                  showBaselined: true,
+                ),
+              )
+              as Map<String, Object?>;
+      final listed = (json['diagnostics']! as List<Object?>)
+          .cast<Map<String, Object?>>();
+      expect(listed.map((d) => (d['code'], d['baselined'])), [
+        ('TOA005', false),
+        ('TOA201', true),
+        ('TOA011', false),
+      ]);
     });
-    expect(json['summary'], {'error': 1, 'warning': 0, 'info': 1});
   });
 
   test('ReportFormat maps each format to its reporter', () {
```

- [ ] **Step 2: Запустити тести**

Run (з `packages/typed_openapi`): `dart test test/baseline test/check test/cli test/config test/diagnostics`
Expected: FAIL — компіляція: `baseline.dart`, `baseline_loader.dart` не існують, `DiagnosticBag` не має `addBaselined`.

- [ ] **Step 3: Реалізація**

Файл `packages/typed_openapi/lib/src/baseline/baseline.dart` (новий):

```dart
import 'dart:convert';

import 'package:source_span/source_span.dart';

import '../diagnostics/diagnostic.dart';
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/json_pointer.dart';
import '../load/spec_document.dart';
import 'fingerprints.dart';

/// One accepted finding of a baseline file.
///
/// Only [fingerprint] and [count] take part in matching; [code], [anchor]
/// and [message] are there for the person who reads the file.
final class BaselineEntry {
  /// Creates an entry.
  const BaselineEntry({
    required this.fingerprint,
    this.code,
    this.anchor,
    this.message,
    this.count = 1,
    this.pointer = JsonPointer.root,
  });

  /// The fingerprint of the accepted diagnostics (see [Fingerprints]).
  final String fingerprint;

  /// The code of the diagnostics, such as `TOA201`.
  final String? code;

  /// Where they are (see [Fingerprints.anchorOf]).
  final String? anchor;

  /// The message of the first of them when the entry was written.
  final String? message;

  /// How many diagnostics with [fingerprint] the entry accepts.
  final int count;

  /// Where the entry is in its baseline file.
  final JsonPointer pointer;

  BaselineEntry _withCount(int count) => BaselineEntry(
    fingerprint: fingerprint,
    code: code,
    anchor: anchor,
    message: message,
    count: count,
    pointer: pointer,
  );
}

/// What a baseline does to a client's diagnostics.
final class BaselineMatch {
  /// Creates a match.
  const BaselineMatch({
    required this.shown,
    required this.baselined,
    required this.stale,
  });

  /// Diagnostics no entry accepts, in report order.
  final List<Diagnostic> shown;

  /// Diagnostics an entry accepts, in report order.
  final List<Diagnostic> baselined;

  /// Entries that accept more diagnostics than there are, with how many
  /// diagnostics they still match.
  final List<(BaselineEntry, int)> stale;
}

/// A client's baseline: the diagnostics it has accepted, so that `check`
/// fails only on new ones (R2.3).
///
/// The file is YAML with `version: 1` and a list of `entries`, sorted by
/// code, anchor and fingerprint; see [toYaml].
final class Baseline {
  /// Creates a baseline named [file] in reports; [source] is the document
  /// it was read from, for positions.
  const Baseline(this.file, this.entries, {SpecDocument? source})
    : _source = source;

  /// A baseline that accepts every diagnostic in [diagnostics] except those
  /// of [DiagnosticCode.fixedCodes], which a baseline never hides.
  factory Baseline.of(
    String file,
    Iterable<Diagnostic> diagnostics,
    Fingerprints fingerprints,
  ) {
    final entries = <String, BaselineEntry>{};
    for (final diagnostic in diagnostics.toList()..sort()) {
      if (DiagnosticCode.fixedCodes.contains(diagnostic.code)) continue;
      final fingerprint = fingerprints.of(diagnostic);
      final entry = entries[fingerprint];
      entries[fingerprint] = entry == null
          ? BaselineEntry(
              fingerprint: fingerprint,
              code: diagnostic.code.id,
              anchor: fingerprints.anchorOf(diagnostic),
              message: diagnostic.message,
            )
          : entry._withCount(entry.count + 1);
    }
    return Baseline(file, _sorted(entries.values));
  }

  /// The version of the file format this tool writes and reads.
  static const version = 1;

  /// The baseline file as diagnostics name it.
  final String file;

  /// The entries, in file order.
  final List<BaselineEntry> entries;

  final SpecDocument? _source;

  /// The source range of [pointer] in the file, if known.
  SourceSpan? spanOf(JsonPointer pointer) => _source?.spanOf(pointer);

  /// Splits [diagnostics] into those the entries accept and the rest.
  ///
  /// An entry accepts up to its count of diagnostics with its fingerprint,
  /// in report order; a diagnostic of [DiagnosticCode.fixedCodes] is never
  /// accepted.
  BaselineMatch match(
    Iterable<Diagnostic> diagnostics,
    Fingerprints fingerprints,
  ) {
    final allowed = <String, int>{};
    for (final entry in entries) {
      allowed[entry.fingerprint] =
          (allowed[entry.fingerprint] ?? 0) + entry.count;
    }
    final used = <String, int>{};
    final shown = <Diagnostic>[];
    final baselined = <Diagnostic>[];
    for (final diagnostic in diagnostics.toList()..sort()) {
      final fingerprint = DiagnosticCode.fixedCodes.contains(diagnostic.code)
          ? null
          : fingerprints.of(diagnostic);
      final count = used[fingerprint] ?? 0;
      if (fingerprint != null && count < (allowed[fingerprint] ?? 0)) {
        used[fingerprint] = count + 1;
        baselined.add(diagnostic);
      } else {
        shown.add(diagnostic);
      }
    }
    final stale = <(BaselineEntry, int)>[];
    for (final entry in entries) {
      final left = used[entry.fingerprint] ?? 0;
      final matched = left < entry.count ? left : entry.count;
      used[entry.fingerprint] = left - matched;
      if (matched < entry.count) stale.add((entry, matched));
    }
    return BaselineMatch(shown: shown, baselined: baselined, stale: stale);
  }

  /// This baseline without what [match] found stale: an entry that matches
  /// nothing is removed, one that matches fewer diagnostics than its count
  /// gets that number. Nothing is added.
  Baseline pruned(BaselineMatch match) {
    final matched = {
      for (final (entry, count) in match.stale) entry: count,
    };
    final kept = <BaselineEntry>[];
    for (final entry in entries) {
      final count = matched[entry];
      if (count == null) {
        kept.add(entry);
      } else if (count > 0) {
        kept.add(entry._withCount(count));
      }
    }
    return Baseline(file, kept);
  }

  /// The baseline file's text: a comment, `version` and the entries sorted
  /// by code, anchor and fingerprint. Strings are written as JSON strings,
  /// which YAML reads unchanged.
  String toYaml() {
    final out = StringBuffer()
      ..writeln('# Diagnostics accepted for this client: typed_openapi check')
      ..writeln('# hides them. Written by `typed_openapi baseline create`;')
      ..writeln('# `typed_openapi baseline prune` removes stale entries.')
      ..writeln('version: $version');
    final sorted = _sorted(entries);
    if (sorted.isEmpty) {
      out.writeln('entries: []');
      return out.toString();
    }
    out.writeln('entries:');
    for (final entry in sorted) {
      out.writeln('  - fingerprint: ${jsonEncode(entry.fingerprint)}');
      for (final (key, value) in [
        ('code', entry.code),
        ('anchor', entry.anchor),
        ('message', entry.message),
      ]) {
        if (value != null) out.writeln('    $key: ${jsonEncode(value)}');
      }
      if (entry.count != 1) out.writeln('    count: ${entry.count}');
    }
    return out.toString();
  }

  static List<BaselineEntry> _sorted(Iterable<BaselineEntry> entries) =>
      entries.toList()..sort((a, b) {
        final byCode = (a.code ?? '').compareTo(b.code ?? '');
        if (byCode != 0) return byCode;
        final byAnchor = (a.anchor ?? '').compareTo(b.anchor ?? '');
        if (byAnchor != 0) return byAnchor;
        return a.fingerprint.compareTo(b.fingerprint);
      });
}
```

Файл `packages/typed_openapi/lib/src/baseline/baseline_loader.dart` (новий):

```dart
import 'dart:io';

import 'package:path/path.dart' as p;

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/json_pointer.dart';
import '../diagnostics/severity.dart';
import '../load/spec_document.dart';
import '../load/spec_loader.dart';
import 'baseline.dart';

/// Reads a client's baseline file into a [Baseline].
///
/// Every problem goes to the [DiagnosticBag] given to the constructor, at
/// its position in the baseline file: a missing file is
/// `baseline-not-found`; text that cannot be read, a wrong `version` and a
/// bad entry are `invalid-baseline` errors (the entry is skipped); an
/// unknown key and a repeated fingerprint are `invalid-baseline` warnings.
final class BaselineLoader {
  /// Creates a loader that reports to [_diagnostics].
  const BaselineLoader(this._diagnostics);

  static final _fingerprint = RegExp(r'^[0-9a-f]{12}$');
  static const _rootKeys = {'version', 'entries'};
  static const _entryKeys = {
    'fingerprint',
    'code',
    'anchor',
    'message',
    'count',
  };

  final DiagnosticBag _diagnostics;

  /// Reads the baseline file at [path]; [displayPath] names it in
  /// diagnostics. Returns null when the file cannot be used at all.
  Baseline? load(String path, {String? displayPath}) {
    final file = displayPath ?? path;
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) {
      _diagnostics.report(
        .baselineNotFound,
        'Baseline file $file does not exist.',
        file: file,
        fix:
            'Write it with `typed_openapi baseline create`, or fix '
            '"baseline" of this client in the config.',
      );
      return null;
    }
    if (type == FileSystemEntityType.directory) {
      _diagnostics.report(
        .invalidBaseline,
        'Baseline path $file is a directory, not a file.',
        file: file,
        fix: 'Point "baseline" of this client at the baseline file itself.',
      );
      return null;
    }
    final String text;
    try {
      text = File(path).readAsStringSync();
    } on FileSystemException catch (e) {
      _diagnostics.report(
        .invalidBaseline,
        'Cannot read $file: ${e.message}.',
        file: file,
      );
      return null;
    }
    return parse(text, file, uri: p.toUri(p.normalize(p.absolute(path))));
  }

  /// Reads a baseline from [text]; [file] names it in diagnostics.
  Baseline? parse(String text, String file, {Uri? uri}) {
    if (text.split('\n').every(_isBlankLine)) return Baseline(file, const []);
    final scratch = DiagnosticBag();
    final document = SpecLoader(scratch).parse(text, file, uri: uri);
    for (final d in scratch.all) {
      _diagnostics.report(
        .invalidBaseline,
        d.message,
        severity: d.severity,
        file: d.file,
        pointer: d.pointer,
        span: d.span,
        fix: d.fix,
      );
    }
    return document == null ? null : _read(document);
  }

  Baseline? _read(SpecDocument document) {
    final root = document.root;
    _unknownKeys(document, root, _rootKeys, .root);
    final version = root['version'];
    if (version != Baseline.version) {
      _invalid(
        document,
        root.containsKey('version')
            ? 'Unsupported baseline version $version; this tool reads '
                  'version ${Baseline.version}.'
            : 'The baseline has no "version".',
        root.containsKey('version') ? JsonPointer.root.child('version') : .root,
        fix: 'Write the file again with `typed_openapi baseline create`.',
      );
      return null;
    }
    final list = root['entries'];
    final listPointer = JsonPointer.root.child('entries');
    if (list is! List<Object?>) {
      _invalid(
        document,
        '"entries" must be a list.',
        root.containsKey('entries') ? listPointer : .root,
      );
      return null;
    }
    final entries = <BaselineEntry>[];
    final seen = <String, JsonPointer>{};
    for (final (index, value) in list.indexed) {
      final at = listPointer.child(index);
      final entry = _entry(document, value, at);
      if (entry == null) continue;
      if (seen[entry.fingerprint] case final first?) {
        _diagnostics.report(
          .invalidBaseline,
          'This entry repeats the fingerprint of the entry at '
          '${first.value}; their counts add up.',
          severity: .warning,
          file: document.file,
          pointer: at,
          span: document.spanOf(at),
        );
      }
      seen.putIfAbsent(entry.fingerprint, () => at);
      entries.add(entry);
    }
    return Baseline(document.file, entries, source: document);
  }

  BaselineEntry? _entry(SpecDocument document, Object? value, JsonPointer at) {
    if (value is! Map<String, Object?>) {
      _invalid(document, 'An entry must be a mapping.', at);
      return null;
    }
    _unknownKeys(document, value, _entryKeys, at);
    final fingerprint = value['fingerprint'];
    if (fingerprint is! String || !_fingerprint.hasMatch(fingerprint)) {
      _invalid(
        document,
        'An entry needs a "fingerprint" of 12 lowercase hex digits; the '
        'entry is ignored.',
        value.containsKey('fingerprint') ? at.child('fingerprint') : at,
      );
      return null;
    }
    final count = value['count'] ?? 1;
    if (count is! int || count < 1) {
      _invalid(
        document,
        '"count" must be a positive integer; the entry is ignored.',
        at.child('count'),
      );
      return null;
    }
    String? text(String key) {
      final text = value[key];
      if (text == null || text is String) return text as String?;
      _invalid(
        document,
        '"$key" must be a string; it is ignored.',
        at.child(key),
      );
      return null;
    }

    return BaselineEntry(
      fingerprint: fingerprint,
      code: text('code'),
      anchor: text('anchor'),
      message: text('message'),
      count: count,
      pointer: at,
    );
  }

  void _unknownKeys(
    SpecDocument document,
    Map<String, Object?> map,
    Set<String> allowed,
    JsonPointer at,
  ) {
    for (final key in map.keys) {
      if (allowed.contains(key)) continue;
      _diagnostics.report(
        .invalidBaseline,
        'Unknown key "$key"; it is ignored.',
        severity: Severity.warning,
        file: document.file,
        pointer: at.child(key),
        span: document.spanOf(at.child(key)),
        fix: 'Allowed keys here: ${(allowed.toList()..sort()).join(', ')}.',
      );
    }
  }

  void _invalid(
    SpecDocument document,
    String message,
    JsonPointer at, {
    String? fix,
  }) {
    _diagnostics.report(
      .invalidBaseline,
      message,
      file: document.file,
      pointer: at,
      span: document.spanOf(at),
      fix: fix,
    );
  }

  static bool _isBlankLine(String line) {
    final t = line.trim();
    return t.isEmpty || t.startsWith('#') || t == '---' || t == '...';
  }
}
```

Файл `packages/typed_openapi/lib/src/cli/baseline_command.dart` (новий):

```dart
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart' show ExitCode;

import '../baseline/baseline.dart';
import '../baseline/baseline_loader.dart';
import '../check/spec_checker.dart';
import '../config/config_loader.dart';
import '../config/project_config.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/display_paths.dart';
import '../diagnostics/reporters.dart';

/// `typed_openapi baseline`: writes and updates the clients' baseline files.
final class BaselineCommand extends Command<int> {
  /// Creates the command; reports are written to [out] and name files as
  /// [paths] does.
  BaselineCommand(StringSink out, [DisplayPaths paths = const DisplayPaths()]) {
    addSubcommand(BaselineCreateCommand(out, paths));
    addSubcommand(BaselinePruneCommand(out, paths));
  }

  @override
  String get name => 'baseline';

  @override
  String get description =>
      'Accept the current diagnostics, or remove entries that no longer '
      'match.';
}

/// What `baseline create` and `baseline prune` share: the config, the
/// clients with a baseline, the report and the exit code.
abstract base class _BaselineSubcommand extends Command<int> {
  _BaselineSubcommand(this._out, this._paths) {
    argParser.addOption(
      'config',
      abbr: 'c',
      defaultsTo: 'typed_openapi.yaml',
      help: 'Path to the config file.',
    );
  }

  final StringSink _out;
  final DisplayPaths _paths;

  @override
  String get invocation =>
      '${runner!.executableName} baseline $name [options] [client...]';

  /// Updates the baseline file of each result's client; reports problems
  /// to [diagnostics] and returns one line per written file.
  List<String> update(List<ClientCheck> results, DiagnosticBag diagnostics);

  @override
  Future<int> run() async {
    final diagnostics = DiagnosticBag();
    final config = ConfigLoader(
      diagnostics,
      _paths,
    ).load(argResults!.option('config')!);
    if (config == null) {
      _out.writeln(const TextReporter().format(diagnostics));
      return ExitCode.config.code;
    }
    final clients = _clients(config);
    final results = SpecChecker(
      diagnostics,
      _paths,
    ).checkClients(config, only: clients);
    final lines = update(results, diagnostics);
    _out.writeln(const TextReporter().format(diagnostics));
    lines.forEach(_out.writeln);
    return diagnostics.hasErrors ? 1 : ExitCode.success.code;
  }

  /// The names of the clients to update: those named on the command line,
  /// or every client with a baseline.
  Set<String> _clients(ProjectConfig config) {
    final named = argResults!.rest.toSet();
    final unknown = named.difference(config.declaredClients);
    if (unknown.isNotEmpty) {
      usageException(
        'Unknown client: ${(unknown.toList()..sort()).join(', ')}.',
      );
    }
    final withBaseline = {
      for (final client in config.clients)
        if (client.baseline != null) client.name,
    };
    final without = named.where((n) => !withBaseline.contains(n)).toList()
      ..sort();
    if (without.isNotEmpty) {
      usageException(
        'No "baseline" in the config for: ${without.join(', ')}.',
      );
    }
    if (withBaseline.isEmpty) {
      usageException('No client has a "baseline" in the config.');
    }
    return named.isEmpty ? withBaseline : named;
  }

  /// Writes [baseline] to [path]; returns whether it was written.
  bool write(Baseline baseline, String path, DiagnosticBag diagnostics) {
    try {
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(baseline.toYaml());
      return true;
    } on FileSystemException catch (e) {
      diagnostics.report(
        .baselineNotWritten,
        'Cannot write ${baseline.file}: ${e.message}.',
        file: baseline.file,
      );
      return false;
    }
  }
}

/// `typed_openapi baseline create`: accepts every current diagnostic.
final class BaselineCreateCommand extends _BaselineSubcommand {
  /// Creates the command; reports are written to [out].
  BaselineCreateCommand(super._out, super._paths);

  @override
  String get name => 'create';

  @override
  String get description =>
      'Write each client\'s baseline file from its current diagnostics.';

  @override
  List<String> update(List<ClientCheck> results, DiagnosticBag diagnostics) {
    final lines = <String>[];
    for (final result in results) {
      final path = result.client.baseline!;
      final baseline = Baseline.of(
        _paths.of(path),
        result.diagnostics,
        result.fingerprints(path, _paths),
      );
      // A baseline never accepts fixed codes, so they stay in the report.
      final accepted = baseline.match(
        result.diagnostics,
        result.fingerprints(path, _paths),
      );
      accepted.shown.forEach(diagnostics.add);
      if (!write(baseline, path, diagnostics)) continue;
      final count = accepted.baselined.length;
      lines.add(
        'Wrote ${baseline.file}: ${baseline.entries.length} entries '
        'accept $count diagnostics.',
      );
    }
    return lines;
  }
}

/// `typed_openapi baseline prune`: removes entries that no longer match.
final class BaselinePruneCommand extends _BaselineSubcommand {
  /// Creates the command; reports are written to [out].
  BaselinePruneCommand(super._out, super._paths);

  @override
  String get name => 'prune';

  @override
  String get description =>
      'Remove the entries of each client\'s baseline file that no longer '
      'match a diagnostic.';

  @override
  List<String> update(List<ClientCheck> results, DiagnosticBag diagnostics) {
    final lines = <String>[];
    for (final result in results) {
      final path = result.client.baseline!;
      final baseline = BaselineLoader(
        diagnostics,
      ).load(path, displayPath: _paths.of(path));
      if (baseline == null) continue;
      final pruned = baseline.pruned(
        baseline.match(result.diagnostics, result.fingerprints(path, _paths)),
      );
      if (!write(pruned, path, diagnostics)) continue;
      final removed = baseline.entries.length - pruned.entries.length;
      lines.add(
        'Pruned ${baseline.file}: removed $removed entries, '
        '${pruned.entries.length} left.',
      );
    }
    return lines;
  }
}
```

Diff `packages/typed_openapi/lib/src/check/spec_checker.dart`, `packages/typed_openapi/lib/src/cli/check_command.dart`, `packages/typed_openapi/lib/src/cli/cli.dart`, `packages/typed_openapi/lib/src/config/config_loader.dart`, `packages/typed_openapi/lib/src/diagnostics/diagnostic_bag.dart`, `packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_openapi/lib/src/diagnostics/reporters.dart` (`git apply` з кореня):

```diff
diff --git a/packages/typed_openapi/lib/src/check/spec_checker.dart b/packages/typed_openapi/lib/src/check/spec_checker.dart
index f1f3232..f1e60ba 100644
--- a/packages/typed_openapi/lib/src/check/spec_checker.dart
+++ b/packages/typed_openapi/lib/src/check/spec_checker.dart
@@ -1,5 +1,8 @@
 import 'package:path/path.dart' as p;
 
+import '../baseline/anchor_index.dart';
+import '../baseline/baseline_loader.dart';
+import '../baseline/fingerprints.dart';
 import '../config/project_config.dart';
 import '../diagnostics/diagnostic.dart';
 import '../diagnostics/diagnostic_bag.dart';
@@ -9,6 +12,27 @@ import '../load/spec_loader.dart';
 import '../normalize/normalizer.dart';
 import '../overrides/override_loader.dart';
 
+/// What checking one client found.
+final class ClientCheck {
+  /// Creates the result for [client].
+  const ClientCheck(this.client, this.diagnostics, this.anchors);
+
+  /// The client.
+  final ClientConfig client;
+
+  /// The diagnostics of the client's spec with the client's levels; codes
+  /// the client turns off are gone.
+  final List<Diagnostic> diagnostics;
+
+  /// The logical addresses of the client's spec, for baseline anchors.
+  final AnchorIndex anchors;
+
+  /// The fingerprints of [diagnostics] for the client's baseline file at
+  /// [baselineFile]; [paths] reads the file names of the diagnostics.
+  Fingerprints fingerprints(String baselineFile, DisplayPaths paths) =>
+      Fingerprints(anchors, baselineFile, paths);
+}
+
 /// Loads every client's spec and reports what is wrong with it.
 ///
 /// Nothing is generated. Problems go to the [DiagnosticBag] given to the
@@ -21,7 +45,69 @@ final class SpecChecker {
   final DiagnosticBag _diagnostics;
   final DisplayPaths _paths;
 
-  /// Checks the spec of every client in [config].
+  /// Checks the spec of every client in [config] and reports what each
+  /// client's baseline does not accept.
+  ///
+  /// See [checkClients] for how specs are checked. A client with a
+  /// `baseline` reports only the diagnostics its baseline does not accept;
+  /// the accepted ones go to [DiagnosticBag.addBaselined]. An entry that
+  /// accepts more than the check finds is `baseline-entry-stale`: a warning,
+  /// or an error with [strictBaseline]. A baseline file that cannot be read
+  /// is reported, and every diagnostic of the client is shown.
+  void check(
+    ProjectConfig config, {
+    Set<String> only = const {},
+    bool strictBaseline = false,
+  }) {
+    for (final result in checkClients(config, only: only)) {
+      final client = result.client;
+      final path = client.baseline;
+      if (path == null) {
+        result.diagnostics.forEach(_diagnostics.add);
+        continue;
+      }
+      final problems = DiagnosticBag();
+      final baseline = BaselineLoader(
+        problems,
+      ).load(path, displayPath: _paths.of(path));
+      if (baseline == null) {
+        result.diagnostics.forEach(_diagnostics.add);
+      } else {
+        final match = baseline.match(
+          result.diagnostics,
+          result.fingerprints(path, _paths),
+        );
+        match.shown.forEach(_diagnostics.add);
+        match.baselined.forEach(_diagnostics.addBaselined);
+        for (final (entry, found) in match.stale) {
+          final what =
+              '${entry.code ?? 'A diagnostic'} at '
+              '${entry.anchor ?? entry.fingerprint}';
+          problems.report(
+            .baselineEntryStale,
+            found == 0
+                ? 'No diagnostic matches this entry ($what); the problem '
+                      'is gone.'
+                : 'This entry accepts ${entry.count} diagnostics ($what), '
+                      'but the check finds $found.',
+            severity: strictBaseline ? .error : null,
+            file: baseline.file,
+            pointer: entry.pointer,
+            span: baseline.spanOf(entry.pointer),
+            fix: 'Run `typed_openapi baseline prune` to update the baseline.',
+          );
+        }
+      }
+      for (final problem in problems.all) {
+        final reported = client.severity.apply(problem);
+        if (reported != null) _diagnostics.add(reported);
+      }
+    }
+  }
+
+  /// Checks the spec of every client in [config]; returns what each client
+  /// found, in client order. Only problems of the config itself go to the
+  /// bag; the rest are in the results.
   ///
   /// Each spec is loaded, its OpenAPI version detected, and then it is read
   /// into the model with its `$ref`s resolved, changed by the client's
@@ -32,50 +118,63 @@ final class SpecChecker {
   /// distinct preset, set of disabled rules and overrides file; each client
   /// then gives the diagnostics of that run its own levels
   /// ([ClientConfig.severity]), because levels change how a finding is
-  /// reported, not what a run finds. The bag reports a diagnostic the
-  /// clients share once. Diagnostics name files
-  /// relative to the working directory (see [DisplayPaths]).
-  void check(ProjectConfig config, {Set<String> only = const {}}) {
+  /// reported, not what a run finds. Diagnostics name files relative to the
+  /// working directory (see [DisplayPaths]).
+  List<ClientCheck> checkClients(
+    ProjectConfig config, {
+    Set<String> only = const {},
+  }) {
     // A run is a file with a preset, a set of disabled rules and overrides.
-    final runs = <(String, Preset?, String, String?), List<Diagnostic>>{};
-    for (final client in config.clients) {
-      if (only.isNotEmpty && !only.contains(client.name)) continue;
-      final rules = (client.disabledRules.toList()..sort()).join(',');
-      final run = (
-        p.absolute(client.input),
-        client.preset,
-        rules,
-        client.overrides,
-      );
-      final found = runs[run] ??= _run(client);
-      for (final diagnostic in found) {
-        final reported = client.severity.apply(diagnostic);
-        if (reported != null) _diagnostics.add(reported);
-      }
-    }
+    final runs = <(String, Preset?, String, String?), ClientCheck>{};
+    return [
+      for (final client in config.clients)
+        if (only.isEmpty || only.contains(client.name))
+          _withLevels(
+            client,
+            runs[(
+              p.absolute(client.input),
+              client.preset,
+              (client.disabledRules.toList()..sort()).join(','),
+              client.overrides,
+            )] ??= _run(
+              client,
+            ),
+          ),
+    ];
   }
 
+  ClientCheck _withLevels(ClientConfig client, ClientCheck run) => ClientCheck(
+    client,
+    [
+      for (final diagnostic in run.diagnostics)
+        ?client.severity.apply(diagnostic),
+    ],
+    run.anchors,
+  );
+
   /// Checks the spec of [client]; returns what the run found, with default
   /// levels.
-  List<Diagnostic> _run(ClientConfig client) {
+  ClientCheck _run(ClientConfig client) {
     final found = DiagnosticBag();
+    ClientCheck result([AnchorIndex? anchors]) =>
+        ClientCheck(client, found.all, anchors ?? AnchorIndex.none());
     final document = SpecLoader(
       found,
     ).load(client.input, displayPath: _paths.of(client.input));
-    if (document == null) return found.all;
+    if (document == null) return result();
     final version = OpenApiVersionDetector(found).detect(document);
-    if (version == null) return found.all;
+    if (version == null) return result();
     final overridesPath = client.overrides;
     final overrides = overridesPath == null
         ? null
         : OverrideLoader(
             found,
           ).load(overridesPath, displayPath: _paths.of(overridesPath));
-    Normalizer(
+    final normalized = Normalizer(
       found,
       disabled: client.disabledRules,
       preset: client.preset,
     ).normalize(document, version, overrides: overrides);
-    return found.all;
+    return result(AnchorIndex(normalized.model, normalized.documents));
   }
 }
diff --git a/packages/typed_openapi/lib/src/cli/check_command.dart b/packages/typed_openapi/lib/src/cli/check_command.dart
index 09f674c..a65eabd 100644
--- a/packages/typed_openapi/lib/src/cli/check_command.dart
+++ b/packages/typed_openapi/lib/src/cli/check_command.dart
@@ -24,6 +24,18 @@ final class CheckCommand extends Command<int> {
         allowed: [for (final format in ReportFormat.values) format.name],
         defaultsTo: ReportFormat.text.name,
         help: 'Report format.',
+      )
+      ..addFlag(
+        'show-baselined',
+        negatable: false,
+        help: 'Also list the diagnostics the baseline accepts, marked.',
+      )
+      ..addFlag(
+        'strict-baseline',
+        negatable: false,
+        help:
+            'Fail on baseline entries that no longer match: run '
+            '`baseline prune` to remove them.',
       );
   }
 
@@ -60,10 +72,19 @@ final class CheckCommand extends Command<int> {
           'Unknown client: ${(unknown.toList()..sort()).join(', ')}.',
         );
       }
-      SpecChecker(diagnostics, _paths).check(config, only: only);
+      SpecChecker(diagnostics, _paths).check(
+        config,
+        only: only,
+        strictBaseline: results.flag('strict-baseline'),
+      );
     }
     final format = ReportFormat.values.byName(results.option('format')!);
-    _out.writeln(format.reporter.format(diagnostics));
+    _out.writeln(
+      format.reporter.format(
+        diagnostics,
+        showBaselined: results.flag('show-baselined'),
+      ),
+    );
     if (config == null) return ExitCode.config.code;
     return diagnostics.hasErrors ? exitHasErrors : ExitCode.success.code;
   }
diff --git a/packages/typed_openapi/lib/src/cli/cli.dart b/packages/typed_openapi/lib/src/cli/cli.dart
index bc5848f..374a944 100644
--- a/packages/typed_openapi/lib/src/cli/cli.dart
+++ b/packages/typed_openapi/lib/src/cli/cli.dart
@@ -4,6 +4,7 @@ import 'package:args/command_runner.dart';
 import 'package:io/io.dart' show ExitCode;
 
 import '../diagnostics/display_paths.dart';
+import 'baseline_command.dart';
 import 'check_command.dart';
 
 /// The `typed_openapi` command line.
@@ -16,13 +17,15 @@ final class TypedOpenApiCli {
   /// to the current directory.
   TypedOpenApiCli({StringSink? out, StringSink? err, String? workingDirectory})
     : _err = err ?? stderr,
-      _runner =
-          CommandRunner<int>(
-            'typed_openapi',
-            'OpenAPI 3.x to Dart client generator.',
-          )..addCommand(
-            CheckCommand(out ?? stdout, DisplayPaths(workingDirectory)),
-          );
+      _runner = CommandRunner<int>(
+        'typed_openapi',
+        'OpenAPI 3.x to Dart client generator.',
+      ) {
+    final paths = DisplayPaths(workingDirectory);
+    _runner
+      ..addCommand(CheckCommand(out ?? stdout, paths))
+      ..addCommand(BaselineCommand(out ?? stdout, paths));
+  }
 
   final CommandRunner<int> _runner;
   final StringSink _err;
diff --git a/packages/typed_openapi/lib/src/config/config_loader.dart b/packages/typed_openapi/lib/src/config/config_loader.dart
index e1bcf80..a9daf76 100644
--- a/packages/typed_openapi/lib/src/config/config_loader.dart
+++ b/packages/typed_openapi/lib/src/config/config_loader.dart
@@ -115,6 +115,7 @@ final class ConfigLoader {
     final clients = <ClientConfig>[];
     final declared = <String>{};
     final outputSpans = <String, SourceSpan?>{};
+    final baselineSpans = <String, SourceSpan?>{};
     for (final MapEntry(key: name, :value) in clientNodes.entries) {
       declared.add(name);
       final pointer = clientsPointer.child(name);
@@ -139,6 +140,7 @@ final class ConfigLoader {
       };
       if (input == null || output == null) continue;
       outputSpans[name] = reader.spanAt(pointer.child('output'));
+      baselineSpans[name] = reader.spanAt(pointer.child('baseline'));
       clients.add(
         ClientConfig(
           name: name,
@@ -158,6 +160,7 @@ final class ConfigLoader {
     }
     clients.sort((a, b) => a.name.compareTo(b.name));
     _checkOutputOverlap(clients, outputSpans, file);
+    _checkSharedBaselines(clients, baselineSpans, file);
     return ProjectConfig(
       file: path,
       clients: clients,
@@ -195,6 +198,36 @@ final class ConfigLoader {
     return composed;
   }
 
+  /// Reports a baseline file named by two clients: each client's baseline
+  /// is written from that client's diagnostics alone.
+  void _checkSharedBaselines(
+    List<ClientConfig> clients,
+    Map<String, SourceSpan?> spans,
+    String file,
+  ) {
+    final owners = <String, String>{};
+    for (final client in clients) {
+      final baseline = client.baseline;
+      if (baseline == null) continue;
+      final owner = owners[p.canonicalize(baseline)];
+      if (owner == null) {
+        owners[p.canonicalize(baseline)] = client.name;
+        continue;
+      }
+      _diagnostics.report(
+        .configInvalid,
+        'Clients "$owner" and "${client.name}" name the same baseline file.',
+        file: file,
+        pointer: JsonPointer.root
+            .child('clients')
+            .child(client.name)
+            .child('baseline'),
+        span: spans[client.name],
+        fix: 'Give each client its own baseline file.',
+      );
+    }
+  }
+
   void _checkOutputOverlap(
     List<ClientConfig> clients,
     Map<String, SourceSpan?> outputSpans,
diff --git a/packages/typed_openapi/lib/src/diagnostics/diagnostic_bag.dart b/packages/typed_openapi/lib/src/diagnostics/diagnostic_bag.dart
index f4307f7..069db63 100644
--- a/packages/typed_openapi/lib/src/diagnostics/diagnostic_bag.dart
+++ b/packages/typed_openapi/lib/src/diagnostics/diagnostic_bag.dart
@@ -14,14 +14,23 @@ import 'severity.dart';
 /// message, file, pointer and start position) is ignored: the same region
 /// of a file read twice, for example through two `$ref`s or two clients,
 /// reports each problem once.
+///
+/// Diagnostics a baseline accepts are kept apart ([baselined]): they are
+/// not in [all], [count] or [hasErrors].
 final class DiagnosticBag {
   final List<Diagnostic> _items = [];
+  final List<Diagnostic> _baselined = [];
   final Set<(DiagnosticCode, Severity, String, String?, String?, int?)> _seen =
       {};
+  final Set<(DiagnosticCode, Severity, String, String?, String?, int?)>
+  _seenBaselined = {};
 
   /// All diagnostics in the order they were reported.
   List<Diagnostic> get all => List.unmodifiable(_items);
 
+  /// Diagnostics a baseline accepts, in report order.
+  List<Diagnostic> get baselined => _baselined.toList()..sort();
+
   /// Whether any diagnostic has [Severity.error].
   bool get hasErrors => _items.any((d) => d.severity == .error);
 
@@ -35,17 +44,26 @@ final class DiagnosticBag {
 
   /// Adds an already built [diagnostic], unless an equal one is present.
   void add(Diagnostic diagnostic) {
-    final key = (
-      diagnostic.code,
-      diagnostic.severity,
-      diagnostic.message,
-      diagnostic.file,
-      diagnostic.pointer?.value,
-      diagnostic.span?.start.offset,
-    );
-    if (_seen.add(key)) _items.add(diagnostic);
+    if (_seen.add(_keyOf(diagnostic))) _items.add(diagnostic);
   }
 
+  /// Adds [diagnostic], which a baseline accepts, unless an equal one is
+  /// present.
+  void addBaselined(Diagnostic diagnostic) {
+    if (_seenBaselined.add(_keyOf(diagnostic))) _baselined.add(diagnostic);
+  }
+
+  static (DiagnosticCode, Severity, String, String?, String?, int?) _keyOf(
+    Diagnostic diagnostic,
+  ) => (
+    diagnostic.code,
+    diagnostic.severity,
+    diagnostic.message,
+    diagnostic.file,
+    diagnostic.pointer?.value,
+    diagnostic.span?.start.offset,
+  );
+
   /// Reports [code] with [message].
   ///
   /// [severity] defaults to the code's [DiagnosticCode.defaultSeverity].
diff --git a/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart b/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart
index 0c559b8..1be2c44 100644
--- a/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart
+++ b/packages/typed_openapi/lib/src/diagnostics/diagnostic_code.dart
@@ -241,6 +241,20 @@ enum DiagnosticCode {
     .info,
   ),
 
+  /// The baseline file a client names does not exist.
+  baselineNotFound('TOA820', 'baseline-not-found', .error),
+
+  /// The baseline file cannot be read, or an entry is malformed and is
+  /// ignored.
+  invalidBaseline('TOA821', 'invalid-baseline', .error),
+
+  /// A baseline entry accepts more diagnostics than the check finds: the
+  /// problem was fixed, and `baseline prune` can remove the entry.
+  baselineEntryStale('TOA822', 'baseline-entry-stale', .warning),
+
+  /// The baseline file cannot be written.
+  baselineNotWritten('TOA823', 'baseline-not-written', .error),
+
   /// The configuration file does not exist.
   configNotFound('TOA901', 'config-not-found', .error),
 
@@ -266,7 +280,7 @@ enum DiagnosticCode {
 
   /// Codes the config may raise but not lower or turn off: without them the
   /// spec is not read at all, or they are about a file the user writes for
-  /// this tool (the config and the overrides file).
+  /// this tool (the config, the overrides file and the baseline file).
   static const fixedCodes = {
     parseError,
     rootNotObject,
@@ -285,6 +299,10 @@ enum DiagnosticCode {
     overrideUnchanged,
     overrideSharedTarget,
     overrideNullabilityDropped,
+    baselineNotFound,
+    invalidBaseline,
+    baselineEntryStale,
+    baselineNotWritten,
     ...configCodes,
   };
 
diff --git a/packages/typed_openapi/lib/src/diagnostics/reporters.dart b/packages/typed_openapi/lib/src/diagnostics/reporters.dart
index b9d58c9..e953664 100644
--- a/packages/typed_openapi/lib/src/diagnostics/reporters.dart
+++ b/packages/typed_openapi/lib/src/diagnostics/reporters.dart
@@ -6,7 +6,10 @@ import 'severity.dart';
 /// Turns collected diagnostics into the text a user or a tool reads.
 abstract interface class DiagnosticReporter {
   /// Formats [diagnostics], sorted in report order.
-  String format(DiagnosticBag diagnostics);
+  ///
+  /// Diagnostics a baseline accepts are counted; with [showBaselined] they
+  /// are listed too, marked as baselined.
+  String format(DiagnosticBag diagnostics, {bool showBaselined = false});
 }
 
 /// Formats diagnostics for a terminal, ending with a summary line.
@@ -15,11 +18,17 @@ final class TextReporter implements DiagnosticReporter {
   const TextReporter();
 
   @override
-  String format(DiagnosticBag diagnostics) {
+  String format(DiagnosticBag diagnostics, {bool showBaselined = false}) {
     final out = StringBuffer();
-    for (final d in diagnostics.sorted) {
+    final baselined = diagnostics.baselined;
+    final listed = [
+      ...diagnostics.sorted.map((d) => (d, false)),
+      if (showBaselined) ...baselined.map((d) => (d, true)),
+    ]..sort((a, b) => a.$1.compareTo(b.$1));
+    for (final (d, accepted) in listed) {
+      final mark = accepted ? ' [baselined]' : '';
       out.writeln(
-        '${d.severity.name} ${d.code.id} ${d.code.slug}: ${d.message}',
+        '${d.severity.name} ${d.code.id} ${d.code.slug}$mark: ${d.message}',
       );
       final location = d.location;
       if (location != null) out.writeln('  --> $location');
@@ -34,6 +43,7 @@ final class TextReporter implements DiagnosticReporter {
       'warnings: ${diagnostics.count(.warning)}, '
       'infos: ${diagnostics.count(.info)}',
     );
+    if (baselined.isNotEmpty) out.write(', baselined: ${baselined.length}');
     return out.toString();
   }
 }
@@ -41,15 +51,21 @@ final class TextReporter implements DiagnosticReporter {
 /// Formats diagnostics as JSON for CI and other tools.
 ///
 /// Lines and columns are 1-based; they are null when positions are unknown.
+/// `summary.baselined` counts the diagnostics a baseline accepts.
 final class JsonReporter implements DiagnosticReporter {
   /// Creates a JSON reporter.
   const JsonReporter();
 
   @override
-  String format(DiagnosticBag diagnostics) {
+  String format(DiagnosticBag diagnostics, {bool showBaselined = false}) {
+    final baselined = diagnostics.baselined;
+    final listed = [
+      ...diagnostics.sorted.map((d) => (d, false)),
+      if (showBaselined) ...baselined.map((d) => (d, true)),
+    ]..sort((a, b) => a.$1.compareTo(b.$1));
     return const JsonEncoder.withIndent('  ').convert({
       'diagnostics': [
-        for (final d in diagnostics.sorted)
+        for (final (d, accepted) in listed)
           {
             'code': d.code.id,
             'name': d.code.slug,
@@ -60,10 +76,12 @@ final class JsonReporter implements DiagnosticReporter {
             'line': d.line,
             'column': d.column,
             'fix': d.fix,
+            'baselined': accepted,
           },
       ],
       'summary': {
         for (final s in Severity.values) s.name: diagnostics.count(s),
+        'baselined': baselined.length,
       },
     });
   }
```

- [ ] **Step 4: Перевірити**

Run (з `packages/typed_openapi`): `dart test`
Expected: PASS, 469 тестів (`+469: All tests passed!`).

Run (з `packages/typed_openapi`): `dart format lib test bin` двічі
Expected: другий запуск — `0 changed`.

Run (з кореня): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 5: Коміт**

```bash
git add packages/typed_openapi
git commit -m "feat(typed_openapi): baseline files with create, prune and check matching" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 5: Формати `sarif` і `github-actions`, друга позиція в моделі діагностики

**Files:**
- Create: `lib/src/diagnostics/sarif_reporter.dart`, `lib/src/diagnostics/github_actions_reporter.dart`, `test/diagnostics/sarif_reporter_test.dart`, `test/diagnostics/github_actions_reporter_test.dart`
- Modify: `lib/src/diagnostics/diagnostic.dart`, `lib/src/diagnostics/reporters.dart`, `lib/src/cli/check_command.dart`
- Test: `test/diagnostics/reporters_test.dart`, `test/cli/cli_test.dart`

**Interfaces:**
- Consumes: `DiagnosticBag.baselined`, `format(showBaselined:)` (задача 4).
- Produces: `RelatedLocation`, `Diagnostic.related`, `TextReporter.summary`, `SarifReporter`, `GitHubActionsReporter`, `ReportFormat.option` / `byOption` (CLI: `--format text|json|sarif|github-actions`). Задача 6 заповнює `related`.

Поведінка, яку закріплюють тести: SARIF проходить перевірку форми 2.1.0 (тест `expectValidSarif`: `version`, `$schema`, `tool.driver.name`, `rules[].id`, рівні з enum, `ruleIndex` указує на правило з тим самим id, регіони ≥ 1, URI без `\` і такий, що `Uri.parse` не змінює, унікальні `id` пов'язаних позицій, `suppressions[].kind`); коди — `ruleId`, правила — лише наявні коди за id; info — `note`; файл з пробілом — `specs/my%20api.yaml`, абсолютний — `file:///…`; `relatedLocations`; прийняті — лише з `showBaselined` і з `suppressions`; порожній звіт — run без результатів. github-actions — точний текст з екрануванням `%`, `,`, переносів, related-рядком і підсумком; прийняті — `::notice … (baselined)` лише з `showBaselined`. Text показує related під діагностикою; JSON має `related`; CLI друкує обидва формати з відносним URI.

- [ ] **Step 1: Тести, що не проходять**

Файл `packages/typed_openapi/test/diagnostics/github_actions_reporter_test.dart` (новий):

```dart
import 'package:source_span/source_span.dart';
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/github_actions_reporter.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';

void main() {
  final source = SourceFile.fromString(
    'openapi: 3.0.3\ncomponents:\n  schemas:\n    Pet: {type: object}\n',
    url: Uri.parse('api.yaml'),
  );

  test('writes one annotation per diagnostic and the summary', () {
    final bag = DiagnosticBag()
      ..report(
        .binaryObject,
        'type: object, format: binary; 100% wrong.',
        file: 'specs/a,b.yaml',
        pointer: JsonPointer.parse('#/components/schemas/Pet'),
        span: source.span(48, 61),
        fix: 'Use type: string.',
      )
      ..add(
        Diagnostic(
          code: DiagnosticCode.overrideUnchanged,
          severity: Severity.info,
          message: 'Unchanged.',
          file: 'api.overrides.yaml',
          related: [
            RelatedLocation(
              message: 'Changed here.',
              file: 'api.yaml',
              pointer: JsonPointer.parse('#/components'),
              span: source.span(15, 25),
            ),
          ],
        ),
      )
      ..report(.configNotFound, 'No config.');
    expect(
      const GitHubActionsReporter().format(bag),
      '::error title=TOA901 config-not-found::No config.\n'
      '::notice file=api.overrides.yaml,'
      'title=TOA807 override-unchanged::Unchanged.\n'
      '::notice file=api.yaml,line=2,col=1,endLine=2,endColumn=11,'
      'title=TOA807 override-unchanged (related)::'
      'Changed here.%0Aat #/components\n'
      '::warning file=specs/a%2Cb.yaml,line=4,col=11,endLine=4,endColumn=24,'
      'title=TOA205 binary-object::type: object, format: binary; 100%25 '
      'wrong.%0Aat #/components/schemas/Pet%0Afix: Use type: string.\n'
      'errors: 1, warnings: 1, infos: 1',
    );
  });

  test('marks accepted diagnostics as notices only when asked', () {
    final bag = DiagnosticBag()
      ..addBaselined(
        const Diagnostic(
          code: DiagnosticCode.duplicateOperationId,
          severity: Severity.error,
          message: 'Twice.',
          file: 'api.yaml',
        ),
      );
    expect(
      const GitHubActionsReporter().format(bag),
      'errors: 0, warnings: 0, infos: 0, baselined: 1',
    );
    expect(
      const GitHubActionsReporter().format(bag, showBaselined: true),
      '::notice file=api.yaml,'
      'title=TOA504 duplicate-operation-id (baselined)::Twice.\n'
      'errors: 0, warnings: 0, infos: 0, baselined: 1',
    );
  });
}
```

Файл `packages/typed_openapi/test/diagnostics/sarif_reporter_test.dart` (новий):

```dart
import 'dart:convert';

import 'package:source_span/source_span.dart';
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
import 'package:typed_openapi/src/diagnostics/sarif_reporter.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';

void main() {
  final source = SourceFile.fromString(
    'openapi: 3.0.3\ncomponents:\n  schemas:\n    Pet: {type: object}\n',
    url: Uri.parse('specs/my api.yaml'),
  );
  final overrides = SourceFile.fromString(
    'schemas:\n  Pet: {format: binary}\n',
    url: Uri.parse('api.overrides.yaml'),
  );

  DiagnosticBag sample() => DiagnosticBag()
    ..report(
      .binaryObject,
      'type: object with format: binary.',
      file: 'specs/my api.yaml',
      pointer: JsonPointer.parse('#/components/schemas/Pet'),
      span: source.span(48, 61),
      fix: 'Use type: string.',
    )
    ..add(
      Diagnostic(
        code: DiagnosticCode.overrideUnchanged,
        severity: Severity.info,
        message: 'Unchanged.',
        file: 'api.overrides.yaml',
        pointer: JsonPointer.parse('#/schemas/Pet/format'),
        span: overrides.span(16, 22),
        related: [
          RelatedLocation(
            message: 'The schema it changes.',
            file: '/abs/specs/api.yaml',
            pointer: JsonPointer.parse('#/components/schemas/Pet'),
            span: source.span(48, 61),
          ),
        ],
      ),
    )
    ..report(.configNotFound, 'No config.');

  Map<String, Object?> sarif(DiagnosticBag bag, {bool show = false}) =>
      jsonDecode(const SarifReporter().format(bag, showBaselined: show))
          as Map<String, Object?>;

  test('has the shape SARIF 2.1.0 requires', () {
    final log = sarif(sample());
    expectValidSarif(log);
    final run = (log['runs']! as List<Object?>).single as Map<String, Object?>;
    final rules =
        ((run['tool']! as Map<String, Object?>)['driver']!
                as Map<String, Object?>)['rules']!
            as List<Object?>;
    expect(rules.map((r) => (r! as Map<String, Object?>)['id']), [
      'TOA205',
      'TOA807',
      'TOA901',
    ]);
  });

  test('maps codes, levels, locations and related locations', () {
    final results = _results(sarif(sample()));
    expect(results.map((r) => (r['ruleId'], r['level'])), [
      ('TOA901', 'error'),
      ('TOA807', 'note'),
      ('TOA205', 'warning'),
    ]);
    expect(results.first.containsKey('locations'), isTrue);
    expect(results.first['locations'], isEmpty);
    expect(results.last['message'], {
      'text': 'type: object with format: binary.\nFix: Use type: string.',
    });
    expect(results.last['locations'], [
      {
        'physicalLocation': {
          'artifactLocation': {'uri': 'specs/my%20api.yaml'},
          'region': {
            'startLine': 4,
            'startColumn': 11,
            'endLine': 4,
            'endColumn': 24,
          },
        },
        'logicalLocations': [
          {'fullyQualifiedName': '#/components/schemas/Pet', 'kind': 'object'},
        ],
      },
    ]);
    final related = results[1]['relatedLocations']! as List<Object?>;
    expect(related.single, {
      'id': 1,
      'message': {'text': 'The schema it changes.'},
      'physicalLocation': {
        'artifactLocation': {'uri': 'file:///abs/specs/api.yaml'},
        'region': {
          'startLine': 4,
          'startColumn': 11,
          'endLine': 4,
          'endColumn': 24,
        },
      },
      'logicalLocations': [
        {'fullyQualifiedName': '#/components/schemas/Pet', 'kind': 'object'},
      ],
    });
  });

  test('lists accepted diagnostics as suppressed only when asked', () {
    final bag = sample()
      ..addBaselined(
        const Diagnostic(
          code: DiagnosticCode.boolRequired,
          severity: Severity.warning,
          message: 'Accepted.',
          file: 'a.yaml',
        ),
      );
    expect(
      _results(sarif(bag)).where((r) => r['ruleId'] == 'TOA201'),
      isEmpty,
    );
    final shown = sarif(bag, show: true);
    expectValidSarif(shown);
    expect(
      _results(
        shown,
      ).singleWhere((r) => r['ruleId'] == 'TOA201')['suppressions'],
      [
        {'kind': 'external', 'justification': 'Accepted in the baseline.'},
      ],
    );
  });

  test('an empty report is a run without results', () {
    final log = sarif(DiagnosticBag());
    expectValidSarif(log);
    expect(_results(log), isEmpty);
  });
}

List<Map<String, Object?>> _results(Map<String, Object?> log) =>
    (((log['runs']! as List<Object?>).single
                as Map<String, Object?>)['results']!
            as List<Object?>)
        .cast<Map<String, Object?>>();

/// Checks the parts of the SARIF 2.1.0 schema this tool writes: required
/// properties, enum values, 1-based regions, URI references and rule
/// indexes.
void expectValidSarif(Map<String, Object?> log) {
  expect(log['version'], '2.1.0');
  expect(log[r'$schema'], 'https://json.schemastore.org/sarif-2.1.0.json');
  final runs = log['runs']! as List<Object?>;
  expect(runs, isNotEmpty);
  for (final run in runs.cast<Map<String, Object?>>()) {
    final driver =
        (run['tool']! as Map<String, Object?>)['driver']!
            as Map<String, Object?>;
    expect(driver['name'], isA<String>());
    final rules = (driver['rules']! as List<Object?>)
        .cast<Map<String, Object?>>();
    for (final rule in rules) {
      expect(rule['id'], matches(RegExp(r'^TOA\d{3}$')));
      final level =
          (rule['defaultConfiguration']! as Map<String, Object?>)['level'];
      expect(level, isIn(['none', 'note', 'warning', 'error']));
    }
    for (final result
        in (run['results']! as List<Object?>).cast<Map<String, Object?>>()) {
      expect(result['ruleId'], isA<String>());
      expect(
        rules[result['ruleIndex']! as int]['id'],
        result['ruleId'],
      );
      expect(result['level'], isIn(['none', 'note', 'warning', 'error']));
      expect(
        (result['message']! as Map<String, Object?>)['text'],
        isA<String>(),
      );
      final locations = [
        ...(result['locations']! as List<Object?>),
        ...?(result['relatedLocations'] as List<Object?>?),
      ].cast<Map<String, Object?>>();
      for (final location in locations) {
        final physical = location['physicalLocation'] as Map<String, Object?>?;
        if (physical == null) continue;
        final uri =
            (physical['artifactLocation']! as Map<String, Object?>)['uri']!
                as String;
        expect(uri, isNot(contains(r'\')));
        expect(Uri.parse(uri).toString(), uri);
        final region = physical['region'] as Map<String, Object?>?;
        if (region == null) continue;
        for (final key in [
          'startLine',
          'startColumn',
          'endLine',
          'endColumn',
        ]) {
          expect(region[key], isA<int>().having((v) => v, key, greaterThan(0)));
        }
      }
      final related = (result['relatedLocations'] as List<Object?>?) ?? [];
      final ids = [
        for (final r in related.cast<Map<String, Object?>>()) r['id'] as int,
      ];
      expect(ids.toSet().length, ids.length);
      expect(ids.every((id) => id >= 0), isTrue);
      for (final s
          in ((result['suppressions'] as List<Object?>?) ?? [])
              .cast<Map<String, Object?>>()) {
        expect(s['kind'], isIn(['inSource', 'external']));
      }
    }
  }
}
```

Diff `packages/typed_openapi/test/cli/cli_test.dart`, `packages/typed_openapi/test/diagnostics/reporters_test.dart` (`git apply` з кореня):

```diff
diff --git a/packages/typed_openapi/test/cli/cli_test.dart b/packages/typed_openapi/test/cli/cli_test.dart
index f6a1297..ad3d018 100644
--- a/packages/typed_openapi/test/cli/cli_test.dart
+++ b/packages/typed_openapi/test/cli/cli_test.dart
@@ -74,6 +74,33 @@ clients:
     });
   });
 
+  test('prints SARIF and GitHub Actions annotations', () async {
+    final (sarifCode, sarif, _) = await run([
+      'check',
+      '-c',
+      configPath,
+      '--format',
+      'sarif',
+    ], workingDirectory: workingDirectory);
+    expect(sarifCode, 1);
+    expect(sarif, contains('"uri": "specs/old.json"'));
+    final (code, out, _) = await run([
+      'check',
+      '-c',
+      configPath,
+      '--format',
+      'github-actions',
+    ], workingDirectory: workingDirectory);
+    expect(code, 1);
+    expect(
+      out,
+      startsWith(
+        '::error file=specs/old.json,line=2,col=14,endLine=2,endColumn=19,'
+        'title=TOA011 unsupported-openapi-version::',
+      ),
+    );
+  });
+
   test('exits 78 when the config file is missing', () async {
     final (code, out, _) = await run([
       'check',
diff --git a/packages/typed_openapi/test/diagnostics/reporters_test.dart b/packages/typed_openapi/test/diagnostics/reporters_test.dart
index f631636..8209405 100644
--- a/packages/typed_openapi/test/diagnostics/reporters_test.dart
+++ b/packages/typed_openapi/test/diagnostics/reporters_test.dart
@@ -5,8 +5,10 @@ import 'package:test/test.dart';
 import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
 import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
 import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
+import 'package:typed_openapi/src/diagnostics/github_actions_reporter.dart';
 import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
 import 'package:typed_openapi/src/diagnostics/reporters.dart';
+import 'package:typed_openapi/src/diagnostics/sarif_reporter.dart';
 import 'package:typed_openapi/src/diagnostics/severity.dart';
 
 void main() {
@@ -62,6 +64,7 @@ void main() {
       'line': 2,
       'column': 14,
       'fix': 'Emit OpenAPI 3.',
+      'related': <Object?>[],
       'baselined': false,
     });
     expect(json['summary'], {
@@ -129,5 +132,44 @@ void main() {
   test('ReportFormat maps each format to its reporter', () {
     expect(ReportFormat.text.reporter, isA<TextReporter>());
     expect(ReportFormat.json.reporter, isA<JsonReporter>());
+    expect(ReportFormat.sarif.reporter, isA<SarifReporter>());
+    expect(
+      ReportFormat.byOption('github-actions').reporter,
+      isA<GitHubActionsReporter>(),
+    );
+    expect(ReportFormat.values.map((f) => f.option), [
+      'text',
+      'json',
+      'sarif',
+      'github-actions',
+    ]);
+  });
+
+  test('TextReporter lists related locations under the diagnostic', () {
+    final bag = DiagnosticBag()
+      ..add(
+        Diagnostic(
+          code: DiagnosticCode.binaryObject,
+          severity: Severity.warning,
+          message: 'Binary object.',
+          file: 'api.json',
+          related: [
+            RelatedLocation(
+              message: 'Introduced by this override.',
+              file: 'api.overrides.yaml',
+              pointer: JsonPointer.parse('#/schemas/Pet/type'),
+            ),
+          ],
+        ),
+      );
+    expect(
+      const TextReporter().format(bag),
+      'warning TOA205 binary-object: Binary object.\n'
+      '  --> api.json\n'
+      '  related: Introduced by this override.\n'
+      '    --> api.overrides.yaml\n'
+      '    at #/schemas/Pet/type\n'
+      'errors: 0, warnings: 1, infos: 0',
+    );
   });
 }
```

- [ ] **Step 2: Запустити тести**

Run (з `packages/typed_openapi`): `dart test test/diagnostics test/cli`
Expected: FAIL — компіляція: `sarif_reporter.dart`, `github_actions_reporter.dart` не існують, `RelatedLocation` не визначено.

- [ ] **Step 3: Реалізація**

Файл `packages/typed_openapi/lib/src/diagnostics/github_actions_reporter.dart` (новий):

```dart
import 'package:source_span/source_span.dart';

import 'diagnostic_bag.dart';
import 'json_pointer.dart';
import 'reporters.dart';
import 'severity.dart';

/// Formats diagnostics as GitHub Actions workflow commands, which GitHub
/// shows as annotations on the changed files.
///
/// One line per diagnostic: `::error`, `::warning` or `::notice` (for
/// info) with `file`, `line`, `col`, `endLine`, `endColumn` and a `title`
/// of code and name, then the message, the JSON pointer and the fix. A
/// related location is a `::notice` of its own. The summary line of the
/// text format ends the output. Values are escaped as the runner expects
/// (`%`, CR and LF, and in properties also `:` and `,`).
final class GitHubActionsReporter implements DiagnosticReporter {
  /// Creates a GitHub Actions reporter.
  const GitHubActionsReporter();

  @override
  String format(DiagnosticBag diagnostics, {bool showBaselined = false}) {
    final listed = [
      ...diagnostics.sorted.map((d) => (d, false)),
      if (showBaselined) ...diagnostics.baselined.map((d) => (d, true)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final out = StringBuffer();
    for (final (d, accepted) in listed) {
      final title =
          '${d.code.id} ${d.code.slug}${accepted ? ' (baselined)' : ''}';
      out.writeln(
        _command(
          accepted ? 'notice' : _kind(d.severity),
          title,
          d.file,
          d.span,
          [
            d.message,
            if (d.pointer case final pointer?) 'at ${pointer.value}',
            if (d.fix case final fix?) 'fix: $fix',
          ],
        ),
      );
      for (final related in d.related) {
        out.writeln(
          _command(
            'notice',
            '$title (related)',
            related.file,
            related.span,
            [
              related.message,
              if (related.pointer case final JsonPointer pointer)
                'at ${pointer.value}',
            ],
          ),
        );
      }
    }
    out.write(TextReporter.summary(diagnostics));
    return out.toString();
  }

  static String _command(
    String kind,
    String title,
    String? file,
    SourceSpan? span,
    List<String> lines,
  ) {
    final properties = [
      if (file != null) 'file=${_property(file)}',
      if (span != null) ...[
        'line=${span.start.line + 1}',
        'col=${span.start.column + 1}',
        'endLine=${span.end.line + 1}',
        'endColumn=${span.end.column + 1}',
      ],
      'title=${_property(title)}',
    ];
    return '::$kind ${properties.join(',')}::${_data(lines.join('\n'))}';
  }

  static String _kind(Severity severity) => switch (severity) {
    .error => 'error',
    .warning => 'warning',
    .info => 'notice',
  };

  static String _data(String value) => value
      .replaceAll('%', '%25')
      .replaceAll('\r', '%0D')
      .replaceAll('\n', '%0A');

  static String _property(String value) =>
      _data(value).replaceAll(':', '%3A').replaceAll(',', '%2C');
}
```

Файл `packages/typed_openapi/lib/src/diagnostics/sarif_reporter.dart` (новий):

```dart
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';

import 'diagnostic.dart';
import 'diagnostic_bag.dart';
import 'diagnostic_code.dart';
import 'json_pointer.dart';
import 'reporters.dart';
import 'severity.dart';

/// Formats diagnostics as SARIF 2.1.0, for code scanning in CI.
///
/// One run of the `typed_openapi` tool; its rules are the codes that occur,
/// sorted by id. A result has the code as `ruleId`, the level `error`,
/// `warning` or `note` (for info), the message with the fix, a physical
/// location (the file as a relative URI reference, or a `file:` URI outside
/// the working directory, and the 1-based region) and the JSON pointer as a
/// logical location. A related location (such as the override that
/// introduced the problem) is a `relatedLocations` item. With
/// `showBaselined`, accepted diagnostics are results with an external
/// suppression.
final class SarifReporter implements DiagnosticReporter {
  /// Creates a SARIF reporter.
  const SarifReporter();

  /// The SARIF version written.
  static const version = '2.1.0';

  /// The JSON schema of [version].
  static const schema = 'https://json.schemastore.org/sarif-2.1.0.json';

  @override
  String format(DiagnosticBag diagnostics, {bool showBaselined = false}) {
    final listed = [
      ...diagnostics.sorted.map((d) => (d, false)),
      if (showBaselined) ...diagnostics.baselined.map((d) => (d, true)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final codes = {for (final (d, _) in listed) d.code}.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final index = {for (final (i, code) in codes.indexed) code: i};
    return const JsonEncoder.withIndent('  ').convert({
      r'$schema': schema,
      'version': version,
      'runs': [
        {
          'tool': {
            'driver': {
              'name': 'typed_openapi',
              'informationUri': 'https://github.com/4akLoon/typed_openapi',
              'rules': [for (final code in codes) _rule(code)],
            },
          },
          'results': [
            for (final (d, accepted) in listed)
              _result(d, index[d.code]!, accepted: accepted),
          ],
        },
      ],
    });
  }

  static Map<String, Object?> _rule(DiagnosticCode code) => {
    'id': code.id,
    'name': code.slug,
    'defaultConfiguration': {'level': _level(code.defaultSeverity)},
  };

  static Map<String, Object?> _result(
    Diagnostic d,
    int ruleIndex, {
    required bool accepted,
  }) {
    final fix = d.fix;
    return {
      'ruleId': d.code.id,
      'ruleIndex': ruleIndex,
      'level': _level(d.severity),
      'message': {'text': fix == null ? d.message : '${d.message}\nFix: $fix'},
      'locations': [?_location(d.file, d.pointer, d.span)],
      if (d.related.isNotEmpty)
        'relatedLocations': [
          for (final (i, r) in d.related.indexed)
            {
              'id': i + 1,
              'message': {'text': r.message},
              ...?_location(r.file, r.pointer, r.span),
            },
        ],
      if (accepted)
        'suppressions': [
          {'kind': 'external', 'justification': 'Accepted in the baseline.'},
        ],
    };
  }

  static Map<String, Object?>? _location(
    String? file,
    JsonPointer? pointer,
    SourceSpan? span,
  ) {
    if (file == null && pointer == null) return null;
    return {
      if (file != null)
        'physicalLocation': {
          'artifactLocation': {'uri': _uri(file)},
          if (span != null)
            'region': {
              'startLine': span.start.line + 1,
              'startColumn': span.start.column + 1,
              'endLine': span.end.line + 1,
              'endColumn': span.end.column + 1,
            },
        },
      if (pointer != null)
        'logicalLocations': [
          {'fullyQualifiedName': pointer.value, 'kind': 'object'},
        ],
    };
  }

  /// [file] as a URI reference: relative paths keep `/` separators and are
  /// percent-encoded; absolute paths become `file:` URIs.
  static String _uri(String file) => p.isAbsolute(file)
      ? '${p.toUri(file)}'
      : Uri(pathSegments: p.split(file)).toString();

  static String _level(Severity severity) => switch (severity) {
    .error => 'error',
    .warning => 'warning',
    .info => 'note',
  };
}
```

Diff `packages/typed_openapi/lib/src/cli/check_command.dart`, `packages/typed_openapi/lib/src/diagnostics/diagnostic.dart`, `packages/typed_openapi/lib/src/diagnostics/reporters.dart` (`git apply` з кореня):

```diff
diff --git a/packages/typed_openapi/lib/src/cli/check_command.dart b/packages/typed_openapi/lib/src/cli/check_command.dart
index a65eabd..cf4ca37 100644
--- a/packages/typed_openapi/lib/src/cli/check_command.dart
+++ b/packages/typed_openapi/lib/src/cli/check_command.dart
@@ -21,8 +21,8 @@ final class CheckCommand extends Command<int> {
       )
       ..addOption(
         'format',
-        allowed: [for (final format in ReportFormat.values) format.name],
-        defaultsTo: ReportFormat.text.name,
+        allowed: [for (final format in ReportFormat.values) format.option],
+        defaultsTo: ReportFormat.text.option,
         help: 'Report format.',
       )
       ..addFlag(
@@ -78,7 +78,7 @@ final class CheckCommand extends Command<int> {
         strictBaseline: results.flag('strict-baseline'),
       );
     }
-    final format = ReportFormat.values.byName(results.option('format')!);
+    final format = ReportFormat.byOption(results.option('format')!);
     _out.writeln(
       format.reporter.format(
         diagnostics,
diff --git a/packages/typed_openapi/lib/src/diagnostics/diagnostic.dart b/packages/typed_openapi/lib/src/diagnostics/diagnostic.dart
index af04807..e6e59a1 100644
--- a/packages/typed_openapi/lib/src/diagnostics/diagnostic.dart
+++ b/packages/typed_openapi/lib/src/diagnostics/diagnostic.dart
@@ -4,6 +4,38 @@ import 'diagnostic_code.dart';
 import 'json_pointer.dart';
 import 'severity.dart';
 
+/// Another place a [Diagnostic] is about, such as the override that
+/// introduced the problem.
+final class RelatedLocation {
+  /// Creates a related location.
+  const RelatedLocation({
+    required this.message,
+    this.file,
+    this.pointer,
+    this.span,
+  });
+
+  /// What this place has to do with the finding.
+  final String message;
+
+  /// The file, as shown to the user.
+  final String? file;
+
+  /// Where in [file] the place is.
+  final JsonPointer? pointer;
+
+  /// The source range in [file], when positions are known.
+  final SourceSpan? span;
+
+  /// `file:line:column`, `file` when only the file is known, or null.
+  String? get location {
+    final file = this.file;
+    if (file == null) return null;
+    final start = span?.start;
+    return start == null ? file : '$file:${start.line + 1}:${start.column + 1}';
+  }
+}
+
 /// One finding about a spec or the configuration.
 ///
 /// Diagnostics are ordered by file, position, pointer, code and message, so
@@ -19,6 +51,7 @@ final class Diagnostic implements Comparable<Diagnostic> {
     this.span,
     this.fix,
     this.args = const [],
+    this.related = const [],
   });
 
   /// The stable code from the catalog.
@@ -47,6 +80,9 @@ final class Diagnostic implements Comparable<Diagnostic> {
   /// the baseline fingerprint, unlike [message].
   final List<String> args;
 
+  /// Other places the finding is about.
+  final List<RelatedLocation> related;
+
   /// The 1-based line of the finding, or null when the position is unknown.
   int? get line {
     final start = span?.start;
@@ -69,6 +105,7 @@ final class Diagnostic implements Comparable<Diagnostic> {
     span: span,
     fix: fix,
     args: args,
+    related: related,
   );
 
   /// `file:line:column`, `file` when only the file is known, or null.
diff --git a/packages/typed_openapi/lib/src/diagnostics/reporters.dart b/packages/typed_openapi/lib/src/diagnostics/reporters.dart
index e953664..ed29da6 100644
--- a/packages/typed_openapi/lib/src/diagnostics/reporters.dart
+++ b/packages/typed_openapi/lib/src/diagnostics/reporters.dart
@@ -1,6 +1,8 @@
 import 'dart:convert';
 
 import 'diagnostic_bag.dart';
+import 'github_actions_reporter.dart';
+import 'sarif_reporter.dart';
 import 'severity.dart';
 
 /// Turns collected diagnostics into the text a user or a tool reads.
@@ -37,15 +39,27 @@ final class TextReporter implements DiagnosticReporter {
       final fix = d.fix;
       // A fix may end with an override snippet on several lines.
       if (fix != null) out.writeln('  fix: ${fix.replaceAll('\n', '\n    ')}');
+      for (final related in d.related) {
+        out.writeln('  related: ${related.message}');
+        final location = related.location;
+        if (location != null) out.writeln('    --> $location');
+        final pointer = related.pointer;
+        if (pointer != null) out.writeln('    at ${pointer.value}');
+      }
     }
-    out.write(
-      'errors: ${diagnostics.count(.error)}, '
-      'warnings: ${diagnostics.count(.warning)}, '
-      'infos: ${diagnostics.count(.info)}',
-    );
-    if (baselined.isNotEmpty) out.write(', baselined: ${baselined.length}');
+    out.write(summary(diagnostics));
     return out.toString();
   }
+
+  /// The summary line: errors, warnings and infos, and how many diagnostics
+  /// a baseline accepts when there are any.
+  static String summary(DiagnosticBag diagnostics) {
+    final baselined = diagnostics.baselined.length;
+    return 'errors: ${diagnostics.count(.error)}, '
+        'warnings: ${diagnostics.count(.warning)}, '
+        'infos: ${diagnostics.count(.info)}'
+        '${baselined == 0 ? '' : ', baselined: $baselined'}';
+  }
 }
 
 /// Formats diagnostics as JSON for CI and other tools.
@@ -76,6 +90,16 @@ final class JsonReporter implements DiagnosticReporter {
             'line': d.line,
             'column': d.column,
             'fix': d.fix,
+            'related': [
+              for (final r in d.related)
+                {
+                  'message': r.message,
+                  'file': r.file,
+                  'pointer': r.pointer?.value,
+                  'line': r.span == null ? null : r.span!.start.line + 1,
+                  'column': r.span == null ? null : r.span!.start.column + 1,
+                },
+            ],
             'baselined': accepted,
           },
       ],
@@ -90,13 +114,26 @@ final class JsonReporter implements DiagnosticReporter {
 /// The output formats the tool can print.
 enum ReportFormat {
   /// Human-readable text.
-  text(TextReporter()),
+  text('text', TextReporter()),
 
   /// Machine-readable JSON.
-  json(JsonReporter());
+  json('json', JsonReporter()),
+
+  /// SARIF 2.1.0 for code scanning.
+  sarif('sarif', SarifReporter()),
 
-  const ReportFormat(this.reporter);
+  /// GitHub Actions annotations.
+  githubActions('github-actions', GitHubActionsReporter());
+
+  const ReportFormat(this.option, this.reporter);
+
+  /// The value of `--format` that selects this format.
+  final String option;
 
   /// The reporter that prints this format.
   final DiagnosticReporter reporter;
+
+  /// The format whose [option] is [value].
+  static ReportFormat byOption(String value) =>
+      values.firstWhere((format) => format.option == value);
 }
```

- [ ] **Step 4: Перевірити**

Run (з `packages/typed_openapi`): `dart test`
Expected: PASS, 477 тестів (`+477: All tests passed!`).

Run (з `packages/typed_openapi`): `dart format lib test bin` двічі
Expected: другий запуск — `0 changed`.

Run (з кореня): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 5: Коміт**

```bash
git add packages/typed_openapi
git commit -m "feat(typed_openapi): SARIF and GitHub Actions report formats" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 6: Перенесене — позиція override-у, що вніс проблему; підказки пресетів при дедупі

**Files:**
- Create: `test/normalize/override_origins_test.dart`
- Modify: `lib/src/diagnostics/diagnostic.dart`, `lib/src/diagnostics/diagnostic_bag.dart`, `lib/src/normalize/normalizer.dart`
- Test: `test/diagnostics/diagnostic_bag_test.dart`, `test/check/spec_checker_test.dart`, `test/cli/cli_test.dart`

**Interfaces:**
- Consumes: `RelatedLocation`, `Diagnostic.related` (задача 5); `OverrideEdit(edit, sources)`, `OverrideSet.file` / `spanOf`, `NormalizerRule.check` / `hint`, `RuleContext` (M3, M4).
- Produces: `Diagnostic.hints`, `Diagnostic.withHints`, `Diagnostic.withRelated`; `fix` стає геттером `fix + hints`; `Normalizer` додає related-позицію override-у.

Поведінка, яку закріплюють тести: `format: binary` з override-у на `type: object` дає TOA205 з related `api.overrides.yaml:2:17` `#/schemas/Pet/format`; TOA205, що вже був у специфікації, і TOA201 в іншій схемі related не отримують; дублікат з іншими підказками додає лише нові (порядок збережено, повтор не дублюється); спільна специфікація клієнтів без пресету і з `nestjs` дає одну TOA301 з підказкою NestJS (до задачі її губив дедуп); CLI друкує `related:` під знахідкою.

- [ ] **Step 1: Тести, що не проходять**

Файл `packages/typed_openapi/test/normalize/override_origins_test.dart` (новий):

```dart
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/load/openapi_version.dart';
import 'package:typed_openapi/src/load/spec_loader.dart';
import 'package:typed_openapi/src/normalize/normalizer.dart';
import 'package:typed_openapi/src/overrides/override_loader.dart';

void main() {
  List<Diagnostic> check(String spec, String overrides) {
    final bag = DiagnosticBag();
    final document = SpecLoader(bag).parse(spec, 'api.yaml')!;
    final set = OverrideLoader(bag).parse(overrides, 'api.overrides.yaml');
    Normalizer(bag).normalize(document, OpenApiVersion.v30, overrides: set);
    return bag.sorted;
  }

  test('a problem an override introduces points at the override', () {
    final found = check(
      '''
openapi: 3.0.3
info: {title: t, version: "1"}
paths: {}
components:
  schemas:
    Pet: {type: object, properties: {name: {type: string}}}
''',
      'schemas:\n  Pet: {format: binary}\n',
    );
    final binary = found.singleWhere(
      (d) => d.code == DiagnosticCode.binaryObject,
    );
    expect(binary.file, 'api.yaml');
    expect(
      binary.related.map((r) => (r.message, r.location, r.pointer?.value)),
      [
        (
          'Introduced by this override.',
          'api.overrides.yaml:2:17',
          '#/schemas/Pet/format',
        ),
      ],
    );
  });

  test('a problem the spec already had has no override location', () {
    final found = check(
      '''
openapi: 3.0.3
info: {title: t, version: "1"}
paths: {}
components:
  schemas:
    Pet: {type: object, format: binary, description: a}
    Tag: {type: object, format: binary}
''',
      'schemas:\n  Pet: {description: b}\n',
    );
    final binary = found.where((d) => d.code == DiagnosticCode.binaryObject);
    expect(binary, hasLength(2));
    expect(binary.every((d) => d.related.isEmpty), isTrue);
  });

  test('a problem elsewhere has no override location', () {
    final found = check(
      '''
openapi: 3.0.3
info: {title: t, version: "1"}
paths: {}
components:
  schemas:
    Pet: {type: object}
    Tag: {type: object, properties: {name: {type: string, required: true}}}
''',
      'schemas:\n  Pet: {format: binary}\n',
    );
    final tag = found.singleWhere((d) => d.code == DiagnosticCode.boolRequired);
    expect(tag.related, isEmpty);
  });
}
```

Diff `packages/typed_openapi/test/check/spec_checker_test.dart`, `packages/typed_openapi/test/cli/cli_test.dart`, `packages/typed_openapi/test/diagnostics/diagnostic_bag_test.dart` (`git apply` з кореня):

```diff
diff --git a/packages/typed_openapi/test/check/spec_checker_test.dart b/packages/typed_openapi/test/check/spec_checker_test.dart
index c43cf85..30d54f7 100644
--- a/packages/typed_openapi/test/check/spec_checker_test.dart
+++ b/packages/typed_openapi/test/check/spec_checker_test.dart
@@ -485,4 +485,27 @@ entries:
       expect(bag.baselined, isEmpty);
     });
   });
+
+  test('clients with different presets keep both hints on a shared '
+      'finding', () {
+    final dir = TempDir();
+    dir.write('api.yaml', '''
+openapi: 3.0.3
+info: {title: t, version: "1"}
+components: {schemas: {Kind: {type: string, enum: [a, a]}}}
+''');
+    final path = dir.write('typed_openapi.yaml', '''
+clients:
+  a: {input: api.yaml, output: lib/a}
+  b: {input: api.yaml, output: lib/b, preset: nestjs}
+''');
+    final bag = DiagnosticBag();
+    SpecChecker(
+      bag,
+      DisplayPaths(dir.path),
+    ).check(ConfigLoader(bag).load(path)!);
+    final finding = bag.all.single;
+    expect(finding.code, DiagnosticCode.duplicateEnumValue);
+    expect(finding.fix, contains('In NestJS, give the enum its own schema'));
+  });
 }
diff --git a/packages/typed_openapi/test/cli/cli_test.dart b/packages/typed_openapi/test/cli/cli_test.dart
index ad3d018..1f4149f 100644
--- a/packages/typed_openapi/test/cli/cli_test.dart
+++ b/packages/typed_openapi/test/cli/cli_test.dart
@@ -390,4 +390,42 @@ clients:
       expect(err, contains('No client has a "baseline" in the config.'));
     });
   });
+
+  test('a problem an override introduces names the override', () async {
+    final dir = TempDir();
+    dir.write('api.yaml', '''
+openapi: 3.0.3
+info: {title: api, version: "1"}
+paths: {}
+components:
+  schemas:
+    Pet: {type: object}
+''');
+    dir.write('api.overrides.yaml', 'schemas:\n  Pet: {format: binary}\n');
+    final path = dir.write('typed_openapi.yaml', '''
+clients:
+  api: {input: api.yaml, output: lib/api, overrides: api.overrides.yaml}
+''');
+    final (code, out, _) = await run([
+      'check',
+      '-c',
+      path,
+    ], workingDirectory: dir.path);
+    expect(code, 0);
+    expect(
+      out,
+      contains(
+        '  at #/components/schemas/Pet/type\n'
+        '  fix: ',
+      ),
+    );
+    expect(
+      out,
+      contains(
+        '  related: Introduced by this override.\n'
+        '    --> api.overrides.yaml:2:17\n'
+        '    at #/schemas/Pet/format\n',
+      ),
+    );
+  });
 }
diff --git a/packages/typed_openapi/test/diagnostics/diagnostic_bag_test.dart b/packages/typed_openapi/test/diagnostics/diagnostic_bag_test.dart
index 85eae27..b66f620 100644
--- a/packages/typed_openapi/test/diagnostics/diagnostic_bag_test.dart
+++ b/packages/typed_openapi/test/diagnostics/diagnostic_bag_test.dart
@@ -1,6 +1,8 @@
 import 'package:source_span/source_span.dart';
 import 'package:test/test.dart';
+import 'package:typed_openapi/src/diagnostics/diagnostic.dart';
 import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
+import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
 import 'package:typed_openapi/src/diagnostics/json_pointer.dart';
 import 'package:typed_openapi/src/diagnostics/severity.dart';
 
@@ -70,4 +72,24 @@ void main() {
     expect(bag.count(Severity.warning), 1);
     expect(bag.count(Severity.info), 0);
   });
+
+  test('a duplicate adds its new preset hints to the one in the bag', () {
+    const base = Diagnostic(
+      code: DiagnosticCode.duplicateEnumValue,
+      severity: Severity.warning,
+      message: 'Repeats.',
+      file: 'api.yaml',
+      fix: 'Remove it.',
+    );
+    final bag = DiagnosticBag()
+      ..add(base)
+      ..add(base.withHints(['In NestJS, ...']))
+      ..add(base.withHints(['In FastAPI, ...', 'In NestJS, ...']))
+      ..add(base);
+    expect(bag.all.single.hints, ['In NestJS, ...', 'In FastAPI, ...']);
+    expect(
+      bag.all.single.fix,
+      'Remove it. In NestJS, ... In FastAPI, ...',
+    );
+  });
 }
```

- [ ] **Step 2: Запустити тести**

Run (з `packages/typed_openapi`): `dart test test/normalize/override_origins_test.dart test/diagnostics test/check test/cli`
Expected: FAIL — компіляція: `Diagnostic` не має `withHints`; після неї — related порожній і підказку NestJS загублено.

- [ ] **Step 3: Реалізація**

Diff `packages/typed_openapi/lib/src/diagnostics/diagnostic.dart`, `packages/typed_openapi/lib/src/diagnostics/diagnostic_bag.dart`, `packages/typed_openapi/lib/src/normalize/normalizer.dart` (`git apply` з кореня):

```diff
diff --git a/packages/typed_openapi/lib/src/diagnostics/diagnostic.dart b/packages/typed_openapi/lib/src/diagnostics/diagnostic.dart
index e6e59a1..a276681 100644
--- a/packages/typed_openapi/lib/src/diagnostics/diagnostic.dart
+++ b/packages/typed_openapi/lib/src/diagnostics/diagnostic.dart
@@ -49,10 +49,11 @@ final class Diagnostic implements Comparable<Diagnostic> {
     this.file,
     this.pointer,
     this.span,
-    this.fix,
+    String? fix,
+    this.hints = const [],
     this.args = const [],
     this.related = const [],
-  });
+  }) : _fix = fix;
 
   /// The stable code from the catalog.
   final DiagnosticCode code;
@@ -72,8 +73,15 @@ final class Diagnostic implements Comparable<Diagnostic> {
   /// The source range in [file], when positions are known.
   final SourceSpan? span;
 
-  /// What to change in the source to fix the finding.
-  final String? fix;
+  final String? _fix;
+
+  /// What to change in the source to fix the finding, followed by the
+  /// [hints].
+  String? get fix => hints.isEmpty ? _fix : [?_fix, ...hints].join(' ');
+
+  /// How to fix the finding in the code of a framework, one per preset of
+  /// the clients that share the finding.
+  final List<String> hints;
 
   /// Values from the spec that tell this finding from another of the same
   /// code at the same place, such as the name of a missing field; part of
@@ -95,6 +103,34 @@ final class Diagnostic implements Comparable<Diagnostic> {
     return start == null ? null : start.column + 1;
   }
 
+  /// This diagnostic with [related] instead of its own related locations.
+  Diagnostic withRelated(List<RelatedLocation> related) => Diagnostic(
+    code: code,
+    severity: severity,
+    message: message,
+    file: file,
+    pointer: pointer,
+    span: span,
+    fix: _fix,
+    hints: hints,
+    args: args,
+    related: related,
+  );
+
+  /// This diagnostic with [hints] instead of its own.
+  Diagnostic withHints(List<String> hints) => Diagnostic(
+    code: code,
+    severity: severity,
+    message: message,
+    file: file,
+    pointer: pointer,
+    span: span,
+    fix: _fix,
+    hints: hints,
+    args: args,
+    related: related,
+  );
+
   /// This diagnostic with [severity] instead of its own.
   Diagnostic withSeverity(Severity severity) => Diagnostic(
     code: code,
@@ -103,7 +139,8 @@ final class Diagnostic implements Comparable<Diagnostic> {
     file: file,
     pointer: pointer,
     span: span,
-    fix: fix,
+    fix: _fix,
+    hints: hints,
     args: args,
     related: related,
   );
diff --git a/packages/typed_openapi/lib/src/diagnostics/diagnostic_bag.dart b/packages/typed_openapi/lib/src/diagnostics/diagnostic_bag.dart
index 069db63..222ab66 100644
--- a/packages/typed_openapi/lib/src/diagnostics/diagnostic_bag.dart
+++ b/packages/typed_openapi/lib/src/diagnostics/diagnostic_bag.dart
@@ -13,16 +13,18 @@ import 'severity.dart';
 /// A diagnostic equal to one already in the bag (same code, severity,
 /// message, file, pointer and start position) is ignored: the same region
 /// of a file read twice, for example through two `$ref`s or two clients,
-/// reports each problem once.
+/// reports each problem once. Its preset hints ([Diagnostic.hints]) are
+/// added to the one in the bag, so two clients with different presets keep
+/// both hints.
 ///
 /// Diagnostics a baseline accepts are kept apart ([baselined]): they are
 /// not in [all], [count] or [hasErrors].
 final class DiagnosticBag {
   final List<Diagnostic> _items = [];
   final List<Diagnostic> _baselined = [];
-  final Set<(DiagnosticCode, Severity, String, String?, String?, int?)> _seen =
-      {};
-  final Set<(DiagnosticCode, Severity, String, String?, String?, int?)>
+  final Map<(DiagnosticCode, Severity, String, String?, String?, int?), int>
+  _seen = {};
+  final Map<(DiagnosticCode, Severity, String, String?, String?, int?), int>
   _seenBaselined = {};
 
   /// All diagnostics in the order they were reported.
@@ -42,15 +44,35 @@ final class DiagnosticBag {
   int count(Severity severity) =>
       _items.where((d) => d.severity == severity).length;
 
-  /// Adds an already built [diagnostic], unless an equal one is present.
-  void add(Diagnostic diagnostic) {
-    if (_seen.add(_keyOf(diagnostic))) _items.add(diagnostic);
-  }
+  /// Adds an already built [diagnostic], unless an equal one is present;
+  /// then only its new hints are added to that one.
+  void add(Diagnostic diagnostic) => _add(_items, _seen, diagnostic);
+
+  /// Adds [diagnostic], which a baseline accepts, like [add].
+  void addBaselined(Diagnostic diagnostic) =>
+      _add(_baselined, _seenBaselined, diagnostic);
 
-  /// Adds [diagnostic], which a baseline accepts, unless an equal one is
-  /// present.
-  void addBaselined(Diagnostic diagnostic) {
-    if (_seenBaselined.add(_keyOf(diagnostic))) _baselined.add(diagnostic);
+  static void _add(
+    List<Diagnostic> items,
+    Map<(DiagnosticCode, Severity, String, String?, String?, int?), int> seen,
+    Diagnostic diagnostic,
+  ) {
+    final key = _keyOf(diagnostic);
+    final index = seen[key];
+    if (index == null) {
+      seen[key] = items.length;
+      items.add(diagnostic);
+      return;
+    }
+    final present = items[index];
+    final hints = [
+      ...present.hints,
+      for (final hint in diagnostic.hints)
+        if (!present.hints.contains(hint)) hint,
+    ];
+    if (hints.length != present.hints.length) {
+      items[index] = present.withHints(hints);
+    }
   }
 
   static (DiagnosticCode, Severity, String, String?, String?, int?) _keyOf(
diff --git a/packages/typed_openapi/lib/src/normalize/normalizer.dart b/packages/typed_openapi/lib/src/normalize/normalizer.dart
index ea342e1..274d892 100644
--- a/packages/typed_openapi/lib/src/normalize/normalizer.dart
+++ b/packages/typed_openapi/lib/src/normalize/normalizer.dart
@@ -1,6 +1,8 @@
 import '../config/project_config.dart';
 import '../diagnostics/diagnostic.dart';
 import '../diagnostics/diagnostic_bag.dart';
+import '../diagnostics/diagnostic_code.dart';
+import '../diagnostics/json_pointer.dart';
 import '../load/openapi_version.dart';
 import '../load/spec_document.dart';
 import '../load/spec_loader.dart';
@@ -107,10 +109,12 @@ final class Normalizer {
     final loader = SpecLoader(_diagnostics);
     var root = document;
     var others = const <SpecDocument>[];
+    _OverrideOrigins? origins;
     if (overrides != null && !overrides.isEmpty) {
       final documents = SpecDocuments(loader, root);
+      final read = DiagnosticBag();
       final model = SpecReader(
-        DiagnosticBag(),
+        read,
       ).read(root, version, documents: documents);
       final targets = OverrideResolver(
         _diagnostics,
@@ -122,7 +126,28 @@ final class Normalizer {
         documents,
         version,
       ).edits(targets);
-      final edited = _applyOverrides(documents, overrides, edits);
+      final applied = <OverrideEdit>[];
+      final edited = _applyOverrides(documents, overrides, edits, applied);
+      origins = _OverrideOrigins(
+        overrides,
+        before: [
+          ...read.all,
+          for (final rule in _rules)
+            for (final finding in rule.check(
+              RuleContext(model, documents, version),
+            ))
+              finding.diagnostic,
+        ],
+        changes: [
+          for (final OverrideEdit(:edit, :sources) in applied)
+            for (final (entry, field) in sources)
+              (
+                documents.displayPath(edit.location.document),
+                _parentOf(edit.location.pointer),
+                entry.pointer.child(field),
+              ),
+        ],
+      );
       root = edited[root.uri] ?? root;
       others = [
         for (final loaded in documents.loaded)
@@ -144,10 +169,12 @@ final class Normalizer {
       ];
       final hasEdits = found.any((f) => f.$2.edits.isNotEmpty);
       if (!hasEdits || pass == maxPasses) {
-        scratch.all.forEach(_diagnostics.add);
+        for (final diagnostic in scratch.all) {
+          _diagnostics.add(origins?.attach(diagnostic) ?? diagnostic);
+        }
         final reported = <SpecEdit>[];
         for (final (rule, finding) in found) {
-          _report(rule, finding);
+          _report(rule, finding, origins);
           for (final edit in finding.edits) {
             // An edit proposed twice (a path item shared by several paths)
             // is one fix.
@@ -171,7 +198,7 @@ final class Normalizer {
           if (finding.edits.isNotEmpty) rule,
       };
       for (final (rule, finding) in found) {
-        if (fixing.contains(rule)) _report(rule, finding);
+        if (fixing.contains(rule)) _report(rule, finding, origins);
       }
       final edited = _apply(documents, found);
       root = edited[root.uri] ?? root;
@@ -220,20 +247,26 @@ final class Normalizer {
     };
   }
 
-  /// Applies the override [edits] in order; returns the edited documents by
-  /// URI. An edit that cannot be applied is reported at its override.
+  /// Applies the override [edits] in order and adds the applied ones to
+  /// [applied]; returns the edited documents by URI. An edit that cannot be
+  /// applied is reported at its override.
   Map<Uri, SpecDocument> _applyOverrides(
     SpecDocuments documents,
     OverrideSet overrides,
     List<OverrideEdit> edits,
+    List<OverrideEdit> applied,
   ) {
     final editors = <Uri, TreeEditor>{};
-    for (final OverrideEdit(:edit, :sources) in edits) {
+    for (final override in edits) {
+      final OverrideEdit(:edit, :sources) = override;
       final uri = edit.location.document;
       final document = documents[uri]!;
       final editor = editors[uri] ??= TreeEditor(document.root);
       final problem = editor.apply(edit);
-      if (problem == null) continue;
+      if (problem == null) {
+        applied.add(override);
+        continue;
+      }
       for (final (entry, field) in sources) {
         final at = entry.pointer.child(field);
         _diagnostics.report(
@@ -251,25 +284,27 @@ final class Normalizer {
     };
   }
 
-  void _report(NormalizerRule rule, Finding finding) {
+  void _report(
+    NormalizerRule rule,
+    Finding finding,
+    _OverrideOrigins? origins,
+  ) {
     final d = finding.diagnostic;
     final hint = switch (preset) {
       final preset? => rule.hint(d.code, preset),
       null => null,
     };
-    _diagnostics.add(
-      hint == null
-          ? d
-          : Diagnostic(
-              code: d.code,
-              severity: d.severity,
-              message: d.message,
-              file: d.file,
-              pointer: d.pointer,
-              span: d.span,
-              fix: d.fix == null ? hint : '${d.fix} $hint',
-            ),
-    );
+    final hinted = hint == null ? d : d.withHints([...d.hints, hint]);
+    _diagnostics.add(origins?.attach(hinted) ?? hinted);
+  }
+
+  /// The node an edit at [pointer] changes: the object or list it sets a
+  /// member of.
+  static JsonPointer _parentOf(JsonPointer pointer) {
+    final tokens = pointer.tokens;
+    return tokens
+        .take(tokens.isEmpty ? 0 : tokens.length - 1)
+        .fold(JsonPointer.root, (at, token) => at.child(token));
   }
 
   void _notApplied(
@@ -289,3 +324,60 @@ final class Normalizer {
     );
   }
 }
+
+/// Which problems of a spec its overrides introduced.
+///
+/// A problem is introduced when the spec as read, before the overrides,
+/// did not have it (same code, file and pointer), and an applied override
+/// changed a member of its node, of a node inside it or of a node around
+/// it.
+final class _OverrideOrigins {
+  _OverrideOrigins(
+    this._overrides, {
+    required List<Diagnostic> before,
+    required this.changes,
+  }) : _before = {for (final d in before) _keyOf(d)};
+
+  final OverrideSet _overrides;
+  final Set<(DiagnosticCode, String?, String?)> _before;
+
+  /// The changed nodes: the file as diagnostics name it, the pointer of the
+  /// node an override set a member of, and the pointer of the override field
+  /// that did.
+  final List<(String, JsonPointer, JsonPointer)> changes;
+
+  /// [diagnostic] with the overrides that introduced it as related
+  /// locations.
+  Diagnostic attach(Diagnostic diagnostic) {
+    final pointer = diagnostic.pointer;
+    if (pointer == null || _before.contains(_keyOf(diagnostic))) {
+      return diagnostic;
+    }
+    final related = [
+      for (final (file, at, field) in changes)
+        if (file == diagnostic.file && _nested(pointer, at))
+          RelatedLocation(
+            message: 'Introduced by this override.',
+            file: _overrides.file,
+            pointer: field,
+            span: _overrides.spanOf(field),
+          ),
+    ];
+    if (related.isEmpty) return diagnostic;
+    return diagnostic.withRelated([...diagnostic.related, ...related]);
+  }
+
+  static (DiagnosticCode, String?, String?) _keyOf(Diagnostic d) =>
+      (d.code, d.file, d.pointer?.value);
+
+  /// Whether one of [a] and [b] is the other or inside it.
+  static bool _nested(JsonPointer a, JsonPointer b) {
+    final x = a.tokens;
+    final y = b.tokens;
+    final length = x.length < y.length ? x.length : y.length;
+    for (var i = 0; i < length; i++) {
+      if (x[i] != y[i]) return false;
+    }
+    return true;
+  }
+}
```

- [ ] **Step 4: Перевірити**

Run (з `packages/typed_openapi`): `dart test`
Expected: PASS, 483 тести (`+483: All tests passed!`).

Run (з `packages/typed_openapi`): `dart format lib test bin` двічі
Expected: другий запуск — `0 changed`.

Run (з кореня): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 5: Коміт**

```bash
git add packages/typed_openapi
git commit -m "feat(typed_openapi): point problems an override introduces at the override and keep every preset hint" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 7: Документація, публічний API, прогін корпусу

**Files:**
- Modify: `CLAUDE.md`, `packages/typed_openapi/CHANGELOG.md`, `packages/typed_openapi/README.md`, `packages/typed_openapi/README.ua.md`, `packages/typed_openapi/lib/typed_openapi.dart`

**Interfaces:**
- Consumes: усе з задач 1–6.
- Produces: експорт `AnchorIndex`, `Baseline`, `BaselineEntry`, `BaselineMatch`, `BaselineLoader`, `Fingerprints`, `ClientCheck`, `RelatedLocation`, `DisplayPaths`, `SarifReporter`, `GitHubActionsReporter`, `SeverityLevels`. Не експортуються `BaselineCommand` і його підкоманди.

- [ ] **Step 1: Документація і експорт**

Diff `CLAUDE.md`, `packages/typed_openapi/CHANGELOG.md`, `packages/typed_openapi/README.md`, `packages/typed_openapi/README.ua.md`, `packages/typed_openapi/lib/typed_openapi.dart` (`git apply` з кореня):

````diff
diff --git a/CLAUDE.md b/CLAUDE.md
index 1449442..9f83d87 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -32,9 +32,14 @@ Git commands run from the repo root. Commit messages are Conventional Commits
 
 All under `packages/typed_openapi/lib/src/`, one folder per stage:
 
-- `diagnostics/` - `Diagnostic`, `DiagnosticCode` (stable `TOAnnn` catalog),
-  `Severity`, `JsonPointer`, `DiagnosticBag`, and the reporters
-  (`DiagnosticReporter`, `TextReporter`, `JsonReporter`, `ReportFormat`).
+- `diagnostics/` - `Diagnostic` (with `RelatedLocation`s, preset `hints`
+  and fingerprint `args`), `DiagnosticCode` (stable `TOAnnn` catalog;
+  `fixedCodes` cannot be lowered, `configCodes` not changed), `Severity`,
+  `SeverityLevels` (a client's `severity` config), `JsonPointer`,
+  `DiagnosticBag` (baselined diagnostics kept apart), `DisplayPaths` (files
+  relative to the working directory, absolute outside it), and the reporters
+  (`DiagnosticReporter`, `TextReporter`, `JsonReporter`, `SarifReporter`,
+  `GitHubActionsReporter`, `ReportFormat`).
 - `load/` - `SpecLoader` reads JSON/YAML into a `SpecDocument` (plain tree,
   absolute file URI, source spans by JSON pointer, `valueAt(pointer)`,
   `withRoot`) through `YamlComposer`, which `ConfigLoader` uses too.
@@ -157,18 +162,31 @@ All under `packages/typed_openapi/lib/src/`, one folder per stage:
   a value cannot be written as YAML (non-finite numbers).
 - `config/` - `ConfigLoader`, `ProjectConfig`, `ClientConfig`, `Preset`.
 - `check/` - `SpecChecker`: config -> load -> version -> overrides ->
-  `Normalizer`; an overrides file that cannot be used is reported (an
-  error) and the spec is checked without it; `generate` (M9) must skip
-  such a client.
+  `Normalizer` once per run (file, preset, rules, overrides file); an
+  overrides file that cannot be used is reported (an error) and the spec is
+  checked without it; `generate` (M9) must skip such a client. Each client
+  then applies its levels (`checkClients` -> `ClientCheck`) and its baseline
+  (`check`).
+- `baseline/` - `AnchorIndex` (logical addresses of a spec's nodes:
+  operation `METHOD /path`, `in:name` parameter, components schema,
+  property), `Fingerprints` (anchor, `sha256([code, anchor, args])[:12]`),
+  `Baseline`, `BaselineEntry`, `BaselineMatch` (match, prune, YAML) and
+  `BaselineLoader` (TOA820, TOA821).
 - `cli/` - `TypedOpenApiCli` (`cli.dart`, owns the `CommandRunner` and maps
-  usage errors to exit code 64) and `CheckCommand` (`check_command.dart`,
-  options `--config/-c` and `--format`, client names as positional
-  arguments); `bin/typed_openapi.dart` only calls `TypedOpenApiCli().run(args)`
+  usage errors to exit code 64; `workingDirectory` for tests),
+  `CheckCommand` (`check_command.dart`, options `--config/-c`, `--format`
+  (`text`, `json`, `sarif`, `github-actions`), `--show-baselined`,
+  `--strict-baseline`, client names as positional arguments) and
+  `BaselineCommand` (`baseline_command.dart`, subcommands `create` and
+  `prune`); `bin/typed_openapi.dart` only calls `TypedOpenApiCli().run(args)`
   and sets `exitCode`.
 - `lib/typed_openapi.dart` exports the public API, each with a `show` list:
-  `SpecChecker`, `TypedOpenApiCli`, `ConfigLoader`, `ClientConfig`, `Preset`,
-  `ProjectConfig`, the diagnostics (`Diagnostic`, `DiagnosticBag`,
-  `DiagnosticCode`, `JsonPointer`, `Severity` and the reporters), the loader
+  `SpecChecker`, `ClientCheck`, `TypedOpenApiCli`, `ConfigLoader`,
+  `ClientConfig`, `Preset`, `ProjectConfig`, the diagnostics (`Diagnostic`,
+  `RelatedLocation`, `DiagnosticBag`, `DiagnosticCode`, `DisplayPaths`,
+  `JsonPointer`, `Severity`, `SeverityLevels` and the reporters), the
+  baseline (`AnchorIndex`, `Baseline`, `BaselineEntry`, `BaselineMatch`,
+  `BaselineLoader`, `Fingerprints`), the loader
   (`SpecLoader`, `SpecDocument`, `OpenApiVersion`, `OpenApiVersionDetector`),
   the whole `model/` (`SpecNode`, `SpecLocation`, `RefOr`, `Ref`, `Inline`,
   `RefKind`, `OpenApiDocument` and the other OAS objects), the entry points
@@ -176,7 +194,7 @@ All under `packages/typed_openapi/lib/src/`, one folder per stage:
   (`Normalizer`, `NormalizedSpec`, `NormalizerRule`, `RuleContext`,
   `Finding`, `SpecEdit`, `EditOperation`) and the overrides file
   (`OverrideLoader`, `OverrideSet`, `OverrideEntry` and its subclasses,
-  `DartTypeOverride`). Not exported: `CheckCommand`, the
+  `DartTypeOverride`). Not exported: `CheckCommand`, `BaselineCommand`, the
   internals of `parse/` (`OpenApiParser`, `OperationParser`, `SchemaParser`,
   `ObjectReader`, `ParseContext`, `SpecIndex`, `DialectChecker`), `resolve/`
   (`RefTarget`, `RefResolver`), `normalize/` (`TreeEditor`, the rule
@@ -194,11 +212,12 @@ Rules of the pipeline:
 - Reports are deterministic: diagnostics sort by file, position, pointer, code,
   message (`Diagnostic.compareTo`, `DiagnosticBag.sorted`). `DiagnosticBag`
   ignores a diagnostic equal to one it has (same code, severity, message, file,
-  pointer and start position), so a region read twice reports once.
+  pointer and start position), so a region read twice reports once; only its
+  new preset hints are added. Paths are relative to the working directory.
 - The CLI never calls `exit()`; commands return the code. Reports go to
   stdout, usage errors to stderr. Codes: `0` ok, `1` errors found, `64` usage,
   `78` the config file could not be loaded (TOA904 and per-client TOA902 exit
-  `1`).
+  `1`). Diagnostics a baseline accepts do not count.
 
 ## Code rules
 
diff --git a/packages/typed_openapi/CHANGELOG.md b/packages/typed_openapi/CHANGELOG.md
index 9bf8fa4..6c05e70 100644
--- a/packages/typed_openapi/CHANGELOG.md
+++ b/packages/typed_openapi/CHANGELOG.md
@@ -102,3 +102,35 @@
   `ResponseOverride`, `SchemaOverride`, `PropertyOverride`,
   `DartTypeOverride`; `Normalizer.normalize` takes `overrides:` and
   `NormalizedSpec.overrides` is the set, or null without an overrides file.
+- Paths in reports are relative to the working directory, in every format
+  and for every file (the config, specs, files reached through `$ref`,
+  overrides and baseline files); a file outside it is named by its absolute
+  path (`DisplayPaths`). `TypedOpenApiCli(workingDirectory:)` sets the
+  directory for tests and tools.
+- Levels in the config: `severity: {<code or name>: error|warning|info|off}`
+  in `defaults` and per client (a client overrides `defaults` code by code)
+  changes the report and the exit code. An unknown code is TOA903; a bad
+  level, a code named twice, lowering or turning off a code without which
+  the spec or the overrides file would pass broken
+  (`DiagnosticCode.fixedCodes`), and any change of a config code are TOA902.
+- Baseline (R2.3): `clients.<name>.baseline` names a YAML file written by
+  `typed_openapi baseline create [client...]`; `check` then hides the
+  diagnostics it accepts and counts them (`baselined: N`), lists them marked
+  with `--show-baselined`, and reports an entry that matches nothing (or
+  fewer diagnostics than its `count`) as TOA822 (warning, an error with
+  `--strict-baseline`) with a hint to run `typed_openapi baseline prune`.
+  Entries are keyed by a fingerprint: the first 12 hex digits of SHA-256 of
+  `[code, anchor, args]`, where the anchor is the logical address of the
+  place (operation `METHOD /path`, `in:name` parameter, components schema,
+  property) or the file (relative to the baseline file) and JSON pointer;
+  message text and positions are not part of it. A missing baseline file
+  is TOA820, an unreadable one or a bad entry TOA821, a file that cannot be
+  written TOA823; two clients naming one baseline file is TOA902.
+- Report formats `sarif` (SARIF 2.1.0: rules, levels, relative URIs,
+  logical locations, `relatedLocations`, baselined results as suppressed)
+  and `github-actions` (workflow-command annotations).
+- A problem an override introduces has a related location: the override
+  field (text `related:`, JSON `related`, SARIF `relatedLocations`).
+- Preset hints are kept apart (`Diagnostic.hints`): a finding two clients
+  share keeps the hints of both presets instead of the first one's.
+- `Diagnostic.args` (part of the fingerprint): the field name of TOA112.
diff --git a/packages/typed_openapi/README.md b/packages/typed_openapi/README.md
index 3654aa3..cbde051 100644
--- a/packages/typed_openapi/README.md
+++ b/packages/typed_openapi/README.md
@@ -28,7 +28,7 @@ Check the specs without generating anything:
 ```sh
 dart run typed_openapi check            # all clients
 dart run typed_openapi check core_api   # one client
-dart run typed_openapi check --format json
+dart run typed_openapi check --format json   # also: sarif, github-actions
 ```
 
 `check` reads the whole spec, follows its `$ref`s (also into other local
@@ -73,9 +73,41 @@ code generation lands. Hints of rules that cannot fix a defect themselves
 end with the override to copy.
 
 Every finding has a stable code (`TOA011`), a JSON pointer into the spec and,
-for files the parser could position, a line and column. Exit code `1` means
-at least one error, `64` wrong arguments or an unknown client, `78` the
-config could not be read.
+for files the parser could position, a line and column. Paths are relative
+to the directory you run the command in. Change the level of a code, by its
+id or name, in `defaults` or per client; `off` drops it. Codes without which
+a broken spec, overrides or baseline file would pass cannot be lowered:
+
+```yaml
+defaults:
+  severity: {TOA208: off, duplicate-operation-id: warning}
+```
+
+To adopt the tool on a spec with many findings, accept the current ones in
+a baseline and fail only on new ones:
+
+```yaml
+clients:
+  core_api:
+    input: specs/core_api.json
+    output: lib/src/api/core_api
+    baseline: specs/core_api.baseline.yaml
+```
+
+```sh
+dart run typed_openapi baseline create   # accept today's findings
+dart run typed_openapi check             # new findings only; "baselined: N"
+dart run typed_openapi check --show-baselined
+dart run typed_openapi baseline prune    # drop entries that no longer match
+```
+
+A finding is matched by a fingerprint of its code and its place (the
+operation, parameter, schema or property when it has one), not by its
+message or line, so rewording a message or editing the spec elsewhere keeps
+it. An entry that no longer matches is a warning that suggests
+`baseline prune`; `check --strict-baseline` makes it an error. Exit code `1`
+means at least one error that is not accepted, `64` wrong arguments or an
+unknown client, `78` the config could not be read.
 
 Generated clients depend on
 [`typed_openapi_runtime`](../typed_openapi_runtime/README.md).
diff --git a/packages/typed_openapi/README.ua.md b/packages/typed_openapi/README.ua.md
index 16cf3d2..798a4f7 100644
--- a/packages/typed_openapi/README.ua.md
+++ b/packages/typed_openapi/README.ua.md
@@ -29,7 +29,7 @@ clients:
 ```sh
 dart run typed_openapi check            # усі клієнти
 dart run typed_openapi check core_api   # один клієнт
-dart run typed_openapi check --format json
+dart run typed_openapi check --format json   # також: sarif, github-actions
 ```
 
 `check` читає всю специфікацію, проходить її `$ref` (зокрема в інші локальні
@@ -74,9 +74,42 @@ Override, ціль якого зникла, дає warning, той, з яким
 дефект самі, закінчуються override-ом, який можна скопіювати.
 
 У кожної знахідки є стабільний код (`TOA011`), JSON-pointer на місце в
-специфікації і, якщо парсер зміг визначити позицію, рядок і колонка. Код
-виходу `1` означає хоча б одну помилку, `64` — неправильні аргументи або
-невідомий клієнт, `78` — конфіг не вдалося прочитати.
+специфікації і, якщо парсер зміг визначити позицію, рядок і колонка. Шляхи —
+відносно каталогу, з якого запущено команду. Рівень коду (за кодом або
+назвою) змінюється в `defaults` або в клієнті; `off` вимикає його. Коди, без
+яких зламаний файл специфікації, override-ів чи baseline пройшов би
+перевірку, знизити не можна:
+
+```yaml
+defaults:
+  severity: {TOA208: off, duplicate-operation-id: warning}
+```
+
+Щоб почати зі специфікацією, де багато знахідок, зафіксуй наявні в baseline
+і вали перевірку лише на нових:
+
+```yaml
+clients:
+  core_api:
+    input: specs/core_api.json
+    output: lib/src/api/core_api
+    baseline: specs/core_api.baseline.yaml
+```
+
+```sh
+dart run typed_openapi baseline create   # зафіксувати сьогоднішні знахідки
+dart run typed_openapi check             # лише нові; «baselined: N»
+dart run typed_openapi check --show-baselined
+dart run typed_openapi baseline prune    # прибрати записи, що вже не збігаються
+```
+
+Знахідка зіставляється за fingerprint її коду і місця (операція, параметр,
+схема чи властивість, якщо місце їх має), а не за текстом чи рядком, тож
+інше формулювання повідомлення чи правка деінде в специфікації його не
+змінюють. Запис, що більше не збігається, — warning з підказкою
+`baseline prune`; `check --strict-baseline` робить його помилкою. Код виходу
+`1` означає хоча б одну незафіксовану помилку, `64` — неправильні аргументи
+або невідомий клієнт, `78` — конфіг не вдалося прочитати.
 
 Згенеровані клієнти залежать від
 [`typed_openapi_runtime`](../typed_openapi_runtime/README.ua.md).
diff --git a/packages/typed_openapi/lib/typed_openapi.dart b/packages/typed_openapi/lib/typed_openapi.dart
index f813174..281fdec 100644
--- a/packages/typed_openapi/lib/typed_openapi.dart
+++ b/packages/typed_openapi/lib/typed_openapi.dart
@@ -4,21 +4,32 @@
 /// diagnostics. [SpecReader] reads a loaded spec into the typed model
 /// ([SpecModel]) with its `$ref`s resolved; [OverrideLoader] reads a
 /// client's overrides file; [Normalizer] applies its spec fields, runs the
-/// named rules over the spec and applies their fixes.
+/// named rules over the spec and applies their fixes. [Baseline] and
+/// [BaselineLoader] read and write a client's baseline file, and
+/// [Fingerprints] computes the keys it matches diagnostics by.
 library;
 
-export 'src/check/spec_checker.dart' show SpecChecker;
+export 'src/baseline/anchor_index.dart' show AnchorIndex;
+export 'src/baseline/baseline.dart' show Baseline, BaselineEntry, BaselineMatch;
+export 'src/baseline/baseline_loader.dart' show BaselineLoader;
+export 'src/baseline/fingerprints.dart' show Fingerprints;
+export 'src/check/spec_checker.dart' show ClientCheck, SpecChecker;
 export 'src/cli/cli.dart' show TypedOpenApiCli;
 export 'src/config/config_loader.dart' show ConfigLoader;
 export 'src/config/project_config.dart'
     show ClientConfig, Preset, ProjectConfig;
-export 'src/diagnostics/diagnostic.dart' show Diagnostic;
+export 'src/diagnostics/diagnostic.dart' show Diagnostic, RelatedLocation;
 export 'src/diagnostics/diagnostic_bag.dart' show DiagnosticBag;
 export 'src/diagnostics/diagnostic_code.dart' show DiagnosticCode;
+export 'src/diagnostics/display_paths.dart' show DisplayPaths;
+export 'src/diagnostics/github_actions_reporter.dart'
+    show GitHubActionsReporter;
 export 'src/diagnostics/json_pointer.dart' show JsonPointer;
 export 'src/diagnostics/reporters.dart'
     show DiagnosticReporter, JsonReporter, ReportFormat, TextReporter;
+export 'src/diagnostics/sarif_reporter.dart' show SarifReporter;
 export 'src/diagnostics/severity.dart' show Severity;
+export 'src/diagnostics/severity_levels.dart' show SeverityLevels;
 export 'src/load/openapi_version.dart'
     show OpenApiVersion, OpenApiVersionDetector;
 export 'src/load/spec_document.dart' show SpecDocument;
````

- [ ] **Step 2: Перевірити**

Run (з `packages/typed_openapi`): `dart test`
Expected: PASS, 483 тести (`+483: All tests passed!`).

Run (з `packages/typed_openapi`): `dart format lib test bin` двічі
Expected: другий запуск — `0 changed`.

Run (з кореня): `dart analyze packages`
Expected: `No issues found!`

- [ ] **Step 3: Прогін корпусу**

Скомпілюй `bin/typed_openapi.dart` на `main` і після задачі 7 (`dart compile exe`) і запусти `check -c typed_openapi.yaml --format json` на конфігу публічного корпусу (research/08) — один раз з каталогу конфігу, другий — з батьківського каталогу (`-c corpus/typed_openapi.yaml`).
Expected: з каталогу конфігу звіти однакові, крім нового `summary.baselined: 0` і полів `related: []`, `baselined: false` (на момент планування — 1029 діагностик: 2 error, 853 warning, 174 info, код виходу `1`). З батьківського каталогу різниця лише в `file`: на `main` — відносно конфігу (`openai/openapi.yaml`), після M5 — відносно робочого каталогу (`corpus/openai/openapi.yaml`); 12 файлів, зокрема файли за `$ref` (`corpus/grace/src/src/OpenAPI/Shared.Components.OpenAPI.yaml`, `corpus/medusa/.../BaseRegionCountry.yaml`). `--format sarif` — 1029 результатів, 12 правил; `--format github-actions` — код виходу `1`.

- [ ] **Step 4: Коміт**

```bash
git add CLAUDE.md packages/typed_openapi/CHANGELOG.md packages/typed_openapi/README.md packages/typed_openapi/README.ua.md packages/typed_openapi/lib/typed_openapi.dart
git commit -m "docs(typed_openapi): document baselines, levels and report formats" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Перевірити пакет**

Run (з `packages/typed_openapi`, після коміту): `dart pub publish --dry-run`
Expected: `Package has 0 warnings.`

## Відкриті питання

Специфікація лишає їх відкритими; план реалізує запропонований варіант, а користувач підтверджує або змінює його до виконання.

1. **Формат файлу baseline.** YAML з коментарем-шапкою, `version: 1` і `entries:` — список записів `fingerprint`, `code`, `anchor`, `message`, `count` (лише коли > 1); рядки — у лапках JSON, записи — за кодом, якорем, fingerprint. Чи потрібні `version` і коментар; чи писати `count: 1`?
2. **Запис якоря.** `@/<адреса override-у як JSON pointer>#<хвіст pointer-а>` (`@/schemas/Tag/properties/name#/required`, `@/operations/GET ~1pets/parameters/query:limit#/bogus`) і `<файл>#<pointer>` без адреси. Операція — завжди `METHOD /path`, а не `operationId`: перейменування шляху змінює fingerprint, перейменування `operationId` — ні. Чи прийнятно, чи віддати перевагу `operationId`?
3. **Список незмінних кодів.** Чи всі коди файлу override-ів (TOA801–TOA809, зокрема info TOA807–TOA809 і warning TOA804) мають бути незмінними, чи лише «файл не читається» (TOA801–TOA803)? Коди конфігу не змінюються зовсім — чи дозволити підняти TOA903 до error (тоді рівні з `defaults` треба застосовувати й до діагностик конфігу)?
4. **Що пише `baseline create`.** Усі діагностики клієнта після рівнів, зокрема info, крім незмінних кодів. Чи фіксувати info (вони не валять CI), чи лише error і warning?
5. **Вивід `baseline create` / `prune`.** Звіт text (незмінні коди, що лишилися, і проблеми файлу baseline) і рядок `Wrote api.baseline.yaml: 2 entries accept 2 diagnostics.` / `Pruned …: removed N entries, M left.`; `--format` немає; без `baseline` у конфігу — помилка використання (`64`). Чи так?
6. **Розмітка прийнятих у звіті.** text: `warning TOA201 bool-required [baselined]: …` і `, baselined: N` у підсумку лише коли N > 0; JSON: `baselined` у кожній діагностиці і в `summary` завжди; SARIF: `suppressions` (external); github-actions: `::notice` з `(baselined)`.
7. **Текст у SARIF і github-actions.** Повідомлення разом із fix (`\nFix: …` у SARIF; `at <pointer>` і `fix: …` окремими рядками в анотації). Чи прибрати fix з тексту SARIF (лишивши в `properties`)?
8. **Підказки двох пресетів** однієї знахідки йдуть у `fix` поспіль, без назви клієнта. Чи називати клієнта/пресет біля підказки?
