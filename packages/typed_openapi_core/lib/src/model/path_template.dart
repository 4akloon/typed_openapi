/// A path template (`/pets/{id}`) or any URL with `{variable}` parts.
///
/// The variable pattern is the one the runtime resolves paths with
/// (`OperationRequest.pathVariable`, which a test keeps equal), so every
/// variable the runtime finds has a parameter here.
extension type const PathTemplate(String value) {
  /// A variable of a template: `{name}`, where the name has no brace (`{}`
  /// is a variable with an empty name).
  static final variable = RegExp(r'\{([^{}]*)\}');

  /// The variables of the template, in order, as matches whose group 1 is
  /// the name.
  Iterable<RegExpMatch> get variables => variable.allMatches(value);
}
