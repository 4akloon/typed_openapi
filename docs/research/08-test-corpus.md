# 08. Тестовий корпус специфікацій

Дата: **2026-10-11**. Мета: підібрати публічні OpenAPI-специфікації, на яких ганяти `typed_openapi check` зараз і генерацію далі. Пов'язано з [06](06-spec-versions-and-defects.md) (версії і дефекти) та [../requirements.md](../requirements.md).

Файли специфікацій **не збережено** ні в репозиторії, ні на диск. Їх лише прочитано потоком (`curl | скрипт`), щоб порахувати операції, схеми й ознаки. Усі цифри нижче виміряні 2026-10-11 на зазначених комітах. Якщо цифра взята з опису, а не виміряна, це сказано.

## Критерії

- ~12 специфікацій, різні домени, без повторів, де можна їх уникнути.
- Версії: 3.0.x, 3.1.x, 3.2. Формати: JSON і YAML. Є багатофайлові з крос-файловими `$ref`.
- Мінімум 4 згенеровані з коду (FastAPI, NestJS, springdoc, Swashbuckle), решта написані вручну.
- Ознаки для навантаження: `oneOf`/`anyOf` з `discriminator`, `allOf`, `nullable` проти `type: [x, "null"]`, нестрокові enum, `additionalProperties`, multipart і бінарні тіла, SSE, PATCH, конверти і пагінація, багато тегів, схеми безпеки, дуже великий і дуже малий розмір.
- Відомі дефекти — плюс: генератор саме для таких специфікацій.
- Джерело — власник API (його репозиторій або офіційний сайт). Посилання закріплені на SHA коміту або версії, де це можливо.

Ліцензія в таблиці — це ліцензія **репозиторію чи специфікації**, а не юридичний висновок. Колонка «Копія в репо» відповідає на питання, чи можна покласти файл у публічний репозиторій як фікстуру.

## Зведена таблиця

| # | Назва | Домен | OAS | Формат | Розмір | Походження | Ключові ознаки | Ліцензія / копія в репо |
|---|---|---|---|---|---|---|---|---|
| 1 | Stripe API | платежі | 3.0.0 | JSON | 8,3 MB, 612 оп., 1538 схем | власник, внутрішній генератор | `nullable` 2795, `anyOf` 2124, form-urlencoded + `deepObject`, власні `format`, без тегів | MIT, так |
| 2 | OpenAI API | AI/LLM | 3.1.0 | YAML | 4,1 MB, 359 оп., 2048 схем | власник | SSE, multipart, 176 `oneOf`+`discriminator`, `type: [x,"null"]`, `webhooks` | MIT, так |
| 3 | Discord HTTP API | месенджер | 3.1.0 | JSON | 1,2 MB, 246 оп., 538 схем | власник | `oneOf`+`const` без `discriminator`, цілі enum, PATCH, multipart | MIT, так |
| 4 | DigitalOcean API | інфраструктура | 3.0.0 | YAML | 3340 файлів, 3,3 MB, 791 оп. | вручну | **багатофайловий**, `$ref` на рівні операції, шляхи з `:` | Apache-2.0, так |
| 5 | Medusa Store API | e-commerce | 3.0.0 | YAML | 692 файли, 3,1 MB, 78 оп. | з коду (анотації) | **багатофайловий**, `{id}` в іменах файлів, `$ref` у `x-` на `.js`/`.sh` | MIT (з винятком Enterprise), так |
| 6 | Grace Server API | dev tools (VCS) | **3.2.0** | YAML | 38 файлів, 133 оп., 351 схема | вручну | **багатофайловий** `$ref` з `~1`-екрануванням, є бандл поруч | MIT, так |
| 7 | Apache Airflow REST v2 | дані/оркестрація | 3.1.0 | YAML | 544 KB, 134 оп., 198 схем | **FastAPI** | `anyOf`+`null` 803, PATCH 21 з `update_mask`, OAuth2 | Apache-2.0, так |
| 8 | Artemis | освіта | 3.1.0 | YAML (flow) | 112 KB, 67 оп., 127 схем | **springdoc** | flow-стиль YAML, 8 `oneOf`+`discriminator`, дефекти `required` | MIT, так |
| 9 | Tambo API | AI-платформа | 3.0.0 | JSON | 131 KB, 45 оп., 65 схем | **NestJS** | SSE, multipart, `discriminator`, apiKey + bearer | MIT, так |
| 10 | Jellyfin API | медіа | 3.0.4 | JSON | 1,9 MB, 364 оп., 357 схем | **Swashbuckle** (ASP.NET) | `nullable`+`allOf`-обгортка 1038, 46 тегів, подвійні content-type | GPL-2.0 (репозиторій), **ні** |
| 11 | Eclipse Ditto HTTP API | IoT | 3.0.0 | YAML | 519 KB бандл + 234 файли джерел, 131 оп. | вручну | **усі 131 оп. без `operationId`**, `merge-patch+json`, `openIdConnect` | EPL-2.0, з умовами |
| 12 | Google Maps Platform | карти/гео | 3.0.3 | JSON | 2,7 MB, 17 оп., 75 схем | власник (з документації) | величезні `examples`, apiKey у query, `pipeDelimited` | Apache-2.0, так (репо архівне) |
| 13 | EFGS Federation Gateway | здоров'я/уряд | 3.0.1 | JSON | 16 KB, 7 оп. | **springdoc** | мінімум; protobuf, `OPTIONS`, `Accept`/`Content-Type` як параметри | Apache-2.0, так |

Згенеровані з коду: №5, 7, 8, 9, 10, 13 (шість). Багатофайлові: №4, 5, 6 (і джерела №11).

Шарування для CI:
- **Малі (мілісекунди):** №13, №9, №8. Ганяти на кожному коміті.
- **Середні:** №7, №11, №6, №5, №4, №2/3 (бандл). Нормальний набір.
- **Навантаження:** №1 (8,3 MB), №2 (4,1 MB), №12 (2,7 MB), №10 (1,9 MB), №3 (1,2 MB). Для перевірки меж (див. TOA007/TOA008 у CLAUDE.md) і часу.

## Специфікації

### 1. Stripe API (платежі)

- **Власник:** Stripe. Репозиторій [stripe/openapi](https://github.com/stripe/openapi).
- **URL:** `https://raw.githubusercontent.com/stripe/openapi/7a1f5c21117298a85995746eeeedb6207969dc4e/openapi/spec3.json`. Версія API: `2026-09-30.endive`.
- **OAS / формат:** 3.0.0, JSON. Є і YAML (`spec3.yaml`, 6,6 MB).
- **Розмір:** 8 317 513 байт; 431 шлях, 612 операцій (273 GET, 307 POST, 32 DELETE), 1538 схем.
- **Один чи кілька файлів:** один. Поруч менший `fixtures3.json` (193 KB) — зручний для швидких прогонів.
- **Походження:** власник, інструментом; `info.x-stripeSpecFilename` вказує на внутрішній експорт. Не код-фреймворк.
- **Ознаки:** `anyOf` 2124, `oneOf` 322, `nullable: true` 2795, enum 4399 (24 з булевими `true`), `additionalProperties` 958. Тіла запитів у `application/x-www-form-urlencoded` (611) з `style: deepObject` (366 параметрів). Пагінація: `has_more`, `starting_after`, `ending_before`, `limit`. Безпека: `basic` і `bearer`. Один multipart (завантаження файлів).
- **Дефекти й особливості:** власні `format`: `unix-time` (528), `currency` (182), `decimal` (116) — це перевірка R6.8. Нема `tags` і нема `PATCH`. 77 імен схем із крапкою (`billing.alert`). Усі 4062 `$ref` внутрішні і розв'язуються.
- **Ліцензія:** [MIT](https://github.com/stripe/openapi/blob/master/LICENSE). Копія в репо дозволена, але 8,3 MB — краще брати `fixtures3.json` або завантажувати за SHA у CI.

### 2. OpenAI API (AI/LLM)

- **Власник:** OpenAI. Репозиторій [openai/openai-openapi](https://github.com/openai/openai-openapi).
- **URL:** `https://raw.githubusercontent.com/openai/openai-openapi/e95c0fe615f45a19e8878af923a729948445a6bd/openapi.yaml`. `info.version`: 2.3.0.
- **OAS / формат:** 3.1.0, YAML (є й `openapi.json`, 4,8 MB).
- **Розмір:** 4 058 614 байт; 230 шляхів, 359 операцій (159 GET, 149 POST, 51 DELETE), 2048 схем, 40 тегів, 30 `webhooks`.
- **Файли:** один.
- **Походження:** підтримується власником; фреймворк не вказано. Розширення `x-oaiMeta`, `x-openai-structured-output-limits`.
- **Ознаки:**
  - SSE: `text/event-stream` у 12 місцях.
  - Multipart (18) і бінарні тіла (`format: binary` 35, `application/octet-stream`, `audio/wav`, `application/sdp`).
  - `oneOf` з `discriminator` 176 (124 без `mapping`), `type: [x, "null"]` 304, `anyOf` з `null` 1115, `allOf` 165.
  - Enum із `null` (7) і цілими (5).
  - Пагінація: `after`/`before`/`limit` + `has_more`/`first_id`/`last_id`.
  - Безпека: два `bearer` (звичайний і адмін-ключ).
- **Дефекти:** 117 `operationId` не є ідентифікаторами (`create-live`, `accept-live-session`); 10 схем із суфіксом `-2` (`Error-2`, `ConversationParam-2` — наслідок злиття); 18 об'єктів, де `required` містить поля, яких нема в `properties`; `PATCH` немає (зміни через `POST`).
- **Ліцензія:** [MIT](https://github.com/openai/openai-openapi/blob/main/LICENSE), `info.license` теж MIT. Копія дозволена; 4,1 MB — краще завантажувати в CI.

### 3. Discord HTTP API (месенджер/соцмережа)

- **Власник:** Discord. Репозиторій [discord/discord-api-spec](https://github.com/discord/discord-api-spec).
- **URL:** `https://raw.githubusercontent.com/discord/discord-api-spec/1ff2dee3677fabef7b49f942bbae93d06c0c9f2c/specs/openapi.json`. Заголовок: «Discord HTTP API (Preview)», версія `10`.
- **OAS / формат:** 3.1.0, JSON.
- **Розмір:** 1 192 427 байт; 153 шляхи, 246 операцій (103 GET, 45 POST, 40 DELETE, 33 PATCH, 25 PUT), 538 схем.
- **Файли:** один.
- **Походження:** власник; не оголошено. Стиль (`const`, `snake_case` ідентифікатори, послідовність) схожий на згенерований, але це припущення.
- **Ознаки:** `oneOf` 497 разом із `const` 659 і **без жодного `discriminator`** — тип розрізняється значенням `const`. `type: [x, "null"]` 909. Цілі enum 165. Власні `format`: `snowflake`, `nonce`. `multipart/form-data` 15, `x-www-form-urlencoded` 12; PATCH 33 (3 із них не JSON). 12 операцій з кількома 2xx. Безпека: `apiKey` у заголовку (BotToken) + OAuth2. Тегів нема.
- **Дефекти:** немає — специфікація чиста. Корисна як «еталон складного, але правильного 3.1».
- **Ліцензія:** [MIT](https://github.com/discord/discord-api-spec/blob/main/LICENSE). Копія дозволена (1,2 MB).

### 4. DigitalOcean API (хмара/інфраструктура)

- **Власник:** DigitalOcean. Репозиторій [digitalocean/openapi](https://github.com/digitalocean/openapi).
- **URL входу:** `https://raw.githubusercontent.com/digitalocean/openapi/6fda13183a6046c669b591e057b9d7b3a6344829/specification/DigitalOcean-public.v2.yaml`. Для крос-файлового тесту потрібна вся тека `specification/` на тому ж SHA ([дерево](https://github.com/digitalocean/openapi/tree/6fda13183a6046c669b591e057b9d7b3a6344829/specification)).
- **OAS / формат:** 3.0.0, YAML.
- **Розмір:** вхідний файл 129 461 байт; усього 3340 YAML-файлів, 3,3 MB. 538 шляхів, 791 операція (412 GET, 178 POST, 110 DELETE, 72 PUT, 19 PATCH).
- **Файли:** багато. Вхід містить `info`, `security`, `components.securitySchemes`, `x-tagGroups`; схем і операцій у ньому нема.
- **Походження:** вручну (YAML-джерела в `resources/<група>/`, спільне в `shared/`).
- **Ознаки і дефекти (усі корисні для тесту `$ref`):**
  - **`$ref` стоїть на рівні операції** (`get: { $ref: "resources/.../x.yml" }`), а не на рівні Path Item. За специфікацією так не можна; це пряма перевірка TOA10x.
  - Посилання на цілі файли без фрагмента (`models/droplet.yml`), на фрагменти (`examples.yml#/droplet_create_request`), відносні вгору (`../../shared/responses/unauthorized.yml`).
  - Посилання на `description.yml#/introduction` — на довільний YAML-вузол.
  - Шляхи з двокрапкою: `/v2/action-gateway/actors/{actor_id}/limits:clear`.
  - `operationId` лише у файлах операцій (`droplets_create`); у вхідному файлі їх нема.
  - `oneOf` у тілі запиту (один або кілька дроплетів). `x-tagGroups`.
- **Ліцензія:** [Apache-2.0](https://github.com/digitalocean/openapi/blob/main/LICENSE). Копія дозволена, але 3340 файлів — краще підтягувати за SHA.

### 5. Medusa Store API (e-commerce)

- **Власник:** Medusa. Репозиторій [medusajs/medusa](https://github.com/medusajs/medusa).
- **URL входу:** `https://raw.githubusercontent.com/medusajs/medusa/146c46b0ad1146b40595c8ef586c4d5890982603/www/apps/api-reference/specs/store/openapi.yaml`. Дерево: [specs/store](https://github.com/medusajs/medusa/tree/146c46b0ad1146b40595c8ef586c4d5890982603/www/apps/api-reference/specs/store). Є й `specs/admin` (273 шляхи, 897 файлів, 7,2 MB).
- **OAS / формат:** 3.0.0, YAML. `info.version`: 2.21.2.
- **Розмір:** вхід 15 858 байт; 692 файли (без прикладів коду), 3 136 987 байт: 68 файлів шляхів (78 операцій: 39 POST, 33 GET, 6 DELETE) і 607 файлів схем.
- **Файли:** багато (шляхи, схеми, відповіді, параметри окремими файлами).
- **Походження:** з коду. Розширення операцій `x-workflow: createCartWorkflow`, `x-events`, `x-allowed` ведуть у серверний код. Сам інструмент генерації не перевірено.
- **Ознаки:** `allOf` у тілах, `securitySchemes`: `jwt_token` (bearer), `cookie_auth` (apiKey у cookie), `reset_password`. `operationId` на кшталт `PostActor_typeAuth_providerVerificationConfirm` — псевдо-PascalCase з імен параметрів шляху.
- **Дефекти:** в іменах файлів фігурні дужки (`store_carts_{id}.yaml`) — у `$ref` вони не екрановані (не RFC 3986). `x-associatedSchema` у тегах містить `$ref` усередині розширення. `x-codeSamples[].source` — `$ref` на `.js` і `.sh`, не на YAML/JSON. Вхід має 88 зовнішніх `$ref` і жодного внутрішнього.
- **Ліцензія:** репозиторій під [MIT, крім Enterprise](https://github.com/medusajs/medusa/blob/develop/LICENSE); `info.license` у специфікації — MIT. Копія дозволена для `specs/store` (там нема Enterprise-матеріалів).

### 6. Grace Server API (dev tools: контроль версій)

- **Власник:** Scott Arbeit. Репозиторій [ScottArbeit/Grace](https://github.com/ScottArbeit/Grace), сервер на F#.
- **URL входу (джерело):** `https://raw.githubusercontent.com/ScottArbeit/Grace/f746b688e0d20fdfdc46eedb42bd8d301be61a34/src/OpenAPI/Main.OpenAPI.yaml`. Бандл: `.../src/OpenAPI/Grace.OpenAPI.yaml` на тому ж SHA. Тека: [src/OpenAPI](https://github.com/ScottArbeit/Grace/tree/f746b688e0d20fdfdc46eedb42bd8d301be61a34/src/OpenAPI).
- **OAS / формат:** **3.2.0**, YAML. Версія API `2023-10-01`.
- **Розмір:** бандл 338 021 байт; 133 операції (129 POST, 4 GET), 351 схема, 11 тегів. Теку складають 38 файлів, 1,1 MB (разом із бандлом і проєкцією).
- **Файли:** і багатофайлове джерело, і готовий бандл. Це дає тест «джерело і бандл дають однакову модель».
- **Походження:** вручну; опис операції `GetOpenApi` прямо каже, що специфікація збирається з файлів `src/OpenAPI`. У теці є й `Grace.OpenAPI.3.1.2.yaml` — автоматичний зсув версії 3.2.0 → 3.1.2 (`@redocly/cli`), з `loss-report.json`.
- **Ознаки:** `$ref` з фрагментами, де ключі шляхів екрановані як `~1`: `./Approval.Paths.OpenAPI.yaml#/~1approval~1policy~1create`. Компоненти-посилання на корінь файла: `Approval.Components.OpenAPI.yaml#/ApprovalPolicy`. `allOf` 170, `nullable: true` 73 (!), `const` 6, цілі enum 5, `application/octet-stream`. Безпека: `apiKey` + `bearer`.
- **Дефекти:** документ позначений 3.2.0, але вживає `nullable: true` — це ключове слово 3.0, у 3.1+ його нема. Один об'єкт із `required` без відповідного поля. З 3.2-конструкцій використано лише рядок версії.
- **Ліцензія:** [MIT](https://github.com/ScottArbeit/Grace/blob/main/LICENSE.md). Копія дозволена.

### 7. Apache Airflow REST API v2 (дані/оркестрація, FastAPI)

- **Власник:** Apache Airflow. Репозиторій [apache/airflow](https://github.com/apache/airflow).
- **URL:** `https://raw.githubusercontent.com/apache/airflow/4ca1f6693bb380ae1f148a6187001adbcadbfa22/airflow-core/src/airflow/api_fastapi/core_api/openapi/v2-rest-api-generated.yaml`.
- **OAS / формат:** 3.1.0, YAML.
- **Розмір:** 543 538 байт; 94 шляхи, 134 операції (73 GET, 21 PATCH, 20 POST, 14 DELETE, 6 PUT), 198 схем, 29 тегів.
- **Файли:** один. Поруч `_private_ui.yaml` (166 KB, внутрішній).
- **Походження: FastAPI.** Докази: ім'я файла `...-generated.yaml`, 131 згадка `ValidationError`/`HTTPValidationError`, `operationId` у `snake_case` з імен функцій (`get_assets`), `title: Update Mask` (автозаголовки Pydantic).
- **Ознаки:** це зразок виходу FastAPI + Pydantic v2: `anyOf: [X, {type: "null"}]` 803 разів (замість `nullable`), `const` 22, `prefixItems` 2, `oneOf` 10, `additionalProperties` 90. **PATCH 21** з `update_mask` у query (`anyOf` масив/null) і `application/json`-тілом — пряма перевірка `Patch<T>`. Конверти `*CollectionResponse` з `total_entries` (78 згадок). Пагінація `limit`/`offset`. `application/x-ndjson` (2) — потокові відповіді. Безпека: `OAuth2PasswordBearer` + `HTTPBearer`.
- **Дефекти:** `discriminator` не використано, хоча є `oneOf`. Інакше специфікація чиста.
- **Ліцензія:** [Apache-2.0](https://github.com/apache/airflow/blob/main/LICENSE). Копія дозволена (544 KB).

### 8. Artemis (освіта, springdoc)

- **Власник:** TUM (ls1intum). Репозиторій [ls1intum/Artemis](https://github.com/ls1intum/Artemis).
- **URL:** `https://raw.githubusercontent.com/ls1intum/Artemis/e92f350e7892b514b976b05c4f83cfcec12ec54c/config/openapi/openapi.yaml`. Версія `10.3`.
- **OAS / формат:** 3.1.0, YAML **у flow-стилі** (`schema: {type: integer, format: int64}`, `servers: - {url: ..., description: ...}`).
- **Розмір:** 112 129 байт; 58 шляхів, 67 операцій (30 POST, 21 GET, 9 PUT, 5 DELETE, 2 PATCH), 127 схем, 16 тегів.
- **Файли:** один.
- **Походження: springdoc.** Докази: у `build.gradle` плагін `org.springdoc.openapi-gradle-plugin`; `servers[0].description: "Generated server url"` (фірмовий знак springdoc).
- **Ознаки:** `oneOf` з `discriminator` 8 (1 без `mapping`), `type: [x, "null"]` 6, enum 79, `additionalProperties` 4, `text/csv`, `text/calendar`, `format: binary`.
- **Дефекти:** 2 об'єкти з `required` без відповідного поля в `properties` ; серед `operationId` є надто загальні (`update`) — перевірка колізій імен у клієнті.
- **Ліцензія:** [MIT](https://github.com/ls1intum/Artemis/blob/develop/LICENSE). Копія дозволена.

### 9. Tambo API (AI-платформа, NestJS)

- **Власник:** tambo-ai. Репозиторій [tambo-ai/tambo](https://github.com/tambo-ai/tambo).
- **URL:** `https://raw.githubusercontent.com/tambo-ai/tambo/6e2c1bff3b68a00c094b6d876788cc8f33f7bb02/stainless/openapi.json`.
- **OAS / формат:** 3.0.0, JSON.
- **Розмір:** 130 999 байт; 36 шляхів, 45 операцій (19 POST, 16 GET, 7 DELETE, 2 PUT, 1 PATCH), 65 схем, 9 тегів.
- **Файли:** один.
- **Походження: NestJS (`@nestjs/swagger`).** Докази: `@nestjs/swagger` у `apps/api/package.json`; `operationId` вигляду `V1Controller_createRun`, `AppController_getHello`; `info.contact: {}`; порожній `servers`.
- **Ознаки:** SSE у `POST /v1/threads/runs` і `POST /v1/threads/{threadId}/runs`; multipart у `POST /audio/transcribe`; `discriminator` у 5 схемах (`Message`, `InputMessage`, `ToolResultContent`), `oneOf` 7, `allOf` 16; `nullable: true` 3; enum 33; `additionalProperties` 38; пагінація `limit`/`cursor` + `hasMore`. Безпека: `apiKey` (заголовок) + `bearer`.
- **Дефекти:** `operationId` з `Controller_` — типовий шум NestJS; перевірка правил імен (R5.1). `servers` порожній.
- **Домен:** перетинається з №2 (AI). Якщо потрібна сувора різнорідність доменів, замінити на Immich (див. runner-up).
- **Ліцензія:** [MIT](https://github.com/tambo-ai/tambo/blob/main/LICENSE). Копія дозволена.

### 10. Jellyfin API (медіа, ASP.NET Swashbuckle)

- **Власник:** Jellyfin. Опубліковано на `repo.jellyfin.org`; сервер: [jellyfin/jellyfin](https://github.com/jellyfin/jellyfin).
- **URL (версійний):** `https://repo.jellyfin.org/files/openapi/stable/jellyfin-openapi-12.2.json`. Перевірено: 1 896 214 байт, SHA-256 починається з `bd31bb194443d1c5`, `Last-Modified: 2026-10-05`. Рухомий псевдонім: `https://api.jellyfin.org/openapi/jellyfin-openapi-stable.json`.
- **OAS / формат:** **3.0.4**, JSON (рідкісний патч-рядок). `info.x-jellyfin-version: 12.2.0`.
- **Розмір:** 1 896 214 байт; 294 шляхи, 364 операції (186 GET, 130 POST, 30 DELETE, 18 HEAD), 357 схем, 46 тегів.
- **Файли:** один.
- **Походження: Swashbuckle.** Докази: `Swashbuckle` в `Jellyfin.Api/Jellyfin.Api.csproj` і `Directory.Packages.props`; `operationId` з імен дій (`GetLogEntries`, `CreateKey`).
- **Ознаки:** `nullable: true` 1038 + `allOf` 530 — типова обгортка Swashbuckle `allOf: [{$ref}]` + `nullable`; `discriminator` 3; `additionalProperties` 316; 68 `deprecated`. Три-чотири дублі content-type на кожну відповідь: `application/json`, `application/json; profile="CamelCase"`, `application/json; profile="PascalCase"`, `text/json`, `application/*+json`. `format: binary` 64, `image/*`, `video/*` (стрімінг). `HEAD`-операції. `style: deepObject` 8.
- **Дефекти:** `format: text` (364) — нестандартний формат; багато дублювання схем відповіді; одна `securityScheme` (`apiKey` у заголовку) з кастомною назвою.
- **Ліцензія:** репозиторій сервера — [GPL-2.0](https://github.com/jellyfin/jellyfin/blob/master/LICENSE); ліцензію самого файла специфікації не вказано. Копію в публічне репо **не класти**, брати за URL у CI.

### 11. Eclipse Ditto HTTP API (IoT)

- **Власник:** Eclipse Ditto. Репозиторій [eclipse-ditto/ditto](https://github.com/eclipse-ditto/ditto).
- **URL бандла:** `https://raw.githubusercontent.com/eclipse-ditto/ditto/952e3c270e7845666ee40e1ae945872fba520430/documentation/src/main/resources/openapi/ditto-api-2.yml`. Джерела: [openapi/sources](https://github.com/eclipse-ditto/ditto/tree/952e3c270e7845666ee40e1ae945872fba520430/documentation/src/main/resources/openapi/sources) (`api-2-index.yml` + `paths/`, `schemas/`, `parameters/`, `responses/`, `requests/`, `security/`).
- **OAS / формат:** 3.0.0, YAML. (У README сказано «version 2» — це версія API, не OAS.)
- **Розмір:** бандл 519 051 байт; 61 шлях, 131 операція (45 GET, 32 PUT, 21 DELETE, 20 POST, 12 PATCH, 1 HEAD), 82 схеми, 47 параметрів, 12 відповідей, 10 requestBodies, 9 тегів. Джерела: 234 файли.
- **Файли:** і багатофайлове джерело (збирається `swagger-cli bundle`), і бандл.
- **Походження:** вручну.
- **Ознаки:** PATCH з **`application/merge-patch+json`** (9 з 12) — найближче до реального JSON Merge Patch (R7). Інші типи: `application/td+json`, `application/vnd.eclipse.ditto+json`. 21 операція з кількома 2xx. Безпека: п'ять схем, зокрема `openIdConnect` і два `basic`. `links` 1. 1656 `$ref`.
- **Дефекти:** **`operationId` відсутній у всіх 131 операції** — прямий тест генерації імен із `method + path`. `iri-reference` як `format`.
- **Ліцензія:** [EPL-2.0](https://github.com/eclipse-ditto/ditto/blob/master/LICENSE) (файловий copyleft). Копія допустима зі збереженням заголовка і повідомлення; для зручності можна не зберігати, а брати за SHA.

### 12. Google Maps Platform (карти/гео)

- **Власник:** Google. Репозиторій [googlemaps/openapi-specification](https://github.com/googlemaps/openapi-specification) — **архівний/deprecated** (README веде до Postman).
- **URL (реліз):** `https://github.com/googlemaps/openapi-specification/releases/download/v1.22.3/google-maps-platform-openapi3.json`. Реліз 2023-01-25, тег `v1.22.3` → комміт `21659934ef78dd9e24982fadb843f83b2c15609f`. Є `.yml`-варіант (2,3 MB).
- **OAS / формат:** 3.0.3, JSON.
- **Розмір:** 2 727 068 байт, але лише 17 операцій (16 GET, 1 POST), 75 схем, 74 параметри, 9 тегів. Розмір дають вбудовані приклади.
- **Файли:** один.
- **Походження:** власник, зібрано з документації Google (не з коду).
- **Ознаки:** `securitySchemes`: `apiKey` у **query** (`key`); `style: pipeDelimited` (9); enum 31, у них цілі (10); пагінація `next_page_token`; `format: binary` для зображень (`image/*`). Стрес «малий API — великий документ».
- **Дефекти:** файл 2023 року, більше не оновлюється. Корисний як регресія для великих `examples`.
- **Ліцензія:** [Apache-2.0](https://github.com/googlemaps/openapi-specification/blob/main/LICENSE) (GitHub показує NOASSERTION через формат файла). Копія допустима, але 2,7 MB — у CI краще за URL.

### 13. EFGS Federation Gateway (здоров'я/уряд, springdoc)

- **Власник:** EU Federation Gateway Service (коронавірусні додатки). Репозиторій [efgs-federation-gateway](https://github.com/eu-federation-gateway-service/efgs-federation-gateway).
- **URL:** `https://raw.githubusercontent.com/eu-federation-gateway-service/efgs-federation-gateway/cba7be6756b089a7775e2354b367b9830d979105/docs/openapi.json`. Останній комміт 2025-01-24.
- **OAS / формат:** 3.0.1, JSON.
- **Розмір:** 15 766 байт; 6 шляхів, 7 операцій (3 GET, PUT, DELETE, OPTIONS, POST), 1 схема, 5 тегів.
- **Файли:** один.
- **Походження: springdoc.** Докази: `servers[0].description: "Generated server url"` (`http://localhost:8090`), OAS 3.0.1, `title: efgs-federation-gateway`, `version: 1.0.0-SNAPSHOT`.
- **Ознаки і дефекти:**
  - Заголовки `Accept` і `Content-Type` описано як **параметри** (за специфікацією їх ігнорують).
  - Тіло запиту `application/protobuf; version=1.0` і `application/json; version=1.0`; відповідь `application/json+v1.0`.
  - Операція `OPTIONS`; 207 і 410 серед відповідей; відповіді без `content`.
- **Ліцензія:** [Apache-2.0](https://github.com/eu-federation-gateway-service/efgs-federation-gateway/blob/master/LICENSE). Копія дозволена.

## Runner-up

Не потрапили в основний набір з вказаних причин. Придатні як заміна або доповнення.

1. **GitHub REST API** — [github/rest-api-description](https://github.com/github/rest-api-description), MIT. `descriptions/api.github.com/api.github.com.2022-11-28.json` на SHA `58b1e0c00b39b9e46c24dc4a0ba6a2669c90e9c1`: 3.0.3, 12,9 MB, 1232 операції, 994 схеми, 44 теги. Є пара 3.0/3.1 (`descriptions-next/`). `operationId` на кшталт `meta/root` (слеш, дефіс) і 893 імені схем у kebab-case — найсильніший тест нормалізації імен. Не взято, бо вже є три стрес-специфікації (№1, 2, 10) і домен dev tools покритий №6.
2. **Immich** — [immich-app/immich](https://github.com/immich-app/immich), `open-api/immich-openapi-specs.json`, SHA `2685234ed390746413203a2cf0b18bc36dba53d1`: 3.0.0, 955 KB, 279 операцій, 438 схем, NestJS. Multipart (3), `application/octet-stream` (11), три схеми безпеки (bearer, cookie, `api_key`), `nullable` 252. **AGPL-3.0**, копію не класти. Домен «фото/медіа» перетинається з №10.
3. **weather.gov API (NWS)** — `https://api.weather.gov/openapi.json`, живий URL (ETag `d35176a8...`, версія 3.12.2), **OAS 3.1.2**, JSON, 123 KB, 69 GET. Типи `application/ld+json`, `application/geo+json`, XML. Публічне надбання США; URL не закріплюється (старіша копія в [weather-gov/api](https://github.com/weather-gov/api) — 3.0.3, v1.9.0).
4. **traefik/whoami** — [traefik/whoami](https://github.com/traefik/whoami), SHA `1ce75d01b6978863647da42557a707a479da3a51`, `openapi.yaml`: **3.2.0**, 8 KB, 6 операцій, Apache-2.0. Найменша справжня 3.2-специфікація. Не взято, бо №13 вже закриває «малий», а 3.2 закриває №6.
5. **Train Travel API** — [bump-sh-examples/train-travel-api](https://github.com/bump-sh-examples/train-travel-api), `openapi.yaml`: 3.2.0, 57 KB, метод `QUERY`, `webhooks`, OAuth2, `allOf` 24. Ліцензія **CC-BY-NC-SA-4.0** (некомерційна) — у публічний репо з MIT не клали б.

Також для 3.2-конструкцій: офіційні приклади OAI [learn.openapis.org/examples/v3.2](https://github.com/OAI/learn.openapis.org/tree/82b82f372aa185a07ea11bc158619895ab21f741/examples/v3.2) (`3.2-query-example.yaml`, `3.2-tags-example.yaml`, 3 KB і 2 KB, [CC-BY-4.0](https://github.com/OAI/learn.openapis.org)). Метод `query` вони показують у чистому вигляді. Рекомендую додати їх як маленькі фікстури.

Також дивилися й відхилили: ClinicalTrials.gov (`https://clinicaltrials.gov/api/oas/v2`, 3.0.3, YAML, 81 KB, 9 операцій, живий URL без версії, схоже на Java-генерацію, але не доведено); Supabase Management API (`apps/docs/spec/transforms/api_v1_openapi_deparsed.json`, 3.0.0, 644 KB, `nullable` 519, але це перетворений для документації файл і NestJS не доведено); MITRE Vulcan (3.2.0, багатофайловий, 223 файли, але домен безпеки/Rails і ліцензія файлів не визначена).

## Матриця покриття

Позначки: ✅ є · ⚠️ є, але слабо чи частково · ❌ немає. Номери як у зведеній таблиці. Виміряно скриптом по специфікаціях; для багатофайлових №4, 5 — за повним проходом (№5 по файлах шляхів) або за описом, де прямо сказано.

| Ознака | 1 Stripe | 2 OpenAI | 3 Discord | 4 DO | 5 Medusa | 6 Grace | 7 Airflow | 8 Artemis | 9 Tambo | 10 Jellyfin | 11 Ditto | 12 Maps | 13 EFGS |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| OAS 3.0.x | ✅ | | | ✅ | ✅ | | | | ✅ | ✅ (3.0.4) | ✅ | ✅ | ✅ (3.0.1) |
| OAS 3.1.x | | ✅ | ✅ | | | | ✅ | ✅ | | | | | |
| OAS 3.2 | | | | | | ✅ (лише рядок) | | | | | | | |
| JSON | ✅ | | ✅ | | | | | | ✅ | ✅ | | ✅ | ✅ |
| YAML | | ✅ | | ✅ | ✅ | ✅ | ✅ | ✅ (flow) | | | ✅ | | |
| Багатофайловий `$ref` | | | | ✅ | ✅ | ✅ | | | | | ✅ (джерела) | | |
| Згенеровано з коду | ⚠️ | ❌ | ⚠️ | ❌ | ✅ | ❌ | ✅ FastAPI | ✅ springdoc | ✅ NestJS | ✅ Swashbuckle | ❌ | ❌ | ✅ springdoc |
| `oneOf` + `discriminator` | ❌ | ✅ | ❌ (`const`) | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ⚠️ (3) | ❌ | ❌ | ❌ |
| `oneOf`/`anyOf` без `discriminator` | ✅ | ✅ | ✅ | ✅ | ⚠️ | ⚠️ | ✅ | ✅ | ✅ | ⚠️ | ✅ | ❌ | ❌ |
| `allOf` (спадкування) | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ |
| `nullable: true` | ✅ | ⚠️ | ❌ | ❌ | ? | ✅ | ❌ | ❌ | ⚠️ | ✅ | ❌ | ❌ | ❌ |
| `type: [x, "null"]` | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `anyOf` з `{type: "null"}` | ❌ | ✅ | ❌ | ❌ | ❌ | ⚠️ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Нестрокові enum | ✅ (bool) | ✅ | ✅ (int) | ? | ? | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ (int) | ❌ |
| `additionalProperties` | ✅ | ✅ | ✅ | ? | ? | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| multipart / бінарне тіло | ⚠️ | ✅ | ✅ | ❌ | ❌ | ⚠️ | ❌ | ⚠️ | ✅ | ⚠️ (відповіді) | ⚠️ | ⚠️ | ✅ (protobuf) |
| SSE / `text/event-stream` | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ⚠️ (ndjson) | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| PATCH | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ⚠️ | ❌ | ✅ (merge-patch) | ❌ | ❌ |
| Конверт / пагінація | ✅ | ✅ | ⚠️ | ✅ | ✅ | ❌ | ✅ | ⚠️ | ✅ | ⚠️ | ⚠️ | ⚠️ | ❌ |
| Багато тегів (≥15) | ❌ | ✅ | ❌ | ✅ | ⚠️ | ⚠️ (11) | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ |
| apiKey | | | ✅ | | ✅ (cookie) | ✅ | | | ✅ | ✅ | | ✅ (query) | |
| bearer / http | ✅ | ✅ | | ✅ | ✅ | ✅ | ✅ | | ✅ | | ✅ | | |
| OAuth2 / OIDC | | | ✅ | | | | ✅ | | | | ✅ (OIDC) | | |
| Дуже великий (>1 MB) | ✅ | ✅ | ✅ | ✅ (сума) | ✅ (сума) | | | | | ✅ | | ✅ | |
| Дуже малий (<20 KB) | | | | | ⚠️ (вхід 16 KB) | | | | | | | | ✅ |
| Нема `operationId` | ❌ | ❌ | ❌ | ⚠️ (у файлах) | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| Не-ідентифікатори в іменах | ✅ (схеми з `.`) | ✅ | ❌ | ❌ | ⚠️ | ❌ | ❌ | ❌ | ⚠️ | ❌ | ❌ | ❌ | ❌ |
| `required` поза `properties` | ❌ | ✅ (18) | ❌ | ? | ? | ✅ (1) | ❌ | ✅ (2) | ❌ | ❌ | ❌ | ❌ | ❌ |
| Нестандартний `format` | ✅ | ✅ | ✅ | ? | ? | ⚠️ | ❌ | ❌ | ❌ | ✅ (`text`) | ⚠️ | ❌ | ❌ |
| `$ref` не на схему (файл/розширення) | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ⚠️ | ❌ | ❌ |

`?` у багатофайлових №4 і №5 — не вимірювалось по всіх файлах схем (скрипт читає лише одну кореневу структуру).

## Прогалини покриття

Не вдалося закрити:

1. **Конструкції 3.2 понад рядок версії.** У Grace і у whoami використано лише `openapi: 3.2.0`. Метод `QUERY`, `tags` з `parent`/`kind`, `itemSchema` (для SSE у 3.2), `$self`, `mediaTypes` є тільки в офіційних прикладах OAI (CC-BY-4.0, 3 KB) і в Train Travel (NC-SA). Рекомендація: взяти приклади OAI як малі фікстури.
2. **Стилі параметрів шляху `matrix`/`label`.** Не знайшов жодної публічної специфікації з ними. Єдиний явний стиль шляху — `simple` у Stripe (450). `form`/`deepObject`/`pipeDelimited` покриті Stripe, OpenAI, Jellyfin, Maps. Потрібна синтетична фікстура.
3. **Справжній SSE зі схемою подій.** Є лише `text/event-stream` у відповіді OpenAI і Tambo. SSE на `itemSchema` (3.2) і з `discriminator` по типу події не знайдено. Потрібна синтетична фікстура.
4. **Зв'язка `nullable: true` + `type: [x, "null"]` в одному документі у 3.1+.** Grace майже (3.2 з `nullable`), але масштабу мало. Для 3.1 це частий дефект генераторів; шукати окремо або писати вручну.
5. **Багатофайлова специфікація з `$ref` за HTTP.** Усі знайдені — лише локальні відносні посилання. R-вимоги забороняють мережу, тому це й не потрібно, але справжньої специфікації з `http(s)://`-посиланнями у корпусі нема.
6. **Код-фреймворки, для яких нема окремого прикладу:** NSwag (лише крихітний [приклад RicoSuter](https://github.com/RicoSuter/NSwag/tree/master/src/NSwag.Sample.NET90Minimal), MIT) і чистий springfox/OAS 2→3 перехід. Це закрито частково: Swashbuckle (№10) дає той самий клас помилок.
7. **Домени.** №2 і №9 (AI) перетинаються; №10 і runner-up Immich (медіа) теж. Домен «здоров'я» закритий найменшою специфікацією (№13); реальної медичної системи (FHIR/HL7) у корпусі нема. Ключові «живі» державні API (weather.gov, ClinicalTrials.gov) без закріплення версії, тому в основний набір не взяті.
8. **Помилки HTTP-рівня**: специфікацій, де `default`-відповідь має різну схему на різних операціях (R11.4), не шукав окремо. Перевірити на Stripe і Airflow (`HTTPValidationError`).

## Джерела

- Дослідження виконано через GitHub API (`gh api`), офіційні raw-URL власників і прямі запити до `repo.jellyfin.org`, `api.jellyfin.org`, `api.weather.gov`, `clinicaltrials.gov`. Лічильники порахувано власним скриптом (Ruby, лише читання потоку).
- Версії специфікації OpenAPI: [3.2.0](https://spec.openapis.org/oas/v3.2). Приклади 3.2: [OAI/learn.openapis.org](https://github.com/OAI/learn.openapis.org/tree/main/examples/v3.2).
- Дефекти й нормалізація: [06-spec-versions-and-defects.md](06-spec-versions-and-defects.md).

## Перший прогін `check` (2026-10-11, гілка M2, коміт 9e590a8)

Скомпільований `check`, усі 13 специфікацій за закріпленими SHA. Grace — двічі: джерело з 38 файлів і бандл.

| Специфікація | Вихід | Час | Пам'ять | Діагностика |
|---|---|---|---|---|
| Stripe | 0 | 1,04 с | 185 MB | — |
| OpenAI | 0 | 0,29 с | 119 MB | TOA021 ×1 (7 місць), TOA110 ×1 |
| Discord | 0 | 0,11 с | 85 MB | — |
| DigitalOcean | 0 | 0,02 с | 27 MB | TOA110 ×791, TOA111 ×2 |
| Medusa Store | 0 | 0,10 с | 58 MB | — |
| Grace (джерело) | 0 | 0,05 с | 54 MB | TOA111 ×16, TOA110 ×2, TOA021 ×1 |
| Grace (бандл) | 0 | 0,04 с | 46 MB | те саме, що в джерелі |
| Airflow | 0 | 0,06 с | 63 MB | — |
| Artemis | **1** | 0,01 с | 20 MB | TOA001 ×1 |
| Tambo | 0 | 0,01 с | 26 MB | — |
| Jellyfin | 0 | 0,14 с | 92 MB | — |
| Ditto | 0 | 0,04 с | 48 MB | — |
| Google Maps | 0 | 0,11 с | 87 MB | — |
| EFGS | 0 | 0,01 с | 16 MB | — |

Що знайшлося:

1. **Artemis не читається взагалі.** springdoc пише в прикладах `example: !!timestamp '2025-07-27T07:17:05.500Z'`. `package:yaml` не знає тегу YAML 1.1 `!!timestamp` і падає з TOA001. Треба: стандартні теги YAML 1.1 (`!!timestamp`, `!!binary`, `!!set`, `!!omap`) читати як рядок або значення з діагностикою-попередженням, а не відкидати документ.
2. **DigitalOcean фактично порожній.** Багатофайлова специфікація у стилі Redocly ставить `$ref` там, де OAS його не дозволяє: на рівні операції (`get: {$ref: resources/....yml}`) і замість рядка (`description: {$ref: "description.yml#/introduction"}`). Бандлери (Redocly, swagger-cli) розв'язують `$ref` будь-де, як JSON Reference. Ми ігноруємо такі ключі (TOA110), тож усі 791 операція випадають. Треба: режим «`$ref` будь-де» (підстановка до парсингу, як у бандлерів) з діагностикою на кожне нестандартне місце.
3. **Grace: справжні дефекти, діагностика правильна.**
   - `$ref: #/DifferenceType` без лапок: у YAML `#` починає коментар, тож значення стає `null`. Варто додати підказку «візьми `$ref` у лапки».
   - `oneOf: [[{$ref}]]` — список у списку.
   - Порожній `description:`.
   - `nullable` у документі 3.2.

Решта (Stripe, Discord, Medusa, Airflow, Tambo, Jellyfin, Ditto, Google Maps, EFGS) читаються без діагностики M2. Дефекти з каталогу вище (нестандартні `operationId`, відсутні `operationId`, `required` без властивості) — це рівень нормалізатора (M3), `check` M2 їх ще не шукає.
