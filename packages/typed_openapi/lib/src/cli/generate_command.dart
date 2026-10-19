import 'package:args/command_runner.dart';
import 'package:io/io.dart' show ExitCode;

import '../check/spec_checker.dart';
import '../config/config_loader.dart';
import '../config/project_config.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/display_paths.dart';
import '../diagnostics/reporters.dart';
import '../generate/output_writer.dart';
import '../generate/real_paths.dart';
import 'check_command.dart';
import 'client_writer.dart';

/// `typed_openapi generate`: checks every client as `check` does and
/// writes each client without errors into its output directory: the
/// models, the API classes and the root client (M8, M9).
///
/// A client whose check reports an error, including an overrides file that
/// cannot be used, is skipped; so is one whose output directory the
/// generator may not replace (TOA830): a directory that holds a package, a
/// file the config makes any client read, or a file the generator did not
/// write or that changed since it did (`--force` replaces those and lists
/// each, never the others; `--break-lock` only takes over a lock). The report
/// and a line per client go to stdout, and the exit code is the one `check`
/// gives.
final class GenerateCommand extends Command<int> {
  /// Creates the command; reports go to [_out], and files are named as
  /// [_paths] does.
  GenerateCommand(this._out, [this._paths = const DisplayPaths()]) {
    argParser
      ..addOption(
        'config',
        abbr: 'c',
        defaultsTo: 'typed_openapi.yaml',
        help: 'Path to the config file.',
      )
      ..addFlag(
        'force',
        negatable: false,
        help:
            'Replace files in an output directory that typed_openapi did not '
            'write or that changed since it wrote them; each is listed.',
      )
      ..addFlag(
        'break-lock',
        negatable: false,
        help:
            'Take over the lock of an output when it cannot be told whether '
            'the run that holds it is still going. Replaces no file.',
      );
  }

  final StringSink _out;
  final DisplayPaths _paths;

  @override
  String get name => 'generate';

  @override
  String get description =>
      'Check specs and generate the clients without errors.';

  @override
  String get invocation =>
      '${runner!.executableName} generate [options] [client...]';

  @override
  Future<int> run() async {
    final results = argResults!;
    final diagnostics = DiagnosticBag();
    final configPath = results.option('config')!;
    final config = ConfigLoader(diagnostics, _paths).load(configPath);
    final lines = <String>[];
    if (config != null) {
      final only = results.rest.toSet();
      final unknown = only.difference(config.declaredClients);
      if (unknown.isNotEmpty) {
        usageException(
          'Unknown client: ${(unknown.toList()..sort()).join(', ')}.',
        );
      }
      final checks = SpecChecker(diagnostics, _paths).check(config, only: only);
      final writer = ClientWriter(
        OutputWriter(diagnostics, _paths),
        _paths,
        protected: _protected(configPath, config, checks),
        overlapping: _overlapping(config.clients),
        force: results.flag('force'),
        breakLock: results.flag('break-lock'),
      );
      lines.addAll(checks.map(writer.write));
    }
    _out.writeln(const TextReporter().format(diagnostics));
    lines.forEach(_out.writeln);
    if (config == null) return ExitCode.config.code;
    return diagnostics.hasErrors
        ? CheckCommand.exitHasErrors
        : ExitCode.success.code;
  }

  /// Every file any client of [config] reads, also one that is not run, by
  /// absolute path: an output directory must not hold one, or the run would
  /// delete it.
  List<String> _protected(
    String configPath,
    ProjectConfig config,
    List<ClientCheck> checks,
  ) => {
    _paths.absolute(configPath),
    for (final client in config.clients) ...[
      client.input,
      ?client.overrides,
      ?client.baseline,
    ],
    for (final check in checks) ...check.sources,
  }.toList()..sort();

  /// The names of the clients whose output directory is, or is inside, that
  /// of another client, also through symbolic links or a different case.
  static Set<String> _overlapping(List<ClientConfig> clients) => {
    for (var i = 0; i < clients.length; i++)
      for (var j = i + 1; j < clients.length; j++)
        if (RealPaths.overlap(clients[i].output, clients[j].output)) ...[
          clients[i].name,
          clients[j].name,
        ],
  };
}
