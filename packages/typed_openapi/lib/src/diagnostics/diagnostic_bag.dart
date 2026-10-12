import 'package:source_span/source_span.dart';

import 'diagnostic.dart';
import 'diagnostic_code.dart';
import 'json_pointer.dart';
import 'severity.dart';

/// Collects diagnostics while input is processed.
///
/// Processing code reports problems here instead of throwing, so a single
/// run shows every problem it can find.
///
/// A diagnostic equal to one already in the bag (same code, severity,
/// message, file, pointer and start position) is ignored: the same region
/// of a file read twice, for example through two `$ref`s or two clients,
/// reports each problem once.
///
/// Diagnostics a baseline accepts are kept apart ([baselined]): they are
/// not in [all], [count] or [hasErrors].
final class DiagnosticBag {
  final List<Diagnostic> _items = [];
  final List<Diagnostic> _baselined = [];
  final Set<(DiagnosticCode, Severity, String, String?, String?, int?)> _seen =
      {};
  final Set<(DiagnosticCode, Severity, String, String?, String?, int?)>
  _seenBaselined = {};

  /// All diagnostics in the order they were reported.
  List<Diagnostic> get all => List.unmodifiable(_items);

  /// Diagnostics a baseline accepts, in report order.
  List<Diagnostic> get baselined => _baselined.toList()..sort();

  /// Whether any diagnostic has [Severity.error].
  bool get hasErrors => _items.any((d) => d.severity == .error);

  /// All diagnostics in report order: by file, position, pointer, code and
  /// message (see [Diagnostic.compareTo]).
  List<Diagnostic> get sorted => _items.toList()..sort();

  /// How many diagnostics have [severity].
  int count(Severity severity) =>
      _items.where((d) => d.severity == severity).length;

  /// Adds an already built [diagnostic], unless an equal one is present.
  void add(Diagnostic diagnostic) {
    if (_seen.add(_keyOf(diagnostic))) _items.add(diagnostic);
  }

  /// Adds [diagnostic], which a baseline accepts, unless an equal one is
  /// present.
  void addBaselined(Diagnostic diagnostic) {
    if (_seenBaselined.add(_keyOf(diagnostic))) _baselined.add(diagnostic);
  }

  static (DiagnosticCode, Severity, String, String?, String?, int?) _keyOf(
    Diagnostic diagnostic,
  ) => (
    diagnostic.code,
    diagnostic.severity,
    diagnostic.message,
    diagnostic.file,
    diagnostic.pointer?.value,
    diagnostic.span?.start.offset,
  );

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
    List<String> args = const [],
  }) {
    add(
      Diagnostic(
        code: code,
        severity: severity ?? code.defaultSeverity,
        message: message,
        file: file,
        pointer: pointer,
        span: span,
        fix: fix,
        args: args,
      ),
    );
  }
}
