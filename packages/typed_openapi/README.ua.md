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
dart run typed_openapi check --format json
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
`group`, `exhaustive`, `dartType`, `triState`) уже перевіряються і
запрацюють разом із генерацією коду. Підказки правил, які не
можуть виправити дефект самі, закінчуються override-ом, який можна скопіювати.

У кожної знахідки є стабільний код (`TOA011`), JSON-pointer на місце в
специфікації і, якщо парсер зміг визначити позицію, рядок і колонка. Код
виходу `1` означає хоча б одну помилку, `64` — неправильні аргументи або
невідомий клієнт, `78` — конфіг не вдалося прочитати.

Згенеровані клієнти залежать від
[`typed_openapi_runtime`](../typed_openapi_runtime/README.ua.md).

[English version](README.md)
