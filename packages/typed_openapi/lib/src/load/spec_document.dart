import 'package:source_span/source_span.dart';

import '../diagnostics/json_pointer.dart';

/// A loaded spec: a plain JSON-like tree plus the source position of every
/// node, looked up by JSON pointer.
///
/// [root] contains only `Map<String, Object?>`, `List<Object?>`, `String`,
/// `num`, `bool` and `null`; keys are always strings.
final class SpecDocument {
  /// Creates a document; [spans] maps pointer values to source ranges.
  const SpecDocument({
    required this.file,
    required this.root,
    required Map<String, SourceSpan> spans,
  }) : _spans = spans;

  /// The file path as shown to the user.
  final String file;

  /// The document contents.
  final Map<String, Object?> root;

  final Map<String, SourceSpan> _spans;

  /// Whether source positions were recorded.
  bool get hasPositions => _spans.isNotEmpty;

  /// The source range of the node at [pointer], if known.
  SourceSpan? spanOf(JsonPointer pointer) => _spans[pointer.value];
}
