import 'package:args/command_runner.dart';
import 'package:io/io.dart' show ExitCode;

import '../check/spec_checker.dart';
import '../config/config_loader.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/display_paths.dart';
import '../diagnostics/reporters.dart';

/// `typed_openapi check`: analyzes specs without generating code.
final class CheckCommand extends Command<int> {
  /// Creates the command; reports are written to [_out] and name files as
  /// [_paths] does.
  CheckCommand(this._out, [this._paths = const DisplayPaths()]) {
    argParser
      ..addOption(
        'config',
        abbr: 'c',
        defaultsTo: 'typed_openapi.yaml',
        help: 'Path to the config file.',
      )
      ..addOption(
        'format',
        allowed: [for (final format in ReportFormat.values) format.option],
        defaultsTo: ReportFormat.text.option,
        help: 'Report format.',
      )
      ..addFlag(
        'show-baselined',
        negatable: false,
        help: 'Also list the diagnostics the baseline accepts, marked.',
      )
      ..addFlag(
        'strict-baseline',
        negatable: false,
        help:
            'Fail on baseline entries that no longer match, whatever level '
            'the config gives baseline-entry-stale: run `baseline prune` to '
            'remove them.',
      );
  }

  /// Exit code when the check found at least one error.
  static const exitHasErrors = 1;

  final StringSink _out;
  final DisplayPaths _paths;

  @override
  String get name => 'check';

  @override
  String get description =>
      'Check specs and report diagnostics without generating code.';

  @override
  String get invocation =>
      '${runner!.executableName} check [options] [client...]';

  @override
  Future<int> run() async {
    final results = argResults!;
    final diagnostics = DiagnosticBag();
    final config = ConfigLoader(
      diagnostics,
      _paths,
    ).load(results.option('config')!);
    if (config != null) {
      final only = results.rest.toSet();
      final unknown = only.difference(config.declaredClients);
      if (unknown.isNotEmpty) {
        usageException(
          'Unknown client: ${(unknown.toList()..sort()).join(', ')}.',
        );
      }
      SpecChecker(diagnostics, _paths).check(
        config,
        only: only,
        strictBaseline: results.flag('strict-baseline'),
      );
    }
    final format = ReportFormat.byOption(results.option('format')!);
    _out.writeln(
      format.reporter.format(
        diagnostics,
        showBaselined: results.flag('show-baselined'),
      ),
    );
    if (config == null) return ExitCode.config.code;
    return diagnostics.hasErrors ? exitHasErrors : ExitCode.success.code;
  }
}
