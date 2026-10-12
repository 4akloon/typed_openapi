import 'diagnostic.dart';
import 'diagnostic_code.dart';
import 'severity.dart';

/// The levels a client's config gives diagnostic codes, in place of their
/// [DiagnosticCode.defaultSeverity].
///
/// A level of `null` turns the code off: its diagnostics are not reported
/// and do not change the exit code.
final class SeverityLevels {
  /// Creates the levels; codes missing from [levels] keep their default.
  const SeverityLevels([this.levels = const {}]);

  /// The level of each code the config names; `null` is `off`.
  final Map<DiagnosticCode, Severity?> levels;

  /// [diagnostic] with the level of its code, or null when the code is off.
  Diagnostic? apply(Diagnostic diagnostic) {
    if (!levels.containsKey(diagnostic.code)) return diagnostic;
    final level = levels[diagnostic.code];
    if (level == null) return null;
    return level == diagnostic.severity
        ? diagnostic
        : diagnostic.withSeverity(level);
  }
}
