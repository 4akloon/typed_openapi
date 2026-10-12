import 'spec_node.dart';

/// A Security Requirement Object: scheme names and the scopes each needs.
///
/// An empty requirement (`{}`) makes security optional.
final class SecurityRequirement extends SpecNode {
  /// Creates a requirement.
  const SecurityRequirement({required super.location, this.schemes = const {}});

  /// Scopes by security scheme name, in document order.
  final Map<String, List<String>> schemes;
}
