import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/config/project_config.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/generate/output_writer.dart';

import '../helpers/temp_dir.dart';

void main() {
  late TempDir dir;
  late DiagnosticBag bag;
  late ClientConfig client;

  setUp(() {
    dir = TempDir();
    bag = DiagnosticBag();
    client = ClientConfig(
      name: 'pets',
      input: p.join(dir.path, 'spec.yaml'),
      output: p.join(dir.path, 'gen', 'pets'),
      lineWidth: 80,
    );
  });

  OutputChanges? write(
    Map<String, String> files, {
    List<String> protected = const [],
    void Function()? beforeInstall,
    bool force = false,
    ProcessResult Function(String, List<String>)? run,
  }) => OutputWriter.forTesting(bag, beforeInstall: beforeInstall, run: run)
      .write(
        client,
        files,
        inputs: 'in',
        protected: protected,
        force: force,
      );

  /// Every entry under the temp directory, sorted, with file content.
  Map<String, String?> everything() => {
    for (final e
        in dir.directory.listSync(recursive: true, followLinks: false).toList()
          ..sort((a, b) => a.path.compareTo(b.path)))
      p.relative(e.path, from: dir.path): e is File
          ? e.readAsStringSync()
          : null,
  };

  const old = {'a.dart': '// a', 'sub/b.dart': '// b'};

  group('a run is atomic', () {
    test('a failure while writing keeps the previous tree and manifest', () {
      expect(write(old), isNotNull);
      final before = everything();
      // `c` is a file and a directory at once: the second write fails.
      final changes = write({'a.dart': '// new', 'c': 'x', 'c/d.dart': 'y'});
      expect(changes, isNull);
      expect(bag.all.single.code, DiagnosticCode.outputNotWritten);
      expect(everything(), before);
    });

    test('a failed first run leaves nothing, and the next run works', () {
      expect(write({'c': 'x', 'c/d.dart': 'y'}), isNull);
      expect(bag.all.single.code, DiagnosticCode.outputNotWritten);
      expect(everything(), isEmpty);
      expect(write(old), isNotNull);
      expect(bag.all, hasLength(1));
      expect(
        File(p.join(client.output, 'sub/b.dart')).readAsStringSync(),
        '// b',
      );
    });

    test('a failure of the swap puts the old directory back', () {
      write(old);
      final before = everything();
      final changes = write(
        {'a.dart': '// new'},
        beforeInstall: () =>
            throw const FileSystemException('disk gone', 'somewhere'),
      );
      expect(changes, isNull);
      expect(bag.all.single.code, DiagnosticCode.outputNotWritten);
      expect(everything(), before);
    });

    test('when the old directory cannot be put back, TOA831 names it', () {
      write(old);
      final changes = write(
        {'a.dart': '// new'},
        // Something takes the place of the output: neither the new tree nor
        // the backup can be renamed to it.
        beforeInstall: () => dir.write('gen/pets/in_the_way.txt', 'x'),
      );
      expect(changes, isNull);
      final backups = Directory(
        p.dirname(client.output),
      ).listSync().where((e) => p.basename(e.path).endsWith('-old')).toList();
      expect(backups, hasLength(1));
      final message = bag.all.single.message;
      expect(bag.all.single.code, DiagnosticCode.outputNotWritten);
      expect(message, contains(p.basename(backups.single.path)));
      expect(message, contains('the previous output'));
      expect(
        File(p.join(backups.single.path, 'sub/b.dart')).readAsStringSync(),
        '// b',
      );
    });

    test('a failure of the first swap leaves nothing', () {
      final changes = write(
        old,
        beforeInstall: () => throw const FileSystemException('disk gone'),
      );
      expect(changes, isNull);
      expect(everything(), isEmpty);
    });

    test('a directory that cannot be created is TOA831', () {
      dir.write('gen', 'a file where the parent should be');
      expect(write(old), isNull);
      expect(bag.all.single.code, DiagnosticCode.outputNotWritten);
    });

    test('a run with nothing to change does not touch the directory', () {
      write(old);
      final stat = File(p.join(client.output, 'a.dart')).statSync().changed;
      final changes = write(old)!;
      expect(
        (changes.written, changes.unchanged, changes.deleted),
        (0, 2, 0),
      );
      expect(
        File(p.join(client.output, 'a.dart')).statSync().changed,
        stat,
      );
    });

    test('counts what changed', () {
      write(old);
      final changes = write({'a.dart': '// changed', 'new.dart': '// n'})!;
      expect((changes.written, changes.unchanged, changes.deleted), (2, 0, 1));
      expect(changes.forced, 0);
      expect(
        Directory(client.output).listSync().map((e) => p.basename(e.path)),
        unorderedEquals(['.typed_openapi.json', 'a.dart', 'new.dart']),
      );
    });
  });

  group('the permissions of the output directory', () {
    int mode(String path) => FileStat.statSync(path).mode & 0xfff;

    test('a new directory gets the default mode, as one made normally', () {
      write(old);
      final normal = Directory(p.join(dir.path, 'gen', 'normal'))..createSync();
      expect(mode(client.output), mode(normal.path));
      expect(mode(p.join(client.output, 'sub')), mode(normal.path));
    }, skip: Platform.isWindows ? 'no POSIX modes' : false);

    test('the mode of the previous directory is kept', () {
      write(old);
      Process.runSync('chmod', ['775', client.output]);
      final group = int.parse('775', radix: 8);
      expect(mode(client.output), group);
      write({'a.dart': '// changed'});
      expect(mode(client.output), group);
    }, skip: Platform.isWindows ? 'no POSIX modes' : false);
  });

  group('one run at a time works on an output (the lock)', () {
    String lockPath() =>
        p.join(p.dirname(client.output), '.pets.typed_openapi.lock');

    /// The text of a lock of [pid] on [host], as a run writes it.
    String lockOf({int? process, String? host}) => jsonEncode({
      'pid': process ?? pid,
      'host': host ?? Platform.localHostname,
      'id': 'other',
    });

    /// The pid of a process that has ended.
    int deadPid() => Process.runSync('true', const []).pid;

    test('a second run is refused while the first holds the lock', () {
      write(old);
      final before = everything();
      OutputChanges? second;
      final bag2 = DiagnosticBag();
      Map<String, String?>? duringFirst;
      Map<String, String?>? afterSecond;
      final first = write(
        {'a.dart': '// first', 'sub/b.dart': '// first b'},
        beforeInstall: () {
          duringFirst = everything();
          second = OutputWriter(bag2).write(
            client,
            {'a.dart': '// second'},
            inputs: 'in',
          );
          afterSecond = everything();
        },
      );
      expect(first, isNotNull);
      expect(bag.all, isEmpty);
      expect(second, isNull);
      expect(bag2.all.single.code, DiagnosticCode.outputNotWritten);
      expect(bag2.all.single.message, contains('another typed_openapi run'));
      expect(bag2.all.single.message, contains('.pets.typed_openapi.lock'));
      expect(bag2.all.single.message, contains('Nothing was changed'));
      expect(bag2.all.single.fix, contains('--force'));
      // The second run touched nothing: not the staging tree of the first.
      expect(afterSecond, duringFirst);
      expect(
        duringFirst!.keys.where((k) => k.contains('typed_openapi-')),
        isNotEmpty,
      );
      expect(before, isNot(everything()));
      expect(
        File(p.join(client.output, 'a.dart')).readAsStringSync(),
        '// first',
      );
      expect(
        File(p.join(client.output, 'sub/b.dart')).readAsStringSync(),
        '// first b',
      );
    });

    test('the lock is a file next to the output, gone after the run', () {
      String? during;
      write(
        old,
        beforeInstall: () => during = File(lockPath()).readAsStringSync(),
      );
      final held = jsonDecode(during!) as Map<String, Object?>;
      expect(held['pid'], pid);
      expect(held['host'], Platform.localHostname);
      expect(File(lockPath()).existsSync(), isFalse);
      expect(write(old), isNotNull);
    });

    test('a failed run releases the lock', () {
      write(old);
      write(
        {'a.dart': '// new'},
        beforeInstall: () => throw const FileSystemException('disk gone'),
      );
      expect(File(lockPath()).existsSync(), isFalse);
      expect(write(old), isNotNull);
    });

    test('a refused output releases the lock', () {
      dir.write('gen/pets/notes.txt', 'mine');
      expect(write(old), isNull);
      expect(bag.all.single.code, DiagnosticCode.outputNotOwned);
      expect(File(lockPath()).existsSync(), isFalse);
    });

    test('the lock of a process that is gone is taken over', () {
      dir.write('gen/.pets.typed_openapi.lock', lockOf(process: deadPid()));
      expect(write(old), isNotNull);
      final taken = bag.all.single;
      expect(taken.code, DiagnosticCode.outputRecovered);
      expect(taken.severity, Severity.info);
      expect(taken.message, contains('process is gone'));
      expect(File(lockPath()).existsSync(), isFalse);
      expect(File(p.join(client.output, 'a.dart')).existsSync(), isTrue);
    }, skip: Platform.isWindows ? 'no kill' : false);

    test('the lock of a process that runs is held, and nothing changes', () {
      write(old);
      dir.write('gen/.pets.typed_openapi.lock', lockOf());
      final before = everything();
      expect(write({'a.dart': '// new'}), isNull);
      expect(bag.all.single.code, DiagnosticCode.outputNotWritten);
      expect(bag.all.single.message, contains('process $pid'));
      expect(bag.all.single.message, contains('which is running'));
      expect(everything(), before);
    });

    test('--force breaks the lock of a process that runs', () {
      write(old);
      dir.write('gen/.pets.typed_openapi.lock', lockOf());
      expect(write({'a.dart': '// new'}, force: true), isNotNull);
      expect(bag.all.single.code, DiagnosticCode.outputRecovered);
      expect(bag.all.single.message, contains('--force breaks it'));
      expect(
        File(p.join(client.output, 'a.dart')).readAsStringSync(),
        '// new',
      );
      expect(File(lockPath()).existsSync(), isFalse);
    });

    test('a lock that cannot be read or is from another host is held', () {
      write(old);
      for (final text in ['', 'garbage', lockOf(host: 'some-other-host')]) {
        bag = DiagnosticBag();
        dir.write('gen/.pets.typed_openapi.lock', text);
        final before = everything();
        expect(write({'a.dart': '// new'}), isNull, reason: text);
        expect(bag.all.single.code, DiagnosticCode.outputNotWritten);
        expect(bag.all.single.message, contains('cannot be told'));
        expect(everything(), before);
        expect(write({'a.dart': '// new'}, force: true), isNotNull);
        bag = DiagnosticBag();
        write(old, force: true);
      }
    });

    test('a system with no kill cannot tell, so the lock is held', () {
      write(old);
      dir.write('gen/.pets.typed_openapi.lock', lockOf(process: deadPid()));
      expect(
        write(
          {'a.dart': '// new'},
          run: (executable, arguments) =>
              throw ProcessException(executable, arguments, 'not found'),
        ),
        isNull,
      );
      expect(bag.all.single.message, contains('cannot be told'));
    }, skip: Platform.isWindows ? 'no kill' : false);

    test('recovery waits for the lock', () {
      write(old);
      dir.write('gen/.pets.typed_openapi-Zz9Zz9Zz/a.dart', '// partial');
      dir.write('gen/.pets.typed_openapi.lock', lockOf());
      expect(write(old), isNull);
      expect(
        File(
          p.join(dir.path, 'gen/.pets.typed_openapi-Zz9Zz9Zz/a.dart'),
        ).existsSync(),
        isTrue,
      );
    });
  });

  group('the mode of the old directory', () {
    int mode(String path) => FileStat.statSync(path).mode & 0xfff;

    test('a read-only output (0555) is replaced and stays read-only', () {
      write(old);
      Process.runSync('chmod', ['555', client.output]);
      addTearDown(() => Process.runSync('chmod', ['755', client.output]));
      final changes = write({'a.dart': '// changed'});
      expect(changes, isNotNull, reason: '${bag.all}');
      expect(bag.all, isEmpty);
      expect(mode(client.output), int.parse('555', radix: 8));
      expect(
        File(p.join(client.output, 'a.dart')).readAsStringSync(),
        '// changed',
      );
      expect(
        Directory(
          p.dirname(client.output),
        ).listSync().map((e) => p.basename(e.path)),
        ['pets'],
      );
    }, skip: Platform.isWindows ? 'no POSIX modes' : false);

    test('a missing chmod is TOA831, not a crash, and changes nothing', () {
      write(old);
      Process.runSync('chmod', ['700', client.output]);
      final before = everything();
      final changes = write(
        {'a.dart': '// changed'},
        run: (executable, arguments) =>
            throw ProcessException(executable, arguments, 'not found'),
      );
      expect(changes, isNull);
      expect(bag.all.single.code, DiagnosticCode.outputNotWritten);
      expect(bag.all.single.message, contains('mode'));
      expect(bag.all.single.message, contains('chmod'));
      expect(everything(), before);
    }, skip: Platform.isWindows ? 'no POSIX modes' : false);

    test('chmod is not run when the modes are the same', () {
      write(old);
      final changes = write(
        {'a.dart': '// changed'},
        run: (executable, arguments) =>
            throw ProcessException(executable, arguments, 'not found'),
      );
      expect(changes, isNotNull);
      expect(bag.all, isEmpty);
    }, skip: Platform.isWindows ? 'no POSIX modes' : false);
  });

  group('the leftovers of a killed run', () {
    /// Simulates a process killed between the two renames of the swap: the
    /// old tree is the backup, the new one is complete in its directory, and
    /// the output does not exist.
    void killBetweenRenames() {
      write(old);
      final parent = p.dirname(client.output);
      Directory(
        client.output,
      ).renameSync(p.join(parent, '.pets.typed_openapi-Ab12Cd34-old'));
      dir.write('gen/.pets.typed_openapi-Ab12Cd34/new.dart', '// half');
    }

    test('the backup is restored and the temp directory removed', () {
      killBetweenRenames();
      final changes = write(old)!;
      expect((changes.written, changes.unchanged, changes.deleted), (0, 2, 0));
      expect(
        File(p.join(client.output, 'sub/b.dart')).readAsStringSync(),
        '// b',
      );
      expect(
        Directory(
          p.dirname(client.output),
        ).listSync().map((e) => p.basename(e.path)),
        ['pets'],
      );
      final recovered = bag.all.single;
      expect(recovered.code, DiagnosticCode.outputRecovered);
      expect(recovered.severity, Severity.info);
      expect(recovered.message, contains('restored'));
    });

    test('a run killed while the temp tree was written is cleaned', () {
      write(old);
      dir.write('gen/.pets.typed_openapi-Zz9Zz9Zz/a.dart', '// partial');
      write(old);
      expect(
        Directory(
          p.dirname(client.output),
        ).listSync().map((e) => p.basename(e.path)),
        ['pets'],
      );
      expect(bag.all.single.code, DiagnosticCode.outputRecovered);
      expect(bag.all.single.message, isNot(contains('restored')));
    });

    test('a backup left after the new tree was installed is removed', () {
      write(old);
      dir.write('gen/.pets.typed_openapi-Ab12Cd34-old/a.dart', '// older');
      write(old);
      expect(
        Directory(
          p.dirname(client.output),
        ).listSync().map((e) => p.basename(e.path)),
        ['pets'],
      );
      expect(bag.all.single.code, DiagnosticCode.outputRecovered);
    });

    test('a backup is kept while the output is not a generated tree', () {
      write(old);
      Directory(client.output).renameSync(
        p.join(p.dirname(client.output), '.pets.typed_openapi-Ab12Cd34-old'),
      );
      dir.write('gen/pets/in_the_way.txt', 'x');
      expect(write(old), isNull);
      expect(bag.all.single.code, DiagnosticCode.outputNotOwned);
      expect(
        File(
          p.join(dir.path, 'gen/.pets.typed_openapi-Ab12Cd34-old/a.dart'),
        ).readAsStringSync(),
        '// a',
      );
    });

    test('the restored tree is then updated by the run', () {
      killBetweenRenames();
      final changes = write({'a.dart': '// changed'})!;
      expect((changes.written, changes.deleted), (1, 1));
      expect(
        File(p.join(client.output, 'a.dart')).readAsStringSync(),
        '// changed',
      );
      expect(File(p.join(client.output, 'sub/b.dart')).existsSync(), isFalse);
    });

    test('directories of other outputs and clean runs are left alone', () {
      write(old);
      dir.write('gen/.other.typed_openapi-Ab12Cd34/x.dart', '// other');
      dir.write('gen/.pets.typed_openapi-my_notes/x.dart', '// not a leftover');
      write(old);
      expect(
        File(
          p.join(dir.path, 'gen/.other.typed_openapi-Ab12Cd34/x.dart'),
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          p.join(dir.path, 'gen/.pets.typed_openapi-my_notes/x.dart'),
        ).existsSync(),
        isTrue,
      );
      expect(bag.all, isEmpty);
    });

    test('a clean run reports nothing', () {
      write(old);
      write(old);
      expect(bag.all, isEmpty);
    });
  });

  group('recovery never touches an input of the run', () {
    List<String> names() => Directory(
      p.dirname(client.output),
    ).listSync().map((e) => p.basename(e.path)).toList()..sort();

    test('a leftover that holds the spec is neither deleted nor restored', () {
      write(old);
      // The spec of the client lives in a directory named like a leftover.
      final spec = dir.write(
        'gen/.pets.typed_openapi-specs123/pets.yaml',
        'openapi: 3.1.0\n',
      );
      final changes = write({'a.dart': '// new'}, protected: [spec]);
      expect(changes, isNotNull);
      expect(File(spec).readAsStringSync(), 'openapi: 3.1.0\n');
      expect(bag.all, isEmpty);
      expect(names(), ['.pets.typed_openapi-specs123', 'pets']);
    });

    test('a backup that holds an input is not restored, nor removed', () {
      write(old);
      final parent = p.dirname(client.output);
      Directory(client.output).renameSync(
        p.join(parent, '.pets.typed_openapi-Ab12Cd34-old'),
      );
      final spec = dir.write(
        'gen/.pets.typed_openapi-Ab12Cd34-old/spec.yaml',
        'openapi: 3.1.0\n',
      );
      expect(write(old, protected: [spec]), isNotNull);
      expect(File(spec).readAsStringSync(), 'openapi: 3.1.0\n');
      expect(bag.all, isEmpty);
      // The output was written afresh, not from the backup.
      expect(File(p.join(client.output, 'a.dart')).existsSync(), isTrue);
      expect(
        File(
          p.join(parent, '.pets.typed_openapi-Ab12Cd34-old/a.dart'),
        ).existsSync(),
        isTrue,
      );
    });

    test('a hard link to an input inside a leftover keeps the leftover', () {
      write(old);
      final spec = dir.write('spec.yaml', 'openapi: 3.1.0\n');
      dir.hardLink('gen/.pets.typed_openapi-Zz9Zz9Zz/copy.yaml', 'spec.yaml');
      expect(write(old, protected: [spec]), isNotNull);
      expect(
        File(
          p.join(dir.path, 'gen/.pets.typed_openapi-Zz9Zz9Zz/copy.yaml'),
        ).existsSync(),
        isTrue,
      );
      expect(bag.all, isEmpty);
    }, skip: Platform.isWindows ? 'no ln' : false);

    test('a leftover is kept when the output is refused', () {
      write(old);
      dir
        ..write('gen/pets/notes.txt', 'mine')
        ..write('gen/.pets.typed_openapi-Zz9Zz9Zz/a.dart', '// partial');
      expect(write(old), isNull);
      expect(bag.all.single.code, DiagnosticCode.outputNotOwned);
      expect(
        File(
          p.join(dir.path, 'gen/.pets.typed_openapi-Zz9Zz9Zz/a.dart'),
        ).existsSync(),
        isTrue,
      );
    });

    test(
      'a backup is not restored when the restored tree would be refused',
      () {
        write(old);
        final parent = p.dirname(client.output);
        Directory(client.output).renameSync(
          p.join(parent, '.pets.typed_openapi-Ab12Cd34-old'),
        );
        dir.write('gen/.pets.typed_openapi-Ab12Cd34-old/notes.txt', 'mine');
        expect(write(old), isNull);
        expect(bag.all.single.code, DiagnosticCode.outputNotOwned);
        expect(bag.all.single.message, contains('the backup'));
        expect(Directory(client.output).existsSync(), isFalse);
        expect(
          File(
            p.join(parent, '.pets.typed_openapi-Ab12Cd34-old/notes.txt'),
          ).existsSync(),
          isTrue,
        );
      },
    );

    test('only names of exactly eight characters are leftovers', () {
      write(old);
      dir.write('gen/.pets.typed_openapi-Zz9/x.dart', '// mine');
      dir.write('gen/.pets.typed_openapi-Zz9Zz9Zz1/x.dart', '// mine');
      write(old);
      expect(bag.all, isEmpty);
      expect(names(), [
        '.pets.typed_openapi-Zz9',
        '.pets.typed_openapi-Zz9Zz9Zz1',
        'pets',
      ]);
    });
  });

  group('a file that is an input of the run is never deleted', () {
    test('a hard link to it inside the output', () {
      write(old);
      final spec = dir.write('spec.yaml', 'openapi: 3.1.0\n');
      dir.hardLink('gen/pets/copy.yaml', 'spec.yaml');
      final before = everything();
      expect(write(old, protected: [spec]), isNull);
      expect(bag.all.single.code, DiagnosticCode.outputNotOwned);
      expect(bag.all.single.message, contains('the input'));
      expect(everything(), before);
    });
  });

  test('an output directory that exists and is empty is used', () {
    Directory(client.output).createSync(recursive: true);
    expect(write(old), isNotNull);
    expect(bag.all, isEmpty);
    expect(File(p.join(client.output, 'a.dart')).existsSync(), isTrue);
  });
}
