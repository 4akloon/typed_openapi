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
    if (base.startsWith('-')) {
      usageException('The base revision must not start with "-": $base');
    }
    try {
      return await _check(root, base);
    } on _GitFailure catch (e) {
      _err.writeln(e.message);
      return 1;
    } on ProcessException catch (e) {
      _err.writeln('git could not be run: ${e.message}');
      return 1;
    } on FileSystemException catch (e) {
      _err.writeln('${e.message}: ${e.path}');
      return 1;
    }
  }

  Future<int> _check(String root, String base) async {
    if (!Directory(root).existsSync()) {
      throw _GitFailure('The root is not a directory: $root');
    }
    final pubspec = File('$root/$_pubspec').readAsStringSync();
    final changelog = File('$root/$_changelog').readAsStringSync();
    final sha = await _revision(root, base);
    // The lock is compared from the first base that has one (M11 adds it);
    // the goldens always are.
    final hasLock = (await _git(root, ['show', '$sha:${outputs.first}'])).ok;
    final changed = await _require(root, [
      'diff',
      '--name-only',
      '$sha...HEAD',
      '--',
      ...hasLock ? outputs : outputs.skip(1),
    ]);
    final problems = const SemverRule().problems(
      outputChanged: changed.trim().isNotEmpty,
      basePubspec: await _require(root, ['show', '$sha:$_pubspec']),
      pubspec: pubspec,
      baseChangelog: await _require(root, ['show', '$sha:$_changelog']),
      changelog: changelog,
    );
    problems.forEach(_err.writeln);
    _out.writeln(switch ((changed.trim().isEmpty, problems.length)) {
      (true, _) => 'The generated output did not change.',
      (false, 0) => 'The generated output changed and complies.',
      (false, final n) => 'The generated output changed: $n problems.',
    });
    return problems.isEmpty ? 0 : 1;
  }

  /// The full commit id of [base]; fails when it names no commit.
  Future<String> _revision(String root, String base) async {
    final result = await _git(root, [
      'rev-parse',
      '--verify',
      '--quiet',
      '$base^{commit}',
    ]);
    if (!result.ok) {
      throw _GitFailure(
        'The base revision "$base" is not a commit of the repository at '
        '$root.',
      );
    }
    return result.stdout.trim();
  }

  static Future<String> _require(String root, List<String> arguments) async {
    final result = await _git(root, arguments);
    if (!result.ok) throw _GitFailure('git failed: ${result.stderr.trim()}');
    return result.stdout;
  }

  static Future<_GitResult> _git(String root, List<String> arguments) async {
    final result = await Process.run('git', ['-C', root, ...arguments]);
    return _GitResult(
      result.exitCode == 0,
      '${result.stdout}',
      '${result.stderr}',
    );
  }
}

final class _GitResult {
  const _GitResult(this.ok, this.stdout, this.stderr);

  final bool ok;
  final String stdout;
  final String stderr;
}

final class _GitFailure implements Exception {
  const _GitFailure(this.message);

  final String message;
}
