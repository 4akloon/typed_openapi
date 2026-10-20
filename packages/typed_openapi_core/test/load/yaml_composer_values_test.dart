import 'package:test/test.dart';
import 'package:typed_openapi_core/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi_core/src/diagnostics/severity.dart';
import 'package:yaml/yaml.dart';

import '../helpers/compose_fixture.dart';

void main() {
  const fixture = ComposeFixture();
  final compose = fixture.compose;

  final plain = fixture.plain;

  group('scalars', () {
    test('resolve exactly as package:yaml loads them', () {
      const scalars = [
        '',
        '~',
        'null',
        'Null',
        'NULL',
        'nULL',
        'true',
        'True',
        'TRUE',
        'tRUE',
        'false',
        'False',
        'FALSE',
        'yes',
        'no',
        'on',
        'off',
        'y',
        '0',
        '7',
        '-0',
        '+1',
        '-12',
        '012',
        '0o17',
        '0o',
        '0x1F',
        '0xg',
        '-0x10',
        '1_000',
        '1.5',
        '-1.5',
        '+1.5',
        '.5',
        '-.5',
        '+.5',
        '1e3',
        '1E-3',
        '1.',
        '.inf',
        '.Inf',
        '.INF',
        '-.inf',
        '+.inf',
        '.nan',
        '.NaN',
        '.NAN',
        '.',
        '+',
        '2025-07-27',
        '12:30',
        '1.2.3',
        '9223372036854775808',
        'x',
        '"quoted 1"',
        "'single'",
        '"true"',
        "'~'",
        '!!str 12',
        '!!int 12',
        '!!float .5',
        '!!bool true',
        '!!null ~',
        '! 12',
        '!!int 0x1F',
      ];
      for (final scalar in scalars) {
        final expected = (loadYaml('k: $scalar') as YamlMap)['k'];
        final actual = (plain('k: $scalar')! as Map)['k'];
        if (expected is double && expected.isNaN) {
          expect(actual, isA<double>().having((d) => d.isNaN, 'isNaN', true));
          continue;
        }
        expect(actual, expected, reason: scalar);
        expect(actual.runtimeType, expected.runtimeType, reason: scalar);
      }
    });

    test('keys are their text, as the Failsafe schema reads them', () {
      expect(plain('200: a\ntrue: b\n0x1F: c\n1.0: d\n"q": e\n'), {
        '200': 'a',
        'true': 'b',
        '0x1F': 'c',
        '1.0': 'd',
        'q': 'e',
      });
    });

    test('a null key is a warning to quote it, and is read as its text', () {
      final (result, bag) = compose('~: a\nnull: b\n: c\n"~": d\n');
      expect(result!.root, {'~': 'd', 'null': 'b', '': 'c'});
      expect(
        bag.all.map((d) => (d.code, d.pointer?.value, d.severity)),
        [
          (DiagnosticCode.nullKey, '#/~0', Severity.warning),
          (DiagnosticCode.nullKey, '#/null', Severity.warning),
          (DiagnosticCode.nullKey, '#/', Severity.warning),
          (DiagnosticCode.duplicateKey, '#/~0', Severity.warning),
        ],
      );
      expect(bag.all.first.fix, 'Quote the key: "~".');
    });
  });

  group('tags', () {
    for (final (tag, value) in [
      ('!!timestamp', '2025-07-27T07:17:05.500Z'),
      ('!!binary', 'R0lGODlh'),
      ('!custom', 'x'),
      ('!custom', '42'),
    ]) {
      test('$tag is an error and the value is read as its text', () {
        final (result, bag) = compose(
          'a: 1\nexample: $tag \'$value\'\nb: 2\n',
        );
        expect(result!.root, {'a': 1, 'example': value, 'b': 2});
        final d = bag.all.single;
        expect(d.code, DiagnosticCode.yamlTagUnsupported);
        expect(d.severity, Severity.error);
        expect(d.pointer?.value, '#/example');
        expect(d.line, 2);
        expect(d.fix, contains('JSON Schema ruleset'));
      });
    }

    test('!!set and !!omap collections are read without the tag', () {
      final (result, bag) = compose(
        's: !!set {a: null, b: null}\no: !!omap [x: 1]\n',
      );
      expect(result!.root, {
        's': {'a': null, 'b': null},
        'o': [
          {'x': 1},
        ],
      });
      expect(bag.all.map((d) => d.code), [
        DiagnosticCode.yamlTagUnsupported,
        DiagnosticCode.yamlTagUnsupported,
      ]);
      expect(bag.all.first.message, contains('!!set'));
    });

    test('a ruleset tag with a value it cannot have is reported too', () {
      final (result, bag) = compose('a: !!int abc\n');
      expect(result!.root, {'a': 'abc'});
      expect(bag.all.single.message, contains('not a valid !!int'));
    });

    test('!!float reads one digit as a double, !!int as an int', () {
      // package:yaml's own loader throws on a one-digit !!float, so the
      // expected values are written out.
      const floats = {'!!float 1': 1.0, '!!float "2"': 2.0, "!!float '3'": 3.0};
      for (final MapEntry(key: scalar, value: expected) in floats.entries) {
        final (result, bag) = compose('k: $scalar\n');
        final value = (result!.root as Map)['k'];
        expect(bag.all, isEmpty, reason: scalar);
        expect(value, isA<double>(), reason: scalar);
        expect(value, expected, reason: scalar);
      }
      final (result, bag) = compose('a: !!int 1\nb: !!float 0\n');
      expect(bag.all, isEmpty);
      expect(result!.root, {'a': 1, 'b': 0.0});
      expect((result.root as Map)['a'], isA<int>());
      expect((result.root as Map)['b'], isA<double>());
    });

    test('a tagged key is checked like a value', () {
      final (result, bag) = compose('!!timestamp 2026-01-01: x\n');
      expect(result!.root, {'2026-01-01': 'x'});
      expect(bag.all.single.pointer?.value, '#');
    });
  });

  test('a YAML warning is a diagnostic, not a print', () {
    final (result, bag) = compose('%FOO bar\n---\na: 1\n');
    expect(result!.root, {'a': 1});
    final d = bag.all.single;
    expect(d.code, DiagnosticCode.yamlWarning);
    expect(d.message, 'Unknown directive.');
    expect(d.line, 1);
  });
}
