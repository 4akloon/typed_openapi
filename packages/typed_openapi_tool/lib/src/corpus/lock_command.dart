import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'corpus_lock.dart';
import 'corpus_run.dart';
import 'fetch_command.dart';
import 'spec_cache.dart';
import 'timed_process.dart';

/// `corpus update` and `corpus check`: fetch the specs, run the corpus
/// ([CorpusRun]) and write `corpus.lock` (`update`) or compare the run with
/// it (`check`). Both fail when a gate fails; `check` also fails on any
/// difference from the lock and lists the changed files and codes.
final class LockCommand extends Command<int> {
  /// Creates `corpus update`, which rewrites the lock.
  LockCommand.update(
    this._out,
    this._err,
    this._download, {
    this.fetchesPackages = true,
  }) : name = 'update',
       _writes = true {
    _addOptions();
  }

  /// Creates `corpus check`, which compares the run with the lock.
  LockCommand.check(
    this._out,
    this._err,
    this._download, {
    this.fetchesPackages = true,
  }) : name = 'check',
       _writes = false {
    _addOptions();
  }

  @override
  final String name;

  /// Whether the gate may download packages when they are not cached.
  final bool fetchesPackages;

  /// How many spec defects a run prints.
  static const int maxDefectsPrinted = 50;

  final bool _writes;
  final StringSink _out;
  final StringSink _err;
  final Download _download;

  @override
  String get description => _writes
      ? 'Generate the corpus and write corpus.lock.'
      : 'Generate the corpus and compare it with corpus.lock.';

  void _addOptions() {
    FetchCommand.addCorpusOptions(argParser);
    argParser
      ..addOption('lock', defaultsTo: 'corpus.lock', help: 'The lock file.')
      ..addOption(
        'work',
        defaultsTo: '.dart_tool/corpus/out',
        help: 'Where the generated packages are written.',
      )
      ..addOption(
        'runtime',
        defaultsTo: '../typed_openapi_runtime',
        help: 'The typed_openapi_runtime package the output depends on.',
      );
  }

  @override
  Future<int> run() async {
    final results = argResults!;
    final specs = FetchCommand.specsOf(results);
    final lockFile = File(results.option('lock')!);
    // A lock that cannot be read fails before the long run.
    final expected = _writes || !lockFile.existsSync()
        ? null
        : CorpusLock.parse(lockFile.readAsStringSync());
    final cache = SpecCache(results.option('cache')!, _download);
    final result =
        await CorpusRun(
          work: p.normalize(p.absolute(results.option('work')!)),
          runtime: p.normalize(p.absolute(results.option('runtime')!)),
          fetchesPackages: fetchesPackages,
        ).run(specs, {
          for (final spec in specs)
            spec.name: p.normalize(p.absolute(await cache.fetch(spec))),
        });
    final differences = [
      if (expected != null) ...result.lock.differencesFrom(expected),
      if (!_writes && expected == null)
        '${lockFile.path} does not exist: run corpus update.',
    ];
    result.failures.forEach(_err.writeln);
    for (final failure in result.roundTrips) {
      _err.writeln('round trip: $failure');
    }
    _printDefects(result.defects);
    if (_writes && result.failures.isEmpty) {
      lockFile.writeAsStringSync(result.lock.format());
    } else if (_writes) {
      _err.writeln('${lockFile.path} was not written: the run has failures.');
    }
    differences.forEach(_out.writeln);
    _out.writeln(_summary(result.lock, differences));
    return result.failures.isEmpty && differences.isEmpty ? 0 : 1;
  }

  /// Lists the examples that do not match their own schema, the first
  /// [maxDefectsPrinted]; the lock counts them all.
  void _printDefects(List<String> defects) {
    for (final defect in defects.take(maxDefectsPrinted)) {
      _out.writeln('spec defect: ${TimedProcess.excerpt(defect)}');
    }
    if (defects.length > maxDefectsPrinted) {
      _out.writeln(
        '... and ${defects.length - maxDefectsPrinted} more spec defects.',
      );
    }
  }

  static String _summary(CorpusLock lock, List<String> differences) {
    final generated = lock.clients.values.where((c) => c.files.isNotEmpty);
    final files = generated.fold(0, (n, c) => n + c.files.length);
    return '${lock.clients.length} clients, ${generated.length} generated, '
        '$files files; ${differences.length} differences from the lock.';
  }
}
