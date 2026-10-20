import '../model/document.dart';
import '../model/schema.dart';
import '../model/spec_node.dart';

/// A parsed spec with its `$ref`s resolved.
///
/// Holds the root [document], every node read from any file by location,
/// and where each `$ref` that could be followed points.
final class SpecModel {
  /// Creates a model.
  SpecModel({
    required this.document,
    required Map<SpecLocation, SpecNode> nodes,
    required Map<SpecLocation, SpecLocation> targets,
  }) : _nodes = Map.unmodifiable(nodes),
       _targets = Map.unmodifiable(targets);

  /// The root document.
  final OpenApiDocument document;

  /// Every node read from any file, ordered by location.
  late final List<SpecNode> nodes = List.unmodifiable(
    _nodes.values.toList()..sort((a, b) => a.location.compareTo(b.location)),
  );

  final Map<SpecLocation, SpecNode> _nodes;
  final Map<SpecLocation, SpecLocation> _targets;

  /// The node at [location], if one was read there.
  SpecNode? nodeAt(SpecLocation location) => _nodes[location];

  /// Where the `$ref` of the node at [site] points, or null when the node
  /// has no `$ref` or it could not be followed.
  SpecLocation? targetOf(SpecLocation site) => _targets[site];

  /// The node [value] stands for: the value itself, or the node at the end
  /// of its `$ref` chain; null when a `$ref` on the way is broken.
  T? resolve<T extends SpecNode>(RefOr<T> value) => switch (value) {
    Inline(:final value) => value,
    Ref() => switch (_follow(value.location)) {
      final T node => node,
      _ => null,
    },
  };

  /// The schema at the end of [schema]'s `$ref` chain, or [schema] itself
  /// when it has no `$ref`; null when a `$ref` on the way is broken.
  ///
  /// Keywords next to a `$ref` are not merged into the result.
  Schema? resolveSchema(Schema schema) {
    if (schema is! SchemaObject || schema.ref == null) return schema;
    return switch (_follow(schema.location)) {
      final Schema node => node,
      _ => null,
    };
  }

  SpecNode? _follow(SpecLocation site) {
    final seen = <SpecLocation>{};
    var current = site;
    while (seen.add(current)) {
      final target = _targets[current];
      if (target == null) return null;
      final node = _nodes[target];
      final isAlias = node is Ref || (node is SchemaObject && node.ref != null);
      if (!isAlias) return node;
      current = target;
    }
    return null;
  }
}
