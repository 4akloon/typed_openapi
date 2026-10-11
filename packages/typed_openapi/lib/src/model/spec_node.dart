import '../diagnostics/json_pointer.dart';

/// Where a node of a spec is: the absolute URI of its document and its JSON
/// pointer in that document.
///
/// This pair is the identity of a node. Two documents may both have
/// `#/components/schemas/User`; their locations still differ.
final class SpecLocation implements Comparable<SpecLocation> {
  /// Creates a location.
  const SpecLocation(this.document, this.pointer);

  /// The absolute URI of the document, without a fragment.
  final Uri document;

  /// The pointer to the node inside [document].
  final JsonPointer pointer;

  /// The location of [token] (a property name or a list index) under this
  /// one, in the same document.
  SpecLocation child(Object token) =>
      SpecLocation(document, pointer.child(token));

  @override
  bool operator ==(Object other) =>
      other is SpecLocation &&
      other.document == document &&
      other.pointer == pointer;

  @override
  int get hashCode => Object.hash(document, pointer);

  @override
  int compareTo(SpecLocation other) {
    final byDocument = '$document'.compareTo('${other.document}');
    if (byDocument != 0) return byDocument;
    return pointer.value.compareTo(other.pointer.value);
  }

  @override
  String toString() => '$document${pointer.value}';
}

/// What every node of the spec model carries.
abstract class SpecNode {
  /// Creates a node.
  const SpecNode({
    required this.location,
    this.extensions = const {},
    this.unknownKeys = const {},
  });

  /// Where the node is.
  final SpecLocation location;

  /// The `x-` keys of the node and their raw values, in document order.
  final Map<String, Object?> extensions;

  /// Keys no OpenAPI version defines for this node, with their raw values.
  ///
  /// Each of them was reported as `unknown-key` when the node was read.
  final Map<String, Object?> unknownKeys;

  /// The pointer part of [location].
  JsonPointer get pointer => location.pointer;
}

/// The kinds of node a `$ref` may point to.
///
/// Schemas are not wrapped in [RefOr]: in a Schema Object `$ref` is a
/// keyword, see `SchemaObject.ref`.
enum RefKind {
  /// A Schema Object.
  schema('schema'),

  /// A Response Object.
  response('response'),

  /// A Parameter Object.
  parameter('parameter'),

  /// An Example Object.
  example('example'),

  /// A Request Body Object.
  requestBody('request body'),

  /// A Header Object.
  header('header'),

  /// A Security Scheme Object.
  securityScheme('security scheme'),

  /// A Path Item Object.
  pathItem('path item'),

  /// A Media Type Object (OpenAPI 3.2).
  mediaType('media type');

  const RefKind(this.noun);

  /// How messages name a node of this kind, such as `request body`.
  final String noun;

  /// [noun] with its article, such as `an example`.
  String get withArticle => '${noun.startsWith('e') ? 'an' : 'a'} $noun';
}

/// A node of type [T] written inline, or a Reference Object to one.
sealed class RefOr<T extends SpecNode> {}

/// A Reference Object: `{$ref: ...}`, with an optional summary and
/// description.
final class Ref<T extends SpecNode> extends SpecNode implements RefOr<T> {
  /// Creates a reference.
  const Ref({
    required super.location,
    required this.ref,
    required this.kind,
    this.summary,
    this.description,
    super.unknownKeys,
  });

  /// The `$ref` value as written.
  final String ref;

  /// The kind of node the reference must point to.
  final RefKind kind;

  /// The `summary` that overrides the target's one.
  final String? summary;

  /// The `description` that overrides the target's one.
  final String? description;
}

/// A node written in place.
final class Inline<T extends SpecNode> implements RefOr<T> {
  /// Wraps [value].
  const Inline(this.value);

  /// The node.
  final T value;
}
