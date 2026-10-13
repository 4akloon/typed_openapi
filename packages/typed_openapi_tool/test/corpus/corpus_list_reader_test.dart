import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_exception.dart';
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

  test('an entry without a lowercase sha256 is a CorpusException', () {
    expect(
      () => reader.read('''
specs:
  pets: {url: https://example.com/a.yaml, sha256: ABC, license: MIT, expect: generate}
'''),
      throwsA(
        isA<CorpusException>().having(
          (e) => e.message,
          'message',
          contains('pets has no lowercase sha256'),
        ),
      ),
    );
  });

  test('an unknown key or expectation is a CorpusException', () {
    expect(
      () => reader.read('''
specs:
  pets: {url: u, sha256: $_hash, license: MIT, expect: generate, mode: x}
'''),
      throwsA(isA<CorpusException>()),
    );
    expect(
      () => reader.read('''
specs:
  pets: {url: u, sha256: $_hash, license: MIT, expect: compile}
'''),
      throwsA(isA<CorpusException>()),
    );
  });

  test('reads the pinned schemas, and none when the file has no map', () {
    final schemas = reader.readSchemas('''
specs: {}
schemas:
  sarif_schema:
    url: https://example.com/abc/sarif.json
    sha256: $_hash
    license: OASIS
''');
    expect(schemas.single.name, 'sarif_schema');
    expect(schemas.single.url.pathSegments.last, 'sarif.json');
    expect(schemas.single.license, 'OASIS');
    expect(reader.readSchemas('specs: {}\n'), isEmpty);
    expect(reader.read('specs: {}\nschemas: {a: 1}\n'), isEmpty);
  });

  test('a schema without a lowercase sha256 is a CorpusException', () {
    expect(
      () => reader.readSchemas(
        'schemas: {a: {url: u, sha256: x, license: MIT}}',
      ),
      throwsA(isA<CorpusException>()),
    );
  });

  test('bad YAML is a CorpusException, not a YamlException', () {
    expect(
      () => reader.read('specs: [unclosed\n'),
      throwsA(
        isA<CorpusException>().having(
          (e) => e.message,
          'message',
          startsWith('corpus.yaml: '),
        ),
      ),
    );
    expect(
      () => reader.readSchemas('schemas: {a: [\n'),
      throwsA(isA<CorpusException>()),
    );
  });

  test('a wrong type or a URL that does not parse is a CorpusException', () {
    for (final text in [
      'specs: [a, b]\n',
      'specs: {pets: 3}\n',
      'specs: {pets: {url: [x], sha256: $_hash, license: MIT, expect: generate}}',
      'specs: {pets: {url: "http://[::", sha256: $_hash, license: MIT, '
          'expect: generate}}',
      'specs: {pets: {url: u, sha256: $_hash, license: MIT, '
          'expect: {check-errors: [1]}}}',
    ]) {
      expect(
        () => reader.read(text),
        throwsA(isA<CorpusException>()),
        reason: text,
      );
    }
  });

  group('a file or archive path', () {
    String archive(String root, String entry) =>
        'specs: {shop: {archive: https://example.com/s.tar.gz, '
        'root: "$root", entry: "$entry", sha256: $_hash, license: MIT, '
        'expect: generate}}';

    test('with a dot-dot, an absolute path or an empty segment fails', () {
      for (final (root, entry) in [
        ('../x', 'a.yaml'),
        ('a/../b', 'a.yaml'),
        ('/etc', 'a.yaml'),
        ('a//b', 'a.yaml'),
        ('a/', 'a.yaml'),
        (r'a\\b', 'a.yaml'),
        ('C:/x', 'a.yaml'),
        ('x', '../a.yaml'),
        ('x', '/a.yaml'),
        ('x', 'a//b.yaml'),
        ('x', '.'),
        ('x', 'a/./b.yaml'),
      ]) {
        expect(
          () => reader.read(archive(root, entry)),
          throwsA(
            isA<CorpusException>().having(
              (e) => e.message,
              'message',
              contains('shop'),
            ),
          ),
          reason: '$root | $entry',
        );
      }
    });

    test('a file URL without a usable last segment fails', () {
      for (final url in [
        'https://example.com/dir/',
        'https://example.com',
        'https://example.com/a/..',
        'https://example.com/a/.',
        'https://example.com/a%2F..%2F..%2Fx.json',
        'https://example.com/a%2Fb.json',
        'https://example.com/a%5Cb.json',
        'https://example.com/%2E%2E',
      ]) {
        expect(
          () => reader.read(
            'specs: {pets: {url: "$url", sha256: $_hash, license: MIT, '
            'expect: generate}}',
          ),
          throwsA(isA<CorpusException>()),
          reason: 'spec $url',
        );
        expect(
          () => reader.readSchemas(
            'schemas: {pets: {url: "$url", sha256: $_hash, license: MIT}}',
          ),
          throwsA(isA<CorpusException>()),
          reason: 'schema $url',
        );
      }
    });
  });
}
