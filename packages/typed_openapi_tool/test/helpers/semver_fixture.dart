import 'package:typed_openapi_tool/src/corpus/corpus_cli.dart';

import 'git_repo.dart';

/// Repositories and runs for the `corpus semver` tests.
final class SemverFixture {
  const SemverFixture._();

  /// The generator's pubspec path in the repository.
  static const pubspec = 'packages/typed_openapi/pubspec.yaml';

  /// The generator's changelog path.
  static const changelog = 'packages/typed_openapi/CHANGELOG.md';

  /// A golden file path.
  static const golden = 'packages/typed_openapi/test/emit/goldens/a.dart';

  /// The corpus lock path.
  static const lock = 'packages/typed_openapi_tool/corpus.lock';

  /// A changelog without an output-changes entry.
  static const plainChangelog = '## 0.1.0\n\n### Added\n- Things.\n';

  /// A changelog with an entry under 0.2.0.
  static const notedChangelog =
      '## 0.2.0\n\n### Output changes\n- stripe: a.dart.\n\n## 0.1.0\n';

  /// The pubspec text of version [v].
  static String version(String v) => 'name: typed_openapi\nversion: $v\n';

  /// A repository whose commit `base` has the generator files; with
  /// [withLock] it also has a lock.
  static GitRepo repoWith({bool withLock = false}) {
    final repo = GitRepo()
      ..write(pubspec, version('0.1.0'))
      ..write(changelog, plainChangelog)
      ..write(golden, 'one\n');
    if (withLock) repo.write(lock, '{}\n');
    repo
      ..commit('base')
      ..git(['tag', 'base']);
    return repo;
  }

  /// Runs `corpus semver` on [repo] with [arguments].
  static Future<({int code, String out, String err})> run(
    GitRepo repo,
    List<String> arguments,
  ) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await CorpusCli(
      out: out,
      err: err,
    ).run(['semver', '--root', repo.path, ...arguments]);
    return (code: code, out: '$out', err: '$err');
  }
}
