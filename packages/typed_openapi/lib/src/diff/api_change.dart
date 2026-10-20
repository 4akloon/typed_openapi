/// How a change of the API affects code that uses the client (M12, decision
/// 2), from the most to the least serious: `--fail-on` fails at a category
/// and every category before it.
enum ChangeCategory {
  /// Code that uses the client may no longer compile.
  breaking('breaking'),

  /// Only an exhaustive `switch` over a sealed type may no longer compile.
  switchBreaking('switch-breaking'),

  /// The Dart API is the same, but what goes on the wire changed.
  wire('wire'),

  /// Something was added; code that compiled still compiles.
  additive('additive'),

  /// Only documentation or `@Deprecated` changed.
  docs('docs');

  const ChangeCategory(this.label);

  /// The name in reports and on the command line.
  final String label;

  /// The category named [label]; null for another text.
  static ChangeCategory? parse(String label) {
    for (final category in values) {
      if (category.label == label) return category;
    }
    return null;
  }
}

/// One change between two snapshots of a client's API.
final class ApiChange implements Comparable<ApiChange> {
  /// Creates a change of the type [type], or of its member [member].
  const ApiChange(
    this.category,
    this.message, {
    required this.type,
    this.member,
    this.fix,
  });

  /// How the change affects code that uses the client.
  final ChangeCategory category;

  /// What changed, as a sentence that names the Dart declarations.
  final String message;

  /// The identity of the type that changed.
  final String type;

  /// The identity of the member that changed; null for the type itself.
  final String? member;

  /// A ready override that undoes the change, such as `name:` for a schema
  /// renamed in the spec; null when there is none.
  final String? fix;

  /// Orders by category, type and member.
  @override
  int compareTo(ApiChange other) {
    final byCategory = category.index.compareTo(other.category.index);
    if (byCategory != 0) return byCategory;
    final byType = type.compareTo(other.type);
    if (byType != 0) return byType;
    return (member ?? '').compareTo(other.member ?? '');
  }

  /// The change as plain JSON values.
  Map<String, Object?> toJson() => {
    'category': category.label,
    'type': type,
    'member': ?member,
    'message': message,
    'fix': ?fix,
  };
}
