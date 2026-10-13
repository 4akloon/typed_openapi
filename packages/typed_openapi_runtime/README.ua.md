# typed_openapi_runtime

Runtime для клієнтів, згенерованих
[`typed_openapi`](https://pub.dev/packages/typed_openapi): єдиний пакет, від якого
залежить згенерований код. Залежності: `dio` і `meta`.

> **Статус:** у розробці, ще не опубліковано.

## Що всередині

- `Result<T, E>`: його повертає кожен згенерований метод; для очікуваних
  проблем нічого не кидається. Читається через pattern matching:

  ```dart
  switch (await api.pets.getPetById(petId: 1)) {
    case Success(:final data): show(data);
    case HttpError(:final body): showError(body);          // задокументований 4xx/5xx
    case DecodeError(:final error): log(error.pointer);    // тіло не відповідає схемі
    case UndocumentedStatus() || TransportError() || Cancelled(): retryLater();
  }
  ```

  Операція без задокументованих помилок має `E = Never`. `switch` по ній
  усе одно потребує `case Failure()` (він покриває всі невдачі) або ж
  case для кожного варіанта невдачі, включно з `HttpError()`, бо інші
  невдачі (транспорт, скасування, декодування, незадокументований статус)
  можливі; самого `HttpError()` недостатньо. Операція без тіла відповіді має
  `T = void`: збігай її через `Success()`.

- `Patch<T>` для полів запиту з трьома станами: поле `Patch<T>?`, що дорівнює
  `null`, не надсилається, `.nullValue()` надсилає `null`, `.value(x)` — `x`.
- `JsonReader` для згенерованих `fromJson`: строге декодування (єдине
  розширення — ціле число там, де очікується `number`), що кидає
  `JsonDecodeException` з JSON pointer, очікуваним і фактичним типом першої
  невідповідності. `JsonValue` тримає будь-яке JSON-значення.
- `Date` для `format: date` (`YYYY-MM-DD`, без часу і часового поясу):
  читається через `JsonReader.asDate`, пишеться через `Date.toJson()`;
  `Date.parse` кидає `FormatException`, `Date.tryParse` повертає `null`.
- Для згенерованих моделей: `DeepEquality` (глибокі `==` і `hashCode` списків,
  map-ів і patch-ів), `JsonReader.constant`, `additional` (ключі, яких модель
  не перелічує, як незмінна map) і `asBytes`, а також `immutable`, що
  реекспортується з `package:meta`, тож згенерований код імпортує лише цей
  пакет.
- Кодувальники стилів параметрів OpenAPI (`simple`, `label`, `matrix`,
  `form`, `spaceDelimited`, `pipeDelimited`, `deepObject`, заголовки,
  cookie) з percent-кодуванням за RFC 3986.
- `DioRequestSender`: надсилає запит через твій `Dio` і типізує результат.
  `CallOptions` несе токен скасування, заголовки, `extra` і колбеки прогресу
  для одного виклику. Заголовки з `CallOptions.headers` мають перевагу над
  заголовками-параметрами операції, але не над її `Content-Type`: тип вмісту
  тіла запиту (наприклад `application/json`) завжди виграє, тож
  `Content-Type`, заданий там, ігнорується, коли операція надсилає тіло.
- Декодер потоку подій (`text/event-stream`) за WHATWG;
  `DioRequestSender.openEvents` повертає `Result`, у `Success` якого лежить
  потік із `SseEvent`, `SseDecodeError` (одна погана подія) і наприкінці
  `SseDisconnected`. Проблеми з даними — це елементи потоку, а не помилки
  потоку (єдиний виняток: `Error` з твого декодера подій — це баг програми,
  тож він доходить до слухача як помилка потоку, і потік закривається).
  Слухай потік або скасуй його: потік, який ніхто не слухає, тримає
  з'єднання відкритим. Скасування підписки скасовує запит.
- Перепідключення за замовчуванням вимкнене. Виклик вмикає його через
  `CallOptions(sse: SseOptions(reconnect: true))`; операція може ввімкнути
  його для кожного виклику (override `sse.reconnect` або ключ конфігу
  генератора), і тоді `reconnect: false` у виклику його вимикає. GET може
  перепідключатися, коли про це просить виклик; будь-який інший метод — лише
  коли його операція це вмикає, бо повтор запиту може бути небезпечним. Коли
  з'єднання закінчується, потік видає `SseReconnecting` (спроба, затримка і
  причина), чекає і відкриває запит знову з останнім id події як
  `Last-Event-ID` (id, що не є друкованим ASCII, не надсилається). Очікування
  — це `retry` сервера, інакше 1 с, що подвоюється до межі 30 с (`retry`
  сервера понад межу зберігається). Після 5 спроб поспіль без жодного
  повідомлення потік закінчується; повідомлення на новому з'єднанні (подія,
  також така, що не декодується або яку твій декодер відкидає) починає
  відлік заново. 204 від сервера, помилковий статус і скасування закінчують
  потік одразу; останній елемент — завжди `SseDisconnected` з останнім id
  події та `retry`, тож можна відновитися самому.

## Твій Dio використовується як є

- У твоєму `Dio` нічого не змінюється: base URL, заголовки, таймаути,
  інтерсептори, transformer і `validateStatus` лишаються твоїми. Повторів
  немає: це справа твоїх інтерсепторів.
- Помилкові статуси проходять через `onError` твоїх інтерсепторів, і лише
  потім типізуються.
- Кожен запит несе свій `OperationInfo` (operation id, метод, шаблон шляху,
  теги): `OperationInfo.of(options)` в інтерсепторі.
- Шлях і query кодує runtime і передає Dio одним рядком, тож в
  інтерсепторах `options.queryParameters` порожній; читай `options.uri`.
  Dio стискає кожне `//` готового URL; коли значення query містить `//`
  (значення з `allowReserved`, наприклад `next=/a//b`), а base URL
  абсолютний, runtime сам з'єднує base URL зі шляхом, щоб значення
  збереглося.

## Нотатки

- `Result` збігається з `Result` з `package:async`. У бібліотеці, що
  імпортує обидва, сховай один (`import 'package:async/async.dart' hide
  Result;`, або `import 'package:typed_openapi_runtime/typed_openapi_runtime.dart'
  hide Result;`) або імпортуй один із префіксом.
- JSON розбирає Dio. Коли тіло — невалідний JSON, Dio відкидає відповідь,
  тож `DecodeError` не має `statusCode`, а його `rawBody` — текст, який
  повідомив парсер Dio: усе тіло, коли Dio прочитав його одразу, і лише
  чанк із помилкою, коли Dio його стрімив (був заголовок `Content-Length`).
  Після компіляції в JavaScript Dio повідомляє лише текст `SyntaxError`
  браузера, тож там `rawBody` — `null`.
- `FormatException`, кинутий під час декодування (твій конвертер,
  `Date.parse`), — це проблема з даними: `DecodeError` у результаті,
  `SseDecodeError` у потоці подій. `Error` — це баг, його не ловлять.
- Параметр шляху, чий готовий вираз порожній або є сегментом `.` чи `..`
  (`''`, порожній список, `label` від `''`), кидає `ArgumentError`: клієнт
  прибрав би сегмент, і `/users/{id}/sessions` став би `/users/sessions`.
- `rawBody` у `DecodeError` і `UndocumentedStatus` — за можливістю: це тіло
  в тому вигляді, в якому його повернув Dio (розібраний JSON, текст або
  байти), або `null`, коли відповідь без тіла чи Dio нічого не зберіг.
- `date-time` має бути RFC 3339 зі зсувом (`2024-02-03T04:05:06Z`). Значення
  без зсуву — `DecodeError` з підказкою: для сервера, що пише інший формат,
  зістав формат зі своїм типом через конвертер (`types.formats`) або
  перевизнач `format` властивості в override-і. `date` має бути
  `YYYY-MM-DD`; `date-time`, надісланий замість нього, теж `DecodeError`.
- Цілі числа понад 2^53 на web втрачають точність, бо там `int` — це число
  JavaScript. Якщо в API є такі id, зістав властивість зі своїм типом через
  конвертер (`types.formats` або override `dartType`), наприклад
  `BigInt` або `String`: `JsonReader.asString` відхиляє JSON-число.

## Web

Пакет працює на web, зібраний у JavaScript (dart2js) або в WebAssembly
(dart2wasm). Потокам подій там потрібен потоковий адаптер: стандартний
браузерний адаптер Dio віддає тіло лише після закриття з'єднання, тож
операція з потоком подій повертає `TransportError` з поясненням
(`DioRequestSender.webStreamingMessage`). Постав у свій Dio адаптер на
fetch, наприклад `ConversionLayerAdapter` з `dio_compatibility_layer` з
`BrowserClient` з `package:http` або `fetch_client`. Перепідключення надсилає
`Last-Event-ID`, який не належить до заголовків запиту, дозволених CORS
за замовчуванням: для потоку з іншого origin сервер має дозволити
`Last-Event-ID` в `Access-Control-Allow-Headers` у відповіді на preflight,
інакше кожне перепідключення з id завершується `TransportError`.

Браузер не дозволяє сторінці виставляти заголовок `Cookie`, тож
cookie-параметри на web не працюють (браузер тримає свої cookie і надсилає
їх сам, за своїми налаштуваннями credentials). Тест перевіряє це в Chrome,
скомпільованому в JavaScript і в Wasm: заголовок `Cookie`, виставлений
через Dio, cookie-параметром чи напряму, ніколи не доходить до сервера, а
інші заголовки того самого запиту доходять.

## Розробка

```sh
dart test                                    # VM
dart test -p chrome                          # dart2js (потрібен Chrome)
dart test -p chrome --compiler dart2wasm     # dart2wasm
```

Файли й тести, що потребують VM (`dart:io`, літерали int64), позначені
`@TestOn('vm')` або `testOn: 'vm'`; `test/dio/web_test.dart` працює лише в
браузері. Якщо Chrome не знайдено, задай `CHROME_EXECUTABLE`.

[English version](README.md)
