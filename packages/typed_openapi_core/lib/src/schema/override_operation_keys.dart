import '../model/parameter.dart';
import '../model/path_item.dart';
import '../overrides/sse_override.dart';
import 'key_spec.dart';
import 'key_type.dart';
import 'override_schema_keys.dart';

/// The keys of an operation entry of the overrides file and of what it
/// holds: parameters, the request body, responses and `sse`.
final class OverrideOperationKeys {
  OverrideOperationKeys._();

  /// The pattern of an operation key: an `operationId`, or `METHOD /path`
  /// with a method OpenAPI has, in either case. Text that starts like
  /// `METHOD /` with another word is rejected, as the loader does.
  static final String operationKeyPattern =
      '^(?:(?:${PathItem.methods.map(_anyCase).join('|')}) /.*'
      r'|(?![A-Za-z]+ /).*)$';

  /// The pattern of a parameter key: `name`, or `in:name` with an `in` of
  /// OpenAPI.
  static final String parameterKeyPattern =
      '^(?:(?:${ParameterLocation.values.map((l) => l.name).join('|')}):.*'
      r'|:.*|[^:]*)$';

  static String _anyCase(String word) => [
    for (final rune in word.runes)
      '[${String.fromCharCode(rune)}${String.fromCharCode(rune).toUpperCase()}]',
  ].join();

  /// The keys of the body of a request or of a response.
  static const List<KeySpec> content = [
    OverrideSchemaKeys.reason,
    KeySpec(
      'contentType',
      StringKey(pattern: '/'),
      description:
          'The media type to use, such as application/json. The schema checks '
          'only that it has a slash; the loader reads it as a media type.',
      example: 'application/json',
      invalidExamples: ['json'],
    ),
    KeySpec(
      'schema',
      FreeObjectKey(),
      description: 'The schema of the body, written as in the spec.',
      example: {'type': 'string'},
    ),
  ];

  /// The keys of a parameter entry.
  static final List<KeySpec> parameter = [
    OverrideSchemaKeys.reason,
    const KeySpec(
      'required',
      BooleanKey(),
      description: 'Whether the parameter is required.',
      example: true,
    ),
    const KeySpec(
      'schema',
      FreeObjectKey(),
      description: 'The schema of the parameter, written as in the spec.',
      example: {'type': 'integer'},
    ),
    const KeySpec(
      'name',
      StringKey(),
      description: 'The Dart name of the argument.',
      example: 'pageSize',
    ),
    OverrideSchemaKeys.dartType,
  ];

  /// The keys of `sse`.
  static final List<KeySpec> sse = [
    const KeySpec(
      'data',
      OneOfKey([StringKey(), FreeObjectKey()]),
      description:
          'The data of every event: a components.schemas key or an inline '
          'schema. It excludes events, which the schema cannot say: the '
          'loader reports both together and ignores them.',
      example: 'Pet',
    ),
    const KeySpec(
      'events',
      MapKey(
        NullableKey(OneOfKey([StringKey(), FreeObjectKey()])),
        minProperties: 1,
      ),
      description:
          'The data of each event by event name: a components.schemas key, '
          'an inline schema, or null for an event without data.',
      example: {'pet': 'Pet', 'ping': null},
    ),
    const KeySpec(
      'unknown',
      ChoiceKey(['keep', 'ignore']),
      description:
          'What to do with an event name the spec does not list: keep it as '
          'an unknown event or drop it.',
      example: 'ignore',
    ),
    const KeySpec(
      'reconnect',
      BooleanKey(),
      description: 'Whether this stream reconnects.',
      example: true,
    ),
    KeySpec(
      'method',
      ChoiceKey([for (final method in SseMethod.values) method.name]),
      description:
          'Which methods are generated: stream (the events beside the '
          'body), only (the events only) or none (leave the operation out).',
      example: 'stream',
    ),
  ];

  /// The keys of an operation entry.
  static final List<KeySpec> operation = [
    OverrideSchemaKeys.reason,
    const KeySpec(
      'name',
      StringKey(),
      description: 'The Dart name of the method.',
      example: 'fetchPet',
    ),
    const KeySpec(
      'exclude',
      BooleanKey(),
      description: 'Whether the operation is left out.',
      example: true,
    ),
    const KeySpec(
      'group',
      StringKey(),
      description:
          'The class the method goes to, UpperCamelCase. The loader does not '
          'check the case; the generator reports a group that differs.',
      example: 'Pets',
    ),
    KeySpec(
      'parameters',
      NullableKey(
        MapKey(
          ObjectKey(parameter),
          keyPattern: parameterKeyPattern,
          invalidKeys: ['bogus:limit'],
        ),
      ),
      description:
          'Parameter overrides, by name or as in:name (in is query, header, '
          'path, cookie or querystring).',
      example: {
        'limit': {'name': 'pageSize'},
      },
    ),
    const KeySpec(
      'requestBody',
      ObjectKey(content),
      description: 'The override of the request body.',
      example: {'contentType': 'application/json'},
    ),
    const KeySpec(
      'responses',
      NullableKey(MapKey(ObjectKey(content))),
      description:
          'Response overrides by status or range, such as 200, 4XX or '
          'default.',
      example: {
        '200': {'contentType': 'application/json'},
      },
    ),
    KeySpec(
      'sse',
      ObjectKey(sse),
      description: 'How the event stream of the operation is generated.',
      example: {'data': 'Pet', 'unknown': 'ignore'},
    ),
  ];
}
