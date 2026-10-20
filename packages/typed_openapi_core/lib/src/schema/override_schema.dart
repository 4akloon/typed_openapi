import 'dart:convert';

import 'override_catalog.dart';
import 'schema_writer.dart';

/// The JSON Schema of the overrides file, made from [OverrideCatalog].
///
/// The schema says what the loader accepts, with these gaps, where the
/// loader rejects more than the schema does: `sse` with both `data` and
/// `events`; a schema field other than `nullable` beside a `$ref`, and
/// `properties` beside a `$ref`; a `dartType` whose `type` or `converter` is
/// a reserved word of Dart; and a `contentType` that is a text with a slash
/// but not a media type. Operation and parameter keys are checked as the
/// loader reads them: `METHOD /path` needs a method OpenAPI has, `in:name`
/// an `in` it has, and any other key is an `operationId` or a name. A key
/// with a line break is an `operationId` or a name for the loader (`.` does
/// not match it), but the schema's lookahead rejects it: a gap, in an extreme
/// edge case.
final class OverrideSchema {
  /// Creates the schema.
  const OverrideSchema();

  /// Where the published copy of the schema is.
  static const url =
      'https://raw.githubusercontent.com/4akloon/typed_openapi/main/packages/'
      'typed_openapi/schema/typed_openapi.overrides.schema.json';

  static const _writer = SchemaWriter();

  /// The schema as decoded JSON.
  Map<String, Object?> toJson() => {
    r'$schema': SchemaWriter.dialect,
    'title': 'typed_openapi overrides',
    'description': 'The overrides file of a typed_openapi client.',
    ..._writer.objectOf(OverrideCatalog.file),
  };

  /// The schema as the text of the published file.
  String toText() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';
}
