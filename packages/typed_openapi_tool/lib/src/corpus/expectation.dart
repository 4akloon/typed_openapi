/// What generation is expected to do with a corpus spec.
sealed class Expectation {
  /// Creates the expectation.
  const Expectation();
}

/// The client is generated, and its code passes the analyzer.
final class Generates extends Expectation {
  /// Creates the expectation.
  const Generates();
}

/// The client is skipped for errors of the spec itself: its error codes are
/// exactly [codes] (artemis: TOA009).
final class CheckErrors extends Expectation {
  /// Creates the expectation of the error codes [codes].
  const CheckErrors(this.codes);

  /// The codes of the errors, sorted.
  final List<String> codes;
}
