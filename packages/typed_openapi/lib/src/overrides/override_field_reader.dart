import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/json_pointer.dart';
import '../load/spec_document.dart';
import 'key_suggestion.dart';

/// Typed access to the fields of an overrides document: every value of the
/// wrong type is reported as `invalid-override` at its position and read as
/// absent.
final class OverrideFieldReader {
  /// Creates a reader of [_document] that reports to [_diagnostics].
  const OverrideFieldReader(this._diagnostics, this._document);

  final DiagnosticBag _diagnostics;
  final SpecDocument _document;

  /// The entries of the [key] mapping of [parent] whose values are
  /// mappings, with their pointers; other values are reported.
  List<(String, Map<String, Object?>, JsonPointer)> entries(
    Map<String, Object?> parent,
    String key,
    JsonPointer at,
  ) {
    // A section whose entries are all commented out reads as null.
    if (parent.containsKey(key) && parent[key] == null) return const [];
    final section = map(parent, key, at);
    if (section == null) return const [];
    final p = at.child(key);
    final entries = <(String, Map<String, Object?>, JsonPointer)>[];
    for (final MapEntry(key: name, :value) in section.entries) {
      if (value is Map<String, Object?>) {
        entries.add((name, value, p.child(name)));
      } else {
        invalid('"$name" must be a mapping.', p.child(name));
      }
    }
    return entries;
  }

  /// The mapping at [key] of [parent]; null when absent or not a mapping.
  Map<String, Object?>? map(
    Map<String, Object?> parent,
    String key,
    JsonPointer at,
  ) {
    if (!parent.containsKey(key)) return null;
    final value = parent[key];
    if (value is Map<String, Object?>) return value;
    invalid('"$key" must be a mapping.', at.child(key));
    return null;
  }

  /// The non-empty string at [key] of [parent]; null when absent or not
  /// one, and for an absent [required] key a report at [at].
  String? string(
    Map<String, Object?> parent,
    String key,
    JsonPointer at, {
    bool required = false,
  }) {
    if (!parent.containsKey(key)) {
      if (required) invalid('"$key" is required.', at);
      return null;
    }
    final value = parent[key];
    if (value is String && value.isNotEmpty) return value;
    invalid('"$key" must be a non-empty string.', at.child(key));
    return null;
  }

  /// The boolean at [key] of [parent]; null when absent or not one.
  bool? boolean(Map<String, Object?> parent, String key, JsonPointer at) {
    if (!parent.containsKey(key)) return null;
    final value = parent[key];
    if (value is bool) return value;
    invalid('"$key" must be true or false.', at.child(key));
    return null;
  }

  /// Reports every key of [map] that is not in [allowed], with the closest
  /// allowed key as a hint.
  void checkKeys(
    Map<String, Object?> map,
    Set<String> allowed,
    JsonPointer at,
  ) {
    final known = allowed.toList()..sort();
    for (final key in map.keys) {
      if (allowed.contains(key)) continue;
      final closest = KeySuggestion.closest(key, known);
      _diagnostics.report(
        .unknownOverrideKey,
        'Unknown key "$key"; it is ignored.',
        file: _document.file,
        pointer: at.child(key),
        span: _document.spanOf(at.child(key)),
        fix:
            '${closest == null ? '' : 'Did you mean "$closest"? '}'
            'Allowed keys here: ${known.join(', ')}.',
      );
    }
  }

  /// Reports [message] at [at] as an invalid override.
  void invalid(String message, JsonPointer at, {String? fix}) {
    _diagnostics.report(
      DiagnosticCode.invalidOverride,
      message,
      file: _document.file,
      pointer: at,
      span: _document.spanOf(at),
      fix: fix,
    );
  }
}
