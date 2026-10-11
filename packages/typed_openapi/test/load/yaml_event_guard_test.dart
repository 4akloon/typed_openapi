import 'package:test/test.dart';
import 'package:typed_openapi/src/load/yaml_event_guard.dart';

void main() {
  const guard = YamlEventGuard();
  const longTimeout = Timeout(Duration(seconds: 60));

  /// The problem [guard] finds in [text], or null.
  GuardProblem? find(String text, {int limit = YamlEventGuard.maxDepth}) =>
      guard.check(text, limit: limit)?.problem;

  group('nesting', () {
    test('smoke test of the parser event API', () {
      expect(find('a: &x [1, {b: *x}]\n'), isNull);
      expect(find('a: [[[1]]]\n', limit: 2), GuardProblem.tooDeep);
    });

    test('a root collection is level 0, in YAML and JSON alike', () {
      for (final doc in [
        (String open, String close) => 'a: $open$close\n',
        (String open, String close) => '{"a": $open$close}',
      ]) {
        expect(find(doc('[' * 5, ']' * 5), limit: 5), isNull);
        expect(find(doc('[' * 6, ']' * 6), limit: 5), GuardProblem.tooDeep);
      }
      expect(find('[' * 6 + ']' * 6, limit: 5), isNull);
      expect(find('[' * 7 + ']' * 7, limit: 5), GuardProblem.tooDeep);
    });

    test(
      'block sequences, explicit keys and mappings count one level each',
      () {
        expect(find('${'- ' * 5}x', limit: 3), GuardProblem.tooDeep);
        expect(find('${'- ' * 5}x', limit: 4), isNull);
        expect(find('${'? ' * 5}x', limit: 3), GuardProblem.tooDeep);
        expect(find('${'? ' * 5}x', limit: 4), isNull);
        const nested = 'a:\n  b:\n    c:\n      d: x\n';
        expect(find(nested, limit: 2), GuardProblem.tooDeep);
        expect(find(nested, limit: 3), isNull);
      },
    );

    test('the one-pair mapping of [k: v] is a level, as for the converter', () {
      expect(find('[k: [k: [k: x]]]', limit: 5), isNull);
      expect(find('[k: [k: [k: x]]]', limit: 4), GuardProblem.tooDeep);
      expect(find('${'[k: ' * 600}x${']' * 600}'), GuardProblem.tooDeep);
    });

    test('it reports the offset of the collection that is too deep', () {
      expect(guard.check('{"a": [[[1]]]}', limit: 2)?.offset, 8);
    });

    test('100 000 nested levels are reported, not a stack overflow', () {
      for (final text in [
        '${'[' * 100000}${']' * 100000}',
        '${'- ' * 100000}x',
        '${'{a: ' * 100000}x${'}' * 100000}',
        'x:\n  - a\n  -\n    ${'- ' * 100000}x',
        'x:\n  - a\n  -\n    ${'[' * 100000}',
      ]) {
        expect(find(text), GuardProblem.tooDeep);
      }
    }, timeout: longTimeout);

    test('a syntax error is not reported: loadYamlNode reports it', () {
      expect(guard.check('a: [1, 2\nb: {'), isNull);
      expect(guard.check('a: *missing\n'), isNull);
      expect(guard.check('a: 1\n a: 2\n  - x\n'), isNull);
    });
  });

  group('aliases', () {
    const prefix = 'x-a: &a [1, 2]\n';

    for (final (name, tail) in [
      ('as a block key after ?', '? *a\n: v\n'),
      ('as a block key', '*a : v\n'),
      ('as a flow mapping key', 'x: {*a : v}\n'),
      ('as an entry of a flow mapping', 'x: {a: 1, *a : v}\n'),
      ('as a bare entry of a flow mapping', 'x: {*a, b: 1}\n'),
      ('after ? in a flow mapping', 'x: {? *a : v}\n'),
      ('after ? in a flow sequence', 'x: [? *a : v]\n'),
      ('after a bare ? in a flow sequence', 'x: [? *a]\n'),
      ('inside a ? key sequence', '? [*a]\n: v\n'),
      ('inside a ? key block sequence', '? - *a\n: v\n'),
      ('inside a ? key block sequence at the same column', '?\n- *a\n: v\n'),
      ('inside a nested ? key', 'x:\n  ?\n  - *a\n  : v\n'),
      ('inside a flow sequence key', '[*a]: v\n'),
      ('inside a flow mapping key', '{a: *a}: v\n'),
      ('inside a flow key of a flow mapping', 'x: {[*a]: v}\n'),
      ('inside a flow key without a colon', 'x: {[*a]}\n'),
      ('inside a flow key before a comma', 'x: {[*a], a: 1}\n'),
      ('inside a flow mapping in a flow mapping', 'x: {{a: *a}}\n'),
      (
        'inside a flow key with the colon on the next line',
        'x: [ [*a]\n  : v]\n',
      ),
      ('inside a tagged flow key', '!!seq [*a]: v\n'),
      ('inside an anchored flow key', '&z [*a]: v\n'),
      ('inside a flow key in a flow sequence', 'x: [[*a]: v]\n'),
      ('inside a flow key in a block sequence', 'x:\n  - [*a]: v\n'),
      ('as a key after a bare dash line', 'x:\n  - a\n  -\n    *a : v\n'),
      ('after a : with a # and no blank', 'x:\n  {a:# x, b: *a}: v\n'),
      ('in a flow sequence after a : with a #', 'x:\n  [a:#, *a]: v\n'),
      ('after a : with a quote and no blank', "x:\n  {true:'x, c: *a}: v\n"),
      ('after a ? with a quote and no blank', 'x:\n  {?"a : *a}: v\n'),
      ('after a ? with a # and no blank', 'x:\n  {?#a : {v: *a}}: 1\n'),
      ('after a " in a flow mapping', 'x:\n  [{a:"b, c: *a}]: 1\n'),
      ('after an indented ---', 'x:\n --- "q:\n    j: 1\n    ? *a\n'),
    ]) {
      test('an alias $name is reported', () {
        expect(find('$prefix$tail'), GuardProblem.aliasInKey, reason: tail);
      });
    }

    for (final (name, doc) in [
      ('block values', 'k: *a\n'),
      ('block sequence items', '- *a\n- - *a\n- k: *a\n'),
      ('merge keys', 'k:\n  <<: *a\n  b: 1\n'),
      ('flow sequences', 'k: [*a, *a]\n'),
      ('flow mappings', 'k: {x: *a, y: [*a]}\n'),
      ('merge of flow aliases', 'k:\n  <<: [*a, *a]\n'),
      ('a value on its own line', 'k:\n  *a\n'),
      ('a value with a property', 'k: !!seq *a\n'),
      ('a value with a trailing comment', 'k: *a # why\n'),
      ('an explicit key without aliases', '? /pets\n: *a\n'),
      ('a flow collection key without aliases', '[a]: *a\n{b: 1}: 2\n'),
      ('quoted keys with a *', '"*a": 1\n\'*b\' : 2\n'),
      ('markdown in plain scalars', 'k: some *bold* text\n  * item\n'),
      ('markdown in block scalars', 'k: |\n  *a : v\n  [*a]\n'),
      ('a ? in text', 'k: what? *a\nu: http://e.com/a?b=1\n'),
      ('JSON', '{"a": [1, {"b": [2]}], "c": "*a"}'),
      ('CRLF', 'k: *a\r\nj: *a\r\n'),
    ]) {
      test('an alias is accepted in $name', () {
        expect(find('$prefix$doc'), isNull, reason: doc);
      });
    }
  });
}
