import 'package:source_span/source_span.dart';

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/json_pointer.dart';
import '../load/spec_document.dart';
import '../model/spec_node.dart';
import 'object_reader.dart';
import 'spec_feature.dart';

/// A `$ref` found while parsing.
final class RefUse {
  /// Creates a use of [ref] by the node at [site].
  const RefUse(this.site, this.ref, this.kind);

  /// The node that holds the `$ref`: a `Ref` or a `SchemaObject`.
  final SpecLocation site;

  /// The `$ref` value as written.
  final String ref;

  /// The kind of node the reference must point to.
  final RefKind kind;
}

/// A version-specific construct found while parsing.
final class FeatureUse {
  /// Creates a use of [feature].
  const FeatureUse(this.feature, this.file, this.pointer, this.span);

  /// The construct.
  final SpecFeature feature;

  /// The file it is in, as shown to the user.
  final String file;

  /// Where in [file] it is.
  final JsonPointer pointer;

  /// The source range, when positions are known.
  final SourceSpan? span;
}

/// What the parsers of one run collect: every node by location, every
/// `$ref` and every version-specific construct, in the order found.
final class SpecIndex {
  /// Every parsed node, references included, by location.
  final Map<SpecLocation, SpecNode> nodes = {};

  /// Every location a parser has read, whether or not it produced a node,
  /// with the kind it was read as (null for a node no `$ref` may point to).
  ///
  /// A location is read once: a later read, for example of an enclosing
  /// node, gets the node of the first one and reports nothing again.
  final Map<SpecLocation, RefKind?> visited = {};

  /// Every `$ref` found.
  final List<RefUse> refs = [];

  /// Every version-specific construct found.
  final List<FeatureUse> features = [];
}

/// The document being parsed, with the helpers every parser needs.
final class ParseContext {
  /// Creates a context for [document] that reports to [diagnostics] and
  /// records into [index].
  ParseContext(this.diagnostics, this.document, this.index);

  /// Where problems go.
  final DiagnosticBag diagnostics;

  /// The document being parsed.
  final SpecDocument document;

  /// Where nodes, refs and features are recorded.
  final SpecIndex index;

  /// The location of the node at [pointer] in [document].
  SpecLocation locate(JsonPointer pointer) =>
      SpecLocation(document.uri, pointer);

  /// Reports [code] at [pointer] of [document].
  void report(
    DiagnosticCode code,
    String message,
    JsonPointer pointer, {
    String? fix,
    List<String> args = const [],
  }) {
    diagnostics.report(
      code,
      message,
      file: document.file,
      pointer: pointer,
      span: document.spanOf(pointer),
      fix: fix,
      args: args,
    );
  }

  /// Records that [feature] is used at [pointer].
  void note(SpecFeature feature, JsonPointer pointer) {
    index.features.add(
      FeatureUse(feature, document.file, pointer, document.spanOf(pointer)),
    );
  }

  /// Records [node] by its location and returns it.
  T register<T extends SpecNode>(T node) {
    index.nodes[node.location] = node;
    return node;
  }

  /// Whether the node at [pointer] was read before; when it was not, marks
  /// it as read, as a node [kind] (what a `$ref` to it expects; null when
  /// none may point there).
  ///
  /// Every parser calls this before it reads a node, so a location is read
  /// once however many `$ref`s and enclosing nodes reach it. On true, the
  /// parser returns [earlier] instead of reading again.
  bool seen(JsonPointer pointer, {RefKind? kind}) {
    final location = locate(pointer);
    if (index.visited.containsKey(location)) return true;
    index.visited[location] = kind;
    return false;
  }

  /// The node an earlier read produced at [pointer]; null when that read
  /// produced none (it reported why) or produced a node that is not a [T].
  T? earlier<T extends SpecNode>(JsonPointer pointer) =>
      switch (index.nodes[locate(pointer)]) {
        final T node => node,
        _ => null,
      };

  /// Reads [raw] at [pointer] as an object with [build], once (see
  /// [seen]); null after reporting that [raw] is not an object, and [what]
  /// names the node in the report.
  T? node<T extends SpecNode>(
    Object? raw,
    JsonPointer pointer,
    String what,
    T Function(ObjectReader reader) build,
  ) {
    if (seen(pointer)) return earlier<T>(pointer);
    final reader = this.reader(raw, pointer, what);
    return reader == null ? null : build(reader);
  }

  /// A reader for [raw] at [pointer], or null after reporting that [raw] is
  /// not an object; [what] names the node in the report.
  ObjectReader? reader(Object? raw, JsonPointer pointer, String what) {
    if (raw is Map<String, Object?>) return ObjectReader(this, raw, pointer);
    report(
      .invalidValue,
      '$what must be an object, not ${ObjectReader.describe(raw)}.',
      pointer,
    );
    return null;
  }

  /// Reads [raw] at [pointer] as a Reference Object to a [kind] node, or
  /// with [parse] as an inline node; null when [raw] is not an object.
  RefOr<T>? refOr<T extends SpecNode>(
    Object? raw,
    JsonPointer pointer,
    RefKind kind,
    T Function(ObjectReader reader) parse,
  ) {
    if (seen(pointer, kind: kind)) {
      return switch (index.nodes[locate(pointer)]) {
        final Ref<T> ref => ref,
        final T node => Inline(node),
        _ => null,
      };
    }
    final reader = this.reader(raw, pointer, 'This ${kind.noun}');
    if (reader == null) return null;
    if (!reader.has(r'$ref')) return Inline(parse(reader));
    final ref = reader.string(r'$ref');
    final node = Ref<T>(
      location: reader.location,
      ref: ref ?? '',
      kind: kind,
      summary: reader.string('summary'),
      description: reader.string('description'),
      unknownKeys: reader.unknownKeys(reportExtensions: true),
    );
    if (ref != null) index.refs.add(RefUse(node.location, ref, kind));
    if (kind == .mediaType) note(.mediaTypeRef, pointer);
    register(node);
    return node;
  }
}
