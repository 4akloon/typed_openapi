# typed_openapi_runtime

Runtime для клієнтів, згенерованих
[`typed_openapi`](../typed_openapi/README.ua.md).

> **Статус:** рання стадія проєктування, пакет ще не опубліковано.

Що планується:

- типізовані винятки API і `Result`;
- `Patch<T>` для полів із трьома станами (відсутнє / `null` / значення);
- хелпери декодування JSON, що показують шлях до місця помилки;
- кодувальники стилів параметрів OpenAPI (`form`, `deepObject`, `pipeDelimited`, …);
- SSE-декодер за специфікацією WHATWG.

Пакет навмисно маленький: залежності лише `dio` і `meta`.

[English version](README.md)
