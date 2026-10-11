import 'dart:collection';

import '../model/spec_node.dart';

/// What a [SpecEdit] does at its location.
enum EditOperation {
  /// Sets an object member, inserts a list item at an index or appends it
  /// at `-`, as JSON Patch `add` does.
  add,

  /// Replaces the value that is there.
  replace,

  /// Removes the value that is there.
  remove,
}

/// A change to the plain tree of one spec file: a rule's fix, and later an
/// override (M4).
final class SpecEdit {
  /// Sets the member, or inserts the item, at [location] to [value].
  const SpecEdit.add(this.location, this.value) : operation = .add;

  /// Replaces the value at [location] with [value].
  const SpecEdit.replace(this.location, this.value) : operation = .replace;

  /// Removes the value at [location].
  const SpecEdit.remove(this.location) : operation = .remove, value = null;

  /// The document and the pointer the edit applies to.
  final SpecLocation location;

  /// What the edit does.
  final EditOperation operation;

  /// The new plain value for [EditOperation.add] and
  /// [EditOperation.replace].
  final Object? value;

  /// Whether this edit and [other] touch the same node, or one of them a
  /// node inside the other's.
  bool overlaps(SpecEdit other) {
    if (location.document != other.location.document) return false;
    final a = location.pointer.tokens;
    final b = other.location.pointer.tokens;
    final shorter = a.length < b.length ? a : b;
    for (var i = 0; i < shorter.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Applies [SpecEdit]s to a plain tree without changing it: every object
/// and list on the way to an edit is copied once, and the copy is changed.
///
/// The tree may share nodes (a YAML alias is the same Dart object as its
/// anchor), so changing a node in place would change every place that
/// shares it.
final class TreeEditor {
  /// Creates an editor of [root].
  TreeEditor(Map<String, Object?> root) : _root = root;

  Map<String, Object?> _root;
  final Set<Object> _copies = HashSet.identity();

  /// The tree with every applied edit.
  Map<String, Object?> get root => _root;

  /// Applies [edit]; returns why it cannot be applied, or null.
  String? apply(SpecEdit edit) {
    final tokens = edit.location.pointer.tokens;
    if (tokens.isEmpty) return 'the document root cannot be edited';
    Object container = _root = _own(_root) as Map<String, Object?>;
    for (final token in tokens.take(tokens.length - 1)) {
      final child = _child(container, token);
      if (child is! Map<String, Object?> && child is! List<Object?>) {
        return 'there is no object or list at ${edit.location.pointer.value}';
      }
      final owned = _own(child!);
      _set(container, token, owned);
      container = owned;
    }
    return _change(container, tokens.last, edit);
  }

  String? _change(Object container, String token, SpecEdit edit) {
    switch ((container, edit.operation)) {
      case (final Map<String, Object?> map, .add):
        map[token] = edit.value;
      case (final Map<String, Object?> map, .replace)
          when map.containsKey(
            token,
          ):
        map[token] = edit.value;
      case (final Map<String, Object?> map, .remove)
          when map.containsKey(
            token,
          ):
        map.remove(token);
      case (final List<Object?> list, .add) when token == '-':
        list.add(edit.value);
      case (final List<Object?> list, .add):
        final index = _index(token);
        if (index == null || index > list.length) return _missing(edit);
        list.insert(index, edit.value);
      case (final List<Object?> list, .replace || .remove):
        final index = _index(token);
        if (index == null || index >= list.length) return _missing(edit);
        if (edit.operation == .replace) {
          list[index] = edit.value;
        } else {
          list.removeAt(index);
        }
      default:
        return _missing(edit);
    }
    return null;
  }

  static String _missing(SpecEdit edit) =>
      'nothing is at ${edit.location.pointer.value}';

  Object _own(Object container) {
    if (_copies.contains(container)) return container;
    final copy = container is Map<String, Object?>
        ? Map<String, Object?>.of(container)
        : List<Object?>.of(container as List<Object?>);
    _copies.add(copy);
    return copy;
  }

  static Object? _child(Object container, String token) => switch (container) {
    final Map<String, Object?> map => map[token],
    final List<Object?> list => switch (_index(token)) {
      final index? when index < list.length => list[index],
      _ => null,
    },
    _ => null,
  };

  static void _set(Object container, String token, Object value) {
    switch (container) {
      case final Map<String, Object?> map:
        map[token] = value;
      case final List<Object?> list:
        list[_index(token)!] = value;
    }
  }

  static int? _index(String token) =>
      _indexPattern.hasMatch(token) ? int.parse(token) : null;

  static final _indexPattern = RegExp(r'^(0|[1-9][0-9]{0,8})$');
}
