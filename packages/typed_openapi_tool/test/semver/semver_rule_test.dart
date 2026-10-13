import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/semver/semver_rule.dart';

const _base = '## 0.1.0 - Unreleased\n\n### Added\n- Things.\n';
const _entry =
    '## 0.2.0 - Unreleased\n\n### Output changes\n'
    '- stripe: models/a.dart.\n\n## 0.1.0\n';

void main() {
  const rule = SemverRule();

  List<String> problems({
    bool changed = true,
    String version = '0.2.0',
    String changelog = _entry,
    String baseVersion = '0.1.0',
  }) => rule.problems(
    outputChanged: changed,
    basePubspec: 'name: typed_openapi\nversion: $baseVersion\n',
    pubspec: 'name: typed_openapi\nversion: $version\n',
    baseChangelog: _base,
    changelog: changelog,
  );

  test('no change of output needs nothing', () {
    expect(
      problems(changed: false, version: '0.1.0', changelog: _base),
      isEmpty,
    );
  });

  test('a change with an entry and a raised minor version complies', () {
    expect(problems(), isEmpty);
  });

  test('a change without an entry says what to add', () {
    expect(problems(changelog: _base), [
      contains('add an entry under "### Output changes"'),
    ]);
  });

  test('before 1.0 the minor version must rise, after it the major', () {
    expect(problems(version: '0.1.1'), [
      contains('from 0.1.0 to 0.2.0 or later (minor before 1.0)'),
    ]);
    expect(problems(baseVersion: '1.2.0', version: '1.3.0'), [
      contains('from 1.2.0 to 2.0.0 or later (major after 1.0)'),
    ]);
    expect(problems(baseVersion: '1.2.0', version: '2.0.0'), isEmpty);
  });

  test('an unreadable version is a problem of its own', () {
    final result = rule.problems(
      outputChanged: true,
      basePubspec: 'name: x\n',
      pubspec: 'name: x\n',
      baseChangelog: _base,
      changelog: _entry,
    );
    expect(result, [contains('version of packages/typed_openapi/pubspec')]);
  });

  test('a missing entry and a missing version are both reported', () {
    expect(problems(version: '0.1.0', changelog: _base), hasLength(2));
  });

  test('an entry in a section that is not the top one does not count', () {
    const old =
        '## 0.2.0\n\n### Added\n- x.\n\n## 0.1.0\n\n### Output changes\n- a.\n';
    expect(problems(changelog: old), [contains('add an entry')]);
  });

  test('a lower version does not comply', () {
    expect(problems(baseVersion: '0.3.0', version: '0.2.0'), hasLength(1));
  });

  test('a changelog edited without the heading has no entry', () {
    expect(problems(changelog: '$_base- More things.\n'), [
      contains('add an entry'),
    ]);
  });

  test('an unrelated edit does not satisfy an existing block', () {
    const withBlock = '## 0.2.0\n\n### Output changes\n- old.\n';
    final result = rule.problems(
      outputChanged: true,
      basePubspec: 'version: 0.1.0\n',
      pubspec: 'version: 0.2.0\n',
      baseChangelog: withBlock,
      changelog: '$withBlock\n### Fixed\n- Other.\n',
    );
    expect(result, [contains('add an entry')]);
  });

  test('a new bullet in an existing block counts', () {
    const withBlock = '## 0.2.0\n\n### Output changes\n- old.\n';
    final result = rule.problems(
      outputChanged: true,
      basePubspec: 'version: 0.1.0\n',
      pubspec: 'version: 0.2.0\n',
      baseChangelog: withBlock,
      changelog: '$withBlock- new.\n',
    );
    expect(result, isEmpty);
  });

  test('CRLF line ends and a blank line after the heading are accepted', () {
    const crlf = '## 0.2.0\r\n\r\n### Output changes\r\n\r\n* a.\r\n';
    expect(problems(changelog: crlf), isEmpty);
  });
}
