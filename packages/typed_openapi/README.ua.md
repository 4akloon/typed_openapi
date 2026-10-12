# typed_openapi

Генератор Dart-клієнтів з OpenAPI 3.x для неідеальних специфікацій, згенерованих з коду.

> **Статус:** рання стадія проєктування, пакет ще не опубліковано.

- Вхід: локальний файл OpenAPI 3.0 / 3.1 / 3.2 (JSON або YAML).
- Вихід: готовий Dart-код на Dio, без кроку `build_runner`.
- Моделі дотримуються контракту `json_serializable` (`fromJson` / `toJson`).
- Дефекти специфікації виправляються іменованими правилами нормалізатора і
  потрапляють у звіт як діагностика зі стабільними кодами. Усе неоднозначне
  супроводжується пропозицією override-у.

## Використання

Опиши кожен клієнт у `typed_openapi.yaml` поряд із `pubspec.yaml`:

```yaml
defaults:
  preset: nestjs          # пресет нормалізатора; також: generic, fastapi, springdoc, aspnet
clients:
  core_api:
    input: specs/core_api.json      # локальний знімок, JSON або YAML
    output: lib/src/api/core_api    # у кожного клієнта свій каталог
```

Перевір специфікації без генерації:

```sh
dart run typed_openapi check            # усі клієнти
dart run typed_openapi check core_api   # один клієнт
dart run typed_openapi check --format json   # також: sarif, github-actions
```

`check` читає всю специфікацію, проходить її `$ref` (зокрема в інші локальні
файли) і повідомляє про невідомі ключі, значення неправильного типу, биті або
зациклені посилання і конструкції, яких немає в оголошеній версії OpenAPI.
Потім працює нормалізатор: іменовані правила виправляють дефекти, виправлення
яких випливає зі специфікації або з HTTP (`required: true` на властивості,
повторені значення enum, неоголошені path-параметри, `default` не того типу),
а про решту повідомляють, що змінити в джерелі. `preset` додає до цих підказок
рецепт для вашого фреймворку. Правило вимикається в клієнті або в `defaults`:

```yaml
defaults:
  rules: {dedupe-enum-values: false}
```

Те, чого нормалізатор знати не може, виправляє файл override-ів — без змін на
бекенді. Вкажи його в клієнті (`overrides: typed_openapi.overrides.yaml`) і
адресуй специфікацію операціями та схемами, а не pointer-ами:

```yaml
operations:
  getPet:                     # operationId або METHOD /path: 'GET /pets/{id}'
    parameters:
      id: {schema: {type: integer, format: int64}}   # path:id, якщо імена збігаються
    responses:
      '200': {contentType: application/json}
schemas:
  Pet:
    reason: бекенд надсилає null для тварин без власника
    properties:
      owner: {nullable: true}
      photo: {type: string, format: binary}
```

Override-и змінюють специфікацію до нормалізатора; `null` прибирає поле.
Override, ціль якого зникла, дає warning, той, з яким специфікація вже
збігається, — info, що його можна прибрати, а ключ з одруком — помилку з
підказкою найближчого відомого ключа. Поля для генератора (`name`, `exclude`,
`group`, `exhaustive`, `dartType`, `triState`) задають ім'я, виключення,
групу і тип того, що генерується. Підказки правил, які не можуть виправити
дефект самі, закінчуються override-ом, який можна скопіювати.

`check` також визначає, що буде згенеровано: імена, групи і Dart-типи.
Колізії імен отримують суфікс (`List` -> `ListModel`, `class` -> `class_`,
`getPet2`) і info з override-ом, що закріплює ім'я. Що і як генерувати,
задається в `defaults` або для клієнта:

```yaml
defaults:
  naming:
    group: '{Tag}Api'            # клас на тег; group_by: tag|path|single
    patch_suffix: Patch          # PetPatch: тіло PATCH схеми, вжитої ще деінде
    operation_prefix: '^v1_'     # зрізається з operationId (nestjs: XController_)
  include: {tags: [pets], paths: ['/store/**']}
  exclude: {operations: [deletePet]}
  types:
    number: double               # number без формату; за замовчуванням num
    formats: {decimal: {type: Decimal, import: 'package:decimal/decimal.dart'}}
    schemas: {Money: {type: Money, import: 'package:app/money.dart', converter: MoneyConverter}}
  tri_state: patch               # optional nullable поля PATCH — Patch<T>?
  errors: {default_schema: ErrorDto}
```

У кожної знахідки є стабільний код (`TOA011`), JSON-pointer на місце в
специфікації і, якщо парсер зміг визначити позицію, рядок і колонка. Шляхи —
відносно каталогу, з якого запущено команду. Рівень коду (за кодом або
назвою) змінюється в `defaults` або в клієнті; `off` вимикає його. Коди про
те, що файл специфікації, override-ів чи baseline не читається, знизити не
можна:

```yaml
defaults:
  severity: {TOA208: off, duplicate-operation-id: warning}
```

Щоб почати зі специфікацією, де багато знахідок, зафіксуй наявні в baseline
і вали перевірку лише на нових:

```yaml
clients:
  core_api:
    input: specs/core_api.json
    output: lib/src/api/core_api
    baseline: specs/core_api.baseline.yaml
```

```sh
dart run typed_openapi baseline create   # зафіксувати сьогоднішні error і warning
dart run typed_openapi check             # лише нові; «baselined: N»
dart run typed_openapi check --show-baselined
dart run typed_openapi baseline prune    # прибрати записи, що вже не збігаються
```

Знахідка зіставляється за fingerprint її коду і місця (операція, параметр,
схема чи властивість, якщо місце їх має), а не за текстом чи рядком, тож
інше формулювання повідомлення чи правка деінде в специфікації його не
змінюють. Запис, що більше не збігається, — warning з підказкою
`baseline prune`; `check --strict-baseline` робить його помилкою за будь-якого
рівня з конфігу. `check` повідомляє `TOA820` (baseline-файл не існує), доки
перший `baseline create` його не запише. `baseline create` і `baseline prune`
не чіпають baseline клієнта, чию специфікацію не вдалося прочитати, і
завершуються з кодом `1`. Код виходу `1` означає хоча б одну незафіксовану
помилку, `64` — неправильні аргументи або невідомий клієнт, `78` — конфіг не
вдалося прочитати.

`--format github-actions` друкує по одній анотації workflow на знахідку;
GitHub показує лише обмежену кількість анотацій за запуск, тож для
специфікації з багатьма знахідками спершу заведи baseline.

Згенеровані клієнти залежать від
[`typed_openapi_runtime`](../typed_openapi_runtime/README.ua.md).

[English version](README.md)
