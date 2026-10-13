import 'package:typed_openapi/typed_openapi.dart';

/// What one `typed_openapi generate` of a corpus package did.
typedef GenerateResult = ({
  Map<String, int> changed,
  Set<String> skipped,
  String report,
});

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
  static final _skipped = RegExp(r'^Skipped (\S+):');

  /// Generates every client; [GenerateResult.changed] counts the files each
  /// generated client wrote or deleted, and [GenerateResult.skipped] names
  /// the clients that were not generated.
  Future<GenerateResult> generate() async {
    final out = StringBuffer();
    await TypedOpenApiCli(out: out, err: out).run(['generate', '-c', config]);
    final changed = <String, int>{};
    final skipped = <String>{};
    for (final line in out.toString().split('\n')) {
      if (_generated.firstMatch(line) case final m?) {
        if ((m[1], m[2], m[3]) case (final name?, final w?, final d?)) {
          changed[name] = int.parse(w) + int.parse(d);
        }
      } else if (_skipped.firstMatch(line)?[1] case final name?) {
        skipped.add(name);
      }
    }
    return (changed: changed, skipped: skipped, report: '$out');
  }

  /// The diagnostics of each client of the config, by client name.
  List<ClientCheck> check() {
    final bag = DiagnosticBag();
    final project = ConfigLoader(bag).load(config);
    if (project == null) return const [];
    return SpecChecker(bag).check(project);
  }
}
