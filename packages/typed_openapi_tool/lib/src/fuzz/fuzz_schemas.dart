import 'dart:math';

import 'hostile.dart';

/// Random schemas of one fuzz spec: primitives with constraints and formats,
/// enums and constants, unions, `allOf`, maps and references between the
/// components [names], with hostile property names, enum values and
/// descriptions.
final class FuzzSchemas {
  /// Creates the schemas drawn from [_random] that refer to [names].
  FuzzSchemas(this._random, this.names);

  final Random _random;

  /// The names of the components, sorted.
  final List<String> names;

  /// One of [items], drawn at random.
  T pick<T>(List<T> items) => items[_random.nextInt(items.length)];

  /// A random boolean.
  bool coin() => _random.nextBool();

  /// A reference to a random component.
  Map<String, Object?> ref() => {
    r'$ref': '#/components/schemas/${pick(names)}',
  };

  /// An inline object of one to three properties, some named with hostile
  /// text.
  Map<String, Object?> inlineObject() => {
    'type': 'object',
    'description': pick(Hostile.texts),
    'properties': {
      for (var i = 0; i < 1 + _random.nextInt(3); i++)
        coin() ? 'q$i' : pick(Hostile.names): primitive(),
    },
  };

  /// An enum or a constant.
  Map<String, Object?> enumeration() => pick<Map<String, Object?> Function()>([
    () => {
      'type': 'string',
      'enum': ['a', 'b'],
    },
    () => {
      'type': 'string',
      'enum': [pick(Hostile.names), pick(Hostile.names)],
    },
    () => {
      'type': 'string',
      'enum': ['a', 'b'],
      'default': pick(['a', 'b']),
      'x-enum-varnames': [pick(Hostile.names), pick(Hostile.names)],
    },
    () => {'const': pick(Hostile.names)},
    () => {
      'type': 'integer',
      'enum': [1, 2],
    },
    () => {
      'type': 'integer',
      'enum': [7],
    },
    () => {'const': true},
    () => {'const': 1.5},
    () => {'const': null},
  ])();

  /// A property schema.
  Map<String, Object?> primitive() => pick<Map<String, Object?> Function()>([
    ..._constrained(),
    ..._formatted(),
    ..._composite(),
  ])();

  List<Map<String, Object?> Function()> _constrained() => [
    () => {
      'type': 'string',
      'minLength': _random.nextInt(3),
      'maxLength': 9,
      'pattern': pick(['^a', r"^[*/'$\\]"]),
    },
    () => {'type': 'integer', 'minimum': 0, 'exclusiveMaximum': 10},
    () => {'type': 'number', 'minimum': 0, 'multipleOf': 0.5},
    () => {
      'type': 'array',
      'items': {'type': 'string'},
      'minItems': 1,
    },
    enumeration,
  ];

  List<Map<String, Object?> Function()> _formatted() => [
    () => {'type': 'string', 'format': 'date-time'},
    () => {'type': 'string', 'format': 'date'},
    () => {'type': 'string', 'format': 'byte'},
    () => {'type': 'integer', 'format': 'int64'},
    () => {'type': 'boolean', 'default': true},
    () => {'type': 'string', 'default': pick(Hostile.names)},
    () => <String, Object?>{'description': pick(Hostile.texts)},
    () => {
      'type': 'object',
      'additionalProperties': {'type': 'string'},
    },
  ];

  List<Map<String, Object?> Function()> _composite() => [
    ref,
    () => {
      'allOf': [
        ref(),
        {'description': pick(Hostile.texts), 'maxLength': 3},
      ],
    },
    () => {
      'anyOf': [
        {'type': 'string', 'maxLength': 5000},
        {
          'enum': [''],
        },
      ],
    },
    () => {
      'oneOf': [
        {'type': 'string'},
        {
          'enum': [pick(Hostile.names), 'c*/d'],
        },
        {'type': 'integer'},
      ],
    },
    () => {
      'anyOf': [
        {'type': 'integer'},
        {'type': 'null'},
      ],
    },
  ];

  /// A branch of a union.
  Map<String, Object?> variant() => pick<Map<String, Object?> Function()>([
    ref,
    ref,
    inlineObject,
    () => {'type': 'string'},
    () => {'type': 'integer'},
    () => {'type': 'number'},
    () => {'type': 'boolean'},
    () => {
      'type': 'array',
      'items': {'type': 'string'},
    },
    () => {
      'type': 'object',
      'additionalProperties': {'type': 'string'},
    },
    () => {'type': 'string', 'format': 'date'},
    enumeration,
    enumeration,
    () => {
      'type': ['string', 'null'],
    },
  ])();

  /// A component schema.
  Map<String, Object?> component() => pick<Map<String, Object?> Function()>([
    () => {
      'type': 'object',
      'description': pick(Hostile.texts),
      'required': [pick(Hostile.names)],
      'properties': {
        for (var i = 0; i < 1 + _random.nextInt(4); i++)
          pick(['q$i', 'kind', ...Hostile.names]): primitive(),
      },
      if (coin())
        'additionalProperties': pick([
          {'type': 'integer'},
          ref(),
        ]),
    },
    () => {
      'oneOf': [for (var i = 0; i < 2 + _random.nextInt(3); i++) variant()],
    },
    () => {
      'anyOf': [for (var i = 0; i < 2 + _random.nextInt(3); i++) variant()],
      if (coin())
        'discriminator': {
          'propertyName': pick(Hostile.names),
          'mapping': {
            pick(Hostile.names): '#/components/schemas/${pick(names)}',
          },
        },
    },
    () => {
      'type': 'string',
      'enum': [
        for (final name in Hostile.names)
          if (coin()) name,
      ],
    },
    () => {
      'type': 'integer',
      'enum': [1, 2],
    },
    () => {
      'allOf': [ref(), inlineObject()],
    },
    () => {'type': 'string', 'description': pick(Hostile.texts)},
  ])();
}
