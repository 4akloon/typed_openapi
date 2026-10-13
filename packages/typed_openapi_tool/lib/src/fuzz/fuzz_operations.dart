import 'dart:math';

import 'fuzz_schemas.dart';
import 'hostile.dart';

/// Random operations of one fuzz spec: parameters of every location and
/// style, bodies and responses of every media type the generator knows,
/// event streams, and `sse` overrides (from the M9 and M10 harnesses).
final class FuzzOperations {
  /// Creates the operations drawn from [_random] over [schemas].
  FuzzOperations(this._random, this.schemas);

  final Random _random;

  /// The schemas the operations refer to.
  final FuzzSchemas schemas;

  T _pick<T>(List<T> items) => schemas.pick(items);

  /// A parameter; [i] keeps names of one operation apart.
  Map<String, Object?> parameter(int i) =>
      _pick<Map<String, Object?> Function()>([
        ..._plainParameters(i),
        ..._styledParameters(i),
      ])();

  List<Map<String, Object?> Function()> _plainParameters(int i) => [
    () => {'name': 'q$i', 'in': 'query', 'schema': schemas.primitive()},
    () => {
      'name': _pick(Hostile.names),
      'in': 'query',
      'description': _pick(Hostile.texts),
      'schema': schemas.primitive(),
    },
    () => {
      'name': 'h$i',
      'in': 'header',
      'required': true,
      'schema': schemas.primitive(),
    },
    () => {
      'name': 'c$i',
      'in': 'cookie',
      'explode': schemas.coin(),
      'schema': schemas.primitive(),
    },
  ];

  List<Map<String, Object?> Function()> _styledParameters(int i) => [
    () => {
      'name': 'd$i',
      'in': 'query',
      'style': 'deepObject',
      'explode': true,
      'schema': {
        'type': 'object',
        'additionalProperties': {'type': 'string'},
      },
    },
    () => {
      'name': 'p$i',
      'in': 'query',
      'style': _pick(['pipeDelimited', 'spaceDelimited', 'form']),
      'schema': {'type': 'array', 'items': schemas.enumeration()},
    },
    () => {
      'name': 'j$i',
      'in': 'query',
      'content': {
        'application/json': {'schema': schemas.primitive()},
      },
    },
    () => {
      'name': "x'\$\n*/$i",
      'in': 'query',
      'schema': {'type': 'string', 'default': r"*/ $x '"},
    },
  ];

  /// The content of a body or a response.
  Map<String, Object?> content() => _pick<Map<String, Object?> Function()>([
    ..._jsonContent(),
    ..._otherContent(),
  ])();

  List<Map<String, Object?> Function()> _jsonContent() => [
    () => {
      'application/json': {'schema': schemas.ref()},
    },
    () => {
      'application/json': {'schema': schemas.variant()},
    },
    () => {
      _pick(Hostile.mediaTypes): {'schema': schemas.ref()},
    },
  ];

  List<Map<String, Object?> Function()> _otherContent() => [
    () => {
      'text/plain': {
        'schema': {'type': 'string'},
      },
    },
    () => {
      'application/octet-stream': {
        'schema': {'type': 'string', 'format': 'binary'},
      },
    },
    () => {
      'application/x-www-form-urlencoded': {
        'schema': schemas.inlineObject(),
      },
    },
    () => {
      'multipart/form-data': {
        'schema': {
          'type': 'object',
          'properties': {
            'f': {'type': 'string', 'format': 'binary'},
            'm': schemas.primitive(),
          },
        },
      },
    },
    () => {'text/event-stream': _stream()},
    () => {
      'application/json': {'schema': schemas.ref()},
      'text/event-stream': _stream(),
    },
  ];

  Map<String, Object?> _stream() => _pick<Map<String, Object?> Function()>([
    () => {'schema': schemas.primitive()},
    () => <String, Object?>{},
    () => {
      'itemSchema': {
        'oneOf': [
          for (var i = 0; i < 1 + _random.nextInt(4); i++)
            {
              'properties': {
                'event': {'const': _pick(Hostile.names)},
                if (schemas.coin())
                  'data': {
                    'type': 'string',
                    'contentMediaType': 'application/json',
                    'contentSchema': schemas.ref(),
                  },
              },
            },
        ],
      },
    },
  ])();

  /// The responses of an operation.
  Map<String, Object?> responses() => {
    for (var k = 0; k < 1 + _random.nextInt(4); k++)
      _pick([
        '200',
        '201',
        '204',
        '2XX',
        '400',
        '404',
        '4XX',
        '500',
        'default',
      ]): {
        'description': _pick(Hostile.texts),
        if (schemas.coin()) 'content': content(),
      },
  };

  /// An `sse` override of an operation.
  Map<String, Object?> sseOverride() => {
    if (schemas.coin())
      'events': {
        for (var i = 0; i < 1 + _random.nextInt(3); i++)
          _pick(Hostile.names): _pick<Object?>([null, _pick(schemas.names)]),
      },
    if (schemas.coin()) 'unknown': _pick(['keep', 'ignore']),
    if (schemas.coin()) 'method': _pick(['stream', 'only', 'none']),
  };
}
