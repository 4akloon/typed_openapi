import '../model/spec_node.dart';

/// A reference from one place of a spec to another, for the analysis that
/// finds what only some operations use.
final class RefEdge {
  /// Creates the edge from [source] to [target].
  const RefEdge(this.source, this.target);

  /// The node that refers: the object with the `$ref`, a schema with a
  /// `discriminator` mapping, or a discriminated base that a schema extends.
  final SpecLocation source;

  /// The node that is referred to.
  final SpecLocation target;
}
