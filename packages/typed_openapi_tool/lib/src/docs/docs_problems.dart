/// Thrown when a doc comment breaks the convention the generated docs need.
final class DocsProblems implements Exception {
  /// Creates the exception from one sentence per [problems] entry.
  const DocsProblems(this.problems);

  /// What is missing or incomplete.
  final List<String> problems;

  @override
  String toString() => problems.join('\n');
}
