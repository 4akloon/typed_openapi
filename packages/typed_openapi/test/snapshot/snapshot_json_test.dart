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

  test('bidirectional and line separator characters are escaped', () {
    const hostile = 'a\u202eb\u2028c\u0085d\u200fe\u2066f';
    final text = json.encode({
      'a': const ApiSnapshot({
        '#/x': SnapshotType(
          'X',
          .enumeration,
          members: {
            '"a\u202e"': SnapshotMember(
              'v',
              .value,
              facts: {'path': hostile},
            ),
          },
        ),
      }),
    });
    expect(text, isNot(matches(RegExp('[\u0085\u200f\u2028\u202e\u2066]'))));
    expect(text, contains(r'\u202e'));
    final back = json.decode(text)['a']!.types['#/x']!;
    expect(back.members['"a\u202e"']?.facts['path'], hostile);
    expect(json.encode(json.decode(text)), text);
  });

  test('an exhaustive that is not a bool is a FormatException', () {
    expect(
      () => json.decode(
        '{"version": 1, "clients": {"a": {"t": {"name": "T", '
        '"kind": "model", "exhaustive": "x"}}}}',
      ),
      throwsFormatException,
    );
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
