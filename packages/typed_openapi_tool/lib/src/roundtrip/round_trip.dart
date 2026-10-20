import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:typed_openapi_core/typed_openapi_core.dart';

import '../corpus/corpus_exception.dart';
import '../corpus/timed_process.dart';
import 'example_reader.dart';
import 'roundtrip_program.dart';
import 'sample.dart';
import 'synthetic_values.dart';

/// What the round trip of one client found: the examples and synthetic
/// values that decoded, the examples that do not (defects of the spec), and
/// the failures (of the generator or of the tool), and how many examples
/// and synthetic values could not be built (`skippedExamples`,
/// `skippedSynthetic`). `notRun` says why the program could not run (a
/// crash or a timeout): that is a failure of the infrastructure, not a
/// count.
typedef RoundTripResult = ({
  int examples,
  int synthetic,
  int skippedExamples,
  int skippedSynthetic,
  List<String> defects,
  List<String> failures,
  List<String> notRun,
});

/// Runs the runtime decoding test of one generated client (R15.3) in the
/// package that holds its code, after `dart pub get`.
final class RoundTrip {
  /// Creates the round trip in the package [directory] named [package]; the
  /// program of a client is killed after [timeout].
  const RoundTrip(
    this.directory,
    this.package, {
    this.timeout = const Duration(minutes: 10),
  });

  /// The directory of the package of generated code.
  final String directory;

  /// The name of the package, for its `package:` imports.
  final String package;

  /// How long the program of one client may run.
  final Duration timeout;

  /// Round-trips the examples [examples] reads and the synthetic values of
  /// the client [client] with the IR [ir].
  ///
  /// A value `jsonEncode` rejects (`.nan`, `.inf`, a timestamp) is not run:
  /// in an example it is a defect of the spec, in a synthetic value a
  /// failure of the tool.
  Future<RoundTripResult> run(
    String client,
    ClientIr ir,
    ExampleReader examples,
  ) async {
    final read = examples.of(ir);
    final synthetic = SyntheticValues(ir);
    final built = synthetic.all();
    final samples = [...read.samples, ...built];
    final program = _writeProgram(client, ir, samples);
    final ran = await _run(client, program.source, program.data);
    return (
      examples: ran.examples,
      synthetic: ran.synthetic,
      skippedExamples: read.skipped,
      skippedSynthetic: synthetic.attempted - built.length,
      defects: [
        ...ran.defects,
        for (final s in samples)
          if (!s.isEncodable && s.isExample)
            '$client: ${s.type}: an example is not JSON a client can read '
                '(NaN, infinity or a value JSON has no form for).',
      ],
      notRun: ran.notRun,
      failures: [
        ...ran.failures,
        for (final s in samples)
          if (!s.isEncodable && !s.isExample)
            '$client: ${s.type}: a synthetic value is not JSON.',
      ],
    );
  }

  /// Writes the data file of the encodable [samples] and the program of the
  /// client; returns their paths (the program relative to the package).
  ({String source, String data}) _writeProgram(
    String client,
    ClientIr ir,
    List<Sample> samples,
  ) {
    final data = p.join(directory, 'roundtrip', '$client.json');
    File(data)
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode([
          for (final s in samples)
            if (s.isEncodable) s.toJson(),
        ]),
      );
    final source = p.join('bin', 'roundtrip_$client.dart');
    File(p.join(directory, source))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        RoundTripProgram(ir).source('package:$package/$client/models.dart'),
      );
    return (source: source, data: data);
  }

  Future<RoundTripResult> _run(
    String client,
    String program,
    String data,
  ) async {
    final ProcessResult result;
    try {
      result = await TimedProcess(timeout: timeout).run(
        Platform.resolvedExecutable,
        ['run', program, data],
        workingDirectory: directory,
      );
    } on CorpusException catch (e) {
      return _failed(client, e.message);
    }
    return readOutput(client, result);
  }

  static RoundTripResult _failed(String client, String reason) => (
    examples: 0,
    synthetic: 0,
    skippedExamples: 0,
    skippedSynthetic: 0,
    defects: const <String>[],
    failures: const <String>[],
    notRun: ['$client: the round trip did not run: $reason'],
  );

  /// The result the program printed as its last line; output that is no
  /// result (a crash, other text, a wrong shape) is a run that did not run.
  static RoundTripResult readOutput(String client, ProcessResult result) {
    final lines = '${result.stdout}'.trim().split('\n');
    if (result.exitCode != 0 || lines.last.isEmpty) {
      return _failed(client, TimedProcess.excerpt(result.stderr));
    }
    final Object? json;
    try {
      json = jsonDecode(lines.last);
    } on FormatException {
      return _failed(client, 'the program printed no result.');
    }
    return _parse(client, json) ??
        _failed(client, 'the program printed a result of the wrong shape.');
  }

  /// The result in [json], or null when it has not the shape the program
  /// prints.
  static RoundTripResult? _parse(String client, Object? json) {
    if (json case {
      'examples': final int examples,
      'synthetic': final int synthetic,
      'defects': final List<Object?> defects,
      'failures': final List<Object?> failures,
    }) {
      return (
        examples: examples,
        synthetic: synthetic,
        skippedExamples: 0,
        skippedSynthetic: 0,
        defects: [for (final text in defects) '$client: $text'],
        failures: [for (final text in failures) '$client: $text'],
        notRun: const <String>[],
      );
    }
    return null;
  }
}
