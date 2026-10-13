import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'dart_literals.dart';

/// Checks that escaping never changes content (spec decision 5, check 2):
/// the string literals of each sampled client are evaluated by the Dart VM,
/// and every spec string the client's IR holds must be among their values.
final class LiteralCheck {
  /// Creates the check of the sample package in [directory], whose clients
  /// are `lib/<name>/`.
  const LiteralCheck(this.directory);

  /// The directory of the sample package.
  final String directory;

  /// The failures for [expected], the spec strings of each sampled client
  /// by its name; empty when every string is a literal's value.
  Future<List<String>> run(Map<String, List<String>> expected) async {
    final program = StringBuffer()
      ..writeln("import 'dart:convert';")
      ..writeln('const literals = <String, List<String>>{');
    for (final name in expected.keys) {
      program.writeln("  '$name': [");
      for (final literal in _literals(p.join(directory, 'lib', name))) {
        program.writeln('    $literal,');
      }
      program.writeln('  ],');
    }
    program
      ..writeln('};')
      ..writeln('void main() => print(jsonEncode(literals));');
    final file = p.join(directory, 'bin', 'literals.dart');
    File(file)
      ..createSync(recursive: true)
      ..writeAsStringSync('$program');
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      file,
    ], workingDirectory: directory);
    if (result.exitCode != 0) {
      return ['The literals program failed: ${result.stderr}'];
    }
    final values = jsonDecode('${result.stdout}') as Map<String, Object?>;
    return [
      for (final MapEntry(key: name, value: strings) in expected.entries)
        ..._missing(name, strings, (values[name] as List<Object?>).cast()),
    ];
  }

  /// The failures of the client [name]: a string in fewer [literals] than
  /// [expected] holds it. A common string such as `a` is among the literals
  /// of any client, so its count, not its presence, is what must match.
  static List<String> _missing(
    String name,
    List<String> expected,
    List<String> literals,
  ) {
    final held = <String, int>{};
    for (final literal in literals) {
      held.update(literal, (n) => n + 1, ifAbsent: () => 1);
    }
    final wanted = <String, int>{};
    for (final string in expected) {
      wanted.update(string, (n) => n + 1, ifAbsent: () => 1);
    }
    return [
      for (final MapEntry(key: string, value: count) in wanted.entries)
        if ((held[string] ?? 0) < count)
          if ((held[string] ?? 0) == 0 && count == 1)
            '$name: the spec string ${jsonEncode(string)} is in no literal.'
          else
            '$name: the spec string ${jsonEncode(string)} is in '
                '${held[string] ?? 0} literals, not $count.',
    ];
  }

  /// The literals of every Dart file under [folder], each as often as it
  /// occurs, sorted.
  static List<String> _literals(String folder) {
    final literals = <String>[];
    for (final entity in Directory(folder).listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        literals.addAll(DartLiterals(entity.readAsStringSync()).scan());
      }
    }
    return literals..sort();
  }
}
