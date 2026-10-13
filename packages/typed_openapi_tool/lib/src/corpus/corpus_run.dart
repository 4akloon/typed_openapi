import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:typed_openapi/typed_openapi.dart';

import 'client_lock.dart';
import 'corpus_lock.dart';
import 'corpus_package.dart';
import 'corpus_spec.dart';
import 'expectation.dart';
import 'generate_run.dart';
import 'package_gate.dart';
import 'tree_hash.dart';

/// The lock a corpus run computed and the failures of its gates.
typedef CorpusResult = ({CorpusLock lock, List<String> failures});

/// One run of the corpus: for each `union` mode, generates every spec into a
/// fresh package, checks the expectation of each, generates again (which
/// must write nothing), and runs the [PackageGate] on the package.
final class CorpusRun {
  /// Creates the run that works in [work] with the runtime in [runtime],
  /// both absolute.
  const CorpusRun({
    required this.work,
    required this.runtime,
    this.modes = const ['raw', 'structural'],
  });

  /// The directory of the packages, one per mode.
  final String work;

  /// The directory of `typed_openapi_runtime`.
  final String runtime;

  /// The `union` modes to generate.
  final List<String> modes;

  /// The name of the manifest `generate` writes, which is not output code.
  static const String manifest = '.typed_openapi.json';

  /// Runs [specs], whose spec files are [inputs] (by name, absolute).
  Future<CorpusResult> run(
    List<CorpusSpec> specs,
    Map<String, String> inputs,
  ) async {
    final clients = <String, ClientLock>{};
    final failures = <String>[];
    for (final mode in modes) {
      final package = CorpusPackage(p.join(work, mode), mode);
      final lib = Directory(p.join(package.directory, 'lib'));
      if (lib.existsSync()) lib.deleteSync(recursive: true);
      package.write(inputs, runtime);
      final generate = GenerateRun(package.config);
      final first = await generate.generate();
      final checks = {for (final c in generate.check()) c.client.name: c};
      final second = await generate.generate();
      for (final spec in specs) {
        final key = '$mode/${spec.name}';
        final skipped = first.skipped.contains(spec.name);
        failures.addAll(_unexpected(key, spec, skipped, checks[spec.name]));
        final again = second.changed[spec.name] ?? 0;
        if (again > 0) failures.add('$key: a second generate wrote $again.');
        clients[key] = ClientLock(
          files: skipped ? const {} : _files(package.outputOf(spec.name)),
          diagnostics: _counts(checks[spec.name]),
        );
      }
      failures.addAll(await PackageGate(package.directory).run());
    }
    return (lock: CorpusLock(clients), failures: failures);
  }

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
        '$key: expected to generate, but it was skipped for $errors.',
      ],
      CheckErrors(:final codes) when !skipped => [
        '$key: expected the errors $codes, but it was generated.',
      ],
      CheckErrors(:final codes) when codes.join() != errors.join() => [
        '$key: expected the errors $codes, but got $errors.',
      ],
      _ => const [],
    };
  }

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
