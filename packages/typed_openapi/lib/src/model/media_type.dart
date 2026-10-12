import 'example.dart';
import 'header.dart';
import 'parameter.dart';
import 'schema.dart';
import 'spec_node.dart';

/// A Media Type Object.
final class MediaType extends SpecNode {
  /// Creates a media type.
  const MediaType({
    required super.location,
    this.schema,
    this.itemSchema,
    this.example,
    this.examples = const {},
    this.encoding = const {},
    this.prefixEncoding = const [],
    this.itemEncoding,
    super.extensions,
    super.unknownKeys,
  });

  /// `schema`.
  final Schema? schema;

  /// `itemSchema` (OpenAPI 3.2): the schema of each item of a sequential
  /// media type such as `text/event-stream`.
  final Schema? itemSchema;

  /// `example`.
  final (Object?,)? example;

  /// `examples`.
  final Map<String, RefOr<Example>> examples;

  /// `encoding` by property name.
  final Map<String, Encoding> encoding;

  /// `prefixEncoding` (OpenAPI 3.2).
  final List<Encoding> prefixEncoding;

  /// `itemEncoding` (OpenAPI 3.2).
  final Encoding? itemEncoding;
}

/// An Encoding Object.
final class Encoding extends SpecNode {
  /// Creates an encoding.
  const Encoding({
    required super.location,
    this.contentType,
    this.headers = const {},
    this.style,
    this.explode,
    this.allowReserved = false,
    super.extensions,
    super.unknownKeys,
  });

  /// `contentType`.
  final String? contentType;

  /// `headers`.
  final Map<String, RefOr<Header>> headers;

  /// `style`.
  final ParameterStyle? style;

  /// `explode`.
  final bool? explode;

  /// `allowReserved`.
  final bool allowReserved;
}
