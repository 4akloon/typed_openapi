# Models

Every object schema the API reaches becomes a plain, `@immutable` Dart class in `models/<snake_case>.dart` with `fromJson`, `toJson`, value equality and a `toString`. Only schemas an operation (or another model) can reach are generated; an unused entry of `components.schemas` produces nothing.

The examples below come from this spec, generated with `tri_state: patch`:

```yaml
components:
  schemas:
    User:
      type: object
      description: An account.
      required: [id, name]
      properties:
        id: {type: integer, format: int64, readOnly: true}
        name: {type: string, minLength: 1, maxLength: 80}
        nickname: {type: string}
        email: {type: [string, 'null'], format: email}
        password: {type: string, format: password, writeOnly: true}
        createdAt: {type: string, format: date-time, readOnly: true}
        birthday: {type: string, format: date}
        score: {type: number, default: 0.5}
        tags: {type: array, items: {type: string}}
        schemaVersion: {const: 2}
        legacyId: {type: string, deprecated: true, description: Use id.}
      additionalProperties: {type: string}
```

## The class

```dart
/// An account.
@immutable
class User {
  /// Creates a [User].
  const User({
    required this.id,
    required this.name,
    this.nickname,
    this.email,
    this.createdAt,
    this.birthday,
    this.score,
    this.tags,
    this.legacyId,
    this.additionalProperties = const {},
  });

  /// Decodes a [User] from [json]; throws a `JsonDecodeException` when it does
  /// not match the schema.
  factory User.fromJson(Map<String, Object?> json) { /* ... */ }

  /// Always `2`.
  int get schemaVersion => 2;

  final int id;

  /// 1–80 characters.
  final String name;

  final String? nickname;
  final DateTime? createdAt;
  final Date? birthday;

  /// Defaults to `0.5` on the server.
  final num? score;

  /// Use id.
  @Deprecated('Deprecated in the API spec.')
  final String? legacyId;

  /// The properties of the object the schema does not list
  /// (`additionalProperties`).
  final Map<String, String> additionalProperties;

  /// Encodes this [User]; optional fields that are not set are not sent.
  Map<String, Object?> toJson() => { /* ... */ };
}
```

(Trimmed; the real file also has `==`, `hashCode` and `toString`.)

- **Classes are plain `class`es**, not `final class`, so you can extend them. They are `@immutable`; `immutable` is re-exported by the runtime, so a generated file imports the runtime only.
- **Named arguments only.** Required properties are `required`; optional ones are nullable and omitted from `toJson` when unset.
- **There is no `copyWith`.** Build a changed copy with the constructor, or keep your own extension.
- **`==` and `hashCode` are by value**, deep for lists, maps and `Patch` fields (`DeepEquality` of the runtime). A decoded model equals the model decoded from its own `toJson()`.
- **Doc comments** carry the spec's `description`, length and range constraints (`1–80 characters.`), `default` (`Defaults to ...on the server.`) and, for a field that collapsed an enum branch, `Known values: ...` (see [Unions](unions.md)). Markdown that would break dartdoc (`[`, `<`, `{@`) is escaped, and spec text never reaches code unescaped.
- **`deprecated: true`** gives `@Deprecated('Deprecated in the API spec.')` on the field (and on a method, see [Operations](operations.md)).
- **Dart reserved words** and names Dart already has get a trailing underscore (`class` becomes `class_`, `TOA550`); the JSON key stays `class`.

## Dart types

| Schema | Dart |
| --- | --- |
| `integer` | `int` |
| `number` | `num`; `double` for `format: float` or `double`; `types.number: double` or `int` changes the default |
| `string` | `String` |
| `string`, `format: date-time` | `DateTime`, always UTC; RFC 3339 with an offset is required on decode |
| `string`, `format: date` | `Date` (runtime class: no time, no zone) |
| `string`, `format: byte` | `Uint8List` (base64 in JSON) |
| `string`, `format: binary` | `Uint8List` in a body; `FileUpload` in a multipart part or a binary body |
| other `format` (`uuid`, `email`, `int64`...) | the base type; map one with `types.formats` |
| `boolean` | `bool` |
| `array` | `List<T>` |
| object with `additionalProperties` | `Map<String, T>` |
| no type, `{}`, `true` | `JsonValue` (runtime extension type over `Object?`) |
| `enum` | [an open enum](enums.md) |
| `oneOf`, `anyOf` | [a union](unions.md), or `JsonValue` |

Custom types replace a `format` or a schema. The setting is in [Configuration](../configuration.md):

```yaml
clients:
  billing:
    types:
      number: double
      formats:
        decimal: {type: Decimal, import: 'package:decimal/decimal.dart'}
```

A property with `format: decimal` is then a `Decimal` and is decoded with `Decimal.fromJson(...)` and encoded with `.toJson()`. The package must be a dependency of your project; the generator does not check. A `converter` entry changes the calls to `const Converter().fromJson(...)` and `.toJson(value)`; the required shape is in [Configuration](../configuration.md#the-shape-of-a-custom-type).

## Decoding

`fromJson` is strict, and the error says where. It throws a `JsonDecodeException` for the first mismatch (and never prints the value, which may be a secret):

```dart
User.fromJson({'id': 'one', 'name': 'Ann'});
// JsonDecodeException: expected an integer, got a string at /id in User

User.fromJson({'id': 1});
// JsonDecodeException: expected a required property, got no value at /name in User

User.fromJson({'id': 1, 'name': 'A', 'schemaVersion': 3});
// JsonDecodeException: expected the constant 2, got another value at /schemaVersion in User

User.fromJson({'id': 1, 'name': 'A', 'createdAt': '2026-01-01T00:00:00'});
// JsonDecodeException: expected an RFC 3339 date-time string, got a date-time without an offset at /createdAt in User. ...
```

You rarely call `fromJson` yourself: a generated method catches the exception and returns it as a `DecodeError` (see [Responses and errors](responses_and_errors.md)). The only widening is an `int` where a number is expected. Details of the reader are in the [runtime guide on JSON decoding](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/json_decoding.md).

## Required, optional, nullable

| In the spec | Dart | Decoding |
| --- | --- | --- |
| in `required`, not nullable | `T x`, `required` | absent or `null` is an error |
| in `required`, nullable (`type: [T, 'null']`, `nullable: true`) | `T? x`, `required` | must be present; `null` allowed; `toJson` writes `null` |
| optional, not nullable | `T? x` | absent is `null`; a `null` value is read as absent |
| optional, nullable | `T? x` | `null` and absent are both `null` |

Optional fields that are `null` are left out of `toJson`.

### Tri-state fields for PATCH

An optional nullable property cannot say "leave it" and "set it to null" with a plain `T?`. With `tri_state: patch` (the default; `optional` and `extension` are the other values, set in `defaults` or on a client), the optional nullable properties of **PATCH request bodies** become `Patch<T>?`:

```dart
final patch = UserPatch(
  email: const PatchNull(),            // send "email": null
  nickname: const PatchValue('Ann'),   // send "nickname": "Ann"
  // name: not set                     // not sent
);
patch.toJson(); // {nickname: Ann, email: null}
const UserPatch(name: 'Bo').toJson(); // {name: Bo}
UserPatch.fromJson({'email': null}).email; // Patch.nullValue()
UserPatch.fromJson({}).email;              // null
```

```dart
class UserPatch {
  const UserPatch({this.nickname, this.email, this.name});
  final Patch<String>? nickname;   // optional and nullable in the spec
  final Patch<String>? email;
  final String? name;              // optional, not nullable: a plain String?
}
```

Only PATCH bodies are affected, and only their optional nullable properties. A PATCH body schema that other operations use too is generated as a separate class named with `naming.patch_suffix` (`Patch` by default, `PetPatch`), so the other uses keep plain fields. The override `triState` does the same for one schema or property. See the runtime guide on [patch and nullability](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi_runtime/doc/patch_and_nullability.md).

## Constants and defaults

- **`const` and one-value enums** of a property are not constructor arguments. A required constant is a plain getter; an optional one is a getter (`int get schemaVersion => 2`) and the class remembers whether the decoded JSON had it, so `toJson` of a decoded value omits what the server omitted, and a model built in code writes the constant.
- **`default`** is documentation: the field stays nullable and the value is never sent for you (`Defaults to 0.5 on the server.`). The same holds for parameters. A required property's default is not documented. A default that does not match its type or format is dropped (`TOA211`, `TOA660`).

## Unknown properties

- `additionalProperties: false`, `true` or absent: unknown JSON keys are ignored.
- `additionalProperties` with a schema: they are collected into `additionalProperties` (`Map<String, T>`), decoded with the schema and written back by `toJson`.
- An object that only has `additionalProperties` with a schema is a `Map<String, T>`, not a class.

## `allOf`

`allOf` is merged into one flat class. Properties of all parts are in the class, `required` lists are united, and a property defined twice keeps the later definition (`TOA252` says so when they differ):

```yaml
Admin:
  allOf:
    - $ref: '#/components/schemas/User'
    - type: object
      required: [level]
      properties:
        level: {type: integer}
```

gives `class Admin` with every field of `User` plus `required this.level`. There is no inheritance between `Admin` and `User`, so an `Admin` is not a `User`. If you need that relation, use a base with a discriminator (see [Unions](unions.md)). An `allOf` part without structure (annotations, `nullable`) is set aside and a single `$ref` part stands for the schema itself. Parts that cannot be merged (`TOA253`) and properties beside a union (`TOA256`) are reported.

## Request and response models

`readOnly` properties are never sent and `writeOnly` ones are never received. A schema that is used in only one direction drops the other kind. A schema used **both** ways is generated twice:

| Class | Used for | Has |
| --- | --- | --- |
| `User` | responses | `id`, `createdAt` (read-only); no `password` |
| `UserInput` | request bodies | `password` (write-only); no `id`, `createdAt` |

The suffix is `naming.input_suffix` (`Input`; it must differ from `patch_suffix`). A method takes `UserInput body` and returns `User`.

## Secrets are never printed

`toString` writes `<redacted>` for a secret property: `writeOnly`, `format: password`, or one that reaches a schema with those through a `$ref`, an annotation-only `allOf` part, a nullable `anyOf` (Pydantic's `Optional[SecretStr]`), array items, map values or a union variant:

```dart
print(Problem(code: 'E1', password: 'hunter2'));
// Problem(code: E1, password: <redacted>)
```

A value that stays raw JSON (`JsonValue`, the `...Unknown` class of a union) is redacted too when its schema could hold a secret at any depth. `toJson` still writes the real value: redaction protects logs and `print`, not the wire. Exceptions never contain values either.

## Objects with no properties and mixed types

- An object with neither properties nor `additionalProperties` is `Map<String, JsonValue>`.
- A required `const` property (`kind: {const: open}`) is a getter (`String get kind => 'open'`) and decoding checks it.
- A schema whose `type` list holds several non-null types is `JsonValue` (`TOA250`).
- A schema that reaches itself with no declaration in between is a warning (`TOA251`); recursive models themselves are fine (`Thing? shape` of `Thing`).

## See also

- [Enums](enums.md) and [Unions](unions.md) for the other two declaration kinds.
- [Overrides](../overrides.md) to fix types, nullability and names without touching the backend.
- [Presets and rules](../presets_and_rules.md) for the normalizer fixes that run before models are built.
- [Troubleshooting](../troubleshooting.md).
