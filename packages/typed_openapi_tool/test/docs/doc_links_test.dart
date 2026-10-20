@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:typed_openapi_test_support/typed_openapi_test_support.dart';

import '../helpers/doc_links.dart';

void main() {
  final root = p.normalize(p.absolute('..', '..'));

  test('no link of a guide or a README leads nowhere', () {
    final files = Directory(p.join(root, 'packages'))
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .where((f) => !f.path.contains('.dart_tool'))
        .where((f) {
          final parts = p.split(p.relative(f.path, from: root));
          return parts.contains('doc') ||
              p.basename(f.path).startsWith('README');
        })
        .toList();

    expect(files.length, greaterThan(20));
    expect(DocLinks(root).problems(files), isEmpty);
  });

  test('a missing file and a missing heading are found', () {
    final dir = TempDir();
    final a = File(
      dir.write(
        'a.md',
        '# One\n\n[ok](b.md#two) [file](c.md) [head](b.md#nope)\n',
      ),
    );
    final b = File(
      dir.write('b.md', '# Two\n\n```\n[in a fence](gone.md)\n```\n'),
    );

    expect(DocLinks(dir.path).problems([a, b]), [
      'a.md:3: c.md (no such file)',
      'a.md:3: b.md#nope (no such heading)',
    ]);
  });
}
