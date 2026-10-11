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

У кожної знахідки є стабільний код (`TOA011`), JSON-pointer на місце в
специфікації і, якщо парсер зміг визначити позицію, рядок і колонка. Код
виходу `1` означає хоча б одну помилку, `64` — неправильні аргументи або
невідомий клієнт, `78` — конфіг не вдалося прочитати.

Згенеровані клієнти залежать від
[`typed_openapi_runtime`](../typed_openapi_runtime/README.ua.md).

[English version](README.md)
