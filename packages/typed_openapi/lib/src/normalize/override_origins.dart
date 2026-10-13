import '../diagnostics/diagnostic.dart';
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/json_pointer.dart';
import '../overrides/override_set.dart';

/// Which problems of a spec its overrides introduced.
///
/// A problem is introduced when the spec as read, before the overrides,
/// did not have it (same code, file and pointer), and an applied override
/// changed a member of its node, of a node inside it or of a node around
/// it.
final class OverrideOrigins {
  /// Creates origins for [_overrides]: [before] are the problems the spec
  /// had before they were applied, [changes] the nodes they changed.
  OverrideOrigins(
    this._overrides, {
    required List<Diagnostic> before,
    required this.changes,
  }) : _before = {for (final d in before) _keyOf(d)};

  final OverrideSet _overrides;
  final Set<(DiagnosticCode, String?, String?)> _before;

  /// The changed nodes: the file as diagnostics name it, the pointer of the
  /// node an override set a member of, and the pointer of the override field
  /// that did.
  final List<(String, JsonPointer, JsonPointer)> changes;

  /// [diagnostic] with the overrides that introduced it as related
  /// locations.
  Diagnostic attach(Diagnostic diagnostic) {
    final pointer = diagnostic.pointer;
    if (pointer == null || _before.contains(_keyOf(diagnostic))) {
      return diagnostic;
    }
    // One override field may change several nodes: it is named once.
    final fields = <String>{};
    final related = [
      for (final (file, at, field) in changes)
        if (file == diagnostic.file &&
            _nested(pointer, at) &&
            fields.add(field.value))
          RelatedLocation(
            message: 'Introduced by this override.',
            file: _overrides.file,
            pointer: field,
            span: _overrides.spanOf(field),
          ),
    ];
    if (related.isEmpty) return diagnostic;
    return diagnostic.withRelated([...diagnostic.related, ...related]);
  }

  static (DiagnosticCode, String?, String?) _keyOf(Diagnostic d) =>
      (d.code, d.file, d.pointer?.value);

  /// Whether one of [a] and [b] is the other or inside it.
  static bool _nested(JsonPointer a, JsonPointer b) {
    final x = a.tokens;
    final y = b.tokens;
    final length = x.length < y.length ? x.length : y.length;
    for (var i = 0; i < length; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }
}
