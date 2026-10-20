import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi_core/typed_openapi_core.dart';

import '../helpers/output_writer_fixture.dart';

void main() {
  late OutputWriterFixture fx;

  setUp(() => fx = OutputWriterFixture());

  const old = {'a.dart': '// a', 'sub/b.dart': '// b'};

  group('the leftovers of a killed run', () {
    /// Simulates a process killed between the two renames of the swap: the
    /// old tree is the backup, the new one is complete in its directory, and
    /// the output does not exist.
    void killBetweenRenames() {
      fx.write(old);
      final parent = p.dirname(fx.client.output);
      Directory(
        fx.client.output,
      ).renameSync(p.join(parent, '.pets.typed_openapi-Ab12Cd34-old'));
      fx.dir.write('gen/.pets.typed_openapi-Ab12Cd34/new.dart', '// half');
    }

    test('the backup is restored and the temp directory removed', () {
      killBetweenRenames();
      final changes = fx.write(old)!;
      expect((changes.written, changes.unchanged, changes.deleted), (0, 2, 0));
      expect(
        File(p.join(fx.client.output, 'sub/b.dart')).readAsStringSync(),
        '// b',
      );
      expect(
        Directory(
          p.dirname(fx.client.output),
        ).listSync().map((e) => p.basename(e.path)),
        ['pets'],
      );
      final recovered = fx.bag.all.single;
      expect(recovered.code, DiagnosticCode.outputRecovered);
      expect(recovered.severity, Severity.info);
      expect(recovered.message, contains('restored'));
    });

    test('a run killed while the temp tree was written is cleaned', () {
      fx.write(old);
      fx.dir.write('gen/.pets.typed_openapi-Zz9Zz9Zz/a.dart', '// partial');
      fx.write(old);
      expect(
        Directory(
          p.dirname(fx.client.output),
        ).listSync().map((e) => p.basename(e.path)),
        ['pets'],
      );
      expect(fx.bag.all.single.code, DiagnosticCode.outputRecovered);
      expect(fx.bag.all.single.message, isNot(contains('restored')));
    });

    test('a backup left after the new tree was installed is removed', () {
      fx.write(old);
      fx.dir.write('gen/.pets.typed_openapi-Ab12Cd34-old/a.dart', '// older');
      fx.write(old);
      expect(
        Directory(
          p.dirname(fx.client.output),
        ).listSync().map((e) => p.basename(e.path)),
        ['pets'],
      );
      expect(fx.bag.all.single.code, DiagnosticCode.outputRecovered);
    });

    test('a backup is kept while the output is not a generated tree', () {
      fx.write(old);
      Directory(fx.client.output).renameSync(
        p.join(p.dirname(fx.client.output), '.pets.typed_openapi-Ab12Cd34-old'),
      );
      fx.dir.write('gen/pets/in_the_way.txt', 'x');
      expect(fx.write(old), isNull);
      expect(fx.bag.all.single.code, DiagnosticCode.outputNotOwned);
      expect(
        File(
          p.join(fx.dir.path, 'gen/.pets.typed_openapi-Ab12Cd34-old/a.dart'),
        ).readAsStringSync(),
        '// a',
      );
    });

    test('the restored tree is then updated by the run', () {
      killBetweenRenames();
      final changes = fx.write({'a.dart': '// changed'})!;
      expect((changes.written, changes.deleted), (1, 1));
      expect(
        File(p.join(fx.client.output, 'a.dart')).readAsStringSync(),
        '// changed',
      );
      expect(
        File(p.join(fx.client.output, 'sub/b.dart')).existsSync(),
        isFalse,
      );
    });

    test('directories of other outputs and clean runs are left alone', () {
      fx.write(old);
      fx.dir.write('gen/.other.typed_openapi-Ab12Cd34/x.dart', '// other');
      fx.dir.write(
        'gen/.pets.typed_openapi-my_notes/x.dart',
        '// not a leftover',
      );
      fx.write(old);
      expect(
        File(
          p.join(fx.dir.path, 'gen/.other.typed_openapi-Ab12Cd34/x.dart'),
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          p.join(fx.dir.path, 'gen/.pets.typed_openapi-my_notes/x.dart'),
        ).existsSync(),
        isTrue,
      );
      expect(fx.bag.all, isEmpty);
    });

    test('a clean run reports nothing', () {
      fx.write(old);
      fx.write(old);
      expect(fx.bag.all, isEmpty);
    });
  });

  group('recovery never touches an input of the run', () {
    List<String> names() => Directory(
      p.dirname(fx.client.output),
    ).listSync().map((e) => p.basename(e.path)).toList()..sort();

    test('a leftover that holds the spec is neither deleted nor restored', () {
      fx.write(old);
      // The spec of the fx.client lives in a directory named like a leftover.
      final spec = fx.dir.write(
        'gen/.pets.typed_openapi-specs123/pets.yaml',
        'openapi: 3.1.0\n',
      );
      final changes = fx.write({'a.dart': '// new'}, protected: [spec]);
      expect(changes, isNotNull);
      expect(File(spec).readAsStringSync(), 'openapi: 3.1.0\n');
      expect(fx.bag.all, isEmpty);
      expect(names(), ['.pets.typed_openapi-specs123', 'pets']);
    });

    test('a backup that holds an input is not restored, nor removed', () {
      fx.write(old);
      final parent = p.dirname(fx.client.output);
      Directory(fx.client.output).renameSync(
        p.join(parent, '.pets.typed_openapi-Ab12Cd34-old'),
      );
      final spec = fx.dir.write(
        'gen/.pets.typed_openapi-Ab12Cd34-old/spec.yaml',
        'openapi: 3.1.0\n',
      );
      expect(fx.write(old, protected: [spec]), isNotNull);
      expect(File(spec).readAsStringSync(), 'openapi: 3.1.0\n');
      expect(fx.bag.all, isEmpty);
      // The output was written afresh, not from the backup.
      expect(File(p.join(fx.client.output, 'a.dart')).existsSync(), isTrue);
      expect(
        File(
          p.join(parent, '.pets.typed_openapi-Ab12Cd34-old/a.dart'),
        ).existsSync(),
        isTrue,
      );
    });

    test('a hard link to an input inside a leftover keeps the leftover', () {
      fx.write(old);
      final spec = fx.dir.write('spec.yaml', 'openapi: 3.1.0\n');
      fx.dir.hardLink(
        'gen/.pets.typed_openapi-Zz9Zz9Zz/copy.yaml',
        'spec.yaml',
      );
      expect(fx.write(old, protected: [spec]), isNotNull);
      expect(
        File(
          p.join(fx.dir.path, 'gen/.pets.typed_openapi-Zz9Zz9Zz/copy.yaml'),
        ).existsSync(),
        isTrue,
      );
      expect(fx.bag.all, isEmpty);
    }, skip: Platform.isWindows ? 'no ln' : false);

    test('a leftover is kept when the output is refused', () {
      fx.write(old);
      fx.dir
        ..write('gen/pets/notes.txt', 'mine')
        ..write('gen/.pets.typed_openapi-Zz9Zz9Zz/a.dart', '// partial');
      expect(fx.write(old), isNull);
      expect(fx.bag.all.single.code, DiagnosticCode.outputNotOwned);
      expect(
        File(
          p.join(fx.dir.path, 'gen/.pets.typed_openapi-Zz9Zz9Zz/a.dart'),
        ).existsSync(),
        isTrue,
      );
    });

    test(
      'a backup is not restored when the restored tree would be refused',
      () {
        fx.write(old);
        final parent = p.dirname(fx.client.output);
        Directory(fx.client.output).renameSync(
          p.join(parent, '.pets.typed_openapi-Ab12Cd34-old'),
        );
        fx.dir.write('gen/.pets.typed_openapi-Ab12Cd34-old/notes.txt', 'mine');
        expect(fx.write(old), isNull);
        expect(fx.bag.all.single.code, DiagnosticCode.outputNotOwned);
        expect(fx.bag.all.single.message, contains('the backup'));
        expect(Directory(fx.client.output).existsSync(), isFalse);
        expect(
          File(
            p.join(parent, '.pets.typed_openapi-Ab12Cd34-old/notes.txt'),
          ).existsSync(),
          isTrue,
        );
      },
    );

    test('only names of exactly eight characters are leftovers', () {
      fx.write(old);
      fx.dir.write('gen/.pets.typed_openapi-Zz9/x.dart', '// mine');
      fx.dir.write('gen/.pets.typed_openapi-Zz9Zz9Zz1/x.dart', '// mine');
      fx.write(old);
      expect(fx.bag.all, isEmpty);
      expect(names(), [
        '.pets.typed_openapi-Zz9',
        '.pets.typed_openapi-Zz9Zz9Zz1',
        'pets',
      ]);
    });
  });
}
