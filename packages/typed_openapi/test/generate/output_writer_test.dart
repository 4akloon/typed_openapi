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
  }) => OutputWriter(
    bag,
    const .new(),
    beforeInstall,
  ).write(client, files, inputs: 'in', protected: protected);

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
      dir.write('gen/pets/stale.dart', '// stale');
      final changes = write({'a.dart': '// changed', 'new.dart': '// n'})!;
      expect((changes.written, changes.unchanged, changes.deleted), (2, 0, 2));
      expect(
        Directory(client.output).listSync().map((e) => p.basename(e.path)),
        unorderedEquals(['.typed_openapi.json', 'a.dart', 'new.dart']),
      );
    });
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
      ).renameSync(p.join(parent, '.pets.typed_openapi-Ab12Cd-old'));
      dir.write('gen/.pets.typed_openapi-Ab12Cd/new.dart', '// half');
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
      dir.write('gen/.pets.typed_openapi-Zz9/a.dart', '// partial');
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
      dir.write('gen/.pets.typed_openapi-Ab12Cd-old/a.dart', '// older');
      write(old);
      expect(
        Directory(
          p.dirname(client.output),
        ).listSync().map((e) => p.basename(e.path)),
        ['pets'],
      );
      expect(bag.all.single.code, DiagnosticCode.outputRecovered);
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
      dir.write('gen/.other.typed_openapi-Ab12Cd/x.dart', '// other');
      dir.write('gen/.pets.typed_openapi-my_notes/x.dart', '// not a leftover');
      write(old);
      expect(
        File(
          p.join(dir.path, 'gen/.other.typed_openapi-Ab12Cd/x.dart'),
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
