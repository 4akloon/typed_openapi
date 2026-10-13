import 'dart:io';

import 'package:args/command_runner.dart';

import 'fetch_command.dart';
import 'http_download.dart';
import 'spec_cache.dart';

/// The `corpus` command line of the repository (M11): `fetch`.
final class CorpusCli {
  /// Creates the command line; lines go to [out], failures and usage errors
  /// to [err]; [download] fetches a spec (the network by default).
  CorpusCli({StringSink? out, StringSink? err, Download? download})
    : _err = err ?? stderr,
      _runner = CommandRunner<int>(
        'corpus',
        'The public-spec corpus of typed_openapi.',
      ) {
    _runner.addCommand(
      FetchCommand(out ?? stdout, _err, download ?? const HttpDownload().call),
    );
  }

  final CommandRunner<int> _runner;
  final StringSink _err;

  /// Runs the command line with [args]; returns the exit code.
  Future<int> run(List<String> args) async {
    try {
      return await _runner.run(args) ?? 0;
    } on UsageException catch (e) {
      _err
        ..writeln(e.message)
        ..writeln()
        ..writeln(e.usage);
      return 64;
    }
  }
}
