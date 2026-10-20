import '../schema/config_generation_keys.dart';
import '../schema/key_spec.dart';
import '../schema/override_catalog.dart';
import '../schema/override_operation_keys.dart';
import '../schema/override_schema_keys.dart';

/// The keys the overrides file allows in each of its sections, taken from
/// [OverrideCatalog] so the readers and the JSON Schema cannot differ; any
/// other key is reported (TOA803).
final class OverrideKeys {
  OverrideKeys._();

  static Set<String> _names(List<KeySpec> keys) => {
    for (final key in keys) key.name,
  };

  /// The sections of the file.
  static final Set<String> sections = _names(OverrideCatalog.file);

  /// The keys of an operation entry.
  static final Set<String> operation = _names(OverrideOperationKeys.operation);

  /// The keys of a parameter entry.
  static final Set<String> parameter = _names(OverrideOperationKeys.parameter);

  /// The keys of a request body entry.
  static final Set<String> requestBody = _names(OverrideOperationKeys.content);

  /// The keys of a response entry.
  static final Set<String> response = _names(OverrideOperationKeys.content);

  /// The keys of `sse`.
  static final Set<String> sse = _names(OverrideOperationKeys.sse);

  /// The keys of a schema entry.
  static final Set<String> schema = _names(OverrideSchemaKeys.schema);

  /// The keys of a property entry.
  static final Set<String> property = _names(OverrideSchemaKeys.property);

  /// The keys of `dartType`.
  static final Set<String> dartType = _names(ConfigGenerationKeys.customType);
}
