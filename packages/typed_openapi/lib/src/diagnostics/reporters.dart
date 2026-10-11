import 'dart:convert';

import 'diagnostic.dart';
import 'severity.dart';

/// Orders [diagnostics] by file, position, pointer, code and message, so
/// the same input always prints the same report.
List<Diagnostic> sortDiagnostics(Iterable<Diagnostic> diagnostics) {
  return diagnostics.toList()..sort(_compare);
}

int _compare(Diagnostic a, Diagnostic b) {
  final byFile = (a.file ?? '').compareTo(b.file ?? '');
  if (byFile != 0) return byFile;
  final byOffset = (a.span?.start.offset ?? -1).compareTo(
    b.span?.start.offset ?? -1,
  );
  if (byOffset != 0) return byOffset;
  final byPointer = (a.pointer?.value ?? '').compareTo(b.pointer?.value ?? '');
  if (byPointer != 0) return byPointer;
  final byCode = a.code.id.compareTo(b.code.id);
  if (byCode != 0) return byCode;
  return a.message.compareTo(b.message);
}

/// Formats [diagnostics] for a terminal, ending with a summary line.
String formatText(Iterable<Diagnostic> diagnostics) {
  final sorted = sortDiagnostics(diagnostics);
  final out = StringBuffer();
  for (final d in sorted) {
    out.writeln('${d.severity.name} ${d.code.id} ${d.code.slug}: ${d.message}');
    final location = _location(d);
    if (location != null) out.writeln('  --> $location');
    final pointer = d.pointer;
    if (pointer != null) out.writeln('  at ${pointer.value}');
    final fix = d.fix;
    if (fix != null) out.writeln('  fix: $fix');
  }
  final counts = _counts(sorted);
  out.write(
    'errors: ${counts[Severity.error]}, '
    'warnings: ${counts[Severity.warning]}, '
    'infos: ${counts[Severity.info]}',
  );
  return out.toString();
}

/// Formats [diagnostics] as JSON for CI and other tools.
///
/// Lines and columns are 1-based; they are null when positions are unknown.
String formatJson(Iterable<Diagnostic> diagnostics) {
  final sorted = sortDiagnostics(diagnostics);
  final counts = _counts(sorted);
  return const JsonEncoder.withIndent('  ').convert({
    'diagnostics': [
      for (final d in sorted)
        {
          'code': d.code.id,
          'name': d.code.slug,
          'severity': d.severity.name,
          'message': d.message,
          'file': d.file,
          'pointer': d.pointer?.value,
          'line': _line(d),
          'column': _column(d),
          'fix': d.fix,
        },
    ],
    'summary': {for (final s in Severity.values) s.name: counts[s]},
  });
}

String? _location(Diagnostic d) {
  final file = d.file;
  if (file == null) return null;
  final line = _line(d);
  return line == null ? file : '$file:$line:${_column(d)}';
}

int? _line(Diagnostic d) {
  final start = d.span?.start;
  return start == null ? null : start.line + 1;
}

int? _column(Diagnostic d) {
  final start = d.span?.start;
  return start == null ? null : start.column + 1;
}

Map<Severity, int> _counts(List<Diagnostic> diagnostics) => {
  for (final s in Severity.values)
    s: diagnostics.where((d) => d.severity == s).length,
};
