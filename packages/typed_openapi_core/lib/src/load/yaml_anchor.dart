import 'package:source_span/source_span.dart';

/// What an anchor names: a scalar, a collection, or a node that is skipped.
final class YamlAnchor {
  /// An anchored scalar with its [value], source [text] and [span].
  YamlAnchor.scalar(this.value, this.text, this.span)
    : skipped = false,
      first = -1,
      end = -1,
      base = '',
      level = -1,
      open = false;

  /// An anchored collection whose records start at [first], at the pointer
  /// value [base] and nesting [level]; it is open until it is closed.
  YamlAnchor.collection(this.first, this.base, this.level)
    : skipped = false,
      text = null,
      span = null,
      end = -1,
      open = true;

  /// A node inside a skipped key or value.
  YamlAnchor.skipped()
    : skipped = true,
      value = null,
      text = null,
      span = null,
      first = -1,
      end = -1,
      base = '',
      level = -1,
      open = false;

  /// Whether the anchored node is inside a skipped key or value.
  final bool skipped;

  /// The anchored value; a collection's is set when it is closed.
  Object? value;

  /// The text of a scalar.
  final String? text;

  /// The span of a scalar.
  final SourceSpan? span;

  /// The first record of a collection; the records run to [end] (exclusive).
  final int first;

  /// The end of the records of a collection; -1 for a scalar or while the
  /// collection is open.
  int end;

  /// The pointer value of the anchored collection.
  final String base;

  /// The level of the anchored collection.
  final int level;

  /// Whether the anchored collection is still being built.
  bool open;
}
