/// A failure of the corpus tool that its command reports and exits `1` for:
/// a download, a hash that differs from its pin, a tool that failed.
final class CorpusException implements Exception {
  /// Creates the failure with [message].
  const CorpusException(this.message);

  /// What failed, as a sentence for the person who runs the tool.
  final String message;

  @override
  String toString() => message;
}
