/// One method found by [MethodScanner.methodsOf].
final class MeasuredMethod {
  /// A method called [name] of [length] lines.
  const MeasuredMethod(this.name, this.length);

  /// `Class.name`, with `@2`... for a repeated name.
  final String name;

  /// Lines from the signature to the closing brace.
  final int length;
}
