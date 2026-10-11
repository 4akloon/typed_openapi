import 'package:source_span/source_span.dart';

import 'diagnostic.dart';
import 'diagnostic_code.dart';
import 'json_pointer.dart';
import 'severity.dart';

/// Collects diagnostics while input is processed.
///
/// Processing code reports problems here instead of throwing, so a single
/// run shows every problem it can find.
class DiagnosticBag {
  final List<Diagnostic> _items = [];

  /// All diagnostics in the order they were reported.
  List<Diagnostic> get all => List.unmodifiable(_items);

  /// Whether any diagnostic has [Severity.error].
  bool get hasErrors => _items.any((d) => d.severity == Severity.error);

  /// Adds an already built [diagnostic].
  void add(Diagnostic diagnostic) => _items.add(diagnostic);

  /// Reports [code] with [message].
  ///
  /// [severity] defaults to the code's [DiagnosticCode.defaultSeverity].
  void report(
    DiagnosticCode code,
    String message, {
    Severity? severity,
    String? file,
    JsonPointer? pointer,
    SourceSpan? span,
    String? fix,
  }) {
    _items.add(
      Diagnostic(
        code: code,
        severity: severity ?? code.defaultSeverity,
        message: message,
        file: file,
        pointer: pointer,
        span: span,
        fix: fix,
      ),
    );
  }
}
