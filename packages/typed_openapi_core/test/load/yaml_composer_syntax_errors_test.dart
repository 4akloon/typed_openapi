import 'dart:math';

import 'package:test/test.dart';

import '../helpers/compose_fixture.dart';

void main() {
  const limit = Timeout(Duration(seconds: 60));
  const fixture = ComposeFixture();
  final compose = fixture.compose;

  group('syntax errors are returned, not reported', () {
    for (final (name, text, message) in [
      ('an unclosed flow sequence', 'a: [1, 2\nb: {', null),
      ('an undefined alias', 'a: *missing\n', 'Undefined alias.'),
      (
        'a collection that contains its own alias',
        'a: &a [*a]\n',
        'Self-referential collections are not supported.',
      ),
      ('two documents', 'a: 1\n---\nb: 2\n', 'Only expected one document.'),
      (
        'a key alias in a second document',
        'x: &a [1]\n---\n? *a\n: v\n',
        'Only expected one document.',
      ),
      ('a bad indentation', 'a: 1\n a: 2\n  - x\n', null),
    ]) {
      test(name, () {
        final (result, bag) = compose(text);
        expect(bag.all, isEmpty);
        expect(result!.syntaxError, isNotNull);
        if (message != null) {
          expect(result.syntaxError!.message, message);
        }
      });
    }

    test('the document that broke package:yaml\'s scanner assert is a '
        'syntax error', () {
      // `Scanner._saveSimpleKey` asserted on this document; the copy reports
      // a syntax error there instead.
      final (result, bag) = compose(
        'x-a: &a [1, 2]\nx-z:\n   - ? "\n      , \'s\'] : \n  "!!seq \n'
        '  , *a :  "\n',
      );
      expect(bag.all, isEmpty);
      expect(
        result!.syntaxError!.message,
        'Expected a key at this indentation.',
      );
    });

    test('no assert escapes on the 300 000 documents of the M2 fuzz', () {
      // The generator and seed of M2's alias-key fuzz, which found the
      // scanner assert in 86 of these documents. Any AssertionError fails
      // the test.
      final random = Random(11);
      const tokens = [
        '- ',
        '? ',
        ': ',
        'k: ',
        'j: ',
        '&b ',
        '*a',
        '*a ',
        '*b',
        '[',
        ']',
        '{',
        '}',
        ', ',
        'v',
        'k',
        '|',
        '>',
        '"q"',
        "'s'",
        '"',
        "'",
        '#c',
        '!!str ',
        '!!seq ',
        ' ',
        '*a : ',
        '? *a',
        '[*a]',
        '{*a: 1}',
        '[*a]: ',
        '{a: *a}: ',
        ':',
        '?',
        '-',
        '&c ',
        'x y',
        '] : ',
        ':#',
        '?"',
        ":'",
        '?#',
        ' --- ',
        '---',
        '\t',
      ];
      const indents = ['', ' ', '  ', '   ', '    '];
      var syntaxErrors = 0;
      for (var i = 0; i < 300000; i++) {
        final lines = List.generate(2 + random.nextInt(5), (_) {
          final line = StringBuffer(indents[random.nextInt(indents.length)]);
          for (var t = 1 + random.nextInt(5); t > 0; t--) {
            line.write(tokens[random.nextInt(tokens.length)]);
          }
          return '  $line';
        });
        final text = 'x-a: &a [1, 2]\nx-z:\n${lines.join('\n')}\n';
        final (result, _) = compose(text);
        if (result?.syntaxError != null) syntaxErrors++;
      }
      expect(syntaxErrors, greaterThan(1000));
    }, timeout: limit);
  });
}
