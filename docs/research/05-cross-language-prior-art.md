# 05. Prior art з інших мов і комерційних SDK-генераторів

Дата: 2026-10-11. Обсяг: конкретні патерни, які можна скопіювати, для R2, R3, R4, R5, R6.2/R6.4, R7, R8, R9, R10.5/R10.8, R11, R12, R13.1 і R14. Це не загальний огляд інструментів. Нормалізатор OpenAPI Generator тут згадано лише коротко, бо його розбирає окремий документ.

Метод: офіційні документи, README і вихідний код (через `gh api`). Кожне твердження має посилання. Якщо щось не вдалося перевірити, це сказано прямо. Позначки: **✅ взяти**, **⚠️ адаптувати**, **❌ уникати**.

---

## 0. Коротко: 15 найцінніших патернів

1. **Каталог діагностик Stainless** (R2.2). Код має форму `Категорія/Назва`, наприклад `Schema/ArrayMissingItems` чи `Name/Collision`. Рівнів чотири: Fatal, Error, Warning, Note. Текст повідомлення — шаблон із параметрами і порадою, що робити. Ігнорувати можна в конфігу: `diagnostics.ignored: {код: [{location, reason}]}`.
2. **Відбиток (fingerprint) з oasdiff** (R2.3, R14). Рахується як `SHA256("{id}:{operation}:{path}:{args}")[:12]`. Текст повідомлення в хеш не входить, тому відбиток — найкращий ключ для baseline.
3. **Масові придушення ESLint** (R2.3, ratchet). Файл має форму «файл → правило → count». Нові порушення ламають збірку. Якщо придушення більше не спрацьовує, процес завершується з ненульовим кодом і радить `--prune-suppressions`.
4. **`Transform/Useless` у Stainless і «does nothing» / «did not match any targets» у Speakeasy** (R3.2). Override, що нічого не змінив або нічого не знайшов, дає окрему діагностику.
5. **`strict: true` для overlay в oapi-codegen** (R3.2/R3.3). Режим увімкнено за замовчуванням, він «підсвічує дії, які нічого не змінюють».
6. **Трансформації Stainless з обов'язковим `reason`** (R3). Є операції `update`, `append`, `merge`, `remove`, `copy` і `move`. `matches_schema` знаходить усі схеми, глибоко рівні шаблону, і замінює їх на `$ref`. Це дедуплікація «з коробки».
7. **Фільтри `GET /path` з регулярними виразами в hey-api і `#METHOD` у Kiota** (R4). `exclude` має пріоритет. Схеми-сироти прибираються автоматично, щойно задано будь-який фільтр.
8. **Відкриті enum: `x-speakeasy-unknown-values` / `forwardCompatibleEnumsByDefault` у Speakeasy і `Known`/`Value._UNKNOWN` у Stainless Java** (R8). Сире значення зберігається, enum з одним значенням лишаються закритими.
9. **`OptNil[T]` в ogen з явною таблицею «required × nullable → поведінка декодера»** (R6.1/R7). Поруч `Unset` в openapi-python-client, `Omit` у Stainless Python і `JsonField` (missing/null/value) у Stainless Java.
10. **`defaultMapping` у дискримінаторі OAS 3.2** (R9). Це стандартний спосіб задати запасний варіант для невідомого або відсутнього значення дискримінатора. Speakeasy повертає `{type: "UNKNOWN", raw}`.
11. **`undocumented(statusCode:, payload)` у swift-openapi-generator і `Error<E>` у progenitor** (R11). Транспортні збої, задокументовані помилки, помилки декодування і незадокументовані відповіді — окремі варіанти.
12. **Таблиця обробників `streaming.on_event` у Stainless** (R12). Обробники `event_type`, `data_starts_with` і `kind: fallthrough` мають дії `yield | done | break | error`. Fern додає `resumable` (Last-Event-ID, `retry:`, ліміт 5 спроб із скиданням) і `terminator`.
13. **FastAPI вже видає `itemSchema` для `text/event-stream`, хоча документ має `openapi: 3.1.0`** (R1.4/R12). Нормалізатор має приймати ключ із 3.2 у документах 3.0 і 3.1.
14. **Lock-файли Kiota і Speakeasy** (R13.1/R14). Зберігають хеш опису, хеш конфігу і версію генератора. **Editions у Stainless** — версіоновані набори змін виходу, які ламають сумісність (стосується R15.4).
15. **`--fail-on` і `--severity-levels` в oasdiff** (R14). Перевірки враховують напрям даних (запит чи відповідь). Для Dart API є готовий `dart_apitool diff`.

---

## R2. Нормалізатор, діагностика, baseline, режим lint

### Як це роблять інші

**Stainless: каталог діагностик.** Довідник [Generator diagnostics](https://www.stainless.com/docs/reference/diagnostics/) — найближчий аналог того, чого вимагає R2.2.
- Код має форму `Категорія/Назва`. Категорії: `Schema`, `Name`, `Endpoint`, `Method`, `Parameter`, `Pagination`, `Streaming`, `Transform`, `OAS`, `Reference` і окремо мовні (`Go/…`, `Java/…`). Приклади: `Schema/ArrayMissingItems`, `Schema/EnumDuplicateMembers`, `Schema/RequiredPropertyNotDefined`, `Schema/IsAmbiguous`, `Parameter/PathTemplateVariableMissing`, `Operation/PathTemplateVariableMissingParameter`, `Name/Collision`, `Transform/Useless`.
- Рівні прив'язані до процесу релізу: 💀 Fatal (генерація неможлива), ❌ Error («усунути до 0.0.1»), ⚠️ Warning («до 1.0.0»), ✍️ Note («розглянути до 1.0.0»).
- Повідомлення — шаблон із параметрами (`{oas_path}`, `{endpoint}`, `{fallback_name}`), і кожне каже, як виправити. Приклад `Schema/IsAmbiguous`: «у схеми немає `type`, тому трактуємо її як `unknown`… якщо вона справді приймає будь-що, додайте `x-stainless-any: true`… для багатьох таких схем застосуйте `update`-трансформацію з `matches_schema`». Діагностика пропонує конкретну дію, як того вимагає R2.5.
- Придушення живе в конфігу ([DiagnosticsConfig](https://www.stainless.com/docs/reference/config/)): `diagnostics.ignored: Record<код, true | Array<{location, reason} | {target: мова, reason}>>`. Ігнорувати можна або все, або окремі місця, і кожне місце має обов'язковий `reason`.
- Є [Language Server](https://www.stainless.com/docs/tools/stainless-language-server/), тож діагностики видно прямо в редакторі.

**Speakeasy: lint-правила з категоріями** ([linting](https://www.speakeasy.com/docs/sdks/prep-openapi/linting)).
- ID у kebab-case з префіксом категорії: `generator-*` (генерація SDK), `semantic-*`, `style-*`, `oas3-*`, `owasp-*`. Приклади: `generator-duplicate-schema-name`, `generator-duplicate-path-params`, `generator-validate-enums`, `generator-duplicate-inline-schemas`.
- У `.speakeasy/lint.yaml` визначаються ruleset-и з `extends`. Правило перевизначається через `id`, `severity: error|warn|hint`, `disabled: true` і `match` (регулярний вираз по тексту повідомлення).
- Ruleset **`speakeasy-generation`** (32 правила, з них 26 `generator-*`) завжди застосовується перед генерацією, і перевизначити його не можна. Тобто частина правил принципово не знижується.
- Механізму baseline немає.

**Kiota: іменовані правила валідації** ([using](https://learn.microsoft.com/en-us/openapi/kiota/using)).
- Правила: `DivergentResponseSchema`, `GetWithBody`, `InconsistentTypeFormat`, `KnownAndNotSupportedFormats`, `MissingDiscriminator`, `MultipleServerEntries`, `NoContentWithBody`, `NoServerEntry`, `UrlFormEncodedComplex`.
- Усі видають warning і вимикаються за назвою: `--disable-validation-rules NoServerEntry` або `all`.

**OpenAPI Generator: нормалізатор** ([customization.md](https://github.com/OpenAPITools/openapi-generator/blob/master/docs/customization.md)). Іменовані правила, кожне вмикається окремо через `--openapi-normalizer RULE=true`: `REF_AS_PARENT_IN_ALLOF`, `SIMPLIFY_ONEOF_ANYOF`, `SIMPLIFY_BOOLEAN_ENUM`, `FIX_DUPLICATED_OPERATIONID`, `REMOVE_X_INTERNAL`, `FILTER` і інші. Детальний розбір — в окремому документі.

**Redocly CLI** ([lint](https://redocly.com/docs/cli/commands/lint), [rules](https://redocly.com/docs/cli/configuration/reference/rules)).
- Рівні: `error | warn | off`. Вбудовані правила мають прості назви (`security-defined`), налаштовувані — префікс `rule/…`, правила плагінів — `plugin/rule`.
- JSON-вивід містить `location[].pointer` (JSON Pointer), `source.ref`, `start`/`end` з `line`/`col` і `reportOnKey`.
- **`--generate-ignore-file`** створює `.redocly.lint-ignore.yaml`. Це по суті baseline зі структурою «файл → ruleId → [JSON pointers]»:
  ```yaml
  museum-with-errors.yaml:
    operation-operationId:
      - '#/paths/~1museum-hours/get/operationId'
  ```
- Проігноровані проблеми все одно рахуються, і вивід показує їхню кількість.
- Формати: `codeframe`, `stylish`, `json`, `checkstyle`, `codeclimate`, `github-actions`, `markdown`, `summary`, `junit`.

**Spectral** ([overrides](https://github.com/stoplightio/spectral/blob/develop/docs/guides/4d-overrides.md), [CLI](https://github.com/stoplightio/spectral/blob/develop/docs/guides/2-cli.md)).
- Правило можна вимкнути в конкретному місці: `overrides: [{files: ["legacy/**/*.oas.json#/paths/~1Pets~1%7BpetId%7D/get/parameters/0"], rules: {rule: "off"}}]`. Це glob файлу плюс JSON Pointer.
- Застереження: overrides працюють лише для кореневих документів, а не для зовнішніх `$ref`.
- `--fail-severity`. Формати включають `sarif`, `github-actions`, `junit`, `gitlab`.

**vacuum** ([lint](https://quobix.com/vacuum/commands/lint/), [ignoring](https://quobix.com/vacuum/ignoring/)).
- `--ignore-file` — YAML у формі «rule id → [точні шляхи результатів або вирази JSONPath]». Генерується командою `vacuum generate-ignorefile`.
- Вбудоване придушення `x-lint-ignore: rule-id | [ids]` діє на об'єкт і все його піддерево.
- `--fail-severity error|warn|info|hint|none`.

**Zally** ([README](https://github.com/zalando/zally), [rules.md](https://github.com/zalando/zally/blob/main/server/rules.md)). ID правил мають форму `M008`, `S005`, `H001`. Є вбудоване придушення `x-zally-ignore`, але є й окреме правило H002, яке нагадує, що ним варто користуватися «помірно, для тимчасових винятків».

**Ratchet у лінтерах коду** — найкращий прототип для R2.3:
- **ESLint, bulk suppressions** (v9.24, [документація](https://eslint.org/docs/latest/use/suppressions), [анонс](https://eslint.org/blog/2025/04/introducing-bulk-suppressions/)).
  - `eslint --suppress-all` записує `eslint-suppressions.json` у формі «файл → правило → `{count}`».
  - `count` — це стеля: якщо порушень стало більше, звітуються **всі**, а не лише нові.
  - Якщо придушення більше не спрацьовують, процес завершується з ненульовим кодом і повідомленням «There are suppressions left that do not occur anymore. Consider re-running the command with `--prune-suppressions`».
  - Вимкнути цю поведінку можна прапорцем `--pass-on-unpruned-suppressions` (v9.28).
- **PHPStan** ([baseline](https://phpstan.org/user-guide/baseline)). `--generate-baseline` пише записи `message` (регулярний вираз) + `count` + `path`. Якщо проігнорована помилка зникла, PHPStan про це повідомляє (`reportUnmatchedIgnoredErrors`).

**oasdiff: відбиток** ([FINGERPRINT.md](https://github.com/oasdiff/oasdiff/blob/main/docs/FINGERPRINT.md)).
- Формула: `SHA256("{id}:{operation}:{path}:{args}")[:12]`, де `args` — значення, з яких будується повідомлення.
- Текст повідомлення в хеш не входить, тож переформулювання відбиток не змінює.
- Документація чесно перелічує, коли відбиток «плаває»: позиційні назви на кшталт `oneOf[subschema #4]` і перейменування.

### Що взяти для Dart

- ✅ **Запис діагностики**:
  ```
  {code: "SG012", name: "array-missing-items", severity: warning,
   message: <шаблон+args>, pointer: "#/components/schemas/Pet/properties/tags",
   source: {file, line, col}, fix: {text, override: <готовий YAML-фрагмент>},
   fingerprint: sha256(code|pointer|args)[:12]}
  ```
  Числовий код `SG012` потрібен за R2.2, а людська назва в стилі Stainless робить код читабельним. Каталог документації (R15.5) генерується з того самого реєстру кодів, як сторінка Stainless.
- ✅ **Рівні з бізнес-семантикою.** Кожному рівню error/warning/info дати пояснення в дусі Stainless («блокує генерацію», «генерує, але API погіршене», «підказка»). Додати внутрішній fatal для «неможливо продовжити».
- ✅ **Незнижувані коди.** Позначка `overridable: false` для кодів, без яких генерація неможлива (як ruleset `speakeasy-generation`): нерозв'язний `$ref`, цикл без можливості розриву тощо.
- ✅ **Перевизначення рівня і точкове придушення** в конфігу:
  `diagnostics: {SG012: warning, SG020: off, ignore: {SG031: [{pointer: "#/paths/~1legacy~1*", reason: "…"}]}}`.
  `reason` має бути обов'язковим, як у Stainless. Pointer-и підтримують glob, як overrides у Spectral.
- ✅ **Baseline** — окремий файл, відсортований детерміновано:
  ```yaml
  # openapi_dart.baseline.yaml
  specs/api.yaml:
    SG012:
      - {fingerprint: a3f8c21b9d04, pointer: "#/components/schemas/Pet/properties/tags"}
    SG044: {count: 7}   # ESLint-стиль для «масових» кодів
  ```
  Поведінка:
  - нова діагностика, якої немає в baseline, з рівнем не нижче `--fail-on` → помилка;
  - якщо запис baseline більше не спрацьовує → діагностика `SG0xx stale-baseline-entry`, і CI падає, поки її не прибрати командою `baseline prune` (як ESLint). Опційно — `--allow-stale-baseline`;
  - команди: `baseline create | update | prune`.
- ✅ **Кожне спрацювання нормалізатора — це info-діагностика** зі своїм кодом і pointer-ом. Тоді звіт, baseline і рівні працюють однаково і для виправлень, і для проблем. Назви правил у kebab-case, як у Speakeasy. Набір правил — як у OpenAPI Generator.
- ✅ **Формати виводу**: `text` (codeframe), `json` (з опублікованою JSON Schema виводу, як `oasdiff schema`), `sarif` (GitHub code scanning), `github-actions`, `junit`. Команда `check` / `lint` проходить той самий конвеєр без генерації коду (R2.4).
- ⚠️ **Позиції line/col** можливі лише при YAML-парсингу з позиціями. Для JSON oasdiff прямо пише, що позицій немає ([SOURCE-LOCATOR.md](https://github.com/oasdiff/oasdiff/blob/main/docs/SOURCE-LOCATOR.md)). Pointer тому має бути первинним, а line/col — додатковим.
- ⚠️ **Вбудоване придушення** (`x-<tool>-ignore: [SG012]`, як у vacuum і Zally) варто підтримати, але як вторинний механізм: специфікацією володіє бекенд, тож основне місце для придушень — конфіг клієнта.
- ❌ **Не робити регулярний вираз по тексту повідомлення ключем придушення** (`match` у Speakeasy, `message` у PHPStan). Такий ключ ламається від переформулювання. Ключ — це код плюс pointer або fingerprint.

---

## R3. Override-и та overlays

### Як це роблять інші

**OpenAPI Overlay — стандарт** ([поточна версія](https://spec.openapis.org/overlay/latest.html), [усі версії](https://spec.openapis.org/overlay/)).
- Версії: 1.0.0 (схема 2024-10), 1.1.0 (додано `copy`), 1.2.0 (вересень 2026).
- `Action` має поля `target` (RFC 9535 JSONPath), `description`, `update`, `remove` і `copy`.
- Правила злиття для `update`: об'єкти зливаються рекурсивно, **масиви конкатенуються**, примітиви замінюються, інші комбінації — помилка.
- За специфікацією target, що не вибрав жодного вузла, — **не помилка**: «the action succeeds without changing the target document».

**Speakeasy: бібліотека overlay** ([apply.go](https://github.com/speakeasy-api/openapi/blob/main/overlay/apply.go), [CLI](https://www.speakeasy.com/docs/speakeasy-reference/cli/overlay)).
- `ApplyToStrict` повертає помилку `selector "…" did not match any targets`. Це «override на неіснуючий елемент».
- На кожну дію збираються попередження. `update`, який нічого не змінив, дає warning **«does nothing»** (`didMakeChange == false`). Це рівно сценарій R3.2: override збігся з уже виправленою специфікацією.
- `speakeasy overlay compare` будує overlay з двох версій специфікації (до і після). Зручний сценарій: відредагувати копію специфікації і отримати overlay автоматично.

**oapi-codegen** ([README, розділ Overlay](https://github.com/oapi-codegen/oapi-codegen#modifying-the-input-openapi-specification-with-openapi-overlay), [configuration-schema.json](https://github.com/oapi-codegen/oapi-codegen/blob/main/configuration-schema.json)).
- Overlay задається через `output-options.overlay: {path, strict}`. `strict` за замовчуванням `true` і «highlighting any actions that will not take any effect».
- Overlay рекомендують саме тоді, коли специфікацією володіє інша команда.
- Водночас документація попереджає: JSONPath складно писати і підтримувати.

**Fern: overrides.yml** ([overrides](https://buildwithfern.com/learn/api-definitions/openapi/overrides)).
- Файл повторює структуру специфікації і глибоко зливається з нею.
- Можна вказати кілька файлів; вони застосовуються по черзі, пізніші перемагають.
- Overrides застосовуються **перед** overlays.
- Є команда-заготовка `fern write-overrides`. Сам Fern тепер рекомендує overlays як більш стандартний варіант.

**Stainless: transforms** ([config: OpenAPIConfig](https://www.stainless.com/docs/reference/config/), [transforms](https://www.stainless.com/docs/openapi/transforms/)).
- Команди: `update`, `append`, `merge`, `remove`, `copy`, `move`. Кожна має **обов'язковий `reason`**. Ціль задається через JSONPath Plus.
- `update` «fails if path doesn't exist», `append` падає, якщо властивість уже існує.
- `matches_schema` знаходить усі схеми, глибоко рівні шаблону, і замінює їх на `$ref`. Це дедуплікація однакових inline-схем.
- `{{value}}` дає шаблонізацію рядків.
- Діагностики: `Transform/Failed` і **`Transform/Useless`**: «Transformation {command} had no effect… and can safely be removed».

**Функціональні патчі.**
- hey-api: `parser.patch.schemas.Foo = (schema) => {…}` до парсингу ([parser](https://heyapi.dev/openapi-ts/configuration/parser)).
- orval: `input.override.transformer` — функція над усім документом, що виконується **до** валідації, тож нею можна лагодити й невалідні специфікації ([input.mdx](https://github.com/orval-labs/orval/blob/master/docs/content/docs/reference/configuration/input.mdx)).
- openapi-python-client: `class_overrides` (`class_name` + `module_name`) і `content_type_overrides` ([README](https://github.com/openapi-generators/openapi-python-client)).
- Redocly: decorators `filter-in`, `filter-out`, `remove-x-internal`, `remove-unused-components`, `*-override` під час bundle ([decorators](https://redocly.com/docs/cli/decorators)).

**progenitor / typify (Rust)** ([lib.rs](https://github.com/oxidecomputer/progenitor/blob/main/progenitor-impl/src/lib.rs)). Override-и на рівні типів: `with_patch(type_name, TypePatch)` (перейменування, derive), `with_replacement(schema_type, rust_type, impls)` і `with_conversion(schema, type, impls)`.

### Що взяти для Dart

- ✅ **Три шари з фіксованим порядком** (як у Fern):
  1. нормалізатор;
  2. сирі патчі специфікації: Overlay 1.0/1.1 і JSON Patch (R3.3);
  3. **семантичний файл override-ів** (R3.1).

  Діагностики всіх шарів вказують на **оригінальні** місця в специфікації.
- ✅ **Семантичні селектори замість JSONPath** у файлі override-ів: `operation: getUser` або `GET /users/{id}`, `schema: Pet`, `property: Pet.tags`, `parameter: getUser.query.limit`. JSONPath складний (визнає навіть oapi-codegen), а для згенерованих специфікацій він ще й крихкий. JSONPath лишається тільки в шарі Overlay.
- ✅ **Кожен запис override має `reason`.** Без нього — warning, як у Stainless.
- ✅ **Виявлення застарілих override-ів (R3.2)** — як у Speakeasy і Stainless:
  - target не знайдено → warning `override-target-missing` («did not match any targets»);
  - застосування нічого не змінило (вузол до == вузол після) → info `override-redundant` («can safely be removed»). Перевіряється тим, що override застосовується до нормалізованої специфікації і результат порівнюється до і після.

  Режим `strict` за замовчуванням увімкнено в CI (як `strict: true` в oapi-codegen): тоді warning-и стають помилками.
- ✅ **Команда `overrides diff spec.orig.yaml spec.fixed.yaml`**, яка видає готовий файл override-ів або overlay (як `speakeasy overlay compare`). Це найшвидший шлях для команд із NestJS чи FastAPI: виправити копію руками і отримати override.
- ✅ **Операція дедуплікації `dedupe: {matches_schema: …}`.** Вона замінює глибоко рівні inline-схеми на `$ref` і закриває типові дублікати DTO з NestJS.
- ⚠️ **Overlay вимагає RFC 9535 JSONPath у Dart.** Треба перевірити відповідність пакета на pub.dev; на момент дослідження це не перевірено.
- ⚠️ **Функціональні хуки** (як hey-api `patch` чи orval `transformer`) давати лише в програмному API (R15.1), не як основний механізм. Вони недекларативні, їх не можна діагностувати і показати в звіті.

---

## R4. Фільтрація і tree-shaking

### Як це роблять інші

- **Kiota** ([using](https://learn.microsoft.com/en-us/openapi/kiota/using)).
  - `--include-path` і `--exclude-path` приймають glob-и, наприклад `**/users/**`. Суфікс `#METHOD` фільтрує за методом: `**/users/**#GET`.
  - Семантика: елемент включається, якщо «(немає include АБО збігся з include) І (немає exclude АБО не збігся з exclude)».
  - Параметри зберігаються в `kiota-lock.json`.
- **hey-api** ([parser.filters](https://heyapi.dev/openapi-ts/configuration/parser)).
  - Фільтруються `operations` (точні ключі `'GET /api/v1/foo'` або регулярні вирази `'/^[A-Z]+ /api/v1//'`), `tags`, `deprecated: false`, а також `schemas`, `parameters`, `requestBodies` і `responses`.
  - `exclude` має пріоритет над `include`.
  - `orphans: false` (прибрати схеми-сироти) вмикається за замовчуванням, щойно задано будь-який інший фільтр. Це і є tree-shaking.
  - `preserveOrder: true` зберігає порядок.
- **orval** ([input.mdx](https://github.com/orval-labs/orval/blob/master/docs/content/docs/reference/configuration/input.mdx)).
  - `filters: {mode: include|exclude, tags: [string|RegExp], schemas: […]}`.
  - Якщо задано `tags`, вихід автоматично обмежується схемами, на які **транзитивно** посилаються вибрані операції. `includeUnreferencedSchemas: true` вимикає це обмеження.
  - Схеми, досяжні лише через прив'язки `$dynamicAnchor`, теж знаходяться автоматично.
- **oapi-codegen**: `include-tags`, `exclude-tags`, `include-operation-ids`, `exclude-operation-ids`, `exclude-schemas`. Невикористані компоненти прибираються за замовчуванням, `skip-prune` це вимикає ([схема конфігу](https://github.com/oapi-codegen/oapi-codegen/blob/main/configuration-schema.json)).
- **OpenAPI Generator**: нормалізатор `FILTER="operationId:addPet|getPetById ; tag:store"` (також `method:` і `path:`) позначає невідповідні операції як `x-internal: true` ([customization.md](https://github.com/OpenAPITools/openapi-generator/blob/master/docs/customization.md)).
- **Stainless — модель opt-in** ([diagnostics](https://www.stainless.com/docs/reference/diagnostics/)).
  - Генеруються лише ендпоінти, перелічені в `resources`.
  - Ендпоінт зі специфікації, якого немає в конфігу, дає note `Endpoint/NotConfigured`.
  - Явне виключення задається через `unspecified_endpoints: ["post /internal"]`.
  - Ендпоінт у конфігу, якого вже немає в специфікації, дає error `Endpoint/NotFound`.
  - Конфлікт між двома списками дає `Endpoint/BothSpecifiedAndUnspecified`.
- **Маркери в специфікації**: `x-speakeasy-ignore: true` (на операції або параметрі) ([methods](https://www.speakeasy.com/docs/customize/methods)), `x-fern-ignore`, `x-internal` (Redocly `remove-x-internal`, OpenAPI Generator `REMOVE_X_INTERNAL`).

### Що взяти для Dart

- ✅ **Єдина граматика селекторів** для фільтрів і override-ів: `GET /users/**`, `* /admin/**`, `tag:Admin`, `op:getUser`, `/regex/`. Семантика Kiota, `exclude` перемагає.
- ✅ **Tree-shaking за замовчуванням**, щойно задано фільтр (як hey-api і orval). Досяжність рахується через:
  - `$ref`;
  - цілі `discriminator.mapping`;
  - батьківські схеми в `allOf`;
  - схеми помилок і SSE-подій;
  - `$dynamicRef`.

  Звіт: info «відфільтровано N операцій, прибрано M схем». Опційно — команда `explain Schema`, яка показує, через що схема досяжна.
- ✅ **Застарілі фільтри.** Селектор, що не збігся з жодною операцією, дає warning, як `Endpoint/NotFound` у Stainless. Це те саме правило, що й для застарілих override-ів у R3.2.
- ⚠️ **Модель opt-in Stainless** («генерувати лише перелічене») — корисний окремий режим для великих специфікацій, а не режим за замовчуванням. Note `operation-not-selected` дає видимість того, що не згенеровано.

---

## R5. Іменування

### Як це роблять інші

- **Speakeasy**
  - `x-speakeasy-name-override` у корені документа — список правил «регулярний вираз по `operationId` → `methodNameOverride`», наприклад `^get.*` → `get`. Те саме розширення на рівні операції має пріоритет ([methods](https://www.speakeasy.com/docs/customize/methods)).
  - Значення enum санітизуються ([enums](https://www.speakeasy.com/docs/customize/data-model/enums)):
    - спецсимволи замінюються словами: `+` → Plus, `-` → Minus, `.` → Dot;
    - колізії розв'язуються сталою стратегією: `foo/Foo/FOO` → `FOO_LOWER/FOO_MIXED/FOO_UPPER`;
    - якщо колізію не вдалося розв'язати, валідація падає і просить задати `x-speakeasy-enums`.
  - Для `x-speakeasy-enums` **рекомендують форму map**, бо масив ламається, коли його довжина не збігається з `enum`.
- **Stainless**
  - Іменування явне: `resources.accounts.methods.retrieve: get /accounts/{account_id}` ([config](https://www.stainless.com/docs/reference/config/)).
  - Діагностика **`Name/Collision`** перелічує бажані імена в порядку спроб, причину відмови для кожного (з місцем конфлікту) і запасне ім'я, яке зрештою використано. Наприкінці підказка: «якщо `{fallback_name}` прийнятне — ігноруйте, інакше `x-stainless-naming` або transform».
  - Інші коди: `Schema/CannotInferName`, `Model/GeneratedNameClash`, `Java/NameIsReserved`, `Python/NameNotAllowed`, `Schema/CannotInferEnumMemberName` ([diagnostics](https://www.stainless.com/docs/reference/diagnostics/)). Для ініціалізмів є `custom_casings`.
- **oapi-codegen** ([схема конфігу](https://github.com/oapi-codegen/oapi-codegen/blob/main/configuration-schema.json))
  - `name-normalizer`: `ToCamelCase | ToCamelCaseWithDigits | ToCamelCaseWithInitialisms`, разом із `additional-initialisms`.
  - `resolve-type-name-collisions: true` додає суфікс за секцією компонентів (schemas, parameters, requestBodies…). Без цього колізія — **помилка**, і її треба розв'язати вручну через `x-go-name`.
  - `generate-types-for-anonymous-schemas` дає inline-схемам імена зі шляху (`GetRolesIdResponseBody_Data`).
- **orval** ([output.mdx](https://github.com/orval-labs/orval/blob/master/docs/content/docs/reference/configuration/output.mdx))
  - `override.operationName(operation, route, verb)` повертає рядок **або кортеж `[methodName, typeNameBase]`**. Ім'я методу і база імен типів (`*Params`, `*Body`, `*Error`) тоді задаються незалежно. Корисно, коли однакові методи з різних сервісів мають отримати різні імена типів.
  - `override.components.schemas: {prefix, suffix, itemPrefix}`; префікс застосовується і до `$ref`.
- **hey-api** ([parser](https://heyapi.dev/openapi-ts/configuration/parser))
  - `transforms.schemaName` — функція або шаблон `'Api{{name}}'`.
  - Якщо перейменування дає колізію, **воно пропускається**. Тихий відкат — це протилежність R2.5.
  - `hooks.symbols.getName`.
- **Kiota** ([models](https://learn.microsoft.com/en-us/openapi/kiota/models))
  - Імена inline-схем: `<останній сегмент шляху><операція>RequestBody|Response` або `<Батьківський тип><член><порядковий номер>`.
  - Імена членів enum беруться з `x-ms-enum`.
- **openapi-python-client**: `class_overrides` і `use_path_prefixes_for_title_model_names` (довгі, але унікальні імена з повного шляху або `title`) ([README](https://github.com/openapi-generators/openapi-python-client)).
- **Fern і ogen**: `x-fern-sdk-method-name`, `x-fern-sdk-group-name`, `x-fern-type-name`, `x-fern-parameter-name`, `x-fern-property-name` ([extensions](https://buildwithfern.com/learn/api-definitions/openapi/extensions/overview)); `x-ogen-name`, `x-ogen-properties`, `x-ogen-operation-group` ([ogen extensions](https://github.com/ogen-go/web/blob/main/docs/spec/extensions.md)).

### Що взяти для Dart

- ✅ **Конвеєр імені — чиста детермінована функція:**
  1. **список кандидатів у порядку пріоритету**: override → `x-…-name` → `operationId`/ключ схеми → `title` → шлях;
  2. санітизація (спецсимволи стають словами, як у Speakeasy);
  3. регістр;
  4. перевірка зарезервованих слів (ключові слова Dart і імена з `dart:core`: `List`, `Map`, `Type`, `Object`, `Function`, `Error`, `Iterable`…);
  5. розв'язання колізій зі сталим тай-брейком: сортування за JSON pointer, а не за порядком обходу;
  6. **діагностика, як `Name/Collision` у Stainless**: які імена пробувались, чому кожне відкинуто, де конфлікт, яке ім'я вибрано і який override поставити (R5.2 + R2.5).
- ✅ **Політика колізій**: суфікс за секцією компонентів (як `resolve-type-name-collisions`: `UserParam` / `UserBody`) **з warning**. Режим `strict` робить це помилкою. Ніколи не відкатуватися мовчки, як hey-api.
- ✅ **Окремо ім'я методу і база імен типів** (кортеж як в orval). Це закриває R5.1 і R5.3 при групуванні за тегами.
- ✅ **Inline-схеми** за замовчуванням іменуються `<Parent><Property>`; якщо цього не вистачає — ім'ям зі шляху. **Дедуплікація inline-enum за структурним хешем** множини значень (R5.4); це той самий механізм, що `matches_schema` в R3.
- ✅ **Перевизначення імен членів enum** приймати у формі map (`value → name`), а не масиву (досвід Speakeasy). Масив `x-enum-varnames` теж читати, але перевіряти довжину (діагностика).

---

## R6.2 / R6.4. Відповідність типів, довільний JSON, конверти і дженерики

### Як це роблять інші

**Довільний JSON як окремий тип, а не `dynamic`**
- **Kiota**: ієрархія `UntypedNode` з класами `UntypedObject`, `UntypedArray`, `UntypedString`, `UntypedBoolean`, `UntypedInteger`, `UntypedLong`, `UntypedFloat`, `UntypedDouble`, `UntypedDecimal`, `UntypedNull` ([kiota-dotnet, serialization](https://github.com/microsoft/kiota-dotnet/tree/main/src/abstractions/serialization)). Невідомі властивості потрапляють в `AdditionalData` ([models](https://learn.microsoft.com/en-us/openapi/kiota/models)).
- **Stainless Java** ([openai-java README, Undocumented API functionality](https://github.com/openai/openai-java#undocumented-api-functionality)): `JsonValue` з фабрикою `from(...)` і `Visitor` (`visitNull`, `visitBoolean`, `visitNumber`, `visitString`, `visitArray`, `visitObject`, **`visitMissing`**). Невідомі поля доступні через `_additionalProperties()`.
- **ogen**: `jx.Raw` — сирі байти з методом `.Type()` ([any.md](https://github.com/ogen-go/web/blob/main/docs/types/any.md)).
- **progenitor**: `serde_json::Value`.
- **openapi-typescript**: `unknown`; прапорець `--empty-objects-unknown` ([CLI](https://openapi-ts.dev/cli)).
- **Speakeasy**: `x-speakeasy-type-override: any` ([extensions](https://www.speakeasy.com/docs/speakeasy-reference/extensions)).
- **Stainless `Schema/IsAmbiguous`**: схема без `type` трактується як unknown з note; намір підтверджується через `x-stainless-any: true`.

**Налаштовувана відповідність типів**
- **oapi-codegen `type-mapping`** зливається поверх значень за замовчуванням:
  ```yaml
  output-options:
    type-mapping:
      string:
        formats:
          date-time: {type: time.Time, import: time}
          decimal:   {type: decimal.Decimal, import: github.com/shopspring/decimal}
  ```
  Для окремої схеми є `x-go-type` / `x-go-type-import`.
- **progenitor**: `with_replacement` і `with_conversion`.
- **Kiota**: правило `KnownAndNotSupportedFormats` попереджає, якщо формат відомий, але не підтримується.

**Конверти і дженерики**
- **Stainless**
  - `settings.unwrap_response_fields: [data]` — глобальний конверт; на рівні методу `unwrap_response: <поле> | false` ([config](https://www.stainless.com/docs/reference/config/)).
  - Діагностики: `Method/MissingEnvelopeUnwrap` (з переліком полів, які знайдено, і підказкою `unwrap_field: false`), `Method/AmbiguousEnvelopeUnwrap`, `Response/TypeNotObjectForEnvelope`.
  - Пагінація описується схемами з `type: cursor | cursor_id | cursor_url | offset | page_number | fake_page`. Поля позначаються `x-stainless-pagination-property.purpose`: `items`, `next_cursor_field`, `has_next_page`, `offset_total_count_field`… На виході — дженерик-класи сторінок і автоітератор.
- **Speakeasy** `x-speakeasy-pagination`: `inputs` і `outputs` через JSONPath. **Fern** `x-fern-pagination`. **AutoRest** `x-ms-pageable: {itemName, nextLinkName, operationName}` ([autorest extensions](https://github.com/Azure/autorest/blob/main/docs/extensions/readme.md)).
- **orval + `$dynamicRef`/`$dynamicAnchor`** (OAS 3.1, [output.mdx](https://github.com/orval-labs/orval/blob/master/docs/content/docs/reference/configuration/output.mdx)): шаблон стає `interface PaginatedResponse<itemType>`, а прив'язки — аліасами `type UserListResponse = PaginatedResponse<User>`.
  ```yaml
  PaginatedResponse:
    $defs: {itemType: {$dynamicAnchor: itemType, not: {}}}
    properties: {items: {type: array, items: {$dynamicRef: '#itemType'}}}
  UserListResponse:
    $defs: {itemType: {$dynamicAnchor: itemType, $ref: '#/components/schemas/User'}}
    $ref: '#/components/schemas/PaginatedResponse'
  ```
  **OAS 3.2 §4.24.6.2 прямо рекомендує** (SHOULD) підтримувати дженерики через `$dynamicRef` ([OAS 3.2](https://spec.openapis.org/oas/v3.2.0.html)).

### Що взяти для Dart

- ✅ **`JsonValue` — sealed-ієрархія в runtime-пакеті**: `JsonNull`, `JsonBool`, `JsonNumber`, `JsonString`, `JsonArray`, `JsonObject`. Має `fromJson(Object?)`, `toJson()` і зручні `asString()` / `asMap()`. Pattern matching замінює Visitor зі Stainless. Схема без `type` дає info `untyped-schema` і тип `JsonValue`; підтвердити намір можна через `x-<tool>-any: true` або override.
- ✅ **`type_mapping`, як в oapi-codegen, але з конвертером.** json_serializable потребує `JsonConverter`, тож запис мапінгу містить і тип, і конвертер:
  ```yaml
  type_mapping:
    string:
      formats:
        date: {type: Date, import: "package:my_app/date.dart", converter: DateConverter}
        decimal: {type: Decimal, import: "package:decimal/decimal.dart", converter: DecimalConverter}
  ```
  Невідомий формат дає діагностику, як `KnownAndNotSupportedFormats` у Kiota.
- ✅ **Конверти — три розпізнавачі в порядку пріоритету:**
  1. override або конфіг: `envelope: {field: data, siblings: [meta]}`, як `unwrap_response_fields` у Stainless;
  2. **`$dynamicRef`/`$dynamicAnchor`** (стандарт, перевірений в orval);
  3. структурна евристика: схеми з однаковими «сусідніми» полями, що відрізняються лише типом `data`. Вона лише **пропонує** дженерик через діагностику і готовий override, але нічого не вмикає мовчки (R2.5).

  Неоднозначність дає діагностику на кшталт `AmbiguousEnvelopeUnwrap`. Для серіалізації — `genericArgumentFactories` у json_serializable.
- ⚠️ **Пагінацію як окрему фічу** проєктувати вже зараз на словнику purpose зі Stainless (`items`, `next_cursor_field`…), щоб пізніше не ламати формат конфігу.

---

## R7. Три стани поля в PATCH

### Як це роблять інші

- **ogen** ([optional.md](https://github.com/ogen-go/web/blob/main/docs/types/optional.md)). `OptNilString { Value string; Set bool; Null bool }` з методами `IsSet()`, `IsNull()`, `Get()`, `Or()`, `SetTo()`, `Reset()`. Головне — **явна матриця поведінки декодера**, рівно те, що вимагає R6.1:

  | Схема | немає значення | `null` | значення |
  |---|---|---|---|
  | required | Error | Error | OK |
  | optional | `Set=false` | Error | `Set=true` |
  | nullable, required | Error | `Null=true` | OK |
  | optional & nullable | `Set=false` | `Set=true, Null=true` | `Set=true, Null=false` |

  Для масивів є окрема матриця, де `nil` і `[]` розрізняються.
- **oapi-codegen** ([README, Nullable types](https://github.com/oapi-codegen/oapi-codegen#generating-nullable-types)). `output-options.nullable-type: true` генерує `nullable.Nullable[T]` з тегом `omitempty`. Без цієї опції `*string` не розрізняє «не надіслано» і `null`, і README прямо це визнає.
- **openapi-python-client** ([types.py у golden record](https://github.com/openapi-generators/openapi-python-client/tree/main/end_to_end_tests/golden-records)). Сентинел `class Unset: __bool__ → False; UNSET = Unset()`. Поля мають тип `T | None | Unset = UNSET`, а `to_dict` пропускає `UNSET`.
- **Stainless Python** ([`_types.py`](https://github.com/openai/openai-python/blob/main/src/openai/_types.py)). Параметри мають вигляд `temperature: Optional[float] | Omit = omit`. `NotGiven` використовують там, де `None` має власне значення («без таймауту»). На боці відповіді `model_fields_set` відрізняє відсутнє поле від `null` ([README](https://github.com/openai/openai-python#how-to-tell-whether-none-means-null-or-missing)).
- **Stainless Java** `JsonField<T>`: `isMissing()`, `isNull()`, значення або `asUnknown()`. `JsonMissing.of()` примусово прибирає навіть обов'язкове поле. FAQ пояснює вибір: «Representing absent vs explicitly null values» ([openai-java FAQ](https://github.com/openai/openai-java#why-do-you-represent-fields-using-jsonfieldt-instead-of-just-plain-t)).
- **Kiota BackingStore** (`--backing-store`) ([abstractions](https://learn.microsoft.com/en-us/openapi/kiota/abstractions), [models](https://learn.microsoft.com/en-us/openapi/kiota/models)). Значення живуть у сховищі з **відстеженням змін**: `InitializationCompleted`, `ReturnOnlyChangedValues`, `EnumerateKeysForValuesChangedToNull()`. Сценарій: отримати об'єкт через GET, змінити одне поле і відправити PATCH лише з ним.

### Що взяти для Dart

- ✅ **Sealed-тип у runtime-пакеті** (наприклад, `Patch<T>` / `Optional<T>`) з трьома станами: `Absent`, `Null`, `Value(T)`. Це прямий відповідник `OptNil` / `JsonField` з exhaustive pattern matching у Dart 3. Генерується лише для полів, які проходять правило з R7.2 (за замовчуванням optional + nullable у тілі PATCH).
- ✅ **Матрицю ogen задокументувати як контракт.** Окрема таблиця для запиту, відповіді і PATCH (R6.1) з колонками «немає / null / значення» і описом, що робить декодер і що робить енкодер.
- ⚠️ **json_serializable не вміє «пропустити ключ» з конвертера.** `includeIfNull` не відрізняє Absent від Null. Тому для моделей із tri-state полями генератор має видати свій `toJson`: або обгортку над `_$XToJson`, яка прибирає ключі зі значенням-сентинелом (як `UNSET` у Python), або повністю власний. Це треба вирішити в архітектурі серіалізації.
- ✅ **R7.3** (поле з одним станом ніколи не шле null, якщо його не задано): за замовчуванням `includeIfNull: false` для optional полів запиту. Це поведінка `omit` у Stainless.
- ⚠️ **BackingStore з Kiota** (відстеження змін) — цікава альтернатива для «PATCH з отриманого об'єкта», але складна, і моделі перестають бути простими. Не робити за замовчуванням; можливо, пізніше як режим.
- ⚠️ **На боці відповіді tri-state за замовчуванням не показувати.** Достатньо опційного `fieldsSet` у стилі `model_fields_set` для тих, кому це потрібно.

---

## R8. Відкриті enum із сирим значенням

### Як це роблять інші

- **Speakeasy** ([enums](https://www.speakeasy.com/docs/customize/data-model/enums), [forward compatibility](https://www.speakeasy.com/docs/sdks/manage/forward-compatibility)).
  - Схема відкривається або закривається через `x-speakeasy-unknown-values: allow | disallow`.
  - Прапорець у `gen.yaml` `forwardCompatibleEnumsByDefault` з'явився в [v1.661.0](https://www.speakeasy.com/changelog/release/v1.661.0) і **увімкнений за замовчуванням** (крім Terraform). **Enum з одним значенням автоматично не відкриваються.**
  - Представлення: TS — `"red" | "green" | Unrecognized<string>`; Python — `Union[Literal[...], UnrecognizedStr]`; Java — `BackgroundColor.of("purple")` з `isKnown()`.
  - Закриті enum залишають свідомо: вони «допомагають помітити дрейф API в тестах».
- **Stainless Java/Kotlin** ([FinishReason.kt у openai-java](https://github.com/openai/openai-java/blob/main/openai-java-core/src/main/kotlin/com/openai/models/chat/completions/ChatCompletion.kt)). Згенерований клас містить:
  - приватний конструктор над `JsonField<String>` і константи `STOP = of("stop")`;
  - `enum Known { STOP, … }` і `enum Value { STOP, …, _UNKNOWN }`;
  - `value()`, що повертає `_UNKNOWN`; `known()`, що кидає `InvalidDataException`; `asString()`, `validate()`, `isValid()`.

  FAQ пояснює: «Java `enum` classes are not trivially forwards compatible».
- **OpenAPI Generator** (dart-dio, swift, kotlin): `enumUnknownDefaultCase=true` додає `unknown_default_open_api` ([dart-dio](https://openapi-generator.tech/docs/generators/dart-dio)). Сире значення **губиться**, це антипатерн для R8.1.
- **AutoRest** `x-ms-enum: {name, modelAsString, values: [{value, name, description}]}`. **`modelAsString: true` — значення за замовчуванням**, і такий enum вважається розширюваним (extensible) ([autorest extensions](https://github.com/Azure/autorest/blob/main/docs/extensions/readme.md)).
- **Zalando `x-extensible-enum`**: oasdiff окремо знає, що додавання значення до такого enum у відповіді не ламає сумісність ([BREAKING-CHANGES.md](https://github.com/oasdiff/oasdiff/blob/main/docs/BREAKING-CHANGES.md#breaking-changes-to-enum-values)).
- **Kiota — свідомо протилежне**: невідоме значення enum кидає виняток, щоб «fail as early as possible» ([models](https://learn.microsoft.com/en-us/openapi/kiota/models)). Це антиприклад для R8.1.
- **oapi-codegen**: enum — це типізовані рядкові константи (відкриті за природою) з методом `Valid()`.

### Що взяти для Dart

- ✅ **Відкриті enum у відповідях за замовчуванням, закриті в запитах** (R8.1 + R8.2):
  - request-тип — звичайний Dart `enum Status` (закритий, невідоме значення не надіслати);
  - response-поле — `OpenEnum<Status>` = sealed `Known(Status)` | `Unknown(Object raw)`. Це прямий відповідник `Known`/`Value._UNKNOWN` зі Stainless.

  Якщо схема спільна для обох напрямів, генеруються два види. Конструктор `Unknown` у request-API недоступний.
- ✅ **Правила Speakeasy**:
  - enum з одним значенням лишається закритим (це константа);
  - override на рівні схеми: `x-<tool>-unknown-values: allow | disallow`;
  - для сумісності також читати `x-extensible-enum`, `x-ms-enum.modelAsString` і `x-speakeasy-unknown-values`.
- ⚠️ **Конфлікт R8 з R14.2 через exhaustiveness у Dart.** Додавання значення в Dart `enum` чи підкласу в `sealed`-ієрархію **ламає компіляцію** `switch` у споживача, якщо там немає `_`/`default` ([exhaustiveness](https://dart.dev/language/branches#exhaustiveness-checking)). `Unknown` проблему не вирішує, бо новий *відомий* член теж додає case. Варіанти:
  - (а) `enum_style: dart_enum`: зручно, але кожне нове значення — breaking зміна Dart API, і R14 має це показувати;
  - (б) `enum_style: open_class`: клас із `static const`-екземплярами (або `extension type` над `String`); `switch` за константами не перевіряється на повноту, тож нове значення нічого не ламає.

  Рекомендація: (б) для response-enum за замовчуванням, (а) як опція. Це висновок із мовної семантики Dart і досвіду Stainless (FAQ про `enum`); на генераторах перевірено не було.

---

## R9. Поліморфізм: варіант для невідомого типу

### Як це роблять інші

- **Speakeasy** ([forward compatibility](https://www.speakeasy.com/docs/sdks/manage/forward-compatibility)).
  - `forwardCompatibleUnionsByDefault: tagged-only | false | true` з'явився в [v1.663.0](https://www.speakeasy.com/changelog/release/v1.663.0). Невідомий дискримінатор дає `{ type: "UNKNOWN"; raw: unknown }`.
  - Для об'єднань без дискримінатора — `unionStrategy: populated-fields`: спробувати всі варіанти, взяти той, у якому заповнено найбільше полів, при рівності — той, де найменше приведень типів.
- **OAS 3.2 `discriminator.defaultMapping`** ([OAS 3.2 §4.25](https://spec.openapis.org/oas/v3.2.0.html)). Обов'язковий, якщо властивість-дискримінатор optional. Застосовується, коли властивості **немає або для її значення немає мапінгу**. Це **стандартне** місце для варіанта «невідомий».
- **ogen** ([sumtype.md](https://github.com/ogen-go/web/blob/main/docs/types/sumtype.md), [features](https://github.com/ogen-go/web/blob/main/docs/02-features.mdx)). `oneOf` стає struct з полем `Type` (enum) і полями варіантів. Дискримінатор виводиться **під час генерації** по драбині:
  1. явний `discriminator`;
  2. JSON-тип (для примітивів);
  3. **унікальні поля**;
  4. однакове поле з різними JSON-типами;
  5. однакове поле з непересічними значеннями enum.
- **Kiota** ([models](https://learn.microsoft.com/en-us/openapi/kiota/models)). `oneOf` — обгортка з окремою властивістю на кожен варіант. Якщо серед варіантів є object, дискримінатор «MUST»; правило `MissingDiscriminator` дає warning. Примітиви пробуються по черзі.
- **Stainless**
  - Діагностики ([diagnostics](https://www.stainless.com/docs/reference/diagnostics/)): `Java/SchemaUnionDiscriminatorMissing` («доведеться пробувати кожен варіант по черзі — неефективно або неоднозначно, якщо два варіанти мають однакові required»), `Go/DuplicateVariantDeserializationConditions`, `Schema/DiscriminatedUnionVariantMissingProperty`.
  - Java-union має `_json()` (сирий JSON) і `Visitor` з методом `unknown(json: JsonValue?)`, який за замовчуванням кидає виняток ([ChatCompletionMessageParam.kt](https://github.com/openai/openai-java/blob/main/openai-java-core/src/main/kotlin/com/openai/models/chat/completions/ChatCompletionMessageParam.kt)).
- **Fern** `x-fern-discriminator-context: data | protocol` розрізняє дискримінатор усередині JSON і дискримінатор у рамці протоколу, як `event:` в SSE ([discriminator-context](https://buildwithfern.com/learn/api-definitions/openapi/extensions/discriminator-context)).

### Що взяти для Dart

- ✅ **Sealed-ієрархія з варіантом `XUnknown(String? discriminatorValue, Map<String, Object?> raw)`** (R9.1). Також враховувати `defaultMapping` з OAS 3.2: якщо він заданий, запасним варіантом стає вказана схема, а не `Unknown`.
- ✅ **`oneOf` без дискримінатора (R9.2)**: діагностика з налаштовуваною поведінкою `union_strategy: error | structural | raw` на рівні схеми.
  - `structural` — драбина ogen, обчислена **під час генерації**: тип → унікальні required-поля → тип поля → непересічні const/enum.
  - Якщо умови варіантів перетинаються, діагностика як `DuplicateVariantDeserializationConditions` пропонує override дискримінатора.
  - Runtime-евристику `populated-fields` зі Speakeasy давати лише як явну опцію.
- ✅ **Змішані примітиви (R9.3)** — обгортка `StringOrInt` з розрізненням за JSON-типом (type discriminator в ogen).
- ⚠️ **Дискримінатор протоколу і дискримінатор у даних** (Fern) обов'язково врахувати для SSE в R12.
- ⚠️ **Нагадування з R8 щодо exhaustiveness**: додати варіант у sealed — breaking для `switch` споживача. Варіант `Unknown` цього не рятує.

---

## R10.5 / R10.8. Метадані запиту і security як метадані

### Як це роблять інші

- **progenitor** ([progenitor_client.rs](https://github.com/oxidecomputer/progenitor/blob/main/progenitor-client/src/progenitor_client.rs)): `OperationInfo { operation_id: &'static str }` передається в `ClientHooks::pre(&mut request, &info)` і `post`.
- **openapi-fetch**: middleware `onRequest({ request, schemaPath, params, id, options })`. `schemaPath` — шаблон шляху на кшталт `/projects/{project_id}`, і за ним роблять маршрутизацію логіки ([middleware-auth](https://openapi-ts.dev/openapi-fetch/middleware-auth)).
- **hey-api** ([згенерований sdk.gen.ts](https://github.com/hey-api/openapi-ts/blob/main/examples/openapi-ts-fetch/src/client/sdk.gen.ts), [auth.gen.ts](https://github.com/hey-api/openapi-ts/blob/main/examples/openapi-ts-fetch/src/client/core/auth.gen.ts)).
  - Кожен виклик передає `security: [{ scheme: 'bearer', type: 'http' }]`.
  - Клієнт викликає `auth(auth: Auth)` з `{type, scheme, in, name, key}`. Токен «attached only to requests that require auth».
  - Це рівно R10.8: security — метадані, а не код у згенерованому методі.
- **Kiota** `RequestInformation.RequestOptions: IEnumerable<IRequestOption>` — опції middleware на рівні запиту ([abstractions](https://learn.microsoft.com/en-us/openapi/kiota/abstractions)).
- **Stainless**
  - TS: `{ maxRetries, timeout, signal, headers }` на кожен виклик, плюс `.withResponse()` / `.asResponse()` ([openai-node](https://github.com/openai/openai-node)).
  - Python: `extra_headers`, `extra_query`, `extra_body`, `timeout`, `.with_raw_response`, `.with_options()` ([openai-python](https://github.com/openai/openai-python)).
  - Java: `RequestOptions.builder().responseValidation(true)`.
- **Speakeasy**: `x-speakeasy-retries` на рівні операції і `retries` як аргумент виклику ([retries](https://www.speakeasy.com/docs/customize/runtime/retries)).
- **ogen**: типізований інтерфейс `SecuritySource` ([features](https://github.com/ogen-go/web/blob/main/docs/02-features.mdx)).

### Що взяти для Dart (dio)

- ✅ **Метадані операції в `Options.extra` під одним ключем** з типізованим доступом із runtime-пакета:
  ```dart
  // runtime
  final class OperationInfo {
    final String operationId, method, pathTemplate;
    final List<String> tags;
    final List<List<SecurityRequirement>> security; // OR of AND, як в OAS
    static OperationInfo? of(RequestOptions o) => o.extra[_key] as OperationInfo?;
  }
  ```
  Структуру `security` зберегти так, як в OAS: масив альтернатив, кожна з яких — набір схем з `scopes`. hey-api цю структуру спрощує.
- ✅ **Параметри кожного виклику**: `CancelToken`, `onSendProgress`, `onReceiveProgress`, `Map<String, Object?>? extra`, `Options? options` (зливаються, а не замінюються). Згенерований код нічого не додає до клієнта (R10.1).
- ✅ **Опційний `SecurityInterceptor`** у runtime на кшталт `auth` у hey-api: `resolve(SecurityScheme scheme) → FutureOr<String?>` підставляє лише ті схеми, яких вимагає операція. Згенерований код авторизацію **не** вбудовує.

---

## R11. Типізовані помилки, Result чи винятки, незадокументований статус

### Як це роблять інші

- **Kiota: алгоритм вибору типу помилки** ([errors](https://learn.microsoft.com/en-us/openapi/kiota/errors)):
  1. точний код;
  2. діапазон `4XX` / `5XX`;
  3. `default`;
  4. базовий `ApiException` з повідомленням «The server returned an unexpected status code and no error factory is registered for this code».

  Інші деталі:
  - `ResponseStatusCode` і `ResponseHeaders` є на базовому класі;
  - **`x-ms-primary-error-message: true`** позначає поле, звідки береться текст повідомлення;
  - мапінг вважається валідним, лише якщо схема — object щонайменше з одним полем.
- **progenitor** — найчистіше розділення варіантів ([progenitor_client.rs](https://github.com/oxidecomputer/progenitor/blob/main/progenitor-client/src/progenitor_client.rs)):
  ```rust
  pub enum Error<E> {
    InvalidRequest(String), CommunicationError(reqwest::Error), InvalidUpgrade(..),
    ErrorResponse(ResponseValue<E>),            // задокументована помилка
    ResponseBodyError(reqwest::Error),
    InvalidResponsePayload(Bytes, serde_json::Error), // очікуваний код, не декодувалось
    UnexpectedResponse(reqwest::Response),      // не описано; «may represent a success or failure»
    Custom(String) }
  ```
- **swift-openapi-generator** ([SOAR-0007](https://github.com/apple/swift-openapi-generator/blob/main/Sources/swift-openapi-generator/Documentation.docc/Proposals/SOAR-0007.md)). `Output` — enum з case на кожен задокументований статус плюс **`case undocumented(statusCode: Int, UndocumentedPayload)`**. До цього є **кидальні геттери**: `try await client.getGreeting().ok.body.json` кидає помилку, якщо статус не 200 або тіло не JSON. Одна модель обслуговує обидва стилі: Result-подібний `switch` і винятки.
- **Stainless**
  - Ієрархія: `APIError` поділяється на `APIConnectionError` (з `APITimeoutError`) і `APIStatusError(status_code, response)`. Від останнього: `BadRequestError` (400), `AuthenticationError` (401), `PermissionDeniedError` (403), `NotFoundError` (404), `UnprocessableEntityError` (422), `RateLimitError` (429), `InternalServerError` (≥500) ([openai-python](https://github.com/openai/openai-python#handling-errors)).
  - Java додає `UnexpectedStatusCodeException` для інших статусів, `SseException` для помилок «після успішної початкової відповіді», `IoException` і `InvalidDataException` (лінива валідація: виняток лише при доступі до поля) ([openai-java](https://github.com/openai/openai-java#error-handling)).
- **Speakeasy** ([errors](https://www.speakeasy.com/docs/customize/responses/errors)).
  - `x-speakeasy-errors: {statusCodes: [4XX, 5XX, …], override: true}`. `default` не вважається помилкою, поки його не перелічено.
  - Типізовані помилки мають «підняті» (hoisted) властивості.
  - `SDKError` (статус, тіло як рядок, сира відповідь) — для незадокументованих статусів.
  - `SDKValidationError` з `rawValue` і `pretty()`, `HTTPClientError` — для мережевих помилок.
  - `x-speakeasy-error-message: true` задає поле з текстом повідомлення.
- **openapi-python-client**: `Response[T]` з `parsed`; прапорець `raise_on_unexpected_status` (за замовчуванням `False`) кидає `UnexpectedStatus(status_code, content)`.
- **hey-api** ([types.gen.ts](https://github.com/hey-api/openapi-ts/blob/main/examples/openapi-ts-fetch/src/client/client/types.gen.ts)): дженерик `ThrowOnError`. При `false` метод повертає `{data, error, response}` як розмічене об'єднання, при `true` — кидає виняток. Модель доставки обирається на рівні типу.
- **ogen, convenient errors** ([convenient_errors.md](https://github.com/ogen-go/web/blob/main/docs/concepts/convenient_errors.md)): якщо **кожна** операція має однакову `default`-відповідь з одним JSON, генерується один спільний тип помилки. Перемикач `convenient_errors: auto | on | off`.
- **openapi-fetch**: `onError` ловить лише помилки `fetch` (мережа, abort), а 4xx/5xx — ні. Транспорт відокремлено від HTTP.

### Що взяти для Dart

- ✅ **Sealed-ієрархія в runtime-пакеті** (R11.1, R11.3, R11.7, за зразком progenitor):
  ```
  ApiFailure<E>
   ├─ TransportFailure (DioException без response: connection, timeout, cancel)
   ├─ HttpFailure (status, headers, rawBody)
   │   ├─ DocumentedError<E>   // тіло E за мапінгом статусу
   │   └─ UndocumentedResponse // R11.3; може бути і 2xx (як у progenitor)
   └─ DecodeFailure (status, raw, schema, jsonPath)  // InvalidResponsePayload; R6.5
  ```
- ✅ **Порядок вибору типу як у Kiota**: точний код → `4XX`/`5XX` → `default` → `UndocumentedResponse`.
- ✅ **Спільна схема помилки генерується один раз** (R11.4): дедуплікація за `$ref` плюс евристика ogen для однакового `default` у всіх операціях. Поле з текстом повідомлення задається через `x-<tool>-error-message` (за аналогією з `x-ms-primary-error-message` і `x-speakeasy-error-message`).
- ✅ **Модель доставки (R11.2) у стилі swift**: метод повертає `Future<T>` і кидає `ApiFailure`; поряд — варіант (`…Result()` або extension `.result`), який повертає `Result<T, ApiFailure<E>>`. Помилки dio при цьому йдуть звичайним шляхом через `onError` інтерсептори (R10.2), а згенерований код мапить `DioException` у типізовану помилку **після** ланцюга інтерсепторів. Конфіг: `errors: throw | result | both`.
- ⚠️ **Лінива валідація** (`InvalidDataException` у Stainless Java) — цікава для сумісності вперед, але суперечить R6.5 («зрозуміла помилка декодування одразу»). Лишити суворе декодування за замовчуванням.

---

## R12. SSE: типізовані події, `itemSchema`, перепідключення

### Як це роблять інші

- **OAS 3.2** ([§4.14.4, §4.14.6.3](https://spec.openapis.org/oas/v3.2.0.html)).
  - `text/event-stream` описується через `itemSchema`.
  - Типова схема події: `{data: string (required), event: string, id: string, retry: integer ≥ 0}`.
  - JSON у `data` описується через `contentMediaType: application/json` + `contentSchema`. Типи подій — через `oneOf` по `event` з `const`.
  - Спершу потік парситься за WHATWG: коментарі й невідомі поля ігноруються, багаторядковий `data` склеюється через `\n`. Лише потім застосовується схема. `contentSchema` за замовчуванням не валідується.
- **FastAPI вже видає `itemSchema`** ([fastapi/openapi/utils.py](https://github.com/fastapi/fastapi/blob/master/fastapi/openapi/utils.py), [SSE reference](https://fastapi.tiangolo.com/reference/sse/)).
  - Для SSE-маршрутів: `text/event-stream: {itemSchema: {…, data: {type: string, contentMediaType: application/json, contentSchema: <Model>}}}`.
  - Для генераторів: `application/jsonl: {itemSchema: …}`.
  - Водночас `openapi_version` за замовчуванням — `"3.1.0"`. Отже, документ 3.1 містить ключ із 3.2. orval прямо згадує, що для «FastAPI's `itemSchema`» доводиться вимикати валідацію ([input.mdx](https://github.com/orval-labs/orval/blob/master/docs/content/docs/reference/configuration/input.mdx)).
- **Speakeasy** ([SSE](https://www.speakeasy.com/docs/customize/runtime/server-sent-events)).
  - У схемі події дозволені лише поля `id`, `event`, `data`, `retry`; будь-що інше — помилка валідації.
  - Типи подій задаються через `oneOf` + `discriminator.propertyName: event` з `const`.
  - **`x-speakeasy-sse-sentinel: '[DONE]'`** ховає сентинел і завершує ітерацію.
  - `inferSSEOverload` дає один метод з параметром `stream: true`. Окремі методи можна отримати через фрагмент URL (`/chat#streamed`).
- **Stainless** ([streaming](https://www.stainless.com/docs/sdks/configure/streaming/), [config](https://www.stainless.com/docs/reference/config/)).
  - `streaming.on_event` — **упорядкована таблиця обробників**:
    ```yaml
    on_event:
      - data_starts_with: '[DONE]'
        handle: done            # дочитати потік, ігноруючи решту
      - event_type: error
        handle: error           # з error_property
      - event_type: [ping, heartbeat]
        handle: continue
      - kind: fallthrough       # ловить усе, включно з майбутніми типами подій
        handle: yield
    ```
  - `event_type: null` ловить події без рядка `event:`.
  - `done` і `break` відрізняються: `done` дочитує з'єднання до кінця, `break` рве одразу.
  - Діагностики: `Streaming/DuplicateFallthroughEvents`, `Streaming/ConflictingEventTypeHandling`.
  - `param_discriminator` задає параметр `stream`, а `stream_event_model` — модель події.
- **Fern** ([SSE](https://buildwithfern.com/learn/api-definitions/openapi/endpoints/sse), [SSE metadata](https://buildwithfern.com/learn/sdks/deep-dives/sse-metadata)).
  - Синтаксис: `x-fern-streaming: {format: sse, terminator: "[DONE]", resumable: true, stream-condition: $request.stream, response, response-stream}`.
  - **`resumable`**: після обриву клієнт перепідключається і надсилає останній id в `Last-Event-ID`.
    - Затримка береться з `retry:`; якщо його немає — 1 с, з обмеженням 30 с.
    - **До 5 спроб поспіль; лічильник скидається з кожною отриманою подією.**
    - Потрібен `terminator`, щоб відрізнити завершений потік від обірваного.
  - `withMetadata()` дає доступ до `id`, `event` і `retry`.
- **ogen** ([README, SSE](https://github.com/ogen-go/ogen#server-sent-events)).
  - `x-ogen-sse-event-shape: data-only` (за замовчуванням схема описує лише `data`) | `full` (уся «конверт»-подія з дискримінатором по `event`) | `full-array`.
  - Подія відправляється, лише якщо є хоча б один рядок `data:`. `event` за замовчуванням — `"message"`.
  - `id` і `retry` оновлюються навіть для подій, які не відправлено.
  - Опції перепідключення: початковий Last-Event-ID, затримка, максимум спроб, розмір буфера, **максимальний розмір події** (`ErrEventTooLarge`: подія дочитується до кінця, потік не закривається).
  - Інтерфейс: `Next`, `All`, `State`, `Close`.
- **hey-api** ([serverSentEvents.gen.ts](https://github.com/hey-api/openapi-ts/blob/main/examples/openapi-ts-fetch/src/client/core/serverSentEvents.gen.ts)): опції `onSseEvent`, `onSseError`, `sseDefaultRetryDelay` (3000), `sseMaxRetryAttempts`, `sseMaxRetryDelay` (30000); експоненційний backoff і `Last-Event-ID`.
- **Нюанси Stainless**: openai-python **не повторює стрім автоматично**, бо «replaying a request could duplicate output already delivered» ([README](https://github.com/openai/openai-python#handling-errors)). openai-java має окремий `SseException` для помилок після 200.
- **swift-openapi-generator** ([Useful patterns](https://github.com/apple/swift-openapi-generator/blob/main/Sources/swift-openapi-generator/Documentation.docc/Articles/Useful-OpenAPI-patterns.md)): `asDecodedServerSentEventsWithJSONData(of:decoder:while:)`, де `while` — умова завершення, тобто сентинел.

### Що взяти для Dart

- ✅ **Парсер у runtime-пакеті строго за WHATWG.**
  - Рядки розбиваються за CR, LF і CRLF; коментарі ігноруються; `data` склеюється.
  - Подія відправляється, лише якщо є `data`. `event` за замовчуванням — `message`.
  - `id` і `retry` оновлюються навіть без відправки (як в ogen). Є ліміт розміру події.
  - На виході `SseEvent {id, event, data, retry}`.
- ✅ **Джерела схем подій за пріоритетом**:
  1. override;
  2. `itemSchema` — **у будь-якій заявленій версії OAS**: нормалізатор приймає його і в 3.0/3.1 з info-діагностикою (кейс FastAPI);
  3. сумісні `x-` (`x-<tool>-sse`, опційно читати `x-speakeasy-sse-sentinel` і `x-fern-streaming`);
  4. `schema` у режимі «data-only», як за замовчуванням в ogen.
- ✅ **Типізовані події** — sealed з варіантом `UnknownEvent(SseEvent raw)` (R12.2). Дискримінатор з рамки протоколу (`event:`) явно відділено від дискримінатора всередині `data` (`x-fern-discriminator-context`).
- ✅ **Таблиця обробників як у Stainless**: сентинел (`[DONE]`) дає `done`; подія типу error дає типізовану `SseStreamError` (окремо від HTTP-помилок, як `SseException` у Java); ping дає `skip`; fallthrough дає `yield Unknown`. Діагностики конфліктів правил — як у Stainless.
- ✅ **Перепідключення (R12.5)** — політика Fern:
  - `Last-Event-ID` і `retry:` з запасним значенням і обмеженням;
  - N спроб поспіль зі скиданням лічильника на кожній події;
  - повтор лише за наявності `terminator`.

  **За замовчуванням вимкнено для POST**: повтор може задублювати результат (аргумент openai-python). Вмикається прапорцем `resumable` на операції.
- ⚠️ **NDJSON/JSONL (R12.6)**: FastAPI вже видає `application/jsonl` з `itemSchema`. Парсер варто проєктувати так, щоб формат рамки був змінним (SSE або JSONL).

---

## R13.1. Детермінований вихід

### Як це роблять інші

- **Kiota** `kiota-lock.json`: усі параметри генерації і **хеш опису**. Якщо опис і параметри не змінились, генерація пропускається. Файл призначений для коміту ([using](https://learn.microsoft.com/en-us/openapi/kiota/using)).
- **Speakeasy** `gen.lock`: `docChecksum`, `docVersion`, `speakeasyVersion`, `generationVersion`, `configChecksum`, `releaseVersion`, версії фіч генератора і `releaseNotes` ([versioning](https://www.speakeasy.com/docs/sdks/manage/versioning)).
- **OpenAPI Generator**: опція `hideGenerationTimestamp` (за замовчуванням `false` у Java), тобто **за замовчуванням вихід не детермінований** ([java](https://openapi-generator.tech/docs/generators/java)). Це ❌-приклад.
- **openapi-typescript**: `--alphabetize`. **hey-api**: `preserveOrder`; без нього порядок не зберігається «for performance reasons».
- **oasdiff**: явне правило вибору «спільна схема звітується в першій за алфавітом властивості»: «The same comparison always reports the change at the same property».
- **Stainless editions**: `edition: "2025-10-08"` — «a versioned set of non-backwards-compatible changes» ([config](https://www.stainless.com/docs/reference/config/)). Генератор змінює вихід, а користувач переходить на нове видання явно. Це відповідь на R15.4: зміна виходу для того самого входу — breaking change. **Kiota** схожим чином має `--exclude-backward-compatible`.

### Що взяти для Dart

- ✅ **У згенерованому коді немає часу, абсолютних шляхів і версії генератора.** Версія живе лише в lock-файлі. Заголовок — стала фраза «GENERATED CODE — DO NOT EDIT».
- ✅ **`openapi_dart.lock`** містить sha256 специфікації, конфігу, override-ів і baseline, версію генератора, edition і список згенерованих файлів з хешами. На ньому будуються команда `check --up-to-date` для CI і база порівняння для R14.
- ✅ **Сталий порядок усюди**: сортування за канонічним ключем із тай-брейком за JSON pointer. Кожне правило вибору записане явно (як у oasdiff). Ніяких `HashSet` і `HashMap` у вихідних колекціях. Golden-тести запускаються двічі (і на різних ОС, з `\n`) і порівнюються побайтово.
- ✅ **`edition` у конфігу** (ідея Stainless). Нові правила виходу йдуть за новим edition, і зміна генератора не ламає користувача без його згоди.

---

## R14. Звіт про зміни між регенераціями, breaking changes Dart API

### Як це роблять інші

- **oasdiff** ([BREAKING-CHANGES.md](https://github.com/oasdiff/oasdiff/blob/main/docs/BREAKING-CHANGES.md)).
  - Команди `breaking` і `changelog`. Сотні перевірок з ID на кшталт `response-success-status-removed`, `request-property-became-nullable`, `api-security-removed`; рівні `ERR`, `WARN`, `INFO`.
  - `--fail-on ERR|WARN|INFO` задає, з якого рівня CI падає.
  - `--severity-levels file`: рядки `check-id err|warn|info|none`.
  - `--err-ignore` / `--warn-ignore`: текстові файли (можна markdown) з рядками «METHOD /path + опис».
  - Формати: `json`, `yaml`, `markdown`, `html`, `githubactions`, `junit`, `singleline`. `oasdiff schema` видає JSON Schema виводу. Є відбиток зміни і позиції в YAML-джерелі.
  - **Перевірки враховують напрям** ([NULLABILITY.md](https://github.com/oasdiff/oasdiff/blob/main/docs/NULLABILITY.md)): поле запиту стало nullable — не breaking; поле відповіді стало nullable — breaking. Усі три форми nullable (`nullable`, `type: [T, "null"]`, `oneOf` з null) вважаються еквівалентними.
  - Зміна спільної схеми звітується один раз з «also at …».
  - Окремо обробляється `x-extensible-enum`.
- **Speakeasy** ([versioning](https://www.speakeasy.com/docs/sdks/manage/versioning), [SDK changelogs](https://www.speakeasy.com/docs/sdks/manage/sdk-changelogs), [breaking changes](https://www.speakeasy.com/docs/sdks/manage/breaking-changes)).
  - Bump версії рахується з трьох незалежних джерел: фічі генератора в `gen.lock`, `info.version` або checksum специфікації, checksum конфігу. Береться максимальний.
  - Аналіз **вмісту** специфікації на breaking changes позначено як «coming soon».
  - Changelog SDK: додані, видалені і змінені методи; видалення позначені як breaking.
- **Fern** `--version AUTO` ([блог, серпень 2026](https://buildwithfern.com/post/automating-semantic-versioning-api-sdks-claude), [self-hosted](https://buildwithfern.com/learn/sdks/deep-dives/self-hosted-versioning)).
  - Порівнює **згенерований SDK** попереднього і нового релізу. Результат — major, minor, patch або no_change, плюс changelog і PR summary. CI падає на major.
  - Альтернатива — `fern ir` + `fern diff` на рівні проміжного представлення (IR).
  - Документація визнає, що інструмент спирається на «AI diff analysis», і чесно описує хибні спрацювання (вставка поля в Go struct).
  - Каже прямо: додавання значення enum «additive over HTTP but breaking in a closed-enum deserializer».
- **Stainless**: breaking change detection — платна enterprise-фіча для GitHub CI ([docs](https://www.stainless.com/docs/enterprise/breaking-change-detection/)).
- **Dart: `dart_apitool diff --old <ref> --new <ref>`** ([pub.dev](https://pub.dev/packages/dart_apitool)). Посилання бувають шляхом, `pub://name/version` або `git://…`. Є `--version-check-mode none|fully|onlyBreakingChanges`, `--report-format cli|markdown|json` і ненульовий код виходу, якщо semver порушено. Моделює публічний API пакета і порівнює дві версії.

### Що взяти для Dart

- ✅ **Два рівні звіту (R14.1).**
  1. **Зміни специфікації** на нормалізованому IR. ID перевірок у стилі oasdiff, обов'язково **з урахуванням напряму** (запит чи відповідь). Можна запускати і сам oasdiff як зовнішній крок, але власний diff на IR точніший, бо бачить override-и.
  2. **Зміни Dart API**, обчислені з «моделі поверхні» генератора: класи, конструктори (required чи optional параметри), поля і типи, члени enum, варіанти sealed. Класифікувати треба за правилами Dart, а не HTTP:
     - новий required-параметр конструктора request-моделі — breaking;
     - новий член `enum` або варіант `sealed` — breaking для exhaustive `switch` (див. R8/R9);
     - нове optional поле — не breaking.

  Як страховка в CI — `dart_apitool diff` на згенерованому пакеті.
- ✅ **Fingerprint і ignore для схвалених breaking changes** (oasdiff), `--fail-on`, `--severity-levels`. Формати markdown (для PR) і json.
- ✅ **Bump семантичної версії рахувати як Speakeasy**: максимум із (зміни генератора або edition, зміни специфікації, зміни конфігу). Без LLM-аналізу, детерміновано.
- ✅ **R14.2 перевіряти автоматично**: golden-тест «додали значення enum / варіант union / optional поле → згенерований код споживача з фікстур компілюється». Це ловить конфлікт exhaustiveness з R8 і R9.

---

## Таблиця де-факто `x-` розширень

Позначки: «читають» означає перевірено в документації чи коді за посиланнями вище. Колонка «Для Dart» — рекомендація.

| Розширення | Призначення | Хто читає | Хто генерує | Для Dart |
|---|---|---|---|---|
| `x-enum-varnames` | Імена членів enum (масив, довжина = `enum`) | OpenAPI Generator ([templating](https://github.com/OpenAPITools/openapi-generator/blob/master/docs/templating.md)), oapi-codegen, openapi-python-client, orval, openapi-typescript ([advanced](https://openapi-ts.dev/advanced)) | вручну або через overlay | ✅ читати (R8.4), перевіряти довжину |
| `x-enumNames` | Те саме, «стиль NSwag/NJsonSchema» | oapi-codegen, orval, openapi-typescript | NSwag/NJsonSchema (ASP.NET); у `@nestjs/swagger` автоматичної генерації не знайдено | ✅ читати як аліас |
| `x-enum-descriptions` / `x-enumDescriptions` | Опис кожного значення | OpenAPI Generator, openapi-typescript, orval (також варіанти в нижньому регістрі) | NJsonSchema / вручну | ✅ читати обидві форми → doc-коментарі |
| OAS 3.1 `oneOf: [{const, title, description}]` | «Annotated enumerations» (OAS 3.2 §4.24.6.3, MAY) | oapi-codegen (enum-via-oneOf, `skip-enum-via-oneof`), orval | Pydantic/інші вручну | ✅ розпізнавати як enum з метаданими |
| `x-extensible-enum` | Відкритий enum (Zalando) | oasdiff, Zally | вручну | ✅ трактувати як open enum |
| `x-ms-enum` `{name, modelAsString, values[{value,name,description}]}` | Ім'я enum і членів; `modelAsString: true` (за замовчуванням) = розширюваний | AutoRest, Kiota (імена членів) | Azure-специфікації | ✅ читати `name` і `values`; `modelAsString` → open |
| `x-speakeasy-unknown-values: allow\|disallow` | Відкритий чи закритий enum/union | Speakeasy | — | ⚠️ читати для сумісності |
| `x-speakeasy-enums` (map\|array), `x-speakeasy-enum-descriptions` | Імена й описи членів | Speakeasy | — | ⚠️ опційно |
| `x-nullable` | nullable зі Swagger 2.0 | OpenAPI Generator (migration doc), AutoRest | Swashbuckle/NSwag у 2.0 | ✅ нормалізатор → `nullable` (info) |
| `x-internal` | Виключити з генерації чи публікації | Redocly (`remove-x-internal`), OpenAPI Generator (`REMOVE_X_INTERNAL`, `FILTER`) | вручну / нормалізатор | ✅ поважати як exclude |
| `x-go-type` / `x-go-type-import` / `x-go-name` / `x-go-type-name` / `x-omitempty` / `x-order` / `x-deprecated-reason` | Мапінг типів і імен для Go | oapi-codegen; ogen читає `x-oapi-codegen-extra-tags` | — | ❌ не читати; ✅ скопіювати дизайн: `x-dart-type` + `x-dart-type-import` |
| `x-ogen-name`, `x-ogen-properties`, `x-ogen-operation-group`, `x-ogen-sse-event-shape` | Імена, групи, форма SSE | ogen | — | ❌ / ідея `event-shape` ✅ |
| `x-speakeasy-name-override`, `x-speakeasy-ignore`, `x-speakeasy-retries`, `x-speakeasy-pagination`, `x-speakeasy-errors`, `x-speakeasy-error-message`, `x-speakeasy-sse-sentinel`, `x-speakeasy-type-override: any`, `x-speakeasy-max-method-params` | Повний набір налаштувань SDK | Speakeasy | — | ⚠️ читати `sse-sentinel` і `error-message` опційно; решта — ідеї для власних `x-` |
| `x-fern-sdk-method-name`, `x-fern-sdk-group-name`, `x-fern-type-name`, `x-fern-ignore`, `x-fern-streaming`, `x-fern-discriminator-context`, `x-fern-pagination`, `x-fern-enum` | Імена, групи, стріми, пагінація | Fern | — | ⚠️ ідеї; `discriminator-context` ✅ як концепт |
| `x-stainless-pagination-property`, `x-stainless-any`, `x-stainless-naming` | Пагінація, явний any, імена | Stainless | — | ✅ ідея `x-<tool>-any` |
| `x-ms-primary-error-message` | Поле з текстом помилки | Kiota | Microsoft Graph | ✅ читати (аліас до власного) |
| `x-ms-pageable`, `x-ms-error-response`, `x-ms-client-name`, `x-ms-discriminator-value` | Пагінація, «це помилка», ім'я, значення дискримінатора | AutoRest | Azure | ⚠️ `x-ms-client-name` можна читати як ім'я |
| `x-lint-ignore` / `x-zally-ignore` | Вбудоване придушення правил | vacuum / Zally | вручну | ⚠️ ідея для `x-<tool>-ignore` |
| `x-oapi-codegen-extra-tags` | Довільні Go struct tags | oapi-codegen, ogen | — | ❌ |

Підсумок для реєстру (R15.5): **читати** стандартні або широко вживані (`x-enum-varnames`, `x-enumNames`, `x-enum-descriptions`/`x-enumDescriptions`, `x-extensible-enum`, `x-ms-enum`, `x-nullable`, `x-internal`, анотовані `oneOf+const`). **Власні** — один простір імен `x-<tool>-*` за зразком Speakeasy, Fern і Stainless: `-name`, `-type`, `-type-import`, `-any`, `-unknown-values`, `-error-message`, `-sse`, `-ignore`, `-tristate`. Опційні **аліаси сумісності** (`x-speakeasy-sse-sentinel`, `x-ms-primary-error-message`) теж зафіксувати в реєстрі.

---

## Джерела

**Speakeasy**
- Enums: https://www.speakeasy.com/docs/customize/data-model/enums
- Forward compatibility: https://www.speakeasy.com/docs/sdks/manage/forward-compatibility
- Changelog v1.661.0: https://www.speakeasy.com/changelog/release/v1.661.0 · v1.663.0: https://www.speakeasy.com/changelog/release/v1.663.0
- SSE: https://www.speakeasy.com/docs/customize/runtime/server-sent-events
- Errors: https://www.speakeasy.com/docs/customize/responses/errors
- Retries: https://www.speakeasy.com/docs/customize/runtime/retries
- Methods (name-override, ignore): https://www.speakeasy.com/docs/customize/methods
- Linting: https://www.speakeasy.com/docs/sdks/prep-openapi/linting
- Extensions: https://www.speakeasy.com/docs/speakeasy-reference/extensions
- Overlay CLI: https://www.speakeasy.com/docs/speakeasy-reference/cli/overlay
- Overlay apply (код): https://github.com/speakeasy-api/openapi/blob/main/overlay/apply.go
- Versioning / changelogs / breaking: https://www.speakeasy.com/docs/sdks/manage/versioning · https://www.speakeasy.com/docs/sdks/manage/sdk-changelogs · https://www.speakeasy.com/docs/sdks/manage/breaking-changes

**Stainless**
- Config reference: https://www.stainless.com/docs/reference/config/
- Diagnostics: https://www.stainless.com/docs/reference/diagnostics/
- Streaming: https://www.stainless.com/docs/sdks/configure/streaming/
- Transforms: https://www.stainless.com/docs/openapi/transforms/
- Breaking change detection: https://www.stainless.com/docs/enterprise/breaking-change-detection/
- LSP: https://www.stainless.com/docs/tools/stainless-language-server/
- SDK, згенеровані Stainless: https://github.com/openai/openai-java · https://github.com/openai/openai-python (`src/openai/_types.py`) · https://github.com/openai/openai-node

**Fern**
- Extensions overview: https://buildwithfern.com/learn/api-definitions/openapi/extensions/overview
- SSE: https://buildwithfern.com/learn/api-definitions/openapi/endpoints/sse
- SSE metadata і reconnection: https://buildwithfern.com/learn/sdks/deep-dives/sse-metadata
- Discriminator context: https://buildwithfern.com/learn/api-definitions/openapi/extensions/discriminator-context
- Overrides: https://buildwithfern.com/learn/api-definitions/openapi/overrides
- Versioning: https://buildwithfern.com/post/automating-semantic-versioning-api-sdks-claude · https://buildwithfern.com/learn/sdks/deep-dives/self-hosted-versioning

**TypeScript-генератори**
- hey-api parser: https://heyapi.dev/openapi-ts/configuration/parser
- hey-api fetch client: https://heyapi.dev/openapi-ts/clients/fetch
- hey-api приклад згенерованого клієнта: https://github.com/hey-api/openapi-ts/tree/main/examples/openapi-ts-fetch/src/client
- orval input/output/enums: https://github.com/orval-labs/orval/tree/master/docs/content/docs
- openapi-typescript CLI / advanced: https://openapi-ts.dev/cli · https://openapi-ts.dev/advanced
- openapi-fetch middleware: https://openapi-ts.dev/openapi-fetch/middleware-auth

**Kiota**
- Using (фільтри, lock, validation rules): https://learn.microsoft.com/en-us/openapi/kiota/using
- Errors: https://learn.microsoft.com/en-us/openapi/kiota/errors
- Abstractions (BackingStore, RequestOptions): https://learn.microsoft.com/en-us/openapi/kiota/abstractions
- Models (oneOf, enums, backing store, імена): https://learn.microsoft.com/en-us/openapi/kiota/models
- UntypedNode: https://github.com/microsoft/kiota-dotnet/tree/main/src/abstractions/serialization

**Go / Python / Rust / Swift**
- oapi-codegen: https://github.com/oapi-codegen/oapi-codegen · https://github.com/oapi-codegen/oapi-codegen/blob/main/configuration-schema.json · https://github.com/oapi-codegen/nullable
- ogen: https://github.com/ogen-go/ogen · документація: https://github.com/ogen-go/web/tree/main/docs (types/optional.md, types/sumtype.md, types/any.md, concepts/convenient_errors.md, spec/extensions.md, 02-features.mdx)
- openapi-python-client: https://github.com/openapi-generators/openapi-python-client
- progenitor: https://github.com/oxidecomputer/progenitor (progenitor-client/src/progenitor_client.rs, progenitor-impl/src/lib.rs)
- swift-openapi-generator: SOAR-0007 https://github.com/apple/swift-openapi-generator/blob/main/Sources/swift-openapi-generator/Documentation.docc/Proposals/SOAR-0007.md · Useful patterns https://github.com/apple/swift-openapi-generator/blob/main/Sources/swift-openapi-generator/Documentation.docc/Articles/Useful-OpenAPI-patterns.md

**OpenAPI Generator, AutoRest**
- Normalizer: https://github.com/OpenAPITools/openapi-generator/blob/master/docs/customization.md
- Templating (`x-enum-varnames`, `x-enum-descriptions`): https://github.com/OpenAPITools/openapi-generator/blob/master/docs/templating.md
- dart-dio `enumUnknownDefaultCase`: https://openapi-generator.tech/docs/generators/dart-dio
- java `hideGenerationTimestamp`: https://openapi-generator.tech/docs/generators/java
- AutoRest extensions: https://github.com/Azure/autorest/blob/main/docs/extensions/readme.md

**Інструменти для специфікацій**
- oasdiff: https://github.com/oasdiff/oasdiff/tree/main/docs (BREAKING-CHANGES.md, FINGERPRINT.md, SOURCE-LOCATOR.md, NULLABILITY.md)
- Spectral: https://github.com/stoplightio/spectral/blob/develop/docs/guides/4d-overrides.md · https://github.com/stoplightio/spectral/blob/develop/docs/guides/2-cli.md
- Redocly: https://redocly.com/docs/cli/commands/lint · https://redocly.com/docs/cli/configuration/reference/rules · https://redocly.com/docs/cli/decorators
- vacuum: https://quobix.com/vacuum/commands/lint/ · https://quobix.com/vacuum/ignoring/
- Zally: https://github.com/zalando/zally · https://github.com/zalando/zally/blob/main/server/rules.md

**Baseline і ratchet у лінтерах коду**
- ESLint suppressions: https://eslint.org/docs/latest/use/suppressions · https://eslint.org/blog/2025/04/introducing-bulk-suppressions/
- PHPStan baseline: https://phpstan.org/user-guide/baseline

**Стандарти і фреймворки**
- OpenAPI 3.2.0: https://spec.openapis.org/oas/v3.2.0.html (§4.14.4, §4.14.6.3, §4.24.6.2, §4.24.6.3, §4.25 `defaultMapping`)
- Overlay: https://spec.openapis.org/overlay/latest.html · https://spec.openapis.org/overlay/
- FastAPI: https://github.com/fastapi/fastapi/blob/master/fastapi/openapi/utils.py · https://fastapi.tiangolo.com/reference/sse/

**Dart**
- dart_apitool: https://pub.dev/packages/dart_apitool
- Exhaustiveness checking: https://dart.dev/language/branches#exhaustiveness-checking

---

### Що не вдалося перевірити

- Чи підтримує hey-api `x-enum-varnames` / `x-enumNames`: пошук по коду впав на rate limit GitHub, тож hey-api у таблицю не внесено.
- Чи генерує `@nestjs/swagger` `x-enumNames` автоматично: підтвердження не знайдено.
- Яка бібліотека Dart реалізує RFC 9535 JSONPath і наскільки повно: не перевірено.
- Підтримка `extension type` у json_serializable (для варіанта (б) у R8): не перевірено.
- Опис ogen («дискримінатор виводиться автоматично») не каже явно, що відбувається при неоднозначності — помилка генерації чи щось інше.
