import 'dart:convert';

import 'diagnostic_bag.dart';
import 'github_actions_reporter.dart';
import 'message_text.dart';
import 'sarif_reporter.dart';
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
        '${d.severity.name} ${d.code.id} ${d.code.slug}$mark: '
        '${MessageText.neutralise(d.message)}',
      );
      final location = d.location;
      if (location != null) out.writeln('  --> $location');
      final pointer = d.pointer;
      if (pointer != null) out.writeln('  at ${pointer.value}');
      final fix = d.fix;
      // A fix may end with an override snippet on several lines.
      if (fix != null) {
        final text = MessageText.neutralise(fix, keepLineFeeds: true);
        out.writeln('  fix: ${text.replaceAll('\n', '\n    ')}');
      }
      for (final related in d.related) {
        out.writeln('  related: ${MessageText.neutralise(related.message)}');
        final location = related.location;
        if (location != null) out.writeln('    --> $location');
        final pointer = related.pointer;
        if (pointer != null) out.writeln('    at ${pointer.value}');
      }
    }
    out.write(summary(diagnostics));
    return out.toString();
  }

  /// The summary line: errors, warnings and infos, and how many diagnostics
  /// a baseline accepts when there are any.
  static String summary(DiagnosticBag diagnostics) {
    final baselined = diagnostics.baselined.length;
    return 'errors: ${diagnostics.count(.error)}, '
        'warnings: ${diagnostics.count(.warning)}, '
        'infos: ${diagnostics.count(.info)}'
        '${baselined == 0 ? '' : ', baselined: $baselined'}';
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
            'related': [
              for (final r in d.related)
                {
                  'message': r.message,
                  'file': r.file,
                  'pointer': r.pointer?.value,
                  'line': r.span == null ? null : r.span!.start.line + 1,
                  'column': r.span == null ? null : r.span!.start.column + 1,
                },
            ],
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
  text('text', TextReporter()),

  /// Machine-readable JSON.
  json('json', JsonReporter()),

  /// SARIF 2.1.0 for code scanning.
  sarif('sarif', SarifReporter()),

  /// GitHub Actions annotations.
  githubActions('github-actions', GitHubActionsReporter());

  const ReportFormat(this.option, this.reporter);

  /// The value of `--format` that selects this format.
  final String option;

  /// The reporter that prints this format.
  final DiagnosticReporter reporter;

  /// The format whose [option] is [value].
  static ReportFormat byOption(String value) =>
      values.firstWhere((format) => format.option == value);
}
