import 'media_type.dart';
import 'spec_node.dart';

/// A Request Body Object.
final class RequestBody extends SpecNode {
  /// Creates a request body.
  const RequestBody({
    required super.location,
    this.description,
    this.content = const {},
    this.required = false,
    super.extensions,
    super.unknownKeys,
  });

  /// `description`.
  final String? description;

  /// `content` by media type, in document order.
  final Map<String, RefOr<MediaType>> content;

  /// `required`.
  final bool required;
}
