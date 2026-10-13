import 'dart:io';

import 'timed_process.dart';

/// The checks of a package of generated code: `dart analyze --fatal-infos`
/// and `dart format --set-exit-if-changed` on its `lib` (generated code
/// carries `// dart format off`, so the formatter of any SDK keeps it).
///
/// A check that does not finish in time is a `CorpusException`; the output a
/// failure quotes is cut to [TimedProcess.maxQuoted] characters.
final class PackageGate {
  /// Creates the gate of the package in [directory].
  const PackageGate(this.directory, {this.fetchesPackages = true});

  /// The directory of the package.
  final String directory;

  /// Whether `pub get` may go online when the offline one fails.
  final bool fetchesPackages;

  /// The failures of the checks, one line each; empty when all pass.
  Future<List<String>> run() async {
    final get = await _pubGet();
    if (get.exitCode != 0) {
      return [
        '$directory: dart pub get failed:\n'
            '${TimedProcess.excerpt('${get.stderr}\n${get.stdout}')}',
      ];
    }
    final analyze = await _dart(['analyze', '--fatal-infos']);
    final format = await _dart([
      'format',
      '--output=none',
      '--set-exit-if-changed',
      'lib',
    ]);
    return [
      if (analyze.exitCode != 0)
        '$directory: dart analyze --fatal-infos failed:\n'
            '${TimedProcess.excerpt(analyze.stdout)}',
      if (format.exitCode != 0)
        '$directory: dart format would change files:\n'
            '${TimedProcess.excerpt(format.stdout)}',
    ];
  }

  Future<ProcessResult> _pubGet() async {
    final offline = await _dart(['pub', 'get', '--offline']);
    if (offline.exitCode == 0 || !fetchesPackages) return offline;
    return _dart(['pub', 'get']);
  }

  Future<ProcessResult> _dart(List<String> arguments) =>
      const TimedProcess().run(
        Platform.resolvedExecutable,
        arguments,
        workingDirectory: directory,
      );
}
