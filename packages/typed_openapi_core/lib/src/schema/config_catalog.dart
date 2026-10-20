import '../config/project_config.dart';
import '../normalize/normalizer.dart';
import 'config_generation_keys.dart';
import 'key_spec.dart';
import 'key_type.dart';

/// Every key `typed_openapi.yaml` allows, with its type, description and an
/// example. The JSON Schema of the config, `ConfigKeys` and the tests that
/// compare the schema with the loader are made from it.
final class ConfigCatalog {
  ConfigCatalog._();

  /// The keys that `defaults` and a client share and that are not about how
  /// code is generated.
  static final List<KeySpec> shared = [
    KeySpec(
      'preset',
      ChoiceKey([for (final preset in Preset.values) preset.name]),
      description: 'The framework the spec comes from; it adds hints.',
      example: 'nestjs',
      defaultValue: 'generic',
    ),
    const KeySpec(
      'line_width',
      IntegerKey(minimum: 1),
      description: 'The line width of the generated code.',
      example: 100,
      defaultValue: 80,
    ),
    KeySpec(
      'rules',
      const RuleFlagsKey(),
      description:
          'Normalizer rules by name; false turns a rule off. A client adds to '
          'the rules of defaults.',
      example: {Normalizer.rules.first.name: false},
    ),
    const KeySpec(
      'severity',
      CodeLevelsKey(),
      description:
          'The level of diagnostic codes, by id or by name: error, warning, '
          'info or off. A code that reports a file that cannot be read can '
          'be raised but not lowered.',
      example: {'TOA303': 'off'},
    ),
  ];

  /// The keys only a client has.
  static const List<KeySpec> clientOnly = [
    KeySpec(
      'input',
      StringKey(),
      description: 'The OpenAPI file, relative to this file.',
      example: 'openapi.yaml',
      isRequired: true,
    ),
    KeySpec(
      'output',
      StringKey(),
      description: 'The directory the client is written to.',
      example: 'lib/api',
      isRequired: true,
    ),
    KeySpec(
      'overrides',
      StringKey(),
      description: 'The overrides file of this client.',
      example: 'overrides.yaml',
    ),
    KeySpec(
      'baseline',
      StringKey(),
      description: 'The baseline file of this client; each client has its own.',
      example: 'baseline.yaml',
    ),
  ];

  /// The keys of `defaults`.
  static final List<KeySpec> defaultsKeys = [
    ...shared,
    ...ConfigGenerationKeys.generation,
  ];

  /// The keys of a client.
  static final List<KeySpec> client = [
    ...clientOnly,
    ...shared,
    ...ConfigGenerationKeys.generation,
  ];

  /// `defaults` as a key.
  static final KeySpec defaults = KeySpec.object(
    'defaults',
    defaultsKeys,
    description: 'Settings every client starts from.',
  );

  /// `clients` as a key: a mapping of client names to clients.
  static final KeySpec clients = KeySpec(
    'clients',
    MapKey(ObjectKey(client), minProperties: 1),
    description: 'The clients to generate, by name.',
    example: {
      'api': {for (final key in clientOnly) key.name: key.example},
    },
    isRequired: true,
  );

  /// The keys of the file itself.
  static final List<KeySpec> file = [defaults, clients];
}
