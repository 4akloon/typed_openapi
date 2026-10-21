import '../diagnostics/json_pointer.dart';
import '../model/spec_node.dart';
import '../resolve/ref_target.dart';
import '../resolve/spec_documents.dart';
import 'ref_edge.dart';

/// The uses the IR makes of a discriminated base that no `$ref` shows: the
/// schemas that extend it with `allOf`, directly, through another subtype or
/// through an alias (`SubtypeFinder`), are variants of its union.
///
/// This is wider than the IR on purpose: any schema node counts, not only
/// the entries of `components.schemas`, so a doubt keeps a level.
final class SubtypeEdges {
  /// Creates the finder over [_documents].
  SubtypeEdges(this._documents);

  final SpecDocuments _documents;
  final Set<SpecLocation> _discriminated = {};
  final List<(SpecLocation, List<List<SpecLocation>>)> _extending = [];

  /// Notes the schema at [pointer] of the document [uri] when it has a
  /// discriminator or extends other schemas with `allOf`.
  void read(Uri uri, Map<String, Object?> node, JsonPointer pointer) {
    final here = SpecLocation(uri, pointer);
    if (node['discriminator'] is Map) _discriminated.add(here);
    if (node['allOf'] case final List<Object?> parts) {
      final chains = [
        for (final part in parts)
          if (part is Map<String, Object?> && part[r'$ref'] is String)
            _chain(part[r'$ref'] as String, uri),
      ];
      if (chains.isNotEmpty) _extending.add((here, chains));
    }
  }

  /// The edges from every schema of an alias chain that ends in a
  /// polymorphic schema to the schemas extending it.
  List<RefEdge> edges() {
    final polymorphic = {..._discriminated};
    var grew = true;
    while (grew) {
      grew = false;
      for (final (schema, chains) in _extending) {
        if (polymorphic.contains(schema)) continue;
        if (chains.any((c) => c.isNotEmpty && polymorphic.contains(c.last))) {
          polymorphic.add(schema);
          grew = true;
        }
      }
    }
    return [
      for (final (schema, chains) in _extending)
        for (final chain in chains)
          if (chain.isNotEmpty && polymorphic.contains(chain.last))
            for (final member in chain) RefEdge(member, schema),
    ];
  }

  /// The schema [ref] names and the schemas its `$ref` aliases lead to; a
  /// cycle ends it.
  List<SpecLocation> _chain(String ref, Uri base) {
    final chain = <SpecLocation>[];
    var target = RefTarget.parse(ref, base);
    while (target is ResolvableRef && !chain.contains(target.location)) {
      final location = target.location;
      chain.add(location);
      final value = _documents[location.document]?.valueAt(location.pointer);
      final next = value?.$1 is Map<String, Object?>
          ? (value!.$1 as Map<String, Object?>)[r'$ref']
          : null;
      if (next is! String) break;
      target = RefTarget.parse(next, location.document);
    }
    return chain;
  }
}
