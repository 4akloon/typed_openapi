import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_list_reader.dart';
import 'package:typed_openapi_tool/src/corpus/expectation.dart';
import 'package:typed_openapi_tool/src/corpus/spec_source.dart';

const _hash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  const reader = CorpusListReader();

  test('reads a file entry and an archive entry in file order', () {
    final specs = reader.read('''
specs:
  pets:
    url: https://example.com/abc/openapi.yaml
    sha256: $_hash
    license: MIT
    expect: generate
  shop:
    archive: https://example.com/shop.tar.gz
    root: specs/store
    entry: openapi.yaml
    sha256: $_hash
    license: Apache-2.0
    expect: {check-errors: [TOA009, TOA001]}
''');
    expect([for (final s in specs) s.name], ['pets', 'shop']);
    final pets = specs.first;
    expect(pets.source, isA<FileSource>());
    expect(pets.source.entry, 'openapi.yaml');
    expect(pets.license, 'MIT');
    expect(pets.expectation, isA<Generates>());
    final shop = specs.last.source as ArchiveSource;
    expect(shop.root, 'specs/store');
    expect(shop.entry, 'openapi.yaml');
    expect((specs.last.expectation as CheckErrors).codes, [
      'TOA001',
      'TOA009',
    ]);
  });

  test('an entry without a lowercase sha256 is a FormatException', () {
    expect(
      () => reader.read('''
specs:
  pets: {url: https://example.com/a.yaml, sha256: ABC, license: MIT, expect: generate}
'''),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('pets has no lowercase sha256'),
        ),
      ),
    );
  });

  test('an unknown key or expectation is a FormatException', () {
    expect(
      () => reader.read('''
specs:
  pets: {url: u, sha256: $_hash, license: MIT, expect: generate, mode: x}
'''),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => reader.read('''
specs:
  pets: {url: u, sha256: $_hash, license: MIT, expect: compile}
'''),
      throwsA(isA<FormatException>()),
    );
  });
}
