import 'package:test/test.dart';
import 'package:typed_openapi_tool/src/fuzz/dart_literals.dart';

void main() {
  test('finds plain, raw and triple-quoted literals, not comments', () {
    const source = r"""
// 'in a comment'
/// 'in a doc comment'
/* 'in a block' */
const a = 'it\'s';
const b = r'raw\n';
const c = '''three
lines''';
const d = "double";
""";
    expect(DartLiterals(source).scan(), [
      r"'it\'s'",
      r"r'raw\n'",
      "'''three\nlines'''",
      '"double"',
    ]);
  });

  test('skips an interpolated literal and scans its interpolation', () {
    const source = r"""
final a = 'x $name';
final b = 'y ${m['key']} z';
final c = '\$cost';
""";
    expect(DartLiterals(source).scan(), ["'key'", r"'\$cost'"]);
  });

  test('an unterminated block comment runs to the end of the input', () {
    expect(DartLiterals("const a = 'x'; /* never closed 'y'").scan(), ["'x'"]);
  });
}
