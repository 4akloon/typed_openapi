import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/corpus/client_lock.dart';
import 'package:typed_openapi_tool/src/corpus/corpus_lock.dart';

void main() {
  const pets = ClientLock(
    files: {'models/pet.dart': 'b', 'api.dart': 'a'},
    diagnostics: {'TOA651': 2, 'TOA201': 1},
  );
  const skipped = ClientLock(files: {}, diagnostics: {'TOA009': 2});

  test('the text has sorted keys whatever the insertion order', () {
    const lock = CorpusLock({'raw/z': skipped, 'raw/pets': pets});
    final text = lock.format();
    expect(text.indexOf('raw/pets'), lessThan(text.indexOf('raw/z')));
    expect(text.indexOf('api.dart'), lessThan(text.indexOf('models/')));
    expect(text.indexOf('TOA201'), lessThan(text.indexOf('TOA651')));
    expect(text, endsWith('}\n'));
    expect(CorpusLock.parse(text).format(), text);
  });

  test('a skipped client records only its diagnostics', () {
    expect(skipped.toJson(), {
      'diagnostics': {'TOA009': 2},
    });
    expect(pets.toJson()['output'], hasLength(64));
  });

  test('lists every changed file, code and client', () {
    const changed = ClientLock(
      files: {'api.dart': 'a2', 'models/cat.dart': 'c'},
      diagnostics: {'TOA651': 3},
    );
    const got = CorpusLock({'raw/pets': changed, 'raw/new': skipped});
    const want = CorpusLock({'raw/pets': pets, 'raw/z': skipped});
    expect(got.differencesFrom(want), [
      'raw/new: new client',
      'raw/pets: changed api.dart',
      'raw/pets: added models/cat.dart',
      'raw/pets: removed models/pet.dart',
      'raw/pets: TOA201 1 -> 0',
      'raw/pets: TOA651 2 -> 3',
      'raw/z: client is gone',
    ]);
    expect(want.differencesFrom(want), isEmpty);
  });

  group('round-trip counts', () {
    ClientLock withValues(Map<String, int>? values) => ClientLock(
      files: const {'api.dart': 'a'},
      diagnostics: const {},
      values: values,
    );

    List<String> differences(Map<String, int>? got, Map<String, int>? want) =>
        CorpusLock({'raw/p': withValues(got)}).differencesFrom(
          CorpusLock({'raw/p': withValues(want)}),
        );

    test('a changed count is a difference that names the count', () {
      expect(
        differences(
          {'failures': 1, 'synthetic': 5},
          {
            'failures': 0,
            'synthetic': 5,
          },
        ),
        ['raw/p: failures 0 -> 1'],
      );
    });

    test('a client without counts equals itself', () {
      expect(differences(null, null), isEmpty);
      expect(
        const CorpusLock({'raw/z': skipped}).differencesFrom(
          const CorpusLock({'raw/z': skipped}),
        ),
        isEmpty,
      );
    });

    test('gaining or losing counts is a difference', () {
      expect(differences({'failures': 0}, null), [
        'raw/p: round-trip counts added',
      ]);
      expect(differences(null, {'failures': 0}), [
        'raw/p: round-trip counts removed',
      ]);
    });
  });
}
