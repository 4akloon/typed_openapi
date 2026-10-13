import 'dart:io';

/// The checks of a package of generated code: `dart analyze --fatal-infos`
/// and `dart format --set-exit-if-changed` on its `lib` (generated code
/// carries `// dart format off`, so the formatter of any SDK keeps it).
final class PackageGate {
  /// Creates the gate of the package in [directory].
  const PackageGate(this.directory);

  /// The directory of the package.
  final String directory;

  /// The failures of the checks, one line each; empty when all pass.
  Future<List<String>> run() async {
    final get = await _dart(['pub', 'get', '--offline']);
    if (get.exitCode != 0 && (await _dart(['pub', 'get'])).exitCode != 0) {
      return ['$directory: dart pub get failed: ${get.stderr}'];
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
        '$directory: dart analyze --fatal-infos failed:\n${analyze.stdout}',
      if (format.exitCode != 0)
        '$directory: dart format would change files:\n${format.stdout}',
    ];
  }

  Future<ProcessResult> _dart(List<String> arguments) => Process.run(
    Platform.resolvedExecutable,
    arguments,
    workingDirectory: directory,
  );
}
