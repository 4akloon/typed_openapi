/// The keys `typed_openapi.yaml` allows in each of its sections; any other
/// key is reported (TOA902).
final class ConfigKeys {
  ConfigKeys._();

  /// The keys of the file itself.
  static const topLevel = {'defaults', 'clients'};

  /// The keys of how code is generated, allowed in `defaults` and in a
  /// client.
  static const generation = {
    'naming',
    'group_by',
    'include',
    'exclude',
    'types',
    'tri_state',
    'union',
    'exhaustive',
    'errors',
    'sse',
  };

  /// The keys of `defaults`.
  static const defaults = {
    'preset',
    'line_width',
    'rules',
    'severity',
    ...generation,
  };

  /// The keys of a client.
  static const client = {
    'input',
    'output',
    'preset',
    'overrides',
    'baseline',
    'line_width',
    'rules',
    'severity',
    ...generation,
  };

  /// The keys of `naming`.
  static const naming = {
    'client',
    'group',
    'default_group',
    'input_suffix',
    'patch_suffix',
    'operation_prefix',
    'stream_suffix',
  };

  /// The keys of `types`.
  static const types = {'number', 'formats', 'schemas'};
}
