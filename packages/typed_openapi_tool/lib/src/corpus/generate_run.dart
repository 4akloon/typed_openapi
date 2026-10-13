import 'package:typed_openapi/typed_openapi.dart';

import 'corpus_exception.dart';

/// What one `typed_openapi generate` of a corpus package did.
typedef GenerateResult = ({Map<String, int> changed, String report});

/// Runs `typed_openapi generate` and `check` in-process on the config of a
/// corpus package.
final class GenerateRun {
  /// Creates the run of the config [config].
  const GenerateRun(this.config);

  /// The generator config.
  final String config;

  static final _generated = RegExp(
    r'^Generated (\S+) in .*: \d+ files?, (\d+) written, (\d+) deleted\.',
  );

  /// Generates every client; [GenerateResult.changed] counts the files each
  /// generated client wrote or deleted. A client the report does not name
  /// was not generated; why is in [GenerateResult.report].
  Future<GenerateResult> generate() async {
    final out = StringBuffer();
    await TypedOpenApiCli(out: out, err: out).run(['generate', '-c', config]);
    final changed = <String, int>{};
    for (final line in out.toString().split('\n')) {
      if (_generated.firstMatch(line) case final m?) {
        if ((m[1], m[2], m[3]) case (final name?, final w?, final d?)) {
          changed[name] = int.parse(w) + int.parse(d);
        }
      }
    }
    return (changed: changed, report: '$out');
  }

  /// What checking each client of the config found: its diagnostics and
  /// its IR. A config that cannot be loaded, or that reports an error, is a
  /// [CorpusException]: the tool writes the config itself, so that is a
  /// defect of the tool and no client can be judged.
  List<ClientCheck> check() {
    final bag = DiagnosticBag();
    final project = ConfigLoader(bag).load(config);
    if (project == null || bag.hasErrors) {
      throw CorpusException(
        '$config: the generator config is not valid:\n'
        '${const TextReporter().format(bag)}',
      );
    }
    return SpecChecker(bag).check(project);
  }
}
