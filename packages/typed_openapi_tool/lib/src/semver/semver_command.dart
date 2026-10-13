import 'dart:io';

import 'package:args/command_runner.dart';

import 'semver_rule.dart';

/// `corpus semver`: compares the change with its base branch and fails when
/// the generated output changed without a CHANGELOG entry under "Output
/// changes" and a raised version (R15.4, [SemverRule]).
final class SemverCommand extends Command<int> {
  /// Creates the command; lines go to [_out], problems to [_err].
  SemverCommand(this._out, this._err) {
    argParser
      ..addOption(
        'base',
        defaultsTo: 'origin/main',
        help: 'The git revision the change is compared with.',
      )
      ..addOption(
        'root',
        defaultsTo: '../..',
        help: 'The root of the repository.',
      );
  }

  final StringSink _out;
  final StringSink _err;

  /// The files whose change is a change of generated output.
  static const outputs = [
    'packages/typed_openapi_tool/corpus.lock',
    'packages/typed_openapi/test/emit/goldens',
  ];

  static const _pubspec = 'packages/typed_openapi/pubspec.yaml';
  static const _changelog = 'packages/typed_openapi/CHANGELOG.md';

  @override
  String get name => 'semver';

  @override
  String get description =>
      'Check that a change of output has a CHANGELOG entry and a raised '
      'version.';

  @override
  Future<int> run() async {
    final results = argResults!;
    final root = results.option('root')!;
    final base = results.option('base')!;
    // The lock is compared from the first base that has one (M11 adds it);
    // the goldens always are.
    final lock = await _git(root, ['show', '$base:${outputs.first}']);
    final changed = await _git(root, [
      'diff',
      '--name-only',
      '$base...HEAD',
      '--',
      ...lock.isEmpty ? outputs.skip(1) : outputs,
    ]);
    final problems = const SemverRule().problems(
      outputChanged: changed.trim().isNotEmpty,
      basePubspec: await _git(root, ['show', '$base:$_pubspec']),
      pubspec: File('$root/$_pubspec').readAsStringSync(),
      baseChangelog: await _git(root, ['show', '$base:$_changelog']),
      changelog: File('$root/$_changelog').readAsStringSync(),
    );
    problems.forEach(_err.writeln);
    _out.writeln(
      changed.trim().isEmpty
          ? 'The generated output did not change.'
          : 'The generated output changed: ${problems.length} problems.',
    );
    return problems.isEmpty ? 0 : 1;
  }

  static Future<String> _git(String root, List<String> arguments) async {
    final result = await Process.run('git', ['-C', root, ...arguments]);
    return result.exitCode == 0 ? '${result.stdout}' : '';
  }
}
