import 'package:source_span/source_span.dart';

/// A JSON or YAML text read into plain values, with the source range of
/// every node by JSON pointer value.
final class ComposedYaml {
  /// Creates a composed document.
  const ComposedYaml({
    required this.root,
    required this.spans,
    this.syntaxError,
  });

  /// The root value: `Map<String, Object?>`, `List<Object?>`, `String`,
  /// `num`, `bool` or `null`. Null when [syntaxError] is set.
  final Object? root;

  /// The source range of every node, by pointer value.
  final Map<String, SourceSpan> spans;

  /// Why the text is not valid YAML, when it is not; nothing was reported
  /// for it, so the caller decides how to.
  final ({String message, SourceSpan span})? syntaxError;
}
