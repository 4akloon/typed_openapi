import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_cli.dart';

import '../helpers/git_repo.dart';

const _pubspec = 'packages/typed_openapi/pubspec.yaml';
const _changelog = 'packages/typed_openapi/CHANGELOG.md';
const _golden = 'packages/typed_openapi/test/emit/goldens/a.dart';
const _lock = 'packages/typed_openapi_tool/corpus.lock';

String _version(String v) => 'name: typed_openapi\nversion: $v\n';

const _plain = '## 0.1.0\n\n### Added\n- Things.\n';
const _noted =
    '## 0.2.0\n\n### Output changes\n- stripe: a.dart.\n\n## 0.1.0\n';

/// A repository whose commit `base` has the generator files.
GitRepo _repo({bool lock = false}) {
  final repo = GitRepo()
    ..write(_pubspec, _version('0.1.0'))
    ..write(_changelog, _plain)
    ..write(_golden, 'one\n');
  if (lock) repo.write(_lock, '{}\n');
  repo
    ..commit('base')
    ..git(['tag', 'base']);
  return repo;
}

Future<({int code, String out, String err})> _run(
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

void main() {
  test('an unknown base is a message and a failure', () async {
    final result = await _run(_repo(), ['--base', 'nonexistent_rev']);
    expect(result.code, 1);
    expect(result.err, contains('"nonexistent_rev" is not a commit'));
    expect(result.out, isNot(contains('did not change')));
  });

  test('a base that starts with a dash is a usage error', () async {
    final result = await _run(_repo(), ['--base=-x']);
    expect(result.code, 64);
    expect(result.err, contains('must not start with "-"'));
  });

  test('a root that is not a directory is a message, not a trace', () async {
    final result = await _run(_repo(), ['--base', 'base', '--root', '/nope']);
    expect(result.code, 1);
    expect(result.err, contains('The root is not a directory'));
  });

  test('a root without the generator files is a message', () async {
    final repo = GitRepo()
      ..write('x.txt', 'x')
      ..commit('base')
      ..git(['tag', 'base']);
    final result = await _run(repo, ['--base', 'base']);
    expect(result.code, 1);
    expect(result.err, contains('pubspec.yaml'));
  });

  test('an unchanged output passes', () async {
    final result = await _run(_repo(), ['--base', 'base']);
    expect(result.code, 0);
    expect(result.out, contains('did not change'));
  });

  test('a changed golden without an entry fails', () async {
    final repo = _repo()..write(_golden, 'two\n');
    repo.commit('change');
    final result = await _run(repo, ['--base', 'base']);
    expect(result.code, 1);
    expect(result.err, contains('add an entry under "### Output changes"'));
    expect(result.err, contains('raise the version'));
    expect(result.out, contains('changed: 2 problems'));
  });

  test('a changed golden with an entry and a version complies', () async {
    final repo = _repo()
      ..write(_golden, 'two\n')
      ..write(_changelog, _noted)
      ..write(_pubspec, _version('0.2.0'));
    repo.commit('change');
    final result = await _run(repo, ['--base', 'base']);
    expect(result.code, 0);
    expect(result.out, contains('changed and complies'));
    expect(result.err, isEmpty);
  });

  test('a base without a lock is judged by the goldens alone', () async {
    final repo = _repo()..write(_lock, '{"a": 1}\n');
    repo.commit('add the lock');
    final result = await _run(repo, ['--base', 'base']);
    expect(result.code, 0);
    expect(result.out, contains('did not change'));
  });

  test('a base with a lock is judged by the lock too', () async {
    final repo = _repo(lock: true)..write(_lock, '{"a": 1}\n');
    repo.commit('change the lock');
    final result = await _run(repo, ['--base', 'base']);
    expect(result.code, 1);
    expect(result.out, contains('changed: 2 problems'));
  });
}
