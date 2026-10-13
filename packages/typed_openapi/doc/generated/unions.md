# Unions

A `oneOf` or `anyOf` becomes a `sealed` class with one wrapper class per variant and an `Unknown` variant that keeps the raw JSON of anything no variant takes. How a value picks its variant depends on what the spec offers: a discriminator, a distinct JSON type, or neither.

## With a discriminator

```yaml
Cat: {type: object, required: [kind, lives], properties: {kind: {type: string}, lives: {type: integer}}}
Dog: {type: object, required: [kind, barks], properties: {kind: {type: string}, barks: {type: boolean}}}
Pet:
  oneOf:
    - $ref: '#/components/schemas/Cat'
    - $ref: '#/components/schemas/Dog'
  discriminator:
    propertyName: kind
    mapping:
      cat: '#/components/schemas/Cat'
      kitty: '#/components/schemas/Cat'
      dog: '#/components/schemas/Dog'
```

Generated (trimmed):

```dart
sealed class Pet {
  /// Decodes a [Pet] by its `kind`; a value no variant has is a [PetUnknown].
  factory Pet.fromJson(Object? json) {
    final r = JsonReader.of(json, schema: 'Pet');
    return switch (r.json['kind']) {
      'cat' || 'kitty' => PetCat(Cat.fromJson(JsonReader.asObject(r.json))),
      'dog' => PetDog(Dog.fromJson(JsonReader.asObject(r.json))),
      _ => PetUnknown._(JsonValue(r.json)),
    };
  }
  Object? toJson();
}

class PetCat implements Pet { const PetCat(this.value); final Cat value; /* ==, toJson */ }
class PetDog implements Pet { const PetDog(this.value); final Dog value; /* ... */ }

/// A [Pet] that no variant takes; only [Pet.fromJson] creates one.
class PetUnknown implements Pet { final JsonValue json; /* ... */ }
```

Switching is exhaustive; the compiler makes you decide what to do with `PetUnknown`:

```dart
String describe(Pet pet) => switch (pet) {
  PetCat(:final value) => 'cat with ${value.lives} lives (kind ${value.kind})',
  PetDog(:final value) => 'dog, barks: ${value.barks}',
  PetUnknown(:final json) => 'unknown pet: ${json.raw}',
};

describe(Pet.fromJson({'kind': 'kitty', 'lives': 9})); // cat with 9 lives (kind kitty)
describe(Pet.fromJson({'kind': 'fish'}));              // unknown pet: {kind: fish}
Pet.fromJson({'kind': 'kitty', 'lives': 9}).toJson();  // {kind: kitty, lives: 9}
```

- A variant class is named `<Union><Variant>`; the wrapped model is `value`. Wrappers are equal by value.
- Several mapping values for one variant (`cat` and `kitty`) are all accepted, and the value a payload came with is kept, so it is written back as it arrived.
- A variant model that has no property for the discriminator gets it written by the wrapper: the remembered value, or the first mapping value for a variant built in code. (`PetCat(Cat(...)).toJson()` of such a model writes the discriminator.)
- `exhaustive: false` in the [overrides](../overrides.md) turns `sealed` into `abstract interface` (see [Enums](enums.md)).

### Where the value comes from

| Source | Rule |
| --- | --- |
| `mapping` entry | wins; a value may be a component name or a `#/...` reference |
| Not in the mapping, but the variant fixes the property to one value (`const`, a one-value `enum`, also through `$ref` or `allOf`) | that value selects it, `TOA457` info (OpenAI's tool unions) |
| Otherwise | the component name (`Cat`) |

`TOA457` shows what the generator derived so you can pin it:

```text
info TOA457 discriminator-value-derived: The mapping does not name this variant, and its discriminator property is always "web_search", so "web_search" selects it, not the component name "Search".
  fix: Add "web_search" to the mapping to say so, or map the name "Search" if the payloads carry it.
```

### Inheritance with `allOf`

A schema with a `discriminator` that other schemas extend with `allOf` is, where it is used as a type, a union of those subtypes:

```yaml
Animal:
  type: object
  required: [type]
  properties: {type: {type: string}, name: {type: string}}
  discriminator: {propertyName: type}
Bird: {allOf: [{$ref: '#/components/schemas/Animal'}, {type: object, properties: {wingspan: {type: number}}}]}
Fish: {allOf: [{$ref: '#/components/schemas/Animal'}, {type: object, properties: {fins: {type: integer}}}]}
```

gives `sealed class Animal` with `AnimalBird`, `AnimalFish` and `AnimalUnknown`, selected by `type` (`'Bird'`, `'Fish'`, the implicit component names). Subtypes in other files the spec reads are found too. A discriminator on a schema nothing extends leaves it a model (`TOA452`).

### Diagnostics for discriminated unions

| Code | Meaning |
| --- | --- |
| `TOA401` | The discriminator property is not `required` in a variant; a payload without it falls to the unknown variant |
| `TOA402` | A mapping value points to a schema that does not exist (error) |
| `TOA450` | A variant is written inline, so no value can select it; it has no private constructor |
| `TOA451` | A mapping value names a schema that is not a variant; ignored |
| `TOA456` | Two variants are selected by the same value; the earlier one decodes it |
| `TOA457` | A selecting value was derived from a `const`, see above |

## Without a discriminator: by JSON type

When the variants have different JSON types, the runtime type picks the variant:

```yaml
Value:
  oneOf:
    - type: string
    - type: integer
    - $ref: '#/components/schemas/Cat'
```

```dart
sealed class Value {
  factory Value.fromJson(Object? json) => switch (json) {
    final String value => ValueString(JsonReader.asString(value)),
    final int value => ValueInt(JsonReader.asInt(value)),
    final Map<String, Object?> value => ValueCat(Cat.fromJson(JsonReader.asObject(value))),
    _ => ValueUnknown._(JsonValue(json)),
  };
}
```

`int` is tried before `num`. Variants of the same Dart type are one (`TOA454` info drops the later one).

## Variants that share a JSON type (`TOA453`)

Two object variants without a discriminator cannot be told apart by type:

```yaml
Shape:
  oneOf: [{$ref: '#/components/schemas/Circle'}, {$ref: '#/components/schemas/Square'}]
```

```text
warning TOA453 union-undiscriminated: This oneOf has no discriminator and variants that share a JSON type, so a value cannot be told apart by its type; it is generated as JsonValue.
  fix: Add a discriminator at the source, or generate a union that tries the variants with union: structural (an override of the schema, or the config key for every such union). Override:
    schemas:
      Shape:
        union: structural
```

`union: raw` (the default) keeps the value:

- If **all** variants share one JSON type, the union is not generated: the field is `JsonValue`.
- If only **some** do, they become one variant that keeps the raw JSON, named after the type: for `oneOf: [string, Circle, Square]` the union is `MixedString`, `MixedJson(JsonValue)` (both objects) and `MixedUnknown`.

`union: structural` generates a class that tries every variant's decoder and takes the one that matches **alone**; none or several matching give the unknown variant:

```dart
factory Shape.fromJson(Object? json) {
  final decoders = <Shape Function()>[
    () => ShapeCircle(Circle.fromJson(JsonReader.asObject(json))),
    () => ShapeSquare(Square.fromJson(JsonReader.asObject(json))),
  ];
  final matches = [for (final decode in decoders) ?JsonReader.attempt(decode)];
  return matches.length == 1 ? matches.single : ShapeUnknown._(JsonValue(json));
}
```

Set it for all unions in `defaults` or a client (`union: structural`) or for one schema or property (`union: structural` in the overrides file; the override wins). A discriminator at the source is better than either: structural decoding is only as good as your required properties.

## Branches that add nothing (`TOA455`)

An enum or `const` branch of a primitive type next to a plain branch of the same type (`anyOf: [{type: string}, {enum: ['']}]`) is dropped, and when one branch is left the union is that type. The dropped values go to the field's doc comment (`Known values: ...`). For `oneOf` this accepts a value both branches take, which the spec's `oneOf` would reject; that is deliberate (Stripe's idiom). A union left as `JsonValue` lists none.

## Nullable unions

A branch `{type: 'null'}` (3.1) or `nullable: true` (3.0) makes the field nullable (`Pet?`) instead of adding a variant.

## See also

- [Models](models.md), [Enums](enums.md).
- [Overrides](../overrides.md): `union`, `exhaustive`, discriminator fixes.
- [Presets and rules](../presets_and_rules.md): `discriminator-property-required` and `discriminator-mapping-target`.
- [Troubleshooting](../troubleshooting.md): "a union decodes to `Unknown`".
