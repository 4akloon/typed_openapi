import 'header.dart';
import 'media_type.dart';
import 'spec_node.dart';

/// A Response Object.
final class Response extends SpecNode {
  /// Creates a response.
  const Response({
    required super.location,
    this.summary,
    this.description,
    this.headers = const {},
    this.content = const {},
    super.extensions,
    super.unknownKeys,
  });

  /// `summary` (OpenAPI 3.2).
  final String? summary;

  /// `description`.
  final String? description;

  /// `headers`.
  final Map<String, RefOr<Header>> headers;

  /// `content` by media type, in document order.
  final Map<String, RefOr<MediaType>> content;
}
