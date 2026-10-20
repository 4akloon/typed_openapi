import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/generate/output_writer.dart';
import 'package:typed_openapi_core/typed_openapi_core.dart';

import '../helpers/output_writer_fixture.dart';

void main() {
  late OutputWriterFixture fx;

  setUp(() => fx = OutputWriterFixture());

  const old = {'a.dart': '// a', 'sub/b.dart': '// b'};

  group('one run at a time works on an output (the lock)', () {
    String lockPath() =>
        p.join(p.dirname(fx.client.output), '.pets.typed_openapi.lock');

    /// The text of a lock of [pid] on [host], as a run writes it.
    String lockOf({int? process, String? host}) => jsonEncode({
      'pid': process ?? pid,
      'host': host ?? Platform.localHostname,
      'id': 'other',
    });

    /// The pid of a process that has ended.
    int deadPid() => Process.runSync('true', const []).pid;

    test('a second run is refused while the first holds the lock', () {
      fx.write(old);
      final before = fx.everything();
      OutputChanges? second;
      final bag2 = DiagnosticBag();
      Map<String, String?>? duringFirst;
      Map<String, String?>? afterSecond;
      final first = fx.write(
        {'a.dart': '// first', 'sub/b.dart': '// first b'},
        beforeInstall: () {
          duringFirst = fx.everything();
          second = OutputWriter(bag2).write(
            fx.client,
            {'a.dart': '// second'},
            inputs: 'in',
          );
          afterSecond = fx.everything();
        },
      );
      expect(first, isNotNull);
      expect(fx.bag.all, isEmpty);
      expect(second, isNull);
      expect(bag2.all.single.code, DiagnosticCode.outputNotWritten);
      expect(bag2.all.single.message, contains('another typed_openapi run'));
      expect(bag2.all.single.message, contains('.pets.typed_openapi.lock'));
      expect(bag2.all.single.message, contains('Nothing was changed'));
      expect(bag2.all.single.fix, isNot(contains('--force')));
      // The second run touched nothing: not the staging tree of the first.
      expect(afterSecond, duringFirst);
      expect(
        duringFirst!.keys.where((k) => k.contains('typed_openapi-')),
        isNotEmpty,
      );
      expect(before, isNot(fx.everything()));
      expect(
        File(p.join(fx.client.output, 'a.dart')).readAsStringSync(),
        '// first',
      );
      expect(
        File(p.join(fx.client.output, 'sub/b.dart')).readAsStringSync(),
        '// first b',
      );
    });

    test('the lock is a file next to the output, gone after the run', () {
      String? during;
      fx.write(
        old,
        beforeInstall: () => during = File(lockPath()).readAsStringSync(),
      );
      final held = jsonDecode(during!) as Map<String, Object?>;
      expect(held['pid'], pid);
      expect(held['host'], Platform.localHostname);
      expect(File(lockPath()).existsSync(), isFalse);
      expect(fx.write(old), isNotNull);
    });

    test('a failed run releases the lock', () {
      fx.write(old);
      fx.write(
        {'a.dart': '// new'},
        beforeInstall: () => throw const FileSystemException('disk gone'),
      );
      expect(File(lockPath()).existsSync(), isFalse);
      expect(fx.write(old), isNotNull);
    });

    test('a refused output releases the lock', () {
      fx.dir.write('gen/pets/notes.txt', 'mine');
      expect(fx.write(old), isNull);
      expect(fx.bag.all.single.code, DiagnosticCode.outputNotOwned);
      expect(File(lockPath()).existsSync(), isFalse);
    });

    test('the lock of a process that is gone is taken over', () {
      fx.dir.write('gen/.pets.typed_openapi.lock', lockOf(process: deadPid()));
      expect(fx.write(old), isNotNull);
      final taken = fx.bag.all.single;
      expect(taken.code, DiagnosticCode.outputRecovered);
      expect(taken.severity, Severity.info);
      expect(taken.message, contains('process is gone'));
      expect(File(lockPath()).existsSync(), isFalse);
      expect(File(p.join(fx.client.output, 'a.dart')).existsSync(), isTrue);
    }, skip: Platform.isWindows ? 'no kill' : false);

    test('the lock of a process that runs is held, and nothing changes', () {
      fx.write(old);
      fx.dir.write('gen/.pets.typed_openapi.lock', lockOf());
      final before = fx.everything();
      expect(fx.write({'a.dart': '// new'}), isNull);
      expect(fx.bag.all.single.code, DiagnosticCode.outputNotWritten);
      expect(fx.bag.all.single.message, contains('process $pid'));
      expect(fx.bag.all.single.message, contains('which is running'));
      expect(fx.everything(), before);
    });

    test('neither --break-lock nor --force breaks the lock of a process that '
        'runs', () {
      fx.write(old);
      fx.dir.write('gen/.pets.typed_openapi.lock', lockOf());
      final before = fx.everything();
      for (final (force, breakLock) in [(false, true), (true, false)]) {
        fx.bag = DiagnosticBag();
        expect(
          fx.write({'a.dart': '// new'}, force: force, breakLock: breakLock),
          isNull,
        );
        expect(fx.bag.all.single.code, DiagnosticCode.outputNotWritten);
        expect(fx.bag.all.single.message, contains('which is running'));
        expect(fx.everything(), before);
      }
    });

    test('a lock that cannot be read or is from another host is held, and '
        '--break-lock takes it over, --force does not', () {
      fx.write(old);
      for (final text in ['', 'garbage', lockOf(host: 'some-other-host')]) {
        fx.bag = DiagnosticBag();
        fx.dir.write('gen/.pets.typed_openapi.lock', text);
        final before = fx.everything();
        expect(fx.write({'a.dart': '// new'}), isNull, reason: text);
        final held = fx.bag.all.single;
        expect(held.code, DiagnosticCode.outputNotWritten);
        expect(held.message, contains('cannot be told'));
        expect(held.fix, contains('--break-lock'));
        expect('${held.message} ${held.fix}', isNot(contains('--force')));
        expect(fx.everything(), before);
        fx.bag = DiagnosticBag();
        expect(fx.write({'a.dart': '// new'}, force: true), isNull);
        expect(fx.everything(), before);
        fx.bag = DiagnosticBag();
        expect(fx.write({'a.dart': '// new'}, breakLock: true), isNotNull);
        expect(fx.bag.all.single.code, DiagnosticCode.outputRecovered);
        expect(fx.bag.all.single.severity, Severity.info);
        expect(File(lockPath()).existsSync(), isFalse);
        fx.write(old);
      }
    });

    test('a held lock of a running process never suggests --force', () {
      fx.write(old);
      fx.dir.write('gen/.pets.typed_openapi.lock', lockOf());
      expect(fx.write({'a.dart': '// new'}), isNull);
      final held = fx.bag.all.single;
      expect('${held.message} ${held.fix}', isNot(contains('--force')));
      expect('${held.message} ${held.fix}', isNot(contains('--break-lock')));
    });

    test('breaking a lock replaces no foreign or modified file', () {
      fx.write(old);
      fx.dir
        ..write('gen/pets/NOTES.md', 'mine')
        ..write('gen/pets/a.dart', '// my edit')
        ..write(
          'gen/.pets.typed_openapi.lock',
          lockOf(host: 'old-hostname.local'),
        );
      final before = fx.everything();
      expect(fx.write({'a.dart': '// new'}, breakLock: true), isNull);
      final refused = fx.bag.all.firstWhere(
        (d) => d.code == DiagnosticCode.outputNotOwned,
      );
      expect(refused.message, contains('NOTES.md'));
      expect(refused.message, contains('a.dart'));
      // The lock went; the files are all there.
      expect(File(lockPath()).existsSync(), isFalse);
      final after = fx.everything()..remove('gen/.pets.typed_openapi.lock');
      expect(after, before..remove('gen/.pets.typed_openapi.lock'));
    });

    test('a system with no kill cannot tell, so the lock is held', () {
      fx.write(old);
      fx.dir.write('gen/.pets.typed_openapi.lock', lockOf(process: deadPid()));
      expect(
        fx.write(
          {'a.dart': '// new'},
          run: (executable, arguments) =>
              throw ProcessException(executable, arguments, 'not found'),
        ),
        isNull,
      );
      expect(fx.bag.all.single.message, contains('cannot be told'));
    }, skip: Platform.isWindows ? 'no kill' : false);

    test('recovery waits for the lock', () {
      fx.write(old);
      fx.dir.write('gen/.pets.typed_openapi-Zz9Zz9Zz/a.dart', '// partial');
      fx.dir.write('gen/.pets.typed_openapi.lock', lockOf());
      expect(fx.write(old), isNull);
      expect(
        File(
          p.join(fx.dir.path, 'gen/.pets.typed_openapi-Zz9Zz9Zz/a.dart'),
        ).existsSync(),
        isTrue,
      );
    });
  });
}
