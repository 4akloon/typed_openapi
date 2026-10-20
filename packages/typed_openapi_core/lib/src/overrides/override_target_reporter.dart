import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/diagnostic_code.dart';
import 'override_set.dart';

/// Reports the problems of resolving an override at its position in the
/// overrides file.
final class OverrideTargetReporter {
  /// Creates a reporter of [_overrides] that reports to [_diagnostics].
  const OverrideTargetReporter(this._diagnostics, this._overrides);

  final DiagnosticBag _diagnostics;
  final OverrideSet _overrides;

  /// Reports that the node [entry] names is missing, with [message].
  void notFound(OverrideEntry entry, String message) => report(
    .overrideTargetNotFound,
    entry,
    '$message The override is not applied.',
    fix: 'Remove the override, or fix its address.',
  );

  /// Reports [message] at [entry], with the reason the entry gives.
  void report(
    DiagnosticCode code,
    OverrideEntry entry,
    String message, {
    String? fix,
  }) {
    final reason = entry.reason;
    _diagnostics.report(
      code,
      reason == null ? message : '$message Reason given: "$reason".',
      file: _overrides.file,
      pointer: entry.pointer,
      span: _overrides.spanOf(entry.pointer),
      fix: fix,
    );
  }
}
