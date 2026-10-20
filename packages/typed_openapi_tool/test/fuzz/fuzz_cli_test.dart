import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';
import 'package:typed_openapi_tool/src/fuzz/fuzz_cli.dart';

void main() {
  for (final args in const [
    ['--sample-every', '0'],
    ['--seeds', 'many'],
    ['--from', '-1'],
  ]) {
    test('${args.join(' ')} is a usage error', () async {
      final err = StringBuffer();
      final code = await FuzzCli(out: StringBuffer(), err: err).run(args);
      expect(code, 64);
      expect('$err', contains(args.first));
    });
  }

  test(
    'a work directory that is not ours is one line, exit 1, untouched',
    () async {
      final temp = TempDir();
      final pubspec = temp.write('pubspec.yaml', 'name: real_app');
      final err = StringBuffer();
      final code = await FuzzCli(
        out: StringBuffer(),
        err: err,
      ).run(['--seeds', '0', '--work', temp.path]);
      expect(code, 1);
      expect('$err'.trim().split('\n'), hasLength(1));
      expect('$err', contains('choose another --work directory'));
      expect(File(pubspec).existsSync(), isTrue);
    },
  );

  test('a work path that is a file is one line, exit 1', () async {
    final temp = TempDir();
    final file = temp.write('file', 'x');
    final err = StringBuffer();
    final code = await FuzzCli(
      out: StringBuffer(),
      err: err,
    ).run(['--seeds', '0', '--work', p.join(file, 'sub')]);
    expect(code, 1);
    expect('$err', isNot(contains('#0')));
  });
}
