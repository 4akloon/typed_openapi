@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_openapi/src/snapshot/api_snapshot.dart';
import 'package:typed_openapi/src/snapshot/snapshot_json.dart';

import '../helpers/snapshot_fixture.dart';

void main() {
  const json = SnapshotJson();

  test('the same spec gives the same text', () {
    expect(
      json.encode({'a': snapshotOfFixture('petstore.yaml')}),
      json.encode({'a': snapshotOfFixture('petstore.yaml')}),
    );
  });

  test('the text reads back as it was written', () {
    final text = json.encode({
      'pets': snapshotOfFixture('pets.yaml'),
      'chat': snapshotOfFixture('chat.yaml'),
    });
    expect(json.encode(json.decode(text)), text);
  });

  test('a type is written on its own lines, a member on one line', () {
    final text = json.encode({
      'a': const ApiSnapshot({
        '#/components/schemas/Pet': SnapshotType(
          'Pet',
          .model,
          members: {
            'id': SnapshotMember('id', .field, facts: {'type': 'int'}),
          },
        ),
      }),
    });
    expect(text, '''
{
  "version": 1,
  "clients": {
    "a": {
      "#/components/schemas/Pet": {
        "name": "Pet",
        "kind": "model",
        "members": {
          "id": {"name":"id","kind":"field","facts":{"type":"int"}}
        }
      }
    }
  }
}
''');
  });

  test('a lock without clients is valid', () {
    final text = json.encode({});
    expect(json.decode(text), isEmpty);
  });

  group('a text that is not a lock is a FormatException', () {
    for (final (what, text) in [
      ('not JSON', '{'),
      ('another version', '{"version": 2, "clients": {}}'),
      (
        'a type without a kind',
        '{"version": 1, "clients": {"a": {"t": {"name": "T"}}}}',
      ),
      (
        'an unknown kind',
        '{"version": 1, "clients": {"a": {"t": {"name": "T", "kind": "x"}}}}',
      ),
      (
        'a fact that is not a string',
        '{"version": 1, "clients": {"a": {"t": {"name": "T", "kind": "model", '
            '"facts": {"doc": 1}}}}}',
      ),
    ]) {
      test(what, () {
        expect(() => json.decode(text), throwsFormatException);
      });
    }
  });
}
