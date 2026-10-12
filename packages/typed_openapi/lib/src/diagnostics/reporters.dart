import 'dart:convert';

import 'diagnostic_bag.dart';
import 'severity.dart';

/// Turns collected diagnostics into the text a user or a tool reads.
abstract interface class DiagnosticReporter {
  /// Formats [diagnostics], sorted in report order.
  String format(DiagnosticBag diagnostics);
}

/// Formats diagnostics for a terminal, ending with a summary line.
final class TextReporter implements DiagnosticReporter {
  /// Creates a text reporter.
  const TextReporter();

  @override
  String format(DiagnosticBag diagnostics) {
    final out = StringBuffer();
    for (final d in diagnostics.sorted) {
      out.writeln(
        '${d.severity.name} ${d.code.id} ${d.code.slug}: ${d.message}',
      );
      final location = d.location;
      if (location != null) out.writeln('  --> $location');
      final pointer = d.pointer;
      if (pointer != null) out.writeln('  at ${pointer.value}');
      final fix = d.fix;
      // A fix may end with an override snippet on several lines.
      if (fix != null) out.writeln('  fix: ${fix.replaceAll('\n', '\n    ')}');
    }
    out.write(
      'errors: ${diagnostics.count(.error)}, '
      'warnings: ${diagnostics.count(.warning)}, '
      'infos: ${diagnostics.count(.info)}',
    );
    return out.toString();
  }
}

/// Formats diagnostics as JSON for CI and other tools.
///
/// Lines and columns are 1-based; they are null when positions are unknown.
final class JsonReporter implements DiagnosticReporter {
  /// Creates a JSON reporter.
  const JsonReporter();

  @override
  String format(DiagnosticBag diagnostics) {
    return const JsonEncoder.withIndent('  ').convert({
      'diagnostics': [
        for (final d in diagnostics.sorted)
          {
            'code': d.code.id,
            'name': d.code.slug,
            'severity': d.severity.name,
            'message': d.message,
            'file': d.file,
            'pointer': d.pointer?.value,
            'line': d.line,
            'column': d.column,
            'fix': d.fix,
          },
      ],
      'summary': {
        for (final s in Severity.values) s.name: diagnostics.count(s),
      },
    });
  }
}

/// The output formats the tool can print.
enum ReportFormat {
  /// Human-readable text.
  text(TextReporter()),

  /// Machine-readable JSON.
  json(JsonReporter());

  const ReportFormat(this.reporter);

  /// The reporter that prints this format.
  final DiagnosticReporter reporter;
}
