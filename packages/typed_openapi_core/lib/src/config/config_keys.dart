import '../schema/config_catalog.dart';
import '../schema/config_generation_keys.dart';
import '../schema/config_naming_keys.dart';
import '../schema/key_spec.dart';

/// The keys `typed_openapi.yaml` allows in each of its sections, taken from
/// [ConfigCatalog] so the loader and the JSON Schema cannot differ; any other
/// key is reported (TOA902).
final class ConfigKeys {
  ConfigKeys._();

  static Set<String> _names(List<KeySpec> keys) => {
    for (final key in keys) key.name,
  };

  /// The keys of the file itself.
  static final Set<String> topLevel = _names(ConfigCatalog.file);

  /// The keys of how code is generated, allowed in `defaults` and in a
  /// client.
  static final Set<String> generation = _names(ConfigGenerationKeys.generation);

  /// The keys of `defaults`.
  static final Set<String> defaults = _names(ConfigCatalog.defaultsKeys);

  /// The keys of a client.
  static final Set<String> client = _names(ConfigCatalog.client);

  /// The keys of `naming`.
  static final Set<String> naming = _names(ConfigNamingKeys.keys);

  /// The keys of `types`.
  static final Set<String> types = _names(ConfigGenerationKeys.typeKeys);

  /// The keys of `include` and `exclude`.
  static final Set<String> filter = _names(ConfigGenerationKeys.filter);

  /// The keys of a custom type.
  static final Set<String> customType = _names(ConfigGenerationKeys.customType);

  /// The keys of `errors`.
  static final Set<String> errors = _names(ConfigGenerationKeys.errorsKeys);

  /// The keys of `sse`.
  static final Set<String> sse = _names(ConfigGenerationKeys.sseKeys);
}
