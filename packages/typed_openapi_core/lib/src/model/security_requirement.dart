import 'spec_node.dart';

/// A Security Requirement Object: scheme names and the scopes each needs.
///
/// An empty requirement (`{}`) makes security optional.
final class SecurityRequirement extends SpecNode {
  /// Creates a requirement.
  const SecurityRequirement({
    required super.location,
    this.schemes = const {},
    this.isMalformed = false,
    this.isNotList = false,
  });

  /// Scopes by security scheme name, in document order.
  final Map<String, List<String>> schemes;

  /// Whether the entry was not an object (a string, a number, `null`): it
  /// was reported, and it still stands for a requirement the spec made but
  /// this tool cannot read, so no operation reads as open. A string entry
  /// is kept as the one name in [schemes].
  final bool isMalformed;

  /// Whether this stands for a whole `security` field that was not a list
  /// (a map, a string, a number, `null`), not for one entry of it. It is
  /// always [isMalformed].
  final bool isNotList;
}
