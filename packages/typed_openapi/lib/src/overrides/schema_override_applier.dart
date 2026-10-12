import '../model/spec_node.dart';
import '../normalize/spec_edit.dart';
import 'nullable_shape.dart';
import 'override_edit.dart';
import 'override_edit_context.dart';
import 'override_resolver.dart';
import 'override_set.dart';
import 'reference_override_applier.dart';
import 'type_override_applier.dart';

/// The edits of the overrides of a schema or of one of its properties.
final class SchemaOverrideApplier {
  /// Creates an applier that works in [_context].
  SchemaOverrideApplier(this._context)
    : _references = ReferenceOverrideApplier(_context),
      _types = TypeOverrideApplier(_context);

  final OverrideEditContext _context;
  final ReferenceOverrideApplier _references;
  final TypeOverrideApplier _types;

  /// Schema fields replaced as they are, in the order they are applied.
  static const _plainFields = [
    'format',
    'required',
    'items',
    'additionalProperties',
    'enum',
    'discriminator',
  ];

  /// The edits of the spec fields of [entry] for the schema at [at]; for a
  /// [property], `required` is left to [required].
  Iterable<OverrideEdit> edits(
    OverrideEntry entry,
    SpecLocation at, {
    required bool property,
  }) sync* {
    final spec = entry.spec;
    if (spec.keys.every((k) => property && k == 'required')) return;
    final raw = _context.object(at);
    if (raw == null) {
      _context.report(
        .invalidOverride,
        entry,
        null,
        'The schema at ${at.pointer.value} is not an object; its fields '
        'cannot be set.',
      );
      return;
    }
    final rawRef = raw[r'$ref'] is String ? raw[r'$ref'] as String : null;
    final shape = NullableShape.of(raw, _context.version);
    final toRef =
        spec[r'$ref'] is String ||
        spec.containsKey('nullable') && (rawRef != null || shape != null);
    if (toRef) {
      yield* _references.edits(
        entry,
        at,
        raw,
        property: property,
        rawRef: rawRef,
        shape: shape,
      );
    } else if (_context.version == .v30 && rawRef != null) {
      _reportIgnoredSiblings(entry, property);
    } else {
      yield* _fields(entry, at, raw, property);
    }
  }

  /// Reports every field of [entry] that 3.0 would ignore on a reference.
  void _reportIgnoredSiblings(OverrideEntry entry, bool property) {
    for (final field in ['type', ..._plainFields]) {
      if (!entry.spec.containsKey(field) || property && field == 'required') {
        continue;
      }
      _context.report(
        .fixNotApplied,
        entry,
        field,
        'This override was not applied: in OpenAPI 3.0 the siblings of '
        '"\$ref" are ignored, so "$field" would have no effect on a '
        'schema that is a reference.',
        fix: 'Override the referenced schema by its name under "schemas".',
      );
    }
  }

  /// The edits of `type`, `nullable` and the plain fields of a schema that
  /// is not a reference.
  Iterable<OverrideEdit> _fields(
    OverrideEntry entry,
    SpecLocation at,
    Map<String, Object?> raw,
    bool property,
  ) sync* {
    final spec = entry.spec;
    if (spec.containsKey('type') || spec.containsKey('nullable')) {
      yield* _types.edits(entry, at, raw);
    }
    for (final field in _plainFields) {
      if (field == 'required' && property) continue;
      if (!spec.containsKey(field)) continue;
      yield* _context.set(entry, field, at, raw, spec[field]);
    }
  }

  /// The edits of the `required` list of the schema at [owner] for the
  /// `required` of its [properties].
  Iterable<OverrideEdit> required(
    SpecLocation owner,
    List<PropertyTarget> properties,
  ) sync* {
    final raw = _context.object(owner) ?? const {};
    final current = switch (raw['required']) {
      final List<Object?> names => names,
      _ => const <Object?>[],
    };
    final next = [...current];
    final sources = <(OverrideEntry, String)>[];
    for (final property in properties) {
      final name = property.entry.key;
      final required = property.entry.spec['required'] == true;
      if (next.contains(name) == required) {
        _context.unchanged(property.entry, 'required');
        continue;
      }
      if (required) {
        next.add(name);
      } else {
        next.remove(name);
      }
      sources.add((property.entry, 'required'));
    }
    if (sources.isEmpty) return;
    final at = owner.child('required');
    yield OverrideEdit(
      next.isEmpty ? SpecEdit.remove(at) : SpecEdit.add(at, next),
      sources,
    );
  }
}
