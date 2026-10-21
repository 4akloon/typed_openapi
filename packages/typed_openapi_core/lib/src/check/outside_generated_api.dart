import '../config/project_config.dart';
import '../diagnostics/diagnostic.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/json_pointer.dart';
import '../ir/ir_context.dart';
import '../ir/name_lock.dart';
import '../ir/operation_selector.dart';
import '../ir/spec_operations.dart';
import '../model/spec_node.dart';
import '../normalize/normalized_spec.dart';
import 'outside_region.dart';
import 'ref_edges.dart';

/// Lowers to info the errors and warnings that lie outside the API a client
/// generates (TOA811).
///
/// The whole spec is read, since a reference cannot be judged before it is
/// read; but a finding in an operation that `include`, `exclude` or an
/// overrides `exclude: true` leave out, or in a node only such operations
/// use (see [OutsideRegion]), changes nothing in the generated client, so it
/// must not stop `generate`. The finding keeps its code and message.
final class OutsideGeneratedApi {
  /// Creates the analysis of [_spec] generated as [_client] says.
  const OutsideGeneratedApi(this._spec, this._client, this._names);

  final NormalizedSpec _spec;
  final ClientConfig _client;
  final NameLock _names;

  /// [diagnostics] with the findings outside the generated API lowered, and
  /// the note TOA811 when there were any.
  List<Diagnostic> apply(List<Diagnostic> diagnostics) {
    final (dropped, generated) = _operations();
    if (dropped.isEmpty) return diagnostics;
    final region = OutsideRegion(
      dropped,
      RefEdges(
        _spec.documents,
        _client.generation.defaultErrorSchema,
        generated,
      ).collect(),
    );
    final uris = {
      for (final document in _spec.documents.loaded)
        _spec.documents.displayPath(document.uri): document.uri,
    };
    var lowered = 0;
    final result = <Diagnostic>[];
    for (final diagnostic in diagnostics) {
      if (_isOutside(diagnostic, uris, region)) {
        lowered++;
        result.add(diagnostic.withSeverity(.info));
      } else {
        result.add(diagnostic);
      }
    }
    return lowered == 0 ? diagnostics : [...result, ..._note(lowered)];
  }

  bool _isOutside(
    Diagnostic diagnostic,
    Map<String, Uri> uris,
    OutsideRegion region,
  ) {
    if (diagnostic.severity != .error && diagnostic.severity != .warning) {
      return false;
    }
    final uri = uris[diagnostic.file];
    final pointer = diagnostic.pointer;
    return uri != null &&
        pointer != null &&
        region.contains(SpecLocation(uri, pointer));
  }

  /// The locations of the operations the client's filters and overrides
  /// leave out and that no generated operation shares, and the nodes the
  /// generated operations use: themselves, and the parameters and servers of
  /// their path items.
  (List<SpecLocation>, List<SpecLocation>) _operations() {
    final context = IrContext(DiagnosticBag(), _spec, _client, names: _names);
    final (all, _) = SpecOperations.of(context);
    final chosen = OperationSelector(context).select(all);
    final selected = {for (final entry in chosen) entry.operation.location};
    return (
      [
        for (final entry in all)
          if (!selected.contains(entry.operation.location))
            entry.operation.location,
      ],
      [
        for (final entry in chosen) ...[
          entry.operation.location,
          entry.item.location.child('parameters'),
          entry.item.location.child('servers'),
        ],
      ],
    );
  }

  List<Diagnostic> _note(int count) {
    final config = _client.generation;
    final byFilter =
        (!config.include.isEmpty || !config.exclude.isEmpty) &&
        config.client != null;
    final root = _spec.model.document.location.document;
    final bag = DiagnosticBag();
    bag.report(
      .findingsOutsideGeneratedApi,
      '$count ${count == 1 ? 'finding in an operation' : 'findings in '
                'operations'} that include, exclude or an `exclude: true` '
      'override leave out, or in schemas only those operations use, '
      '${count == 1 ? 'was' : 'were'} lowered to info.',
      file: byFilter ? config.file : _spec.documents.displayPath(root),
      pointer: byFilter ? config.client : JsonPointer.root.child('paths'),
      span: byFilter
          ? config.clientSpan
          : _spec.documents[root]?.spanOf(JsonPointer.root.child('paths')),
      fix:
          'They stay visible under their own codes and do not stop the '
          'client from being generated; fix them at the source if those '
          'operations should be generated.',
    );
    return bag.all;
  }
}
