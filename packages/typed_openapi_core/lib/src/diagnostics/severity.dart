/// How serious a diagnostic is.
///
/// The values are declared from the most to the least serious: code that
/// compares levels (a config may raise a level but not lower it) compares
/// [index], so do not reorder them.
enum Severity {
  /// Correct code cannot be generated until this is fixed.
  error,

  /// Code is generated, but something in the input is wrong or ambiguous.
  warning,

  /// A note: a fix that was applied automatically, or a hint.
  info,
}
