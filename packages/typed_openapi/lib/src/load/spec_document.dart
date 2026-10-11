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
    required this.uri,
    required this.root,
    required Map<String, SourceSpan> spans,
  }) : _spans = spans;

  /// The file path as shown to the user.
  final String file;

  /// The absolute URI of the file; relative `$ref`s resolve against it.
  final Uri uri;

  /// The document contents.
  final Map<String, Object?> root;

  final Map<String, SourceSpan> _spans;

  /// Whether source positions were recorded.
  bool get hasPositions => _spans.isNotEmpty;

  /// The source range of the node at [pointer], if known.
  SourceSpan? spanOf(JsonPointer pointer) => _spans[pointer.value];

  /// The value at [pointer] as a one-element record, or null when nothing is
  /// there.
  ///
  /// The record tells an explicit `null` in the document, `(null,)`, from a
  /// missing node, `null`.
  (Object?,)? valueAt(JsonPointer pointer) {
    Object? current = root;
    for (final token in pointer.tokens) {
      switch (current) {
        case Map<String, Object?>() when current.containsKey(token):
          current = current[token];
        case List<Object?>():
          final index = _index.hasMatch(token) ? int.parse(token) : -1;
          if (index < 0 || index >= current.length) return null;
          current = current[index];
        default:
          return null;
      }
    }
    return (current,);
  }

  static final _index = RegExp(r'^(0|[1-9][0-9]{0,8})$');
}
