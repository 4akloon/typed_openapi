import 'package:args/command_runner.dart';
import 'package:io/io.dart' show ExitCode;

import 'package:typed_openapi_core/typed_openapi_core.dart';

/// `typed_openapi lint`: checks one spec for the team that writes it.
///
/// It needs no config. Every fix it prints is a change at the source or a
/// recipe of the backend framework, never an override of the generator.
final class LintCommand extends Command<int> {
  /// Creates the command; reports go to [_out] (and the preset note to
  /// [_err] when the report is a document), and files are named as [_paths]
  /// does.
  LintCommand(this._out, this._err, [this._paths = const DisplayPaths()]) {
    argParser
      ..addOption(
        'preset',
        allowed: [for (final preset in Preset.values) preset.name],
        help: 'The backend framework, instead of detecting it.',
      )
      ..addOption(
        'format',
        allowed: [for (final format in ReportFormat.values) format.option],
        defaultsTo: ReportFormat.text.option,
        help: 'Report format.',
      )
      ..addOption(
        'fail-on',
        allowed: ['error', 'warning'],
        allowedHelp: {
          'error': 'Exit 1 when an error is found.',
          'warning': 'Exit 1 when an error or a warning is found.',
        },
        help: 'The level that fails the run. By default lint only reports.',
      );
  }

  /// Exit code when the spec could not be read, or a finding reached the
  /// level of `--fail-on`.
  static const exitFailed = 1;

  final StringSink _out;
  final StringSink _err;
  final DisplayPaths _paths;

  @override
  String get name => 'lint';

  @override
  String get description =>
      'Check one spec and say how to fix it at the source; needs no config.';

  @override
  String get invocation => '${runner!.executableName} lint [options] <spec>';

  @override
  Future<int> run() async {
    final results = argResults!;
    if (results.rest.length != 1) {
      usageException('Give the path of one spec file.');
    }
    final input = results.rest.single;
    final named = results.option('preset');
    final result = SpecLinter(_paths).lint(
      input,
      preset: named == null ? null : Preset.values.byName(named),
    );
    final format = ReportFormat.byOption(results.option('format')!);
    final note = _note(result);
    (format == .text ? _out : _err).writeln(note);
    // Code scanning needs a file for every result.
    final reporter = format == .sarif
        ? SarifReporter(defaultFile: _paths.of(input))
        : format.reporter;
    _out.writeln(reporter.format(result.diagnostics));
    return _exitCode(result, results.option('fail-on'));
  }

  static String _note(LintResult result) {
    final detection = result.detection;
    final preset = detection.preset.name;
    if (result.isChosen) return 'Preset: $preset (set with --preset).';
    if (detection.isFramework) {
      return 'Preset: $preset (detected: ${detection.reason}).';
    }
    return 'Preset: $preset (${detection.reason}; name the framework with '
        '--preset to get its recipes).';
  }

  static int _exitCode(LintResult result, String? failOn) {
    if (!result.isRead) return exitFailed;
    if (failOn == null) return ExitCode.success.code;
    final level = Severity.values.byName(failOn);
    final fails = result.diagnostics.all.any(
      (d) => d.severity.index <= level.index,
    );
    return fails ? exitFailed : ExitCode.success.code;
  }
}
