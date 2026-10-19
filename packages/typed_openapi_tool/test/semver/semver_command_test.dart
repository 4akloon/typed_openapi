import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../helpers/git_repo.dart';
import '../helpers/semver_fixture.dart';

void main() {
  test('an unknown base is a message and a failure', () async {
    final result = await SemverFixture.run(SemverFixture.repoWith(), [
      '--base',
      'nonexistent_rev',
    ]);
    expect(result.code, 1);
    expect(result.err, contains('"nonexistent_rev" is not a commit'));
    expect(result.out, isNot(contains('did not change')));
  });

  test('a base that starts with a dash is a usage error', () async {
    final result = await SemverFixture.run(SemverFixture.repoWith(), [
      '--base=-x',
    ]);
    expect(result.code, 64);
    expect(result.err, contains('must not start with "-"'));
  });

  test('a root that is not a directory is a message, not a trace', () async {
    final result = await SemverFixture.run(SemverFixture.repoWith(), [
      '--base',
      'base',
      '--root',
      '/nope',
    ]);
    expect(result.code, 1);
    expect(result.err, contains('The root is not a directory'));
  });

  test('a root without the generator files is a message', () async {
    final repo = GitRepo()
      ..write('x.txt', 'x')
      ..commit('base')
      ..git(['tag', 'base']);
    final result = await SemverFixture.run(repo, ['--base', 'base']);
    expect(result.code, 1);
    expect(result.err, contains('pubspec.yaml'));
  });

  test('an unchanged output passes', () async {
    final result = await SemverFixture.run(SemverFixture.repoWith(), [
      '--base',
      'base',
    ]);
    expect(result.code, 0);
    expect(result.out, contains('did not change'));
  });

  test('a changed golden without an entry fails', () async {
    final repo = SemverFixture.repoWith()..write(SemverFixture.golden, 'two\n');
    repo.commit('change');
    final result = await SemverFixture.run(repo, ['--base', 'base']);
    expect(result.code, 1);
    expect(result.err, contains('add an entry under "### Output changes"'));
    expect(result.err, contains('raise the version'));
    expect(result.out, contains('changed: 2 problems'));
  });

  test('a changed golden with an entry and a version complies', () async {
    final repo = SemverFixture.repoWith()
      ..write(SemverFixture.golden, 'two\n')
      ..write(SemverFixture.changelog, SemverFixture.notedChangelog)
      ..write(SemverFixture.pubspec, SemverFixture.version('0.2.0'));
    repo.commit('change');
    final result = await SemverFixture.run(repo, ['--base', 'base']);
    expect(result.code, 0);
    expect(result.out, contains('changed and complies'));
    expect(result.err, isEmpty);
  });

  test('a base without a lock is judged by the goldens alone', () async {
    final repo = SemverFixture.repoWith()
      ..write(SemverFixture.lock, '{"a": 1}\n');
    repo.commit('add the lock');
    final result = await SemverFixture.run(repo, ['--base', 'base']);
    expect(result.code, 0);
    expect(result.out, contains('did not change'));
  });

  test('a base with a lock is judged by the lock too', () async {
    final repo = SemverFixture.repoWith(withLock: true)
      ..write(SemverFixture.lock, '{"a": 1}\n');
    repo.commit('change the lock');
    final result = await SemverFixture.run(repo, ['--base', 'base']);
    expect(result.code, 1);
    expect(result.out, contains('changed: 2 problems'));
  });

  test('a version raised only in the working tree does not count', () async {
    final repo = SemverFixture.repoWith()..write(SemverFixture.golden, 'two\n');
    repo.commit('change');
    repo
      ..write(SemverFixture.changelog, SemverFixture.notedChangelog)
      ..write(SemverFixture.pubspec, SemverFixture.version('0.2.0'));
    final result = await SemverFixture.run(repo, ['--base', 'base']);
    expect(result.code, 1);
    expect(result.err, contains('raise the version'));
  });

  test('a base without the generator files is a git message', () async {
    final repo = GitRepo()
      ..write('x.txt', 'x')
      ..commit('base')
      ..git(['tag', 'base'])
      ..write(SemverFixture.pubspec, SemverFixture.version('0.1.0'))
      ..write(SemverFixture.changelog, SemverFixture.plainChangelog)
      ..write(SemverFixture.golden, 'one\n');
    repo.commit('add the generator');
    final result = await SemverFixture.run(repo, ['--base', 'base']);
    expect(result.code, 1);
    expect(result.err, contains('git failed:'));
  });

  test('git output that is not UTF-8 is not an uncaught error', () async {
    final repo = SemverFixture.repoWith();
    File(
      '${repo.path}/$SemverFixture.changelog',
    ).writeAsBytesSync([
      ...utf8.encode(SemverFixture.plainChangelog),
      0xff,
      0x0a,
    ]);
    repo.commit('binary changelog');
    final result = await SemverFixture.run(repo, ['--base', 'base']);
    expect(result.code, 0);
    expect(result.out, contains('did not change'));
  });
}
