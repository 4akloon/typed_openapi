import 'key_spec.dart';
import 'key_type.dart';

/// The keys of `naming` in `typed_openapi.yaml`.
final class ConfigNamingKeys {
  ConfigNamingKeys._();

  static const _identifier = r'^[A-Za-z_$][A-Za-z0-9_$]*$';

  /// The keys inside `naming`.
  static final List<KeySpec> keys = [
    const KeySpec(
      'client',
      StringKey(pattern: r'^[A-Z$][A-Za-z0-9_$]*$'),
      description:
          'The name of the root client class. It must be a Dart class name '
          'that starts with an uppercase letter and is not a reserved word '
          '(the schema cannot check the last). '
          'When unset it is made from the client name with Client.',
      example: 'PetstoreClient',
      invalidExamples: ['lower', '1Client'],
    ),
    const KeySpec(
      'group',
      StringKey(
        pattern:
            r'^(?=.*\{Tag\})(?:[A-Za-z_$]|\{Tag\})(?:[A-Za-z0-9_$]|\{Tag\})*$',
      ),
      description:
          'The template of the name of a group class. It must contain {Tag} '
          'and give a Dart identifier.',
      example: '{Tag}Api',
      defaultValue: '{Tag}Api',
      invalidExamples: ['NoTag', '{Tag}-Api'],
    ),
    const KeySpec(
      'default_group',
      StringKey(pattern: _identifier),
      description:
          'The class of operations without a group. It is the name of a '
          'class, so a reserved word cannot be it (the schema cannot check '
          'this).',
      example: 'DefaultApi',
      defaultValue: 'DefaultApi',
      invalidExamples: ['1Group', 'two words'],
    ),
    const KeySpec(
      'input_suffix',
      StringKey(pattern: _identifier),
      description:
          'The suffix of the request model of a schema that is split by '
          'direction. It must differ from patch_suffix (the schema cannot check this).',
      example: 'Input',
      defaultValue: 'Input',
      invalidExamples: ['1Input', 'two words'],
    ),
    const KeySpec(
      'patch_suffix',
      StringKey(pattern: _identifier),
      description:
          'The suffix of the PATCH body model of a schema that is also used '
          'elsewhere. It must differ from input_suffix (the schema cannot check this).',
      example: 'Patch',
      defaultValue: 'Patch',
      invalidExamples: ['1Patch', 'two words'],
    ),
    const KeySpec(
      'operation_prefix',
      StringKey(),
      description:
          'A regular expression removed from the start of an operationId '
          'before the method name is made. It applies only where its match '
          'starts at the first character. It must be a valid regular '
          'expression (the schema cannot check this).',
      example: 'api_',
    ),
    const KeySpec(
      'stream_suffix',
      StringKey(pattern: r'^[A-Z0-9][A-Za-z0-9]*$'),
      description:
          'The suffix of the event-stream method of an operation that also '
          'returns JSON. Letters and digits, from an uppercase letter or a '
          'digit.',
      example: 'Stream',
      defaultValue: 'Stream',
      invalidExamples: ['stream', 'Str_eam'],
    ),
  ];

  /// `naming` as a key.
  static final KeySpec naming = KeySpec.object(
    'naming',
    keys,
    description: 'How the generated classes and methods are named.',
  );
}
