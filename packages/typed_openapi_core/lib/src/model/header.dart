import 'example.dart';
import 'media_type.dart';
import 'parameter.dart';
import 'schema.dart';
import 'spec_node.dart';

/// A Header Object.
final class Header extends SpecNode {
  /// Creates a header.
  const Header({
    required super.location,
    this.description,
    this.required = false,
    this.deprecated = false,
    this.style,
    this.explode,
    this.schema,
    this.example,
    this.examples = const {},
    this.content = const {},
    super.extensions,
    super.unknownKeys,
  });

  /// `description`.
  final String? description;

  /// `required`.
  final bool required;

  /// `deprecated`.
  final bool deprecated;

  /// `style`.
  final ParameterStyle? style;

  /// `explode`.
  final bool? explode;

  /// `schema`.
  final Schema? schema;

  /// `example`.
  final (Object?,)? example;

  /// `examples`.
  final Map<String, RefOr<Example>> examples;

  /// `content`.
  final Map<String, RefOr<MediaType>> content;
}
