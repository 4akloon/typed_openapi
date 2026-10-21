import '../diagnostics/message_text.dart';
import 'ir_context.dart';
import 'operation_builder.dart';

/// Reports the overrides of operations that the client's `include` and
/// `exclude` filters leave out (TOA810): the entry is applied to the spec
/// and generates nothing.
///
/// An entry is reported once, with its parameter, body and response
/// overrides. An entry that resolves to no operation is TOA804 already, and
/// one with its own `exclude: true` asked for the operation to be left out.
final class DeadOverrides {
  /// Creates a check for the client of [_context].
  const DeadOverrides(this._context);

  final IrContext _context;

  /// Reports the operation entries whose operation is in [all] but not in
  /// [selected].
  void report(List<SpecOperation> all, List<SpecOperation> selected) {
    final generated = {for (final e in selected) e.operation.location};
    final present = {for (final e in all) e.operation.location};
    final overrides = _context.spec.overrides;
    if (overrides == null) return;
    for (final (location, entry) in _context.overrides.operations) {
      if (!present.contains(location) || generated.contains(location)) {
        continue;
      }
      if (entry.exclude ?? false) continue;
      _context.diagnostics.report(
        .overrideOperationNotGenerated,
        'The override of ${MessageText.quote(entry.key)} changes nothing: '
        'the operation is left out by include or exclude, so it is not '
        'generated.',
        file: overrides.file,
        pointer: entry.pointer,
        span: overrides.spanOf(entry.pointer),
        fix:
            'Remove the override, or change include or exclude so that '
            'the operation is generated.',
      );
    }
  }
}
