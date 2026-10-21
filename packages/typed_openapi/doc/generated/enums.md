# Enums

An `enum` schema becomes an **open enum**: a sealed type with a Dart `enum` of the values the spec lists and an `Unknown` class for any other value the server sends. A new value on the server never breaks decoding.

```yaml
Priority:
  type: string
  enum: [low, medium, high]
  x-enum-varnames: [Low, Medium, High]
Severity:
  type: integer
  enum: [1, 2, 3]
  x-enum-varnames: [minor, major, critical]
```

## Generated shape (trimmed)

```dart
sealed class Priority {
  /// Decodes a [Priority]; a value the spec does not list is a
  /// [PriorityUnknown].
  factory Priority.fromJson(Object? json) { /* ... */ }

  /// `'low'`
  static const low = PriorityKnown.low;
  static const medium = PriorityKnown.medium;
  static const high = PriorityKnown.high;

  String get value;
  String toJson();
}

/// The values of [Priority] the spec lists.
enum PriorityKnown implements Priority { low('low'), medium('medium'), high('high'); /* ... */ }

/// A value of [Priority] the spec does not list; only [Priority.fromJson]
/// creates one.
class PriorityUnknown implements Priority { /* value, ==, hashCode, toString */ }
```

- `Priority.high` is the known value; `Priority.fromJson('urgent')` is `PriorityUnknown('urgent')` and `toJson()` writes `urgent` back, so a value you received survives a round trip.
- Both `PriorityKnown` and `PriorityUnknown` implement `Priority`, so a field of the model is typed `Priority`.
- `Priority.high == Priority.fromJson('high')` is `true`.
- Integer enums work the same way (`Severity.fromJson(3)` is `SeverityKnown.critical`, `value` is an `int`). Number and boolean enums are supported; an enum that mixes JSON types, or has objects or lists among its values, is generated as `JsonValue` (`TOA350`).
- Only a `Unknown` created by `fromJson` exists: its constructor is private, so you cannot send a value the spec does not list.

## Using them

Switch over a field and handle the unknown case; the compiler checks that you do:

```dart
String label(Priority p) => switch (p) {
  PriorityKnown.low => 'low',
  PriorityKnown.medium => 'medium',
  PriorityKnown.high => 'high',
  PriorityUnknown(:final value) => 'other: $value',
};

label(Priority.fromJson('high'));   // high
label(Priority.fromJson('urgent')); // other: urgent
```

**As an argument** a method takes the known type only, because the client cannot send what the spec does not list:

```dart
Future<Result<List<Book>, Never>> listBooks({GenreKnown? genre, int? limit, CallOptions? call});
```

```dart
await client.books.listBooks(genre: GenreKnown.fiction);
```

**In a model** (a response) the field is the open type (`final Genre? genre`), so you see unknown values. In a request model the constructor takes the known type, too (`StatusKnown? this.status`).

An unknown value in a response, as the library example prints it: `genre: GenreUnknown(poetry)`.

## Naming values

Value names are lowerCamelCase of the spec's value, in this order:

1. `x-enum-varnames` (a list of strings as long as the enum). `x-enum-descriptions` becomes doc comments. A list of the wrong length or type is ignored with `TOA351`.
2. The value itself (`in-progress` gives `inProgress`).

| Case | Result |
| --- | --- |
| Reserved word (`default`, `class`) | trailing underscore (`default_`), `TOA550` |
| Value `unknown` | `unknown_` |
| Value with no letter or digit (`~`, `""`) | `value_`, `value_2`..., `TOA552` info: add `x-enum-varnames` to name it |
| Two values with the same name | `2`, `3` after the first, `TOA551` |
| A repeated value | removed, first one kept, `TOA301` |
| Enum named in the spec at `components.schemas` | that key; an inline enum is named after its own site: the property (`TicketKind` for `Ticket.kind`) or the operation and parameter; two inline enums with equal values are two types |

## Exhaustive or open for switching

By default the base is `sealed`, so a `switch` over it must cover `PriorityUnknown` too. An override `exhaustive: false` generates `abstract interface class` instead, for a type you want to allow other implementations of; a `switch` then needs a default arm:

```yaml
schemas:
  Level:
    exhaustive: false
```

`exhaustive` has no effect on a model (the override says so with a diagnostic).

## Nullable enums

A nullable enum (`type: [string, 'null']` with `enum`, or a `$ref` with `null`) is the same type with a `?`. The OpenAPI 3.0 pattern of `oneOf` with an enum of only `null` plus a `$ref` is read as nullable and reported (`TOA303`).

## Enums in unions and formats

A string field with `anyOf: [string, {enum: ['']}]` is not an enum; the enum branch adds nothing and is dropped into the doc comment's "Known values" (`TOA455`, see [Unions](unions.md)).

## See also

- [Overrides](../overrides.md): `name`, `exhaustive` and spec fields of a schema.
- [Models](models.md) and [Unions](unions.md).
- [Troubleshooting](../troubleshooting.md): "my enum value became Unknown".
