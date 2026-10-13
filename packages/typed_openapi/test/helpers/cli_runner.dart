import 'package:typed_openapi/src/cli/cli.dart';

/// Runs the command line in-process, with its output captured.
final class CliRunner {
  const CliRunner._();

  /// Runs [args] in [workingDirectory] (the process's when null); returns the
  /// exit code, what went to stdout and what went to stderr.
  static Future<(int, String, String)> run(
    List<String> args, {
    String? workingDirectory,
  }) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await TypedOpenApiCli(
      out: out,
      err: err,
      workingDirectory: workingDirectory,
    ).run(args);
    return (code, out.toString(), err.toString());
  }
}
