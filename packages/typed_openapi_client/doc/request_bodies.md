# Request bodies

A generated method puts its body into `OperationRequest.body` together with a
`contentType`, and `DioRequestSender` turns it into what Dio sends. The body
is one of: a JSON value (the `toJson()` of a model, or a string, number,
boolean, list or map), text, a `FormBody`, a `MultipartBody` or a
`FileUpload`; `null` means no body. This guide lists what goes on the wire
for each and which arguments throw. The bodies below were sent through an
in-memory Dio adapter and are shown as it recorded them.

## JSON

A body whose content type is `application/json`, `text/json` or any `+json`
type (`application/vnd.api+json`) is JSON.

| Body | `Content-Type` | Wire |
| --- | --- | --- |
| `{'name': 'Rex', 'tag': null}` | `application/json` | `{"name":"Rex","tag":null}` |
| `'a"b'` (a string) | `application/json` | `"a\"b"` |
| `null` (a required nullable body) | `application/json` | `null` |
| `'x'` | `application/vnd.api+json` | `"x"` |
| `null` | none (`contentType` is `null`) | no body, no `Content-Type` |
| `null` | `text/plain` | no body, no `Content-Type` |

The runtime encodes a JSON body itself only where Dio gets it wrong: Dio
sends a `String` as it is, so the string `a"b` would go out unquoted, and it
sends `null` as no body. A map, list, number or boolean stays Dio's data, so
an interceptor sees the object, not a string.

> **Gotcha:** A `null` body with a JSON content type is the JSON value
> `null`, and a generated method passes no `contentType` for an absent
> *optional* body, so nothing is sent for it. A `null` body with any other
> content type sends no `Content-Type` at all.

## Text and bytes

A text body (`text/plain`) is sent as the `String` it is. A binary body is a
`FileUpload` (below). A request is never given a type of the HTTP client:
signatures use `FileUpload`, `FormBody` and `MultipartBody` so that they do
not depend on Dio.

## `Content-Type` and `Accept`

- The **content type of the body always wins**. `CallOptions.headers` beats
  an operation's header parameters, but a `Content-Type` given there is
  ignored when the operation sends a body: it cannot pick
  `application/merge-patch+json`.
- A `FileUpload` with its own `contentType` wins over the spec's, and a
  multipart body gets `multipart/form-data; boundary=...` from Dio.
- `Accept`: the `OperationRequest.accept` of an operation that has both a
  body method and an event-stream method (for example `application/json`),
  so a server that picks by `Accept` does not answer with the stream. `null`
  sends none. An `Accept` in `CallOptions.headers` wins, in any case
  (`accept` and `Accept` are the same header). An event stream sends
  `text/event-stream` and ignores this.
- Responses are read as `ResponseKind.json`, `.text` or `.bytes` as the spec
  says; a JSON operation answered with `text/plain` gives a `String`, which a
  decoder that expects an object rejects ([Results and errors](results_and_errors.md)).

## Forms: `FormBody` and `FormEncoding`

`FormBody(json, [encoding])` is an `application/x-www-form-urlencoded` body:
each property of a JSON object is written like a [query
parameter](parameters.md#query-parameters) and the pairs are joined by `&`.
`null` properties are not sent. The default for a property is the `form`
style with explode; `FormEncoding` is the spec's `encoding` for one property:

| `FormEncoding` field | Meaning |
| --- | --- |
| `style` | A `QueryStyle`: `form` (default), `spaceDelimited`, `pipeDelimited`, `deepObject` |
| `explode` | `null` is the style's default |
| `allowReserved` | Keep reserved characters, as for a query |
| `json` | Send the value as JSON text (`contentType: application/json` in the spec) |

```dart
FormBody(
  {
    'name': 'Rex Jr',
    'tags': ['a', 'b'],
    'filter': {'min': 1, 'max': 5},
    'meta': {'k': 'v'},
    'skip': null,
  },
  {
    'tags': FormEncoding(explode: false),
    'filter': FormEncoding(style: QueryStyle.deepObject),
    'meta': FormEncoding(json: true),
  },
)
// name=Rex%20Jr&tags=a,b&filter%5Bmin%5D=1&filter%5Bmax%5D=5&meta=%7B%22k%22%3A%22v%22%7D
```

A value nested deeper than the style allows (an object inside an object
with `form`) throws `ArgumentError`, as for query parameters. A `json` that is
not an object is rejected too, but at a different time: `FormBody([1])` is
built and throws an `ArgumentError` ("A form body must be a JSON object") when
it is encoded, while `MultipartBody.fromJson([1])` throws at construction.

## Files: `FileUpload`

`FileUpload` is a file for a binary request body or a file part of a
multipart body.

```dart
FileUpload.bytes(bytes, filename: 'a.png', contentType: 'image/png');
FileUpload.stream(file.openRead(), length: await file.length());
```

- `.bytes` holds the data in memory and works on every platform.
- `.stream` sends the data as it is read and can be sent **once** (a stream
  is listened to once); `length` is required, and the runtime sends it as
  `Content-Length`, because Dio sends a stream as it is.
- `contentType` wins over the spec's; a value that is not a media type
  (`'nonsense'`) throws a `FormatException` when sending.
- On the web, Dio's browser adapter buffers a stream into one `Uint8List`
  before it sends, so a stream is not streamed there.

As a body of its own, a `FileUpload` is sent as the bytes or the stream with
its `contentType` (or the operation's). `FileUpload(a.bin, 3 bytes, x/y)` is
its `toString`.

## Multipart: `MultipartBody` and `MultipartPart`

`MultipartBody(parts)` is a `multipart/form-data` body, sent **in the order
of the parts**.

```dart
MultipartBody([
  const MultipartPart.value('title', 'Holiday'),
  const MultipartPart.value('tags', ['a', 'b']),
  const MultipartPart.value('meta', {'k': 1}),
  MultipartPart.file('photo', FileUpload.bytes(png, filename: 'a.png', contentType: 'image/png')),
  const MultipartPart.value('caption', 'late text'),
])
```

The wire body (boundary shortened, headers lower-cased as Dio writes them):

```text
----BOUNDARY
content-disposition: form-data; name="title"

Holiday
----BOUNDARY
content-disposition: form-data; name="tags"

a
----BOUNDARY
content-disposition: form-data; name="tags"

b
----BOUNDARY
content-disposition: form-data; name="meta"
content-type: application/json; charset=utf-8

{"k":1}
----BOUNDARY
content-disposition: form-data; name="photo"; filename="a.png"
content-type: image/png

PNGDATA
----BOUNDARY
content-disposition: form-data; name="caption"
content-type: text/plain; charset=utf-8

late text
----BOUNDARY--
```

### How a value part is written

| Value | Sent as |
| --- | --- |
| a string, finite number or boolean | text |
| an object | JSON, with `Content-Type: application/json` |
| a list | one part per item, all with the part's name |
| `null` | nothing |
| any value with a JSON `contentType` | JSON text |
| a scalar with another `contentType` | text with that media type (`text/csv; charset=utf-8`) |

`MultipartPart.value(name, value, {contentType})` takes the **JSON form** of
a property; `contentType` is the spec's `encoding` for it. `MultipartPart.file(name, file, {contentType})`
sends a file; the file's own `contentType` wins over the part's.
`MultipartBody.fromJson(json)` is for a schema with no parts class: a value
part for each property of the object, in order, `null` giving none
(`{'a': 1, 'b': null, 'c': true}` sends `a` and `c`).

### The ordering rule

Dio writes every plain field of a `FormData` before its files. A text part
stays a plain field **while no file or typed part precedes it** (the usual
shape: values first, files last), and sends no `Content-Type` for the text.
After the first file or typed part, text parts are sent as
`text/plain; charset=utf-8` parts (the `caption` above), so the wire order is
always the order of `MultipartBody.parts`.

### Errors

Each of these throws from the method, before any request is sent:

| Mistake | Error |
| --- | --- |
| A nested list (`[[1]]`) | `ArgumentError`: `Cannot be sent as a multipart part (a nested list); convert values with toJson` |
| `NaN`, an infinity or another non-JSON scalar | `ArgumentError`: `... (not a finite JSON scalar) ...` |
| An object with a media type that is not JSON (`text/plain`) | `ArgumentError`: `An object part cannot be sent as "text/plain": only JSON media types carry an object` |
| A non-JSON value in a JSON part | `ArgumentError`: `... (not JSON) ...` |
| A body that is not an object (`MultipartBody.fromJson([1])`) | `ArgumentError`: `A multipart body must be a JSON object` |
| A `contentType` that is not a media type | `FormatException` |

Values are never stringified: a `DateTime` in a part is a mistake, convert it
with `toJson` first.

## Progress

`CallOptions.onSendProgress` and `onReceiveProgress` are Dio's callbacks and
are passed through. On the web `dio_web_adapter` reports send progress when
the request has a body; see [Web and platforms](web_and_platforms.md).

## See also

- [Parameters](parameters.md) - the encoders `FormBody` reuses.
- [Patch and nullability](patch_and_nullability.md) - which JSON a model emits.
- [Getting started](getting_started.md) - `CallOptions` headers.
- What the generator writes for each body kind:
  [generated request bodies](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/request_bodies.md).
