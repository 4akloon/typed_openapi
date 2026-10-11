import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../model/document.dart';
import '../model/operation.dart';
import '../model/schema.dart';
import '../model/security.dart';
import '../model/spec_node.dart';
import '../parse/openapi_parser.dart';
import '../parse/parse_context.dart';
import 'ref_target.dart';
import 'spec_documents.dart';
import 'spec_model.dart';

/// Follows every `$ref` of a parsed spec.
///
/// A target is identified by the absolute URI of its file plus its JSON
/// pointer. Targets in other local files are loaded once and parsed as the
/// kind of node the `$ref` expects; their own `$ref`s are followed in turn.
/// Problems go to the [DiagnosticBag] given to the constructor.
final class RefResolver {
  /// Creates a resolver that reports to [_diagnostics].
  const RefResolver(this._diagnostics);

  final DiagnosticBag _diagnostics;

  /// Resolves the `$ref`s in [index], which parsing [document] filled; the
  /// root document of the spec is [documents]' root.
  SpecModel resolve(
    OpenApiDocument document,
    SpecIndex index,
    SpecDocuments documents,
  ) {
    final parsers = <Uri, OpenApiParser>{};
    final targets = <SpecLocation, SpecLocation>{};
    final attempted = <SpecLocation>{};
    for (var i = 0; i < index.refs.length; i++) {
      final use = index.refs[i];
      switch (RefTarget.parse(use.ref, use.site.document)) {
        case BrokenRef(:final code, :final reason, :final fix):
          _report(documents, use, code, reason, fix: fix);
        case ResolvableRef(:final location):
          final file = documents[location.document];
          if (file == null) {
            _report(
              documents,
              use,
              .unresolvedRef,
              '"${use.ref}" points to '
              '${documents.displayPath(location.document)}, which does not '
              'exist or cannot be read.',
            );
            continue;
          }
          var node = index.nodes[location];
          if (node == null) {
            if (file.valueAt(location.pointer) == null) {
              _report(
                documents,
                use,
                .unresolvedRef,
                'Nothing is at "${use.ref}".',
                fix:
                    'Define the target, or point the reference at an '
                    'existing one.',
              );
              continue;
            }
            // A target that failed to parse was reported once; later refs
            // to it are not parsed, and so not reported, again.
            if (!attempted.add(location)) continue;
            final parser = parsers[location.document] ??= OpenApiParser(
              _diagnostics,
              file,
              index,
            );
            node = parser.parseFragment(location.pointer, use.kind);
            if (node == null) continue;
          }
          final kind = _kindOf(node);
          if (kind != use.kind) {
            _report(
              documents,
              use,
              .refKindMismatch,
              '"${use.ref}" points to '
              '${kind?.withArticle ?? 'a node that is not referable'}, but '
              '${use.kind.withArticle} is expected here.',
            );
            continue;
          }
          targets[use.site] = location;
      }
    }
    _reportCycles(targets, documents);
    return SpecModel(document: document, nodes: index.nodes, targets: targets);
  }

  /// Reports every loop of `$ref`s that never reaches a node without one.
  ///
  /// A key of [targets] is a node whose `$ref` resolved, so a chain that
  /// stays inside the keys only passes through references. A recursive
  /// schema is not a loop: its chain ends at the schema itself, which has
  /// no `$ref`.
  void _reportCycles(
    Map<SpecLocation, SpecLocation> targets,
    SpecDocuments documents,
  ) {
    final done = <SpecLocation>{};
    for (final start in targets.keys.toList()..sort()) {
      final path = <SpecLocation>[];
      final positions = <SpecLocation, int>{};
      SpecLocation? current = start;
      while (current != null &&
          targets.containsKey(current) &&
          !done.contains(current)) {
        final seen = positions[current];
        if (seen != null) {
          _reportCycle(path.sublist(seen), documents);
          break;
        }
        positions[current] = path.length;
        path.add(current);
        current = targets[current];
      }
      done.addAll(path);
    }
  }

  void _reportCycle(List<SpecLocation> cycle, SpecDocuments documents) {
    final first = cycle.reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
    final start = cycle.indexOf(first);
    final ordered = [...cycle.skip(start), ...cycle.take(start), first];
    String name(SpecLocation location) => location.document == first.document
        ? location.pointer.value
        : '${documents.displayPath(location.document)}'
              '${location.pointer.value}';
    final pointer = first.pointer.child(r'$ref');
    _diagnostics.report(
      .refCycle,
      'These references point at each other and never reach a definition: '
      '${ordered.map(name).join(' -> ')}.',
      file: documents.displayPath(first.document),
      pointer: pointer,
      span: documents[first.document]?.spanOf(pointer),
      fix: 'Point one of them at the actual definition.',
    );
  }

  static RefKind? _kindOf(SpecNode node) => switch (node) {
    Ref(:final kind) => kind,
    Schema() => .schema,
    Response() => .response,
    Parameter() => .parameter,
    Example() => .example,
    RequestBody() => .requestBody,
    Header() => .header,
    SecurityScheme() => .securityScheme,
    PathItem() => .pathItem,
    MediaType() => .mediaType,
    _ => null,
  };

  void _report(
    SpecDocuments documents,
    RefUse use,
    DiagnosticCode code,
    String message, {
    String? fix,
  }) {
    final document = documents[use.site.document];
    final pointer = use.site.pointer.child(r'$ref');
    _diagnostics.report(
      code,
      message,
      file: documents.displayPath(use.site.document),
      pointer: pointer,
      span: document?.spanOf(pointer),
      fix: fix,
    );
  }
}
