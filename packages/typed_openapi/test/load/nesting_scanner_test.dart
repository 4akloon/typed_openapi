import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_openapi/src/load/nesting_scanner.dart';

void main() {
  const scanner = NestingScanner();

  test('accepts JSON as deep as the limit', () {
    final text = '${'[' * 5}${']' * 5}';
    expect(scanner.findTooDeep(text, limit: 5), isNull);
  });

  test('finds the bracket that goes one level too deep', () {
    final text = '{"a": ${'[' * 6}${']' * 6}}';
    expect(scanner.findTooDeep(text, limit: 5), 11);
  });

  test('a root flow collection is level 0, like a root block mapping', () {
    expect(
      scanner.findTooDeep('{"a": ${'[' * 5}${']' * 5}}', limit: 5),
      isNull,
    );
    expect(scanner.findTooDeep('a: ${'[' * 5}${']' * 5}', limit: 5), isNull);
    expect(scanner.findTooDeep('a: ${'[' * 6}${']' * 6}', limit: 5), 8);
    expect(scanner.findTooDeep('${'[' * 5}${']' * 5}', limit: 5), isNull);
    expect(
      scanner.findTooDeep('---\n# c\n{"a": [[[[[1]]]]]}', limit: 5),
      isNull,
    );
    expect(scanner.findTooDeep('- ${'[' * 5}${']' * 5}', limit: 5), 5);
  });

  test('ignores brackets in strings and comments', () {
    const text = '''
a: "[[[[[["
b: '[[[[[[ it''s'
# [[[[[[
c: [1, 2]
''';
    expect(scanner.findTooDeep(text, limit: 2), isNull);
  });

  test('counts compact YAML sequences and indentation', () {
    expect(scanner.findTooDeep('- - - x\n', limit: 6), isNull);
    expect(scanner.findTooDeep('- - - - x\n', limit: 6), 6);
    expect(scanner.findTooDeep('a:\n        b: 1\n', limit: 6), 9);
  });

  test('a flow collection starts from the indentation of its line', () {
    expect(scanner.findTooDeep('a:\n    b: [[1]]\n', limit: 6), isNull);
    expect(scanner.findTooDeep('a:\n     b: [[1]]\n', limit: 6), 12);
  });

  test('scans 20 000 levels without recursion', () {
    final text = '${'[' * 20000}${']' * 20000}';
    expect(scanner.findTooDeep(text), NestingScanner.maxDepth + 1);
  });

  test('a stray quote in a plain scalar does not hide what follows', () {
    const head = "a: it 'x\nb: ";
    final text = '$head${'[' * 20000}${']' * 20000}';
    expect(scanner.findTooDeep(text), head.length + NestingScanner.maxDepth);
  });

  test('a stray quote in a block scalar does not hide what follows', () {
    const head = "a: |\n  it 'x\nb: ";
    final text = '$head${'[' * 20000}${']' * 20000}';
    expect(scanner.findTooDeep(text), head.length + NestingScanner.maxDepth);
  });

  test('an unbalanced brace in a plain scalar is not a collection', () {
    final text = List.generate(
      1200,
      (n) => 'p$n:\n  description: use { to open\n',
    ).join();
    expect(scanner.findTooDeep(text), isNull);
  });

  test('an apostrophe in a plain scalar does not open a string', () {
    const text = "a: it's here\nb: [1, [2]]\nc: 'it''s'\nd: [[1]]\n";
    expect(scanner.findTooDeep(text, limit: 3), isNull);
  });

  test('brackets in quoted values are not collections', () {
    expect(scanner.findTooDeep('key: "a [ b"\nk2: [1]\n', limit: 2), isNull);
    expect(
      scanner.findTooDeep("key: 'it''s [ fine'\nk2: [1]\n", limit: 2),
      isNull,
    );
  });

  test('a block scalar hides its lines but not the lines after it', () {
    const hidden = 'a: |\n  [[[[[[\n  {{{{{{\n\n  [[[[[[\nb: [1]\n';
    expect(scanner.findTooDeep(hidden, limit: 3), isNull);
    const after = 'a: |\n  x\nb:\n        c: 1\n';
    expect(scanner.findTooDeep(after, limit: 6), 18);
    const seq = '- a: |\n    x\n  b: [[[1]]]\n';
    expect(scanner.findTooDeep(seq, limit: 4), 20);
  });

  test('anchors, tags and document markers do not hide a collection', () {
    expect(scanner.findTooDeep('a: &x [[[1]]]\n', limit: 2), 8);
    expect(scanner.findTooDeep('a: !!seq [[[1]]]\n', limit: 2), 11);
    expect(scanner.findTooDeep('--- ${'[' * 20000}'), isNotNull);
    expect(scanner.findTooDeep('--- [1]\n--- |\n  [[[[\n', limit: 6), isNull);
  });

  test('a lone CR and CRLF are line breaks', () {
    expect(scanner.findTooDeep('a:\r        b: 1\r', limit: 6), 9);
    expect(scanner.findTooDeep('a:\r\n        b: 1\r\n', limit: 6), 10);
    expect(scanner.findTooDeep('  x\r' * 10, limit: 6), isNull);
    expect(scanner.findTooDeep('  x\r\n' * 10, limit: 6), isNull);
  });

  test('a continuation line starting with a bracket is scalar text', () {
    final deep = '- ' * 20000;
    expect(scanner.findTooDeep('a: foo\n  [x\nb:\n  $deep'), isNotNull);
    expect(scanner.findTooDeep('a: foo\n  {x\nb:\n  $deep'), isNotNull);
    expect(scanner.findTooDeep('- foo\n  [x\n- $deep'), isNotNull);
    expect(scanner.findTooDeep("a: foo\n  'x\nb:\n  $deep"), isNotNull);
    expect(scanner.findTooDeep('a: foo\n  - [x\nb:\n  $deep'), isNotNull);
    expect(scanner.findTooDeep('a: foo\n  [[[[[[\nb: 1\n', limit: 3), isNull);
  });

  test('a flow collection after a plain scalar is real when not indented', () {
    expect(scanner.findTooDeep('a: foo\n[[[x]]]: 1\n', limit: 2), 9);
    expect(scanner.findTooDeep('a:\n  [[[x]]]\n', limit: 2), 5);
  });

  test('pretty-printed JSON nested 600 levels is not double counted', () {
    Object? value = 'x';
    for (var i = 0; i < 600; i++) {
      value = {'a': value};
    }
    final text = const JsonEncoder.withIndent('  ').convert(value);
    expect(scanner.findTooDeep(text), isNull);
  });

  test('markers at the start of a line count inside flow collections', () {
    expect(scanner.findTooDeep('[\n${'- ' * 3}x\n]', limit: 5), 6);
    expect(scanner.findTooDeep('[\n${'- ' * 2}x\n]', limit: 5), isNull);
  });

  test('an empty-key value indicator nests like a complex key marker', () {
    expect(scanner.findTooDeep('${': ' * 20000}x'), isNotNull);
    expect(scanner.findTooDeep('${'- : ' * 10000}x'), isNotNull);
    expect(scanner.findTooDeep('${': - ' * 10000}x'), isNotNull);
    expect(scanner.findTooDeep('${'? ' * 20000}x'), isNotNull);
    expect(scanner.findTooDeep('${': ' * 3}x', limit: 5), 5);
    expect(scanner.findTooDeep('${': ' * 2}x', limit: 5), isNull);
  });

  test('ordinary key: value lines are not nesting', () {
    final text = List.generate(
      5000,
      (n) => 'k$n: v\nm$n:\n  - a: b\n    c: [1, {d: e}]\n  - : x\n',
    ).join();
    expect(scanner.findTooDeep(text, limit: 10), isNull);
  });

  group('findAliasKey', () {
    int? find(String text) => scanner.findAliasKey(text);

    test('finds an alias after a ? marker', () {
      expect(find('a:\n  ? *x\n  : v\n'), 5);
      expect(find('? *x\n'), 0);
      expect(find('?\n  *x\n'), 0);
    });

    test('with an alias anywhere, rejects every explicit ? key', () {
      expect(find('? [*x]\n: v\n'), 0);
      expect(find('? - *x\n: v\n'), 0);
      expect(find('?\n- *x\n: v\n'), 0);
      expect(find('a:\n  ?\n  - *x\n  : v\n'), 5);
      expect(find('? a\n: *x\n'), 0);
      expect(find('a:\n  ? k\n  : v\n  b: *y\n'), 5);
      expect(find('b: &y 1\n? k\n: *y\n'), 8);
      expect(find('{? *x : v}'), 3);
      expect(find('[? *x : v]'), 3);
      expect(find('[? *x]'), 1);
      expect(find('{a: 1, ? *x : v}'), 9);
      expect(find('{? [*x] : v}'), 1);
      expect(find('[\n? *x\n]'), 2);
    });

    test('with an alias anywhere, rejects a flow collection used as a key', () {
      expect(find('[*x]: v\n'), 0);
      expect(find('{a: *x}: v\n'), 0);
      expect(find('- [*x]: v\n'), 2);
      expect(find('!!seq [*x]: v\n'), 6);
      expect(find('&z [*x]: v\n'), 3);
      expect(find('{[*x]: v}'), 1);
      expect(find('[[*x]: v]'), 1);
      expect(find('{{a: *x}: v}'), 1);
      expect(find('[a] : v\nb: *x\n'), 0);
      expect(find('b: *x\n[a] : v\n'), 6);
      expect(find('{a: 1}:v\nb: *x\n'), 0);
    });

    test('without an alias, explicit and collection keys are left alone', () {
      expect(find('? /pets\n: v\n'), isNull);
      expect(find('[a]: v\n'), isNull);
      expect(find('{? a : v}'), isNull);
      expect(find('{"a": [1, 2], "b": {"c": [3]}}'), isNull);
    });

    test('with an alias, JSON-like collections that are values are fine', () {
      expect(
        find('x: &a [1]\ny: *a\nz: {"a": [1, 2], "b": {"c": [3]}}\n'),
        isNull,
      );
      expect(find('x: [1] # note: here\ny: *x\n'), isNull);
      expect(find('what? *x\n'), isNull);
      expect(find('a: ?x\nb: *y\n'), isNull);
      expect(find('a: [ ?x, *y ]\n'), isNull);
    });

    test('finds an alias before a value indicator', () {
      expect(find('*x : v\n'), 0);
      expect(find('a:\n  *x : v\n'), 5);
      expect(find('- *x : v\n'), 2);
      expect(find('*x :\n  v\n'), 0);
    });

    test('finds an alias key inside a flow collection', () {
      expect(find('{*x : v}'), 1);
      expect(find('{a: 1, *x: v}'), 7);
      expect(find('{*x, a: 1}'), 1);
      expect(find('{a: 1, *x}'), 7);
      expect(find('[*x : v]'), 1);
      expect(find('a: [{b: [1], *x : 2}]'), 13);
    });

    test('ignores aliases in value position', () {
      expect(find('a: *x\n'), isNull);
      expect(find('<<: *x\n'), isNull);
      expect(find('- *x\n- *y # c\n'), isNull);
      expect(find('a: {b: *x, c: [*x, *y]}\n'), isNull);
      expect(find('{a: *x}'), isNull);
      expect(find('{a: *x , b: 1}'), isNull);
      expect(find('[*x, *y]'), isNull);
    });

    test('ignores a * that is not an alias', () {
      expect(find('"*x" : v\n'), isNull);
      expect(find("'*x' : v\n"), isNull);
      expect(find('a*b : v\n'), isNull);
      expect(find('a: b * c\n'), isNull);
      expect(find('a: |\n  *x : v\n'), isNull);
      expect(find('# *x : v\n'), isNull);
      expect(find('a: "[*x : v]"\n'), isNull);
      expect(find('a: b\n  *x : v\n'), isNull);
    });
  });
}
