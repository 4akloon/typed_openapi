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

  test('a repeated heading gets -1 and -2, and an in-page link is checked', () {
    final dir = TempDir();
    final a = File(
      dir.write(
        'a.md',
        '# Same\n\n## Same\n\n### Same\n\n'
            '[one](#same) [two](#same-1) [three](#same-2) [four](#same-3)\n',
      ),
    );

    expect(DocLinks(dir.path).problems([a]), [
      'a.md:7: #same-3 (no such heading)',
    ]);
  });

  test('a link with a scheme and a link in a code span are not read', () {
    final dir = TempDir();
    final a = File(
      dir.write(
        'a.md',
        '[web](https://example.com/gone.md) [mail](mailto:a@b.c)\n'
            'A code span: `[x](gone.md)`.\n',
      ),
    );

    expect(DocLinks(dir.path).problems([a]), isEmpty);
  });

  test('anchors drop markup and punctuation, and spaces become hyphens', () {
    final dir = TempDir();
    final a = File(
      dir.write(
        'a.md',
        '# A `code` Heading, with: punctuation!\n\n'
            '[ok](#a-code-heading-with-punctuation)\n',
      ),
    );

    expect(DocLinks(dir.path).problems([a]), isEmpty);
  });
}
