import 'example.dart';
import 'media_type.dart';
import 'schema.dart';
import 'spec_node.dart';

/// Where a parameter is sent: the `in` field.
enum ParameterLocation {
  /// A query parameter.
  query,

  /// The whole query string as one value (OpenAPI 3.2).
  querystring,

  /// A header.
  header,

  /// A path segment.
  path,

  /// A cookie.
  cookie,
}

/// How a parameter value is serialized: the `style` field.
enum ParameterStyle {
  /// `matrix`.
  matrix,

  /// `label`.
  label,

  /// `simple`.
  simple,

  /// `form`.
  form,

  /// `spaceDelimited`.
  spaceDelimited,

  /// `pipeDelimited`.
  pipeDelimited,

  /// `deepObject`.
  deepObject,

  /// `cookie` (OpenAPI 3.2).
  cookie,
}

/// A Parameter Object.
final class Parameter extends SpecNode {
  /// Creates a parameter.
  const Parameter({
    required super.location,
    this.name,
    this.placement,
    this.description,
    this.required = false,
    this.deprecated = false,
    this.allowEmptyValue = false,
    this.style,
    this.explode,
    this.allowReserved = false,
    this.schema,
    this.example,
    this.examples = const {},
    this.content = const {},
    super.extensions,
    super.unknownKeys,
  });

  /// `name`; required by the spec.
  final String? name;

  /// `in`; required by the spec.
  final ParameterLocation? placement;

  /// `description`.
  final String? description;

  /// `required`.
  final bool required;

  /// `deprecated`.
  final bool deprecated;

  /// `allowEmptyValue`.
  final bool allowEmptyValue;

  /// `style`.
  final ParameterStyle? style;

  /// `explode`; null when the spec leaves it to the style's default.
  final bool? explode;

  /// `allowReserved`.
  final bool allowReserved;

  /// `schema`.
  final Schema? schema;

  /// `example`.
  final (Object?,)? example;

  /// `examples`.
  final Map<String, RefOr<Example>> examples;

  /// `content`, used instead of [schema] for complex serialization.
  final Map<String, RefOr<MediaType>> content;
}
