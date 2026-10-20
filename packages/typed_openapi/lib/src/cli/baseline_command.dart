import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart' show ExitCode;
import 'package:path/path.dart' as p;

import 'package:typed_openapi_core/typed_openapi_core.dart';

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
    final Set<String> clients;
    try {
      clients = _clients(config);
    } on UsageException {
      // Say what is wrong with the config before the usage error.
      if (diagnostics.all.isNotEmpty) {
        _out.writeln(const TextReporter().format(diagnostics));
      }
      rethrow;
    }
    final shared = _sharingBaseline(config);
    final results = [
      for (final result in SpecChecker(
        diagnostics,
        _paths,
      ).checkClients(config, only: clients))
        // The config reports clients that share a baseline file; writing it
        // once per client would let the last one win.
        if (!shared.contains(result.client.name)) result,
    ];
    final lines = update(results, diagnostics);
    _out.writeln(const TextReporter().format(diagnostics));
    lines.forEach(_out.writeln);
    return diagnostics.hasErrors ? 1 : ExitCode.success.code;
  }

  /// The names of the clients whose baseline file another client names too.
  Set<String> _sharingBaseline(ProjectConfig config) {
    final owners = <String, List<String>>{};
    for (final client in config.clients) {
      final baseline = client.baseline;
      if (baseline == null) continue;
      (owners[p.canonicalize(baseline)] ??= []).add(client.name);
    }
    return {
      for (final names in owners.values)
        if (names.length > 1) ...names,
    };
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

  /// Writes [baseline] to [path] through a temporary file in the same
  /// directory, so an interrupted write never leaves a broken baseline;
  /// returns whether it was written.
  bool write(Baseline baseline, String path, DiagnosticBag diagnostics) {
    final target = File(path);
    final temp = File('$path.tmp');
    try {
      target.parent.createSync(recursive: true);
      temp.writeAsStringSync(baseline.toYaml());
      temp.renameSync(path);
      return true;
    } on FileSystemException catch (e) {
      try {
        if (temp.existsSync()) temp.deleteSync();
      } on FileSystemException {
        // Nothing more can be done about a leftover temporary file.
      }
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
      if (result.readErrors.isNotEmpty) {
        // The run found too little to write a baseline from.
        result.readErrors.forEach(diagnostics.add);
        continue;
      }
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
      if (result.readErrors.isNotEmpty) {
        // Every entry would look stale; keep the file as it is.
        result.readErrors.forEach(diagnostics.add);
        continue;
      }
      final problems = DiagnosticBag();
      final baseline = BaselineLoader(
        problems,
      ).load(path, displayPath: _paths.of(path));
      problems.all.forEach(diagnostics.add);
      // A rejected entry would be lost by the rewrite.
      if (baseline == null || problems.hasErrors) continue;
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
