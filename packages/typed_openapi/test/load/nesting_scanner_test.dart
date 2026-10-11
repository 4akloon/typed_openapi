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
    expect(scanner.findTooDeep(text, limit: 5), 10);
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
    expect(scanner.findTooDeep(text), NestingScanner.maxDepth);
  });
}
