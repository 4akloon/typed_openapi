# M7: runtime (`typed_openapi_runtime`) — дизайн

Дата: 2026-10-12. Вимоги: R6.5, R7.1, R10.1–R10.3, R10.5, R11.2, R11.3, R11.7, R12.3 ([requirements.md](../../requirements.md)). Дослідження: [research/README](../../research/README.md) (таблиця ухвалених рішень; §7.3 HTTP-шар; §7.4 модель помилок; §7.7 представлення), [research/07](../../research/07-dart-building-blocks.md) (§B Dio 5.11, §C мова, §E ескізи). Рішення, позначені «(к. N)», підтвердив користувач 2026-10-12 (номер — у його списку); «(в. N)» — відповіді користувача і контролера на відкриті питання першої версії дизайну (номер питання).

Runtime — єдиний пакет, від якого залежить згенерований код. Згенерованого коду ще немає (M8–M10), тому API спроєктовано з боку його викликів; ескіз — наприкінці.

## Рішення

1. **Залежності — лише `dio` і `meta`** (R13.3; к. 15). `meta` дає `@visibleForTesting`. Логіка, що не потребує транспорту, від Dio не залежить (§7.3): `json/`, `model/`, `params/`, `OperationRequest`, `RawResponse`, SSE-декодер. Dio знають лише `dio/` (`DioRequestSender`, `CallOptions`), `result/` (транспортні варіанти несуть `DioException`, к. 5) і `OperationInfo.of(RequestOptions)` (к. 12).
2. **`Result<T, E>` без винятків** (§7.4; R11.1–R11.3, R11.7; к. 1.1, 7; в. 5). Sealed `Result<T, E>` = `Success<T, E>` (`data`, `statusCode`, `headers: Map<String, List<String>>`) | sealed `Failure<T, E>` = `HttpError` (задокументований 4xx/5xx/`default`; `statusCode`, `body: E`, `headers`) | `UndocumentedStatus` (`statusCode`, `rawBody`, `headers`) | `DecodeError` | `TransportError` | `Cancelled`. Префікса `Api` немає ніде. Допоміжних методів (`dataOrNull`, `map`, `getOrThrow`, `fold`) немає: лише pattern matching. R11.2 у v1 — лише `Result` (§7.4). Ім'я `Result` збігається з `Result` з `package:async`; це прийнято, README радить `hide Result` або префікс імпорту.
3. **`E = Never`, `T = void`** (к. 4, 16). Операція без задокументованих помилок має `E = Never` (усі не-2xx — `UndocumentedStatus`); із `errors.default_schema` у конфігу `E` — ця схема (вирішує M9). Успіх без тіла — `T = void`.
4. **Транспорт і скасування** (R11.7; research §6 R11.7; к. 5). `TransportError(DioException exception, StackTrace stackTrace)` без власного enum видів: вид — `exception.type`. Скасування — окремий варіант `Cancelled(DioException, StackTrace)`. Тип `DioExceptionType`, якого ще немає в Dio 5.11, — теж `TransportError` (switch з `_`, щоб новий мінорний Dio не ламав компіляцію runtime).
5. **Декодування: контракт json_serializable і один тип винятку** (R6.5; §7.2; к. 2, 3, 13; в. 4). Згенерований `Model.fromJson(Map<String, Object?>)` кидає лише `JsonDecodeException` (JSON pointer, `expected`, `actual`, `schema`), і лише на першій невідповідності — помилки не збираються. Клієнт ловить тільки цей тип, `DioException` і `FormatException` декодера; `Error` (`TypeError`, `StateError`) не ловиться. `FormatException` декодера (`DateTime.parse`, конвертер R6.8) — це збій даних, тож він перетворюється на `JsonDecodeException` (`JsonDecodeException.fromFormatException`): `JsonReader` робить це в pointer поля, `DioRequestSender` — у корені (`DecodeError` зі статусом і `rawBody`), `SseItemDecoder` — у `SseDecodeError`, і потік іде далі. Інакше конвертер користувача вилітав би винятком із згенерованого методу або необробленою помилкою зони з SSE. Повідомлення називають типи JSON, а не значення (значення бувають великими або приватними). Для помилки, яку сервер робить навмисно, виняток несе `hint` — явне виправлення (див. рішення 6).
6. **Строгість** (к. 2; в. 3, 4). Значення іншого JSON-типу — помилка; єдине розширення — ціле там, де очікується `number`. `asInt` не приймає `1.0`; ціле понад 2^63 `jsonDecode` дає як `double`, тож воно теж помилка (а не мовчазне обрізання `toInt`). Нескінченність (`jsonDecode('1e400')`) — помилка: `jsonEncode` не записав би її назад. `date-time` — лише RFC 3339 зі зсувом; неіснуючі дати і секунда 60 — помилка (`DateTime.parse` мовчки переносить їх). `date-time` без зсуву (Spring `LocalDateTime`) — `DecodeError` з `actual: a date-time without an offset` і `hint`: зіставити формат зі своїм типом через конвертер (`types.formats`, R6.8) або перевизначити `format` властивості override-ом. `null` — помилка лише в required non-nullable властивості; optional non-nullable читає `null` як «немає» (поле в Dart однаково `T?`).
7. **Матриця читань** (R6.1, R7.1; в. 3). `JsonReader`: `required` (немає або `null` — помилка), `requiredNullable` (немає — помилка), `optional` (nullable чи ні: немає і `null` → `null`), `patch` (немає → `null`, `null` → `Patch.nullValue()`), `requiredValue` / `optionalValue` для схем без обмежень. Декодери — статичні функції `T Function(Object?)`: `asInt`, `asDouble`, `asNumber`, `asString`, `asBool`, `asDateTime`, `asObject`, `asList`, `asValue`, комбінатори `listOf`, `mapOf`, `objectOf`, `nullable`; індекс масиву і ключ мапи потрапляють у pointer. Зайві поля ігноруються (R6.5).
8. **Межі вхідних даних.** `jsonDecode` ітеративний, а рекурсивні `fromJson` і `jsonEncode` — ні (перевірено: 200 000 рівнів → `StackOverflowError` у `jsonEncode`). `RawResponse.json` і `SseMessage.json` перевіряють глибину без рекурсії (`JsonReader.checkDepth`, 1000 рівнів, як TOA007 генератора) і дають `DecodeError` з pointer на перший занадто глибокий контейнер.
9. **`Patch<T>`** (§7.7, E.2; к. 8). Sealed `Patch<T>` = `PatchValue` | `PatchNull`, `const` фабрики `.value(x)` / `.nullValue()`, `toJson(encode)`; поле `Patch<T>?`, `null` = не надсилати (R7.3).
10. **`JsonValue`** (R6.2; §C.6; к. 9). `extension type const JsonValue(Object? raw)` з `asObject`, `asList`, `asString`, `asNumber`, `asBool`, `isNull`, `operator []` (відсутній ключ або індекс — `JsonValue(null)`), `fromJson`/`toJson`. Extension type стирається: `JsonValue(null)` під час виконання — це `null`, тож `JsonValue?` не відрізнив би «немає» від `null`; поле схеми без обмежень має тип `JsonValue`, відсутнє читається як `JsonValue(null)`.
11. **Параметри кодує runtime** (R10.3; §B.4; к. 10). `PathParameter` (`simple`, `label`, `matrix`), `QueryParameter` (`form`, `spaceDelimited`, `pipeDelimited`, `deepObject`, `allowReserved`), `HeaderParameter`, `CookieParameter` за RFC 6570 і RFC 3986. Значення — JSON-форма (`toJson` уже застосовано, R6.8). Порядок — порядок параметрів у специфікації; `null`, порожні список і мапа не надсилаються. `explode` за замовчуванням як в OAS (`true` лише для `form`). `allowReserved` лишає лише безпечні в query зарезервовані символи (OAS 3.2: `[ ] #` і `& = +` кодуються завжди); `[`, `]`, `|` кодуються, бо `Uri.parse` у Dio однаково їх закодував би (перевірено). Заголовки не percent-кодуються, крім керівних і не-ASCII (захист від CRLF-ін'єкції). Cookie — пари `name=value` через `; `. Dio отримує готовий шлях із query; інтерсептори бачать порожній `queryParameters` (читати `options.uri`) — у README. Не-JSON-скаляр (`DateTime`, вкладений список, нескінченність) — `ArgumentError`: це помилка згенерованого коду, а не даних.
12. **Потік Dio** (R10.1, R10.2; §B.1, §B.2; типові рішення користувача). Запит іде через `dio.request` (зливає `BaseOptions`: base URL, заголовки, таймаути). Dio користувача не змінюється, `validateStatus` не чіпається, повторів немає (це справа інтерсепторів). `DioException.badResponse` з відповіддю декодується так само, як успішна відповідь: генерований декодер завжди перемикається за статусом (інтерсептор міг `resolve`-нути 503, а `validateStatus` користувача — пропустити 404).
13. **Тіла відповідей** (§B.1; к. 14; в. 2). JSON парсить Dio (`ResponseType.json`), runtime декодує вже розібраний об'єкт і нічого не перепарсює: `text/plain` з JSON для JSON-операції — `DecodeError` «expected an object, got a string». Не-JSON тіла — `ResponseKind.text` / `.bytes` (тип-аргумент `request<String>` / `request<List<int>>`, бо Dio примусово ставить JSON для інших типів). Невалідний JSON: Dio кидає `DioException.unknown` з `FormatException` і відкидає відповідь, тож `DecodeError` має `statusCode: null` і `rawBody` — текст, який повідомив парсер, best effort: усе тіло, коли Dio прочитав його одним шматком, і лише останній чанк, коли Dio стрімив тіло (є `Content-Length`; перевірено). Повне тіло і статус дав би лише `ResponseType.plain` з власним `jsonDecode`, що суперечить к. 14; обмеження описано в README.
14. **`CallOptions`** (R10.5; §C.4; к. 1). Один необов'язковий параметр `call` у кожному згенерованому методі: `cancelToken`, `headers` (перемагають заголовки-параметри), `extra` (для інтерсепторів), `onSendProgress`, `onReceiveProgress`. Таймаутів немає: вони в Dio користувача.
15. **`OperationInfo`** (R10.5; research R10.5/10.8; к. 12). `operationId`, `method`, `pathTemplate`, `tags` (security — у M9) лежить у `RequestOptions.extra` під `OperationInfo.extraKey`; `OperationInfo.of(RequestOptions)` повертає `null` для запитів не з генерованого клієнта.
16. **SSE-декодер за WHATWG** (R12.3; §B.6). `SseDecoder`: байти → `SseMessage(event, data, id, retry)`; UTF-8 з заміною невалідних послідовностей, BOM на початку відкидається, символ, розрізаний між чанками, лишається цілим; кінці рядків CRLF/LF/CR (зокрема CR і LF у різних чанках); `data` багаторядкове; `id` з U+0000 ігнорується, `id` і `retry` зберігаються між подіями; `retry` — лише ASCII-цифри; коментарі; незавершена подія наприкінці відкидається. Використовувати `bind`, а не `stream.transform`: Dio дає `Stream<Uint8List>`, і `transform` з трансформером `List<int>` падає під час виконання (знайдено тестом).
17. **Потік подій як значення** (§7.4, відкрите питання про стріми; к. 11; в. 6). `DioRequestSender.openEvents` повертає `Result<Stream<SseItem<T>>, E>`: відкриття — `Result`, далі sealed `SseItem<T>` = `SseEvent<T>` (`data`, `event`, `id`, `retry`) | `SseDecodeError` (одна подія не декодувалась, потік іде далі) | `SseDisconnected` (завжди останній; `cause` — помилка, зокрема `DioException` скасування, або `null`, коли сервер закрив потік). Потік не випускає помилок і винятків. Потік відкривають лише задокументовані статуси успіху, які згенерований виклик передає в `OperationRequest.streamStatuses` (так само, як інші відповіді перемикаються за статусом); будь-який інший статус — тіло читається повністю, JSON за content-type, і декодується звичайним шляхом помилки або незадокументованого статусу. Перепідключення — M10.
18. **Web** (R12.4; §B.6; к. 15). Усе працює на web, крім SSE зі стандартним браузерним адаптером Dio (XHR віддає тіло після закриття з'єднання): тоді `openEvents` одразу повертає `TransportError` з поясненням, як поставити fetch-адаптер у свій Dio (`ConversionLayerAdapter` з `dio_compatibility_layer` + `BrowserClient` або `fetch_client`). Web визначається `bool.fromEnvironment('dart.library.js_interop')`, стандартний адаптер — порівнянням `runtimeType` з `HttpClientAdapter()`; на VM це перевіряється через `DioRequestSender.forPlatform(isWeb: true)`.

19. **Імена** (в. 1): `DioRequestSender` з `send` / `openEvents`, `OperationRequest`, `RawResponse` (`success` / `error` / `undocumented`), `ResponseKind`, `JsonReader`, `SseMessage`, `SseItemDecoder` — як у цьому дизайні.

### Ескіз згенерованого коду (ілюстрація, не контракт для M8)

Перевірено тестом `test/helpers/pets_api.dart` + `test/generated_client_test.dart` (план, задача 8).

```dart
final class Pet {
  const Pet({required this.id, required this.name, this.tags, this.metadata = const JsonValue(null)});

  factory Pet.fromJson(Map<String, Object?> json) {
    final r = JsonReader(json, schema: 'Pet');
    return Pet(
      id: r.required('id', JsonReader.asInt),
      name: r.required('name', JsonReader.asString),
      tags: r.optional('tags', JsonReader.listOf(JsonReader.objectOf(Tag.fromJson))),
      metadata: r.optionalValue('metadata'),
    );
  }

  final int id;
  final String name;
  final List<Tag>? tags;
  final JsonValue metadata;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'tags': ?tags?.map((t) => t.toJson()).toList(),
    'metadata': ?metadata.raw,
  };
}

final class UpdatePet {                      // тіло PATCH (R7)
  const UpdatePet({this.name, this.tag});
  final Patch<String>? name;
  final Patch<String>? tag;
  Map<String, Object?> toJson() => {
    if (name case final v?) 'name': v.toJson((s) => s),
    if (tag case final v?) 'tag': v.toJson((s) => s),
  };
}

class PetsApi {                              // без модифікаторів: mock через implements (R10.7)
  PetsApi(Dio dio) : _sender = DioRequestSender(dio);
  final DioRequestSender _sender;

  static const _getPetById = OperationInfo(
    operationId: 'getPetById', method: 'GET', pathTemplate: '/pets/{petId}', tags: ['pets']);

  Future<Result<Pet, ApiError>> getPetById({required int petId, List<String>? fields, CallOptions? call}) =>
      _sender.send(
        OperationRequest(
          _getPetById,
          path: [PathParameter('petId', petId)],
          query: [QueryParameter('fields', fields, explode: false)],
        ),
        (r) => switch (r.statusCode) {
          200 => r.success(Pet.fromJson(r.jsonObject)),
          >= 400 && < 600 => r.error(ApiError.fromJson(r.jsonObject)),
          _ => r.undocumented(),
        },
        call: call,
      );

  Future<Result<Stream<SseItem<PetChange>>, Never>> watchPet({required int petId, CallOptions? call}) =>
      _sender.openEvents(
        OperationRequest(_watchPet, path: [PathParameter('petId', petId)], streamStatuses: const {200}),
        PetChange.fromEvent,                 // SseMessage → PetChange, через message.jsonObject
        (r) => r.undocumented(),
        call: call,
      );
}

// виклик
switch (await pets.getPetById(petId: 7)) {
  case Success(:final data): show(data);
  case HttpError(:final body): showError(body.code);
  case DecodeError(:final error): log('${error.schema} ${error.pointer}');
  case UndocumentedStatus() || TransportError() || Cancelled(): retryLater();
}
```

## Що не входить

- Перепідключення SSE з `Last-Event-ID` і політикою (R12.5), диспетчер подій за `event` і `itemSchema` (R12.2) — M10.
- Тіла запитів `multipart/form-data` і `x-www-form-urlencoded` (R10.4) — M9; runtime передає `body` і `contentType` у Dio як є (форму можна зібрати з `QueryParameter.encode`).
- Декодери форматів `date`, `byte`, `uuid`, `int64` на web — разом із мапінгом типів (M6, M8).
- Security-метадані в `OperationInfo` (R10.8) — M9; поле додається без зламу.
- Режим доставки помилок винятками (R11.2) — пізніше, якщо з'явиться запит (§7.4).
- Власна абстракція транспорту `ApiTransport` — рішення до 1.0 (§7.3).
- Валідація обмежень (R6.7), NDJSON (R12.6).
- Ліміти розміру: рядок SSE і тіло помилки SSE читаються в пам'ять без ліміту (як і будь-яке тіло в Dio).
