import 'key_spec.dart';
import 'key_type.dart';
import 'override_operation_keys.dart';
import 'override_schema_keys.dart';

/// Every key the overrides file allows, with its type, description and an
/// example. The JSON Schema of the overrides, `OverrideKeys` and the tests
/// that compare the schema with the loader are made from it.
final class OverrideCatalog {
  OverrideCatalog._();

  /// `operations` as a key: entries by `operationId` or `METHOD /path`.
  static final KeySpec operations = KeySpec(
    'operations',
    NullableKey(
      MapKey(
        ObjectKey(OverrideOperationKeys.operation),
        keyPattern: OverrideOperationKeys.operationKeyPattern,
        invalidKeys: const ['FOO /pets'],
      ),
    ),
    description:
        'Operation overrides, by operationId or as METHOD /path. Null, as '
        'when every entry is commented out, means none.',
    example: {
      'getPet': {'name': 'fetchPet'},
    },
  );

  /// `schemas` as a key: entries by `components.schemas` key.
  static final KeySpec schemas = KeySpec(
    'schemas',
    NullableKey(MapKey(ObjectKey(OverrideSchemaKeys.schema))),
    description:
        'Schema overrides, by components.schemas key. Null, as when every '
        'entry is commented out, means none.',
    example: {
      'Pet': {'name': 'Animal'},
    },
  );

  /// The keys of the file itself.
  static final List<KeySpec> file = [operations, schemas];
}
