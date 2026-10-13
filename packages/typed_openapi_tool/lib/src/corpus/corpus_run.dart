import 'package:path/path.dart' as p;
import 'package:typed_openapi/typed_openapi.dart';

import '../roundtrip/example_reader.dart';
import '../roundtrip/round_trip.dart';
import 'client_lock.dart';
import 'corpus_lock.dart';
import 'corpus_package.dart';
import 'corpus_spec.dart';
import 'expectation.dart';
import 'generate_run.dart';
import 'package_gate.dart';
import 'tree_hash.dart';

/// The lock a corpus run computed, the failures of its gates, and the
/// values whose round trip failed and the examples that are defects of their
/// spec (both counted in the lock, see [ClientLock]).
typedef CorpusResult = ({
  CorpusLock lock,
  List<String> failures,
  List<String> roundTrips,
  List<String> defects,
});

/// One run of the corpus: for each `union` mode, generates every spec into a
/// fresh package, checks the expectation of each, generates again (which
/// must write nothing), runs the [PackageGate] on the package and the
/// [RoundTrip] of every generated client.
final class CorpusRun {
  /// Creates the run that works in [work] with the runtime in [runtime],
  /// both absolute.
  const CorpusRun({
    required this.work,
    required this.runtime,
    this.modes = allModes,
    this.fetchesPackages = true,
    this.roundTripTimeout = const Duration(minutes: 10),
  });

  /// The directory of the packages, one per mode.
  final String work;

  /// The directory of `typed_openapi_runtime`.
  final String runtime;

  /// The `union` modes to generate.
  final List<String> modes;

  /// Whether the gate may download packages when they are not cached.
  final bool fetchesPackages;

  /// How long the round-trip program of one client may run.
  final Duration roundTripTimeout;

  /// Every `union` mode the corpus knows.
  static const List<String> allModes = ['raw', 'structural'];

  /// The name of the manifest `generate` writes, which is not output code.
  static const String manifest = '.typed_openapi.json';

  /// Runs [specs], whose spec files are [inputs] (by name, absolute).
  Future<CorpusResult> run(
    List<CorpusSpec> specs,
    Map<String, String> inputs,
  ) async {
    final clients = <String, ClientLock>{};
    final failures = <String>[];
    final roundTrips = <String>[];
    final defects = <String>[];
    _cleanUnused();
    for (final mode in modes) {
      final result = await _mode(mode, specs, inputs);
      clients.addAll(result.lock.clients);
      failures.addAll(result.failures);
      roundTrips.addAll(result.roundTrips);
      defects.addAll(result.defects);
    }
    return (
      lock: CorpusLock(clients),
      failures: failures,
      roundTrips: roundTrips,
      defects: defects,
    );
  }

  /// Removes what an earlier run generated for the modes this run skips, so
  /// a reused [work] directory holds nothing stale.
  void _cleanUnused() {
    for (final mode in allModes.where((m) => !modes.contains(m))) {
      CorpusPackage(p.join(work, mode), mode).clean();
    }
  }

  Future<CorpusResult> _mode(
    String mode,
    List<CorpusSpec> specs,
    Map<String, String> inputs,
  ) async {
    final package = CorpusPackage(p.join(work, mode), mode)
      ..clean()
      ..write(inputs, runtime);
    final generate = GenerateRun(package.config);
    final first = await generate.generate();
    final checks = {for (final c in generate.check()) c.client.name: c};
    final second = await generate.generate();
    final failures = await PackageGate(
      package.directory,
      fetchesPackages: fetchesPackages,
    ).run();
    final trips = await _roundTrips(package, checks, roundTripTimeout);
    final clients = <String, ClientLock>{};
    final roundTrips = <String>[];
    final defects = <String>[];
    for (final spec in specs) {
      final key = '$mode/${spec.name}';
      final check = checks[spec.name];
      final trip = trips[spec.name];
      failures
        ..addAll(_failuresOf(key, spec, check, first, second))
        ..addAll([for (final f in trip?.notRun ?? const []) '$mode/$f']);
      roundTrips.addAll([
        for (final f in trip?.failures ?? const []) '$mode/$f',
      ]);
      defects.addAll([for (final d in trip?.defects ?? const []) '$mode/$d']);
      clients[key] = _record(package, spec.name, check, first, trip);
    }
    return (
      lock: CorpusLock(clients),
      failures: failures,
      roundTrips: roundTrips,
      defects: defects,
    );
  }

  static ClientLock _record(
    CorpusPackage package,
    String name,
    ClientCheck? check,
    GenerateResult first,
    RoundTripResult? trip,
  ) {
    final generated = !_isSkipped(check) && first.changed.containsKey(name);
    return ClientLock(
      files: generated ? _files(package.outputOf(name)) : const {},
      diagnostics: _counts(check),
      values: trip == null ? null : _values(trip),
    );
  }

  static List<String> _failuresOf(
    String key,
    CorpusSpec spec,
    ClientCheck? check,
    GenerateResult first,
    GenerateResult second,
  ) {
    final skipped = _isSkipped(check);
    return [
      ..._unexpected(key, spec, skipped, check),
      if (!skipped) ..._notWritten(key, spec.name, first, second),
    ];
  }

  /// Whether `generate` leaves the client out: it was not checked, its spec
  /// could not be read, or its check reports an error.
  static bool _isSkipped(ClientCheck? check) =>
      check == null || check.ir == null || check.errors > 0;

  /// The failures of a client whose check passed: it must be generated by
  /// the first run and by the second, and the second must write nothing.
  static List<String> _notWritten(
    String key,
    String name,
    GenerateResult first,
    GenerateResult second,
  ) {
    final reasons = RegExp(
      '^Skipped ${RegExp.escape(name)}: .*',
      multiLine: true,
    ).firstMatch(first.report)?[0];
    if (!first.changed.containsKey(name)) {
      return ['$key: was not generated. ${reasons ?? 'See the report.'}'];
    }
    final again = second.changed[name];
    return [
      if (again == null) '$key: the second generate did not run it.',
      if (again != null && again > 0) '$key: a second generate wrote $again.',
    ];
  }

  /// The round trip of every generated client of [package].
  static Future<Map<String, RoundTripResult>> _roundTrips(
    CorpusPackage package,
    Map<String, ClientCheck> checks,
    Duration timeout,
  ) async {
    final examples = ExampleReader();
    final trip = RoundTrip(
      package.directory,
      package.name,
      timeout: timeout,
    );
    return {
      for (final MapEntry(key: name, value: check) in checks.entries)
        if (check.ir case final ir? when !_isSkipped(check))
          name: await trip.run(name, ir, examples),
    };
  }

  static Map<String, int> _values(RoundTripResult trip) => {
    'examples': trip.examples,
    'examples_skipped': trip.skippedExamples,
    'failures': trip.failures.length,
    'spec_defects': trip.defects.length,
    'synthetic': trip.synthetic,
    'synthetic_skipped': trip.skippedSynthetic,
  };

  static List<String> _unexpected(
    String key,
    CorpusSpec spec,
    bool skipped,
    ClientCheck? check,
  ) {
    final errors = {
      for (final d in check?.diagnostics ?? const <Diagnostic>[])
        if (d.severity == Severity.error) d.code.id,
    }.toList()..sort();
    return switch (spec.expectation) {
      Generates() when skipped => [
        '$key: expected to generate, but it was skipped'
            '${errors.isEmpty ? ' (no error code: it was not checked or its '
                      'spec could not be read)' : ' for $errors'}.',
      ],
      CheckErrors(:final codes) when !skipped => [
        '$key: expected the errors $codes, but it was generated.',
      ],
      CheckErrors(:final codes) when '${_sorted(codes)}' != '$errors' => [
        '$key: expected the errors $codes, but got $errors.',
      ],
      _ => const [],
    };
  }

  static List<String> _sorted(List<String> codes) => [...codes]..sort();

  static Map<String, String> _files(String output) =>
      const TreeHash().files(output)..remove(manifest);

  static Map<String, int> _counts(ClientCheck? check) {
    final counts = <String, int>{};
    for (final d in check?.diagnostics ?? const <Diagnostic>[]) {
      counts.update(d.code.id, (n) => n + 1, ifAbsent: () => 1);
    }
    return counts;
  }
}
