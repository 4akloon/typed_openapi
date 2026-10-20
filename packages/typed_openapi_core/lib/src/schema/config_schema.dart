import 'dart:convert';

import 'config_catalog.dart';
import 'schema_writer.dart';

/// The JSON Schema of `typed_openapi.yaml`, made from [ConfigCatalog].
///
/// The schema says what the loader accepts, with these gaps, where the
/// loader rejects more than the schema does: one diagnostic code written
/// under both its id and its name; a reserved word or built-in identifier of
/// Dart as a class name (`naming.client`, `naming.default_group`) or as a
/// custom `type` or `converter`; equal `naming.input_suffix` and
/// `naming.patch_suffix`; and a `naming.operation_prefix` that is not a
/// valid regular expression.
final class ConfigSchema {
  /// Creates the schema.
  const ConfigSchema();

  /// Where the published copy of the schema is.
  static const url =
      'https://raw.githubusercontent.com/4akLoon/typed_openapi/main/packages/'
      'typed_openapi/schema/typed_openapi.schema.json';

  static const _writer = SchemaWriter();

  /// The schema as decoded JSON.
  Map<String, Object?> toJson() {
    final shared = {for (final key in ConfigCatalog.shared) key.name};
    return {
      r'$schema': SchemaWriter.dialect,
      'title': 'typed_openapi.yaml',
      'description': 'The config of typed_openapi.',
      'type': 'object',
      'properties': {
        'defaults': {r'$ref': '#/definitions/defaults'},
        'clients': {
          'type': 'object',
          'description': _writer.describe(ConfigCatalog.clients),
          'minProperties': 1,
          'additionalProperties': {r'$ref': '#/definitions/client'},
        },
      },
      'required': ['clients'],
      'additionalProperties': false,
      'definitions': {
        'defaults': {
          ..._writer.objectOf(ConfigCatalog.defaultsKeys, references: shared),
          'description': ConfigCatalog.defaults.description,
        },
        'client': {
          ..._writer.objectOf(ConfigCatalog.client, references: shared),
          'description': 'One client: a spec and where its code goes.',
        },
        for (final key in ConfigCatalog.shared) key.name: _writer.keyOf(key),
      },
    };
  }

  /// The schema as the text of the published file.
  String toText() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';
}
