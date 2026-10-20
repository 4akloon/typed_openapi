@TestOn('!windows')
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/release_fixture.dart';

const _archive = 'typed_openapi-0.1.0-linux-x64.tar.gz';

List<String> _listing(String archive) {
  final result = Process.runSync('tar', ['-tzf', archive]);
  return (result.stdout as String).trim().split('\n')..sort();
}

void main() {
  group('package.sh', () {
    test('packs the executable and the licence with a matching checksum', () {
      final fixture = ReleaseFixture()..pack('linux-x64');
      final archive = p.join(fixture.releaseDirectory, _archive);
      expect(_listing(archive), ['LICENSE', 'typed_openapi']);
      final bytes = File(archive).readAsBytesSync();
      expect(
        File('$archive.sha256').readAsStringSync(),
        '${sha256.convert(bytes)}  $_archive\n',
      );
    });

    test('names the executable of a windows target typed_openapi.exe', () {
      final fixture = ReleaseFixture()..pack('windows-x64');
      final archive = p.join(
        fixture.releaseDirectory,
        'typed_openapi-0.1.0-windows-x64.tar.gz',
      );
      expect(_listing(archive), contains('typed_openapi.exe'));
    });

    test('with the wrong number of arguments exits 64', () {
      final result = ReleaseFixture().package(['linux-x64']);
      expect(result.exitCode, 64);
      expect(result.stderr, contains('usage: package.sh'));
    });
  });

  group('install.sh', () {
    test('prints the path of a verified executable that runs', () {
      final fixture = ReleaseFixture()..pack('linux-x64');
      final result = fixture.install('Linux', 'X64');
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final path = (result.stdout as String).trim();
      expect(path, p.join(fixture.installDirectory, 'typed_openapi'));
      expect(Process.runSync(path, ['--help']).stdout, contains('fake'));
    });

    test('refuses an archive that does not match SHA256SUMS', () {
      final fixture = ReleaseFixture()..pack('linux-x64');
      File(
        p.join(fixture.releaseDirectory, _archive),
      ).writeAsBytesSync([1, 2, 3], mode: FileMode.append);
      final result = fixture.install('Linux', 'X64');
      expect(result.exitCode, 1);
      expect(result.stderr, contains('does not match SHA256SUMS'));
    });

    test('with the wrong number of arguments exits 64', () {
      final result = Process.runSync(
        p.absolute('..', '..', 'action', 'install.sh'),
        ['0.1.0'],
      );
      expect(result.exitCode, 64);
    });

    test('refuses an archive that SHA256SUMS does not list', () {
      final fixture = ReleaseFixture()..pack('linux-x64');
      File(
        p.join(fixture.releaseDirectory, 'SHA256SUMS'),
      ).writeAsStringSync('');
      final result = fixture.install('Linux', 'X64');
      expect(result.exitCode, 1);
      expect(result.stderr, contains('is not in SHA256SUMS'));
    });

    test('refuses a target the release does not build', () {
      final fixture = ReleaseFixture()..pack('linux-x64');
      final result = fixture.install('Windows', 'ARM64');
      expect(result.exitCode, 1);
      expect(result.stderr, contains('windows-arm64'));
    });

    test('refuses an unknown architecture and a version that is a path', () {
      final fixture = ReleaseFixture()..pack('linux-x64');
      expect(fixture.install('Linux', 'ARM').exitCode, 1);
      final result = fixture.install('Linux', 'X64', version: '0.1.0/../x');
      expect(result.exitCode, 1);
      expect(result.stderr, contains('is not a version'));
    });
  });

  group('run.sh', () {
    test('runs lint with the preset, the level and the spec', () {
      final result = ReleaseFixture().run({
        'INPUT_COMMAND': 'lint',
        'INPUT_SPEC': 'openapi.json',
        'INPUT_PRESET': 'nestjs',
        'INPUT_FAIL_ON': 'warning',
      });
      expect(
        (result.stdout as String).trim(),
        'fake typed_openapi lint --format text --preset nestjs '
        '--fail-on warning -- openapi.json',
      );
    });

    test('runs check with the config', () {
      final result = ReleaseFixture().run({
        'INPUT_COMMAND': 'check',
        'INPUT_CONFIG': 'api/typed_openapi.yaml',
      });
      expect(
        (result.stdout as String).trim(),
        'fake typed_openapi check --format text '
        '--config api/typed_openapi.yaml',
      );
    });

    test('passes a spec path with spaces and shell characters as one word', () {
      final result = ReleaseFixture().run({
        'INPUT_COMMAND': 'lint',
        'INPUT_SPEC': r'my spec; echo $HOME.yaml',
      });
      expect(
        (result.stdout as String).trim(),
        r'fake typed_openapi lint --format text -- my spec; echo $HOME.yaml',
      );
    });

    test('puts -- before the spec and ignores empty preset and level', () {
      final result = ReleaseFixture().run({
        'INPUT_COMMAND': 'lint',
        'INPUT_SPEC': '-x.yaml',
        'INPUT_PRESET': '',
        'INPUT_FAIL_ON': '',
      });
      expect(
        (result.stdout as String).trim(),
        'fake typed_openapi lint --format text -- -x.yaml',
      );
    });

    test('refuses an option value that starts with a dash', () {
      final result = ReleaseFixture().run({
        'INPUT_COMMAND': 'lint',
        'INPUT_SPEC': 'a.yaml',
        'INPUT_PRESET': '--help',
      });
      expect(result.exitCode, 64);
      expect(result.stdout, startsWith('::error::'));
    });

    test('refuses lint without a spec and check with lint options', () {
      final fixture = ReleaseFixture();
      final lint = fixture.run({'INPUT_COMMAND': 'lint'});
      expect(lint.exitCode, 64);
      expect(lint.stdout, startsWith('::error::'));
      final check = fixture.run({
        'INPUT_COMMAND': 'check',
        'INPUT_FAIL_ON': 'error',
      });
      expect(check.exitCode, 64);
      expect((check.stdout as String).trim().split('\n'), hasLength(1));
    });
  });
}
