import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'corpus_exception.dart';

/// Runs an external process with a time limit, so a hung `dart analyze` or
/// round-trip program fails the run instead of stalling it.
final class TimedProcess {
  /// Creates the runner; a process that outlives [timeout] is killed.
  const TimedProcess({this.timeout = const Duration(minutes: 10)});

  /// How long a process may run.
  final Duration timeout;

  /// The most characters of a process's output a message quotes.
  static const int maxQuoted = 4000;

  /// Runs [executable] with [arguments] in [workingDirectory] and returns
  /// what it printed; a process that runs longer than [timeout] is killed
  /// and is a [CorpusException].
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
    final stdout = _text(process.stdout);
    final stderr = _text(process.stderr);
    final exitCode = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        throw CorpusException(
          '$executable ${arguments.join(' ')} did not finish within '
          '${timeout.inSeconds} s and was killed.',
        );
      },
    );
    return ProcessResult(process.pid, exitCode, await stdout, await stderr);
  }

  /// The first [maxQuoted] characters of [text], with a note of how much was
  /// left out.
  static String excerpt(Object? text) {
    final string = '$text'.trim();
    if (string.length <= maxQuoted) return string;
    return '${string.substring(0, maxQuoted)}\n'
        '... ${string.length - maxQuoted} more characters.';
  }

  static Future<String> _text(Stream<List<int>> bytes) =>
      bytes.transform(const Utf8Decoder(allowMalformed: true)).join();
}
