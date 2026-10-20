import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi_core/typed_openapi_core.dart';

import '../helpers/output_writer_fixture.dart';

void main() {
  late OutputWriterFixture fx;

  setUp(() => fx = OutputWriterFixture());

  const old = {'a.dart': '// a', 'sub/b.dart': '// b'};

  group('a run is atomic', () {
    test('a failure while writing keeps the previous tree and manifest', () {
      expect(fx.write(old), isNotNull);
      final before = fx.everything();
      // `c` is a file and a directory at once: the second write fails.
      final changes = fx.write({'a.dart': '// new', 'c': 'x', 'c/d.dart': 'y'});
      expect(changes, isNull);
      expect(fx.bag.all.single.code, DiagnosticCode.outputNotWritten);
      expect(fx.everything(), before);
    });

    test('a failed first run leaves nothing, and the next run works', () {
      expect(fx.write({'c': 'x', 'c/d.dart': 'y'}), isNull);
      expect(fx.bag.all.single.code, DiagnosticCode.outputNotWritten);
      expect(fx.everything(), isEmpty);
      expect(fx.write(old), isNotNull);
      expect(fx.bag.all, hasLength(1));
      expect(
        File(p.join(fx.client.output, 'sub/b.dart')).readAsStringSync(),
        '// b',
      );
    });

    test('a failure of the swap puts the old directory back', () {
      fx.write(old);
      final before = fx.everything();
      final changes = fx.write(
        {'a.dart': '// new'},
        beforeInstall: () =>
            throw const FileSystemException('disk gone', 'somewhere'),
      );
      expect(changes, isNull);
      expect(fx.bag.all.single.code, DiagnosticCode.outputNotWritten);
      expect(fx.everything(), before);
    });

    test('when the old directory cannot be put back, TOA831 names it', () {
      fx.write(old);
      final changes = fx.write(
        {'a.dart': '// new'},
        // Something takes the place of the output: neither the new tree nor
        // the backup can be renamed to it.
        beforeInstall: () => fx.dir.write('gen/pets/in_the_way.txt', 'x'),
      );
      expect(changes, isNull);
      final backups = Directory(
        p.dirname(fx.client.output),
      ).listSync().where((e) => p.basename(e.path).endsWith('-old')).toList();
      expect(backups, hasLength(1));
      final message = fx.bag.all.single.message;
      expect(fx.bag.all.single.code, DiagnosticCode.outputNotWritten);
      expect(message, contains(p.basename(backups.single.path)));
      expect(message, contains('the previous output'));
      expect(
        File(p.join(backups.single.path, 'sub/b.dart')).readAsStringSync(),
        '// b',
      );
    });

    test('a failure of the first swap leaves nothing', () {
      final changes = fx.write(
        old,
        beforeInstall: () => throw const FileSystemException('disk gone'),
      );
      expect(changes, isNull);
      expect(fx.everything(), isEmpty);
    });

    test('a directory that cannot be created is TOA831', () {
      fx.dir.write('gen', 'a file where the parent should be');
      expect(fx.write(old), isNull);
      expect(fx.bag.all.single.code, DiagnosticCode.outputNotWritten);
    });

    test('a run with nothing to change does not touch the directory', () {
      fx.write(old);
      final stat = File(p.join(fx.client.output, 'a.dart')).statSync().changed;
      final changes = fx.write(old)!;
      expect(
        (changes.written, changes.unchanged, changes.deleted),
        (0, 2, 0),
      );
      expect(
        File(p.join(fx.client.output, 'a.dart')).statSync().changed,
        stat,
      );
    });

    test('counts what changed', () {
      fx.write(old);
      final changes = fx.write({'a.dart': '// changed', 'new.dart': '// n'})!;
      expect((changes.written, changes.unchanged, changes.deleted), (2, 0, 1));
      expect(changes.forced, 0);
      expect(
        Directory(fx.client.output).listSync().map((e) => p.basename(e.path)),
        unorderedEquals(['.typed_openapi.json', 'a.dart', 'new.dart']),
      );
    });
  });

  group('the permissions of the output directory', () {
    int mode(String path) => FileStat.statSync(path).mode & 0xfff;

    test('a new directory gets the default mode, as one made normally', () {
      fx.write(old);
      final normal = Directory(p.join(fx.dir.path, 'gen', 'normal'))
        ..createSync();
      expect(mode(fx.client.output), mode(normal.path));
      expect(mode(p.join(fx.client.output, 'sub')), mode(normal.path));
    }, skip: Platform.isWindows ? 'no POSIX modes' : false);

    test('the mode of the previous directory is kept', () {
      fx.write(old);
      Process.runSync('chmod', ['775', fx.client.output]);
      final group = int.parse('775', radix: 8);
      expect(mode(fx.client.output), group);
      fx.write({'a.dart': '// changed'});
      expect(mode(fx.client.output), group);
    }, skip: Platform.isWindows ? 'no POSIX modes' : false);
  });

  group('the mode of the old directory', () {
    int mode(String path) => FileStat.statSync(path).mode & 0xfff;

    test('a read-only output (0555) is replaced and stays read-only', () {
      fx.write(old);
      Process.runSync('chmod', ['555', fx.client.output]);
      addTearDown(() => Process.runSync('chmod', ['755', fx.client.output]));
      final changes = fx.write({'a.dart': '// changed'});
      expect(changes, isNotNull, reason: '${fx.bag.all}');
      expect(fx.bag.all, isEmpty);
      expect(mode(fx.client.output), int.parse('555', radix: 8));
      expect(
        File(p.join(fx.client.output, 'a.dart')).readAsStringSync(),
        '// changed',
      );
      expect(
        Directory(
          p.dirname(fx.client.output),
        ).listSync().map((e) => p.basename(e.path)),
        ['pets'],
      );
    }, skip: Platform.isWindows ? 'no POSIX modes' : false);

    test('a missing chmod is TOA831, not a crash, and changes nothing', () {
      fx.write(old);
      Process.runSync('chmod', ['700', fx.client.output]);
      final before = fx.everything();
      final changes = fx.write(
        {'a.dart': '// changed'},
        run: (executable, arguments) =>
            throw ProcessException(executable, arguments, 'not found'),
      );
      expect(changes, isNull);
      expect(fx.bag.all.single.code, DiagnosticCode.outputNotWritten);
      expect(fx.bag.all.single.message, contains('mode'));
      expect(fx.bag.all.single.message, contains('chmod'));
      expect(fx.everything(), before);
    }, skip: Platform.isWindows ? 'no POSIX modes' : false);

    test('chmod is not run when the modes are the same', () {
      fx.write(old);
      final changes = fx.write(
        {'a.dart': '// changed'},
        run: (executable, arguments) =>
            throw ProcessException(executable, arguments, 'not found'),
      );
      expect(changes, isNotNull);
      expect(fx.bag.all, isEmpty);
    }, skip: Platform.isWindows ? 'no POSIX modes' : false);
  });

  test('an output directory that exists and is empty is used', () {
    Directory(fx.client.output).createSync(recursive: true);
    expect(fx.write(old), isNotNull);
    expect(fx.bag.all, isEmpty);
    expect(File(p.join(fx.client.output, 'a.dart')).existsSync(), isTrue);
  });
}
