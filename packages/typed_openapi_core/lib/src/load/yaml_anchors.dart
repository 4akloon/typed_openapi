import 'package:source_span/source_span.dart';

import '../diagnostics/json_pointer.dart';
import 'yaml_anchor.dart';
import 'yaml_limits.dart';

/// The span of one node, kept while an anchored collection is open.
final class YamlSpanRecord {
  /// Creates the record of the node at the pointer value [pointer], with its
  /// [span] (null until a collection is complete) and nesting [level].
  YamlSpanRecord(this.pointer, this.span, this.level);

  /// The pointer value of the node.
  final String pointer;

  /// Set when the node is complete.
  SourceSpan? span;

  /// The level of a collection; -1 for a scalar.
  final int level;
}

/// The anchors of a document and the span records an alias repeats.
///
/// A collection that has an anchor, and everything inside it, leaves span
/// records; an alias to it copies them under its own pointer and charges each
/// to the limits, so an alias bomb is stopped before it is built.
final class YamlAnchors {
  /// Creates the anchors of a composition that charges [_limits].
  YamlAnchors(this._limits);

  final YamlLimits _limits;
  final Map<String, YamlAnchor> _byName = {};
  final List<YamlSpanRecord> _records = [];
  int _openCollections = 0;

  /// The anchor named [name], or null.
  YamlAnchor? operator [](String name) => _byName[name];

  /// Names a scalar [value] read from [text] at [span], if it has an anchor.
  void defineScalar(String? name, Object? value, String text, SourceSpan span) {
    if (name != null) _byName[name] = YamlAnchor.scalar(value, text, span);
  }

  /// Names a node that is skipped, if it has an anchor.
  void defineSkipped(String? name) {
    if (name != null) _byName[name] = YamlAnchor.skipped();
  }

  /// Keeps the span of a scalar at the pointer value [pointer] when an
  /// anchored collection is open.
  void recordScalar(String pointer, SourceSpan span) {
    if (_openCollections > 0) _records.add(YamlSpanRecord(pointer, span, -1));
  }

  /// Starts the collection of [record], named [name] if it has an anchor;
  /// returns the anchor.
  YamlAnchor? startCollection(String? name, YamlSpanRecord record) {
    YamlAnchor? anchor;
    if (name != null) {
      anchor = _byName[name] = YamlAnchor.collection(
        _records.length,
        record.pointer,
        record.level,
      );
      _openCollections++;
    }
    if (_openCollections > 0) _records.add(record);
    return anchor;
  }

  /// Completes the collection [anchor] names, built as [value].
  void endCollection(YamlAnchor anchor, Object value) {
    anchor
      ..value = value
      ..end = _records.length
      ..open = false;
    _openCollections--;
  }

  /// Repeats the records of [anchor] under [pointer], charging each one and
  /// writing the spans to [spans]; false after reporting a limit.
  bool expand(
    YamlAnchor anchor,
    JsonPointer pointer,
    SourceSpan span,
    Map<String, SourceSpan> spans,
  ) {
    // Only a scalar has no records.
    if (anchor.end < 0) return _expandScalar(anchor, pointer, span, spans);
    final level = _limits.open;
    for (var i = anchor.first; i < anchor.end; i++) {
      final record = _records[i];
      if (!_expandRecord(record, anchor, pointer, level, spans)) return false;
    }
    return true;
  }

  bool _expandScalar(
    YamlAnchor anchor,
    JsonPointer pointer,
    SourceSpan span,
    Map<String, SourceSpan> spans,
  ) {
    if (!_limits.charge(pointer, span)) return false;
    spans[pointer.value] = anchor.span!;
    recordScalar(pointer.value, anchor.span!);
    return true;
  }

  bool _expandRecord(
    YamlSpanRecord record,
    YamlAnchor anchor,
    JsonPointer pointer,
    int level,
    Map<String, SourceSpan> spans,
  ) {
    final at = pointer.value + record.pointer.substring(anchor.base.length);
    final atLevel = record.level < 0 ? -1 : level + record.level - anchor.level;
    final target = JsonPointer.parse(at);
    if (!_limits.acceptExpandedLevel(atLevel, target, record.span!)) {
      return false;
    }
    if (!_limits.charge(target, record.span!)) return false;
    spans[at] = record.span!;
    if (_openCollections > 0) {
      _records.add(YamlSpanRecord(at, record.span, atLevel));
    }
    return true;
  }
}
