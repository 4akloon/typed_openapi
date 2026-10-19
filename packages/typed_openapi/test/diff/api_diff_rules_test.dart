import 'package:test/test.dart';
import 'package:typed_openapi/src/diff/api_change.dart';
import 'package:typed_openapi/src/diff/api_diff.dart';
import 'package:typed_openapi/src/diff/fact_changes.dart';
import 'package:typed_openapi/src/snapshot/api_snapshot.dart';

/// The categories of the changes from [before] to [after], each snapshot
/// one type `t`.
List<ChangeCategory> categories(SnapshotType? before, SnapshotType? after) => [
  for (final change in const ApiDiff().compare(
    ApiSnapshot({'t': ?before}),
    ApiSnapshot({'t': ?after}),
  ))
    change.category,
];

SnapshotType model(Map<String, SnapshotMember> members) =>
    SnapshotType('T', .model, members: members);

SnapshotMember field({String required = 'false', String type = 'int?'}) =>
    SnapshotMember('f', .field, facts: {'required': required, 'type': type});

SnapshotType enumType(List<String> values, {bool exhaustive = true}) =>
    SnapshotType(
      'E',
      .enumeration,
      exhaustive: exhaustive,
      members: {for (final v in values) v: SnapshotMember(v, .value)},
    );

void main() {
  group('types', () {
    test('a removed type is breaking', () {
      expect(categories(model({}), null), [ChangeCategory.breaking]);
    });
    test('an added type is additive', () {
      expect(categories(null, model({})), [ChangeCategory.additive]);
    });
    test('a renamed type is breaking', () {
      expect(categories(model({}), const SnapshotType('U', .model)), [
        ChangeCategory.breaking,
      ]);
    });
    test(
      'a type of another kind is breaking, its members are not compared',
      () {
        expect(
          categories(model({'f': field()}), const SnapshotType('T', .union)),
          [ChangeCategory.breaking],
        );
      },
    );
    test('a sealed type that becomes an interface is switch-breaking', () {
      expect(categories(enumType([]), enumType([], exhaustive: false)), [
        ChangeCategory.switchBreaking,
      ]);
    });
    test('an interface that becomes sealed is breaking', () {
      expect(categories(enumType([], exhaustive: false), enumType([])), [
        ChangeCategory.breaking,
      ]);
    });
  });

  group('members', () {
    test('a removed member is breaking', () {
      expect(categories(model({'f': field()}), model({})), [
        ChangeCategory.breaking,
      ]);
    });
    test('a new optional field is additive', () {
      expect(categories(model({}), model({'f': field()})), [
        ChangeCategory.additive,
      ]);
    });
    test('a new required field is breaking', () {
      expect(categories(model({}), model({'f': field(required: 'true')})), [
        ChangeCategory.breaking,
      ]);
    });
    test('a renamed member is breaking', () {
      expect(
        categories(
          model({'f': field()}),
          model({
            'f': const SnapshotMember(
              'g',
              .field,
              facts: {
                'required': 'false',
                'type': 'int?',
              },
            ),
          }),
        ),
        [ChangeCategory.breaking],
      );
    });
    test('a new value of a sealed enum is switch-breaking', () {
      expect(categories(enumType(['a']), enumType(['a', 'b'])), [
        ChangeCategory.switchBreaking,
      ]);
    });
    test('a new value of a non-exhaustive enum is additive', () {
      expect(
        categories(
          enumType(['a'], exhaustive: false),
          enumType(['a', 'b'], exhaustive: false),
        ),
        [ChangeCategory.additive],
      );
    });
    for (final kind in [
      MemberKind.variant,
      MemberKind.statusCase,
      MemberKind.event,
    ]) {
      test('a new ${kind.name} of a sealed type is switch-breaking', () {
        expect(
          categories(
            const SnapshotType('S', .union),
            SnapshotType(
              'S',
              .union,
              members: {'x': SnapshotMember('X', kind)},
            ),
          ),
          [ChangeCategory.switchBreaking],
        );
      });
    }
    test('a new method is additive, its arguments are part of it', () {
      const group = SnapshotType(
        'G',
        .group,
        members: {
          'op': SnapshotMember('op', .method),
          'op/id': SnapshotMember(
            'id',
            .parameter,
            owner: 'op',
            facts: {
              'required': 'true',
            },
          ),
        },
      );
      expect(categories(const SnapshotType('G', .group), group), [
        ChangeCategory.additive,
      ]);
      expect(categories(group, const SnapshotType('G', .group)), [
        ChangeCategory.breaking,
      ]);
    });
  });

  group('facts', () {
    test('a changed type is breaking', () {
      expect(
        categories(model({'f': field()}), model({'f': field(type: 'String?')})),
        [ChangeCategory.breaking],
      );
    });
    test('an argument that becomes required is breaking', () {
      expect(
        categories(
          model({'f': field()}),
          model({'f': field(required: 'true', type: 'int?')}),
        ),
        [ChangeCategory.breaking],
      );
    });
    test('an argument that becomes optional is additive', () {
      expect(
        categories(
          model({'f': field(required: 'true', type: 'int?')}),
          model({'f': field()}),
        ),
        [ChangeCategory.additive],
      );
    });
    for (final (fact, category) in [
      ('json', ChangeCategory.wire),
      ('path', ChangeCategory.wire),
      ('style', ChangeCategory.wire),
      ('media', ChangeCategory.wire),
      ('responses', ChangeCategory.wire),
      ('doc', ChangeCategory.docs),
      ('deprecated', ChangeCategory.docs),
      ('returns', ChangeCategory.breaking),
      ('an unknown fact', ChangeCategory.breaking),
    ]) {
      test('a changed $fact is ${category.label}', () {
        expect(
          categories(
            SnapshotType('T', .model, facts: {fact: 'a'}),
            SnapshotType('T', .model, facts: {fact: 'b'}),
          ),
          [category],
        );
      });
    }
  });

  group('rename fixes', () {
    const pet = '#/components/schemas/Pet';
    String? fixWhenAdded(List<String> keys) {
      final changes = const ApiDiff().compare(
        ApiSnapshot({pet: model({})}),
        ApiSnapshot({
          for (final key in keys) '#/components/schemas/$key': model({}),
        }),
      );
      return changes.firstWhere((c) => c.type == pet).fix;
    }

    test('one new schema of the kind is named in the fix', () {
      expect(fixWhenAdded(['Animal']), 'schemas:\n  Animal:\n    name: T');
    });
    test('a key YAML would misread is quoted', () {
      expect(
        fixWhenAdded(['a b: c']),
        "schemas:\n  'a b: c':\n    name: T",
      );
    });
    test('several new schemas leave a template', () {
      expect(
        fixWhenAdded(['Animal', 'Beast']),
        'schemas:\n  <NewKey>:\n    name: T',
      );
    });
    test('a type that is not a component schema has no fix', () {
      final changes = const ApiDiff().compare(
        ApiSnapshot({'getPet#success': model({})}),
        const ApiSnapshot({}),
      );
      expect(changes.single.fix, isNull);
    });
  });

  group('wording', () {
    const facts = FactChanges();
    test('a fact that appears says so', () {
      expect(
        facts.describe('Method A.b', 'accept', null, 'application/json'),
        'Method A.b: accept is now application/json.',
      );
    });
    test('a fact that goes says so, also when its value is "none"', () {
      expect(
        facts.describe('Field A.b', 'const', '"none"', null),
        'Field A.b: const "none" is gone.',
      );
    });
  });

  test('changes are sorted by category', () {
    final changes = const ApiDiff().compare(
      ApiSnapshot({
        'a': model({}),
        'b': enumType(['x']),
      }),
      ApiSnapshot({
        'b': enumType(['x', 'y']),
        'c': model({}),
      }),
    );
    expect(
      [for (final c in changes) c.category],
      [
        ChangeCategory.breaking,
        ChangeCategory.switchBreaking,
        ChangeCategory.additive,
      ],
    );
  });
}
