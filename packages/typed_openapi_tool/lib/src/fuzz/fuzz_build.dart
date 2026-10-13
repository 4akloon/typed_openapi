import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:typed_openapi/typed_openapi.dart';

import 'fuzz_spec.dart';

/// What one build of a fuzz seed gave: the files of each client, the IR of
/// each client, and the text report of the run.
typedef FuzzOutput = ({
  Map<String, Map<String, String>> files,
  Map<String, ClientIr> irs,
  String report,
});

/// Builds the spec of one seed as `generate` would, in-process: one client
/// per generation config and `union` mode, all of the same spec and the
/// same overrides file.
final class FuzzBuild {
  /// Creates the build of the seed's [input] in the empty directory
  /// [directory].
  FuzzBuild(this.directory, FuzzInput input) {
    File(p.join(directory, 'spec.json')).writeAsStringSync(input.spec);
    File(
      p.join(directory, 'overrides.json'),
    ).writeAsStringSync(input.overrides);
    final clients = StringBuffer();
    for (final (name, settings) in configs) {
      for (final mode in const ['raw', 'structural']) {
        clients.writeln(
          '  ${name}_$mode: {input: spec.json, output: out/${name}_$mode, '
          'overrides: overrides.json, union: $mode, $settings}',
        );
      }
    }
    File(config).writeAsStringSync('clients:\n$clients');
  }

  /// The generation configs, by name: grouping by tag with a template, by
  /// path with optional tri-state fields, one class with the extension.
  static const configs = [
    ('tag', "naming: {group: '{Tag}Calls'}"),
    ('path', 'group_by: path, tri_state: optional'),
    ('single', 'group_by: single, tri_state: extension'),
  ];

  /// The directory of the seed's files.
  final String directory;

  /// The config of the build.
  String get config => p.join(directory, 'typed_openapi.yaml');

  /// Checks and emits every client; a crash of the generator is not
  /// caught.
  FuzzOutput build() {
    final bag = DiagnosticBag();
    final project = ConfigLoader(bag).load(config);
    final files = <String, Map<String, String>>{};
    final irs = <String, ClientIr>{};
    for (final check
        in project == null
            ? const <ClientCheck>[]
            : SpecChecker(bag).check(project)) {
      if (check.ir case final ir?) {
        irs[check.client.name] = ir;
        files[check.client.name] = const ApiLibrary().files(
          ir,
          client: 'api',
        );
      }
    }
    return (files: files, irs: irs, report: const TextReporter().format(bag));
  }
}
