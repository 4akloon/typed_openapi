# Request bodies

The request body of an operation is the `body` argument of its method. Its Dart type and the `Content-Type` follow the media type the generator picks: JSON first, then multipart, form, text, event stream; anything else is bytes.

| Media type | `body` type | Sent as |
| --- | --- | --- |
| `application/json`, `text/json`, `+json` | the model, list, map or scalar | `body.toJson()`, `application/json` |
| `application/x-www-form-urlencoded` | the model | `FormBody` with the spec's `encoding` |
| `multipart/form-data` | a generated parts class | `MultipartBody(body.toParts())` |
| `text/*` | `String` | as given, with that media type |
| `application/octet-stream`, `image/*`, XML, any other | `FileUpload` | raw bytes or a stream, the media type of the spec (a wildcard becomes a concrete one) |

A body is `required` in the signature when the spec says `required: true`; otherwise it is nullable and, when `null`, no `Content-Type` is sent. A required body whose schema is nullable sends the JSON `null`. A media type that is dropped because the operation offers several is named in `TOA651`; one sent as bytes without its schema is `TOA650`.

## JSON

```dart
Future<Result<User, Never>> createUser({required UserInput body, CallOptions? call});
```

```dart
OperationRequest(_createUser, body: body.toJson(), contentType: 'application/json')
```

The body model is the request side of the schema (read-only properties dropped, see [Models](models.md)).

## Forms

```yaml
requestBody:
  content:
    application/x-www-form-urlencoded:
      schema:
        type: object
        properties:
          petId: {type: integer}
          tags: {type: array, items: {type: string}}
          meta: {type: object, additionalProperties: {type: string}}
      encoding:
        tags: {explode: false}
        meta: {style: deepObject, explode: true}
```

```dart
body: body == null
    ? null
    : FormBody(body.toJson(), {
        'meta': FormEncoding(style: .deepObject, explode: true),
        'tags': FormEncoding(explode: false),
      }),
contentType: body == null ? null : 'application/x-www-form-urlencoded',
```

An `encoding` key that names no property of the schema is `TOA659` and ignored; a style the form does not allow is `TOA564`; `headers` in an encoding are ignored (`TOA656`).

## Multipart

A multipart body gets a **parts class** after the group class, one field per property:

```yaml
multipart/form-data:
  schema:
    type: object
    required: [file]
    properties:
      file: {type: string, format: binary, description: The photo.}
      extra: {type: array, items: {type: string, format: binary}}
      caption: {type: string}
      meta: {$ref: '#/components/schemas/Job'}
  encoding:
    file: {contentType: image/png}
```

```dart
class UploadPhotoRequest {
  const UploadPhotoRequest({required this.file, this.extra, this.caption, this.meta});

  /// The photo.
  final FileUpload file;
  final List<FileUpload>? extra;
  final String? caption;
  final Job? meta;

  /// The parts, in the order of the schema.
  List<MultipartPart> toParts() => [
    MultipartPart.file('file', file, contentType: 'image/png'),
    for (final file in [...?extra]) MultipartPart.file('extra', file),
    MultipartPart.value('caption', caption),
    if (meta case final value?) MultipartPart.value('meta', value.toJson()),
  ];
}
```

```dart
await client.pets.uploadPhoto(
  petId: 1,
  body: UploadPhotoRequest(file: FileUpload.bytes(bytes, filename: 'cat.png'), caption: 'Tom'),
);
```

- Binary strings and lists of them are `FileUpload`; text and numbers are plain values; an object part is JSON (`application/json`).
- Parts are sent in schema order. Dio writes fields before files, so a text part stays a plain field only while no file or typed part precedes it; later text parts carry `Content-Type: text/plain; charset=utf-8`.
- A part `contentType` that is a list or a wildcard is sent as one concrete type: the file's own, else the first concrete one, else `application/octet-stream` (`TOA661` info). An object part with a non-JSON type is a `String` you supply (`TOA662` warning).
- A multipart schema that is not an object with properties (a union, a map) has no parts class: the body is the schema's type and each property is a part, a binary string as base64 text (`TOA655`).
- A value that is not a finite JSON scalar, or a list in a list, throws `ArgumentError` rather than being stringified.

## Files, text and bytes

```dart
Future<Result<void, Never>> putPhoto({required int petId, required FileUpload body, CallOptions? call});
Future<Result<JsonValue, SendNoteError>> sendNote({String? body, CallOptions? call}); // text/plain
```

`FileUpload.bytes(...)` works everywhere including the web; `FileUpload.stream(...)` takes a stream, which Dio's browser adapter buffers. Constructors and the content-type check are in the [runtime guide on request bodies](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/request_bodies.md).

## See also

- [Operations](operations.md) and [Responses and errors](responses_and_errors.md).
- [Troubleshooting](../troubleshooting.md).
