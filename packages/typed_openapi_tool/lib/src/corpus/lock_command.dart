import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'corpus_exception.dart';
import 'corpus_lock.dart';
import 'corpus_run.dart';
import 'fetch_command.dart';
import 'spec_cache.dart';

/// `corpus update` and `corpus check`: fetch the specs, run the corpus
/// ([CorpusRun]) and write `corpus.lock` (`update`) or compare the run with
/// it (`check`). Both fail when a gate fails; `check` also fails on any
/// difference from the lock and lists the changed files and codes.
final class LockCommand extends Command<int> {
  /// Creates `corpus update`, which rewrites the lock.
  LockCommand.update(this._out, this._err, this._download)
    : name = 'update',
      _writes = true {
    _addOptions();
  }

  /// Creates `corpus check`, which compares the run with the lock.
  LockCommand.check(this._out, this._err, this._download)
    : name = 'check',
      _writes = false {
    _addOptions();
  }

  @override
  final String name;

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
    final cache = SpecCache(results.option('cache')!, _download);
    final CorpusResult result;
    try {
      result =
          await CorpusRun(
            work: p.normalize(p.absolute(results.option('work')!)),
            runtime: p.normalize(p.absolute(results.option('runtime')!)),
          ).run(specs, {
            for (final spec in specs)
              spec.name: p.normalize(p.absolute(await cache.fetch(spec))),
          });
    } on CorpusException catch (e) {
      _err.writeln(e.message);
      return 1;
    }
    final lockFile = File(results.option('lock')!);
    final differences = _writes || !lockFile.existsSync()
        ? <String>[]
        : result.lock.differencesFrom(
            CorpusLock.parse(lockFile.readAsStringSync()),
          );
    if (_writes) lockFile.writeAsStringSync(result.lock.format());
    if (!_writes && !lockFile.existsSync()) {
      differences.add('${lockFile.path} does not exist: run corpus update.');
    }
    result.failures.forEach(_err.writeln);
    for (final failure in result.roundTrips) {
      _err.writeln('round trip: $failure');
    }
    differences.forEach(_out.writeln);
    _out.writeln(_summary(result.lock, differences));
    return result.failures.isEmpty && differences.isEmpty ? 0 : 1;
  }

  static String _summary(CorpusLock lock, List<String> differences) {
    final generated = lock.clients.values.where((c) => c.files.isNotEmpty);
    final files = generated.fold(0, (n, c) => n + c.files.length);
    return '${lock.clients.length} clients, ${generated.length} generated, '
        '$files files; ${differences.length} differences from the lock.';
  }
}
