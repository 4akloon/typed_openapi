import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart' show ExitCode;

import '../diagnostics/display_paths.dart';
import 'check_command.dart';

/// The `typed_openapi` command line.
final class TypedOpenApiCli {
  /// Creates the command line.
  ///
  /// Reports go to [out] and usage errors to [err]; both default to the
  /// process streams. Paths on the command line are relative to
  /// [workingDirectory], and reports name files relative to it; it defaults
  /// to the current directory.
  TypedOpenApiCli({StringSink? out, StringSink? err, String? workingDirectory})
    : _err = err ?? stderr,
      _runner =
          CommandRunner<int>(
            'typed_openapi',
            'OpenAPI 3.x to Dart client generator.',
          )..addCommand(
            CheckCommand(out ?? stdout, DisplayPaths(workingDirectory)),
          );

  final CommandRunner<int> _runner;
  final StringSink _err;

  /// Runs the command line with [args]; returns the exit code.
  Future<int> run(List<String> args) async {
    try {
      return await _runner.run(args) ?? ExitCode.success.code;
    } on UsageException catch (e) {
      _err
        ..writeln(e.message)
        ..writeln()
        ..writeln(e.usage);
      return ExitCode.usage.code;
    }
  }
}
