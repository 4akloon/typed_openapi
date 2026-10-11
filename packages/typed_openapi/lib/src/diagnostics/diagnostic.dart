import 'package:source_span/source_span.dart';

import 'diagnostic_code.dart';
import 'json_pointer.dart';
import 'severity.dart';

/// One finding about a spec or the configuration.
///
/// Diagnostics are ordered by file, position, pointer, code and message, so
/// the same input always prints the same report.
final class Diagnostic implements Comparable<Diagnostic> {
  /// Creates a diagnostic.
  const Diagnostic({
    required this.code,
    required this.severity,
    required this.message,
    this.file,
    this.pointer,
    this.span,
    this.fix,
  });

  /// The stable code from the catalog.
  final DiagnosticCode code;

  /// The severity; may differ from [DiagnosticCode.defaultSeverity].
  final Severity severity;

  /// What is wrong, in one or two sentences.
  final String message;

  /// The file the finding is about, as shown to the user.
  final String? file;

  /// Where in [file] the finding is.
  final JsonPointer? pointer;

  /// The source range in [file], when positions are known.
  final SourceSpan? span;

  /// What to change in the source to fix the finding.
  final String? fix;

  /// The 1-based line of the finding, or null when the position is unknown.
  int? get line => span == null ? null : span!.start.line + 1;

  /// The 1-based column of the finding, or null when the position is unknown.
  int? get column => span == null ? null : span!.start.column + 1;

  /// `file:line:column`, `file` when only the file is known, or null.
  String? get location {
    final file = this.file;
    if (file == null) return null;
    final line = this.line;
    return line == null ? file : '$file:$line:$column';
  }

  @override
  int compareTo(Diagnostic other) {
    final byFile = (file ?? '').compareTo(other.file ?? '');
    if (byFile != 0) return byFile;
    final byOffset = (span?.start.offset ?? -1).compareTo(
      other.span?.start.offset ?? -1,
    );
    if (byOffset != 0) return byOffset;
    final byPointer = (pointer?.value ?? '').compareTo(
      other.pointer?.value ?? '',
    );
    if (byPointer != 0) return byPointer;
    final byCode = code.id.compareTo(other.code.id);
    if (byCode != 0) return byCode;
    return message.compareTo(other.message);
  }
}
