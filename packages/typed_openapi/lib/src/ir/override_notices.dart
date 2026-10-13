import '../model/schema.dart';
import '../overrides/override_set.dart';
import 'ir_context.dart';

/// Reports the fields of an override that change nothing for the schema
/// they are written for (TOA807).
final class OverrideNotices {
  /// Reports for the client of [_context].
  const OverrideNotices(this._context);

  final IrContext _context;

  /// Reports the override `union` of [schema], which has no effect on
  /// [what].
  void unionHasNoEffect(SchemaObject schema, String what) {
    final entry = _context.overrides.schemaAt(schema.location);
    if (entry == null || entry.union == null) return;
    _context.reportAtOverride(
      .overrideUnchanged,
      'The union of this override has no effect: $what.',
      entry,
      'union',
      fix: 'Remove it.',
    );
  }

  /// Reports the `name` and `exhaustive` of the override of [schema], an
  /// alias that is not a declaration: they would change a type it does not
  /// have.
  void aliasHasNoEffect(SchemaObject schema) {
    final entry = _context.overrides.schemaAt(schema.location);
    if (entry == null) return;
    for (final (field, written) in [
      ('name', entry.name),
      ('exhaustive', entry.exhaustive),
    ]) {
      if (written == null) continue;
      _context.reportAtOverride(
        .overrideUnchanged,
        'The $field of this override has no effect: the schema is not '
        'generated as a type of its own, its uses are the type of what it '
        'stands for.',
        entry,
        field,
        fix: 'Remove it, or override the schema this one refers to.',
      );
    }
  }

  /// Reports the `exhaustive` of the override of [schema], a model: only an
  /// enum or a union can be exhaustive.
  void exhaustiveOnModel(SchemaObject schema) {
    final entry = _context.overrides.schemaAt(schema.location);
    if (entry == null || entry.exhaustive == null) return;
    _context.reportAtOverride(
      .overrideUnchanged,
      'The exhaustive of this override has no effect: only an enum or a '
          'union can be exhaustive, and this schema is a model.',
      entry,
      'exhaustive',
      fix: 'Remove it.',
    );
  }

  /// Reports the `triState` of the property override [entry], whose model is
  /// used in responses only: only a request model has tri-state fields.
  void triStateOnResponseModel(PropertyOverride entry) {
    _context.reportAtOverride(
      .overrideUnchanged,
      'The triState of this override has no effect: the model is used in '
          'responses only, and only a request model has tri-state fields.',
      entry,
      'triState',
      fix: 'Remove it.',
    );
  }
}
