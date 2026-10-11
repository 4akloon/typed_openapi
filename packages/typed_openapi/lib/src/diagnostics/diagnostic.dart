import 'package:source_span/source_span.dart';

import 'diagnostic_code.dart';
import 'json_pointer.dart';
import 'severity.dart';

/// One finding about a spec or the configuration.
final class Diagnostic {
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
}
