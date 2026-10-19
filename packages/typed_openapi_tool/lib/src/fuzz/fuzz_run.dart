import 'dart:io';

import 'package:path/path.dart' as p;

import '../corpus/corpus_package.dart';
import '../corpus/package_gate.dart';
import 'fuzz_build.dart';
import 'fuzz_spec.dart';
import 'leak_check.dart';
import 'literal_check.dart';
import 'seed_builds.dart';
import 'seed_checks.dart';
import 'spec_strings.dart';

/// What a fuzz run found.
typedef FuzzReport = ({
  int builds,
  int files,
  int sampled,
  List<String> failures,
});

/// The escaping fuzz (spec decision 5): builds the spec of each seed twice
/// in every generation config and `union` mode, and checks that
/// - the two builds give the same files (determinism);
/// - spec text stays in its sink, in the code and in the report
///   ([LeakCheck]);
/// - a sample of the outputs (every [sampleEvery]-th seed) passes
///   `dart analyze --fatal-infos` ([PackageGate]) and holds every spec
///   string as a literal of the same value ([LiteralCheck]).
///
/// A crash of the generator is not caught: it ends the run, and [log] names
/// the seed and the build. A run that builds no client fails.
final class FuzzRun {
  /// Creates the run that writes its sample package into [work] (absolute)
  /// with the runtime in [runtime].
  const FuzzRun({
    required this.work,
    required this.runtime,
    required this.log,
    this.sampleEvery = 12,
    this.fetchesPackages = true,
  });

  /// Whether the gate may download packages when they are not cached.
  final bool fetchesPackages;

  /// The directory of the sample package.
  final String work;

  /// The directory of `typed_openapi_client`.
  final String runtime;

  /// Where the run names the seed it is on when the generator crashes.
  final StringSink log;

  /// Every how many seeds an output goes into the sample.
  final int sampleEvery;

  /// Runs the seeds `from` to `from + count - 1`.
  Future<FuzzReport> run({required int from, required int count}) async {
    final sample = CorpusPackage(work, 'fuzz')
      ..clean()
      ..write(const {}, runtime);
    final temp = Directory.systemTemp.createTempSync('typed_openapi_fuzz_');
    final failures = <String>[];
    final strings = <String, List<String>>{};
    var builds = 0;
    var files = 0;
    try {
      for (var seed = from; seed < from + count; seed++) {
        final seen = _seed(seed, p.join(temp.path, '$seed'), sample);
        builds += seen.builds;
        files += seen.files;
        failures.addAll(seen.failures);
        if (seen.strings case final found?) strings['s$seed'] = found;
      }
    } finally {
      temp.deleteSync(recursive: true);
    }
    if (strings.isNotEmpty) {
      failures
        ..addAll(
          await PackageGate(work, fetchesPackages: fetchesPackages).run(),
        )
        ..addAll(await LiteralCheck(work).run(strings));
    }
    if (builds == 0) failures.add('The fuzz built no client.');
    return (
      builds: builds,
      files: files,
      sampled: strings.length,
      failures: failures,
    );
  }

  /// Builds the seed [seed] twice in [directory], checks the builds, and
  /// writes the sampled output into [sample].
  ({int builds, int files, List<String> failures, List<String>? strings}) _seed(
    int seed,
    String directory,
    CorpusPackage sample,
  ) {
    Directory(directory).createSync(recursive: true);
    final build = FuzzBuild(directory, const FuzzSpec().of(seed));
    final (first, second) = SeedBuilds(log).twice(seed, build.build);
    return (
      builds: first.files.length,
      files: first.files.values.fold(0, (n, f) => n + f.length),
      failures: const SeedChecks().of(seed, first, second),
      strings: seed % sampleEvery == 0
          ? _sample(seed, first, sample, sampleEvery)
          : null,
    );
  }

  /// Writes the output of one client of the seed into [sample] and returns
  /// its spec strings; null when the client has no IR.
  static List<String>? _sample(
    int seed,
    FuzzOutput output,
    CorpusPackage sample,
    int sampleEvery,
  ) {
    final client = sampledClient(seed, sampleEvery);
    final ir = output.irs[client];
    if (ir == null) return null;
    for (final MapEntry(key: path, value: text)
        in (output.files[client] ?? const {}).entries) {
      File(p.join(sample.outputOf('s$seed'), path))
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
    }
    return const SpecStrings().of(ir);
  }

  /// The client whose output the seed [seed] adds to the sample: successive
  /// samples cycle through the configs, then through the `union` modes, so
  /// every client is analyzed (seeds are multiples of [sampleEvery]).
  static String sampledClient(int seed, int sampleEvery) {
    final index = seed ~/ sampleEvery;
    final config = FuzzBuild.configs[index % FuzzBuild.configs.length].$1;
    final mode = FuzzBuild
        .modes[(index ~/ FuzzBuild.configs.length) % FuzzBuild.modes.length];
    return '${config}_$mode';
  }
}
