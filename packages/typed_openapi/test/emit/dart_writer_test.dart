import 'package:test/test.dart';
import 'package:typed_openapi/src/emit/dart_code.dart';
import 'package:typed_openapi/src/emit/dart_writer.dart';
import 'package:typed_openapi/src/emit/imports.dart';

void main() {
  const code = DartCode();

  group('DartCode', () {
    test('escapes every character a string literal cannot hold', () {
      expect(code.string("it's"), r"'it\'s'");
      expect(code.string(r'$x ${y}'), r"'\$x \${y}'");
      expect(code.string(r'a\b'), r"'a\\b'");
      expect(code.string('a\nb\r\tc'), r"'a\nb\r\tc'");
      expect(code.string('\x00\x1f\x7f '), r"'\u{0}\u{1f}\u{7f}\u{2028}'");
      expect(code.string('\ud800'), r"'\u{d800}'");
      expect(code.string("ім'я 🐱"), r"'ім\'я 🐱'");
    });

    test('writes JSON scalars as constants', () {
      expect(code.literal('a'), "'a'");
      expect(code.literal(-3), '-3');
      expect(code.literal(2.0), '2.0');
      expect(code.literal(0.25), '0.25');
      expect(code.literal(true), 'true');
      expect(code.literal(null), 'null');
    });

    test('interpolates names with a dollar in braces', () {
      expect(code.interpolate('name'), r'$name');
      expect(code.interpolate(r'$2fa'), r'${$2fa}');
    });

    test('escapes doc text outside code spans and fences', () {
      expect(code.docLines(r'A <b> [c] d\e `x<y>` */', 80), [
        r'A \<b\> \[c\] d\\e `x<y>` */',
      ]);
      expect(code.docLines('odd ` <b>', 80), [r'odd ` \<b\>']);
      expect(code.docLines('\n\nText\r\n\n```\n<raw> [x]\n```\n\n', 80), [
        'Text',
        '',
        '```',
        '<raw> [x]',
        '```',
      ]);
      expect(code.docLines('```\nopen <fence>', 80), [
        '```',
        'open <fence>',
        '```',
      ]);
      expect(code.docLines('a\x01b', 80), ['ab']);
    });

    test('wraps long doc lines at the width, keeping the indent', () {
      expect(
        code.docLines('  one two three four five six seven', 20),
        ['  one two three four', '  five six seven'],
      );
      expect(code.docLines('averyveryverylongwordthatdoesnotfit x', 20), [
        'averyveryverylongwordthatdoesnotfit',
        'x',
      ]);
    });
  });

  group('DartWriter', () {
    test('indents blocks and keeps empty lines empty', () {
      final out = DartWriter(80)
        ..block('class A', () {
          final inner = DartWriter(80);
          expect(inner.indent, '');
        });
      out.indented(() => out.line());
      expect(out.text, 'class A {\n}\n\n');
    });

    test('puts a list on one line when it fits, else one item a line', () {
      final out = DartWriter(30)
        ..list('f(', ['a', 'b'], ');')
        ..list('const LongName({', ['required this.a', 'this.b'], '});')
        ..list('g(', [], ');');
      expect(
        out.text,
        'f(a, b);\n'
        'const LongName({\n'
        '  required this.a,\n'
        '  this.b,\n'
        '});\n'
        'g();\n',
      );
    });

    test('breaks a long chain one operand a line', () {
      final out = DartWriter(40)
        ..chain('bool operator ==(Object o) =>', ['o is A'], '&&')
        ..chain('bool operator ==(Object o) =>', [
          'o is A',
          'o.first == first',
        ], '&&');
      expect(
        out.text,
        'bool operator ==(Object o) => o is A;\n'
        'bool operator ==(Object o) =>\n'
        '    o is A &&\n'
        '    o.first == first;\n',
      );
    });

    test('writes doc comments at the indentation', () {
      final out = DartWriter(80);
      out.indented(() => out.doc('Line <one>.\n\nTwo.'));
      out.doc(null);
      expect(out.text, '  /// Line \\<one\\>.\n  ///\n  /// Two.\n');
    });
  });

  test('Imports writes sorted sections and show lists', () {
    final imports = Imports('pet.dart')
      ..fromRuntime('JsonReader')
      ..fromRuntime('Date')
      ..fromRuntime('JsonReader')
      ..show('dart:typed_data', 'Uint8List')
      ..show('dart:convert', 'base64Encode')
      ..show('package:app/money.dart', 'Money')
      ..file('tag.dart')
      ..file('pet.dart')
      ..file('cat.dart');
    final out = DartWriter(100);
    imports.write(out);
    expect(
      out.text,
      "import 'dart:convert' show base64Encode;\n"
      "import 'dart:typed_data' show Uint8List;\n"
      '\n'
      "import 'package:app/money.dart' show Money;\n"
      "import 'package:typed_openapi_runtime/typed_openapi_runtime.dart' "
      'show Date, JsonReader;\n'
      '\n'
      "import 'cat.dart';\n"
      "import 'tag.dart';\n"
      '\n',
    );
    final narrow = DartWriter(40);
    (Imports('a.dart')..fromRuntime('JsonReader')).write(narrow);
    expect(
      narrow.text,
      "import 'package:typed_openapi_runtime/typed_openapi_runtime.dart'\n"
      '    show JsonReader;\n'
      '\n',
    );
  });
}
