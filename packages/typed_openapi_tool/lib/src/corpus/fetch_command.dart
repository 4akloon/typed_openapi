import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'corpus_exception.dart';
import 'corpus_list_reader.dart';
import 'corpus_spec.dart';
import 'pinned_schema.dart';
import 'spec_cache.dart';

/// `corpus fetch`: downloads the specs of `corpus.yaml` that are not in the
/// cache yet, and the `schemas` the tests read, and verifies the hash of
/// every one.
final class FetchCommand extends Command<int> {
  /// Creates the command; lines go to [_out], failures to [_err].
  FetchCommand(this._out, this._err, this._download) {
    addCorpusOptions(argParser);
  }

  final StringSink _out;
  final StringSink _err;
  final Download _download;

  @override
  String get name => 'fetch';

  @override
  String get description =>
      'Download the specs of corpus.yaml into the cache and verify them.';

  /// Adds `--corpus` and `--cache`, which every corpus command takes.
  static void addCorpusOptions(ArgParser parser) => parser
    ..addOption(
      'corpus',
      defaultsTo: 'corpus.yaml',
      help: 'The list of pinned specs.',
    )
    ..addOption(
      'cache',
      defaultsTo: '.dart_tool/corpus/specs',
      help: 'Where the downloaded specs are kept.',
    );

  /// The entries of the corpus file of [results], restricted to the names
  /// in its rest arguments when there are any.
  static List<CorpusSpec> specsOf(ArgResults results) {
    final specs = const CorpusListReader().read(
      File(results.option('corpus')!).readAsStringSync(),
    );
    final only = results.rest.toSet();
    return [
      for (final spec in specs)
        if (only.isEmpty || only.contains(spec.name)) spec,
    ];
  }

  /// The `schemas` of the corpus file of [results], restricted to the names
  /// in its rest arguments when there are any.
  static List<PinnedSchema> schemasOf(ArgResults results) {
    final schemas = const CorpusListReader().readSchemas(
      File(results.option('corpus')!).readAsStringSync(),
    );
    final only = results.rest.toSet();
    return [
      for (final schema in schemas)
        if (only.isEmpty || only.contains(schema.name)) schema,
    ];
  }

  /// Throws a [UsageException] when a name in the rest arguments is neither
  /// a spec nor a schema, so a typo never fetches nothing and succeeds.
  void _checkNames(ArgResults results) {
    const reader = CorpusListReader();
    final text = File(results.option('corpus')!).readAsStringSync();
    final known = [
      for (final spec in reader.read(text)) spec.name,
      for (final schema in reader.readSchemas(text)) schema.name,
    ];
    final unknown = results.rest.where((n) => !known.contains(n)).toList();
    if (unknown.isNotEmpty) {
      throw UsageException(
        'Unknown name ${unknown.join(', ')}; known: ${known.join(', ')}.',
        usage,
      );
    }
  }

  @override
  Future<int> run() async {
    final results = argResults!;
    _checkNames(results);
    final cache = SpecCache(results.option('cache')!, _download);
    try {
      for (final spec in specsOf(results)) {
        _out.writeln('${spec.name}: ${await cache.fetch(spec)}');
      }
      for (final schema in schemasOf(results)) {
        _out.writeln('${schema.name}: ${await cache.fetchSchema(schema)}');
      }
      return 0;
    } on CorpusException catch (e) {
      _err.writeln(e.message);
      return 1;
    }
  }
}
