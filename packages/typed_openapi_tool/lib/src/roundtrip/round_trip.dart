import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:typed_openapi/typed_openapi.dart';

import 'example_reader.dart';
import 'roundtrip_program.dart';
import 'synthetic_values.dart';

/// What the round trip of one client found: the examples and synthetic
/// values that decoded, the examples that do not (defects of the spec), and
/// the failures (of the generator or of the tool).
typedef RoundTripResult = ({
  int examples,
  int synthetic,
  List<String> defects,
  List<String> failures,
});

/// Runs the runtime decoding test of one generated client (R15.3) in the
/// package that holds its code, after `dart pub get`.
final class RoundTrip {
  /// Creates the round trip in the package [directory] named [package].
  const RoundTrip(this.directory, this.package);

  /// The directory of the package of generated code.
  final String directory;

  /// The name of the package, for its `package:` imports.
  final String package;

  /// Round-trips the examples [examples] reads and the synthetic values of
  /// the client [client] with the IR [ir].
  Future<RoundTripResult> run(
    String client,
    ClientIr ir,
    ExampleReader examples,
  ) async {
    final samples = [...examples.of(ir), ...SyntheticValues(ir).all()];
    final data = p.join(directory, 'roundtrip', '$client.json');
    File(data)
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode([for (final s in samples) s.toJson()]));
    final program = p.join('bin', 'roundtrip_$client.dart');
    File(p.join(directory, program))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        RoundTripProgram(ir).source('package:$package/$client/models.dart'),
      );
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      program,
      data,
    ], workingDirectory: directory);
    return _read(client, result);
  }

  /// The result the program printed as its last line.
  static RoundTripResult _read(String client, ProcessResult result) {
    final lines = '${result.stdout}'.trim().split('\n');
    if (result.exitCode != 0 || lines.last.isEmpty) {
      return (
        examples: 0,
        synthetic: 0,
        defects: const <String>[],
        failures: ['$client: the round trip did not run: ${result.stderr}'],
      );
    }
    final json = jsonDecode(lines.last) as Map<String, Object?>;
    List<String> texts(String key) => [
      for (final text in json[key] as List<Object?>) '$client: $text',
    ];
    return (
      examples: json['examples'] as int,
      synthetic: json['synthetic'] as int,
      defects: texts('defects'),
      failures: texts('failures'),
    );
  }
}
