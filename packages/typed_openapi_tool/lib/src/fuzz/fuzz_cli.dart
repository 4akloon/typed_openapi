import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../corpus/corpus_exception.dart';
import 'fuzz_run.dart';

/// The `fuzz` command line of the repository (M11): runs the escaping fuzz
/// on a range of seeds and exits `1` when it finds a problem.
final class FuzzCli {
  /// Creates the command line; the summary goes to [out], problems to [err].
  FuzzCli({StringSink? out, StringSink? err})
    : _out = out ?? stdout,
      _err = err ?? stderr;

  final StringSink _out;
  final StringSink _err;

  static final _parser = ArgParser()
    ..addOption('seeds', defaultsTo: '200', help: 'How many seeds to run.')
    ..addOption('from', defaultsTo: '0', help: 'The first seed.')
    ..addOption(
      'sample-every',
      defaultsTo: '12',
      help: 'Every how many seeds an output is analyzed.',
    )
    ..addOption(
      'work',
      defaultsTo: '.dart_tool/fuzz',
      help: 'Where the sample package is written.',
    )
    ..addOption(
      'runtime',
      defaultsTo: '../typed_openapi_runtime',
      help: 'The typed_openapi_runtime package the sample depends on.',
    );

  /// Runs the fuzz with [args]; returns the exit code.
  Future<int> run(List<String> args) async {
    final ArgResults results;
    final int seeds;
    final int from;
    final int sampleEvery;
    try {
      results = _parser.parse(args);
      seeds = _number(results, 'seeds', least: 0);
      from = _number(results, 'from', least: 0);
      sampleEvery = _number(results, 'sample-every', least: 1);
    } on FormatException catch (e) {
      _err
        ..writeln(e.message)
        ..writeln(_parser.usage);
      return 64;
    }
    try {
      return await _fuzz(results, seeds: seeds, from: from, every: sampleEvery);
    } on CorpusException catch (e) {
      _err.writeln(e.message);
      return 1;
    } on FileSystemException catch (e) {
      _err.writeln('${e.message}: ${e.path}');
      return 1;
    }
  }

  Future<int> _fuzz(
    ArgResults results, {
    required int seeds,
    required int from,
    required int every,
  }) async {
    final report = await FuzzRun(
      work: p.normalize(p.absolute(results.option('work')!)),
      runtime: p.normalize(p.absolute(results.option('runtime')!)),
      log: _err,
      sampleEvery: every,
    ).run(from: from, count: seeds);
    report.failures.forEach(_err.writeln);
    _out.writeln(
      '$seeds seeds: ${report.builds} builds, '
      '${report.files} files, ${report.sampled} sampled; '
      '${report.failures.length} problems.',
    );
    return report.failures.isEmpty ? 0 : 1;
  }

  static int _number(ArgResults results, String name, {required int least}) {
    final text = results.option(name)!;
    final value = int.tryParse(text);
    if (value == null || value < least) {
      throw FormatException(
        '--$name must be a whole number of $least or more, '
        'not "$text".',
      );
    }
    return value;
  }
}
