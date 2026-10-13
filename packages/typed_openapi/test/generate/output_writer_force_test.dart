import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';

import '../helpers/output_writer_fixture.dart';

void main() {
  late OutputWriterFixture fx;

  setUp(() => fx = OutputWriterFixture());

  const old = {'a.dart': '// a', 'sub/b.dart': '// b'};

  group('--force lists what it replaces (TOA833)', () {
    List<String> replaced() => [
      for (final d in fx.bag.all)
        if (d.code == DiagnosticCode.outputFileReplaced) d.message,
    ];

    test('every foreign and modified file is named, as info', () {
      fx.write(old);
      fx.dir
        ..write('gen/pets/NOTES.md', 'mine')
        ..write('gen/pets/sub/deep.txt', 'mine')
        ..write('gen/pets/a.dart', '// my edit');
      final changes = fx.write({'a.dart': '// new'}, force: true)!;
      expect(changes.forced, 3);
      for (final d in fx.bag.all) {
        expect(d.code, DiagnosticCode.outputFileReplaced);
        expect(d.severity, Severity.info);
      }
      final lines = replaced();
      expect(lines, hasLength(3));
      expect(lines.join('\n'), contains('NOTES.md'));
      expect(lines.join('\n'), contains('sub/deep.txt'));
      final edited = lines.singleWhere((m) => m.contains('a.dart'));
      expect(edited, contains('changed since'));
      expect(edited, contains('--force'));
      expect(File(p.join(fx.client.output, 'NOTES.md')).existsSync(), isFalse);
    });

    test('a directory with no manifest: every file is named', () {
      fx.dir
        ..write('gen/pets/one.txt', 'mine')
        ..write('gen/pets/two.txt', 'mine');
      expect(fx.write(old, force: true), isNotNull);
      final lines = replaced();
      expect(lines, hasLength(2));
      expect(lines.join('\n'), allOf(contains('one.txt'), contains('two.txt')));
    });

    test('nothing is listed when nothing is replaced, or the run fails', () {
      fx.write(old);
      expect(fx.write(old, force: true), isNotNull);
      expect(fx.bag.all, isEmpty);
      fx.dir.write('gen/pets/NOTES.md', 'mine');
      fx.write(
        {'a.dart': '// new'},
        force: true,
        beforeInstall: () => throw const FileSystemException('disk gone'),
      );
      expect(replaced(), isEmpty);
    });
  });

  group('a file that is an input of the run is never deleted', () {
    test('a hard link to it inside the output', () {
      fx.write(old);
      final spec = fx.dir.write('spec.yaml', 'openapi: 3.1.0\n');
      fx.dir.hardLink('gen/pets/copy.yaml', 'spec.yaml');
      final before = fx.everything();
      expect(fx.write(old, protected: [spec]), isNull);
      expect(fx.bag.all.single.code, DiagnosticCode.outputNotOwned);
      expect(fx.bag.all.single.message, contains('the input'));
      expect(fx.everything(), before);
    });
  });
}
