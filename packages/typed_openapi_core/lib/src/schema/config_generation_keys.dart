import '../config/generation_config.dart';
import '../overrides/override_set.dart';
import 'config_naming_keys.dart';
import 'key_spec.dart';
import 'key_type.dart';

/// The keys of how code is generated, allowed in `defaults` and in a client.
final class ConfigGenerationKeys {
  ConfigGenerationKeys._();

  static List<String> _names(List<Enum> values) => [
    for (final value in values) value.name,
  ];

  /// The keys of `include` and `exclude`.
  static const List<KeySpec> filter = [
    KeySpec(
      'tags',
      ListKey(StringKey()),
      description: 'Tags to match, case-sensitive.',
      example: ['pets'],
    ),
    KeySpec(
      'operations',
      ListKey(StringKey()),
      description:
          'Operations to match, by operationId or as METHOD /path; * matches '
          'inside one segment.',
      example: ['getPet'],
    ),
    KeySpec(
      'paths',
      ListKey(StringKey()),
      description:
          'Paths to match; * is one path segment and ** is any number.',
      example: ['/pets/**'],
    ),
  ];

  /// The keys of a custom type in `types.formats` and `types.schemas`.
  static const List<KeySpec> customType = [
    KeySpec(
      'type',
      StringKey(pattern: r'^[A-Za-z$][A-Za-z0-9_$]*$'),
      description:
          'The Dart type, written as it is: no prefix and no type arguments, and '
          'not a reserved word (the schema cannot check the last).',
      example: 'Money',
      isRequired: true,
      invalidExamples: ['1Money', 'List<int>'],
    ),
    KeySpec(
      'import',
      StringKey(pattern: r'^(package:[A-Za-z_][A-Za-z0-9_]*/\S+|dart:\w+)$'),
      description: 'The package: or dart: library that declares the type.',
      example: 'package:app/money.dart',
      isRequired: true,
      invalidExamples: ['lib/money.dart', 'file:///money.dart'],
    ),
    KeySpec(
      'converter',
      StringKey(pattern: r'^[A-Za-z$][A-Za-z0-9_$]*$'),
      description:
          'A class with fromJson and toJson that converts the type, when '
          'the type itself has no such members.',
      example: 'MoneyConverter',
      invalidExamples: ['1Converter'],
    ),
  ];

  /// The keys of `types`.
  static const List<KeySpec> typeKeys = [
    KeySpec(
      'number',
      ChoiceKey(['num', 'double', 'int']),
      description: 'The Dart type of a number without a format.',
      example: 'double',
      defaultValue: 'num',
    ),
    KeySpec(
      'formats',
      MapKey(ObjectKey(customType)),
      description: 'Custom Dart types by the format of a schema.',
      example: {
        'money': {'type': 'Money', 'import': 'package:app/money.dart'},
      },
    ),
    KeySpec(
      'schemas',
      MapKey(ObjectKey(customType)),
      description: 'Custom Dart types by the key of a component schema.',
      example: {
        'Money': {'type': 'Money', 'import': 'package:app/money.dart'},
      },
    ),
  ];

  /// `types` as a key.
  static final KeySpec types = KeySpec.object(
    'types',
    typeKeys,
    description: 'How the types of schemas are written.',
  );

  /// The keys of `errors`.
  static const List<KeySpec> errorsKeys = [
    KeySpec(
      'default_schema',
      StringKey(),
      description:
          'The key of the component schema that is the body of an error '
          'status declared without one.',
      example: 'Error',
    ),
  ];

  /// The keys of `sse`.
  static const List<KeySpec> sseKeys = [
    KeySpec(
      'reconnect',
      BooleanKey(),
      description:
          'Whether the event streams of GET operations reconnect unless a '
          'call says no.',
      example: true,
      defaultValue: false,
    ),
  ];

  /// The keys of how code is generated.
  static final List<KeySpec> generation = [
    ConfigNamingKeys.naming,
    KeySpec(
      'group_by',
      ChoiceKey(_names(GroupBy.values)),
      description: 'How operations are put into classes.',
      example: 'path',
      defaultValue: 'tag',
    ),
    KeySpec.object(
      'include',
      filter,
      description:
          'Generate only the operations that match (a union of tags, '
          'operations and paths); empty means all.',
    ),
    KeySpec.object(
      'exclude',
      filter,
      description: 'Leave out the operations that match; it wins.',
    ),
    types,
    KeySpec(
      'tri_state',
      ChoiceKey(_names(TriStateRule.values)),
      description: 'Which properties of PATCH bodies tell null from absent.',
      example: 'optional',
      defaultValue: 'patch',
    ),
    KeySpec(
      'union',
      ChoiceKey(_names(UnionMode.values)),
      description:
          'How a oneOf or anyOf without a discriminator whose variants '
          'share a JSON type is generated.',
      example: 'structural',
      defaultValue: 'raw',
    ),
    const KeySpec(
      'exhaustive',
      BooleanKey(),
      description:
          'Whether the bases of enums, unions, status types and event unions '
          'are sealed, so a switch names every case.',
      example: false,
      defaultValue: true,
    ),
    KeySpec.object(
      'errors',
      errorsKeys,
      description: 'How error responses are typed.',
    ),
    KeySpec.object(
      'sse',
      sseKeys,
      description: 'How event streams are generated.',
    ),
  ];
}
