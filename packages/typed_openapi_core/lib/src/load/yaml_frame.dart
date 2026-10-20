import 'package:source_span/source_span.dart';

import '../diagnostics/json_pointer.dart';
import 'yaml_anchor.dart';
import 'yaml_anchors.dart';

/// A mapping key read so far: its YAML value and its span.
typedef YamlKey = ({Object? value, SourceSpan span});

/// What a collection frame expects next.
enum FrameState {
  /// A key.
  key,

  /// The value of [YamlFrame.key].
  value,

  /// A value to skip, because its key was not a string.
  skipValue,

  /// The rest of a key collection that is being skipped.
  skippedKey,

  /// The rest of a value collection that is being skipped.
  skippedValue,
}

/// A collection being built.
final class YamlFrame {
  /// Starts the frame of the collection at [pointer], filled into [value]
  /// (a map or a list), that began at [start].
  YamlFrame(this.pointer, this.value, this.start, this.record, this.anchor)
    : state = value is List<Object?> ? .value : .key;

  /// The pointer of the collection.
  final JsonPointer pointer;

  /// The `Map<String, Object?>` or `List<Object?>` being filled.
  final Object value;

  /// The span of the start event.
  final FileSpan start;

  /// The span record of the collection.
  final YamlSpanRecord record;

  /// The anchor defined on the collection, if any.
  final YamlAnchor? anchor;

  /// The keys read so far, with their YAML values and spans.
  final Map<String, YamlKey> keys = {};

  /// The key whose value comes next.
  String? key;

  /// What comes next; always [FrameState.value] in a list.
  FrameState state;

  /// The pointer of the value that comes next.
  JsonPointer get childPointer => switch (value) {
    final List<Object?> list => pointer.child(list.length),
    _ => pointer.child(key!),
  };

  /// Takes the key [text] whose YAML value is [value]; returns the key it
  /// repeats, if any.
  YamlKey? acceptKey(String text, Object? value, SourceSpan span) {
    final earlier = keys[text];
    keys[text] = (value: value, span: span);
    key = text;
    state = .value;
    return earlier;
  }

  /// Adds the finished child [child] to the list, or sets it as the value of
  /// the current key.
  void attach(Object? child) {
    switch (value) {
      case final List<Object?> list:
        list.add(child);
      case final Map<String, Object?> map:
        map[key!] = child;
        state = .key;
    }
  }
}
