import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart' show ExitCode;

import '../check/spec_checker.dart';
import '../config/config_loader.dart';
import '../diagnostics/diagnostic_bag.dart';
import '../diagnostics/display_paths.dart';
import '../diagnostics/reporters.dart';
import '../diff/api_change.dart';
import '../diff/api_diff.dart';
import '../diff/json_diff_report.dart';
import '../diff/markdown_diff_report.dart';
import '../diff/text_diff_report.dart';
import '../snapshot/api_lock.dart';
import '../snapshot/api_snapshot.dart';
import 'api_lock_run.dart';
import 'check_command.dart';

/// `typed_openapi diff`: compares the API of each client in
/// `typed_openapi.lock` with the API the current spec and config give, or
/// two lock files with each other, and reports every change by category
/// (M12, decision 4). It writes nothing.
///
/// The report goes to stdout, the errors of the run to stderr. The exit
/// code is `0` unless `--fail-on` names a category that a change reaches,
/// or a spec or lock cannot be read; then it is `1`.
final class DiffCommand extends Command<int> {
  /// Creates the command; the report goes to [_out], errors to [_err], and
  /// files are named as [_paths] does.
  DiffCommand(this._out, this._err, [this._paths = const DisplayPaths()]) {
    argParser
      ..addOption(
        'config',
        abbr: 'c',
        defaultsTo: 'typed_openapi.yaml',
        help: 'Path to the config file.',
      )
      ..addOption(
        'format',
        allowed: ['text', 'json', 'markdown'],
        defaultsTo: 'text',
        help: 'Report format; markdown is for a pull request comment.',
      )
      ..addOption(
        'fail-on',
        allowed: ['breaking', 'switch-breaking', 'wire', 'any'],
        help:
            'Exit 1 when a change of this category or a more serious one '
            'is found (any: every change). By default the command only '
            'reports.',
      )
      ..addOption(
        'from',
        help:
            'The lock file to compare from (default: typed_openapi.lock '
            'next to the config).',
      )
      ..addOption(
        'to',
        help:
            'The lock file to compare to, instead of the current spec and '
            'config; needs --from.',
      );
  }

  final StringSink _out;
  final StringSink _err;
  final DisplayPaths _paths;

  @override
  String get name => 'diff';

  @override
  String get description =>
      'Report how the API of the clients changed since typed_openapi.lock.';

  @override
  String get invocation =>
      '${runner!.executableName} diff [options] [client...]';

  @override
  Future<int> run() async {
    final results = argResults!;
    final diagnostics = DiagnosticBag();
    final (sides, code) = results.option('to') == null
        ? _current(diagnostics)
        : (_files(diagnostics), null);
    _printErrors(diagnostics);
    if (code != null) return code;
    if (sides == null) return CheckCommand.exitHasErrors;
    final changes = {
      for (final MapEntry(key: client, value: (before, after)) in sides.entries)
        client: const ApiDiff().compare(before, after),
    };
    _out.write(switch (results.option('format')) {
      'json' => '${const JsonDiffReport().format(changes)}\n',
      'markdown' => const MarkdownDiffReport().format(changes),
      _ => const TextDiffReport().format(changes),
    });
    final failed =
        _fails(results.option('fail-on'), changes.values.expand((c) => c)) ||
        diagnostics.hasErrors;
    return failed ? CheckCommand.exitHasErrors : ExitCode.success.code;
  }

  /// The sides of each client: the lock (`--from`, or the one next to the
  /// config) and the current spec. The code is set when the config cannot
  /// be loaded.
  (Map<String, (ApiSnapshot, ApiSnapshot)>?, int?) _current(
    DiagnosticBag diagnostics,
  ) {
    final configPath = argResults!.option('config')!;
    final config = ConfigLoader(diagnostics, _paths).load(configPath);
    if (config == null) return (null, ExitCode.config.code);
    final only = argResults!.rest.toSet();
    final unknown = only.difference(config.declaredClients);
    if (unknown.isNotEmpty) {
      usageException(
        'Unknown client: ${(unknown.toList()..sort()).join(', ')}.',
      );
    }
    final from = argResults!.option('from');
    final locked = ApiLock(diagnostics, _paths).read(
      from == null
          ? ApiLock.pathFor(_paths.absolute(configPath))
          : _existing(from),
    );
    final checks = SpecChecker(diagnostics, _paths).check(config, only: only);
    if (locked == null) return (null, null);
    final sides = <String, (ApiSnapshot, ApiSnapshot)>{};
    for (final ClientCheck(:client, :ir) in checks) {
      if (ir == null) {
        _err.writeln(
          'Client ${client.name} has no API: its spec could not be read '
          '(see the errors above).',
        );
        continue;
      }
      sides[client.name] = (
        locked[client.name] ?? const ApiSnapshot({}),
        ApiLockRun.snapshotOf(client, ir),
      );
    }
    return (sides, null);
  }

  /// The sides of each client in the lock files `--from` and `--to`; null
  /// when one cannot be read.
  Map<String, (ApiSnapshot, ApiSnapshot)>? _files(DiagnosticBag diagnostics) {
    final from = argResults!.option('from');
    if (from == null) usageException('--to needs --from.');
    final lock = ApiLock(diagnostics, _paths);
    final before = lock.read(_existing(from));
    final after = lock.read(_existing(argResults!.option('to')!));
    if (before == null || after == null) return null;
    final names = {...before.keys, ...after.keys};
    final only = argResults!.rest.toSet();
    final unknown = only.difference(names);
    if (unknown.isNotEmpty) {
      usageException(
        'No client in either file: ${(unknown.toList()..sort()).join(', ')}.',
      );
    }
    return {
      for (final name in only.isEmpty ? names : only)
        name: (
          before[name] ?? const ApiSnapshot({}),
          after[name] ?? const ApiSnapshot({}),
        ),
    };
  }

  /// The absolute path of the file [path] names; a usage error when there
  /// is none.
  String _existing(String path) {
    final absolute = _paths.absolute(path);
    if (!File(absolute).existsSync()) usageException('No file at $path.');
    return absolute;
  }

  /// Whether a change in [changes] reaches the category [failOn].
  static bool _fails(String? failOn, Iterable<ApiChange> changes) {
    if (failOn == null) return false;
    final limit = ChangeCategory.parse(failOn);
    return changes.any((c) => limit == null || c.category.index <= limit.index);
  }

  /// Writes the errors of [diagnostics] to stderr, with the summary of
  /// every diagnostic: `check` lists the others.
  void _printErrors(DiagnosticBag diagnostics) {
    if (!diagnostics.hasErrors) return;
    final errors = DiagnosticBag();
    diagnostics.all.where((d) => d.severity == .error).forEach(errors.add);
    final listing = const TextReporter().format(errors);
    final summary = TextReporter.summary(errors);
    _err
      ..write(listing.substring(0, listing.length - summary.length))
      ..writeln(TextReporter.summary(diagnostics));
  }
}
