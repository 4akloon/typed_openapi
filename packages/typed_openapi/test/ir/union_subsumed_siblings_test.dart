import 'package:test/test.dart';

import '../helpers/ir_fixture.dart';
import '../helpers/mapping.dart';

void main() {
  group(r'the keywords next to a $ref', () {
    const defs = '''
    Str: {type: string}
    Num: {type: number}
''';

    String types(String version, String branches) {
      final fixture = IrFixture('''
openapi: $version
info: {title: t, version: "1"}
components:
  schemas:
$defs    Unit:
      anyOf: $branches
''');
      final (_, mapped) = mapComponents(fixture, ['Unit']);
      return mapped['Unit']!;
    }

    const str = r"$ref: '#/components/schemas/Str'";
    const number = r"$ref: '#/components/schemas/Num'";

    // The four cases of the review: each of these widens what is accepted.
    for (final (name, branches) in [
      ('format', '[{$str, format: date-time}, {enum: [abcdef]}]'),
      ('pattern', "[{$str, pattern: '^x'}, {enum: [abcdef]}]"),
      ('maxLength', '[{$str, maxLength: 1}, {enum: [abcdef]}]'),
      ('enum', '[{$str, enum: [x]}, {enum: [y]}]'),
      ('const', '[{$str, const: x}, {enum: [y]}]'),
      ('minimum', '[{$number, minimum: 5}, {type: number, enum: [1.5]}]'),
      (
        'a keyword the rule does not model',
        '[{$str, not: {minLength: 3}}, {enum: [abcdef]}]',
      ),
      ('another type', '[{$str, type: integer}, {enum: [abcdef]}]'),
    ]) {
      test('a sibling $name in 3.1 keeps the union', () {
        expect(types('3.1.0', branches), 'JsonValue');
      });
    }

    test('in 3.0 the siblings are ignored', () {
      expect(
        types('3.0.3', '[{$str, format: date-time}, {enum: [abcdef]}]'),
        'String',
      );
    });

    test('a sibling limit every enum value meets still collapses', () {
      expect(
        types('3.1.0', '[{$str, maxLength: 10}, {enum: [abcdef]}]'),
        'String',
      );
      expect(
        types(
          '3.1.0',
          '[{$str, description: a, type: string}, {enum: [abcdef]}]',
        ),
        'String',
      );
    });
  });

  test('a plain branch with a keyword the rule does not model is kept', () {
    final fixture = IrFixture(r'''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Conditional:
      anyOf:
        - {type: string, if: {minLength: 1}, then: {pattern: '^a'}}
        - {enum: ['']}
    Dependent:
      anyOf:
        - {type: string, dependentSchemas: {a: {minLength: 3}}}
        - {enum: [abc]}
    Commented:
      anyOf:
        - {type: string, $comment: only a note}
        - {enum: [abc]}
''');
    final (_, types) = mapComponents(fixture, [
      'Conditional',
      'Dependent',
      'Commented',
    ]);
    expect(types, {
      'Conditional': 'JsonValue',
      'Dependent': 'JsonValue',
      'Commented': 'String',
    });
  });

  group('multipleOf is decided on the decimal numbers', () {
    String type(String step, String value) {
      final fixture = IrFixture('''
openapi: 3.1.0
info: {title: t, version: "1"}
components:
  schemas:
    Unit:
      anyOf: [{type: number, multipleOf: $step}, {type: number, enum: [$value]}]
''');
      return mapComponents(fixture, ['Unit']).$2['Unit']!;
    }

    for (final (step, value) in [
      ('1', '1.0000000001'),
      ('2', '2.0000000005'),
      ('0.1', '0.1000000001'),
      ('0.25', '1.000000000001'),
      ('0.1', '0.35'),
    ]) {
      test('$value is not a multiple of $step', () {
        expect(type(step, value), 'JsonValue');
      });
    }

    for (final (step, value) in [
      ('0.1', '0.3'),
      ('0.01', '0.07'),
      ('0.01', '19.99'),
      ('0.25', '1.5'),
      ('1', '3.0'),
      ('1e-7', '3e-7'),
    ]) {
      test('$value is a multiple of $step', () {
        expect(type(step, value), 'num');
      });
    }
  });
}
