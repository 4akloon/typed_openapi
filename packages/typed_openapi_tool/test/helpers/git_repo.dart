import 'dart:io';

import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

/// A real git repository in a temp directory, for tests of git commands.
final class GitRepo {
  /// Creates and initialises the repository.
  GitRepo() : _dir = TempDir() {
    git(['init', '-q']);
  }

  final TempDir _dir;

  /// The repository root.
  String get path => _dir.path;

  /// Writes [content] to [relativePath].
  void write(String relativePath, String content) =>
      _dir.write(relativePath, content);

  /// Runs git in the repository; fails the test setup when git fails.
  void git(List<String> arguments) {
    final result = Process.runSync('git', [
      '-C',
      path,
      '-c',
      'user.name=Test',
      '-c',
      'user.email=test@example.com',
      '-c',
      'commit.gpgsign=false',
      ...arguments,
    ]);
    if (result.exitCode != 0) {
      throw StateError('git ${arguments.join(' ')}: ${result.stderr}');
    }
  }

  /// Commits everything under [message].
  void commit(String message) {
    git(['add', '-A']);
    git(['commit', '-q', '-m', message]);
  }
}
