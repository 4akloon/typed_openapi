import 'output_stray.dart';

/// What an output directory holds before a run.
final class ExistingOutput {
  /// Creates what a directory holds.
  const ExistingOutput(this.hashes, this.directories, [this.strays = const []]);

  /// An output directory that does not exist yet.
  static const none = ExistingOutput({}, {});

  /// The files, by path relative to the directory with `/` separators, with
  /// the SHA-256 of their content.
  final Map<String, String> hashes;

  /// The directories, the same way.
  final Set<String> directories;

  /// The files the generator did not write or that changed, sorted.
  final List<OutputStray> strays;
}
