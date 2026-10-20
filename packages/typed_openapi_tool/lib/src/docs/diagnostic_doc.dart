import 'package:typed_openapi_core/typed_openapi_core.dart';

/// The documentation of one [DiagnosticCode], read from its doc comment.
final class DiagnosticDoc {
  /// Creates the documentation of [code].
  const DiagnosticDoc({
    required this.code,
    required this.meaning,
    required this.example,
    required this.fix,
  });

  /// The code that is documented.
  final DiagnosticCode code;

  /// The paragraphs that say what the code means.
  final List<String> meaning;

  /// A short situation that reports the code, without the `Example:` label.
  final String example;

  /// What to change to make the code go away, without the `Fix:` label.
  final String fix;
}
