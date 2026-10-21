import '../diagnostics/json_pointer.dart';
import '../load/spec_document.dart';
import '../model/spec_node.dart';
import '../resolve/ref_target.dart';
import '../resolve/spec_documents.dart';
import 'ref_edge.dart';

/// Finds the references between the nodes of every loaded document by
/// walking the plain trees, so a `$ref` that does not resolve, or sits where
/// the model drops it, does not stop the walk.
///
/// Besides `$ref`, a `discriminator.mapping` value refers to a schema, and a
/// schema that extends a discriminated base with `allOf` is used by the base,
/// since the generated union holds it.
final class RefEdges {
  /// Creates a finder over [_documents].
  const RefEdges(this._documents);

  final SpecDocuments _documents;

  /// Every reference of the loaded documents.
  List<RefEdge> collect() {
    final edges = <RefEdge>[];
    for (final document in _documents.loaded) {
      final stack = <(Object?, JsonPointer)>[(document.root, JsonPointer.root)];
      while (stack.isNotEmpty) {
        final (node, pointer) = stack.removeLast();
        switch (node) {
          case Map<String, Object?>():
            _readObject(document, node, pointer, edges);
            for (final MapEntry(:key, :value) in node.entries) {
              stack.add((value, pointer.child(key)));
            }
          case List<Object?>():
            for (var i = 0; i < node.length; i++) {
              stack.add((node[i], pointer.child(i)));
            }
        }
      }
    }
    return edges;
  }

  void _readObject(
    SpecDocument document,
    Map<String, Object?> node,
    JsonPointer pointer,
    List<RefEdge> edges,
  ) {
    final here = SpecLocation(document.uri, pointer);
    final ref = node[r'$ref'];
    if (ref is String) {
      _add(edges, here, RefTarget.parse(ref, document.uri));
    }
    if (node['discriminator'] case {'mapping': final Map<String, Object?> m}) {
      for (final value in m.values) {
        if (value is String) _addMapping(edges, document, here, value);
      }
    }
    if (node['allOf'] case final List<Object?> parts) {
      for (final part in parts) {
        if (part is! Map<String, Object?>) continue;
        final extended = part[r'$ref'];
        if (extended is! String) continue;
        final base = RefTarget.parse(extended, document.uri);
        if (base is ResolvableRef && _hasDiscriminator(base.location)) {
          edges.add(RefEdge(base.location, here));
        }
      }
    }
  }

  void _addMapping(
    List<RefEdge> edges,
    SpecDocument document,
    SpecLocation schema,
    String value,
  ) {
    if (value.contains('#') || value.contains('/')) {
      _add(edges, schema, RefTarget.parse(value, document.uri));
      return;
    }
    final named = JsonPointer.root.child('components').child('schemas');
    edges.add(
      RefEdge(schema, SpecLocation(document.uri, named.child(value))),
    );
  }

  bool _hasDiscriminator(SpecLocation base) {
    final value = _documents[base.document]?.valueAt(base.pointer)?.$1;
    return value is Map<String, Object?> && value['discriminator'] is Map;
  }

  void _add(List<RefEdge> edges, SpecLocation source, RefTarget target) {
    if (target is ResolvableRef) edges.add(RefEdge(source, target.location));
  }
}
