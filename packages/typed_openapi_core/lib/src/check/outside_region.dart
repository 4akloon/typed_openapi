import '../diagnostics/json_pointer.dart';
import '../model/spec_node.dart';
import 'ref_edge.dart';

/// The part of a spec that only the operations a client leaves out use: the
/// operations themselves and the nodes they alone refer to.
///
/// It is found by incoming references, not by reachability from the generated
/// operations, so an edge nobody walks (a discriminated subtype, a mapping,
/// a path item parameter) cannot hide a use. The nodes the left out
/// operations reach are candidates; a candidate that a node outside the
/// region refers to is dropped from it, and that is repeated until nothing
/// changes, because dropping one makes its own references count.
final class OutsideRegion {
  /// Finds the region of [dropped] operations in a spec with [edges].
  factory OutsideRegion(List<SpecLocation> dropped, List<RefEdge> edges) {
    final inside = <SpecLocation>{...dropped};
    final candidates = _reached(inside, edges);
    inside.addAll(candidates);
    final users = _Users(edges);
    var changed = true;
    while (changed) {
      changed = false;
      for (final candidate in candidates.toList()) {
        final isUsed = users
            .of(candidate)
            .any((source) => !_isInside(source, inside));
        if (!isUsed) continue;
        candidates.remove(candidate);
        inside.remove(candidate);
        changed = true;
      }
    }
    return OutsideRegion._(inside);
  }

  const OutsideRegion._(this._roots);

  final Set<SpecLocation> _roots;

  /// Whether [location] is a node of the region or lies below one.
  bool contains(SpecLocation location) => _isInside(location, _roots);

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

/// The sources of the references to a node: to the node, to a node below
/// it, or to a node that holds it.
final class _Users {
  _Users(List<RefEdge> edges) {
    for (final edge in edges) {
      (_exact[edge.target] ??= []).add(edge.source);
      for (final held in OutsideRegion._selfAndAncestors(edge.target)) {
        (_within[held] ??= []).add(edge.source);
      }
    }
  }

  final Map<SpecLocation, List<SpecLocation>> _exact = {};
  final Map<SpecLocation, List<SpecLocation>> _within = {};

  Iterable<SpecLocation> of(SpecLocation node) sync* {
    yield* _within[node] ?? const [];
    for (final holder in OutsideRegion._selfAndAncestors(node).skip(1)) {
      yield* _exact[holder] ?? const [];
    }
  }
}
