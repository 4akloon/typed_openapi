import '../model/spec_node.dart';
import '../normalize/spec_edit.dart';
import 'override_edit.dart';
import 'override_edit_context.dart';
import 'override_set.dart';

/// The edits of `type` and `nullable` of a schema that is not a reference;
/// `nullable` follows the document's dialect: `nullable: true` in 3.0, `null`
/// in `type` from 3.1.
final class TypeOverrideApplier {
  /// Creates an applier that works in [_context].
  const TypeOverrideApplier(this._context);

  final OverrideEditContext _context;

  static const _equality = OverrideEditContext.equality;

  /// The edits of `type` and `nullable` of the schema at [at] for the
  /// dialect of the document.
  Iterable<OverrideEdit> edits(
    OverrideEntry entry,
    SpecLocation at,
    Map<String, Object?> raw,
  ) => _context.version == .v30
      ? _typeAndNullable30(entry, at, raw)
      : _typeAndNullable31(entry, at, raw);

  Iterable<OverrideEdit> _typeAndNullable30(
    OverrideEntry entry,
    SpecLocation at,
    Map<String, Object?> raw,
  ) sync* {
    final spec = entry.spec;
    if (spec.containsKey('type')) {
      yield* _context.set(entry, 'type', at, raw, spec['type']);
    }
    if (spec case {'nullable': final bool nullable}) {
      if ((raw['nullable'] == true) == nullable) {
        _context.unchanged(entry, 'nullable');
      } else {
        yield OverrideEdit(
          nullable
              ? SpecEdit.add(at.child('nullable'), true)
              : SpecEdit.remove(at.child('nullable')),
          [(entry, 'nullable')],
        );
      }
    }
  }

  Iterable<OverrideEdit> _typeAndNullable31(
    OverrideEntry entry,
    SpecLocation at,
    Map<String, Object?> raw,
  ) sync* {
    final spec = entry.spec;
    final current = _types(raw['type']);
    final wasNullable = current.contains('null');
    final base = [
      for (final type in current)
        if (type != 'null') type,
    ];
    final nextBase = _nextBase(spec, base);
    var nullable = _nullableAfter(spec, wasNullable);
    var failed = false;
    if (nullable && nextBase.isEmpty) {
      failed = true;
      _reportNullableWithoutType(entry);
      if (!spec.containsKey('type')) return;
      nullable = false;
    }
    final fields = _changedFields(
      entry,
      sameType: _equality.equals(base, nextBase),
      sameNullable: wasNullable == nullable,
      nullableFailed: failed,
    );
    if (fields.isEmpty) return;
    if (_dropsNullability(spec, wasNullable)) _reportDroppedNullability(entry);
    final types = [...nextBase, if (nullable) 'null'];
    yield OverrideEdit(
      switch (types) {
        [] => SpecEdit.remove(at.child('type')),
        [final type] => SpecEdit.add(at.child('type'), type),
        _ => SpecEdit.add(at.child('type'), types),
      },
      [for (final field in fields) (entry, field)],
    );
  }

  /// The type names of a `type` value, a string or a list of them.
  static List<String> _types(Object? type) => switch (type) {
    final String type => [type],
    final List<Object?> types => types.whereType<String>().toList(),
    _ => const <String>[],
  };

  /// The types without `null` after the override: the one it sets, none for
  /// `type: null`, else the [base] it keeps.
  static List<String> _nextBase(Map<String, Object?> spec, List<String> base) =>
      switch (spec) {
        {'type': final String type} => [type],
        {'type': null} => const <String>[],
        _ => base,
      };

  /// Whether the schema is nullable after the override. `type: null` without
  /// `nullable` removes the type, and the schema with it is no longer
  /// nullable.
  static bool _nullableAfter(Map<String, Object?> spec, bool wasNullable) =>
      spec['nullable'] as bool? ??
      (wasNullable && (spec['type'] != null || !spec.containsKey('type')));

  /// Whether the override removes the type of a nullable schema and says
  /// nothing about `nullable`.
  static bool _dropsNullability(Map<String, Object?> spec, bool wasNullable) =>
      spec.containsKey('type') &&
      spec['type'] == null &&
      wasNullable &&
      !spec.containsKey('nullable');

  /// The fields of [entry] that change the `type` list, after reporting the
  /// ones that do not.
  List<String> _changedFields(
    OverrideEntry entry, {
    required bool sameType,
    required bool sameNullable,
    required bool nullableFailed,
  }) {
    final spec = entry.spec;
    final fields = [
      if (spec.containsKey('type')) 'type',
      if (spec.containsKey('nullable') && !nullableFailed) 'nullable',
    ];
    if (spec.containsKey('type') && sameType) {
      _context.unchanged(entry, 'type');
      fields.remove('type');
    }
    if (fields.contains('nullable') && sameNullable) {
      _context.unchanged(entry, 'nullable');
      fields.remove('nullable');
    }
    return fields;
  }

  void _reportNullableWithoutType(OverrideEntry entry) {
    _context.report(
      .invalidOverride,
      entry,
      'nullable',
      'From OpenAPI 3.1, a schema is nullable through "null" in its '
          '"type", and this schema has no type.',
      fix: 'Add "type" to the override.',
    );
  }

  void _reportDroppedNullability(OverrideEntry entry) {
    _context.report(
      .overrideNullabilityDropped,
      entry,
      'type',
      'From OpenAPI 3.1, nullability is the "null" in "type"; removing the '
          'type also makes the schema non-nullable.',
    );
  }
}
