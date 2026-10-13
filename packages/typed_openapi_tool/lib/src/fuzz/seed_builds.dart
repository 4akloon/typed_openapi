import 'fuzz_build.dart';

/// Runs the two builds of one seed and names the build when the generator
/// crashes.
final class SeedBuilds {
  /// Creates the runner that writes to [log].
  const SeedBuilds(this.log);

  /// Where a crash is named; the crash itself is not caught.
  final StringSink log;

  /// The output of [build] run twice for the seed [seed].
  (FuzzOutput, FuzzOutput) twice(int seed, FuzzOutput Function() build) =>
      (_once(seed, 'first', build), _once(seed, 'second', build));

  FuzzOutput _once(int seed, String which, FuzzOutput Function() build) {
    FuzzOutput? output;
    try {
      output = build();
    } finally {
      if (output == null) {
        log.writeln('The generator crashed on the $which build of seed $seed.');
      }
    }
    return output;
  }
}
