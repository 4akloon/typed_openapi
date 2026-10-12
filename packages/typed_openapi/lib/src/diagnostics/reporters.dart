import 'dart:convert';

import 'diagnostic_bag.dart';
import 'severity.dart';

/// Turns collected diagnostics into the text a user or a tool reads.
abstract interface class DiagnosticReporter {
  /// Formats [diagnostics], sorted in report order.
  ///
  /// Diagnostics a baseline accepts are counted; with [showBaselined] they
  /// are listed too, marked as baselined.
  String format(DiagnosticBag diagnostics, {bool showBaselined = false});
}

/// Formats diagnostics for a terminal, ending with a summary line.
final class TextReporter implements DiagnosticReporter {
  /// Creates a text reporter.
  const TextReporter();

  @override
  String format(DiagnosticBag diagnostics, {bool showBaselined = false}) {
    final out = StringBuffer();
    final baselined = diagnostics.baselined;
    final listed = [
      ...diagnostics.sorted.map((d) => (d, false)),
      if (showBaselined) ...baselined.map((d) => (d, true)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    for (final (d, accepted) in listed) {
      final mark = accepted ? ' [baselined]' : '';
      out.writeln(
        '${d.severity.name} ${d.code.id} ${d.code.slug}$mark: ${d.message}',
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
    if (baselined.isNotEmpty) out.write(', baselined: ${baselined.length}');
    return out.toString();
  }
}

/// Formats diagnostics as JSON for CI and other tools.
///
/// Lines and columns are 1-based; they are null when positions are unknown.
/// `summary.baselined` counts the diagnostics a baseline accepts.
final class JsonReporter implements DiagnosticReporter {
  /// Creates a JSON reporter.
  const JsonReporter();

  @override
  String format(DiagnosticBag diagnostics, {bool showBaselined = false}) {
    final baselined = diagnostics.baselined;
    final listed = [
      ...diagnostics.sorted.map((d) => (d, false)),
      if (showBaselined) ...baselined.map((d) => (d, true)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return const JsonEncoder.withIndent('  ').convert({
      'diagnostics': [
        for (final (d, accepted) in listed)
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
            'baselined': accepted,
          },
      ],
      'summary': {
        for (final s in Severity.values) s.name: diagnostics.count(s),
        'baselined': baselined.length,
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
