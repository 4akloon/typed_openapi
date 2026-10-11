/// How serious a diagnostic is.
enum Severity {
  /// Correct code cannot be generated until this is fixed.
  error,

  /// Code is generated, but something in the input is wrong or ambiguous.
  warning,

  /// A note: a fix that was applied automatically, or a hint.
  info,
}
