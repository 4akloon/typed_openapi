# Patch and nullability

A JSON object has three ways to treat a property: leave it out, send `null`,
or send a value. A plain Dart `String?` can say only two of them. `Patch<T>`
is the third state: a field of type `Patch<T>?` is **absent** when it is
`null`, an **explicit `null`** when it is `Patch.nullValue()`, and a **value**
when it is `Patch.value(x)`. This matters for `PATCH` requests, where "leave
it alone" and "clear it" are different instructions.

## The three states

```dart
class UpdatePet {
  const UpdatePet({this.name, this.tag});
  final String? name;
  final Patch<String>? tag;   // tri-state
  // ...
}

const UpdatePet();                                  // {}
const UpdatePet(tag: Patch.nullValue());            // {"tag":null}
const UpdatePet(tag: Patch.value('good boy'));      // {"tag":"good boy"}
const UpdatePet(name: 'Rex', tag: .nullValue());    // {"name":"Rex","tag":null}
```

The JSON on the wire, taken from the request body the generated client
sent through an in-memory adapter:

| Dart | Request body |
| --- | --- |
| `UpdatePet()` | `{}` |
| `UpdatePet(tag: Patch.nullValue())` | `{"tag":null}` |
| `UpdatePet(tag: Patch.value('good boy'))` | `{"tag":"good boy"}` |
| `UpdatePet(name: 'Rex', tag: .nullValue())` | `{"name":"Rex","tag":null}` |

## The API

| Member | Meaning |
| --- | --- |
| `Patch.value(x)` | Sends `x` (`PatchValue<T>`, holds `value`) |
| `Patch.nullValue()` | Sends an explicit `null` (`PatchNull<T>`) |
| `valueOrNull` | The value, or `null` for `PatchNull` |
| `toJson(encode)` | `encode(value)`, or `null` for `PatchNull` |

`Patch` is a sealed class with two final subclasses, `PatchValue` and
`PatchNull`, so it matches exhaustively. Both are `const`-constructible
(`Patch.value(x)` is `const` when `x` is), and both have value equality
(`Patch.value(3) == Patch.value(3)`; two `nullValue()` are equal).
`DeepEquality` compares the values of two `PatchValue`s deeply, so
`Patch.value([1, 2])` equals another `Patch.value([1, 2])`.

```dart
switch (update.tag) {
  case null:            print('absent');
  case PatchNull():     print('explicit null');
  case PatchValue(:final value): print('value $value');
}
```

`toJson` takes the encoder for the value, because `T` may be a model, a date
or a list:

```dart
Patch.value(DateTime.utc(2024)).toJson((d) => d.toIso8601String());
// 2024-01-01T00:00:00.000Z
```

## How generated models use it

Which properties become `Patch<T>?` is decided by the generator's
[`tri_state`](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/configuration.md)
setting and per-property overrides. The default rule applies to the optional,
nullable properties of `PATCH` request bodies. Other fields keep their plain
Dart type, as `name` does above.

A generated model encodes only the fields that are set:

```dart
Map<String, Object?> toJson() => {
  'name': ?name,                                       // null-aware element: skipped when null
  if (tag case final v?) 'tag': v.toJson((p0) => p0),  // absent / null / value
};
```

and decodes with `JsonReader.patch`, which tells the three apart:

```dart
tag: r.patch('tag', JsonReader.asString),
```

```text
{}              -> tag=null                  (absent)
{"tag":null}    -> tag=Patch.nullValue()     (explicit null)
{"tag":"x"}     -> tag=Patch.value(x)
```

`JsonReader.patchValue(key)` does the same for a property of any JSON value
(`Patch<JsonValue>?`).

> **Gotcha:** A `JsonValue` over `null` is `null` at run time, so a plain
> `JsonValue` field cannot tell an absent property from an explicit `null`.
> Only `Patch<JsonValue>` can.

## Plain optional and nullable fields

For comparison, the other combinations of a property decode as follows (see
the table in [JSON decoding](json_decoding.md)): an optional property reads
absent and `null` both as `null`, a required nullable one reads `null` as
`null` and fails when absent, a required non-null one fails on both. Only
`Patch` keeps absent and `null` apart.

## Sending a `null` body

The body of a request is not a property: a required nullable body is the JSON
value `null`, which the runtime sends as the text `null` with its
`Content-Type`. See [Request bodies](request_bodies.md#json).

## See also

- [JSON decoding](json_decoding.md) - `required`, `optional`, `patch`.
- [Request bodies](request_bodies.md) - how a model's `toJson` result is sent.
- How the generator decides tri-state fields:
  [generated models](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/models.md).
