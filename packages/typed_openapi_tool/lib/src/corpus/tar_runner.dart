import 'corpus_exception.dart';
import 'timed_process.dart';

/// Runs the system `tar` with a time limit, so a hung or hostile archive
/// fails the run instead of stalling it.
final class TarRunner {
  /// Creates the runner; a `tar` that outlives [timeout] is killed.
  const TarRunner({
    this.timeout = const Duration(minutes: 2),
    this.executable = 'tar',
  });

  /// How long one `tar` may run.
  final Duration timeout;

  /// The program that is run; `tar`, another one in a test.
  final String executable;

  /// The output of `tar` with [arguments]; a failure or a timeout is a
  /// [CorpusException].
  Future<String> run(List<String> arguments) async {
    final result = await TimedProcess(
      timeout: timeout,
    ).run(executable, arguments);
    if (result.exitCode != 0) {
      throw CorpusException(
        '$executable ${arguments.first} failed: ${TimedProcess.excerpt(result.stderr)}',
      );
    }
    return '${result.stdout}';
  }
}
