import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_bag.dart';
import 'package:typed_openapi/src/diagnostics/diagnostic_code.dart';
import 'package:typed_openapi/src/diagnostics/severity.dart';
import 'package:typed_openapi/src/load/yaml_composer.dart';
import 'package:yaml/yaml.dart';

void main() {
  const limit = Timeout(Duration(seconds: 60));

  /// Composes [text] as `api.yaml` (or `api.json` with [json]).
  (ComposedYaml?, DiagnosticBag) compose(String text, {bool json = false}) {
    final bag = DiagnosticBag();
    final result = YamlComposer(bag).compose(
      text,
      file: json ? 'api.json' : 'api.yaml',
      uri: Uri.file('/specs/api.yaml'),
      json: json,
    );
    return (result, bag);
  }

  /// The plain tree of [text]; it must compose without diagnostics.
  Object? plain(String text) {
    final (result, bag) = compose(text);
    expect(bag.all, isEmpty, reason: text);
    expect(result?.syntaxError, isNull, reason: text);
    return result!.root;
  }

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

    test('a tagged key is checked like a value', () {
      final (result, bag) = compose('!!timestamp 2026-01-01: x\n');
      expect(result!.root, {'2026-01-01': 'x'});
      expect(bag.all.single.pointer?.value, '#');
    });
  });

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

  group('nesting', () {
    test('every collection the parser opens is a level, keys included', () {
      String nested(int levels) => '${'[' * levels}${']' * levels}';
      expect(compose('a: ${nested(1000)}\n').$2.all, isEmpty);
      expect(
        compose('a: ${nested(1001)}\n').$2.all.single.code,
        DiagnosticCode.nestingTooDeep,
      );
      final (key, bag) = compose('? ${nested(1001)}\n: v\n');
      expect(key, isNull);
      expect(
        bag.all.map((d) => d.code),
        contains(DiagnosticCode.nestingTooDeep),
      );
    }, timeout: limit);

    test('100 000 nested levels are reported, not a stack overflow', () {
      for (final text in [
        '${'[' * 100000}${']' * 100000}',
        '${'- ' * 100000}x',
        '${'{a: ' * 100000}x${'}' * 100000}',
        'x:\n  - a\n  -\n    ${'- ' * 100000}x',
        'x:\n  - a\n  -\n    ${'[' * 100000}',
      ]) {
        final (result, bag) = compose(text);
        expect(result, isNull);
        expect(bag.all.single.code, DiagnosticCode.nestingTooDeep);
      }
    }, timeout: limit);
  });

  group('flow collections that hide their closing brackets', () {
    // The scanner copied from package:yaml spent time proportional to the
    // flow depth on every token; each of these took a minute or more. No
    // assertion measures time: the timeout is the test.
    for (final (name, text) in [
      ('quoted closers after a key', 'x: ${'["]",' * 199000}'),
      ('quoted closers after a key, closed', 'x: ${'["]",' * 160000}]'),
      ('quoted closers at the root', '["]",' * 200000),
      ('quoted closers in braces', '{"}":' * 200000),
      ('single-quoted closers', "x: ${"[']'," * 200000}"),
      ('quoted closers on separate lines', 'x: [\n${'"]",[\n' * 150000}'),
      ('closers in comments', 'x: [\n${'[ #]\n' * 150000}'),
      ('a quoted opening bracket first', 'x: ["[", ${'["]",' * 200000}'),
    ]) {
      test('$name are nesting-too-deep, found in near-linear time', () {
        final (result, bag) = compose(text);
        expect(result, isNull);
        final d = bag.all.single;
        expect(d.code, DiagnosticCode.nestingTooDeep);
        expect(d.span, isNotNull);
      }, timeout: limit);
    }

    test(
      'quoted closers without a comma are a syntax error, found at once',
      () {
        // `["]"["]"...`: the parser rejects the second item before the
        // nesting gets deep.
        final (result, bag) = compose('["]"' * 250000);
        expect(bag.all, isEmpty);
        expect(result!.syntaxError, isNotNull);
      },
      timeout: limit,
    );

    test('the position is the first collection that is too deep', () {
      // `x: ` is 3 characters and each `["]",` starts with its `[`. The
      // root mapping is level 0, so the sequence at index 1000 is level 1001.
      final (_, bag) = compose('x: ${'["]",' * 5000}');
      expect(bag.all.single.span!.start.offset, 3 + 5 * 1000);
    });

    test('many short flow collections are read', () {
      final (result, bag) = compose('x: [${'[1, 2], ' * 60000}0]\n');
      expect(bag.all, isEmpty);
      expect(((result!.root! as Map)['x']! as List).length, 60001);
      expect(compose('{"a": [${'{"k": ["v"]},' * 40000}1]}').$2.all, isEmpty);
      expect(compose('x: ${'["]", ' * 900}${']' * 900}\n').$2.all, isEmpty);
    }, timeout: limit);
  });

  test('a YAML warning is a diagnostic, not a print', () {
    final (result, bag) = compose('%FOO bar\n---\na: 1\n');
    expect(result!.root, {'a': 1});
    final d = bag.all.single;
    expect(d.code, DiagnosticCode.yamlWarning);
    expect(d.message, 'Unknown directive.');
    expect(d.line, 1);
  });

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

  test('the composed tree matches package:yaml on random block and flow '
      'documents (fixed seed)', () {
    final random = Random(7);
    const tokens = [
      'k: ',
      'j: ',
      '- ',
      '[',
      ']',
      '{',
      '}',
      ', ',
      'v',
      '1',
      '"q"',
      "'s'",
      '~',
      'true',
      '2.5',
      '&b ',
      '*a',
      ': ',
      '? ',
      '|',
      '#c',
      ' ',
    ];
    var compared = 0;
    for (var i = 0; i < 20000; i++) {
      final lines = List.generate(1 + random.nextInt(4), (_) {
        final line = StringBuffer(' ' * (2 + random.nextInt(3)));
        for (var t = 1 + random.nextInt(5); t > 0; t--) {
          line.write(tokens[random.nextInt(tokens.length)]);
        }
        return '$line';
      });
      final text = 'x-a: &a [1, 2]\nx-z:\n${lines.join('\n')}\n';
      final YamlNode node;
      try {
        node = loadYamlNode(text);
        // package:yaml's own scanner asserts on some invalid documents; the
        // comparison skips them (the copy reports a syntax error).
        // ignore: avoid_catching_errors
      } on AssertionError {
        continue;
      } on YamlException {
        continue;
      }
      final expected = _failsafeKeys(node);
      if (expected == _skip) continue;
      final (result, bag) = compose(text);
      expect(
        bag.all.where((d) => d.code != DiagnosticCode.nullKey),
        isEmpty,
        reason: text,
      );
      expect(result!.root, expected, reason: text);
      compared++;
    }
    expect(compared, greaterThan(1000));
  }, timeout: limit);
}

const _skip = Object();

/// An anchor or a tag in front of a scalar's text.
final _properties = RegExp(r'^(?:[&!]\S*(?:\s+|$))+');

/// The plain value of [node] with keys as their Failsafe text, or [_skip]
/// when a key is a collection or two keys are one JSON key.
Object? _failsafeKeys(YamlNode node) {
  switch (node) {
    case YamlMap():
      final map = <String, Object?>{};
      for (final MapEntry(:key, value: entry) in node.nodes.entries) {
        final keyNode = key as YamlNode;
        if (keyNode is! YamlScalar) return _skip;
        final value = keyNode.value;
        final name = value is String
            ? value
            : keyNode.span.text.replaceFirst(_properties, '').trim();
        if (map.containsKey(name)) return _skip;
        final converted = _failsafeKeys(entry);
        if (converted == _skip) return _skip;
        map[name] = converted;
      }
      return map;
    case YamlList():
      final list = <Object?>[];
      for (final item in node.nodes) {
        final converted = _failsafeKeys(item);
        if (converted == _skip) return _skip;
        list.add(converted);
      }
      return list;
    default:
      return node.value;
  }
}
