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
  }) {
    diagnostics.report(
      code,
      message,
      file: document.file,
      pointer: pointer,
      span: document.spanOf(pointer),
      fix: fix,
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
