import '../model/spec_node.dart';
import '../normalize/spec_edit.dart';
import 'nullable_shape.dart';
import 'override_edit.dart';
import 'override_edit_context.dart';
import 'override_set.dart';

/// The edits of a schema override that makes the node a `$ref`, or changes
/// the nullability of a node that is one or has a `null` branch.
///
/// A nullable reference is `allOf: [{$ref}]` with `nullable: true` in 3.0
/// and `anyOf: [{$ref}, {type: 'null'}]` from 3.1.
final class ReferenceOverrideApplier {
  /// Creates an applier that works in [_context].
  const ReferenceOverrideApplier(this._context);

  final OverrideEditContext _context;

  static const _equality = OverrideEditContext.equality;

  /// Makes the schema at [at] a (nullable) reference, or changes the
  /// nullability of a schema that is one or has a `null` branch.
  ///
  /// An override with `$ref` replaces the node. One with only `nullable`
  /// keeps every other key of the node: [rawRef] is the `$ref` of a schema
  /// that is a reference, [shape] the nullable form of one that is nullable.
  Iterable<OverrideEdit> edits(
    OverrideEntry entry,
    SpecLocation at,
    Map<String, Object?> raw, {
    required bool property,
    required String? rawRef,
    required NullableShape? shape,
  }) sync* {
    final spec = entry.spec;
    final specRef = spec[r'$ref'];
    final others = [
      for (final field in spec.keys)
        if (field != r'$ref' &&
            field != 'nullable' &&
            !(property && field == 'required'))
          field,
    ];
    if (others.isNotEmpty) {
      _reportOtherField(
        entry,
        others.first,
        specRef is String || rawRef != null,
      );
    } else if (specRef is String) {
      yield* _replaceWithReference(entry, at, raw, specRef);
    } else {
      yield* _changeNullability(entry, at, raw, rawRef, shape);
    }
  }

  /// Reports [field], which cannot be set where the node becomes (or is) a
  /// reference or a nullable union.
  void _reportOtherField(OverrideEntry entry, String field, bool isReference) {
    _context.report(
      .invalidOverride,
      entry,
      field,
      isReference
          ? '"$field" cannot be set on a schema that is a reference.'
          : '"$field" cannot be set together with "nullable" on a schema that '
                'is nullable through "anyOf" or "oneOf".',
      fix: isReference
          ? r'Replace the reference with "$ref" and "nullable" only.'
          : 'Override "nullable" alone, or the schema by its name.',
    );
  }

  /// The edit that makes the node at [at] the (nullable) reference [specRef].
  Iterable<OverrideEdit> _replaceWithReference(
    OverrideEntry entry,
    SpecLocation at,
    Map<String, Object?> raw,
    String specRef,
  ) sync* {
    final spec = entry.spec;
    final nullable = spec['nullable'] == true;
    final next = <String, Object?>{
      if (!nullable) r'$ref': specRef,
      ..._nullableForm(specRef, nullable),
    };
    final fields = [
      for (final field in [r'$ref', 'nullable'])
        if (spec.containsKey(field)) field,
    ];
    if (_equality.equals(raw, next)) {
      for (final field in fields) {
        _context.unchanged(entry, field);
      }
      return;
    }
    yield OverrideEdit(SpecEdit.replace(at, next), [
      for (final field in fields) (entry, field),
    ]);
  }

  /// The edit that adds or removes the nullability of a reference
  /// ([rawRef]) or of a nullable schema ([shape]), keeping the other keys.
  Iterable<OverrideEdit> _changeNullability(
    OverrideEntry entry,
    SpecLocation at,
    Map<String, Object?> raw,
    String? rawRef,
    NullableShape? shape,
  ) sync* {
    final nullable = entry.spec['nullable'] == true;
    if (nullable == (shape != null)) {
      _context.unchanged(entry, 'nullable');
      return;
    }
    final Map<String, Object?> next;
    if (shape == null) {
      next = {
        for (final MapEntry(:key, :value) in raw.entries)
          if (key != r'$ref') key: value,
        ..._nullableForm(rawRef!, true),
      };
    } else {
      final merged = shape.withoutNull();
      if (merged == null) {
        _reportUnmergeable(entry, shape);
        return;
      }
      next = merged;
    }
    yield OverrideEdit(SpecEdit.replace(at, next), [(entry, 'nullable')]);
  }

  void _reportUnmergeable(OverrideEntry entry, NullableShape shape) {
    _context.report(
      .fixNotApplied,
      entry,
      'nullable',
      'This override was not applied: the schema and the "'
          '${shape.key}" branch both set the same key to different values, '
          'so they cannot be merged.',
      fix: 'Override the schema by its name.',
    );
  }

  /// The keys that make [ref] nullable in the document's dialect; none when
  /// [nullable] is false.
  Map<String, Object?> _nullableForm(String ref, bool nullable) => {
    if (nullable && _context.version == .v30) ...{
      'allOf': [
        {r'$ref': ref},
      ],
      'nullable': true,
    },
    if (nullable && _context.version != .v30)
      'anyOf': [
        {r'$ref': ref},
        {'type': 'null'},
      ],
  };
}
