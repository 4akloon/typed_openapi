import 'dart:io';

import 'package:path/path.dart' as p;

/// The scratch package of one `union` mode of a corpus run: its pubspec, the
/// analyzer gate's lints and the generator config, with each client's
/// output in `lib/<name>`.
final class CorpusPackage {
  /// Creates the package in [directory] for the `union` mode [mode].
  const CorpusPackage(this.directory, this.mode);

  /// The directory of the package, absolute.
  final String directory;

  /// The `union` mode of the clients: `raw` or `structural`.
  final String mode;

  /// The name of the package, for `package:` imports.
  String get name => 'corpus_$mode';

  /// The generator config of the package.
  String get config => p.join(directory, 'typed_openapi.yaml');

  /// The output directory of the client [name].
  String outputOf(String name) => p.join(directory, 'lib', name);

  /// Deletes what an earlier run generated: the code, the round-trip
  /// programs and their data.
  void clean() {
    for (final folder in const ['lib', 'bin', 'roundtrip']) {
      final directory = Directory(p.join(this.directory, folder));
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    }
  }

  /// Writes the package for the clients [inputs] (a name and the absolute
  /// path of its spec); [runtime] is the directory of
  /// `typed_openapi_runtime`.
  void write(Map<String, String> inputs, String runtime) {
    Directory(directory).createSync(recursive: true);
    File(
      p.join(directory, 'pubspec.yaml'),
    ).writeAsStringSync(_pubspec(runtime));
    File(
      p.join(directory, 'analysis_options.yaml'),
    ).writeAsStringSync(_analysisOptions);
    final clients = StringBuffer();
    for (final MapEntry(key: name, value: input) in inputs.entries) {
      clients
        ..writeln('  ${_quoted(name)}:')
        ..writeln('    input: ${_quoted(input)}')
        ..writeln('    output: ${_quoted(outputOf(name))}');
    }
    File(config).writeAsStringSync(
      'defaults:\n  union: $mode\nclients:\n$clients',
    );
  }

  String _pubspec(String runtime) =>
      '''
name: $name
publish_to: none
environment:
  sdk: ">=3.10.0 <4.0.0"
dependencies:
  dio: ^5.11.1
  typed_openapi_runtime:
    path: ${_quoted(runtime)}
dev_dependencies:
  lints: ^6.1.0
''';

  /// package:lints/recommended and the rules flutter_lints adds, as in the
  /// analyzer gate of the generator's tests.
  static const _analysisOptions = '''
include: package:lints/recommended.yaml
linter:
  rules:
    - avoid_print
    - avoid_unnecessary_containers
    - avoid_web_libraries_in_flutter
    - no_logic_in_create_state
    - prefer_const_constructors_in_immutables
    - sized_box_for_whitespace
    - sort_child_properties_last
    - use_build_context_synchronously
    - use_full_hex_values_for_flutter_colors
    - use_key_in_widget_constructors
''';

  /// [path] as a single-quoted YAML scalar, with `/` separators.
  static String _quoted(String path) =>
      "'${path.replaceAll(r'\', '/').replaceAll("'", "''")}'";
}
