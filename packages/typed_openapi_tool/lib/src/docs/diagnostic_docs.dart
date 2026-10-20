import 'diagnostic_doc.dart';

/// What [DiagnosticSource.read] found: the complete docs and what is missing.
final class DiagnosticDocs {
  /// Creates the result.
  const DiagnosticDocs({required this.docs, required this.problems});

  /// The documentation of every code whose comment is complete, in the
  /// order of the enum.
  final List<DiagnosticDoc> docs;

  /// One sentence for each comment that is missing or incomplete.
  final List<String> problems;
}
