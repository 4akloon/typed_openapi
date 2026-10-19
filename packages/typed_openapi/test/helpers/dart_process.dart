import 'dart:io';

/// Runs the `dart` executable of the test run.
final class DartProcess {
  const DartProcess._();

  /// Runs `dart` with [arguments] in [directory].
  ///
  /// The text on stdout and stderr has `\n` line ends on every platform
  /// (Dart's `print` writes `\r\n` on Windows), so a test compares it with
  /// a literal.
  static ProcessResult run(List<String> arguments, String directory) {
    final result = Process.runSync(
      Platform.resolvedExecutable,
      arguments,
      workingDirectory: directory,
    );
    return ProcessResult(
      result.pid,
      result.exitCode,
      _unixLines(result.stdout),
      _unixLines(result.stderr),
    );
  }

  static Object? _unixLines(Object? output) =>
      output is String ? output.replaceAll('\r\n', '\n') : output;
}
