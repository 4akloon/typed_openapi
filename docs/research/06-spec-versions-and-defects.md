# 06. Версії OpenAPI, Overlay / JSON Patch і каталог дефектів згенерованих специфікацій

> Дата дослідження: **2026-10-11**. Стосується вимог R0.1, R0.2, R1.2, R1.4, R2.1–R2.5, R3.1–R3.3, R5.x, R6.x, R8.x, R9.x, R10.x, R11.4, R12.x, R13.1, R14.1, R15.5, R15.6.
> Першоджерела: тексти специфікацій (markdown-джерела з репозиторію OAI, звірені з spec.openapis.org), RFC, документація фреймворків, GitHub issues/PR/discussions. Номери у квадратних дужках `[S#]` ведуть до розділу «Джерела».

## Коротко

- **Актуальні версії на 2026-10-11:** OAS **3.0.4** (2024-10-24), **3.1.2** (2025-09-19), **3.2.0** (2025-09-19) і **3.2.1** (2026-09-10, патч лише з уточненнями тексту). Над 3.3 працюють, дати релізу немає. Moonwalk (4.0) дати не має і може взагалі не вийти. Overlay: **1.0.0** (2024-10-17), **1.1.0** (2026-01-14, додано `copy`), **1.2.0** (2026-09-22, додано reusable actions і `$self`) [S1][S2][S3][S20][S21].
- **Специфікації, згенеровані фреймворками, змішують діалекти.** NestJS до 12.0.0 писав `nullable` у документи 3.1, а в документи 3.0 — `type: 'null'`. FastAPI з 0.134/0.135 кладе поле `itemSchema` з OAS 3.2 у документ `openapi: 3.1.0`. ASP.NET у режимі 3.0 прибирає `type` у чисел. Тому парсер має визначати діалект за вмістом, а не лише за полем `openapi` (правило `detect-schema-dialect`, SG001–SG003).
- **Головний біль — nullability.** У реальних документах вона записується щонайменше шістьма способами: `nullable`, `type: [T, null]`, `anyOf`/`oneOf` з `{type: null}`, `allOf` з одним `$ref` плюс `nullable`, `type: 'null'` поряд зі структурою, `enum` з `null`. Нормалізатор зводить усі шість до однієї канонічної форми.
- **Друге за частотою — імена.** Тут і шумні, і дубльовані, і нестабільні `operationId`, і тихі колізії схем з однаковими іменами класів. Springdoc мовчки бере першу схему з таких, тож у самій специфікації цю колізію не видно.
- **Overlay:** action, чий `target` не збігся з жодним вузлом, за специфікацією вважається **успішним**. Тому R3.2 (warning на override мертвого елемента) треба реалізувати власною діагностикою. На pub.dev немає реалізації Overlay для Dart, але є готові `json_path` (RFC 9535), `rfc_6901` і `rfc_6902` [S27][S28][S29].
- **Каталог:** у розділі C 48 дефектів з доказами, ~40 іменованих правил і схема кодів `SG0xx`–`SG8xx`. У розділі D — рецепти для NestJS, FastAPI, Spring і ASP.NET.

---

## A. Версії OpenAPI: що має вміти генератор

### A.0. Стан специфікацій і фреймворків (жовтень 2026)

| Специфікація | Дата | Статус / що важливо |
|---|---|---|
| OAS 3.0.4 | 2024-10-24 | Останній патч гілки 3.0. JSON Schema «Wright-00», власний `nullable` [S4] |
| OAS 3.1.0 / 3.1.1 / 3.1.2 | 2021-02-15 / 2024-10-24 / 2025-09-19 | JSON Schema 2020-12, діалект `https://spec.openapis.org/oas/3.1/dialect/base` [S5] |
| OAS 3.2.0 | 2025-09-19 | Стріми (`itemSchema`), QUERY, `additionalOperations`, `in: querystring`, теги-ієрархії, `defaultMapping` [S1] |
| OAS 3.2.1 | 2026-09-10 | «No significant changes»: уточнено Style Examples, заборонено комбінації `in: cookie, style: form, explode: false` для масивів і об'єктів та `style: form, explode: true` для масивів і об'єктів у Encoding, уточнено `prefixEncoding`/`itemEncoding`, матчинг шаблонів шляху з `/` [S2] |
| OAS 3.3 | — | В роботі. У червні 2026 дати не було, ціль «3 вересня» знято [S22] |
| Overlay 1.0 / 1.1 / 1.2 | 2024-10-17 / 2026-01-14 / 2026-09-22 | Див. розділ B [S3] |

Правило версіонування OAS: «The patch version SHOULD NOT be considered by tooling» [S1, Versions and Deprecation]. Отже, генератор розрізняє лише `3.0`, `3.1` і `3.2`, а `3.1.0`/`3.1.1`/`3.1.2` обробляє однаково.

Яку версію за замовчуванням видають фреймворки:

| Фреймворк | Версія за замовчуванням | Примітка |
|---|---|---|
| NestJS `@nestjs/swagger` | `3.0.0` | `DocumentBuilder.setOpenAPIVersion('3.1.0' / '3.2.0')`. З 12.0.0 (2026-08-27) nullability записується відповідно до оголошеної версії [S30][S31] |
| FastAPI | `3.1.0` (з 0.99.0) | 0.134.0 (2026-02-27) — JSONL з `itemSchema`; 0.135.0 (2026-03-01) — SSE з `itemSchema`, але `openapi` лишається `3.1.0` [S32][S33] |
| springdoc-openapi | `3.1` (з 2.8.0, 2025-01-03, «Moving to OpenAPI 3.1 as the default») | `springdoc.api-docs.version=openapi_3_0` повертає 3.0 [S40][S41] |
| Swashbuckle.AspNetCore | `3.0` | З v10+ можна ввімкнути 3.1 через `UseSwagger(o => o.OpenApiVersion = OpenApi3_1)` [S50] |
| Microsoft.AspNetCore.OpenApi | .NET 10: `3.1`; .NET 9: `3.0` | `OpenApiOptions.OpenApiVersion` [S52] |

### A.1. 3.0.x → 3.1.x

Позначення впливу: **P** — парсинг/нормалізація, **M** — внутрішня модель, **C** — кодоген. Пріоритет: **must** / **should** / **later**.

| # | Зміна | 3.0.x | 3.1.x | Вплив на генератор | Пріор. | R |
|---|---|---|---|---|---|---|
| 1 | `nullable` прибрано | `type: string`, `nullable: true`; діє лише разом із `type` [S4] | `type: [string, "null"]` або `anyOf`/`oneOf` з `{type: "null"}` [S6] | P: усі форми зводяться до канонічного `nullable` у моделі. M: nullability — властивість посилання на тип, а не самого типу | must | R6.1 |
| 2 | `type` може бути масивом | лише рядок («Multiple types via an array are not supported») [S4] | `type: [string, integer]` | P/M: мульти-тип → union-обгортка (R9.3), окремий випадок `[T, null]` | must | R9.3 |
| 3 | `const` | немає | є (JSON Schema) | P: `const` → enum з одного значення. Важливо для дискримінаторів pydantic (див. C-14) | must | R8, R9 |
| 4 | `examples` у Schema | лише `example` | `examples: [...]` (масив). `example` — Deprecated [S5] | P: обидва зводяться до doc-метаданих, на типи не впливають | should | R13.4 |
| 5 | `$ref` із сусідніми ключами | Reference Object: «any properties added SHALL be ignored» [S4] | У Schema Object `$ref` — звичайний ключ JSON Schema, сусідні ключі застосовуються разом із ним. Reference Object поза схемами може мати лише `summary`/`description` [S5] | P/M: `{$ref: X, description}` → тип X з описом. `{$ref: X, properties: …}` → фактично `allOf` | must | R6.3 |
| 6 | `items` масивом → `prefixItems` | `items` — лише об'єкт і обов'язковий для `type: array` [S4] | `prefixItems` (кортежі), `items` після префікса, `items: false`. `items` більше не обов'язкове | M/C: кортеж → Dart record або `List<JsonValue>`. Відсутнє `items` → `List<JsonValue>` | should | R6.2 |
| 7 | `exclusiveMinimum`/`exclusiveMaximum` | boolean-модифікатори до `minimum`/`maximum` | числа: `exclusiveMinimum: 7` [S7] | P: конвертація в обидва боки. Метадані обмежень (R6.7) | should | R6.7 |
| 8 | Бінарні дані | `type: string`, `format: binary` / `byte` | `contentMediaType` / `contentEncoding: base64`; сире тіло — порожня схема [S5][S7] | P: канонічне `Binary` / `Base64`. У multipart файл = `contentMediaType` без `contentEncoding` | must | R6.2, R10.4 |
| 9 | `contentSchema` | немає | схема для вмісту рядка (наприклад, JSON у рядку) | M: потрібно для SSE `data` (A.2 №2) | must (для SSE) | R12.2 |
| 10 | `$id`, `$anchor`, `$defs`, `$schema` | немає | є. `$id` змінює базовий URI для `$ref` | P: резолвер `$ref` має враховувати `$id`/`$anchor` (R1.2) | should | R1.2 |
| 11 | `$dynamicRef` / `$dynamicAnchor` | немає | «Generic (Template) Data Structures» [S5] | M: природне джерело дженериків (R6.4). На практиці фреймворки його не генерують | later | R6.4 |
| 12 | `jsonSchemaDialect`, `$schema` у схемах | немає | інший діалект за замовчуванням | P: якщо діалект не OAS-base і не 2020-12 — warning SG004 | should | R2.2 |
| 13 | `unevaluatedProperties`, `unevaluatedItems`, `dependentRequired`, `dependentSchemas`, `if`/`then`/`else`, `patternProperties`, `propertyNames`, `contains` | немає (або «strictly unsupported») | є | P: зберегти як метадані. C: не впливають на форму типу, крім `unevaluatedProperties: false` ≈ закритий об'єкт. `if`/`then`/`else` → info «не моделюється» | later | R2.5 |
| 14 | Boolean-схеми `true`/`false` | немає | є | P: `true` → JSON value, `false` → «never» (поле не генерується + info) | must | R6.2 |
| 15 | Discriminator | лише з `oneOf`/`anyOf`/`allOf`, властивість MUST бути required | те саме. `mapping` — ім'я компонента або URI. Inline-підсхеми не враховуються в implicit mapping [S5] | M: implicit mapping = ім'я компонента. Для inline-варіантів потрібен явний `mapping` або override | must | R9.1 |
| 16 | Annotated enumerations | — | `oneOf`/`anyOf` з елементів `{const, title, description}` можна трактувати як enum з описами (implementation-defined) [S5] | P: розпізнавати як enum з doc-рядками (R8.4) | should | R8.4 |
| 17 | `webhooks` | немає | `webhooks: {name: PathItem}` | C: клієнту не потрібен, але моделі payload можна згенерувати для обробника | later | — |
| 18 | `components.pathItems` | немає | є. Path Item `$ref` на компонент | P: резолвити | must | R1.2 |
| 19 | `paths` і `responses` необов'язкові | обидва REQUIRED | обидва optional [S5] | P: операція без `responses` → результат `void`/сире тіло + info | must | R10.6 |
| 20 | `requestBody` у GET/HEAD/DELETE | «SHALL be ignored by consumers» [S4] | «permitted but … SHOULD be avoided» [S5] | C: для 3.1 генерувати тіло і в GET/DELETE (Dio це дозволяє) | should | R10.4 |
| 21 | `readOnly`/`writeOnly` | `readOnly` + `required` → required лише у відповіді | анотації. «behavior of readOnly … differs from 3.0» [S5] | M: матриця required × nullable × напрям (R6.1) | must | R6.1 |
| 22 | `info.summary`, `license.identifier`, тип безпеки `mutualTLS` | немає | є | C: лише метадані / doc | later | R10.8 |

### A.2. 3.1.x → 3.2.x

Колонка «Для клієнта?» показує, чи впливає зміна на згенерований клієнт.

| # | Зміна в 3.2 | Суть (з тексту специфікації) | Для клієнта? | Вплив | Пріор. | R |
|---|---|---|---|---|---|---|
| 1 | `itemSchema` у Media Type Object | «A schema describing each item within a sequential media type». На відміну від `schema` застосовується до кожного елемента стріму окремо [S1 §Media Type] | **так** | P/M: окрема модель «стрім елементів типу T». C: метод повертає `Stream<T>` | **must** | R1.4, R12.1 |
| 2 | Послідовні media types | `application/jsonl`, `application/x-ndjson`, `application/json-seq`, `application/geo+json-seq`, `text/event-stream`, `multipart/mixed`. «MUST support mapping … as if the values were in an array» [S1] | **так** | C: SSE — R12; JSONL/NDJSON — R12.6 | must (SSE), later (JSONL) | R12 |
| 3 | Особливості SSE | Дані парсяться за WHATWG: коментарі ігноруються, багаторядкові `data` склеюються. `retry` — integer, решта полів — рядки. Для JSON у `data` використовуються `contentMediaType` + `contentSchema`. Спека дає типову схему події: `data` (required), `event`, `id`, `retry` [S1 §Special Considerations for SSE] | **так** | M: подія = `{event, id, retry, data: T}`, де T береться з `contentSchema`. Дискримінація за `event` через `oneOf` з `const` (приклад у спеці) | **must** | R12.2, R12.3 |
| 4 | `prefixEncoding` / `itemEncoding` | Позиційне кодування `multipart`. `encoding` з ними несумісне [S1] | так, рідко | C: позиційний `multipart/mixed` | later | R10.4 |
| 5 | Метод `QUERY` | поле `query` у Path Item (draft-ietf-httpbis-safe-method-w-body) [S1] | **так** | C: `Options(method: 'QUERY')` у Dio + тіло запиту | should | R10 |
| 6 | `additionalOperations` | Map: HTTP-метод з точним регістром → Operation. Не може дублювати стандартні методи [S1] | **так** | C: довільні методи (`PURGE`, `COPY`). Ім'я методу — з `operationId` | should | R10 |
| 7 | `in: querystring` | Увесь query-рядок як одне значення через `content` (зазвичай `application/x-www-form-urlencoded`). Не більше одного на операцію, несумісне з `in: query` [S1] | **так** | C: параметр-об'єкт, що серіалізується в повний query | should | R10.3 |
| 8 | `style: cookie` і pass-through для header/cookie | `cookie` — як `form`, але за RFC 6265 (`n1=v1; n2=v2`) і без percent-encoding. Значення header і cookie передаються «unchanged» [S1] | так | C: серіалізатор cookie. Не екранувати header-значення | should | R10.3 |
| 9 | `allowEmptyValue` | Deprecated [S1] | ні | P: прийняти, вивести info | later | — |
| 10 | Tag `summary`, `parent`, `kind` | Ієрархія тегів (замість `x-tagGroups`) і категорія (`nav`, `badge`, `audience`). `parent` MUST існувати, цикли заборонені [S1] | частково | C: групування класів (R5.3): `parent` → простір імен чи вкладене групування; `kind: badge`/`audience` → фільтр (R4.1) | should | R5.3, R4.1 |
| 11 | `discriminator.defaultMapping` | Дискримінуюча властивість MAY бути optional, і тоді `defaultMapping` MUST. `defaultMapping` також ловить незамаплені значення [S1 §Discriminator] | **так** | M/C: замість «unknown»-варіанта або на додачу до нього — варіант за `defaultMapping` | **must** | R9.1 |
| 12 | `$self` | Самопризначений URI документа, база для `$ref`. «references MUST use the target document's `$self` URI if present» [S1] | так (резолвінг) | P: базовий URI при резолвінгу `$ref` між файлами | should | R1.2 |
| 13 | `components.mediaTypes`, `$ref` на Media Type Object | Перевикористовувані Media Type Objects [S1] | так | P: резолвер | must | R1.2 |
| 14 | Example Object `dataValue` / `serializedValue` | `value` — «Deprecated for non-JSON serialization targets». `example` і `examples` взаємовиключні [S1] | ні (лише doc) | P: прийняти. C: doc-приклади | later | R13.4 |
| 15 | Response `summary`; `description` більше не REQUIRED | У 3.0/3.1 `description` — REQUIRED [S1][S4][S5] | ні | P: не падати на відсутньому `description` (для 3.0/3.1 лише info) | must (толерантність) | R2.1 |
| 16 | Безпека: OAuth Device flow (`deviceAuthorization`, `deviceAuthorizationUrl`), `oauth2MetadataUrl`, `deprecated` у Security Scheme, посилання на схему безпеки через URI [S1] | — | так (метадані) | C: метадані для інтерсепторів (R10.8). `deprecated` → `@Deprecated` у doc | should | R10.8 |
| 17 | Server `name`; `url` без query і fragment | — | частково | C: іменовані сервери в R10.9 | later | R10.9 |
| 18 | XML `nodeType`; `attribute`/`wrapped` Deprecated | — | ні (XML поза скоупом) | P: прийняти | later | R0.3 |
| 19 | Моделювання `Set-Cookie` та `Link` у Header Object | — | частково | C: доступ до заголовків (R10.6) | later | R10.6 |
| 20 | Ключі `content` у відповіді — діапазони media type («most specific key applies», `text/plain` переважає `text/*`) | є і в 3.1 | так | C: вибір декодера за найспецифічнішим ключем | must | R10.6 |

**Що з 3.2 вже трапляється в реальних документах:**
- FastAPI видає `itemSchema` для JSONL і SSE, причому `data` описується як `{type: string, contentMediaType: application/json, contentSchema: <Item>}` [S32][S34].
- NestJS дає задати теги з `parent`/`kind`/`summary` через `setOpenAPIVersion('3.2.0')` [S35].
- Swagger UI/Editor підтримують 3.2 з квітня 2026 [S23].

### A.3. Що з цього випливає для архітектури парсера

1. **Внутрішня модель — надмножина 3.2.** Документи 3.0 і 3.1 піднімаються до неї, і далі все працює з однією моделлю. 3.2 не має breaking changes відносно 3.1 [S24], тож надмножина безпечна.
2. **Діалект схем визначається за вмістом.** Заголовок `openapi` задає лише значення за замовчуванням. Якщо в документі 3.0 трапилися `type`-масив, `{type: 'null'}`, `const`, `prefixItems` чи `examples`-масив, схема читається як 2020-12, а користувач отримує діагностику SG001. І навпаки: `nullable` у документі 3.1 дає SG002 (див. C-16, C-17).
3. **Канонічна nullability.** Модель зберігає `nullable` як ознаку посилання на тип: поля, елемента масиву, значення map. Шість вхідних спельнгів зводяться до неї правилами `nullable-*` (розділ C).
4. **Невідомі ключі JSON Schema не губляться.** Вони зберігаються як метадані (R6.7). Якщо ключ впливає на форму типу (`if`/`then`/`else`, `dependentSchemas`), видається info з пропозицією override (R2.5).
5. **Патч-версія ігнорується** [S1]: `3.1.0`/`3.1.1`/`3.1.2` обробляються однаково, `3.2.0`/`3.2.1` — теж.

---

## B. Стандарти патчів і overlay (R3.3) та JSON Pointer для діагностики (R2.2)

### B.1. OpenAPI Overlay Specification

**Структура (1.2.0)** [S3]:

```yaml
overlay: 1.2.0                 # REQUIRED; версія Overlay, а не OpenAPI
$self: https://example.com/fix.overlay.yaml   # 1.2+, без fragment
info: {title: ..., version: ..., description: ...}  # description з'явився в 1.1+
extends: ./openapi.yaml        # optional: цільовий документ (з 1.2 — без fragment)
actions:                       # REQUIRED, ≥1, застосовуються ПОСЛІДОВНО
  - target: "$.paths['/users/{id}'].get"   # RFC 9535 JSONPath
    description: ...
    update: {operationId: getUser}         # merge
  - target: "$.paths.*.get.parameters[?@.name == 'dummy']"
    remove: true
  - target: "$.components.schemas['Bar']"
    copy: "$.components.schemas['Foo']"    # 1.1+
  - $ref: '#/components/actions/addErrorResponses'  # 1.2+ reusable action
    target: "$.paths.*.*.responses"
components:                    # 1.2+
  actions:
    addErrorResponses:
      description: ...
      fields: {update: {...}}  # будь-які поля Action, окрім target
```

**Семантика**, за текстом 1.2.0 [S3]:
- Actions застосовуються по черзі. Кожна діє на результат попередньої.
- `update`, якщо `target` — об'єкти: рекурсивний merge. Примітив замінює примітив, масив **конкатенується** з масивом, об'єкт зливається рекурсивно, інші комбінації дають помилку. Якщо `target` — масиви: значення-масив конкатенується, а об'єкт чи примітив додається в кінець. Якщо `target` — примітиви: значення замінюється (з 1.1; в 1.0 ціль MUST бути об'єктом або масивом [S20]).
- `remove: true` видаляє вузол із map або масиву. `update` і `copy` при цьому ігноруються.
- `copy` (1.1+) — JSONPath на **один** вузол-джерело. Merge відбувається за тими самими правилами. Пара `update` (створити порожню ціль) + `copy` + `remove` дає «move», тобто перейменування [S3][S25].
- Якщо `target` вибрав **0 вузлів**, «the action succeeds without changing the target document». Якщо вузлів ≥2, усі вони мусять бути одного виду (об'єкти, масиви або примітиви).
- JSONPath MUST бути повною реалізацією RFC 9535 без розширень окремих інструментів. При переході на 1.1 довелося переписати вирази: `@['x-oai-traits']` замість `@.x-oai-traits`, а неіснуючий у RFC оператор `in` — замінити фільтром [S3][S25].
- Коментарі YAML можуть загубитися.

**Обмеження, важливі для нас:**

| Обмеження | Наслідок для R3.x | Що робимо |
|---|---|---|
| 0 збігів = тихий успіх | Суперечить R3.2 (override мертвого елемента має давати warning) | Рахуємо збіги для кожної action і при 0 видаємо **SG802 warning** |
| Немає `test` чи передумов | Не видно, що бекенд уже виправив дефект | Після action порівнюємо документ «до» і «після». Якщо він не змінився — **SG803 info**: «override можна прибрати» (R3.2) |
| Масиви лише конкатенуються | Масив (`required`, `enum`) не замінити одним `update` | `remove` на елемент масиву (1.1+ для примітивів) + `update` або `remove` всього масиву + `update` батька. Наш формат override (R3.1) має власну операцію «set» |
| Ключі map не перейменовуються | Перейменування схеми через overlay виходить незграбним | `copy` + `remove` (1.1+). Наш override `rename` перейменовує логічне ім'я в моделі, а не ключ у документі |
| Неможливо адресувати «логічні» сутності (operationId, ім'я параметра) інакше ніж фільтром | Override на кшталт «операція X» в overlay крихкий | Наш формат override адресує логічно (R3.1). Overlay — лише як альтернативний вхід (R3.3) |
| Рядки JSONPath відрізняються між старими бібліотеками | Overlay, написаний під Speakeasy-alpha, може не працювати в нас | Строгий RFC 9535 + діагностика з позицією помилки у виразі |

**Хто реалізує Overlay** (станом на жовтень 2026):

| Інструмент | Мова / тип | Версія Overlay / примітки |
|---|---|---|
| Speakeasy (`speakeasy overlay apply / compare / validate`; Go: `speakeasy-api/openapi` → пакет `overlay`, раніше `openapi-overlay`) | Go, CLI | 1.0+. `compare` будує overlay з різниці двох специфікацій [S26] |
| Bump.sh (`bump overlay`, `bump deploy --overlay`) | CLI | Можна використовувати без підписки [S26] |
| oapi-codegen | Go codegen | Overlay для вхідної специфікації з v2.4.0 (2024-09-20) [S26][S36] |
| libopenapi (pb33f) | Go | З v0.31, відповідає 1.1.0 [S26] |
| Redocly CLI | Node | Типи і лінт Overlay — з 2024–2025. **Застосування overlay в `bundle`** — з `@redocly/cli@2.56.0` (2026-09-30) [S37] |
| openapi-format | npm | Застосування + GUI-playground [S26] |
| oas-patch | Python | Overlay **і** JSON Patch [S26] |
| BinkyLabs.OpenApi.Overlays | .NET | 1.0 і 1.1; кілька overlay, порядок має значення [S26] |
| openapi-overlays-js (Lorna Mitchell) | JS-бібліотека | Еталонна JS-реалізація [S26] |
| IBM oas-overlay-java, roas-overlay (Rust), Zuplo CLI, Zudoku | різні | [S26] |
| **Dart** | — | Реалізацій Overlay на pub.dev не знайдено (пошук 2026-10-11). Будівельні блоки: `json_path` 0.9.0 (RFC 9535, 160/160 pub points), `rfc_6901` 0.2.1, `rfc_6902` 0.3.1 (обидва — той самий автор f3ath) [S27][S28][S29] |

### B.2. JSON Patch (RFC 6902)

- Документ — масив операцій, що виконуються по черзі. Кожна має `op` і `path` (JSON Pointer) [S9 §3–4].
- Операції: `add` (замінює наявний член; `-` у кінці шляху означає «додати в кінець масиву»; батько MUST існувати), `remove` (ціль MUST існувати), `replace` (ціль MUST існувати), `move` (`from` не може бути префіксом `path`), `copy`, `test` (порівняння з урахуванням типу: `10` ≠ `"10"`) [S9 §4.1–4.6].
- **Атомарність:** якщо будь-яка операція падає, документ не змінюється взагалі («HTTP PATCH is atomic») [S9 §5]. Media type — `application/json-patch+json`.

**Для R3.3:** JSON Patch точніший за overlay, бо адресує конкретний вузол, і має `test`, тобто передумову. Проте:
1. **Атомарність суперечить R3.2.** Наприклад, `remove` неіснуючого шляху має давати warning, а не валити генерацію. Тому операції виконуються по одній у «м'якому» режимі: невдала операція стає warning SG801, решта застосовуються. Строгий режим вмикається опційно.
2. **Індекси масивів крихкі** (`/parameters/2`). Варто попереджати (info) про патчі з числовими індексами в `parameters`/`allOf`/`oneOf` і пропонувати логічну адресацію з нашого формату.
3. **`test` дає R3.2 безкоштовно.** Якщо `test` на «дефектне» значення падає, дефект уже виправлено. Тоді SG803: «патч більше не потрібен».

### B.3. JSON Pointer (RFC 6901) для діагностики (R2.2)

- Екранування в reference token: `~` → `~0`, `/` → `~1` [S8 §3].
- **Порядок декодування:** спочатку `~1` → `/`, потім `~0` → `~`, щоб `~01` правильно розкодувалося в `~1` [S8 §4].
- У URI fragment символи, які не дозволені правилом `fragment` (RFC 3986), percent-кодуються [S8 §6]. Еталонний приклад зі специфікації OAS: `#/paths/~12.0~1repositories~1%7Busername%7D/get` [S1 §Link Object]. Тут `{` і `}` закодовано як `%7B`/`%7D`.
- `-` як індекс масиву — завжди помилка при обчисленні (лише для `add` у JSON Patch) [S8 §4].

**Приклади для наших діагностик:**

| Місце | JSON Pointer (рядкова форма) | URI fragment |
|---|---|---|
| Операція `GET /users/{id}` | `/paths/~1users~1{id}/get` | `#/paths/~1users~1%7Bid%7D/get` |
| Схема тіла JSON | `/paths/~1users/post/requestBody/content/application~1json/schema` | `#/paths/~1users/post/requestBody/content/application~1json/schema` |
| Властивість з `~` у назві | `/components/schemas/A/properties/a~0b` | те саме |

**Рекомендації:**
1. Діагностика містить **рядкову форму** pointer-а (стабільну, читабельну), а також файл і `line:col` з YAML/JSON-парсера (source map). Для посилань будується fragment-форма.
2. Pointer вказує на місце в **оригінальному** документі, а не на нормалізований результат: R2.2 вимагає пояснити, що виправити в джерелі. Тому нормалізатор зберігає source map: який вузол з якого виник.
3. **Ключ для baseline (R2.3)** будується як `code + семантичний якір`, а не як «сирий» pointer. Індекси масивів (`/parameters/3`, `/oneOf/1`) змінюються при перестановках, тому для елементів масивів якорем є логічний ключ: параметр — `name+in`, варіант — `$ref`-ціль або хеш вмісту.
4. Для `$ref` між файлами формат такий: `relative/file.yaml#/json/pointer`, де шлях до файлу береться відносно кореня конфігу (R13.1 — без абсолютних шляхів).

---

## C. Каталог дефектів у специфікаціях, згенерованих з коду (R2.1)

### C.0. Легенда

**Коди діагностики (пропозиція):**

| Діапазон | Область |
|---|---|
| `SG0xx` | Документ, версія, діалект |
| `SG1xx` | Посилання (`$ref`), структура, ключі components |
| `SG2xx` | Схеми й типи: nullable, required, format, default |
| `SG3xx` | Enum |
| `SG4xx` | Поліморфізм, дискримінатори |
| `SG5xx` | Операції, параметри, іменування |
| `SG6xx` | Media types, тіла, стріми, помилки |
| `SG7xx` | Детермінізм / стабільність виходу |
| `SG8xx` | Override, overlay, patch (R3.2) |

**Рівень** — рівень за замовчуванням. Після автоматичного виправлення error можна знизити до warning (налаштовується, R2.2).
**Auto-fix:** **так** — правило виправляє однозначно; **частково** — виправляє з типовим припущенням, і результат варто підтвердити override-ом; **ні** — тільки діагностика і пропозиція override (R2.5).

### C.1. Каталог

| # | Дефект | Фреймворки | Приклад | Докази | Правило нормалізатора | Код / рівень | Auto-fix |
|---|---|---|---|---|---|---|---|
| 1 | `required: true/false` (boolean) всередині схеми властивості | Ручні правки, анотаційні генератори, конвертація зі Swagger 2. У 4 цільових фреймворках за замовчуванням не відтворюється | `name: {type: string, required: true}` | openapi-generator падає з «required is not of type `array`» [S60]; така сама помилка в JSON-схемах MCP [S61] | `bool-required-to-array`: `true` → ім'я додається в `required[]` батька, `false` → прибирається | SG201 / warning | так |
| 2 | Порожній або обрізаний `$ref` | Анотаційні генератори; у TS — цикли імпортів (тип `undefined`) | `$ref: '#/components/schemas/'` | L5-Swagger [S62]; NestJS: цикл → тип `undefined` [S63] | `empty-ref-to-any`: замінити на JSON value + пропозиція override типу | SG101 / error | частково |
| 3 | Висячий `$ref` (цілі не існує) | NestJS (модель не зареєстрована через `@ApiExtraModels`; рекурсія з `@ApiSchema({name})` дає `$ref` на ім'я класу; CLI-плагін губить моделі з workspace-пакетів), springdoc (за замовч. **видаляє** «broken reference definitions») | `$ref: '#/components/schemas/MenuNodeDto'` при схемі `MenuNode` | [S64] nestjs/swagger#3368; [S65] #4006; NestJS docs «extra models» [S35]; springdoc `remove-broken-reference-definitions=true` [S41] | `dangling-ref-to-any` (opt-in), інакше error | SG102 / error | частково |
| 4 | `discriminator.mapping` вказує на неіснуючий компонент | FastAPI 0.128.0: однойменні моделі з різних модулів | `mapping: {x: '#/components/schemas/Variant'}`, а компоненти — `…__Variant` | fastapi discussion #14737 [S38] | `discriminator-mapping-repair`: якщо рівно один варіант `oneOf` має `const`/`enum` = ключ, переприв'язати на нього | SG103 / error | частково |
| 5 | Масив без `items` | Загальне (NestJS — дженерики або `type: Array` без явного типу; specs великих API) | `tags: {type: array}` | OpenAI spec: «items is missing», openapi-generator: «Undefined array inner type … Default to String» [S66]; NestJS docs «Generics and interfaces» [S35]; OAS 3.0.4: «`items` MUST be present if type is array» [S4] | `array-items-default`: `items: {}` → `List<JsonValue>` | SG202 / warning (3.0), info (3.1) | так |
| 6 | Неоголошені path-параметри | NestJS (вкладені роутери, префікс з параметром), FastAPI (параметр у `APIRouter(prefix='/abc/{arg1}')`, який handler не приймає) | `/pets/{context}/cat/{name}` без `context` у `parameters` | nestjs/swagger#1368 [S67]; fastapi discussion #12081 [S39]; OAS: `name` для `in: path` MUST відповідати шаблону [S1] | `declare-missing-path-params`: `{name, in: path, required: true, schema: {type: string}}` | SG504 / error | так |
| 7 | Path-параметр оголошено, але в шаблоні його немає або регістр інший | Загальне (перейменування в коді) | `in: path, name: userId` при `/users/{id}` | Вимога OAS [S1] | — (не вгадуємо, R2.5) → override | SG505 / error | ні |
| 8 | `examples` (масив) у Schema документа 3.0, або `example` у 3.1 | FastAPI з примусовим `openapi_version="3.0.x"` (pydantic `Field(examples=…)`), ручні правки | `schema: {type: string, examples: [a, b]}` при `openapi: 3.0.3` | OAS 3.0.4: «Additional keywords … strictly unsupported» [S4]; OAS 3.1: `example` Deprecated [S5]; FastAPI docs про `examples` у 3.1 [S42] | `schema-examples-by-version`: у 3.0 `examples[0]` → `example`; у 3.1 `example` → `examples: [..]` | SG213 / info | так |
| 9 | Дублікати значень enum | Go/swaggo та інші. Також дублікати, що відрізняються лише регістром | `enum: [user, admin, user]` | homebox#1175 [S68] | `dedupe-enum-values` (лишається перше входження, порядок стабільний) | SG301 / warning | так |
| 10 | Різні значення enum дають однаковий Dart-ідентифікатор після санітизації | Загальне | `enum: ['1', '-1']` → `_1` двічі | openapi-generator#7288 [S69] | (іменування, R5.2) детермінований суфікс | SG302 / warning | так |
| 11 | Inline-enum дублюється в кожному місці використання | NestJS без `enumName`; springdoc без `enumAsRef`; Swashbuckle з `UseInlineDefinitionsForEnums` | `breed: {type: string, enum: [Persian, …]}` у двох DTO → `CatDetailEnum` і `CatInformationEnum` | NestJS docs «Enums schema» [S35]; springdoc FAQ [S43] | `dedupe-inline-enums`: однаковий тип і набір значень → один Dart-enum, ім'я з контексту або override (R5.4) | SG303 / info | так |
| 12 | Числові enum без імен | ASP.NET без `JsonStringEnumConverter` (обидва генератори); іноді з `x-enumNames` (стиль NSwag) | `type: integer, enum: [0, 1, 2]` | MS docs: «An enum type without a [JsonConverter] will be defined as type: integer» [S52]; dart-dio ігнорує `x-enumNames` [S70] | `enum-varnames-from-extensions` (`x-enum-varnames`, `x-enumNames`, `x-enum-names`), інакше `value0…` + підказка | SG304 / info | частково |
| 13 | Nullable enum губить `null` | NestJS ≤11 (`enumName` + `nullable`), Microsoft.AspNetCore.OpenApi (`null` у `enum` залежить від порядку параметрів; компонент enum змінюється залежно від nullability посилання) | `$ref: PaymentTerms` + `nullable: true` → генератор дає non-null | nestjs/swagger#1889 [S71]; aspnetcore#65017, #67557 [S53] | `nullable-enum-normalize`: nullability переноситься на посилання, `null` прибирається з набору значень компонента | SG305 / warning | так |
| 14 | Одне значення через `const` замість `enum` (`Literal['cat']`) | FastAPI / pydantic v2 | `pet_type: {const: cat, type: string}` | pydantic `literal_schema`: одне значення → `const`, кілька → `enum` [S44] | `const-to-enum` (з урахуванням ролі дискримінатора) | SG306 / info | так |
| 15 | Flags-enum як `type: string` без `enum` | ASP.NET (`[Flags]` + `JsonStringEnumConverter`) | `"Pepperoni, Sausage"` | MS docs [S52] | — (override на `Set<Enum>` або `String`) | SG307 / info | ні |
| 16 | `nullable` (3.0) у документі 3.1 | NestJS ≤11.x з `setOpenAPIVersion('3.1.0')` | `{type: string, nullable: true}` при `openapi: 3.1.0` | nestjs/swagger#4063; виправлено в 12.0.0 [S30][S31] | `nullable-to-type-null`: у 3.1 `nullable: true` трактується як union з `null` | SG002 / warning | так |
| 17 | Конструкції 3.1 у документі 3.0 (type-масиви, `{type: 'null'}`, `const`, `examples`, числовий `exclusiveMinimum`) | NestJS (type-масиви; з #3897 до 12.0.0 — `oneOf: [X, {type: 'null'}]` у 3.0), FastAPI з примусовим `openapi_version="3.0.x"` | `additionalProperties: {type: [string, boolean]}` при `openapi: 3.0.0` | nestjs/swagger#1880 [S72]; NestJS 12.0.0 notes [S31]; fastapi discussion #9789 [S39] | `detect-schema-dialect`: парсинг за фактичним вмістом (superset) | SG001 / warning | так |
| 18 | `nullable: true` поряд з `allOf`/`$ref` без `type` (3.0) | NestJS (плагін, TS-union `UserDto` або `null`), Swashbuckle (`UseAllOfToExtendReferenceSchemas`) | `{nullable: true, allOf: [{$ref: UserDto}]}` | nestjs/swagger#3274 (Redocly: «type must be defined when nullable is used») [S73]; OAS 3.0.4: `nullable` «only takes effect if type is explicitly defined» [S4] | `nullable-ref-to-union`: трактується як nullable-посилання (R6.3) | SG203 / warning | так |
| 19 | `type: 'null'` поряд зі структурою або як єдиний тип для «any» | springdoc 2.8.17 і 3.1.0 (`Any?`), Swashbuckle v10 (`type: 'null'` + `allOf`) | `{type: 'null', properties: {…}}`; `anyName: {type: 'null'}` | springdoc#3275, #3338 [S45]; Swashbuckle#3649 [S54]; openapi-generator 7.26 падає на `type: 'null'` [S74] | `null-type-with-structure-to-nullable`: структура + null → nullable структура; самотній `type: 'null'` у полі → nullable JSON value + warning | SG204 / warning | частково |
| 20 | Optional через `anyOf`/`oneOf: [X, {type: 'null'}]` | FastAPI / pydantic v2; .NET 10 (`oneOf` для complex-типів); NestJS 12 (`anyOf` для `$ref`) | `last_name: {anyOf: [{type: string}, {type: 'null'}]}` | swagger_parser#84 (Dart-генератор виводив `Object`) [S75]; MS docs «nullable complex types» [S52]; NestJS 12.0.0 [S31] | `anyof-null-to-nullable` (канонізація; не дефект, але критично для Dart) | — (info, якщо гілок не-null >1 → R9.3) | так |
| 21 | `allOf` з одним `$ref` лише для того, щоб додати `description`/`nullable` | NestJS, Swashbuckle (`UseAllOfToExtendReferenceSchemas`) | `{description: '…', allOf: [{$ref: SecondLevelDTO}]}` | nestjs/swagger#3311 [S76] | `unwrap-single-allof-ref` (R6.3) | SG206 / info | так |
| 22 | Суперечливий `type` поряд з комбінатором | NestJS (`oneOf` + `nullable` → лишається `type: object`), .NET (базовий тип з `type: object` + `anyOf`) | `{type: object, nullable: true, oneOf: [{type: string}, {type: number}]}` | nestjs/swagger#3928 [S77]; aspnetcore#60469 [S53] | `drop-contradictory-type`: якщо жодна гілка не object, `type` прибирається | SG205 / warning | так |
| 23 | Числа як `type: [integer, string]` + `pattern`; у режимі 3.0 — **без `type`**, лише `format`/`pattern` | Microsoft.AspNetCore.OpenApi (.NET 9/10, через `JsonNumberHandling.AllowReadingFromString` за замовчуванням) | `{type: [integer, string], format: int32, pattern: …}` | aspnetcore#61038, #64920 [S53]; MS docs: для 3.0 «the type field is dropped» [S52] | `numeric-string-union-to-number` + `infer-type-from-format` (`int32`/`int64` → integer, `float`/`double` → number) | SG208 / info; SG207 / warning | так |
| 24 | Decimal як `format: double` або `anyOf: [number, string(pattern)]` | ASP.NET (`decimal` → `number`/`double`), pydantic `Decimal` (`anyOf` у validation-режимі, рядок — у serialization) | `price: {anyOf: [{type: number}, {type: string, pattern: …}]}` | MS docs, таблиця типів [S52]; pydantic `decimal_schema` [S44] | `decimal-detect` → тип із конфігу (R6.2, `Decimal`) | SG209 / info | частково |
| 25 | Схема без типу або `type: object` без властивостей для any / union / interface | NestJS (reflect-metadata дає `Object` для union та інтерфейсів), ASP.NET (`object`/`dynamic` → `type` опущено), springdoc (`use-arbitrary-schemas`) | `meta: {type: object}`; `payload: {}` | nestjs/swagger#3928 [S77]; MS docs [S52]; springdoc properties [S41] | `untyped-to-json-value` (R6.2: окремий JSON-тип, а не `dynamic`) | SG210 / info | так |
| 26 | Словник без `additionalProperties` | NestJS (`Record<string, X>`, `{[k: string]: X}`) | `colors: {type: object}` | nestjs/swagger#1771 [S78] | — → `Map<String, JsonValue>` + override `additionalProperties` | SG211 / info | ні |
| 27 | Об'єктна схема без `type: object` | springdoc (`explicit-object-schema=false` за замовч.), похідні типи в .NET | `FooBar: {required: [value], properties: {…}}` | springdoc properties [S41]; aspnetcore#60469 [S53] | `infer-object-type` (є `properties`/`required` → object) | — / info | так |
| 28 | `default` не відповідає типу; «динамічні» default | Великі ручні specs; NestJS (`new Date()` у default → diff при кожному запуску) | `default: ''` для `array` | openai-openapi#453 [S66]; nestjs/swagger#3541 і `excludeDynamicDefaults` [S35] | `drop-invalid-default` | SG212 / warning | так |
| 29 | Пари `X-Input` / `X-Output` | FastAPI + pydantic v2 (`separate_input_output_schemas=True` за замовч.; регресія 0.119.0 — розщеплення через enum) | `Item-Input` (`description` optional) / `Item-Output` (required) | FastAPI docs [S46]; discussion #14177 [S39] | `merge-io-variants` (opt-in): структурно рівні, крім `required` → одна модель з матрицею R6.1; інакше імена `ItemInput`/`Item` | SG215 / info | частково |
| 30 | Синтетичні схеми тіла `Body_<fn>_<path>_<method>` | FastAPI (Form/File без моделі) | `Body_handler_upload_csv_arg1__post` | fastapi discussion #12081 [S39] | `rename-synthetic-body` → `<OperationName>Request` | SG508 / info | так |
| 31 | Колізії імен схем (однакові класи з різних пакетів або модулів) | springdoc (лишає **першу** схему мовчки), NestJS (перезапис), swagger-core (колізія supertypes), Swashbuckle (виняток «Conflicting schemaIds» → `FullName`), pydantic (ключі `module__path__Name` з однаковим `title`) | `backend__gateways__types__ApprovementStatus` і `…__approvement__ApprovementStatus`, обидва з `title: ApprovementStatus` | springdoc#2863, #3160 [S47]; nestjs/swagger#2826 [S79]; swagger-core#4706 [S48]; Swashbuckle docs [S51]; openapi-python-client#1355 [S80] | `prefer-key-over-title` + `sanitize-component-keys`. **Тиха колізія springdoc зі специфікації не видна** → лише бекенд-lint (R15.6) | SG507 / warning | частково |
| 32 | Ключі components з недозволеними символами або «шумом» дженериків | Swashbuckle `FullName` (`Ns.Outer+Inner`), pydantic (`Page[User]` → `Page_User_`), .NET 9+ (`PagedResultOfUserDto`, `ArrayOfX`), springdoc (`PageUserDto`) | `Page_UserOut_` | OAS: ключі MUST відповідати `^[a-zA-Z0-9\.\-_]+$` [S1]; pydantic `normalize_name` [S44]; ASP.NET `GetSchemaReferenceId` [S55] | `sanitize-component-keys` + `envelope-detect` (R6.4) | SG104 / warning; SG509 / info | частково |
| 33 | Втрачені дженерики в конвертах і пагінації | NestJS (метадані дженериків не зберігаються; рецепт `allOf` + `getSchemaPath`), springdoc (`ApiResponse<Page<UserVO>>` → `PageObject`) | `data: {$ref: PageObject}` | springdoc#3192 [S49]; NestJS docs «Generic ApiResponse» [S35]; swagger_parser#156 [S81] | `envelope-detect` за шаблоном (`allOf: [$ref Envelope, {properties: {data: …}}]`) | SG509 / info | частково |
| 34 | Відсутній `operationId` | Swashbuckle (не генерує за замовч.), Microsoft.AspNetCore.OpenApi (лише з `[EndpointName]`/`WithName`) | `get: {responses: …}` | Swashbuckle docs «omits the operationId by default» [S51]; MS docs [S52] | `synthesize-operation-id` з method+path, детерміновано (R5.1) | SG501 / info | так |
| 35 | Шумні `operationId` | NestJS `CatsController_findAll` (+`_v1`), FastAPI `create_item_items_post` | — | NestJS docs `operationIdFactory` [S35]; FastAPI docs «Generate Clients» [S42] | трансформації R5.1: `strip-controller-prefix`, `strip-path-method-suffix` | SG503 / info | так |
| 36 | Дублікати `operationId` | NestJS (однакові контролер+метод, версіонування), springdoc (суфікс `_1`) | `UsersController_findAll` ×2; `getAll_1` | nestjs/swagger#482, #1711 [S82]; springdoc#885, #733 [S47] | `dedupe-operation-ids`: детермінований суфікс за path+method | SG502 / error | так |
| 37 | Нестабільний вихід між збірками (порядок ключів, плаваючі `_1`, динамічні default) | springdoc (`writer-with-order-by-keys=false` за замовч.; «Flaky operationIds»), NestJS (dynamic defaults) | `getAll_1` ↔ `getAll` між запусками | springdoc#885 («Flaky operationIds»), #733 [S47]; properties [S41]; nestjs/swagger#3541 [S35] | канонічне сортування. Звіт R14 позначає «перейменування без зміни структури» | SG701 / warning | частково |
| 38 | `*/*` як media type відповіді | springdoc (`default-produces-media-type=*/*`) | `content: {'*/*': {schema: {$ref: X}}}` | springdoc#659 [S47]; properties [S41] | `wildcard-media-to-json`: якщо схема структурна → `application/json` | SG601 / warning | так |
| 39 | Кілька еквівалентних JSON media types (`application/json`, `text/json`, `application/*+json`, `text/plain`) | ASP.NET MVC (формати з formatters), Swashbuckle | та сама схема тричі | Swashbuckle#2731 (`text/plain`, `text/json`) [S54]; Swashbuckle media types docs [S56]; MS docs про input formatters [S52] | `collapse-json-media-types` (пріоритет `application/json`) | SG602 / info | так |
| 40 | Помилки в `application/problem+json`, або задокументований тип помилки не збігається з фактичним | ASP.NET (4xx → ProblemDetails), springdoc (#2982, #2963) | `400: {content: {application/problem+json: {$ref: ProblemDetails}}}` | MS docs (controllers) [S52]; springdoc#2982 [S47] | `problem-json-as-json`: `+json` декодується як JSON, схема помилки спільна (R11.4) | SG603 / info | так |
| 41 | Дискримінатор без `mapping`, коли значення в JSON ≠ імені схеми | springdoc / swagger-core (імена з `@JsonSubTypes` не переносяться) | `discriminator: {propertyName: fooType}` при `@JsonSubTypes.Type(name = "foo1")` | swagger-core#3411 [S48]; springdoc#2999 (2.8.8) [S47] | `discriminator-mapping-from-const`: якщо підсхеми мають `const`/`enum` у властивості — будується mapping; інакше SG402 + override | SG402 / warning | частково |
| 42 | Властивість-дискримінатор не `required` у підтипах | Microsoft.AspNetCore.OpenApi (`$type`) | `FooBar.properties.$type` без `required` | aspnetcore#60469 [S53]; OAS 3.2 Discriminator [S1] | `discriminator-require-property` | SG403 / info | так |
| 43 | `$type` має бути **першим** полем JSON | System.Text.Json (.NET); `AllowOutOfOrderMetadataProperties` лише з .NET 9 | `{"$type": "bar", "value": 1}` | STJ polymorphism docs [S57] | — (кодоген: дискримінатор серіалізується першим; `$type` → валідний Dart-ідентифікатор) | SG404 / info | так (кодоген) |
| 44 | Успадкування через `allOf` з `required` не на тому рівні; колізії supertypes | springdoc, swagger-core | — | springdoc#2699 [S47]; swagger-core#4706 [S48] | — | SG405 / warning | ні |
| 45 | `oneOf` без дискримінатора | NestJS (`oneOf` + `@ApiExtraModels`; масив `oneOf` — некоректна схема), pydantic `Union` без `discriminator` | `oneOf: [{$ref: Cat}, {$ref: Dog}]` | NestJS docs [S35]; nestjs/swagger#3415 [S83] | — (R9.2: error / вибір за структурою / сире значення) | SG401 / warning | ні |
| 46 | Файл як `contentMediaType` без `format: binary` (валідно для 3.1, але старі генератори не розуміють) | FastAPI ≥0.129.1 | `file: {type: string, contentMediaType: application/octet-stream}` | openapi-python-client#1417 [S84]; FastAPI 0.129.1 (#14953) [S33]; learn.openapis.org 3.0→3.1 [S7] | `binary-content-media-type` → канонічний `Binary` | SG216 / info | так |
| 47 | Поля 3.2 у документі 3.1 (`itemSchema`, `application/jsonl`) | FastAPI ≥0.134 / 0.135 | `text/event-stream: {itemSchema: {… data: {contentMediaType: application/json, contentSchema: {$ref: Item}}}}` | `fastapi/openapi/utils.py` [S34]; release notes 0.134.0 / 0.135.0 [S33] | `accept-item-schema-any-version` | SG003 / info | так |
| 48 | Стрім (SSE) не описаний або описаний як `type: string` | NestJS (немає SSE-декоратора), FastAPI до 0.135 (`StreamingResponse`) | `text/event-stream: {schema: {type: string}}` | nestjs/swagger#3728 [S85]; fastapi discussion #15102 [S39] | — (override / `x-` → R12.2) | SG604 / warning | ні |

**Додатково:** ці спостереження не є дефектами, але впливають на генерацію.
- **Кортежі `prefixItems`** (pydantic `tuple[int, str]`) — `prefix-items-to-record`: Dart record, а для змінної довжини — `List<JsonValue>`. Код SG214 / info [S44].
- **Об'єкт як query-параметр без стилю.** Spring `Pageable` без `@ParameterObject` стає одним параметром `pageable` зі `$ref`. NestJS масив об'єктів у query перетворює на «масив масивів». Потрібен override flatten/`deepObject`, код SG506 / warning [S43][S86].
- **422 `HTTPValidationError` на кожній операції FastAPI** — це не дефект, але схема має генеруватися один раз (R11.4) [S34].
- **`readOnly` не виставляється** для get-only властивостей у .NET [S53] → матриця R6.1 отримує неповні дані. Код SG217 / info.

### C.1a. Доповнення з реальної NestJS-специфікації (2026-10-11)

Знайдено в продакшн-специфікації NestJS (OAS 3.0.0, 734 операції, 1434 схеми). Імена в прикладах знеособлені.

| # | Дефект | Приклад | Правило нормалізатора | Код / рівень | Auto-fix |
|---|---|---|---|---|---|
| 49 | **Подвійний масив** з `required: bool` усередині `items` (`@ApiProperty({ type: [X], isArray: true })`) | `{type: array, items: {required: true, type: array, items: {$ref: X}}}` | `collapse-double-array`: `items` типу `array` з булевим `required` → один масив `X` | SG218 / warning | так (з діагностикою) |
| 50 | `format` на самому масиві замість елемента, `items` немає | `ids: {type: array, format: uuid}` | `array-format-to-items`: `items: {type: string, format: uuid}` | SG219 / warning | так |
| 51 | Файл як `type: object, format: binary` | `file: {type: object, format: binary}` у multipart | `binary-object-to-string`: `type: string, format: binary` | SG220 / warning | так |
| 52 | Злиття кількох TS-enum в один (`enum: [...Object.values(A), ...Object.values(B)]`) → дублікати й «зоопарк» значень | `status: {enum: [BUILT, ERROR, …, BUILT, ERROR, …]}` | `dedupe-enum-values` + info «enum схоже на об'єднання кількох; винесіть `enumName`» | SG301 / warning | так |
| 53 | Union `T | T[]` («одне значення (legacy) або масив») | `oneOf: [{type: string, enum: […]}, {type: array, items: {…}}]` | — (R9.3: обгортка з розрізненням за JSON-типом) | SG401 / info | ні |
| 54 | Nullable enum у стилі NestJS 11: `oneOf` з `{enum: [null]}` + `$ref` | `{nullable: true, oneOf: [{type: string, nullable: true, enum: [null]}, {$ref: Currency}]}` | `nullable-enum-oneof-to-ref`: → nullable посилання на `Currency` | SG305 / warning | так |
| 55 | Опис замість назви тегу | тег `"Logo old-logo is deprecated, use new-logo instead."` | — (нормалізація тегів дає діагностику + override імені групи, R5.3) | SG510 / warning | ні |
| 56 | Ієрархія тегів через крапку | `Billing.Invoices`, `Billing.Payments`, … | `dotted-tags-to-groups` (opt-in): вкладені групи `api.billing.invoices` | SG511 / info | частково |
| 57 | Колізії імен методів після зрізання `XController_` (кілька контролерів з одним тегом) | `AdminRefsController_getById` і `RefsController_getById` в одному тегу | детермінований суфікс (з імені контролера) + діагностика | SG512 / warning | частково |
| 58 | Помилки без тіла: 4xx/5xx задокументовано лише описом, хоча сервер повертає спільну схему помилки | `401: {description: Unauthorized}` | — (конфіг `errors.default_schema` для відповідей без `content`) | SG605 / info | ні |
| 59 | `security` на рівні операції лише в частини операцій, глобального `security` немає | 61 з 734 операцій | — (конфіг безпеки за замовчуванням; R10.8) | SG606 / info | ні |
| 60 | Форма `example` суперечить схемі: схема — об'єкт, приклад — масив (або навпаки). Клієнт впаде на декодуванні кожної відповіді | `tokens: {allOf: [{$ref: Token}], example: [{…}, {…}]}` | — (не вгадуємо: діагностика з готовим override-ом `type: array`) | SG221 / warning | ні |
| 61 | `type: object` без `properties`, хоча приклад показує map з однаковими значеннями | `popup: {type: object, example: {"<uuid>": {"shown": true}}}` | — (`Map<String, JsonValue>` + підказка override-у `additionalProperties`) | SG211 / info | ні |

Масштаб: 827 inline-enum (250 різних наборів значень, 146 повторюються, `asc/desc` — 31 раз); 639 `allOf` з одним `$ref` заради `description`; 196 конвертів `{data: X}`; 6 SSE-ендпоінтів описані як `type: string` з прикладом тексту (C-48).

### C.2. Пресети нормалізатора за фреймворком

Ідея: у конфігу пишемо `preset: fastapi` і отримуємо набір правил, увімкнених за замовчуванням. Кожне правило можна вимкнути окремо (R2.1).

| Пресет | Правила, увімкнені за замовчуванням |
|---|---|
| `nestjs` | `detect-schema-dialect`, `nullable-to-type-null`, `nullable-ref-to-union`, `unwrap-single-allof-ref`, `drop-contradictory-type`, `dedupe-inline-enums`, `untyped-to-json-value`, `declare-missing-path-params`, `dedupe-operation-ids`, `collapse-double-array`, `array-format-to-items`, `binary-object-to-string`, `nullable-enum-oneof-to-ref`, `dedupe-enum-values`, трансформація `strip-controller-prefix` |
| `fastapi` | `anyof-null-to-nullable`, `const-to-enum`, `binary-content-media-type`, `accept-item-schema-any-version`, `rename-synthetic-body`, `prefer-key-over-title`, `decimal-detect`, `prefix-items-to-record`, трансформація `strip-path-method-suffix`; `merge-io-variants` — opt-in |
| `springdoc` | `wildcard-media-to-json`, `null-type-with-structure-to-nullable`, `infer-object-type`, `dedupe-operation-ids`, `dedupe-inline-enums`, `discriminator-mapping-from-const`, `envelope-detect` (Spring Data `Page`), `problem-json-as-json` |
| `aspnet` (Swashbuckle / MS.OpenApi) | `synthesize-operation-id`, `numeric-string-union-to-number`, `infer-type-from-format`, `collapse-json-media-types`, `enum-varnames-from-extensions`, `discriminator-require-property`, `problem-json-as-json`, `decimal-detect`, `sanitize-component-keys`, `null-type-with-structure-to-nullable` |
| `generic` | `bool-required-to-array`, `empty-ref-to-any`, `array-items-default`, `schema-examples-by-version`, `dedupe-enum-values`, `drop-invalid-default` |

### C.3. Що виправити автоматично не можна (лише діагностика + override, R2.5)

- Тип висячого або порожнього `$ref` (C-2, C-3): правило ставить JSON value, а справжній тип можна задати лише override-ом.
- Тип значень словника (C-26), `oneOf` без дискримінатора (C-45), mapping дискримінатора без `const` у підсхемах (C-41), схеми подій SSE (C-48), flags-enum (C-15), path-параметр, якого немає в шаблоні (C-7).
- **Дефекти, яких у специфікації не видно.** Springdoc мовчки бере першу з однойменних схем (C-31), NestJS перезаписує одну одною. Їх ловить лише рекомендаційний бекенд-lint (R15.6) або ручна перевірка. Тому в документації (R15.5) варто описати, як бекенд-команда запускає `check` у своєму CI (R2.4).

---

## D. Рецепти для бекендів (R15.5): як отримати хорошу специфікацію

### D.1. NestJS (`@nestjs/swagger`)

1. **CLI-плагін** (`nest-cli.json`). Він виставляє `required` за `?`, тип і enum за TS-типом, `default` за ініціалізатором, обмеження з `class-validator`, описи з коментарів. Аналізуються лише файли `*.dto.ts`/`*.entity.ts`, інші суфікси налаштовуються через `dtoFileNameSuffix` [S35]:
   ```json
   { "compilerOptions": { "plugins": [{ "name": "@nestjs/swagger",
       "options": { "introspectComments": true, "classValidatorShim": true, "autoFillEnumName": true } }] } }
   ```
   `autoFillEnumName` автоматично ставить `enumName`, тож enum стає окремою схемою, а не дублюється inline (C-11).
2. **`operationIdFactory`**. За замовчуванням id має вигляд `controllerKey_methodKey_version` [S35]:
   ```ts
   SwaggerModule.createDocument(app, config, {
     operationIdFactory: (controllerKey, methodKey) => methodKey, // унікальність — на вашій совісті
     excludeDynamicDefaults: true,   // default-и на кшталт new Date() не потрапляють у документ (C-28, C-37)
   });
   ```
3. **Версія 3.1 — лише з `@nestjs/swagger` ≥12.0.0.** Саме в 12.0.0 nullability почала записуватися відповідно до версії документа. На 11.x документ 3.1 містить `nullable`, а 3.0 — `oneOf` з `type: 'null'` [S31]. На 11.x лишайтеся на 3.0.
4. **Унікальні імена схем:** `@ApiSchema({ name: 'Menu' })`. Інакше однойменні DTO з різних модулів перезаписують одна одну (C-31) [S79].
5. **Дженерики і конверти:** `@ApiExtraModels(PaginatedDto, Model)` + `allOf: [{ $ref: getSchemaPath(PaginatedDto) }, { properties: { results: { type: 'array', items: { $ref: getSchemaPath(Model) } } } }]`. Саме цей шаблон розпізнаватиме `envelope-detect` [S35].
6. **Цикли:** лінивий тип `@ApiProperty({ type: () => Node })`. **Словники:** `@ApiProperty({ type: 'object', additionalProperties: { $ref: getSchemaPath(X) } })`. **Масиви в тілі:** `@ApiBody({ type: [CreateUserDto] })` [S35][S78].
7. **SSE:** вбудованого декоратора немає. Можна використати власний декоратор із nestjs/swagger#3728 або override у генераторі [S85].

### D.2. FastAPI / pydantic v2

1. **operationId:**
   ```python
   def custom_generate_unique_id(route: APIRoute) -> str:
       return f"{route.tags[0]}-{route.name}"
   app = FastAPI(generate_unique_id_function=custom_generate_unique_id)
   ```
   Без цього id виходять у стилі `create_item_items_post` [S42]. Префікс тегу потім прибирає трансформація R5.1.
2. **`separate_input_output_schemas=False`** (з 0.102.0) дає одну схему замість `Item-Input`/`Item-Output` [S46]. Альтернатива — лишити розщеплення і ввімкнути `merge-io-variants`.
3. **Не примушуйте `openapi_version="3.0.x"`.** FastAPI все одно генерує вміст 3.1 (`anyOf` з `null`, `const`, `examples`), тож документ стає змішаним (C-17) [S39][S42].
4. **Форми через моделі** (`Annotated[Model, Form()]`, FastAPI ≥0.113.0) замість окремих `Form`/`File`-параметрів. Тоді не з'являються синтетичні `Body_…`-схеми (C-30) [S39].
5. **Унікальні імена моделей у межах застосунку.** Інакше pydantic дасть ключі `module__path__Name` з однаковим `title` (C-31, C-4) [S38][S80].
6. **Discriminated unions:** `Annotated[Cat | Dog, Field(discriminator="pet_type")]`, де `pet_type: Literal["cat"]`. Pydantic додасть `discriminator.mapping`, а кожен варіант отримає `const` [S44].
7. **Стріми:** `response_class=EventSourceResponse` + тип повернення `AsyncIterable[Item]` (≥0.135.0) або JSON Lines (≥0.134.0). FastAPI сам згенерує `itemSchema`, а без анотації типу — ні [S32][S34].
8. **Помилки:** `responses={404: {"model": ErrorOut}}` для типізованих 4xx (R11.1). 422 `HTTPValidationError` додається автоматично [S34].

### D.3. Spring Boot / springdoc-openapi

1. Властивості [S41]:
   ```properties
   # за замовчуванням з 2.8.0
   springdoc.api-docs.version=openapi_3_1
   # замість */* (C-38)
   springdoc.default-produces-media-type=application/json
   # детермінований вихід (C-37)
   springdoc.writer-with-order-by-keys=true
   # або @Schema(name=...) для однойменних класів (C-31)
   springdoc.use-fqn=false
   ```
   (У `.properties` коментар `#` діє лише з початку рядка, тому коментарі винесено окремо.)
2. **Явні `@Operation(operationId = "...")`**: автоматичні суфікси `_1` нестабільні [S47].
3. **Enum як `$ref`:** `@Schema(enumAsRef = true)` на enum, або глобально `ModelResolver.enumsAsRef = true` [S43].
4. **`Pageable`:** `@ParameterObject Pageable pageable` розгортає параметри `page`/`size`/`sort` [S43]. Для стабільної форми відповіді — `@EnableSpringDataWebSupport(pageSerializationMode = VIA_DTO)`. Але в generic-обгортці тип `Page<T>` може зводитися до `PageObject` [S49], тож краще повертати власний DTO сторінки.
5. **Required / nullable:** `@Schema(requiredMode = Schema.RequiredMode.REQUIRED)`; `@Nullable`. Регресії в 2.8.17–3.1.x (C-19) показують, що вихід треба **закріпити snapshot-тестом специфікації** в CI бекенда [S45].
6. **Поліморфізм:** `@JsonTypeInfo(property = "kind")` + `@JsonSubTypes` **і** `@Schema(discriminatorProperty = "kind", discriminatorMapping = {@DiscriminatorMapping(value = "foo1", schema = Foo1.class)})`. Імена з `@JsonSubTypes` автоматично в mapping не потрапляють [S48][S47].
7. **Помилки:** `@ApiResponse(responseCode = "400", content = @Content(mediaType = "application/problem+json", schema = @Schema(implementation = ProblemDetail.class)))` [S47].

### D.4. ASP.NET Core

**Microsoft.AspNetCore.OpenApi (.NET 9/10)** [S52]:
1. JSON-опції для OpenAPI задаються **глобально**. MVC-опції (`AddControllers().AddJsonOptions`) на документ не впливають: у таблиці MS docs для них «Influence on OpenAPI: None».
   ```csharp
   builder.Services.Configure<Microsoft.AspNetCore.Http.Json.JsonOptions>(o => {
       o.SerializerOptions.NumberHandling = JsonNumberHandling.Strict;      // integer замість [integer,string]+pattern (C-23)
       o.SerializerOptions.Converters.Add(new JsonStringEnumConverter());   // enum-рядки з іменами (C-12)
   });
   builder.Services.AddOpenApi(o => o.OpenApiVersion = OpenApiSpecVersion.OpenApi3_1);
   ```
2. **operationId:** `.WithName("getUser")` або `[EndpointName("getUser")]`. Без цього `operationId` у документі немає (C-34).
3. **Media types:** `[Produces("application/json")]` / `[Consumes("application/json")]` прибирають `text/json`, `application/*+json` і `text/plain` (C-39). Помилки: `[ProducesResponseType<ProblemDetails>(400, "application/problem+json")]`.
4. **Поліморфізм:** `[JsonPolymorphic]` на **абстрактному** базовому типі + `[JsonDerivedType(typeof(Bar), "bar")]`. Для конкретного базового типу дискримінатор у документ не потрапить [S52].
5. **Required:** `[Required]` або модифікатор `required`. Decimal: schema transformer, що виставляє `format: decimal` (C-24).

**Swashbuckle.AspNetCore** (v10) [S50][S51]:
```csharp
builder.Services.AddSwaggerGen(o => {
    o.CustomOperationIds(api => api.TryGetMethodInfo(out var mi) ? mi.Name : null); // C-34
    o.SupportNonNullableReferenceTypes();
    o.NonNullableReferenceTypesAsRequired();
    o.UseAllOfForInheritance();
    o.UseOneOfForPolymorphism();
    o.CustomSchemaIds(t => t.FullName!.Replace('+', '.'));   // колізії; '+' недопустимий у ключі (C-32)
});
app.UseSwagger(o => o.OpenApiVersion = OpenApiSpecVersion.OpenApi3_1); // v10+, за замовч. 3.0
```
Після оновлення до v10 перевірте nullability: комбінація `SupportNonNullableReferenceTypes` + `UseAllOfToExtendReferenceSchemas` дає `type: 'null'` + `allOf` (C-19) [S54]. Для перейменування значень enum у System.Text.Json потрібен `[JsonStringEnumMemberName]` (.NET 9+), бо `[EnumMember]` STJ ігнорує [S51].

### D.5. Рекомендаційний бекенд-lint (R15.6): мінімальний чекліст

Ці коди варто вмикати як **error** у CI бекенда (режим `check`, R2.4):
- SG101–SG103 (`$ref`), SG502 (дублікати `operationId`), SG504/SG505 (path-параметри);
- SG001/SG002 (змішані діалекти), SG204 (`type: 'null'` + структура);
- SG601 (`*/*`), SG402 (дискримінатор без mapping), SG507 (колізії імен);
- SG701 (нестабільний вихід), тобто дві генерації поспіль мають давати однаковий документ.

Як **warning**: SG201, SG202, SG203, SG301, SG303, SG304, SG401, SG604.

---

## Джерела

**Специфікації і RFC**
- [S1] OpenAPI Specification 3.2.0 — https://spec.openapis.org/oas/v3.2.0.html (джерело: https://github.com/OAI/OpenAPI-Specification/blob/main/versions/3.2.0.md); реліз 2025-09-19 — https://github.com/OAI/OpenAPI-Specification/releases/tag/3.2.0
- [S2] OAS 3.2.1, release notes (2026-09-10) — https://github.com/OAI/OpenAPI-Specification/releases/tag/3.2.1 ; текст — https://github.com/OAI/OpenAPI-Specification/blob/main/versions/3.2.1.md
- [S3] Overlay Specification 1.2.0 (і 1.0.0, 1.1.0) — https://spec.openapis.org/overlay/latest ; https://github.com/OAI/Overlay-Specification/tree/main/versions ; релізи 1.1.0 / 1.2.0 — https://github.com/OAI/Overlay-Specification/releases
- [S4] OAS 3.0.4 — https://spec.openapis.org/oas/v3.0.4.html
- [S5] OAS 3.1.2 (і 3.1.1, 3.1.0) — https://spec.openapis.org/oas/v3.1.2.html
- [S6] JSON Schema 2020-12 Core / Validation — https://json-schema.org/draft/2020-12/json-schema-core ; https://json-schema.org/draft/2020-12/json-schema-validation
- [S7] Learn OpenAPI: Upgrading 3.0 → 3.1 — https://learn.openapis.org/upgrading/v3.0-to-v3.1.html
- [S8] RFC 6901 JSON Pointer — https://www.rfc-editor.org/rfc/rfc6901
- [S9] RFC 6902 JSON Patch — https://www.rfc-editor.org/rfc/rfc6902
- [S10] RFC 9535 JSONPath — https://www.rfc-editor.org/rfc/rfc9535
- [S20] Overlay 1.0.0 — https://spec.openapis.org/overlay/v1.0.html
- [S21] OAI GitHub releases (дати всіх версій) — https://github.com/OAI/OpenAPI-Specification/releases
- [S22] OAI Newsletter, June 2026 (3.3 у роботі) — https://www.openapis.org/blog/2026/06/09/openapi-initiative-newsletter-june-2026 ; Moonwalk — https://github.com/OAI/Moonwalk
- [S23] Swagger: підтримка OAS 3.2.0 (квітень 2026) — https://swagger.io/blog/swagger-launches-support-for-openapi-3-2-0/
- [S24] Learn OpenAPI: Upgrading 3.1 → 3.2 — https://learn.openapis.org/upgrading/v3.1-to-v3.2.html
- [S25] Learn OpenAPI: Overlay 1.0 → 1.1 і 1.1 → 1.2 — https://learn.openapis.org/upgrading/overlay-v1.0-to-v1.1.html ; https://learn.openapis.org/upgrading/overlay-v1.1-to-v1.2.html ; приклад copy — https://learn.openapis.org/overlay/example-copy-schema.html

**Overlay-інструменти та Dart-пакети**
- [S26] Огляд інструментів: https://apievangelist.com/2026/06/25/openapi-overlays-tooling-support/ ; Speakeasy — https://www.speakeasy.com/docs/sdks/prep-openapi/overlays/create-overlays ; Bump.sh — https://docs.bump.sh/help/specification-support/overlays/ ; libopenapi — https://pb33f.io/libopenapi/overlays/ ; oas-patch — https://tools.apievangelist.com/store/oas-patch/ ; BinkyLabs — https://www.nuget.org/packages/BinkyLabs.OpenApi.Overlays/ ; Learn OpenAPI tools — https://learn.openapis.org/overlay/
- [S27] `json_path` (RFC 9535) — https://pub.dev/packages/json_path
- [S28] `rfc_6901` — https://pub.dev/packages/rfc_6901
- [S29] `rfc_6902` — https://pub.dev/packages/rfc_6902
- [S36] oapi-codegen v2.4.0 (overlay) — https://github.com/oapi-codegen/oapi-codegen/releases/tag/v2.4.0
- [S37] Redocly CLI 2.56.0 (overlay у `bundle`) — https://github.com/Redocly/redocly-cli/releases ; PR — https://github.com/Redocly/redocly-cli/pull/3143

**NestJS**
- [S30] nestjs/swagger#4063 (nullable у 3.1) — https://github.com/nestjs/swagger/issues/4063 ; PR #4070 — https://github.com/nestjs/swagger/pull/4070
- [S31] @nestjs/swagger 12.0.0 release notes (2026-08-27) — https://github.com/nestjs/swagger/releases/tag/12.0.0
- [S35] NestJS docs OpenAPI (introduction, types-and-parameters, operations, cli-plugin) — https://docs.nestjs.com/openapi/introduction ; https://docs.nestjs.com/openapi/types-and-parameters ; https://docs.nestjs.com/openapi/operations ; https://docs.nestjs.com/openapi/cli-plugin ; nestjs/swagger#3541 — https://github.com/nestjs/swagger/issues/3541
- [S63] nestjs/swagger#675 — https://github.com/nestjs/swagger/issues/675
- [S64] nestjs/swagger#3368 — https://github.com/nestjs/swagger/issues/3368
- [S65] nestjs/swagger#4006 — https://github.com/nestjs/swagger/issues/4006
- [S67] nestjs/swagger#1368 — https://github.com/nestjs/swagger/issues/1368
- [S71] nestjs/swagger#1889 — https://github.com/nestjs/swagger/issues/1889
- [S72] nestjs/swagger#1880 — https://github.com/nestjs/swagger/issues/1880
- [S73] nestjs/swagger#3274 — https://github.com/nestjs/swagger/issues/3274
- [S76] nestjs/swagger#3311 — https://github.com/nestjs/swagger/issues/3311
- [S77] nestjs/swagger#3928 — https://github.com/nestjs/swagger/issues/3928
- [S78] nestjs/swagger#1771 — https://github.com/nestjs/swagger/issues/1771
- [S79] nestjs/swagger#2826 — https://github.com/nestjs/swagger/issues/2826
- [S82] nestjs/swagger#482, #1711, #2537 — https://github.com/nestjs/swagger/issues/482 ; https://github.com/nestjs/swagger/issues/1711 ; https://github.com/nestjs/swagger/issues/2537
- [S83] nestjs/swagger#3415 — https://github.com/nestjs/swagger/issues/3415
- [S85] nestjs/swagger#3728 (SSE) — https://github.com/nestjs/swagger/issues/3728
- [S86] nestjs/swagger#3624 — https://github.com/nestjs/swagger/issues/3624

**FastAPI / pydantic**
- [S32] FastAPI docs: Server-Sent Events, Stream JSON Lines — https://fastapi.tiangolo.com/tutorial/server-sent-events/ ; https://fastapi.tiangolo.com/tutorial/stream-json-lines/
- [S33] FastAPI releases 0.129.1 / 0.134.0 / 0.135.0 — https://github.com/fastapi/fastapi/releases/tag/0.129.1 ; https://github.com/fastapi/fastapi/releases/tag/0.134.0 ; https://github.com/fastapi/fastapi/releases/tag/0.135.0
- [S34] `fastapi/openapi/utils.py` (`itemSchema`, `HTTPValidationError`, `openapi_version="3.1.0"`) — https://github.com/fastapi/fastapi/blob/master/fastapi/openapi/utils.py
- [S38] fastapi discussion #14737 — https://github.com/fastapi/fastapi/discussions/14737
- [S39] fastapi discussions #12081, #14177, #9789, #15102 — https://github.com/fastapi/fastapi/discussions/12081 ; https://github.com/fastapi/fastapi/discussions/14177 ; https://github.com/fastapi/fastapi/discussions/9789 ; https://github.com/fastapi/fastapi/discussions/15102 ; Form models — https://fastapi.tiangolo.com/tutorial/request-form-models/
- [S42] FastAPI docs: Generate Clients; Declare Request Example Data — https://fastapi.tiangolo.com/advanced/generate-clients/ ; https://fastapi.tiangolo.com/tutorial/schema-extra-example/
- [S44] pydantic `json_schema.py` (`literal_schema`, `decimal_schema`, `tuple_schema`, `normalize_name`) — https://github.com/pydantic/pydantic/blob/main/pydantic/json_schema.py
- [S46] FastAPI docs: Separate OpenAPI Schemas for Input and Output — https://fastapi.tiangolo.com/how-to/separate-openapi-schemas/

**Spring / springdoc / swagger-core**
- [S40] springdoc v2.8.0 (3.1 за замовч.) — https://github.com/springdoc/springdoc-openapi/releases/tag/v2.8.0
- [S41] springdoc properties — https://springdoc.org/properties
- [S43] springdoc FAQ — https://springdoc.org/faq.html
- [S45] springdoc#3275, #3338, #3358, #3362 — https://github.com/springdoc/springdoc-openapi/issues/3275 ; https://github.com/springdoc/springdoc-openapi/issues/3338 ; https://github.com/springdoc/springdoc-openapi/issues/3358 ; https://github.com/springdoc/springdoc-openapi/issues/3362
- [S47] springdoc#659, #733, #885, #2699, #2863, #2963, #2982, #2999, #3160 — https://github.com/springdoc/springdoc-openapi/issues/659 ; https://github.com/springdoc/springdoc-openapi/issues/733 ; https://github.com/springdoc/springdoc-openapi/issues/885 ; https://github.com/springdoc/springdoc-openapi/issues/2699 ; https://github.com/springdoc/springdoc-openapi/issues/2863 ; https://github.com/springdoc/springdoc-openapi/issues/2963 ; https://github.com/springdoc/springdoc-openapi/issues/2982 ; https://github.com/springdoc/springdoc-openapi/issues/2999 ; https://github.com/springdoc/springdoc-openapi/issues/3160
- [S48] swagger-core#3411, #4706 — https://github.com/swagger-api/swagger-core/issues/3411 ; https://github.com/swagger-api/swagger-core/issues/4706
- [S49] springdoc#3192 — https://github.com/springdoc/springdoc-openapi/issues/3192

**ASP.NET Core**
- [S50] Swashbuckle: Migrating to v10 (3.1) — https://github.com/domaindrivendev/Swashbuckle.AspNetCore/blob/master/docs/migrating-to-v10.md
- [S51] Swashbuckle: Configure and customize SwaggerGen (operationId, CustomSchemaIds, enum, inheritance) — https://github.com/domaindrivendev/Swashbuckle.AspNetCore/blob/master/docs/configure-and-customize-swaggergen.md
- [S52] Microsoft Learn: Include OpenAPI metadata (.NET 10); What's new in ASP.NET Core 10 — https://learn.microsoft.com/aspnet/core/fundamentals/openapi/include-metadata?view=aspnetcore-10.0 ; https://learn.microsoft.com/aspnet/core/release-notes/aspnetcore-10.0
- [S53] dotnet/aspnetcore#61038, #64920, #60469, #65017, #67557, #65403 — https://github.com/dotnet/aspnetcore/issues/61038 ; https://github.com/dotnet/aspnetcore/issues/64920 ; https://github.com/dotnet/aspnetcore/issues/60469 ; https://github.com/dotnet/aspnetcore/issues/65017 ; https://github.com/dotnet/aspnetcore/issues/67557 ; https://github.com/dotnet/aspnetcore/issues/65403
- [S54] Swashbuckle#3649, #2731 — https://github.com/domaindrivendev/Swashbuckle.AspNetCore/issues/3649 ; https://github.com/domaindrivendev/Swashbuckle.AspNetCore/issues/2731
- [S55] `JsonTypeInfoExtensions.GetSchemaReferenceId` (`…Of…`, `ArrayOf…`) — https://github.com/dotnet/aspnetcore/blob/main/src/OpenApi/src/Extensions/JsonTypeInfoExtensions.cs
- [S56] Swashbuckle docs: Media Types — https://swashbuckleaspnetcore.readthedocs.io/en/latest/getting-started/media-types.html
- [S57] System.Text.Json polymorphism, `AllowOutOfOrderMetadataProperties` — https://learn.microsoft.com/dotnet/standard/serialization/system-text-json/polymorphism ; https://learn.microsoft.com/dotnet/api/system.text.json.jsonserializeroptions.allowoutofordermetadataproperties

**Генератори й інші докази**
- [S60] nftstorage PR#2470 («required is not of type `array`») — https://github.com/nftstorage/nft.storage/pull/2470
- [S61] indodax-cli#48 — https://github.com/ibidathoillah/indodax-cli/issues/48
- [S62] L5-Swagger#616 (`#/components/schemas/`) — https://github.com/DarkaOnLine/L5-Swagger/issues/616
- [S66] openai-openapi#453 — https://github.com/openai/openai-openapi/issues/453
- [S68] homebox#1175 — https://github.com/sysadminsmedia/homebox/issues/1175
- [S69] openapi-generator#7288 — https://github.com/OpenAPITools/openapi-generator/issues/7288
- [S70] openapi-generator#18055 (dart-dio, `x-enumNames`) — https://github.com/OpenAPITools/openapi-generator/issues/18055
- [S74] openapi-generator#25176 (`type: "null"`, 7.26.0) — https://github.com/OpenAPITools/openapi-generator/issues/25176
- [S75] swagger_parser#84 (Dart, `anyOf` + null) — https://github.com/Carapacik/swagger_parser/issues/84
- [S80] openapi-python-client#1355, #652 — https://github.com/openapi-generators/openapi-python-client/issues/1355 ; https://github.com/openapi-generators/openapi-python-client/issues/652
- [S81] swagger_parser#156 (дженерики NestJS) — https://github.com/Carapacik/swagger_parser/issues/156
- [S84] openapi-python-client#1417 (`contentMediaType` для файлу) — https://github.com/openapi-generators/openapi-python-client/issues/1417
