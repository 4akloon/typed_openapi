import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';

import '../helpers/compose_fixture.dart';

void main() {
  const limit = Timeout(Duration(seconds: 60));
  const fixture = ComposeFixture();
  final compose = fixture.compose;

  group('duplicate keys', () {
    test('keys YAML considers equal are an error, as in YAML, and the last '
        'value wins', () {
      final (result, bag) = compose('a: 1\n"a": 2\nb: 3\n');
      expect(result!.root, {'a': 2, 'b': 3});
      final d = bag.all.single;
      expect(d.severity, Severity.error);
      expect(d.message, 'Duplicate mapping key "a"; the last value is used.');
      expect(d.pointer?.value, '#/a');
    });

    test('in a .json file they are a warning and the last value wins', () {
      final (result, bag) = compose('{"a": 1, "b": 0, "a": 2}', json: true);
      expect(result!.root, {'a': 2, 'b': 0});
      final d = bag.all.single;
      expect(d.severity, Severity.warning);
      expect(d.pointer?.value, '#/a');
      expect(d.column, 18);
    });

    test('keys equal only as JSON keys are a warning, last wins', () {
      final (result, bag) = compose('r:\n  1: a\n  "1": b\n');
      expect(result!.root, {
        'r': {'1': 'b'},
      });
      expect(bag.all.single.message, contains('same key "1" in JSON'));
    });
  });

  group('non-string keys', () {
    const prefix = 'x-a: &a [1, 2]\n';

    // Every key syntax the M2 alias-key guard covered: each makes a
    // collection a key.
    for (final (name, tail) in [
      ('an alias as a block key after ?', '? *a\n: v\n'),
      ('an alias as a block key', '*a : v\n'),
      ('an alias as a flow mapping key', 'x: {*a : v}\n'),
      ('an alias as an entry of a flow mapping', 'x: {a: 1, *a : v}\n'),
      ('an alias as a bare entry of a flow mapping', 'x: {*a, b: 1}\n'),
      ('an alias after ? in a flow mapping', 'x: {? *a : v}\n'),
      ('an alias after ? in a flow sequence', 'x: [? *a : v]\n'),
      ('an alias after a bare ? in a flow sequence', 'x: [? *a]\n'),
      ('a ? key sequence', '? [*a]\n: v\n'),
      ('a ? key block sequence', '? - *a\n: v\n'),
      ('a ? key block sequence at the same column', '?\n- *a\n: v\n'),
      ('a nested ? key', 'x:\n  ?\n  - *a\n  : v\n'),
      ('a flow sequence key', '[*a]: v\n'),
      ('a flow mapping key', '{a: *a}: v\n'),
      ('a flow key of a flow mapping', 'x: {[*a]: v}\n'),
      ('a flow key without a colon', 'x: {[*a]}\n'),
      ('a flow key before a comma', 'x: {[*a], a: 1}\n'),
      ('a flow mapping in a flow mapping', 'x: {{a: *a}}\n'),
      ('a flow key with the colon on the next line', 'x: [ [*a]\n  : v]\n'),
      ('a tagged flow key', '!!seq [*a]: v\n'),
      ('an anchored flow key', '&z [*a]: v\n'),
      ('a flow key in a flow sequence', 'x: [[*a]: v]\n'),
      ('a flow key in a block sequence', 'x:\n  - [*a]: v\n'),
      ('an alias key after a bare dash line', 'x:\n  - a\n  -\n    *a : v\n'),
      ('a key after a : with a # and no blank', 'x:\n  {a:# x, b: *a}: v\n'),
      ('a key after a : with a quote', "x:\n  {true:'x, c: *a}: v\n"),
      ('a key after a ? with a quote', 'x:\n  {?"a : *a}: v\n'),
      ('a key after a " in a flow mapping', 'x:\n  [{a:"b, c: *a}]: 1\n'),
    ]) {
      test('$name is an error and the entry is dropped', () {
        final (result, bag) = compose('$prefix$tail');
        expect(result?.syntaxError, isNull, reason: tail);
        expect(
          bag.all.map((d) => d.code),
          everyElement(DiagnosticCode.nonStringKey),
          reason: tail,
        );
        expect(bag.all, isNotEmpty, reason: tail);
        expect(bag.all.first.span, isNotNull);
      });
    }

    test('a key is never expanded, so a bomb in a key costs nothing', () {
      final text = StringBuffer('l0: &l0 [x, x, x, x, x, x, x, x, x]\n');
      for (var i = 1; i <= 9; i++) {
        text.write('? &l$i [');
        text.write(List.filled(9, '*l${i - 1}').join(', '));
        text.writeln(']\n: v');
      }
      text.writeln('after: 1');
      final (result, bag) = compose('$text');
      expect((result!.root! as Map)['after'], 1);
      expect(bag.all, hasLength(9));
    }, timeout: limit);

    test('an alias of a node inside a dropped key reads as null', () {
      final (result, bag) = compose('? &k [1]\n: v\nx: *k\n');
      expect(result!.root, {'x': null});
      expect(bag.all.map((d) => d.code), [
        DiagnosticCode.nonStringKey,
        DiagnosticCode.nonStringKey,
      ]);
    });

    for (final (name, doc) in [
      ('block values', 'k: *a\n'),
      ('block sequence items', '- *a\n- - *a\n- k: *a\n'),
      ('merge keys', 'k:\n  <<: *a\n  b: 1\n'),
      ('flow sequences', 'k: [*a, *a]\n'),
      ('flow mappings', 'k: {x: *a, y: [*a]}\n'),
      ('a value on its own line', 'k:\n  *a\n'),
      ('a value with a trailing comment', 'k: *a # why\n'),
      ('an explicit key without aliases', '? /pets\n: *a\n'),
      ('an alias of a scalar as a key', 's: &s name\n*s : 1\n'),
      ('quoted keys with a *', '"*a": 1\n\'*b\' : 2\n'),
      ('markdown in plain scalars', 'k: some *bold* text\n  * item\n'),
      ('markdown in block scalars', 'k: |\n  *a : v\n  [*a]\n'),
      ('CRLF', 'k: *a\r\nj: *a\r\n'),
    ]) {
      test('aliases are accepted in $name', () {
        final (result, bag) = compose(
          '${doc.startsWith('-') ? 'x-l: &a [1, 2]\nx-s:\n' : prefix}$doc',
        );
        expect(bag.all, isEmpty, reason: doc);
        expect(result?.syntaxError, isNull, reason: doc);
      });
    }
  });
}
