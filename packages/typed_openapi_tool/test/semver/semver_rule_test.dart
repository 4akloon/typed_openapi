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
}
