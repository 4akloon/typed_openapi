import 'dart:io';

import 'package:path/path.dart' as p;

import '../corpus/corpus_exception.dart';
import 'diagnostic_source.dart';
import 'docs_problems.dart';
import 'generated_docs.dart';

/// The `docs.dart` command line: `generate` and `check`.
final class DocsCli {
  /// Creates the command line; the output goes to [out] and [err].
  DocsCli({StringSink? out, StringSink? err})
    : _out = out ?? stdout,
      _err = err ?? stderr;

  final StringSink _out;
  final StringSink _err;

  static const _usage =
      'Usage: dart run bin/docs.dart [--root <packages directory>] '
      '<generate|check>';

  /// Runs the command in [args] and returns the exit code.
  Future<int> run(List<String> args) async {
    var root = '..';
    var rest = args;
    if (args.length >= 2 && args.first == '--root') {
      root = args[1];
      rest = args.sublist(2);
    }
    final command = rest.length == 1 ? rest.single : null;
    if (command != 'generate' && command != 'check') {
      _err.writeln(_usage);
      return 64;
    }
    try {
      final files = GeneratedDocs(await DiagnosticSource.load()).files();
      return command == 'generate'
          ? _generate(root, files)
          : _check(root, files);
    } on DocsProblems catch (e) {
      _err.writeln('A doc comment breaks the convention:\n$e');
      return 1;
    } on CorpusException catch (e) {
      _err.writeln(e);
      return 1;
    }
  }

  int _generate(String root, Map<String, String> files) {
    for (final path in _differing(root, files)) {
      File(p.join(root, path))
        ..createSync(recursive: true)
        ..writeAsStringSync(files[path]!);
      _out.writeln('Wrote $path');
    }
    return 0;
  }

  int _check(String root, Map<String, String> files) {
    final stale = _differing(root, files);
    if (stale.isEmpty) {
      _out.writeln('The generated docs are current.');
      return 0;
    }
    _err
      ..writeln('These generated files are stale: ${stale.join(', ')}')
      ..writeln('Run "dart run bin/docs.dart generate" and commit the result.');
    return 1;
  }

  List<String> _differing(String root, Map<String, String> files) => [
    for (final MapEntry(:key, :value) in files.entries)
      if (!_matches(File(p.join(root, key)), value)) key,
  ];

  bool _matches(File file, String text) =>
      file.existsSync() && file.readAsStringSync() == text;
}
