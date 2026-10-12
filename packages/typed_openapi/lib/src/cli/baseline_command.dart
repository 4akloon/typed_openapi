import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart' show ExitCode;

import '../baseline/baseline.dart';
import '../baseline/baseline_loader.dart';
import '../check/spec_checker.dart';
import '../config/config_loader.dart';
import '../config/project_config.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/display_paths.dart';
import '../diagnostics/reporters.dart';

/// `typed_openapi baseline`: writes and updates the clients' baseline files.
final class BaselineCommand extends Command<int> {
  /// Creates the command; reports are written to [out] and name files as
  /// [paths] does.
  BaselineCommand(StringSink out, [DisplayPaths paths = const DisplayPaths()]) {
    addSubcommand(BaselineCreateCommand(out, paths));
    addSubcommand(BaselinePruneCommand(out, paths));
  }

  @override
  String get name => 'baseline';

  @override
  String get description =>
      'Accept the current diagnostics, or remove entries that no longer '
      'match.';
}

/// What `baseline create` and `baseline prune` share: the config, the
/// clients with a baseline, the report and the exit code.
abstract base class _BaselineSubcommand extends Command<int> {
  _BaselineSubcommand(this._out, this._paths) {
    argParser.addOption(
      'config',
      abbr: 'c',
      defaultsTo: 'typed_openapi.yaml',
      help: 'Path to the config file.',
    );
  }

  final StringSink _out;
  final DisplayPaths _paths;

  @override
  String get invocation =>
      '${runner!.executableName} baseline $name [options] [client...]';

  /// Updates the baseline file of each result's client; reports problems
  /// to [diagnostics] and returns one line per written file.
  List<String> update(List<ClientCheck> results, DiagnosticBag diagnostics);

  @override
  Future<int> run() async {
    final diagnostics = DiagnosticBag();
    final config = ConfigLoader(
      diagnostics,
      _paths,
    ).load(argResults!.option('config')!);
    if (config == null) {
      _out.writeln(const TextReporter().format(diagnostics));
      return ExitCode.config.code;
    }
    final clients = _clients(config);
    final results = SpecChecker(
      diagnostics,
      _paths,
    ).checkClients(config, only: clients);
    final lines = update(results, diagnostics);
    _out.writeln(const TextReporter().format(diagnostics));
    lines.forEach(_out.writeln);
    return diagnostics.hasErrors ? 1 : ExitCode.success.code;
  }

  /// The names of the clients to update: those named on the command line,
  /// or every client with a baseline.
  Set<String> _clients(ProjectConfig config) {
    final named = argResults!.rest.toSet();
    final unknown = named.difference(config.declaredClients);
    if (unknown.isNotEmpty) {
      usageException(
        'Unknown client: ${(unknown.toList()..sort()).join(', ')}.',
      );
    }
    final withBaseline = {
      for (final client in config.clients)
        if (client.baseline != null) client.name,
    };
    final without = named.where((n) => !withBaseline.contains(n)).toList()
      ..sort();
    if (without.isNotEmpty) {
      usageException(
        'No "baseline" in the config for: ${without.join(', ')}.',
      );
    }
    if (withBaseline.isEmpty) {
      usageException('No client has a "baseline" in the config.');
    }
    return named.isEmpty ? withBaseline : named;
  }

  /// Writes [baseline] to [path]; returns whether it was written.
  bool write(Baseline baseline, String path, DiagnosticBag diagnostics) {
    try {
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(baseline.toYaml());
      return true;
    } on FileSystemException catch (e) {
      diagnostics.report(
        .baselineNotWritten,
        'Cannot write ${baseline.file}: ${e.message}.',
        file: baseline.file,
      );
      return false;
    }
  }
}

/// `typed_openapi baseline create`: accepts every current diagnostic.
final class BaselineCreateCommand extends _BaselineSubcommand {
  /// Creates the command; reports are written to [out].
  BaselineCreateCommand(super._out, super._paths);

  @override
  String get name => 'create';

  @override
  String get description =>
      'Write each client\'s baseline file from its current diagnostics.';

  @override
  List<String> update(List<ClientCheck> results, DiagnosticBag diagnostics) {
    final lines = <String>[];
    for (final result in results) {
      final path = result.client.baseline!;
      final baseline = Baseline.of(
        _paths.of(path),
        result.diagnostics,
        result.fingerprints(path, _paths),
      );
      // A baseline never accepts fixed codes, so they stay in the report.
      final accepted = baseline.match(
        result.diagnostics,
        result.fingerprints(path, _paths),
      );
      accepted.shown.forEach(diagnostics.add);
      if (!write(baseline, path, diagnostics)) continue;
      final count = accepted.baselined.length;
      lines.add(
        'Wrote ${baseline.file}: ${baseline.entries.length} entries '
        'accept $count diagnostics.',
      );
    }
    return lines;
  }
}

/// `typed_openapi baseline prune`: removes entries that no longer match.
final class BaselinePruneCommand extends _BaselineSubcommand {
  /// Creates the command; reports are written to [out].
  BaselinePruneCommand(super._out, super._paths);

  @override
  String get name => 'prune';

  @override
  String get description =>
      'Remove the entries of each client\'s baseline file that no longer '
      'match a diagnostic.';

  @override
  List<String> update(List<ClientCheck> results, DiagnosticBag diagnostics) {
    final lines = <String>[];
    for (final result in results) {
      final path = result.client.baseline!;
      final baseline = BaselineLoader(
        diagnostics,
      ).load(path, displayPath: _paths.of(path));
      if (baseline == null) continue;
      final pruned = baseline.pruned(
        baseline.match(result.diagnostics, result.fingerprints(path, _paths)),
      );
      if (!write(pruned, path, diagnostics)) continue;
      final removed = baseline.entries.length - pruned.entries.length;
      lines.add(
        'Pruned ${baseline.file}: removed $removed entries, '
        '${pruned.entries.length} left.',
      );
    }
    return lines;
  }
}
