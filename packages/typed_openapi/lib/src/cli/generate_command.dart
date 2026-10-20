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
import '../snapshot/api_lock.dart';
import 'api_lock_run.dart';
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
/// each, never the others; `--break-lock` only takes over a lock). The API
/// snapshot of each client written goes into `typed_openapi.lock` next to
/// the config, with a line that counts its changes per category; `--locked`
/// checks the lock instead and skips a client whose API differs (M12).
/// Types and methods keep the names the lock has for them unless
/// `--fresh-names` is given. The
/// report and the lines per client go to stdout, and the exit code is the
/// one `check` gives.
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
      )
      ..addFlag(
        'locked',
        negatable: false,
        help:
            'Check each client against its API snapshot in '
            'typed_openapi.lock instead of updating it; a client whose API '
            'differs is not written (for CI).',
      )
      ..addFlag(
        'fresh-names',
        negatable: false,
        help:
            'Name types and methods from the spec alone, not as '
            'typed_openapi.lock keeps them; may rename some.',
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
    final diagnostics = DiagnosticBag();
    final configPath = argResults!.option('config')!;
    final config = ConfigLoader(diagnostics, _paths).load(configPath);
    final lines = config == null
        ? const <String>[]
        : _generate(config, configPath, diagnostics);
    _out.writeln(const TextReporter().format(diagnostics));
    lines.forEach(_out.writeln);
    if (config == null) return ExitCode.config.code;
    return diagnostics.hasErrors
        ? CheckCommand.exitHasErrors
        : ExitCode.success.code;
  }

  /// Checks and writes the clients of [config] and updates (or, with
  /// `--locked`, checks) the API lock; returns a line per client.
  List<String> _generate(
    ProjectConfig config,
    String configPath,
    DiagnosticBag diagnostics,
  ) {
    final results = argResults!;
    final only = results.rest.toSet();
    final unknown = only.difference(config.declaredClients);
    if (unknown.isNotEmpty) {
      usageException(
        'Unknown client: ${(unknown.toList()..sort()).join(', ')}.',
      );
    }
    final checker = results.flag('fresh-names')
        ? SpecChecker.freshNames(diagnostics, _paths)
        : SpecChecker(diagnostics, _paths);
    final checks = checker.check(config, only: only);
    final lock = ApiLockRun.open(
      diagnostics,
      _paths,
      configPath,
      isLocked: results.flag('locked'),
    );
    if (lock == null) {
      return ['Skipped every client: ${ApiLock.fileName} cannot be used.'];
    }
    final writer = ClientWriter(
      OutputWriter(diagnostics, _paths),
      _paths,
      lock,
      protected: _protected(configPath, config, checks, lock.path),
      overlapping: _overlapping(config.clients),
      force: results.flag('force'),
      breakLock: results.flag('break-lock'),
    );
    final lines = checks.map(writer.write).toList();
    lock.finish(config.declaredClients);
    return lines;
  }

  /// Every file any client of [config] reads, also one that is not run,
  /// and the API lock at [lockPath], by absolute path: an output directory
  /// must not hold one, or the run would delete it.
  List<String> _protected(
    String configPath,
    ProjectConfig config,
    List<ClientCheck> checks,
    String lockPath,
  ) => {
    _paths.absolute(configPath),
    lockPath,
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
