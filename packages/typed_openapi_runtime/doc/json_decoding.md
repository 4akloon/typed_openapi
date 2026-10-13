# JSON decoding

Generated models decode themselves with `JsonReader`: a strict reader that
stops at the first mismatch and says where it is. A mismatch throws
`JsonDecodeException`; the request sender turns it into a `DecodeError`, so
it never reaches the caller of a generated method. This guide lists the rules
a model follows and the helpers around them (`JsonValue`, `Date`,
`DeepEquality`).

## What a generated `fromJson` looks like

```dart
factory Pet.fromJson(Map<String, Object?> json) {
  final r = JsonReader(json, schema: 'Pet');
  return Pet(
    id: r.required('id', JsonReader.asInt),
    score: r.required('score', JsonReader.asDouble),
    nick: r.requiredNullable('nick', JsonReader.asString),
    born: r.optional('born', JsonReader.asDateTime),
    tags: r.optional('tags', JsonReader.listOf(JsonReader.objectOf(Tag.fromJson))),
    extra: r.additional({'id', 'score', 'nick', 'born', 'tags'}, JsonReader.asString),
  );
}
```

Every read takes a decoder, `T Function(Object? value)`: one of the static
`as...` decoders, a combinator (`listOf`, `mapOf`, `objectOf`, `nullable`), a
generated `fromJson`, or your own converter. Undeclared properties are
ignored (unless a model collects them with `additional`).

## Required, nullable and optional

| Read | Absent | `null` | Other value |
| --- | --- | --- | --- |
| `required` | error `a required property` | error `a non-null value` | decoded |
| `requiredNullable` | error `a required property` | `null` | decoded |
| `optional` | `null` | `null` | decoded |
| `patch` | `null` (no patch) | `Patch.nullValue()` | `Patch.value(...)` |

`optional` serves optional properties whether or not the schema also allows
`null`: the Dart field is `T?` either way, so absent and `null` read the same.
Use `patch` ([Patch and nullability](patch_and_nullability.md)) when the two
must be told apart. `requiredValue`, `optionalValue` and `patchValue` do the
same for a property of any JSON value.

Results for the model above, one line per input (`/id` is a JSON pointer):

```text
absent required -> /id   | expected: a required property | actual: no value
null required   -> /id   | expected: a non-null value     | actual: null
absent nullable -> /nick | expected: a required property | actual: no value
optional null   -> ok (born = null)
string where int-> /id   | expected: an integer           | actual: a string
nested index    -> /tags/1/name | expected: a string     | actual: a number
```

## Types are strict

The only widening is an `int` where a `number` is expected.

| Decoder | Accepts | Rejects |
| --- | --- | --- |
| `asString`, `asBool` | a string, a boolean | everything else (`"true"`, `0`) |
| `asInt` | a JSON integer | a double, even `1.0`; a string |
| `asDouble` | any finite number (an integer is widened) | a string; `1e400` |
| `asNumber` | any finite number, as `num` | a string; `1e400` |
| `asList`, `listOf` | an array; a problem in an item gets the index in its path | an object |
| `asObject`, `objectOf`, `mapOf` | an object (string keys only) | an array; a map with a non-string key |
| `asValue` | anything, as `JsonValue` | nothing |
| `asBytes` | a base64 string (`format: byte`), URL-safe alphabet and missing padding accepted | a string that is not base64 |
| `asDateTime`, `asDate` | see below | see below |

- `asInt(1.0)` fails: `jsonDecode` gives an `int` for every integer literal
  that fits, so a double means the server wrote a fraction or an exponent, or
  a number too big for `int`. **On JavaScript** `1.0` *is* the integer `1`, so
  it is accepted there ([Web and platforms](web_and_platforms.md)).
- JSON has no infinity, but `jsonDecode('1e400')` gives one. It is rejected as
  `a finite number`, because `jsonEncode` could not write it back.
- `nullable(decode)` wraps a decoder to accept `null`, for nullable array
  items and map values. `mapOf` keeps the JSON key order.

## Dates and times

`asDateTime` (`format: date-time`) accepts **RFC 3339 with an offset**:
`2024-02-03T04:05:06Z`, `2024-02-03T04:05:06.5+02:00`. It rejects:

- a date-time without an offset (it does not name an instant);
- dates that do not exist (`2024-02-30`);
- leap seconds (`23:59:60`), which `DateTime` would silently roll over.

```text
date ok          -> 2024-02-03 02:05:06.500Z
date no offset   -> /born | expected: an RFC 3339 date-time string | actual: a date-time without an offset
date feb 30      -> /born | expected: an RFC 3339 date-time string | actual: a string in another format
leap second      -> /born | expected: an RFC 3339 date-time string | actual: a string in another format
```

The error carries a hint for a server that sends another format on purpose:

```text
JsonDecodeException: expected an RFC 3339 date-time string, got a date-time without an offset. If the server sends this format on purpose, map it to your own type with a converter (types.formats in the config) or override the property's format
```

The fix is in the generator config
([`types.formats`](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/configuration.md)),
not in the runtime.

`asDate` (`format: date`) returns a `Date`: a calendar date without a time or
a zone.

```dart
Date(2024, 2, 29);                    // 2024-02-29
Date.parse('2024-02-29');             // exactly YYYY-MM-DD
Date.tryParse('2024-02-30');          // null: the date does not exist
Date.fromDateTime(DateTime(2024, 5, 6, 23)); // 2024-05-06, no conversion to UTC
Date(2024, 2, 29).toJson();           // '2024-02-29'
```

- `Date(y, m, d)` throws `ArgumentError` (a `RangeError`) for a year outside
  0..9999, a month outside 1..12 or a day that does not exist.
- `Date.parse` throws `FormatException`: `Not an RFC 3339 full-date
  (YYYY-MM-DD)` for a time part, an offset, surrounding whitespace, another
  separator or `2024-2-3`.
- `Date` is comparable (`isBefore`, `isAfter`, `compareTo`), has value
  equality and `toDateTimeUtc()` (midnight UTC).
- A date-time sent where a date is declared is reported as such
  (`actual: a date-time`).

## `JsonDecodeException`

```dart
try {
  Pet.fromJson(json);
} on JsonDecodeException catch (e) {
  print(e.pointer);   // /tags/1/name  (RFC 6901; '' is the decoded value itself)
  print(e.expected);  // a string
  print(e.actual);    // a number
  print(e.schema);    // Tag           (the schema whose fromJson found it)
  print(e.field);     // name          (null when the problem is not in a property)
  print(e.hint);      // advice, or null
}
```

| Member | Meaning |
| --- | --- |
| `expected` / `actual` | What the schema wants and what the JSON has, as phrases (`an integer`, `a string`, `no value`, `null`, `an object`, `an array`, `a boolean`, `a number`) |
| `path` / `pointer` | Keys (`String`) and indexes (`int`) to the problem; `pointer` is the RFC 6901 form with `~` as `~0` and `/` as `~1` |
| `schema` | The innermost schema name that was reading when it failed |
| `field` | The last path segment when it is a key |
| `hint` | A fix for a server that sends the value on purpose (dates) |
| `message` | `expected ..., got ...` |

`toString` reads `JsonDecodeException: expected an integer, got a string at
/id in Pet`.

**The value is never in the message**, only its JSON type: values can be
large or private. A `FormatException` thrown by a decoder (a converter,
`DateTime.parse`) is the one exception to the wording, because its message is
the decoder's own; it becomes a `JsonDecodeException` at the property:

```text
converter -> /when expected a value its decoder accepts, got a value it rejected: Invalid date format
escaped pointer: /a~1b~0c
```

The first mismatch stops decoding: you get one error, not a list.

## Depth limit

`JsonReader.maxDepth` is 1000. `RawResponse.json`, `SseMessage.json` and
`JsonReader.checkDepth` check that arrays and objects nest at most that deep,
**without recursion**, so a hostile body cannot overflow the stack of a
recursive `fromJson` or `jsonEncode`. A deeper value is a
`JsonDecodeException` (`expected arrays and objects nested at most 1000
deep, got deeper nesting`) whose path points at the first container that is
too deep.

```text
1000 levels ok
1001 -> expected arrays and objects nested at most 1000 deep, got deeper nesting; pointer length 2000
```

## `JsonValue`: any JSON

A schema without constraints (`{}`, `true`) is a `JsonValue`, an extension
type over the decoded value. It costs nothing at run time and `jsonEncode`
accepts it as it is. Its accessors never throw: a value of another JSON type
gives `null`, and indexing a missing key or index gives `JsonValue(null)`, so
lookups chain.

```dart
final v = JsonValue(jsonDecode('{"a":[{"b":"deep"}],"n":1.5}'));
v['a'][0]['b'].asString; // 'deep'
v['zzz'][3].asString;    // null
v['n'].asNumber;         // 1.5
v['n'].asString;         // null (wrong type)
v['zzz'].isNull;         // true
```

`raw`, `asObject`, `asList`, `asString`, `asNumber`, `asBool` and `isNull`
complete the API. A `JsonValue` over `null` is `null` at run time, so an
absent property and an explicit `null` are the same (`optionalValue`); use
`patchValue` to tell them apart.

## Constants, additional properties, unions

- `constant(key, value, {required})` checks a property that holds one value
  (`const`, a one-value enum) and returns whether it was there. A wrong value
  is `expected the constant "dog", got another value`. An optional constant
  may be absent or `null`, which read as absent.
- `additional(known, decode)` returns the properties a model does not list as
  an unmodifiable map in JSON order. A value that fails to decode names its
  key in the pointer (`/color`).
- `attempt(() => ...)` returns `null` instead of throwing; a union without a
  discriminator tries its variants with it (`union: structural`).

## `DeepEquality`

Generated models use value equality built on `DeepEquality`: lists compare
item by item in order, maps by key in any order, `PatchValue`s by their
values, everything else with `==`. A `JsonValue` is its raw value, so JSON of
any shape compares by content. `hash` agrees with `equals`.

```dart
const eq = DeepEquality();
eq.equals([1, {'a': [2]}], [1, {'a': [2]}]);          // true
eq.equals({'a': 1, 'b': 2}, {'b': 2, 'a': 1});        // true
eq.equals(Patch.value([1, 2]), Patch.value([1, 2]));  // true
```

> **Gotcha:** `DeepEquality` starts with `identical`. On JavaScript
> `identical(double.nan, double.nan)` is false, so `NaN` is not equal to
> itself there, while it is on the VM and dart2wasm. JSON has no `NaN`, so a
> decoded value never holds one.

## See also

- [Results and errors](results_and_errors.md) - `DecodeError` and its `rawBody`.
- [Patch and nullability](patch_and_nullability.md) - absent versus `null`.
- [Web and platforms](web_and_platforms.md) - integers beyond 2^53, `1.0`.
- How the generator picks types and formats:
  [generated models](https://github.com/4akloon/typed_openapi/blob/main/packages/typed_openapi/doc/generated/models.md).
