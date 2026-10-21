import '../diagnostics/json_pointer.dart';
import '../model/spec_node.dart';
import 'ref_edge.dart';

/// The part of a spec that only the operations a client leaves out use: the
/// operations themselves and the nodes they alone refer to.
///
/// It is found by incoming references, not by reachability from the generated
/// operations, so an edge nobody walks (a discriminated subtype, a mapping,
/// a path item parameter) cannot hide a use. The nodes the left out
/// operations reach are candidates; a candidate or left out operation that a
/// node outside the region refers to is dropped from it (a node below a left
/// out operation becomes a hole in it), and that is repeated until nothing
/// changes, because dropping one makes its own references count.
final class OutsideRegion {
  /// Finds the region of [dropped] operations in a spec with [edges].
  factory OutsideRegion(List<SpecLocation> dropped, List<RefEdge> edges) {
    final roots = <SpecLocation>{...dropped};
    roots.addAll(_reached(roots, edges));
    final holes = <SpecLocation>{};
    final users = _Users(edges);
    final droppedRoots = dropped.toSet();
    bool isOutside(SpecLocation source) =>
        !_isInside(source, roots) || _isInside(source, holes);
    var changed = true;
    while (changed) {
      changed = false;
      for (final root in roots.toList()) {
        if (!roots.contains(root)) continue;
        for (final edge in users.edgesTo(root)) {
          if (!isOutside(edge.source)) continue;
          // A node below a left out operation that is referred to from
          // outside is a hole in the region; anything else used from
          // outside leaves the region whole.
          if (droppedRoots.contains(root) &&
              edge.target != root &&
              _isInside(edge.target, {root})) {
            changed = holes.add(edge.target) || changed;
            continue;
          }
          roots.remove(root);
          changed = true;
          break;
        }
      }
    }
    return OutsideRegion._(roots, holes);
  }

  const OutsideRegion._(this._roots, this._holes);

  final Set<SpecLocation> _roots;
  final Set<SpecLocation> _holes;

  /// Whether [location] is a node of the region or lies below one.
  bool contains(SpecLocation location) =>
      _isInside(location, _roots) && !_isInside(location, _holes);

  /// The nodes that [dropped] operations refer to, directly or not.
  static Set<SpecLocation> _reached(
    Set<SpecLocation> dropped,
    List<RefEdge> edges,
  ) {
    final reached = <SpecLocation>{};
    var changed = true;
    while (changed) {
      changed = false;
      final known = {...dropped, ...reached};
      for (final edge in edges) {
        if (!_isInside(edge.source, known) || _isInside(edge.target, known)) {
          continue;
        }
        reached.add(edge.target);
        known.add(edge.target);
        changed = true;
      }
    }
    return reached;
  }

  static bool _isInside(SpecLocation location, Set<SpecLocation> roots) =>
      _selfAndAncestors(location).any(roots.contains);

  static Iterable<SpecLocation> _selfAndAncestors(
    SpecLocation location,
  ) sync* {
    final tokens = location.pointer.tokens;
    for (var length = tokens.length; length >= 0; length--) {
      yield SpecLocation(
        location.document,
        tokens.take(length).fold(JsonPointer.root, (p, t) => p.child(t)),
      );
    }
  }
}

/// The references to a node: to the node, to a node below it, or to a node
/// that holds it.
final class _Users {
  _Users(List<RefEdge> edges) {
    for (final edge in edges) {
      (_exact[edge.target] ??= []).add(edge);
      for (final held in OutsideRegion._selfAndAncestors(edge.target)) {
        (_within[held] ??= []).add(edge);
      }
    }
  }

  final Map<SpecLocation, List<RefEdge>> _exact = {};
  final Map<SpecLocation, List<RefEdge>> _within = {};

  Iterable<RefEdge> edgesTo(SpecLocation node) sync* {
    yield* _within[node] ?? const [];
    for (final holder in OutsideRegion._selfAndAncestors(node).skip(1)) {
      yield* _exact[holder] ?? const [];
    }
  }
}
