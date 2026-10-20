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
/// reports each problem once. Its preset hints ([Diagnostic.hints]) are
/// added to the one in the bag, so two clients with different presets keep
/// both hints.
///
/// Diagnostics a baseline accepts are kept apart ([baselined]): they are
/// not in [all], [count] or [hasErrors].
final class DiagnosticBag {
  final List<Diagnostic> _items = [];
  final List<Diagnostic> _baselined = [];
  final Map<(DiagnosticCode, Severity, String, String?, String?, int?), int>
  _seen = {};
  final Map<(DiagnosticCode, Severity, String, String?, String?, int?), int>
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

  /// Adds an already built [diagnostic], unless an equal one is present;
  /// then only its new hints are added to that one.
  void add(Diagnostic diagnostic) => _add(_items, _seen, diagnostic);

  /// Adds [diagnostic], which a baseline accepts, like [add].
  void addBaselined(Diagnostic diagnostic) =>
      _add(_baselined, _seenBaselined, diagnostic);

  static void _add(
    List<Diagnostic> items,
    Map<(DiagnosticCode, Severity, String, String?, String?, int?), int> seen,
    Diagnostic diagnostic,
  ) {
    final key = _keyOf(diagnostic);
    final index = seen[key];
    if (index == null) {
      seen[key] = items.length;
      items.add(diagnostic);
      return;
    }
    final present = items[index];
    final hints = [
      ...present.hints,
      for (final hint in diagnostic.hints)
        if (!present.hints.contains(hint)) hint,
    ];
    if (hints.length != present.hints.length) {
      items[index] = present.withHints(hints);
    }
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
