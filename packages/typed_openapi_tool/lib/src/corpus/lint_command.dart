import 'package:args/command_runner.dart';
import 'package:typed_openapi_core/typed_openapi_core.dart';

import 'corpus_exception.dart';
import 'corpus_lint_report.dart';
import 'fetch_command.dart';
import 'spec_cache.dart';
import 'spec_lint_row.dart';

/// `corpus lint`: runs `typed_openapi lint` on the specs of `corpus.yaml`,
/// prints the counts by framework and fails when the detected preset is not
/// the one the corpus names.
final class CorpusLintCommand extends Command<int> {
  /// Creates the command; lines go to [_out], failures to [_err].
  CorpusLintCommand(this._out, this._err, this._download) {
    FetchCommand.addCorpusOptions(argParser);
  }

  final StringSink _out;
  final StringSink _err;
  final Download _download;

  @override
  String get name => 'lint';

  @override
  String get description =>
      'Lint the specs of corpus.yaml and check the framework detection.';

  @override
  String get invocation => '${super.invocation} [names]';

  @override
  Future<int> run() async {
    final results = argResults!;
    FetchCommand.checkNames(results, usage);
    final cache = SpecCache(results.option('cache')!, _download);
    try {
      final rows = <SpecLintRow>[];
      for (final spec in FetchCommand.specsOf(results)) {
        final path = await cache.fetch(spec);
        rows.add(SpecLintRow(spec, const SpecLinter().lint(path)));
      }
      final report = CorpusLintReport(rows);
      _out.write(report.format());
      return report.misdetected.isEmpty ? 0 : 1;
    } on CorpusException catch (e) {
      _err.writeln(e.message);
      return 1;
    }
  }
}
