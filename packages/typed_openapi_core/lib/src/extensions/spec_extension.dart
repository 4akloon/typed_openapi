import '../diagnostics/diagnostic_code.dart';

/// One `x-` extension key that the generator reads from a spec.
final class SpecExtension {
  /// Creates the description of an extension.
  const SpecExtension({
    required this.key,
    required this.appliesTo,
    required this.effect,
    required this.example,
    this.diagnostics = const [],
  });

  /// The key as it is written in the spec, such as `x-enum-varnames`.
  final String key;

  /// The kind of spec node that carries the key.
  final String appliesTo;

  /// What the key changes in the generated code, as a sentence.
  final String effect;

  /// A YAML snippet that uses the key.
  final String example;

  /// The diagnostics that report a wrong value of the key.
  final List<DiagnosticCode> diagnostics;
}
