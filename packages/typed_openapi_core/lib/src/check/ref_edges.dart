import '../diagnostics/json_pointer.dart';
import '../load/spec_document.dart';
import '../model/spec_node.dart';
import '../resolve/ref_target.dart';
import '../resolve/spec_documents.dart';
import 'ref_edge.dart';
import 'subtype_edges.dart';

/// Finds the references between the nodes of every loaded document by
/// walking the plain trees, so a `$ref` that does not resolve, or sits where
/// the model drops it, does not stop the walk.
///
/// Besides `$ref`, a `discriminator.mapping` value refers to a schema, the
/// schemas that extend a discriminated base are used by it ([SubtypeEdges]),
/// and the IR reads the `errors.default_schema` by name, which no `$ref`
/// shows: it is a use from outside every operation.
final class RefEdges {
  /// Creates a finder over [_documents]; [_defaultErrorSchema] is the key the
  /// config names in `errors.default_schema`, and [_generated] are the nodes
  /// of the generated operations, which use their whole subtree.
  const RefEdges(
    this._documents,
    this._defaultErrorSchema, [
    this._generated = const [],
  ]);

  /// The source of the uses that come from no place of a spec: the code
  /// generated for an operation or read by name.
  static final SpecLocation outside = SpecLocation(
    Uri.parse('typed-openapi:outside'),
    JsonPointer.root,
  );

  final SpecDocuments _documents;
  final String? _defaultErrorSchema;
  final List<SpecLocation> _generated;

  /// Every reference of the loaded documents.
  List<RefEdge> collect() {
    final edges = <RefEdge>[];
    final subtypes = SubtypeEdges(_documents);
    for (final document in _documents.loaded) {
      final stack = <(Object?, JsonPointer)>[(document.root, JsonPointer.root)];
      while (stack.isNotEmpty) {
        final (node, pointer) = stack.removeLast();
        switch (node) {
          case Map<String, Object?>():
            _readObject(document, node, pointer, edges);
            subtypes.read(document.uri, node, pointer);
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
    final root = _documents.root.uri;
    final name = _defaultErrorSchema;
    return [
      ...edges,
      ...subtypes.edges(),
      if (name != null)
        RefEdge(outside, SpecLocation(root, _schemaPointer(name))),
      for (final node in _generated) RefEdge(outside, node),
    ];
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
  }

  /// A mapping value that is a bare name is a `components.schemas` key of
  /// the root document for the IR; the holder's document is kept as well.
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
    for (final uri in {document.uri, _documents.root.uri}) {
      edges.add(RefEdge(schema, SpecLocation(uri, _schemaPointer(value))));
    }
  }

  static JsonPointer _schemaPointer(String name) =>
      JsonPointer.root.child('components').child('schemas').child(name);

  void _add(List<RefEdge> edges, SpecLocation source, RefTarget target) {
    if (target is ResolvableRef) edges.add(RefEdge(source, target.location));
  }
}
