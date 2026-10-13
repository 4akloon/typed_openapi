import 'fuzz_build.dart';
import 'leak_check.dart';

/// The checks of one seed's two builds (spec decision 5, checks 1 and 3):
/// the builds are equal, and no file or report leaks spec text.
final class SeedChecks {
  /// Creates the checks.
  const SeedChecks();

  /// The problems of the seed [seed], whose builds gave [first] and
  /// [second].
  List<String> of(int seed, FuzzOutput first, FuzzOutput second) {
    const leaks = LeakCheck();
    return [
      for (final MapEntry(key: client, value: files)
          in first.files.entries) ...[
        if (!_same(files, second.files[client]))
          'seed $seed: $client is not deterministic.',
        ...leaks.code('seed $seed $client', files),
      ],
      for (final client in second.files.keys)
        if (!first.files.containsKey(client))
          'seed $seed: $client is not deterministic.',
      for (final problem in leaks.report(first.report)) 'seed $seed: $problem',
    ];
  }

  static bool _same(Map<String, String> a, Map<String, String>? b) =>
      b != null &&
      a.length == b.length &&
      a.entries.every((e) => b[e.key] == e.value);
}
