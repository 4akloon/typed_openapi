import 'package:collection/collection.dart';

import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../load/openapi_version.dart';
import '../model/spec_node.dart';
import '../normalize/spec_edit.dart';
import '../resolve/spec_documents.dart';
import 'override_edit.dart';
import 'override_set.dart';

/// What the appliers of [OverrideEdit]s share: the plain trees of the spec,
/// the dialect of its root, and the way they report problems at an override.
final class OverrideEditContext {
  /// Creates a context over [documents], whose root declares [version]; it
  /// reports to [_diagnostics] at positions of [overrides].
  const OverrideEditContext(
    this._diagnostics,
    this.overrides,
    this.documents,
    this.version,
  );

  /// Compares values of the spec and of an override deeply.
  static const equality = DeepCollectionEquality();

  final DiagnosticBag _diagnostics;

  /// The overrides file the edits come from.
  final OverrideSet overrides;

  /// The plain trees of the spec's files.
  final SpecDocuments documents;

  /// The OpenAPI version the root document declares.
  final OpenApiVersion version;

  /// The object at [at] in its document's plain tree, or null.
  Map<String, Object?>? object(SpecLocation at) =>
      switch (documents[at.document]?.valueAt(at.pointer)) {
        (final Map<String, Object?> raw,) => raw,
        _ => null,
      };

  /// The edit that sets [field] of the object at [at] to [value]; `null`
  /// removes it.
  Iterable<OverrideEdit> set(
    OverrideEntry entry,
    String field,
    SpecLocation at,
    Map<String, Object?> raw,
    Object? value,
  ) sync* {
    final has = raw.containsKey(field);
    if (value == null ? !has : has && equality.equals(raw[field], value)) {
      unchanged(entry, field);
      return;
    }
    yield OverrideEdit(
      value == null
          ? SpecEdit.remove(at.child(field))
          : SpecEdit.add(at.child(field), value),
      [(entry, field)],
    );
  }

  /// Reports that the spec already has [field] of [entry].
  void unchanged(OverrideEntry entry, String field) => report(
    .overrideUnchanged,
    entry,
    field,
    'The spec already has this "$field"; the override changes nothing and '
    'can be removed.',
    fix: 'Remove "$field" from the override.',
  );

  /// Reports [message] at [field] of [entry] (at the entry itself when
  /// [field] is null), with the reason the entry gives.
  void report(
    DiagnosticCode code,
    OverrideEntry entry,
    String? field,
    String message, {
    String? fix,
  }) {
    final at = field == null ? entry.pointer : entry.pointer.child(field);
    final reason = entry.reason;
    _diagnostics.report(
      code,
      reason == null ? message : '$message Reason given: "$reason".',
      file: overrides.file,
      pointer: at,
      span: overrides.spanOf(at),
      fix: fix,
    );
  }
}
