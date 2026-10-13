/// A file of an output directory that the generator may not replace: it did
/// not write it, or it differs from what the manifest says it wrote.
final class OutputStray {
  /// Creates a stray [path] with the [reason] it is not the generator's.
  const OutputStray(this.path, this.reason);

  /// The path relative to the directory, with `/` separators.
  final String path;

  /// Why the file counts as someone else's.
  final String reason;
}
